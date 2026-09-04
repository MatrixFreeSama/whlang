#!/usr/bin/env python3
from pathlib import Path
import re

SRC = Path('build/tensor_frontend_product_subtract_residency.S')
BASE = Path('build/tensor_frontend_shared_base_125.S')
WIDE = Path('build/tensor_frontend_shared_wide_125.S')
text = SRC.read_text(encoding='utf-8')

# Compile-time reciprocal generation for tolerant FP. Strict mode remains on the
# mature exact-power-of-two path. This helper executes in the AOT compiler only;
# no division instruction is copied into generated runtime code. The reciprocal
# calculation temporarily installs the canonical IEEE binary64 MXCSR state and
# restores the caller state immediately. Subnormal reciprocal results are still
# rejected, keeping emitted runtime behavior independent of a consumer FTZ/DAZ
# environment; those cases retain the proved vector division recipe.
anchor = '''.rpf_no:\n    xor eax,eax\n    mov edx,1\n    ret\n\n# gen_load_f64_bits'''
if anchor not in text:
    raise SystemExit('reciprocal helper anchor missing')
helper = '''.rpf_no:\n    xor eax,eax\n    mov edx,1\n    ret\n\n# tolerant_recip_f64_bits(rax=f64 bits) -> rounded normal binary64 reciprocal bits.\n# Reject zero, NaN, infinity and subnormal results. Used only when tensor_tolerant_fp is set.\ntolerant_recip_f64_bits:\n    mov rcx,rax\n    mov rdx,rcx\n    btr rdx,63\n    test rdx,rdx\n    jz .trf_no\n    mov r8,rdx\n    shr r8,52\n    and r8d,0x7ff\n    cmp r8d,0x7ff\n    je .trf_no\n    movq xmm0,rcx\n    sub rsp,16\n    stmxcsr dword ptr [rsp]\n    mov dword ptr [rsp+4],0x1f80\n    ldmxcsr dword ptr [rsp+4]\n    mov rcx,0x3ff0000000000000\n    movq xmm1,rcx\n    divsd xmm1,xmm0\n    movq rax,xmm1\n    ldmxcsr dword ptr [rsp]\n    add rsp,16\n    mov rcx,rax\n    shr rcx,52\n    and ecx,0x7ff\n    test ecx,ecx\n    jz .trf_no\n    cmp ecx,0x7ff\n    je .trf_no\n    xor edx,edx\n    ret\n.trf_no:\n    xor eax,eax\n    mov edx,1\n    ret\n\n# gen_load_f64_bits'''
text = text.replace(anchor, helper, 1)

# Extend the ordinary vector division lowering. Exact reciprocal stays first, so
# strict and already-mature power-of-two cases emit the same runtime instruction
# sequence. Only tolerant non-power-of-two literal division takes the new path.
old = '''    call recip_pow2_f64_bits\n    test edx,edx; jnz .evf_normal_bin\n    mov r12,rax\n    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail\n'''
new = '''    call recip_pow2_f64_bits\n    test edx,edx; jz .evf_div_have_recip\n    cmp dword ptr [rip+tensor_tolerant_fp],0\n    je .evf_normal_bin\n    mov rdi,r14; call expr_literal_f64_bits\n    test edx,edx; jnz .evf_normal_bin\n    call tolerant_recip_f64_bits\n    test edx,edx; jnz .evf_normal_bin\n.evf_div_have_recip:\n    mov r12,rax\n    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail\n'''
if old not in text:
    raise SystemExit('vector division reciprocal anchor missing')
text = text.replace(old, new, 1)

# Tolerant flattened accumulation should recognize the same literal reciprocal,
# otherwise a non-power-of-two division hidden inside an add tree would fall back
# to VDIVPD and defeat episode fusion.
old = '''    call recip_pow2_f64_bits\n    test edx,edx; jnz .evfa_fallback\n    mov r14,rax\n.evfa_scaled:\n'''
new = '''    call recip_pow2_f64_bits\n    test edx,edx; jz .evfa_div_have_recip\n    mov rdi,rbx; call expr_literal_f64_bits\n    test edx,edx; jnz .evfa_fallback\n    call tolerant_recip_f64_bits\n    test edx,edx; jnz .evfa_fallback\n.evfa_div_have_recip:\n    mov r14,rax\n.evfa_scaled:\n'''
if old not in text:
    raise SystemExit('accumulator division reciprocal anchor missing')
text = text.replace(old, new, 1)

BASE.write_text(text, encoding='utf-8')

# Wide recipe: keep runtime-owned ZMM12..15 untouched. Persistent dependency/CSE
# ownership expands only inside the architecturally free ZMM16..29 domain; ZMM30
# and ZMM31 remain immutable constant carriers. Constants beyond two are already
# supported by RIP-relative EVEX broadcasts, so no scalar path is introduced.
wide = text
repls = [
    ('mov dword ptr [rip+vec_cache_reg_mask],0x000003FF # ZMM16..25 shared persistent ownership domain',
     'mov dword ptr [rip+vec_cache_reg_mask],0x00003FFF # ZMM16..29 shared persistent ownership domain'),
    ('mov dword ptr [rip+vec_const_reg_mask],0x0000003F # ZMM26..31 constant ownership domain',
     'mov dword ptr [rip+vec_const_reg_mask],0x00000003 # ZMM30..31 constant ownership domain'),
    ('cmp edi,25\n    jbe .vf_cache_pool', 'cmp edi,29\n    jbe .vf_cache_pool'),
    ('cmp edi,9\n    ja .vcrf_done', 'cmp edi,13\n    ja .vcrf_done'),
    ('lea eax,[ecx+26]\n    ret\n.vcora_fail:', 'lea eax,[ecx+30]\n    ret\n.vcora_fail:'),
    ('sub edi,26\n    cmp edi,5\n    ja .vcorf_done', 'sub edi,30\n    cmp edi,1\n    ja .vcorf_done'),
]
for a,b in repls:
    if a not in wide:
        raise SystemExit(f'wide ownership anchor missing: {a[:60]}')
    wide = wide.replace(a,b,1)
wide = wide.replace('ZMM16..25 is a shared physical pool', 'ZMM16..29 is a shared physical pool')
wide = wide.replace('Persistent CSE registers and pressure-borrowed temporaries share ZMM16..25.', 'Persistent CSE registers and pressure-borrowed temporaries share ZMM16..29.')
wide = wide.replace('Read-only constant registers are a disjoint physical ownership domain: ZMM26..31.', 'Read-only constant registers are a disjoint physical ownership domain: ZMM30..31.')
wide = wide.replace('vec_emit_init_const(edi=ZMM26..31', 'vec_emit_init_const(edi=ZMM30..31')
wide = wide.replace('vec_const_get_reg(rsi=qword bits) -> eax resident ZMM26..31', 'vec_const_get_reg(rsi=qword bits) -> eax resident ZMM30..31')
WIDE.write_text(wide, encoding='utf-8')
print('SHARED_DEPENDENCY_EPISODE_BASE_1_2_5=DERIVED')
print('SHARED_DEPENDENCY_EPISODE_WIDE_1_2_5=DERIVED')
print('SHARED_DEPENDENCY_EPISODE_RUNTIME_RESERVED_ZMM12_15=PROTECTED')
print('SHARED_DEPENDENCY_EPISODE_AOT_MXCSR_CANONICAL=PASS')
print('SHARED_DEPENDENCY_EPISODE_SUBNORMAL_RECIPROCAL_REJECT=PASS')
print('SHARED_DEPENDENCY_EPISODE_SCALAR_FALLBACK=0')
