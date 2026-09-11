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
    call take_remote
    cmp eax, EMPTY
    jne .sl_have_node
    lea rax, [rip+home_remaining]
    cmp dword ptr [rax+rbx*4], 0
    je .sl_ok

    # Publish sleeping intent before the second remote check. A producer that
    # races after this point either wakes us or changes slot_epoch so FUTEX_WAIT
    # cannot sleep on stale causal time.
    lea rax, [rip+slot_parked]
    mov dword ptr [rax+rbx*4], 1
    mov edi, ebx
    call take_remote
    cmp eax, EMPTY
    jne .sl_unpark_have
    lea rax, [rip+home_remaining]
    cmp dword ptr [rax+rbx*4], 0
    je .sl_unpark_ok
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
    lea rax, [rip+slot_parked]
    mov dword ptr [rax+rbx*4], 0
    jmp .sl_again
.sl_unpark_have:
    lea rcx, [rip+slot_parked]
    mov dword ptr [rcx+rbx*4], 0
    jmp .sl_have_node
.sl_unpark_ok:
    lea rax, [rip+slot_parked]
    mov dword ptr [rax+rbx*4], 0
    jmp .sl_ok
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

# Per-slot MPSC causal inbox. It is not a runnable-work queue: only a producer
# whose declared dependency transition reached exactly zero can publish a node,
# and only the AOT home slot consumes its own inbox.
take_remote:
    lea rcx, [rip+remote_cache]
    mov eax, dword ptr [rcx+rdi*4]
    cmp eax, EMPTY
    jne .tr_have
    mov eax, EMPTY
    lea rcx, [rip+remote_head]
    xchg eax, dword ptr [rcx+rdi*4]
    cmp eax, EMPTY
    je .tr_empty
.tr_have:
    mov edx, eax
    lea rcx, [rip+ready_next]
    mov eax, dword ptr [rcx+rdx*4]
    lea rcx, [rip+remote_cache]
    mov dword ptr [rcx+rdi*4], eax
    mov eax, edx
    ret
.tr_empty:
    mov eax, EMPTY
    ret

# Node readiness is single-publication by construction: a source is seeded once,
# or exactly one predecessor observes remaining_deps transition to zero. Because
# every ready node executes on its AOT home slot, claim/completion state changes
# do not need cache-line-locking atomics.
claim_node:
    lea rcx, [rip+node_state]
    cmp byte ptr [rcx+rsi], 1
    jne .cn_no
    mov byte ptr [rcx+rsi], 2
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
    cmp byte ptr [rcx+r12], 2
    jne .pc_fail
    mov byte ptr [rcx+r12], 3

    # Home ownership is exact after collision-free causal inbox delivery.
    lea rax, [rip+home_slot]
    mov r13d, dword ptr [rax+r12*4]
    cmp r13d, ebx
    jne .pc_fail
    lea rax, [rip+home_remaining]
    sub dword ptr [rax+r13*4], 1
    jc .pc_fail

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

    # This remains atomic: distinct predecessor slots may complete concurrently.
    lea rax, [rip+remaining_deps]
    lock sub dword ptr [rax+r13*4], 1
    jc .pc_fail
    jnz .pc_next

    # Exactly one predecessor can observe the zero transition, so it is the
    # unique publisher of this consumer's ready state.
    lea rcx, [rip+node_state]
    cmp byte ptr [rcx+r13], 0
    jne .pc_fail
    mov byte ptr [rcx+r13], 1
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
    # Lock-free MPSC stack local to the destination slot. Each ready node owns a
    # single next link, so concurrent producers never need a global queue or a
    # collision fallback onto the producer.
    lea rcx, [rip+remote_head]
.dr_push:
    mov eax, dword ptr [rcx+r13*4]
    lea rdx, [rip+ready_next]
    mov dword ptr [rdx+r12*4], eax
    mov edx, r12d
    lock cmpxchg dword ptr [rcx+r13*4], edx
    jne .dr_push
    lea rax, [rip+metric_remote]
    inc qword ptr [rax+rbx*8]
    mov edi, r13d
    call wake_slot
    xor eax, eax
    jmp .dr_done
.dr_fail:
    mov eax, 1
.dr_done:
    pop r13
    pop r12
    pop rbx
    ret

# Event-count wake. A remote producer always advances causal time but enters the
# kernel only when the destination slot has actually published a parked state.
wake_slot:
    push rbx
    mov ebx, edi
    lea rcx, [rip+slot_epoch]
    lock inc dword ptr [rcx+rbx*4]
    xor eax, eax
    lea rcx, [rip+slot_parked]
    xchg eax, dword ptr [rcx+rbx*4]
    test eax, eax
    jz .ws_done
    mov eax, SYS_futex
    lea rdi, [rip+slot_epoch]
    lea rdi, [rdi+rbx*4]
    mov esi, FUTEX_WAKE
    mov edx, 1
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
.ws_done:
    pop rbx
    ret
