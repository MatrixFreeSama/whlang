# Wheelchair Tensor SupportFact convergence.
# This authority derives execution support from ValueFact topology. Zero-false
# selects contribute contiguous primitive Regions; ADD/SUB compose their union.
# Runtime discovers exact IEEE boundaries, canonicalizes a source-sized RegionSet,
# and Physical Reality erases proven-zero subtrees without workload geometry.

# support_resolve_identity_load(rdi=expr) -> rax=canonical expression.
# Only direct same-axis map edges are transparent. Indexed maps remain real
# CoordinateFacts and are never guessed through by SupportFact analysis.
support_resolve_identity_load:
    push rbx
    push r12
    push r13
    mov r12,rdi
.sril_loop:
    mov rdi,r12
    lea rsi,[rip+k_load]
    mov edx,k_load_end-k_load
    call obj_get
    test rax,rax
    jz .sril_done
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call find_binding
    test rax,rax
    jz .sril_done
    mov r13,rax
    cmp dword ptr [r13+16],OP_MAP
    jne .sril_done
    mov rdi,r12
    lea rsi,[rip+k_indices]
    mov edx,k_indices_end-k_indices
    call obj_get
    test rax,rax
    jz .sril_done
    mov rbx,[rax+24]
    test rbx,rbx
    jz .sril_done
    cmp qword ptr [rbx+32],0
    jne .sril_done
    mov rdi,rbx
    lea rsi,[rip+k_axis]
    mov edx,k_axis_end-k_axis
    call obj_get
    test rax,rax
    jz .sril_done
    mov r12,[r13+40]
    test r12,r12
    jnz .sril_loop
.sril_done:
    mov rax,r12
    pop r13
    pop r12
    pop rbx
    ret

# support_const_sign(rdi=expr) -> eax = -1,0,+1; eax=2 unknown.
# It recognizes only axis-independent sign facts already present in the tensor
# algebra. Runtime n is positive by ShapeFact range validation.
support_const_sign:
    push rbx
    push r12
    push r13
    push r14
    mov r12,rdi
    call support_resolve_identity_load
    mov r12,rax
    mov rdi,r12
    call expr_literal_f64_bits
    test edx,edx
    jnz .scs_u64_probe
    mov rcx,rax
    mov rdx,rax
    shr rdx,52
    and edx,0x7ff
    cmp edx,0x7ff
    je .scs_unknown
    mov rdx,rax
    shl rdx,1
    test rdx,rdx
    jz .scs_zero
    test rcx,rcx
    js .scs_neg
    mov eax,1
    jmp .scs_done
.scs_zero:
    xor eax,eax
    jmp .scs_done
.scs_neg:
    mov eax,-1
    jmp .scs_done
.scs_u64_probe:
    mov rdi,r12
    call expr_literal_u64
    test edx,edx
    jnz .scs_var_probe
    test rax,rax
    jz .scs_zero
    mov eax,1
    jmp .scs_done
.scs_var_probe:
    mov rdi,r12
    lea rsi,[rip+k_var]
    mov edx,k_var_end-k_var
    call obj_get
    test rax,rax
    jz .scs_op
    mov rdi,[rax+8]; mov rsi,[rax+16]
    call tensor_find_input
    test edx,edx; jz .scs_unknown
    shl rax,5
    add rax,[rip+tensor_input_descriptors]
    lea rdi,[rax+8]
    mov esi,3; cmp edx,TYPE_F64; jne .scs_range_sign
    mov esi,5
.scs_range_sign:
    call physical_input_range_sign
    jmp .scs_done

.scs_op:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .scs_unknown
    mov r13,rax
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .scs_unknown
    mov r14,[rax+24]
    test r14,r14
    jz .scs_unknown
    # cast(f64,n) and cast(f64,u64-literal) preserve nonnegative sign.
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_cast]
    mov ecx,v_cast_end-v_cast
    call span_eq
    test eax,eax
    jz .scs_mul_probe
    mov rdi,r14
    call support_const_sign
    jmp .scs_done
.scs_mul_probe:
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_mul]
    mov ecx,v_mul_end-v_mul
    call span_eq
    test eax,eax
    jz .scs_div_probe
    mov rbx,[r14+32]
    test rbx,rbx
    jz .scs_unknown
    cmp qword ptr [rbx+32],0
    jne .scs_unknown
    mov rdi,r14
    call support_const_sign
    cmp eax,2
    je .scs_unknown
    mov r13d,eax
    mov rdi,rbx
    call support_const_sign
    cmp eax,2
    je .scs_unknown
    imul eax,r13d
    jmp .scs_done
.scs_div_probe:
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_div]
    mov ecx,v_div_end-v_div
    call span_eq
    test eax,eax
    jz .scs_unknown
    mov rbx,[r14+32]
    test rbx,rbx
    jz .scs_unknown
    cmp qword ptr [rbx+32],0
    jne .scs_unknown
    mov rdi,r14
    call support_const_sign
    cmp eax,2
    je .scs_unknown
    mov r13d,eax
    mov rdi,rbx
    call support_const_sign
    cmp eax,2
    je .scs_unknown
    test eax,eax
    jz .scs_unknown
    imul eax,r13d
    jmp .scs_done
.scs_unknown:
    mov eax,2
.scs_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Strip only proved nonzero axis-independent multiplicative factors.
# This is a proof identity, never a rewrite of the emitted IEEE expression.
support_multiplicative_core:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
.smc_loop:
    mov rdi,r12; call support_resolve_identity_load; mov r12,rax
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .smc_done
    mov r13,rax; xor r14d,r14d
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jnz .smc_args
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .smc_done
    mov r14d,1
.smc_args:
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .smc_done
    mov r13,[rax+24]; test r13,r13; jz .smc_done
    mov rbx,[r13+32]; test rbx,rbx; jz .smc_done
    cmp qword ptr [rbx+32],0; jne .smc_done
    mov rdi,rbx; call support_const_sign
    cmp eax,1; je .smc_strip_rhs
    cmp eax,-1; je .smc_strip_rhs
    test r14d,r14d; jnz .smc_done
    mov rdi,r13; call support_const_sign
    cmp eax,1; je .smc_strip_lhs
    cmp eax,-1; jne .smc_done
.smc_strip_lhs:
    mov r12,rbx; jmp .smc_loop
.smc_strip_rhs:
    mov r12,r13; jmp .smc_loop
.smc_done:
    mov rax,r12
    pop r14; pop r13; pop r12; pop rbx; ret

# support_shape_class(rdi=expr) -> eax shape class, 0 unsupported.
# INC/DEC are monotone axis sequences. BASIN is a single discrete basin, hence
# every sublevel predicate against an axis-independent constant has contiguous
# support. The closure is deliberately small and algebraic: direct-axis map
# expansion, cast(axis), constant translations, signed constant scaling, and
# squaring of one monotone expression.
support_shape_class:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,32
    mov r12,rdi
    call support_resolve_identity_load
    mov r12,rax
    mov rdi,r12
    call expr_literal_f64_bits
    test edx,edx
    jz .ssc_const
    # A runtime InputFact is axis-independent. Finite validity is checked once
    # by the shared launch parser before this proof can erase a zero subtree.
    mov rdi,r12; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .ssc_operator
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_find_input
    cmp edx,TYPE_F64; je .ssc_const
    jmp .ssc_no
.ssc_operator:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .ssc_no
    mov r13,rax
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .ssc_no
    mov r14,[rax+24]
    test r14,r14
    jz .ssc_no

    # cast(axis) is monotone; cast(n)/literal is axis-independent.
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_cast]
    mov ecx,v_cast_end-v_cast
    call span_eq
    test eax,eax
    jz .ssc_square_probe
    cmp qword ptr [r14+32],0
    jne .ssc_no
    mov rdi,r14
    lea rsi,[rip+k_axis]
    mov edx,k_axis_end-k_axis
    call obj_get
    test rax,rax
    jnz .ssc_inc
    mov rdi,r14
    call support_const_sign
    cmp eax,2
    je .ssc_no
    jmp .ssc_const

.ssc_square_probe:
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_square]
    mov ecx,v_square_end-v_square
    call span_eq
    test eax,eax
    jz .ssc_binary
    cmp qword ptr [r14+32],0
    jne .ssc_no
    mov rdi,r14
    call support_shape_class
    cmp eax,SUPPORT_SHAPE_INC
    je .ssc_basin
    cmp eax,SUPPORT_SHAPE_DEC
    je .ssc_basin
    jmp .ssc_no

.ssc_binary:
    mov r15,[r14+32]
    test r15,r15
    jz .ssc_no
    cmp qword ptr [r15+32],0
    jne .ssc_no
    # classify operands once.
    mov rdi,r14
    call support_shape_class
    mov dword ptr [rsp],eax
    mov rdi,r15
    call support_shape_class
    mov dword ptr [rsp+4],eax

    # ADD
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_add]
    mov ecx,v_add_end-v_add
    call span_eq
    test eax,eax
    jz .ssc_sub_probe
    mov eax,dword ptr [rsp]
    mov edx,dword ptr [rsp+4]
    cmp eax,SUPPORT_SHAPE_CONST
    jne .ssc_add_l_nonconst
    mov eax,edx
    jmp .ssc_add_return
.ssc_add_l_nonconst:
    cmp edx,SUPPORT_SHAPE_CONST
    je .ssc_add_return
    cmp eax,edx
    jne .ssc_no
    cmp eax,SUPPORT_SHAPE_INC
    je .ssc_add_return
    cmp eax,SUPPORT_SHAPE_DEC
    je .ssc_add_return
    jmp .ssc_no
.ssc_add_return:
    test eax,eax
    jnz .ssc_done
    jmp .ssc_no

    # SUB
.ssc_sub_probe:
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_sub]
    mov ecx,v_sub_end-v_sub
    call span_eq
    test eax,eax
    jz .ssc_mul_probe
    mov eax,dword ptr [rsp]
    mov edx,dword ptr [rsp+4]
    cmp edx,SUPPORT_SHAPE_CONST
    je .ssc_done                    # nonconstant - constant, or constant-constant
    cmp eax,SUPPORT_SHAPE_CONST
    jne .ssc_no
    cmp edx,SUPPORT_SHAPE_INC
    je .ssc_dec
    cmp edx,SUPPORT_SHAPE_DEC
    je .ssc_inc
    cmp edx,SUPPORT_SHAPE_BASIN
    je .ssc_cap
    cmp edx,SUPPORT_SHAPE_CAP
    je .ssc_basin
    jmp .ssc_no

    # MUL
.ssc_mul_probe:
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_mul]
    mov ecx,v_mul_end-v_mul
    call span_eq
    test eax,eax
    jz .ssc_div_probe

    # A common monotone coordinate, scaled without translating its zero, has
    # one IEEE basin/cap. Mere equal slope signs of unrelated rounded affines
    # do not certify a discrete extremum, so that former inference is removed.
    cmp dword ptr [rsp],SUPPORT_SHAPE_CONST; je .ssc_mul_const
    cmp dword ptr [rsp+4],SUPPORT_SHAPE_CONST; je .ssc_mul_const
    mov rdi,r14; call support_multiplicative_core
    mov [rsp+8],rax
    mov rdi,r15; call support_multiplicative_core
    mov rsi,rax; mov rdi,[rsp+8]; xor edx,edx
    call physical_value_expr_equal
    test eax,eax; jz .ssc_no
    mov eax,dword ptr [rsp]
    mov edx,dword ptr [rsp+4]
    cmp eax,SUPPORT_SHAPE_INC
    jne .ssc_mul_both_dec
    cmp edx,SUPPORT_SHAPE_INC
    je .ssc_basin
    cmp edx,SUPPORT_SHAPE_DEC
    je .ssc_cap
    jmp .ssc_mul_const
.ssc_mul_both_dec:
    cmp eax,SUPPORT_SHAPE_DEC
    jne .ssc_mul_const
    cmp edx,SUPPORT_SHAPE_DEC
    je .ssc_basin
    cmp edx,SUPPORT_SHAPE_INC
    je .ssc_cap
.ssc_mul_const:
    mov eax,dword ptr [rsp]
    mov edx,dword ptr [rsp+4]
    cmp eax,SUPPORT_SHAPE_CONST
    je .ssc_mul_left_const
    cmp edx,SUPPORT_SHAPE_CONST
    jne .ssc_no
    mov rdi,r15
    call support_const_sign
    mov edx,eax
    mov eax,dword ptr [rsp]
    jmp .ssc_scale
.ssc_mul_left_const:
    cmp edx,SUPPORT_SHAPE_CONST
    je .ssc_const
    mov rdi,r14
    call support_const_sign
    mov ecx,eax
    mov eax,dword ptr [rsp+4]
    mov edx,ecx
.ssc_scale:
    cmp edx,2
    je .ssc_no
    test edx,edx
    jz .ssc_no                      # zero * unbounded is not a constant proof
    test edx,edx
    js .ssc_scale_neg
    jmp .ssc_done
.ssc_scale_neg:
    cmp eax,SUPPORT_SHAPE_INC
    je .ssc_dec
    cmp eax,SUPPORT_SHAPE_DEC
    je .ssc_inc
    cmp eax,SUPPORT_SHAPE_BASIN
    je .ssc_cap
    cmp eax,SUPPORT_SHAPE_CAP
    je .ssc_basin
    jmp .ssc_no

    # DIV by one signed axis-independent constant.
.ssc_div_probe:
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_div]
    mov ecx,v_div_end-v_div
    call span_eq
    test eax,eax
    jz .ssc_no
    cmp dword ptr [rsp+4],SUPPORT_SHAPE_CONST
    jne .ssc_no
    mov rdi,r15
    call support_const_sign
    mov edx,eax
    cmp edx,2
    je .ssc_no
    test edx,edx
    jz .ssc_no
    mov eax,dword ptr [rsp]
    test eax,eax
    jz .ssc_no
    test edx,edx
    jns .ssc_done
    cmp eax,SUPPORT_SHAPE_INC
    je .ssc_dec
    cmp eax,SUPPORT_SHAPE_DEC
    je .ssc_inc
    cmp eax,SUPPORT_SHAPE_BASIN
    je .ssc_cap
    cmp eax,SUPPORT_SHAPE_CAP
    je .ssc_basin
    jmp .ssc_no

.ssc_const:
    mov eax,SUPPORT_SHAPE_CONST
    jmp .ssc_done
.ssc_inc:
    mov eax,SUPPORT_SHAPE_INC
    jmp .ssc_done
.ssc_dec:
    mov eax,SUPPORT_SHAPE_DEC
    jmp .ssc_done
.ssc_basin:
    mov eax,SUPPORT_SHAPE_BASIN
    jmp .ssc_done
.ssc_cap:
    mov eax,SUPPORT_SHAPE_CAP
    jmp .ssc_done
.ssc_no:
    xor eax,eax
.ssc_done:
    add rsp,32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# support_shape_sublevel_ok(eax=shape class) -> eax 0/1.
# One contiguous true support after +shape minimum normalization.
support_shape_sublevel_ok:
    cmp eax,SUPPORT_SHAPE_INC
    je .sslo_yes
    cmp eax,SUPPORT_SHAPE_DEC
    je .sslo_yes
    cmp eax,SUPPORT_SHAPE_BASIN
    je .sslo_yes
    xor eax,eax
    ret
.sslo_yes:
    mov eax,1
    ret

# support_shape_superlevel_ok(eax=shape class) -> eax 0/1.
# CAP is the curvature-dual of BASIN; negating the witness turns its maximum
# into the same minimum-oriented runtime proof.
support_shape_superlevel_ok:
    cmp eax,SUPPORT_SHAPE_INC
    je .ssuo_yes
    cmp eax,SUPPORT_SHAPE_DEC
    je .ssuo_yes
    cmp eax,SUPPORT_SHAPE_CAP
    je .ssuo_yes
    xor eax,eax
    ret
.ssuo_yes:
    mov eax,1
    ret

# support_prepare_leaf(rdi=expression) -> eax=1 iff expression is one exact
# zero-false select whose ordered predicate has one provable contiguous support.
# On success tensor_support_predicate/tensor_support_basin name the cold witness.
support_prepare_leaf:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    call support_resolve_identity_load
    mov r12,rax
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .spl_no
    mov r13,rax
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_select]
    mov ecx,v_select_end-v_select
    call span_eq
    test eax,eax
    jz .spl_no
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .spl_no
    mov r14,[rax+24]               # predicate
    test r14,r14
    jz .spl_no
    mov r15,[r14+32]               # true arm
    test r15,r15
    jz .spl_no
    mov rbx,[r15+32]               # false arm
    test rbx,rbx
    jz .spl_no
    cmp qword ptr [rbx+32],0
    jne .spl_no
    mov rdi,rbx
    call expr_literal_f64_bits
    test edx,edx
    jnz .spl_no
    test rax,rax
    jnz .spl_no

    # Predicate is one ordered comparison. Boolean RegionSet algebra is kept at
    # the expression level; a leaf remains one original IEEE relation.
    mov rdi,r14
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .spl_no
    mov r13,rax
    mov rdi,r14
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .spl_no
    mov r15,[rax+24]               # lhs
    test r15,r15
    jz .spl_no
    mov rbx,[r15+32]               # rhs
    test rbx,rbx
    jz .spl_no
    cmp qword ptr [rbx+32],0
    jne .spl_no

    # Normalize every ordered predicate to one extremum witness whose global
    # minimum lies inside the true support. Sublevel uses +shape; superlevel
    # uses -shape. This keeps runtime boundary discovery topology-generic.
    mov dword ptr [rip+tensor_support_negate],0
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_lt]
    mov ecx,v_lt_end-v_lt
    call span_eq
    test eax,eax
    jnz .spl_lt_le
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_le]
    mov ecx,v_le_end-v_le
    call span_eq
    test eax,eax
    jnz .spl_lt_le
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_gt]
    mov ecx,v_gt_end-v_gt
    call span_eq
    test eax,eax
    jnz .spl_gt_ge
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_ge]
    mov ecx,v_ge_end-v_ge
    call span_eq
    test eax,eax
    jnz .spl_gt_ge
    jmp .spl_no

.spl_lt_le:
    # lhs shape < rhs const => sublevel; lhs const < rhs shape => superlevel.
    mov rdi,r15
    call support_shape_class
    mov r12d,eax
    mov rdi,rbx
    call support_shape_class
    mov edx,eax
    cmp edx,SUPPORT_SHAPE_CONST
    je .spl_accept_lhs_sub
    cmp r12d,SUPPORT_SHAPE_CONST
    je .spl_accept_rhs_super
    jmp .spl_no

.spl_gt_ge:
    # lhs shape > rhs const => superlevel; lhs const > rhs shape => sublevel.
    mov rdi,r15
    call support_shape_class
    mov r12d,eax
    mov rdi,rbx
    call support_shape_class
    mov edx,eax
    cmp edx,SUPPORT_SHAPE_CONST
    je .spl_accept_lhs_super
    cmp r12d,SUPPORT_SHAPE_CONST
    je .spl_accept_rhs_sub
    jmp .spl_no

.spl_accept_lhs_sub:
    mov eax,r12d
    call support_shape_sublevel_ok
    test eax,eax
    jz .spl_no
    mov qword ptr [rip+tensor_support_basin],r15
    jmp .spl_accept
.spl_accept_rhs_sub:
    mov eax,edx
    call support_shape_sublevel_ok
    test eax,eax
    jz .spl_no
    mov qword ptr [rip+tensor_support_basin],rbx
    jmp .spl_accept
.spl_accept_lhs_super:
    mov eax,r12d
    call support_shape_superlevel_ok
    test eax,eax
    jz .spl_no
    mov dword ptr [rip+tensor_support_negate],1
    mov qword ptr [rip+tensor_support_basin],r15
    jmp .spl_accept
.spl_accept_rhs_super:
    mov eax,edx
    call support_shape_superlevel_ok
    test eax,eax
    jz .spl_no
    mov dword ptr [rip+tensor_support_negate],1
    mov qword ptr [rip+tensor_support_basin],rbx
.spl_accept:
    mov qword ptr [rip+tensor_support_predicate],r14
    mov eax,1
    jmp .spl_done
.spl_no:
    xor eax,eax
.spl_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# support_reset_binding_seen() -> clears the existing source-sized binding
# visitation vector for one SupportFact pass.  The storage is the same AOT use-
# graph scratch already owned by Tensor Physical Reality; no second capacity or
# runtime manager is introduced.
support_reset_binding_seen:
    push rdi
    push rcx
    mov rdi,qword ptr [rip+tensor_binding_expanded_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+tensor_binding_count]
    rep stosd
    pop rcx
    pop rdi
    ret

# support_binding_first(rdi=binding) -> eax=1 first visit, eax=0 already seen,
# edx=0 success; edx=1 malformed binding.  One binding definition therefore has
# one SupportFact authority even when the expression DAG references it many times.
support_binding_first:
    push rbx
    mov rbx,qword ptr [rip+tensor_bindings_ptr]
    mov rax,rdi
    sub rax,rbx
    test rax,63
    jnz .sbf_fail
    shr rax,6
    cmp eax,dword ptr [rip+tensor_binding_count]
    jae .sbf_fail
    mov rcx,qword ptr [rip+tensor_binding_expanded_ptr]
    cmp dword ptr [rcx+rax*4],0
    jne .sbf_seen
    mov dword ptr [rcx+rax*4],1
    mov eax,1
    xor edx,edx
    pop rbx
    ret
.sbf_seen:
    xor eax,eax
    xor edx,edx
    pop rbx
    ret
.sbf_fail:
    xor eax,eax
    mov edx,1
    pop rbx
    ret

# support_predicate_exterior(rdi=ordered comparison) -> eax=0/1 exterior truth,
# edx=1 when both operands have exact exterior ValueFacts.  Ordered comparisons
# remain ordered for NaNs; != is true for unordered, the other relations false.
support_predicate_exterior:
    push rbx
    push r12
    push r13
    push r14
    sub rsp,16
    mov r12,rdi
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .spe_no
    mov r13,rax
    xor r14d,r14d
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax; jz .spe_ne; mov r14d,1; jmp .spe_kind
.spe_ne:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_ne]; mov ecx,v_ne_end-v_ne; call span_eq
    test eax,eax; jz .spe_lt; mov r14d,2; jmp .spe_kind
.spe_lt:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_lt]; mov ecx,v_lt_end-v_lt; call span_eq
    test eax,eax; jz .spe_le; mov r14d,3; jmp .spe_kind
.spe_le:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_le]; mov ecx,v_le_end-v_le; call span_eq
    test eax,eax; jz .spe_gt; mov r14d,4; jmp .spe_kind
.spe_gt:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_gt]; mov ecx,v_gt_end-v_gt; call span_eq
    test eax,eax; jz .spe_ge; mov r14d,5; jmp .spe_kind
.spe_ge:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_ge]; mov ecx,v_ge_end-v_ge; call span_eq
    test eax,eax; jz .spe_no; mov r14d,6
.spe_kind:
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .spe_no
    mov rbx,[rax+24]
    test rbx,rbx
    jz .spe_no
    mov r12,[rbx+32]
    test r12,r12
    jz .spe_no
    cmp qword ptr [r12+32],0
    jne .spe_no
    mov rdi,rbx
    call support_exterior_fact
    test edx,edx
    jz .spe_no
    mov qword ptr [rsp],rax
    mov rdi,r12
    call support_exterior_fact
    test edx,edx
    jz .spe_no
    mov qword ptr [rsp+8],rax
    movq xmm0,qword ptr [rsp]
    movq xmm1,qword ptr [rsp+8]
    ucomisd xmm0,xmm1
    jp .spe_unordered
    cmp r14d,1
    je .spe_eq_test
    cmp r14d,2
    je .spe_ne_test
    cmp r14d,3
    je .spe_lt_test
    cmp r14d,4
    je .spe_le_test
    cmp r14d,5
    je .spe_gt_test
    # GE
    jae .spe_true
    jmp .spe_false
.spe_eq_test:
    je .spe_true
    jmp .spe_false
.spe_ne_test:
    jne .spe_true
    jmp .spe_false
.spe_lt_test:
    jb .spe_true
    jmp .spe_false
.spe_le_test:
    jbe .spe_true
    jmp .spe_false
.spe_gt_test:
    ja .spe_true
    jmp .spe_false
.spe_unordered:
    cmp r14d,2
    je .spe_true
.spe_false:
    xor eax,eax
    mov edx,1
    jmp .spe_done
.spe_true:
    mov eax,1
    mov edx,1
    jmp .spe_done
.spe_no:
    xor eax,eax
    xor edx,edx
.spe_done:
    add rsp,16
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# support_exterior_fact(rdi=expr) -> rax=exact exterior f64 bits, edx=1 success.
# A SupportFact is no longer restricted to exterior +0 internally.  The region
# carries the places that may differ; this ValueFact carries the exact value
# outside that region.  Only the final reduction must converge back to exact +0
# before Physical Reality is allowed to erase exterior work.
support_exterior_fact:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,16
    mov r12,rdi

    mov rdi,r12
    call expr_literal_f64_bits
    test edx,edx
    jnz .sef_load
    mov edx,1
    jmp .sef_done

.sef_load:
    mov rdi,r12
    lea rsi,[rip+k_load]
    mov edx,k_load_end-k_load
    call obj_get
    test rax,rax
    jz .sef_op
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call find_binding
    test rax,rax
    jz .sef_no
    cmp dword ptr [rax+16],OP_MAP
    jne .sef_no
    mov rdi,[rax+40]
    call support_exterior_fact
    jmp .sef_done

.sef_op:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .sef_no
    mov r13,rax

    # A primitive topological select already proves that outside its predicate
    # Region the result is the exact +0 false arm.  Do not force its active arm
    # through a full-domain exterior analysis.
    mov rdi,r12
    call support_prepare_leaf
    test eax,eax
    jz .sef_sqrt_probe
    xor eax,eax
    mov edx,1
    jmp .sef_done

.sef_sqrt_probe:
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .sef_no
    mov r14,[rax+24]
    test r14,r14
    jz .sef_no

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax; jz .sef_square_probe
    cmp qword ptr [r14+32],0
    jne .sef_no
    mov rdi,r14
    call support_exterior_fact
    test edx,edx
    jz .sef_no
    movq xmm0,rax
    sqrtsd xmm0,xmm0
    movq rax,xmm0
    mov edx,1
    jmp .sef_done

.sef_square_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_square]; mov ecx,v_square_end-v_square; call span_eq
    test eax,eax; jz .sef_select_probe
    cmp qword ptr [r14+32],0
    jne .sef_no
    mov rdi,r14
    call support_exterior_fact
    test edx,edx
    jz .sef_no
    movq xmm0,rax
    mulsd xmm0,xmm0
    movq rax,xmm0
    mov edx,1
    jmp .sef_done

.sef_select_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .sef_binary
    mov r15,[r14+32]
    test r15,r15
    jz .sef_no
    mov rbx,[r15+32]
    test rbx,rbx
    jz .sef_no
    cmp qword ptr [rbx+32],0
    jne .sef_no
    mov rdi,r14
    call support_predicate_exterior
    test edx,edx
    jz .sef_no
    test eax,eax
    jz .sef_select_false
    mov rdi,r15
    call support_exterior_fact
    jmp .sef_done
.sef_select_false:
    mov rdi,rbx
    call support_exterior_fact
    jmp .sef_done

.sef_binary:
    mov r15,[r14+32]
    test r15,r15
    jz .sef_no
    cmp qword ptr [r15+32],0
    jne .sef_no
    xor ebx,ebx
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz .sef_sub; mov ebx,1; jmp .sef_binary_kind
.sef_sub:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz .sef_mul; mov ebx,2; jmp .sef_binary_kind
.sef_mul:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz .sef_div; mov ebx,3; jmp .sef_binary_kind
.sef_div:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .sef_no; mov ebx,4
.sef_binary_kind:
    mov rdi,r14
    call support_exterior_fact
    test edx,edx
    jz .sef_no
    mov qword ptr [rsp],rax
    mov rdi,r15
    call support_exterior_fact
    test edx,edx
    jz .sef_no
    mov qword ptr [rsp+8],rax
    movq xmm0,qword ptr [rsp]
    movq xmm1,qword ptr [rsp+8]
    cmp ebx,1
    je .sef_do_add
    cmp ebx,2
    je .sef_do_sub
    cmp ebx,3
    je .sef_do_mul
    divsd xmm0,xmm1
    jmp .sef_binary_out
.sef_do_add:
    addsd xmm0,xmm1
    jmp .sef_binary_out
.sef_do_sub:
    subsd xmm0,xmm1
    jmp .sef_binary_out
.sef_do_mul:
    mulsd xmm0,xmm1
.sef_binary_out:
    movq rax,xmm0
    mov edx,1
    jmp .sef_done

.sef_no:
    xor eax,eax
    xor edx,edx
.sef_done:
    add rsp,16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# support_note_index(rdi=index expression) -> eax=1 supported CoordinateFact,
# eax=0 unsupported.  Direct axis identity needs no dilation.  A dynamic-ring
# unit-affine translation contributes its exact signed displacement to the one
# current CoordinateFact chain; Physical Reality later dilates the RegionSet by
# the maximum absolute displacement actually present in the expression DAG.
support_note_index:
    push rbx
    push r12
    mov r12,rdi
    mov rdi,r12
    lea rsi,[rip+k_axis]
    mov edx,k_axis_end-k_axis
    call obj_get
    test rax,rax
    jnz .sni_yes
    mov rdi,r12
    call expr_index_key_u64
    test ecx,ecx
    jz .sni_no
    cmp rax,1
    jne .sni_no
    cmp r8,-1
    jne .sni_no
    mov rbx,qword ptr [rip+tensor_support_coord_shift]
    add rbx,rdx
    jo .sni_no
    mov qword ptr [rip+tensor_support_coord_shift],rbx
    mov rax,rbx
    test rax,rax
    jns .sni_abs_ready
    neg rax
    jo .sni_no
.sni_abs_ready:
    cmp rax,qword ptr [rip+tensor_support_halo_elems]
    jbe .sni_yes
    mov qword ptr [rip+tensor_support_halo_elems],rax
.sni_yes:
    mov eax,1
    pop r12
    pop rbx
    ret
.sni_no:
    xor eax,eax
    pop r12
    pop rbx
    ret

# support_count_predicate_terms(rdi=ordered comparison) -> eax=count, edx=1.
# A predicate can change only where either of its ValueFact operands changes.
support_count_predicate_terms:
    push rbx
    push r12
    mov r12,rdi
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .scpt_no
    mov r12,[rax+24]
    test r12,r12
    jz .scpt_no
    mov rbx,[r12+32]
    test rbx,rbx
    jz .scpt_no
    cmp qword ptr [rbx+32],0
    jne .scpt_no
    mov rdi,r12
    call support_count_terms
    test edx,edx
    jz .scpt_no
    mov r12d,eax
    mov rdi,rbx
    call support_count_terms
    test edx,edx
    jz .scpt_no
    add eax,r12d
    jc .scpt_no
    mov edx,1
    jmp .scpt_done
.scpt_no:
    xor eax,eax
    xor edx,edx
.scpt_done:
    pop r12
    pop rbx
    ret

# support_count_terms(rdi=expr) -> eax=unique primitive Region count, edx=1.
# Geometry and exterior ValueFact are separate facts.  Ordinary f64 relations
# conservatively union operand Regions; primitive topological selects still own
# exact cold boundary witnesses.  Binding definitions are expanded once, so a
# source DAG does not become a runtime tree of duplicate Region discoveries.
support_count_terms:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi

    mov rdi,r12
    call expr_literal_f64_bits
    test edx,edx
    jnz .sct_load
    xor eax,eax
    mov edx,1
    jmp .sct_done

.sct_load:
    mov rdi,r12
    lea rsi,[rip+k_load]
    mov edx,k_load_end-k_load
    call obj_get
    test rax,rax
    jz .sct_op
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call find_binding
    test rax,rax
    jz .sct_no
    mov r13,rax
    cmp dword ptr [r13+16],OP_MAP
    jne .sct_no
    mov rdi,r12
    lea rsi,[rip+k_indices]
    mov edx,k_indices_end-k_indices
    call obj_get
    test rax,rax
    jz .sct_no
    mov r14,[rax+24]
    test r14,r14
    jz .sct_no
    cmp qword ptr [r14+32],0
    jne .sct_no
    mov r15,qword ptr [rip+tensor_support_coord_shift]
    mov rdi,r14
    call support_note_index
    test eax,eax
    jz .sct_load_restore_no
    mov rdi,r13
    call support_binding_first
    test edx,edx
    jnz .sct_load_restore_no
    test eax,eax
    jz .sct_load_seen
    mov rdi,[r13+40]
    call support_count_terms
    mov qword ptr [rip+tensor_support_coord_shift],r15
    jmp .sct_done
.sct_load_seen:
    mov qword ptr [rip+tensor_support_coord_shift],r15
    xor eax,eax
    mov edx,1
    jmp .sct_done
.sct_load_restore_no:
    mov qword ptr [rip+tensor_support_coord_shift],r15
    jmp .sct_no

.sct_op:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .sct_no
    mov r13,rax

    mov rdi,r12
    call support_prepare_leaf
    test eax,eax
    jz .sct_args
    mov eax,1
    mov edx,1
    jmp .sct_done

.sct_args:
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .sct_no
    mov r14,[rax+24]
    test r14,r14
    jz .sct_no

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax; jnz .sct_unary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_square]; mov ecx,v_square_end-v_square; call span_eq
    test eax,eax; jnz .sct_unary

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .sct_binary_probe
    mov r15,[r14+32]
    test r15,r15
    jz .sct_no
    mov rbx,[r15+32]
    test rbx,rbx
    jz .sct_no
    cmp qword ptr [rbx+32],0
    jne .sct_no
    mov rdi,r14
    call support_count_predicate_terms
    test edx,edx
    jz .sct_no
    mov r13d,eax
    mov rdi,r15
    call support_count_terms
    test edx,edx
    jz .sct_no
    add r13d,eax
    jc .sct_no
    mov rdi,rbx
    call support_count_terms
    test edx,edx
    jz .sct_no
    add eax,r13d
    jc .sct_no
    mov edx,1
    jmp .sct_done

.sct_binary_probe:
    xor ebx,ebx
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jnz .sct_binary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jnz .sct_binary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jnz .sct_binary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .sct_no
.sct_binary:
    mov r15,[r14+32]
    test r15,r15
    jz .sct_no
    cmp qword ptr [r15+32],0
    jne .sct_no
    mov rdi,r14
    call support_count_terms
    test edx,edx
    jz .sct_no
    mov r13d,eax
    mov rdi,r15
    call support_count_terms
    test edx,edx
    jz .sct_no
    add eax,r13d
    jc .sct_no
    mov edx,1
    jmp .sct_done

.sct_unary:
    cmp qword ptr [r14+32],0
    jne .sct_no
    mov rdi,r14
    call support_count_terms
    jmp .sct_done

.sct_no:
    xor eax,eax
    xor edx,edx
.sct_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# tensor_support_analyze_root(rdi=reduction expression).
# The final reduction may contract only when its exact exterior ValueFact is
# +0.  Intermediate bindings may carry any exact exterior f64 value; their
# RegionSets remain the places where the value may differ from that background.
tensor_support_analyze_root:
    push r12
    mov dword ptr [rip+tensor_support_mode],SUPPORT_NONE
    mov dword ptr [rip+tensor_support_count],0
    mov qword ptr [rip+tensor_support_predicate],0
    mov qword ptr [rip+tensor_support_basin],0
    mov dword ptr [rip+tensor_support_negate],0
    mov qword ptr [rip+tensor_support_halo_elems],0
    mov qword ptr [rip+tensor_support_coord_shift],0
    mov r12,rdi

    # Exterior ValueFact first.  Exact +0 is the only identity that can be
    # physically erased from a strict sum without altering any IEEE bit.
    mov rdi,r12
    call support_exterior_fact
    test edx,edx
    jz .tsa_regions_done
    test rax,rax
    jnz .tsa_regions_done

    # Geometry is a separate pass so binding identity can be deduplicated
    # without sacrificing exterior-value propagation.
    call support_reset_binding_seen
    mov qword ptr [rip+tensor_support_coord_shift],0
    mov rdi,r12
    call support_count_terms
    test edx,edx
    jz .tsa_regions_done
    test eax,eax
    jz .tsa_regions_empty
    mov dword ptr [rip+tensor_support_count],eax
    mov dword ptr [rip+tensor_support_mode],SUPPORT_INTERVAL
    jmp .tsa_regions_done
.tsa_regions_empty:
    mov dword ptr [rip+tensor_support_mode],SUPPORT_EMPTY
.tsa_regions_done:
    pop r12
    ret

# Emit one exact leaf witness after support_prepare_leaf established predicate
# and basin. ABI: R8=i, R9=n; EAX=ordered predicate; XMM0=single-basin value.
tensor_emit_support_leaf:
    push rbx; push r12; push r13; push r14
    mov dword ptr [rip+emit_gpr_mask],0x00000CC2
    mov dword ptr [rip+emit_xmm_mask],0x00000FFC
    mov rdi,[rip+tensor_support_basin]; xor esi,esi
    call emit_float_reg
    test eax,eax; jnz .tesl_fail

    # The completed witness is already one operand of the PredicateFact.
    # Consume it directly rather than re-expanding the same map DAG.
    mov rdi,[rip+tensor_support_predicate]
    lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .tesl_fail
    mov r12,[rax+24]
    xor r13d,r13d                  # lhs is witness XMM0
    cmp r12,[rip+tensor_support_basin]; je .tesl_lhs_witness
    mov r13d,1                    # lhs constant XMM1, rhs witness XMM0
    mov rdi,r12; jmp .tesl_other
.tesl_lhs_witness:
    mov rdi,[r12+32]
.tesl_other:
    mov esi,1; call emit_float_reg
    test eax,eax; jnz .tesl_fail
    mov rdi,[rip+tensor_support_predicate]
    lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .tesl_fail
    mov r14,rax
    lea rbx,[rip+support_compare_relations]
.tesl_relation:
    mov rdi,[r14+8]; mov rsi,[r14+16]
    mov rdx,[rbx]; mov ecx,[rbx+8]; call span_eq
    test eax,eax; jnz .tesl_compare
    add rbx,16
    cmp qword ptr [rbx],0; jne .tesl_relation
    jmp .tesl_fail
.tesl_compare:
    mov ecx,[rbx+12]; xor edi,edi
    mov esi,r13d; mov edx,r13d; xor edx,1
    call gen_ucomisd_setcc          # sole ordered IEEE PredicateFact recipe
    cmp dword ptr [rip+tensor_support_negate],0
    je .tesl_return
    # Preserve EAX truth while normalizing the witness by exact sign-bit flip.
    mov edi,0x66; call emit_u8
    mov edi,0x48; call emit_u8
    mov edi,0x0f; call emit_u8
    mov edi,0x7e; call emit_u8
    mov edi,0xc2; call emit_u8      # movq rdx,xmm0
    mov edi,0x48; call emit_u8
    mov edi,0x0f; call emit_u8
    mov edi,0xba; call emit_u8
    mov edi,0xfa; call emit_u8
    mov edi,0x3f; call emit_u8      # btc rdx,63
    mov edi,0x66; call emit_u8
    mov edi,0x48; call emit_u8
    mov edi,0x0f; call emit_u8
    mov edi,0x6e; call emit_u8
    mov edi,0xc2; call emit_u8      # movq xmm0,rdx
.tesl_return:
    mov edi,0xc3; call emit_u8
    xor eax,eax; jmp .tesl_done
.tesl_fail:
    mov eax,1
.tesl_done:
    pop r14; pop r13; pop r12; pop rbx; ret
.pushsection .rodata
.p2align 3
support_compare_relations:
    .quad v_lt; .long v_lt_end-v_lt,0x92
    .quad v_le; .long v_le_end-v_le,0x96
    .quad v_gt; .long v_gt_end-v_gt,0x97
    .quad v_ge; .long v_ge_end-v_ge,0x93
    .quad 0
.popsection

# support_emit_leaf_current(rdi=primitive select) -> eax 0/1.  The same
# source-derived dispatcher is patched once per unique primitive SupportFact.
support_emit_leaf_current:
    push rbx
    push r12
    push r13
    push r14
    mov r12,rdi
    mov rdi,r12
    call support_prepare_leaf
    test eax,eax
    jz .selc_fail
    mov ecx,dword ptr [rip+tensor_support_emit_index]
    cmp ecx,dword ptr [rip+tensor_support_count]
    jae .selc_fail
    mov rax,rcx
    imul rax,13
    mov rdx,qword ptr [rip+tensor_support_dispatch_base]
    lea rbx,[rdx+rax+9]
    lea r13,[rdx+rax+13]
    mov r14,qword ptr [rip+emit_ptr]
    sub r14,r13
    mov dword ptr [rbx],r14d
    inc dword ptr [rip+tensor_support_emit_index]
    call tensor_emit_support_leaf
    jmp .selc_done
.selc_fail:
    mov eax,1
.selc_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

support_emit_predicate_terms:
    push rbx
    push r12
    mov r12,rdi
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .sept_fail
    mov r12,[rax+24]
    test r12,r12
    jz .sept_fail
    mov rbx,[r12+32]
    test rbx,rbx
    jz .sept_fail
    cmp qword ptr [rbx+32],0
    jne .sept_fail
    mov rdi,r12
    call support_emit_terms
    test eax,eax
    jnz .sept_fail
    mov rdi,rbx
    call support_emit_terms
    jmp .sept_done
.sept_fail:
    mov eax,1
.sept_done:
    pop r12
    pop rbx
    ret

# support_emit_terms(rdi=expr) mirrors support_count_terms.  Binding identity is
# deduplicated with the same source-sized visitation vector, so runtime boundary
# discovery is proportional to unique primitive Regions rather than expression
# occurrence count.
support_emit_terms:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi

    mov rdi,r12
    call expr_literal_f64_bits
    test edx,edx
    jnz .set_load
    xor eax,eax
    jmp .set_done

.set_load:
    mov rdi,r12
    lea rsi,[rip+k_load]
    mov edx,k_load_end-k_load
    call obj_get
    test rax,rax
    jz .set_op
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call find_binding
    test rax,rax
    jz .set_fail
    mov r13,rax
    cmp dword ptr [r13+16],OP_MAP
    jne .set_fail
    mov rdi,r12
    lea rsi,[rip+k_indices]
    mov edx,k_indices_end-k_indices
    call obj_get
    test rax,rax
    jz .set_fail
    mov r14,[rax+24]
    test r14,r14
    jz .set_fail
    cmp qword ptr [r14+32],0
    jne .set_fail
    mov r15,qword ptr [rip+tensor_support_coord_shift]
    mov rdi,r14
    call support_note_index
    test eax,eax
    jz .set_load_restore_fail
    mov rdi,r13
    call support_binding_first
    test edx,edx
    jnz .set_load_restore_fail
    test eax,eax
    jz .set_load_seen
    mov rdi,[r13+40]
    call support_emit_terms
    mov qword ptr [rip+tensor_support_coord_shift],r15
    jmp .set_done
.set_load_seen:
    mov qword ptr [rip+tensor_support_coord_shift],r15
    xor eax,eax
    jmp .set_done
.set_load_restore_fail:
    mov qword ptr [rip+tensor_support_coord_shift],r15
    jmp .set_fail

.set_op:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .set_fail
    mov r13,rax

    mov rdi,r12
    call support_prepare_leaf
    test eax,eax
    jz .set_args
    mov rdi,r12
    call support_emit_leaf_current
    jmp .set_done

.set_args:
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .set_fail
    mov r14,[rax+24]
    test r14,r14
    jz .set_fail

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax; jnz .set_unary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_square]; mov ecx,v_square_end-v_square; call span_eq
    test eax,eax; jnz .set_unary

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .set_binary_probe
    mov r15,[r14+32]
    test r15,r15
    jz .set_fail
    mov rbx,[r15+32]
    test rbx,rbx
    jz .set_fail
    cmp qword ptr [rbx+32],0
    jne .set_fail
    mov rdi,r14
    call support_emit_predicate_terms
    test eax,eax
    jnz .set_fail
    mov rdi,r15
    call support_emit_terms
    test eax,eax
    jnz .set_fail
    mov rdi,rbx
    call support_emit_terms
    jmp .set_done

.set_binary_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jnz .set_binary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jnz .set_binary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jnz .set_binary
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .set_fail
.set_binary:
    mov r15,[r14+32]
    test r15,r15
    jz .set_fail
    cmp qword ptr [r15+32],0
    jne .set_fail
    mov rdi,r14
    call support_emit_terms
    test eax,eax
    jnz .set_fail
    mov rdi,r15
    call support_emit_terms
    jmp .set_done

.set_unary:
    cmp qword ptr [r14+32],0
    jne .set_fail
    mov rdi,r14
    call support_emit_terms
    jmp .set_done

.set_fail:
    mov eax,1
.set_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# tensor_emit_support_probe() -> eax 0/1.
# The generated cold witness starts with one source-cardinality dispatcher.
# R10D selects a RegionSet leaf. The dispatcher count is not a fixed capacity.
tensor_emit_support_probe:
    cmp dword ptr [rip+tensor_support_mode],SUPPORT_INTERVAL
    jne .tesp_regions_none
    push rbx
    push r12
    mov r12d,dword ptr [rip+tensor_support_count]
    test r12d,r12d
    jz .tesp_regions_fail_pop
    mov rax,qword ptr [rip+emit_ptr]
    mov qword ptr [rip+tensor_support_dispatch_base],rax
    mov dword ptr [rip+tensor_support_emit_index],0
    xor ebx,ebx
.tesp_dispatch_loop:
    cmp ebx,r12d
    jae .tesp_dispatch_done
    # CMP r10d, imm32 ; JE rel32. Rel32 is patched when the leaf is emitted.
    mov edi,0x41; call emit_u8
    mov edi,0x81; call emit_u8
    mov edi,0xFA; call emit_u8
    mov rax,qword ptr [rip+emit_ptr]
    lea rcx,[rax+4]
    cmp rcx,qword ptr [rip+emit_end]
    ja .tesp_regions_fail_pop
    mov dword ptr [rax],ebx
    mov qword ptr [rip+emit_ptr],rcx
    mov edi,0x0F; call emit_u8
    mov edi,0x84; call emit_u8
    mov rax,qword ptr [rip+emit_ptr]
    lea rcx,[rax+4]
    cmp rcx,qword ptr [rip+emit_end]
    ja .tesp_regions_fail_pop
    mov dword ptr [rax],0
    mov qword ptr [rip+emit_ptr],rcx
    inc ebx
    jmp .tesp_dispatch_loop
.tesp_dispatch_done:
    mov edi,0x31; call emit_u8           # XOR eax,eax
    mov edi,0xC0; call emit_u8
    mov edi,0xC3; call emit_u8           # RET for invalid leaf index
    call support_reset_binding_seen
    mov qword ptr [rip+tensor_support_coord_shift],0
    mov rdi,qword ptr [rip+tensor_reduce_binding]
    mov rdi,qword ptr [rdi+40]
    call support_emit_terms
    test eax,eax
    jnz .tesp_regions_fail_pop
    mov eax,dword ptr [rip+tensor_support_emit_index]
    cmp eax,dword ptr [rip+tensor_support_count]
    jne .tesp_regions_fail_pop
    xor eax,eax
    pop r12
    pop rbx
    ret
.tesp_regions_none:
    xor eax,eax
    ret
.tesp_regions_fail_pop:
    mov eax,1
    pop r12
    pop rbx
    ret

.pushsection .bss
.p2align 3
tensor_support_mode:.skip 4
tensor_support_count:.skip 4
tensor_support_emit_index:.skip 4
tensor_support_negate:.skip 4
.p2align 3
tensor_support_predicate:.skip 8
tensor_support_basin:.skip 8
tensor_support_dispatch_base:.skip 8
tensor_support_halo_elems:.skip 8
tensor_support_coord_shift:.skip 8
tensor_binding_uses_ptr:.skip 8
tensor_binding_expanded_ptr:.skip 8
.popsection
