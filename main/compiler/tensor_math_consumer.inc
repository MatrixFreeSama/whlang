# Tensor consumes the same physical mathematical entities as General/Field.
# The operand is completed once; only the primitive may contract to scalar.
# No polynomial, argument reduction, workload selector or runtime cache here.

.macro TMC_scalar_probe
.efr_math_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov edx,64
    call physical_math_fragment
    test rax,rax; jz .efr_select_probe
    cmp qword ptr [r15+32],0; jne .efr_fail
    push rax; push rcx
    mov rdi,r15; mov esi,r13d; call emit_float_reg
    test eax,eax; jnz .efr_math_child_fail
    mov edi,0x50; call emit_u8
    mov edi,r13d; mov esi,1; call tensor_math_scalar_slot
    mov rdi,[rsp+8]; mov esi,[rsp]; call emit_bytes
    test eax,eax; jnz .efr_math_child_fail
    mov edi,r13d; xor esi,esi; call tensor_math_scalar_slot
    mov edi,0x58; call emit_u8
    add rsp,16; xor eax,eax; jmp .efr_done
.efr_math_child_fail:
    add rsp,16; jmp .efr_fail
.endm

.macro TMC_vector_probe
.evf_math_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov edx,64
    call physical_math_fragment
    test rax,rax; jz .evf_select_probe
    cmp qword ptr [r15+32],0; jne .evf_fail
    push rdx
    mov rdi,r15; call tensor_math_has_axis
    test eax,eax; jz .evf_math_child_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_math_child_fail
    mov edx,-1
.if TENSOR_PHYSICAL_LANES == 8
    mov rax,[rip+tensor_math_projection_request]
    test rax,rax; jz 1f
    cmp [rax+8],r12; jne 1f
    mov edx,[rax+24]
1:
.endif
    mov edi,r13d; mov esi,[rsp]; call tensor_math_packet
    add rsp,8; jmp .evf_done
.evf_math_child_fail:
    add rsp,8; jmp .evf_fail
.endm

.macro TMC_functions
# Invocation-invariant math requires a lifetime owner outside the Axis episode.
# Until Tensor consumes that shared authority, reject this unrepresented slice;
# WH admission retains its proven General consumer. No runtime polling cache.
tensor_math_has_axis:
    push rbx
    mov rbx,rdi
    mov rdi,rbx; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jnz .tmha_yes
    mov rdi,rbx; lea rsi,[rip+k_indices]; mov edx,k_indices_end-k_indices; call obj_get
    test rax,rax; jnz .tmha_array
    mov rdi,rbx; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .tmha_no
.tmha_array:
    mov rbx,[rax+24]
.tmha_loop:
    test rbx,rbx; jz .tmha_no
    mov rdi,rbx; call tensor_math_has_axis
    test eax,eax; jnz .tmha_yes
    mov rbx,[rbx+32]; jmp .tmha_loop
.tmha_no: xor eax,eax; pop rbx; ret
.tmha_yes: mov eax,1; pop rbx; ret

# edi=XMM, esi=store. Shared scalar primitive preserves all vector/GPR owners.
tensor_math_scalar_slot:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov edi,0xf2; call emit_u8
    test ebx,8; jz 1f
    mov edi,0x44; call emit_u8
1:  mov edi,0x0f; call emit_u8
    lea edi,[r12+0x10]; call emit_u8
    mov edi,ebx; and edi,7; shl edi,3; or edi,4; call emit_u8
    mov edi,0x24; call emit_u8
    pop r12; pop rbx; ret

# edi=SIMD, esi=disp32, edx=store. Payload width follows the physical profile.
tensor_math_packet_slot:
    sub rsp,16
    mov ecx,edx; mov edx,esi; mov esi,TENSOR_PHYSICAL_LANES*8
    mov r8,rsp; call physical_encode_simd_rsp
    test eax,eax; jz 1f
    mov rdi,rsp; mov esi,eax; call vec_emit_bytes
    add rsp,16; ret
1:  mov eax,1; add rsp,16; ret

# edi=bytes, esi=release. No compressed immediate/displacement width limits.
tensor_math_stack_adjust:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov edi,0x48; call vec_emit_u8
    mov edi,0x81; call vec_emit_u8
    mov edi,0xec; test r12d,r12d; jz 1f
    mov edi,0xc4
1:  call vec_emit_u8
    mov edi,ebx; call vec_emit_u8
    mov edi,ebx; shr edi,8; call vec_emit_u8
    mov edi,ebx; shr edi,16; call vec_emit_u8
    mov edi,ebx; shr edi,24; call vec_emit_u8
    pop r12; pop rbx; ret

# edi=completed destination carrier, esi=canonical mathematical ordinal.
tensor_math_packet:
    push rbx; push r12; push r13; push r14; push r15; sub rsp,16
    mov r12d,edi; mov ebx,esi; mov [rsp+8],edx
    mov edi,esi; mov esi,64; mov edx,TENSOR_PHYSICAL_LANES
    cmp dword ptr [rsp+8],0; jl 1f
    call physical_math_packet_dual_fragment_by_id
    test rax,rax; jz .tmp_bad
    jmp 2f
1:  call physical_math_packet_fragment_by_id
    test rax,rax; jz .tmp_scalar
2:
    mov r14,rax; mov r15d,ecx
    # Reserved axis/extent/reduction owners plus allocated temporaries.
    # High-bank owners survive the fragment untouched. The result owner is dead
    # after its operand is placed at offset zero, so it does not need restoring.
    mov r13d,[rip+vec_reg_mask]; not r13d; and r13d,0x0f3e
    or r13d,[rip+tensor_expression_live]
    or r13d,0x10c0
.if TENSOR_PHYSICAL_LANES == 8
    cmp dword ptr [rip+vec13_free],0; jne 1f
    or r13d,0x2000
.endif
1:  and r13d,r8d; btr r13d,r12d
    mov [rsp],r13d
    mov edx,r13d; xor eax,eax
    test edx,edx; jz .tmp_count_done
1: lea ecx,[rdx-1]; and edx,ecx
    inc eax; test edx,edx; jnz 1b
 .tmp_count_done:
    inc eax
    cmp dword ptr [rsp+8],0; jl 1f
    inc eax
1:  imul eax,TENSOR_PHYSICAL_LANES*8
    mov [rsp+4],eax
    mov edi,eax; xor esi,esi; call tensor_math_stack_adjust
    mov edi,r12d; xor esi,esi; mov edx,1; call tensor_math_packet_slot
    mov ebx,TENSOR_PHYSICAL_LANES*8
    cmp dword ptr [rsp+8],0; jl 1f
    add ebx,TENSOR_PHYSICAL_LANES*8
1:
.tmp_save:
    test r13d,r13d; jz .tmp_execute
    bsf edi,r13d; btr r13d,edi
    mov esi,ebx; mov edx,1; call tensor_math_packet_slot
    add ebx,TENSOR_PHYSICAL_LANES*8; jmp .tmp_save
.tmp_execute:
    mov rdi,r14; mov esi,r15d; call vec_emit_bytes
    test eax,eax; jnz .tmp_bad
    mov r13d,[rsp]; mov ebx,TENSOR_PHYSICAL_LANES*8
    cmp dword ptr [rsp+8],0; jl 1f
    add ebx,TENSOR_PHYSICAL_LANES*8
1:
.tmp_restore:
    test r13d,r13d; jz .tmp_result
    bsf edi,r13d; btr r13d,edi
    mov esi,ebx; xor edx,edx; call tensor_math_packet_slot
    add ebx,TENSOR_PHYSICAL_LANES*8; jmp .tmp_restore
.tmp_result:
    mov edi,r12d; xor esi,esi; xor edx,edx; call tensor_math_packet_slot
    mov edi,[rsp+8]; test edi,edi; js 1f
    mov esi,TENSOR_PHYSICAL_LANES*8; xor edx,edx; call tensor_math_packet_slot
1:  mov edi,[rsp+4]; mov esi,1; call tensor_math_stack_adjust
    xor eax,eax; jmp .tmp_done
.tmp_scalar:
    mov edi,ebx; mov esi,64; call physical_math_fragment_by_id
    test rax,rax; jz .tmp_bad
    mov r14,rax; mov r15d,ecx
    mov edi,TENSOR_PHYSICAL_LANES*8+8; xor esi,esi; call tensor_math_stack_adjust
    mov edi,r12d; mov esi,8; mov edx,1; call tensor_math_packet_slot
    xor ebx,ebx
.tmp_lane:
    # Each natural f64 lane is consumed through the same scalar fragment.
    # One fixed ABI slot contracts the completed payload. Keep RSP stable
    # between primitives; fewer PUSH/POP bytes lengthen its dependency chain.
    mov edi,0x48; call vec_emit_u8
    mov edi,0x8b; call vec_emit_u8; mov edi,0x44; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8; lea edi,[rbx*8+8]; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x89; call vec_emit_u8; mov edi,4; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8
    mov rdi,r14; mov esi,r15d; call vec_emit_bytes
    test eax,eax; jnz .tmp_bad
    mov edi,0x48; call vec_emit_u8
    mov edi,0x8b; call vec_emit_u8; mov edi,4; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x89; call vec_emit_u8; mov edi,0x44; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8; lea edi,[rbx*8+8]; call vec_emit_u8
    inc ebx; cmp ebx,TENSOR_PHYSICAL_LANES; jb .tmp_lane
    mov edi,r12d; mov esi,8; xor edx,edx; call tensor_math_packet_slot
    mov edi,TENSOR_PHYSICAL_LANES*8+8; mov esi,1; call tensor_math_stack_adjust
    xor eax,eax; jmp .tmp_done
.tmp_bad: mov eax,1
.tmp_done:
    add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret
.endm

.macro TMC_equal_operands
    mov rdi,r15; mov rsi,r14; xor edx,edx; call physical_value_expr_equal
    test eax,eax; jz .Ltmc_distinct\@
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_fail
    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r13d; mov r8d,1
    call vec_vex2_rrr
    jmp .evf_done
.Ltmc_distinct\@:
.endm

.pushsection .bss
.p2align 2
tensor_expression_live:.skip 4
.popsection
