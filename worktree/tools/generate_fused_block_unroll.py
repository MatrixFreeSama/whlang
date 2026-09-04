#!/usr/bin/env python3
from pathlib import Path

SRC = Path('build/tensor_frontend_product_subtract_residency.S')
OUT = Path('build/tensor_frontend_product_subtract_residency_unroll2.S')
text = SRC.read_text(encoding='utf-8')

# The second reduction carrier is a fixed ABI hole, not a dynamically stolen
# expression register.  The mature allocator owns ZMM1..5,8..11, emergency
# ZMM13, topology/induction ZMM16..25 and constants ZMM26..31.  ZMM14 is not in
# any ownership set.  Refuse derivation if that invariant ever changes.
if 'zmm14' in text.lower():
    raise SystemExit('ZMM14 unexpectedly occupied before static fused-block unroll')

# Compiler-only state.  It never enters the emitted runtime image.
bss_anchor = 'vec_fused_common_disp:.skip 8\n'
if text.count(bss_anchor) != 1:
    raise SystemExit('bulk-unroll BSS anchor changed')
text = text.replace(
    bss_anchor,
    bss_anchor
    + 'vec_fused_bulk_remaining_disp:.skip 8\n'
    + 'vec_fused_bulk_end_disp:.skip 8\n'
    + 'vec_bulk_unroll_active:.skip 4\n',
    1,
)

init_anchor = '    mov dword ptr [rip+vec_product_subtract_contractions],0\n    mov dword ptr [rip+vec_induct_count],0\n'
if text.count(init_anchor) != 1:
    raise SystemExit('bulk-unroll compiler-state init anchor changed')
text = text.replace(
    init_anchor,
    '    mov dword ptr [rip+vec_product_subtract_contractions],0\n'
    '    mov dword ptr [rip+vec_bulk_unroll_active],0\n'
    '    mov dword ptr [rip+vec_induct_count],0\n',
    1,
)

# Replace only the interior builder.  The first interior evaluator is lowered
# exactly as before, which lets the already-proven structural contraction act
# as a conservative compile-time profitability certificate.  If it did not
# fire, the frozen one-block builder is emitted byte-for-byte as before.
interior_anchor = '''    mov dword ptr [rip+vec_interior_mode],1\n    mov rdi,[r15+40]\n    xor esi,esi\n    call emit_vec_float\n    test eax,eax\n    jnz .fail\n    call vec_emit_jmp_placeholder\n    test rax,rax\n    jz .fail\n    mov [rip+vec_fused_common_disp],rax\n\n    # Cache values created while compiling the mutually-exclusive interior body\n    # are local to that path. Release only their compile-time ownership before\n    # lowering the safe body; persistent induction carriers remain reserved.\n    call vec_cache_free_current\n\n    # Boundary-safe vector body. Patch both discriminator edges here, then lower\n'''
if text.count(interior_anchor) != 1:
    raise SystemExit('interior fused-body builder anchor changed')
interior_repl = '''    mov dword ptr [rip+vec_interior_mode],1\n    mov rdi,[r15+40]\n    xor esi,esi\n    call emit_vec_float\n    test eax,eax\n    jnz .fail\n\n    # Generic compile-time two-block fused unroll.  The decision is based only\n    # on emitted structural algebra, never a source/workload name.  The runtime\n    # bulk gate executes once per *pair* and only asks whether a second full\n    # interior vector is legal.  There is no per-block carrier selector.\n    cmp dword ptr [rip+vec_product_subtract_contractions],0\n    je .vec_bulk_legacy_interior\n    mov dword ptr [rip+vec_bulk_unroll_active],1\n\n    lea rdi,[rip+vec_fused_bulk_remaining_test_fragment]\n    mov esi,vec_fused_bulk_remaining_test_fragment_end-vec_fused_bulk_remaining_test_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    call vec_emit_jbe_placeholder\n    test rax,rax\n    jz .fail\n    mov [rip+vec_fused_bulk_remaining_disp],rax\n\n    lea rdi,[rip+vec_fused_bulk_end_test_fragment]\n    mov esi,vec_fused_bulk_end_test_fragment_end-vec_fused_bulk_end_test_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    call vec_emit_jae_placeholder\n    test rax,rax\n    jz .fail\n    mov [rip+vec_fused_bulk_end_disp],rax\n\n    # First full vector goes to carrier 0.  Because remaining>16 and the second\n    # block is globally interior, no mask is needed here.\n    lea rdi,[rip+vec_fused_bulk_accum0_fragment]\n    mov esi,vec_fused_bulk_accum0_fragment_end-vec_fused_bulk_accum0_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    call vec_emit_fused_step8\n    test eax,eax\n    jnz .fail\n\n    # The second statically emitted evaluator must not reuse first-block CSE\n    # values.  Release only current-generation cache ownership and start a new\n    # compile-time generation; induction carriers remain persistent and are the\n    # values advanced by the emitted step above.\n    call vec_cache_free_current\n    inc dword ptr [rip+vec_gen_counter]\n    mov eax,dword ptr [rip+vec_gen_counter]\n    mov dword ptr [rip+vec_current_gen],eax\n    mov rdi,[r15+40]\n    xor esi,esi\n    call emit_vec_float\n    test eax,eax\n    jnz .fail\n    lea rdi,[rip+vec_fused_bulk_accum1_fragment]\n    mov esi,vec_fused_bulk_accum1_fragment_end-vec_fused_bulk_accum1_fragment\n    call vec_emit_bytes\n    test eax,eax\n    jnz .fail\n    call vec_emit_fused_step8\n    test eax,eax\n    jnz .fail\n    call vec_cache_free_current\n\n    # One back edge now represents sixteen source points and two independent\n    # eight-lane accumulation chains.\n    mov rsi,[rip+vec_fused_loop_start]\n    call vec_emit_jmp_to\n    test eax,eax\n    jnz .fail\n    jmp .vec_bulk_boundary_compile\n\n.vec_bulk_legacy_interior:\n    call vec_emit_jmp_placeholder\n    test rax,rax\n    jz .fail\n    mov [rip+vec_fused_common_disp],rax\n    call vec_cache_free_current\n\n.vec_bulk_boundary_compile:\n    # Boundary-safe vector body. Patch both discriminator edges here, then lower\n'''
text = text.replace(interior_anchor, interior_repl, 1)

# In the unrolled recipe, two conditional edges from the first interior body
# fall back to the mature common mask/reduce path when a second block is not
# legal.  Programs that never admitted the structural recipe retain the old
# single unconditional interior-to-common edge.
common_anchor = '''    # Both vector regions converge on the same masked reduction fabric.\n    mov rsi,[rip+vec_emit_ptr]\n    mov rdi,[rip+vec_fused_common_disp]\n    call vec_patch_rel32\n    test eax,eax\n    jnz .fail\n    # Generic tolerant Vector Reduction Residency.  A program that proved\n'''
if text.count(common_anchor) != 1:
    raise SystemExit('common reduction patch anchor changed')
common_repl = '''    # Both vector regions converge on the same masked reduction fabric.\n    cmp dword ptr [rip+vec_bulk_unroll_active],0\n    je .vec_bulk_patch_legacy_common\n    mov rsi,[rip+vec_emit_ptr]\n    mov rdi,[rip+vec_fused_bulk_remaining_disp]\n    call vec_patch_rel32\n    test eax,eax\n    jnz .fail\n    mov rsi,[rip+vec_emit_ptr]\n    mov rdi,[rip+vec_fused_bulk_end_disp]\n    call vec_patch_rel32\n    test eax,eax\n    jnz .fail\n    jmp .vec_bulk_common_patched\n.vec_bulk_patch_legacy_common:\n    mov rsi,[rip+vec_emit_ptr]\n    mov rdi,[rip+vec_fused_common_disp]\n    call vec_patch_rel32\n    test eax,eax\n    jnz .fail\n.vec_bulk_common_patched:\n    # Generic tolerant Vector Reduction Residency.  A program that proved\n'''
text = text.replace(common_anchor, common_repl, 1)

# Add the bulk legality tests and two fixed accumulation destinations alongside
# the resident reduction fragment.  These are copied into generated RX; no
# runtime metadata or central dispatch is introduced.
frag_anchor = '''vec_fused_mask_reduce_resident_fragment_end:\n\nvec_fused_cmp8_fragment:\n'''
if text.count(frag_anchor) != 1:
    raise SystemExit('resident fragment insertion anchor changed')
text = text.replace(
    frag_anchor,
    '''vec_fused_mask_reduce_resident_fragment_end:\n\n# A pair is legal only when more than sixteen chunk elements remain and the\n# second eight-lane vector is also strictly before the global last element.\nvec_fused_bulk_remaining_test_fragment:\n    cmp r8,16\nvec_fused_bulk_remaining_test_fragment_end:\nvec_fused_bulk_end_test_fragment:\n    lea rax,[rsi+16]\n    cmp rax,rdi\nvec_fused_bulk_end_test_fragment_end:\nvec_fused_bulk_accum0_fragment:\n    vaddpd zmm12,zmm12,zmm0\nvec_fused_bulk_accum0_fragment_end:\nvec_fused_bulk_accum1_fragment:\n    vaddpd zmm14,zmm14,zmm0\nvec_fused_bulk_accum1_fragment_end:\n\nvec_fused_cmp8_fragment:\n''',
    1,
)

# The second carrier is initialized once per chunk and merged exactly once at
# finish.  A resident-but-not-unrolled program therefore merely adds zero,
# preserving semantics while keeping one deterministic resident ABI.
finish_anchor = '''vec_fused_finish_resident_fragment:\n    vextractf64x4 ymm13,zmm12,1\n'''
if text.count(finish_anchor) != 1:
    raise SystemExit('resident finish fragment anchor changed')
text = text.replace(
    finish_anchor,
    '''vec_fused_finish_resident_fragment:\n    vaddpd zmm12,zmm12,zmm14\n    vextractf64x4 ymm13,zmm12,1\n''',
    1,
)
init_frag_anchor = '''vec_fused_init_resident_fragment:\n    mov r8,rdx\n    sub r8,rsi\n    vxorpd zmm12,zmm12,zmm12\nvec_fused_init_resident_fragment_end:\n'''
if text.count(init_frag_anchor) != 1:
    raise SystemExit('resident init fragment anchor changed')
text = text.replace(
    init_frag_anchor,
    '''vec_fused_init_resident_fragment:\n    mov r8,rdx\n    sub r8,rsi\n    vxorpd zmm12,zmm12,zmm12\n    vxorpd zmm14,zmm14,zmm14\nvec_fused_init_resident_fragment_end:\n''',
    1,
)

# Compiler helper: emit exactly the mature one-block state advance.  This is a
# build-time helper, not a generated call edge.  It is used between the two
# statically emitted evaluators and after the second evaluator.
helper_anchor = '# ---------------- JSON DOM parser ----------------\n'
if text.count(helper_anchor) != 1:
    raise SystemExit('compiler helper insertion anchor changed')
helper = r'''# Emit one SIMD-block recurrence into generated RX.  eax=0 success, 1 failure.
vec_emit_fused_step8:
    push r12
    lea rdi,[rip+vec_fused_sub8_fragment]
    mov esi,vec_fused_sub8_fragment_end-vec_fused_sub8_fragment
    call vec_emit_bytes
    test eax,eax
    jnz .vefs8_fail
    lea rdi,[rip+vec_fused_add_index8_fragment]
    mov esi,vec_fused_add_index8_fragment_end-vec_fused_add_index8_fragment
    call vec_emit_bytes
    test eax,eax
    jnz .vefs8_fail
    mov rsi,8
    call vec_const_intern
    cmp eax,-1
    je .vefs8_fail
    mov edx,eax
    mov edi,6
    mov esi,6
    call vec_vpaddq_mem_const
    test eax,eax
    jnz .vefs8_fail
    xor r12d,r12d
.vefs8_induct:
    cmp r12d,dword ptr [rip+vec_induct_count]
    jae .vefs8_done
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    mov rax,rsi
    mov rcx,8
    mul rcx
    test rdx,rdx
    jnz .vefs8_fail
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1
    je .vefs8_fail
    mov edx,eax
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    call vec_vpaddq_mem_const
    test eax,eax
    jnz .vefs8_fail
    inc r12d
    jmp .vefs8_induct
.vefs8_done:
    xor eax,eax
    pop r12
    ret
.vefs8_fail:
    mov eax,1
    pop r12
    ret

'''
text = text.replace(helper_anchor, helper + helper_anchor, 1)

OUT.write_text(text, encoding='utf-8')
print('GENERIC_STATIC_FUSED_BLOCK_UNROLL=DERIVED')
print('STATIC_FUSED_BLOCK_UNROLL_FACTOR=2')
print('STATIC_FUSED_BLOCK_REDUCTION_CARRIERS=2')
print('STATIC_FUSED_BLOCK_RUNTIME_CARRIER_DISPATCH=0')
print('STATIC_FUSED_BLOCK_SCALAR_FALLBACK=0')
