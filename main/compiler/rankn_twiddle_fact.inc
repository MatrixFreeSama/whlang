.text
# rdi=tw, rsi=m, rdx=len, ecx=inv(0 fwd / 1 inv)
# Extended-precision recurrence with periodic renormalization; no libm/runtime planner.
g_rankn_make_tw:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    sub rsp,96
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15d,ecx
    mov [rsp+0],rdx
    # One exact base-angle seed.  The fast binary64 recurrence below is
    # periodically re-anchored with x87 FSINCOS, so phase error cannot walk.
    fldpi
    fadd st(0),st(0)
    fild qword ptr [rsp+0]
    fdivp st(1),st(0)
    test r15d,r15d
    jnz .rpf_nmtf_sign_ok
    fchs
.rpf_nmtf_sign_ok:
    fstp tbyte ptr [rsp+16]                 # signed base angle
    fld tbyte ptr [rsp+16]
    fsincos
    fstp qword ptr [rsp+32]                 # wr
    fstp qword ptr [rsp+40]                 # wi
    vmovsd xmm2,[rsp+32]
    vmovsd xmm3,[rsp+40]
    # j=0 is the exact unit twiddle.  Do not ask x87 to rediscover (1,0).
    mov rax,0x3ff0000000000000
    vmovq xmm0,rax
    vxorpd xmm1,xmm1,xmm1
    xor ebx,ebx
.rpf_nmtf_loop:
    cmp rbx,r13
    jae .rpf_nmtf_done
    # Re-anchor every 16 nonzero values from j*base_angle using x87 extended input.
    test rbx,rbx
    jz .rpf_nmtf_have_phase
    test bl,15
    jnz .rpf_nmtf_have_phase
    mov [rsp+8],rbx
    fild qword ptr [rsp+8]
    fld tbyte ptr [rsp+16]
    fmulp st(1),st(0)
    fsincos
    fstp qword ptr [rsp+48]                 # cr
    fstp qword ptr [rsp+56]                 # ci
    vmovsd xmm0,[rsp+48]
    vmovsd xmm1,[rsp+56]
.rpf_nmtf_have_phase:
    mov rax,rbx
    shl rax,4
    vmovsd [r12+rax],xmm0
    vmovsd [r12+rax+8],xmm1
    # (cr+i ci) *= (wr+i wi), all in registers.
    vmulsd xmm4,xmm0,xmm2
    vmulsd xmm5,xmm1,xmm3
    vsubsd xmm4,xmm4,xmm5                  # nr
    vmulsd xmm6,xmm0,xmm3
    vmulsd xmm5,xmm1,xmm2
    vaddsd xmm6,xmm6,xmm5                  # ni
    vmovapd xmm0,xmm4
    vmovapd xmm1,xmm6
    inc rbx
    jmp .rpf_nmtf_loop
.rpf_nmtf_done:
    add rsp,96
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret


# rdi=type -> mark this type's Fourier constant capability as reachable.
g_require_rankn_twiddles:
    mov eax,edi
    sub eax,GTYPE_RANKN_FP_BASE
    imul rax,rax,RPF_FACT_BYTES
    add rax,[rip+g_rankn_type_facts_ptr]
    mov qword ptr [rax+RPF_FACT_TW_REQUIRED],1
    ret

# rdi=output pointer or zero for measurement, rsi=fact, edx=direction.
# Forward stages are 5/3/2; inverse stages are 2/3/5. One parameterized
# relation materializes exactly the immutable stage constants that are used.
# Returns rax=bytes. Only the compiler executes this construction.
g_rankn_twiddle_direction:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi; mov r15,rsi
    mov [rsp+8],rdi
    mov [rsp+16],edx
    mov qword ptr [rsp],0
    mov r14,1
    xor ebx,ebx
    test edx,edx; jnz .gtwd_stage
    mov r14,[r15+RPF_FACT_FOURIER+24]
    mov ebx,2
.gtwd_stage:
    lea rax,[rip+g_rankn_radices]
    mov rbp,[rax+rbx*8]
    mov r13d,[r15+RPF_FACT_FOURIER+4+rbx*4]
.gtwd_repeat:
    test r13d,r13d; jz .gtwd_next
    mov rsi,r14
    mov rdx,r14
    cmp dword ptr [rsp+16],0; jne .gtwd_inverse
    mov rax,r14; xor edx,edx; div rbp
    mov r14,rax
    mov rsi,rax
    imul rdx,rax,1
    imul rdx,rbp
    jmp .gtwd_have
.gtwd_inverse:
    imul r14,rbp
    mov rdx,r14
.gtwd_have:
    mov [rsp+24],rsi
    test r12,r12; jz .gtwd_measure
    mov rdi,r12
    mov ecx,[rsp+16]
    call g_rankn_make_tw
.gtwd_measure:
    mov rax,[rsp+24]; shl rax,4
    add [rsp],rax
    test r12,r12; jz .gtwd_count
    add r12,rax
.gtwd_count:
    dec r13d; jmp .gtwd_repeat
.gtwd_next:
    cmp dword ptr [rsp+16],0; jne .gtwd_next_inverse
    dec ebx; jns .gtwd_stage
    jmp .gtwd_done
.gtwd_next_inverse:
    inc ebx; cmp ebx,3; jb .gtwd_stage
.gtwd_done:
    mov rax,[rsp]
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# Prepare one immutable constant pool, only for reachable multiply capabilities.
g_prepare_rankn_twiddle_facts:
    push rbx; push rbp; push r12; push r13
    xor ebx,ebx
    xor ebp,ebp
.gtpf_measure:
    cmp ebx,dword ptr [rip+g_rankn_type_count]; jae .gtpf_allocate
    mov r12,rbx; imul r12,r12,RPF_FACT_BYTES
    add r12,[rip+g_rankn_type_facts_ptr]
    cmp qword ptr [r12+RPF_FACT_TW_REQUIRED],0; je .gtpf_next
    xor edi,edi; mov rsi,r12; xor edx,edx
    call g_rankn_twiddle_direction
    mov [r12+RPF_FACT_TW_FORWARD],rbp
    add rbp,rax; jc .gtpf_bad
    mov [r12+RPF_FACT_TW_INVERSE],rbp
    shl rax,1; jc .gtpf_bad
    mov [r12+RPF_FACT_TW_BYTES],rax
    shr rax,1
    add rbp,rax; jc .gtpf_bad
.gtpf_next:
    inc ebx; jmp .gtpf_measure
.gtpf_allocate:
    mov [rip+g_rankn_twiddle_bytes],rbp
    test rbp,rbp; jz .gtpf_ok
    mov eax,SYS_mmap; xor edi,edi; mov rsi,rbp
    mov edx,PROT_READ_WRITE; mov r10d,MAP_PRIVATE_ANON
    mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .gtpf_bad
    mov [rip+g_rankn_twiddle_ptr],rax
    xor ebx,ebx
.gtpf_fill:
    cmp ebx,dword ptr [rip+g_rankn_type_count]; jae .gtpf_ok
    mov r12,rbx; imul r12,r12,RPF_FACT_BYTES
    add r12,[rip+g_rankn_type_facts_ptr]
    cmp qword ptr [r12+RPF_FACT_TW_REQUIRED],0; je .gtpf_fill_next
    mov rdi,[rip+g_rankn_twiddle_ptr]; add rdi,[r12+RPF_FACT_TW_FORWARD]
    mov rsi,r12; xor edx,edx; call g_rankn_twiddle_direction
    mov rdi,[rip+g_rankn_twiddle_ptr]; add rdi,[r12+RPF_FACT_TW_INVERSE]
    mov rsi,r12; mov edx,1; call g_rankn_twiddle_direction
    # Type-relative offsets refer to this same mapped, immutable trailer.
    mov eax,dword ptr [rip+g_rankn_type_count]; sub rax,rbx
    imul rax,rax,RPF_FACT_BYTES
    add [r12+RPF_FACT_TW_FORWARD],rax
    add [r12+RPF_FACT_TW_INVERSE],rax
.gtpf_fill_next:
    inc ebx; jmp .gtpf_fill
.gtpf_ok: xor eax,eax; jmp .gtpf_done
.gtpf_bad: mov eax,1
.gtpf_done:
    pop r13; pop r12; pop rbp; pop rbx; ret

.pushsection .rodata
.balign 8
g_rankn_radices: .quad 2,3,5
.popsection
.pushsection .bss
.balign 8
g_rankn_twiddle_ptr: .skip 8
g_rankn_twiddle_bytes: .skip 8
.popsection
