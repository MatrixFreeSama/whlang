#!/usr/bin/env python3
"""Wheelchair 1.2.10 recipient-blind causal-region native linker."""
from __future__ import annotations
import json, os, re, struct
from pathlib import Path
from typing import Any
import general_parallel_plan as gpp

FORMAT="wheelchair.general_parallel_native/3"
SCALAR_SLOT_OPS={"compute","reduce","iterate","lookup","nested_reduce"}
RUNTIME_FRAGMENT_OPS={"compute","reduce","iterate","nested_reduce"}
OUTPUT_PREFIX="@wheelchair.output."
class GeneralParallelNativeError(ValueError): pass

def _equs(path:Path)->dict[str,int]:
    out={}; rx=re.compile(r'^\.equ\s+([A-Za-z0-9_]+),\s*(0x[0-9A-Fa-f]+|[0-9]+)\s*$')
    for line in path.read_text(encoding='utf-8').splitlines():
        m=rx.match(line.strip())
        if m: out[m.group(1)]=int(m.group(2),0)
    return out

def _raw_refs(node:Any,names:set[str])->set[str]: return set(gpp._refs(node,names))

def _runtime_layout(data:dict[str,Any]):
    runtime=[]; binding_index={}; scalar_index=0
    for binding in data.get('bindings',[]):
        if not isinstance(binding,dict) or not isinstance(binding.get('name'),str): continue
        op=str(binding.get('op',''))
        if op in SCALAR_SLOT_OPS:
            binding_index[binding['name']]=scalar_index
            if op in RUNTIME_FRAGMENT_OPS: runtime.append(binding)
            scalar_index+=1
    return runtime,binding_index

def build_plan(data:dict[str,Any],slots:int)->dict[str,Any]:
    if slots not in gpp.VALID_WIDTHS: raise GeneralParallelNativeError(f'general native CPU width must be one of {gpp.VALID_WIDTHS}')
    bindings={str(b['name']):b for b in data.get('bindings',[]) if isinstance(b,dict) and isinstance(b.get('name'),str)}
    all_names=set(bindings); runtime,binding_index=_runtime_layout(data); runtime_names={str(b['name']) for b in runtime}
    for b in data.get('bindings',[]):
        if isinstance(b,dict) and b.get('op') in {'lookup','cascade'}:
            raise GeneralParallelNativeError(f"dynamic {b.get('op')} has no proved direct-native fragment; explicit rejection replaces serialization")
    def materialized(name:str,trail:frozenset[str])->set[str]:
        if name in runtime_names: return {name}
        if name in trail: raise GeneralParallelNativeError('structural reference cycle while erasing non-materialized bindings')
        b=bindings.get(name)
        if b is None: return set()
        out=set()
        for ref in _raw_refs(b,all_names): out.update(materialized(ref,trail|{name}))
        return out
    def deps_for(node:Any,self_name:str|None=None)->set[str]:
        out=set()
        for ref in _raw_refs(node,all_names): out.update(materialized(ref,frozenset()))
        if self_name is not None: out.discard(self_name)
        return out
    fragments=[]; node_ids=[]; node_work=[]; deps={}
    for b in runtime:
        name=str(b['name']); node_ids.append(name); node_work.append(gpp._literal_work(b)); deps[name]=deps_for(b,name)
        fragments.append({'kind':'binding','name':name,'index':binding_index[name],'op':b.get('op')})
    for i,out in enumerate(o for o in data.get('outputs',[]) if isinstance(o,dict)):
        ident=f'{OUTPUT_PREFIX}{i}'; node_ids.append(ident); node_work.append(1); deps[ident]=deps_for(out.get('expr',{}),None)
        fragments.append({'kind':'output','name':ident,'index':i,'op':'output'})
    if not node_ids: raise GeneralParallelNativeError('general program has no materialized binding/output fragments')
    node_set=set(node_ids)
    for ident in node_ids: deps[ident].intersection_update(node_set)
    index={name:i for i,name in enumerate(node_ids)}; edges=[(index[src],index[dst]) for dst in node_ids for src in sorted(deps[dst])]
    physical=gpp.causal_geometry(node_ids,edges,slots,work=node_work)
    return {'format':FORMAT,'cpu_width':slots,'node_ids':node_ids,'fragments':fragments,'dependencies':{k:sorted(v) for k,v in deps.items()},
            'edge_uv_u32':[[u,v] for u,v in edges],'source_count':physical['source_count'],'topological_depth':physical['topological_depth'],
            'max_ready_width':physical['max_ready_width'],'structural_signature_sha256':physical['structural_signature_sha256'],
            'blind_release_causal':physical,'runtime_selector':False,'global_ready_queue':0,'global_ready_scan':0,'root_scheduler':0,
            'work_stealing':0,'serial_fallback':0,'runtime_fixed_home_ownership':0,'persistent_idle_worker_spin':0,
            'post_completion_work_search':0,'post_completion_peer_query':0,'resource_release_destination':0,'resource_handoff':0,
            'causal_region_fusion':physical['fusion_rule'],'causal_region_count':physical['causal_region_count'],
            'fused_node_count':physical['fused_node_count'],'max_region_nodes':physical['max_region_nodes'],
            'terminal_join_only':True,'fragment_machine_code_origin':'handwritten_topologyc_general_frontend'}

def _all_occurrences(h:bytes,n:bytes)->list[int]:
    out=[]; start=0
    while True:
        p=h.find(n,start)
        if p<0:return out
        out.append(p); start=p+1

def _extract_fragments(serial_slot:bytes,plan:dict[str,Any],runtime_eq:dict[str,int])->list[bytes]:
    bind_va=runtime_eq['GENERAL_BINDING_VALUES_VA']; out_va=runtime_eq['GENERAL_OUTPUT_VALUES_VA']; cursor=0; fragments=[]
    for spec in plan['fragments']:
        address=(bind_va if spec['kind']=='binding' else out_va)+int(spec['index'])*8
        marker=b'\x48\xa3'+struct.pack('<Q',address); positions=_all_occurrences(serial_slot,marker)
        if len(positions)!=1: raise GeneralParallelNativeError(f"native fragment boundary for {spec['name']!r} expected one absolute result store, found {len(positions)}")
        end=positions[0]+len(marker)
        if end<=cursor: raise GeneralParallelNativeError(f"native fragment order for {spec['name']!r} is not monotone")
        frag=serial_slot[cursor:end]
        if not frag: raise GeneralParallelNativeError(f"native fragment {spec['name']!r} is empty")
        fragments.append(frag+b'\xc3'); cursor=end
    return fragments

def _fuse_regions(fragments:list[bytes],plan:dict[str,Any])->list[bytes]:
    regions=plan['blind_release_causal']['causal_region_indices']
    used=[]; fused=[]
    for region in regions:
        if not region: raise GeneralParallelNativeError('empty causal region is invalid')
        parts=[]
        for pos,idx in enumerate(region):
            if not (0<=idx<len(fragments)): raise GeneralParallelNativeError('causal region references an unknown native fragment')
            frag=fragments[idx]
            if not frag or frag[-1:]!=b'\xc3': raise GeneralParallelNativeError('native fragment lacks linker-owned terminal RET')
            parts.append(frag if pos==len(region)-1 else frag[:-1])
            used.append(idx)
        fused.append(b''.join(parts))
    if sorted(used)!=list(range(len(fragments))):
        raise GeneralParallelNativeError('causal region fusion must cover every native fragment exactly once')
    return fused

def _patch_u32(image:bytearray,off:int,value:int)->None: struct.pack_into('<I',image,off,value&0xffffffff)
def _patch_i32(image:bytearray,off:int,value:int)->None: struct.pack_into('<i',image,off,int(value))

def link(serial_elf:Path,output:Path,data:dict[str,Any],slots:int,*,root:Path)->dict[str,Any]:
    plan=build_plan(data,slots); runtime_eq=_equs(root/'compiler/general_runtime_offsets.inc')
    required=('GENERAL_PROGRAM_OFF','GENERAL_BINDING_VALUES_VA','GENERAL_OUTPUT_VALUES_VA'); missing=[k for k in required if k not in runtime_eq]
    if missing: raise GeneralParallelNativeError('missing general runtime offsets: '+', '.join(missing))
    layout=json.loads((root/'build/general_parallel_release_offsets.json').read_text(encoding='utf-8'))
    raw_template=(root/'build/general_parallel_release_template.bin').read_bytes()
    if layout.get('format')!='wheelchair.general_parallel_release_offsets/1': raise GeneralParallelNativeError('general blind-release offset map format mismatch')
    cap=int(layout['program_slot_capacity']); max_nodes=int(layout['max_nodes']); max_edges=int(layout['max_edges']); offsets={k:int(v) for k,v in layout['offsets'].items()}
    serial=bytearray(serial_elf.read_bytes()); program_off=runtime_eq['GENERAL_PROGRAM_OFF']
    if program_off+cap>len(serial): raise GeneralParallelNativeError('serial general ELF does not contain the expected program_slot capacity')
    source_fragments=_extract_fragments(bytes(serial[program_off:program_off+cap]),plan,runtime_eq)
    region_fragments=_fuse_regions(source_fragments,plan)
    region_edges=[tuple(map(int,e)) for e in plan['blind_release_causal']['region_edge_uv_u32']]
    if len(region_fragments)>max_nodes or len(region_edges)>max_edges: raise GeneralParallelNativeError('general blind-release region graph exceeds bounded program-slot image')

    image=bytearray(b'\x90'*cap)
    if len(raw_template)>cap: raise GeneralParallelNativeError('general blind-release template exceeds program_slot')
    image[:len(raw_template)]=raw_template; cursor=(len(raw_template)+15)&~15; entries=[]
    for frag in region_fragments:
        cursor=(cursor+15)&~15
        if cursor+len(frag)>cap: raise GeneralParallelNativeError('native causal regions plus blind-release engine exceed program_slot capacity')
        entries.append(cursor); image[cursor:cursor+len(frag)]=frag; cursor+=len(frag)
    n=len(entries); edges=region_edges; indegree=[0]*n; first=[-1]*n; nxt=[-1]*len(edges); edge_v=[0]*len(edges)
    for i,(u,v) in enumerate(edges):
        if not (0<=u<n and 0<=v<n): raise GeneralParallelNativeError('physical region edge references an unknown causal region')
        indegree[v]+=1; edge_v[i]=v; nxt[i]=first[u]; first[u]=i
    _patch_u32(image,offsets['gr_node_count'],n); _patch_u32(image,offsets['gr_edge_count'],len(edges)); _patch_u32(image,offsets['gr_cpu_width'],slots)
    for i,v in enumerate(indegree): _patch_u32(image,offsets['gr_indegree']+i*4,v)
    for i,v in enumerate(first): _patch_i32(image,offsets['gr_first_out']+i*4,v)
    for i,v in enumerate(edge_v): _patch_u32(image,offsets['gr_edge_v']+i*4,v)
    for i,v in enumerate(nxt): _patch_i32(image,offsets['gr_next_edge']+i*4,v)
    for i,v in enumerate(entries): _patch_u32(image,offsets['gr_entry_offsets']+i*4,v)
    serial[program_off:program_off+cap]=image; output.parent.mkdir(parents=True,exist_ok=True); output.write_bytes(serial); os.chmod(output,serial_elf.stat().st_mode|0o111)
    plan['source_native_fragment_bytes']=sum(len(x) for x in source_fragments)
    plan['native_fragment_bytes']=sum(len(x) for x in region_fragments)
    plan['program_slot_bytes_used']=cursor; plan['program_slot_capacity']=cap
    plan['cpu_width']=slots; plan['node_context_materialization']=n; plan['native_fragment_count']=len(source_fragments)
    plan['causal_region_count']=n; plan['fused_fragment_count']=len(source_fragments)-n
    plan['per_context_stack_mmap']=0; plan['per_context_stack_munmap']=0; plan['invocation_stack_arena']=int(n>1)
    return plan
