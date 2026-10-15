.include "compiler/reduction_frontier.inc"
# 1.3.140 shared InputFact / ReductionFact authority. One descriptor per actual
# input, one runtime allocation; no fixed slot ceiling or source-name dispatch.
.section .text
tensor_prepare_rank1_shape:
    push rbx; push r12; push r13
    mov r12,rdi
    lea rsi,[rip+k_bindings]; mov edx,k_bindings_end-k_bindings; call obj_get
    test rax,rax; jz .tprs_fail
    mov rdi,[rax+24]; test rdi,rdi; jz .tprs_fail
    lea rsi,[rip+k_axes]; mov edx,k_axes_end-k_axes; call obj_get
    test rax,rax; jz .tprs_fail
    mov rdi,[rax+24]; test rdi,rdi; jz .tprs_fail
    cmp qword ptr [rdi+32],0; jne .tprs_fail
    lea rsi,[rip+k_extent]; mov edx,k_extent_end-k_extent; call obj_get
    test rax,rax; jz .tprs_fail
    mov rdi,rax; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .tprs_fail
    mov rbx,[rax+8]; mov r13,[rax+16]
    mov [rip+tensor_shape_runtime_name_ptr],rbx
    mov [rip+tensor_shape_runtime_name_len],r13
    mov dword ptr [rip+tensor_shape_rank],1
    mov qword ptr [rip+tensor_shape_static_product],1
    mov qword ptr [rip+tensor_shape_extent_min],0
    mov qword ptr [rip+tensor_shape_extent_max],-1
    # Bounds are consumed by the one InputFact parser below. No parser copy.
    xor eax,eax; jmp .tprs_done
.tprs_fail:
    mov eax,1
.tprs_done:
    pop r13; pop r12; pop rbx; ret

tensor_prepare_input_facts:
    push rbx; push r12; push r13; push r14; push r15
    lea rsi,[rip+k_inputs]; mov edx,k_inputs_end-k_inputs; call obj_get
    test rax,rax; jz .tpif_fail
    cmp qword ptr [rax],J_ARRAY; jne .tpif_fail
    mov r12,[rax+24]; mov [rip+tensor_inputs_first],r12
    xor r13d,r13d
    mov rbx,r12
.tpif_count:
    test rbx,rbx; jz .tpif_allocate
    inc r13; mov rbx,[rbx+32]; jmp .tpif_count
.tpif_allocate:
    test r13,r13; jz .tpif_fail
    mov [rip+tensor_input_count],r13
    mov rsi,r13; shl rsi,5; jc .tpif_fail
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .tpif_fail
    mov [rip+tensor_input_descriptors],rax; mov r15,rax
    xor r14d,r14d
    mov qword ptr [rip+tensor_extent_input_index],-1
.tpif_loop:
    mov rdi,r12; lea rsi,[rip+k_type]; mov edx,k_type_end-k_type; call obj_get
    test rax,rax; jz .tpif_fail
    mov rbx,rax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+v_u64]; mov ecx,v_u64_end-v_u64; call span_eq
    mov ebx,TYPE_U64; test eax,eax; jnz .tpif_type_ready
    mov rdi,r12; lea rsi,[rip+k_type]; mov edx,k_type_end-k_type; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_f64]; mov ecx,v_f64_end-v_f64; call span_eq
    test eax,eax; jz .tpif_fail
    mov ebx,TYPE_F64
.tpif_type_ready:
    mov [r15],rbx
    mov rdi,r12; mov esi,3; cmp ebx,TYPE_F64; jne 1f
    mov esi,5
1:  lea rdx,[r15+8]; call physical_input_range_parse
    test eax,eax; jnz .tpif_fail
.tpif_identity:
    cmp ebx,TYPE_U64; jne .tpif_next
    mov rdi,r12; lea rsi,[rip+k_name]; mov edx,k_name_end-k_name; call obj_get
    test rax,rax; jz .tpif_fail
    mov rdi,[rax+8]; mov rsi,[rax+16]
    cmp dword ptr [rip+tensor_shape_active],0; je .tpif_rank1_name
    mov rdx,[rip+tensor_shape_runtime_name_ptr]; mov rcx,[rip+tensor_shape_runtime_name_len]
    call span_eq; jmp .tpif_match_ready
.tpif_rank1_name:
    call tensor_domain_var_match
.tpif_match_ready:
    test eax,eax; jz .tpif_next
    mov [rip+tensor_extent_input_index],r14
    cmp dword ptr [rip+tensor_shape_active],0; jne .tpif_next
    test qword ptr [r15+24],1; jz .tpif_extent_max
    mov rax,[r15+8]; mov [rip+tensor_shape_extent_min],rax
.tpif_extent_max:
    test qword ptr [r15+24],2; jz .tpif_next
    mov rax,[r15+16]; mov [rip+tensor_shape_extent_max],rax
.tpif_next:
    inc r14; add r15,32; mov r12,[r12+32]
    test r12,r12; jnz .tpif_loop
    cmp qword ptr [rip+tensor_extent_input_index],-1; je .tpif_fail
    xor eax,eax; jmp .tpif_done
.tpif_fail:
    mov eax,1
.tpif_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# name span -> eax=ordinal, edx=type; edx=0 for unresolved.
tensor_find_input:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi
    mov rbx,[rip+tensor_inputs_first]; xor r14d,r14d
.tfi_loop:
    test rbx,rbx; jz .tfi_no
    mov rdi,rbx; lea rsi,[rip+k_name]; mov edx,k_name_end-k_name; call obj_get
    test rax,rax; jz .tfi_no
    mov rdi,r12; mov rsi,r13; mov rdx,[rax+8]; mov rcx,[rax+16]; call span_eq
    test eax,eax; jnz .tfi_found
    inc r14; mov rbx,[rbx+32]; jmp .tfi_loop
.tfi_found:
    mov rax,r14; shl rax,5; add rax,[rip+tensor_input_descriptors]
    mov edx,[rax]; mov eax,r14d; jmp .tfi_done
.tfi_no:
    xor edx,edx; mov eax,-1
.tfi_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# A runtime AddressFact load through the sole input arena. RAX is emitter scratch.
tensor_emit_vec_input:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov rax,[rip+vec_emit_ptr]; add rax,40
    cmp rax,[rip+vec_emit_end]; jbe .tevi_space
    mov dword ptr [rip+tensor_code_overflow],1
    mov eax,1; pop r12; pop rbx; ret
.tevi_space:
    mov edi,0x48; call vec_emit_u8
    mov edi,0xA1; call vec_emit_u8
    mov rax,[rip+vec_emit_ptr]
    mov rcx,0x400000+RUNTIME_INPUT_VALUES_OFF
    mov [rax],rcx; add rax,8; mov [rip+vec_emit_ptr],rax
    mov edi,0x48; call vec_emit_u8
    mov edi,0x8B; call vec_emit_u8
    mov edi,0x80; call vec_emit_u8
    mov rax,[rip+vec_emit_ptr]; mov edx,r12d; shl edx,3
    mov [rax],edx; add rax,4; mov [rip+vec_emit_ptr],rax
.if TENSOR_PHYSICAL_LANES == 8
    mov edi,0x62; call vec_emit_u8
    mov eax,0xF2
    test ebx,8; jz 1f; and eax,0x7F
1:  test ebx,16; jz 2f; and eax,0xEF
2:  mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x7C; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call vec_emit_u8
.else
    # vmovq xmmD,rax then vpbroadcastq ymmD,xmmD (AVX2).
    mov edi,0x66; call vec_emit_u8
    mov eax,0x48; test ebx,8; jz 3f; or eax,4
3:  mov edi,eax; call vec_emit_u8
    mov edi,0x0F; call vec_emit_u8; mov edi,0x6E; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0; mov edi,eax; call vec_emit_u8
    mov edi,0xC4; call vec_emit_u8
    mov eax,0xE2; test ebx,8; jz 4f; and eax,0x7F
4:  mov edi,eax; call vec_emit_u8; mov edi,0x7D; call vec_emit_u8
    mov edi,0x59; call vec_emit_u8
    mov eax,ebx; and eax,7; mov ecx,eax; shl eax,3; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
.endif
    xor eax,eax; pop r12; pop rbx; ret

tensor_emit_scalar_input_int:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    xor edi,edi; mov rsi,0x400000+RUNTIME_INPUT_VALUES_OFF; call gen_mov_ri64
    mov edi,0x48; call emit_u8; mov edi,0x8B; call emit_u8; mov edi,0; call emit_u8
    mov eax,0x48; test ebx,8; jz 1f; or eax,4
1:  mov edi,eax; call emit_u8; mov edi,0x8B; call emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x80; mov edi,eax; call emit_u8
    mov rax,[rip+emit_ptr]; mov edx,r12d; shl edx,3; mov [rax],edx; add rax,4; mov [rip+emit_ptr],rax
    xor eax,eax; pop r12; pop rbx; ret

tensor_emit_scalar_input_float:
    push rbx
    mov ebx,edi; xor edi,edi; call tensor_emit_scalar_input_int
    mov edi,ebx; xor esi,esi; call gen_movq_xmm_gpr
    xor eax,eax; pop rbx; ret

# Image has descriptors after generated code. Their address is one cold patch.
tensor_write_input_facts:
    mov rax,RUNTIME_GENERATED_VA; add rax,r15
    mov [rip+tensor_input_table_va],rax
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+tensor_input_table_va]
    mov edx,8; mov r10d,RUNTIME_INPUT_TABLE_OFF; syscall
    cmp rax,8; jne .twif_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+tensor_input_count]
    mov edx,8; mov r10d,RUNTIME_INPUT_COUNT_OFF; syscall
    cmp rax,8; jne .twif_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+tensor_extent_input_index]
    mov edx,8; mov r10d,RUNTIME_EXTENT_INPUT_OFF; syscall
    cmp rax,8; jne .twif_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+tensor_ordered_reduction]
    mov edx,4; mov r10d,RUNTIME_REDUCTION_ORDERED_OFF; syscall
    cmp rax,4; jne .twif_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+tensor_input_descriptors]
    mov rdx,[rip+tensor_input_count]; shl rdx,5
    mov r10,RUNTIME_GENERATED_FILE_OFF; add r10,r15; syscall
    mov rdx,[rip+tensor_input_count]; shl rdx,5
    cmp rax,rdx; jne .twif_fail
    add r15,rdx
    xor eax,eax; ret
.twif_fail:
    mov eax,1; ret

# One operator-to-ISA relation for every FP physical consumer. Scalar and
# vector encodings already take an opcode parameter; no per-consumer matcher.
tensor_fp_binary_opcode:
    push rbx; push r12; push r13
    mov r12,rdi
    lea r13,[rip+tensor_fp_binary_table]
    xor ebx,ebx
.tfbop_next:
    cmp ebx,(tensor_fp_binary_table_end-tensor_fp_binary_table)/16
    jae .tfbop_missing
    mov rdi,[r12+8]; mov rsi,[r12+16]
    mov rdx,[r13]; mov ecx,[r13+8]
    call span_eq
    test eax,eax; jnz .tfbop_found
    add r13,16; inc ebx; jmp .tfbop_next
.tfbop_found:
    mov eax,[r13+12]
    jmp .tfbop_done
.tfbop_missing:
    xor eax,eax
.tfbop_done:
    pop r13; pop r12; pop rbx; ret

# ReductionFact owns source-order fold or the canonical leaf tree. The same
# VectorFact map feeds both; tree frontiers now live in the generated episode.
tensor_emit_reduce_bytes:
    cmp dword ptr [rip+tensor_ordered_reduction],0
    jne .terb_ordered
    call vec_emit_bytes
    test eax,eax; jnz .terb_done
    cmp dword ptr [rip+tensor_tolerant_fp],0
    jne .terb_done
    call tensor_tree_packet_factor
    cmp eax,1
    jbe .terb_leaf
    push rax
    lea rdi,[rip+tensor_tree_pending_increment]
    mov esi,tensor_tree_pending_increment_end-tensor_tree_pending_increment
    call vec_emit_bytes
    pop rdi
    test eax,eax; jnz .terb_done
    push rdi
    mov rdi,rsp
    mov esi,4
    call vec_emit_bytes
    add rsp,8
    test eax,eax; jnz .terb_done
    call vec_emit_je_placeholder
    test rax,rax; jz .terb_fail
    xor byte ptr [rax-1],1           # same conditional edge, inverted equality
    push rax
    lea rdi,[rip+tensor_tree_pending_clear]
    mov esi,tensor_tree_pending_clear_end-tensor_tree_pending_clear
    call vec_emit_bytes
    test eax,eax; jnz .terb_drop_fail
    call tensor_emit_tree_leaf
    test eax,eax; jnz .terb_drop_fail
    pop rdi
    mov rsi,[rip+vec_emit_ptr]
    jmp vec_patch_rel32
.terb_leaf:
    jmp tensor_emit_tree_leaf
.terb_ordered:
    lea rdi,[rip+tensor_ordered_packet]
    mov esi,tensor_ordered_packet_end-tensor_ordered_packet
    jmp vec_emit_bytes
.terb_drop_fail:
    add rsp,8
.terb_fail:
    mov eax,1
.terb_done:
    ret

tensor_tree_packet_factor:
    mov eax,1
    cmp dword ptr [rip+physical_plan_pass],0
    je .ttpf_done
    mov eax,dword ptr [rip+group_body_factor]
.ttpf_done:
    ret

tensor_emit_tree_leaf:
    lea rdi,[rip+tensor_tree_leaf]
    mov esi,tensor_tree_leaf_end-tensor_tree_leaf
    jmp vec_emit_bytes

tensor_emit_reduction_init:
    xor eax,eax
    cmp dword ptr [rip+tensor_ordered_reduction],0
    jne .teri_done
    cmp dword ptr [rip+tensor_tolerant_fp],0
    jne .teri_done
    lea rdi,[rip+tensor_tree_init]
    mov esi,tensor_tree_init_end-tensor_tree_init
    jmp vec_emit_bytes
.teri_done:
    ret

tensor_emit_finish_bytes:
    cmp dword ptr [rip+tensor_ordered_reduction],0
    jne .tefb_ordered
    cmp dword ptr [rip+tensor_tolerant_fp],0
    jne vec_emit_bytes
    call tensor_tree_packet_factor
    cmp eax,1
    jbe .tefb_frontier
    lea rdi,[rip+tensor_tree_pending_test]
    mov esi,tensor_tree_pending_test_end-tensor_tree_pending_test
    call vec_emit_bytes
    test eax,eax; jnz .tefb_done
    call vec_emit_je_placeholder
    test rax,rax; jz .tefb_fail
    push rax
    call tensor_emit_tree_leaf
    test eax,eax; jnz .tefb_drop_fail
    pop rdi
    mov rsi,[rip+vec_emit_ptr]
    call vec_patch_rel32
    test eax,eax; jnz .tefb_done
.tefb_frontier:
    lea rdi,[rip+tensor_tree_finish]
    mov esi,tensor_tree_finish_end-tensor_tree_finish
    jmp vec_emit_bytes
.tefb_ordered:
    lea rdi,[rip+tensor_ordered_finish]
    mov esi,tensor_ordered_finish_end-tensor_ordered_finish
    jmp vec_emit_bytes
.tefb_drop_fail:
    add rsp,8
.tefb_fail:
    mov eax,1
.tefb_done:
    ret

.section .rodata
tensor_fp_binary_table:
    .quad v_add; .long v_add_end-v_add,0x58
    .quad v_sub; .long v_sub_end-v_sub,0x5C
    .quad v_mul; .long v_mul_end-v_mul,0x59
    .quad v_div; .long v_div_end-v_div,0x5E
    .quad tensor_v_min; .long 3,0x5D
    .quad tensor_v_max; .long 3,0x5F
tensor_fp_binary_table_end:
tensor_v_min:.ascii "min"
tensor_v_max:.ascii "max"
tensor_v_neg:.ascii "neg"
tensor_v_abs:.ascii "abs"
# 64 frontier levels follow the u64 leaf-index domain. This is a worker-local
# ReductionFact carrier, not a materialized tensor or an execution queue.
tensor_tree_init:
    sub rsp,544
    mov qword ptr [rsp+512],0
    mov qword ptr [rsp+520],0
tensor_tree_init_end:
tensor_tree_pending_increment:
    inc qword ptr [rsp+520]
    .byte 0x48,0x81,0xbc,0x24
    .long 520                       # cmp qword [rsp+520], imm32
                                    # factor emitted by the common caller
 tensor_tree_pending_increment_end:
tensor_tree_pending_clear:
    mov qword ptr [rsp+520],0
tensor_tree_pending_clear_end:
tensor_tree_pending_test:
    cmp qword ptr [rsp+520],0
tensor_tree_pending_test_end:
tensor_tree_leaf:
    # Same canonical leaf horizontal tree as the prior finish, with disposable
    # map temporaries instead of clobbering invariant domain carriers XMM14/15.
    vextractf128 xmm0,ymm12,1
    vunpckhpd xmm3,xmm0,xmm0
    vaddsd xmm0,xmm0,xmm3
    vunpckhpd xmm3,xmm12,xmm12
    vaddsd xmm3,xmm12,xmm3
    vaddsd xmm0,xmm3,xmm0
    vxorpd ymm12,ymm12,ymm12
    mov rax,qword ptr [rsp+512]      # occupied frontier = consumed leaf count
    REDUCTION_FRONTIER_INSERT rax,xmm3
    mov qword ptr [rsp+512],rax
tensor_tree_leaf_end:
tensor_tree_finish:
    mov rax,qword ptr [rsp+512]
    REDUCTION_FRONTIER_FINISH rax,xmm3
    add rsp,544
    ret
tensor_tree_finish_end:
.section .rodata
tensor_ordered_packet:
    sub rsp,TENSOR_PHYSICAL_LANES*8
.if TENSOR_PHYSICAL_LANES == 8
    vmovupd zmmword ptr [rsp],zmm0
.else
    vmovupd ymmword ptr [rsp],ymm0
.endif
    mov ecx,TENSOR_PHYSICAL_LANES
    cmp r8,rcx
    cmovb rcx,r8
    xor eax,eax
1:  vaddsd xmm12,xmm12,qword ptr [rsp+rax*8]
    inc rax; cmp rax,rcx; jb 1b
    add rsp,TENSOR_PHYSICAL_LANES*8
tensor_ordered_packet_end:
tensor_ordered_finish:
    vmovapd xmm0,xmm12
    ret
tensor_ordered_finish_end:
.section .bss
.align 8
tensor_inputs_first:.skip 8
tensor_input_count:.skip 8
tensor_input_descriptors:.skip 8
tensor_extent_input_index:.skip 8
tensor_input_table_va:.skip 8
tensor_ordered_reduction:.skip 4
.section .text

# Scalar realization of the same u32 decomposition. Source is consumed; no
# per-value branch exists and RAX remains the established emitter scratch.
# edi=destination XMM, esi=unsigned GPR -> eax=0/1.
tensor_emit_u64_to_f64:
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12d,esi
    call alloc_xmm; cmp eax,-1; je .teuf_fail
    mov r13d,eax
    call alloc_xmm; cmp eax,-1; je .teuf_free_one
    mov r14d,eax
    cmp r12d,8; jb .teuf_low
    mov edi,0x41; call emit_u8
.teuf_low:
    mov edi,0x8b; call emit_u8
    mov edi,r12d; and edi,7; or edi,0xc0; call emit_u8
    mov edi,r13d; xor esi,esi; call gen_cvtsi2sd
    mov edi,r12d; shr edi,3; or edi,0x48; call emit_u8
    mov edi,0xc1; call emit_u8
    mov edi,r12d; and edi,7; or edi,0xe8; call emit_u8
    mov edi,32; call emit_u8
    mov edi,ebx; mov esi,r12d; call gen_cvtsi2sd
    mov edi,r14d; mov rsi,0x41f0000000000000; call gen_load_f64_bits
    mov edi,0x59; mov esi,ebx; mov edx,r14d; call gen_sse_rr
    mov edi,0x58; mov esi,ebx; mov edx,r13d; call gen_sse_rr
    mov edi,r14d; call free_xmm
    mov edi,r13d; call free_xmm
    xor eax,eax; jmp .teuf_done
.teuf_free_one:
    mov edi,r13d; call free_xmm
.teuf_fail:
    mov eax,1
.teuf_done:
    pop r14; pop r13; pop r12; pop rbx; ret
