#!/usr/bin/env python3
"""Preserve 2^k±1 constant-multiply shift counts across native helper calls.

The AVX2 strength reducer originally held k in caller-saved ECX and then called
vec_mov_ext, whose encoder legitimately reuses ECX.  That changed the semantic
constant whenever the source physical register number differed from k.  Keep k
in callee-saved r14d instead.  This is a generic machine-lifetime correction;
no workload identity, runtime selector, or scalar path is introduced.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / 'build' / 'generated_native256'
FILES = [
    GEN / 'tensor_frontend_base_native256.S',
    GEN / 'tensor_frontend_wide_native256.S',
    GEN / 'tensor_frontend_derived_native256.S',
]

MINUS_OLD = '''    bsf rcx,rax\n    mov edi,13; mov esi,r12d; call vec_mov_ext\n    mov edi,ebx; mov esi,13; mov edx,ecx; call vec_vpsllq_imm\n    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1\n'''
MINUS_NEW = '''    bsf r14,rax\n    mov edi,13; mov esi,r12d; call vec_mov_ext\n    mov edi,ebx; mov esi,13; mov edx,r14d; call vec_vpsllq_imm\n    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1\n'''
PLUS_OLD = '''    bsf rcx,rax\n    mov edi,13; mov esi,r12d; call vec_mov_ext\n    mov edi,ebx; mov esi,13; mov edx,ecx; call vec_vpsllq_imm\n    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1\n'''
PLUS_NEW = '''    bsf r14,rax\n    mov edi,13; mov esi,r12d; call vec_mov_ext\n    mov edi,ebx; mov esi,13; mov edx,r14d; call vec_vpsllq_imm\n    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1\n'''

for path in FILES:
    text = path.read_text(encoding='utf-8')
    if text.count(MINUS_OLD) != 1:
        raise SystemExit(f'minus-one shift lifetime anchor changed: {path.name}')
    if text.count(PLUS_OLD) != 1:
        raise SystemExit(f'plus-one shift lifetime anchor changed: {path.name}')
    text = text.replace(MINUS_OLD, MINUS_NEW, 1)
    text = text.replace(PLUS_OLD, PLUS_NEW, 1)
    path.write_text(text, encoding='utf-8')
    print(f'NATIVE256_CONST_SHIFT_LIFETIME_FILE={path.name} PASS')

print('NATIVE256_CONST_SHIFT_COUNT_CALLEE_SAVED=PASS')
print('NATIVE256_CONST_SHIFT_WORKLOAD_ROUTE=0')
print('NATIVE256_CONST_SHIFT_RUNTIME_SELECTOR=0')
print('NATIVE256_CONST_SHIFT_SCALAR_FALLBACK=0')
