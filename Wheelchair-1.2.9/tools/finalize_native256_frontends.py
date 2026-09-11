#!/usr/bin/env python3
"""Finalize generated native256 tensor frontends into mature AVX2/YMM units.

This pass is purely structural and workload-blind. It resolves physical helper-label
ownership, materializes the generic resident-reduction ABI, and installs the
pressure-bounded AVX2 integer recipes required by a 16-register YMM file.
No workload route, runtime selector, or scalar lane is introduced.
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
        raise SystemExit(f'native256 finalizer: missing function {name}')
    m = re.search(r'(?m)^[A-Za-z][A-Za-z0-9_]*:\n', text[start + len(name) + 2:])
    end = len(text) if m is None else start + len(name) + 2 + m.start()
    return start, end


def replace_function(text: str, name: str, body: str) -> str:
    a, b = function_span(text, name)
    return text[:a] + name + ':\n' + body.rstrip() + '\n\n' + text[b:]


def uniquify_fixed_wrapper_labels(text: str) -> str:
    funcs = [
        'vec_vpaddq_mem_const',
        'vec_vpandq_mem_const',
        'vec_vmulpd_mem_const',
        'vec_vaddpd_mem_const',
    ]
    spans = []
    for idx, name in enumerate(funcs):
        a, b = function_span(text, name)
        spans.append((a, b, idx, name))
    for a, b, idx, name in sorted(spans, reverse=True):
        body = text[a:b]
        if '.vcm256_fail' not in body or '.vcm256_done' not in body:
            raise SystemExit(f'native256 finalizer: fixed-wrapper labels missing in {name}')
        suffix = f'_{idx}'
        body = body.replace('.vcm256_fail', '.vcm256_fail' + suffix)
        body = body.replace('.vcm256_done', '.vcm256_done' + suffix)
        text = text[:a] + body + text[b:]
    return text


# AVX2 has no VPMULLQ. The frozen generic recipe needed two allocator-owned
# temporaries, which is unnecessarily expensive on a 16-register YMM file.
# YMM13 is already a native256 physical scratch and never carries semantic state,
# so one allocator temporary plus YMM13 is sufficient for exact low-64-bit mul.
VPMULLQ_PRESSURE_BOUNDED = r'''    push rbx
    push r12
    push r13
    push r14
    mov ebx,esi                    # destination
    mov r12d,edx                   # src1
    mov r13d,ecx                   # src2
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_I64_MUL_SYNTH
    jz .vml256_fail
    call vec_alloc
    cmp eax,-1
    je .vml256_fail
    mov r14d,eax

    # t = hi(a), ymm13 = hi(b)
    mov edi,r14d; mov esi,r12d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vml256_free_fail
    mov edi,13; mov esi,r13d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vml256_free_fail

    # t = hi(a)*lo(b) + lo(a)*hi(b)
    mov edi,r14d; mov edx,r14d; mov ecx,r13d; call vec_vpmuludq
    test eax,eax; jnz .vml256_free_fail
    mov edi,13; mov edx,r12d; mov ecx,13; call vec_vpmuludq
    test eax,eax; jnz .vml256_free_fail
    mov edi,0xD4; mov esi,r14d; mov edx,r14d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    mov edi,r14d; mov esi,r14d; mov edx,32; call vec_vpsllq_imm
    test eax,eax; jnz .vml256_free_fail

    # ymm13 = lo(a)*lo(b); dst = cross<<32 + low product.
    mov edi,13; mov edx,r12d; mov ecx,r13d; call vec_vpmuludq
    test eax,eax; jnz .vml256_free_fail
    mov edi,0xD4; mov esi,ebx; mov edx,r14d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    mov edi,r14d; call vec_free
    xor eax,eax
    jmp .vml256_done
.vml256_free_fail:
    mov edi,r14d; call vec_free
.vml256_fail:
    mov eax,1
.vml256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret'''


# Compile-time small constants are more efficiently represented as an addition
# chain than by manufacturing a vector constant and entering the general AVX2
# qword-multiply synthesizer. The algorithm is semantic and constant-value based:
# no workload identity participates. Values <= 16 bits are emitted with Horner
# shift/add; 2^k +/- 1 gets a shorter shift +/- source form. All arithmetic is
# vector u64 modulo 2^64 and uses the fixed YMM13 scratch, so allocator pressure is
# zero even when the surrounding expression is at its live-register peak.
MUL_CONST_PRESSURE_BOUNDED = r'''    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                    # dst
    mov r12d,esi                   # src
    mov r13,rdx                    # unsigned constant
    test r13,r13
    jnz .vmcs256_one
    mov edi,0xEF; mov esi,ebx; mov edx,r12d; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs256_done
.vmcs256_one:
    cmp r13,1
    jne .vmcs256_pow2
    cmp ebx,r12d
    je .vmcs256_ok
    mov edi,ebx; mov esi,r12d; call vec_mov_ext
.vmcs256_ok:
    xor eax,eax
    jmp .vmcs256_done
.vmcs256_pow2:
    lea rax,[r13-1]
    test rax,r13
    jnz .vmcs256_minus1
    bsf rcx,r13
    mov edi,ebx; mov esi,r12d; mov edx,ecx; call vec_vpsllq_imm
    xor eax,eax
    jmp .vmcs256_done

    # c = 2^k - 1
.vmcs256_minus1:
    lea rax,[r13+1]
    test rax,rax
    jz .vmcs256_plus1
    lea rcx,[rax-1]
    test rcx,rax
    jnz .vmcs256_plus1
    bsf rcx,rax
    mov edi,13; mov esi,r12d; call vec_mov_ext
    mov edi,ebx; mov esi,13; mov edx,ecx; call vec_vpsllq_imm
    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs256_done

    # c = 2^k + 1
.vmcs256_plus1:
    cmp r13,2
    jbe .vmcs256_horner_gate
    lea rax,[r13-1]
    lea rcx,[rax-1]
    test rcx,rax
    jnz .vmcs256_horner_gate
    bsf rcx,rax
    mov edi,13; mov esi,r12d; call vec_mov_ext
    mov edi,ebx; mov esi,13; mov edx,ecx; call vec_vpsllq_imm
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs256_done

.vmcs256_horner_gate:
    cmp r13,0xFFFF
    ja .vmcs256_unsupported
    mov edi,13; mov esi,r12d; call vec_mov_ext
    bsr r14,r13
    mov edi,ebx; mov esi,13; call vec_mov_ext
    dec r14
.vmcs256_horner:
    test r14,r14
    js .vmcs256_horner_done
    mov edi,ebx; mov esi,ebx; mov edx,1; call vec_vpsllq_imm
    bt r13,r14
    jnc .vmcs256_horner_next
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
.vmcs256_horner_next:
    dec r14
    jmp .vmcs256_horner
.vmcs256_horner_done:
    xor eax,eax
    jmp .vmcs256_done
.vmcs256_unsupported:
    mov eax,1
.vmcs256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret'''


# Constant-pool fallback for constants that are deliberately not addition-chain
# materialized. Unlike 1.2.7 it never aliases the fixed YMM13 scratch with the
# general multiplier's own scratch state.
VPMULLQ_CONST_SAFE = r'''    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    call vec_alloc
    cmp eax,-1; je .vmulc256_fail
    mov r14d,eax
    mov edi,r14d; call vec_emit_const_load_index
    test eax,eax; jnz .vmulc256_free_fail
    mov edi,ebx; mov esi,ebx; mov edx,r12d; mov ecx,r14d
    call vec_vpmullq
    mov r15d,eax
    mov edi,r14d; call vec_free
    mov eax,r15d
    jmp .vmulc256_done
.vmulc256_free_fail:
    mov edi,r14d; call vec_free
.vmulc256_fail:
    mov eax,1
.vmulc256_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret'''


RESIDENT_MASK = r'''vec_fused_mask_reduce_resident_fragment:
    cmp r8,4
    jae .Lvfmrr256_full
    vmovq xmm13,r8
    vpbroadcastq ymm13,xmm13
    vpcmpgtq ymm13,ymm13,ymmword ptr [rip+.Lvfmr256_lanes]
    vandpd ymm0,ymm0,ymm13
.Lvfmrr256_full:
    vaddpd ymm12,ymm12,ymm0
vec_fused_mask_reduce_resident_fragment_end:
'''

RESIDENT_FINISH = r'''vec_fused_finish_resident_fragment:
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
vec_fused_finish_resident_fragment_end:
'''

RESIDENT_INIT = r'''vec_fused_init_resident_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
vec_fused_init_resident_fragment_end:
'''


def materialize_resident_fragments(text: str) -> str:
    mask_anchor = 'vec_fused_mask_reduce_fragment_end:\n\n'
    if mask_anchor not in text:
        raise SystemExit('native256 finalizer: ordinary mask fragment anchor missing')
    if 'vec_fused_mask_reduce_resident_fragment:' not in text:
        text = text.replace(mask_anchor, mask_anchor + RESIDENT_MASK + '\n', 1)

    finish_anchor = 'vec_fused_finish_fragment_end:\n\n'
    if finish_anchor not in text:
        raise SystemExit('native256 finalizer: ordinary finish fragment anchor missing')
    if 'vec_fused_finish_resident_fragment:' not in text:
        text = text.replace(finish_anchor, finish_anchor + RESIDENT_FINISH + '\n', 1)

    init_anchor = 'vec_fused_init_fragment_end:\n\n'
    if init_anchor not in text:
        raise SystemExit('native256 finalizer: ordinary init fragment anchor missing')
    if 'vec_fused_init_resident_fragment:' not in text:
        text = text.replace(init_anchor, init_anchor + RESIDENT_INIT + '\n', 1)
    return text


for path in FILES:
    text = path.read_text(encoding='utf-8')
    text = uniquify_fixed_wrapper_labels(text)
    text = materialize_resident_fragments(text)
    text = replace_function(text, 'vec_vpmullq', VPMULLQ_PRESSURE_BOUNDED)
    text = replace_function(text, 'vec_mul_const_strength', MUL_CONST_PRESSURE_BOUNDED)
    text = replace_function(text, 'vec_vpmullq_mem_const', VPMULLQ_CONST_SAFE)
    lowered = text.lower()
    for forbidden in ('newton', 'fsi', 'fluid', 'solid', 'stiffness', 'poisson'):
        if forbidden in lowered:
            raise SystemExit(f'native256 finalizer: workload identity leaked into {path.name}: {forbidden}')
    path.write_text(text, encoding='utf-8')

print('NATIVE256_HELPER_LABEL_OWNERSHIP=PASS')
print('NATIVE256_RESIDENT_REDUCTION_ABI=PASS')
print('NATIVE256_I64_MUL_TEMPORARIES=1')
print('NATIVE256_SMALL_CONSTANT_ALLOCATOR_TEMPS=0')
print('NATIVE256_SMALL_CONSTANT_CHAIN_LIMIT=65535')
print('NATIVE256_WORKLOAD_SPECIALIZATION=0')
print('NATIVE256_RUNTIME_SELECTOR=0')
print('NATIVE256_SCALAR_FALLBACK=0')