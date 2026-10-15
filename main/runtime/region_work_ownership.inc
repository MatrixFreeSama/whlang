# Cold ready-root ownership closure. The existing node line owns both its work
# fact and its bundle sum. No task queue, runtime idle query or work transfer.
# node +24/32 = work low64/high32; +36=unknown. Bundle +40/48=128-bit sum,
# +56=unknown cardinality; +60=assignment/price-closure bits. Line stays 64.
.equ ST_WORK_LO,24
.equ ST_WORK_HI,32
.equ ST_WORK_UNKNOWN,36
.equ ST_BUNDLE_LO,40
.equ ST_BUNDLE_HI,48
.equ ST_BUNDLE_UNKNOWN,56
.equ ST_WORK_FLAGS,60
.equ ST_ROOT_ASSIGNED_BIT,1
.equ ST_WORK_PRICE_CLOSED_BIT,2
.text
gr_meta_work_fact_ptr:
    call gr_meta_fabric_descriptor_ptr
    mov ecx,[rip+gr_node_count]; imul rcx,rcx,48; add rax,rcx; ret

# edi=node -> rdx:rax=base + bound*slope, ecx=unknown.
# work_ticks and the existing 16-byte projection describe one work relation.
# No early expression evaluation; input carriers already passed admission.
gr_node_work_price:
    push rbx; push r12
    mov ebx,edi
    mov r8d,ebx; shl r8,6
    test dword ptr [r15+r8+ST_WORK_FLAGS],ST_WORK_PRICE_CLOSED_BIT
    jnz .grnwp_read
    call gr_meta_work_ticks_ptr
    mov r12d,[rax+rbx*4]
    cmp r12d,-1; je .grnwp_unknown
    call gr_meta_work_fact_ptr
    mov ecx,ebx; shl rcx,4; add rcx,rax
    mov edx,[rcx+12]
    test edx,edx; jz .grnwp_base
    mov rax,[rcx]
    cmp edx,2; jne .grnwp_bound
    mov rax,[rax]
.grnwp_bound:
    mov edx,[rcx+8]; mul rdx
    add rax,r12; adc rdx,0
    xor ecx,ecx; jmp .grnwp_done
.grnwp_base:
    mov rax,r12; xor edx,edx; xor ecx,ecx; jmp .grnwp_done
.grnwp_unknown:
    xor eax,eax; xor edx,edx; mov ecx,1
.grnwp_done:
    mov r8d,ebx; shl r8,6
    mov [r15+r8+ST_WORK_LO],rax
    mov [r15+r8+ST_WORK_HI],edx
    mov [r15+r8+ST_WORK_UNKNOWN],ecx
    or dword ptr [r15+r8+ST_WORK_FLAGS],ST_WORK_PRICE_CLOSED_BIT
    jmp .grnwp_return
.grnwp_read:
    mov rax,[r15+r8+ST_WORK_LO]
    mov edx,[r15+r8+ST_WORK_HI]
    mov ecx,[r15+r8+ST_WORK_UNKNOWN]
.grnwp_return: pop r12; pop rbx; ret

# esi=extra lifecycle must be repaid (0/1), eax=highest unassigned ready root.
# Unknown work is explicit cardinality, never invented numeric cycles.
gr_choose_root:
    push rbx; push r12; push r13; push r14; push rbp
    mov ebp,esi; mov r12d,-1; xor ebx,ebx
.grcr_scan:
    cmp ebx,[rip+gr_node_count]; jae .grcr_done
    call gr_meta_indegree_ptr; cmp dword ptr [rax+rbx*4],0; jne .grcr_next
    call gr_meta_realization_tag_ptr; cmp dword ptr [rax+rbx*4],GR_REALIZATION_RECONFIGURABLE_FABRIC; je .grcr_next
    mov r14d,ebx; shl r14,6
    test dword ptr [r15+r14+ST_WORK_FLAGS],ST_ROOT_ASSIGNED_BIT; jnz .grcr_next
    test ebp,ebp; jz .grcr_compare
    mov edi,ebx; call gr_should_materialize; test eax,eax; jz .grcr_next
.grcr_compare:
    cmp r12d,-1; je .grcr_take
    mov r13d,r12d; shl r13,6
    mov eax,[r15+r14+ST_WORK_UNKNOWN]; cmp eax,[r15+r13+ST_WORK_UNKNOWN]
    ja .grcr_take; jb .grcr_next
    mov eax,[r15+r14+ST_WORK_HI]; cmp eax,[r15+r13+ST_WORK_HI]
    ja .grcr_take; jb .grcr_next
    mov rax,[r15+r14+ST_WORK_LO]; cmp rax,[r15+r13+ST_WORK_LO]
    jbe .grcr_next
.grcr_take: mov r12d,ebx
.grcr_next: inc ebx; jmp .grcr_scan
.grcr_done:
    mov eax,r12d
    cmp eax,-1; je .grcr_return
    mov ecx,eax; shl rcx,6; or dword ptr [r15+rcx+ST_WORK_FLAGS],ST_ROOT_ASSIGNED_BIT
.grcr_return: pop rbp; pop r14; pop r13; pop r12; pop rbx; ret

# ebx=root: publish one anchor and copy its work into the existing bundle line.
gr_anchor_root:
    mov eax,ebx; shl rax,6
    mov dword ptr [r15+rax+ST_NODE_LOCAL_NEXT],-1
    mov [r15+rax+ST_NODE_FRONTIER_TAIL],ebx
    mov dword ptr [r15+rax+ST_NODE_FRONTIER_ANCHOR_NEXT],-1
    mov dword ptr [r15+rax+ST_NODE_FRONTIER_ANCHOR],1
    mov rcx,[r15+rax+ST_WORK_LO]; mov [r15+rax+ST_BUNDLE_LO],rcx
    mov ecx,[r15+rax+ST_WORK_HI]; mov [r15+rax+ST_BUNDLE_HI],rcx
    mov ecx,[r15+rax+ST_WORK_UNKNOWN]; mov [r15+rax+ST_BUNDLE_UNKNOWN],ecx
    ret

# edi=first anchor -> eax=least accumulated work, stable ties.
gr_least_work_anchor:
    mov r8d,edi; mov r9d,edi
.grlwa_scan:
    mov ecx,r9d; shl rcx,6
    mov edx,[r15+rcx+ST_NODE_FRONTIER_ANCHOR_NEXT]
    cmp edx,-1; je .grlwa_done
    mov r9d,edx; shl rdx,6
    mov ecx,r8d; shl rcx,6
    mov eax,[r15+rdx+ST_BUNDLE_UNKNOWN]; cmp eax,[r15+rcx+ST_BUNDLE_UNKNOWN]
    jb .grlwa_take; ja .grlwa_scan
    mov rax,[r15+rdx+ST_BUNDLE_HI]; cmp rax,[r15+rcx+ST_BUNDLE_HI]
    jb .grlwa_take; ja .grlwa_scan
    mov rax,[r15+rdx+ST_BUNDLE_LO]; cmp rax,[r15+rcx+ST_BUNDLE_LO]
    jae .grlwa_scan
.grlwa_take: mov r8d,r9d; jmp .grlwa_scan
.grlwa_done: mov eax,r8d; ret

# ebx=root, r13d=anchor. Source-sized work sums fit 128 bits: u64*u32*u32.
gr_accumulate_root_work:
    mov eax,ebx; shl rax,6
    mov edx,r13d; shl rdx,6
    mov rcx,[r15+rax+ST_WORK_LO]; add [r15+rdx+ST_BUNDLE_LO],rcx
    mov ecx,[r15+rax+ST_WORK_HI]; adc [r15+rdx+ST_BUNDLE_HI],rcx
    mov ecx,[r15+rax+ST_WORK_UNKNOWN]; add [r15+rdx+ST_BUNDLE_UNKNOWN],ecx
    ret
