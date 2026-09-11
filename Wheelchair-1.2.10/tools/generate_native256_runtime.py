#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
GEN=BUILD/'generated_native256'
GEN.mkdir(parents=True,exist_ok=True)


def transform(src: Path, out: Path) -> None:
    s=src.read_text(encoding='utf-8')
    old='cmp dword ptr [rip+vector_width_patch],8'
    if s.count(old)!=3:
        raise SystemExit(f'native256 runtime expected 3 vector-width gates in {src}, found {s.count(old)}')
    s=s.replace(old,'cmp dword ptr [rip+vector_width_patch],4')
    for a,b in [('vbroadcastsd zmm14,xmm14','vbroadcastsd ymm14,xmm14'),('vbroadcastsd zmm15,xmm15','vbroadcastsd ymm15,xmm15')]:
        if s.count(a)!=1: raise SystemExit(f'native256 runtime missing {a} in {src}')
        s=s.replace(a,b,1)
    s=s.replace('generated AVX-512 kernel','generated AVX2/YMM kernel')
    s=s.replace('every eight-lane step','every four-lane step')
    s=s.replace('keep ZMM14/ZMM15 resident','keep YMM14/YMM15 resident')
    out.write_text(s,encoding='utf-8')

transform(ROOT/'runtime/tensor_runtime_template_x86_64.S', GEN/'tensor_runtime_native256_template_x86_64.S')
transform(BUILD/'generated_derived/tensor_derived_runtime_template_x86_64.S', GEN/'tensor_derived_runtime_native256_template_x86_64.S')

(GEN/'runtime_native256_blob_x86_64.S').write_text(
    '.intel_syntax noprefix\n.section .rodata\n.global runtime_template_blob\n.global runtime_template_blob_end\n'
    'runtime_template_blob:\n.incbin "build/tensor_runtime_native256_template"\nruntime_template_blob_end:\n',encoding='utf-8')
(GEN/'runtime_derived_native256_blob_x86_64.S').write_text(
    '.intel_syntax noprefix\n.section .rodata\n.global runtime_template_blob\n.global runtime_template_blob_end\n'
    'runtime_template_blob:\n.incbin "build/tensor_derived_runtime_native256_template"\nruntime_template_blob_end:\n',encoding='utf-8')
print('NATIVE256_RUNTIME_GENERATION=PASS')
print('NATIVE256_RUNTIME_SCALAR_FALLBACK=0')
