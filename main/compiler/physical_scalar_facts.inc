# First unconditional demand owns a checked producer. This is compile-time
# generation-local availability, using the existing packet scope table.
.text
g_phys_cse_demand_resident:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    cmp dword ptr [rip+g_iter_reg_mode],1; jne .gpcdr_done
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpcdr_done
    cmp dword ptr [rip+g_packet_fact_scope],1; jne .gpcdr_done
    cmp r13d,GTYPE_U64; je .gpcdr_done
    cmp r13d,GTYPE_I64; je .gpcdr_done
    xor ebx,ebx
.gpcdr_scan:
    cmp ebx,[rip+g_phys_cse_ready_count]; jae .gpcdr_done
    mov rax,[rip+g_packet_fact_scope_ptr]; cmp dword ptr [rax+rbx*4],0; jne .gpcdr_next
    mov rax,[rip+g_phys_cse_resident_type_ptr]; cmp [rax+rbx*4],r13d; jne .gpcdr_next
    mov rax,[rip+g_phys_cse_resident_reg_ptr]; mov r14d,[rax+rbx*4]
    test r14d,r14d; js .gpcdr_next
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov rsi,[rax+rbx*8]; mov rdi,r12
    cmp r13d,GTYPE_BOOL; je .gpcdr_bool_equal
    call g_phys_expr_equal; jmp .gpcdr_equal
.gpcdr_bool_equal: call g_phys_predicate_equal
.gpcdr_equal:
    test eax,eax; jz .gpcdr_next
    mov rax,[rip+g_packet_fact_scope_ptr]; mov dword ptr [rax+rbx*4],-1
    cmp r13d,GTYPE_BOOL; je .gpcdr_bool
    mov rdi,r12; mov esi,r14d; mov edx,r13d; call g_emit_phys_fp_value_to
    cmp eax,r13d; jne .gpcdr_bad
    jmp .gpcdr_publish
.gpcdr_bool:
    mov rdi,r12; call g_emit_phys_bool_expr_to_rax
    test eax,eax; jnz .gpcdr_bad
    mov edi,r14d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpcdr_bad
.gpcdr_publish:
    mov rax,[rip+g_packet_fact_scope_ptr]; mov dword ptr [rax+rbx*4],1
    jmp .gpcdr_done
.gpcdr_bad:
    mov dword ptr [rip+g_code_overflow],1
    jmp .gpcdr_done
.gpcdr_next:
    inc ebx; jmp .gpcdr_scan
.gpcdr_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# The ordinary integer producer keeps its requested GPR. Retention transports
# only its exact bits into the common immutable scalar bank; no second evaluator.
g_phys_cse_retain_integer:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi; mov r15d,edx
    cmp dword ptr [rip+g_iter_reg_mode],1; jne .gpcri_done
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpcri_done
    cmp dword ptr [rip+g_packet_fact_scope],1; jne .gpcri_done
    xor ebx,ebx
.gpcri_scan:
    cmp ebx,[rip+g_phys_cse_ready_count]; jae .gpcri_done
    mov rax,[rip+g_packet_fact_scope_ptr]; cmp dword ptr [rax+rbx*4],0; jne .gpcri_next
    mov rax,[rip+g_phys_cse_resident_type_ptr]; cmp [rax+rbx*4],r13d; jne .gpcri_next
    mov rax,[rip+g_phys_cse_resident_reg_ptr]; mov r14d,[rax+rbx*4]
    test r14d,r14d; js .gpcri_next
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov rsi,[rax+rbx*8]; mov rdi,r12
    call g_phys_expr_equal; test eax,eax; jz .gpcri_next
    xor edi,edi; mov esi,r15d; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpcri_bad
    mov edi,r14d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpcri_bad
    mov rax,[rip+g_packet_fact_scope_ptr]; mov dword ptr [rax+rbx*4],1
    jmp .gpcri_done
.gpcri_bad:
    mov dword ptr [rip+g_code_overflow],1
    jmp .gpcri_done
.gpcri_next:
    inc ebx; jmp .gpcri_scan
.gpcri_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret
