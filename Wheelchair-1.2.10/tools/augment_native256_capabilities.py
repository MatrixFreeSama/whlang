#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'build/topologyc_multi_isa_x86_64.S'
s=p.read_text(encoding='utf-8')

old='''    bt eax,1                       # AVX2\n    jnc .dic_no_avx2\n    or ebx,ISA_CAP_VEC256_INT | ISA_CAP_GATHER | ISA_CAP_MASKED_MEMORY | ISA_CAP_I64_MUL_SYNTH\n.dic_no_avx2:\n'''
new='''    bt eax,1                       # AVX2\n    jnc .dic_no_avx2\n    # AVX2 is a complete native256 tensor substrate. Predicate/tail/minimum and\n    # i64<->f64 operations are synthesized with YMM relations, never scalar lanes.\n    or ebx,ISA_CAP_VEC256_INT | ISA_CAP_GATHER | ISA_CAP_MASKED_MEMORY | ISA_CAP_I64_MUL_SYNTH\n    or ebx,ISA_CAP_PREDICATE | ISA_CAP_MASKED_TAIL | ISA_CAP_SCALAR_BROADCAST | ISA_CAP_I64_MIN\n    or ebx,ISA_CAP_I64_FP_CONVERT_SYNTH | ISA_CAP_NONNEG_F64_U64_TRUNC_SYNTH\n    or ebx,ISA_CAP_CROSS_VECTOR_STATE | ISA_CAP_REDUCTION_TREE\n.dic_no_avx2:\n'''
if s.count(old)!=1: raise SystemExit('AVX2 capability block changed')
s=s.replace(old,new,1)

old='''    mov edx,ISA_CAP_VEC256_FP | ISA_CAP_VEC256_INT | ISA_CAP_FMA | ISA_CAP_GATHER | ISA_CAP_I64_MUL_SYNTH | ISA_CAP_MASKED_MEMORY | ISA_CAP_BIT_EXTRACT_DEPOSIT | ISA_CAP_POPCOUNT | ISA_CAP_LZCNT\n    and ecx,edx\n'''
new='''    mov edx,ISA_CAP_TENSOR256_BASE | ISA_CAP_GATHER | ISA_CAP_MASKED_MEMORY | ISA_CAP_BIT_EXTRACT_DEPOSIT | ISA_CAP_POPCOUNT | ISA_CAP_LZCNT\n    and ecx,edx\n'''
if s.count(old)!=1: raise SystemExit('AVX2 ISA ceiling block changed')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
print('NATIVE256_CAPABILITY_SYNTHESIS=PASS')
