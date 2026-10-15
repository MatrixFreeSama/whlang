.section .text
.include "runtime/input_range_relation.inc"
.global physical_input_range_check
INPUT_RANGE_RELATION physical_input_range_check

# rdi=input DOM, esi=natural type, rdx=three qwords lo/hi/flags.
# No bound is permitted to become an unconsumed compiler proof.
.global physical_input_range_parse
physical_input_range_parse:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi; mov r14,rdx; xor ebx,ebx
    mov qword ptr [r14],0; mov qword ptr [r14+8],0; mov qword ptr [r14+16],0
.pirp_next:
    mov rdi,r12; lea rsi,[rip+pir_min]; test ebx,ebx; jz 1f
    lea rsi,[rip+pir_max]
1:  mov edx,3; call obj_get
    test rax,rax; jz .pirp_advance
    mov ecx,ebx; mov edx,1; shl edx,cl; or [r14+16],rdx
    cmp r13d,1; je .pirp_bool
    cmp r13d,2; je .pirp_signed
    cmp r13d,3; je .pirp_unsigned
    cmp r13d,4; je .pirp_f32
    cmp r13d,5; jne .pirp_bad
    call node_parse_f64_bits; jmp .pirp_store
.pirp_f32:
    call node_parse_f32_bits; jmp .pirp_store
.pirp_signed:
    mov rdi,rax; call physical_parse_i64_node; jmp .pirp_store
.pirp_unsigned:
    call node_parse_u64; jmp .pirp_store
.pirp_bool:
    cmp qword ptr [rax],5; je .pirp_true
    cmp qword ptr [rax],6; je .pirp_false
    call node_parse_u64; test edx,edx; jnz .pirp_bad
    cmp rax,1; ja .pirp_bad; jmp .pirp_store
.pirp_true: mov eax,1; xor edx,edx; jmp .pirp_store
.pirp_false: xor eax,eax; xor edx,edx
.pirp_store:
    test edx,edx; jnz .pirp_bad
    mov [r14+rbx*8],rax
    # A single unordered bound is invalid too; checking against itself uses
    # the same typed relation as input admission, including direct f32 bits.
    sub rsp,24
    mov [rsp],rax; mov [rsp+8],rax; mov qword ptr [rsp+16],3
    mov edi,r13d; mov rsi,rsp; call physical_input_range_check
    add rsp,24
    test edx,edx; jnz .pirp_bad
.pirp_advance:
    inc ebx; cmp ebx,2; jb .pirp_next
    cmp qword ptr [r14+16],3; jne .pirp_ok
    mov rax,[r14]; mov edi,r13d; mov rsi,r14; call physical_input_range_check
    test edx,edx; jnz .pirp_bad
.pirp_ok: xor eax,eax; jmp .pirp_done
.pirp_bad: mov eax,1
.pirp_done: pop r14; pop r13; pop r12; pop rbx; ret

# rdi=admitted lo/hi/flags, esi=natural type -> eax=-1,0,1 or 2 unknown.
# Bounds already use the sole typed admission relation. This projection adds no
# input parser or runtime checks; it is an AOT consequence of that same contract.
.global physical_input_range_sign
physical_input_range_sign:
    mov rcx,[rdi+16]
    cmp esi,4; je .pirs_fp32
    cmp esi,5; je .pirs_fp64
    test cl,1; jz .pirs_int_upper
    mov rax,[rdi]
    cmp esi,3; je .pirs_uint_lower
    test rax,rax; jg .pirs_positive
    jmp .pirs_int_upper
.pirs_uint_lower:
    test rax,rax; jnz .pirs_positive
.pirs_int_upper:
    test cl,2; jz .pirs_unknown
    mov rax,[rdi+8]
    cmp esi,3; je .pirs_uint_upper
    test rax,rax; js .pirs_negative
    jmp .pirs_int_zero
.pirs_uint_upper:
    test rax,rax; jz .pirs_zero
.pirs_int_zero:
    cmp ecx,3; jne .pirs_unknown
    or rax,[rdi]; jz .pirs_zero
    jmp .pirs_unknown
.pirs_fp32:
    movd xmm0,dword ptr [rdi]
    movd xmm1,dword ptr [rdi+8]
    cvtss2sd xmm0,xmm0; cvtss2sd xmm1,xmm1
    jmp .pirs_fp
.pirs_fp64:
    movq xmm0,[rdi]; movq xmm1,[rdi+8]
.pirs_fp:
    pxor xmm2,xmm2
    test cl,1; jz .pirs_fp_upper
    ucomisd xmm0,xmm2; jp .pirs_unknown; ja .pirs_positive
.pirs_fp_upper:
    test cl,2; jz .pirs_unknown
    ucomisd xmm1,xmm2; jp .pirs_unknown; jb .pirs_negative
    jne .pirs_unknown
    cmp ecx,3; jne .pirs_unknown
    ucomisd xmm0,xmm2; jp .pirs_unknown; jne .pirs_unknown
.pirs_zero: xor eax,eax; ret
.pirs_negative: mov eax,-1; ret
.pirs_positive: mov eax,1; ret
.pirs_unknown: mov eax,2; ret

# Signed decimal ingress checks before multiplying, including INT64_MIN.
# rdi=JSON number node -> rax=bits, edx=0/1.
.global physical_parse_i64_node
physical_parse_i64_node:
    test rdi,rdi; jz .pi64_bad
    cmp qword ptr [rdi],4; jne .pi64_bad
    mov r8,[rdi+8]; mov rcx,[rdi+16]; xor r9d,r9d
    test rcx,rcx; jz .pi64_bad
    cmp byte ptr [r8],'-'; jne .pi64_digits
    mov r9d,1; inc r8; dec rcx
.pi64_digits:
    xor eax,eax; test rcx,rcx; jz .pi64_bad
.pi64_loop:
    movzx edx,byte ptr [r8]; cmp dl,'0'; jb .pi64_bad; cmp dl,'9'; ja .pi64_bad
    sub edx,'0'
    mov r10,922337203685477580
    cmp rax,r10; ja .pi64_bad; jb .pi64_acc
    lea r10d,[r9+7]; cmp edx,r10d; ja .pi64_bad
.pi64_acc:
    imul rax,rax,10; add rax,rdx; inc r8; dec rcx; jnz .pi64_loop
    test r9d,r9d; jz .pi64_ok; neg rax
.pi64_ok: xor edx,edx; ret
.pi64_bad: xor eax,eax; mov edx,1; ret
.section .rodata
pir_min: .ascii "min"
pir_max: .ascii "max"
