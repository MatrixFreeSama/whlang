# One dynamic-ring range authority. rdi=c, rsi=signed d; eax=0
# reciprocal, 1 exact ring, 2 invalid; rdx=normalization multiple.
vec_periodic_range_class:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; xor r15d,r15d
    # A canonical Z/nZ CoordinateFact may carry a negative signed offset.
    # Choose the smallest compile-time k with k*n+d >= 0 for every admitted n.
    # Adding k*n does not change the residue; it only gives the reciprocal
    # materializer one non-negative physical representative.  This is a ring
    # normalization, not a special case for backward shifts.
    test r13,r13
    jns .vpr_affine_emit
    mov rax,r13
    neg rax
    jo .vpr_invalid
    mov rcx,qword ptr [rip+tensor_shape_extent_min]
    test rcx,rcx
    jz .vpr_invalid
    xor edx,edx
    div rcx                        # |d| / n_min
    test rdx,rdx
    jz .vpr_norm_k_ready
    inc rax
    jz .vpr_invalid
.vpr_norm_k_ready:
    mov r15,rax

.vpr_affine_emit:
    # Dynamic modulo has two physical realizations under one PeriodicAffineFact.
    # Keep the existing reciprocal path only when its strict exactness proof is
    # valid. Otherwise emit exact integer ring arithmetic before any affine hot
    # bytes are produced; physical precision must never become a source limit.
    mov rax,r12
    add rax,r15                    # effective non-negative coefficient bound
    jc .vpr_exact
    mov rcx,rax
    mul qword ptr [rip+tensor_shape_extent_max]
    test rdx,rdx
    jnz .vpr_exact
    test r15,r15
    jnz .vpr_recip_first_ready
    add rax,r13                    # positive d; negative d always has k>0
    jc .vpr_exact
.vpr_recip_first_ready:
    # The mature reciprocal quotient needs an exact integer conversion only
    # for its one-sided proof.  The bidirectional correction stays exact when
    # the signed binary64 quotient estimate is within one integer.  Prove that
    # from the physical range instead of rejecting the PeriodicAffineFact.
    # When n < 2^53 its scalar conversion is exact; x conversion, reciprocal
    # rounding and the multiply contribute three binary64 roundings.  Thus
    #   x < 2^63, n_max < 2^53, floor(x/n_min) < 2^52
    # gives |q_hat-q| < 2 under the conservative 4u relative-error bound.
    # Two bidirectional integer corrections close that bounded uncertainty.
    # Values outside the proof domain fall through to exact ring arithmetic.
    mov rdx,0x0020000000000000     # exact integer -> binary64 domain
    cmp rax,rdx
    jb .vpr_short
    # Unsigned conversion removes the artificial x<2^63 wall.  Bound the
    # quotient from the affine relation itself instead of combining incompatible
    # extrema x(n_max) and n_min: for 0<=i<n,
    #   floor((c*i + k*n + d)/n) < c+k+ceil(max(d,0)/n).
    mov rdx,qword ptr [rip+tensor_shape_extent_max]
    mov rcx,0x0020000000000000     # n < 2^53 => exact scalar binary64 n
    cmp rdx,rcx
    jae .vpr_exact
    mov rax,r12
    add rax,r15
    jc .vpr_exact
    test r13,r13
    jle .vpr_q_bound_ready
    mov rcx,qword ptr [rip+tensor_shape_extent_min]
    test rcx,rcx
    jz .vpr_exact
    mov rdx,r13
    dec rdx
    js .vpr_exact
    xor r8d,r8d
    # ceil(d/n_min) = 1 + floor((d-1)/n_min), d>0.
    mov r9,rax
    mov rax,rdx
    xor edx,edx
    div rcx
    inc rax
    add rax,r9
    jc .vpr_exact
.vpr_q_bound_ready:
    mov rdx,0x0010000000000000     # q_bound < 2^52 => 4u*q < 2
    cmp rax,rdx
    jae .vpr_exact
    jmp .vpr_short
.vpr_short:
    xor eax,eax; jmp .vpr_done
.vpr_exact:
    mov eax,1; jmp .vpr_done
.vpr_invalid:
    mov eax,2
.vpr_done:
    mov rdx,r15
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Count work of the existing realizations using shared physical ticks. Exact
# ring work follows the coefficient/offset bit graph, with no workload cutoff.
vec_periodic_key_ticks:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13,rsi; mov rbx,rdx
    xor eax,eax
    cmp r12,1; jne .vpkt_nonidentity
    test r13,r13; jnz .vpkt_nonidentity
    test rbx,rbx; jz .vpkt_done
.vpkt_nonidentity:
    mov ebx,PRC_INT_MUL_LOAD_AGU_TICKS+PRC_LOAD_AGU_TICKS+PRC_INT_ALU_TICKS
    cmp rdx,-1; jne .vpkt_value
    call vec_periodic_range_class
    test eax,eax; jnz .vpkt_ring
    add ebx,2*PRC_FP_CONV_TICKS+PRC_FP_MUL_TICKS+PRC_INT_MUL_TICKS+2*PRC_INT_ALU_TICKS
    jmp .vpkt_value
.vpkt_ring:
    xor ebx,ebx
    mov rdi,r12
    call vec_periodic_bit_work
    add ebx,eax
    mov rdi,r13
    test rdi,rdi; jns .vpkt_offset
    neg rdi
.vpkt_offset:
    call vec_periodic_bit_work
    add ebx,eax
    mov ecx,3*PRC_INT_ALU_TICKS
    mov rax,0x8000000000000000
    cmp rax,qword ptr [rip+tensor_shape_extent_max]; jae .vpkt_ring_ticks
    mov ecx,7*PRC_INT_ALU_TICKS
.vpkt_ring_ticks:
    imul ebx,ecx
    add ebx,2*PRC_LOAD_AGU_TICKS
.vpkt_value:
    mov eax,ebx
.vpkt_done:
    pop r13; pop r12; pop rbx; ret

vec_periodic_bit_work:
    xor eax,eax
    test rdi,rdi; jz .vpbw_done
    bsr rcx,rdi
    mov eax,ecx                  # squarings = bit length - 1
.vpbw_ones:
    lea rcx,[rdi-1]; and rdi,rcx; inc eax
    test rdi,rdi; jnz .vpbw_ones
.vpbw_done:
    ret

