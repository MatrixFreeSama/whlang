parse_f32:
    mov eax,32; jmp parse_decimal
parse_f64:
    mov eax,64
parse_decimal:
    sub rsp,64
    mov [rsp+24],eax
    cmp byte ptr [rdi],'+'; jne 1f; inc rdi
1:  mov rcx,rdi
    cmp byte ptr [rcx],'-'; jne 2f; inc rcx
2:  cmp byte ptr [rcx],'0'; jb .pfi_bad
    cmp byte ptr [rcx],'9'; ja .pfi_bad
    xor ecx,ecx
3:  cmp byte ptr [rdi+rcx],0; je 4f
    inc rcx; jmp 3b
4:  mov qword ptr [rsp],4
    mov [rsp+8],rdi; mov [rsp+16],rcx
    mov rax,rsp
    cmp dword ptr [rsp+24],32; jne 5f
    call node_parse_f32_bits; jmp 6f
5:  call node_parse_f64_bits
6:
    add rsp,64; ret
.pfi_bad:
    xor eax,eax; mov edx,1; add rsp,64; ret
.equ J_NUMBER,4
.equ J_STRING,3
.include "compiler/numeric_literal_parser.inc"
