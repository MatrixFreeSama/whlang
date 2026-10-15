# Cold launch InputFact materialization; one authority for all widths and ranks.
parse_input_facts:
    push rbx; push r12; push r13; push r14
    mov r12,[rip+input_count_patch]
    lea rax,[r12+1]
    cmp rax,[r15]; jne .pif_bad
    mov rsi,r12; shl rsi,3; jc .pif_bad
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_RW
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .pif_bad
    mov [rip+input_values],rax
    mov r13,[rip+input_table_patch]; xor ebx,ebx
.pif_next:
    cmp rbx,r12; jae .pif_extent
    mov rdi,[r15+rbx*8+16]
    cmp qword ptr [r13],2; je .pif_float
    call parse_u64
    test edx,edx; jnz .pif_bad
    mov edi,3; jmp .pif_range
.pif_float:
    call parse_f64
    test edx,edx; jnz .pif_bad
    mov edi,5
.pif_range:
    lea rsi,[r13+8]; call input_range_check
    test edx,edx; jnz .pif_bad
.pif_store:
    cmp qword ptr [r13],2; jne .pif_value_store
    mov rdx,rax; shr rdx,52; and edx,0x7ff
    cmp edx,0x7ff; jne .pif_value_store
    mov dword ptr [rip+support_mode_patch],0
.pif_value_store:
    mov r14,[rip+input_values]; mov [r14+rbx*8],rax
    inc rbx; add r13,32; jmp .pif_next
.pif_extent:
    mov rbx,[rip+extent_input_patch]
    cmp rbx,r12; jae .pif_bad
    mov rax,[r14+rbx*8]; xor edx,edx; jmp .pif_done
.pif_bad:
    xor eax,eax; mov edx,1
.pif_done:
    pop r14; pop r13; pop r12; pop rbx; ret

.include "runtime/input_range_relation.inc"
INPUT_RANGE_RELATION input_range_check
