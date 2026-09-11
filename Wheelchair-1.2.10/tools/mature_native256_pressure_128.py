#!/usr/bin/env python3
"""Second-stage limited-register maturation for native256.

This pass is workload-blind.  It lowers two AVX2 pressure peaks that are cheap on
32-register AVX-512 but unnecessarily expensive on a 16-register YMM file:

* qword->double synthesis uses one allocator temporary plus the fixed YMM13
  physical scratch instead of two allocator temporaries;
* qword-to-dword packing uses its destination as the upper-half staging register,
  so it no longer consumes a second hidden scratch.

No scalar lane, runtime selector, workload identity, or source-path route exists.
"""
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / 'build' / 'generated_native256'
FILES = [
    GEN / 'tensor_frontend_base_native256.S',
    GEN / 'tensor_frontend_wide_native256.S',
    GEN / 'tensor_frontend_derived_native256.S',
]


def function_span(text: str, name: str) -> tuple[int, int]:
    start = text.find(name + ':\n')
    if start < 0:
        raise SystemExit(f'native256 pressure pass: missing {name}')
    m = re.search(r'(?m)^[A-Za-z][A-Za-z0-9_]*:\n', text[start + len(name) + 2:])
    end = len(text) if m is None else start + len(name) + 2 + m.start()
    return start, end


def replace_function(text: str, name: str, body: str) -> str:
    a, b = function_span(text, name)
    return text[:a] + name + ':\n' + body.rstrip() + '\n\n' + text[b:]


PACK_QD_DEST_STAGING = r'''    # Pack low dword of four qword lanes into XMM dst.
    # dst must differ from src. The destination itself receives the high 128
    # half first, then VSHUFPS combines low(src) and high(src). No hidden YMM
    # scratch is consumed, which is important on AVX2's 16-register file.
    push rbx
    mov ebx,edi
    mov r10d,esi
    cmp ebx,r10d
    je .vpack256_fail

    # vextracti128 xmmDST,ymmSRC,1
    mov edi,0xC4; call vec_emit_u8
    mov eax,r10d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40                    # X unused -> inverted one
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,3                       # map 0F3A
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8 # L=256, pp=66
    mov edi,0x39; call vec_emit_u8
    mov eax,r10d; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,1; call vec_emit_u8

    # vshufps xmmDST,xmmSRC,xmmDST,0x88
    # => [src.d0,src.d2,upper.d0,upper.d2] = four low qword dwords.
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1                       # map 0F
    mov edi,eax; call vec_emit_u8
    mov eax,r10d; not eax; and eax,0xF; shl eax,3
    mov edi,eax; call vec_emit_u8  # L=128, pp=none
    mov edi,0xC6; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,0x88; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax
    pop rbx
    ret
.vpack256_fail:
    mov eax,1
    pop rbx
    ret'''


CVT_QQ_PD_ONE_TEMP = r'''    # Exact signed i64 -> f64 using one allocator temp.
    # Caller-generated uses have distinct dst/src. YMM13 is the native256 fixed
    # physical scratch and never owns semantic state.
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                    # destination
    mov r12d,esi                   # source
    cmp ebx,r12d
    je .vcq2pds256_fail

    call vec_alloc
    cmp eax,-1
    je .vcq2pds256_fail
    mov r13d,eax                   # one allocator-owned temporary

    mov rsi,0x41F0000000000000     # exact binary64 2^32
    call vec_const_intern
    cmp eax,-1
    je .vcq2pds256_free_fail
    mov r14d,eax

    # temp = high signed dword source; YMM13 = low-dword sign bit.
    mov edi,r13d; mov esi,r12d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,13; mov esi,r12d; mov edx,31; call vec_vpsrld_imm
    test eax,eax; jnz .vcq2pds256_free_fail

    # Convert high32 first, then retain the double vector in temp.
    mov edi,ebx; mov esi,r13d; call vec_vpmovqd_ymm_from_zmm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,ebx; mov esi,ebx; call vec_vcvtdq2pd_zmm_from_ymm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,r13d; mov esi,ebx; call vec_mov_ext

    # Convert low32 sign correction. Multiplying it by 2^32 may clobber YMM13
    # inside the constant helper, which is fine after the packed sign is in dst.
    mov edi,ebx; mov esi,13; call vec_vpmovqd_ymm_from_zmm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,ebx; mov esi,ebx; call vec_vcvtdq2pd_zmm_from_ymm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,ebx; mov esi,ebx; mov edx,r14d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vcq2pds256_free_fail

    # Low signed dword -> YMM13, then add correction to form unsigned low32.
    mov edi,13; mov esi,r12d; call vec_vpmovqd_ymm_from_zmm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,13; mov esi,13; call vec_vcvtdq2pd_zmm_from_ymm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr

    # high32*2^32 + unsigned_low32. Final add is the sole int64->f64 rounding.
    mov edi,r13d; mov esi,r13d; mov edx,r14d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr

    mov edi,r13d; call vec_free
    xor eax,eax
    jmp .vcq2pds256_done
.vcq2pds256_free_fail:
    mov edi,r13d; call vec_free
.vcq2pds256_fail:
    mov eax,1
.vcq2pds256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret'''


for path in FILES:
    text = path.read_text(encoding='utf-8')
    text = replace_function(text, 'vec_vpmovqd_ymm_from_zmm', PACK_QD_DEST_STAGING)
    text = replace_function(text, 'vec_vcvtqq2pd_synth', CVT_QQ_PD_ONE_TEMP)
    lowered = text.lower()
    for forbidden in ('newton', 'fsi', 'fluid', 'solid', 'stiffness', 'poisson'):
        if forbidden in lowered:
            raise SystemExit(f'native256 pressure pass: workload identity leaked: {forbidden}')
    path.write_text(text, encoding='utf-8')

print('NATIVE256_I64_F64_CONVERT_TEMPORARIES=1')
print('NATIVE256_PACK_HIDDEN_SCRATCH=0')
print('NATIVE256_PRESSURE_MATURITY_WORKLOAD_ROUTE=0')
print('NATIVE256_PRESSURE_MATURITY_SCALAR_FALLBACK=0')
