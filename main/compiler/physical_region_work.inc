# Invocation-stable iteration work projects existing immutable ValueFacts.
# No expression is evaluated early: only a proved u64 literal/input carrier may
# be read by the invocation closure. Unknown expressions remain unknown. The
# Existing work_ticks own one-shot work; this projection owns the iterative
# term. One price serves ownership and outward lifecycle, never correctness.
.text
g_fragment_work_fact:
    push rbx; push r12; push r13
    mov ebx,[rip+g_fragment_count]
    mov rax,[rip+g_fragment_work_source_ptr]; mov qword ptr [rax+rbx*8],0
    mov rax,[rip+g_fragment_work_kind_ptr]; mov qword ptr [rax+rbx*8],0
    mov rax,[rip+g_fragment_kind_ptr]; cmp dword ptr [rax+rbx*4],1; jne .gfwork_done
    mov rax,[rip+g_fragment_nodes_ptr]; mov r12,[rax+rbx*8]
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gfwork_done
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_classify_binding_op
    cmp eax,GK_ITERATE; jne .gfwork_done
    mov rdi,r12; lea rsi,[rip+gk_max_iterations]; mov edx,gk_max_iterations_end-gk_max_iterations; call obj_get
    test rax,rax; jz .gfwork_done
    mov r13,rax; mov rdi,rax; call g_expr_u64_literal
    test edx,edx; jnz .gfwork_input
    mov ecx,1; jmp .gfwork_publish
.gfwork_input:
    mov rdi,r13; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gfwork_done
    cmp qword ptr [rax],J_STRING; jne .gfwork_done
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gfwork_done
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gfwork_done
    cmp dword ptr [rax+16],GK_INPUT; jne .gfwork_done
    cmp dword ptr [rax+20],GTYPE_U64; jne .gfwork_done
    mov eax,[rax+24]; call g_input_slot_addr
    mov ecx,2
.gfwork_publish:
    mov rdx,[rip+g_fragment_work_source_ptr]; mov [rdx+rbx*8],rax
    mov rdx,[rip+g_fragment_work_kind_ptr]; mov [rdx+rbx*8],rcx
    mov ecx,[rip+g_current_loop_work_ticks]; mov [rdx+rbx*8+4],ecx
.gfwork_done: pop r13; pop r12; pop rbx; ret

# ebx=Region, r13=head, r14=len. One dynamic fragment plus straight continuations
# yields a work span; more than one unknown/dynamic fragment remains unknown.
# Per-trip front-end price comes from actual emitted bytes, not a group/size gate.
g_region_work_fact_ptr:
    mov eax,[rip+g_region_count]; imul rax,rax,68
    mov ecx,[rip+g_region_edge_count]; shl rcx,4; add rax,rcx
    add rax,GR_TEMPLATE_SIZE; add rax,[rip+g_parallel_code_ptr]
    mov ecx,ebx; shl rcx,4; add rax,rcx; ret
g_region_work_fact:
    push rbx; push r12; push r13; push r14; push rbp
    call g_region_work_fact_ptr; mov r12,rax
    mov qword ptr [r12],0; mov qword ptr [r12+8],0
    xor ebp,ebp
.grwork_scan:
    test r14d,r14d; jz .grwork_done
    mov rax,[rip+g_fragment_static_ptr]; cmp dword ptr [rax+r13*4],0; jne .grwork_next
    inc ebp; cmp ebp,1; ja .grwork_unknown
    mov rax,[rip+g_fragment_work_kind_ptr]; mov ecx,[rax+r13*8]
    test ecx,ecx; jz .grwork_unknown
    mov [r12+12],ecx
    mov rax,[rip+g_fragment_work_source_ptr]; mov rax,[rax+r13*8]; mov [r12],rax
    mov rax,[rip+g_fragment_work_kind_ptr]; mov eax,[rax+r13*8+4]
    test eax,eax; jz .grwork_unknown
    mov [r12+8],eax
.grwork_next:
    dec r14d; jz .grwork_done
    mov rax,[rip+g_sole_succ_ptr]; mov r13d,[rax+r13*4]
    jmp .grwork_scan
.grwork_unknown: mov qword ptr [r12+8],0
.grwork_done:
    mov eax,[r12+12]                 # nonzero iff the iterative term is proved
    pop rbp; pop r14; pop r13; pop r12; pop rbx; ret
.bss
.p2align 3
g_current_loop_work_ticks: .skip 4
.p2align 3
g_fragment_work_source_ptr: .skip 8
g_fragment_work_kind_ptr: .skip 8
.text
