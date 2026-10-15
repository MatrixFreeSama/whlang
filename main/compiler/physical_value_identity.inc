# One typed identity relation; the consumer passes its admission predicate in RDX.
# RDX=0 is valid only for a previously admitted pure expression slice.
.text
.global physical_value_expr_equal
physical_value_expr_equal:
    push rbx; push r12; push r13; push r14; push r15; sub rsp,8
    mov [rsp],rdx
    mov r12,rdi; mov r13,rsi
    cmp r12,r13; je .pvee_yes
    test r12,r12; jz .pvee_no
    test r13,r13; jz .pvee_no
    cmp qword ptr [r12],1; jne .pvee_no
    cmp qword ptr [r13],1; jne .pvee_no

    # State leaf identity.
    mov rdi,r12; lea rsi,[rip+pvk_state]; mov edx,pvk_state_end-pvk_state; call obj_get
    test rax,rax; jz .pvee_literal
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+pvk_state]; mov edx,pvk_state_end-pvk_state; call obj_get
    test rax,rax; jz .pvee_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[rax+8]; mov ecx,dword ptr [rax+16]; call span_eq
    jmp .pvee_done

.pvee_literal:
    mov rdi,r12; lea rsi,[rip+pvk_literal]; mov edx,pvk_literal_end-pvk_literal; call obj_get
    test rax,rax; jz .pvee_var
    mov r14,rax                            # literal node A
    mov rdi,r13; lea rsi,[rip+pvk_literal]; mov edx,pvk_literal_end-pvk_literal; call obj_get
    test rax,rax; jz .pvee_no
    mov r15,rax                            # literal node B

    # Type is part of literal identity.  Floating literals are compared by the
    # already-rounded Numeric ValueFact, not by source spelling: 1e-8,
    # 0.00000001 and 0.000000010000 therefore become one physical value when
    # their target type and IEEE bits are identical.  No algebraic reassociation
    # or tolerance is introduced.
    mov rdi,r12; lea rsi,[rip+pvk_type]; mov edx,pvk_type_end-pvk_type; call obj_get
    test rax,rax; jz .pvee_no
    mov rbx,rax
    mov rdi,r13; lea rsi,[rip+pvk_type]; mov edx,pvk_type_end-pvk_type; call obj_get
    test rax,rax; jz .pvee_no
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; mov rdx,[rax+8]; mov ecx,[rax+16]; call span_eq
    test eax,eax; jz .pvee_no
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+pv_f64]; mov ecx,3; call span_eq
    test eax,eax; jnz .pvee_literal_f64_bits
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+pv_f32]; mov ecx,3; call span_eq
    test eax,eax; jnz .pvee_literal_f32_bits

    # Non-floating literal families retain exact spelling identity.
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[r15+8]; mov ecx,dword ptr [r15+16]; call span_eq
    jmp .pvee_done

.pvee_literal_f64_bits:
    mov rax,r14; call node_parse_f64_bits; test edx,edx; jnz .pvee_no
    mov r12,rax
    mov rax,r15; call node_parse_f64_bits; test edx,edx; jnz .pvee_no
    cmp rax,r12; sete al; movzx eax,al
    jmp .pvee_done

.pvee_literal_f32_bits:
    mov rax,r14; call node_parse_f32_bits; test edx,edx; jnz .pvee_no
    mov r12d,eax
    mov rax,r15; call node_parse_f32_bits; test edx,edx; jnz .pvee_no
    cmp eax,r12d; sete al; movzx eax,al
    jmp .pvee_done

.pvee_var:
    mov rdi,r12; lea rsi,[rip+pvk_var]; mov edx,pvk_var_end-pvk_var; call obj_get
    test rax,rax; jz .pvee_op
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+pvk_var]; mov edx,pvk_var_end-pvk_var; call obj_get
    test rax,rax; jz .pvee_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[rax+8]; mov ecx,dword ptr [rax+16]; call span_eq
    jmp .pvee_done

.pvee_op:
    mov rdi,r12; lea rsi,[rip+pvk_axis]; mov edx,pvk_axis_end-pvk_axis; call obj_get
    test rax,rax; jz .pvee_load
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+pvk_axis]; mov edx,pvk_axis_end-pvk_axis; call obj_get
    test rax,rax; jz .pvee_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[rax+8]; mov ecx,dword ptr [rax+16]; call span_eq
    jmp .pvee_done
.pvee_load:
    mov rdi,r12; lea rsi,[rip+pvk_load]; mov edx,pvk_load_end-pvk_load; call obj_get
    test rax,rax; jz .pvee_operator
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+pvk_load]; mov edx,pvk_load_end-pvk_load; call obj_get
    test rax,rax; jz .pvee_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[rax+8]; mov ecx,dword ptr [rax+16]; call span_eq
    test eax,eax; jz .pvee_no
    mov rdi,r12; lea rsi,[rip+pvk_indices]; mov edx,pvk_indices_end-pvk_indices; call obj_get
    mov r14,[rax+24]; test r14,r14; jz .pvee_no
    cmp qword ptr [r14+32],0; jne .pvee_no
    mov rdi,r13; lea rsi,[rip+pvk_indices]; mov edx,pvk_indices_end-pvk_indices; call obj_get
    mov rsi,[rax+24]; test rsi,rsi; jz .pvee_no
    cmp qword ptr [rsi+32],0; jne .pvee_no
    mov rdi,r14; mov rdx,[rsp]; call physical_value_expr_equal
    jmp .pvee_done
.pvee_operator:
    cmp qword ptr [rsp],0; je 1f
    mov rdi,r12; call qword ptr [rsp]
    test eax,eax; jz .pvee_no
    mov rdi,r13; call qword ptr [rsp]
    test eax,eax; jz .pvee_no
1:
    mov rdi,r12; lea rsi,[rip+pvk_op]; mov edx,pvk_op_end-pvk_op; call obj_get
    test rax,rax; jz .pvee_no
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+pvk_op]; mov edx,pvk_op_end-pvk_op; call obj_get
    test rax,rax; jz .pvee_no
    mov r15,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[r15+8]; mov ecx,dword ptr [r15+16]; call span_eq
    test eax,eax; jz .pvee_no
    mov rdi,r12; lea rsi,[rip+pvk_args]; mov edx,pvk_args_end-pvk_args; call obj_get
    test rax,rax; jz .pvee_no
    mov r14,[rax+24]; test r14,r14; jz .pvee_no
    mov rbx,[r14+32]
    test rbx,rbx; jz .pvee_a_arity_ready
    cmp qword ptr [rbx+32],0; jne .pvee_no
.pvee_a_arity_ready:
    mov rdi,r13; lea rsi,[rip+pvk_args]; mov edx,pvk_args_end-pvk_args; call obj_get
    test rax,rax; jz .pvee_no
    mov r15,[rax+24]; test r15,r15; jz .pvee_no
    mov r13,[r15+32]
    test r13,r13; jz .pvee_b_arity_ready
    cmp qword ptr [r13+32],0; jne .pvee_no
.pvee_b_arity_ready:
    mov rdi,r14; mov rsi,r15; mov rdx,[rsp]; call physical_value_expr_equal
    test eax,eax; jz .pvee_no
    test rbx,rbx; jz .pvee_unary_tail
    test r13,r13; jz .pvee_no
    mov rdi,rbx; mov rsi,r13; mov rdx,[rsp]; call physical_value_expr_equal
    jmp .pvee_done
.pvee_unary_tail:
    test r13,r13; setz al; movzx eax,al
    jmp .pvee_done
.pvee_yes:
    mov eax,1; jmp .pvee_done
.pvee_no:
    xor eax,eax
.pvee_done:
    add rsp,8; pop r15; pop r14; pop r13; pop r12; pop rbx; ret


.section .rodata
pvk_state:.ascii "state"; pvk_state_end:
pvk_literal:.ascii "literal"; pvk_literal_end:
pvk_type:.ascii "type"; pvk_type_end:
pvk_var:.ascii "var"; pvk_var_end:
pvk_axis:.ascii "axis"; pvk_axis_end:
pvk_load:.ascii "load"; pvk_load_end:
pvk_indices:.ascii "indices"; pvk_indices_end:
pvk_op:.ascii "op"; pvk_op_end:
pvk_args:.ascii "args"; pvk_args_end:
pv_f32:.ascii "f32"
pv_f64:.ascii "f64"
