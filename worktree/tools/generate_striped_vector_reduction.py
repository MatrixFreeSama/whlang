#!/usr/bin/env python3
from pathlib import Path

SRC = Path('build/tensor_frontend_product_subtract_residency.S')
OUT = Path('build/tensor_frontend_product_subtract_residency_striped.S')
text = SRC.read_text(encoding='utf-8')

# ZMM14 is intentionally outside every mature allocator ownership set:
#   primary temps: ZMM1..5,8..11
#   emergency temp: ZMM13
#   topology/induction pool: ZMM16..25
#   constants: ZMM26..31
# ZMM0 is the expression result, ZMM6 the root axis, ZMM7 a special integer
# helper, ZMM12 the mature reduction carrier, and ZMM15 may be used by exact
# modulo lowering.  Therefore ZMM14 is the only fixed second reduction carrier
# that can be admitted without stealing a dynamically-owned register.
if 'zmm14' in text.lower():
    raise SystemExit('ZMM14 unexpectedly occupied before striped-reduction derivation')

old_reduce = '''vec_fused_mask_reduce_resident_fragment:\n    cmp r8,8\n    jae .Lvfmrr_full\n    mov rcx,r8\n    mov rax,1\n    shl rax,cl\n    dec rax\n    kmovq k1,rax\n    vmovapd zmm0{k1}{z},zmm0\n.Lvfmrr_full:\n    vaddpd zmm12,zmm12,zmm0\nvec_fused_mask_reduce_resident_fragment_end:\n'''
new_reduce = '''vec_fused_mask_reduce_resident_fragment:\n    cmp r8,8\n    jae .Lvfmrr_full\n    mov rcx,r8\n    mov rax,1\n    shl rax,cl\n    dec rax\n    kmovq k1,rax\n    vmovapd zmm0{k1}{z},zmm0\n.Lvfmrr_full:\n    # Generic two-stripe resident reduction.  The block origin advances by eight\n    # elements, so bit 3 alternates deterministically and selects two independent\n    # accumulator dependency chains.  This is a local arithmetic dispatch only:\n    # it creates no scheduler, synchronization edge, scalar element path, or\n    # workload-specific branch.\n    test sil,8\n    jnz .Lvfmrr_stripe1\n    vaddpd zmm12,zmm12,zmm0\n    jmp .Lvfmrr_done\n.Lvfmrr_stripe1:\n    vaddpd zmm14,zmm14,zmm0\n.Lvfmrr_done:\nvec_fused_mask_reduce_resident_fragment_end:\n'''
if text.count(old_reduce) != 1:
    raise SystemExit('resident reduction fragment anchor changed')
text = text.replace(old_reduce, new_reduce, 1)

old_finish = '''vec_fused_finish_resident_fragment:\n    vextractf64x4 ymm13,zmm12,1\n    vaddpd ymm12,ymm12,ymm13\n'''
new_finish = '''vec_fused_finish_resident_fragment:\n    # Merge the two independent full-width chains exactly once per chunk, then\n    # perform the mature fixed fan-in horizontal fold.\n    vaddpd zmm12,zmm12,zmm14\n    vextractf64x4 ymm13,zmm12,1\n    vaddpd ymm12,ymm12,ymm13\n'''
if text.count(old_finish) != 1:
    raise SystemExit('resident finish fragment anchor changed')
text = text.replace(old_finish, new_finish, 1)

old_init = '''vec_fused_init_resident_fragment:\n    mov r8,rdx\n    sub r8,rsi\n    vxorpd zmm12,zmm12,zmm12\nvec_fused_init_resident_fragment_end:\n'''
new_init = '''vec_fused_init_resident_fragment:\n    mov r8,rdx\n    sub r8,rsi\n    vxorpd zmm12,zmm12,zmm12\n    vxorpd zmm14,zmm14,zmm14\nvec_fused_init_resident_fragment_end:\n'''
if text.count(old_init) != 1:
    raise SystemExit('resident init fragment anchor changed')
text = text.replace(old_init, new_init, 1)

# A compile-time audit marker, never emitted as runtime metadata.
text = text.replace(
    "print('GENERIC_VECTOR_REDUCTION_RESIDENCY=DERIVED')" if False else '__NO_SUCH_MARKER__',
    '__NO_SUCH_MARKER__',
)

OUT.write_text(text, encoding='utf-8')
print('GENERIC_STRIPED_VECTOR_REDUCTION=DERIVED')
print('STRIPED_VECTOR_REDUCTION_CARRIERS=2')
print('STRIPED_VECTOR_REDUCTION_SCALAR_FALLBACK=0')
