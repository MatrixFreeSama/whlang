# Wheelchair tensor frontend common bodies.
# Compile-time single authority; wrappers retain only semantic entry labels.

.macro TFC_tensor_prepare_code_arenas
    mov rdi,qword ptr [rip+tensor_code_arena_ptr]
    test rdi,rdi
    jz .tpca_size
    mov rsi,qword ptr [rip+tensor_code_arena_bytes]
    mov eax,SYS_munmap
    syscall
    mov qword ptr [rip+tensor_code_arena_ptr],0
    mov qword ptr [rip+tensor_code_arena_bytes],0
.tpca_size:
    mov rax,qword ptr [rip+source_length]
    mov rcx,qword ptr [rip+tensor_code_growth_factor]
    mul rcx
    test rdx,rdx
    jnz .tpca_fail
    cmp rax,65536
    jae .tpca_round
    mov eax,65536
.tpca_round:
    add rax,4095
    jc .tpca_fail
    and rax,-4096
    mov r8,rax                       # bytes per staging lane
    mov rsi,rax
    shl rsi,1
    jc .tpca_fail
    mov rdi,rsi
    add rsi,rax                      # three code lanes
    jc .tpca_fail
    add rsi,rsi                      # plus three metadata lanes = six total
    jc .tpca_fail
    push r8                           # lane bytes
    push rsi                          # total bytes
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    pop rsi
    pop rcx                           # lane bytes
    test rax,rax
    js .tpca_fail
    mov qword ptr [rip+tensor_code_arena_ptr],rax
    mov qword ptr [rip+tensor_code_arena_bytes],rsi
    mov qword ptr [rip+tensor_code_lane_bytes],rcx
    mov qword ptr [rip+tensor_eval_base],rax
    lea rsi,[rax+rcx]
    mov qword ptr [rip+tensor_vec_base],rsi
    lea rdi,[rsi+rcx]
    mov qword ptr [rip+tensor_vec_init_base],rdi
    # Fixup metadata is derived from the same actual code arena.  A fixup must
    # own at least one disp32 in generated code, so lane_bytes/4 is a structural
    # upper bound rather than an independent capability constant.
    lea rdx,[rdi+rcx]                # base + 3*lane
    mov qword ptr [rip+tensor_fixup_ptr_base],rdx
    lea rdx,[rdx+rcx*2]              # base + 5*lane
    mov qword ptr [rip+tensor_fixup_const_base],rdx
    mov rdx,rcx
    shr rdx,2
    mov dword ptr [rip+tensor_fixup_capacity],edx
    mov qword ptr [rip+emit_ptr],rax
    lea rsi,[rax+rcx]
    mov qword ptr [rip+emit_end],rsi
    mov qword ptr [rip+vec_emit_ptr],rsi
    lea rax,[rsi+rcx]
    mov qword ptr [rip+vec_emit_end],rax
    mov qword ptr [rip+vec_init_emit_ptr],rax
    lea rax,[rax+rcx]
    mov qword ptr [rip+vec_init_emit_end],rax
    xor eax,eax
    ret
.tpca_fail:
    mov eax,1
    ret

# 1.3.56 optimizer-metadata aging.  Constant interning and affine-linear facts
# are compile-time properties of the parsed tensor graph.  Their storage is
# instance-sized from the actual JSON node population; no constant/linear fact
# count is allowed to become a language capability ceiling.
.endm

.macro TFC_json_skip_ws
    mov rax,[rip+jcur]
    mov rcx,[rip+jend]
.jsw:
    cmp rax,rcx
    jae .jsw_done
    mov dl,byte ptr [rax]
    cmp dl,' '
    je .jsw_inc
    cmp dl,9
    je .jsw_inc
    cmp dl,10
    je .jsw_inc
    cmp dl,13
    je .jsw_inc
    jmp .jsw_done
.jsw_inc:
    inc rax
    jmp .jsw
.jsw_done:
    mov [rip+jcur],rax
    ret

# Build a parser arena from the actual source span.  A JSON node consumes at
# least one source byte, so source_length is a structural upper bound on node
# count.  This removes the historical 65,536-node language ceiling without
# inventing a second allocator policy.
.endm

.macro TFC_json_prepare_arena
    mov rdi,[rip+json_nodes_ptr]
    test rdi,rdi
    jz .jpa_allocate
    mov rsi,[rip+json_nodes_bytes]
    mov eax,SYS_munmap
    syscall
    mov qword ptr [rip+json_nodes_ptr],0
.jpa_allocate:
    mov rax,[rip+source_length]
    test rax,rax
    jz .jpa_fail
    mov [rip+json_node_capacity],rax
    mov rcx,rax
    shr rcx,58
    jnz .jpa_fail
    shl rax,6
    mov [rip+json_nodes_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .jpa_fail
    mov [rip+json_nodes_ptr],rax
    xor eax,eax
    ret
.jpa_fail:
    mov eax,1
    ret

.endm

.macro TFC_new_node
    mov rax,[rip+json_node_count]
    cmp rax,[rip+json_node_capacity]
    jae .nn_fail
    mov rcx,rax
    shl rcx,6
    mov rax,[rip+json_nodes_ptr]
    add rax,rcx
    inc qword ptr [rip+json_node_count]
    # clear 64 bytes
    pxor xmm0,xmm0
    movdqu [rax],xmm0
    movdqu [rax+16],xmm0
    movdqu [rax+32],xmm0
    movdqu [rax+48],xmm0
    ret
.nn_fail:
    xor eax,eax
    ret

# parse raw JSON string at jcur; returns rax=content ptr, rcx=len, jcur after quote.
.endm

.macro TFC_json_parse_value
    push rbx
    push r12
    push r13
    call json_skip_ws
    mov rbx,[rip+jcur]
    cmp rbx,[rip+jend]
    jae .jpv_fail
    mov al,byte ptr [rbx]
    cmp al,'{'
    je .jpv_obj
    cmp al,'['
    je .jpv_arr
    cmp al,'"'
    je .jpv_str
    cmp al,'-'
    je .jpv_num
    cmp al,'0'
    jb .jpv_kw
    cmp al,'9'
    jbe .jpv_num
.jpv_kw:
    lea rsi,[rip+lit_true]
    mov edx,4
    mov rdi,rbx
    call bytes_eq_n
    test eax,eax
    jnz .jpv_true
    lea rsi,[rip+lit_false]
    mov edx,5
    mov rdi,rbx
    call bytes_eq_n
    test eax,eax
    jnz .jpv_false
    lea rsi,[rip+lit_null]
    mov edx,4
    mov rdi,rbx
    call bytes_eq_n
    test eax,eax
    jnz .jpv_null
    jmp .jpv_fail
.jpv_true:
    add qword ptr [rip+jcur],4
    call new_node
    test rax,rax
    jz .jpv_fail
    mov qword ptr [rax],J_TRUE
    jmp .jpv_done
.jpv_false:
    add qword ptr [rip+jcur],5
    call new_node
    test rax,rax
    jz .jpv_fail
    mov qword ptr [rax],J_FALSE
    jmp .jpv_done
.jpv_null:
    add qword ptr [rip+jcur],4
    call new_node
    test rax,rax
    jz .jpv_fail
    mov qword ptr [rax],J_NULL
    jmp .jpv_done
.jpv_str:
    call json_parse_string_raw
    test rax,rax
    jz .jpv_fail
    mov r12,rax
    mov r13,rcx
    call new_node
    test rax,rax
    jz .jpv_fail
    mov qword ptr [rax],J_STRING
    mov [rax+8],r12
    mov [rax+16],r13
    jmp .jpv_done
.jpv_num:
    mov r12,rbx
    mov r13,rbx
    cmp byte ptr [r13],'-'
    jne .jpn_digits
    inc r13
.jpn_digits:
    cmp r13,[rip+jend]
    jae .jpv_fail
    xor ecx,ecx
.jpn_dloop:
    cmp r13,[rip+jend]
    jae .jpn_frac
    mov dl,byte ptr [r13]
    cmp dl,'0'
    jb .jpn_frac
    cmp dl,'9'
    ja .jpn_frac
    inc r13
    inc ecx
    jmp .jpn_dloop
.jpn_frac:
    test ecx,ecx
    jz .jpv_fail
    cmp r13,[rip+jend]
    jae .jpn_end
    cmp byte ptr [r13],'.'
    jne .jpn_exp
    inc r13
    xor ecx,ecx
.jpn_floop:
    cmp r13,[rip+jend]
    jae .jpn_end
    mov dl,byte ptr [r13]
    cmp dl,'0'
    jb .jpn_fdone
    cmp dl,'9'
    ja .jpn_fdone
    inc r13
    inc ecx
    jmp .jpn_floop
.jpn_fdone:
    test ecx,ecx
    jz .jpv_fail
.jpn_exp:
    cmp r13,[rip+jend]
    jae .jpn_end
    mov dl,byte ptr [r13]
    cmp dl,'e'
    je .jpn_expgo
    cmp dl,'E'
    jne .jpn_end
.jpn_expgo:
    inc r13
    cmp r13,[rip+jend]
    jae .jpv_fail
    mov dl,byte ptr [r13]
    cmp dl,'+'
    je .jpn_expsign
    cmp dl,'-'
    jne .jpn_expdigits
.jpn_expsign:
    inc r13
.jpn_expdigits:
    xor ecx,ecx
.jpn_eloop:
    cmp r13,[rip+jend]
    jae .jpn_edone
    mov dl,byte ptr [r13]
    cmp dl,'0'
    jb .jpn_edone
    cmp dl,'9'
    ja .jpn_edone
    inc r13
    inc ecx
    jmp .jpn_eloop
.jpn_edone:
    test ecx,ecx
    jz .jpv_fail
.jpn_end:
    mov [rip+jcur],r13
    call new_node
    test rax,rax
    jz .jpv_fail
    mov qword ptr [rax],J_NUMBER
    mov [rax+8],r12
    mov rcx,r13
    sub rcx,r12
    mov [rax+16],rcx
    jmp .jpv_done
.jpv_obj:
    inc qword ptr [rip+jcur]
    call new_node
    test rax,rax
    jz .jpv_fail
    mov qword ptr [rax],J_OBJECT
    mov r12,rax
    xor r13d,r13d                  # last child pointer
.jpo_loop:
    call json_skip_ws
    mov rbx,[rip+jcur]
    cmp rbx,[rip+jend]
    jae .jpv_fail
    cmp byte ptr [rbx],'}'
    je .jpo_close
    call json_parse_string_raw
    test rax,rax
    jz .jpv_fail
    push rax
    push rcx
    call json_skip_ws
    mov rbx,[rip+jcur]
    cmp rbx,[rip+jend]
    jae .jpo_stackfail
    cmp byte ptr [rbx],':'
    jne .jpo_stackfail
    inc qword ptr [rip+jcur]
    call json_parse_value
    test rax,rax
    jz .jpo_stackfail
    pop rcx
    pop rbx
    mov [rax+40],rbx
    mov [rax+48],rcx
    test r13,r13
    jnz .jpo_link
    mov [r12+24],rax
    jmp .jpo_linked
.jpo_link:
    mov [r13+32],rax
.jpo_linked:
    mov r13,rax
    call json_skip_ws
    mov rbx,[rip+jcur]
    cmp rbx,[rip+jend]
    jae .jpv_fail
    cmp byte ptr [rbx],','
    je .jpo_comma
    cmp byte ptr [rbx],'}'
    je .jpo_close
    jmp .jpv_fail
.jpo_comma:
    inc qword ptr [rip+jcur]
    jmp .jpo_loop
.jpo_close:
    inc qword ptr [rip+jcur]
    mov rax,r12
    jmp .jpv_done
.jpo_stackfail:
    add rsp,16
    jmp .jpv_fail
.jpv_arr:
    inc qword ptr [rip+jcur]
    call new_node
    test rax,rax
    jz .jpv_fail
    mov qword ptr [rax],J_ARRAY
    mov r12,rax
    xor r13d,r13d
.jpa_loop:
    call json_skip_ws
    mov rbx,[rip+jcur]
    cmp rbx,[rip+jend]
    jae .jpv_fail
    cmp byte ptr [rbx],']'
    je .jpa_close
    call json_parse_value
    test rax,rax
    jz .jpv_fail
    test r13,r13
    jnz .jpa_link
    mov [r12+24],rax
    jmp .jpa_linked
.jpa_link:
    mov [r13+32],rax
.jpa_linked:
    mov r13,rax
    call json_skip_ws
    mov rbx,[rip+jcur]
    cmp rbx,[rip+jend]
    jae .jpv_fail
    cmp byte ptr [rbx],','
    je .jpa_comma
    cmp byte ptr [rbx],']'
    je .jpa_close
    jmp .jpv_fail
.jpa_comma:
    inc qword ptr [rip+jcur]
    jmp .jpa_loop
.jpa_close:
    inc qword ptr [rip+jcur]
    mov rax,r12
    jmp .jpv_done
.jpv_fail:
    mov dword ptr [rip+tensor_error],1
    xor eax,eax
.jpv_done:
    pop r13
    pop r12
    pop rbx
    ret

# bytes_eq_n(rdi=a,rsi=b,edx=n), assumes source bounds already checked enough for keywords.
.endm

.macro TFC_bytes_eq_n
    xor ecx,ecx
.ben:
    cmp ecx,edx
    je .beyes
    mov al,[rdi+rcx]
    cmp al,[rsi+rcx]
    jne .beno
    inc ecx
    jmp .ben
.beyes: mov eax,1; ret
.beno: xor eax,eax; ret

# span_eq(rdi=ptr,rsi=len,rdx=const,ecx=const_len)
.endm

.macro TFC_span_eq
    # Shared frontends may retain source pointers in r8 across string probes.
    # Treat r8 as caller state rather than an undocumented scratch register.
    push r8
    cmp rsi,rcx
    jne .seq_no
    xor r8d,r8d
.seq_loop:
    cmp r8,rcx
    jae .seq_yes
    mov al,[rdi+r8]
    cmp al,[rdx+r8]
    jne .seq_no
    inc r8
    jmp .seq_loop
.seq_yes:
    mov eax,1
    pop r8
    ret
.seq_no:
    xor eax,eax
    pop r8
    ret

# obj_get(rdi=obj,rsi=key,edx=len) -> rax child/0
.endm

.macro TFC_obj_get
    mov r8,[rdi+24]
.og_loop:
    test r8,r8
    jz .og_no
    cmp [r8+48],rdx
    jne .og_next
    xor ecx,ecx
.og_cmp:
    cmp ecx,edx
    je .og_yes
    mov r9,[r8+40]
    mov al,[r9+rcx]
    cmp al,[rsi+rcx]
    jne .og_next
    inc ecx
    jmp .og_cmp
.og_yes:
    mov rax,r8
    ret
.og_next:
    mov r8,[r8+32]
    jmp .og_loop
.og_no:
    xor eax,eax
    ret

# node_parse_u64(rax=node) -> rax value, edx error
.endm

.macro TFC_node_parse_u64
    test rax,rax
    jz .npu_bad
    cmp qword ptr [rax],J_NUMBER
    jne .npu_bad
    mov rdi,[rax+8]
    mov rcx,[rax+16]
    xor eax,eax
    xor edx,edx
    test rcx,rcx
    jz .npu_bad
.npu_loop:
    movzx r8d,byte ptr [rdi]
    cmp r8b,'0'
    jb .npu_bad
    cmp r8b,'9'
    ja .npu_bad
    imul rax,rax,10
    sub r8d,'0'
    add rax,r8
    inc rdi
    dec rcx
    jnz .npu_loop
    xor edx,edx
    ret
.npu_bad:
    xor eax,eax
    mov edx,1
    ret

# Convert unsigned u64 RAX to f64 in XMM0 without signed reinterpretation.
# For values with bit63 set, halve into the signed-positive range, round the
# dropped low bit upward into the half-value, convert, then double. This is the
# standard exact-range unsigned conversion pattern used by native compilers.
.endm

.macro TFC_find_binding
    xor ecx,ecx
.fb_loop:
    cmp ecx,dword ptr [rip+tensor_binding_count]
    jae .fb_no
    mov eax,ecx
    shl rax,6
    mov r8,[rip+tensor_bindings_ptr]
    add r8,rax
    cmp [r8+8],rsi
    jne .fb_next
    xor r9d,r9d
.fb_cmp:
    cmp r9,rsi
    jae .fb_yes
    mov r10,[r8]
    mov al,[r10+r9]
    cmp al,[rdi+r9]
    jne .fb_next
    inc r9
    jmp .fb_cmp
.fb_yes:
    mov rax,r8
    ret
.fb_next:
    inc ecx
    jmp .fb_loop
.fb_no:
    xor eax,eax
    ret

# ---------------- 1.3.7 Tensor Physical Reality use graph ----------------
# tensor_analyze_expr(rdi=expr)
# Compile-time only. Each binding definition is recursively expanded at most
# once, while every structural load edge increments the target binding use
# count. This approximates the physical DAG after binding-level CSE rather than
# multiplying leaf counts merely because a parent map is referenced twice.
.endm

.macro TFC_alloc_gpr
    mov eax,dword ptr [rip+emit_gpr_mask]
    test eax,eax
    jz .ag_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+emit_gpr_mask],eax
    mov eax,ecx
    ret
.ag_fail:
    mov eax,-1
    ret
.endm

.macro TFC_alloc_xmm
    mov eax,dword ptr [rip+emit_xmm_mask]
    test eax,eax
    jz .ax_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+emit_xmm_mask],eax
    mov eax,ecx
    ret
.ax_fail:
    mov eax,-1
    ret
.endm

.macro TFC_gen_mov_ri64
    push rbx
    mov ebx,edi
    mov eax,ebx
    shr eax,3
    and eax,1
    or eax,0x48
    mov edi,eax
    call emit_u8
    mov eax,ebx
    and eax,7
    add eax,0xB8
    mov edi,eax
    call emit_u8
    mov rax,[rip+emit_ptr]
    lea rcx,[rax+8]
    cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_1
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .gmri_fail
.tcgrow_ok_1:
    mov [rax],rsi
    mov [rip+emit_ptr],rcx
    xor eax,eax
    pop rbx
    ret
.gmri_fail:
    mov eax,1
    pop rbx
    ret

# gen_rr_opcode(edi=opcode, esi=dst_rm, edx=src_reg)
.endm

.macro TFC_gen_rr_opcode
    push rbx
    mov ebx,edi
    mov eax,edx
    shr eax,3
    and eax,1
    shl eax,2
    mov ecx,esi
    shr ecx,3
    and ecx,1
    or eax,ecx
    or eax,0x48
    mov edi,eax
    call emit_u8
    mov edi,ebx
    call emit_u8
    mov eax,edx
    and eax,7
    shl eax,3
    mov ecx,esi
    and ecx,7
    or eax,ecx
    or eax,0xC0
    mov edi,eax
    call emit_u8
    pop rbx
    ret

# gen_mov_rr(edi=dst,esi=src)
.endm

.macro TFC_gen_mov_rr
    mov edx,esi
    mov esi,edi
    mov edi,0x89
    jmp gen_rr_opcode

# gen_alu_ri32(edi=extension, esi=dst, edx=imm32)
.endm

.macro TFC_gen_alu_ri32
    push rbx
    push r12
    mov ebx,edi
    mov r12d,edx
    mov eax,esi
    shr eax,3
    and eax,1
    or eax,0x48
    mov edi,eax
    call emit_u8
    mov edi,0x81
    call emit_u8
    mov eax,ebx
    and eax,7
    shl eax,3
    mov ecx,esi
    and ecx,7
    or eax,ecx
    or eax,0xC0
    mov edi,eax
    call emit_u8
    mov rax,[rip+emit_ptr]
    lea rcx,[rax+4]
    cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_2
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .gari_fail
.tcgrow_ok_2:
    mov [rax],r12d
    mov [rip+emit_ptr],rcx
    xor eax,eax
    pop r12
    pop rbx
    ret
.gari_fail:
    mov eax,1
    pop r12
    pop rbx
    ret

# gen_imul_rr(edi=dst,esi=src)
.endm

.macro TFC_gen_imul_rr
    push rbx
    mov ebx,edi
    mov eax,ebx
    shr eax,3
    and eax,1
    shl eax,2
    mov ecx,esi
    shr ecx,3
    and ecx,1
    or eax,ecx
    or eax,0x48
    mov edi,eax
    call emit_u8
    mov edi,0x0F
    call emit_u8
    mov edi,0xAF
    call emit_u8
    mov eax,ebx
    and eax,7
    shl eax,3
    mov ecx,esi
    and ecx,7
    or eax,ecx
    or eax,0xC0
    mov edi,eax
    call emit_u8
    pop rbx
    ret

# gen_imul_ri32(edi=dst, esi=src, edx=imm32)
.endm

.macro TFC_gen_imul_ri32
    push rbx
    push r12
    mov ebx,edi
    mov r12d,edx
    mov eax,ebx
    shr eax,3
    and eax,1
    shl eax,2
    mov ecx,esi
    shr ecx,3
    and ecx,1
    or eax,ecx
    or eax,0x48
    mov edi,eax
    call emit_u8
    mov edi,0x69
    call emit_u8
    mov eax,ebx
    and eax,7
    shl eax,3
    mov ecx,esi
    and ecx,7
    or eax,ecx
    or eax,0xC0
    mov edi,eax
    call emit_u8
    mov rax,[rip+emit_ptr]
    lea rcx,[rax+4]
    cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_3
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .gimri_fail
.tcgrow_ok_3:
    mov [rax],r12d
    mov [rip+emit_ptr],rcx
    xor eax,eax
    pop r12
    pop rbx
    ret
.gimri_fail:
    mov eax,1
    pop r12
    pop rbx
    ret

# gen_div_reg(edi=divisor)
.endm

.macro TFC_gen_div_reg
    mov eax,edi
    shr eax,3
    and eax,1
    or eax,0x48
    push rdi
    mov edi,eax
    call emit_u8
    mov edi,0xF7
    call emit_u8
    pop rax
    and eax,7
    or eax,0xF0                    # mod=3, /6
    mov edi,eax
    jmp emit_u8

# gen_cvtsi2sd(edi=xmm, esi=gpr)
.endm

.macro TFC_gen_cvtsi2sd
    push rbx
    mov ebx,edi
    mov edi,0xF2
    call emit_u8
    mov eax,ebx
    shr eax,3
    and eax,1
    shl eax,2
    mov ecx,esi
    shr ecx,3
    and ecx,1
    or eax,ecx
    or eax,0x48
    mov edi,eax
    call emit_u8
    mov edi,0x0F; call emit_u8
    mov edi,0x2A; call emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,esi; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call emit_u8
    pop rbx
    ret

# gen_movq_xmm_gpr(edi=xmm, esi=gpr)
.endm

.macro TFC_gen_movq_xmm_gpr
    push rbx
    mov ebx,edi
    mov edi,0x66; call emit_u8
    mov eax,ebx; shr eax,3; and eax,1; shl eax,2
    mov ecx,esi; shr ecx,3; and ecx,1; or eax,ecx; or eax,0x48
    mov edi,eax; call emit_u8
    mov edi,0x0F; call emit_u8
    mov edi,0x6E; call emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,esi; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call emit_u8
    pop rbx
    ret

# gen_sse_rr(edi=opcode 58/5c/59/5e, esi=dst_xmm, edx=src_xmm)
.endm

.macro TFC_gen_sse_rr
    push rbx
    mov ebx,edi
    mov edi,0xF2; call emit_u8
    mov eax,esi; shr eax,3; and eax,1; shl eax,2
    mov ecx,edx; shr ecx,3; and ecx,1; or eax,ecx
    test eax,eax
    jz .gsse_norex
    or eax,0x40
    mov edi,eax; call emit_u8
.gsse_norex:
    mov edi,0x0F; call emit_u8
    mov edi,ebx; call emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov ecx,edx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call emit_u8
    pop rbx
    ret

# gen_cmp_setcc(edi=dst, esi=lhs, edx=rhs, ecx=setcc opcode)
# PredicateFact is represented as canonical 0/1 only when a value consumer
# requires it.  Integer relation choice is data, not a separate emitter family.
.endm

.macro TFC_gen_cmp_setcc
    push rbx
    push r12
    mov ebx,edi
    mov r12d,ecx
    mov edi,0x39
    call gen_rr_opcode
    mov edi,0x0F; call emit_u8
    mov edi,r12d; call emit_u8
    mov edi,0xC0; call emit_u8
    mov eax,ebx; shr eax,3; and eax,1; shl eax,2
    test eax,eax
    jz .gcsc_no_rex
    or eax,0x40
    mov edi,eax; call emit_u8
.gcsc_no_rex:
    mov edi,0x0F; call emit_u8
    mov edi,0xB6; call emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call emit_u8
    pop r12
    pop rbx
    ret

# gen_ucomisd_setcc(edi=dst_gpr, esi=lhs_xmm, edx=rhs_xmm, ecx=setcc opcode)
# This is the scalar realization of the same PredicateFact relation used by the
# vector emitter.  No scalar-only semantic branch is introduced.
.endm

.macro TFC_gen_ucomisd_setcc
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,ecx
    mov r13d,esi
    mov edi,0x66; call emit_u8
    mov eax,r13d; shr eax,3; and eax,1; shl eax,2
    mov ecx,edx; shr ecx,3; and ecx,1; or eax,ecx
    test eax,eax
    jz .gusc_no_rex
    or eax,0x40
    mov edi,eax; call emit_u8
.gusc_no_rex:
    mov edi,0x0F; call emit_u8
    mov edi,0x2E; call emit_u8
    mov eax,r13d; and eax,7; shl eax,3
    mov ecx,edx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call emit_u8
    mov edi,0x0F; call emit_u8
    mov edi,r12d; call emit_u8
    mov edi,0xC0; call emit_u8
    mov eax,ebx; shr eax,3; and eax,1; shl eax,2
    test eax,eax
    jz .gusc_movzx_no_rex
    or eax,0x40
    mov edi,eax; call emit_u8
.gusc_movzx_no_rex:
    mov edi,0x0F; call emit_u8
    mov edi,0xB6; call emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call emit_u8
    pop r13
    pop r12
    pop rbx
    ret

# gen_neg_gpr(edi=reg): two's-complement negation.  For a canonical bool this
# maps 0/1 to an all-zero/all-one bit mask without creating a new fact kind.
.endm

.macro TFC_gen_neg_gpr
    push rbx
    mov ebx,edi
    mov eax,ebx; shr eax,3; and eax,1
    or eax,0x48
    mov edi,eax; call emit_u8
    mov edi,0xF7; call emit_u8
    mov eax,ebx; and eax,7; or eax,0xD8
    mov edi,eax; call emit_u8
    pop rbx
    ret

# gen_sse66_rr(edi=opcode, esi=dst_xmm, edx=src_xmm)
# Shared exact-bit relation used to realize a floating select from a PredicateFact.
.endm

.macro TFC_gen_sse66_rr
    push rbx
    mov ebx,edi
    mov edi,0x66; call emit_u8
    mov eax,esi; shr eax,3; and eax,1; shl eax,2
    mov ecx,edx; shr ecx,3; and ecx,1; or eax,ecx
    test eax,eax
    jz .gs66_no_rex
    or eax,0x40
    mov edi,eax; call emit_u8
.gs66_no_rex:
    mov edi,0x0F; call emit_u8
    mov edi,ebx; call emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov ecx,edx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call emit_u8
    pop rbx
    ret

# gen_test_rr(edi=reg): test reg,reg
.endm

.macro TFC_gen_test_rr
    mov edx,edi
    mov esi,edi
    mov edi,0x85
    jmp gen_rr_opcode

# gen_cmovz(edi=dst,esi=src)
.endm

.macro TFC_gen_cmovz
    push rbx
    mov ebx,edi
    mov eax,ebx; shr eax,3; and eax,1; shl eax,2
    mov ecx,esi; shr ecx,3; and ecx,1; or eax,ecx; or eax,0x48
    mov edi,eax; call emit_u8
    mov edi,0x0F; call emit_u8
    mov edi,0x44; call emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,esi; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call emit_u8
    pop rbx
    ret

# obj literal u64 helper: rdi=expr object -> rax=value, edx=0 if typed u64 literal else 1
.endm

.macro TFC_expr_literal_u64
    push rbx
    push r12
    push r13
    push r14
    mov r12,rdi
    # Direct typed literal first.
    lea rsi,[rip+k_literal]; mov edx,k_literal_end-k_literal; call obj_get
    test rax,rax; jz .elu_fold
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+k_type]; mov edx,k_type_end-k_type; call obj_get
    test rax,rax; jz .elu_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_u64]; mov ecx,v_u64_end-v_u64; call span_eq
    test eax,eax; jz .elu_no
    mov rax,r13
    call node_parse_u64
    jmp .elu_done
.elu_fold:
    # Generic compile-time folding for binary u64 add/sub/mul/mod.  This is
    # workload-agnostic and removes static topology arithmetic before either
    # scalar or AVX-512 register allocation sees it.
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .elu_no
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .elu_no
    cmp qword ptr [rax],J_ARRAY; jne .elu_no
    mov r14,[rax+24]; test r14,r14; jz .elu_no
    mov rbx,[r14+32]; test rbx,rbx; jz .elu_no
    cmp qword ptr [rbx+32],0; jne .elu_no
    mov rdi,r14; call expr_literal_u64
    test edx,edx; jnz .elu_no
    push rax
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .elu_pop_no
    mov rbx,rax
    pop rax
    # Re-load lhs because the string comparisons below return booleans in eax.
    mov rdi,r14; call expr_literal_u64
    test edx,edx; jnz .elu_no
    mov r12,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz .elu_chk_sub
    mov rax,r12; add rax,rbx; jc .elu_no
    xor edx,edx; jmp .elu_done
.elu_chk_sub:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz .elu_chk_mul
    cmp r12,rbx; jb .elu_no
    mov rax,r12; sub rax,rbx
    xor edx,edx; jmp .elu_done
.elu_chk_mul:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz .elu_chk_mod
    mov rax,r12; mul rbx
    test rdx,rdx; jnz .elu_no
    xor edx,edx; jmp .elu_done
.elu_chk_mod:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .elu_no
    test rbx,rbx; jz .elu_no
    mov rax,r12; xor edx,edx; div rbx; mov rax,rdx
    xor edx,edx; jmp .elu_done
.elu_pop_no:
    add rsp,8
.elu_no:
    xor eax,eax
    mov edx,1
.elu_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# expr_literal_f64_bits(rdi=expr object) -> rax=bits, edx=0 success
.endm

.macro TFC_expr_literal_f64_bits
    push rbx
    mov rbx,rdi
    lea rsi,[rip+k_literal]; mov edx,k_literal_end-k_literal; call obj_get
    test rax,rax; jz .elf_no
    push rax
    mov rdi,rbx; lea rsi,[rip+k_type]; mov edx,k_type_end-k_type; call obj_get
    test rax,rax; jz .elf_pop_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_f64]; mov ecx,v_f64_end-v_f64; call span_eq
    test eax,eax; jz .elf_pop_no
    pop rax
    call node_parse_f64_bits
    pop rbx
    ret
.elf_pop_no:
    add rsp,8
.elf_no:
    xor eax,eax
    mov edx,1
    pop rbx
    ret

# expr_is_float_value(rdi=expr) -> eax=1 when the structured expression
# denotes an f64 ValueFact, else 0.  This is semantic type closure, not a
# workload route: map values are f64 and arithmetic/select preserve that type.
.endm

.macro TFC_expr_is_float_value
    push rbx
    push r12
    mov rbx,rdi
    mov rdi,rbx
    call expr_literal_f64_bits
    test edx,edx
    jz .eifv_yes
    mov rdi,rbx; lea rsi,[rip+k_load]; mov edx,k_load_end-k_load; call obj_get
    test rax,rax
    jz .eifv_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call find_binding
    test rax,rax
    jz .eifv_no
    cmp dword ptr [rax+20],TYPE_F64
    je .eifv_yes
    jmp .eifv_no
.eifv_op:
    mov rdi,rbx; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax
    jz .eifv_no
    mov r12,rax
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_cast]; mov ecx,v_cast_end-v_cast; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_square]; mov ecx,v_square_end-v_square; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_trunc]; mov ecx,v_trunc_end-v_trunc; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jnz .eifv_yes
    mov rdi,[r12+8]; mov rsi,[r12+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jnz .eifv_yes
.eifv_no:
    xor eax,eax
    jmp .eifv_done
.eifv_yes:
    mov eax,1
.eifv_done:
    pop r12
    pop rbx
    ret

# match mul(f64_literal, expr) or mul(expr, f64_literal).
# rdi=expr -> rax=literal bits, rdx=other expr, ecx=1 success; ecx=0 otherwise.
.endm

.macro TFC_expr_mul_literal_other
    push rbx
    push r12
    push r13
    mov r12,rdi
    cmp qword ptr [r12],J_OBJECT
    jne .emlo_no
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .emlo_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz .emlo_no
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .emlo_no
    mov r12,[rax+24]; test r12,r12; jz .emlo_no
    mov r13,[r12+32]; test r13,r13; jz .emlo_no
    cmp qword ptr [r13+32],0; jne .emlo_no
    mov rdi,r12; call expr_literal_f64_bits
    test edx,edx; jnz .emlo_rhs
    mov rdx,r13; mov ecx,1; jmp .emlo_done
.emlo_rhs:
    mov rdi,r13; call expr_literal_f64_bits
    test edx,edx; jnz .emlo_no
    mov rdx,r12; mov ecx,1; jmp .emlo_done
.emlo_no:
    xor eax,eax; xor edx,edx; xor ecx,ecx
.emlo_done:
    pop r13; pop r12; pop rbx; ret

# recip_pow2_f64_bits(rax=positive f64 bits) -> rax=reciprocal bits, edx=0; else edx=1
.endm

.macro TFC_recip_pow2_f64_bits
    mov rcx,rax
    mov rdx,0x800fffffffffffff
    test rcx,rdx                  # sign or mantissa must be zero
    jnz .rpf_no
    mov rdx,rcx
    shr rdx,52
    and edx,0x7ff
    test edx,edx
    jz .rpf_no
    cmp edx,0x7ff
    je .rpf_no
    mov ecx,2046
    sub ecx,edx
    cmp ecx,1
    jb .rpf_no
    cmp ecx,2046
    ja .rpf_no
    mov rax,rcx
    shl rax,52
    xor edx,edx
    ret
.rpf_no:
    xor eax,eax
    mov edx,1
    ret

# tolerant_recip_f64_bits(rax=f64 bits) -> rounded normal binary64 reciprocal bits.
# Reject zero, NaN, infinity and subnormal results. Used only when tensor_tolerant_fp is set.
.endm

.macro TFC_gen_load_f64_bits
    push rbx
    mov ebx,edi
    xor edi,edi
    call gen_mov_ri64
    mov edi,ebx
    xor esi,esi
    call gen_movq_xmm_gpr
    pop rbx
    ret

# emit_int_reg(rdi=expr object, esi=dst gpr) -> eax=0/1
.endm

.macro TFC_emit_float_reg
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13d,esi
    # literal f64?
    mov rdi,r12; lea rsi,[rip+k_literal]; mov edx,k_literal_end-k_literal; call obj_get
    test rax,rax; jz .efr_load
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+k_type]; mov edx,k_type_end-k_type; call obj_get
    test rax,rax; jz .efr_fail
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_f64]; mov ecx,v_f64_end-v_f64; call span_eq
    test eax,eax; jz .efr_fail
    mov rax,r14; call node_parse_f64_bits; test edx,edx; jnz .efr_fail
    mov rsi,rax; mov edi,r13d; call gen_load_f64_bits
    xor eax,eax; jmp .efr_done
.efr_load:
    mov rdi,r12; lea rsi,[rip+k_load]; mov edx,k_load_end-k_load; call obj_get
    test rax,rax; jz .efr_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call find_binding
    test rax,rax; jz .efr_fail
    mov r14,rax
    cmp dword ptr [r14+16],OP_MAP; jne .efr_fail
    mov rdi,r12; lea rsi,[rip+k_indices]; mov edx,k_indices_end-k_indices; call obj_get
    test rax,rax; jz .efr_fail
    mov r15,[rax+24]; test r15,r15; jz .efr_fail
    call alloc_gpr; cmp eax,-1; je .efr_fail; mov r12d,eax      # index
    mov rdi,r15; mov esi,r12d; call emit_int_reg; test eax,eax; jnz .efr_free_index_fail
    # Axis-save is a structural load-frame, not an expression temporary.  Use
    # the machine stack so nested map fusion does not consume the finite GPR pool.
    mov edi,0x5041                  # push r8
    call emit_u16
    mov edi,8; mov esi,r12d; call gen_mov_rr
    mov edi,r12d; call free_gpr
    mov r12d,-1
    mov rdi,[r14+40]; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_restore_axis_stack_fail
    mov edi,0x5841                  # pop r8
    call emit_u16
    xor eax,eax; jmp .efr_done
.efr_restore_axis_stack_fail:
    mov edi,0x5841; call emit_u16
    jmp .efr_fail
.efr_free_index_fail:
    mov edi,r12d; call free_gpr
    jmp .efr_fail
.efr_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .efr_fail
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .efr_fail
    mov r15,[rax+24]; test r15,r15; jz .efr_fail
    # cast
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_cast]; mov ecx,v_cast_end-v_cast; call span_eq
    test eax,eax; jz .efr_sqrt_probe
    call alloc_gpr; cmp eax,-1; je .efr_fail; mov ebx,eax
    mov rdi,r15; mov esi,ebx; call emit_int_reg; test eax,eax; jnz .efr_free_b_fail
    mov edi,r13d; mov esi,ebx; call gen_cvtsi2sd
    mov edi,ebx; call free_gpr
    inc dword ptr [rip+schedule_counts+4*3] # fp convert
    xor eax,eax; jmp .efr_done
.efr_sqrt_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax; jz .efr_square_probe
    cmp qword ptr [r15+32],0; jne .efr_fail
    mov rdi,r15; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_fail
    mov edi,0x51; mov esi,r13d; mov edx,r13d; call gen_sse_rr
    # The current resource vocabulary has no false "math unit".  Until target
    # profiles expose a distinct sqrt fact, charge its long-latency pipe to the
    # existing FP-div/special slot rather than creating a second scheduler.
    inc dword ptr [rip+schedule_counts+8]
    xor eax,eax; jmp .efr_done
.efr_square_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_square]; mov ecx,v_square_end-v_square; call span_eq
    test eax,eax; jz .efr_trunc_probe
    cmp qword ptr [r15+32],0; jne .efr_fail
    mov rdi,r15; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_fail
    mov edi,0x59; mov esi,r13d; mov edx,r13d; call gen_sse_rr
    inc dword ptr [rip+schedule_counts+4]
    xor eax,eax; jmp .efr_done
.efr_trunc_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_trunc]; mov ecx,v_trunc_end-v_trunc; call span_eq
    test eax,eax; jz .efr_select_probe
    cmp qword ptr [r15+32],0; jne .efr_fail
    mov rdi,r15; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_fail
    mov edi,r13d; mov esi,r13d; call vec_roundpd_trunc_scalar_reg
    test eax,eax; jnz .efr_fail
    inc dword ptr [rip+schedule_counts+4*3]
    xor eax,eax; jmp .efr_done
.efr_select_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .efr_binary
    # select(P,T,F) is one typed ValueFact relation.  The scalar realization
    # uses the same canonical predicate value as the vector path, then blends
    # the exact f64 bit patterns without changing rounding.
    call alloc_gpr; cmp eax,-1; je .efr_fail; mov ebx,eax
    mov rdi,r15; mov esi,ebx; call emit_int_reg; test eax,eax; jnz .efr_select_free_cond_fail
    mov r15,[r15+32]; test r15,r15; jz .efr_select_free_cond_fail
    mov rdi,r15; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_select_free_cond_fail
    mov r15,[r15+32]; test r15,r15; jz .efr_select_free_cond_fail
    call alloc_xmm; cmp eax,-1; je .efr_select_free_cond_fail; mov r12d,eax
    mov rdi,r15; mov esi,r12d; call emit_float_reg; test eax,eax; jnz .efr_select_free_false_fail
    call alloc_xmm; cmp eax,-1; je .efr_select_free_false_fail; mov r14d,eax
    mov edi,ebx; call gen_neg_gpr
    mov edi,r14d; mov esi,ebx; call gen_movq_xmm_gpr
    mov edi,0x54; mov esi,r13d; mov edx,r14d; call gen_sse66_rr
    mov edi,0x55; mov esi,r14d; mov edx,r12d; call gen_sse66_rr
    mov edi,0x56; mov esi,r13d; mov edx,r14d; call gen_sse66_rr
    mov edi,r14d; call free_xmm
    mov edi,r12d; call free_xmm
    mov edi,ebx; call free_gpr
    add dword ptr [rip+schedule_counts+4*4],4
    xor eax,eax; jmp .efr_done
.efr_select_free_false_fail:
    mov edi,r12d; call free_xmm
.efr_select_free_cond_fail:
    mov edi,ebx; call free_gpr
    jmp .efr_fail
.efr_binary:
    xor ebx,ebx
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz 11f; mov ebx,0x58; jmp 15f
11: mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz 12f; mov ebx,0x5C; jmp 15f
12: mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz 13f; mov ebx,0x59; jmp 15f
13: mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .efr_fail; mov ebx,0x5E
15:
    mov r14,[r15+32]; test r14,r14; jz .efr_fail
    cmp ebx,0x5E
    jne .efr_generic_binary
    mov rdi,r14
    call expr_literal_f64_bits
    test edx,edx
    jnz .efr_generic_binary
    call recip_pow2_f64_bits
    test edx,edx
    jnz .efr_generic_binary
    mov r14,rax                    # reciprocal bits
    call alloc_xmm; cmp eax,-1; je .efr_fail; mov r12d,eax
    mov rdi,r15; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_free_x_fail
    mov edi,r12d; mov rsi,r14; call gen_load_f64_bits
    mov edi,0x59; mov esi,r13d; mov edx,r12d; call gen_sse_rr
    inc dword ptr [rip+schedule_counts+4]
    mov edi,r12d; call free_xmm
    xor eax,eax; jmp .efr_done
.efr_generic_binary:
    call alloc_xmm; cmp eax,-1; je .efr_fail; mov r12d,eax
    mov rdi,r15; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_free_x_fail
    mov rdi,r14; mov esi,r12d; call emit_float_reg; test eax,eax; jnz .efr_free_x_fail
    mov edi,ebx; mov esi,r13d; mov edx,r12d; call gen_sse_rr
    cmp ebx,0x59; je .efr_count_mul
    cmp ebx,0x5E; je .efr_count_div
    inc dword ptr [rip+schedule_counts+0]
    jmp .efr_free_x_ok
.efr_count_mul: inc dword ptr [rip+schedule_counts+4]; jmp .efr_free_x_ok
.efr_count_div: inc dword ptr [rip+schedule_counts+8]
.efr_free_x_ok:
    mov edi,r12d; call free_xmm
    xor eax,eax; jmp .efr_done
.efr_free_x_fail:
    mov edi,r12d; call free_xmm
    jmp .efr_fail
.efr_free2_fail:
    mov edi,r12d; call free_gpr
.efr_free_b_fail:
    mov edi,ebx; call free_gpr
.efr_fail:
    mov eax,1
.efr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- 4-lane vector expression emitter ----------------
# Pass-0 physical pressure probe for the unified ZMM16..31 bank. The disposable
# lowering is already required by Physical Reality; this records how many high
# carriers the exact DAG simultaneously occupies without creating a runtime
# manager or an additional profiling execution.
.endm

.macro TFC_vec_init_emit_u8
    mov rax,[rip+vec_init_emit_ptr]
    cmp rax,[rip+vec_init_emit_end]
    jb .tcgrow_ok_4
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vie_fail
.tcgrow_ok_4:
    mov [rax],dil
    inc rax
    mov [rip+vec_init_emit_ptr],rax
    xor eax,eax
    ret
.vie_fail:
    mov eax,1
    ret

# vec_emit_init_const(edi=resident physical ZMM, rsi=qword bits). Executed once per worker.
.endm

.macro TFC_vec_emit_u8
    mov rax,[rip+vec_emit_ptr]
    cmp rax,[rip+vec_emit_end]
    jb .tcgrow_ok_6
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .veu_fail
.tcgrow_ok_6:
    mov [rax],dil
    inc rax
    mov [rip+vec_emit_ptr],rax
    xor eax,eax
    ret
.veu_fail: mov eax,1; ret

.endm

.macro TFC_vec_patch_rel32
    test rdi,rdi
    jz .vpr_fail
    mov rax,rsi
    lea rcx,[rdi+4]
    sub rax,rcx
    movsxd rdx,eax
    cmp rdx,rax
    jne .vpr_fail
    mov dword ptr [rdi],eax
    xor eax,eax
    ret
.vpr_fail:
    mov eax,1
    ret

# rsi=target, emits E9 rel32. eax=0/1.
.endm

.macro TFC_vec_emit_jmp_to
    push rbx
    mov rbx,rsi
    call vec_emit_jmp_placeholder
    test rax,rax
    jz .vejt_fail
    mov rdi,rax
    mov rsi,rbx
    call vec_patch_rel32
    pop rbx
    ret
.vejt_fail:
    pop rbx
    mov eax,1
    ret

# Low-register VEX2 3-operand: edi=opcode, esi=dst, edx=src1, ecx=src2, r8d=pp.
# map is 0F, L=256. All vector regs are 0..7 by construction.
.endm

.macro TFC_vec_vex3_0f38_rrr
    push rbx
    mov ebx,edi
    mov edi,0xC4; call vec_emit_u8
    mov eax,esi; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov r9d,ecx; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5
    or eax,r9d
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov eax,edx; not eax; and eax,0xF; shl eax,3
    or eax,0x04
    or eax,r8d
    mov edi,eax; call vec_emit_u8
    mov edi,ebx; call vec_emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov r9d,ecx; and r9d,7; or eax,r9d; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    pop rbx
    ret

# EVEX vmovdqa64 ymm dst,ymm src, regs 0..31.  Used for persistent CSE
# ingress/egress so YMM16..23 never alias XMM12..15 reduction carriers.
.endm

.macro TFC_vec_const_intern
    push rbx
    push r12
    mov r12,rsi
    xor ebx,ebx
    mov ecx,dword ptr [rip+vec_const_count]
    mov r8,[rip+vec_const_bits_ptr]
.vci_find:
    cmp ebx,ecx
    jae .vci_new
    cmp qword ptr [r8+rbx*8],r12
    je .vci_have
    inc ebx
    jmp .vci_find
.vci_new:
    cmp ecx,dword ptr [rip+tensor_optimizer_capacity]
    jae .vci_fail
    mov qword ptr [r8+rcx*8],r12
    mov ebx,ecx
    inc ecx
    mov dword ptr [rip+vec_const_count],ecx
.vci_have:
    mov eax,ebx
    jmp .vci_done
.vci_fail:
    mov eax,-1
.vci_done:
    pop r12
    pop rbx
    ret

# vec_const_get_reg(rsi=qword bits) -> eax resident physical ZMM or -1.
# Unlike vec_broadcast_imm64 this returns the immutable source register directly,
# allowing arithmetic to consume constants without a synthetic copy edge.
.endm

.macro TFC_vec_vpmullq_native
    push rbx
    mov ebx,edi
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov r9d,esi; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,7; or eax,r9d
    mov r9d,ecx; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,6; or eax,r9d
    mov r9d,ecx; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5; or eax,r9d
    mov r9d,esi; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,4; or eax,r9d
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov eax,edx; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,edx; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40
    mov edi,eax; call vec_emit_u8
    mov edi,0x40; call vec_emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov r9d,ecx; and r9d,7; or eax,r9d; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*5]
    pop rbx
    ret

# AVX512F VPMULUDQ primitive used by the synthesized i64 multiply recipe.
# Arguments mirror vec_vex2_rrr: edi=dst, edx=src1, ecx=src2; esi is ignored.
.endm

.macro TFC_vec_vpmuludq
    # Caller passes dst in edi and sources in edx/ecx; vec_vex2_rrr expects
    # dst in esi, so normalize registers here.
    push rbx
    mov ebx,edi
    mov r9d,edx
    mov r10d,ecx
    mov edi,0xF4
    mov esi,ebx
    mov edx,r9d
    mov ecx,r10d
    mov r8d,1
    call vec_vex2_rrr
    # Reclassify the generic encoder's default integer-ALU accounting as multiply.
    dec dword ptr [rip+schedule_counts+4*4]
    inc dword ptr [rip+schedule_counts+4*5]
    pop rbx
    ret

# EVEX vpsllq zmm dst,src,imm8.  Destination is encoded in EVEX.vvvv/V',
# source in ModRM.rm/B/B'.  Used for exact modulo-2^64 strength reduction.
.endm

.macro TFC_vec_vcvtqq2pd
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_I64_FP_CONVERT
    jnz .vcq2pd_native_dispatch
    test eax,ISA_CAP_I64_FP_CONVERT_SYNTH
    jz .vcq2pd_no_cap
    jmp vec_vcvtqq2pd_synth
.vcq2pd_native_dispatch:
    jmp vec_vcvtqq2pd_native
.vcq2pd_no_cap:
    mov eax,1
    ret

# AVX512DQ native realization.
.endm

.macro TFC_vec_vcvtqq2pd_native
    push rbx
    mov ebx,edi
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,esi; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,esi; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0xFE; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0xE6; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,esi; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3]
    pop rbx
    xor eax,eax
    ret

# AVX512F exact synthesis of signed int64 -> binary64.
# For each lane x, split x = hi32*2^32 + lo32(unsigned).  hi32 and lo32 are
# exactly representable as binary64; the correction of a negative signed low
# dword is also exact.  The final add is therefore the same single rounding of
# the exact int64 value performed by VCVTQQ2PD.
.endm

.macro TFC_vec_roundpd_trunc_scalar_reg
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0x66; call vec_emit_u8
    mov eax,0x40
    test ebx,8; jz 991f; or eax,0x04
991: test r10d,8; jz 992f; or eax,0x01
992: cmp eax,0x40; je 993f
    mov edi,eax; call vec_emit_u8
993: mov edi,0x0F; call vec_emit_u8
    mov edi,0x3A; call vec_emit_u8
    mov edi,0x0B; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,3; call vec_emit_u8
    pop rbx
    xor eax,eax
    ret

.endm

.macro TFC_vec_trunc_nonneg_pd_to_u64
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_I64_FP_CONVERT
    jnz .vtnp_native
    test eax,ISA_CAP_NONNEG_F64_U64_TRUNC_SYNTH
    jz .vtnp_fail
    jmp vec_trunc_nonneg_pd_to_u64_synth
.vtnp_native:
    jmp vec_vcvttpd2qq
.vtnp_fail:
    mov eax,1
    ret

.endm

.macro TFC_vec_trunc_nonneg_pd_to_u64_synth
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi

    # Intern both immutable constants before touching the generated code.
    # 2^52 double bits; after addition, subtracting these raw bits reveals the
    # integer mantissa exactly for all proven 0 <= x < 2^52.
    mov rsi,0x4330000000000000
    call vec_const_intern
    cmp eax,-1
    je .vtnps_fail
    mov r13d,eax
    mov rsi,0xBCD0000000000000     # -0x4330000000000000 modulo 2^64
    call vec_const_intern
    cmp eax,-1
    je .vtnps_fail
    push rax                       # pool index for raw-bits subtraction

    # Round toward zero while still in FP.  For the proven non-negative domain
    # this is floor/trunc and produces an exact integer-valued binary64.
    mov edi,ebx; mov esi,r12d; call vec_vrndscalepd_trunc

    # dst += 2^52 as a floating-point value.  The result is in [2^52,2^53),
    # where every integer is exactly representable and raw mantissa bits equal x.
    mov edi,ebx; mov esi,ebx; mov edx,r13d; call vec_vaddpd_mem_const
    test eax,eax
    jnz .vtnps_fail_pop

    # Reinterpret the bits and subtract the 2^52 encoding with integer add.
    pop rdx
    mov edi,ebx; mov esi,ebx; call vec_vpaddq_mem_const
    test eax,eax
    jnz .vtnps_fail
    xor eax,eax
    jmp .vtnps_done
.vtnps_fail_pop:
    add rsp,8
.vtnps_fail:
    mov eax,1
.vtnps_done:
    pop r13
    pop r12
    pop rbx
    ret

# AVX512F VRNDSCALEPD zmmDST,zmmSRC,truncate-toward-zero.
.endm

.macro TFC_vec_vcvttpd2qq
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_I64_FP_CONVERT
    jz .vctpdq_no_cap
    push rbx
    mov ebx,edi
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,esi; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,esi; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x7A; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,esi; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3] # AVX-512 FP conversion
    pop rbx
    ret
.vctpdq_no_cap:
    mov eax,1
    ret

# vpcmpeqq k1,zmm src1,zmm src2; vpmovm2q zmm dst,k1
.endm

.macro TFC_expr_affine_axis_u64
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    # axis
    mov rdi,r12; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .eaa_op
    mov eax,1
    xor edx,edx
    mov ecx,1
    jmp .eaa_done
.eaa_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eaa_no
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eaa_no
    mov r14,[rax+24]; test r14,r14; jz .eaa_no
    mov r15,[r14+32]; test r15,r15; jz .eaa_no
    cmp qword ptr [r15+32],0; jne .eaa_no
    # mul(axis,literal) or mul(literal,axis)
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz .eaa_add
    mov rdi,r14; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .eaa_mul_rev
    mov rdi,r15; call expr_literal_u64
    test edx,edx; jnz .eaa_no
    xor edx,edx; mov ecx,1; jmp .eaa_done
.eaa_mul_rev:
    mov rdi,r15; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .eaa_no
    mov rdi,r14; call expr_literal_u64
    test edx,edx; jnz .eaa_no
    xor edx,edx; mov ecx,1; jmp .eaa_done
.eaa_add:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz .eaa_no
    # affine + literal
    mov rdi,r15; call expr_literal_u64
    test edx,edx; jnz .eaa_add_rev
    mov rbx,rax
    mov rdi,r14; call expr_affine_axis_u64
    test ecx,ecx; jz .eaa_no
    add rdx,rbx; jc .eaa_no
    mov ecx,1; jmp .eaa_done
.eaa_add_rev:
    mov rdi,r14; call expr_literal_u64
    test edx,edx; jnz .eaa_no
    mov rbx,rax
    mov rdi,r15; call expr_affine_axis_u64
    test ecx,ecx; jz .eaa_no
    add rdx,rbx; jc .eaa_no
    mov ecx,1; jmp .eaa_done
.eaa_no:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
.eaa_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_interior_affine_residue_safe(rdi=local_c,rsi=local_signed_d) -> eax=1/0.
# Proves that the composed affine coordinate lies in [0,n) for every lane of
# the already-proven interior vector region.  The physical root lanes there
# satisfy 1 <= root <= n-2.  This is a generic interval proof used to erase a
# dynamic modulo-n only when modulo is mathematically the identity after ring
# normalization; it is not tied to any workload, stencil radius or coefficient.
.endm

.macro TFC_vec_axis_compose_from_index
    push rbx
    push r12
    mov r12,rdi
    cmp dword ptr [rip+vec_axis_root_valid],1
    jne .vaci_invalid
    mov rdi,r12
    call expr_affine_axis_interior_u64
    test ecx,ecx
    jz .vaci_invalid
    mov rbx,rax
    mov r12,rdx
    mov rax,qword ptr [rip+vec_axis_root_c]
    mul rbx
    test rdx,rdx
    jnz .vaci_invalid
    mov r8,rax
    mov rax,qword ptr [rip+vec_axis_root_d]
    mul rbx
    # Interior signed-small offsets intentionally use modulo-2^64 arithmetic.
    add rax,r12
    mov qword ptr [rip+vec_axis_root_c],r8
    mov qword ptr [rip+vec_axis_root_d],rax
    mov dword ptr [rip+vec_axis_root_valid],1
    xor eax,eax
    jmp .vaci_done
.vaci_invalid:
    mov dword ptr [rip+vec_axis_root_valid],0
    mov eax,1
.vaci_done:
    pop r12
    pop rbx
    ret

# 1.3.7 constant-use profiler. rsi=exact qword identity, edi=physical
# savings weight. Pass 0 observes demand; pass 1 alone is allowed residency.
.endm

.macro TFC_vec_save_axis
    lea rdi,[rip+vec_save_axis_code]
    mov esi,vec_save_axis_code_end-vec_save_axis_code
    jmp vec_emit_bytes
.endm

.macro TFC_vec_restore_axis
    lea rdi,[rip+vec_restore_axis_code]
    mov esi,vec_restore_axis_code_end-vec_restore_axis_code
    jmp vec_emit_bytes

# Direct-axis pure-map CSE scoped by coordinate generation.
# lookup(rdi=binding) -> eax=ymm reg or -1
.endm

.macro TFC_vec_linear_operator_expr
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    inc dword ptr [rip+vec_operator_check_depth]
    cmp qword ptr [r12],J_OBJECT
    jne .vloe_no
    mov rdi,r12; lea rsi,[rip+k_load]; mov edx,k_load_end-k_load; call obj_get
    test rax,rax; jz .vloe_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call find_binding
    test rax,rax; jz .vloe_no
    cmp dword ptr [rax+16],OP_MAP; jne .vloe_no
    mov eax,1
    jmp .vloe_done
.vloe_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .vloe_no
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .vloe_no
    mov r14,[rax+24]; test r14,r14; jz .vloe_no
    mov r15,[r14+32]; test r15,r15; jz .vloe_no
    cmp qword ptr [r15+32],0; jne .vloe_no
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jnz .vloe_two
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jnz .vloe_two
    mov rdi,r12; call expr_mul_literal_other
    test ecx,ecx; jnz .vloe_scaled
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .vloe_no
    mov rdi,r15; call expr_literal_f64_bits
    test edx,edx; jnz .vloe_no
    call recip_pow2_f64_bits
    test edx,edx; jnz .vloe_no
    mov rdi,r14; call vec_linear_operator_expr
    jmp .vloe_done
.vloe_scaled:
    mov rdi,rdx; call vec_linear_operator_expr
    jmp .vloe_done
.vloe_two:
    mov rdi,r14; call vec_linear_operator_expr
    test eax,eax; jz .vloe_no
    mov rdi,r15; call vec_linear_operator_expr
    jmp .vloe_done
.vloe_no:
    xor eax,eax
.vloe_done:
    dec dword ptr [rip+vec_operator_check_depth]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Canonical structural coordinate algebra for linear operator leaves.
# A direction key is (source, c, d, modulus) and means
#       source[(c*root + d) mod modulus]
# with modulus=0 denoting the ordinary affine domain.  No solver/workload name
# participates.  Periodic composition is admitted only when its modular
# arithmetic is exactly provable; fixed external extents are normalized to a
# canonical residue class so algebraic relations collapse by ordinary key
# equality.

# vec_linear_modulus_value(rdi=modtoken) -> rax=value, ecx=1 if compile-time
# known. modtoken=-1 denotes external n and is known only for a fixed extent.
.endm

.macro TFC_vec_linear_mul_mod
    push rbx
    push r12
    mov r12,rdx
    mov rax,rdi
    xor edx,edx
    div r12
    mov rbx,rdx
    mov rax,rsi
    xor edx,edx
    div r12
    mov rax,rdx
    mul rbx
    div r12
    mov rax,rdx
    pop r12
    pop rbx
    ret

# vec_linear_add_mod(rdi=a,rsi=b,rdx=m) -> rax=(a+b)%m
.endm

.macro TFC_vec_linear_add_mod
    push rbx
    push r12
    mov r12,rdx
    mov rax,rdi
    xor edx,edx
    div r12
    mov rbx,rdx
    mov rax,rsi
    xor edx,edx
    div r12
    mov rcx,rdx
    mov rax,rbx
    xor edx,edx
    add rax,rcx
    adc rdx,0
    div r12
    mov rax,rdx
    pop r12
    pop rbx
    ret

# vec_linear_compose_key(rdi=local_c,rsi=local_d,rdx=local_mod)
# -> rax=root_c, rdx=root_d, r8=canonical_mod, ecx=1/0.
# Composition is generic affine-function composition. If a modulus is present,
# both nested modulo domains must denote the same ring. A fixed n is normalized
# numerically; a dynamic n remains symbolic and is accepted only when the
# unnormalized affine arithmetic cannot overflow.
.endm

.macro TFC_vec_linear_add_term
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13,rsi
    mov r14,rdx
    mov r15,rcx
    mov rbx,r8
    mov r10,r9
    mov eax,dword ptr [rip+vec_linear_count]
    xor ecx,ecx
.vlat_find:
    cmp ecx,eax
    jae .vlat_new
    mov rdx,[rip+vec_linear_binding_ptr]
    cmp qword ptr [rdx+rcx*8],r12
    jne .vlat_next
    mov rdx,[rip+vec_linear_key_a_ptr]
    cmp qword ptr [rdx+rcx*8],r13
    jne .vlat_next
    mov rdx,[rip+vec_linear_key_b_ptr]
    cmp qword ptr [rdx+rcx*8],r14
    jne .vlat_next
    mov rdx,[rip+vec_linear_key_c_ptr]
    cmp qword ptr [rdx+rcx*8],r15
    jne .vlat_next
    mov rdx,[rip+vec_linear_coeff_ptr]
    movq xmm0,qword ptr [rdx+rcx*8]
    movq xmm1,r10
    addsd xmm0,xmm1
    movq qword ptr [rdx+rcx*8],xmm0
    mov rdx,[rip+vec_linear_mode_ptr]
    mov eax,dword ptr [rip+vec_linear_term_mode]
    cmp eax,dword ptr [rdx+rcx*4]
    jbe .vlat_mode_ready
    mov dword ptr [rdx+rcx*4],eax
.vlat_mode_ready:
    xor eax,eax
    jmp .vlat_done
.vlat_next:
    inc ecx
    jmp .vlat_find
.vlat_new:
    cmp eax,dword ptr [rip+tensor_optimizer_capacity]
    jae .vlat_fail
    mov rdx,[rip+vec_linear_binding_ptr]
    mov qword ptr [rdx+rax*8],r12
    mov rdx,[rip+vec_linear_key_a_ptr]
    mov qword ptr [rdx+rax*8],r13
    mov rdx,[rip+vec_linear_key_b_ptr]
    mov qword ptr [rdx+rax*8],r14
    mov rdx,[rip+vec_linear_key_c_ptr]
    mov qword ptr [rdx+rax*8],r15
    mov rdx,[rip+vec_linear_expr_ptr]
    mov qword ptr [rdx+rax*8],rbx
    mov rdx,[rip+vec_linear_coeff_ptr]
    mov qword ptr [rdx+rax*8],r10
    mov rdx,[rip+vec_linear_mode_ptr]
    mov ecx,dword ptr [rip+vec_linear_term_mode]
    mov dword ptr [rdx+rax*4],ecx
    inc eax
    mov dword ptr [rip+vec_linear_count],eax
    xor eax,eax
    jmp .vlat_done
.vlat_fail:
    mov eax,1
.vlat_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_linear_collect(rdi=expr,rsi=scale_bits) -> eax=0 if the entire tree is a
# supported linear topology expression, 1 otherwise.  Direct-axis map wrappers
# are transparent. Indexed map loads become aggregation leaves.
.endm

.macro TFC_vec_linear_collect
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi                    # expr
    mov r13,rsi                    # accumulated coefficient bits
    cmp qword ptr [r12],J_OBJECT
    jne .vlc_fail

    # add(a,b) -> collect both at the same scale.
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax
    jz .vlc_try_load
    mov r14,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax
    jz .vlc_try_mul
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .vlc_fail
    mov r14,[rax+24]; test r14,r14; jz .vlc_fail
    mov r15,[r14+32]; test r15,r15; jz .vlc_fail
    cmp qword ptr [r15+32],0; jne .vlc_fail
    mov rdi,r14; mov rsi,r13; call vec_linear_collect
    test eax,eax; jnz .vlc_fail
    mov rdi,r15; mov rsi,r13; call vec_linear_collect
    jmp .vlc_done

.vlc_try_mul:
    # literal*expr or expr*literal: fold the literal into the compile-time scale.
    mov rdi,r12; call expr_mul_literal_other
    test ecx,ecx
    jz .vlc_try_div
    mov r14,rax                    # literal coefficient bits
    mov r15,rdx                    # other expression
    movq xmm0,r13
    movq xmm1,r14
    mulsd xmm0,xmm1
    movq rsi,xmm0
    mov rdi,r15
    call vec_linear_collect
    jmp .vlc_done

.vlc_try_div:
    # expr / exact power-of-two literal is also a linear scale.
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax
    jz .vlc_fail
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .vlc_fail
    mov r15,[rax+24]; test r15,r15; jz .vlc_fail
    mov rbx,[r15+32]; test rbx,rbx; jz .vlc_fail
    cmp qword ptr [rbx+32],0; jne .vlc_fail
    mov rdi,rbx; call expr_literal_f64_bits
    test edx,edx; jnz .vlc_fail
    call recip_pow2_f64_bits
    test edx,edx; jnz .vlc_fail
    movq xmm0,r13
    movq xmm1,rax
    mulsd xmm0,xmm1
    movq rsi,xmm0
    mov rdi,r15
    call vec_linear_collect
    jmp .vlc_done

.vlc_try_load:
    # A map load may be a recursively transparent linear operator wrapper or a
    # base-direction leaf. Repeated A^k applications collapse before emission.
    mov rdi,r12; lea rsi,[rip+k_load]; mov edx,k_load_end-k_load; call obj_get
    test rax,rax; jz .vlc_fail
    mov rdi,[rax+8]; mov rsi,[rax+16]; call find_binding
    test rax,rax; jz .vlc_fail
    mov r14,rax
    cmp dword ptr [r14+16],OP_MAP; jne .vlc_fail
    mov rdi,r12; lea rsi,[rip+k_indices]; mov edx,k_indices_end-k_indices; call obj_get
    test rax,rax; jz .vlc_fail
    mov r15,[rax+24]; test r15,r15; jz .vlc_fail
    cmp qword ptr [r15+32],0; jne .vlc_fail

    mov rdi,r15; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .vlc_indexed
    mov rdi,[r14+40]
    call vec_linear_operator_expr
    test eax,eax; jz .vlc_direct_leaf
    inc dword ptr [rip+vec_operator_compositions]
    mov rdi,[r14+40]
    mov rsi,r13
    call vec_linear_collect
    jmp .vlc_done
.vlc_direct_leaf:
    inc dword ptr [rip+vec_linear_raw_count]
    mov eax,1
    cmp qword ptr [rip+vec_linear_ctx_mod],0
    je .vlc_direct_mode_ready
    mov eax,2
.vlc_direct_mode_ready:
    mov dword ptr [rip+vec_linear_term_mode],eax
    mov rdi,r14
    mov rsi,qword ptr [rip+vec_linear_ctx_c]
    mov rdx,qword ptr [rip+vec_linear_ctx_d]
    mov rcx,qword ptr [rip+vec_linear_ctx_mod]
    mov r8,r12
    mov r9,r13
    call vec_linear_add_term
    jmp .vlc_done

.vlc_indexed:
    mov rdi,r15
    call expr_index_key_u64
    test ecx,ecx; jz .vlc_fail
    push rax
    push rdx
    push r8
    mov rdi,[rsp+16]
    mov rsi,[rsp+8]
    mov rdx,[rsp]
    call vec_linear_compose_key
    test ecx,ecx; jz .vlc_index_old
    push rax
    push rdx
    push r8
    mov rdi,[r14+40]
    call vec_linear_operator_expr
    test eax,eax; jz .vlc_composed_leaf
    mov rax,qword ptr [rip+vec_linear_ctx_c]; push rax
    mov rax,qword ptr [rip+vec_linear_ctx_d]; push rax
    mov rax,qword ptr [rip+vec_linear_ctx_mod]; push rax
    mov rax,[rsp+40]; mov qword ptr [rip+vec_linear_ctx_c],rax
    mov rax,[rsp+32]; mov qword ptr [rip+vec_linear_ctx_d],rax
    mov rax,[rsp+24]; mov qword ptr [rip+vec_linear_ctx_mod],rax
    inc dword ptr [rip+vec_operator_compositions]
    mov eax,dword ptr [rip+vec_operator_inline_depth]
    inc eax
    mov dword ptr [rip+vec_operator_inline_depth],eax
    cmp eax,dword ptr [rip+vec_operator_max_depth]
    jbe .vlc_depth_recorded
    mov dword ptr [rip+vec_operator_max_depth],eax
.vlc_depth_recorded:
    mov rdi,[r14+40]
    mov rsi,r13
    call vec_linear_collect
    mov r11d,eax                  # preserve recursive proof status
    dec dword ptr [rip+vec_operator_inline_depth]
    pop rax; mov qword ptr [rip+vec_linear_ctx_mod],rax
    pop rax; mov qword ptr [rip+vec_linear_ctx_d],rax
    pop rax; mov qword ptr [rip+vec_linear_ctx_c],rax
    add rsp,48
    mov eax,r11d                  # restore true collector result
    jmp .vlc_done

.vlc_composed_leaf:
    inc dword ptr [rip+vec_linear_raw_count]
    mov eax,1
    cmp qword ptr [rsp],0
    je .vlc_composed_mode_ready
    mov eax,2
.vlc_composed_mode_ready:
    mov dword ptr [rip+vec_linear_term_mode],eax
    mov rdi,r14
    mov rsi,[rsp+16]
    mov rdx,[rsp+8]
    mov rcx,[rsp]
    mov r8,r12
    mov r9,r13
    call vec_linear_add_term
    add rsp,48
    jmp .vlc_done

.vlc_index_old:
    inc dword ptr [rip+vec_linear_raw_count]
    mov dword ptr [rip+vec_linear_term_mode],0
    mov rdi,r14
    mov rsi,[rsp+16]
    mov rdx,[rsp+8]
    mov rcx,[rsp]
    mov r8,r12
    mov r9,r13
    call vec_linear_add_term
    add rsp,24
    jmp .vlc_done

.vlc_fail:
    mov eax,1
.vlc_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Transactional structural rewrite state. Proof/resource planning may reject a
# candidate after consulting nested emitters; rejection must be observationally
# identical to never attempting the rewrite.  These helpers snapshot every
# mutable native-realization frontier touched by vec_linear_try_emit.
.endm

.macro TFC_vec_linear_try_emit
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13d,esi
    call vec_linear_txn_begin
    mov dword ptr [rip+vec_linear_count],0
    mov dword ptr [rip+vec_linear_raw_count],0
    mov dword ptr [rip+vec_linear_live_count],0
    mov dword ptr [rip+vec_elim_carriers],0
    mov dword ptr [rip+vec_elim_carrier1],-1
    mov dword ptr [rip+vec_elim_carrier2],-1
    mov dword ptr [rip+vec_elim_carrier3],-1
    mov dword ptr [rip+vec_elim_emit_ordinal],0
    mov dword ptr [rip+vec_elim_span_before],0
    mov dword ptr [rip+vec_elim_span_after],0
    cmp dword ptr [rip+vec_axis_root_valid],1
    jne .vlte_fail
    mov rax,qword ptr [rip+vec_axis_root_c]
    mov qword ptr [rip+vec_linear_ctx_c],rax
    mov rax,qword ptr [rip+vec_axis_root_d]
    mov qword ptr [rip+vec_linear_ctx_d],rax
    mov qword ptr [rip+vec_linear_ctx_mod],0
    mov dword ptr [rip+vec_linear_term_mode],0
    mov dword ptr [rip+vec_operator_inline_depth],0
    mov dword ptr [rip+vec_operator_max_depth],0
    mov dword ptr [rip+vec_operator_compositions],0
    mov dword ptr [rip+vec_operator_check_depth],0
    mov rdi,r12
    mov rsi,0x3ff0000000000000     # 1.0
    call vec_linear_collect
    test eax,eax; jnz .vlte_fail
    mov ebx,dword ptr [rip+vec_linear_count]
    test ebx,ebx; jz .vlte_fail

    # Count non-zero post-aggregation leaves. Treat +0 and -0 as the same
    # eliminated coefficient.  This is an exact compile-time cancellation, not
    # a tolerance guess.
    xor r14d,r14d
    xor r15d,r15d
.vlte_count_live:
    cmp r14d,ebx
    jae .vlte_count_done
    mov rax,[rip+vec_linear_coeff_ptr]
    mov r12,[rax+r14*8]
    mov rax,r12
    shl rax,1                     # both IEEE signed zeros become zero
    jz .vlte_count_next
    inc r15d
.vlte_count_next:
    inc r14d
    jmp .vlte_count_live
.vlte_count_done:
    mov dword ptr [rip+vec_linear_live_count],r15d
    test r15d,r15d
    jz .vlte_all_cancelled
    mov eax,dword ptr [rip+vec_linear_raw_count]
    mov dword ptr [rip+vec_elim_span_before],eax
    # Computation-elimination is accepted only if work strictly shrinks.
    cmp r15d,eax
    jae .vlte_fail

    # Carrier policy is itself parallel-preserving: enough independent terms
    # receive 4 carriers; medium reductions receive 2; tiny reductions use 1.
    # The old tolerant fallback is a single accumulator, so this can only keep
    # or increase arithmetic ILP.
    mov ecx,1
    cmp r15d,4
    jb .vlte_carriers_chosen
    mov ecx,2
    cmp r15d,8
    jb .vlte_carriers_chosen
    mov ecx,4
.vlte_carriers_chosen:
    mov dword ptr [rip+vec_elim_carriers],ecx

    # span_after = ceil(live/carriers) + log2(carriers).  Reject if the
    # elimination would lengthen the dependency chain relative to the exact
    # pre-pass tolerant lowering.  For 1/2/4 carriers log2 = 0/1/2.
    mov eax,r15d
    lea edx,[rcx-1]
    add eax,edx
    xor edx,edx
    div ecx
    cmp ecx,2
    jb .vlte_span_ready
    add eax,1
    cmp ecx,4
    jne .vlte_span_ready
    add eax,1
.vlte_span_ready:
    mov dword ptr [rip+vec_elim_span_after],eax
    cmp eax,dword ptr [rip+vec_elim_span_before]
    ja .vlte_fail

    # Reserve all extra accumulators before emitting a single byte.  If the
    # register file cannot preserve the requested parallel width, reject the
    # pass and let the ordinary lowering proceed instead of silently serializing.
    cmp ecx,1
    je .vlte_carriers_reserved
    call vec_alloc
    cmp eax,-1; je .vlte_fail
    mov dword ptr [rip+vec_elim_carrier1],eax
    cmp ecx,2
    je .vlte_carriers_reserved
    call vec_alloc
    cmp eax,-1; je .vlte_reserve_fail1
    mov dword ptr [rip+vec_elim_carrier2],eax
    call vec_alloc
    cmp eax,-1; je .vlte_reserve_fail2
    mov dword ptr [rip+vec_elim_carrier3],eax
.vlte_carriers_reserved:

    # Keep the table stable while representative loads are recursively emitted.
    mov dword ptr [rip+vec_linear_active],1
    mov edi,r13d
    xor esi,esi                    # +0.0
    call vec_broadcast_imm64
    test eax,eax; jnz .vlte_emit_fail
    mov eax,dword ptr [rip+vec_elim_carriers]
    cmp eax,1; je .vlte_zero_done
    mov edi,dword ptr [rip+vec_elim_carrier1]
    xor esi,esi; call vec_broadcast_imm64
    test eax,eax; jnz .vlte_emit_fail
    cmp dword ptr [rip+vec_elim_carriers],2; je .vlte_zero_done
    mov edi,dword ptr [rip+vec_elim_carrier2]
    xor esi,esi; call vec_broadcast_imm64
    test eax,eax; jnz .vlte_emit_fail
    mov edi,dword ptr [rip+vec_elim_carrier3]
    xor esi,esi; call vec_broadcast_imm64
    test eax,eax; jnz .vlte_emit_fail
.vlte_zero_done:
    xor r14d,r14d                  # table term index
.vlte_loop:
    cmp r14d,dword ptr [rip+vec_linear_count]
    jae .vlte_reduce
    mov rax,[rip+vec_linear_coeff_ptr]
    mov r12,[rax+r14*8]
    mov rax,r12
    shl rax,1
    jz .vlte_next                  # exact +/-0 coefficient

    # Select an independent accumulation carrier round-robin over live terms.
    mov eax,dword ptr [rip+vec_elim_emit_ordinal]
    inc dword ptr [rip+vec_elim_emit_ordinal]
    xor ebx,ebx
    cmp dword ptr [rip+vec_elim_carriers],1
    je .vlte_carrier_dst
    cmp dword ptr [rip+vec_elim_carriers],2
    je .vlte_carrier_two
    and eax,3
    test eax,eax; jz .vlte_carrier_dst
    cmp eax,1; je .vlte_carrier_one
    cmp eax,2; je .vlte_carrier_two_idx
    mov ebx,dword ptr [rip+vec_elim_carrier3]
    jmp .vlte_carrier_ready
.vlte_carrier_two:
    and eax,1
    test eax,eax; jz .vlte_carrier_dst
.vlte_carrier_one:
    mov ebx,dword ptr [rip+vec_elim_carrier1]
    jmp .vlte_carrier_ready
.vlte_carrier_two_idx:
    mov ebx,dword ptr [rip+vec_elim_carrier2]
    jmp .vlte_carrier_ready
.vlte_carrier_dst:
    mov ebx,r13d
.vlte_carrier_ready:

    call vec_alloc
    cmp eax,-1; je .vlte_emit_fail
    mov r15d,eax
    mov rax,[rip+vec_linear_mode_ptr]
    mov eax,dword ptr [rax+r14*4]
    test eax,eax
    jz .vlte_emit_representative
    # mode 1/2 are both canonical base directions. Their modulus token selects
    # physical realization inside one generic key emitter.
    mov rax,[rip+vec_linear_binding_ptr]
    mov rdi,[rax+r14*8]
    mov esi,r15d
    mov rax,[rip+vec_linear_key_a_ptr]
    mov rdx,[rax+r14*8]
    mov rax,[rip+vec_linear_key_b_ptr]
    mov rcx,[rax+r14*8]
    mov rax,[rip+vec_linear_key_c_ptr]
    mov r8,[rax+r14*8]
    push rbx
    call vec_linear_emit_base_term
    mov r10d,eax
    pop rbx
    test r10d,r10d; jnz .vlte_term_fail
    jmp .vlte_term_emitted
.vlte_emit_representative:
    mov rax,[rip+vec_linear_expr_ptr]
    mov rdi,[rax+r14*8]
    mov esi,r15d
    push rbx
    call emit_vec_float
    mov r10d,eax
    pop rbx
    test r10d,r10d; jnz .vlte_term_fail
.vlte_term_emitted:
    mov rsi,r12
    call vec_const_get_reg
    cmp eax,-1; je .vlte_term_mem
    mov ecx,eax
    mov edi,ebx; mov esi,ebx; mov edx,r15d; call vec_vfmadd231pd
    mov edi,r15d; call vec_free
    jmp .vlte_next
.vlte_term_mem:
    mov rsi,r12
    call vec_const_intern
    cmp eax,-1; je .vlte_term_fail
    mov edx,eax
    mov edi,ebx; mov esi,r15d; call vec_vfmadd231pd_mem_const
    test eax,eax; jnz .vlte_term_fail
    mov edi,r15d; call vec_free
.vlte_next:
    inc r14d
    jmp .vlte_loop

.vlte_reduce:
    # Balanced merge: 4 carriers -> (c0+c1) || (c2+c3) -> final.
    cmp dword ptr [rip+vec_elim_carriers],1
    je .vlte_success
    mov ebx,dword ptr [rip+vec_elim_carrier1]
    mov edi,0x58; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1
    call vec_vex2_rrr
    cmp dword ptr [rip+vec_elim_carriers],2
    je .vlte_success
    mov ebx,dword ptr [rip+vec_elim_carrier2]
    mov r12d,dword ptr [rip+vec_elim_carrier3]
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    mov edi,0x58; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1
    call vec_vex2_rrr
    jmp .vlte_success

.vlte_all_cancelled:
    # Every leaf cancelled exactly.  Emit one zero vector and no topology load,
    # arithmetic, barrier, or synchronization work.
    mov eax,dword ptr [rip+vec_linear_raw_count]
    test eax,eax; jz .vlte_fail
    mov dword ptr [rip+vec_elim_span_before],eax
    mov dword ptr [rip+vec_elim_span_after],1
    mov dword ptr [rip+vec_elim_carriers],1
    mov dword ptr [rip+vec_linear_active],1
    mov edi,r13d; xor esi,esi; call vec_broadcast_imm64
    test eax,eax; jnz .vlte_emit_fail
    jmp .vlte_success

.vlte_term_fail:
    mov edi,r15d; call vec_free
.vlte_emit_fail:
    mov dword ptr [rip+vec_linear_active],0
    call vec_elim_free_carriers
    jmp .vlte_rollback_fail
.vlte_success:
    mov dword ptr [rip+vec_linear_active],0
    call vec_elim_free_carriers
    xor eax,eax
    jmp .vlte_done
.vlte_reserve_fail2:
    mov edi,dword ptr [rip+vec_elim_carrier2]
    call vec_free
    mov dword ptr [rip+vec_elim_carrier2],-1
.vlte_reserve_fail1:
    mov edi,dword ptr [rip+vec_elim_carrier1]
    call vec_free
    mov dword ptr [rip+vec_elim_carrier1],-1
.vlte_fail:
    mov dword ptr [rip+vec_linear_count],0
.vlte_rollback_fail:
    call vec_linear_txn_rollback
    mov eax,1
.vlte_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Free only the extra elimination accumulators.  The caller-owned destination is
# never part of this list.  This helper makes every exit path restore allocator
# state, which is required for safe fallback to the ordinary vector lowering.
.endm

.macro TFC_vec_elim_free_carriers
    push rbx
    mov ebx,dword ptr [rip+vec_elim_carrier1]
    cmp ebx,-1; je .vefc_c2
    mov edi,ebx; call vec_free
    mov dword ptr [rip+vec_elim_carrier1],-1
.vefc_c2:
    mov ebx,dword ptr [rip+vec_elim_carrier2]
    cmp ebx,-1; je .vefc_c3
    mov edi,ebx; call vec_free
    mov dword ptr [rip+vec_elim_carrier2],-1
.vefc_c3:
    mov ebx,dword ptr [rip+vec_elim_carrier3]
    cmp ebx,-1; je .vefc_done
    mov edi,ebx; call vec_free
    mov dword ptr [rip+vec_elim_carrier3],-1
.vefc_done:
    pop rbx
    ret

# Tolerant floating-point additive accumulator.
# emit_vec_float_accum(rdi=expr, esi=dst) adds expr into an already initialized
# destination.  Add trees are flattened recursively so every literal-scaled
# leaf can contract directly into the same accumulator instead of materializing
# balanced-tree temporaries.  Exact power-of-two division is treated as a
# literal scale.  Strict mode never calls this helper.
.endm

.macro TFC_vec_fused_finish_fragment
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
.endm

