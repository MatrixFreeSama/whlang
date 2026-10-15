# Compiler-only scheduling of native, register-only scalar ValueFacts. The
# existing expression emitter and physical_encode_rrr remain the sole semantic
# and byte authorities. An opaque byte primitive closes the window before its
# instruction: memory, effects, branches, conversions and calls never cross it.
# SSA versions preserve operand order and rounding; no contraction/reassociation.
# Output anchors and constant/CSE authorities retain their existing carriers.
# Anonymous versions use the entire architectural carrier domain with the
# same owner/future-consumer proof. A strict
# resource-price improvement including actual front-end bytes is required.
# Only register arithmetic is captured: no internal label/fixup is exported,
# and the next opaque primitive has not been emitted when the window closes.
# Re-encoding can change its span; later addresses derive from the final cursor.
# Original bytes are retained for proof misses; no alternate semantic generator,
# runtime scheduler, source recognizer or fixed grouping is introduced.
.text
# Transparent to the deliberately small clobber footprint of byte primitives.
g_phys_window_barrier:
    pushfq
    cmp dword ptr [rip+g_phys_window_active],0; je .gpwb_fast
    cmp dword ptr [rip+g_phys_window_encoding],0; jne .gpwb_fast
    cmp dword ptr [rip+g_phys_window_count],0; je .gpwb_fast
    push rax; push rcx; push rdx; push rsi; push rdi
    push r8; push r9; push r10; push r11
    call g_phys_window_flush
    pop r11; pop r10; pop r9; pop r8
    pop rdi; pop rsi; pop rdx; pop rcx; pop rax
.gpwb_fast:
    popfq; ret

# Same descriptor interface as the common encoder; captures only scalar binary
# arithmetic. The already encoded bytes are written immediately, so existing
# patch addresses and code-buffer ownership remain authoritative.
g_phys_window_scalar_descriptor:
    cmp dword ptr [rip+g_phys_window_active],0; je g_emit_phys_rrr_descriptor
    # The scalar binary arithmetic descriptor family excludes move/conversion.
    mov eax,edi; and eax,0xff; cmp eax,0x58; jb .gpws_opaque
    cmp eax,0x5f; ja .gpws_opaque
    cmp eax,0x5a; je .gpws_opaque
    cmp eax,0x5b; je .gpws_opaque
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,24
    mov [rsp],edi; mov [rsp+4],esi; mov [rsp+8],edx; mov [rsp+12],ecx
    mov ebx,[rip+g_phys_window_count]
    cmp ebx,[rip+g_phys_window_capacity]; jb .gpws_room
    mov r12d,[rip+g_phys_window_capacity]
    test r12d,r12d; jnz .gpws_grow
    mov r12d,32                    # capacity derives from one OS page
.gpws_grow:
    shl r12d,1
    mov edi,r12d; shl rdi,6; call physical_plan_bytes_alloc
    test rax,rax; jz .gpws_no_arena
    mov r13,rax
    mov rsi,[rip+g_phys_window_records]; mov rdi,r13
    mov ecx,ebx; shl ecx,3; rep movsq
    mov rdi,[rip+g_phys_window_records]; test rdi,rdi; jz .gpws_publish
    mov esi,[rip+g_phys_window_capacity]; shl rsi,6; call physical_plan_bytes_free
.gpws_publish:
    mov [rip+g_phys_window_records],r13
    mov [rip+g_phys_window_capacity],r12d
.gpws_room:
    mov edi,[rsp]; mov esi,[rsp+4]; mov edx,[rsp+8]; mov ecx,[rsp+12]
    call physical_encode_rrr
    test edx,edx; jz .gpws_bad
    mov r12,rax; mov r13d,edx
    test ebx,ebx; jnz .gpws_record
    mov rax,[rip+g_emit_ptr]; mov [rip+g_phys_window_start],rax
.gpws_record:
    mov r14,[rip+g_phys_window_records]; mov eax,ebx; shl rax,6; add r14,rax
    mov rax,[rsp]; mov [r14],rax
    mov rax,[rsp+8]; mov [r14+8],rax
    mov [r14+48],r12; mov [r14+56],r13d
    mov [rsp+16],r12
    mov dword ptr [rip+g_phys_window_encoding],1
    lea rdi,[rsp+16]; mov esi,r13d; call g_emit_bytes
    mov dword ptr [rip+g_phys_window_encoding],0
    test eax,eax; jnz .gpws_bad
    inc dword ptr [rip+g_phys_window_count]
    jmp .gpws_done
.gpws_no_arena:
    call g_phys_window_flush
    mov dword ptr [rip+g_phys_window_active],0
    mov edi,[rsp]; mov esi,[rsp+4]; mov edx,[rsp+8]; mov ecx,[rsp+12]
    call g_emit_phys_rrr_descriptor
    jmp .gpws_done
.gpws_bad:
    mov eax,1
.gpws_done:
    add rsp,24
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret
.gpws_opaque:
    call g_phys_window_barrier
    jmp g_emit_phys_rrr_descriptor

# SSA id < 0 denotes an initial physical authority; id >= 0 denotes a record.
# eax=id -> rax=&remaining-use count. Preserves all other registers.
g_phys_window_uses:
    test eax,eax; js .gpwu_initial
    shl rax,6; add rax,[rip+g_phys_window_records]; add rax,32; ret
.gpwu_initial:
    neg eax; dec eax
    push rdx; lea rdx,[rip+g_phys_window_initial_uses]
    lea rax,[rdx+rax*4]; pop rdx; ret

# eax=id -> eax=physical carrier.
g_phys_window_reg:
    test eax,eax; js .gpwr_initial
    shl rax,6; add rax,[rip+g_phys_window_records]; mov eax,[rax+20]; ret
.gpwr_initial: neg eax; dec eax; ret

# eax=id -> rax=completion ticks, CF=1 if not emitted yet.
g_phys_window_ready:
    test eax,eax; js .gpwready_initial
    shl rax,6; add rax,[rip+g_phys_window_records]
    cmp dword ptr [rax+60],-1; je .gpwready_no
    mov rax,[rax+40]; clc; ret
.gpwready_initial: xor eax,eax; ret
.gpwready_no: stc; ret

# eax=id: retire one read; release only dead, unanchored versions.
g_phys_window_consume:
    push rbx; push r12
    mov ebx,eax
    call g_phys_window_uses
    dec dword ptr [rax]; jnz .gpwc_done
    mov eax,ebx; call g_phys_window_reg; mov r12d,eax
    test ebx,ebx; jns .gpwc_produced
    bt dword ptr [rip+g_phys_window_initial_keep],r12d; jc .gpwc_done
    jmp .gpwc_free
.gpwc_produced:
    mov eax,ebx; shl rax,6; add rax,[rip+g_phys_window_records]
    cmp dword ptr [rax+36],-1; jne .gpwc_done
.gpwc_free:
    lea rax,[rip+g_phys_window_owner]
    mov dword ptr [rax+r12*4],0x80000000
.gpwc_done: pop r12; pop rbx; ret

# edi=physical destination, rsi=candidate record -> eax=available. A live owner
# can be overwritten only when both of its remaining reads are this operation.
g_phys_window_available:
    push rbx; push r12; push r13
    mov r12d,edi; mov r13,rsi
    lea rax,[rip+g_phys_window_owner]; mov ebx,[rax+r12*4]
    cmp ebx,0x80000000; je .gpwa_yes
    test ebx,ebx; jns .gpwa_produced
    bt dword ptr [rip+g_phys_window_initial_keep],r12d; jc .gpwa_no
    jmp .gpwa_reads
.gpwa_produced:
    mov eax,ebx; shl rax,6; add rax,[rip+g_phys_window_records]
    cmp dword ptr [rax+36],-1; jne .gpwa_no
.gpwa_reads:
    xor r12d,r12d
    cmp ebx,[r13+24]; sete r12b
    xor eax,eax; cmp ebx,[r13+28]; sete al; add r12d,eax
    mov eax,ebx; call g_phys_window_uses
    cmp r12d,[rax]; jne .gpwa_no
.gpwa_yes: mov eax,1; jmp .gpwa_done
.gpwa_no: xor eax,eax
.gpwa_done: pop r13; pop r12; pop rbx; ret

# edi=descriptor -> eax=issue price, edx=latency, shared physical-price units.
g_phys_window_price:
    and edi,0xff
    mov eax,PRC_FP_ADD_TICKS; mov edx,PRC_FP_ADD_LATENCY_TICKS
    cmp edi,0x59; jne .gpwp_div
    mov eax,PRC_FP_MUL_TICKS
.gpwp_div:
    cmp edi,0x5e; jne .gpwp_done
    mov eax,PRC_FP_DIV_TICKS; mov edx,PRC_FP_DIV_TICKS
.gpwp_done: ret

g_phys_window_flush:
    cmp dword ptr [rip+g_phys_window_count],0; je .gpw_empty
    push rbx; push r12; push r13; push r14; push r15
    mov dword ptr [rip+g_phys_window_active],0
    mov rax,[rip+g_emit_ptr]; mov [rip+g_phys_window_end],rax
    mov r12,[rip+g_phys_window_records]
    # Initial SSA versions and per-version reads, not root/state occurrence counts.
    lea rdi,[rip+g_phys_window_initial_uses]; xor eax,eax; mov ecx,32; rep stosd
    lea rdi,[rip+g_phys_window_last]; xor ecx,ecx
.gpw_init:
    mov eax,ecx; neg eax; dec eax; mov [rdi+rcx*4],eax
    inc ecx; cmp ecx,32; jb .gpw_init
    xor ebx,ebx; xor r13d,r13d; xor r14d,r14d
    mov dword ptr [rip+g_phys_window_written],0
.gpw_graph:
    cmp ebx,[rip+g_phys_window_count]; jae .gpw_graph_done
    mov eax,ebx; shl rax,6; lea r15,[r12+rax]
    mov dword ptr [r15+32],0; mov dword ptr [r15+36],-1
    lea rdx,[rip+g_phys_window_last]
    mov ecx,[r15+8]; mov eax,[rdx+rcx*4]; mov [r15+24],eax
    call g_phys_window_uses; inc dword ptr [rax]
    lea rdx,[rip+g_phys_window_last]
    mov ecx,[r15+12]; mov eax,[rdx+rcx*4]; mov [r15+28],eax
    call g_phys_window_uses; inc dword ptr [rax]
    lea rdx,[rip+g_phys_window_last]
    mov ecx,[r15+4]; mov [rdx+rcx*4],ebx
    bts dword ptr [rip+g_phys_window_written],ecx
    # Original issue-order lower bound using the same SSA and prices.
    mov eax,[r15+24]; call g_phys_window_ready; mov r14,rax
    mov eax,[r15+28]; call g_phys_window_ready
    cmp rax,r14; cmovb rax,r14
    cmp rax,r13; cmovb rax,r13; mov r13,rax
    mov edi,[r15]; call g_phys_window_price
    mov ecx,edx; add rcx,r13; mov [r15+40],rcx
    add r13,rax; mov [r15+60],ebx
    inc ebx; jmp .gpw_graph
.gpw_graph_done:
    xor ebx,ebx
.gpw_original_finish:
    cmp ebx,[rip+g_phys_window_count]; jae .gpw_original_closed
    mov eax,ebx; shl rax,6
    mov rdx,[r12+rax+40]; cmp rdx,r13; cmova r13,rdx
    inc ebx; jmp .gpw_original_finish
.gpw_original_closed:
    mov rax,[rip+g_phys_window_end]; sub rax,[rip+g_phys_window_start]
    imul rax,PRC_FRONTEND_BYTE_TICKS
    cmp r13,rax; cmovb r13,rax
    mov [rip+g_phys_window_original_price],r13
    # Preserve every initial value that is live beyond this window and has not
    # been replaced by a recorded result. Free anonymous carriers are dead.
    mov eax,[rip+g_phys_window_written]; not eax
    mov edx,[rip+g_phys_fp_temp_mask]; not edx; and eax,edx
    mov [rip+g_phys_window_initial_keep],eax
    xor ecx,ecx
.gpw_owners:
    lea rdx,[rip+g_phys_window_owner]
    mov eax,0x80000000
    lea rdi,[rip+g_phys_window_initial_uses]
    cmp dword ptr [rdi+rcx*4],0; jne .gpw_owner_initial
    bt dword ptr [rip+g_phys_window_initial_keep],ecx; jnc .gpw_owner_set
.gpw_owner_initial:
    mov eax,ecx; neg eax; dec eax
.gpw_owner_set:
    mov [rdx+rcx*4],eax
    inc ecx; cmp ecx,32; jb .gpw_owners
    xor ebx,ebx
.gpw_anchors:
    cmp ebx,[rip+g_phys_window_count]; jae .gpw_schedule_start
    mov eax,ebx; shl rax,6; lea r15,[r12+rax]
    mov dword ptr [r15+60],-1
    mov ecx,[r15+4]; lea rdx,[rip+g_phys_window_last]
    cmp ebx,[rdx+rcx*4]; jne .gpw_anchor_next
    bt dword ptr [rip+g_phys_fp_temp_mask],ecx; jc .gpw_anchor_next
    mov [r15+36],ecx
.gpw_anchor_next: inc ebx; jmp .gpw_anchors
.gpw_schedule_start:
    mov rax,[rip+g_phys_window_start]; mov [rip+g_emit_ptr],rax
    xor r13d,r13d; xor r14d,r14d
.gpw_schedule:
    cmp r14d,[rip+g_phys_window_count]; jae .gpw_admit
    mov dword ptr [rip+g_phys_window_best],-1
    mov qword ptr [rip+g_phys_window_best_ready],-1
    xor ebx,ebx
.gpw_candidate:
    cmp ebx,[rip+g_phys_window_count]; jae .gpw_selected
    mov eax,ebx; shl rax,6; lea r15,[r12+rax]
    cmp dword ptr [r15+60],-1; jne .gpw_candidate_next
    mov eax,[r15+24]; call g_phys_window_ready; jc .gpw_candidate_next
    mov [rip+g_phys_window_candidate_ready],rax
    mov eax,[r15+28]; call g_phys_window_ready; jc .gpw_candidate_next
    cmp rax,[rip+g_phys_window_candidate_ready]; jae .gpw_candidate_ready
    mov rax,[rip+g_phys_window_candidate_ready]
.gpw_candidate_ready:
    cmp rax,[rip+g_phys_window_best_ready]; jae .gpw_candidate_next
    mov [rip+g_phys_window_candidate_ready],rax
    mov edi,[r15+36]
    cmp edi,-1; jne .gpw_try_anchor
    # Keep the established carrier when it is already available. Renaming is
    # needed only to remove a real physical ownership conflict, not by default.
    mov edi,[r15+4]
    push rdi; mov rsi,r15; call g_phys_window_available; pop rdi
    test eax,eax; jnz .gpw_found_carrier
    xor edi,edi
.gpw_find_carrier:
    cmp edi,[rip+g_phys_fp_carrier_count]; jae .gpw_candidate_next
    push rdi; mov rsi,r15; call g_phys_window_available; pop rdi
    test eax,eax; jnz .gpw_found_carrier
    inc edi; jmp .gpw_find_carrier
.gpw_try_anchor:
    push rdi; mov rsi,r15; call g_phys_window_available; pop rdi
    test eax,eax; jz .gpw_candidate_next
.gpw_found_carrier:
    mov [rip+g_phys_window_best_reg],edi
    mov [rip+g_phys_window_best],ebx
    mov rax,[rip+g_phys_window_candidate_ready]; mov [rip+g_phys_window_best_ready],rax
.gpw_candidate_next: inc ebx; jmp .gpw_candidate
.gpw_selected:
    mov ebx,[rip+g_phys_window_best]; cmp ebx,-1; je .gpw_restore
    mov eax,ebx; shl rax,6; lea r15,[r12+rax]
    mov eax,[r15+24]; call g_phys_window_reg; mov [rip+g_phys_window_src1],eax
    mov eax,[r15+28]; call g_phys_window_reg; mov [rip+g_phys_window_src2],eax
    mov eax,[r15+24]; call g_phys_window_consume
    mov eax,[r15+28]; call g_phys_window_consume
    mov esi,[rip+g_phys_window_best_reg]; mov [r15+20],esi
    lea rax,[rip+g_phys_window_owner]; mov [rax+rsi*4],ebx
    mov rax,[rip+g_phys_window_best_ready]
    cmp rax,r13; cmovb rax,r13; mov r13,rax
    mov edi,[r15]; call g_phys_window_price
    mov ecx,edx; add rcx,r13; mov [r15+40],rcx; add r13,rax
    mov [r15+60],r14d
    mov edi,[r15]
    # Re-derive the existing encoding geometry after anonymous renaming.
    and edi,0xffff6fff
    mov esi,[r15+20]; mov edx,[rip+g_phys_window_src1]; mov ecx,[rip+g_phys_window_src2]
    mov eax,esi; or eax,edx; or eax,ecx; cmp eax,15; jbe .gpw_vex
    or edi,0x8000
    mov eax,edi; and eax,0xc00; cmp eax,0xc00; jne .gpw_encode
    or edi,0x1000; jmp .gpw_encode
.gpw_vex: and edi,0xffff7fff
.gpw_encode:
    call physical_encode_rrr
    test edx,edx; jz .gpw_restore
    sub rsp,8; mov [rsp],rax; mov rdi,rsp; mov esi,edx; call g_emit_bytes; add rsp,8
    test eax,eax; jnz .gpw_restore
    # A produced version with no consumers and no live-out anchor is dead now.
    cmp dword ptr [r15+32],0; jne .gpw_next
    cmp dword ptr [r15+36],-1; jne .gpw_next
    mov ecx,[r15+20]; lea rax,[rip+g_phys_window_owner]
    mov dword ptr [rax+rcx*4],0x80000000
.gpw_next: inc r14d; jmp .gpw_schedule
.gpw_admit:
    xor ebx,ebx
.gpw_proposed_finish:
    cmp ebx,[rip+g_phys_window_count]; jae .gpw_proposed_closed
    mov eax,ebx; shl rax,6
    mov rdx,[r12+rax+40]; cmp rdx,r13; cmova r13,rdx
    inc ebx; jmp .gpw_proposed_finish
.gpw_proposed_closed:
    mov rax,[rip+g_emit_ptr]; sub rax,[rip+g_phys_window_start]
    imul rax,PRC_FRONTEND_BYTE_TICKS
    cmp r13,rax; cmovb r13,rax
    cmp r13,[rip+g_phys_window_original_price]; jb .gpw_done
.gpw_restore:
    mov rax,[rip+g_phys_window_start]; mov [rip+g_emit_ptr],rax
    xor ebx,ebx
.gpw_restore_next:
    cmp ebx,[rip+g_phys_window_count]; jae .gpw_done
    mov eax,ebx; shl rax,6; lea rdi,[r12+rax+48]; mov esi,[rdi+8]
    call g_emit_bytes
    inc ebx; jmp .gpw_restore_next
.gpw_done:
    mov dword ptr [rip+g_phys_window_count],0
    mov dword ptr [rip+g_phys_window_active],1
    pop r15; pop r14; pop r13; pop r12; pop rbx
.gpw_empty: ret

.bss
.p2align 3
g_phys_window_records: .skip 8
g_phys_window_start: .skip 8
g_phys_window_end: .skip 8
g_phys_window_original_price: .skip 8
g_phys_window_best_ready: .skip 8
g_phys_window_candidate_ready: .skip 8
g_phys_window_active: .skip 4
g_phys_window_encoding: .skip 4
g_phys_window_count: .skip 4
g_phys_window_capacity: .skip 4
g_phys_window_written: .skip 4
g_phys_window_initial_keep: .skip 4
g_phys_window_best: .skip 4
g_phys_window_best_reg: .skip 4
g_phys_window_src1: .skip 4
g_phys_window_src2: .skip 4
g_phys_window_last: .skip 128
g_phys_window_owner: .skip 128
g_phys_window_initial_uses: .skip 128
.text
