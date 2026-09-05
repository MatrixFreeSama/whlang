# ---------------------------------------------------------------------------
# Startup proof / AOT-shaped source seeding. Runtime scheduling begins only
# after this section; no all-node scan appears after run_slot_tree starts.
# ---------------------------------------------------------------------------
clear_state:
    lea rdi, [rip+zero_begin]
    xor eax, eax
    mov ecx, (zero_end-zero_begin)/8
    rep stosq

    mov eax, EMPTY
    lea rdi, [rip+first_out]
    mov ecx, MAX_NODES
    rep stosd
    lea rdi, [rip+next_edge]
    mov ecx, MAX_EDGES
    rep stosd
    lea rdi, [rip+mailbox]
    mov ecx, MAX_SLOTS
    rep stosd
    ret

# Kahn proof is startup validation only. It never participates in execution.
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
    inc dword ptr [rip+proof_processed]
    mov r8d, 1
    lea rax, [rip+first_out]
    mov r9d, dword ptr [rax+rbx*4]
.pd_edges:
    cmp r9d, EMPTY
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

seed_sources:
    mov dword ptr [rip+source_count], 0
    xor ebx, ebx
.ss_scan:
    cmp ebx, dword ptr [rip+node_count]
    jae .ss_done
    lea rax, [rip+remaining_deps]
    cmp dword ptr [rax+rbx*4], 0
    jne .ss_next
    lea rax, [rip+node_state]
    mov byte ptr [rax+rbx], 1
    lea rax, [rip+home_slot]
    mov edi, dword ptr [rax+rbx*4]
    mov esi, ebx
    call startup_push_local
    test eax, eax
    jnz .ss_fail
    inc dword ptr [rip+source_count]
.ss_next:
    inc ebx
    jmp .ss_scan
.ss_done:
    cmp dword ptr [rip+source_count], 0
    je .ss_fail
    xor eax, eax
    ret
.ss_fail:
    mov eax, 1
    ret

# startup_push_local(edi=slot, esi=node). No concurrency yet.
startup_push_local:
    lea rax, [rip+slot_sp]
    mov ecx, dword ptr [rax+rdi*4]
    cmp ecx, MAX_NODES
    jae .spl_fail
    mov eax, edi
    imul eax, eax, MAX_NODES
    add eax, ecx
    lea rdx, [rip+local_stack]
    mov dword ptr [rdx+rax*4], esi
    lea rax, [rip+slot_sp]
    inc dword ptr [rax+rdi*4]
    xor eax, eax
    ret
.spl_fail:
    mov eax, 1
    ret
