.intel_syntax noprefix

# Wheelchair 1.2.9 blind-release general parallel fabric.
#
# Execution doctrine:
#   * a node knows only its true data-dependency neighbors;
#   * readiness is remaining_deps -> 0;
#   * no node, finisher, or producer selects a worker or resource consumer;
#   * no home slot, runnable queue, inbox, work stealing, resource token routing,
#     peer-load query, or idle spin exists;
#   * every causal node has a finite execution context. While dependencies are
#     absent it sleeps in the kernel; after completion it publishes only true
#     dependency transitions and returns/exits;
#   * requested width is an inherited CPU-affinity envelope. Linux chooses which
#     runnable task uses which CPU inside that envelope; the CPU microarchitecture
#     decides its own internal silicon allocation.
#
# This binary is linked at VMA 0 and copied into the direct-general program slot.
# Every internal reference is RIP-relative. Fragment entry offsets are patched AOT.

.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ SYS_clone, 56
.equ SYS_wait4, 61
.equ SYS_exit, 60
.equ SYS_futex, 202
.equ SYS_sched_setaffinity, 203
.equ SYS_sched_getaffinity, 204

.equ FUTEX_WAIT, 0
.equ FUTEX_WAKE, 1
.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ PROT_RW, 3
.equ MAP_PRIVATE_ANON_STACK, 0x20022
.equ MAP_PRIVATE_ANON, 0x22

.equ GR_MAX_NODES, 96
.equ GR_MAX_EDGES, 1024
.equ GR_MAX_CPUS, 4
.equ GR_STACK_BYTES, 65536
.equ GR_AFF_BYTES, 128

.equ ST_REMAIN, 0
.equ ST_DONE, ST_REMAIN + GR_MAX_NODES*4
.equ ST_SIZE, 4096

.section .text
.p2align 6
.global gr_release_base
gr_release_base:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 272

    mov eax, dword ptr [rip+gr_node_count]
    test eax, eax
    jz .gr_ok_no_state
    cmp eax, GR_MAX_NODES
    ja .gr_fail_no_state
    mov eax, dword ptr [rip+gr_edge_count]
    cmp eax, GR_MAX_EDGES
    ja .gr_fail_no_state
    mov eax, dword ptr [rip+gr_cpu_width]
    test eax, eax
    jz .gr_fail_no_state
    cmp eax, GR_MAX_CPUS
    ja .gr_fail_no_state

    lea rdi, [rsp]
    lea rsi, [rsp+128]
    mov edx, dword ptr [rip+gr_cpu_width]
    call gr_enter_affinity
    test eax, eax
    jnz .gr_fail_no_state

    mov eax, SYS_mmap
    xor edi, edi
    mov esi, ST_SIZE
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE_ANON
    mov r8d, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js .gr_restore_fail
    mov r15, rax
    mov qword ptr [rsp+256], rax

    call gr_init_state
    test eax, eax
    jnz .gr_state_fail

    xor edi, edi
    mov esi, dword ptr [rip+gr_node_count]
    call gr_run_node_tree
    mov r14d, eax

    mov eax, SYS_munmap
    mov rdi, qword ptr [rsp+256]
    mov esi, ST_SIZE
    syscall

    lea rdi, [rsp]
    call gr_restore_affinity
    test eax, eax
    jnz .gr_fail_no_state
    mov eax, r14d
    jmp .gr_done

.gr_state_fail:
    mov eax, SYS_munmap
    mov rdi, qword ptr [rsp+256]
    mov esi, ST_SIZE
    syscall
.gr_restore_fail:
    lea rdi, [rsp]
    call gr_restore_affinity
.gr_fail_no_state:
    mov eax, 1
    jmp .gr_done
.gr_ok_no_state:
    xor eax, eax
.gr_done:
    add rsp, 272
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# rdi=original mask, rsi=selected mask, edx=requested width.
# The mask is an execution envelope, never a node->CPU assignment.
gr_enter_affinity:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx

    mov eax, SYS_sched_getaffinity
    xor edi, edi
    mov esi, GR_AFF_BYTES
    mov rdx, r12
    syscall
    test rax, rax
    js .gea_fail

    mov rdi, r13
    xor eax, eax
    mov ecx, GR_AFF_BYTES/8
    rep stosq

    xor ebx, ebx
    xor r10d, r10d
.gea_scan:
    cmp ebx, GR_AFF_BYTES*8
    jae .gea_scanned
    mov eax, ebx
    mov ecx, eax
    and ecx, 63
    shr eax, 6
    bt qword ptr [r12+rax*8], rcx
    jnc .gea_next
    bts qword ptr [r13+rax*8], rcx
    inc r10d
    cmp r10d, r14d
    je .gea_apply
.gea_next:
    inc ebx
    jmp .gea_scan
.gea_scanned:
    cmp r10d, r14d
    jne .gea_fail
.gea_apply:
    mov eax, SYS_sched_setaffinity
    xor edi, edi
    mov esi, GR_AFF_BYTES
    mov rdx, r13
    syscall
    test rax, rax
    js .gea_fail
    xor eax, eax
    jmp .gea_done
.gea_fail:
    mov eax, 1
.gea_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

gr_restore_affinity:
    mov rdx, rdi
    mov eax, SYS_sched_setaffinity
    xor edi, edi
    mov esi, GR_AFF_BYTES
    syscall
    test rax, rax
    js .gra_fail
    xor eax, eax
    ret
.gra_fail:
    mov eax, 1
    ret

gr_init_state:
    xor ecx, ecx
    lea rdx, [rip+gr_indegree]
.gis_loop:
    cmp ecx, dword ptr [rip+gr_node_count]
    jae .gis_ok
    mov eax, dword ptr [rdx+rcx*4]
    mov dword ptr [r15+ST_REMAIN+rcx*4], eax
    mov byte ptr [r15+ST_DONE+rcx], 0
    inc ecx
    jmp .gis_loop
.gis_ok:
    xor eax, eax
    ret

# Binary lifecycle materialization. It creates and joins finite node contexts;
# it never selects which CPU executes a node and carries no resource ownership.
gr_run_node_tree:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov r12d, edi
    mov r13d, esi
    mov eax, r13d
    sub eax, r12d
    cmp eax, 1
    jne .grt_internal

    mov edi, r12d
    call gr_node_task
    jmp .grt_return

.grt_internal:
    mov eax, r12d
    add eax, r13d
    shr eax, 1
    mov r14d, eax

    mov eax, SYS_mmap
    xor edi, edi
    mov esi, GR_STACK_BYTES
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE_ANON_STACK
    mov r8d, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js .grt_fail
    mov qword ptr [rsp+8], rax
    lea rsi, [rax+GR_STACK_BYTES-16]

    mov eax, SYS_clone
    mov edi, CLONE_VM_FILES_FS_SIGCHLD
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    syscall
    test rax, rax
    js .grt_unmap_fail
    jz .grt_child
    mov qword ptr [rsp+16], rax

    mov edi, r12d
    mov esi, r14d
    call gr_run_node_tree
    mov ebx, eax

    mov eax, SYS_wait4
    mov rdi, qword ptr [rsp+16]
    lea rsi, [rsp+24]
    xor edx, edx
    xor r10d, r10d
    syscall
    test rax, rax
    js .grt_parent_fail
    cmp dword ptr [rsp+24], 0
    jne .grt_parent_fail
    test ebx, ebx
    jnz .grt_parent_fail

    mov eax, SYS_munmap
    mov rdi, qword ptr [rsp+8]
    mov esi, GR_STACK_BYTES
    syscall
    xor eax, eax
    jmp .grt_return

.grt_child:
    mov edi, r14d
    mov esi, r13d
    call gr_run_node_tree
    test eax, eax
    jnz .grt_child_fail
    xor edi, edi
    mov eax, SYS_exit
    syscall
    ud2
.grt_child_fail:
    mov edi, 70
    mov eax, SYS_exit
    syscall
    ud2

.grt_parent_fail:
    mov eax, SYS_munmap
    mov rdi, qword ptr [rsp+8]
    mov esi, GR_STACK_BYTES
    syscall
.grt_fail:
    mov eax, 1
    jmp .grt_return
.grt_unmap_fail:
    mov eax, SYS_munmap
    mov rdi, qword ptr [rsp+8]
    mov esi, GR_STACK_BYTES
    syscall
    mov eax, 1
.grt_return:
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# A node waits only on its own dependency count. FUTEX_WAIT releases the CPU.
# Completion wakes a causal node, never a worker; the kernel chooses the CPU.
gr_node_task:
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
.gnt_wait:
    mov eax, dword ptr [r15+ST_REMAIN+rbx*4]
    test eax, eax
    jz .gnt_run
    mov r12d, eax
    mov eax, SYS_futex
    lea rdi, [r15+ST_REMAIN+rbx*4]
    mov esi, FUTEX_WAIT
    mov edx, r12d
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
    jmp .gnt_wait

.gnt_run:
    cmp byte ptr [r15+ST_DONE+rbx], 0
    jne .gnt_fail

    lea rdx, [rip+gr_entry_offsets]
    mov eax, dword ptr [rdx+rbx*4]
    test eax, eax
    jz .gnt_fail
    lea r13, [rip+gr_release_base]
    add r13, rax

    push r15
    push rbx
    push r12
    push r13
    push r14
    call r13
    pop r14
    pop r13
    pop r12
    pop rbx
    pop r15

    mov byte ptr [r15+ST_DONE+rbx], 1

    lea rdx, [rip+gr_first_out]
    mov r14d, dword ptr [rdx+rbx*4]
.gnt_edges:
    cmp r14d, -1
    je .gnt_ok
    cmp r14d, dword ptr [rip+gr_edge_count]
    jae .gnt_fail
    lea rdx, [rip+gr_edge_v]
    mov r12d, dword ptr [rdx+r14*4]
    cmp r12d, dword ptr [rip+gr_node_count]
    jae .gnt_fail
    lock sub dword ptr [r15+ST_REMAIN+r12*4], 1
    jc .gnt_fail
    jnz .gnt_next

    mov eax, SYS_futex
    lea rdi, [r15+ST_REMAIN+r12*4]
    mov esi, FUTEX_WAKE
    mov edx, 1
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
.gnt_next:
    lea rdx, [rip+gr_next_edge]
    mov r14d, dword ptr [rdx+r14*4]
    jmp .gnt_edges

.gnt_ok:
    xor eax, eax
    jmp .gnt_done
.gnt_fail:
    mov eax, 1
.gnt_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.p2align 6
.global gr_node_count
gr_node_count: .long 0
.global gr_edge_count
gr_edge_count: .long 0
.global gr_cpu_width
gr_cpu_width: .long 0
.p2align 4
.global gr_indegree
gr_indegree: .fill GR_MAX_NODES,4,0
.global gr_first_out
gr_first_out: .fill GR_MAX_NODES,4,0xff
.global gr_edge_v
gr_edge_v: .fill GR_MAX_EDGES,4,0
.global gr_next_edge
gr_next_edge: .fill GR_MAX_EDGES,4,0xff
.global gr_entry_offsets
gr_entry_offsets: .fill GR_MAX_NODES,4,0

.p2align 4
.global gr_template_end
gr_template_end:
