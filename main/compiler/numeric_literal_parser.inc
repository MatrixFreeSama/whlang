# One exact integer-rational decimal authority for static and runtime inputs.
# rax=node -> rax=IEEE f64, edx=0/1. Internal bits already carry natural precision.
node_parse_f64_bits:
    push r15
    test rax,rax; jz .npf_bad
    cmp qword ptr [rax],J_STRING; je .npf_bits_string
    cmp qword ptr [rax],J_NUMBER; jne .npf_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]
    call physical_decimal_f64
    pop r15; ret
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

.include "compiler/physical_decimal.inc"

# Natural f32 literals round directly; explicit internal f64-bit values retain
# their declared conversion edge rather than being reinterpreted as decimals.
node_parse_f32_bits:
    test rax,rax; jz 1f
    cmp qword ptr [rax],J_NUMBER; jne 2f
    mov rdi,[rax+8]; mov rsi,[rax+16]
    jmp physical_decimal_f32
2:  call node_parse_f64_bits; test edx,edx; jnz 3f
    movq xmm0,rax; cvtsd2ss xmm0,xmm0; movd eax,xmm0
3:  ret
1:  xor eax,eax; mov edx,1; ret
