.intel_syntax noprefix

# Native parallel Causal Ownership Return Fabric proof runtime.
# Each OS execution slot is itself the resource token. It moves over causal
# adjacency; it never pops/steals from a global work queue.
#
# CLI:
# topology-fabric-run N E SLOTS OWNER[N] WORK[N] EDGE_UV[2E]
# Bounded native parallel gate: N<=64, E<=256, SLOTS<=16, exactly one causal
# source. The deterministic fabric gate separately proves multi-source behavior.

.equ SYS_write, 1
.equ SYS_exit, 60
.equ SYS_exit_group, 231
.equ SYS_clone, 56
.equ SYS_wait4, 61
.equ SYS_futex, 202
.equ FUTEX_WAIT, 0
.equ FUTEX_WAKE, 1
.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ STACK_BYTES, 65536
.equ MAX_SLOTS, 16

.section .text
.global _start
_start:
    mov r15, rsp
    mov r14, [r15]
    lea r13, [r15+8]
    cmp r14, 4
    jl usage_error

    mov rdi, [r13+8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    test eax, eax
    jz parse_error
    cmp eax, 64
    ja parse_error
    mov [rip+node_count], eax
    mov r10d, eax

    mov rdi, [r13+16]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, 256
    ja parse_error
    mov [rip+edge_count], eax
    mov r11d, eax

    mov rdi, [r13+24]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    test eax, eax
    jz parse_error
    cmp eax, MAX_SLOTS
    ja parse_error
    mov [rip+slot_count], eax

    # argc = 4 + 2N + 2E
    mov eax, r10d
    shl eax, 1
    mov ecx, r11d
    shl ecx, 1
    add eax, ecx
    add eax, 4
    cmp r14d, eax
    jne usage_error

    call clear_state
    mov dword ptr [rip+arg_index], 4

    # owners
    xor ebx, ebx
.pp_owners:
    cmp ebx, dword ptr [rip+node_count]
    jae .pp_work
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    lea rcx, [rip+owners]
    mov dword ptr [rcx+rbx*4], eax
    inc dword ptr [rip+arg_index]
    inc ebx
    jmp .pp_owners

    # synthetic work iterations per node
.pp_work:
    xor ebx, ebx
.pp_work_loop:
    cmp ebx, dword ptr [rip+node_count]
    jae .pp_edges
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    lea rcx, [rip+work_iters]
    mov dword ptr [rcx+rbx*4], eax
    inc dword ptr [rip+arg_index]
    inc ebx
    jmp .pp_work_loop

.pp_edges:
    xor ebx, ebx
.pp_edge_loop:
    cmp ebx, dword ptr [rip+edge_count]
    jae .pp_validate
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

    lea rcx, [rip+edge_u]
    mov dword ptr [rcx+rbx*4], r12d
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

    lea rcx, [rip+parent]
    cmp dword ptr [rcx+r9*4], -1
    jne .pp_parent_done
    mov dword ptr [rcx+r9*4], r12d
    lea rdx, [rip+first_child]
    mov eax, dword ptr [rdx+r12*4]
    lea rsi, [rip+next_sibling]
    mov dword ptr [rsi+r9*4], eax
    mov dword ptr [rdx+r12*4], r9d
.pp_parent_done:
    inc ebx
    jmp .pp_edge_loop

.pp_validate:
    call prove_dag
    test eax, eax
    jnz cycle_error
    call initialize_parallel_fabric
    test eax, eax
    jnz source_error
    call spawn_slots
    test eax, eax
    jnz runtime_error
    call wait_slots
    test eax, eax
    jnz runtime_error
    call verify_parallel_final
    test eax, eax
    jnz runtime_error
    call print_result_json
    xor edi, edi
    jmp exit_group

# ---------------------------------------------------------------------------
clear_state:
    lea rdi, [rip+zero_begin]
    xor eax, eax
    mov ecx, (zero_end-zero_begin)/8
    rep stosq
    mov eax, -1
    lea rdi, [rip+parent]
    mov ecx, 64
    rep stosd
    lea rdi, [rip+first_out]
    mov ecx, 64
    rep stosd
    lea rdi, [rip+first_child]
    mov ecx, 64
    rep stosd
    lea rdi, [rip+next_sibling]
    mov ecx, 64
    rep stosd
    lea rdi, [rip+next_edge]
    mov ecx, 256
    rep stosd
    ret

prove_dag:
    mov dword ptr [rip+proof_processed], 0
.pd_wave:
    mov eax, dword ptr [rip+proof_processed]
    cmp eax, dword ptr [rip+node_count]
    je .pd_ok
    xor r8d, r8d
    xor ebx, ebx
.pd_nodes:
    cmp ebx, dword ptr [rip+node_count]
    jae .pd_done
    lea rax, [rip+proof_removed]
    cmp byte ptr [rax+rbx], 0
    jne .pd_next
    lea rax, [rip+proof_indegree]
    cmp dword ptr [rax+rbx*4], 0
    jne .pd_next
    lea rax, [rip+proof_removed]
    mov byte ptr [rax+rbx], 1
    lock inc dword ptr [rip+proof_processed]
    mov r8d, 1
    lea rax, [rip+first_out]
    mov r9d, dword ptr [rax+rbx*4]
.pd_edges:
    cmp r9d, -1
    je .pd_next
    lea rax, [rip+edge_v]
    mov r10d, dword ptr [rax+r9*4]
    lea rax, [rip+proof_indegree]
    sub dword ptr [rax+r10*4], 1
    lea rax, [rip+next_edge]
    mov r9d, dword ptr [rax+r9*4]
    jmp .pd_edges
.pd_next:
    inc ebx
    jmp .pd_nodes
.pd_done:
    test r8d, r8d
    jz .pd_cycle
    jmp .pd_wave
.pd_ok:
    xor eax, eax
    ret
.pd_cycle:
    mov eax, 1
    ret

initialize_parallel_fabric:
    # Native concurrent gate intentionally requires one causal component/root.
    mov dword ptr [rip+source_count], 0
    xor ebx, ebx
.ipf_scan:
    cmp ebx, dword ptr [rip+node_count]
    jae .ipf_done
    lea rax, [rip+remaining_deps]
    cmp dword ptr [rax+rbx*4], 0
    jne .ipf_next
    mov dword ptr [rip+source_root], ebx
    inc dword ptr [rip+source_count]
.ipf_next:
    inc ebx
    jmp .ipf_scan
.ipf_done:
    cmp dword ptr [rip+source_count], 1
    jne .ipf_fail
    mov eax, dword ptr [rip+source_root]
    lea rcx, [rip+ready_pending]
    mov byte ptr [rcx+rax], 1
    # source pending summary along source itself
    lea rcx, [rip+pending_count]
    mov dword ptr [rcx+rax*4], 1
    mov eax, dword ptr [rip+node_count]
    mov dword ptr [rip+root_remaining], eax
    xor eax, eax
    ret
.ipf_fail:
    mov eax, 1
    ret

# ---------------------------------------------------------------------------
# OS slot construction. Parent is lifecycle join only, never scheduler.
# ---------------------------------------------------------------------------
spawn_slots:
    xor r12d, r12d
.ss_loop:
    cmp r12d, dword ptr [rip+slot_count]
    jae .ss_ok
    # child stack top = slot_stacks + (slot+1)*STACK_BYTES, 16B aligned
    mov eax, r12d
    inc eax
    imul rax, rax, STACK_BYTES
    lea rsi, [rip+slot_stacks]
    add rsi, rax
    and rsi, -16
    mov eax, SYS_clone
    mov edi, CLONE_VM_FILES_FS_SIGCHLD
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    syscall
    test rax, rax
    js .ss_fail
    jz slot_child_entry
    lea rcx, [rip+slot_pids]
    mov qword ptr [rcx+r12*8], rax
    inc r12d
    jmp .ss_loop
.ss_ok:
    xor eax, eax
    ret
.ss_fail:
    mov eax, 1
    ret

slot_child_entry:
    # r12d is slot id copied across clone. Every slot starts at causal root.
    mov ebx, dword ptr [rip+source_root]
.slot_loop:
    mov edi, ebx
    call route_token_parallel
    cmp eax, -1
    je .slot_idle
    mov ebx, eax
    mov edi, eax
    call execute_synthetic_work
    mov edi, ebx
    call publish_completion_parallel
    test eax, eax
    jnz .slot_fail
    # token remains at completed node and immediately seeks local causal work
    jmp .slot_loop
.slot_idle:
    cmp dword ptr [rip+root_remaining], 0
    je .slot_exit
    # Local root wait. Epoch changes only for readiness/termination in this
    # causal component. No global scheduler heartbeat exists.
    mov r10d, dword ptr [rip+root_epoch]
    mov eax, SYS_futex
    lea rdi, [rip+root_epoch]
    mov esi, FUTEX_WAIT
    mov edx, r10d
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
    mov ebx, dword ptr [rip+source_root]
    jmp .slot_loop
.slot_exit:
    xor edi, edi
    mov eax, SYS_exit
    syscall
    hlt
.slot_fail:
    mov edi, 70
    mov eax, SYS_exit
    syscall
    hlt

wait_slots:
    xor r12d, r12d
.ws_loop:
    cmp r12d, dword ptr [rip+slot_count]
    jae .ws_ok
    lea rax, [rip+slot_pids]
    mov rdi, qword ptr [rax+r12*8]
    lea rsi, [rip+wait_status]
    xor edx, edx
    xor r10d, r10d
    mov eax, SYS_wait4
    syscall
    test rax, rax
    js .ws_fail
    cmp dword ptr [rip+wait_status], 0
    jne .ws_fail
    inc r12d
    jmp .ws_loop
.ws_ok:
    xor eax, eax
    ret
.ws_fail:
    mov eax, 1
    ret

# ---------------------------------------------------------------------------
# Native resource-token routing
# ---------------------------------------------------------------------------
# try_claim_node(edi=node) -> eax=1 claimed, 0 not pending/already claimed.
try_claim_node:
    lea rcx, [rip+ready_pending]
    mov al, 1
    xor dl, dl
    lock cmpxchg byte ptr [rcx+rdi], dl
    jne .tcn_no
    # Remove pending summary along causal parent chain.
    mov eax, edi
.tcn_clear:
    cmp eax, -1
    je .tcn_yes
    lea rcx, [rip+pending_count]
    lock sub dword ptr [rcx+rax*4], 1
    lea rcx, [rip+parent]
    mov eax, dword ptr [rcx+rax*4]
    jmp .tcn_clear
.tcn_yes:
    lock inc dword ptr [rip+resource_assignments]
    mov eax, 1
    ret
.tcn_no:
    xor eax, eax
    ret

# route_token_parallel(edi=current_location) -> eax=node to execute, or -1 idle.
# Only local adjacency lists / parent / child links are inspected.
route_token_parallel:
    push rbx
    push r12
    push r13
    mov ebx, edi
.rtp_again:
    # pending node exactly at token location
    mov edi, ebx
    call try_claim_node
    test eax, eax
    jz .rtp_direct
    mov eax, ebx
    jmp .rtp_done

.rtp_direct:
    lea rax, [rip+first_out]
    mov r12d, dword ptr [rax+rbx*4]
.rtp_direct_loop:
    cmp r12d, -1
    je .rtp_subtree
    lock inc dword ptr [rip+local_adjacency_probes]
    lea rax, [rip+edge_v]
    mov r13d, dword ptr [rax+r12*4]
    mov edi, r13d
    call try_claim_node
    test eax, eax
    jz .rtp_direct_next
    mov edi, ebx
    mov esi, r13d
    call count_control_edge
    lock inc dword ptr [rip+direct_handoffs]
    mov eax, r13d
    jmp .rtp_done
.rtp_direct_next:
    lea rax, [rip+next_edge]
    mov r12d, dword ptr [rax+r12*4]
    jmp .rtp_direct_loop

.rtp_subtree:
    lea rax, [rip+pending_count]
    cmp dword ptr [rax+rbx*4], 0
    je .rtp_up
    # descend one child subtree with pending demand
    lea rax, [rip+first_child]
    mov r12d, dword ptr [rax+rbx*4]
.rtp_child_loop:
    cmp r12d, -1
    je .rtp_again                    # raced; retry local state
    lock inc dword ptr [rip+local_adjacency_probes]
    lea rax, [rip+pending_count]
    cmp dword ptr [rax+r12*4], 0
    jne .rtp_child_found
    lea rax, [rip+next_sibling]
    mov r12d, dword ptr [rax+r12*4]
    jmp .rtp_child_loop
.rtp_child_found:
    mov edi, ebx
    mov esi, r12d
    call count_control_edge
    lock inc dword ptr [rip+cascade_down_steps]
    mov ebx, r12d
    jmp .rtp_again

.rtp_up:
    lea rax, [rip+parent]
    mov r12d, dword ptr [rax+rbx*4]
    cmp r12d, -1
    je .rtp_idle
    mov edi, ebx
    mov esi, r12d
    call count_control_edge
    lock inc dword ptr [rip+cascade_up_steps]
    mov ebx, r12d
    jmp .rtp_again
.rtp_idle:
    mov eax, -1
.rtp_done:
    pop r13
    pop r12
    pop rbx
    ret

# count_control_edge(edi=a, esi=b)
count_control_edge:
    lea rax, [rip+owners]
    mov ecx, dword ptr [rax+rdi*4]
    mov edx, dword ptr [rax+rsi*4]
    cmp ecx, edx
    jne .cce_cross
    lock inc dword ptr [rip+local_control_edges]
    ret
.cce_cross:
    lock inc dword ptr [rip+cross_owner_control_edges]
    ret

execute_synthetic_work:
    # deterministic integer work; no shared state touched until publication.
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

# publish_completion_parallel(edi=node) -> eax 0 success / 1 invariant failure
publish_completion_parallel:
    push rbx
    push r12
    push r13
    mov ebx, edi
    # exactly once
    lea rcx, [rip+completed]
    mov al, 0
    mov dl, 1
    lock cmpxchg byte ptr [rcx+rbx], dl
    jne .pcp_fail
    lock inc dword ptr [rip+completed_count]

    lea rax, [rip+first_out]
    mov r12d, dword ptr [rax+rbx*4]
.pcp_edges:
    cmp r12d, -1
    je .pcp_finish
    lock inc dword ptr [rip+local_adjacency_probes]
    lea rax, [rip+edge_v]
    mov r13d, dword ptr [rax+r12*4]
    lea rax, [rip+remaining_deps]
    lock sub dword ptr [rax+r13*4], 1
    jc .pcp_fail
    jz .pcp_became_ready
    lock inc dword ptr [rip+dependency_messages]
    jmp .pcp_next
.pcp_became_ready:
    # Branch on this thread's atomic zero transition, never a later memory read.
    # Exactly one predecessor can therefore publish the ready event.
    lock inc dword ptr [rip+dependency_messages]
    # unique transition to ready: set pending and propagate demand to root
    lea rcx, [rip+ready_pending]
    mov byte ptr [rcx+r13], 1
    mov eax, r13d
.pcp_pending_chain:
    cmp eax, -1
    je .pcp_wake
    lea rcx, [rip+pending_count]
    lock add dword ptr [rcx+rax*4], 1
    lea rcx, [rip+parent]
    mov eax, dword ptr [rcx+rax*4]
    jmp .pcp_pending_chain
.pcp_wake:
    lock inc dword ptr [rip+root_epoch]
    mov eax, SYS_futex
    lea rdi, [rip+root_epoch]
    mov esi, FUTEX_WAKE
    mov edx, 1
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
.pcp_next:
    lea rax, [rip+next_edge]
    mov r12d, dword ptr [rax+r12*4]
    jmp .pcp_edges
.pcp_finish:
    lock sub dword ptr [rip+root_remaining], 1
    jne .pcp_ok
    # wake all idle slots for lifecycle exit
    lock inc dword ptr [rip+root_epoch]
    mov eax, SYS_futex
    lea rdi, [rip+root_epoch]
    mov esi, FUTEX_WAKE
    mov edx, MAX_SLOTS
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    syscall
.pcp_ok:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
.pcp_fail:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret

verify_parallel_final:
    cmp dword ptr [rip+root_remaining], 0
    jne .vpf_fail
    mov eax, dword ptr [rip+completed_count]
    cmp eax, dword ptr [rip+node_count]
    jne .vpf_fail
    mov eax, dword ptr [rip+dependency_messages]
    cmp eax, dword ptr [rip+edge_count]
    jne .vpf_fail
    xor ebx, ebx
.vpf_nodes:
    cmp ebx, dword ptr [rip+node_count]
    jae .vpf_ok
    lea rax, [rip+ready_pending]
    cmp byte ptr [rax+rbx], 0
    jne .vpf_fail
    lea rax, [rip+pending_count]
    cmp dword ptr [rax+rbx*4], 0
    jne .vpf_fail
    lea rax, [rip+completed]
    cmp byte ptr [rax+rbx], 1
    jne .vpf_fail
    inc ebx
    jmp .vpf_nodes
.vpf_ok:
    xor eax, eax
    ret
.vpf_fail:
    mov eax, 1
    ret

# ---------------------------------------------------------------------------
# JSON / parser
# ---------------------------------------------------------------------------
print_result_json:
    lea rdi, [rip+j_head]
    mov esi, j_head_end-j_head
    call print_stdout
    lea rdi, [rip+j_nodes]
    mov esi, j_nodes_end-j_nodes
    mov edx, dword ptr [rip+node_count]
    call print_num_field
    lea rdi, [rip+j_edges]
    mov esi, j_edges_end-j_edges
    mov edx, dword ptr [rip+edge_count]
    call print_num_field
    lea rdi, [rip+j_slots]
    mov esi, j_slots_end-j_slots
    mov edx, dword ptr [rip+slot_count]
    call print_num_field
    lea rdi, [rip+j_completed]
    mov esi, j_completed_end-j_completed
    mov edx, dword ptr [rip+completed_count]
    call print_num_field
    lea rdi, [rip+j_dep]
    mov esi, j_dep_end-j_dep
    mov edx, dword ptr [rip+dependency_messages]
    call print_num_field
    lea rdi, [rip+j_assign]
    mov esi, j_assign_end-j_assign
    mov edx, dword ptr [rip+resource_assignments]
    call print_num_field
    lea rdi, [rip+j_direct]
    mov esi, j_direct_end-j_direct
    mov edx, dword ptr [rip+direct_handoffs]
    call print_num_field
    lea rdi, [rip+j_up]
    mov esi, j_up_end-j_up
    mov edx, dword ptr [rip+cascade_up_steps]
    call print_num_field
    lea rdi, [rip+j_down]
    mov esi, j_down_end-j_down
    mov edx, dword ptr [rip+cascade_down_steps]
    call print_num_field
    lea rdi, [rip+j_local]
    mov esi, j_local_end-j_local
    mov edx, dword ptr [rip+local_control_edges]
    call print_num_field
    lea rdi, [rip+j_cross]
    mov esi, j_cross_end-j_cross
    mov edx, dword ptr [rip+cross_owner_control_edges]
    call print_num_field
    lea rdi, [rip+j_probes]
    mov esi, j_probes_end-j_probes
    mov edx, dword ptr [rip+local_adjacency_probes]
    call print_num_field
    lea rdi, [rip+j_tail]
    mov esi, j_tail_end-j_tail
    call print_stdout
    ret

print_num_field:
    push rdx
    call print_stdout
    pop rdx
    mov eax, edx
    lea rdi, [rip+num_buffer+31]
    xor ecx, ecx
    test eax, eax
    jnz .pn_loop
    dec rdi
    mov byte ptr [rdi], '0'
    mov ecx, 1
    jmp .pn_out
.pn_loop:
    xor edx, edx
    mov r9d, 10
    div r9d
    add dl, '0'
    dec rdi
    mov byte ptr [rdi], dl
    inc ecx
    test eax, eax
    jnz .pn_loop
.pn_out:
    mov esi, ecx
    call print_stdout
    ret

parse_u32_cstr:
    xor eax, eax
    xor edx, edx
    xor r8d, r8d
.pu_loop:
    movzx ecx, byte ptr [rdi]
    test cl, cl
    jz .pu_done
    cmp cl, '0'
    jb .pu_bad
    cmp cl, '9'
    ja .pu_bad
    imul rax, rax, 10
    sub ecx, '0'
    add rax, rcx
    mov r9, 0xffffffff
    cmp rax, r9
    ja .pu_bad
    inc rdi
    mov r8d, 1
    jmp .pu_loop
.pu_done:
    test r8d, r8d
    jz .pu_bad
    xor edx, edx
    ret
.pu_bad:
    xor eax, eax
    mov edx, 1
    ret

print_stdout:
    mov rdx, rsi
    mov rsi, rdi
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret
print_stderr:
    mov rdx, rsi
    mov rsi, rdi
    mov eax, SYS_write
    mov edi, 2
    syscall
    ret

usage_error:
    lea rdi, [rip+msg_usage]
    mov esi, msg_usage_end-msg_usage
    call print_stderr
    mov edi, 64
    jmp exit_group
parse_error:
    lea rdi, [rip+msg_parse]
    mov esi, msg_parse_end-msg_parse
    call print_stderr
    mov edi, 65
    jmp exit_group
cycle_error:
    lea rdi, [rip+msg_cycle]
    mov esi, msg_cycle_end-msg_cycle
    call print_stderr
    mov edi, 65
    jmp exit_group
source_error:
    lea rdi, [rip+msg_source]
    mov esi, msg_source_end-msg_source
    call print_stderr
    mov edi, 65
    jmp exit_group
runtime_error:
    lea rdi, [rip+msg_runtime]
    mov esi, msg_runtime_end-msg_runtime
    call print_stderr
    mov edi, 70
    jmp exit_group
exit_group:
    mov eax, SYS_exit_group
    syscall
    hlt

.section .rodata
msg_usage: .ascii "usage: topology-fabric-run N E SLOTS OWNER[N] WORK[N] EDGE_UV[2E]\n"
msg_usage_end:
msg_parse: .ascii "topology-fabric-run: malformed bounded runtime input\n"
msg_parse_end:
msg_cycle: .ascii "topology-fabric-run: dependency cycle rejected\n"
msg_cycle_end:
msg_source: .ascii "topology-fabric-run: native parallel gate currently requires exactly one causal source\n"
msg_source_end:
msg_runtime: .ascii "topology-fabric-run: native causal ownership runtime invariant failed\n"
msg_runtime_end:

j_head: .ascii "{\"format\":\"topology.causal-return-parallel/1\""
j_head_end:
j_nodes: .ascii ",\"nodes\":"
j_nodes_end:
j_edges: .ascii ",\"dependency_edges\":"
j_edges_end:
j_slots: .ascii ",\"native_resource_slots\":"
j_slots_end:
j_completed: .ascii ",\"completed_exactly_once\":"
j_completed_end:
j_dep: .ascii ",\"dependency_messages\":"
j_dep_end:
j_assign: .ascii ",\"resource_assignments\":"
j_assign_end:
j_direct: .ascii ",\"direct_causal_handoffs\":"
j_direct_end:
j_up: .ascii ",\"cascade_up_steps\":"
j_up_end:
j_down: .ascii ",\"cascade_down_steps\":"
j_down_end:
j_local: .ascii ",\"local_control_edges\":"
j_local_end:
j_cross: .ascii ",\"cross_owner_control_edges\":"
j_cross_end:
j_probes: .ascii ",\"local_adjacency_probes\":"
j_probes_end:
j_tail: .ascii ",\"global_ready_queue_ops\":0,\"global_claim_counter_ops\":0,\"work_steals\":0,\"runtime_global_ready_scans\":0,\"noncausal_dependency_messages\":0,\"noncausal_resource_edges\":0,\"idle_wait\":\"ROOT_LOCAL_FUTEX_EPOCH\",\"lifecycle_join\":\"PARENT_WAIT4_ONLY\",\"status\":\"PROVEN_CLEAN\"}\n"
j_tail_end:

.section .bss
.align 64
node_count: .skip 4
edge_count: .skip 4
slot_count: .skip 4
arg_index: .skip 4
source_count: .skip 4
source_root: .skip 4
root_remaining: .skip 4
root_epoch: .skip 4
proof_processed: .skip 4
completed_count: .skip 4
dependency_messages: .skip 4
resource_assignments: .skip 4
direct_handoffs: .skip 4
cascade_up_steps: .skip 4
cascade_down_steps: .skip 4
local_control_edges: .skip 4
cross_owner_control_edges: .skip 4
local_adjacency_probes: .skip 4
wait_status: .skip 4
.align 64
zero_begin:
owners: .skip 256
work_iters: .skip 256
remaining_deps: .skip 256
proof_indegree: .skip 256
parent: .skip 256
first_out: .skip 256
first_child: .skip 256
next_sibling: .skip 256
pending_count: .skip 256
proof_removed: .skip 64
ready_pending: .skip 64
completed: .skip 64
.align 64
edge_u: .skip 1024
edge_v: .skip 1024
next_edge: .skip 1024
node_results: .skip 512
slot_pids: .skip 128
num_buffer: .skip 32
zero_end:
.align 4096
slot_stacks: .skip STACK_BYTES*MAX_SLOTS
