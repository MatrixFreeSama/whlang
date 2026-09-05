# ---------------------------------------------------------------------------
# Schedulerless execution
# ---------------------------------------------------------------------------
slot_loop:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
.sl_again:
    lea rax, [rip+slot_epoch]
    mov r15d, dword ptr [rax+rbx*4]
    mov edi, ebx
    call pop_local
    cmp eax, EMPTY
    jne .sl_have_node
    mov edi, ebx
    call take_mailbox
    cmp eax, EMPTY
    jne .sl_have_node
    lea rax, [rip+home_remaining]
    cmp dword ptr [rax+rbx*4], 0
    je .sl_ok
    lea rax, [rip+metric_waits]
    inc qword ptr [rax+rbx*8]
    mov eax, SYS_futex
    lea rdi, [rip+slot_epoch]
    lea rdi, [rdi+rbx*4]
    mov esi, FUTEX_WAIT
    mov edx, r15d
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
    jmp .sl_again
.sl_have_node:
    mov r12d, eax
    mov edi, ebx
    mov esi, r12d
    call claim_node
    test eax, eax
    jz .sl_fail
    mov edi, r12d
    call execute_synthetic_work
    mov edi, ebx
    mov esi, r12d
    call publish_completion
    test eax, eax
    jnz .sl_fail
    jmp .sl_again
.sl_ok:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.sl_fail:
    mov eax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

pop_local:
    lea rax, [rip+slot_sp]
    mov ecx, dword ptr [rax+rdi*4]
    test ecx, ecx
    jz .pl_empty
    dec ecx
    mov dword ptr [rax+rdi*4], ecx
    mov eax, edi
    imul eax, eax, MAX_NODES
    add eax, ecx
    lea rdx, [rip+local_stack]
    mov eax, dword ptr [rdx+rax*4]
    ret
.pl_empty:
    mov eax, EMPTY
    ret

push_local:
    lea rax, [rip+slot_sp]
    mov ecx, dword ptr [rax+rdi*4]
    cmp ecx, MAX_NODES
    jae .pL_fail
    mov eax, edi
    imul eax, eax, MAX_NODES
    add eax, ecx
    lea rdx, [rip+local_stack]
    mov dword ptr [rdx+rax*4], esi
    lea rax, [rip+slot_sp]
    inc dword ptr [rax+rdi*4]
    xor eax, eax
    ret
.pL_fail:
    mov eax, 1
    ret

take_mailbox:
    mov eax, EMPTY
    lea rcx, [rip+mailbox]
    xchg eax, dword ptr [rcx+rdi*4]
    ret

claim_node:
    lea rcx, [rip+node_state]
    mov al, 1
    mov dl, 2
    lock cmpxchg byte ptr [rcx+rsi], dl
    jne .cn_no
    lea rcx, [rip+metric_claims]
    inc qword ptr [rcx+rdi*8]
    mov eax, 1
    ret
.cn_no:
    xor eax, eax
    ret

execute_synthetic_work:
    lea rax, [rip+work_iters]
    mov ecx, dword ptr [rax+rdi*4]
    mov r8, 0x9e3779b97f4a7c15
    mov eax, edi
    inc rax
.esw_loop:
    test ecx, ecx
    jz .esw_done
    imul rax, r8
    ror rax, 17
    add rax, 0x27d4eb2d
    dec ecx
    jmp .esw_loop
.esw_done:
    lea rcx, [rip+node_results]
    mov qword ptr [rcx+rdi*8], rax
    ret

publish_completion:
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12d, esi
    lea rcx, [rip+node_state]
    mov al, 2
    mov dl, 3
    lock cmpxchg byte ptr [rcx+r12], dl
    jne .pc_fail
    lea rax, [rip+home_slot]
    mov r13d, dword ptr [rax+r12*4]
    lea rax, [rip+home_remaining]
    lock sub dword ptr [rax+r13*4], 1
    jc .pc_fail
    jnz .pc_edges
    mov edi, r13d
    call wake_slot
.pc_edges:
    lea rax, [rip+first_out]
    mov r14d, dword ptr [rax+r12*4]
.pc_edge_loop:
    cmp r14d, EMPTY
    je .pc_ok
    lea rax, [rip+metric_edges]
    inc qword ptr [rax+rbx*8]
    lea rax, [rip+edge_v]
    mov r13d, dword ptr [rax+r14*4]
    lea rax, [rip+remaining_deps]
    lock sub dword ptr [rax+r13*4], 1
    jc .pc_fail
    jnz .pc_next
    lea rcx, [rip+node_state]
    mov al, 0
    mov dl, 1
    lock cmpxchg byte ptr [rcx+r13], dl
    jne .pc_fail
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    call dispatch_ready
    test eax, eax
    jnz .pc_fail
.pc_next:
    lea rax, [rip+next_edge]
    mov r14d, dword ptr [rax+r14*4]
    jmp .pc_edge_loop
.pc_ok:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.pc_fail:
    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

dispatch_ready:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, edx
    lea rax, [rip+home_slot]
    mov r13d, dword ptr [rax+r12*4]
    cmp r13d, ebx
    jne .dr_remote
    mov edi, ebx
    mov esi, r12d
    call push_local
    test eax, eax
    jnz .dr_fail
    lea rax, [rip+metric_direct]
    inc qword ptr [rax+rbx*8]
    xor eax, eax
    jmp .dr_done
.dr_remote:
    mov eax, EMPTY
    lea rcx, [rip+mailbox]
    mov edx, r12d
    lock cmpxchg dword ptr [rcx+r13*4], edx
    jne .dr_collision
    lea rax, [rip+metric_remote]
    inc qword ptr [rax+rbx*8]
    mov edi, r13d
    call wake_slot
    xor eax, eax
    jmp .dr_done
.dr_collision:
    lea rax, [rip+metric_collisions]
    inc qword ptr [rax+rbx*8]
    mov edi, ebx
    mov esi, r12d
    call push_local
    test eax, eax
    jnz .dr_fail
    lea rax, [rip+metric_fallbacks]
    inc qword ptr [rax+rbx*8]
    xor eax, eax
    jmp .dr_done
.dr_fail:
    mov eax, 1
.dr_done:
    pop r13
    pop r12
    pop rbx
    ret

wake_slot:
    push rbx
    mov ebx, edi
    lea rcx, [rip+slot_epoch]
    lock inc dword ptr [rcx+rbx*4]
    mov eax, SYS_futex
    lea rdi, [rip+slot_epoch]
    lea rdi, [rdi+rbx*4]
    mov esi, FUTEX_WAKE
    mov edx, 1
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
    pop rbx
    ret
