# Wheelchair tensor frontend profile-shared bodies.
# A body exists here only when participating physical profiles have identical assembly semantics.

.macro TFP_02_tolerant_recip_f64_bits
    mov rcx,rax
    mov rdx,rcx
    btr rdx,63
    test rdx,rdx
    jz .trf_no
    mov r8,rdx
    shr r8,52
    and r8d,0x7ff
    cmp r8d,0x7ff
    je .trf_no
    movq xmm0,rcx
    sub rsp,16
    stmxcsr dword ptr [rsp]
    mov dword ptr [rsp+4],0x1f80
    ldmxcsr dword ptr [rsp+4]
    mov rcx,0x3ff0000000000000
    movq xmm1,rcx
    divsd xmm1,xmm0
    movq rax,xmm1
    ldmxcsr dword ptr [rsp]
    add rsp,16
    mov rcx,rax
    shr rcx,52
    and ecx,0x7ff
    test ecx,ecx
    jz .trf_no
    cmp ecx,0x7ff
    je .trf_no
    xor edx,edx
    ret
.trf_no:
    xor eax,eax
    mov edx,1
    ret

# gen_load_f64_bits(edi=xmm, rsi=bits)
.endm

.macro TFP_02_emit_int_reg
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13d,esi
    # literal
    mov rdi,r12; call expr_literal_u64
    test edx,edx
    jnz .eir_axis
    mov rsi,rax; mov edi,r13d; call gen_mov_ri64
    xor eax,eax; jmp .eir_done
.eir_axis:
    mov rdi,r12; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .eir_var
    mov edi,r13d; mov esi,8; call gen_mov_rr
    xor eax,eax; jmp .eir_done
.eir_var:
    mov rdi,r12; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eir_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_domain_var_match
    test eax,eax; jz .eir_fail
    mov edi,r13d; mov esi,9; call gen_mov_rr
    xor eax,eax; jmp .eir_done
.eir_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eir_fail
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eir_fail
    mov r15,[rax+24]; test r15,r15; jz .eir_fail
    # One PredicateFact relation family for integer and floating values.
    # The operand type chooses only the physical compare recipe.
    xor ebx,ebx
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax; jz .eir_cmp_ne; mov ebx,0x94; jmp .eir_compare
.eir_cmp_ne:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ne]; mov ecx,v_ne_end-v_ne; call span_eq
    test eax,eax; jz .eir_cmp_lt; mov ebx,0x95; jmp .eir_compare
.eir_cmp_lt:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_lt]; mov ecx,v_lt_end-v_lt; call span_eq
    test eax,eax; jz .eir_cmp_le; mov ebx,0x92; jmp .eir_compare
.eir_cmp_le:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_le]; mov ecx,v_le_end-v_le; call span_eq
    test eax,eax; jz .eir_cmp_gt; mov ebx,0x96; jmp .eir_compare
.eir_cmp_gt:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_gt]; mov ecx,v_gt_end-v_gt; call span_eq
    test eax,eax; jz .eir_cmp_ge; mov ebx,0x97; jmp .eir_compare
.eir_cmp_ge:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ge]; mov ecx,v_ge_end-v_ge; call span_eq
    test eax,eax; jz .eir_select; mov ebx,0x93
.eir_compare:
    push rbx                       # relation code
    mov rbx,[r15+32]
    test rbx,rbx
    jz .eir_compare_drop_fail
    mov rdi,r15
    call expr_is_float_value
    test eax,eax
    jz .eir_compare_int
    call alloc_xmm; cmp eax,-1; je .eir_compare_drop_fail; mov r12d,eax
    call alloc_xmm; cmp eax,-1; je .eir_compare_fp_free_lhs_fail; mov r14d,eax
    mov rdi,r15; mov esi,r12d; call emit_float_reg; test eax,eax; jnz .eir_compare_fp_free2_fail
    mov rdi,rbx; mov esi,r14d; call emit_float_reg; test eax,eax; jnz .eir_compare_fp_free2_fail
    pop rcx
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call gen_ucomisd_setcc
    mov edi,r14d; call free_xmm
    mov edi,r12d; call free_xmm
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax; jmp .eir_done
.eir_compare_fp_free2_fail:
    mov edi,r14d; call free_xmm
.eir_compare_fp_free_lhs_fail:
    mov edi,r12d; call free_xmm
    add rsp,8
    jmp .eir_fail
.eir_compare_int:
    call alloc_gpr; cmp eax,-1; je .eir_compare_drop_fail; mov r12d,eax
    call alloc_gpr; cmp eax,-1; je .eir_compare_int_free_lhs_fail; mov r14d,eax
    mov rdi,r15; mov esi,r12d; call emit_int_reg; test eax,eax; jnz .eir_compare_int_free2_fail
    mov rdi,rbx; mov esi,r14d; call emit_int_reg; test eax,eax; jnz .eir_compare_int_free2_fail
    pop rcx
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call gen_cmp_setcc
    mov edi,r14d; call free_gpr
    mov edi,r12d; call free_gpr
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax; jmp .eir_done
.eir_compare_int_free2_fail:
    mov edi,r14d; call free_gpr
.eir_compare_int_free_lhs_fail:
    mov edi,r12d; call free_gpr
.eir_compare_drop_fail:
    add rsp,8
    jmp .eir_fail
.eir_select:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .eir_mod
    call alloc_gpr; cmp eax,-1; je .eir_fail; mov ebx,eax # cond
    call alloc_gpr; cmp eax,-1; je .eir_free_b_fail; mov r14d,eax # false
    mov rdi,r15; mov esi,ebx; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov r15,[r15+32]; test r15,r15; jz .eir_free2_fail
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov r15,[r15+32]; test r15,r15; jz .eir_free2_fail
    mov rdi,r15; mov esi,r14d; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov edi,ebx; call gen_test_rr
    mov edi,r13d; mov esi,r14d; call gen_cmovz
    mov edi,r14d; call free_gpr; mov edi,ebx; call free_gpr
    inc dword ptr [rip+schedule_counts+4*4] # int compare
    xor eax,eax; jmp .eir_done
.eir_mod:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .eir_binary
    mov rbx,[r15+32]; test rbx,rbx; jz .eir_fail
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .eir_mod_general
    test rax,rax; jz .eir_fail
    mov rcx,rax; dec rcx
    test rax,rcx; jnz .eir_mod_general
    mov r12,rcx
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_fail
    mov edi,4; mov esi,r13d; mov edx,r12d; call gen_alu_ri32
    inc dword ptr [rip+schedule_counts+4*4] # int ALU
    xor eax,eax; jmp .eir_done
.eir_mod_general:
    # numerator -> RAX, divisor -> temporary, div, remainder -> dst
    mov rdi,r15; xor esi,esi; call emit_int_reg; test eax,eax; jnz .eir_fail
    call alloc_gpr; cmp eax,-1; je .eir_fail; mov ebx,eax
    mov rdi,[r15+32]; mov esi,ebx; call emit_int_reg; test eax,eax; jnz .eir_free_b_fail
    # xor rdx,rdx
    mov edi,0x31; mov esi,2; mov edx,2; call gen_rr_opcode
    mov edi,ebx; call gen_div_reg
    mov edi,r13d; mov esi,2; call gen_mov_rr
    mov edi,ebx; call free_gpr
    inc dword ptr [rip+schedule_counts+4*6] # int div/mod
    xor eax,eax; jmp .eir_done
.eir_binary:
    # classify op in r14d
    xor ebx,ebx
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz 1f; mov ebx,1; jmp 4f
1:  mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz 2f; mov ebx,2; jmp 4f
2:  mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz .eir_fail; mov ebx,3
4:
    mov r14,[r15+32]; test r14,r14; jz .eir_fail
    # literal rhs fast path
    mov rdi,r14; call expr_literal_u64
    test edx,edx; jnz .eir_bin_reg
    mov r12,rax
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_fail
    cmp ebx,3; je .eir_mul_imm
    mov edi,0; cmp ebx,1; je 5f; mov edi,5
5:  mov esi,r13d; mov edx,r12d; call gen_alu_ri32
    inc dword ptr [rip+schedule_counts+4*4] # int ALU
    xor eax,eax; jmp .eir_done
.eir_mul_imm:
    mov edi,r13d; mov esi,r13d; mov edx,r12d; call gen_imul_ri32
    inc dword ptr [rip+schedule_counts+4*5] # int multiply
    xor eax,eax; jmp .eir_done
.eir_bin_reg:
    call alloc_gpr; cmp eax,-1; je .eir_fail; mov r12d,eax
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_free_r12_fail
    mov rdi,r14; mov esi,r12d; call emit_int_reg; test eax,eax; jnz .eir_free_r12_fail
    cmp ebx,3; je .eir_mul_reg
    mov edi,0x01; cmp ebx,1; je 6f; mov edi,0x29
6:  mov esi,r13d; mov edx,r12d; call gen_rr_opcode
    inc dword ptr [rip+schedule_counts+4*4] # int ALU
    jmp .eir_free_r12_ok
.eir_mul_reg:
    mov edi,r13d; mov esi,r12d; call gen_imul_rr
    inc dword ptr [rip+schedule_counts+4*5] # int multiply
.eir_free_r12_ok:
    mov edi,r12d; call free_gpr
    xor eax,eax; jmp .eir_done
.eir_free_r12_fail:
    mov edi,r12d; call free_gpr
    jmp .eir_fail
.eir_free2_fail:
    mov edi,r14d; call free_gpr
.eir_free_b_fail:
    mov edi,ebx; call free_gpr
.eir_fail:
    mov eax,1
.eir_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# emit_float_reg(rdi=expr object, esi=dst xmm) -> eax=0/1
.endm

.macro TFP_023_vec_emit_bytes
    mov rax,[rip+vec_emit_ptr]
    mov ecx,esi
    lea rdx,[rax+rcx]
    cmp rdx,[rip+vec_emit_end]
    jbe .tcgrow_ok_7
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .veb_fail
.tcgrow_ok_7:
.veb_loop:
    test ecx,ecx
    jz .veb_done
    mov r8b,[rdi]
    mov [rax],r8b
    inc rdi
    inc rax
    dec ecx
    jmp .veb_loop
.veb_done:
    mov [rip+vec_emit_ptr],rax
    xor eax,eax
    ret
.veb_fail: mov eax,1; ret

# Emit/patch rel32 control flow inside the generated vector kernel.  The return
# value of the placeholder helpers is the address of the four-byte displacement.
.endm

.macro TFP_023_vec_emit_jmp_placeholder
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+5]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_8
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vejph_fail
.tcgrow_ok_8:
    mov byte ptr [rax],0xE9
    mov dword ptr [rax+1],0
    lea rax,[rax+1]
    mov [rip+vec_emit_ptr],rcx
    ret
.vejph_fail:
    xor eax,eax
    ret

.endm

.macro TFP_023_vec_emit_jbe_placeholder
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+6]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_9
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vejb_fail
.tcgrow_ok_9:
    mov word ptr [rax],0x860F
    mov dword ptr [rax+2],0
    lea rax,[rax+2]
    mov [rip+vec_emit_ptr],rcx
    ret
.vejb_fail:
    xor eax,eax
    ret

# Near conditional branches used by the vector-region discriminator.
# Return the rel32 displacement address, matching the other placeholder helpers.
.endm

.macro TFP_023_vec_emit_jb_placeholder
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+6]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_group_jb
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vegroupjb_fail
.tcgrow_ok_group_jb:
    mov word ptr [rax],0x820F
    mov dword ptr [rax+2],0
    lea rax,[rax+2]
    mov [rip+vec_emit_ptr],rcx
    ret
.vegroupjb_fail:
    xor eax,eax
    ret

.endm

.macro TFP_023_vec_emit_je_placeholder
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+6]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_10
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .veje_fail
.tcgrow_ok_10:
    mov word ptr [rax],0x840F
    mov dword ptr [rax+2],0
    lea rax,[rax+2]
    mov [rip+vec_emit_ptr],rcx
    ret
.veje_fail:
    xor eax,eax
    ret

.endm

.macro TFP_023_vec_emit_jae_placeholder
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+6]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_11
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vejae_fail
.tcgrow_ok_11:
    mov word ptr [rax],0x830F
    mov dword ptr [rax+2],0
    lea rax,[rax+2]
    mov [rip+vec_emit_ptr],rcx
    ret
.vejae_fail:
    xor eax,eax
    ret

# rdi=disp32 address, rsi=target. eax=0/1.
.endm

.macro TFP_01_vec_vex2_rrr
    # EVEX.512 generic map=0F, W=1, regs 0..31. r8d carries pp.
    push rbx
    mov ebx,edi
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov r9d,esi; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,7; or eax,r9d
    mov r9d,ecx; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,6; or eax,r9d
    mov r9d,ecx; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5; or eax,r9d
    mov r9d,esi; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,4; or eax,r9d
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,edx; not eax; and eax,0xF; shl eax,3
    or eax,0x84                    # W=1, fixed bit2
    or eax,r8d
    mov edi,eax; call vec_emit_u8
    mov eax,edx; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x40                    # LL=512 (10b)
    mov edi,eax; call vec_emit_u8
    mov edi,ebx; call vec_emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov r9d,ecx; and r9d,7; or eax,r9d; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    # Account the AVX-512 operation that was actually emitted.
    cmp ebx,0x58
    je .vv2_fp_add
    cmp ebx,0x5C
    je .vv2_fp_add
    cmp ebx,0x59
    je .vv2_fp_mul
    cmp ebx,0x5E
    je .vv2_fp_div
    inc dword ptr [rip+schedule_counts+4*4] # integer/logical ALU
    jmp .vv2_count_done
.vv2_fp_add:
    inc dword ptr [rip+schedule_counts+0]
    jmp .vv2_count_done
.vv2_fp_mul:
    inc dword ptr [rip+schedule_counts+4]
    jmp .vv2_count_done
.vv2_fp_div:
    inc dword ptr [rip+schedule_counts+8]
.vv2_count_done:
    pop rbx
    ret

# Low-register VEX3 map=0F38: edi=opcode, esi=dst, edx=src1, ecx=src2, r8d=pp.
# Native unary vector sqrt on the existing AVX-512 carrier. edi=dst, esi=src.
.endm

.macro TFP_01_vec_sqrtpd
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov r9d,ebx; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,7; or eax,r9d
    mov r9d,r12d; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,6; or eax,r9d
    mov r9d,r12d; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5; or eax,r9d
    mov r9d,ebx; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,4; or eax,r9d
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8       # W1, reserved vvvv, pp=66
    mov edi,0x48; call vec_emit_u8       # LL=512, no masking
    mov edi,0x51; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+8]
    xor eax,eax
    pop r12; pop rbx; ret

.endm

.macro TFP_01_vec_mov_ext
    push rbx
    mov ebx,edi
    mov edi,0x62; call vec_emit_u8
    # P0 = ~dst.bit3:R, ~src.bit4:X, ~src.bit3:B, ~dst.bit4:R', map=0F(1)
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,esi; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,esi; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x6F; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,esi; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    pop rbx
    ret

# vec_keep_k1_zero(edi=dst) -> eax=0/1
# Keep exactly the lanes in native PredicateFact k1 and zero all others. This is
# the zero-valued false arm of a guarded Rank-N region, not a separate select IR.
.endm

.macro TFP_01_vec_keep_k1_zero
    push rbx
    mov ebx,edi
    mov edi,0x62; call vec_emit_u8
    # P0 = ~dst.bit3:R, ~src.bit4:X, ~src.bit3:B, ~dst.bit4:R', map=0F(1)
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8
    mov edi,0xC9; call vec_emit_u8       # z=1, LL=512, aaa=k1
    mov edi,0x28; call vec_emit_u8       # VMOVAPD
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax
    pop rbx
    ret

# vec_kortest_k1() -> eax=0/1. Runtime ZF=1 iff support(k1) is empty.
.endm

.macro TFP_01_vec_kortest_k1
    mov edi,0xC5; call vec_emit_u8
    mov edi,0xF8; call vec_emit_u8
    mov edi,0x98; call vec_emit_u8
    mov edi,0xC9; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax
    ret

# movabs rax,imm; vmovq xmmD,rax; vpbroadcastq ymmD,xmmD (D low reg)
.endm

.macro TFP_023_vec_finalize_constants
    push rbx
    push r12
    push r13
    # align current output to 8 bytes after ret
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+7]
    and rcx,-8
.vfc_pad:
    cmp rax,rcx
    jae .vfc_consts
    mov byte ptr [rax],0x90
    inc rax
    jmp .vfc_pad
.vfc_consts:
    mov [rip+vec_emit_ptr],rax
    mov ebx,dword ptr [rip+vec_const_count]
    xor r12d,r12d
    mov r13,[rip+vec_const_addr_ptr]
    mov r8,[rip+vec_const_bits_ptr]
.vfc_copy:
    cmp r12d,ebx
    jae .vfc_patch
    lea rcx,[rax+8]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_13
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vfc_fail
.tcgrow_ok_13:
    mov qword ptr [r13+r12*8],rax
    mov rdx,qword ptr [r8+r12*8]
    mov qword ptr [rax],rdx
    mov rax,rcx
    inc r12d
    jmp .vfc_copy
.vfc_patch:
    mov [rip+vec_emit_ptr],rax
    mov ebx,dword ptr [rip+vec_fixup_count]
    xor r12d,r12d
    mov r8,qword ptr [rip+tensor_fixup_ptr_base]
    mov r9,qword ptr [rip+tensor_fixup_const_base]
    mov r10,[rip+vec_const_addr_ptr]
.vfc_pl:
    cmp r12d,ebx
    jae .vfc_ok
    mov r11,qword ptr [r8+r12*8]
    mov ecx,dword ptr [r9+r12*4]
    mov rax,qword ptr [r10+rcx*8]
    lea rdx,[r11+4]
    sub rax,rdx
    mov dword ptr [r11],eax
    inc r12d
    jmp .vfc_pl
.vfc_ok:
    xor eax,eax
    pop r13
    pop r12
    pop rbx
    ret
.vfc_fail:
    mov eax,1
    pop r13
    pop r12
    pop rbx
    ret

# Generic i64 vector multiply.  The semantic operation is independent of the
# instruction-set spelling: use native VPMULLQ when DQ contributes it, otherwise
# synthesize the exact low 64 bits from AVX512F VPMULUDQ + shifts + adds.
# Canonical generic i64 multiply ABI: edi=dst, edx=src1, ecx=src2.
# Physical recipe selection never changes the semantic operation.
.endm

.macro TFP_01_vec_vpmullq
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi                    # destination
    mov r12d,edx                   # src1
    mov r13d,ecx                   # src2
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_I64_MUL_NATIVE
    jnz .vml_generic_native
    test eax,ISA_CAP_I64_MUL_SYNTH
    jz .vml_generic_fail

    # Two temporary vectors are sufficient:
    # low64(a*b) = low32(a)*low32(b)
    #              + ((hi32(a)*low32(b)+low32(a)*hi32(b)) << 32).
    call vec_alloc
    cmp eax,-1
    je .vml_generic_fail
    mov r14d,eax
    call vec_alloc
    cmp eax,-1
    je .vml_generic_free1
    mov r15d,eax

    mov edi,r14d; mov esi,r12d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vml_generic_free2
    mov edi,r15d; mov esi,r13d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vml_generic_free2
    # t1 = hi(a)*lo(b)
    mov edi,r14d; mov esi,r14d; mov edx,r14d; mov ecx,r13d; mov r8d,1
    call vec_vpmuludq
    test eax,eax; jnz .vml_generic_free2
    # t2 = lo(a)*hi(b)
    mov edi,r15d; mov esi,r15d; mov edx,r12d; mov ecx,r15d; mov r8d,1
    call vec_vpmuludq
    test eax,eax; jnz .vml_generic_free2
    mov edi,0xD4; mov esi,r14d; mov edx,r14d; mov ecx,r15d; mov r8d,1
    call vec_vex2_rrr
    mov edi,r14d; mov esi,r14d; mov edx,32; call vec_vpsllq_imm
    test eax,eax; jnz .vml_generic_free2
    # dst = lo(a)*lo(b) + cross<<32
    mov edi,ebx; mov esi,ebx; mov edx,r12d; mov ecx,r13d; mov r8d,1
    call vec_vpmuludq
    test eax,eax; jnz .vml_generic_free2
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vml_generic_done_free

.vml_generic_native:
    mov edi,ebx
    mov esi,ebx
    mov edx,r12d
    mov ecx,r13d
    call vec_vpmullq_native
    jmp .vml_generic_done
.vml_generic_free2:
    mov edi,r15d; call vec_free
.vml_generic_free1:
    mov edi,r14d; call vec_free
.vml_generic_fail:
    mov eax,1
    jmp .vml_generic_done
.vml_generic_done_free:
    mov edi,r15d; call vec_free
    mov edi,r14d; call vec_free
    xor eax,eax
.vml_generic_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# AVX512DQ native realization of generic i64 vector multiply.
.endm

.macro TFP_01_vec_vpsllq_imm
    push rbx
    mov ebx,edi                    # dst
    mov r10d,esi                   # src
    mov r11d,edx                   # shift
    mov edi,0x62; call vec_emit_u8
    mov eax,0xF1
    bt r10d,4
    jnc .vsi_no_b4
    and eax,0xBF
.vsi_no_b4:
    bt r10d,3
    jnc .vsi_no_b3
    and eax,0xDF
.vsi_no_b3:
    mov edi,eax; call vec_emit_u8
    mov eax,ebx
    not eax
    and eax,0xF
    shl eax,3
    or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,ebx
    shr eax,4
    and eax,1
    xor eax,1
    shl eax,3
    or eax,0x40
    mov edi,eax; call vec_emit_u8
    mov edi,0x73; call vec_emit_u8
    mov eax,r10d
    and eax,7
    or eax,0xF0                   # /6
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4] # integer ALU/shift
    pop rbx
    ret

# EVEX vpsrlq zmm dst,src,imm8. AVX512F foundation primitive.
.endm

.macro TFP_01_vec_vpsrlq_imm
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov r11d,edx
    mov edi,0x62; call vec_emit_u8
    mov eax,0xF1
    bt r10d,4
    jnc .vsri_no_b4
    and eax,0xBF
.vsri_no_b4:
    bt r10d,3
    jnc .vsri_no_b3
    and eax,0xDF
.vsri_no_b3:
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40
    mov edi,eax; call vec_emit_u8
    mov edi,0x73; call vec_emit_u8
    mov eax,r10d; and eax,7; or eax,0xD0       # /2
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    ret

# EVEX vpaddq zmm dst,src1,QWORD BCST [rip+const].
# edi=dst, esi=src1, edx=constant-pool index -> eax=0/1.
# This is the pressure-safe affine-offset path: no temporary vector register and
# no hidden scalar fallback are introduced when the resident constant bank fills.
.endm

.macro TFP_01_vec_vpmullq_mem_const
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_I64_MUL_NATIVE
    jnz .vpmqmc_dispatch_native
    test eax,ISA_CAP_I64_MUL_SYNTH
    jz .vpmqmc_dispatch_fail

    # Foundation recipe: scalar constant -> vector broadcast, then the same
    # generic exact i64 multiply relation. No DQ instruction and no scalar lane.
    call vec_alloc
    cmp eax,-1
    je .vpmqmc_dispatch_fail
    mov r14d,eax
    mov edi,r14d
    call vec_emit_const_load_index      # r13d is pool index
    test eax,eax
    jnz .vpmqmc_dispatch_free_fail
    # Generic multiply keeps the historical emitter ABI: esi=dst,
    # edx=src1, ecx=src2. The broadcast temporary is the second source.
    mov edi,ebx
    mov esi,ebx
    mov edx,r12d
    mov ecx,r14d
    call vec_vpmullq
    mov r15d,eax
    mov edi,r14d
    call vec_free
    mov eax,r15d
    jmp .vpmqmc_dispatch_done
.vpmqmc_dispatch_free_fail:
    mov edi,r14d
    call vec_free
.vpmqmc_dispatch_fail:
    mov eax,1
    jmp .vpmqmc_dispatch_done
.vpmqmc_dispatch_native:
    mov edi,ebx
    mov esi,r12d
    mov edx,r13d
    call vec_vpmullq_mem_const_native
.vpmqmc_dispatch_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_01_vec_vfmadd231pd
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
    mov edi,0xB8; call vec_emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov r9d,ecx; and r9d,7; or eax,r9d; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+0]
    inc dword ptr [rip+schedule_counts+4]
    pop rbx
    ret

# EVEX vfnmadd231pd zmm dst,src1,src2: dst = -(src1*src2) + dst.
# Operand encoding is validated against GNU as for low/high ZMM combinations.
.endm

.macro TFP_02_vec_vfnmadd231pd
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
    mov edi,0xBC; call vec_emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov r9d,ecx; and r9d,7; or eax,r9d; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+0]
    inc dword ptr [rip+schedule_counts+4]
    pop rbx
    ret

# EVEX vfmadd231pd zmm dst,src1,QWORD BCST [rip+const].
# edi=dst, esi=src1, edx=constant-pool index.  This fuses a non-resident
# coefficient directly from the constant pool and removes the old
# vpbroadcastq+temporary dependency edge.
.endm

.macro TFP_01_vec_vpminuq
    # Same EVEX map/operand encoding as vpmullq, opcode 3B.
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
    mov edi,0x3B; call vec_emit_u8
    mov eax,esi; and eax,7; shl eax,3
    mov r9d,ecx; and r9d,7; or eax,r9d; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4] # AVX-512 integer ALU
    pop rbx
    ret

# Generic signed i64-vector -> f64-vector conversion.
# The semantic operation is independent of AVX512DQ.  DQ contributes the
# one-instruction VCVTQQ2PD realization; AVX512F can synthesize the identical
# correctly-rounded result from exact 32-bit pieces without any scalar lane.
# edi=dst zmm, esi=src zmm -> eax=0/1.
.endm

.macro TFP_01_vec_vcvtqq2pd_synth
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi                    # destination
    mov r12d,esi                   # source

    # Reserve every temporary before emitting code. Resource pressure may
    # change the physical recipe, never the semantic result or parallel width.
    call vec_alloc
    cmp eax,-1
    je .vcq2pds_fail
    mov r13d,eax                   # signed hi32
    call vec_alloc
    cmp eax,-1
    je .vcq2pds_free_hi
    mov r14d,eax                   # low32 sign correction (0/1)

    # 2^32 as exact binary64, consumed through the shared immutable pool.
    mov rsi,0x41F0000000000000
    call vec_const_intern
    cmp eax,-1
    je .vcq2pds_free_both
    mov r15d,eax

    # Extract high signed dword and low unsigned-sign bit before dst can alias src.
    mov edi,r13d; mov esi,r12d; mov edx,32; call vec_vpsrlq_imm
    mov edi,r14d; mov esi,r12d; mov edx,31; call vec_vpsrld_imm

    # Pack one dword from each qword lane, then use AVX512F dword->double.
    mov edi,ebx;   mov esi,r12d; call vec_vpmovqd_ymm_from_zmm
    mov edi,r13d;  mov esi,r13d; call vec_vpmovqd_ymm_from_zmm
    mov edi,r14d;  mov esi,r14d; call vec_vpmovqd_ymm_from_zmm
    mov edi,ebx;   mov esi,ebx;  call vec_vcvtdq2pd_zmm_from_ymm
    mov edi,r13d;  mov esi,r13d; call vec_vcvtdq2pd_zmm_from_ymm
    mov edi,r14d;  mov esi,r14d; call vec_vcvtdq2pd_zmm_from_ymm

    # signed(lo32) + sign(lo32)*2^32 = unsigned(lo32), exactly.
    mov edi,r14d; mov esi,r14d; mov edx,r15d; call vec_vmulpd_mem_const
    test eax,eax
    jnz .vcq2pds_free_both
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,r14d; mov r8d,1
    call vec_vex2_rrr

    # hi32*2^32 is exact. The final add performs the required int64->f64 rounding.
    mov edi,r13d; mov esi,r13d; mov edx,r15d; call vec_vmulpd_mem_const
    test eax,eax
    jnz .vcq2pds_free_both
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr

    mov edi,r14d; call vec_free
    mov edi,r13d; call vec_free
    xor eax,eax
    jmp .vcq2pds_done
.vcq2pds_free_both:
    mov edi,r14d; call vec_free
.vcq2pds_free_hi:
    mov edi,r13d; call vec_free
.vcq2pds_fail:
    mov eax,1
.vcq2pds_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# AVX512F VPMOVQD ymmDST,zmmSRC.  The 256-bit destination width is intrinsic
# to the 512-bit narrowing instruction and does not require AVX512VL.
.endm

.macro TFP_01_vec_vpmovqd_ymm_from_zmm
    push rbx
    mov ebx,edi                    # ymm destination physical id
    mov r10d,esi                   # zmm source physical id
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,ebx;  shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,ebx;  shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,r10d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov edi,0x7E; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x35; call vec_emit_u8
    mov eax,r10d; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret

# AVX512F VCVTDQ2PD zmmDST,ymmSRC.
.endm

.macro TFP_01_vec_vcvtdq2pd_zmm_from_ymm
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx;  shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,r10d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx;  shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0x7E; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0xE6; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3]
    pop rbx
    xor eax,eax
    ret

# AVX512F VPSRLD zmmDST,zmmSRC,imm8.
.endm

.macro TFP_01_vec_vpsrld_imm
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov r11d,edx
    mov edi,0x62; call vec_emit_u8
    mov eax,0xF1
    bt r10d,4
    jnc .vsrdi_no_b4
    and eax,0xBF
.vsrdi_no_b4:
    bt r10d,3
    jnc .vsrdi_no_b3
    and eax,0xDF
.vsrdi_no_b3:
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x05
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40
    mov edi,eax; call vec_emit_u8
    mov edi,0x72; call vec_emit_u8
    mov eax,r10d; and eax,7; or eax,0xD0
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret


# Generic property-constrained conversion used after a proof that every lane is
# finite, non-negative and <2^52. DQ can realize it with VCVTTPD2QQ; AVX512F
# synthesizes the same truncation by rounding toward zero in FP, adding the
# exact 2^52 bias, then extracting the mantissa as an integer. No scalar lane.
# edi=dst zmm, esi=src zmm -> eax=0/1.
# Scalar f64 carrier truncate toward zero. edi=dst xmm, esi=src xmm.
# SSE4.1 ROUNDSD is emitted directly; this is the same old register-native lane.
.endm

.macro TFP_01_vec_vrndscalepd_trunc
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx;  shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,r10d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx;  shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,3
    mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x09; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,0x03; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3]
    pop rbx
    xor eax,eax
    ret

# EVEX vaddpd zmm dst,src1,QWORD BCST [rip+const].
# edi=dst, esi=src1, edx=constant-pool index -> eax=0/1.
.endm

.macro TFP_01_vec_cmp_eq_maskvec
    push rbx
    mov ebx,edi                    # predicate vector destination
    mov edi,0x62; call vec_emit_u8
    # VPCMPEQQ k1,zmm src1,zmm src2
    mov eax,0x90
    mov r9d,edx; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,6; or eax,r9d
    mov r9d,edx; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5; or eax,r9d
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov eax,esi; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,esi; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40
    mov edi,eax; call vec_emit_u8
    mov edi,0x29; call vec_emit_u8
    mov eax,edx; and eax,7; or eax,0xC8
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    mov edi,ebx
    call vec_mask_k1_to_qvec
    pop rbx
    ret

# vec_cmp_f64_k1(esi=lhs, edx=rhs, ecx=VCMPPD predicate imm8) -> eax=0/1
# Native control authority for one floating PredicateFact. Consumers that need a
# value representation may materialize it through vec_mask_k1_to_qvec; guarded
# regions consume k1 directly and therefore never bounce mask -> qvec -> mask.
.endm

.macro TFP_01_vec_cmp_f64_k1
    push rbx
    push r12
    push r13
    mov ebx,esi
    mov r12d,edx
    mov r13d,ecx
    # VCMPPD k1,zmm lhs,zmm rhs,imm8
    mov edi,0x62; call vec_emit_u8
    mov eax,0x90
    mov r9d,r12d; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,6; or eax,r9d
    mov r9d,r12d; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5; or eax,r9d
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40
    mov edi,eax; call vec_emit_u8
    mov edi,0xC2; call vec_emit_u8
    mov eax,r12d; and eax,7; or eax,0xC8
    mov edi,eax; call vec_emit_u8
    mov edi,r13d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax
    pop r13
    pop r12
    pop rbx
    ret

# vec_cmp_f64_maskvec(edi=dst, esi=lhs, edx=rhs, ecx=VCMPPD predicate imm8)
# Value consumers materialize the same PredicateFact into all-ones/zero lanes.
.endm

.macro TFP_01_vec_cmp_f64_maskvec
    push rbx
    mov ebx,edi
    call vec_cmp_f64_k1
    test eax,eax; jnz .vcfm_fail
    mov edi,ebx
    call vec_mask_k1_to_qvec
    pop rbx
    ret
.vcfm_fail:
    pop rbx
    mov eax,1
    ret

# vec_mask_k1_to_qvec(edi=dst) -> eax=0/1
# One PredicateFact representation authority for every AVX-512 comparison.
.endm

.macro TFP_01_vec_mask_k1_to_qvec
    push rbx
    mov ebx,edi
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_MASK_TO_I64_NATIVE
    jz .vmk_mask_synth
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov edi,0xFE; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x38; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC1
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret
.vmk_mask_synth:
    test eax,ISA_CAP_MASK_TO_I64_SYNTH
    jz .vmk_mask_fail
    mov edi,0x48; call vec_emit_u8
    mov edi,0xC7; call vec_emit_u8
    mov edi,0xC0; call vec_emit_u8
    mov edi,0xFF; call vec_emit_u8
    mov edi,0xFF; call vec_emit_u8
    mov edi,0xFF; call vec_emit_u8
    mov edi,0xFF; call vec_emit_u8
    mov edi,0x62; call vec_emit_u8
    mov eax,0xF2
    test ebx,8
    jz .vmk_mask_p0_bit4
    and eax,0x7F
.vmk_mask_p0_bit4:
    test ebx,16
    jz .vmk_mask_p0
    and eax,0xEF
.vmk_mask_p0:
    mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8
    mov edi,0xC9; call vec_emit_u8
    mov edi,0x7C; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret
.vmk_mask_fail:
    pop rbx
    mov eax,1
    ret

# expr_affine_axis_u64(rdi=expr) -> rax=coefficient, rdx=offset, ecx=1 success.
.endm

.macro TFP_02_vec_interior_affine_residue_safe
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp dword ptr [rip+vec_interior_mode],1
    jne .viars_no
    cmp dword ptr [rip+vec_axis_root_valid],1
    jne .viars_no
    mov r12,rdi                    # local c
    mov r13,rsi                    # local signed d
    # composed C = local_c * root_c
    mov rax,r12
    mul qword ptr [rip+vec_axis_root_c]
    test rdx,rdx
    jnz .viars_no
    mov r14,rax                    # composed C
    test r14,r14
    js .viars_no                   # keep proof arithmetic in signed domain
    # composed D = local_c * root_d + local_d, checked as signed arithmetic.
    mov rax,qword ptr [rip+vec_axis_root_d]
    imul rax,r12
    jo .viars_no
    add rax,r13
    jo .viars_no
    mov r15,rax                    # composed signed D
    # Constant coordinate: 0 <= D < n_min proves validity for every runtime n.
    test r14,r14
    jnz .viars_nonzero_c
    test r15,r15
    js .viars_no
    cmp r15,qword ptr [rip+tensor_shape_extent_min]
    jae .viars_no
    jmp .viars_yes
.viars_nonzero_c:
    # Minimum is at physical root=1: C + D must be non-negative.
    mov rax,r14
    add rax,r15
    jo .viars_no
    test rax,rax
    js .viars_no
    # Maximum is at root=n-2.  Require C*(n-2)+D < n for the
    # largest admitted n, equivalently (C-1)*n + D - 2*C < 0.
    mov rbx,r14
    dec rbx
    mov rax,qword ptr [rip+tensor_shape_extent_max]
    test rax,rax
    js .viars_no
    imul rax,rbx
    jo .viars_no
    add rax,r15
    jo .viars_no
    mov rdx,r14
    add rdx,r14
    jo .viars_no
    sub rax,rdx
    jo .viars_no
    test rax,rax
    jns .viars_no
.viars_yes:
    mov eax,1
    jmp .viars_done
.viars_no:
    xor eax,eax
.viars_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# expr_affine_axis_interior_u64(rdi=expr) -> rax=c, rdx=d, ecx=1.
# Extends the globally-safe affine recognizer only inside INTERIOR_PROVEN. It
# may unwrap boundary-select forms already proven false there, normalize a
# dynamic periodic affine coordinate whose residue is proven in-range, and
# represent affine-literal subtraction with a two's-complement offset.
.endm

.macro TFP_02_expr_affine_axis_interior_u64
    push rbx
    push r12
    push r13
    push r14
    mov r12,rdi
    call expr_affine_axis_u64
    test ecx,ecx
    jnz .eaai_done
    cmp dword ptr [rip+vec_interior_mode],1
    jne .eaai_no
.eaai_mod:
    # periodic(expr,n) is canonical op=mod.  In the modulo ring, q*n vanishes.
    # Erase the physical modulo only if the remaining affine residue is proven
    # already inside [0,n) for every lane in this interior vector region.
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eaai_sub
    mov r13,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .eaai_sub
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eaai_sub
    mov r13,[rax+24]; test r13,r13; jz .eaai_sub
    mov r14,[r13+32]; test r14,r14; jz .eaai_sub
    cmp qword ptr [r14+32],0; jne .eaai_sub
    mov rdi,r14; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eaai_sub
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_domain_var_match
    test eax,eax; jz .eaai_sub
    mov rdi,r13
    call expr_affine_modn_form
    test ecx,ecx; jz .eaai_sub
    mov r13,rax                    # local c
    mov r14,rdx                    # local signed d; q*n intentionally erased
    mov rdi,r13
    mov rsi,r14
    call vec_interior_affine_residue_safe
    test eax,eax; jz .eaai_sub
    mov rax,r13
    mov rdx,r14
    mov ecx,1
    jmp .eaai_done
.eaai_sub:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eaai_no
    mov rbx,rax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz .eaai_no
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eaai_no
    mov rbx,[rax+24]; test rbx,rbx; jz .eaai_no
    mov r12,[rbx+32]; test r12,r12; jz .eaai_no
    cmp qword ptr [r12+32],0; jne .eaai_no
    mov rdi,r12; call expr_literal_u64
    test edx,edx; jnz .eaai_no
    cmp rax,TENSOR_PHYSICAL_LANES-1
    ja .eaai_no
    push rax
    mov rdi,rbx; call expr_affine_axis_u64
    pop rbx
    test ecx,ecx; jz .eaai_no
    sub rdx,rbx
    mov ecx,1
    jmp .eaai_done
.eaai_no:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
.eaai_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Canonical CoordinateFact composition for ordinary indexed maps.  The same
# integer algebra that powers tolerant linear aggregation is the single
# coordinate authority for strict and tolerant programs; FP reassociation is
# not involved.  rdi=index expr -> rax=c, rdx=d, r8=mod token, ecx=1/0.
.endm

.macro TFP_02_expr_affine_modn_form
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi

    # axis
    mov rdi,r12; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .eamf_var
    mov rax,1; xor edx,edx; xor r8d,r8d; mov ecx,1; jmp .eamf_done
.eamf_var:
    mov rdi,r12; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eamf_lit
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_domain_var_match
    test eax,eax; jz .eamf_no
    xor eax,eax; xor edx,edx; mov r8,1; mov ecx,1; jmp .eamf_done
.eamf_lit:
    mov rdi,r12; call expr_literal_u64
    test edx,edx; jnz .eamf_op
    test rax,rax
    js .eamf_no                    # signed-offset proof domain
    mov rdx,rax; xor eax,eax; xor r8d,r8d; mov ecx,1; jmp .eamf_done
.eamf_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eamf_no
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eamf_no
    mov r14,[rax+24]; test r14,r14; jz .eamf_no
    mov r15,[r14+32]; test r15,r15; jz .eamf_no
    cmp qword ptr [r15+32],0; jne .eamf_no

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jnz .eamf_add
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jnz .eamf_sub
    # Integer affine modulo algebra must match u64 literals, not the f64
    # coefficient helper used by floating-point expression lowering.  Accept
    # mul(u64_literal, expr) and mul(expr, u64_literal) symmetrically.
    mov rdi,r14
    call expr_literal_u64
    test edx,edx
    jnz .eamf_mul_rhs_literal
    mov rbx,rax
    mov rdi,r15
    jmp .eamf_mul_recurse
.eamf_mul_rhs_literal:
    mov rdi,r15
    call expr_literal_u64
    test edx,edx; jnz .eamf_no
    mov rbx,rax
    mov rdi,r14
.eamf_mul_recurse:
    test rbx,rbx; js .eamf_no
    call expr_affine_modn_form
    test ecx,ecx; jz .eamf_no
    mov r13,rdx; mov r14,r8
    mul rbx                        # c *= literal
    test rdx,rdx; jnz .eamf_no
    mov r12,rax
    mov rax,r13
    imul rax,rbx
    jo .eamf_no
    mov r13,rax
    mov rax,r14
    imul rax,rbx
    jo .eamf_no
    mov r8,rax
    mov rax,r12; mov rdx,r13; mov ecx,1; jmp .eamf_done

.eamf_add:
    mov rdi,r14; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_no
    push rax; push rdx; push r8
    mov rdi,r15; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_add_fail
    mov rbx,rax; mov r12,rdx; mov r13,r8
    pop r8; pop rdx; pop rax
    add rax,rbx; jc .eamf_no
    add rdx,r12; jo .eamf_no
    add r8,r13; jo .eamf_no
    mov ecx,1; jmp .eamf_done
.eamf_add_fail:
    add rsp,24
    jmp .eamf_no

.eamf_sub:
    mov rdi,r14; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_no
    push rax; push rdx; push r8
    mov rdi,r15; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_sub_fail
    mov rbx,rax; mov r12,rdx; mov r13,r8
    pop r8; pop rdx; pop rax
    cmp rax,rbx; jb .eamf_no       # negative axis coefficient not in this slice
    sub rax,rbx
    sub rdx,r12; jo .eamf_no
    sub r8,r13; jo .eamf_no
    mov ecx,1; jmp .eamf_done
.eamf_sub_fail:
    add rsp,24
    jmp .eamf_no
.eamf_no:
    xor eax,eax; xor edx,edx; xor r8d,r8d; xor ecx,ecx
.eamf_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Normalize a signed modular offset when the external extent is compile-time
# fixed. rdi=signed d -> rax=canonical 0..n-1, ecx=1; otherwise ecx=0.
.endm

.macro TFP_02_vec_modn_fixed_normalize_d
    mov r9,qword ptr [rip+tensor_shape_extent_min]
    cmp r9,qword ptr [rip+tensor_shape_extent_max]
    jne .vmfnd_no
    test r9,r9; jz .vmfnd_no
    mov rax,rdi
    test rax,rax
    js .vmfnd_neg
    xor edx,edx
    div r9
    mov rax,rdx
    mov ecx,1
    ret
.vmfnd_neg:
    neg rax
    xor edx,edx
    div r9
    test rdx,rdx
    jz .vmfnd_zero
    mov rax,r9
    sub rax,rdx
    mov ecx,1
    ret
.vmfnd_zero:
    xor eax,eax
    mov ecx,1
    ret
.vmfnd_no:
    xor eax,eax
    xor ecx,ecx
    ret

# expr_index_key_u64(rdi=expr) -> rax=affine coefficient, rdx=offset,
# r8=modulus token (0 for no modulo, literal divisor otherwise), ecx=1 success.
# This is a structural compiler key only; it emits no runtime work.
.endm

.macro TFP_02_expr_index_key_u64
    push rbx
    push r12
    push r13
    mov r12,rdi
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eik_affine
    mov r13,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .eik_affine
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eik_no
    mov r13,[rax+24]; test r13,r13; jz .eik_no
    mov rbx,[r13+32]; test rbx,rbx; jz .eik_no
    cmp qword ptr [rbx+32],0; jne .eik_no
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .eik_mod_n
    test rax,rax; jz .eik_no
    mov rbx,rax
    jmp .eik_have_mod
.eik_mod_n:
    mov rdi,rbx; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eik_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_domain_var_match
    test eax,eax; jz .eik_no
    mov rbx,-1
.eik_have_mod:
    cmp rbx,-1
    jne .eik_have_literal_mod
    mov rdi,r13
    call expr_affine_modn_form
    test ecx,ecx; jz .eik_no
    # q*n vanishes in the ring key. Canonicalize signed d when n is fixed; for
    # dynamic n retain the signed representative and let composition prove safety.
    push rax
    push rdx
    mov rdi,rdx
    call vec_modn_fixed_normalize_d
    test ecx,ecx
    jz .eik_dynamic_d
    mov rdx,rax
    pop rax                       # discard original d
    pop rax                       # restore c
    mov r8,-1
    mov ecx,1
    jmp .eik_done
.eik_dynamic_d:
    pop rdx
    pop rax
    mov r8,-1
    mov ecx,1
    jmp .eik_done
.eik_have_literal_mod:
    mov rdi,r13; call expr_affine_axis_u64
    test ecx,ecx; jz .eik_no
    mov r8,rbx
    mov ecx,1
    jmp .eik_done
.eik_affine:
    mov rdi,r12; call expr_affine_axis_u64
    test ecx,ecx; jz .eik_no
    xor r8d,r8d
    mov ecx,1
    jmp .eik_done
.eik_no:
    xor eax,eax
    xor edx,edx
    xor r8d,r8d
    xor ecx,ecx
.eik_done:
    pop r13
    pop r12
    pop rbx
    ret

# save/restore current axis YMM6 at a recursive map-load boundary.
.endm

.macro TFP_01_vec_cache_lookup
    mov ecx,dword ptr [rip+vec_cache_count]
    test ecx,ecx
    jz .vcl_no
    dec ecx
    mov edx,dword ptr [rip+vec_current_gen]
    mov r8,qword ptr [rip+vec_cache_binding_ptr]
    mov r9,qword ptr [rip+vec_cache_gen_ptr]
    mov r10,qword ptr [rip+vec_cache_reg_ptr]
.vcl_loop:
    cmp dword ptr [r9+rcx*4],edx
    jne .vcl_next
    mov r11,qword ptr [rip+vec_cache_kind_ptr]
    cmp dword ptr [r11+rcx*4],0
    jne .vcl_next
    cmp qword ptr [r8+rcx*8],rdi
    jne .vcl_next
    mov eax,dword ptr [r10+rcx*4]
    ret
.vcl_next:
    test ecx,ecx
    jz .vcl_no
    dec ecx
    jmp .vcl_loop
.vcl_no:
    mov eax,-1
    ret

.endm

.macro TFP_01_vec_cache_add
    mov eax,dword ptr [rip+vec_cache_count]
    cmp eax,dword ptr [rip+tensor_optimizer_capacity]
    jae .vca_fail
    mov rcx,qword ptr [rip+vec_cache_binding_ptr]
    mov qword ptr [rcx+rax*8],rdi
    mov rcx,qword ptr [rip+vec_cache_kind_ptr]
    mov dword ptr [rcx+rax*4],0
    mov rcx,qword ptr [rip+vec_cache_gen_ptr]
    mov edx,dword ptr [rip+vec_current_gen]
    mov dword ptr [rcx+rax*4],edx
    mov rcx,qword ptr [rip+vec_cache_reg_ptr]
    mov dword ptr [rcx+rax*4],esi
    inc eax
    mov dword ptr [rip+vec_cache_count],eax
    xor eax,eax
    ret
.vca_fail:
    mov eax,1
    ret

# Indexed topology-coordinate CSE.  Key = (affine coefficient, offset,
# modulus-token) within the current coordinate generation.  This lets sibling
# p0/p1/p2-style fields share one periodic neighbor-index calculation.
# lookup(rdi=c,rsi=d,rdx=modtoken) -> eax=ZMM reg or -1
.endm

.macro TFP_01_vec_index_cache_lookup
    mov ecx,dword ptr [rip+vec_cache_count]
    test ecx,ecx
    jz .vicl_no
    dec ecx
    mov r11d,dword ptr [rip+vec_current_gen]
    mov r8,qword ptr [rip+vec_cache_gen_ptr]
    mov r9,qword ptr [rip+vec_cache_kind_ptr]
.vicl_loop:
    cmp dword ptr [r8+rcx*4],r11d
    jne .vicl_next
    cmp dword ptr [r9+rcx*4],1
    jne .vicl_next
    mov r10,qword ptr [rip+vec_cache_key_a_ptr]
    cmp qword ptr [r10+rcx*8],rdi
    jne .vicl_next
    mov r10,qword ptr [rip+vec_cache_key_b_ptr]
    cmp qword ptr [r10+rcx*8],rsi
    jne .vicl_next
    mov r10,qword ptr [rip+vec_cache_key_c_ptr]
    cmp qword ptr [r10+rcx*8],rdx
    jne .vicl_next
    mov r10,qword ptr [rip+vec_cache_reg_ptr]
    mov eax,dword ptr [r10+rcx*4]
    ret
.vicl_next:
    test ecx,ecx
    jz .vicl_no
    dec ecx
    jmp .vicl_loop
.vicl_no:
    mov eax,-1
    ret

# add(rdi=c,rsi=d,rdx=modtoken,ecx=reg) -> eax=0/1
.endm

.macro TFP_01_vec_index_cache_add
    mov eax,dword ptr [rip+vec_cache_count]
    cmp eax,dword ptr [rip+tensor_optimizer_capacity]
    jae .vica_fail
    mov r8,qword ptr [rip+vec_cache_binding_ptr]
    mov qword ptr [r8+rax*8],0
    mov r8,qword ptr [rip+vec_cache_kind_ptr]
    mov dword ptr [r8+rax*4],1
    mov r8,qword ptr [rip+vec_cache_gen_ptr]
    mov r9d,dword ptr [rip+vec_current_gen]
    mov dword ptr [r8+rax*4],r9d
    mov r8,qword ptr [rip+vec_cache_key_a_ptr]
    mov qword ptr [r8+rax*8],rdi
    mov r8,qword ptr [rip+vec_cache_key_b_ptr]
    mov qword ptr [r8+rax*8],rsi
    mov r8,qword ptr [rip+vec_cache_key_c_ptr]
    mov qword ptr [r8+rax*8],rdx
    mov r8,qword ptr [rip+vec_cache_reg_ptr]
    mov dword ptr [r8+rax*4],ecx
    inc eax
    mov dword ptr [rip+vec_cache_count],eax
    xor eax,eax
    ret
.vica_fail:
    mov eax,1
    ret

# Indexed pure-map value CSE. Key = (binding,c,d,modtoken,generation).
# This is strict-safe common-subexpression elimination: it does not reassociate
# floating-point arithmetic, it only prevents reevaluating the same pure map at
# the same structural coordinate.
# lookup(rdi=binding,rsi=c,rdx=d,rcx=mod) -> eax=ZMM cache reg or -1.
.endm

.macro TFP_01_vec_index_value_cache_lookup
    mov r10,rcx
    mov ecx,dword ptr [rip+vec_cache_count]
    test ecx,ecx; jz .vivcl_no
    dec ecx
    mov r11d,dword ptr [rip+vec_current_gen]
.vivcl_loop:
    mov r8,qword ptr [rip+vec_cache_gen_ptr]
    cmp dword ptr [r8+rcx*4],r11d; jne .vivcl_next
    mov r8,qword ptr [rip+vec_cache_kind_ptr]
    cmp dword ptr [r8+rcx*4],2; jne .vivcl_next
    mov r8,qword ptr [rip+vec_cache_binding_ptr]
    cmp qword ptr [r8+rcx*8],rdi; jne .vivcl_next
    mov r8,qword ptr [rip+vec_cache_key_a_ptr]
    cmp qword ptr [r8+rcx*8],rsi; jne .vivcl_next
    mov r8,qword ptr [rip+vec_cache_key_b_ptr]
    cmp qword ptr [r8+rcx*8],rdx; jne .vivcl_next
    mov r8,qword ptr [rip+vec_cache_key_c_ptr]
    cmp qword ptr [r8+rcx*8],r10; jne .vivcl_next
    mov r8,qword ptr [rip+vec_cache_reg_ptr]
    mov eax,dword ptr [r8+rcx*4]
    ret
.vivcl_next:
    test ecx,ecx; jz .vivcl_no
    dec ecx; jmp .vivcl_loop
.vivcl_no:
    mov eax,-1
    ret

# add(rdi=binding,rsi=c,rdx=d,rcx=mod,r8d=reg) -> eax=0/1.
.endm

.macro TFP_01_vec_index_value_cache_add
    mov r10,rcx
    mov r11d,r8d
    mov eax,dword ptr [rip+vec_cache_count]
    cmp eax,dword ptr [rip+tensor_optimizer_capacity]; jae .vivca_fail
    mov r8,qword ptr [rip+vec_cache_binding_ptr]; mov qword ptr [r8+rax*8],rdi
    mov r8,qword ptr [rip+vec_cache_kind_ptr]; mov dword ptr [r8+rax*4],2
    mov r8,qword ptr [rip+vec_cache_gen_ptr]; mov ecx,dword ptr [rip+vec_current_gen]; mov dword ptr [r8+rax*4],ecx
    mov r8,qword ptr [rip+vec_cache_key_a_ptr]; mov qword ptr [r8+rax*8],rsi
    mov r8,qword ptr [rip+vec_cache_key_b_ptr]; mov qword ptr [r8+rax*8],rdx
    mov r8,qword ptr [rip+vec_cache_key_c_ptr]; mov qword ptr [r8+rax*8],r10
    mov r8,qword ptr [rip+vec_cache_reg_ptr]; mov dword ptr [r8+rax*4],r11d
    inc eax; mov dword ptr [rip+vec_cache_count],eax
    xor eax,eax; ret
.vivca_fail:
    mov eax,1; ret

# free only tail cache entries belonging to current generation (nested scopes are stack-disciplined).
.endm

.macro TFP_01_vec_cache_free_current
    push rbx
    push r12
    mov ebx,dword ptr [rip+vec_current_gen]
.vcf_loop:
    mov eax,dword ptr [rip+vec_cache_count]
    test eax,eax
    jz .vcf_done
    dec eax
    mov rcx,qword ptr [rip+vec_cache_gen_ptr]
    cmp dword ptr [rcx+rax*4],ebx
    jne .vcf_done
    mov r12d,eax
    mov rcx,qword ptr [rip+vec_cache_reg_ptr]
    mov edi,dword ptr [rcx+r12*4]
    call vec_cache_reg_free
    mov dword ptr [rip+vec_cache_count],r12d
    jmp .vcf_loop
.vcf_done:
    pop r12
    pop rbx
    ret

# vec_try_int_source(rdi=expr) -> eax physical ZMM source or -1.
# Pure leaves can feed a 3-operand vector instruction directly without a copy node.
.endm

.macro TFP_02_vec_try_int_source
    push rbx
    mov rbx,rdi
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .vtis_axis
    mov rsi,rax
    call vec_const_get_reg
    jmp .vtis_done
.vtis_axis:
    mov rdi,rbx; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .vtis_var
    cmp dword ptr [rip+vec_axis_root_valid],1; jne .vtis_no
    cmp qword ptr [rip+vec_axis_root_c],1; jne .vtis_no
    cmp qword ptr [rip+vec_axis_root_d],0; jne .vtis_no
    cmp qword ptr [rip+vec_axis_root_mod],0; jne .vtis_no
    mov eax,dword ptr [rip+vec_axis_reg]
    jmp .vtis_done
.vtis_var:
    mov rdi,rbx; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .vtis_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_domain_var_match
    test eax,eax; jz .vtis_no
    mov eax,7
    jmp .vtis_done
.vtis_no:
    mov eax,-1
.vtis_done:
    pop rbx
    ret

# vec_try_float_source(rdi=expr) -> eax resident source reg or -1.
# Literal constants and already-proven direct-axis CSE values are immutable sources.
.endm

.macro TFP_01_emit_vec_predicate_k1
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    cmp qword ptr [r12],J_OBJECT; jne .evpk_unsupported
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .evpk_unsupported
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .evpk_unsupported
    mov r14,[rax+24]; test r14,r14; jz .evpk_unsupported
    mov r15,[r14+32]; test r15,r15; jz .evpk_unsupported
    cmp qword ptr [r15+32],0; jne .evpk_unsupported
    mov ebx,-1
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax; jz .evpk_ne; mov ebx,0; jmp .evpk_kind
.evpk_ne:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_ne]; mov ecx,v_ne_end-v_ne; call span_eq
    test eax,eax; jz .evpk_lt; mov ebx,12; jmp .evpk_kind
.evpk_lt:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_lt]; mov ecx,v_lt_end-v_lt; call span_eq
    test eax,eax; jz .evpk_le; mov ebx,1; jmp .evpk_kind
.evpk_le:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_le]; mov ecx,v_le_end-v_le; call span_eq
    test eax,eax; jz .evpk_gt; mov ebx,2; jmp .evpk_kind
.evpk_gt:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_gt]; mov ecx,v_gt_end-v_gt; call span_eq
    test eax,eax; jz .evpk_ge; mov ebx,14; jmp .evpk_kind
.evpk_ge:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_ge]; mov ecx,v_ge_end-v_ge; call span_eq
    test eax,eax; jz .evpk_unsupported; mov ebx,13
.evpk_kind:
    mov rdi,r14; call expr_is_float_value
    test eax,eax; jz .evpk_unsupported
    call vec_alloc; cmp eax,-1; je .evpk_failure; mov r12d,eax
    call vec_alloc; cmp eax,-1; je .evpk_free_lhs_failure; mov r13d,eax
    mov rdi,r14; mov esi,r12d; call emit_vec_float
    test eax,eax; jnz .evpk_free2_failure
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evpk_free2_failure
    mov esi,r12d; mov edx,r13d; mov ecx,ebx; call vec_cmp_f64_k1
    push rax
    mov edi,r13d; call vec_free
    mov edi,r12d; call vec_free
    pop rax
    test eax,eax; jnz .evpk_failure
    xor eax,eax
    jmp .evpk_done
.evpk_free2_failure:
    mov edi,r13d; call vec_free
.evpk_free_lhs_failure:
    mov edi,r12d; call vec_free
.evpk_failure:
    mov eax,2
    jmp .evpk_done
.evpk_unsupported:
    mov eax,1
.evpk_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# emit_vec_int(rdi=expr, esi=dst ymm low) -> eax 0/1
.endm

.macro TFP_02_vec_emit_periodic_key
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12,rsi                    # c
    mov r13,rdx                    # signed d representative
    mov r14,rcx                    # mod token
    xor r15d,r15d                  # dynamic-ring normalization multiple k

    # A canonical Z/nZ CoordinateFact may carry a negative signed offset.
    # Choose the smallest compile-time k with k*n+d >= 0 for every admitted n.
    # Adding k*n does not change the residue; it only gives the reciprocal
    # materializer one non-negative physical representative.  This is a ring
    # normalization, not a special case for backward shifts.
    cmp r14,-1
    jne .vepk_affine_emit
    test r13,r13
    jns .vepk_affine_emit
    mov rax,r13
    neg rax
    jo .vepk_fail
    mov rcx,qword ptr [rip+tensor_shape_extent_min]
    test rcx,rcx
    jz .vepk_fail
    xor edx,edx
    div rcx                        # |d| / n_min
    test rdx,rdx
    jz .vepk_norm_k_ready
    inc rax
    jz .vepk_fail
.vepk_norm_k_ready:
    mov r15,rax

.vepk_affine_emit:
    # Dynamic modulo has two physical realizations under one PeriodicAffineFact.
    # Keep the existing reciprocal path only when its strict exactness proof is
    # valid. Otherwise emit exact integer ring arithmetic before any affine hot
    # bytes are produced; physical precision must never become a source limit.
    cmp r14,-1
    jne .vepk_affine_emit_ready
    mov rax,r12
    add rax,r15                    # effective non-negative coefficient bound
    jc .vepk_exact_n
    mov rcx,rax
    mul qword ptr [rip+tensor_shape_extent_max]
    test rdx,rdx
    jnz .vepk_exact_n
    test r15,r15
    jnz .vepk_recip_first_ready
    add rax,r13                    # positive d; negative d always has k>0
    jc .vepk_exact_n
.vepk_recip_first_ready:
    # The mature reciprocal quotient needs an exact integer conversion only
    # for its one-sided proof.  The bidirectional correction stays exact when
    # the signed binary64 quotient estimate is within one integer.  Prove that
    # from the physical range instead of rejecting the PeriodicAffineFact.
    # When n < 2^53 its scalar conversion is exact; x conversion, reciprocal
    # rounding and the multiply contribute three binary64 roundings.  Thus
    #   x < 2^63, n_max < 2^53, floor(x/n_min) < 2^52
    # gives |q_hat-q| < 2 under the conservative 4u relative-error bound.
    # Two bidirectional integer corrections close that bounded uncertainty.
    # Values outside the proof domain fall through to exact ring arithmetic.
    mov rdx,0x0020000000000000     # exact integer -> binary64 domain
    cmp rax,rdx
    jb .vepk_affine_emit_ready
    # Unsigned conversion removes the artificial x<2^63 wall.  Bound the
    # quotient from the affine relation itself instead of combining incompatible
    # extrema x(n_max) and n_min: for 0<=i<n,
    #   floor((c*i + k*n + d)/n) < c+k+ceil(max(d,0)/n).
    mov rdx,qword ptr [rip+tensor_shape_extent_max]
    mov rcx,0x0020000000000000     # n < 2^53 => exact scalar binary64 n
    cmp rdx,rcx
    jae .vepk_exact_n
    mov rax,r12
    add rax,r15
    jc .vepk_exact_n
    test r13,r13
    jle .vepk_q_bound_ready
    mov rcx,qword ptr [rip+tensor_shape_extent_min]
    test rcx,rcx
    jz .vepk_exact_n
    mov rdx,r13
    dec rdx
    js .vepk_exact_n
    xor r8d,r8d
    # ceil(d/n_min) = 1 + floor((d-1)/n_min), d>0.
    mov r9,rax
    mov rax,rdx
    xor edx,edx
    div rcx
    inc rax
    add rax,r9
    jc .vepk_exact_n
.vepk_q_bound_ready:
    mov rdx,0x0010000000000000     # q_bound < 2^52 => 4u*q < 2
    cmp rax,rdx
    jae .vepk_exact_n
    jmp .vepk_affine_emit_ready
.vepk_exact_n:
    # Exact periodic facts reuse the same persistent AffineFact authority as
    # ordinary induction. Pass 0 only profiles the fact; canonical codegen may
    # return a value carrier whose initialization is exact and whose hot-loop
    # evolution is one modular recurrence per packet.
    mov rsi,r12
    mov rdx,r13
    mov rcx,-1
    call vec_periodic_induct_get_reg
    cmp eax,-1
    je .vepk_exact_materialize
    mov edi,ebx
    mov esi,eax
    call vec_mov_ext
    test eax,eax
    jnz .vepk_fail
    jmp .vepk_ok
.vepk_exact_materialize:
    mov edi,ebx
    mov rsi,r12
    mov rdx,r13
    call vec_emit_periodic_exact
    test eax,eax
    jnz .vepk_fail
    jmp .vepk_ok

.vepk_affine_emit_ready:
    # Reuse the pressure-safe affine emitter against an identity symbolic root.
    mov eax,dword ptr [rip+vec_axis_root_valid]; push rax
    mov rax,qword ptr [rip+vec_axis_root_c]; push rax
    mov rax,qword ptr [rip+vec_axis_root_d]; push rax
    mov rax,qword ptr [rip+vec_axis_root_mod]; push rax
    mov dword ptr [rip+vec_axis_root_valid],1
    mov qword ptr [rip+vec_axis_root_c],1
    mov qword ptr [rip+vec_axis_root_d],0
    mov qword ptr [rip+vec_axis_root_mod],0
    mov edi,ebx
    mov rsi,r12
    mov rdx,r13
    test r15,r15
    jz .vepk_affine_args_ready
    xor edx,edx                    # d is applied after k*n establishes range
.vepk_affine_args_ready:
    push r15                       # preserve normalization k across emitter
    call vec_emit_affine_current
    mov r10d,eax
    pop r15
    pop rax; mov qword ptr [rip+vec_axis_root_mod],rax
    pop rax; mov qword ptr [rip+vec_axis_root_d],rax
    pop rax; mov qword ptr [rip+vec_axis_root_c],rax
    pop rax; mov dword ptr [rip+vec_axis_root_valid],eax
    test r10d,r10d
    jnz .vepk_fail

    # Materialize the chosen non-negative representative c*x + k*n + d.
    # ZMM7 is the existing runtime extent Fact.  The extra terms vanish modulo
    # n, so arbitrary negative signed representatives share the same backend.
    test r15,r15
    jz .vepk_norm_done
    cmp r15,1
    jne .vepk_norm_scaled_n
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,7; mov r8d,1
    call vec_vex2_rrr
    jmp .vepk_norm_add_d
.vepk_norm_scaled_n:
    mov rsi,r15
    call vec_const_intern
    cmp eax,-1
    je .vepk_fail
    mov r14d,eax
    call vec_alloc
    cmp eax,-1
    je .vepk_fail
    mov r10d,eax
    mov edi,r10d; mov esi,7; mov edx,r14d
    call vec_vpmullq_mem_const
    test eax,eax
    jnz .vepk_norm_free_fail
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,r10d; mov r8d,1
    call vec_vex2_rrr
    mov edi,r10d
    call vec_free
    jmp .vepk_norm_add_d
.vepk_norm_free_fail:
    mov edi,r10d
    call vec_free
    jmp .vepk_fail
.vepk_norm_add_d:
    add r12,r15                    # conservative normalized coefficient bound
    mov rsi,r13
    call vec_const_intern
    cmp eax,-1
    je .vepk_fail
    mov edx,eax
    mov edi,ebx; mov esi,ebx
    call vec_vpaddq_mem_const
    test eax,eax
    jnz .vepk_fail
    xor r13d,r13d                  # bound now represented by (c+k)*n
.vepk_norm_done:

    cmp r14,-1
    je .vepk_mod_n
    # Literal modulo: current vector ISA slice admits exact power-of-two rings.
    test r14,r14
    jz .vepk_ok
    lea rax,[r14-1]
    test rax,r14
    jnz .vepk_fail
    mov rsi,rax                    # mask=m-1
    call vec_const_intern
    cmp eax,-1; je .vepk_fail
    mov edx,eax
    mov edi,ebx
    mov esi,ebx
    call vec_vpandq_mem_const
    test eax,eax; jnz .vepk_fail
    jmp .vepk_ok

.vepk_mod_n:
    # Keep the mature one-sided reciprocal correction byte-identical wherever
    # its stronger proof still holds. The wider exact-integer-conversion domain
    # uses bidirectional quotient correction; only values beyond 2^53 use the
    # integer ring realization.
    mov rax,r12
    add rax,r13
    jc .vepk_mod_n_wide
    mul qword ptr [rip+tensor_shape_extent_max]
    test rdx,rdx
    jnz .vepk_mod_n_wide
    mov rdx,0x0004000000000000
    cmp rax,rdx
    jae .vepk_mod_n_wide
    call vec_alloc; cmp eax,-1; je .vepk_fail
    mov r15d,eax                   # quotient / q*n
    call vec_alloc; cmp eax,-1; je .vepk_free_q
    mov r14d,eax                   # correction temp
    mov edi,r15d; mov esi,ebx; call vec_vcvtqq2pd
    mov edi,0x59; mov esi,r15d; mov edx,r15d; mov ecx,15; mov r8d,1; call vec_vex2_rrr
    mov edi,r15d; mov esi,r15d; call vec_trunc_nonneg_pd_to_u64
    mov edi,r15d; mov esi,r15d; mov edx,r15d; mov ecx,7; call vec_vpmullq
    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,r15d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xFB; mov esi,r14d; mov edx,ebx; mov ecx,7; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; mov esi,ebx; mov edx,ebx; mov ecx,r14d; call vec_vpminuq
    mov edi,r14d; call vec_free
    mov edi,r15d; call vec_free
    jmp .vepk_ok
.vepk_mod_n_wide:
    mov edi,ebx
    call vec_emit_reciprocal_mod_wide
    test eax,eax
    jnz .vepk_fail
.vepk_ok:
    xor eax,eax
    jmp .vepk_done
.vepk_free_q:
    mov edi,r15d; call vec_free
.vepk_fail:
    mov eax,1
.vepk_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Compile-time tolerant linear aggregation.
#
# A structured FEM sum often reaches the backend as several direct wrapper maps
# whose leaves repeat the same indexed field value with different coefficients.
# Register CSE can only retain a handful of those values.  This pass instead
# combines coefficients before any machine instruction is emitted.  The key is
# exact and topology-aware: (binding identity, affine coefficient, offset,
# modulus token).  It is enabled only under the explicit tolerant FP contract;
# strict mode never enters this transformation.
#
# Mature 1.0.11 operator-subspace recovery. Solver/workload names are never
# inspected: this proves homogeneous linear structure under add/sub, literal
# scaling, exact power-of-two division and map loads.
.endm

.macro TFP_02_vec_linear_modulus_value
    cmp rdi,-1
    jne .vlmv_literal
    mov rax,qword ptr [rip+tensor_shape_extent_min]
    cmp rax,qword ptr [rip+tensor_shape_extent_max]
    jne .vlmv_no
    test rax,rax
    jz .vlmv_no
    mov ecx,1
    ret
.vlmv_literal:
    mov rax,rdi
    test rax,rax
    jz .vlmv_no
    mov ecx,1
    ret
.vlmv_no:
    xor eax,eax
    xor ecx,ecx
    ret

# Exact unsigned modular arithmetic helpers. Inputs are reduced before multiply,
# so the 128/64 quotient is always representable.
# vec_linear_mul_mod(rdi=a,rsi=b,rdx=m) -> rax=(a*b)%m
.endm

.macro TFP_02_emit_expr
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13,rsi
    mov r14,rdx
    cmp qword ptr [r12],J_OBJECT
    jne .ee_fail
    # literal?
    mov rdi,r12
    lea rsi,[rip+k_literal]
    mov edx,k_literal_end-k_literal
    call obj_get
    test rax,rax
    jz .ee_axis
    mov r15,rax
    mov rdi,r12
    lea rsi,[rip+k_type]
    mov edx,k_type_end-k_type
    call obj_get
    test rax,rax
    jz .ee_fail
    mov rbx,rax
    mov rdi,[rbx+8]
    mov rsi,[rbx+16]
    lea rdx,[rip+v_u64]
    mov ecx,v_u64_end-v_u64
    call span_eq
    test eax,eax
    jz .ee_lit_f64
    mov rax,r15
    call node_parse_u64
    test edx,edx
    jnz .ee_fail
    mov rdi,rax
    call emit_push_imm64
    mov eax,TYPE_U64
    jmp .ee_done
.ee_lit_f64:
    mov rdi,[rbx+8]
    mov rsi,[rbx+16]
    lea rdx,[rip+v_f64]
    mov ecx,v_f64_end-v_f64
    call span_eq
    test eax,eax
    jz .ee_fail
    mov rax,r15
    call node_parse_f64_bits
    test edx,edx
    jnz .ee_fail
    mov rdi,rax
    call emit_push_imm64
    mov eax,TYPE_F64
    jmp .ee_done

.ee_axis:
    mov rdi,r12
    lea rsi,[rip+k_axis]
    mov edx,k_axis_end-k_axis
    call obj_get
    test rax,rax
    jz .ee_var
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    mov rdx,r13
    mov rcx,r14
    xchg rsi,rcx                    # rsi=current axis len, rcx=expr axis len? fix below
    # easier explicit compare
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    mov rdx,r13
    mov ecx,r14d
    call span_eq
    test eax,eax
    jz .ee_fail
    mov edi,0x5541                  # push r13
    call emit_u16
    mov eax,TYPE_U64
    jmp .ee_done
.ee_var:
    mov rdi,r12
    lea rsi,[rip+k_var]
    mov edx,k_var_end-k_var
    call obj_get
    test rax,rax
    jz .ee_load
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call tensor_domain_var_match
    test eax,eax
    jz .ee_fail
    mov edi,0x5441                  # push r12
    call emit_u16
    mov eax,TYPE_U64
    jmp .ee_done

.ee_load:
    mov rdi,r12
    lea rsi,[rip+k_load]
    mov edx,k_load_end-k_load
    call obj_get
    test rax,rax
    jz .ee_operator
    mov r15,rax
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call find_binding
    test rax,rax
    jz .ee_fail
    mov rbx,rax                     # source binding
    cmp dword ptr [rbx+16],OP_MAP
    jne .ee_fail
    # exactly one index
    mov rdi,r12
    lea rsi,[rip+k_indices]
    mov edx,k_indices_end-k_indices
    call obj_get
    test rax,rax
    jz .ee_fail
    cmp qword ptr [rax],J_ARRAY
    jne .ee_fail
    mov r15,[rax+24]
    test r15,r15
    jz .ee_fail
    cmp qword ptr [r15+32],0
    jne .ee_fail
    # save old runtime axis
    mov edi,0x5541
    call emit_u16
    mov rdi,r15
    mov rsi,r13
    mov rdx,r14
    call emit_expr
    cmp eax,TYPE_U64
    jne .ee_fail
    # pop runtime index into r13
    mov edi,0x5D41
    call emit_u16
    mov rdi,[rbx+40]
    mov rsi,[rbx+24]
    mov rdx,[rbx+32]
    call emit_expr
    cmp eax,TYPE_F64
    jne .ee_fail
    # preserve result while restoring old axis
    mov edi,0x58
    call emit_u8
    mov edi,0x5D41
    call emit_u16
    mov edi,0x50
    call emit_u8
    mov eax,TYPE_F64
    jmp .ee_done

.ee_operator:
    mov rdi,r12
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .ee_fail
    mov r15,rax                     # op string node
    # args array
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .ee_fail
    cmp qword ptr [rax],J_ARRAY
    jne .ee_fail
    mov rbx,[rax+24]                # arg0
    test rbx,rbx
    jz .ee_fail

    # cast
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_cast]; mov ecx,v_cast_end-v_cast; call span_eq
    test eax,eax
    jz .ee_sqrt_probe
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_U64
    jne .ee_fail
    # pop rax; cvtsi2sd xmm0,rax; movq rax,xmm0; push rax
    lea rdi,[rip+code_cast_u64_f64]; mov esi,code_cast_u64_f64_end-code_cast_u64_f64; call emit_bytes
    inc dword ptr [rip+schedule_counts+4*3] # fp convert
    mov eax,TYPE_F64
    jmp .ee_done
.ee_sqrt_probe:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax
    jnz .ee_sqrt
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_square]; mov ecx,v_square_end-v_square; call span_eq
    test eax,eax
    jnz .ee_square
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_trunc]; mov ecx,v_trunc_end-v_trunc; call span_eq
    test eax,eax
    jnz .ee_trunc
    jmp .ee_eq
.ee_sqrt:
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_F64
    jne .ee_fail
    cmp qword ptr [rbx+32],0
    jne .ee_fail
    lea rdi,[rip+code_sqrt_f64]; mov esi,code_sqrt_f64_end-code_sqrt_f64; call emit_bytes
    inc dword ptr [rip+schedule_counts+8] # native sqrt: conservative long-latency FP bucket
    mov eax,TYPE_F64
    jmp .ee_done
.ee_square:
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_F64
    jne .ee_fail
    cmp qword ptr [rbx+32],0
    jne .ee_fail
    lea rdi,[rip+code_square_f64]; mov esi,code_square_f64_end-code_square_f64; call emit_bytes
    inc dword ptr [rip+schedule_counts+4]
    mov eax,TYPE_F64
    jmp .ee_done
.ee_trunc:
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_F64
    jne .ee_fail
    cmp qword ptr [rbx+32],0
    jne .ee_fail
    lea rdi,[rip+code_trunc_f64]; mov esi,code_trunc_f64_end-code_trunc_f64; call emit_bytes
    inc dword ptr [rip+schedule_counts+4*3]
    mov eax,TYPE_F64
    jmp .ee_done
.ee_eq:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax
    jz .ee_select
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_U64
    jne .ee_fail
    mov rbx,[rbx+32]
    test rbx,rbx
    jz .ee_fail
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_U64
    jne .ee_fail
    lea rdi,[rip+code_eq_u64]; mov esi,code_eq_u64_end-code_eq_u64; call emit_bytes
    inc dword ptr [rip+schedule_counts+4*4] # int compare/select
    mov eax,TYPE_U64
    jmp .ee_done
.ee_select:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax
    jz .ee_mod
    # cond, true, false
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_U64
    jne .ee_fail
    mov rbx,[rbx+32]; test rbx,rbx; jz .ee_fail
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    mov r12d,eax                    # branch type; safe? r12 held node, no longer needed below
    test eax,eax
    jz .ee_fail
    mov rbx,[rbx+32]; test rbx,rbx; jz .ee_fail
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,r12d
    jne .ee_fail
    lea rdi,[rip+code_select_bits]; mov esi,code_select_bits_end-code_select_bits; call emit_bytes
    inc dword ptr [rip+schedule_counts+4*4] # int select
    mov eax,r12d
    jmp .ee_done
.ee_mod:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax
    jz .ee_binary
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_U64
    jne .ee_fail
    mov rbx,[rbx+32]; test rbx,rbx; jz .ee_fail
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    cmp eax,TYPE_U64
    jne .ee_fail
    lea rdi,[rip+code_mod_u64]; mov esi,code_mod_u64_end-code_mod_u64; call emit_bytes
    inc dword ptr [rip+schedule_counts+4*6] # int div
    mov eax,TYPE_U64
    jmp .ee_done
.ee_binary:
    # classify op id in r12d: 1 add,2 sub,3 mul,4 div
    xor r12d,r12d
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz 1f; mov r12d,1; jmp 5f
1:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz 2f; mov r12d,2; jmp 5f
2:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz 3f; mov r12d,3; jmp 5f
3:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .ee_fail; mov r12d,4
5:
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    test eax,eax
    jz .ee_fail
    push rax
    mov rbx,[rbx+32]; test rbx,rbx; jz .ee_fail_poptype
    cmp qword ptr [rbx+32],0
    jne .ee_fail_poptype            # binary only
    mov rdi,rbx; mov rsi,r13; mov rdx,r14; call emit_expr
    pop rcx
    cmp eax,ecx
    jne .ee_fail
    cmp eax,TYPE_U64
    je .ee_bin_u64
    cmp eax,TYPE_F64
    jne .ee_fail
    cmp r12d,1; je .ee_fadd
    cmp r12d,2; je .ee_fsub
    cmp r12d,3; je .ee_fmul
    cmp r12d,4; je .ee_fdiv
    jmp .ee_fail
.ee_fadd: lea rdi,[rip+code_add_f64]; mov esi,code_add_f64_end-code_add_f64; call emit_bytes; inc dword ptr [rip+schedule_counts+0]; jmp .ee_fret
.ee_fsub: lea rdi,[rip+code_sub_f64]; mov esi,code_sub_f64_end-code_sub_f64; call emit_bytes; inc dword ptr [rip+schedule_counts+0]; jmp .ee_fret
.ee_fmul: lea rdi,[rip+code_mul_f64]; mov esi,code_mul_f64_end-code_mul_f64; call emit_bytes; inc dword ptr [rip+schedule_counts+4]; jmp .ee_fret
.ee_fdiv: lea rdi,[rip+code_div_f64]; mov esi,code_div_f64_end-code_div_f64; call emit_bytes; inc dword ptr [rip+schedule_counts+8]
.ee_fret: mov eax,TYPE_F64; jmp .ee_done
.ee_fail_poptype:
    add rsp,8
    jmp .ee_fail
.ee_bin_u64:
    cmp r12d,4
    je .ee_fail                     # integer div expressed only as mod in slice
    cmp r12d,1; je .ee_iadd
    cmp r12d,2; je .ee_isub
    cmp r12d,3; je .ee_imul
    jmp .ee_fail
.ee_iadd: lea rdi,[rip+code_add_u64]; mov esi,code_add_u64_end-code_add_u64; call emit_bytes; inc dword ptr [rip+schedule_counts+16]; jmp .ee_iret
.ee_isub: lea rdi,[rip+code_sub_u64]; mov esi,code_sub_u64_end-code_sub_u64; call emit_bytes; inc dword ptr [rip+schedule_counts+16]; jmp .ee_iret
.ee_imul: lea rdi,[rip+code_mul_u64]; mov esi,code_mul_u64_end-code_mul_u64; call emit_bytes; inc dword ptr [rip+schedule_counts+20]
.ee_iret: mov eax,TYPE_U64; jmp .ee_done
.ee_fail:
    xor eax,eax
.ee_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- code buffer helpers ----------------
.endm

.macro TFP_02_emit_fused_reduce_carrier
    push rbx
    mov ebx,edi
    cmp dword ptr [rip+vec_product_subtract_contractions],0
    je .efrc_frozen
    test ebx,ebx
    jnz .efrc_resident_1
    lea rdi,[rip+vec_fused_mask_reduce_resident_fragment]
    mov esi,vec_fused_mask_reduce_resident_fragment_end-vec_fused_mask_reduce_resident_fragment
    jmp .efrc_emit
.efrc_resident_1:
    lea rdi,[rip+vec_fused_mask_reduce_resident_carrier1_fragment]
    mov esi,vec_fused_mask_reduce_resident_carrier1_fragment_end-vec_fused_mask_reduce_resident_carrier1_fragment
    jmp .efrc_emit
.efrc_frozen:
    test ebx,ebx
    jnz .efrc_frozen_1
    lea rdi,[rip+vec_fused_mask_reduce_fragment]
    mov esi,vec_fused_mask_reduce_fragment_end-vec_fused_mask_reduce_fragment
    jmp .efrc_emit
.efrc_frozen_1:
    lea rdi,[rip+vec_fused_mask_reduce_carrier1_fragment]
    mov esi,vec_fused_mask_reduce_carrier1_fragment_end-vec_fused_mask_reduce_carrier1_fragment
.efrc_emit:
    call vec_emit_bytes
    pop rbx
    ret

# Full-packet Group reduction. Group guard proves every packet in the hot
# episode has all eight lanes, so tail-mask construction is dead work here.
.endm

.macro TFP_01_vec_fused_full_reduce_fragment
    vextractf64x4 ymm3,zmm0,1
    vaddpd ymm12,ymm12,ymm0
    vaddpd ymm12,ymm12,ymm3
.endm

.macro TFP_01_vec_fused_mask_reduce_fragment
    cmp r8,8
    jae .Lvfmr_full
    mov rcx,r8
    mov rax,1
    shl rax,cl
    dec rax
    kmovq k1,rax
    vmovapd zmm0{k1}{z},zmm0
.Lvfmr_full:
    vextractf64x4 ymm3,zmm0,1
    vaddpd ymm12,ymm12,ymm0
    vaddpd ymm12,ymm12,ymm3
.endm

.macro TFP_023_vec_fused_init_fragment
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
.endm

.macro TFP_01_vec_prefix_fragment
    jmp .Lvec_prefix_code
.Lvec_offsets:
    .quad 0,1,2,3,4,5,6,7
.Lvec_prefix_code:
    # Direct GPR-source broadcasts keep the 512-bit episode independent of
    # AVX512VL.  These are AVX512F forms and express the generic
    # scalar-to-vector-broadcast capability directly.
    vpbroadcastq zmm6,rsi
    vpaddq zmm6,zmm6,zmmword ptr [rip+.Lvec_offsets]
    vpbroadcastq zmm7,rdi
.endm

.macro TFP_123_tensor_prepare_binding_arena
    push rbx
    mov ebx,edi
    test ebx,ebx
    jz .tpba_fail
    mov rdi,[rip+tensor_bindings_ptr]
    test rdi,rdi
    jz .tpba_size
    mov rsi,[rip+tensor_binding_arena_bytes]
    mov eax,SYS_munmap
    syscall
.tpba_size:
    mov eax,ebx
    shl rax,6
    mov [rip+tensor_binding_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .tpba_fail
    mov [rip+tensor_bindings_ptr],rax
    mov dword ptr [rip+tensor_binding_capacity],ebx
    xor eax,eax
    pop rbx
    ret
.tpba_fail:
    mov eax,1
    pop rbx
    ret

# ---------------- binding lookup ----------------
# find_binding(rdi=nameptr,rsi=len) -> rax binding/0
.endm

.macro TFP_13_emit_int_reg
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13d,esi
    # literal
    mov rdi,r12; call expr_literal_u64
    test edx,edx
    jnz .eir_axis
    mov rsi,rax; mov edi,r13d; call gen_mov_ri64
    xor eax,eax; jmp .eir_done
.eir_axis:
    mov rdi,r12; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .eir_var
    mov edi,r13d; mov esi,8; call gen_mov_rr
    xor eax,eax; jmp .eir_done
.eir_var:
    mov rdi,r12; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eir_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_shape_product]; mov ecx,v_shape_product_end-v_shape_product; call span_eq
    test eax,eax; jz .eir_fail
    mov edi,r13d; mov esi,9; call gen_mov_rr
    xor eax,eax; jmp .eir_done
.eir_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eir_fail
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eir_fail
    mov r15,[rax+24]; test r15,r15; jz .eir_fail
    # One PredicateFact relation family for integer and floating values.
    # The operand type chooses only the physical compare recipe.
    xor ebx,ebx
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax; jz .eir_cmp_ne; mov ebx,0x94; jmp .eir_compare
.eir_cmp_ne:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ne]; mov ecx,v_ne_end-v_ne; call span_eq
    test eax,eax; jz .eir_cmp_lt; mov ebx,0x95; jmp .eir_compare
.eir_cmp_lt:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_lt]; mov ecx,v_lt_end-v_lt; call span_eq
    test eax,eax; jz .eir_cmp_le; mov ebx,0x92; jmp .eir_compare
.eir_cmp_le:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_le]; mov ecx,v_le_end-v_le; call span_eq
    test eax,eax; jz .eir_cmp_gt; mov ebx,0x96; jmp .eir_compare
.eir_cmp_gt:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_gt]; mov ecx,v_gt_end-v_gt; call span_eq
    test eax,eax; jz .eir_cmp_ge; mov ebx,0x97; jmp .eir_compare
.eir_cmp_ge:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ge]; mov ecx,v_ge_end-v_ge; call span_eq
    test eax,eax; jz .eir_select; mov ebx,0x93
.eir_compare:
    push rbx                       # relation code
    mov rbx,[r15+32]
    test rbx,rbx
    jz .eir_compare_drop_fail
    mov rdi,r15
    call expr_is_float_value
    test eax,eax
    jz .eir_compare_int
    call alloc_xmm; cmp eax,-1; je .eir_compare_drop_fail; mov r12d,eax
    call alloc_xmm; cmp eax,-1; je .eir_compare_fp_free_lhs_fail; mov r14d,eax
    mov rdi,r15; mov esi,r12d; call emit_float_reg; test eax,eax; jnz .eir_compare_fp_free2_fail
    mov rdi,rbx; mov esi,r14d; call emit_float_reg; test eax,eax; jnz .eir_compare_fp_free2_fail
    pop rcx
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call gen_ucomisd_setcc
    mov edi,r14d; call free_xmm
    mov edi,r12d; call free_xmm
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax; jmp .eir_done
.eir_compare_fp_free2_fail:
    mov edi,r14d; call free_xmm
.eir_compare_fp_free_lhs_fail:
    mov edi,r12d; call free_xmm
    add rsp,8
    jmp .eir_fail
.eir_compare_int:
    call alloc_gpr; cmp eax,-1; je .eir_compare_drop_fail; mov r12d,eax
    call alloc_gpr; cmp eax,-1; je .eir_compare_int_free_lhs_fail; mov r14d,eax
    mov rdi,r15; mov esi,r12d; call emit_int_reg; test eax,eax; jnz .eir_compare_int_free2_fail
    mov rdi,rbx; mov esi,r14d; call emit_int_reg; test eax,eax; jnz .eir_compare_int_free2_fail
    pop rcx
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call gen_cmp_setcc
    mov edi,r14d; call free_gpr
    mov edi,r12d; call free_gpr
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax; jmp .eir_done
.eir_compare_int_free2_fail:
    mov edi,r14d; call free_gpr
.eir_compare_int_free_lhs_fail:
    mov edi,r12d; call free_gpr
.eir_compare_drop_fail:
    add rsp,8
    jmp .eir_fail
.eir_select:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .eir_mod
    call alloc_gpr; cmp eax,-1; je .eir_fail; mov ebx,eax # cond
    call alloc_gpr; cmp eax,-1; je .eir_free_b_fail; mov r14d,eax # false
    mov rdi,r15; mov esi,ebx; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov r15,[r15+32]; test r15,r15; jz .eir_free2_fail
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov r15,[r15+32]; test r15,r15; jz .eir_free2_fail
    mov rdi,r15; mov esi,r14d; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov edi,ebx; call gen_test_rr
    mov edi,r13d; mov esi,r14d; call gen_cmovz
    mov edi,r14d; call free_gpr; mov edi,ebx; call free_gpr
    inc dword ptr [rip+schedule_counts+4*4] # int compare
    xor eax,eax; jmp .eir_done
.eir_mod:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .eir_binary
    mov rbx,[r15+32]; test rbx,rbx; jz .eir_fail
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .eir_mod_general
    test rax,rax; jz .eir_fail
    mov rcx,rax; dec rcx
    test rax,rcx; jnz .eir_mod_general
    mov r12,rcx
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_fail
    mov edi,4; mov esi,r13d; mov edx,r12d; call gen_alu_ri32
    inc dword ptr [rip+schedule_counts+4*4] # int ALU
    xor eax,eax; jmp .eir_done
.eir_mod_general:
    # numerator -> RAX, divisor -> temporary, div, remainder -> dst
    mov rdi,r15; xor esi,esi; call emit_int_reg; test eax,eax; jnz .eir_fail
    call alloc_gpr; cmp eax,-1; je .eir_fail; mov ebx,eax
    mov rdi,[r15+32]; mov esi,ebx; call emit_int_reg; test eax,eax; jnz .eir_free_b_fail
    # xor rdx,rdx
    mov edi,0x31; mov esi,2; mov edx,2; call gen_rr_opcode
    mov edi,ebx; call gen_div_reg
    mov edi,r13d; mov esi,2; call gen_mov_rr
    mov edi,ebx; call free_gpr
    inc dword ptr [rip+schedule_counts+4*6] # int div/mod
    xor eax,eax; jmp .eir_done
.eir_binary:
    # classify op in r14d
    xor ebx,ebx
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz 1f; mov ebx,1; jmp 4f
1:  mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz 2f; mov ebx,2; jmp 4f
2:  mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz .eir_fail; mov ebx,3
4:
    mov r14,[r15+32]; test r14,r14; jz .eir_fail
    # literal rhs fast path
    mov rdi,r14; call expr_literal_u64
    test edx,edx; jnz .eir_bin_reg
    mov r12,rax
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_fail
    cmp ebx,3; je .eir_mul_imm
    mov edi,0; cmp ebx,1; je 5f; mov edi,5
5:  mov esi,r13d; mov edx,r12d; call gen_alu_ri32
    inc dword ptr [rip+schedule_counts+4*4] # int ALU
    xor eax,eax; jmp .eir_done
.eir_mul_imm:
    mov edi,r13d; mov esi,r13d; mov edx,r12d; call gen_imul_ri32
    inc dword ptr [rip+schedule_counts+4*5] # int multiply
    xor eax,eax; jmp .eir_done
.eir_bin_reg:
    call alloc_gpr; cmp eax,-1; je .eir_fail; mov r12d,eax
    mov rdi,r15; mov esi,r13d; call emit_int_reg; test eax,eax; jnz .eir_free_r12_fail
    mov rdi,r14; mov esi,r12d; call emit_int_reg; test eax,eax; jnz .eir_free_r12_fail
    cmp ebx,3; je .eir_mul_reg
    mov edi,0x01; cmp ebx,1; je 6f; mov edi,0x29
6:  mov esi,r13d; mov edx,r12d; call gen_rr_opcode
    inc dword ptr [rip+schedule_counts+4*4] # int ALU
    jmp .eir_free_r12_ok
.eir_mul_reg:
    mov edi,r13d; mov esi,r12d; call gen_imul_rr
    inc dword ptr [rip+schedule_counts+4*5] # int multiply
.eir_free_r12_ok:
    mov edi,r12d; call free_gpr
    xor eax,eax; jmp .eir_done
.eir_free_r12_fail:
    mov edi,r12d; call free_gpr
    jmp .eir_fail
.eir_free2_fail:
    mov edi,r14d; call free_gpr
.eir_free_b_fail:
    mov edi,ebx; call free_gpr
.eir_fail:
    mov eax,1
.eir_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# emit_float_reg(rdi=expr object, esi=dst xmm) -> eax=0/1
.endm

.macro TFP_13_vec_interior_affine_residue_safe
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp dword ptr [rip+vec_interior_mode],1
    jne .viars_no
    cmp dword ptr [rip+vec_axis_root_valid],1
    jne .viars_no
    mov r12,rdi                    # local c
    mov r13,rsi                    # local signed d
    # composed C = local_c * root_c
    mov rax,r12
    mul qword ptr [rip+vec_axis_root_c]
    test rdx,rdx
    jnz .viars_no
    mov r14,rax                    # composed C
    test r14,r14
    js .viars_no                   # keep proof arithmetic in signed domain
    # composed D = local_c * root_d + local_d, checked as signed arithmetic.
    mov rax,qword ptr [rip+vec_axis_root_d]
    imul rax,r12
    jo .viars_no
    add rax,r13
    jo .viars_no
    mov r15,rax                    # composed signed D
    # Constant coordinate: 0 <= D < n_min proves validity for every runtime n.
    test r14,r14
    jnz .viars_nonzero_c
    test r15,r15
    js .viars_no
    cmp r15,qword ptr [rip+tensor_domain_min]
    jae .viars_no
    jmp .viars_yes
.viars_nonzero_c:
    # Minimum is at physical root=1: C + D must be non-negative.
    mov rax,r14
    add rax,r15
    jo .viars_no
    test rax,rax
    js .viars_no
    # Maximum is at root=n-2.  Require C*(n-2)+D < n for the
    # largest admitted n, equivalently (C-1)*n + D - 2*C < 0.
    mov rbx,r14
    dec rbx
    mov rax,qword ptr [rip+tensor_domain_max]
    test rax,rax
    js .viars_no
    imul rax,rbx
    jo .viars_no
    add rax,r15
    jo .viars_no
    mov rdx,r14
    add rdx,r14
    jo .viars_no
    sub rax,rdx
    jo .viars_no
    test rax,rax
    jns .viars_no
.viars_yes:
    mov eax,1
    jmp .viars_done
.viars_no:
    xor eax,eax
.viars_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# expr_affine_axis_interior_u64(rdi=expr) -> rax=c, rdx=d, ecx=1.
# Extends the globally-safe affine recognizer only inside INTERIOR_PROVEN. It
# may unwrap boundary-select forms already proven false there, normalize a
# dynamic periodic affine coordinate whose residue is proven in-range, and
# represent affine-literal subtraction with a two's-complement offset.
.endm

.macro TFP_13_expr_affine_axis_interior_u64
    push rbx
    push r12
    push r13
    push r14
    mov r12,rdi
    call expr_affine_axis_u64
    test ecx,ecx
    jnz .eaai_done
    cmp dword ptr [rip+vec_interior_mode],1
    jne .eaai_no
.eaai_mod:
    # periodic(expr,n) is canonical op=mod.  In the modulo ring, q*n vanishes.
    # Erase the physical modulo only if the remaining affine residue is proven
    # already inside [0,n) for every lane in this interior vector region.
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eaai_sub
    mov r13,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .eaai_sub
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eaai_sub
    mov r13,[rax+24]; test r13,r13; jz .eaai_sub
    mov r14,[r13+32]; test r14,r14; jz .eaai_sub
    cmp qword ptr [r14+32],0; jne .eaai_sub
    mov rdi,r14; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eaai_sub
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_shape_product]; mov ecx,v_shape_product_end-v_shape_product; call span_eq
    test eax,eax; jz .eaai_sub
    mov rdi,r13
    call expr_affine_modn_form
    test ecx,ecx; jz .eaai_sub
    mov r13,rax                    # local c
    mov r14,rdx                    # local signed d; q*n intentionally erased
    mov rdi,r13
    mov rsi,r14
    call vec_interior_affine_residue_safe
    test eax,eax; jz .eaai_sub
    mov rax,r13
    mov rdx,r14
    mov ecx,1
    jmp .eaai_done
.eaai_sub:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eaai_no
    mov rbx,rax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz .eaai_no
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eaai_no
    mov rbx,[rax+24]; test rbx,rbx; jz .eaai_no
    mov r12,[rbx+32]; test r12,r12; jz .eaai_no
    cmp qword ptr [r12+32],0; jne .eaai_no
    mov rdi,r12; call expr_literal_u64
    test edx,edx; jnz .eaai_no
    cmp rax,TENSOR_PHYSICAL_LANES-1
    ja .eaai_no
    push rax
    mov rdi,rbx; call expr_affine_axis_u64
    pop rbx
    test ecx,ecx; jz .eaai_no
    sub rdx,rbx
    mov ecx,1
    jmp .eaai_done
.eaai_no:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
.eaai_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Compose local index a*x+b with current logical axis c*root+d. The physical
# root axis remains ZMM6 because this mature tree deliberately retains the
# proven 1.0.9 runtime ABI/prefix instead of silently assuming the later
# cross-vector recurrence ABI.
.endm

.macro TFP_13_expr_affine_modn_form
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi

    # axis
    mov rdi,r12; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .eamf_var
    mov rax,1; xor edx,edx; xor r8d,r8d; mov ecx,1; jmp .eamf_done
.eamf_var:
    mov rdi,r12; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eamf_lit
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_shape_product]; mov ecx,v_shape_product_end-v_shape_product; call span_eq
    test eax,eax; jz .eamf_no
    xor eax,eax; xor edx,edx; mov r8,1; mov ecx,1; jmp .eamf_done
.eamf_lit:
    mov rdi,r12; call expr_literal_u64
    test edx,edx; jnz .eamf_op
    test rax,rax
    js .eamf_no                    # signed-offset proof domain
    mov rdx,rax; xor eax,eax; xor r8d,r8d; mov ecx,1; jmp .eamf_done
.eamf_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eamf_no
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eamf_no
    mov r14,[rax+24]; test r14,r14; jz .eamf_no
    mov r15,[r14+32]; test r15,r15; jz .eamf_no
    cmp qword ptr [r15+32],0; jne .eamf_no

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jnz .eamf_add
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jnz .eamf_sub
    # Integer affine modulo algebra must match u64 literals, not the f64
    # coefficient helper used by floating-point expression lowering.  Accept
    # mul(u64_literal, expr) and mul(expr, u64_literal) symmetrically.
    mov rdi,r14
    call expr_literal_u64
    test edx,edx
    jnz .eamf_mul_rhs_literal
    mov rbx,rax
    mov rdi,r15
    jmp .eamf_mul_recurse
.eamf_mul_rhs_literal:
    mov rdi,r15
    call expr_literal_u64
    test edx,edx; jnz .eamf_no
    mov rbx,rax
    mov rdi,r14
.eamf_mul_recurse:
    test rbx,rbx; js .eamf_no
    call expr_affine_modn_form
    test ecx,ecx; jz .eamf_no
    mov r13,rdx; mov r14,r8
    mul rbx                        # c *= literal
    test rdx,rdx; jnz .eamf_no
    mov r12,rax
    mov rax,r13
    imul rax,rbx
    jo .eamf_no
    mov r13,rax
    mov rax,r14
    imul rax,rbx
    jo .eamf_no
    mov r8,rax
    mov rax,r12; mov rdx,r13; mov ecx,1; jmp .eamf_done

.eamf_add:
    mov rdi,r14; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_no
    push rax; push rdx; push r8
    mov rdi,r15; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_add_fail
    mov rbx,rax; mov r12,rdx; mov r13,r8
    pop r8; pop rdx; pop rax
    add rax,rbx; jc .eamf_no
    add rdx,r12; jo .eamf_no
    add r8,r13; jo .eamf_no
    mov ecx,1; jmp .eamf_done
.eamf_add_fail:
    add rsp,24
    jmp .eamf_no

.eamf_sub:
    mov rdi,r14; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_no
    push rax; push rdx; push r8
    mov rdi,r15; call expr_affine_modn_form
    test ecx,ecx; jz .eamf_sub_fail
    mov rbx,rax; mov r12,rdx; mov r13,r8
    pop r8; pop rdx; pop rax
    cmp rax,rbx; jb .eamf_no       # negative axis coefficient not in this slice
    sub rax,rbx
    sub rdx,r12; jo .eamf_no
    sub r8,r13; jo .eamf_no
    mov ecx,1; jmp .eamf_done
.eamf_sub_fail:
    add rsp,24
    jmp .eamf_no
.eamf_no:
    xor eax,eax; xor edx,edx; xor r8d,r8d; xor ecx,ecx
.eamf_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Normalize a signed modular offset when the external extent is compile-time
# fixed. rdi=signed d -> rax=canonical 0..n-1, ecx=1; otherwise ecx=0.
.endm

.macro TFP_13_vec_modn_fixed_normalize_d
    mov r9,qword ptr [rip+tensor_domain_min]
    cmp r9,qword ptr [rip+tensor_domain_max]
    jne .vmfnd_no
    test r9,r9; jz .vmfnd_no
    mov rax,rdi
    test rax,rax
    js .vmfnd_neg
    xor edx,edx
    div r9
    mov rax,rdx
    mov ecx,1
    ret
.vmfnd_neg:
    neg rax
    xor edx,edx
    div r9
    test rdx,rdx
    jz .vmfnd_zero
    mov rax,r9
    sub rax,rdx
    mov ecx,1
    ret
.vmfnd_zero:
    xor eax,eax
    mov ecx,1
    ret
.vmfnd_no:
    xor eax,eax
    xor ecx,ecx
    ret

# expr_index_key_u64(rdi=expr) -> rax=affine coefficient, rdx=offset,
# r8=modulus token (0 for no modulo, literal divisor otherwise), ecx=1 success.
# This is a structural compiler key only; it emits no runtime work.
.endm

.macro TFP_13_expr_index_key_u64
    push rbx
    push r12
    push r13
    mov r12,rdi
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .eik_affine
    mov r13,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .eik_affine
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .eik_no
    mov r13,[rax+24]; test r13,r13; jz .eik_no
    mov rbx,[r13+32]; test rbx,rbx; jz .eik_no
    cmp qword ptr [rbx+32],0; jne .eik_no
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .eik_mod_n
    test rax,rax; jz .eik_no
    mov rbx,rax
    jmp .eik_have_mod
.eik_mod_n:
    mov rdi,rbx; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .eik_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_shape_product]; mov ecx,v_shape_product_end-v_shape_product; call span_eq
    test eax,eax; jz .eik_no
    mov rbx,-1
.eik_have_mod:
    cmp rbx,-1
    jne .eik_have_literal_mod
    mov rdi,r13
    call expr_affine_modn_form
    test ecx,ecx; jz .eik_no
    # q*n vanishes in the ring key. Canonicalize signed d when n is fixed; for
    # dynamic n retain the signed representative and let composition prove safety.
    push rax
    push rdx
    mov rdi,rdx
    call vec_modn_fixed_normalize_d
    test ecx,ecx
    jz .eik_dynamic_d
    mov rdx,rax
    pop rax                       # discard original d
    pop rax                       # restore c
    mov r8,-1
    mov ecx,1
    jmp .eik_done
.eik_dynamic_d:
    pop rdx
    pop rax
    mov r8,-1
    mov ecx,1
    jmp .eik_done
.eik_have_literal_mod:
    mov rdi,r13; call expr_affine_axis_u64
    test ecx,ecx; jz .eik_no
    mov r8,rbx
    mov ecx,1
    jmp .eik_done
.eik_affine:
    mov rdi,r12; call expr_affine_axis_u64
    test ecx,ecx; jz .eik_no
    xor r8d,r8d
    mov ecx,1
    jmp .eik_done
.eik_no:
    xor eax,eax
    xor edx,edx
    xor r8d,r8d
    xor ecx,ecx
.eik_done:
    pop r13
    pop r12
    pop rbx
    ret

# save/restore current axis YMM6 at a recursive map-load boundary.
.endm

.macro TFP_13_vec_emit_periodic_key
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12,rsi                    # c
    mov r13,rdx                    # d
    mov r14,rcx                    # mod token

    # One PeriodicAffineFact, two proof-selected physical realizations. The
    # reciprocal path remains the short form inside its strict exactness domain;
    # outside that domain exact integer ring arithmetic is the authority.
    cmp r14,-1
    jne .vepk_affine_emit_ready
    test r13,r13
    js .vepk_exact_n
    mov rax,r12
    mul qword ptr [rip+tensor_domain_max]
    test rdx,rdx
    jnz .vepk_exact_n
    add rax,r13
    jc .vepk_exact_n
    mov rdx,0x0020000000000000
    cmp rax,rdx
    jb .vepk_affine_emit_ready
    test rax,rax                   # signed integer->double realization domain
    js .vepk_exact_n
    mov rdx,qword ptr [rip+tensor_domain_max]
    mov rcx,0x0020000000000000
    cmp rdx,rcx
    jae .vepk_exact_n
    mov rcx,qword ptr [rip+tensor_domain_min]
    test rcx,rcx
    jz .vepk_exact_n
    xor edx,edx
    div rcx
    mov rdx,0x0010000000000000     # q_max < 2^52; reciprocal error < 2
    cmp rax,rdx
    jae .vepk_exact_n
    jmp .vepk_affine_emit_ready
.vepk_exact_n:
    mov edi,ebx
    mov rsi,r12
    mov rdx,r13
    call vec_emit_periodic_exact
    test eax,eax
    jnz .vepk_fail
    jmp .vepk_ok

.vepk_affine_emit_ready:
    # Reuse the pressure-safe affine emitter against an identity symbolic root.
    mov eax,dword ptr [rip+vec_axis_root_valid]; push rax
    mov rax,qword ptr [rip+vec_axis_root_c]; push rax
    mov rax,qword ptr [rip+vec_axis_root_d]; push rax
    mov dword ptr [rip+vec_axis_root_valid],1
    mov qword ptr [rip+vec_axis_root_c],1
    mov qword ptr [rip+vec_axis_root_d],0
    mov edi,ebx
    mov rsi,r12
    mov rdx,r13
    call vec_emit_affine_current
    mov r15d,eax
    pop rax; mov qword ptr [rip+vec_axis_root_d],rax
    pop rax; mov qword ptr [rip+vec_axis_root_c],rax
    pop rax; mov dword ptr [rip+vec_axis_root_valid],eax
    test r15d,r15d
    jnz .vepk_fail

    cmp r14,-1
    je .vepk_mod_n
    # Literal modulo: current vector ISA slice admits exact power-of-two rings.
    test r14,r14
    jz .vepk_ok
    lea rax,[r14-1]
    test rax,r14
    jnz .vepk_fail
    mov rsi,rax                    # mask=m-1
    call vec_const_intern
    cmp eax,-1; je .vepk_fail
    mov edx,eax
    mov edi,ebx
    mov esi,ebx
    call vec_vpandq_mem_const
    test eax,eax; jnz .vepk_fail
    jmp .vepk_ok

.vepk_mod_n:
    mov rax,r12
    add rax,r13
    jc .vepk_mod_n_wide
    mul qword ptr [rip+tensor_domain_max]
    test rdx,rdx
    jnz .vepk_mod_n_wide
    mov rdx,0x0004000000000000
    cmp rax,rdx
    jae .vepk_mod_n_wide
    call vec_alloc; cmp eax,-1; je .vepk_fail
    mov r15d,eax                   # quotient / q*n
    call vec_alloc; cmp eax,-1; je .vepk_free_q
    mov r14d,eax                   # correction temp
    mov edi,r15d; mov esi,ebx; call vec_vcvtqq2pd
    mov edi,0x59; mov esi,r15d; mov edx,r15d; mov ecx,15; mov r8d,1; call vec_vex2_rrr
    mov edi,r15d; mov esi,r15d; call vec_trunc_nonneg_pd_to_u64
    mov edi,r15d; mov esi,r15d; mov edx,r15d; mov ecx,7; call vec_vpmullq
    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,r15d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xFB; mov esi,r14d; mov edx,ebx; mov ecx,7; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; mov esi,ebx; mov edx,ebx; mov ecx,r14d; call vec_vpminuq
    mov edi,r14d; call vec_free
    mov edi,r15d; call vec_free
    jmp .vepk_ok
.vepk_mod_n_wide:
    mov edi,ebx
    call vec_emit_reciprocal_mod_wide
    test eax,eax
    jnz .vepk_fail
.vepk_ok:
    xor eax,eax
    jmp .vepk_done
.vepk_free_q:
    mov edi,r15d; call vec_free
.vepk_fail:
    mov eax,1
.vepk_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Compile-time tolerant linear aggregation.
#
# A structured FEM sum often reaches the backend as several direct wrapper maps
# whose leaves repeat the same indexed field value with different coefficients.
# Register CSE can only retain a handful of those values.  This pass instead
# combines coefficients before any machine instruction is emitted.  The key is
# exact and topology-aware: (binding identity, affine coefficient, offset,
# modulus token).  It is enabled only under the explicit tolerant FP contract;
# strict mode never enters this transformation.
#
# Mature 1.0.11 operator-subspace recovery. Solver/workload names are never
# inspected: this proves homogeneous linear structure under add/sub, literal
# scaling, exact power-of-two division and map loads.
.endm

.macro TFP_13_vec_linear_modulus_value
    cmp rdi,-1
    jne .vlmv_literal
    mov rax,qword ptr [rip+tensor_domain_min]
    cmp rax,qword ptr [rip+tensor_domain_max]
    jne .vlmv_no
    test rax,rax
    jz .vlmv_no
    mov ecx,1
    ret
.vlmv_literal:
    mov rax,rdi
    test rax,rax
    jz .vlmv_no
    mov ecx,1
    ret
.vlmv_no:
    xor eax,eax
    xor ecx,ecx
    ret

# Exact unsigned modular arithmetic helpers. Inputs are reduced before multiply,
# so the 128/64 quotient is always representable.
# vec_linear_mul_mod(rdi=a,rsi=b,rdx=m) -> rax=(a*b)%m
.endm

.macro TFP_13_vec_linear_compose_key
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi                    # local c
    mov r13,rsi                    # local d
    mov r14,rdx                    # local mod token
    mov r15,qword ptr [rip+vec_linear_ctx_mod]

    # Decide resulting modulus domain.
    test r15,r15
    jz .vlck_ctx_plain
    test r14,r14
    jz .vlck_no                    # cannot erase an existing representative mod
    cmp r14,r15
    je .vlck_mod_same
    # Distinct tokens are equivalent only when both resolve to the same fixed m.
    mov rdi,r14
    call vec_linear_modulus_value
    test ecx,ecx; jz .vlck_no
    mov rbx,rax
    mov rdi,r15
    call vec_linear_modulus_value
    test ecx,ecx; jz .vlck_no
    cmp rax,rbx
    jne .vlck_no
    mov r14,r15
    jmp .vlck_mod_domain
.vlck_mod_same:
    mov r14,r15
    jmp .vlck_mod_domain
.vlck_ctx_plain:
    test r14,r14
    jnz .vlck_mod_domain
    # Plain affine composition with exact overflow checks.
    mov rax,r12
    mul qword ptr [rip+vec_linear_ctx_c]
    test rdx,rdx; jnz .vlck_no
    mov r9,rax
    mov rax,r12
    mul qword ptr [rip+vec_linear_ctx_d]
    test rdx,rdx; jnz .vlck_no
    add rax,r13
    jc .vlck_no
    mov rdx,rax
    mov rax,r9
    xor r8d,r8d
    mov ecx,1
    jmp .vlck_done

.vlck_mod_domain:
    # If m is known, compute canonical residues with exact 128-bit modular math.
    mov rdi,r14
    call vec_linear_modulus_value
    test ecx,ecx
    jz .vlck_mod_symbolic
    mov rbx,rax                    # m
    mov rdi,r12
    mov rsi,qword ptr [rip+vec_linear_ctx_c]
    mov rdx,rbx
    call vec_linear_mul_mod
    mov r9,rax                     # composed c
    mov rdi,r12
    mov rsi,qword ptr [rip+vec_linear_ctx_d]
    mov rdx,rbx
    call vec_linear_mul_mod
    mov r10,rax
    mov rdi,r10
    mov rsi,r13
    mov rdx,rbx
    call vec_linear_add_mod
    mov rdx,rax                    # composed d
    mov rax,r9
    mov r8,r14
    mov ecx,1
    jmp .vlck_done

.vlck_mod_symbolic:
    # Dynamic external n: algebraic composition is valid in Z/nZ, but without a
    # fixed modulus only exact non-overflowing representatives are canonicalized.
    cmp r14,-1
    jne .vlck_no
    mov rax,r12
    mul qword ptr [rip+vec_linear_ctx_c]
    test rdx,rdx; jnz .vlck_no
    mov r9,rax
    mov rax,r12
    mul qword ptr [rip+vec_linear_ctx_d]
    test rdx,rdx; jnz .vlck_no
    add rax,r13
    jc .vlck_no
    mov rdx,rax
    mov rax,r9
    mov r8,r14
    mov ecx,1
    jmp .vlck_done
.vlck_no:
    xor eax,eax
    xor edx,edx
    xor r8d,r8d
    xor ecx,ecx
.vlck_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Caller sets vec_linear_term_mode before vec_linear_add_term. mode=1 means
# emit the base binding body under the composed root axis; mode=0 preserves the
# representative-load path.
# vec_linear_add_term(rdi=binding,rsi=c,rdx=d,rcx=mod,r8=expr,r9=coeff_bits)
# -> eax=0 success, 1 table full.
.endm

.macro TFP_123_vec_linear_emit_base_term
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi                    # binding
    mov r13d,esi                   # value dst
    mov r14,rdx                    # c
    mov r15,rcx                    # d
    mov rbx,r8                     # mod
    test rbx,rbx
    jnz .vlebt_periodic

    # Plain affine direction: bind the base body directly to its physical root.
    mov eax,dword ptr [rip+vec_axis_root_valid]; push rax
    mov rax,qword ptr [rip+vec_axis_root_c]; push rax
    mov rax,qword ptr [rip+vec_axis_root_d]; push rax
    mov dword ptr [rip+vec_axis_root_valid],1
    mov qword ptr [rip+vec_axis_root_c],r14
    mov qword ptr [rip+vec_axis_root_d],r15
    mov rdi,[r12+40]
    mov esi,r13d
    call emit_vec_float
    mov r10d,eax
    pop rax; mov qword ptr [rip+vec_axis_root_d],rax
    pop rax; mov qword ptr [rip+vec_axis_root_c],rax
    pop rax; mov dword ptr [rip+vec_axis_root_valid],eax
    mov eax,r10d
    jmp .vlebt_done

.vlebt_periodic:
    # Materialize the canonical periodic coordinate into a temporary vector axis,
    # then emit the same base body.  The body sees an ordinary physical axis and
    # cannot accidentally reapply the outer symbolic transform.
    call vec_alloc
    cmp eax,-1; je .vlebt_fail
    mov r11d,eax                   # index register
    # r11 is caller-saved.  Preserve the physical register identity across the
    # key-realization call; mathematical key equality must not depend on an
    # accidental caller-saved register lifetime.
    push rax
    mov edi,r11d
    mov rsi,r14
    mov rdx,r15
    mov rcx,rbx
    call vec_emit_periodic_key
    mov r10d,eax
    pop rax
    mov r11d,eax
    test r10d,r10d; jnz .vlebt_free_fail
    mov r14d,r11d                  # callee-saved owner for nested body emission
    mov eax,dword ptr [rip+vec_axis_reg]; push rax
    mov eax,dword ptr [rip+vec_axis_root_valid]; push rax
    mov rax,qword ptr [rip+vec_axis_root_c]; push rax
    mov rax,qword ptr [rip+vec_axis_root_d]; push rax
    mov dword ptr [rip+vec_axis_reg],r14d
    mov dword ptr [rip+vec_axis_root_valid],0
    mov rdi,[r12+40]
    mov esi,r13d
    call emit_vec_float
    mov r10d,eax
    pop rax; mov qword ptr [rip+vec_axis_root_d],rax
    pop rax; mov qword ptr [rip+vec_axis_root_c],rax
    pop rax; mov dword ptr [rip+vec_axis_root_valid],eax
    pop rax; mov dword ptr [rip+vec_axis_reg],eax
    mov edi,r14d
    call vec_free
    mov eax,r10d
    jmp .vlebt_done
.vlebt_free_fail:
    mov edi,r11d
    call vec_free
.vlebt_fail:
    mov eax,1
.vlebt_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_linear_try_emit(rdi=root,esi=dst) -> eax=0 emitted, 1 unsupported.
#
# retained parallel-preserving computation-elimination gate:
#   * work must strictly decrease (live topology leaves < raw leaves),
#   * no topology key may be created (zero fill-in by construction),
#   * no synchronization/global state is introduced (compile-time local pass),
#   * the emitted dependency span may not exceed the old tolerant single-chain
#     baseline.  Large reductions are striped over 4 independent FMA carriers,
#     then merged as a balanced 2-stage tree.  Thus elimination removes useful
#     arithmetic without converting available ILP into a hidden serial chain.
#
# The aggregation/proof tables are compile-time state only and emit no runtime
# metadata or synchronization instructions.
.endm

.macro TFP_23_tensor_prepare_optimizer_arena
    push rbx
    push r12
    mov rdi,qword ptr [rip+tensor_optimizer_arena_ptr]
    test rdi,rdi
    jz .tpoa_size
    mov rsi,qword ptr [rip+tensor_optimizer_arena_bytes]
    mov eax,SYS_munmap
    syscall
    mov qword ptr [rip+tensor_optimizer_arena_ptr],0
    mov qword ptr [rip+tensor_optimizer_arena_bytes],0
.tpoa_size:
    mov r12,qword ptr [rip+json_node_count]
    test r12,r12
    jz .tpoa_fail
    mov eax,0xffffffff
    cmp r12,rax
    ja .tpoa_fail
    mov dword ptr [rip+tensor_optimizer_capacity],r12d
    mov rsi,r12
    imul rsi,rsi,80                  # ten naturally aligned 8-byte lanes/fact
    jo .tpoa_fail
    add rsi,4095
    jc .tpoa_fail
    and rsi,-4096
    mov rbx,rsi
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .tpoa_fail
    mov qword ptr [rip+tensor_optimizer_arena_ptr],rax
    mov qword ptr [rip+tensor_optimizer_arena_bytes],rbx
    mov rdx,r12
    shl rdx,3
    mov qword ptr [rip+vec_const_bits_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_const_reg_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_const_addr_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_linear_binding_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_linear_key_a_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_linear_key_b_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_linear_key_c_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_linear_expr_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_linear_coeff_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_linear_mode_ptr],rax
    xor eax,eax
    pop r12
    pop rbx
    ret
.tpoa_fail:
    mov eax,1
    pop r12
    pop rbx
    ret
# compile_tensor_source(rdi=output_path) -> eax=0 success, nonzero failure
.endm

.macro TFP_23_vec_alloc
    mov eax,dword ptr [rip+vec_reg_mask]
    test eax,eax
    jz .va_try13
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+vec_reg_mask],eax
    mov eax,ecx
    cmp eax,11
    jne .va_ret_primary
    mov dword ptr [rip+vec11_borrowed],1
.va_ret_primary:
    ret
.va_try13:
    # AVX2 has no architectural high SIMD bank. YMM13 is the final phase-local
    # borrowable carrier; when it is live, pressure is explicit rather than
    # spilling into a copied ZMM16+ ownership fiction.
    cmp dword ptr [rip+vec13_free],0
    je .va_fail
    mov dword ptr [rip+vec13_free],0
    mov eax,13
    ret
.va_fail:
    mov eax,-1
    ret
.endm

.macro TFP_23_vec_free
    cmp edi,13
    je .vf_13
    cmp edi,N256_SIMD_REG_COUNT
    jae .vf_done
    bts dword ptr [rip+vec_reg_mask],edi
.vf_done:
    ret
.vf_13:
    mov dword ptr [rip+vec13_free],1
    ret

# Native256 has no persistent high-register CSE/cache domain; loads lower directly through the real YMM0..15 ownership set.

# Native256 constants have one authority: the RIP-relative immutable pool.
# No resident constant-register allocator exists on this physicalizer.

.endm

.macro TFP_23_vec_vex2_rrr
    # edi=opcode, esi=dst, edx=src1, ecx=src2, r8d=pp. VEX3 map 0F, L=256.
    push rbx
    mov ebx,edi
    mov r9d,esi
    mov r10d,edx
    mov r11d,ecx
    mov edi,0xC4; call vec_emit_u8
    mov eax,r9d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r11d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,r10d; not eax; and eax,0xF; shl eax,3
    or eax,0x04
    or eax,r8d
    mov edi,eax; call vec_emit_u8
    mov edi,ebx; call vec_emit_u8
    mov eax,r9d; and eax,7; shl eax,3
    mov ecx,r11d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    cmp ebx,0x58; je .v256_fp_add
    cmp ebx,0x5C; je .v256_fp_add
    cmp ebx,0x59; je .v256_fp_mul
    cmp ebx,0x5E; je .v256_fp_div
    inc dword ptr [rip+schedule_counts+4*4]
    jmp .v256_done
.v256_fp_add:
    inc dword ptr [rip+schedule_counts+0]
    jmp .v256_done
.v256_fp_mul:
    inc dword ptr [rip+schedule_counts+4]
    jmp .v256_done
.v256_fp_div:
    inc dword ptr [rip+schedule_counts+8]
.v256_done:
    pop rbx
    xor eax,eax
    ret

# Native unary vector sqrt on the existing AVX2 carrier. edi=dst, esi=src.
.endm

.macro TFP_23_vec_sqrtpd
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx; or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8       # W0, reserved vvvv, L256, pp=66
    mov edi,0x51; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+8]
    xor eax,eax
    pop r12; pop rbx; ret

.endm

.macro TFP_23_vec_mov_ext
    # VEX3 vmovdqa ymm dst,ymm src, physical registers 0..15.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x6F; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    pop rbx
    xor eax,eax
    ret

.endm

.macro TFP_23_vec_broadcast_imm64
    # Constants are deduplicated twice: once in the RIP-relative qword pool and,
    # when a persistent vector register is available, once in the physical
    # register file.  Reuses become a single register move instead of another
    # front-end broadcast/load.
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                     # requested destination
    mov r12,rsi                     # qword bits
    xor r13d,r13d
    mov ecx,dword ptr [rip+vec_const_count]
    mov r8,[rip+vec_const_bits_ptr]
.vbc_find:
    cmp r13d,ecx
    jae .vbc_new
    cmp qword ptr [r8+r13*8],r12
    je .vbc_have
    inc r13d
    jmp .vbc_find
.vbc_new:
    cmp ecx,dword ptr [rip+tensor_optimizer_capacity]
    jae .vbc_fail
    mov qword ptr [r8+rcx*8],r12
    mov r13d,ecx
    inc ecx
    mov dword ptr [rip+vec_const_count],ecx
.vbc_have:
    # Native256 has no resident constant domain. The deduplicated pool is the
    # sole immutable-constant authority, so broadcast directly from its index.
    mov edi,ebx
    call vec_emit_const_load_index
    jmp .vbc_done
.vbc_fail:
    mov eax,1
.vbc_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_const_intern(rsi=qword bits) -> eax constant-pool index or -1.
# Does not allocate a resident ZMM.  Used by memory-broadcast arithmetic so
# constants that miss the finite residency set can still be consumed directly
# from the RIP-relative pool without a synthetic broadcast temporary.
.endm

.macro TFP_23_vec_const_get_reg
    call vec_const_intern
    mov eax,-1
    ret

# vec_emit_const_load_index(edi=dst zmm, r13d=constant index)
.endm

.macro TFP_23_vec_emit_const_load_index
    # edi=dst YMM, r13d=constant index. AVX2 VPBROADCASTQ from RIP pool.
    push rbx
    push r12
    mov ebx,edi
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_cap_ok_1
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vecli256_fail
.tfix_cap_ok_1:
    mov r12d,eax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x60
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x59; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call vec_emit_u8
    mov rax,[rip+vec_emit_ptr]
    mov r8,qword ptr [rip+tensor_fixup_ptr_base]
    mov qword ptr [r8+r12*8],rax
    mov r8,qword ptr [rip+tensor_fixup_const_base]
    mov dword ptr [r8+r12*4],r13d
    lea rcx,[rax+4]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_12
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vecli256_fail
.tcgrow_ok_12:
    mov dword ptr [rax],0
    mov [rip+vec_emit_ptr],rcx
    inc dword ptr [rip+schedule_counts+4*7]
    inc dword ptr [rip+schedule_counts+4*8]
    xor eax,eax
    pop r12
    pop rbx
    ret
.vecli256_fail:
    mov eax,1
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vpmullq
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                    # destination
    mov r12d,edx                   # src1
    mov r13d,ecx                   # src2
    mov eax,dword ptr [rip+isa_cap_bits]
    test eax,ISA_CAP_I64_MUL_SYNTH
    jz .vml256_fail
    call vec_alloc
    cmp eax,-1
    je .vml256_fail
    mov r14d,eax

    # t = hi(a), ymm13 = hi(b)
    mov edi,r14d; mov esi,r12d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vml256_free_fail
    mov edi,13; mov esi,r13d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vml256_free_fail

    # t = hi(a)*lo(b) + lo(a)*hi(b)
    mov edi,r14d; mov edx,r14d; mov ecx,r13d; call vec_vpmuludq
    test eax,eax; jnz .vml256_free_fail
    mov edi,13; mov edx,r12d; mov ecx,13; call vec_vpmuludq
    test eax,eax; jnz .vml256_free_fail
    mov edi,0xD4; mov esi,r14d; mov edx,r14d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    mov edi,r14d; mov esi,r14d; mov edx,32; call vec_vpsllq_imm
    test eax,eax; jnz .vml256_free_fail

    # ymm13 = lo(a)*lo(b); dst = cross<<32 + low product.
    mov edi,13; mov edx,r12d; mov ecx,r13d; call vec_vpmuludq
    test eax,eax; jnz .vml256_free_fail
    mov edi,0xD4; mov esi,ebx; mov edx,r14d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    mov edi,r14d; call vec_free
    xor eax,eax
    jmp .vml256_done
.vml256_free_fail:
    mov edi,r14d; call vec_free
.vml256_fail:
    mov eax,1
.vml256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vpsllq_imm
    # AVX2 VPSLLQ ymm dst,ymm src,imm8. destination in VEX.vvvv.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov r11d,edx
    mov edi,0xC4; call vec_emit_u8
    mov eax,0xC0
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x05
    mov edi,eax; call vec_emit_u8
    mov edi,0x73; call vec_emit_u8
    mov eax,r10d; and eax,7; or eax,0xF0
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret

.endm

.macro TFP_23_vec_vpsrlq_imm
    # AVX2 VPSRLQ ymm dst,ymm src,imm8. destination in VEX.vvvv.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov r11d,edx
    mov edi,0xC4; call vec_emit_u8
    mov eax,0xC0
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x05
    mov edi,eax; call vec_emit_u8
    mov edi,0x73; call vec_emit_u8
    mov eax,r10d; and eax,7; or eax,0xD0
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret

.endm

.macro TFP_23_vec_vpaddq_mem_const
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vcm256_fail_0
    mov edi,0xd4; mov esi,ebx; mov edx,r12d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vcm256_done_0
.vcm256_fail_0:
    mov eax,1
.vcm256_done_0:
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vpandq_mem_const
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vcm256_fail_1
    mov edi,0xdb; mov esi,ebx; mov edx,r12d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vcm256_done_1
.vcm256_fail_1:
    mov eax,1
.vcm256_done_1:
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vpmullq_mem_const
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    call vec_alloc
    cmp eax,-1; je .vmulc256_fail
    mov r14d,eax
    mov edi,r14d; call vec_emit_const_load_index
    test eax,eax; jnz .vmulc256_free_fail
    mov edi,ebx; mov esi,ebx; mov edx,r12d; mov ecx,r14d
    call vec_vpmullq
    mov r15d,eax
    mov edi,r14d; call vec_free
    mov eax,r15d
    jmp .vmulc256_done
.vmulc256_free_fail:
    mov edi,r14d; call vec_free
.vmulc256_fail:
    mov eax,1
.vmulc256_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vpmullq_mem_const_native
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    # Preflight the complete 10-byte EVEX RIP-relative instruction before
    # touching the fixup table or the hot-code cursor.
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+10]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_14
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmqmc_native_fail
.tcgrow_ok_14:
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_direct_ok_1
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmqmc_native_fail
.tfix_direct_ok_1:
    push rax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    # P0: dst R/R', memory X/B=1, map=0F38(2).
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,2
    mov edi,eax; call vec_emit_u8
    # P1/P2 match the validated EVEX vpmullq register form, with qword BCST.
    mov eax,r12d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x50
    mov edi,eax; call vec_emit_u8
    mov edi,0x40; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call vec_emit_u8
    pop rax
    mov r8,qword ptr [rip+tensor_fixup_ptr_base]
    mov rcx,[rip+vec_emit_ptr]
    mov qword ptr [r8+rax*8],rcx
    mov r8,qword ptr [rip+tensor_fixup_const_base]
    mov dword ptr [r8+rax*4],r13d
    lea r8,[rcx+4]
    cmp r8,[rip+vec_emit_end]
    jbe .tcgrow_ok_15
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmqmc_native_fail_nostack
.tcgrow_ok_15:
    mov dword ptr [rcx],0
    mov [rip+vec_emit_ptr],r8
    inc dword ptr [rip+schedule_counts+4*5] # AVX-512 integer multiply
    inc dword ptr [rip+schedule_counts+4*7] # qword constant load
    inc dword ptr [rip+schedule_counts+4*8] # RIP-relative AGU
    xor eax,eax
    jmp .vpmqmc_native_done
.vpmqmc_native_fail:
    mov eax,1
    jmp .vpmqmc_native_done
.vpmqmc_native_fail_nostack:
    mov eax,1
.vpmqmc_native_done:
    pop r13
    pop r12
    pop rbx
    ret

# vec_mul_const_strength(edi=dst, esi=src, rdx=constant) -> eax=0 emitted,
# eax=1 unsupported. Exact for u64 wrap semantics.  Only transformations that
# reduce this target's hot instruction count are enabled: zero, one, and exact
# powers of two.  Two-instruction 2^k +/- 1 rewrites were measured slower than
# one vpmullq on the validated Zen 4 host and are deliberately not emitted.
.endm

.macro TFP_23_vec_mul_const_strength
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                    # dst
    mov r12d,esi                   # src
    mov r13,rdx                    # unsigned constant
    test r13,r13
    jnz .vmcs256_one
    mov edi,0xEF; mov esi,ebx; mov edx,r12d; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs256_done
.vmcs256_one:
    cmp r13,1
    jne .vmcs256_pow2
    cmp ebx,r12d
    je .vmcs256_ok
    mov edi,ebx; mov esi,r12d; call vec_mov_ext
.vmcs256_ok:
    xor eax,eax
    jmp .vmcs256_done
.vmcs256_pow2:
    lea rax,[r13-1]
    test rax,r13
    jnz .vmcs256_minus1
    bsf rcx,r13
    mov edi,ebx; mov esi,r12d; mov edx,ecx; call vec_vpsllq_imm
    xor eax,eax
    jmp .vmcs256_done

    # c = 2^k - 1
.vmcs256_minus1:
    lea rax,[r13+1]
    test rax,rax
    jz .vmcs256_plus1
    lea rcx,[rax-1]
    test rcx,rax
    jnz .vmcs256_plus1
    bsf r14,rax
    mov edi,13; mov esi,r12d; call vec_mov_ext
    mov edi,ebx; mov esi,13; mov edx,r14d; call vec_vpsllq_imm
    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs256_done

    # c = 2^k + 1
.vmcs256_plus1:
    cmp r13,2
    jbe .vmcs256_horner_gate
    lea rax,[r13-1]
    lea rcx,[rax-1]
    test rcx,rax
    jnz .vmcs256_horner_gate
    bsf r14,rax
    mov edi,13; mov esi,r12d; call vec_mov_ext
    mov edi,ebx; mov esi,13; mov edx,r14d; call vec_vpsllq_imm
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs256_done

.vmcs256_horner_gate:
    cmp r13,0xFFFF
    ja .vmcs256_unsupported
    mov edi,13; mov esi,r12d; call vec_mov_ext
    bsr r14,r13
    mov edi,ebx; mov esi,13; call vec_mov_ext
    dec r14
.vmcs256_horner:
    test r14,r14
    js .vmcs256_horner_done
    mov edi,ebx; mov esi,ebx; mov edx,1; call vec_vpsllq_imm
    bt r13,r14
    jnc .vmcs256_horner_next
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
.vmcs256_horner_next:
    dec r14
    jmp .vmcs256_horner
.vmcs256_horner_done:
    xor eax,eax
    jmp .vmcs256_done
.vmcs256_unsupported:
    mov eax,1
.vmcs256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vmulpd_mem_const
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vcm256_fail_2
    mov edi,0x59; mov esi,ebx; mov edx,r12d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vcm256_done_2
.vcm256_fail_2:
    mov eax,1
.vcm256_done_2:
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vfmadd231pd
    # VEX3 map 0F38 W=1 VFMADD231PD ymm dst,src1,src2.
    push rbx
    mov ebx,esi
    mov r10d,edx
    mov r11d,ecx
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r11d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov eax,r10d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov edi,0xB8; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r11d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+0]
    inc dword ptr [rip+schedule_counts+4]
    pop rbx
    xor eax,eax
    ret

.endm

.macro TFP_23_vec_vfmadd231pd_mem_const
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vfmac256_fail
    mov edi,ebx; mov esi,ebx; mov edx,r12d; mov ecx,13; call vec_vfmadd231pd
    test eax,eax; jnz .vfmac256_fail
    xor eax,eax
    jmp .vfmac256_done
.vfmac256_fail:
    mov eax,1
.vfmac256_done:
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vpminuq
    # Exact AVX2 unsigned qword min using sign-bias + signed compare.
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,esi                    # dst
    mov r12d,edx                   # a
    mov r14d,ecx                   # b
    mov rsi,0x8000000000000000
    call vec_const_intern
    cmp eax,-1; je .vmin256_fail
    mov r13d,eax
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vmin256_fail
    call vec_alloc
    cmp eax,-1; je .vmin256_fail
    mov r15d,eax
    # temp = a ^ sign; ymm13 = b ^ sign
    mov edi,0xEF; mov esi,r15d; mov edx,r12d; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,0xEF; mov esi,13; mov edx,r14d; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    # temp = (a > b) unsigned mask
    mov edi,0x37; mov esi,r15d; mov edx,r15d; mov ecx,13; mov r8d,1; call vec_vex3_0f38_rrr
    # ymm13 = mask & b; dst = ~mask & a; dst |= ymm13
    mov edi,0xDB; mov esi,13; mov edx,r15d; mov ecx,r14d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xDF; mov esi,ebx; mov edx,r15d; mov ecx,r12d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xEB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,r15d; call vec_free
    xor eax,eax
    jmp .vmin256_done
.vmin256_fail:
    mov eax,1
.vmin256_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vcvtqq2pd_synth
    # Exact signed i64 -> f64 using one allocator temp.
    # Caller-generated uses have distinct dst/src. YMM13 is the native256 fixed
    # physical scratch and never owns semantic state.
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                    # destination
    mov r12d,esi                   # source
    cmp ebx,r12d
    je .vcq2pds256_fail

    call vec_alloc
    cmp eax,-1
    je .vcq2pds256_fail
    mov r13d,eax                   # one allocator-owned temporary

    mov rsi,0x41F0000000000000     # exact binary64 2^32
    call vec_const_intern
    cmp eax,-1
    je .vcq2pds256_free_fail
    mov r14d,eax

    # temp = high signed dword source; YMM13 = low-dword sign bit.
    mov edi,r13d; mov esi,r12d; mov edx,32; call vec_vpsrlq_imm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,13; mov esi,r12d; mov edx,31; call vec_vpsrld_imm
    test eax,eax; jnz .vcq2pds256_free_fail

    # Convert high32 first, then retain the double vector in temp.
    mov edi,ebx; mov esi,r13d; call vec_vpmovqd_ymm_from_zmm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,ebx; mov esi,ebx; call vec_vcvtdq2pd_zmm_from_ymm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,r13d; mov esi,ebx; call vec_mov_ext

    # Convert low32 sign correction. Multiplying it by 2^32 may clobber YMM13
    # inside the constant helper, which is fine after the packed sign is in dst.
    mov edi,ebx; mov esi,13; call vec_vpmovqd_ymm_from_zmm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,ebx; mov esi,ebx; call vec_vcvtdq2pd_zmm_from_ymm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,ebx; mov esi,ebx; mov edx,r14d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vcq2pds256_free_fail

    # Low signed dword -> YMM13, then add correction to form unsigned low32.
    mov edi,13; mov esi,r12d; call vec_vpmovqd_ymm_from_zmm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,13; mov esi,13; call vec_vcvtdq2pd_zmm_from_ymm
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr

    # high32*2^32 + unsigned_low32. Final add is the sole int64->f64 rounding.
    mov edi,r13d; mov esi,r13d; mov edx,r14d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vcq2pds256_free_fail
    mov edi,0x58; mov esi,ebx; mov edx,ebx; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr

    mov edi,r13d; call vec_free
    xor eax,eax
    jmp .vcq2pds256_done
.vcq2pds256_free_fail:
    mov edi,r13d; call vec_free
.vcq2pds256_fail:
    mov eax,1
.vcq2pds256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_vpmovqd_ymm_from_zmm
    # Pack low dword of four qword lanes into XMM dst.
    # dst must differ from src. The destination itself receives the high 128
    # half first, then VSHUFPS combines low(src) and high(src). No hidden YMM
    # scratch is consumed, which is important on AVX2's 16-register file.
    push rbx
    mov ebx,edi
    mov r10d,esi
    cmp ebx,r10d
    je .vpack256_fail

    # vextracti128 xmmDST,ymmSRC,1
    mov edi,0xC4; call vec_emit_u8
    mov eax,r10d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40                    # X unused -> inverted one
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,3                       # map 0F3A
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8 # L=256, pp=66
    mov edi,0x39; call vec_emit_u8
    mov eax,r10d; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,1; call vec_emit_u8

    # vshufps xmmDST,xmmSRC,xmmDST,0x88
    # => [src.d0,src.d2,upper.d0,upper.d2] = four low qword dwords.
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1                       # map 0F
    mov edi,eax; call vec_emit_u8
    mov eax,r10d; not eax; and eax,0xF; shl eax,3
    mov edi,eax; call vec_emit_u8  # L=128, pp=none
    mov edi,0xC6; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,0x88; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax
    pop rbx
    ret
.vpack256_fail:
    mov eax,1
    pop rbx
    ret

.endm

.macro TFP_23_vec_vcvtdq2pd_zmm_from_ymm
    # AVX VCVTDQ2PD ymmDST,xmmSRC.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0x7E; call vec_emit_u8
    mov edi,0xE6; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3]
    pop rbx
    xor eax,eax
    ret

.endm

.macro TFP_23_vec_vpsrld_imm
    # AVX2 VPSRLD ymm dst,ymm src,imm8.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov r11d,edx
    mov edi,0xC4; call vec_emit_u8
    mov eax,0xC0
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x05
    mov edi,eax; call vec_emit_u8
    mov edi,0x72; call vec_emit_u8
    mov eax,r10d; and eax,7; or eax,0xD0
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret

# Scalar f64 carrier truncate toward zero. edi=dst xmm, esi=src xmm.
# SSE4.1 ROUNDSD is emitted directly; this is the same old register-native lane.
.endm

.macro TFP_23_vec_vrndscalepd_trunc
    # AVX VROUNDPD ymmDST,ymmSRC,truncate.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,3
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x09; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,3; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3]
    pop rbx
    xor eax,eax
    ret

.endm

.macro TFP_23_vec_vaddpd_mem_const
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vcm256_fail_3
    mov edi,0x58; mov esi,ebx; mov edx,r12d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vcm256_done_3
.vcm256_fail_3:
    mov eax,1
.vcm256_done_3:
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_cmp_eq_maskvec
    # AVX2 VPCMPEQQ yields an all-ones/zero YMM predicate directly.
    push rbx
    mov ebx,edi
    mov r9d,esi
    mov r10d,edx
    mov edi,0x29
    mov esi,ebx
    mov edx,r9d
    mov ecx,r10d
    mov r8d,1
    call vec_vex3_0f38_rrr
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret

# vec_cmp_f64_maskvec(edi=dst, esi=lhs, edx=rhs, ecx=VCMPPD predicate imm8)
# AVX2 materializes the all-ones/zero PredicateFact vector directly.
.endm

.macro TFP_23_vec_cmp_f64_maskvec
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov r14d,ecx
    mov edi,0xC2
    mov esi,ebx
    mov edx,r12d
    mov ecx,r13d
    mov r8d,1
    call vec_vex2_rrr
    test eax,eax
    jnz .vcf256_fail
    mov edi,r14d
    call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    xor eax,eax
    jmp .vcf256_done
.vcf256_fail:
    mov eax,1
.vcf256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_vec_emit_affine_current
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12,rsi
    mov r13,rdx
    cmp dword ptr [rip+vec_axis_root_valid],1
    jne .veac_fail
    # composed coefficient
    mov rax,r12
    mul qword ptr [rip+vec_axis_root_c]
    test rdx,rdx
    jnz .veac_fail
    mov r14,rax
    # composed offset, exact modulo-2^64 in the interior proof domain
    mov rax,r12
    mul qword ptr [rip+vec_axis_root_d]
    add rax,r13
    mov r13,rax

    # Native256 has no spare persistent carrier domain; realize the affine relation directly.
    mov dword ptr [rip+vec_affine_induct_reg],-1

    # Preflight immutable coefficient operand. Zero/one/power-of-two are handled
    # without a constant operand by vec_mul_const_strength.
    mov r15d,0x7fffffff
    cmp dword ptr [rip+vec_affine_induct_reg],-1
    jne .veac_c_ready
    test r14,r14
    jz .veac_c_ready
    cmp r14,1
    je .veac_c_ready
    lea rax,[r14-1]
    test rax,r14
    jz .veac_c_ready
    mov rsi,r14
    call vec_const_get_reg
    cmp eax,-1
    jne .veac_c_resident
    mov rsi,r14
    call vec_const_intern
    cmp eax,-1
    je .veac_fail
    or eax,0x80000000
.veac_c_resident:
    mov r15d,eax
.veac_c_ready:
    # Preflight immutable offset operand. Prefer a resident ZMM, but spill the
    # immutable value to a RIP-relative qword broadcast instead of abandoning
    # the symbolic-coordinate lowering when the resident pool is full.
    mov r12d,0x7fffffff
    test r13,r13
    jz .veac_fixup_preflight
    mov rsi,r13
    call vec_const_get_reg
    cmp eax,-1
    jne .veac_d_resident
    mov rsi,r13
    call vec_const_intern
    cmp eax,-1
    je .veac_fail
    or eax,0x80000000
.veac_d_resident:
    mov r12d,eax

.veac_fixup_preflight:
    # Memory-broadcast operands each consume one existing constant-pool fixup.
    # Reject before emitting the affine hot path if that bounded table cannot
    # represent the proven expression; never half-emit and then fall back.
    xor ecx,ecx
    test r15d,r15d
    jns .veac_fixup_offset
    inc ecx
.veac_fixup_offset:
    test r12d,r12d
    jns .veac_fixup_check
    inc ecx
.veac_fixup_check:
    mov eax,dword ptr [rip+vec_fixup_count]
    add eax,ecx
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jbe .tfix_preflight_ok_1
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .veac_fail
.tfix_preflight_ok_1:

    # coefficient application. A reserved induction carrier replaces repeated
    # c*root multiplication while preserving the exact same integer value.
    mov eax,dword ptr [rip+vec_affine_induct_reg]
    cmp eax,-1
    je .veac_no_induct
    mov edi,ebx
    mov esi,eax
    call vec_mov_ext
    jmp .veac_have_product
.veac_no_induct:
    test r14,r14
    jnz .veac_nonzero_c
    mov rsi,r13
    mov edi,ebx
    call vec_broadcast_imm64
    jmp .veac_done
.veac_nonzero_c:
    mov edi,ebx; mov esi,6; mov rdx,r14
    call vec_mul_const_strength
    test eax,eax
    jz .veac_have_product
    test r15d,r15d
    js .veac_mul_mem
    cmp r15d,0x7fffffff
    je .veac_fail
    mov edi,ebx; mov esi,ebx; mov edx,6; mov ecx,r15d
    call vec_vpmullq
    jmp .veac_have_product
.veac_mul_mem:
    mov edx,r15d
    and edx,0x7fffffff
    mov edi,ebx
    mov esi,6
    call vec_vpmullq_mem_const
    test eax,eax
    jnz .veac_fail
.veac_have_product:
    test r13,r13
    jz .veac_ok
    test r12d,r12d
    js .veac_add_mem
    cmp r12d,0x7fffffff
    je .veac_fail
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    jmp .veac_ok
.veac_add_mem:
    mov edx,r12d
    and edx,0x7fffffff
    mov edi,ebx
    mov esi,ebx
    call vec_vpaddq_mem_const
    test eax,eax
    jnz .veac_fail
.veac_ok:
    xor eax,eax
    jmp .veac_done
.veac_fail:
    mov eax,1
.veac_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# expr_affine_modn_form(rdi=expr) -> rax=c, rdx=signed d, r8=signed q,
# ecx=1 for the exact integer form c*axis + q*n + d.  This is generic ring
# algebra used both by vector modulo proof and canonical operator keys.
.endm

.macro TFP_23_vec_try_float_source
    push rbx
    push r12
    mov rbx,rdi
    mov rdi,rbx; call expr_literal_f64_bits
    test edx,edx; jnz .vtfs_load
    mov rsi,rax
    call vec_const_get_reg
    jmp .vtfs_done
.vtfs_load:
    # No resident native256 source exists beyond the active operand set.
    jmp .vtfs_no
.vtfs_no:
    mov eax,-1
.vtfs_done:
    pop r12
    pop rbx
    ret

# emit_vec_int(rdi=expr, esi=dst ymm low) -> eax 0/1
.endm

.macro TFP_23_vec_stack_spill_push_128
    push rbx
    mov ebx,edi
    mov edi,0x48; call vec_emit_u8
    mov edi,0x83; call vec_emit_u8
    mov edi,0xEC; call vec_emit_u8
    mov edi,0x20; call vec_emit_u8
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x61
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x11; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x04
    mov edi,eax; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*7]
    xor eax,eax
    pop rbx
    ret

.endm

.macro TFP_23_vec_stack_spill_pop_128
    push rbx
    mov ebx,edi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x61
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x10; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x04
    mov edi,eax; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x83; call vec_emit_u8
    mov edi,0xC4; call vec_emit_u8
    mov edi,0x20; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*7]
    xor eax,eax
    pop rbx
    ret

# emit_vec_float(rdi=expr, esi=dst ymm low) -> eax 0/1
.endm

.macro TFP_23_emit_u8
    mov rax,[rip+emit_ptr]
    cmp rax,[rip+emit_end]
    jb .tcgrow_ok_16
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_16:
    mov [rax],dil
    inc rax
    mov [rip+emit_ptr],rax
    xor eax,eax
    ret
.eu_fail: mov eax,1; ret
.endm

.macro TFP_23_emit_u16
    mov rax,[rip+emit_ptr]; lea rcx,[rax+2]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_17
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_17:
    mov [rax],di; mov [rip+emit_ptr],rcx; xor eax,eax; ret
.endm

.macro TFP_23_emit_u24
    mov rax,[rip+emit_ptr]; lea rcx,[rax+3]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_18
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_18:
    mov [rax],di; shr edi,16; mov [rax+2],dil; mov [rip+emit_ptr],rcx; xor eax,eax; ret
.endm

.macro TFP_23_emit_u40
    mov rax,[rip+emit_ptr]; lea rcx,[rax+5]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_19
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_19:
    mov [rax],edi; shr rdi,32; mov [rax+4],dil; mov [rip+emit_ptr],rcx; xor eax,eax; ret
.endm

.macro TFP_23_emit_push_imm64
    push rdi
    mov edi,0xB848                  # 48 b8
    call emit_u16
    pop rdi
    mov rax,[rip+emit_ptr]; lea rcx,[rax+8]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_20
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .epi_fail
.tcgrow_ok_20:
    mov [rax],rdi; mov [rip+emit_ptr],rcx
    mov edi,0x50
    call emit_u8
    ret
.epi_fail: mov eax,1; ret
# emit_bytes(rdi=src,esi=len)
.endm

.macro TFP_23_emit_bytes
    mov rax,[rip+emit_ptr]
    mov ecx,esi
    lea rdx,[rax+rcx]
    cmp rdx,[rip+emit_end]
    jbe .tcgrow_ok_21
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eb_fail
.tcgrow_ok_21:
    mov r8,rdi
.eb_loop:
    test ecx,ecx
    jz .eb_done
    mov dil,[r8]
    mov [rax],dil
    inc r8
    inc rax
    dec ecx
    jmp .eb_loop
.eb_done:
    mov [rip+emit_ptr],rax
    xor eax,eax
    ret
.eb_fail: mov eax,1; ret

# ---------------- output image ----------------
.endm

.macro TFP_23_emit_fused_vector_body
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rdi,[rip+vec_fused_boundary_test_zero_fragment]
    mov esi,vec_fused_boundary_test_zero_fragment_end-vec_fused_boundary_test_zero_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efvb_fail
    call vec_emit_je_placeholder
    test rax,rax; jz .efvb_fail
    mov [rip+vec_fused_safe_zero_disp],rax
    lea rdi,[rip+vec_fused_boundary_test_end_fragment]
    mov esi,vec_fused_boundary_test_end_fragment_end-vec_fused_boundary_test_end_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efvb_fail
    call vec_emit_jae_placeholder
    test rax,rax; jz .efvb_fail
    mov [rip+vec_fused_safe_end_disp],rax
    mov dword ptr [rip+vec_interior_mode],1
    mov rax,[rip+tensor_reduce_binding]
    mov rdi,[rax+40]
    xor esi,esi
    call emit_vec_float
    test eax,eax; jnz .efvb_fail
    call vec_emit_jmp_placeholder
    test rax,rax; jz .efvb_fail
    mov [rip+vec_fused_common_disp],rax
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_safe_zero_disp]
    call vec_patch_rel32
    test eax,eax; jnz .efvb_fail
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_safe_end_disp]
    call vec_patch_rel32
    test eax,eax; jnz .efvb_fail
    mov dword ptr [rip+vec_interior_mode],0
    mov rax,[rip+tensor_reduce_binding]
    mov rdi,[rax+40]
    xor esi,esi
    call emit_vec_float
    test eax,eax; jnz .efvb_fail
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_common_disp]
    call vec_patch_rel32
    test eax,eax; jnz .efvb_fail
    xor eax,eax
    jmp .efvb_done
.efvb_fail:
    mov eax,1
.efvb_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.endm

.macro TFP_23_emit_fused_reduce_carrier_full
    test edi,edi
    jnz .efrcf_1
    lea rdi,[rip+vec_fused_full_reduce_fragment]
    mov esi,vec_fused_full_reduce_fragment_end-vec_fused_full_reduce_fragment
    jmp vec_emit_bytes
.efrcf_1:
    lea rdi,[rip+vec_fused_full_reduce_carrier1_fragment]
    mov esi,vec_fused_full_reduce_carrier1_fragment_end-vec_fused_full_reduce_carrier1_fragment
    jmp vec_emit_bytes

.endm

.macro TFP_23_vec_emit_group_guard
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+13]
    cmp rcx,[rip+vec_emit_end]
    jbe .vegg_space
    mov dword ptr [rip+tensor_code_overflow],1
    xor eax,eax
    ret
.vegg_space:
    mov word ptr [rax],0xB848
    mov rdx,4
    mov ecx,dword ptr [rip+physical_realize_group_body]
    imul rdx,rcx
    mov qword ptr [rax+2],rdx
    mov byte ptr [rax+10],0x49
    mov byte ptr [rax+11],0x39
    mov byte ptr [rax+12],0xC0
    lea rdx,[rax+13]
    mov [rip+vec_emit_ptr],rdx
    call vec_emit_jb_placeholder
    ret

# Advance coordinates by one native256 packet inside a proven full Group.
# The Group episode owns remaining-count updates and completion proof.
.endm

.macro TFP_23_vec_emit_group_countdown_backedge
    push rbx
    mov edx,4
    mov eax,dword ptr [rip+physical_realize_group_body]
    imul rdx,rax
    test rdx,rdx
    jz .vegcb_fail
    cmp rdx,0x7fffffff              # x86-64 imm32 sign-extension proof
    ja .vegcb_fail
    mov rax,[rip+vec_emit_ptr]
    lea rbx,[rax+14]
    cmp rbx,[rip+vec_emit_end]
    jbe .vegcb_space
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vegcb_fail
.vegcb_space:
    mov byte ptr [rax+0],0x49       # sub r8,imm32
    mov byte ptr [rax+1],0x81
    mov byte ptr [rax+2],0xE8
    mov dword ptr [rax+3],edx
    mov byte ptr [rax+7],0x49       # cmp r8,imm32
    mov byte ptr [rax+8],0x81
    mov byte ptr [rax+9],0xF8
    mov dword ptr [rax+10],edx
    mov [rip+vec_emit_ptr],rbx
    call vec_emit_jae_placeholder
    test rax,rax
    jz .vegcb_fail
    mov rdi,rax
    mov rsi,[rip+vec_group_body_start]
    call vec_patch_rel32
    test eax,eax
    jnz .vegcb_fail
    xor eax,eax
    pop rbx
    ret
.vegcb_fail:
    mov eax,1
    pop rbx
    ret

.endm

.macro TFP_23_vec_fused_mask_reduce_fragment
    jmp .Lvfmr256_code
.Lvfmr256_lanes:
    .quad 0,1,2,3
.Lvfmr256_code:
    cmp r8,4
    jae .Lvfmr256_full
    vmovq xmm10,r8
    vpbroadcastq ymm10,xmm10
    vpcmpgtq ymm10,ymm10,ymmword ptr [rip+.Lvfmr256_lanes]
    vandpd ymm0,ymm0,ymm10
.Lvfmr256_full:
    vaddpd ymm12,ymm12,ymm0
.endm

.macro TFP_23_vec_fused_mask_reduce_resident_fragment
    cmp r8,4
    jae .Lvfmrr256_full
    vmovq xmm10,r8
    vpbroadcastq ymm10,xmm10
    vpcmpgtq ymm10,ymm10,ymmword ptr [rip+.Lvfmr256_lanes]
    vandpd ymm0,ymm0,ymm10
.Lvfmrr256_full:
    vaddpd ymm12,ymm12,ymm0
.endm

.macro TFP_23_vec_fused_mask_reduce_carrier1_fragment
    jmp .Lvfmr1_256_code
.Lvfmr1_256_lanes:
    .quad 0,1,2,3
.Lvfmr1_256_code:
    cmp r8,4
    jae .Lvfmr1_256_full
    vmovq xmm10,r8
    vpbroadcastq ymm10,xmm10
    vpcmpgtq ymm10,ymm10,ymmword ptr [rip+.Lvfmr1_256_lanes]
    vandpd ymm0,ymm0,ymm10
.Lvfmr1_256_full:
    vaddpd ymm11,ymm11,ymm0
.endm

.macro TFP_23_vec_fused_finish_resident_fragment
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
.endm

.macro TFP_23_vec_fused_finish_dual_fragment
    vaddpd ymm12,ymm12,ymm11
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
.endm

.macro TFP_23_vec_fused_init_resident_fragment
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
.endm

.macro TFP_23_vec_fused_init_dual_fragment
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
    vxorpd ymm11,ymm11,ymm11
.endm

.macro TFP_23_vec_prefix_fragment
    jmp .Lvec_prefix256_code
.Lvec_offsets256:
    .quad 0,1,2,3
.Lvec_prefix256_code:
    vmovq xmm6,rsi
    vpbroadcastq ymm6,xmm6
    vpaddq ymm6,ymm6,ymmword ptr [rip+.Lvec_offsets256]
    vmovq xmm7,rdi
    vpbroadcastq ymm7,xmm7
.endm


# Exact unsigned qword >= PredicateFact used by the shared integer periodic
# realization.  AVX-512 reuses native unsigned min; AVX2 sign-biases into its
# existing signed compare. Neither profile introduces a runtime selector.
.macro TFP_01_vec_cmp_ge_u64_maskvec
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,ebx; mov esi,ebx; mov edx,r12d; mov ecx,r13d
    call vec_vpminuq
    test eax,eax
    jnz .vcge512_fail
    mov edi,ebx; mov esi,ebx; mov edx,r13d
    call vec_cmp_eq_maskvec
    jmp .vcge512_done
.vcge512_fail:
    mov eax,1
.vcge512_done:
    pop r13
    pop r12
    pop rbx
    ret
.endm

.macro TFP_23_vec_cmp_ge_u64_maskvec
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                    # mask destination (not YMM13)
    mov r12d,esi                   # a
    mov r14d,edx                   # b
    cmp ebx,13
    je .vcge256_fail
    mov rsi,0x8000000000000000
    call vec_const_intern
    cmp eax,-1
    je .vcge256_fail
    mov r13d,eax
    mov edi,13
    call vec_emit_const_load_index
    test eax,eax
    jnz .vcge256_fail
    # dst=a^sign; ymm13=b^sign.
    mov edi,0xEF; mov esi,ebx; mov edx,r12d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    mov edi,0xEF; mov esi,13; mov edx,r14d; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    # dst=(b>a) signed after bias, then invert -> a>=b.
    mov edi,0x37; mov esi,ebx; mov edx,13; mov ecx,ebx; mov r8d,1
    call vec_vex3_0f38_rrr
    mov edi,0x29; mov esi,13; mov edx,13; mov ecx,13; mov r8d,1
    call vec_vex3_0f38_rrr
    mov edi,0xEF; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vcge256_done
.vcge256_fail:
    mov eax,1
.vcge256_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.endm
