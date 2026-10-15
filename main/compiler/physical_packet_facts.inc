# Compile-time dominance stamps; no runtime cache lookup or validity branch.
g_packet_fact_scope_leave:
    mov rdx,[rip+g_packet_fact_scope_ptr]; xor ecx,ecx
    mov eax,[rip+g_packet_fact_scope]
1:  cmp ecx,[rip+g_phys_cse_resident_count]; jae 3f
    cmp [rdx+rcx*4],eax; jb 2f
    mov dword ptr [rdx+rcx*4],0
2:  inc ecx; jmp 1b
3:  dec dword ptr [rip+g_packet_fact_scope]; ret

g_packet_fact_retain:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13d,esi; xor ebx,ebx
1:  cmp ebx,[rip+g_phys_cse_resident_count]; jae 4f
    mov rax,[rip+g_packet_fact_scope_ptr]; cmp dword ptr [rax+rbx*4],0; jne 3f
    mov rax,[rip+g_phys_cse_resident_type_ptr]; cmp [rax+rbx*4],r13d; jne 3f
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov rsi,[rax+rbx*8]
    mov rdi,r12; call g_phys_expr_equal; test eax,eax; jz 3f
    xor edi,edi; mov esi,r13d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov rax,[rip+g_phys_cse_resident_reg_ptr]; mov edx,[rax+rbx*4]
    imul edx,[rip+group_lane_factor]; shl edx,3
    mov dword ptr [rip+g_packet_slot_memory_base],1
    xor edi,edi; mov esi,r13d; mov ecx,1; call g_emit_packet_simd_slot
    mov dword ptr [rip+g_packet_slot_memory_base],0
    mov rax,[rip+g_packet_fact_scope_ptr]; mov ecx,[rip+g_packet_fact_scope]; mov [rax+rbx*4],ecx
    jmp 4f
3:  inc ebx; jmp 1b
4:  pop r13; pop r12; pop rbx; ret

# Descriptor geometry is a property of natural precision and the carrier.
g_packet_register_geometry:
    cmp esi,GTYPE_F64; jne 1f
    or edi,0x400
1:  or edi,0x2000
    cmp esi,GTYPE_F32; jne 2f
    cmp dword ptr [rip+group_lane_factor],4; jne 2f
    and edi,~0x2000
2:  cmp esi,GTYPE_F64; jne 3f
    cmp dword ptr [rip+group_lane_factor],8; jne 3f
    and edi,~0x2000; or edi,0xd000
3:  ret

# rdi=expr, esi=destination, edx=type, r8d=require direct arithmetic consumer.
# eax=result type, r8d=one owned packet stack slot (zero for register-only).
# Ownership follows completed causal edges. A consumer reuses that slot; when
# both operands own slots, it releases only the newer slot after consumption.
# The same strict arithmetic DAG borrows
# registers and releases operands only at final consumption. Leaves consume
# existing shared mathematical fragments and natural precision edges.
g_packet_register_expr:
    push rbx; push r12; push r13; push r14; push r15; sub rsp,40
    mov r12,rdi; mov r13d,esi; mov r14d,edx
    mov [rsp+12],r8d
    mov dword ptr [rsp+24],0; mov dword ptr [rsp+32],0
    mov rdi,r12; call g_infer_expr; cmp eax,r14d; jne .gpre_bad
    mov rdi,r12; mov esi,r14d; call g_phys_cse_find_resident
    cmp eax,0; jge .gpre_resident
    mov rdi,r12; lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gpre_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol; test rax,rax; jz .gpre_bad
    mov rdi,[rax+32]; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    mov rdi,rax; mov esi,r13d; mov edx,r14d; mov r8d,[rsp+12]
    call g_packet_register_expr; mov [rsp+24],r8d; jmp .gpre_done
.gpre_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpre_leaf
    mov r15,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpre_leaf
    mov rbx,[rax+24]; test rbx,rbx; jz .gpre_leaf
    mov rax,[rbx+32]; mov [rsp],rax
    test rax,rax; jz .gpre_leaf
    cmp qword ptr [rax+32],0; jne .gpre_leaf
    mov rdi,rbx; call g_infer_expr; cmp eax,r14d; jne .gpre_leaf
    mov rdi,[rsp]; call g_infer_expr; cmp eax,r14d; jne .gpre_leaf
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_add]; mov ecx,3; call span_eq
    test eax,eax; jz 1f
    mov dword ptr [rsp+8],0x158; jmp .gpre_binary
1:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sub]; mov ecx,3; call span_eq
    test eax,eax; jz 2f
    mov dword ptr [rsp+8],0x15c; jmp .gpre_binary
2:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mul]; mov ecx,3; call span_eq
    test eax,eax; jz 3f
    mov dword ptr [rsp+8],0x159; jmp .gpre_binary
3:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_div]; mov ecx,3; call span_eq
    test eax,eax; jz .gpre_leaf
    mov dword ptr [rsp+8],0x15e
.gpre_binary:
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; xor r8d,r8d; call g_packet_register_expr
    test eax,eax; jz .gpre_bad
    mov [rsp+24],r8d
    bts dword ptr [rip+g_packet_register_live],r13d
    # Two equal causal edges consume the SAME completed register authority.
    # No second evaluation, frame reload or extra carrier is necessary.
    mov rdi,rbx; mov rsi,[rsp]; call g_phys_expr_equal
    test eax,eax; jz .gpre_distinct
    mov r15d,r13d; jmp .gpre_emit_binary
.gpre_distinct:
    mov eax,[rip+g_packet_register_mask]; test eax,eax; jz .gpre_bad
    bsf r15d,eax; btr dword ptr [rip+g_packet_register_mask],r15d
    mov rdi,[rsp]; mov esi,r15d; mov edx,r14d; xor r8d,r8d; call g_packet_register_expr
    bts dword ptr [rip+g_packet_register_mask],r15d
    test eax,eax; jz .gpre_bad
    mov [rsp+32],r8d
.gpre_emit_binary:
    mov edi,[rsp+8]; mov esi,r14d; call g_packet_register_geometry
    mov esi,r13d; mov edx,r13d; mov ecx,r15d; call physical_encode_rrr
    test edx,edx; jz .gpre_bad
    mov [rsp+16],rax; lea rdi,[rsp+16]; mov esi,edx; call g_emit_bytes
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,[rsp+24]; and eax,[rsp+32]; test eax,eax; jz 994f
    mov edi,[rip+group_lane_factor]; shl edi,3; mov esi,1; call g_emit_packet_stack_adjust
994: mov eax,[rsp+32]; or [rsp+24],eax
    mov eax,r14d; jmp .gpre_done
.gpre_resident:
    # A completed dominating ValueFact already owns its payload. Consume that
    # frame slot directly, without rebroadcast or a temporary stack result.
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov edx,[rcx+rax*4]
    imul edx,[rip+group_lane_factor]; shl edx,3
    mov dword ptr [rip+g_packet_slot_memory_base],1
    mov edi,r13d; mov esi,r14d; xor ecx,ecx; call g_emit_packet_simd_slot
    mov dword ptr [rip+g_packet_slot_memory_base],0
    mov eax,r14d; jmp .gpre_done
.gpre_leaf:
    # A stack producer is an operand, not a direct register consumer. Reject
    # it at the root before recursively emitting and rewinding its whole DAG.
    cmp dword ptr [rsp+12],0; jne .gpre_bad
    # Immutable literal and invocation input are direct broadcast operands.
    mov rdi,r12; mov esi,r14d; call g_phys_fp_literal_bits
    test eax,eax; jz .gpre_input
    mov rdi,rdx; call g_emit_mov_rax_imm64
    mov edi,r14d; mov esi,r13d; call g_emit_packet_broadcast_to
    mov eax,r14d; jmp .gpre_done
.gpre_input:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpre_stack_leaf
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gpre_bad
    cmp dword ptr [rax+16],GK_INPUT; jne .gpre_stack_leaf
    mov eax,[rax+24]; call g_input_slot_addr
    mov rdi,rax; call g_emit_load_rax_abs
    mov edi,r14d; mov esi,r13d; call g_emit_packet_broadcast_to
    mov eax,r14d; jmp .gpre_done
.gpre_stack_leaf:
    mov rax,[rip+g_packet_register_skip_expr]; mov [rsp+16],rax
    mov [rip+g_packet_register_skip_expr],r12
    mov rdi,r12; call g_emit_packet_expr
    mov rdx,[rsp+16]; mov [rip+g_packet_register_skip_expr],rdx
    cmp eax,r14d; jne .gpre_bad
    mov edi,r13d; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov dword ptr [rsp+24],1
    mov eax,r14d; jmp .gpre_done
.gpre_bad: xor eax,eax
.gpre_done:
    btr dword ptr [rip+g_packet_register_live],r13d
    test eax,eax; jz 993f
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je 993f
    mov rdi,r12; mov esi,r14d; mov edx,r13d; call g_packet_register_retain
    mov eax,r14d
993: xor r8d,r8d; test eax,eax; jz 995f
    mov r8d,[rsp+24]
995: add rsp,40; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

g_packet_register_root:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    mov rdi,r12; call g_infer_expr; mov r14d,eax
    mov r13,[rip+g_emit_ptr]; mov r15d,[rip+g_packet_native_nodes]
    mov ebx,[rip+g_phys_cse_resident_count]; lea rax,[rbx*8+31]; and rax,-16
    sub rsp,rax; push rax
    lea rdi,[rsp+8]; mov rsi,[rip+g_packet_fact_scope_ptr]; mov ecx,ebx; rep movsd
    mov rsi,[rip+g_packet_fact_mixed_ptr]; mov ecx,ebx; rep movsd
    mov rax,[rip+g_packet_mixed_head]; mov [rdi],rax
    mov eax,[rip+g_packet_mixed_seen]; mov [rdi+8],eax
    mov eax,[rip+g_packet_register_mask]; test eax,eax; jz .gprr_bad
    bsf ebx,eax; btr dword ptr [rip+g_packet_register_mask],ebx
    mov rdi,r12; mov esi,ebx; mov edx,r14d; mov r8d,1; call g_packet_register_expr
    bts dword ptr [rip+g_packet_register_mask],ebx
    test eax,eax; jz .gprr_bad
    test r8d,r8d; jnz .gprr_store
    mov edi,[rip+group_lane_factor]; shl edi,3; xor esi,esi; call g_emit_packet_stack_adjust
.gprr_store:
    mov edi,ebx; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    mov eax,r14d; jmp .gprr_finish
.gprr_bad:
    lea rsi,[rsp+8]; mov rdi,[rip+g_packet_fact_scope_ptr]
    mov ecx,[rip+g_phys_cse_resident_count]; rep movsd
    mov rdi,[rip+g_packet_fact_mixed_ptr]
    mov ecx,[rip+g_phys_cse_resident_count]; rep movsd
    mov rax,[rsi]; mov [rip+g_packet_mixed_head],rax
    mov eax,[rsi+8]; mov [rip+g_packet_mixed_seen],eax
    mov [rip+g_emit_ptr],r13; mov [rip+g_packet_native_nodes],r15d
    mov qword ptr [rip+g_packet_last_store_end],0
    xor eax,eax
.gprr_finish:
    pop rcx; add rsp,rcx
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

.pushsection .bss
.p2align 2
g_packet_fact_scope:.skip 4
g_packet_register_skip_expr:.skip 8
g_packet_register_mask:.skip 4
g_packet_register_live:.skip 4

.popsection

.text
# A register producer can hand its exact completed value to the same selected
# demand fact without an intermediate packet stack result.
g_packet_register_retain:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi; mov r14d,edx; xor ebx,ebx
1:  cmp ebx,[rip+g_phys_cse_resident_count]; jae 4f
    mov rax,[rip+g_packet_fact_scope_ptr]; cmp dword ptr [rax+rbx*4],0; jne 3f
    mov rax,[rip+g_phys_cse_resident_type_ptr]; cmp [rax+rbx*4],r13d; jne 3f
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov rsi,[rax+rbx*8]
    mov rdi,r12; call g_phys_expr_equal; test eax,eax; jz 3f
    mov rax,[rip+g_phys_cse_resident_reg_ptr]; mov edx,[rax+rbx*4]
    imul edx,[rip+group_lane_factor]; shl edx,3
    mov dword ptr [rip+g_packet_slot_memory_base],1
    mov edi,r14d; mov esi,r13d; mov ecx,1; call g_emit_packet_simd_slot
    mov dword ptr [rip+g_packet_slot_memory_base],0
    mov rax,[rip+g_packet_fact_scope_ptr]; mov ecx,[rip+g_packet_fact_scope]; mov [rax+rbx*4],ecx
    jmp 4f
3:  inc ebx; jmp 1b
4:  pop r14; pop r13; pop r12; pop rbx; ret

.text
# rdi=root, rsi=target -> eax=1 only along unconditional causal edges.
g_phys_fact_dominates:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi
    mov rdi,r13; call g_infer_expr
    cmp eax,GTYPE_BOOL; jne .gpfd_numeric
    mov rdi,r12; mov rsi,r13; call g_phys_predicate_equal
    jmp .gpfd_identity
.gpfd_numeric:
    mov rdi,r12; mov rsi,r13; call g_phys_expr_equal
.gpfd_identity:
    test eax,eax; jnz .gpfd_done
    mov rdi,r12; lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gpfd_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol; test rax,rax; jz .gpfd_no
    mov rdi,[rax+32]; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    mov rdi,rax; mov rsi,r13; call g_phys_fact_dominates; jmp .gpfd_done
.gpfd_op:
    xor ebx,ebx
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpfd_no
    mov r14,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_select]; mov ecx,6; call span_eq; or ebx,eax
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_and]; mov ecx,3; call span_eq; or ebx,eax
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_or]; mov ecx,2; call span_eq; or ebx,eax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfd_no
    mov r14,[rax+24]
.gpfd_child:
    test r14,r14; jz .gpfd_no
    mov rdi,r14; mov rsi,r13; call g_phys_fact_dominates
    test eax,eax; jnz .gpfd_done
    test ebx,ebx; jnz .gpfd_no
    mov r14,[r14+32]; jmp .gpfd_child
.gpfd_no: xor eax,eax
.gpfd_done: pop r14; pop r13; pop r12; pop rbx; ret

# One immutable/total/dominating lifetime proof for planning and realization.
# rdi=episode root, rsi=ValueFact -> eax=1 iff safe invocation preheader.
g_phys_fact_is_invariant:
    push r12; push r13
    mov r12,rdi; mov r13,rsi
    mov rdi,r13; call g_semantic_expr_is_pure; test eax,eax; jz .gpfi_ret
    mov rdi,r13; call g_semantic_expr_is_total; test eax,eax; jz .gpfi_ret
    mov rdi,r12; mov rsi,r13; call g_phys_fact_dominates
.gpfi_ret:
    pop r13; pop r12; ret

# Invocation inputs and repeated invariant arithmetic stay still across all
# Axis packets. An arm-local invariant cannot be speculated out of its guard.
g_packet_emit_invariants:
    push rbx; push r12; push r13; push r14
    lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    mov rdi,rax
    jmp .gpeir_body
g_packet_emit_invariant_root:
    push rbx; push r12; push r13; push r14
.gpeir_body:
    mov r12,rdi; xor ebx,ebx
1:  cmp ebx,[rip+g_phys_cse_resident_count]; jae 3f
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov r13,[rax+rbx*8]
    mov rdi,r12; mov rsi,r13; call g_phys_fact_is_invariant; test eax,eax; jz 2f
    mov rax,[rip+g_phys_cse_resident_type_ptr]; mov r14d,[rax+rbx*4]
    mov rdi,r13; call g_emit_packet_expr; cmp eax,r14d; jne 2f
    mov edi,[rip+group_lane_factor]; shl edi,3; mov esi,1; call g_emit_packet_stack_adjust
2:  inc ebx; jmp 1b
3:  pop r14; pop r13; pop r12; pop rbx; ret

# edi=register, esi=disp32, edx=store. Whole opaque packet payload transport.
# Memory addressing goes through the same target geometry; no typed arithmetic.
g_packet_math_slot:
    sub rsp,16
    mov ecx,edx; mov edx,esi
    mov esi,[rip+group_lane_factor]; shl esi,3
    mov r8,rsp; call physical_encode_simd_rsp
    mov rdi,rsp; mov esi,eax; call g_emit_bytes
    add rsp,16; ret

# edi=0 before / 1 after, esi=fragment clobber mask. Only actual live owners
# cross this boundary. A dead scratch bank creates zero spill/load instructions.
g_packet_math_preserve:
    push rbx; push r12; push r13; push r14
    mov r14d,edi; mov r12d,esi; and r12d,[rip+g_packet_register_live]
    test r12d,r12d; jz .gpmp_done
    mov eax,r12d; xor ebx,ebx
1:  lea ecx,[rax-1]; and eax,ecx; inc ebx; test eax,eax; jnz 1b
    inc ebx; imul ebx,[rip+group_lane_factor]; shl ebx,3
    test r14d,r14d; jnz .gpmp_restore
    mov edi,ebx; xor esi,esi; call g_emit_packet_stack_adjust
    xor edi,edi; mov esi,ebx; xor edx,edx; call g_packet_math_slot
    xor edi,edi; xor esi,esi; mov edx,1; call g_packet_math_slot
.gpmp_restore:
    mov r13d,[rip+group_lane_factor]; shl r13d,3
.gpmp_register:
    bsf eax,r12d; btr r12d,eax
    mov edi,eax; mov esi,r13d; mov edx,1; sub edx,r14d; call g_packet_math_slot
    mov eax,[rip+group_lane_factor]; shl eax,3; add r13d,eax
    test r12d,r12d; jnz .gpmp_register
    test r14d,r14d; jz .gpmp_done
    xor edi,edi; xor esi,esi; xor edx,edx; call g_packet_math_slot
    xor edi,edi; mov esi,ebx; mov edx,1; call g_packet_math_slot
    mov edi,ebx; mov esi,1; call g_emit_packet_stack_adjust
.gpmp_done:
    mov qword ptr [rip+g_packet_last_store_end],0
    pop r14; pop r13; pop r12; pop rbx; ret

# Textbook dominance meet at every mixed-control predecessor. The continuation
# may consume only facts already completed on ALL of its incoming paths.
g_packet_fact_mixed_meet:
    cmp dword ptr [rip+g_packet_mixed_enabled],0; je 4f
    mov rdi,[rip+g_packet_fact_scope_ptr]; mov rsi,[rip+g_packet_fact_mixed_ptr]
    xor ecx,ecx
1:  cmp ecx,[rip+g_phys_cse_resident_count]; jae 3f
    xor eax,eax; cmp dword ptr [rdi+rcx*4],0; setne al
    cmp dword ptr [rip+g_packet_mixed_seen],0; je 2f
    and eax,[rsi+rcx*4]
2:  mov [rsi+rcx*4],eax; inc ecx; jmp 1b
3:  mov dword ptr [rip+g_packet_mixed_seen],1
4:  ret
.pushsection .bss
.p2align 2
g_packet_mixed_seen:.skip 4
.popsection
