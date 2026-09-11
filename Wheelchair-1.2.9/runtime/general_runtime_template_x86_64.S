.intel_syntax noprefix
# General scalar/control runtime image for the handwritten-assembly language compiler.
# The compiler patches type/count tables and overwrites program_slot with direct
# native code. There is no interpreter, VM, libc, dynamic loader dependency, or
# user-program assembler/linker invocation.

.equ SYS_write, 1
.equ SYS_exit_group, 231
.equ MAX_INPUTS, 16
.equ MAX_BINDINGS, 64
.equ MAX_STATES, 32
.equ MAX_OUTPUTS, 32
.equ SLOT_BYTES, 8
.equ TYPE_BOOL, 1
.equ TYPE_I64, 2
.equ TYPE_U64, 3
.equ TYPE_F32, 4
.equ TYPE_F64, 5
.equ TYPE_STRING, 6

.section .text
.global _start
_start:
    mov r15,rsp
    mov rax,[r15]                  # argc
    mov ecx,dword ptr [rip+input_count_patch]
    lea rdx,[rcx+1]
    cmp rax,rdx
    jne .bad_args
    lea r12,[r15+16]               # argv[1]
    lea r13,[rip+input_values]
    lea r14,[rip+input_type_patch]
    xor ebx,ebx
.parse_inputs:
    # Decimal parsers use caller-saved RCX internally. Reload immutable input count.
    cmp ebx,dword ptr [rip+input_count_patch]
    jae .run
    mov rdi,[r12+rbx*8]
    movzx eax,byte ptr [r14+rbx]
    cmp eax,TYPE_BOOL
    je .in_bool
    cmp eax,TYPE_I64
    je .in_i64
    cmp eax,TYPE_U64
    je .in_u64
    cmp eax,TYPE_F32
    je .in_f32
    cmp eax,TYPE_F64
    je .in_f64
    cmp eax,TYPE_STRING
    je .in_string
    jmp .bad_args
.in_bool:
    call parse_bool
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_i64:
    call parse_i64
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_u64:
    call parse_u64
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_f32:
    call parse_f64
    test edx,edx
    jnz .bad_args
    movq xmm0,rax
    cvtsd2ss xmm0,xmm0
    movd eax,xmm0
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_f64:
    call parse_f64
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_string:
    mov [r13+rbx*SLOT_BYTES],rdi
    call cstrlen
    lea r10,[rip+input_aux]
    mov [r10+rbx*8],rax
.in_next:
    inc ebx
    jmp .parse_inputs

.run:
    call program_slot
    test eax,eax
    jnz .runtime_reject
    xor ebx,ebx
.print_loop:
    # Output helpers use rcx internally; compare directly against the patched
    # count so helper scratch state can never extend the output loop.
    cmp ebx,dword ptr [rip+output_count_patch]
    jae .ok
    lea r10,[rip+output_type_patch]
    movzx eax,byte ptr [r10+rbx]
    cmp eax,TYPE_STRING
    je .print_string
    mov rax,rbx
    call make_out_index
    lea r10,[rip+output_values]
    mov rax,[r10+rbx*8]
    call print_bits_line
    inc ebx
    jmp .print_loop
.print_string:
    mov rax,rbx
    call make_out_index
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+out_string_prefix]
    mov edx,out_string_prefix_end-out_string_prefix
    syscall
    mov eax,SYS_write
    mov edi,1
    lea r10,[rip+output_values]
    mov rsi,[r10+rbx*8]
    lea r10,[rip+output_aux]
    mov rdx,[r10+rbx*8]
    syscall
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+newline]
    mov edx,1
    syscall
    inc ebx
    jmp .print_loop
.ok:
    xor edi,edi
    mov eax,SYS_exit_group
    syscall
.runtime_reject:
    mov edi,65
    mov eax,SYS_exit_group
    syscall
.bad_args:
    mov edi,2
    mov eax,SYS_exit_group
    syscall

# Patched by compiler. Return eax=0 or language runtime reject code !=0.
.p2align 6
.global program_slot
program_slot:
    xor eax,eax
    ret
    .fill 131072-(.-program_slot),1,0x90
.global program_slot_end
program_slot_end:

# parse bool -> rax 0/1, edx err
parse_bool:
    cmp byte ptr [rdi],'0'
    jne 1f
    cmp byte ptr [rdi+1],0
    jne .pb_bad
    xor eax,eax; xor edx,edx; ret
1:  cmp byte ptr [rdi],'1'
    jne 2f
    cmp byte ptr [rdi+1],0
    jne .pb_bad
    mov eax,1; xor edx,edx; ret
2:  cmp dword ptr [rdi],0x65757274  # true
    jne 3f
    cmp byte ptr [rdi+4],0
    jne .pb_bad
    mov eax,1; xor edx,edx; ret
3:  cmp dword ptr [rdi],0x736c6166  # fals
    jne .pb_bad
    cmp byte ptr [rdi+4],'e'
    jne .pb_bad
    cmp byte ptr [rdi+5],0
    jne .pb_bad
    xor eax,eax; xor edx,edx; ret
.pb_bad: xor eax,eax; mov edx,1; ret

parse_u64:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
.pu_loop:
    movzx r8d,byte ptr [rdi]
    test r8b,r8b
    jz .pu_done
    cmp r8b,'0'; jb .pu_bad
    cmp r8b,'9'; ja .pu_bad
    mov r9,1844674407370955161
    cmp rax,r9; ja .pu_bad
    imul rax,rax,10
    sub r8d,'0'
    add rax,r8
    jc .pu_bad
    inc rdi; inc ecx; jmp .pu_loop
.pu_done:
    test ecx,ecx; jz .pu_bad
    xor edx,edx; ret
.pu_bad: xor eax,eax; mov edx,1; ret

parse_i64:
    xor r8d,r8d
    cmp byte ptr [rdi],'-'
    jne .pi_pos
    mov r8d,1
    inc rdi
.pi_pos:
    push r8
    call parse_u64
    pop r8
    test edx,edx
    jnz .pi_bad
    test r8d,r8d
    jz .pi_positive_range
    mov rcx,0x8000000000000000
    cmp rax,rcx
    ja .pi_bad
    neg rax
    xor edx,edx
    ret
.pi_positive_range:
    mov rcx,0x7fffffffffffffff
    cmp rax,rcx
    ja .pi_bad
    xor edx,edx
    ret
.pi_bad: xor eax,eax; mov edx,1; ret

# Restricted but deterministic decimal parser: [+/-]digits[.digits].
# Returns IEEE f64 bits in rax. Exponent syntax is rejected rather than guessed.
parse_f64:
    push rbx
    push r12
    xor r12d,r12d
    cmp byte ptr [rdi],'-'
    jne .pf_plus
    mov r12d,1
    inc rdi
    jmp .pf_start
.pf_plus:
    cmp byte ptr [rdi],'+'
    jne .pf_start
    inc rdi
.pf_start:
    xor rax,rax                    # integer numerator digits
    mov rbx,1                     # denominator
    xor r8d,r8d                    # seen digit
    xor r9d,r9d                    # after dot
.pf_loop:
    movzx ecx,byte ptr [rdi]
    test cl,cl
    jz .pf_done
    cmp cl,'.'
    jne .pf_digit
    test r9d,r9d
    jnz .pf_bad
    mov r9d,1
    inc rdi
    jmp .pf_loop
.pf_digit:
    cmp cl,'0'; jb .pf_bad
    cmp cl,'9'; ja .pf_bad
    imul rax,rax,10
    sub ecx,'0'
    add rax,rcx
    test r9d,r9d
    jz .pf_next
    imul rbx,rbx,10
.pf_next:
    mov r8d,1
    inc rdi
    jmp .pf_loop
.pf_done:
    test r8d,r8d
    jz .pf_bad
    cvtsi2sd xmm0,rax
    cmp rbx,1
    je .pf_sign
    cvtsi2sd xmm1,rbx
    divsd xmm0,xmm1
.pf_sign:
    test r12d,r12d
    jz .pf_bits
    mov rax,0x8000000000000000
    movq xmm1,rax
    xorpd xmm0,xmm1
.pf_bits:
    movq rax,xmm0
    xor edx,edx
    pop r12
    pop rbx
    ret
.pf_bad:
    xor eax,eax
    mov edx,1
    pop r12
    pop rbx
    ret

cstrlen:
    xor eax,eax
.cs: cmp byte ptr [rdi+rax],0; je .cs_done; inc rax; jmp .cs
.cs_done: ret

# rax=index. Patch the two decimal index bytes in shared prefixes.
make_out_index:
    xor edx,edx
    mov ecx,10
    div rcx
    add al,'0'
    add dl,'0'
    mov byte ptr [rip+out_bits_prefix+3],al
    mov byte ptr [rip+out_bits_prefix+4],dl
    mov byte ptr [rip+out_string_prefix+3],al
    mov byte ptr [rip+out_string_prefix+4],dl
    ret

# rax bits
print_bits_line:
    push rbx
    mov rbx,rax
    lea rdi,[rip+out_bits_prefix+13]
    mov ecx,16
.pb_hex:
    mov rdx,rbx
    shr rdx,60
    and edx,15
    cmp edx,9
    jbe .pb_digit
    add edx,'a'-10
    jmp .pb_store
.pb_digit: add edx,'0'
.pb_store:
    mov byte ptr [rdi],dl
    inc rdi
    shl rbx,4
    dec ecx
    jnz .pb_hex
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+out_bits_prefix]
    mov edx,out_bits_prefix_end-out_bits_prefix
    syscall
    pop rbx
    ret

.section .data
.p2align 6
.global input_count_patch
input_count_patch: .long 0
.global output_count_patch
output_count_patch: .long 0
.global input_type_patch
input_type_patch: .fill MAX_INPUTS,1,0
.global output_type_patch
output_type_patch: .fill MAX_OUTPUTS,1,0
out_bits_prefix: .ascii "out00_bits=0x0000000000000000\n"
out_bits_prefix_end:
out_string_prefix: .ascii "out00_string="
out_string_prefix_end:
newline: .byte 10

.section .bss
.p2align 6
.global input_values
input_values: .skip MAX_INPUTS*SLOT_BYTES
.global input_aux
input_aux: .skip MAX_INPUTS*8
.global binding_values
binding_values: .skip MAX_BINDINGS*SLOT_BYTES
.global state_values
state_values: .skip MAX_STATES*SLOT_BYTES
.global state_temp
state_temp: .skip MAX_STATES*SLOT_BYTES
.global output_values
output_values: .skip MAX_OUTPUTS*SLOT_BYTES
.global output_aux
output_aux: .skip MAX_OUTPUTS*8
