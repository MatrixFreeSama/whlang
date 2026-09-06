.intel_syntax noprefix

# Generic binding-level causal executor that is linked into the existing
# direct-general program_slot.  It owns no language semantics: the mature
# handwritten general frontend still emits every expression/reduction/iterate
# instruction.  This engine only activates already-emitted native fragments when
# their true data-dependency count reaches zero.
#
# The binary is linked at VMA 0 and objcopied to raw bytes.  Every internal
# reference is RIP-relative; fragment entry offsets are patched AOT.

.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ SYS_clone, 56
.equ SYS_wait4, 61
.equ SYS_exit, 60
.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ PROT_RW, 3
.equ MAP_PRIVATE_ANON, 0x22

.equ GP_MAX_NODES, 96
.equ GP_MAX_EDGES, 1024
.equ GP_MAX_SLOTS, 4
.equ GP_EMPTY, -1
.equ GP_STACK_BYTES, 65536

# Shared RW state allocated once by the parent.  CLONE_VM makes this one causal
# state image for every executor without a global runnable queue.
.equ ST_REMAIN, 0
.equ ST_HEAD, ST_REMAIN + GP_MAX_NODES*4
.equ ST_CACHE, ST_HEAD + GP_MAX_SLOTS*4
.equ ST_NEXT, ST_CACHE + GP_MAX_SLOTS*4
.equ ST_HOME_REMAIN, ST_NEXT + GP_MAX_NODES*4
.equ ST_PIDS, ST_HOME_REMAIN + GP_MAX_SLOTS*4
.equ ST_SIZE, 4096

.section .text
.p2align 6
.global gp_slot_base
gp_slot_base:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov eax, dword ptr [rip+gp_node_count]
    test eax, eax
    jz .gp_parent_ok
    cmp eax, GP_MAX_NODES
    ja .gp_parent_fail
    mov eax, dword ptr [rip+gp_edge_count]
    cmp eax, GP_MAX_EDGES
    ja .gp_parent_fail
    mov eax, dword ptr [rip+gp_slot_count]
    test eax, eax
    jz .gp_parent_fail
    cmp eax, GP_MAX_SLOTS
    ja .gp_parent_fail

    # causal state
    mov eax, SYS_mmap
    xor edi, edi
    mov esi, ST_SIZE
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE_ANON
    mov r8d, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js .gp_parent_fail
    mov r15, rax

    # child-stack pool; slot zero keeps the caller's original stack.
    mov eax, SYS_mmap
    xor edi, edi
    mov esi, GP_STACK_BYTES*GP_MAX_SLOTS
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE_ANON
    mov r8d, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js .gp_state_fail
    mov r13, rax

    call gp_init_state
    test eax, eax
    jnz .gp_both_fail

    # Spawn one owner per requested nonzero slot.  There is no root scheduler:
    # children immediately consume only their own causal inbox, while the parent
    # becomes owner zero.
    mov ebx, 1
.gp_spawn_loop:
    cmp ebx, dword ptr [rip+gp_slot_count]
    jae .gp_parent_worker
    mov r14d, ebx
    mov rsi, r13
    mov eax, ebx
    imul rax, GP_STACK_BYTES
    add rsi, rax
    add rsi, GP_STACK_BYTES-16
    mov eax, SYS_clone
    mov edi, CLONE_VM_FILES_FS_SIGCHLD
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    syscall
    test rax, rax
    jz .gp_child_entry
    js .gp_both_fail
    lea rcx, [r15+ST_PIDS]
    mov qword ptr [rcx+rbx*8], rax
    inc ebx
    jmp .gp_spawn_loop

.gp_child_entry:
    mov edi, r14d
    call gp_worker
    mov edi, eax
    mov eax, SYS_exit
    syscall
    ud2

.gp_parent_worker:
    xor edi, edi
    call gp_worker
    test eax, eax
    jnz .gp_both_fail

    mov ebx, 1
.gp_wait_loop:
    cmp ebx, dword ptr [rip+gp_slot_count]
    jae .gp_cleanup_ok
    lea rcx, [r15+ST_PIDS]
    mov rdi, qword ptr [rcx+rbx*8]
    test rdi, rdi
    jz .gp_both_fail
    mov eax, SYS_wait4
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    syscall
    test rax, rax
    js .gp_both_fail
    inc ebx
    jmp .gp_wait_loop

.gp_cleanup_ok:
    mov eax, SYS_munmap
    mov rdi, r13
    mov esi, GP_STACK_BYTES*GP_MAX_SLOTS
    syscall
    mov eax, SYS_munmap
    mov rdi, r15
    mov esi, ST_SIZE
    syscall
.gp_parent_ok:
    xor eax, eax
    jmp .gp_parent_done

.gp_both_fail:
    mov eax, SYS_munmap
    mov rdi, r13
    mov esi, GP_STACK_BYTES*GP_MAX_SLOTS
    syscall
.gp_state_fail:
    mov eax, SYS_munmap
    mov rdi, r15
    mov esi, ST_SIZE
    syscall
.gp_parent_fail:
    mov eax, 1
.gp_parent_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Initialize mutable indegrees, per-slot ownership counts and all inbox links.
# Sources are causally published before any child starts.
gp_init_state:
    xor ecx, ecx
.gis_nodes:
    cmp ecx, dword ptr [rip+gp_node_count]
    jae .gis_slots
    mov eax, dword ptr [rip+gp_indegree+rcx*4]
    mov dword ptr [r15+ST_REMAIN+rcx*4], eax
    mov dword ptr [r15+ST_NEXT+rcx*4], GP_EMPTY
    inc ecx
    jmp .gis_nodes
.gis_slots:
    xor ecx, ecx
.gis_slot_loop:
    cmp ecx, dword ptr [rip+gp_slot_count]
    jae .gis_sources
    mov dword ptr [r15+ST_HEAD+rcx*4], GP_EMPTY
    mov dword ptr [r15+ST_CACHE+rcx*4], GP_EMPTY
    mov eax, dword ptr [rip+gp_home_initial+rcx*4]
    mov dword ptr [r15+ST_HOME_REMAIN+rcx*4], eax
    inc ecx
    jmp .gis_slot_loop
.gis_sources:
    xor ecx, ecx
.gis_source_loop:
    cmp ecx, dword ptr [rip+gp_node_count]
    jae .gis_ok
    cmp dword ptr [rip+gp_indegree+rcx*4], 0
    jne .gis_source_next
    mov esi, ecx
    call gp_enqueue
    test eax, eax
    jnz .gis_fail
.gis_source_next:
    inc ecx
    jmp .gis_source_loop
.gis_ok:
    xor eax, eax
    ret
.gis_fail:
    mov eax, 1
    ret

# edi=slot.  One consumer exists per slot.  Producers may be any predecessor
# owner, so ingress is an MPSC stack and the detached chain is cached locally.
gp_take_ready:
    mov eax, dword ptr [r15+ST_CACHE+rdi*4]
    cmp eax, GP_EMPTY
    jne .gtr_have
    mov eax, GP_EMPTY
    xchg eax, dword ptr [r15+ST_HEAD+rdi*4]
    cmp eax, GP_EMPTY
    je .gtr_empty
.gtr_have:
    mov edx, dword ptr [r15+ST_NEXT+rax*4]
    mov dword ptr [r15+ST_CACHE+rdi*4], edx
    ret
.gtr_empty:
    mov eax, GP_EMPTY
    ret

# esi=node.  Home is AOT data.  Exactly one predecessor can observe the
# remaining-dependency zero transition, therefore every node is published once.
gp_enqueue:
    mov edx, dword ptr [rip+gp_home_slots+rsi*4]
    cmp edx, dword ptr [rip+gp_slot_count]
    jae .ge_bad
    lea r8, [r15+ST_HEAD]
.ge_retry:
    mov eax, dword ptr [r8+rdx*4]
    mov dword ptr [r15+ST_NEXT+rsi*4], eax
    lock cmpxchg dword ptr [r8+rdx*4], esi
    jne .ge_retry
    xor eax, eax
    ret
.ge_bad:
    mov eax, 1
    ret

# edi=slot.  No work stealing, no global ready scan and no runtime selector.
# A worker leaves only after every node whose AOT home is that slot completed.
gp_worker:
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
.gw_loop:
    mov edi, ebx
    call gp_take_ready
    cmp eax, GP_EMPTY
    jne .gw_have
    cmp dword ptr [r15+ST_HOME_REMAIN+rbx*4], 0
    je .gw_ok
    pause
    jmp .gw_loop

.gw_have:
    mov r12d, eax
    mov eax, dword ptr [rip+gp_entry_offsets+r12*4]
    test eax, eax
    jz .gw_fail
    lea r13, [rip+gp_slot_base]
    add r13, rax

    # General fragments were emitted as straight native regions, not ABI
    # functions. Preserve every engine register that must survive their call.
    push r15
    push rbx
    push r12
    push r13
    call r13
    pop r13
    pop r12
    pop rbx
    pop r15

    sub dword ptr [r15+ST_HOME_REMAIN+rbx*4], 1
    jc .gw_fail

    mov r14d, dword ptr [rip+gp_first_out+r12*4]
.gw_edges:
    cmp r14d, GP_EMPTY
    je .gw_loop
    cmp r14d, dword ptr [rip+gp_edge_count]
    jae .gw_fail
    mov esi, dword ptr [rip+gp_edge_v+r14*4]
    cmp esi, dword ptr [rip+gp_node_count]
    jae .gw_fail
    lock sub dword ptr [r15+ST_REMAIN+rsi*4], 1
    jc .gw_fail
    jnz .gw_next
    call gp_enqueue
    test eax, eax
    jnz .gw_fail
.gw_next:
    mov r14d, dword ptr [rip+gp_next_edge+r14*4]
    jmp .gw_edges

.gw_ok:
    xor eax, eax
    jmp .gw_done
.gw_fail:
    mov eax, 1
.gw_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- AOT patch table ----------------
# All arrays are immutable after the compiler patches program_slot. Mutable
# readiness lives only in the anonymous CLONE_VM state above.
.p2align 6
.global gp_node_count
gp_node_count: .long 0
.global gp_edge_count
gp_edge_count: .long 0
.global gp_slot_count
gp_slot_count: .long 0
.p2align 4
.global gp_home_slots
gp_home_slots: .fill GP_MAX_NODES,4,0
.global gp_indegree
gp_indegree: .fill GP_MAX_NODES,4,0
.global gp_first_out
gp_first_out: .fill GP_MAX_NODES,4,0xff
.global gp_edge_v
gp_edge_v: .fill GP_MAX_EDGES,4,0
.global gp_next_edge
gp_next_edge: .fill GP_MAX_EDGES,4,0xff
.global gp_entry_offsets
gp_entry_offsets: .fill GP_MAX_NODES,4,0
.global gp_home_initial
gp_home_initial: .fill GP_MAX_SLOTS,4,0

.p2align 4
.global gp_template_end
gp_template_end:
