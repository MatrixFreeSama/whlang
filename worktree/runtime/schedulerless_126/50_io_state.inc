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
    lea rdi, [rip+j_sources]
    mov esi, j_sources_end-j_sources
    mov edx, dword ptr [rip+source_count]
    call print_num_field
    lea rdi, [rip+j_claims]
    mov esi, j_claims_end-j_claims
    mov rdx, qword ptr [rip+total_claims]
    call print_u64_field
    lea rdi, [rip+j_dep]
    mov esi, j_dep_end-j_dep
    mov rdx, qword ptr [rip+total_edges]
    call print_u64_field
    lea rdi, [rip+j_direct]
    mov esi, j_direct_end-j_direct
    mov rdx, qword ptr [rip+total_direct]
    call print_u64_field
    lea rdi, [rip+j_remote]
    mov esi, j_remote_end-j_remote
    mov rdx, qword ptr [rip+total_remote]
    call print_u64_field
    lea rdi, [rip+j_collision]
    mov esi, j_collision_end-j_collision
    mov rdx, qword ptr [rip+total_collisions]
    call print_u64_field
    lea rdi, [rip+j_fallback]
    mov esi, j_fallback_end-j_fallback
    mov rdx, qword ptr [rip+total_fallbacks]
    call print_u64_field
    lea rdi, [rip+j_waits]
    mov esi, j_waits_end-j_waits
    mov rdx, qword ptr [rip+total_waits]
    call print_u64_field
    lea rdi, [rip+j_tail]
    mov esi, j_tail_end-j_tail
    call print_stdout
    ret

print_num_field:
    push rdx
    call print_stdout
    pop rdx
    mov eax, edx
    mov rdx, rax
    jmp print_u64_value
print_u64_field:
    push rdx
    call print_stdout
    pop rdx
    jmp print_u64_value
print_u64_value:
    mov rax, rdx
    lea rdi, [rip+num_buffer+31]
    xor ecx, ecx
    test rax, rax
    jnz .pu64_loop
    dec rdi
    mov byte ptr [rdi], '0'
    mov ecx, 1
    jmp .pu64_out
.pu64_loop:
    xor edx, edx
    mov r9, 10
    div r9
    add dl, '0'
    dec rdi
    mov byte ptr [rdi], dl
    inc ecx
    test rax, rax
    jnz .pu64_loop
.pu64_out:
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
    mov edx, 1
    ret

print_stdout:
    mov edx, esi
    mov rsi, rdi
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret

usage_error:
    lea rdi, [rip+msg_usage]
    mov esi, msg_usage_end-msg_usage
    call print_stdout
    mov edi, 64
    jmp exit_group
parse_error:
    lea rdi, [rip+msg_parse]
    mov esi, msg_parse_end-msg_parse
    call print_stdout
    mov edi, 65
    jmp exit_group
cycle_error:
    lea rdi, [rip+msg_cycle]
    mov esi, msg_cycle_end-msg_cycle
    call print_stdout
    mov edi, 66
    jmp exit_group
runtime_error:
    lea rdi, [rip+msg_runtime]
    mov esi, msg_runtime_end-msg_runtime
    call print_stdout
    mov edi, 70
exit_group:
    mov eax, SYS_exit_group
    syscall
    hlt

.section .rodata
msg_usage: .ascii "usage: topology-fabric-schedulerless N E SLOTS HOME[N] WORK[N] EDGE_UV[2E]\n"
msg_usage_end:
msg_parse: .ascii "schedulerless fabric: parse/shape rejection\n"
msg_parse_end:
msg_cycle: .ascii "schedulerless fabric: cycle rejection\n"
msg_cycle_end:
msg_runtime: .ascii "schedulerless fabric: invariant failure\n"
msg_runtime_end:
j_head: .ascii "{\"mode\":\"schedulerless_sparse_causal_1_2_6\""
j_head_end:
j_nodes: .ascii ",\"nodes\":"
j_nodes_end:
j_edges: .ascii ",\"edges\":"
j_edges_end:
j_slots: .ascii ",\"slots\":"
j_slots_end:
j_sources: .ascii ",\"sources\":"
j_sources_end:
j_claims: .ascii ",\"completed\":"
j_claims_end:
j_dep: .ascii ",\"dependency_messages\":"
j_dep_end:
j_direct: .ascii ",\"direct_continuations\":"
j_direct_end:
j_remote: .ascii ",\"remote_handoffs\":"
j_remote_end:
j_collision: .ascii ",\"handoff_collisions\":"
j_collision_end:
j_fallback: .ascii ",\"local_fallbacks\":"
j_fallback_end:
j_waits: .ascii ",\"slot_waits\":"
j_waits_end:
j_tail: .ascii ",\"global_ready_scans\":0,\"global_queue_ops\":0,\"root_scheduler_ops\":0,\"parent_chain_updates\":0}\n"
j_tail_end:

.section .bss
.p2align 6
zero_begin:
node_count: .skip 4
edge_count: .skip 4
slot_count: .skip 4
arg_index: .skip 4
source_count: .skip 4
proof_processed: .skip 4
home_slot: .skip MAX_NODES*4
work_iters: .skip MAX_NODES*4
remaining_deps: .skip MAX_NODES*4
proof_indegree: .skip MAX_NODES*4
proof_removed: .skip MAX_NODES
node_state: .skip MAX_NODES
edge_v: .skip MAX_EDGES*4
home_remaining: .skip MAX_SLOTS*4
slot_sp: .skip MAX_SLOTS*4
slot_epoch: .skip MAX_SLOTS*4
local_stack: .skip MAX_SLOTS*MAX_NODES*4
node_results: .skip MAX_NODES*8
metric_claims: .skip MAX_SLOTS*8
metric_edges: .skip MAX_SLOTS*8
metric_direct: .skip MAX_SLOTS*8
metric_remote: .skip MAX_SLOTS*8
metric_collisions: .skip MAX_SLOTS*8
metric_fallbacks: .skip MAX_SLOTS*8
metric_waits: .skip MAX_SLOTS*8
zero_end:
.p2align 4
first_out: .skip MAX_NODES*4
next_edge: .skip MAX_EDGES*4
mailbox: .skip MAX_SLOTS*4
.p2align 3
totals_begin:
total_claims: .skip 8
total_edges: .skip 8
total_direct: .skip 8
total_remote: .skip 8
total_collisions: .skip 8
total_fallbacks: .skip 8
total_waits: .skip 8
totals_end:
num_buffer: .skip 32
