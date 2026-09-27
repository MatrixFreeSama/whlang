# Shared ShapeFact-N canonical parser for Tensor physicalizers.
# Host contract:
#   obj_get, span_eq, node_parse_u64 available
#   tensor_shape_extent_min/tensor_shape_extent_max/tensor_domain_min/tensor_domain_max
#   tensor_shape_static_product, tensor_shape_rank
#   tensor_shape_runtime_name_ptr/len storage
# Returns eax=0 success, eax=1 failure.
.section .text
shapefn_parse_root:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov qword ptr [rip+tensor_shape_static_product],1
    mov dword ptr [rip+tensor_shape_rank],0
    mov qword ptr [rip+tensor_shape_runtime_name_ptr],0
    mov qword ptr [rip+tensor_shape_runtime_name_len],0

    mov rdi,r12
    lea rsi,[rip+shapefn_k_root]
    mov edx,shapefn_k_root_end-shapefn_k_root
    call obj_get
    test rax,rax
    jz .sfp_fail
    cmp qword ptr [rax],J_OBJECT
    jne .sfp_fail
    mov r13,rax

    mov rdi,r13
    lea rsi,[rip+shapefn_k_axes]
    mov edx,shapefn_k_axes_end-shapefn_k_axes
    call obj_get
    test rax,rax
    jz .sfp_fail
    cmp qword ptr [rax],J_ARRAY
    jne .sfp_fail
    mov r13,[rax+24]
    xor ebx,ebx                         # logical axis index
    mov r14,1                           # static suffix product
    xor r15d,r15d                       # runtime extent count
.sfp_axis_loop:
    test r13,r13
    jz .sfp_axes_done
    cmp qword ptr [r13],J_OBJECT
    jne .sfp_fail

    # Axis identity is required even when the physicalizer later collapses it.
    mov rdi,r13
    lea rsi,[rip+shapefn_k_name]
    mov edx,shapefn_k_name_end-shapefn_k_name
    call obj_get
    test rax,rax
    jz .sfp_fail
    cmp qword ptr [rax],J_STRING
    jne .sfp_fail
    cmp qword ptr [rax+16],0
    je .sfp_fail

    mov rdi,r13
    lea rsi,[rip+shapefn_k_extent]
    mov edx,shapefn_k_extent_end-shapefn_k_extent
    call obj_get
    test rax,rax
    jz .sfp_fail
    cmp qword ptr [rax],J_OBJECT
    jne .sfp_fail
    mov rdi,rax
    push r13
    push rbx
    mov r13,rax                          # extent object

    mov rdi,r13
    lea rsi,[rip+shapefn_k_var]
    mov edx,shapefn_k_var_end-shapefn_k_var
    call obj_get
    test rax,rax
    jz .sfp_static_extent
    cmp qword ptr [rax],J_STRING
    jne .sfp_extent_fail
    cmp qword ptr [rax+16],0
    je .sfp_extent_fail
    inc r15d
    cmp r15d,1
    jne .sfp_extent_fail                 # current Tensor consumer: one runtime fact
    cmp ebx,0
    jne .sfp_extent_fail                 # one-root consumer keeps it in high coordinate
    mov rcx,[rax+8]
    mov [rip+tensor_shape_runtime_name_ptr],rcx
    mov rcx,[rax+16]
    mov [rip+tensor_shape_runtime_name_len],rcx
    jmp .sfp_extent_ok

.sfp_static_extent:
    mov rdi,r13
    lea rsi,[rip+shapefn_k_literal]
    mov edx,shapefn_k_literal_end-shapefn_k_literal
    call obj_get
    test rax,rax
    jz .sfp_extent_fail
    call node_parse_u64
    test edx,edx
    jnz .sfp_extent_fail
    test rax,rax
    jz .sfp_extent_fail
    mov rcx,rax
    mov rax,r14
    mul rcx
    test rdx,rdx
    jnz .sfp_extent_fail
    mov r14,rax
.sfp_extent_ok:
    pop rbx
    pop r13
    inc ebx
    mov r13,[r13+32]
    jmp .sfp_axis_loop
.sfp_extent_fail:
    pop rbx
    pop r13
    jmp .sfp_fail

.sfp_axes_done:
    test ebx,ebx
    jz .sfp_fail
    cmp r15d,1
    jne .sfp_fail
    mov dword ptr [rip+tensor_shape_rank],ebx
    mov qword ptr [rip+tensor_shape_static_product],r14

    # Resolve the runtime extent identity against the canonical input relation.
    mov rdi,r12
    lea rsi,[rip+shapefn_k_inputs]
    mov edx,shapefn_k_inputs_end-shapefn_k_inputs
    call obj_get
    test rax,rax
    jz .sfp_fail
    cmp qword ptr [rax],J_ARRAY
    jne .sfp_fail
    mov r13,[rax+24]
.sfp_input_loop:
    test r13,r13
    jz .sfp_fail
    cmp qword ptr [r13],J_OBJECT
    jne .sfp_fail
    mov rdi,r13
    lea rsi,[rip+shapefn_k_name]
    mov edx,shapefn_k_name_end-shapefn_k_name
    call obj_get
    test rax,rax
    jz .sfp_next_input
    cmp qword ptr [rax],J_STRING
    jne .sfp_next_input
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    mov rdx,[rip+tensor_shape_runtime_name_ptr]
    mov rcx,[rip+tensor_shape_runtime_name_len]
    call span_eq
    test eax,eax
    jnz .sfp_input_found
.sfp_next_input:
    mov r13,[r13+32]
    jmp .sfp_input_loop

.sfp_input_found:
    mov rdi,r13
    lea rsi,[rip+shapefn_k_type]
    mov edx,shapefn_k_type_end-shapefn_k_type
    call obj_get
    test rax,rax
    jz .sfp_fail
    cmp qword ptr [rax],J_STRING
    jne .sfp_fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    lea rdx,[rip+shapefn_v_u64]
    mov ecx,shapefn_v_u64_end-shapefn_v_u64
    call span_eq
    test eax,eax
    jz .sfp_fail

    mov rdi,r13
    lea rsi,[rip+shapefn_k_min]
    mov edx,shapefn_k_min_end-shapefn_k_min
    call obj_get
    call node_parse_u64
    test edx,edx
    jnz .sfp_fail
    mov [rip+tensor_shape_extent_min],rax

    mov rdi,r13
    lea rsi,[rip+shapefn_k_max]
    mov edx,shapefn_k_max_end-shapefn_k_max
    call obj_get
    call node_parse_u64
    test edx,edx
    jnz .sfp_fail
    mov [rip+tensor_shape_extent_max],rax
    mov rcx,[rip+tensor_shape_extent_min]
    cmp rcx,rax
    ja .sfp_fail

    # Physical-domain bounds are derived facts, not a policy ceiling.
    mov rbx,[rip+tensor_shape_static_product]
    mov rax,[rip+tensor_shape_extent_min]
    mul rbx
    test rdx,rdx
    jnz .sfp_fail
    mov [rip+tensor_domain_min],rax
    mov rax,[rip+tensor_shape_extent_max]
    mul rbx
    test rdx,rdx
    jnz .sfp_fail
    mov [rip+tensor_domain_max],rax

    xor eax,eax
    jmp .sfp_done
.sfp_fail:
    mov eax,1
.sfp_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.section .rodata
shapefn_k_root:.ascii "shape_fact_n"; shapefn_k_root_end:
shapefn_k_axes:.ascii "axes"; shapefn_k_axes_end:
shapefn_k_name:.ascii "name"; shapefn_k_name_end:
shapefn_k_extent:.ascii "extent"; shapefn_k_extent_end:
shapefn_k_var:.ascii "var"; shapefn_k_var_end:
shapefn_k_literal:.ascii "literal"; shapefn_k_literal_end:
shapefn_k_inputs:.ascii "inputs"; shapefn_k_inputs_end:
shapefn_k_type:.ascii "type"; shapefn_k_type_end:
shapefn_k_min:.ascii "min"; shapefn_k_min_end:
shapefn_k_max:.ascii "max"; shapefn_k_max_end:
shapefn_v_u64:.ascii "u64"; shapefn_v_u64_end:
.section .text
