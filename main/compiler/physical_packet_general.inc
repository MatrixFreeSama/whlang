# Independent AxisFact realization. Each node has one natural type; a packet is
# only a physical carrier. Unsupported primitives contract locally to the same
# scalar semantic authority. Strict folds consume lanes in original axis order.
# No frontend identity, function name, or benchmark name controls packet birth.

# edi=byte count, esi=0 reserve / 1 release generated runtime stack.
g_emit_packet_stack_adjust:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov edi,0x8148; call g_emit_u16
    mov edi,0xec; test r12d,r12d; jz 1f
    mov edi,0xc4
1:  call g_emit_u8
    mov edi,ebx; call g_emit_u32
    pop r12; pop rbx; ret

# edi=offset, esi=type, edx=0 store RAX / 1 load RAX. Always disp32;
# packet geometry therefore cannot silently change a compressed displacement.
g_emit_packet_scalar_slot:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp esi,GTYPE_F32; je 1f
    mov edi,0x48; call g_emit_u8
1:  mov edi,0x89; test r13d,r13d; jz 2f
    mov edi,0x8b
2:  call g_emit_u8
    mov edi,0x2484; call g_emit_u16
    mov edi,ebx; call g_emit_u32
    pop r13; pop r12; pop rbx; ret

# edi=register, esi=type, edx=offset, ecx=0 load / 1 store / 2 final consume.
# Final consume returns eax=1 for adjacent register ownership, or eax=0 without
# emission when the value still owns memory. Ordinary reads materialize as before.
# Natural precision sets payload width; encoding shares opaque slot authority.
g_emit_packet_simd_slot:
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12d,esi; mov r13d,edx; mov r14d,ecx
    cmp ecx,1; je .gpss_memory
    # The just-written packet is still owned by its register. An immediately
    # adjacent read of that same physical slot consumes the existing carrier.
    mov rax,[rip+g_emit_ptr]; cmp rax,[rip+g_packet_last_store_end]; jne .gpss_memory
    cmp esi,[rip+g_packet_last_store_type]; jne .gpss_memory
    cmp edx,[rip+g_packet_last_store_offset]; jne .gpss_memory
    mov eax,[rip+g_packet_slot_memory_base]; cmp eax,[rip+g_packet_last_store_base]; jne .gpss_memory
    cmp edi,[rip+g_packet_last_store_reg]; je .gpss_same
    mov edi,0x2128                    # VMOVAPS is payload transport for every type.
    cmp dword ptr [rip+group_lane_factor],8; jne 90f
    cmp r12d,GTYPE_F32; je 91f
    mov edi,0xc128; jmp 91f
90: cmp r12d,GTYPE_F32; jne 91f
    mov edi,0x128
91: mov esi,ebx; xor edx,edx; mov ecx,[rip+g_packet_last_store_reg]
    call physical_encode_rrr
    test edx,edx; jz .gpss_memory
.gpss_commit:
    # Final consumption removes the adjacent store only after the register
    # transfer is proved encodable. A rejected transfer still owns memory.
    cmp r14d,2; jne .gpss_copy
    mov rcx,[rip+g_packet_last_store_start]; mov [rip+g_emit_ptr],rcx
    mov qword ptr [rip+g_packet_last_store_end],0
.gpss_copy:
    test edx,edx; jz .gpss_done
    sub rsp,8; mov [rsp],rax; mov rdi,rsp; mov esi,edx; call g_emit_bytes; add rsp,8
    jmp .gpss_done
.gpss_same:
    xor edx,edx; jmp .gpss_commit
.gpss_memory:
    cmp r14d,2; je .gpss_unavailable
    and r14d,1
    sub rsp,24
    mov rax,[rip+g_emit_ptr]; mov [rsp+16],rax
    mov edi,ebx; mov esi,[rip+group_lane_factor]
    shl esi,3
    cmp r12d,GTYPE_F32; jne 92f
    shr esi,1
92: mov edx,r13d; mov ecx,r14d
    mov r8,rsp; mov r9d,[rip+g_packet_slot_memory_base]
    call physical_encode_simd_slot
    mov rdi,rsp; mov esi,eax; call g_emit_bytes
    test r14d,r14d; jz 93f
    mov rax,[rsp+16]; mov [rip+g_packet_last_store_start],rax
93: add rsp,24
    test r14d,r14d; jz .gpss_done
    mov rax,[rip+g_emit_ptr]; mov [rip+g_packet_last_store_end],rax
    mov [rip+g_packet_last_store_type],r12d
    mov [rip+g_packet_last_store_offset],r13d
    mov eax,[rip+g_packet_slot_memory_base]; mov [rip+g_packet_last_store_base],eax
    mov [rip+g_packet_last_store_reg],ebx
.gpss_done:
    mov eax,1; jmp .gpss_return
.gpss_unavailable:
    xor eax,eax
.gpss_return:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expression -> eax=natural type; result packet occupies N*8 stack bytes.
g_emit_packet_expr:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,64
    mov r12,rdi
    call g_infer_expr; mov r14d,eax
    mov rdi,r12; mov esi,eax; call g_semantic_identity_representative
    test rax,rax; jz 88f
    mov r12,rax
88: mov rdi,r12; mov esi,r14d; call g_phys_cse_find_resident
    cmp eax,0; jl .gpkt_fresh
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov ebx,dword ptr [rcx+rax*4]
    mov edi,[rip+group_lane_factor]; shl edi,3; xor esi,esi; call g_emit_packet_stack_adjust
    imul ebx,dword ptr [rip+group_lane_factor]; shl ebx,3
    mov dword ptr [rip+g_packet_slot_memory_base],1
    xor edi,edi; mov esi,r14d; mov edx,ebx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov dword ptr [rip+g_packet_slot_memory_base],0
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    mov eax,r14d; jmp .gpkt_done
.gpkt_fresh:
    cmp r12,[rip+g_packet_register_skip_expr]; je .gpkt_stack_fresh
    cmp r14d,GTYPE_F32; jb .gpkt_stack_fresh
    mov rdi,r12; call g_packet_register_root
    test eax,eax; jnz .gpkt_done
.gpkt_stack_fresh: mov eax,r14d
    cmp eax,GTYPE_I64; jb .gpkt_bad
    cmp eax,GTYPE_F64; ja .gpkt_bad
    mov rdi,r12; lea rsi,[rip+gk_axis]; mov edx,gk_axis_end-gk_axis; call obj_get
    test rax,rax; jnz .gpkt_axis
    mov rdi,r12; lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gpkt_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gpkt_bad
    mov rdi,[rax+32]; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gpkt_bad
    mov rbx,rax; mov rdi,rax; call g_infer_expr
    cmp eax,r14d; jne .gpkt_scalar
    mov rdi,rbx; call g_emit_packet_expr; jmp .gpkt_done
.gpkt_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpkt_scalar
    mov r15,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpkt_scalar
    mov r13,[rax+24]; test r13,r13; jz .gpkt_scalar
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jnz .gpkt_cast
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jnz .gpkt_select
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_fma]; mov ecx,3; call span_eq
    test eax,eax; jnz .gpkt_fma
    mov rdi,r13; call g_infer_expr; mov [rsp+16],eax
    cmp eax,r14d; je 61f
    cmp r14d,GTYPE_F32; jb .gpkt_scalar
    cmp eax,GTYPE_F32; jb .gpkt_scalar
    cmp eax,GTYPE_F64; ja .gpkt_scalar
61: mov rbx,[r13+32]; test rbx,rbx; jz .gpkt_unary
    cmp qword ptr [rbx+32],0; jne .gpkt_scalar
    mov rdi,rbx; call g_infer_expr; mov [rsp+20],eax
    cmp eax,r14d; je 62f
    cmp r14d,GTYPE_F32; jb .gpkt_scalar
    cmp eax,GTYPE_F32; jb .gpkt_scalar
    cmp eax,GTYPE_F64; ja .gpkt_scalar
62: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jz 1f
    mov dword ptr [rsp],0x58; mov dword ptr [rsp+4],0xd4; jmp .gpkt_binary_ready
1:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jz 2f
    mov dword ptr [rsp],0x5c; mov dword ptr [rsp+4],0xfb; jmp .gpkt_binary_ready
2:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jz 3f
    mov dword ptr [rsp],0x59; mov dword ptr [rsp+4],0x40; jmp .gpkt_binary_ready
3:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jz .gpkt_projection_probe
    cmp r14d,GTYPE_F32; jb .gpkt_scalar
    mov dword ptr [rsp],0x5e
    jmp .gpkt_binary_ready
.gpkt_projection_probe:
    cmp r14d,GTYPE_U64; jne .gpkt_scalar
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq
    test eax,eax; jz .gpkt_scalar
    mov rdi,rbx; call g_expr_u64_literal; test edx,edx; jnz .gpkt_scalar
    mov rdi,rax; call physical_u64_lowbits_mask; test edx,edx; jz .gpkt_scalar
    mov [rsp+8],rax
    mov rdi,r13; call g_emit_packet_expr; cmp eax,r14d; jne .gpkt_bad
    mov rdi,[rsp+8]; call g_emit_mov_rax_imm64
    mov edi,GTYPE_U64; call g_emit_packet_broadcast_rax
    mov edi,1; mov esi,GTYPE_U64; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,0x25db; cmp dword ptr [rip+group_lane_factor],4; je 51f
    mov edi,0xd5db
51: xor esi,esi; xor edx,edx; mov ecx,1; call physical_encode_rrr
    mov [rsp+8],rax; lea rdi,[rsp+8]; mov esi,edx; call g_emit_bytes
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
.gpkt_binary_ready:
    cmp r14d,GTYPE_F32; jae .gpkt_binary_float
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gpkt_scalar
    cmp dword ptr [rsp+4],0x40; jne .gpkt_binary_integer
    test dword ptr [rip+isa_cap_bits],ISA_CAP_I64_MUL_NATIVE; jz .gpkt_scalar
.gpkt_binary_integer:
    mov eax,[rsp+4]; or eax,0x500
    cmp dword ptr [rsp+4],0x40; jne .gpkt_geometry
    and eax,~0x100; or eax,0x1200; jmp .gpkt_geometry
.gpkt_binary_float:
    mov eax,[rsp]; or eax,0x100
    cmp r14d,GTYPE_F64; jne .gpkt_geometry
    or eax,0x400
.gpkt_geometry:
    cmp dword ptr [rip+group_lane_factor],8; jne 4f
    cmp r14d,GTYPE_F32; je 4f
    or eax,0xc000
    or eax,0x1000
    jmp 5f
4:  or eax,0x2000
    cmp r14d,GTYPE_F32; jne 5f
    cmp dword ptr [rip+group_lane_factor],4; jne 5f
    and eax,~0x2000
5:  mov [rsp+8],eax
    cmp r14d,GTYPE_F32; jb .gpkt_binary_pair
    mov rdi,rbx; mov esi,[rsp+20]; call g_phys_fp_literal_bits
    test eax,eax; jz .gpkt_binary_left_literal
    mov [rsp+24],rdx; mov dword ptr [rsp+32],0
    mov eax,[rsp+20]; mov [rsp+36],eax; mov [rsp+40],r13
    jmp .gpkt_binary_literal
.gpkt_binary_left_literal:
    mov rdi,r13; mov esi,[rsp+16]; call g_phys_fp_literal_bits
    test eax,eax; jz .gpkt_binary_pair
    mov [rsp+24],rdx; mov dword ptr [rsp+32],1
    mov eax,[rsp+16]; mov [rsp+36],eax; mov [rsp+40],rbx
.gpkt_binary_literal:
    # The literal completes its natural precision before this consuming edge.
    cmp dword ptr [rsp+36],GTYPE_F64; jne 96f
    cmp r14d,GTYPE_F32; jne 96f
    movq xmm0,[rsp+24]; cvtsd2ss xmm0,xmm0; movd eax,xmm0; mov [rsp+24],rax
96: mov rdi,[rsp+40]; call g_infer_expr; mov [rsp+36],eax
    mov rdi,[rsp+40]; call g_emit_packet_expr; cmp eax,[rsp+36]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge; test eax,eax; jnz .gpkt_bad
    xor edi,edi; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov rdi,[rsp+24]; call g_emit_mov_rax_imm64
    mov edi,r14d; mov esi,1; call g_emit_packet_broadcast_to
    mov edi,[rsp+8]; xor esi,esi; mov edx,[rsp+32]; mov ecx,1; sub ecx,edx
    call physical_encode_rrr
    test edx,edx; jz .gpkt_bad
    mov [rsp+24],rax; lea rdi,[rsp+24]; mov esi,edx; call g_emit_bytes
    jmp .gpkt_binary_store
.gpkt_binary_pair:
    mov rdi,r13; call g_emit_packet_expr; cmp eax,[rsp+16]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    # A completed right operand already owns a frame carrier. Consume it
    # directly after the left producer, without creating an anonymous packet.
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je 97f
    cmp r14d,[rsp+20]; jne 97f
    mov rdi,rbx; mov esi,r14d; call g_phys_cse_find_resident
    cmp eax,0; jl 97f
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov eax,[rcx+rax*4]
    imul eax,[rip+group_lane_factor]; shl eax,3; mov [rsp+40],eax
    xor edi,edi; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov dword ptr [rip+g_packet_slot_memory_base],1
    mov edi,1; mov esi,r14d; mov edx,[rsp+40]; xor ecx,ecx; call g_emit_packet_simd_slot
    mov dword ptr [rip+g_packet_slot_memory_base],0
    mov edi,[rsp+8]; xor esi,esi; xor edx,edx; mov ecx,1; call physical_encode_rrr
    test edx,edx; jz .gpkt_bad
    mov [rsp+40],rax; lea rdi,[rsp+40]; mov esi,edx; call g_emit_bytes
    jmp .gpkt_binary_store
97: mov rdi,rbx; call g_emit_packet_expr; cmp eax,[rsp+20]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    mov edi,1; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    xor edi,edi; mov esi,r14d; mov edx,[rip+group_lane_factor]; shl edx,3; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,[rsp+8]; xor esi,esi; xor edx,edx; mov ecx,1; call physical_encode_rrr
    test edx,edx; jz .gpkt_bad
    mov [rsp+8],rax; mov rdi,rsp; add rdi,8; mov esi,edx; call g_emit_bytes
    mov edi,[rip+group_lane_factor]; shl edi,3; mov esi,1; call g_emit_packet_stack_adjust
.gpkt_binary_store:
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
.gpkt_fma:
    test dword ptr [rip+isa_cap_bits],ISA_CAP_FMA; jz .gpkt_scalar
    cmp r14d,GTYPE_F32; jb .gpkt_scalar
    mov rbx,r13; xor r15d,r15d
.gpkt_fma_operand:
    test rbx,rbx; jz .gpkt_bad
    mov rdi,rbx; call g_infer_expr; mov [rsp+32],eax
    mov rdi,rbx; call g_emit_packet_expr; cmp eax,[rsp+32]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge; test eax,eax; jnz .gpkt_bad
    mov rbx,[rbx+32]; inc r15d; cmp r15d,3; jb .gpkt_fma_operand
    test rbx,rbx; jnz .gpkt_bad
    mov edi,2; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,1; mov esi,r14d; mov edx,[rip+group_lane_factor]; shl edx,3; xor ecx,ecx; call g_emit_packet_simd_slot
    xor edi,edi; mov esi,r14d; mov edx,[rip+group_lane_factor]; shl edx,4; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,0x26a8
    cmp r14d,GTYPE_F32; je 92f
    or edi,0x1000
92: cmp dword ptr [rip+group_lane_factor],8; jne 93f
    cmp r14d,GTYPE_F32; je 93f
    and edi,~0x2000
    or edi,0xc000; jmp 94f
93: cmp r14d,GTYPE_F32; jne 94f
    cmp dword ptr [rip+group_lane_factor],4; jne 94f
    and edi,~0x2000
94: xor esi,esi; mov edx,1; mov ecx,2; call physical_encode_rrr
    mov [rsp+8],rax; lea rdi,[rsp+8]; mov esi,edx; call g_emit_bytes
    mov edi,[rip+group_lane_factor]; shl edi,4; mov esi,1; call g_emit_packet_stack_adjust
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
.gpkt_cast:
    cmp qword ptr [r13+32],0; jne .gpkt_scalar
    mov rdi,r13; call g_infer_expr
    cmp eax,r14d; jne 57f
    mov rdi,r13; call g_emit_packet_expr; jmp .gpkt_done
57: cmp r14d,GTYPE_F32; jae 58f
    cmp eax,GTYPE_F32; jb .gpkt_integer_bits
    cmp eax,GTYPE_F64; ja .gpkt_scalar
    cmp r14d,GTYPE_I64; jne .gpkt_scalar
    # CVTT's signed destination and invalid-result payload are the existing
    # scalar cast contract. Carrier width changes neither relation.
    test dword ptr [rip+isa_cap_bits],ISA_CAP_I64_FP_CONVERT; jz .gpkt_scalar
    cmp dword ptr [rip+group_lane_factor],8; je .gpkt_fp_to_int_ready
    test dword ptr [rip+isa_cap_bits],ISA_CAP_VECTOR_LENGTH; jz .gpkt_scalar
.gpkt_fp_to_int_ready:
    mov ebx,eax
    mov rdi,r13; call g_emit_packet_expr; cmp eax,ebx; jne .gpkt_bad
    xor edi,edi; mov esi,ebx; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,0x857a; cmp ebx,GTYPE_F32; je .gpkt_fp_to_int_width
    or edi,0x1000
.gpkt_fp_to_int_width:
    or edi,0x2000
    cmp dword ptr [rip+group_lane_factor],4; je .gpkt_fp_to_int_encode
    and edi,~0x2000; or edi,0x4000
.gpkt_fp_to_int_encode:
    xor esi,esi; xor edx,edx; xor ecx,ecx; call physical_encode_rrr
    test edx,edx; jz .gpkt_bad
    mov [rsp+8],rax; lea rdi,[rsp+8]; mov esi,edx; call g_emit_bytes
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
.gpkt_integer_bits:
    cmp eax,GTYPE_I64; jb .gpkt_scalar
    cmp eax,GTYPE_U64; ja .gpkt_scalar
    # Existing native integer casts preserve exactly the same 64 payload bits.
    mov rdi,r13; call g_emit_packet_expr; test eax,eax; jz .gpkt_bad
    mov eax,r14d; jmp .gpkt_done
58: cmp eax,GTYPE_F32; jb .gpkt_integer_to_fp
    cmp eax,GTYPE_F64; ja .gpkt_scalar
    mov ebx,eax
    mov rdi,r13; call g_emit_packet_expr; cmp eax,ebx; jne .gpkt_bad
    mov edi,ebx; mov esi,r14d; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
.gpkt_integer_to_fp:
    test dword ptr [rip+isa_cap_bits],ISA_CAP_I64_FP_CONVERT; jz .gpkt_scalar
    mov rdi,r13; call g_infer_expr; mov ebx,eax
    cmp eax,GTYPE_I64; je 52f
    cmp eax,GTYPE_U64; jne .gpkt_scalar
52: cmp dword ptr [rip+group_lane_factor],8; je 53f
    test dword ptr [rip+isa_cap_bits],ISA_CAP_VECTOR_LENGTH; jz .gpkt_scalar
53: mov rdi,r13; call g_emit_packet_expr; cmp eax,ebx; jne .gpkt_bad
    xor edi,edi; mov esi,ebx; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,0x99e6                   # VCVTQQ2PD, EVEX.128 descriptor before length
    cmp ebx,GTYPE_I64; je 54f
    mov edi,0x997a                   # VCVTUQQ2PD
54: cmp r14d,GTYPE_F64; je 55f
    mov edi,0x915b                   # VCVTQQ2PS, pp=none
    cmp ebx,GTYPE_I64; je 55f
    mov edi,0x9d7a                   # VCVTUQQ2PS, pp=F2
55: or edi,0x2000
    cmp dword ptr [rip+group_lane_factor],4; je 56f
    and edi,~0x2000; or edi,0x4000
56: xor esi,esi; xor edx,edx; xor ecx,ecx; call physical_encode_rrr
    test edx,edx; jz .gpkt_bad
    mov [rsp+8],rax; lea rdi,[rsp+8]; mov esi,edx; call g_emit_bytes
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done

.gpkt_unary:
    cmp r14d,GTYPE_F32; jb .gpkt_scalar
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jz 82f
    mov dword ptr [rsp+8],0x54; jmp .gpkt_sign_bits
82: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq
    test eax,eax; jnz .gpkt_neg_bits
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jz .gpkt_unary_square
    mov dword ptr [rsp+8],0x151; jmp .gpkt_unary_ready
.gpkt_unary_square:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq
    test eax,eax; jz .gpkt_unary_trunc
    # Square has one ValueFact input consumed twice by the multiplication
    # entity. No child recomputation and no source expression substitution.
    mov dword ptr [rsp+8],0x159; jmp .gpkt_unary_ready
.gpkt_unary_trunc:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_trunc]; mov ecx,gv_trunc_end-gv_trunc; call span_eq
    test eax,eax; jz .gpkt_unary_math
    mov dword ptr [rsp+8],0x708
    cmp r14d,GTYPE_F32; je .gpkt_unary_ready
    mov dword ptr [rsp+8],0x709; jmp .gpkt_unary_ready
.gpkt_unary_math:
    mov rdi,[r15+8]; mov rsi,[r15+16]
    mov edx,64; cmp r14d,GTYPE_F64; je 80f
    mov edx,32
80: call physical_math_fragment
    test rax,rax; jz .gpkt_scalar
    mov [rsp+40],rax; mov [rsp+48],ecx
    mov edi,edx; mov esi,64; cmp r14d,GTYPE_F64; je 81f
    mov esi,32
81: mov edx,[rip+group_lane_factor]; call physical_math_packet_fragment_by_id
    test rax,rax; jz .gpkt_unary_scalar_primitive
    mov [rsp+8],rax; mov [rsp+24],ecx; mov [rsp+32],r8d
    mov rdi,r13; call g_emit_packet_expr; cmp eax,[rsp+16]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    xor edi,edi; mov esi,[rsp+32]; call g_packet_math_preserve
    mov rdi,[rsp+8]; mov esi,[rsp+24]; call g_emit_bytes
    mov edi,1; mov esi,[rsp+32]; call g_packet_math_preserve
    mov qword ptr [rip+g_packet_last_store_end],0
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
# A scalar physical primitive consumes completed packet operands lane by lane.
# It contracts only this primitive; it never rebuilds the operand expression.
.gpkt_unary_scalar_primitive:
    mov rdi,r13; call g_emit_packet_expr; cmp eax,[rsp+16]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    xor ebx,ebx
.gpkt_primitive_lane:
    mov edi,ebx; shl edi,3; cmp r14d,GTYPE_F32; jne 83f
    mov edi,ebx; shl edi,2
83: mov esi,r14d; mov edx,1; call g_emit_packet_scalar_slot
    mov edi,0x50; call g_emit_u8
    mov rdi,[rsp+40]; mov esi,[rsp+48]; call g_emit_bytes
    call g_emit_pop_rax
    mov edi,ebx; shl edi,3; cmp r14d,GTYPE_F32; jne 84f
    mov edi,ebx; shl edi,2
84: mov esi,r14d; xor edx,edx; call g_emit_packet_scalar_slot
    inc ebx; cmp ebx,[rip+group_lane_factor]; jb .gpkt_primitive_lane
    mov qword ptr [rip+g_packet_last_store_end],0
    mov eax,r14d; jmp .gpkt_done
.gpkt_neg_bits:
    mov dword ptr [rsp+8],0x57
.gpkt_sign_bits:
    mov rdi,r13; call g_emit_packet_expr; cmp eax,[rsp+16]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge; test eax,eax; jnz .gpkt_bad
    mov edi,1; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov rdi,0x8000000000000000
    cmp r14d,GTYPE_F64; je 83f
    mov edi,0x80000000
83: cmp dword ptr [rsp+8],0x54; jne 84f
    not rdi
84: call g_emit_mov_rax_imm64
    mov edi,r14d; call g_emit_packet_broadcast_rax
    mov edi,[rsp+8]; or edi,0x2100
    cmp r14d,GTYPE_F32; je 85f
    or edi,0x400
85: cmp dword ptr [rip+group_lane_factor],8; jne 86f
    cmp r14d,GTYPE_F32; je 86f
    and edi,~0x2000; or edi,0xd000; jmp 87f
86: cmp r14d,GTYPE_F32; jne 87f
    cmp dword ptr [rip+group_lane_factor],4; jne 87f
    and edi,~0x2000
87: xor esi,esi; xor edx,edx; mov ecx,1; call physical_encode_rrr
    mov [rsp+24],rax; lea rdi,[rsp+24]; mov esi,edx; call g_emit_bytes
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
.gpkt_unary_ready:
    mov rdi,r13; call g_emit_packet_expr; cmp eax,[rsp+16]; jne .gpkt_bad
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    xor edi,edi; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov eax,[rsp+8]
    test eax,0x200; jnz 6f # ROUND map3 already carries its pp
    cmp r14d,GTYPE_F64; jne 6f
    or eax,0x400
6:  cmp dword ptr [rip+group_lane_factor],8; jne 7f
    cmp r14d,GTYPE_F32; je 7f
    or eax,0xd000; jmp 8f
7:  or eax,0x2000
    cmp r14d,GTYPE_F32; jne 8f
    cmp dword ptr [rip+group_lane_factor],4; jne 8f
    and eax,~0x2000
8:  mov edi,eax; xor esi,esi; xor edx,edx; xor ecx,ecx; call physical_encode_rrr
    test edx,edx; jz .gpkt_bad
    # Immediate belongs to the rounding entity, after the common RRR encoding.
    mov [rsp+24],rax; lea rdi,[rsp+24]; mov esi,edx; call g_emit_bytes
    test dword ptr [rsp+8],0x200; jz .gpkt_unary_store
    mov edi,3; call g_emit_u8
.gpkt_unary_store:
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
.gpkt_axis:
    mov edi,[rip+group_lane_factor]; shl edi,3; xor esi,esi; call g_emit_packet_stack_adjust
    mov edi,0xd88948; call g_emit_u24 # mov rax,rbx
    mov edi,GTYPE_U64; call g_emit_packet_broadcast_rax
    # Coordinate offsets are immutable AxisFacts in the same generated image.
    cmp dword ptr [rip+group_lane_factor],8; jne 63f
    mov edi,0xf162; call g_emit_u16; mov edi,0xfe; call g_emit_u8; mov edi,0x48; call g_emit_u8
    jmp 64f
63: mov edi,0xfec5; call g_emit_u16
64: mov edi,0x6f; call g_emit_u8; mov edi,0x0d; call g_emit_u8
    mov rax,[rip+g_packet_axis_offsets_ptr]; sub rax,[rip+g_emit_ptr]; sub rax,4
    mov edi,eax; call g_emit_u32
    mov edi,0x25d4; cmp dword ptr [rip+group_lane_factor],4; je 65f
    mov edi,0xd5d4
65: xor esi,esi; xor edx,edx; mov ecx,1; call physical_encode_rrr
    mov [rsp+8],rax; lea rdi,[rsp+8]; mov esi,edx; call g_emit_bytes
    xor edi,edi; mov esi,GTYPE_U64; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done
# Uniform control consumes only the selected arm as a packet. Mixed lanes
# retain the scalar lazy authority. The totality proof permits predicate-first
# observation; it never permits an unselected arm to execute.
.gpkt_select:
    mov rdi,r12; call g_semantic_expr_is_total; test eax,eax; jz .gpkt_scalar
    mov rbx,[r13+32]; test rbx,rbx; jz .gpkt_scalar
    mov r15,[rbx+32]; test r15,r15; jz .gpkt_scalar
    cmp qword ptr [r15+32],0; jne .gpkt_scalar
    mov [rsp+24],rbx; mov [rsp+32],r15; mov [rsp+56],r13
    mov rdi,r13; call g_semantic_expr_is_pure; test eax,eax; jz .gpkt_select_varying
    mov rdi,r13; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gpkt_bad
    call g_emit_pop_rax
    mov dword ptr [rsp+20],1; jmp .gpkt_select_mask_ready
.gpkt_select_varying:
    mov eax,[rip+group_lane_factor]; mov [rsp+20],eax
    mov rdi,r13; call g_emit_packet_compare_mask; test eax,eax; jz .gpkt_select_scalar_predicate
    mov ecx,[rip+group_lane_factor]; mov eax,1; shl eax,cl; dec eax; mov [rsp+20],eax
    jmp .gpkt_select_mask_ready
.gpkt_select_scalar_predicate:
    mov edi,8; xor esi,esi; call g_emit_packet_stack_adjust
    xor edi,edi; call g_emit_mov_rax_imm64
    xor edi,edi; mov esi,GTYPE_U64; xor edx,edx; call g_emit_packet_scalar_slot
    xor r13d,r13d
.gpkt_select_predicate:
    lea rdi,[rip+gc_mov_r10_rbx]; mov esi,gc_mov_r10_rbx_end-gc_mov_r10_rbx; call g_emit_bytes
    test r13d,r13d; jz 81f
    mov edi,0xc28349; call g_emit_u24; mov edi,r13d; call g_emit_u8
81: mov [rip+g_packet_scalar_lane],r13d
    mov rdi,[rsp+56]; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gpkt_bad
    call g_emit_pop_rax
    mov edi,0xc08548; call g_emit_u24 # test rax,rax
    mov edi,0xc0950f; call g_emit_u24 # setne al
    mov edi,0xc0b60f; call g_emit_u24 # movzx eax,al
    mov edi,0x24040148; call g_emit_u32 # add [rsp],rax
    inc r13d; cmp r13d,[rip+group_lane_factor]; jb .gpkt_select_predicate
    xor edi,edi; mov esi,GTYPE_U64; mov edx,1; call g_emit_packet_scalar_slot
    mov edi,8; mov esi,1; call g_emit_packet_stack_adjust
.gpkt_select_mask_ready:
    mov edi,0xc08548; call g_emit_u24
    call g_emit_jz_patch; mov [rsp+40],rax
    mov edi,0x3d; call g_emit_u8; mov edi,[rsp+20]; call g_emit_u32
    mov edi,0x850f; call g_emit_u16
    mov rax,[rip+g_emit_ptr]; mov [rsp+48],rax; xor edi,edi; call g_emit_u32
    call g_packet_fact_mixed_meet
    inc dword ptr [rip+g_packet_fact_scope]
    mov rdi,[rsp+24]; call g_emit_packet_expr; mov esi,r14d; mov edi,eax; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    call g_packet_fact_scope_leave
    call g_emit_jmp_patch; mov [rsp+24],rax
    mov rdi,[rsp+40]; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    mov qword ptr [rip+g_packet_last_store_end],0
    inc dword ptr [rip+g_packet_fact_scope]
    mov rdi,[rsp+32]; call g_emit_packet_expr; mov esi,r14d; mov edi,eax; call g_emit_packet_fp_edge
    test eax,eax; jnz .gpkt_bad
    call g_packet_fact_scope_leave
    call g_emit_jmp_patch; mov [rsp+32],rax
    mov rdi,[rsp+48]; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    mov qword ptr [rip+g_packet_last_store_end],0
    cmp dword ptr [rip+g_packet_mixed_enabled],0; je .gpkt_select_local_mixed
    call g_emit_jmp_patch
    mov rdx,[rip+g_packet_mixed_head]; test rdx,rdx; jz 95f
    sub rdx,rax
95: mov [rax],edx; mov [rip+g_packet_mixed_head],rax
    jmp .gpkt_select_mixed_done
.gpkt_select_local_mixed:
    mov rdi,r12; mov esi,r14d; call g_emit_packet_scalar_expr
    cmp eax,r14d; jne .gpkt_bad
.gpkt_select_mixed_done:
    mov rdi,[rsp+24]; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    mov rdi,[rsp+32]; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    mov qword ptr [rip+g_packet_last_store_end],0
    inc dword ptr [rip+g_packet_native_nodes]
    mov eax,r14d; jmp .gpkt_done

.gpkt_scalar:
    mov rdi,r12; mov esi,r14d; call g_emit_packet_scalar_expr
    jmp .gpkt_done

# The scalar carrier is also the mixed-control contraction.
g_emit_packet_scalar_expr:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,64
    mov r12,rdi; mov r14d,esi
    mov edi,[rip+group_lane_factor]; shl edi,3; xor esi,esi; call g_emit_packet_stack_adjust
    mov rdi,r12; call g_semantic_expr_is_pure; mov [rsp+4],eax
    xor r13d,r13d
.gpkt_scalar_lane:
    cmp r13d,0; je 12f
    cmp dword ptr [rsp+4],1; je 13f
12: lea rdi,[rip+gc_mov_r10_rbx]; mov esi,gc_mov_r10_rbx_end-gc_mov_r10_rbx; call g_emit_bytes
    test r13d,r13d; jz 9f
    mov edi,0xc28349; call g_emit_u24
    mov edi,r13d; call g_emit_u8
9:  mov [rip+g_packet_scalar_lane],r13d
    mov rdi,r12; mov esi,r14d; call g_emit_packet_scalar_value
    cmp eax,r14d; jne .gpkt_scalar_bad
    cmp dword ptr [rsp+4],1; jne 13f
    mov edi,r14d; call g_emit_packet_broadcast_rax
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    mov eax,r14d; jmp .gpkt_scalar_done
13: mov edi,r13d; shl edi,3; cmp r14d,GTYPE_F32; jne 10f
    mov edi,r13d; shl edi,2
10: mov esi,r14d; xor edx,edx; call g_emit_packet_scalar_slot
    inc r13d; cmp r13d,[rip+group_lane_factor]; jb .gpkt_scalar_lane
    mov eax,r14d; jmp .gpkt_scalar_done
.gpkt_scalar_bad: xor eax,eax
.gpkt_scalar_done:
    add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; ret
.gpkt_bad: xor eax,eax
.gpkt_done:
    test eax,eax; jz 994f
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je 994f
    mov rdi,r12; mov esi,r14d; call g_packet_fact_retain
    mov eax,r14d
994: add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Native relation produces one bit per independent lane in runtime EAX.
# BOOL remains a control value; its arithmetic children retain their own meet.
g_emit_packet_compare_mask:
    push rbx; push r12; push r13; push r14; push r15; sub rsp,40
    mov r12,rdi; mov rax,[rip+g_emit_ptr]; mov [rsp+24],rax
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpcm_no
    mov r15,rax
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq; test eax,eax; jnz .gpcm_eq
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq; test eax,eax; jnz .gpcm_ne
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gpcm_lt
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq; test eax,eax; jnz .gpcm_le
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq; test eax,eax; jnz .gpcm_gt
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gpcm_ge
    jmp .gpcm_no
.gpcm_eq: mov dword ptr [rsp],0; jmp .gpcm_args
.gpcm_ne: mov dword ptr [rsp],4; jmp .gpcm_args
.gpcm_lt: mov dword ptr [rsp],1; jmp .gpcm_args
.gpcm_le: mov dword ptr [rsp],2; jmp .gpcm_args
.gpcm_gt: mov dword ptr [rsp],30; jmp .gpcm_args
.gpcm_ge: mov dword ptr [rsp],29; jmp .gpcm_args
.gpcm_args:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpcm_no
    mov r13,[rax+24]; test r13,r13; jz .gpcm_no
    mov rbx,[r13+32]; test rbx,rbx; jz .gpcm_no
    cmp qword ptr [rbx+32],0; jne .gpcm_no
    mov rdi,r13; call g_infer_expr; mov [rsp+4],eax
    cmp eax,GTYPE_F32; jb .gpcm_no; cmp eax,GTYPE_F64; ja .gpcm_no
    mov r14d,eax
    mov rdi,rbx; call g_infer_expr; mov [rsp+8],eax
    cmp eax,GTYPE_F32; jb .gpcm_no; cmp eax,GTYPE_F64; ja .gpcm_no
    cmp eax,r14d; jae 88f
    mov r14d,eax
88: mov rdi,r13; call g_emit_packet_expr; cmp eax,[rsp+4]; jne .gpcm_no
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge; test eax,eax; jnz .gpcm_no
    mov rdi,rbx; call g_emit_packet_expr; cmp eax,[rsp+8]; jne .gpcm_no
    mov edi,eax; mov esi,r14d; call g_emit_packet_fp_edge; test eax,eax; jnz .gpcm_no
    mov edi,1; mov esi,r14d; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    xor edi,edi; mov esi,r14d; mov edx,[rip+group_lane_factor]; shl edx,3; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,0x21c2; xor esi,esi
    cmp r14d,GTYPE_F32; je 89f
    or edi,0x400
89: cmp dword ptr [rip+group_lane_factor],8; jne 90f
    cmp r14d,GTYPE_F32; je 90f
    and edi,~0x2000; or edi,0xd000; mov esi,1; jmp 91f
90: cmp r14d,GTYPE_F32; jne 91f
    cmp dword ptr [rip+group_lane_factor],4; jne 91f
    and edi,~0x2000
91: xor edx,edx; mov ecx,1; call physical_encode_rrr
    test edx,edx; jz .gpcm_no
    mov [rsp+16],rax; lea rdi,[rsp+16]; mov esi,edx; call g_emit_bytes
    mov edi,[rsp]; call g_emit_u8
    cmp dword ptr [rip+group_lane_factor],8; jne .gpcm_vector_mask
    cmp r14d,GTYPE_F32; je .gpcm_vector_mask
    mov edi,0xc193f8c5; call g_emit_u32 # kmovw eax,k1
    jmp .gpcm_release
.gpcm_vector_mask:
    mov edi,0xfc; cmp r14d,GTYPE_F32; je 92f
    mov edi,0xfd
92: cmp r14d,GTYPE_F32; jne 93f
    cmp dword ptr [rip+group_lane_factor],4; jne 93f
    mov edi,0xf8
93: shl edi,8; or edi,0xc5; call g_emit_u16
    mov edi,0xc050; call g_emit_u16 # vmovmskps/pd eax, vector0
.gpcm_release:
    mov edi,[rip+group_lane_factor]; shl edi,4; mov esi,1; call g_emit_packet_stack_adjust
    mov qword ptr [rip+g_packet_last_store_end],0
    mov eax,1; jmp .gpcm_done
.gpcm_no:
    mov rax,[rsp+24]; mov [rip+g_emit_ptr],rax
    mov qword ptr [rip+g_packet_last_store_end],0
    xor eax,eax
.gpcm_done: add rsp,40; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# One mixed-control contraction belongs to the whole total packet root.
# Every inner edge shares this continuation instead of cloning its scalar DAG.
# R12 is the established packet frame base, so discarded operand carriers have
# one exact restore point. Values may be recomputed only under totality proof.
g_emit_packet_root:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    mov dword ptr [rip+g_packet_mixed_enabled],0
    mov qword ptr [rip+g_packet_mixed_head],0
    mov dword ptr [rip+g_packet_mixed_seen],0
    call g_semantic_expr_is_total
    mov [rip+g_packet_mixed_enabled],eax
    mov rdi,r12; call g_emit_packet_expr; mov r14d,eax
    test eax,eax; jz .gproot_done
    cmp qword ptr [rip+g_packet_mixed_head],0; je .gproot_done
    call g_emit_jmp_patch; mov r13,rax
    mov rbx,[rip+g_packet_mixed_head]
.gproot_patch:
    movsxd rax,dword ptr [rbx]; test eax,eax; jz 96f
    add rax,rbx
96: push rax
    mov rdi,rbx; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    pop rbx; test rbx,rbx; jnz .gproot_patch
    mov edi,0xe4894c; call g_emit_u24 # mov rsp,r12
    mov qword ptr [rip+g_packet_last_store_end],0
    mov rdi,[rip+g_packet_fact_scope_ptr]; mov rsi,[rip+g_packet_fact_mixed_ptr]
    mov ecx,[rip+g_phys_cse_resident_count]; rep movsd
    mov rdi,r12; mov esi,r14d; call g_emit_packet_scalar_expr
    cmp eax,r14d; jne .gproot_done
    mov rdi,r13; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    mov qword ptr [rip+g_packet_last_store_end],0
    mov eax,r14d
.gproot_done:
    mov dword ptr [rip+g_packet_mixed_enabled],0
    mov qword ptr [rip+g_packet_mixed_head],0
    pop r14; pop r13; pop r12; pop rbx; ret

# Natural child precision is completed first; only this consumption edge
# converts the packet. This is the same local meet as the scalar authority.
g_emit_packet_fp_edge:
    cmp edi,esi; je .gpfe_ok
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp edi,GTYPE_F32; jb .gpfe_bad
    cmp edi,GTYPE_F64; ja .gpfe_bad
    cmp esi,GTYPE_F32; jb .gpfe_bad
    cmp esi,GTYPE_F64; ja .gpfe_bad
    xor edi,edi; mov esi,ebx; xor edx,edx; xor ecx,ecx; call g_emit_packet_simd_slot
    mov edi,0x215a
    cmp ebx,GTYPE_F32; je 1f
    mov edi,0x255a
1:  cmp dword ptr [rip+group_lane_factor],4; je 2f
    mov edi,0xc15a
    cmp ebx,GTYPE_F32; je 2f
    mov edi,0xd55a
2:  xor esi,esi; xor edx,edx; xor ecx,ecx; call physical_encode_rrr
    test edx,edx; jz .gpfe_bad
    sub rsp,8; mov [rsp],rax; mov rdi,rsp; mov esi,edx; call g_emit_bytes; add rsp,8
    xor edi,edi; mov esi,r12d; xor edx,edx; mov ecx,1; call g_emit_packet_simd_slot
    pop r12; pop rbx
.gpfe_ok: xor eax,eax; ret
.gpfe_bad: pop r12; pop rbx; mov eax,1; ret

# Broadcast is an operand form of an invocation-immutable ValueFact.
g_emit_packet_broadcast_rax:
    xor esi,esi
# edi=natural type, esi=destination. Broadcast is a register operand form;
# literal operands need no anonymous stack carrier or restoration episode.
g_emit_packet_broadcast_to:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov edi,r12d; mov esi,GTYPE_F64
    cmp ebx,GTYPE_F32; jne 1f
    mov esi,GTYPE_F32
1:  call g_emit_phys_xmm_from_rax
    mov edi,0x2659
    cmp ebx,GTYPE_F32; jne 2f
    mov edi,0x2658
    cmp dword ptr [rip+group_lane_factor],4; jne 3f
    and edi,~0x2000; jmp 3f
2:  cmp dword ptr [rip+group_lane_factor],8; jne 3f
    mov edi,0xd659
3:  mov esi,r12d; xor edx,edx; mov ecx,r12d
    call physical_encode_rrr
    test edx,edx; jz 4f
    sub rsp,8; mov [rsp],rax
    mov rdi,rsp; mov esi,edx; call g_emit_bytes
    add rsp,8; pop r12; pop rbx; ret
4:  mov eax,1; pop r12; pop rbx; ret

# Scalar degeneration uses the old register DAG, including range and constant
# proofs. Stack materialization is used only when that primitive lacks a carrier.
g_emit_packet_scalar_value:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov ebx,esi
    mov r13,[rip+g_emit_ptr]; mov r14,[rip+g_runtime_temp_bytes_used]
    # All live packet values already own memory carriers at scalar contraction.
    # Live packet registers retain their upper payload across scalar leaves.
    mov dword ptr [rip+g_phys_stack_episode],2
    call g_phys_int_temp_reset
    call g_phys_fp_temp_reset
    mov rdi,r12; mov edx,ebx
    cmp ebx,GTYPE_F32; jae 1f
    mov esi,8; call g_emit_phys_int_expr_to
    cmp eax,ebx; jne 2f
    xor edi,edi; mov esi,8; call g_emit_phys_gpr_move; jmp 3f
1:  xor esi,esi; call g_emit_phys_fp_expr_to
    cmp eax,ebx; jne 2f
    xor edi,edi; mov esi,ebx; call g_emit_phys_xmm_to_rax; jmp 3f
2:  mov qword ptr [rip+g_packet_last_store_end],0
    mov [rip+g_emit_ptr],r13; mov [rip+g_runtime_temp_bytes_used],r14
    mov dword ptr [rip+g_phys_stack_episode],0
    mov rdi,r12; call g_emit_expr; cmp eax,ebx; jne 4f
    call g_emit_pop_rax
3:  mov eax,ebx
4:  mov dword ptr [rip+g_phys_stack_episode],0
    pop r14; pop r13; pop r12; pop rbx; ret

# Physical probe closes the candidate before emission. Failure contracts this
# same expression to the established scalar episode, never retries a backend.
g_prepare_packet_episode:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi
    mov dword ptr [rip+g_packet_ready],0
    mov dword ptr [rip+group_lane_factor],1
    mov dword ptr [rip+g_packet_native_nodes],0
    mov dword ptr [rip+g_phys_cse_memory_carrier],0
    mov rdi,rbx; call g_phys_identity_axis_episode; test eax,eax; jz .gppepr_done
    mov rdi,rbx; call g_infer_expr; mov r14d,eax
    cmp eax,GTYPE_I64; jb .gppepr_done
    cmp eax,GTYPE_F64; ja .gppepr_done
    test dword ptr [rip+isa_cap_bits],ISA_CAP_VEC256_FP; jz .gppepr_done
    test dword ptr [rip+isa_cap_bits],ISA_CAP_VEC256_INT; jz .gppepr_done
    mov dword ptr [rip+g_packet_ready],1
    mov dword ptr [rip+group_lane_factor],4
    test dword ptr [rip+isa_cap_bits],ISA_CAP_VEC512; jz 1f
    mov dword ptr [rip+group_lane_factor],8
1:  mov dword ptr [rip+g_phys_stack_episode],0
    call g_phys_fp_geometry_refresh
    mov dword ptr [rip+g_phys_fp_reserved_mask],15
    mov dword ptr [rip+g_phys_int_reserved_mask],(1<<11)|(1<<12)
    mov dword ptr [rip+g_phys_cse_resident_count],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov dword ptr [rip+g_phys_const_resident_count],0
    mov qword ptr [rip+g_packet_register_skip_expr],0
    mov dword ptr [rip+g_packet_register_live],0
    mov dword ptr [rip+g_packet_register_mask],0xfff0
    mov r12,[rip+g_emit_ptr]; mov r13,[rip+g_runtime_temp_bytes_used]
    mov rdi,rbx; call g_emit_packet_root
    mov qword ptr [rip+g_packet_last_store_end],0
    mov [rip+g_emit_ptr],r12; mov [rip+g_runtime_temp_bytes_used],r13
    cmp eax,r14d; jne .gppepr_contract
    cmp dword ptr [rip+g_packet_native_nodes],0; jne .gppepr_done
.gppepr_contract:
    mov dword ptr [rip+g_packet_ready],0
    mov dword ptr [rip+group_lane_factor],1
.gppepr_done:
    cmp dword ptr [rip+g_packet_ready],0; je .gppepr_group
    mov dword ptr [rip+g_phys_cse_memory_carrier],1
    mov dword ptr [rip+g_phys_stack_episode],1
    mov dword ptr [rip+g_phys_cse_candidate_count],0
    mov rdi,rbx; mov esi,r14d; call g_phys_cse_note_tree
    mov [rip+g_phys_plan_root],rbx
    call g_phys_cse_finalize
    call g_phys_cse_order_dependencies
    cmp dword ptr [rip+g_phys_cse_resident_count],0; jne 994f
    # Carrier kind follows actual residency, not packet admission.
    mov dword ptr [rip+g_phys_cse_memory_carrier],0
994: mov dword ptr [rip+g_phys_stack_episode],0
.gppepr_group:
    mov dword ptr [rip+group_logical_rank],1
    mov dword ptr [rip+group_relation_mask],GF_REL_INDEPENDENT|GF_REL_REDUCTION|GF_REL_OPERATOR
    mov dword ptr [rip+group_body_factor],1
    mov dword ptr [rip+group_carrier_factor],1
    call synthesize_group_fact
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=reduce node, esi=natural type. Emit full packets followed by the same
# scalar tail. A sequential FP reduction never acquires a tree reassociation.
g_emit_packet_reduce_prefix:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r14d,esi
    cmp dword ptr [rip+g_packet_ready],0; je .gprp_ok
    # Memory carriers must obey the same target alignment as their SIMD width.
    # R12 owns the saved stack frame and is excluded from anonymous GPR birth.
    mov edi,0x5441; call g_emit_u16 # push r12
    mov edi,0xe48949; call g_emit_u24 # mov r12,rsp
    mov edi,0xe48348; call g_emit_u24 # and rsp,-64
    mov edi,0xc0; call g_emit_u8
    # A restore-pointer header occupies one alignment unit. Pushing only one
    # qword would misalign every following packet and break store forwarding.
    mov edi,64; xor esi,esi; call g_emit_packet_stack_adjust
    mov edi,0x2424894c; call g_emit_u32 # mov [rsp],r12 = saved stack pointer
    mov edi,[rip+g_phys_cse_resident_count]
    imul edi,dword ptr [rip+group_lane_factor]; shl edi,3
    xor esi,esi; call g_emit_packet_stack_adjust
    mov edi,0xe48949; call g_emit_u24 # mov r12,rsp: common frame carrier base
    # One immutable coordinate-offset fact, outside the packet control edge.
    mov edi,0xe9; call g_emit_u8
    mov r13,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32
    mov rax,[rip+g_emit_ptr]; mov [rip+g_packet_axis_offsets_ptr],rax
    xor ebx,ebx
66: mov edi,ebx; call g_emit_u64
    inc ebx; cmp ebx,[rip+group_lane_factor]; jb 66b
    mov rdi,r13; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    mov rdi,[rip+g_packet_fact_scope_ptr]
    mov ecx,[rip+g_phys_cse_resident_count]; xor eax,eax; rep stosd
    mov dword ptr [rip+g_packet_fact_scope],1
    mov qword ptr [rip+g_packet_register_skip_expr],0
    mov dword ptr [rip+g_packet_register_live],0
    mov eax,[rip+g_phys_fp_all_mask]
    and eax,0x0000fff0    # VEX packet operands own the architectural low bank.
    mov [rip+g_packet_register_mask],eax
    # Invocation-invariant facts dominate the Axis loop and are realized once.
    mov rdi,r12; call g_packet_emit_invariants
    mov r15,[rip+g_emit_ptr]
    # remaining=extent-index, so no extent+width overflow is possible.
    mov edi,0x8948; call g_emit_u16; mov edi,0xe8; call g_emit_u8 # mov rax,rbp
    mov edi,0x2948; call g_emit_u16; mov edi,0xd8; call g_emit_u8 # sub rax,rbx
    mov edi,0xf88348; call g_emit_u24; mov edi,[rip+group_lane_factor]; call g_emit_u8
    mov edi,0x820f; call g_emit_u16
    mov r13,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32
    mov dword ptr [rip+g_phys_cse_ready_count],0
.gprp_retained_done:
    mov rdi,r12; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    mov rdi,rax; call g_emit_packet_root; cmp eax,r14d; jne .gprp_bad
    cmp r14d,GTYPE_F32; jae .gprp_ordered_fold
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gprp_ordered_fold
    # Integer wrapping addition is an associative modular relation. Only this
    # proven fold may contract to a horizontal carrier reduction.
    cmp dword ptr [rip+group_lane_factor],8; jne 20f
    lea rdi,[rip+gc_packet_fold8]; mov esi,gc_packet_fold8_end-gc_packet_fold8; call g_emit_bytes
    jmp .gprp_fold_done
20: lea rdi,[rip+gc_packet_fold4]; mov esi,gc_packet_fold4_end-gc_packet_fold4; call g_emit_bytes
    jmp .gprp_fold_done
.gprp_ordered_fold:
    cmp r14d,GTYPE_F32; jb .gprp_scalar_ordered_fold
    # The strict fold consumes the completed payload once, in original lane
    # order. An adjacent producer transfers its register instead of spilling.
    xor edi,edi; mov esi,r14d; xor edx,edx; mov ecx,2; call g_emit_packet_simd_slot
    mov edx,eax
    mov edi,64; cmp r14d,GTYPE_F64; je 99f
    mov edi,32
99: mov esi,[rip+group_lane_factor]; call physical_strict_fold_fragment
    test rax,rax; jz .gprp_bad
    mov rdi,rax; mov esi,ecx; call g_emit_bytes
    jmp .gprp_fold_done
.gprp_scalar_ordered_fold:
    xor ebx,ebx
.gprp_fold:
    mov edi,ebx; shl edi,3; cmp r14d,GTYPE_F32; jne 1f
    mov edi,ebx; shl edi,2
1:  mov esi,r14d; mov edx,1; call g_emit_packet_scalar_slot
    mov edi,r14d; call g_emit_reduce_sum_step; test eax,eax; jnz .gprp_bad
    inc ebx; cmp ebx,[rip+group_lane_factor]; jb .gprp_fold
.gprp_fold_done:
    mov edi,[rip+group_lane_factor]; shl edi,3; mov esi,1; call g_emit_packet_stack_adjust
    mov edi,0xc38348; call g_emit_u24; mov edi,[rip+group_lane_factor]; call g_emit_u8
    mov edi,0xe9; call g_emit_u8
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; mov rdx,r15; sub rdx,rcx
    mov edi,edx; call g_emit_u32
    mov rdi,r13; mov rsi,[rip+g_emit_ptr]; call g_patch_rel32
    mov edi,0xa48b49; call g_emit_u24 # mov rsp,[r12+cache_bytes]
    mov edi,0x24; call g_emit_u8
    mov edi,[rip+g_phys_cse_resident_count]
    imul edi,dword ptr [rip+group_lane_factor]; shl edi,3; call g_emit_u32
    mov edi,0x5c41; call g_emit_u16 # pop r12
    mov dword ptr [rip+g_phys_cse_memory_carrier],0
    mov dword ptr [rip+g_phys_cse_resident_count],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
.gprp_ok: xor eax,eax; jmp .gprp_done
.gprp_bad: mov eax,1
.gprp_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

.pushsection .rodata
# Native fragments use the same operand and modulo-2^64 contract at every width.
gc_packet_fold8:
    vmovdqu64 zmm0,[rsp]
    vextracti64x4 ymm1,zmm0,1
    vpaddq ymm0,ymm0,ymm1
    vextracti128 xmm1,ymm0,1
    vpaddq xmm0,xmm0,xmm1
    vpsrldq xmm1,xmm0,8
    vpaddq xmm0,xmm0,xmm1
    vmovq rax,xmm0
    add r11,rax
 gc_packet_fold8_end:
gc_packet_fold4:
    vmovdqu ymm0,[rsp]
    vextracti128 xmm1,ymm0,1
    vpaddq xmm0,xmm0,xmm1
    vpsrldq xmm1,xmm0,8
    vpaddq xmm0,xmm0,xmm1
    vmovq rax,xmm0
    add r11,rax
 gc_packet_fold4_end:
.popsection

.bss
.p2align 3
g_packet_mixed_head:.skip 8
g_packet_mixed_enabled:.skip 4
.p2align 3
g_packet_last_store_end:.skip 8
g_packet_last_store_start:.skip 8
g_packet_last_store_type:.skip 4
g_packet_last_store_offset:.skip 4
g_packet_last_store_base:.skip 4
g_packet_last_store_reg:.skip 4
.text

.text
.include "compiler/physical_packet_facts.inc"
