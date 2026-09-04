#!/usr/bin/env python3
from pathlib import Path
import sys

SRC = Path('build/tensor_frontend_product_subtract.S')
OUT = Path('build/tensor_frontend_product_subtract_residency.S')
text = SRC.read_text(encoding='utf-8')

# A structural counter records whether this program actually admitted the
# generic tolerant Product-Subtract contraction. It is compiler-only state.
# Reduction residency uses this as one conservative profitability proof route;
# it does not inspect workload, physics, matrix, or source symbol names.
bss_anchor = 'vec_fused_mode:.skip 4\n'
if bss_anchor not in text:
    raise SystemExit('vec_fused_mode bss anchor missing')
text = text.replace(bss_anchor, bss_anchor + 'vec_product_subtract_contractions:.skip 4\n', 1)

init_anchor = '    mov dword ptr [rip+vec_fused_mode],1\n    mov dword ptr [rip+vec_induct_count],0\n'
if init_anchor not in text:
    raise SystemExit('fused-mode init anchor missing')
text = text.replace(
    init_anchor,
    '    mov dword ptr [rip+vec_fused_mode],1\n'
    '    mov dword ptr [rip+vec_product_subtract_contractions],0\n'
    '    mov dword ptr [rip+vec_induct_count],0\n',
    1,
)

success_anchor = '''    mov edi,ebx; call vec_free\n    mov edi,r12d; call vec_free\n    xor eax,eax; jmp .evf_done\n.evf_product_sub_free_b_fail:\n'''
if success_anchor not in text:
    raise SystemExit('product-subtract success anchor missing')
text = text.replace(
    success_anchor,
    '''    mov edi,ebx; call vec_free\n    mov edi,r12d; call vec_free\n    inc dword ptr [rip+vec_product_subtract_contractions]\n    xor eax,eax; jmp .evf_done\n.evf_product_sub_free_b_fail:\n''',
    1,
)

# Select the resident-ZMM reduction only after both mutually-exclusive vector
# bodies have been lowered, so the decision is based on proved emitted algebra.
reduce_anchor = '''    # Mask only the final partial block, then fold the eight lanes into the four\n    # independent reduction carriers. There is no scalar tail.\n    lea rdi,[rip+vec_fused_mask_reduce_fragment]\n    mov esi,vec_fused_mask_reduce_fragment_end-vec_fused_mask_reduce_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n\n    # if remaining <= 8: finish; else remaining -= 8 and advance every axis\n'''
if reduce_anchor not in text:
    raise SystemExit('fused reduction builder anchor missing')
text = text.replace(
    reduce_anchor,
    '''    # Generic tolerant Vector Reduction Residency.  A program that proved\n    # at least one product-subtract contraction has enough admitted FP algebra\n    # for this conservative recipe.  The full eight-lane result remains in one\n    # resident ZMM carrier until the chunk boundary instead of being split and\n    # rejoined every SIMD block.  No runtime type tag or workload dispatch is\n    # emitted; unsupported/unqualified expressions retain the frozen recipe.\n    cmp dword ptr [rip+vec_product_subtract_contractions],0\n    je .vec_reduce_frozen_recipe\n    lea rdi,[rip+vec_fused_mask_reduce_resident_fragment]\n    mov esi,vec_fused_mask_reduce_resident_fragment_end-vec_fused_mask_reduce_resident_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    jmp .vec_reduce_recipe_done\n.vec_reduce_frozen_recipe:\n    lea rdi,[rip+vec_fused_mask_reduce_fragment]\n    mov esi,vec_fused_mask_reduce_fragment_end-vec_fused_mask_reduce_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n.vec_reduce_recipe_done:\n\n    # if remaining <= 8: finish; else remaining -= 8 and advance every axis\n''',
    1,
)

finish_anchor = '''    # Finish target and fixed fan-in-two carrier reduction.\n    mov rsi,[rip+vec_emit_ptr]\n    mov rdi,[rip+vec_fused_finish_disp]\n    call vec_patch_rel32\n    test eax,eax\n    jnz .fail\n    lea rdi,[rip+vec_fused_finish_fragment]\n    mov esi,vec_fused_finish_fragment_end-vec_fused_finish_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    # Initialization island. Runtime arguments are rdi=n, rsi=start, rdx=end.\n'''
if finish_anchor not in text:
    raise SystemExit('fused finish builder anchor missing')
text = text.replace(
    finish_anchor,
    '''    # Finish target.  Resident-ZMM and frozen recipes use distinct fixed\n    # tree folds but both return the same one-scalar tolerant reduction ABI.\n    mov rsi,[rip+vec_emit_ptr]\n    mov rdi,[rip+vec_fused_finish_disp]\n    call vec_patch_rel32\n    test eax,eax\n    jnz .fail\n    cmp dword ptr [rip+vec_product_subtract_contractions],0\n    je .vec_finish_frozen_recipe\n    lea rdi,[rip+vec_fused_finish_resident_fragment]\n    mov esi,vec_fused_finish_resident_fragment_end-vec_fused_finish_resident_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    jmp .vec_finish_recipe_done\n.vec_finish_frozen_recipe:\n    lea rdi,[rip+vec_fused_finish_fragment]\n    mov esi,vec_fused_finish_fragment_end-vec_fused_finish_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n.vec_finish_recipe_done:\n    # Initialization island. Runtime arguments are rdi=n, rsi=start, rdx=end.\n''',
    1,
)

init_builder_anchor = '''    lea rdi,[rip+vec_fused_init_fragment]\n    mov esi,vec_fused_init_fragment_end-vec_fused_init_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    lea rdi,[rip+vec_prefix_fragment]\n'''
if init_builder_anchor not in text:
    raise SystemExit('fused init builder anchor missing')
text = text.replace(
    init_builder_anchor,
    '''    cmp dword ptr [rip+vec_product_subtract_contractions],0\n    je .vec_init_frozen_recipe\n    lea rdi,[rip+vec_fused_init_resident_fragment]\n    mov esi,vec_fused_init_resident_fragment_end-vec_fused_init_resident_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    jmp .vec_init_recipe_done\n.vec_init_frozen_recipe:\n    lea rdi,[rip+vec_fused_init_fragment]\n    mov esi,vec_fused_init_fragment_end-vec_fused_init_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n.vec_init_recipe_done:\n    lea rdi,[rip+vec_prefix_fragment]\n''',
    1,
)

# Add relocatable fragments alongside the mature frozen fragments.  ZMM12 is
# excluded from the expression allocator by the long-standing runtime ABI, so
# keeping it live across the fused evaluator cannot alias a temporary.
frag_anchor = '''vec_fused_mask_reduce_fragment_end:\n\nvec_fused_cmp8_fragment:\n'''
if frag_anchor not in text:
    raise SystemExit('reduction fragment insertion anchor missing')
text = text.replace(
    frag_anchor,
    '''vec_fused_mask_reduce_fragment_end:\n\n# Tolerant resident-ZMM recipe: keep all eight lane chains alive until finish.\n# The final partial vector is still predicated; there is no scalar tail.\nvec_fused_mask_reduce_resident_fragment:\n    cmp r8,8\n    jae .Lvfmrr_full\n    mov rcx,r8\n    mov rax,1\n    shl rax,cl\n    dec rax\n    kmovq k1,rax\n    vmovapd zmm0{k1}{z},zmm0\n.Lvfmrr_full:\n    vaddpd zmm12,zmm12,zmm0\nvec_fused_mask_reduce_resident_fragment_end:\n\nvec_fused_cmp8_fragment:\n''',
    1,
)

finish_frag_anchor = '''vec_fused_finish_fragment_end:\n\nvec_fused_init_fragment:\n'''
if finish_frag_anchor not in text:
    raise SystemExit('finish fragment insertion anchor missing')
text = text.replace(
    finish_frag_anchor,
    '''vec_fused_finish_fragment_end:\n\n# Collapse the resident eight-lane carrier only once at the chunk boundary.\nvec_fused_finish_resident_fragment:\n    vextractf64x4 ymm13,zmm12,1\n    vaddpd ymm12,ymm12,ymm13\n    vextractf128 xmm13,ymm12,1\n    vunpckhpd xmm14,xmm13,xmm13\n    vaddsd xmm13,xmm13,xmm14\n    vunpckhpd xmm14,xmm12,xmm12\n    vaddsd xmm12,xmm12,xmm14\n    vaddsd xmm12,xmm12,xmm13\n    vmovapd xmm0,xmm12\n    ret\nvec_fused_finish_resident_fragment_end:\n\nvec_fused_init_fragment:\n''',
    1,
)

init_frag_anchor = '''vec_fused_init_fragment_end:\n\n# Relocatable copied vector prologue.'''
if init_frag_anchor not in text:
    raise SystemExit('init fragment insertion anchor missing')
text = text.replace(
    init_frag_anchor,
    '''vec_fused_init_fragment_end:\n\nvec_fused_init_resident_fragment:\n    mov r8,rdx\n    sub r8,rsi\n    vxorpd zmm12,zmm12,zmm12\nvec_fused_init_resident_fragment_end:\n\n# Relocatable copied vector prologue.''',
    1,
)

OUT.write_text(text, encoding='utf-8')
print('GENERIC_VECTOR_REDUCTION_RESIDENCY=DERIVED')
