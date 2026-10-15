# Textbook base-2 integer quotient/remainder, one nearest-even rounding.
# Three scratch integers scale with spelling length; no decimal u64 ceiling.
# rdi=span, rsi=length -> rax=bits, edx=0/1. Preserves callee-owned GPRs.
physical_decimal_f64:
    mov edx,64; jmp physical_decimal_bits
physical_decimal_f32:
    mov edx,32
physical_decimal_bits:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    mov r12,rdi; lea r13,[rdi+rsi]
    lea rbp,[rsi+615]; shr rbp,4
    imul rax,rbp,24; add rax,96; sub rsp,rax
    mov rbx,rsp; mov [rbx+56],rax
    lea r14,[rbx+96]; lea r15,[r14+rbp*8]
    mov rdi,rbx; lea rcx,[rbp+rbp*2]; add rcx,12; xor eax,eax; rep stosq
    imul rax,rbp,24; add rax,96; mov [rbx+56],rax
    mov qword ptr [rbx+64],52
    mov qword ptr [rbx+72],-1022
    mov qword ptr [rbx+80],1023
    mov qword ptr [rbx+88],1023
    cmp edx,64; je 20f
    mov qword ptr [rbx+64],23
    mov qword ptr [rbx+72],-126
    mov qword ptr [rbx+80],127
    mov qword ptr [rbx+88],127
20: cmp r12,r13; jae .dec_bad
    cmp byte ptr [r12],'-'; jne 1f
    mov qword ptr [rbx],1; inc r12; jmp .dec_digits
1:  cmp byte ptr [r12],'+'; jne .dec_digits
    inc r12
.dec_digits:
    cmp r12,r13; jae .dec_scale
    movzx eax,byte ptr [r12]
    cmp al,'e'; je .dec_exp
    cmp al,'E'; je .dec_exp
    cmp al,'.'; je .dec_dot
    sub eax,'0'; cmp eax,9; ja .dec_bad
    inc qword ptr [rbx+48]
    cmp qword ptr [rbx+40],0; je 2f
    inc qword ptr [rbx+8]
2:  test eax,eax; jnz 3f
    cmp qword ptr [rbx+16],0; je 4f
3:  inc qword ptr [rbx+16]
4:  mov ecx,eax; mov rdi,r14; mov rsi,rbp; call .dec_times10
    inc r12; jmp .dec_digits
.dec_dot:
    cmp qword ptr [rbx+40],0; jne .dec_bad
    mov qword ptr [rbx+40],1; inc r12
    cmp r12,r13; jae .dec_bad
    movzx eax,byte ptr [r12]; sub eax,'0'; cmp eax,9; ja .dec_bad
    jmp .dec_digits
.dec_exp:
    inc r12; cmp r12,r13; jae .dec_bad
    cmp byte ptr [r12],'-'; jne 5f
    mov qword ptr [rbx+32],1; inc r12; jmp 6f
5:  cmp byte ptr [r12],'+'; jne 6f
    inc r12
6:  cmp r12,r13; jae .dec_bad
    xor r10d,r10d
    mov r9,r13; sub r9,r12; add r9,[rbx+48]; add r9,1024
.dec_exp_digits:
    cmp r12,r13; jae .dec_exp_end
    movzx eax,byte ptr [r12]; sub eax,'0'; cmp eax,9; ja .dec_bad
    cmp r10,r9; jae 7f
    imul r10,r10,10; add r10,rax
7:  inc r12; jmp .dec_exp_digits
.dec_exp_end:
    cmp qword ptr [rbx+32],0; je 8f
    neg r10
8:  mov [rbx+24],r10
.dec_scale:
    cmp qword ptr [rbx+48],0; je .dec_bad
    mov rax,[rbx+24]; sub rax,[rbx+8]; mov [rbx+24],rax
    cmp qword ptr [rbx+16],0; je .dec_zero
    add rax,[rbx+16]
    cmp rax,310; jg .dec_inf
    cmp rax,-324; jl .dec_zero
    mov qword ptr [r15],1
    mov r12,[rbx+24]; test r12,r12; jz .dec_normalize
    mov r13,r14; jns .dec_pow
    mov r13,r15; neg r12
.dec_pow:
    mov rdi,r13; mov rsi,rbp; xor ecx,ecx; call .dec_times10
    dec r12; jnz .dec_pow
.dec_normalize:
    mov rdi,r14; mov rsi,rbp; call .dec_bitlength; mov r12,rax
    mov rdi,r15; mov rsi,rbp; call .dec_bitlength; sub r12,rax
    lea r13,[r15+rbp*8]
    mov rdi,r13; mov rsi,r15
    test r12,r12; jns 9f
    mov rsi,r14
9:  mov rcx,rbp; rep movsq
    mov rdx,r12; test rdx,rdx; jns 10f
    neg rdx
10: mov rdi,r13; mov rsi,rbp; call .dec_shift
    mov rdi,r14; mov rsi,r13
    test r12,r12; jns 11f
    mov rdi,r13; mov rsi,r15
11: mov rcx,rbp; call .dec_compare; test eax,eax; jns 12f
    dec r12
12: cmp r12,[rbx+80]; jg .dec_inf
    mov [rbx+24],r12
    cmp r12,[rbx+72]; jge 13f
    mov r12,[rbx+72]
13: mov rdx,[rbx+64]; sub rdx,r12
    mov rdi,r14; test rdx,rdx; jns 14f
    neg rdx; mov rdi,r15
14: mov rsi,rbp; call .dec_shift
    mov rdi,r14; mov rsi,rbp; call .dec_bitlength; mov r12,rax
    mov rdi,r15; mov rsi,rbp; call .dec_bitlength; sub r12,rax
    mov rdi,r13; mov rsi,r15; mov rcx,rbp; rep movsq
    xor r8d,r8d; test r12,r12; js .dec_round
    mov rdi,r13; mov rsi,rbp; mov rdx,r12; call .dec_shift
.dec_divide:
    mov rdi,r14; mov rsi,r13; mov rcx,rbp; call .dec_compare
    test eax,eax; js 15f
    mov rdi,r14; mov rsi,r13; mov rcx,rbp; call .dec_subtract
    bts r8,r12
15: mov rdi,r13; mov rsi,rbp; call .dec_right1
    dec r12; jns .dec_divide
.dec_round:
    mov rdi,r14; mov rsi,rbp; mov edx,1; call .dec_shift
    mov rdi,r14; mov rsi,r15; mov rcx,rbp; call .dec_compare
    test eax,eax; js .dec_encode
    jnz 16f
    test r8b,1; jz .dec_encode
16: inc r8
.dec_encode:
    mov r12,[rbx+24]
    cmp r12,[rbx+72]; jl .dec_subnormal
    mov rcx,[rbx+64]; inc rcx; bt r8,rcx; jnc 17f
    shr r8,1; inc r12
17: cmp r12,[rbx+80]; jg .dec_inf
    mov rcx,[rbx+64]; btr r8,rcx
    add r12,[rbx+88]; shl r12,cl; or r8,r12
.dec_subnormal:
    mov rax,r8; jmp .dec_sign
.dec_inf: mov rax,[rbx+80]; lea rax,[rax+rax+1]; mov rcx,[rbx+64]; shl rax,cl; jmp .dec_sign
.dec_zero: xor eax,eax
.dec_sign:
    cmp qword ptr [rbx],0; je .dec_ok
    mov ecx,63; cmp qword ptr [rbx+64],52; je 21f
    mov ecx,31
21: bts rax,rcx
.dec_ok: xor edx,edx; jmp .dec_done
.dec_bad: xor eax,eax; mov edx,1
.dec_done:
    mov rcx,[rbx+56]; add rsp,rcx
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx; ret

# Full-limb operations preserve R8 (quotient) and source-lifetime registers.
.dec_times10:
    xor r9d,r9d; mov r10,rcx; mov r11d,10
1:  cmp r9,rsi; jae 2f
    mov rax,[rdi+r9*8]; mul r11
    add rax,r10; adc rdx,0
    mov [rdi+r9*8],rax; mov r10,rdx
    inc r9; jmp 1b
2:  ret
.dec_bitlength:
    mov rcx,rsi
1:  test rcx,rcx; jz 2f
    dec rcx; mov rax,[rdi+rcx*8]; test rax,rax; jz 1b
    bsr rax,rax; shl rcx,6; lea rax,[rax+rcx+1]; ret
2:  xor eax,eax; ret
.dec_compare:
1:  test rcx,rcx; jz 2f
    dec rcx; mov rax,[rdi+rcx*8]; cmp rax,[rsi+rcx*8]; ja 3f; jb 4f
    jmp 1b
2:  xor eax,eax; ret
3:  mov eax,1; ret
4:  mov eax,-1; ret
.dec_subtract:
    xor r9d,r9d; clc
1:  mov rax,[rdi+r9*8]; sbb rax,[rsi+r9*8]; mov [rdi+r9*8],rax
    inc r9; dec rcx; jnz 1b
    ret
# In-place left shift with zero-extension and arbitrary word distance.
.dec_shift:
    mov r9,rdx; shr r9,6; mov ecx,edx; and ecx,63
    mov r10,rsi
1:  dec r10; mov r11,r10; sub r11,r9; js 4f
    mov rax,[rdi+r11*8]; test ecx,ecx; jz 3f
    xor edx,edx; test r11,r11; jz 2f
    mov rdx,[rdi+r11*8-8]
2:  shld rax,rdx,cl
3:  mov [rdi+r10*8],rax; jmp 5f
4:  mov qword ptr [rdi+r10*8],0
5:  test r10,r10; jnz 1b
    ret
.dec_right1:
    mov rcx,rsi; clc
1:  dec rcx; rcr qword ptr [rdi+rcx*8],1
    jrcxz 2f
    jmp 1b
2:  ret
