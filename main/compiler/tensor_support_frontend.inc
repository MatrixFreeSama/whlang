# Wheelchair Tensor SupportFact convergence.
# This authority derives execution support from ValueFact topology. Zero-false
# selects contribute contiguous primitive Regions; ADD/SUB compose their union.
# Runtime discovers exact IEEE boundaries, canonicalizes a source-sized RegionSet,
# and Physical Reality erases proven-zero subtrees without workload geometry.

.equ SUPPORT_NONE, 0
.equ SUPPORT_INTERVAL, 1
.equ SUPPORT_EMPTY, 2
.equ SUPPORT_SHAPE_CONST, 1
.equ SUPPORT_SHAPE_INC, 2
.equ SUPPORT_SHAPE_DEC, 3
.equ SUPPORT_SHAPE_BASIN, 4

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
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call tensor_domain_var_match
    test eax,eax
    jz .scs_unknown
    mov eax,1
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
    lea rsi,[rip+k_var]
    mov edx,k_var_end-k_var
    call obj_get
    test rax,rax
    jz .scs_cast_lit
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call tensor_domain_var_match
    test eax,eax
    jz .scs_unknown
    mov eax,1
    jmp .scs_done
.scs_cast_lit:
    mov rdi,r14
    call expr_literal_u64
    test edx,edx
    jnz .scs_unknown
    test rax,rax
    jz .scs_zero
    mov eax,1
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

    # The only nonconstant products admitted into a monotone class below this
    # point are affine-in-axis relations scaled/translated by axis-independent
    # facts. Equal slope signs therefore form one positive-leading quadratic
    # basin. Opposite signs are concave and are rejected.
    mov eax,dword ptr [rsp]
    mov edx,dword ptr [rsp+4]
    cmp eax,SUPPORT_SHAPE_INC
    jne .ssc_mul_both_dec
    cmp edx,SUPPORT_SHAPE_INC
    je .ssc_basin
    jmp .ssc_mul_const
.ssc_mul_both_dec:
    cmp eax,SUPPORT_SHAPE_DEC
    jne .ssc_mul_const
    cmp edx,SUPPORT_SHAPE_DEC
    je .ssc_basin
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
    jz .ssc_const
    test edx,edx
    js .ssc_scale_neg
    jmp .ssc_done
.ssc_scale_neg:
    cmp eax,SUPPORT_SHAPE_INC
    je .ssc_dec
    cmp eax,SUPPORT_SHAPE_DEC
    je .ssc_inc
    jmp .ssc_no                    # negative basin becomes two outer supports

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

    # LT/LE: shape(lhs) < constant(rhs).
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_lt]
    mov ecx,v_lt_end-v_lt
    call span_eq
    test eax,eax
    jnz .spl_lhs_shape
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_le]
    mov ecx,v_le_end-v_le
    call span_eq
    test eax,eax
    jnz .spl_lhs_shape
    # GT/GE: constant(lhs) > shape(rhs), the same sublevel topology.
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_gt]
    mov ecx,v_gt_end-v_gt
    call span_eq
    test eax,eax
    jnz .spl_rhs_shape
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_ge]
    mov ecx,v_ge_end-v_ge
    call span_eq
    test eax,eax
    jnz .spl_rhs_shape
    jmp .spl_no
.spl_lhs_shape:
    mov rdi,r15
    call support_shape_class
    cmp eax,SUPPORT_SHAPE_INC
    je .spl_lhs_ok
    cmp eax,SUPPORT_SHAPE_DEC
    je .spl_lhs_ok
    cmp eax,SUPPORT_SHAPE_BASIN
    jne .spl_no
.spl_lhs_ok:
    mov rdi,rbx
    call support_shape_class
    cmp eax,SUPPORT_SHAPE_CONST
    jne .spl_no
    mov qword ptr [rip+tensor_support_basin],r15
    jmp .spl_accept
.spl_rhs_shape:
    mov rdi,rbx
    call support_shape_class
    cmp eax,SUPPORT_SHAPE_INC
    je .spl_rhs_ok
    cmp eax,SUPPORT_SHAPE_DEC
    je .spl_rhs_ok
    cmp eax,SUPPORT_SHAPE_BASIN
    jne .spl_no
.spl_rhs_ok:
    mov rdi,r15
    call support_shape_class
    cmp eax,SUPPORT_SHAPE_CONST
    jne .spl_no
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

# support_count_terms(rdi=expr) -> eax=count, edx=1 proven RegionSet algebra;
# edx=0 means the expression support is not representable by this authority.
# Addition/subtraction use the conservative exact execution support union:
# supp(a +/- b) is a subset of supp(a) union supp(b). No cancellation is guessed.
support_count_terms:
    push rbx
    push r12
    push r13
    push r14
    mov r12,rdi
    call support_resolve_identity_load
    mov r12,rax

    # Literal +0 is the empty RegionSet. Other constants have full support and
    # therefore cannot contract the ShapeFact domain here.
    mov rdi,r12
    call expr_literal_f64_bits
    test edx,edx
    jnz .sct_op
    test rax,rax
    jnz .sct_unsupported
    xor eax,eax
    mov edx,1
    jmp .sct_done

.sct_op:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .sct_leaf
    mov r13,rax
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_add]
    mov ecx,v_add_end-v_add
    call span_eq
    test eax,eax
    jnz .sct_union
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_sub]
    mov ecx,v_sub_end-v_sub
    call span_eq
    test eax,eax
    jz .sct_leaf
.sct_union:
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .sct_unsupported
    mov r14,[rax+24]
    test r14,r14
    jz .sct_unsupported
    mov rbx,[r14+32]
    test rbx,rbx
    jz .sct_unsupported
    cmp qword ptr [rbx+32],0
    jne .sct_unsupported
    mov rdi,r14
    call support_count_terms
    test edx,edx
    jz .sct_unsupported
    mov r13d,eax
    mov rdi,rbx
    call support_count_terms
    test edx,edx
    jz .sct_unsupported
    add eax,r13d
    jc .sct_unsupported
    mov edx,1
    jmp .sct_done
.sct_leaf:
    mov rdi,r12
    call support_prepare_leaf
    test eax,eax
    jz .sct_unsupported
    mov eax,1
    mov edx,1
    jmp .sct_done
.sct_unsupported:
    xor eax,eax
    xor edx,edx
.sct_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# tensor_support_analyze_root(rdi=reduction expression).
# SupportFact is a canonical RegionSet algebra, not a one-interval mode. AOT
# proves an arbitrary source-derived union of contiguous leaf supports; runtime
# discovers their exact IEEE boundaries and canonicalizes overlap/adjacency.
tensor_support_analyze_root:
    push r12
    mov dword ptr [rip+tensor_support_mode],SUPPORT_NONE
    mov dword ptr [rip+tensor_support_count],0
    mov qword ptr [rip+tensor_support_predicate],0
    mov qword ptr [rip+tensor_support_basin],0
    mov r12,rdi
    call support_count_terms
    test edx,edx
    jz .tsa_regions_done
    test eax,eax
    jz .tsa_regions_empty
    # Scalar witness uses signed CVTSI2SD. Keep boundary discovery inside the
    # exact signed coordinate domain; this is a physical proof boundary.
    mov rcx,qword ptr [rip+tensor_shape_extent_max]
    test rcx,rcx
    js .tsa_regions_done
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
    mov dword ptr [rip+emit_gpr_mask],0x00000CC2  # RCX,RSI,RDI,R10,R11
    mov dword ptr [rip+emit_xmm_mask],0x00000FFC  # XMM2..XMM11; XMM0/1 reserved
    mov rdi,qword ptr [rip+tensor_support_basin]
    xor esi,esi
    call emit_float_reg
    test eax,eax
    jnz .tesl_fail
    mov rdi,qword ptr [rip+tensor_support_predicate]
    xor esi,esi
    call emit_int_reg
    test eax,eax
    jnz .tesl_fail
    # Preserve ordered IEEE semantics: LT/LE SETcc alone treats unordered as
    # below, so predicate result is masked with SETNP.
    mov edi,0x0F; call emit_u8
    mov edi,0x9B; call emit_u8          # SETNP dl
    mov edi,0xC2; call emit_u8
    mov edi,0x0F; call emit_u8
    mov edi,0xB6; call emit_u8          # MOVZX edx,dl
    mov edi,0xD2; call emit_u8
    mov edi,0x21; call emit_u8          # AND eax,edx
    mov edi,0xD0; call emit_u8
    mov edi,0xC3; call emit_u8          # RET
    xor eax,eax
    ret
.tesl_fail:
    mov eax,1
    ret

# support_emit_terms(rdi=expr) emits leaf witnesses in the same DFS order used
# by support_count_terms and patches the source-derived dispatcher entry.
support_emit_terms:
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
    jnz .set_op
    test rax,rax
    jz .set_ok                         # empty RegionSet contributes no leaf
    jmp .set_fail
.set_op:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .set_leaf
    mov r13,rax
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_add]
    mov ecx,v_add_end-v_add
    call span_eq
    test eax,eax
    jnz .set_union
    mov rdi,[r13+8]
    mov rsi,[r13+16]
    lea rdx,[rip+v_sub]
    mov ecx,v_sub_end-v_sub
    call span_eq
    test eax,eax
    jz .set_leaf
.set_union:
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .set_fail
    mov r14,[rax+24]
    test r14,r14
    jz .set_fail
    mov rbx,[r14+32]
    test rbx,rbx
    jz .set_fail
    cmp qword ptr [rbx+32],0
    jne .set_fail
    mov rdi,r14
    call support_emit_terms
    test eax,eax
    jnz .set_fail
    mov rdi,rbx
    call support_emit_terms
    jmp .set_done
.set_leaf:
    mov rdi,r12
    call support_prepare_leaf
    test eax,eax
    jz .set_fail
    # Patch this dispatcher's JE rel32 to the current leaf body.
    mov ecx,dword ptr [rip+tensor_support_emit_index]
    cmp ecx,dword ptr [rip+tensor_support_count]
    jae .set_fail
    mov rax,rcx
    imul rax,13
    mov rdx,qword ptr [rip+tensor_support_dispatch_base]
    lea rbx,[rdx+rax+9]                 # rel32 field
    lea r13,[rdx+rax+13]                # next instruction
    mov r14,qword ptr [rip+emit_ptr]
    sub r14,r13
    mov dword ptr [rbx],r14d
    inc dword ptr [rip+tensor_support_emit_index]
    call tensor_emit_support_leaf
    jmp .set_done
.set_ok:
    xor eax,eax
    jmp .set_done
.set_fail:
    mov eax,1
.set_done:
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
