#!/usr/bin/env python3
"""Generic AOT native fragment linker for Wheelchair general programs.

The handwritten assembly general frontend remains the only expression/native
lowerer.  For requested width > 1 this module:
  1. receives the exact scalar ELF emitted by topologyc,
  2. cuts its already-native binding/output regions at their unique absolute
     result stores,
  3. derives true-data dependencies from the canonical graph,
  4. places those unchanged regions behind the generic schedulerless causal
     program_slot engine.

No workload name, benchmark id, recipe name, runtime profitability selector,
C/LLVM backend, or serial fallback participates in this transformation.
"""
from __future__ import annotations

import json
import os
import re
import struct
from pathlib import Path
from typing import Any

import general_parallel_plan as gpp
import schedulerless_causal_plan as sc

FORMAT = 'wheelchair.general_parallel_native/1'
SCALAR_SLOT_OPS = {'compute','reduce','iterate','lookup','nested_reduce'}
RUNTIME_FRAGMENT_OPS = {'compute','reduce','iterate','nested_reduce'}
OUTPUT_PREFIX = '@wheelchair.output.'

class GeneralParallelNativeError(ValueError):
    pass


def _equs(path: Path) -> dict[str,int]:
    out: dict[str,int] = {}
    rx=re.compile(r'^\.equ\s+([A-Za-z0-9_]+),\s*(0x[0-9A-Fa-f]+|[0-9]+)\s*$')
    for line in path.read_text(encoding='utf-8').splitlines():
        m=rx.match(line.strip())
        if m:
            out[m.group(1)] = int(m.group(2),0)
    return out


def _raw_refs(node: Any, names: set[str]) -> set[str]:
    # general_parallel_plan is the shared semantic authority.  Keep one public
    # behavior even while its helper remains private for compatibility.
    return set(gpp._refs(node, names))


def _runtime_layout(data: dict[str,Any]) -> tuple[list[dict[str,Any]], dict[str,int]]:
    runtime: list[dict[str,Any]] = []
    slots: dict[str,int] = {}
    scalar_slot=0
    for binding in data.get('bindings',[]):
        if not isinstance(binding,dict) or not isinstance(binding.get('name'),str):
            continue
        op=str(binding.get('op',''))
        if op in SCALAR_SLOT_OPS:
            slots[binding['name']]=scalar_slot
            if op in RUNTIME_FRAGMENT_OPS:
                runtime.append(binding)
            scalar_slot += 1
    return runtime, slots


def build_plan(data: dict[str,Any], slots: int) -> dict[str,Any]:
    if not isinstance(slots,int) or isinstance(slots,bool) or slots not in (1,2,4):
        raise GeneralParallelNativeError('general native slots must be 1, 2, or 4')
    bindings={
        str(b['name']):b for b in data.get('bindings',[])
        if isinstance(b,dict) and isinstance(b.get('name'),str)
    }
    all_names=set(bindings)
    runtime, binding_slots=_runtime_layout(data)
    runtime_names={str(b['name']) for b in runtime}

    # Remaining dynamic operators are deliberately not guessed.  Closed lookup
    # and cascade constructs have already been eliminated by the WH static pass.
    for b in data.get('bindings',[]):
        if not isinstance(b,dict):
            continue
        if b.get('op') in {'lookup','cascade'}:
            raise GeneralParallelNativeError(
                f"dynamic {b.get('op')} has no proved direct-native fragment; explicit rejection replaces serialization"
            )

    def materialized_dependencies_from_name(name: str, trail: frozenset[str]) -> set[str]:
        if name in runtime_names:
            return {name}
        if name in trail:
            raise GeneralParallelNativeError('structural reference cycle while erasing non-materialized bindings')
        b=bindings.get(name)
        if b is None:
            return set()
        out:set[str]=set()
        for ref in _raw_refs(b,all_names):
            out.update(materialized_dependencies_from_name(ref, trail | {name}))
        return out

    def deps_for(node: Any, self_name: str | None=None) -> set[str]:
        out:set[str]=set()
        for ref in _raw_refs(node,all_names):
            out.update(materialized_dependencies_from_name(ref,frozenset()))
        if self_name is not None:
            out.discard(self_name)
        return out

    fragments:list[dict[str,Any]]=[]
    node_ids:list[str]=[]
    node_work:list[int]=[]
    deps:dict[str,set[str]]={}
    for b in runtime:
        name=str(b['name'])
        node_ids.append(name)
        node_work.append(gpp._literal_work(b))
        deps[name]=deps_for(b,name)
        fragments.append({'kind':'binding','name':name,'slot':binding_slots[name],'op':b.get('op')})

    outputs=[o for o in data.get('outputs',[]) if isinstance(o,dict)]
    for i,out in enumerate(outputs):
        ident=f'{OUTPUT_PREFIX}{i}'
        node_ids.append(ident)
        node_work.append(1)
        deps[ident]=deps_for(out.get('expr',{}),None)
        fragments.append({'kind':'output','name':ident,'slot':i,'op':'output'})

    if not node_ids:
        raise GeneralParallelNativeError('general program has no materialized binding/output fragments')
    node_set=set(node_ids)
    for ident in node_ids:
        deps[ident].intersection_update(node_set)
    edges=[(src,dst) for dst in node_ids for src in sorted(deps[dst])]
    spec={
        'format':sc.FORMAT,
        'nodes':[{'id':node_ids[i],'work':node_work[i]} for i in range(len(node_ids))],
        'edges':[[u,v] for u,v in edges],
        'slots':slots,
    }
    physical=sc.plan(spec,slots)
    return {
        'format':FORMAT,
        'slots':slots,
        'node_ids':node_ids,
        'fragments':fragments,
        'dependencies':{k:sorted(v) for k,v in deps.items()},
        'edge_uv_u32':physical['edge_uv_u32'],
        'home_slots':physical['home_slots'],
        'source_count':physical['source_count'],
        'topological_depth':physical['topological_depth'],
        'max_ready_width':physical['max_ready_width'],
        'structural_signature_sha256':physical['structural_signature_sha256'],
        'runtime_selector':False,
        'global_ready_queue':0,
        'global_ready_scan':0,
        'root_scheduler':0,
        'work_stealing':0,
        'serial_fallback':0,
        'terminal_join_only':True,
        'fragment_machine_code_origin':'handwritten_topologyc_general_frontend',
    }


def _all_occurrences(haystack: bytes, needle: bytes) -> list[int]:
    out=[]; start=0
    while True:
        p=haystack.find(needle,start)
        if p<0: return out
        out.append(p); start=p+1


def _extract_fragments(serial_slot: bytes, plan: dict[str,Any], runtime_eq: dict[str,int]) -> list[bytes]:
    bind_va=runtime_eq['GENERAL_BINDING_VALUES_VA']
    out_va=runtime_eq['GENERAL_OUTPUT_VALUES_VA']
    cursor=0
    fragments=[]
    for spec in plan['fragments']:
        if spec['kind']=='binding':
            address=bind_va + int(spec['slot'])*8
        else:
            address=out_va + int(spec['slot'])*8
        marker=b'\x48\xa3'+struct.pack('<Q',address)
        positions=_all_occurrences(serial_slot,marker)
        if len(positions)!=1:
            raise GeneralParallelNativeError(
                f"native fragment boundary for {spec['name']!r} expected one absolute result store, found {len(positions)}"
            )
        end=positions[0]+len(marker)
        if end<=cursor:
            raise GeneralParallelNativeError(f"native fragment order for {spec['name']!r} is not monotone")
        frag=serial_slot[cursor:end]
        if not frag:
            raise GeneralParallelNativeError(f"native fragment {spec['name']!r} is empty")
        fragments.append(frag+b'\xc3')
        cursor=end
    return fragments


def _patch_u32(image: bytearray, off: int, value: int) -> None:
    struct.pack_into('<I',image,off,value & 0xffffffff)

def _patch_i32(image: bytearray, off: int, value: int) -> None:
    struct.pack_into('<i',image,off,int(value))


def link(serial_elf: Path, output: Path, data: dict[str,Any], slots: int,
         *, root: Path) -> dict[str,Any]:
    plan=build_plan(data,slots)
    runtime_eq=_equs(root/'compiler/general_runtime_offsets.inc')
    required=(
        'GENERAL_PROGRAM_OFF','GENERAL_BINDING_VALUES_VA','GENERAL_OUTPUT_VALUES_VA'
    )
    missing=[k for k in required if k not in runtime_eq]
    if missing:
        raise GeneralParallelNativeError('missing general runtime offsets: '+', '.join(missing))

    layout=json.loads((root/'build/general_parallel_slot_offsets.json').read_text(encoding='utf-8'))
    raw_template=(root/'build/general_parallel_slot_template.bin').read_bytes()
    if layout.get('format')!='wheelchair.general_parallel_slot_offsets/1':
        raise GeneralParallelNativeError('general parallel slot offset map format mismatch')
    cap=int(layout['program_slot_capacity']); max_nodes=int(layout['max_nodes']); max_edges=int(layout['max_edges'])
    offsets={k:int(v) for k,v in layout['offsets'].items()}
    if len(plan['node_ids'])>max_nodes or len(plan['edge_uv_u32'])>max_edges:
        raise GeneralParallelNativeError('general parallel native graph exceeds bounded slot image')

    serial=bytearray(serial_elf.read_bytes())
    program_off=runtime_eq['GENERAL_PROGRAM_OFF']
    if program_off+cap>len(serial):
        raise GeneralParallelNativeError('serial general ELF does not contain the expected program_slot capacity')
    serial_slot=bytes(serial[program_off:program_off+cap])
    fragments=_extract_fragments(serial_slot,plan,runtime_eq)

    image=bytearray(b'\x90'*cap)
    if len(raw_template)>cap:
        raise GeneralParallelNativeError('general parallel slot template exceeds program_slot')
    image[:len(raw_template)]=raw_template
    cursor=(len(raw_template)+15)&~15
    entries=[]
    for frag in fragments:
        cursor=(cursor+15)&~15
        if cursor+len(frag)>cap:
            raise GeneralParallelNativeError('native general fragments plus causal engine exceed program_slot capacity')
        entries.append(cursor)
        image[cursor:cursor+len(frag)]=frag
        cursor += len(frag)

    n=len(entries); edges=[tuple(map(int,e)) for e in plan['edge_uv_u32']]
    indegree=[0]*n; first=[-1]*n; nxt=[-1]*len(edges); edge_v=[0]*len(edges)
    for i,(u,v) in enumerate(edges):
        if not (0<=u<n and 0<=v<n):
            raise GeneralParallelNativeError('physical edge references an unknown fragment')
        indegree[v]+=1; edge_v[i]=v; nxt[i]=first[u]; first[u]=i
    home=[int(x) for x in plan['home_slots']]
    home_initial=[0]*int(layout['max_slots'])
    for h in home:
        if not 0<=h<slots:
            raise GeneralParallelNativeError('AOT home slot is outside requested executor width')
        home_initial[h]+=1

    _patch_u32(image,offsets['gp_node_count'],n)
    _patch_u32(image,offsets['gp_edge_count'],len(edges))
    _patch_u32(image,offsets['gp_slot_count'],slots)
    for i,v in enumerate(home): _patch_u32(image,offsets['gp_home_slots']+i*4,v)
    for i,v in enumerate(indegree): _patch_u32(image,offsets['gp_indegree']+i*4,v)
    for i,v in enumerate(first): _patch_i32(image,offsets['gp_first_out']+i*4,v)
    for i,v in enumerate(edge_v): _patch_u32(image,offsets['gp_edge_v']+i*4,v)
    for i,v in enumerate(nxt): _patch_i32(image,offsets['gp_next_edge']+i*4,v)
    for i,v in enumerate(entries): _patch_u32(image,offsets['gp_entry_offsets']+i*4,v)
    for i,v in enumerate(home_initial): _patch_u32(image,offsets['gp_home_initial']+i*4,v)

    serial[program_off:program_off+cap]=image
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(serial)
    os.chmod(output, serial_elf.stat().st_mode | 0o111)
    plan['native_fragment_bytes']=sum(len(x) for x in fragments)
    plan['program_slot_bytes_used']=cursor
    plan['program_slot_capacity']=cap
    plan['executor_materialization']=slots
    plan['native_fragment_count']=n
    return plan
