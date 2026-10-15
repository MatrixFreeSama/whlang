# AOT completed mathematical ValueFacts consume the existing generation/carrier
# authority. The demand frontier is the unconsumed sibling graph, not a runtime
# cache. A fact is born only at its ordinary producer and dies at last demand.
.macro TCC_functions
emit_vec_float:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi
    sub rsp,40
    mov rax,[rip+tensor_math_projection_request]; mov [rsp],rax
    mov qword ptr [rip+tensor_math_projection_request],0
    mov [rsp+8],r12
    mov qword ptr [rsp+16],0; mov dword ptr [rsp+24],-1
    mov eax,[rip+tensor_completed_guard_depth]; mov [rsp+32],eax
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz 1f
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz 1f
    inc dword ptr [rip+tensor_completed_guard_depth]
1:
    mov rdi,r12; call tensor_completed_admit
    test eax,eax; jz .tcc_direct
    mov rdi,r12; call tensor_completed_lookup
    cmp eax,-1; je .tcc_direct
    mov r14d,eax
    mov rcx,[rip+vec_cache_reg_ptr]; mov esi,[rcx+rax*4]
    mov edi,r13d; call vec_mov_ext
    test eax,eax; jnz .tcc_done
    mov rdi,r12; call tensor_completed_future
    test rax,rax; jnz .tcc_ok
    mov rcx,[rip+vec_cache_reg_ptr]; mov edi,[rcx+r14*4]
    mov dword ptr [rcx+r14*4],-1
    call vec_cache_reg_free
    jmp .tcc_ok
.tcc_direct:
    mov rdi,r12; call tensor_completed_prepare_projection
    test rax,rax; jz 1f
    mov [rsp+16],rax; mov [rsp+24],ecx; mov [rsp+28],edx
    mov [rip+tensor_math_projection_request],rsp
1:  mov rdi,r12; mov esi,r13d; call emit_vec_float_body
    test eax,eax; jnz .tcc_done
    mov rdi,[rsp+16]; test rdi,rdi; jz 1f
    mov esi,[rsp+24]; call tensor_completed_add
    test eax,eax; jnz 1f
    mov dword ptr [rsp+24],-1
1:  mov rdi,r12; call tensor_completed_admit
    test eax,eax; jz .tcc_ok
    mov rdi,r12; call tensor_completed_future
    test rax,rax; jz .tcc_ok
    call vec_cache_reg_alloc
    cmp eax,-1; je .tcc_ok
    mov r14d,eax
    mov edi,eax; mov esi,r13d; call vec_mov_ext
    test eax,eax; jnz .tcc_release_fail
    mov rdi,r12; mov esi,r14d; call tensor_completed_add
    test eax,eax; jz .tcc_ok
    mov edi,r14d; call vec_cache_reg_free
    jmp .tcc_ok
.tcc_release_fail:
    push rax; mov edi,r14d; call vec_cache_reg_free; pop rax
    jmp .tcc_done
.tcc_ok: xor eax,eax
.tcc_done:
    push rax
    mov edi,[rsp+32]; test edi,edi; js 1f
    call vec_cache_reg_free
1:  pop rax
    mov rcx,[rsp]; mov [rip+tensor_math_projection_request],rcx
    mov ecx,[rsp+32]; mov [rip+tensor_completed_guard_depth],ecx
    add rsp,40
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Already admitted natural-f64 primitive capabilities define this consumer.
# No function/workload whitelist distinct from the shared physical authority.
tensor_completed_admit:
    push rbx; push r12
    mov rbx,rdi
    cmp dword ptr [rip+tensor_completed_guard_depth],0; jne .tcca_no
    mov rdi,rbx; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .tcca_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov edx,64; call physical_math_fragment
    test rax,rax; jz .tcca_no
    mov r12d,edx
    mov rdi,rbx; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .tcca_no
    mov rax,[rax+24]; test rax,rax; jz .tcca_no
    cmp qword ptr [rax+32],0; jne .tcca_no
    mov edx,r12d; mov eax,1; pop r12; pop rbx; ret
.tcca_no: xor eax,eax; pop r12; pop rbx; ret

tensor_completed_lookup:
    push rbx; push r12; push r13
    mov r12,rdi; mov ebx,[rip+vec_cache_count]
.tccl_next:
    test ebx,ebx; jz .tccl_no
    dec ebx
    mov rcx,[rip+vec_cache_gen_ptr]; mov eax,[rip+vec_current_gen]
    cmp [rcx+rbx*4],eax; jne .tccl_next
    mov rcx,[rip+vec_cache_kind_ptr]; cmp dword ptr [rcx+rbx*4],3; jne .tccl_next
    mov rcx,[rip+vec_cache_reg_ptr]; cmp dword ptr [rcx+rbx*4],0; jl .tccl_next
    mov rcx,[rip+vec_cache_binding_ptr]; mov rsi,[rcx+rbx*8]
    mov rdi,r12; xor edx,edx; call physical_value_expr_equal
    test eax,eax; jz .tccl_next
    mov eax,ebx; jmp .tccl_done
.tccl_no: mov eax,-1
.tccl_done: pop r13; pop r12; pop rbx; ret

# Reuse dead slots in this same generation; other lifetime domains are owned.
tensor_completed_add:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13d,esi; mov ebx,[rip+vec_cache_count]
.tcca_slot:
    test ebx,ebx; jz .tcca_append
    dec ebx
    mov rcx,[rip+vec_cache_gen_ptr]; mov eax,[rip+vec_current_gen]
    cmp [rcx+rbx*4],eax; jne .tcca_slot
    mov rcx,[rip+vec_cache_kind_ptr]; cmp dword ptr [rcx+rbx*4],3; jne .tcca_slot
    mov rcx,[rip+vec_cache_reg_ptr]; cmp dword ptr [rcx+rbx*4],-1; jne .tcca_slot
    jmp .tcca_write
.tcca_append:
    mov ebx,[rip+vec_cache_count]
    cmp ebx,[rip+tensor_optimizer_capacity]; jae .tcca_full
    inc dword ptr [rip+vec_cache_count]
.tcca_write:
    mov rcx,[rip+vec_cache_binding_ptr]; mov [rcx+rbx*8],r12
    mov rcx,[rip+vec_cache_gen_ptr]; mov eax,[rip+vec_current_gen]; mov [rcx+rbx*4],eax
    mov rcx,[rip+vec_cache_reg_ptr]; mov [rcx+rbx*4],r13d
    mov rcx,[rip+vec_cache_kind_ptr]; mov dword ptr [rcx+rbx*4],3
    xor eax,eax; jmp .tcca_done
.tcca_full: mov eax,1
.tcca_done: pop r13; pop r12; pop rbx; ret

# rdi=completed expression -> first identical future consumer, or zero.
tensor_completed_future:
    xor edx,edx
    jmp tensor_completed_demand
tensor_completed_projection_future:
    mov edx,1
tensor_completed_demand:
    push rbx; push r12; push r13
    mov r13d,edx
    mov r12,rdi; mov rbx,[rip+tensor_pending_demand]
.tccf_next:
    test rbx,rbx; jz .tccf_no
    mov eax,[rip+vec_current_gen]; cmp eax,[rbx+16]; jne .tccf_advance
    mov rdi,[rbx+8]; mov rsi,r12; mov edx,r13d; call tensor_completed_find
    test rax,rax; jnz .tccf_done
.tccf_advance: mov rbx,[rbx]; jmp .tccf_next
.tccf_no: xor eax,eax
.tccf_done: pop r13; pop r12; pop rbx; ret

# Search only the unconditionally demanded graph in the same Axis generation.
# Select is a control/Effect boundary; an indexed load is a coordinate boundary.
tensor_completed_find:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    mov rdi,r12; mov rsi,r13; call tensor_completed_match
    test eax,eax; jnz .tccfind_yes
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .tccfind_load
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jnz .tccfind_no
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .tccfind_no
    mov rbx,[rax+24]
.tccfind_args:
    test rbx,rbx; jz .tccfind_no
    mov rdi,rbx; mov rsi,r13; mov edx,r14d; call tensor_completed_find
    test rax,rax; jnz .tccfind_done
    mov rbx,[rbx+32]; jmp .tccfind_args
.tccfind_load:
    mov rdi,r12; lea rsi,[rip+k_load]; mov edx,k_load_end-k_load; call obj_get
    test rax,rax; jz .tccfind_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call find_binding
    test rax,rax; jz .tccfind_no
    mov rbx,rax; cmp dword ptr [rbx+16],OP_MAP; jne .tccfind_no
    mov rdi,r12; lea rsi,[rip+k_indices]; mov edx,k_indices_end-k_indices; call obj_get
    test rax,rax; jz .tccfind_no
    mov rdi,[rax+24]; test rdi,rdi; jz .tccfind_no
    cmp qword ptr [rdi+32],0; jne .tccfind_no
    lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .tccfind_no
    mov rdi,[rbx+40]; mov rsi,r13; mov edx,r14d; call tensor_completed_find
    jmp .tccfind_done
.tccfind_yes: mov rax,r12; jmp .tccfind_done
.tccfind_no: xor eax,eax
.tccfind_done: pop r14; pop r13; pop r12; pop rbx; ret
# A typed relation lookup, independent of any frontend/workload names.
tensor_completed_match:
    test edx,edx; jnz .tccm_projection
    xor edx,edx; jmp physical_value_expr_equal
.tccm_projection:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13,rsi
    call tensor_completed_admit
    test eax,eax; jz .tccm_no
    mov edi,edx; call physical_math_projection_peer
    cmp eax,-1; je .tccm_no
    mov ebx,eax
    mov rdi,r13; call tensor_completed_admit
    test eax,eax; jz .tccm_no
    cmp edx,ebx; jne .tccm_no
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    mov r12,[rax+24]
    mov rdi,r13; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    mov rsi,[rax+24]; mov rdi,r12; xor edx,edx; call physical_value_expr_equal
    jmp .tccm_done
.tccm_no: xor eax,eax
.tccm_done: pop r13; pop r12; pop rbx; ret

# Returns companion expression, its real carrier, and first projection ordinal.
tensor_completed_prepare_projection:
    push rbx; push r12; push r13
    mov r12,rdi
    call tensor_completed_admit
    test eax,eax; jz .tccp_no
    mov r13d,edx
    mov edi,edx; mov esi,64; mov edx,TENSOR_PHYSICAL_LANES
    call physical_math_packet_dual_fragment_by_id
    test rax,rax; jz .tccp_no
    mov rdi,r12; call tensor_completed_projection_future
    test rax,rax; jz .tccp_no
    mov rbx,rax
    mov rdi,rax; call tensor_completed_lookup
    cmp eax,-1; jne .tccp_no
    call vec_cache_reg_alloc
    cmp eax,-1; je .tccp_no
    mov ecx,eax; mov edx,r13d; mov rax,rbx; jmp .tccp_done
.tccp_no: xor eax,eax
.tccp_done: pop r13; pop r12; pop rbx; ret

tensor_completed_snapshot:
    xor edx,edx
    mov r8,[rip+tensor_completed_snapshot_ptr]
.tccs_loop:
    cmp edx,[rip+vec_cache_count]; jae .tccs_done
    mov rcx,[rip+vec_cache_binding_ptr]; mov rax,[rcx+rdx*8]; mov [r8],rax
    mov rcx,[rip+vec_cache_gen_ptr]; mov eax,[rcx+rdx*4]; mov [r8+8],eax
    mov rcx,[rip+vec_cache_kind_ptr]; mov eax,[rcx+rdx*4]; mov [r8+12],eax
    mov rcx,[rip+vec_cache_reg_ptr]; mov eax,[rcx+rdx*4]; mov [r8+16],eax
    add r8,24; inc edx; jmp .tccs_loop
.tccs_done: ret

tensor_completed_rollback:
    xor edx,edx
    mov r8,[rip+tensor_completed_snapshot_ptr]
.tccr_loop:
    cmp edx,[rip+vec_cache_count]; jae .tccr_done
    mov rcx,[rip+vec_cache_binding_ptr]; mov rax,[r8]; mov [rcx+rdx*8],rax
    mov rcx,[rip+vec_cache_gen_ptr]; mov eax,[r8+8]; mov [rcx+rdx*4],eax
    mov rcx,[rip+vec_cache_kind_ptr]; mov eax,[r8+12]; mov [rcx+rdx*4],eax
    mov rcx,[rip+vec_cache_reg_ptr]; mov eax,[r8+16]; mov [rcx+rdx*4],eax
    add r8,24; inc edx; jmp .tccr_loop
.tccr_done: ret
.endm

.macro TCC_pending_lhs
    sub rsp,24
    mov rax,[rip+tensor_pending_demand]; mov [rsp],rax
    mov [rsp+8],r14
    mov eax,[rip+vec_current_gen]; mov [rsp+16],eax
    mov [rip+tensor_pending_demand],rsp
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    mov rcx,[rsp]; mov [rip+tensor_pending_demand],rcx
    add rsp,24
.endm

.pushsection .bss
.p2align 3
tensor_math_projection_request:.skip 8
tensor_pending_demand:.skip 8
tensor_completed_snapshot_ptr:.skip 8
tensor_completed_guard_depth:.skip 4
.popsection
