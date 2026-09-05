.intel_syntax noprefix

# Wheelchair 1.2.6 Schedulerless Sparse Causal Execution proof runtime.
# Linux x86-64, static, no libc, no pthread, no global work queue.
# Runtime readiness is produced only by dependency-edge zero transitions.
# A ready successor continues locally or is handed directly to its AOT home slot.

.equ SYS_write, 1
.equ SYS_exit, 60
.equ SYS_exit_group, 231
.equ SYS_clone, 56
.equ SYS_wait4, 61
.equ SYS_futex, 202
.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ FUTEX_WAIT, 0
.equ FUTEX_WAKE, 1
.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ PROT_RW, 3
.equ MAP_PRIVATE_ANON_STACK, 0x20022
.equ CHILD_STACK_SIZE, 65536
.equ MAX_NODES, 64
.equ MAX_EDGES, 256
.equ MAX_SLOTS, 16
.equ EMPTY, -1

.section .text
.global _start
_start:
    mov r15, rsp
    mov r14, [r15]
    lea r13, [r15+8]
    cmp r14, 4
    jl usage_error
    call clear_state

    mov rdi, [r13+8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    test eax, eax
    jz parse_error
    cmp eax, MAX_NODES
    ja parse_error
    mov dword ptr [rip+node_count], eax
    mov r10d, eax

    mov rdi, [r13+16]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, MAX_EDGES
    ja parse_error
    mov dword ptr [rip+edge_count], eax
    mov r11d, eax

    mov rdi, [r13+24]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    test eax, eax
    jz parse_error
    cmp eax, MAX_SLOTS
    ja parse_error
    mov dword ptr [rip+slot_count], eax

    mov eax, r10d
    shl eax, 1
    mov ecx, r11d
    shl ecx, 1
    add eax, ecx
    add eax, 4
    cmp r14d, eax
    jne usage_error
    mov dword ptr [rip+arg_index], 4

    xor ebx, ebx
.parse_home:
    cmp ebx, dword ptr [rip+node_count]
    jae .parse_work
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, dword ptr [rip+slot_count]
    jae parse_error
    lea rcx, [rip+home_slot]
    mov dword ptr [rcx+rbx*4], eax
    lea rcx, [rip+home_remaining]
    add dword ptr [rcx+rax*4], 1
    inc dword ptr [rip+arg_index]
    inc ebx
    jmp .parse_home

.parse_work:
    xor ebx, ebx
.parse_work_loop:
    cmp ebx, dword ptr [rip+node_count]
    jae .parse_edges
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    lea rcx, [rip+work_iters]
    mov dword ptr [rcx+rbx*4], eax
    inc dword ptr [rip+arg_index]
    inc ebx
    jmp .parse_work_loop

.parse_edges:
    xor ebx, ebx
.edge_loop:
    cmp ebx, dword ptr [rip+edge_count]
    jae .validate
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, dword ptr [rip+node_count]
    jae parse_error
    mov r12d, eax
    inc dword ptr [rip+arg_index]
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, dword ptr [rip+node_count]
    jae parse_error
    mov r9d, eax
    inc dword ptr [rip+arg_index]
    lea rcx, [rip+edge_v]
    mov dword ptr [rcx+rbx*4], r9d
    lea rcx, [rip+first_out]
    mov eax, dword ptr [rcx+r12*4]
    lea rdx, [rip+next_edge]
    mov dword ptr [rdx+rbx*4], eax
    mov dword ptr [rcx+r12*4], ebx
    lea rcx, [rip+remaining_deps]
    add dword ptr [rcx+r9*4], 1
    lea rcx, [rip+proof_indegree]
    add dword ptr [rcx+r9*4], 1
    inc ebx
    jmp .edge_loop

.validate:
    call prove_dag
    test eax, eax
    jnz cycle_error
    call seed_sources
    test eax, eax
    jnz runtime_error
    xor edi, edi
    mov esi, dword ptr [rip+slot_count]
    call run_slot_tree
    test eax, eax
    jnz runtime_error
    call verify_final
    test eax, eax
    jnz runtime_error
    call aggregate_metrics
    call print_result_json
    xor edi, edi
    jmp exit_group
