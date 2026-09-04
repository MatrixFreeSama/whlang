#!/usr/bin/env python3
import argparse,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'surface'))
import whex_surface

def main():
    ap=argparse.ArgumentParser(description='Wheelchair Expert .whex -> native static ELF through dedicated topologyc')
    ap.add_argument('source',type=Path); ap.add_argument('-o','--output',type=Path,required=True)
    ap.add_argument('--executors',type=int,choices=[1,2,4],default=1)
    ap.add_argument('--isa-limit',choices=['native','avx512f','avx512dq','avx2'],default=None,help='backend capability ceiling for ISA audit/testing; never selects a scalar fallback')
    ap.add_argument('--semantic-plan',type=Path,default=None,help='write compile-time Region/Effect/Dependency/parallelism plan JSON')
    a=ap.parse_args()
    data,parser,_=whex_surface.load_surface(a.source)
    whex_surface._compile_native(ROOT,data,a.output,a.executors,a.isa_limit)
    plan=whex_surface.semantic_plan(parser)
    if a.semantic_plan is not None:
        a.semantic_plan.write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'source':str(a.source),'output':str(a.output),'core_sha256':whex_surface.core_hash(data),'repair_count':len(parser.repairs),'repairs':[r.as_dict() for r in parser.repairs],'bottom_layer_modified':True,'compiler_release':'1.1.0','semantic_sha256':plan['semantic_sha256']},ensure_ascii=False,indent=2))
    return 0
if __name__=='__main__':
    try: raise SystemExit(main())
    except Exception as exc:
        print(f'WHEX compile rejection: {exc}',file=sys.stderr); raise SystemExit(1)
