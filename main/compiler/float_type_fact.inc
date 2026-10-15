.ifndef FLOAT_TYPE_FACT_DEFINED
.equ FLOAT_TYPE_FACT_DEFINED,1
# Common semantic floating PrecisionFact. rdi=span, rsi=length -> rax=P or 0.
# Native f32/f64 and parameterized fpP (>64) share one syntax authority.
# This relation executes in the compiler only, never in emitted programs.
.macro FLOAT_TYPE_PRECISION name
\name:
    cmp rsi,3; jb 9f
    cmp byte ptr [rdi],'f'; jne 9f
    cmp byte ptr [rdi+1],'p'; je 1f
    cmp rsi,3; jne 9f
    cmp word ptr [rdi+1],0x3233; je 7f
    cmp word ptr [rdi+1],0x3436; je 8f
    jmp 9f
1:  cmp byte ptr [rdi+2],'0'; je 9f
    xor eax,eax
    mov ecx,2
2:  cmp rcx,rsi; jae 4f
    movzx r10d,byte ptr [rdi+rcx]
    sub r10d,'0'; cmp r10d,9; ja 9f
    mov r11d,10; mul r11
    test rdx,rdx; jnz 9f
    add rax,r10; jc 9f
    inc rcx; jmp 2b
4:  cmp rax,64; jbe 9f
    ret
7:  mov eax,32; ret
8:  mov eax,64; ret
9:  xor eax,eax; ret
.endm

.endif
