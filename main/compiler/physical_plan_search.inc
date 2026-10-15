.include "compiler/physical_plan_layout.inc"
# Compiler-only physical residency. No search state enters emitted programs.
# Records use the common 64-byte ABI; callers prove type, scope and lifetime.
.text
.global physical_plan_alloc,physical_plan_free,physical_plan_bytes_alloc,physical_plan_bytes_free,physical_plan_resolve
physical_plan_alloc:
    imul rdi,rdi,PPR_SIZE
physical_plan_bytes_alloc:
    mov rsi,rdi
    mov eax,9
    xor edi,edi
    mov edx,3
    mov r10d,0x22
    mov r8,-1
    xor r9d,r9d
    syscall
    cmp rax,-4095
    jb .ppa_ret
    xor eax,eax
.ppa_ret: ret
physical_plan_free:
    imul rsi,rsi,PPR_SIZE
physical_plan_bytes_free:
    mov eax,11
    syscall
    ret

# rdi=records, esi=count, edx/ecx=real bank capacities, r8=joint score,
# r9=opaque; optional seventh argument verifies actual emitted physical cost.
# Positive independent equal-carrier facts have an exact density solution.
# Otherwise observe actual marginal conflicts. A stalled single change may
# bridge through locally worse intermediate facts to a better joint exchange.
# The actual carrier deficit determines how many old facts must be released.
# No temperature, random acceptance, cooling, fixed sweeps or workload gate.
# Commit only strict improvements; finite placements give termination. This
# local neighborhood is not a proof of globally optimal physical scheduling.
physical_plan_resolve:
    push rbp; push rbx; push r12; push r13; push r14; push r15
    sub rsp,112
    mov rax,[rsp+168]; mov [rsp+104],rax
    mov r12,rdi; mov r13d,esi
    mov [rsp],edx; mov [rsp+4],ecx
    mov [rsp+8],r8; mov [rsp+16],r9
    mov qword ptr [rsp+24],0
    mov qword ptr [rsp+88],0
    mov dword ptr [rsp+84],0
    xor ebx,ebx
.pr_clear:
    cmp ebx,r13d; jae .pr_seed
    imul rax,rbx,PPR_SIZE
    mov qword ptr [r12+rax+16],0
    mov ecx,[r12+rax+12]; cmp ecx,1; ja .pr_clear_next
    mov edx,[r12+rax+8]; test edx,edx; jz .pr_clear_next
    cmp qword ptr [r12+rax],0; jle .pr_clear_next
    cmp dword ptr [rsp+88+rcx*4],0; jne .pr_weight_compare
    mov [rsp+88+rcx*4],edx
.pr_weight_compare:
    cmp edx,[rsp+88+rcx*4]; je .pr_clear_next
    mov dword ptr [rsp+84],1
.pr_clear_next:
    inc ebx; jmp .pr_clear
.pr_seed:
    mov ebp,-1
    xor r10d,r10d; mov r11d,1
    xor ebx,ebx
.pr_seed_scan:
    cmp ebx,r13d; jae .pr_seed_pick
    imul rax,rbx,PPR_SIZE; lea rdi,[r12+rax]
    cmp dword ptr [rdi+16],0; jne .pr_seed_next
    mov ecx,[rdi+12]; cmp ecx,1; ja .pr_seed_next
    mov edx,[rdi+8]; test edx,edx; jz .pr_seed_next
    mov eax,[rsp+24+rcx*4]; add eax,edx
    cmp eax,[rsp+rcx*4]; ja .pr_seed_next
    mov rax,[rdi]; test rax,rax; jle .pr_seed_next
    imul rax,r11; mov ecx,edx; imul rcx,r10
    cmp rax,rcx; jle .pr_seed_next
    mov r10,[rdi]; mov r11d,edx; mov ebp,ebx
.pr_seed_next:
    inc ebx; jmp .pr_seed_scan
.pr_seed_pick:
    test ebp,ebp; js .pr_seed_done
    mov eax,ebp; call .pr_toggle
    jmp .pr_seed
.pr_seed_done:
    xor ecx,ecx
.pr_seed_record:
    cmp ecx,r13d; jae .pr_seed_score
    imul rax,rcx,PPR_SIZE
    mov edx,[r12+rax+16]; mov [r12+rax+52],edx
    inc ecx; jmp .pr_seed_record
.pr_seed_score:
    call .pr_score
    test rax,rax; jns .pr_seed_profitable
    # The empty placement is admissible; preserve the physical seed separately.
    xor ecx,ecx
.pr_empty:
    cmp ecx,r13d; jae .pr_empty_score
    imul rax,rcx,PPR_SIZE; mov dword ptr [r12+rax+16],0
    inc ecx; jmp .pr_empty
.pr_empty_score:
    mov qword ptr [rsp+24],0
    call .pr_score
.pr_seed_profitable:
    mov [rsp+32],rax
    mov [rsp+40],rax; call .pr_snapshot
.pr_exact_check:
    cmp qword ptr [rsp+8],0; jne .pr_sweep
    cmp dword ptr [rsp+84],0; je .pr_finish
.pr_sweep:
    mov rax,[rsp+32]; mov [rsp+56],rax
    mov qword ptr [rsp+72],-1
    mov dword ptr [rsp+80],0
    xor ebx,ebx
.pr_single:
    cmp ebx,r13d; jae .pr_single_done
    imul rbp,rbx,PPR_SIZE; add rbp,r12
    cmp dword ptr [rbp+12],1; ja .pr_single_next
    cmp dword ptr [rbp+8],0; je .pr_single_next
    mov rax,[rsp+24]; mov [rsp+64],rax
    mov eax,ebx; call .pr_toggle
    call .pr_fits; test eax,eax; jz .pr_capacity_conflict
    call .pr_score
    mov rcx,[rbp]; cmp dword ptr [rbp+16],0; jne .pr_delta
    neg rcx
.pr_delta:
    add rcx,[rsp+32]; cmp rax,rcx; je .pr_single_price
    mov dword ptr [rsp+80],1
.pr_single_price:
    cmp rax,[rsp+56]; jle .pr_single_restore
    mov [rsp+56],rax; mov [rsp+72],ebx
    mov dword ptr [rsp+76],-1
    jmp .pr_single_restore
.pr_capacity_conflict:
    mov dword ptr [rsp+80],1
.pr_single_restore:
    mov eax,ebx; call .pr_toggle
    mov rax,[rsp+64]; mov [rsp+24],rax
.pr_single_next:
    inc ebx; jmp .pr_single
.pr_single_done:
    cmp dword ptr [rsp+72],-1; jne .pr_commit
    cmp dword ptr [rsp+80],0; je .pr_finish
    # Expand the neighborhood only after an observed interaction or capacity
    # conflict. Intermediate choices are compiler scratch, never realizations.
    xor ebx,ebx
.pr_pair:
    cmp ebx,r13d; jae .pr_pair_done
    imul rbp,rbx,PPR_SIZE; add rbp,r12
    cmp dword ptr [rbp+12],1; ja .pr_pair_next
    cmp dword ptr [rbp+8],0; je .pr_pair_next
    lea r15d,[rbx+1]
.pr_peer:
    cmp r15d,r13d; jae .pr_pair_next
    imul rax,r15,PPR_SIZE; lea r14,[r12+rax]
    cmp dword ptr [r14+12],1; ja .pr_peer_next
    cmp dword ptr [r14+8],0; je .pr_peer_next
    mov rax,[rsp+24]; mov [rsp+64],rax
    mov eax,ebx; call .pr_toggle
    mov eax,r15d; call .pr_toggle
    call .pr_repair; test eax,eax; jz .pr_pair_restore
    call .pr_score
    cmp rax,[rsp+56]; jle .pr_pair_restore
    mov [rsp+56],rax; mov [rsp+72],ebx; mov [rsp+76],r15d
.pr_pair_restore:
    call .pr_restore_current
    mov rax,[rsp+64]; mov [rsp+24],rax
.pr_peer_next:
    inc r15d; jmp .pr_peer
.pr_pair_next:
    inc ebx; jmp .pr_pair
.pr_pair_done:
    cmp dword ptr [rsp+72],-1; je .pr_finish
.pr_commit:
    mov eax,[rsp+72]; call .pr_toggle
    mov eax,[rsp+76]; test eax,eax; js .pr_committed
    call .pr_toggle
.pr_committed:
    call .pr_repair
    mov rax,[rsp+56]; mov [rsp+32],rax
    cmp rax,[rsp+40]; jle .pr_sweep
    mov [rsp+40],rax; call .pr_snapshot
    jmp .pr_sweep
.pr_finish:
    xor ebx,ebx
.pr_restore:
    cmp ebx,r13d; jae .pr_verify
    imul rax,rbx,PPR_SIZE
    mov ecx,[r12+rax+20]; mov [r12+rax+16],ecx
    inc ebx; jmp .pr_restore
.pr_verify:
    mov rbp,[rsp+104]; test rbp,rbp; jz .pr_ret
    xor ecx,ecx
.pr_distinct:
    cmp ecx,r13d; jae .pr_ret
    imul rax,rcx,PPR_SIZE
    mov edx,[r12+rax+16]; cmp edx,[r12+rax+52]; jne .pr_emitted
    inc ecx; jmp .pr_distinct
.pr_emitted:
    mov rdi,r12; mov esi,r13d; mov rdx,[rsp+16]; call rbp
    mov [rsp+72],rax
    xor ebx,ebx
.pr_seed_trial:
    cmp ebx,r13d; jae .pr_seed_cost
    imul rax,rbx,PPR_SIZE
    mov ecx,[r12+rax+52]; mov [r12+rax+16],ecx
    inc ebx; jmp .pr_seed_trial
.pr_seed_cost:
    mov rdi,r12; mov esi,r13d; mov rdx,[rsp+16]; call rbp
    cmp rax,[rsp+72]; jl .pr_seed_verified
    mov qword ptr [rsp+104],0
    xor ebx,ebx; jmp .pr_restore
.pr_seed_verified:
    call .pr_score; mov [rsp+40],rax
.pr_ret:
    mov rax,[rsp+40]
    add rsp,112
    pop r15; pop r14; pop r13; pop r12; pop rbx; pop rbp; ret
.pr_fits:
    mov eax,[rsp+32]; cmp eax,[rsp+8]; ja .pr_no_fit
    mov eax,[rsp+36]; cmp eax,[rsp+12]; ja .pr_no_fit
    mov eax,1; ret
.pr_no_fit:
    xor eax,eax; ret
.pr_restore_current:
    xor ecx,ecx
.pr_restore_fact:
    cmp ecx,r13d; jae .pr_restore_done
    imul rax,rcx,PPR_SIZE
    mov edx,[r12+rax+20]; mov [r12+rax+16],edx
    inc ecx; jmp .pr_restore_fact
.pr_restore_done: ret
# A speculative insertion borrows space by releasing old owners only from the
# overfull bank. The deficit, rather than a search-depth constant, ends the
# bridge. Release order uses the same gain/carrier facts as the seed; the joint
# objective evaluates the complete proposal before any commitment.
.pr_repair:
    mov r8d,0
    mov eax,[rsp+32]; cmp eax,[rsp+8]; ja .pr_release_scan
    inc r8d
    mov eax,[rsp+36]; cmp eax,[rsp+12]; ja .pr_release_scan
    mov eax,1; ret
.pr_release_scan:
    mov r9d,-1; xor ecx,ecx
.pr_release_fact:
    cmp ecx,r13d; jae .pr_release_owner
    imul rax,rcx,PPR_SIZE; lea rdi,[r12+rax]
    cmp dword ptr [rdi+16],0; je .pr_release_next
    cmp dword ptr [rdi+20],0; je .pr_release_next
    cmp [rdi+12],r8d; jne .pr_release_next
    cmp r9d,-1; je .pr_release_pick
    mov rax,[rdi]; imul rax,r11
    mov edx,[rdi+8]; imul rdx,r10
    cmp rax,rdx; jge .pr_release_next
.pr_release_pick:
    mov r9d,ecx; mov r10,[rdi]; mov r11d,[rdi+8]
.pr_release_next:
    inc ecx; jmp .pr_release_fact
.pr_release_owner:
    cmp r9d,-1; je .pr_no_fit
    imul rax,r9,PPR_SIZE; lea rdi,[r12+rax]
    mov dword ptr [rdi+16],0
    mov edx,[rdi+8]; sub [rsp+32+r8*4],edx
    jmp .pr_repair
.pr_score:
    mov rax,[rsp+16]; test rax,rax; jz .pr_additive
    mov rdi,r12; mov esi,r13d; mov rdx,[rsp+24]; jmp rax
.pr_additive:
    xor eax,eax; xor ecx,ecx
.pr_sum:
    cmp ecx,r13d; jae .pr_sum_done
    imul rdx,rcx,PPR_SIZE
    cmp dword ptr [r12+rdx+16],0; je .pr_sum_next
    add rax,[r12+rdx]
.pr_sum_next:
    inc ecx; jmp .pr_sum
.pr_sum_done: ret
.pr_snapshot:
    xor ecx,ecx
.pr_copy:
    cmp ecx,r13d; jae .pr_copy_done
    imul rax,rcx,PPR_SIZE
    mov edx,[r12+rax+16]; mov [r12+rax+20],edx
    inc ecx; jmp .pr_copy
.pr_copy_done: ret
.pr_toggle:
    imul rax,rax,PPR_SIZE; lea rdi,[r12+rax]
    mov ecx,[rdi+12]; mov edx,[rdi+8]
    xor dword ptr [rdi+16],1
    cmp dword ptr [rdi+16],0; jne .pr_add_weight
    neg edx
.pr_add_weight:
    add [rsp+32+rcx*4],edx
    ret
