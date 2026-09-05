#!/usr/bin/env python3
import argparse,json,sys,tempfile,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'surface'))
import whex_surface
import shared_dependency_episode as sde


def compile_native(data, output: Path, executors: int, isa_limit: str | None):
    episode=sde.analyze(data)
    with tempfile.TemporaryDirectory(prefix='whex_core_') as td:
        core=Path(td)/'program.core.wh'; core.write_bytes(whex_surface.canonical_core_bytes(data))
        if 'rank_n_product' in data:
            compiler=ROOT/'build/topologyc-rankn'
        elif episode.get('recipe')=='shared_dependency_episode_wide_125':
            compiler=ROOT/'build/topologyc-sdep'
        else:
            compiler=ROOT/'build/topologyc'
        cmd=[str(compiler),str(core),'-o',str(output.resolve())]
        if executors!=1: cmd += ['--executors',str(executors)]
        if isa_limit is not None: cmd += ['--isa-limit',isa_limit]
        p=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if p.returncode:
            raise whex_surface.wh.SurfaceError('current dedicated topologyc rejected WHEX graph:\n'+(p.stderr or p.stdout).strip())
    return episode


def main():
    ap=argparse.ArgumentParser(description='Wheelchair Expert .whex -> native static ELF through dedicated topologyc')
    ap.add_argument('source',type=Path); ap.add_argument('-o','--output',type=Path,required=True)
    ap.add_argument('--executors',type=int,choices=[1,2,4],default=1)
    ap.add_argument('--isa-limit',choices=['native','avx512f','avx512dq','avx2'],default=None,help='backend capability ceiling for ISA audit/testing; never selects a scalar fallback')
    ap.add_argument('--semantic-plan',type=Path,default=None,help='write compile-time Region/Effect/Dependency/parallelism plan JSON')
    a=ap.parse_args()
    data,parser,_=whex_surface.load_surface(a.source)
    episode=compile_native(data,a.output,a.executors,a.isa_limit)
    plan=whex_surface.semantic_plan(parser)
    plan['shared_dependency_episode']=episode
    if a.semantic_plan is not None:
        a.semantic_plan.write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'source':str(a.source),'output':str(a.output),'core_sha256':whex_surface.core_hash(data),'repair_count':len(parser.repairs),'repairs':[r.as_dict() for r in parser.repairs],'bottom_layer_modified':True,'compiler_release':'1.2.6','semantic_sha256':plan['semantic_sha256'],'shared_dependency_episode':episode},ensure_ascii=False,indent=2))
    return 0
if __name__=='__main__':
    try: raise SystemExit(main())
    except Exception as exc:
        print(f'WHEX compile rejection: {exc}',file=sys.stderr); raise SystemExit(1)
