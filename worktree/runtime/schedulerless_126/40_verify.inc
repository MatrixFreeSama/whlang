# ---------------------------------------------------------------------------
# Final proof. Global scans are permitted only after all causal execution ended.
# ---------------------------------------------------------------------------
verify_final:
    xor ebx, ebx
.vf_nodes:
    cmp ebx, dword ptr [rip+node_count]
    jae .vf_slots
    lea rax, [rip+node_state]
    cmp byte ptr [rax+rbx], 3
    jne .vf_fail
    lea rax, [rip+remaining_deps]
    cmp dword ptr [rax+rbx*4], 0
    jne .vf_fail
    inc ebx
    jmp .vf_nodes
.vf_slots:
    xor ebx, ebx
.vf_slot_loop:
    cmp ebx, dword ptr [rip+slot_count]
    jae .vf_ok
    lea rax, [rip+home_remaining]
    cmp dword ptr [rax+rbx*4], 0
    jne .vf_fail
    lea rax, [rip+remote_head]
    cmp dword ptr [rax+rbx*4], EMPTY
    jne .vf_fail
    lea rax, [rip+remote_cache]
    cmp dword ptr [rax+rbx*4], EMPTY
    jne .vf_fail
    lea rax, [rip+slot_sp]
    cmp dword ptr [rax+rbx*4], 0
    jne .vf_fail
    lea rax, [rip+slot_parked]
    cmp dword ptr [rax+rbx*4], 0
    jne .vf_fail
    inc ebx
    jmp .vf_slot_loop
.vf_ok:
    xor eax, eax
    ret
.vf_fail:
    mov eax, 1
    ret

aggregate_metrics:
    lea rdi, [rip+totals_begin]
    xor eax, eax
    mov ecx, (totals_end-totals_begin)/8
    rep stosq
    xor ebx, ebx
.am_loop:
    cmp ebx, dword ptr [rip+slot_count]
    jae .am_done
    lea rax, [rip+metric_claims]
    mov rdx, qword ptr [rax+rbx*8]
    add qword ptr [rip+total_claims], rdx
    lea rax, [rip+metric_edges]
    mov rdx, qword ptr [rax+rbx*8]
    add qword ptr [rip+total_edges], rdx
    lea rax, [rip+metric_direct]
    mov rdx, qword ptr [rax+rbx*8]
    add qword ptr [rip+total_direct], rdx
    lea rax, [rip+metric_remote]
    mov rdx, qword ptr [rax+rbx*8]
    add qword ptr [rip+total_remote], rdx
    lea rax, [rip+metric_collisions]
    mov rdx, qword ptr [rax+rbx*8]
    add qword ptr [rip+total_collisions], rdx
    lea rax, [rip+metric_fallbacks]
    mov rdx, qword ptr [rax+rbx*8]
    add qword ptr [rip+total_fallbacks], rdx
    lea rax, [rip+metric_waits]
    mov rdx, qword ptr [rax+rbx*8]
    add qword ptr [rip+total_waits], rdx
    inc ebx
    jmp .am_loop
.am_done:
    mov rax, qword ptr [rip+total_claims]
    cmp eax, dword ptr [rip+node_count]
    jne runtime_error
    mov rax, qword ptr [rip+total_edges]
    cmp eax, dword ptr [rip+edge_count]
    jne runtime_error
    cmp qword ptr [rip+total_collisions], 0
    jne runtime_error
    cmp qword ptr [rip+total_fallbacks], 0
    jne runtime_error
    ret
