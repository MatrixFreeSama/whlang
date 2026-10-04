# Exact integer realization for one canonical PeriodicAffineFact over the
# runtime modulus carried in vector register 7.  This authority is shared by
# base/derived and AVX-512/AVX2 frontends.  It exists only as a physical
# realization of the existing CoordinateFact; no source-visible mode or
# secondary semantic path is introduced.
#
# vec_modadd_n(edi=dst, esi=a, edx=b) -> eax=0/1
# Preconditions: every lane satisfies 0 <= a,b < n and n > 0.
# Computes (a+b) mod n without overflow by selecting between:
#   b-(n-a)            when b >= n-a
#   a+b                otherwise
# The non-selected sum may wrap, but the selected candidate never does.
vec_modadd_n:
    # Reduced a,b<n with n<=2^63 imply a+b<2^64. In that proved domain the
    # exact ring add contracts to add, subtract-n, unsigned-min. Wider extents
    # retain the overflow-safe realization below under the same authority.
    mov rax,qword ptr [rip+tensor_shape_extent_max]
    mov rcx,0x8000000000000000
    cmp rax,rcx
    ja .vman_full_u64
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    call vec_alloc
    cmp eax,-1
    je .vman_short_fail
    mov r14d,eax
    # dst = a+b (proved non-wrapping)
    mov edi,0xD4; mov esi,ebx; mov edx,r12d; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr
    # tmp = dst-n; wraps to a large unsigned value iff dst<n.
    mov edi,0xFB; mov esi,r14d; mov edx,ebx; mov ecx,7; mov r8d,1
    call vec_vex2_rrr
    # dst = min_u(dst,tmp) = (a+b) mod n.
    mov edi,ebx; mov esi,ebx; mov edx,ebx; mov ecx,r14d
    call vec_vpminuq
    push rax
    mov edi,r14d; call vec_free
    pop rax
    test eax,eax
    jnz .vman_short_fail_after_free
    xor eax,eax
    jmp .vman_short_done
.vman_short_fail:
    mov eax,1
    jmp .vman_short_done
.vman_short_fail_after_free:
    mov eax,1
.vman_short_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.vman_full_u64:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx

    call vec_alloc
    cmp eax,-1
    je .vman_fail
    mov r14d,eax                    # t / selected-true candidate
    call vec_alloc
    cmp eax,-1
    je .vman_free_t_fail
    mov r15d,eax                    # predicate mask

    # t = n-a. Since a<n, t is in 1..n and cannot underflow.
    mov edi,0xFB; mov esi,r14d; mov edx,7; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr

    # mask = (b >= t) from the profile's exact unsigned PredicateFact.
    mov edi,r15d; mov esi,r13d; mov edx,r14d
    call vec_cmp_ge_u64_maskvec
    test eax,eax
    jnz .vman_free_all_fail

    # t = b-(n-a), the reduced candidate for mask=true.
    mov edi,0xFB; mov esi,r14d; mov edx,r13d; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr
    # dst = a+b. It may wrap only when mask=true, where it is discarded.
    mov edi,0xD4; mov esi,ebx; mov edx,r12d; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr

    # dst = (mask & t) | (~mask & dst). Two transient facts suffice even when
    # dst aliases a and/or b because both candidates are complete first.
    mov edi,0xDB; mov esi,r14d; mov edx,r14d; mov ecx,r15d; mov r8d,1
    call vec_vex2_rrr
    mov edi,0xDF; mov esi,ebx; mov edx,r15d; mov ecx,ebx; mov r8d,1
    call vec_vex2_rrr
    mov edi,0xEB; mov esi,ebx; mov edx,ebx; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr

    xor eax,eax
    jmp .vman_free_all
.vman_free_all_fail:
    mov eax,1
.vman_free_all:
    push rax
    mov edi,r15d; call vec_free
    mov edi,r14d; call vec_free
    pop rax
    jmp .vman_done
.vman_free_t_fail:
    mov edi,r14d; call vec_free
.vman_fail:
    mov eax,1
.vman_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_modsub_n(edi=dst, esi=a, edx=b) -> eax=0/1
# Preconditions: every lane satisfies 0 <= a,b < n and n > 0.
# Computes (a-b) mod n without overflow.
vec_modsub_n:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx

    call vec_alloc
    cmp eax,-1
    je .vmsn_fail
    mov r14d,eax                    # t / false candidate
    call vec_alloc
    cmp eax,-1
    je .vmsn_free_t_fail
    mov r15d,eax                    # predicate mask

    # mask = (a >= b) unsigned.
    mov edi,r15d; mov esi,r12d; mov edx,r13d
    call vec_cmp_ge_u64_maskvec
    test eax,eax
    jnz .vmsn_free_all_fail

    # t = n-(b-a), valid when a<b.
    mov edi,0xFB; mov esi,r14d; mov edx,r13d; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    mov edi,0xFB; mov esi,r14d; mov edx,7; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr
    # dst = a-b, valid when a>=b. Inputs are consumed only after t is complete.
    mov edi,0xFB; mov esi,ebx; mov edx,r12d; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr

    mov edi,0xDB; mov esi,ebx; mov edx,ebx; mov ecx,r15d; mov r8d,1
    call vec_vex2_rrr
    mov edi,0xDF; mov esi,r14d; mov edx,r15d; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr
    mov edi,0xEB; mov esi,ebx; mov edx,ebx; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr

    xor eax,eax
    jmp .vmsn_free_all
.vmsn_free_all_fail:
    mov eax,1
.vmsn_free_all:
    push rax
    mov edi,r15d; call vec_free
    mov edi,r14d; call vec_free
    pop rax
    jmp .vmsn_done
.vmsn_free_t_fail:
    mov edi,r14d; call vec_free
.vmsn_fail:
    mov eax,1
.vmsn_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_vcvtuqq2pd_exact(edi=dst,esi=src) -> eax=0/1
# Exact correctly-rounded unsigned-u64 vector -> f64 vector.  The identity
#   u64_to_f64(x) = 2 * i64_to_f64((x>>1) | (x&1))
# removes the signed-conversion boundary without scalar lanes or a second IR.
vec_vcvtuqq2pd_exact:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    call vec_alloc
    cmp eax,-1
    je .vcuq_fail
    mov r13d,eax
    # temp = x >> 1
    mov edi,r13d; mov esi,r12d; mov edx,1
    call vec_vpsrlq_imm
    test eax,eax
    jnz .vcuq_free_fail
    # dst = x & 1
    mov rsi,1
    call vec_const_intern
    cmp eax,-1
    je .vcuq_free_fail
    mov edx,eax
    mov edi,ebx; mov esi,r12d
    call vec_vpandq_mem_const
    test eax,eax
    jnz .vcuq_free_fail
    # temp |= lowbit
    mov edi,0xEB; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1
    call vec_vex2_rrr
    # signed conversion is now valid because temp <= 2^63-1.
    mov edi,ebx; mov esi,r13d
    call vec_vcvtqq2pd
    test eax,eax
    jnz .vcuq_free_fail
    # exact multiplication by two in binary floating point.
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,ebx; mov r8d,1
    call vec_vex2_rrr
    push rax
    mov edi,r13d; call vec_free
    pop rax
    test eax,eax
    jnz .vcuq_fail_after_free
    xor eax,eax
    jmp .vcuq_done
.vcuq_free_fail:
    mov edi,r13d; call vec_free
.vcuq_fail_after_free:
.vcuq_fail:
    mov eax,1
.vcuq_done:
    pop r13
    pop r12
    pop rbx
    ret

# vec_emit_reciprocal_mod_wide(edi=value) -> eax=0/1
# Preconditions: value is a non-negative signed-u64 representative in every
# lane; vector register 7 is n and 15 is the runtime 1/n double Fact. The
# frontend proves the binary64 quotient estimate differs from floor(value/n)
# by at most two. Two exact integer corrections on each side close that bounded
# uncertainty; this is one reciprocal realization, not a depth/workload route.
vec_emit_reciprocal_mod_wide:
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi
    call vec_alloc
    cmp eax,-1
    je .vrmw_fail
    mov r12d,eax                   # quotient product p / low correction
    call vec_alloc
    cmp eax,-1
    je .vrmw_free_p_fail
    mov r13d,eax                   # x>=p predicate
    call vec_alloc
    cmp eax,-1
    je .vrmw_free_pm_fail
    mov r14d,eax                   # p-n candidate

    mov edi,r12d; mov esi,ebx; call vec_vcvtuqq2pd_exact
    mov edi,0x59; mov esi,r12d; mov edx,r12d; mov ecx,15; mov r8d,1
    call vec_vex2_rrr
    mov edi,r12d; mov esi,r12d; call vec_trunc_nonneg_pd_to_u64
    mov edi,r12d; mov esi,r12d; mov edx,r12d; mov ecx,7
    call vec_vpmullq               # p = q_hat*n

    # q_hat may be at most two high. Move p down by n only when p>x, twice.
    mov ecx,2
.vrmw_high_loop:
    push rcx
    mov edi,r13d; mov esi,ebx; mov edx,r12d
    call vec_cmp_ge_u64_maskvec    # mask = x>=p
    test eax,eax
    jnz .vrmw_high_fail_pop
    mov edi,0xFB; mov esi,r14d; mov edx,r12d; mov ecx,7; mov r8d,1
    call vec_vex2_rrr              # candidate = p-n
    mov edi,0xDB; mov esi,r12d; mov edx,r12d; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr              # p &= mask
    mov edi,0xDF; mov esi,r14d; mov edx,r13d; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr              # candidate &= ~mask
    mov edi,0xEB; mov esi,r12d; mov edx,r12d; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr              # p = select(mask,p,p-n)
    pop rcx
    dec ecx
    jnz .vrmw_high_loop

    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr              # r = x-p, now non-wrapped

    # q_hat may be at most two low. Each unsigned min performs one exact
    # conditional subtraction of n; two rounds close r in [0,n).
    mov ecx,2
.vrmw_low_loop:
    push rcx
    mov edi,0xFB; mov esi,r12d; mov edx,ebx; mov ecx,7; mov r8d,1
    call vec_vex2_rrr              # candidate = r-n (wraps when r<n)
    mov edi,ebx; mov esi,ebx; mov edx,ebx; mov ecx,r12d
    call vec_vpminuq
    test eax,eax
    jnz .vrmw_low_fail_pop
    pop rcx
    dec ecx
    jnz .vrmw_low_loop

    xor eax,eax
    jmp .vrmw_free_all
.vrmw_high_fail_pop:
    pop rcx
    jmp .vrmw_free_all_fail
.vrmw_low_fail_pop:
    pop rcx
.vrmw_free_all_fail:
    mov eax,1
.vrmw_free_all:
    push rax
    mov edi,r14d; call vec_free
    mov edi,r13d; call vec_free
    mov edi,r12d; call vec_free
    pop rax
    jmp .vrmw_done
.vrmw_free_pm_fail:
    mov edi,r13d; call vec_free
.vrmw_free_p_fail:
    mov edi,r12d; call vec_free
.vrmw_fail:
    mov eax,1
.vrmw_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_emit_u64_literal_mod_n(edi=dst,rsi=value) -> eax=0/1
# Emit one runtime vector containing value mod n for an arbitrary compile-time
# u64 literal. This is initialization authority for periodic induction steps;
# all runtime intermediates remain in [0,n), so the literal width never leaks
# into source semantics.
vec_emit_u64_literal_mod_n:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12,rsi
    call vec_alloc
    cmp eax,-1
    je .veulm_fail
    mov r13d,eax

    mov edi,ebx
    xor esi,esi
    call vec_broadcast_imm64
    test eax,eax
    jnz .veulm_free_fail
    mov edi,r13d
    mov esi,1
    call vec_broadcast_imm64
    test eax,eax
    jnz .veulm_free_fail
    cmp qword ptr [rip+tensor_shape_extent_min],1
    ja .veulm_pow_ready
    # 1 mod n, including n=1.
    call vec_alloc
    cmp eax,-1
    je .veulm_free_fail
    push r14
    mov r14d,eax
    mov edi,0xFB; mov esi,r14d; mov edx,r13d; mov ecx,7; mov r8d,1
    call vec_vex2_rrr
    mov edi,r13d; mov esi,r13d; mov edx,r13d; mov ecx,r14d
    call vec_vpminuq
    push rax
    mov edi,r14d; call vec_free
    pop rax
    pop r14
    test eax,eax
    jnz .veulm_free_fail
.veulm_pow_ready:
    test r12,r12
    jz .veulm_ok
.veulm_loop:
    test r12b,1
    jz .veulm_no_add
    mov edi,ebx; mov esi,ebx; mov edx,r13d
    call vec_modadd_n
    test eax,eax
    jnz .veulm_free_fail
.veulm_no_add:
    shr r12,1
    jz .veulm_ok
    mov edi,r13d; mov esi,r13d; mov edx,r13d
    call vec_modadd_n
    test eax,eax
    jnz .veulm_free_fail
    jmp .veulm_loop
.veulm_ok:
    mov edi,r13d
    call vec_free
    xor eax,eax
    jmp .veulm_done
.veulm_free_fail:
    mov edi,r13d
    call vec_free
.veulm_fail:
    mov eax,1
.veulm_done:
    pop r13
    pop r12
    pop rbx
    ret

# vec_emit_periodic_exact(edi=dst, rsi=c, rdx=signed d) -> eax=0/1
# Emits exactly (c*x+d) mod n from the physical root vector 6 and runtime
# modulus vector 7.  Binary modular accumulation keeps every live lane in
# [0,n), so neither host u64 overflow nor FP reciprocal precision can become a
# source-language limit.  The coefficient/offset bits are compile-time facts;
# the generated runtime contains no data-dependent algorithm selector.
vec_emit_periodic_exact:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12,rsi                    # c
    mov r13,rdx                    # signed d

    call vec_alloc
    cmp eax,-1
    je .vpex_fail
    mov r14d,eax                   # modular power/base

    # result = 0; base = physical root x (already canonical 0..n-1).
    mov edi,ebx
    xor esi,esi
    call vec_broadcast_imm64
    test eax,eax
    jnz .vpex_free_base_fail
    mov edi,r14d
    mov esi,6
    call vec_mov_ext
    test eax,eax
    jnz .vpex_free_base_fail

    # result += c*x by binary modular multiplication.
    mov r15,r12
.vpex_c_loop:
    test r15,r15
    jz .vpex_c_done
    test r15b,1
    jz .vpex_c_no_add
    mov edi,ebx; mov esi,ebx; mov edx,r14d
    call vec_modadd_n
    test eax,eax
    jnz .vpex_free_base_fail
.vpex_c_no_add:
    shr r15,1
    jz .vpex_c_done
    mov edi,r14d; mov esi,r14d; mov edx,r14d
    call vec_modadd_n
    test eax,eax
    jnz .vpex_free_base_fail
    jmp .vpex_c_loop
.vpex_c_done:

    test r13,r13
    jz .vpex_ok

    # base = 1 mod n.  The unsigned-min correction is exact for the single
    # literal 1 for every n>0, including n=1.
    mov edi,r14d
    mov esi,1
    call vec_broadcast_imm64
    test eax,eax
    jnz .vpex_free_base_fail
    cmp qword ptr [rip+tensor_shape_extent_min],1
    ja .vpex_d_pow_ready
    call vec_alloc
    cmp eax,-1
    je .vpex_free_base_fail
    mov ebp,eax
    mov edi,0xFB; mov esi,ebp; mov edx,r14d; mov ecx,7; mov r8d,1
    call vec_vex2_rrr              # temp = 1-n
    mov edi,r14d; mov esi,r14d; mov edx,r14d; mov ecx,ebp
    call vec_vpminuq               # 1%n = min_u(1,1-n)
    push rax
    mov edi,ebp; call vec_free
    pop rax
    test eax,eax
    jnz .vpex_free_base_fail
.vpex_d_pow_ready:

    # |d| as an unsigned magnitude. NEG of INT64_MIN deliberately leaves
    # 0x8000... which is its exact magnitude in u64.
    xor ebp,ebp                    # 0 positive, 1 negative
    mov r15,r13
    test r15,r15
    jns .vpex_d_mag_ready
    mov ebp,1
    neg r15
.vpex_d_mag_ready:
.vpex_d_loop:
    test r15,r15
    jz .vpex_ok
    test r15b,1
    jz .vpex_d_no_add
    test ebp,ebp
    jnz .vpex_d_sub
    mov edi,ebx; mov esi,ebx; mov edx,r14d
    call vec_modadd_n
    jmp .vpex_d_applied
.vpex_d_sub:
    mov edi,ebx; mov esi,ebx; mov edx,r14d
    call vec_modsub_n
.vpex_d_applied:
    test eax,eax
    jnz .vpex_free_base_fail
.vpex_d_no_add:
    shr r15,1
    jz .vpex_ok
    mov edi,r14d; mov esi,r14d; mov edx,r14d
    call vec_modadd_n
    test eax,eax
    jnz .vpex_free_base_fail
    jmp .vpex_d_loop

.vpex_ok:
    mov edi,r14d
    call vec_free
    xor eax,eax
    jmp .vpex_done
.vpex_free_base_fail:
    mov edi,r14d
    call vec_free
.vpex_fail:
    mov eax,1
.vpex_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
