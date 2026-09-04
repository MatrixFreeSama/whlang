#!/usr/bin/env python3
import argparse, json, subprocess, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'surface'))
import wh_surface
import wh_structural


def _compile_native(core_bytes: bytes, output: Path, executors: int) -> tuple[int,str,str]:
    with tempfile.TemporaryDirectory(prefix='wheelchair_surface_') as td:
        core=Path(td)/'program.core.wh'; core.write_bytes(core_bytes)
        cmd=[str(ROOT/'build/topologyc'),str(core),'-o',str(output)]
        if executors!=1: cmd += ['--executors',str(executors)]
        p=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        return p.returncode,p.stdout,p.stderr


def main():
    ap=argparse.ArgumentParser(description='Wheelchair UTF-8 human surface -> native static ELF')
    ap.add_argument('source',type=Path); ap.add_argument('-o','--output',type=Path,required=True)
    ap.add_argument('--executors',type=int,choices=[1,2,4],default=1)
    ap.add_argument('--semantic-plan',type=Path,default=None,
                    help='write the recovered WH structural semantic plan when the structural surface is selected')
    a=ap.parse_args()

    if a.source.suffix.lower() != '.wh':
        raise wh_surface.SurfaceError("Wheelchair source must use '.wh'; WHEX keeps the '.whex' expert surface")
    text=a.source.read_text(encoding='utf-8',errors='strict')
    structural=wh_structural.looks_structural(text)

    if structural:
        # Lane identity is decided from the source grammar before compilation.
        # Failure in the structural lane is terminal: never retry general or scalar.
        data, parser = wh_structural.compile_surface(text,a.source)
        plan=wh_structural.semantic_plan(parser)
        blob=wh_structural.canonical_core_bytes(data)
        rc,out,err=_compile_native(blob,a.output,a.executors)
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
            'semantic_sha256':plan.get('semantic_sha256'),
            'requested_executors':a.executors,
            'effective_executors':a.executors,
            'repair_count':len(parser.repairs),
            'repairs':[r.as_dict() for r in parser.repairs]
        },ensure_ascii=False,indent=2))
        return 0

    data, parser = wh_surface.compile_surface(text,a.source)
    static_data, static_lowering = wh_surface.lower_static_general_constructs(data)
    lowered_data, gtr = wh_surface.recover_topology_program(static_data)
    # Compile-lane identity is decided before native compilation.  Unrecovered
    # general semantics are never presented to the tensor frontend, while GTR
    # outputs remain byte-equivalent to WHEX topology cores.  This is routing
    # metadata, not a failure-driven fallback.
    native_data = lowered_data
    if not gtr.get('active'):
        native_data = dict(lowered_data)
        native_data['_compiler_lane'] = 'wheelchair.general/1'
    blob=wh_surface.canonical_core_bytes(native_data)
    rc,out,err=_compile_native(blob,a.output,a.executors)
    if rc:
        sys.stderr.write(err or out); return rc
    if a.semantic_plan is not None:
        # General programs deliberately do not fabricate a structural proof.
        a.semantic_plan.parent.mkdir(parents=True,exist_ok=True)
        a.semantic_plan.write_text(json.dumps({
            'semantic_format':'wheelchair.wh.general/1',
            'structural_recovery':gtr,
            'serial_introduction_audit':'not_claimed_for_unrecovered_general_lane'
        },ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(json.dumps({
        'source':str(a.source), 'output':str(a.output),
        'surface_lane':'wheelchair.wh.legacy_general/1',
        'core_sha256':wh_surface.core_hash(data),
        'lowered_core_sha256':wh_surface.core_hash(lowered_data),
        'native_core_sha256':wh_surface.core_hash(native_data),
        'static_general_lowering':static_lowering,
        'general_topology_recovery':gtr,
        'requested_executors':a.executors,
        'effective_executors':a.executors if gtr.get('active') else 1,
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
