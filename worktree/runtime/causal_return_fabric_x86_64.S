.intel_syntax noprefix

# Topology Parallel Compiler - Causal Ownership Return Fabric
# Handwritten x86-64 assembly, Linux, no libc/runtime scheduler.
#
# Execution contract:
#   - completion data moves only on declared dependency edges;
#   - resource-control tokens move only on a declared causal adjacency
#     (forward or reverse along the selected causal-parent forest);
#   - no global ready queue, claim counter, stealing, or runtime all-node scan;
#   - a ready node propagates demand only up its causal-parent chain;
#   - a freed slot returns locally, then upward, and is routed into the nearest
#     pending causal subtree. Disconnected causal components never exchange slots.
#
# Bounded executable proof CLI:
#   topology-fabric N E SLOTS OWNER[N] EDGE_UV[2E] COMPLETION_ORDER[N]
# Bounds: 1<=N<=64, E<=256, 1<=SLOTS<=64.

.equ SYS_write, 1
.equ SYS_exit_group, 231

.section .text
.global _start
_start:
    mov r15, rsp
    mov r14, [r15]
    lea r13, [r15+8]
    cmp r14, 4
    jl usage_error

    # N
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

    # E
    mov rdi, [r13+16]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, 256
    ja parse_error
    mov [rip+edge_count], eax
    mov r11d, eax

    # slots
    mov rdi, [r13+24]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    test eax, eax
    jz parse_error
    cmp eax, 64
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

    # owners start argv[4]
    mov dword ptr [rip+arg_index], 4
    xor ebx, ebx
.parse_owners:
    cmp ebx, dword ptr [rip+node_count]
    jae .parse_edges
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    lea rcx, [rip+owners]
    mov dword ptr [rcx+rbx*4], eax
    inc dword ptr [rip+arg_index]
    inc ebx
    jmp .parse_owners

.parse_edges:
    xor ebx, ebx
.edge_loop:
    cmp ebx, dword ptr [rip+edge_count]
    jae .parse_order

    # u
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, dword ptr [rip+node_count]
    jae parse_error
    mov r12d, eax
    inc dword ptr [rip+arg_index]

    # v
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, dword ptr [rip+node_count]
    jae parse_error
    mov r9d, eax
    inc dword ptr [rip+arg_index]

    # Store edge and outgoing adjacency.
    lea rcx, [rip+edge_u]
    mov dword ptr [rcx+rbx*4], r12d
    lea rcx, [rip+edge_v]
    mov dword ptr [rcx+rbx*4], r9d
    lea rcx, [rip+first_out]
    mov eax, dword ptr [rcx+r12*4]
    lea rdx, [rip+next_edge]
    mov dword ptr [rdx+rbx*4], eax
    mov dword ptr [rcx+r12*4], ebx

    # indegree[v]++ in both runtime and proof copies.
    lea rcx, [rip+remaining_deps]
    add dword ptr [rcx+r9*4], 1
    lea rcx, [rip+proof_indegree]
    add dword ptr [rcx+r9*4], 1

    # Select first declared predecessor as return parent. This is a subset of E.
    lea rcx, [rip+parent]
    cmp dword ptr [rcx+r9*4], -1
    jne .edge_parent_done
    mov dword ptr [rcx+r9*4], r12d
    # child linked list for local return-tree routing.
    lea rdx, [rip+first_child]
    mov eax, dword ptr [rdx+r12*4]
    lea rsi, [rip+next_sibling]
    mov dword ptr [rsi+r9*4], eax
    mov dword ptr [rdx+r12*4], r9d
.edge_parent_done:
    inc ebx
    jmp .edge_loop

.parse_order:
    xor ebx, ebx
.order_loop:
    cmp ebx, dword ptr [rip+node_count]
    jae .validate
    mov eax, dword ptr [rip+arg_index]
    mov rdi, [r13+rax*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    cmp eax, dword ptr [rip+node_count]
    jae parse_error
    lea rcx, [rip+completion_order]
    mov dword ptr [rcx+rbx*4], eax
    inc dword ptr [rip+arg_index]
    inc ebx
    jmp .order_loop

.validate:
    call prove_dag
    test eax, eax
    jnz cycle_error
    call initialize_fabric
    test eax, eax
    jnz slot_error
    call execute_completion_stream
    test eax, eax
    jnz execution_error
    call verify_final_invariants
    test eax, eax
    jnz execution_error
    call print_result_json
    xor edi, edi
    jmp exit_group

# ---------------------------------------------------------------------------
# State initialization / compile-time proof
# ---------------------------------------------------------------------------
clear_state:
    # arrays filled with zero
    lea rdi, [rip+fabric_zero_begin]
    xor eax, eax
    mov ecx, (fabric_zero_end-fabric_zero_begin)/8
    rep stosq
    # lists/parents need -1, not zero.
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

    mov dword ptr [rip+source_count], 0
    mov dword ptr [rip+completed_count], 0
    mov dword ptr [rip+dependency_messages], 0
    mov dword ptr [rip+resource_assignments], 0
    mov dword ptr [rip+direct_handoffs], 0
    mov dword ptr [rip+cascade_up_steps], 0
    mov dword ptr [rip+cascade_down_steps], 0
    mov dword ptr [rip+local_control_edges], 0
    mov dword ptr [rip+cross_owner_control_edges], 0
    mov dword ptr [rip+local_adjacency_probes], 0
    mov dword ptr [rip+root_idle_slots], 0
    ret

# Kahn proof. Startup validation may inspect all nodes; execution scheduling never does.
prove_dag:
    mov dword ptr [rip+proof_processed], 0
.pd_wave:
    mov eax, dword ptr [rip+proof_processed]
    cmp eax, dword ptr [rip+node_count]
    je .pd_ok
    xor r8d, r8d                      # progressed this wave
    xor ebx, ebx
.pd_nodes:
    cmp ebx, dword ptr [rip+node_count]
    jae .pd_wave_done
    lea rax, [rip+proof_removed]
    cmp byte ptr [rax+rbx], 0
    jne .pd_next
    lea rax, [rip+proof_indegree]
    cmp dword ptr [rax+rbx*4], 0
    jne .pd_next
    lea rax, [rip+proof_removed]
    mov byte ptr [rax+rbx], 1
    inc dword ptr [rip+proof_processed]
    mov r8d, 1

    # release outgoing proof indegrees through local adjacency only
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
.pd_wave_done:
    test r8d, r8d
    jz .pd_cycle
    jmp .pd_wave
.pd_ok:
    xor eax, eax
    ret
.pd_cycle:
    mov eax, 1
    ret

initialize_fabric:
    # Identify sources and assign one active slot to each source.
    xor ebx, ebx
.if_sources:
    cmp ebx, dword ptr [rip+node_count]
    jae .if_sources_done
    lea rax, [rip+remaining_deps]
    cmp dword ptr [rax+rbx*4], 0
    jne .if_next
    mov eax, dword ptr [rip+source_count]
    lea rcx, [rip+source_list]
    mov dword ptr [rcx+rax*4], ebx
    inc dword ptr [rip+source_count]
    lea rcx, [rip+assigned]
    mov byte ptr [rcx+rbx], 1
.if_next:
    inc ebx
    jmp .if_sources
.if_sources_done:
    mov eax, dword ptr [rip+source_count]
    test eax, eax
    jz .if_fail
    cmp dword ptr [rip+slot_count], eax
    jb .if_fail

    # Extra slots are statically distributed round-robin among causal roots.
    mov ecx, dword ptr [rip+slot_count]
    sub ecx, eax
    xor ebx, ebx
.if_extra:
    test ecx, ecx
    jz .if_ok
    mov eax, ebx
    xor edx, edx
    div dword ptr [rip+source_count]
    lea rax, [rip+source_list]
    mov eax, dword ptr [rax+rdx*4]
    lea rsi, [rip+free_slots]
    add dword ptr [rsi+rax*4], 1
    inc ebx
    dec ecx
    jmp .if_extra
.if_ok:
    xor eax, eax
    ret
.if_fail:
    mov eax, 1
    ret

# ---------------------------------------------------------------------------
# Runtime execution fabric
# ---------------------------------------------------------------------------
execute_completion_stream:
    xor ebx, ebx
.ecs_loop:
    cmp ebx, dword ptr [rip+node_count]
    jae .ecs_ok
    lea rax, [rip+completion_order]
    mov edi, dword ptr [rax+rbx*4]
    call complete_node
    test eax, eax
    jnz .ecs_fail
    inc ebx
    jmp .ecs_loop
.ecs_ok:
    xor eax, eax
    ret
.ecs_fail:
    mov eax, 1
    ret

# complete_node(edi=node) -> eax 0/1
complete_node:
    push rbx
    mov ebx, edi
    # must be exactly-once, dependency-ready, and resource-assigned
    lea rax, [rip+completed]
    cmp byte ptr [rax+rbx], 0
    jne .cn_fail
    lea rax, [rip+assigned]
    cmp byte ptr [rax+rbx], 1
    jne .cn_fail
    lea rax, [rip+remaining_deps]
    cmp dword ptr [rax+rbx*4], 0
    jne .cn_fail

    lea rax, [rip+completed]
    mov byte ptr [rax+rbx], 1
    lea rax, [rip+assigned]
    mov byte ptr [rax+rbx], 0
    inc dword ptr [rip+completed_count]
    # active slot becomes a local free slot
    lea rax, [rip+free_slots]
    add dword ptr [rax+rbx*4], 1

    # Publish completion only to declared outgoing dependency neighbors.
    lea rax, [rip+first_out]
    mov r12d, dword ptr [rax+rbx*4]
.cn_edges:
    cmp r12d, -1
    je .cn_drain
    inc dword ptr [rip+local_adjacency_probes]
    lea rax, [rip+edge_v]
    mov r13d, dword ptr [rax+r12*4]
    lea rax, [rip+remaining_deps]
    cmp dword ptr [rax+r13*4], 0
    je .cn_fail
    sub dword ptr [rax+r13*4], 1
    inc dword ptr [rip+dependency_messages]
    cmp dword ptr [rax+r13*4], 0
    jne .cn_next_edge

    # Newly ready node publishes demand only along its return-parent chain.
    mov edi, r13d
    call mark_pending
    # Prefer the slot that just completed on the direct causal edge. If that
    # slot is already consumed, demand may pull an idle slot from ancestors.
    lea rax, [rip+free_slots]
    cmp dword ptr [rax+rbx*4], 0
    je .cn_try_pull
    mov edi, ebx
    mov esi, r13d
    call direct_assign
    jmp .cn_next_edge
.cn_try_pull:
    mov edi, r13d
    call try_pull_slot
.cn_next_edge:
    lea rax, [rip+next_edge]
    mov r12d, dword ptr [rax+r12*4]
    jmp .cn_edges

.cn_drain:
    # Any slot still held by the completed node returns/cascades locally.
    mov edi, ebx
    call drain_free_slots
    xor eax, eax
    pop rbx
    ret
.cn_fail:
    mov eax, 1
    pop rbx
    ret

# mark_pending(edi=node): pending ready demand is summarized only on parent chain.
mark_pending:
    mov eax, edi
.mp_loop:
    cmp eax, -1
    je .mp_done
    lea rcx, [rip+pending_count]
    add dword ptr [rcx+rax*4], 1
    lea rcx, [rip+parent]
    mov eax, dword ptr [rcx+rax*4]
    jmp .mp_loop
.mp_done:
    lea rcx, [rip+ready_pending]
    mov byte ptr [rcx+rdi], 1
    ret

# clear_pending(edi=node)
clear_pending:
    lea rcx, [rip+ready_pending]
    mov byte ptr [rcx+rdi], 0
    mov eax, edi
.cp_loop:
    cmp eax, -1
    je .cp_done
    lea rcx, [rip+pending_count]
    cmp dword ptr [rcx+rax*4], 0
    je fabric_invariant_abort
    sub dword ptr [rcx+rax*4], 1
    lea rcx, [rip+parent]
    mov eax, dword ptr [rcx+rax*4]
    jmp .cp_loop
.cp_done:
    ret

# count_control_edge(edi=a, esi=b): a/b must be causal-adjacent by construction.
count_control_edge:
    lea rax, [rip+owners]
    mov ecx, dword ptr [rax+rdi*4]
    mov edx, dword ptr [rax+rsi*4]
    cmp ecx, edx
    jne .cce_cross
    inc dword ptr [rip+local_control_edges]
    ret
.cce_cross:
    inc dword ptr [rip+cross_owner_control_edges]
    ret

# assign_at_node(edi=node): consumes a free slot already physically at node.
assign_at_node:
    lea rax, [rip+free_slots]
    cmp dword ptr [rax+rdi*4], 0
    je fabric_invariant_abort
    sub dword ptr [rax+rdi*4], 1
    lea rax, [rip+assigned]
    cmp byte ptr [rax+rdi], 0
    jne fabric_invariant_abort
    mov byte ptr [rax+rdi], 1
    call clear_pending
    inc dword ptr [rip+resource_assignments]
    ret

# direct_assign(edi=from, esi=to): one causal dependency edge, no search.
direct_assign:
    push rbx
    mov ebx, esi
    lea rax, [rip+free_slots]
    cmp dword ptr [rax+rdi*4], 0
    je fabric_invariant_abort
    sub dword ptr [rax+rdi*4], 1
    mov esi, ebx
    call count_control_edge
    lea rax, [rip+assigned]
    cmp byte ptr [rax+rbx], 0
    jne fabric_invariant_abort
    mov byte ptr [rax+rbx], 1
    mov edi, ebx
    call clear_pending
    inc dword ptr [rip+resource_assignments]
    inc dword ptr [rip+direct_handoffs]
    pop rbx
    ret

# try_pull_slot(edi=ready node): walk only its parent chain. If an idle slot is
# found, move it down the same selected causal-parent edges and assign the node.
try_pull_slot:
    push rbx
    push r12
    mov ebx, edi                       # target
    mov r12d, edi                      # ancestor probe
.tps_up:
    cmp r12d, -1
    je .tps_none
    lea rax, [rip+free_slots]
    cmp dword ptr [rax+r12*4], 0
    jne .tps_found
    lea rax, [rip+parent]
    mov r12d, dword ptr [rax+r12*4]
    jmp .tps_up
.tps_found:
    # Consume at ancestor then conceptually move down target->...->ancestor path.
    lea rax, [rip+free_slots]
    sub dword ptr [rax+r12*4], 1
    mov r8d, ebx                       # child on upward walk
.tps_count_down:
    cmp r8d, r12d
    je .tps_assign
    lea rax, [rip+parent]
    mov r9d, dword ptr [rax+r8*4]
    cmp r9d, -1
    je fabric_invariant_abort
    # token moves parent -> child on a declared parent dependency edge
    mov edi, r9d
    mov esi, r8d
    call count_control_edge
    inc dword ptr [rip+cascade_down_steps]
    mov r8d, r9d
    jmp .tps_count_down
.tps_assign:
    lea rax, [rip+assigned]
    cmp byte ptr [rax+rbx], 0
    jne fabric_invariant_abort
    mov byte ptr [rax+rbx], 1
    mov edi, ebx
    call clear_pending
    inc dword ptr [rip+resource_assignments]
    jmp .tps_done
.tps_none:
.tps_done:
    pop r12
    pop rbx
    ret

# drain_free_slots(edi=start node)
# Runtime scheduling examines only local outgoing adjacency, return-tree children,
# and the parent link. There is no all-node ready scan.
drain_free_slots:
    push rbx
    push r12
    push r13
    mov ebx, edi
.dfs_outer:
    lea rax, [rip+free_slots]
    cmp dword ptr [rax+rbx*4], 0
    je .dfs_done

    # 1) Prefer a directly dependent ready neighbor.
    lea rax, [rip+first_out]
    mov r12d, dword ptr [rax+rbx*4]
.dfs_direct:
    cmp r12d, -1
    je .dfs_subtree
    inc dword ptr [rip+local_adjacency_probes]
    lea rax, [rip+edge_v]
    mov r13d, dword ptr [rax+r12*4]
    lea rax, [rip+ready_pending]
    cmp byte ptr [rax+r13], 1
    jne .dfs_direct_next
    mov edi, ebx
    mov esi, r13d
    call direct_assign
    jmp .dfs_outer
.dfs_direct_next:
    lea rax, [rip+next_edge]
    mov r12d, dword ptr [rax+r12*4]
    jmp .dfs_direct

.dfs_subtree:
    # 2) If this return-tree subtree has pending demand, route one token down
    #    via child links only until it reaches a ready node.
    lea rax, [rip+pending_count]
    cmp dword ptr [rax+rbx*4], 0
    je .dfs_return_up
    mov r12d, ebx
.dfs_descend:
    lea rax, [rip+ready_pending]
    cmp byte ptr [rax+r12], 1
    je .dfs_at_ready
    lea rax, [rip+first_child]
    mov r13d, dword ptr [rax+r12*4]
.dfs_child_search:
    cmp r13d, -1
    je fabric_invariant_abort
    inc dword ptr [rip+local_adjacency_probes]
    lea rax, [rip+pending_count]
    cmp dword ptr [rax+r13*4], 0
    jne .dfs_child_found
    lea rax, [rip+next_sibling]
    mov r13d, dword ptr [rax+r13*4]
    jmp .dfs_child_search
.dfs_child_found:
    # move one free slot current -> child
    lea rax, [rip+free_slots]
    sub dword ptr [rax+r12*4], 1
    add dword ptr [rax+r13*4], 1
    mov edi, r12d
    mov esi, r13d
    call count_control_edge
    inc dword ptr [rip+cascade_down_steps]
    mov r12d, r13d
    jmp .dfs_descend
.dfs_at_ready:
    mov edi, r12d
    call assign_at_node
    jmp .dfs_outer

.dfs_return_up:
    # 3) No local demand: return one slot to causal parent. At the parent it can
    #    be absorbed by a sibling subtree. Root keeps it idle; no global pool.
    lea rax, [rip+parent]
    mov r12d, dword ptr [rax+rbx*4]
    cmp r12d, -1
    je .dfs_done
    lea rax, [rip+free_slots]
    sub dword ptr [rax+rbx*4], 1
    add dword ptr [rax+r12*4], 1
    mov edi, ebx
    mov esi, r12d
    call count_control_edge
    inc dword ptr [rip+cascade_up_steps]
    mov ebx, r12d
    jmp .dfs_outer

.dfs_done:
    pop r13
    pop r12
    pop rbx
    ret

verify_final_invariants:
    mov eax, dword ptr [rip+completed_count]
    cmp eax, dword ptr [rip+node_count]
    jne .vfi_fail
    mov eax, dword ptr [rip+dependency_messages]
    cmp eax, dword ptr [rip+edge_count]
    jne .vfi_fail
    # Every slot must end idle at a causal root; count root-held slots.
    mov dword ptr [rip+root_idle_slots], 0
    xor ebx, ebx
.vfi_nodes:
    cmp ebx, dword ptr [rip+node_count]
    jae .vfi_slots
    lea rax, [rip+assigned]
    cmp byte ptr [rax+rbx], 0
    jne .vfi_fail
    lea rax, [rip+ready_pending]
    cmp byte ptr [rax+rbx], 0
    jne .vfi_fail
    lea rax, [rip+pending_count]
    cmp dword ptr [rax+rbx*4], 0
    jne .vfi_fail
    lea rax, [rip+free_slots]
    mov ecx, dword ptr [rax+rbx*4]
    test ecx, ecx
    jz .vfi_next
    lea rax, [rip+parent]
    cmp dword ptr [rax+rbx*4], -1
    jne .vfi_fail
    add dword ptr [rip+root_idle_slots], ecx
.vfi_next:
    inc ebx
    jmp .vfi_nodes
.vfi_slots:
    mov eax, dword ptr [rip+root_idle_slots]
    cmp eax, dword ptr [rip+slot_count]
    jne .vfi_fail
    xor eax, eax
    ret
.vfi_fail:
    mov eax, 1
    ret

# ---------------------------------------------------------------------------
# JSON / parsing / errors
# ---------------------------------------------------------------------------
print_result_json:
    lea rdi, [rip+json_head]
    mov esi, json_head_end-json_head
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
    lea rdi, [rip+j_completed]
    mov esi, j_completed_end-j_completed
    mov edx, dword ptr [rip+completed_count]
    call print_num_field
    lea rdi, [rip+j_depmsg]
    mov esi, j_depmsg_end-j_depmsg
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
    lea rdi, [rip+j_idle]
    mov esi, j_idle_end-j_idle
    mov edx, dword ptr [rip+root_idle_slots]
    call print_num_field
    lea rdi, [rip+json_tail]
    mov esi, json_tail_end-json_tail
    call print_stdout
    ret

print_num_field:
    push rdx
    call print_stdout
    pop rdx
    mov eax, edx
    lea rdi, [rip+num_buffer+31]
    mov byte ptr [rdi], 0
    xor ecx, ecx
    test eax, eax
    jnz .pn_loop
    dec rdi
    mov byte ptr [rdi], '0'
    mov ecx, 1
    jmp .pn_out
.pn_loop:
    xor edx, edx
    mov ebx, 10
    div ebx
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
slot_error:
    lea rdi, [rip+msg_slots]
    mov esi, msg_slots_end-msg_slots
    call print_stderr
    mov edi, 65
    jmp exit_group
execution_error:
    lea rdi, [rip+msg_execution]
    mov esi, msg_execution_end-msg_execution
    call print_stderr
    mov edi, 65
    jmp exit_group
fabric_invariant_abort:
    lea rdi, [rip+msg_invariant]
    mov esi, msg_invariant_end-msg_invariant
    call print_stderr
    mov edi, 70
    jmp exit_group
exit_group:
    mov eax, SYS_exit_group
    syscall
    hlt

.section .rodata
msg_usage: .ascii "usage: topology-fabric N E SLOTS OWNER[N] EDGE_UV[2E] COMPLETION_ORDER[N]\n"
msg_usage_end:
msg_parse: .ascii "topology-fabric: malformed bounded fabric input\n"
msg_parse_end:
msg_cycle: .ascii "topology-fabric: dependency cycle rejected; no artificial order inserted\n"
msg_cycle_end:
msg_slots: .ascii "topology-fabric: slots must cover every causal source; disconnected components do not steal resources\n"
msg_slots_end:
msg_execution: .ascii "topology-fabric: completion event was not causally ready and resource-assigned\n"
msg_execution_end:
msg_invariant: .ascii "topology-fabric: internal causal ownership invariant failed\n"
msg_invariant_end:

json_head: .ascii "{\"format\":\"topology.causal-return-fabric/1\""
json_head_end:
j_nodes: .ascii ",\"nodes\":"
j_nodes_end:
j_edges: .ascii ",\"dependency_edges\":"
j_edges_end:
j_slots: .ascii ",\"resource_slots\":"
j_slots_end:
j_sources: .ascii ",\"causal_sources\":"
j_sources_end:
j_completed: .ascii ",\"completed_exactly_once\":"
j_completed_end:
j_depmsg: .ascii ",\"dependency_messages\":"
j_depmsg_end:
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
j_idle: .ascii ",\"final_idle_slots_at_causal_roots\":"
j_idle_end:
json_tail: .ascii ",\"global_ready_queue_ops\":0,\"global_claim_counter_ops\":0,\"work_steals\":0,\"runtime_global_ready_scans\":0,\"noncausal_dependency_messages\":0,\"noncausal_resource_edges\":0,\"resource_rule\":\"RESOURCE_FOLLOWS_CAUSAL_ADJACENCY\",\"return_rule\":\"LOCAL_THEN_PARENT_CASCADE\",\"disconnected_component_transfer\":\"FORBIDDEN\",\"status\":\"PROVEN_CLEAN\"}\n"
json_tail_end:

.section .bss
.align 64
node_count: .skip 4
edge_count: .skip 4
slot_count: .skip 4
arg_index: .skip 4
source_count: .skip 4
completed_count: .skip 4
proof_processed: .skip 4
dependency_messages: .skip 4
resource_assignments: .skip 4
direct_handoffs: .skip 4
cascade_up_steps: .skip 4
cascade_down_steps: .skip 4
local_control_edges: .skip 4
cross_owner_control_edges: .skip 4
local_adjacency_probes: .skip 4
root_idle_slots: .skip 4
.align 64
fabric_zero_begin:
owners: .skip 256
remaining_deps: .skip 256
proof_indegree: .skip 256
parent: .skip 256
first_out: .skip 256
first_child: .skip 256
next_sibling: .skip 256
free_slots: .skip 256
pending_count: .skip 256
source_list: .skip 256
completion_order: .skip 256
proof_removed: .skip 64
ready_pending: .skip 64
assigned: .skip 64
completed: .skip 64
.align 64
edge_u: .skip 1024
edge_v: .skip 1024
next_edge: .skip 1024
num_buffer: .skip 32
fabric_zero_end:
