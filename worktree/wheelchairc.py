#!/usr/bin/env python3
import argparse, json, subprocess, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'surface'))
import wh_surface
import wh_structural
import native_resource_profile as nrp
import general_parallel_plan as gpp
import general_parallel_native as gpn


def _compiler_for_profile(profile: dict) -> Path:
    cls=profile.get('backend_class','base')
    table={
        'base':ROOT/'build/topologyc',
        'wide':ROOT/'build/topologyc-wide',
        'derived':ROOT/'build/topologyc-derived',
    }
    if cls not in table:
        raise wh_surface.SurfaceError(f"unknown native resource profile class {cls!r}")
    return table[cls]


def _compile_native(core_bytes: bytes, output: Path, executors: int, *, profile: dict) -> tuple[int,str,str]:
    with tempfile.TemporaryDirectory(prefix='wheelchair_surface_') as td:
        core=Path(td)/'program.core.wh'; core.write_bytes(core_bytes)
        compiler=_compiler_for_profile(profile)
        cmd=[str(compiler),str(core),'-o',str(output)]
        if executors!=1: cmd += ['--executors',str(executors)]
        p=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        return p.returncode,p.stdout,p.stderr


def _compile_general_parallel(core_bytes: bytes, data: dict, output: Path, executors: int):
    """Keep handwritten topologyc as native lowerer; replace only slot layout."""
    with tempfile.TemporaryDirectory(prefix='wheelchair_general_parallel_') as td:
        scalar=Path(td)/'serial-general.elf'
        profile=nrp.analyze(data)
        if profile.get('backend_class')!='base':
            # General scalar/control fragments have no tensor resource pressure.
            # Any other class here means the structural/general boundary changed.
            return 65,'','Wheelchair general-parallel native rejection: non-base general profile\n',None
        rc,out,err=_compile_native(core_bytes,scalar,1,profile=profile)
        if rc:
            return rc,out,err,None
        try:
            native=gpn.link(scalar,output,data,executors,root=ROOT)
        except gpn.GeneralParallelNativeError as exc:
            return 65,'',f'Wheelchair general-parallel native rejection: {exc}\n',None
        return 0,out,err,native


def main():
    ap=argparse.ArgumentParser(description='Wheelchair UTF-8 human surface -> native static ELF')
    ap.add_argument('source',type=Path); ap.add_argument('-o','--output',type=Path,required=True)
    ap.add_argument('--executors',type=int,choices=[1,2,4],default=1)
    ap.add_argument('--semantic-plan',type=Path,default=None,
                    help='write structural/general semantics plus universal causal physicalization')
    a=ap.parse_args()

    if a.source.suffix.lower() != '.wh':
        raise wh_surface.SurfaceError("Wheelchair source must use '.wh'; WHEX keeps the '.whex' expert surface")
    text=a.source.read_text(encoding='utf-8',errors='strict')
    structural=wh_structural.looks_structural(text)

    if structural:
        data, parser = wh_structural.compile_surface(text,a.source)
        plan=wh_structural.semantic_plan(parser)
        parallel=gpp.plan(data,a.executors,semantic=plan,physical_lane='structural_topology_native')
        profile=nrp.analyze(data)
        plan['general_parallel_fabric']=parallel
        plan['native_resource_profile']=profile
        blob=wh_structural.canonical_core_bytes(data)
        rc,out,err=_compile_native(blob,a.output,a.executors,profile=profile)
        if rc:
            sys.stderr.write(err or out); return rc
        if a.semantic_plan is not None:
            a.semantic_plan.parent.mkdir(parents=True,exist_ok=True)
            a.semantic_plan.write_text(json.dumps(plan,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
        print(json.dumps({
            'source':str(a.source), 'output':str(a.output),
            'surface_lane':'wheelchair.wh.inference_surface/1',
            'core_sha256':wh_structural.core_hash(data),
            'native_core_sha256':wh_structural.core_hash(data),
            'general_topology_recovery':{'active':False,'reason':'structural_lane_selected_before_native_compilation'},
            'general_parallel_fabric':parallel,
            'native_resource_profile':profile,
            'semantic_sha256':plan.get('semantic_sha256'),
            'requested_executors':a.executors,
            'effective_executors':a.executors,
            'parallel_fabric_authority':'topology-parallel',
            'repair_count':len(parser.repairs),
            'repairs':[r.as_dict() for r in parser.repairs]
        },ensure_ascii=False,indent=2))
        return 0

    data, parser = wh_surface.compile_surface(text,a.source)
    static_data, static_lowering = wh_surface.lower_static_general_constructs(data)
    lowered_data, gtr = wh_surface.recover_topology_program(static_data)
    native_data = lowered_data
    if not gtr.get('active'):
        native_data = dict(lowered_data)
        native_data['_compiler_lane'] = 'wheelchair.general/1'
    profile=nrp.analyze(native_data)
    parallel=gpp.plan(native_data,a.executors,physical_lane=(
        'recovered_topology_native' if gtr.get('active') else 'general_causal_native'
    ))
    blob=wh_surface.canonical_core_bytes(native_data)

    native_parallel=None
    if gtr.get('active'):
        rc,out,err=_compile_native(blob,a.output,a.executors,profile=profile)
        effective=a.executors
    elif a.executors==1:
        # Explicit width-one AOT specialization preserves the mature direct
        # native peak. It is not a failure path and is never selected at runtime.
        rc,out,err=_compile_native(blob,a.output,1,profile=profile)
        effective=1
    else:
        rc,out,err,native_parallel=_compile_general_parallel(blob,native_data,a.output,a.executors)
        effective=a.executors if rc==0 else 0
    if rc:
        sys.stderr.write(err or out); return rc

    semantic={
        'semantic_format':'wheelchair.wh.general/1',
        'structural_recovery':gtr,
        'general_parallel_fabric':parallel,
        'native_resource_profile':profile,
        'serial_introduction_audit':{
            'synthetic_order_edges':0,
            'global_ready_queue':0,
            'root_scheduler':0,
            'runtime_cost_selector':0,
            'hidden_serial_fallback':0,
            'intermediate_global_barriers':0,
            'terminal_join_only':bool(native_parallel),
        },
        'native_physicalization':{
            'lane':'recovered_topology_native' if gtr.get('active') else ('direct_general_native_q1' if a.executors==1 else 'general_causal_native'),
            'executor_materialization':effective,
            'parallel_fabric_authority':'topology-parallel',
            'native_fragments':native_parallel,
            'machine_code_lowerer':'handwritten_topologyc_general_frontend',
            'foreign_runtime_backend':False,
        },
    }
    if a.semantic_plan is not None:
        a.semantic_plan.parent.mkdir(parents=True,exist_ok=True)
        a.semantic_plan.write_text(json.dumps(semantic,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(json.dumps({
        'source':str(a.source), 'output':str(a.output),
        'surface_lane':'wheelchair.wh.legacy_general/1',
        'core_sha256':wh_surface.core_hash(data),
        'lowered_core_sha256':wh_surface.core_hash(lowered_data),
        'native_core_sha256':wh_surface.core_hash(native_data),
        'static_general_lowering':static_lowering,
        'general_topology_recovery':gtr,
        'general_parallel_fabric':parallel,
        'general_parallel_native':native_parallel,
        'native_resource_profile':profile,
        'requested_executors':a.executors,
        'effective_executors':effective,
        'parallel_fabric_executors':parallel.get('materialized_slots',0),
        'parallel_fabric_authority':'topology-parallel',
        'repair_count':len(parser.repairs),
        'repairs':[r.as_dict() for r in parser.repairs]
    },ensure_ascii=False,indent=2))
    return 0
if __name__=='__main__':
    try:
        raise SystemExit(main())
    except wh_surface.SurfaceError as exc:
        print(f'Wheelchair compile rejection: {exc}',file=sys.stderr)
        raise SystemExit(65)
