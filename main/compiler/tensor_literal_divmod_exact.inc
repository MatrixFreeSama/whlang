# Shared ConstantFact/RangeFact physical division authority.
# r8 is a conservative upper bound on every input lane.
# recip_u64_down_f64_bits(rax=positive u64 <2^48) -> reciprocal bits, edx=0.
# One ulp is deliberately subtracted so the estimate cannot overshoot floor(x/d).
recip_u64_down_f64_bits:
    test rax,rax; jz .rudf_fail
    mov rcx,0x0001000000000000
    cmp rax,rcx; jae .rudf_fail
    cvtsi2sd xmm0,rax
    mov rdx,0x3ff0000000000000
    movq xmm1,rdx
    divsd xmm1,xmm0
    movq rax,xmm1
    test rax,rax; jz .rudf_fail
    dec rax
    xor edx,edx
    ret
.rudf_fail:
    xor eax,eax; mov edx,1; ret

.if TENSOR_PHYSICAL_LANES == 8
# EVEX vpmuludq zmm dst,src1,QWORD BCST [rip+const].
# AVX-512F unsigned low-dword multiply widened to qword.  This is the native
# exact primitive for proven-u32 constant division: values are already known
# to have zero high dwords, so no lane conversion or floating reciprocal exists.
# edi=dst, esi=src1, edx=constant-pool index -> eax=0/1.
vec_vpmuludq_mem_const:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+10]
    cmp rcx,[rip+vec_emit_end]
    jbe .vpmudqmc_space_ok
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmudqmc_fail
.vpmudqmc_space_ok:
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .vpmudqmc_fixup_ok
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmudqmc_fail
.vpmudqmc_fixup_ok:
    push rax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    # P0: dst R/R', memory X/B=1, map=0F(1).
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    # P1: W=1, ~src1.vvvv, pp=66h. P2: 512-bit + qword broadcast.
    mov eax,r12d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x50
    mov edi,eax; call vec_emit_u8
    mov edi,0xF4; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call vec_emit_u8
    pop rax
    mov r8,qword ptr [rip+tensor_fixup_ptr_base]
    mov rcx,[rip+vec_emit_ptr]
    mov qword ptr [r8+rax*8],rcx
    mov r8,qword ptr [rip+tensor_fixup_const_base]
    mov dword ptr [r8+rax*4],r13d
    lea r8,[rcx+4]
    cmp r8,[rip+vec_emit_end]
    jbe .vpmudqmc_disp_ok
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmudqmc_fail_nostack
.vpmudqmc_disp_ok:
    mov dword ptr [rcx],0
    mov [rip+vec_emit_ptr],r8
    inc dword ptr [rip+schedule_counts+4*5]
    inc dword ptr [rip+schedule_counts+4*7]
    inc dword ptr [rip+schedule_counts+4*8]
    xor eax,eax
    jmp .vpmudqmc_done
.vpmudqmc_fail:
    mov eax,1
    jmp .vpmudqmc_done
.vpmudqmc_fail_nostack:
    mov eax,1
.vpmudqmc_done:
    pop r13
    pop r12
    pop rbx
    ret

.endif
# vec_udivmod_literal_exact(edi=dst,esi=src,rdx=nonzero divisor,ecx=0 quotient/1 remainder)
# Exact constant-radix integer division for Rank-N coordinate recovery. The
# derived physical domain is proven <2^48. A downward reciprocal is therefore
# at most one quotient low; exact integer remainder correction closes that gap.
vec_udivmod_literal_exact:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12d,esi; mov r13,rdx; mov r14d,ecx
    test r13,r13; jz .vudm_fail
    cmp r13,1; jne .vudm_range
    test r14d,r14d; jz .vudm_identity
    xor esi,esi; call vec_const_intern
    cmp eax,-1; je .vudm_fail
    mov edx,eax; mov edi,ebx; mov esi,r12d; call vec_vpandq_mem_const
    jmp .vudm_done
.vudm_identity:
    mov edi,ebx; mov esi,r12d; call vec_mov_ext
    jmp .vudm_done
.vudm_range:
    .if TENSOR_PHYSICAL_LANES == 8
    # A proven-u32 physical domain admits an exact integer reciprocal relation:
    #   m=floor(2^32/d), q0=high32(x*m), q=q0+[r>=d], r=x-q0*d.
    # q0 is never more than one low for x<2^32.  The correction is therefore
    # one add/shift, with no int<->fp conversion and no runtime selector.
    mov rax,r8
    mov rcx,0x100000000
    cmp rax,rcx
    jae .vudm_wide_domain
    mov rax,r13
    shr rax,32
    jnz .vudm_wide_domain
    mov edi,ebx
    mov esi,r12d
    mov rdx,r13
    mov ecx,r14d
    call vec_udivmod_literal_u32_exact
    jmp .vudm_done
.vudm_wide_domain:
    .endif
    mov rax,r8
    mov rcx,0x0001000000000000
    cmp rax,rcx; jae .vudm_fail
    mov rax,r13; call recip_u64_down_f64_bits
    test edx,edx; jnz .vudm_fail
    mov rsi,rax; call vec_const_intern
    cmp eax,-1; je .vudm_fail
    mov r15d,eax                    # reciprocal pool; callee-saved authority
    mov rsi,r13; call vec_const_intern
    cmp eax,-1; je .vudm_fail
    push rax                        # divisor pool
    mov rax,r13; neg rax; mov rsi,rax; call vec_const_intern
    cmp eax,-1; je .vudm_fail_pop1
    push rax                        # -divisor pool
    mov rsi,0x3fe0000000000000; call vec_const_intern
    cmp eax,-1; je .vudm_fail_pop2
    push rax                        # 0.5 pool

    # Two physical temporaries are sufficient. The quotient-product carrier is
    # dead immediately after r=x-q*d is formed, so the same carrier becomes the
    # r-d correction. This is lifetime compression inside the existing allocator,
    # not a wider register budget. Register identities live in stack-owned
    # compiler state because emitter helpers freely clobber caller-saved GPRs.
    sub rsp,16
    mov qword ptr [rsp],-1          # original x register id
    mov qword ptr [rsp+8],-1        # q/product -> correction register id
    call vec_alloc; cmp eax,-1; je .vudm_cleanup_fail
    mov dword ptr [rsp],eax
    call vec_alloc; cmp eax,-1; je .vudm_cleanup_fail
    mov dword ptr [rsp+8],eax

    mov edi,dword ptr [rsp]; mov esi,r12d; call vec_mov_ext
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp]; call vec_mov_ext
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_vcvtuqq2pd
    test eax,eax; jnz .vudm_cleanup_fail
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; mov edx,r15d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vudm_cleanup_fail
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_trunc_nonneg_pd_to_u64
    test eax,eax; jnz .vudm_cleanup_fail
    mov edx,dword ptr [rsp+32]      # divisor pool
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_vpmullq_mem_const
    test eax,eax; jnz .vudm_cleanup_fail

    # r = x - q*d in the caller-owned destination. Reuse the dead q*d carrier
    # for the one-step exact remainder correction.
    mov edi,0xFB; mov esi,ebx; mov edx,dword ptr [rsp]; mov ecx,dword ptr [rsp+8]; mov r8d,1; call vec_vex2_rrr
    mov edi,dword ptr [rsp+8]; mov esi,ebx; call vec_mov_ext
    mov edx,dword ptr [rsp+24]      # -divisor pool
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_vpaddq_mem_const
    test eax,eax; jnz .vudm_cleanup_fail
    mov edi,ebx; mov esi,ebx; mov edx,ebx; mov ecx,dword ptr [rsp+8]; call vec_vpminuq
    test r14d,r14d; jnz .vudm_cleanup_success

    # y=x-r is exactly divisible by d. The downward reciprocal is within 0.5
    # of the exact integral quotient over the proven <2^48 domain.
    mov edi,0xFB; mov esi,dword ptr [rsp]; mov edx,dword ptr [rsp]; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; call vec_vcvtuqq2pd
    test eax,eax; jnz .vudm_cleanup_fail
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; mov edx,r15d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vudm_cleanup_fail
    mov edx,dword ptr [rsp+16]      # 0.5 pool
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; call vec_vaddpd_mem_const
    test eax,eax; jnz .vudm_cleanup_fail
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; call vec_trunc_nonneg_pd_to_u64
    test eax,eax; jnz .vudm_cleanup_fail
    mov edi,ebx; mov esi,dword ptr [rsp]; call vec_mov_ext

.vudm_cleanup_success:
    mov edi,dword ptr [rsp+8]; call vec_free
    mov edi,dword ptr [rsp]; call vec_free
    add rsp,40
    xor eax,eax; jmp .vudm_done
.vudm_cleanup_fail:
    mov eax,dword ptr [rsp+8]; cmp eax,-1; je 1f; mov edi,eax; call vec_free
1:  mov eax,dword ptr [rsp]; cmp eax,-1; je 2f; mov edi,eax; call vec_free
2:  add rsp,40
    mov eax,1; jmp .vudm_done
.vudm_fail_pop2: add rsp,8
.vudm_fail_pop1: add rsp,8
.vudm_fail: mov eax,1
.vudm_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx
    ret

.if TENSOR_PHYSICAL_LANES == 8
# Exact constant div/mod for a compile-time-proven u32 value domain.
# edi=dst, esi=src, rdx=1..2^32-1 divisor, ecx=0 quotient / 1 remainder.
# This is one algebraic realization, not a workload path: every literal radix
# in the proven domain shares the same relation.
vec_udivmod_literal_u32_exact:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12d,esi
    mov r13,rdx
    mov r14d,ecx

    # Intern m=floor(2^32/d), d, -d, and correction bias 2^32-d.
    mov rax,0x100000000
    xor edx,edx
    div r13
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1; je .vud32_fail
    mov r15d,eax                    # reciprocal-multiply pool
    mov rsi,r13
    call vec_const_intern
    cmp eax,-1; je .vud32_fail
    push rax                        # divisor pool
    mov rax,r13
    neg rax
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1; je .vud32_fail_pop1
    push rax                        # -divisor pool
    mov rax,0x100000000
    sub rax,r13
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1; je .vud32_fail_pop2
    push rax                        # correction-bias pool

    # Two compiler-owned physical temporaries: q0 and product/correction.
    sub rsp,16
    mov qword ptr [rsp],-1
    mov qword ptr [rsp+8],-1
    call vec_alloc
    cmp eax,-1; je .vud32_cleanup_fail
    mov dword ptr [rsp],eax
    call vec_alloc
    cmp eax,-1; je .vud32_cleanup_fail
    mov dword ptr [rsp+8],eax

    # q0 = high32(low32(x) * floor(2^32/d)).  x is proven <2^32.
    mov edi,dword ptr [rsp]
    mov esi,r12d
    call vec_mov_ext
    mov edi,dword ptr [rsp]
    mov esi,dword ptr [rsp]
    mov edx,r15d
    call vec_vpmuludq_mem_const
    test eax,eax; jnz .vud32_cleanup_fail
    mov edi,dword ptr [rsp]
    mov esi,dword ptr [rsp]
    mov edx,32
    call vec_vpsrlq_imm

    # product=q0*d; r=x-product in destination.
    mov edi,dword ptr [rsp+8]
    mov esi,dword ptr [rsp]
    call vec_mov_ext
    mov edx,dword ptr [rsp+32]      # divisor pool
    mov edi,dword ptr [rsp+8]
    mov esi,dword ptr [rsp+8]
    call vec_vpmuludq_mem_const
    test eax,eax; jnz .vud32_cleanup_fail
    mov edi,0xFB
    mov esi,ebx
    mov edx,r12d
    mov ecx,dword ptr [rsp+8]
    mov r8d,1
    call vec_vex2_rrr               # dst = x - product

    test r14d,r14d
    jz .vud32_quotient

    # Exact remainder: q0 is exact or one low, so r<2d. min(r,r-d) corrects it.
    mov edi,dword ptr [rsp+8]
    mov esi,ebx
    call vec_mov_ext
    mov edx,dword ptr [rsp+24]      # -divisor pool
    mov edi,dword ptr [rsp+8]
    mov esi,dword ptr [rsp+8]
    call vec_vpaddq_mem_const
    test eax,eax; jnz .vud32_cleanup_fail
    mov edi,ebx
    mov esi,ebx
    mov edx,ebx
    mov ecx,dword ptr [rsp+8]
    call vec_vpminuq
    jmp .vud32_cleanup_success

.vud32_quotient:
    # carry = high32(r + 2^32-d): 0 exactly when r<d, otherwise 1.
    mov edi,dword ptr [rsp+8]
    mov esi,ebx
    call vec_mov_ext
    mov edx,dword ptr [rsp+16]      # correction-bias pool
    mov edi,dword ptr [rsp+8]
    mov esi,dword ptr [rsp+8]
    call vec_vpaddq_mem_const
    test eax,eax; jnz .vud32_cleanup_fail
    mov edi,dword ptr [rsp+8]
    mov esi,dword ptr [rsp+8]
    mov edx,32
    call vec_vpsrlq_imm
    mov edi,0xD4
    mov esi,ebx
    mov edx,dword ptr [rsp]
    mov ecx,dword ptr [rsp+8]
    mov r8d,1
    call vec_vex2_rrr               # dst = q0 + carry

.vud32_cleanup_success:
    mov edi,dword ptr [rsp+8]; call vec_free
    mov edi,dword ptr [rsp]; call vec_free
    add rsp,40
    xor eax,eax
    jmp .vud32_done
.vud32_cleanup_fail:
    mov eax,dword ptr [rsp+8]; cmp eax,-1; je 1f; mov edi,eax; call vec_free
1:  mov eax,dword ptr [rsp]; cmp eax,-1; je 2f; mov edi,eax; call vec_free
2:  add rsp,40
    mov eax,1
    jmp .vud32_done
.vud32_fail_pop2:
    add rsp,8
.vud32_fail_pop1:
    add rsp,8
.vud32_fail:
    mov eax,1
.vud32_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endif
