# ---------------------------------------------------------------------------
# Causal lifecycle tree. This is resource materialization / final join, not a
# runnable-work dispatcher. There is no O(P) root spawn or wait sweep.
# run_slot_tree(edi=lo, esi=hi) -> eax 0/1
# ---------------------------------------------------------------------------
run_slot_tree:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    mov r12d, edi
    mov r13d, esi
    mov eax, r13d
    sub eax, r12d
    cmp eax, 1
    jne .rst_internal
    mov edi, r12d
    call slot_loop
    jmp .rst_return

.rst_internal:
    mov eax, r12d
    add eax, r13d
    shr eax, 1
    mov r14d, eax

    mov eax, SYS_mmap
    xor edi, edi
    mov esi, CHILD_STACK_SIZE
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE_ANON_STACK
    mov r8, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js .rst_fail
    mov [rsp+8], rax
    lea rsi, [rax+CHILD_STACK_SIZE-16]

    mov eax, SYS_clone
    mov edi, CLONE_VM_FILES_FS_SIGCHLD
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    syscall
    test rax, rax
    js .rst_unmap_fail
    jz .rst_child
    mov [rsp+16], rax

    mov edi, r12d
    mov esi, r14d
    call run_slot_tree
    test eax, eax
    jnz .rst_parent_child_failed

    mov eax, SYS_wait4
    mov rdi, [rsp+16]
    lea rsi, [rsp+24]
    xor edx, edx
    xor r10d, r10d
    syscall
    test rax, rax
    js .rst_parent_child_failed
    cmp dword ptr [rsp+24], 0
    jne .rst_parent_child_failed

    mov eax, SYS_munmap
    mov rdi, [rsp+8]
    mov esi, CHILD_STACK_SIZE
    syscall
    xor eax, eax
    jmp .rst_return

.rst_child:
    mov edi, r14d
    mov esi, r13d
    call run_slot_tree
    test eax, eax
    jnz .rst_child_fail
    xor edi, edi
    mov eax, SYS_exit
    syscall
    hlt
.rst_child_fail:
    mov edi, 70
    mov eax, SYS_exit
    syscall
    hlt

.rst_parent_child_failed:
    mov eax, SYS_munmap
    mov rdi, [rsp+8]
    mov esi, CHILD_STACK_SIZE
    syscall
    mov eax, 1
    jmp .rst_return
.rst_unmap_fail:
    mov rbx, rax
    mov eax, SYS_munmap
    mov rdi, [rsp+8]
    mov esi, CHILD_STACK_SIZE
    syscall
    mov rax, rbx
.rst_fail:
    mov eax, 1
.rst_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
