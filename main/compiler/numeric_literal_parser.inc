# Shared executable f64 literal parser.
#
# One numeric spelling authority is consumed by every native256/native512 and
# base/derived Tensor/General physicalizer.  Decimal scientific notation is not
# a second numeric family: mantissa and decimal scale use the existing exact-u64
# slice, and the optional base-10 exponent is applied to the same f64 fact by
# exponentiation-by-squaring.  No precision name, workload name, library name,
# or magnitude threshold selects another parser.
#
# Contract: node in rax -> IEEE-754 f64 bits in rax, edx=0 success / 1 reject.
node_parse_f64_bits:
    push r15
    test rax,rax
    jz .npf_bad
    cmp qword ptr [rax],J_STRING
    je .npf_bits_string
    cmp qword ptr [rax],J_NUMBER
    jne .npf_bad
    mov rdi,[rax+8]
    mov rcx,[rax+16]
    xor r8d,r8d                     # sign of complete literal
    cmp byte ptr [rdi],'-'
    jne .npf_start
    mov r8d,1
    inc rdi
    dec rcx
.npf_start:
    xor r9,r9                       # mantissa numerator digits
    mov r10,1                       # decimal denominator from fraction digits
    xor r11d,r11d                   # mantissa is after decimal point
    xor esi,esi                     # optional exponent magnitude; zero = no scale
.npf_loop:
    test rcx,rcx
    jz .npf_make_no_exp
    movzx eax,byte ptr [rdi]
    cmp al,'.'
    je .npf_dot
    cmp al,'e'
    je .npf_exp
    cmp al,'E'
    je .npf_exp
    cmp al,'0'
    jb .npf_bad
    cmp al,'9'
    ja .npf_bad
    sub eax,'0'
    # unsigned overflow guard for numerator = numerator*10 + digit
    mov rdx,1844674407370955161
    cmp r9,rdx
    jb .npf_num_ok
    ja .npf_bad
    cmp eax,5
    ja .npf_bad
.npf_num_ok:
    imul r9,r9,10
    add r9,rax
    test r11d,r11d
    jz .npf_next
    # denominator is a power of ten; reject before unsigned u64 overflow.
    mov rdx,1844674407370955161
    cmp r10,rdx
    ja .npf_bad
    imul r10,r10,10
.npf_next:
    inc rdi
    dec rcx
    jmp .npf_loop
.npf_dot:
    test r11d,r11d
    jnz .npf_bad                      # a second decimal point is not a number
    mov r11d,1
    inc rdi
    dec rcx
    test rcx,rcx
    jz .npf_bad                       # surface grammar requires digits after '.'
    jmp .npf_loop

.npf_exp:
    # The mantissa grammar has ended.  Exponent sign/magnitude reuse ordinary
    # integer structure and never become a runtime configuration object.
    inc rdi
    dec rcx
    test rcx,rcx
    jz .npf_bad
    xor r11d,r11d                     # exponent sign: 1 = negative
    movzx eax,byte ptr [rdi]
    cmp al,'+'
    je .npf_exp_sign_done
    cmp al,'-'
    jne .npf_exp_digits_start
    mov r11d,1
.npf_exp_sign_done:
    inc rdi
    dec rcx
    test rcx,rcx
    jz .npf_bad
.npf_exp_digits_start:
    xor esi,esi
    xor edx,edx                       # count exponent digits
.npf_exp_loop:
    test rcx,rcx
    jz .npf_exp_done
    movzx eax,byte ptr [rdi]
    cmp al,'0'
    jb .npf_bad
    cmp al,'9'
    ja .npf_bad
    sub eax,'0'
    mov r15,1844674407370955161
    cmp rsi,r15
    jb .npf_exp_acc
    ja .npf_bad
    cmp eax,5
    ja .npf_bad
.npf_exp_acc:
    imul rsi,rsi,10
    add rsi,rax
    inc edx
    inc rdi
    dec rcx
    jmp .npf_exp_loop
.npf_exp_done:
    test edx,edx
    jz .npf_bad
    jmp .npf_make

.npf_make_no_exp:
    xor r11d,r11d                     # no exponent => positive zero exponent
.npf_make:
    mov rax,r9
    call node_u64_to_f64
    movapd xmm2,xmm0
    cmp r10,1
    je .npf_restore_num
    mov rax,r10
    call node_u64_to_f64
    movapd xmm1,xmm0
    movapd xmm0,xmm2
    divsd xmm0,xmm1
    jmp .npf_scale
.npf_restore_num:
    movapd xmm0,xmm2
.npf_scale:
    test rsi,rsi
    jz .npf_sign
    test r9,r9
    jz .npf_sign                       # 0e+large remains exact zero
    mov rax,0x4024000000000000         # 10.0
    movq xmm3,rax
    mov rax,0x3ff0000000000000         # 1.0
    movq xmm4,rax
    mov rcx,rsi
.npf_pow10_loop:
    test rcx,rcx
    jz .npf_pow10_ready
    test cl,1
    jz .npf_pow10_skip_mul
    mulsd xmm4,xmm3
.npf_pow10_skip_mul:
    shr rcx,1
    test rcx,rcx
    jz .npf_pow10_ready
    mulsd xmm3,xmm3
    jmp .npf_pow10_loop
.npf_pow10_ready:
    test r11d,r11d
    jnz .npf_scale_down
    mulsd xmm0,xmm4
    jmp .npf_sign
.npf_scale_down:
    divsd xmm0,xmm4
.npf_sign:
    test r8d,r8d
    jz .npf_bits
    mov rax,0x8000000000000000
    movq xmm1,rax
    xorpd xmm0,xmm1
.npf_bits:
    movq rax,xmm0
    xor edx,edx
    pop r15
    ret

.npf_bits_string:
    # Internal exact literal representation emitted by the native human surface.
    # It carries already-rounded target f64 bits; no decimal re-truncation occurs.
    mov rdi,[rax+8]
    mov rcx,[rax+16]
    cmp rcx,10; jb .npf_bad
    cmp byte ptr [rdi+0],'@'; jne .npf_bad
    cmp byte ptr [rdi+1],'f'; jne .npf_bad
    cmp byte ptr [rdi+2],'6'; jne .npf_bad
    cmp byte ptr [rdi+3],'4'; jne .npf_bad
    cmp byte ptr [rdi+4],'b'; jne .npf_bad
    cmp byte ptr [rdi+5],'i'; jne .npf_bad
    cmp byte ptr [rdi+6],'t'; jne .npf_bad
    cmp byte ptr [rdi+7],'s'; jne .npf_bad
    cmp byte ptr [rdi+8],':'; jne .npf_bad
    add rdi,9; sub rcx,9
    xor r9,r9
.npf_bs_loop:
    test rcx,rcx; jz .npf_bs_ok
    movzx eax,byte ptr [rdi]
    cmp al,'0'; jb .npf_bad
    cmp al,'9'; ja .npf_bad
    sub eax,'0'
    mov rdx,1844674407370955161
    cmp r9,rdx; jb .npf_bs_acc
    ja .npf_bad
    cmp eax,5; ja .npf_bad
.npf_bs_acc:
    imul r9,r9,10; add r9,rax
    inc rdi; dec rcx; jmp .npf_bs_loop
.npf_bs_ok:
    mov rax,r9; xor edx,edx
    pop r15
    ret
.npf_bad:
    xor eax,eax
    mov edx,1
    pop r15
    ret
