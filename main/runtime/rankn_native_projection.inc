# Direct native FormatFact projection. Format constants specialize this one
# relation during assembly; generated programs never dispatch on precision.
# Input is a canonical fpP object. The conversion is total, including infinity
# and signed-zero projections, and performs exactly one target RNE.

# rdi=limbs, rcx=N, rdx=first bit -> rax=64-bit window, zero beyond N.
# Both reads select a valid address before loading. SHRD with count zero
# preserves the first limb, so no boundary or alignment execution branch exists.
rpf_native_window:
    mov r8,rdx
    shr r8,6
    lea r10,[rip+rpf_native_zero]
    lea r9,[rdi+r8*8]
    cmp r8,rcx
    cmovae r9,r10
    mov rax,[r9]
    inc r8
    lea r9,[rdi+r8*8]
    cmp r8,rcx
    cmovae r9,r10
    mov r8,[r9]
    mov ecx,edx
    shrd rax,r8,cl
    ret

.macro RPF_NATIVE_PROJECT name, q, emin, emax, bias, width
.global \name
\name:
    RPF_SAVE
    sub rsp,8
    mov r12,rdi
    call rpf_object_is_zero
    test eax,eax
    jnz .Lnative_zero\@
    mov r14,[r12+RPF_EXP]
    cmp r14,\emax
    jg .Lnative_inf\@
    cmp r14,(\emin-\q)
    jl .Lnative_zero\@
    mov r13,[r12+RPF_PREC]
    add r13,63
    shr r13,6
    mov rdx,[r12+RPF_PREC]
    sub rdx,\q
    mov rax,\emin
    sub rax,r14
    xor ecx,ecx
    cmp r14,\emin
    cmovge rax,rcx
    add rdx,rax
    mov [rsp],rdx
    lea rdi,[r12+RPF_DATA]
    mov rcx,r13
    call rpf_native_window
    mov r15,((1<<\q)-1)
    and r15,rax
    # P>64 makes shift positive for both native formats.
    mov rdx,[rsp]
    dec rdx
    lea rdi,[r12+RPF_DATA]
    mov rcx,r13
    call rpf_test_bit
    mov ebx,eax
    mov rdx,[rsp]
    dec rdx
    lea rdi,[r12+RPF_DATA]
    mov rcx,r13
    call rpf_any_low_bits
    or eax,r15d
    and eax,1
    and eax,ebx
    add r15,rax
    bt r15,\q
    jnc .Lnative_pack\@
    shr r15,1
    inc r14
    cmp r14,\emax
    jg .Lnative_inf\@
.Lnative_pack\@:
    mov rax,r15
    cmp r14,\emin
    jl .Lnative_sign\@
    mov rcx,((1<<(\q-1))-1)
    and rax,rcx
    mov rcx,r14
    add rcx,\bias
    shl rcx,(\q-1)
    or rax,rcx
    jmp .Lnative_sign\@
.Lnative_zero\@:
    xor eax,eax
    jmp .Lnative_sign\@
.Lnative_inf\@:
    mov rax,((2*\bias+1)<<(\q-1))
.Lnative_sign\@:
    mov rcx,[r12+RPF_SIGN]
    shl rcx,(\width-1)
    or rax,rcx
    xor edx,edx
    add rsp,8
    RPF_RESTORE
    ret
.endm

RPF_NATIVE_PROJECT rankn_fp_to_f32_bits,24,-126,127,127,32
RPF_NATIVE_PROJECT rankn_fp_to_f64_bits,53,-1022,1023,1023,64

.pushsection .rodata
.balign 8
rpf_native_zero: .quad 0
.popsection
