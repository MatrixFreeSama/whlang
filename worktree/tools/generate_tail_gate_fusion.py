#!/usr/bin/env python3
from pathlib import Path

SRC = Path('build/tensor_frontend_product_subtract_residency.S')
OUT = Path('build/tensor_frontend_product_subtract_residency_tailgate.S')
text = SRC.read_text(encoding='utf-8')

# Resident reduction already compares remaining against one SIMD block before
# deciding whether a tail mask is needed.  Preserve those flags across the
# full-block VADDPD and let the subsequent finish edge consume them directly.
# Only the tail path destroys integer flags while constructing k1, so refresh
# the same compare there once.  This removes one redundant compare from every
# complete hot-loop block without changing reduction order or tail semantics.
old_frag = '''vec_fused_mask_reduce_resident_fragment:\n    cmp r8,8\n    jae .Lvfmrr_full\n    mov rcx,r8\n    mov rax,1\n    shl rax,cl\n    dec rax\n    kmovq k1,rax\n    vmovapd zmm0{k1}{z},zmm0\n.Lvfmrr_full:\n    vaddpd zmm12,zmm12,zmm0\nvec_fused_mask_reduce_resident_fragment_end:\n'''
new_frag = '''vec_fused_mask_reduce_resident_fragment:\n    cmp r8,8\n    jae .Lvfmrr_full\n    mov rcx,r8\n    mov rax,1\n    shl rax,cl\n    dec rax\n    kmovq k1,rax\n    vmovapd zmm0{k1}{z},zmm0\n    # Tail-mask construction clobbers EFLAGS. Re-establish the already-proven\n    # remaining-vs-width relation only on this final partial block.\n    cmp r8,8\n.Lvfmrr_full:\n    # VADDPD does not alter integer flags.  The following finish JBE can consume\n    # the compare emitted above, so complete blocks need no second CMP.\n    vaddpd zmm12,zmm12,zmm0\nvec_fused_mask_reduce_resident_fragment_end:\n'''
if text.count(old_frag) != 1:
    raise SystemExit('resident reduction fragment anchor changed')
text = text.replace(old_frag, new_frag, 1)

old_builder = '''    # if remaining <= 8: finish; else remaining -= 8 and advance every axis\n    # carrier by one SIMD block.\n    lea rdi,[rip+vec_fused_cmp8_fragment]\n    mov esi,vec_fused_cmp8_fragment_end-vec_fused_cmp8_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    call vec_emit_jbe_placeholder\n'''
new_builder = '''    # if remaining <= 8: finish; else remaining -= 8 and advance every axis\n    # carrier by one SIMD block.  The resident recipe leaves valid EFLAGS from\n    # its tail/full-block gate, so reusing them erases one compare per complete\n    # block.  The frozen recipe retains its byte-identical explicit CMP.\n    cmp dword ptr [rip+vec_product_subtract_contractions],0\n    jne .vec_finish_flags_ready\n    lea rdi,[rip+vec_fused_cmp8_fragment]\n    mov esi,vec_fused_cmp8_fragment_end-vec_fused_cmp8_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n.vec_finish_flags_ready:\n    call vec_emit_jbe_placeholder\n'''
if text.count(old_builder) != 1:
    raise SystemExit('fused cmp8 builder anchor changed')
text = text.replace(old_builder, new_builder, 1)

OUT.write_text(text, encoding='utf-8')
print('GENERIC_FULL_BLOCK_TAIL_GATE_FUSION=DERIVED')
print('FULL_BLOCK_REDUNDANT_CMP_ERASURE=1_PER_HOT_BLOCK')
print('TAIL_GATE_SCALAR_FALLBACK=0')
