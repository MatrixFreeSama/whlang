.intel_syntax noprefix
.include "compiler/physical_reality.inc"
# Wheelchair 1.2.17 sovereign materialized-field compiler frontend with locality compression.
# Canonical format: wheelchair.field/1.  The op graph is compile-time only;
# generated executables contain direct SIMD machine instructions, never an
# interpreter, bytecode dispatcher, C/LLVM/JIT backend, or scalar fallback.

.equ SYS_write,1
.equ SYS_mmap,9
.equ SYS_munmap,11
.equ SYS_openat,257
.equ SYS_pwrite64,18
.equ SYS_fchmod,91
.equ SYS_close,3
.equ AT_FDCWD,-100
.equ OUT_FLAGS,577
.equ PROT_READ_WRITE,3
.equ MAP_PRIVATE_ANON,0x22
.equ J_OBJECT,1
.equ J_ARRAY,2
.equ J_STRING,3
.equ J_NUMBER,4
.equ OP_SIZE,32
.equ OP_LOAD,1
.equ OP_CONST,2
.equ OP_ADD,3
.equ OP_SUB,4
.equ OP_MUL,5
.equ OP_DIV,6
.equ OP_STORE,7
.equ OP_REDUCE,8
.equ OP_MOV,9
.equ OP_IINDEX,10
.equ OP_IADD_CONST,11
.equ OP_ISUB_CONST,12
.equ OP_IMUL_CONST,13
.equ OP_IDIV_CONST,14
.equ OP_IMOD_CONST,15
.equ OP_ITOF32,16
.equ OP_FMA_ACC,17
.equ OP_SQRT,18
.equ OP_TRUNC,19
.equ OP_NOP,0
.equ FF_VREG_BASE,1
.equ FF_VREG_COUNT,4
.equ FF_VREG_MAX,3
# FF_VREG_BASE remains the mature native512 contiguous mapping.
# Native256 uses an explicit physical-carrier table because helper, mask, and
# persistent-index ownership make a contiguous four-register bank impossible.
.equ FF_PRELOAD_SCRATCH,1
.equ MODE_INPUT,0
.equ MODE_OUTPUT,1
.equ MODE_INOUT,2
.equ FF_CACHE_NONE,-1
.equ FF_TRAFFIC_QUANTUM_ELEMENTS,(PRC_TRAFFIC_LINE_BYTES/4)

# Map one logical v0..v3 ID already present in REG32 to its physical SIMD carrier.
# Native512 expands to the historical add-one mapping, preserving generated 512
# code. Native256 consumes one explicit ownership table with no runtime branch.
.macro FF_MAP_VREG reg32, reg64
.if FIELD_LANES == 16
    add \reg32,FF_VREG_BASE
.else
    lea rax,[rip+ff_vreg_phys_table]
    movzx \reg32,byte ptr [rax+\reg64]
.endif
.endm

.extern source_ptr
.extern source_length
.extern json_skip_ws
.extern json_parse_value
.extern obj_get
.extern span_eq
.extern node_parse_u64
.extern node_parse_f64_bits
.extern jcur
.extern jend
.extern json_node_count
.extern json_prepare_arena
.extern execution_admission_capacity
.extern outward_materialization_ticks
.extern fabric_target_facts_proved
.extern sd_static_placement_required
.extern sd_preferred_l3_mask_bytes
.extern sd_preferred_l3_mask
.extern field_runtime_template_blob
.extern field_runtime_template_blob_end
.extern group_body_factor
.extern group_carrier_factor
.extern group_relation_mask
.extern group_lane_factor

.global compile_field_source
# compile_field_source(rdi=output path) -> eax 0 success, 1 reject
compile_field_source:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [rip+ff_output_path],rdi
    mov qword ptr [rip+ff_code_growth_factor],64
.ffs_retry:
    mov dword ptr [rip+ff_code_overflow],0
    mov dword ptr [rip+ff_field_count],0
    mov dword ptr [rip+ff_access_count],0
    mov dword ptr [rip+ff_op_count],0
    mov dword ptr [rip+ff_reduce_count],0
    mov dword ptr [rip+ff_fp_tolerant],0
    mov dword ptr [rip+ff_arith_fma_fused_count],0
    mov qword ptr [rip+ff_common_rank],0
    mov qword ptr [rip+ff_access_delta_stride],0
    mov dword ptr [rip+ff_const_pool_count],0
    mov dword ptr [rip+ff_addr_pool_count],0
    mov rdi,[rip+source_length]
    call ff_prepare_code_arena
    test eax,eax; jnz .ffs_bad_final

    mov qword ptr [rip+json_node_count],0
    call json_prepare_arena
    test eax,eax; jnz .ffs_bad
    mov rax,[rip+source_ptr]; mov [rip+jcur],rax
    add rax,[rip+source_length]; mov [rip+jend],rax
    call json_parse_value
    test rax,rax; jz .ffs_bad
    mov r12,rax
    call json_skip_ws
    mov rax,[rip+jcur]; cmp rax,[rip+jend]; jne .ffs_bad
    cmp qword ptr [r12],J_OBJECT; jne .ffs_bad
    mov rdi,[rip+json_node_count]
    call ff_prepare_graph_arena
    test eax,eax; jnz .ffs_bad
    mov rdi,[rip+json_node_count]
    call ff_prepare_instance_arena
    test eax,eax; jnz .ffs_bad

    # format == wheelchair.field/1
    mov rdi,r12; lea rsi,[rip+k_format]; mov edx,k_format_end-k_format; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_STRING; jne .ffs_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_field_format]; mov ecx,v_field_format_end-v_field_format; call span_eq
    test eax,eax; jz .ffs_bad

    # contracts.floating_point is optional strict/tolerant; both preserve direct
    # f32 semantics here.  Tolerant may be used by future fusion but never causes
    # hidden f64 promotion.
    mov rdi,r12; lea rsi,[rip+k_contracts]; mov edx,k_contracts_end-k_contracts; call obj_get
    test rax,rax; jz .ffs_fields
    cmp qword ptr [rax],J_OBJECT; jne .ffs_bad
    mov rdi,rax; lea rsi,[rip+k_floating_point]; mov edx,k_floating_point_end-k_floating_point; call obj_get
    test rax,rax; jz .ffs_fields
    cmp qword ptr [rax],J_STRING; jne .ffs_bad
    mov r13,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_strict]; mov ecx,v_strict_end-v_strict; call span_eq
    test eax,eax; jnz .ffs_fields
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+v_tolerant]; mov ecx,v_tolerant_end-v_tolerant; call span_eq
    test eax,eax; jz .ffs_bad
    mov dword ptr [rip+ff_fp_tolerant],1

.ffs_fields:
    mov rdi,r12; lea rsi,[rip+k_fields]; mov edx,k_fields_end-k_fields; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_ARRAY; jne .ffs_bad
    mov r13,[rax+24]
.ffs_field_loop:
    test r13,r13; jz .ffs_fields_done
    mov eax,dword ptr [rip+ff_field_count]; cmp eax,dword ptr [rip+ff_instance_capacity]; jae .ffs_bad
    cmp qword ptr [r13],J_OBJECT; jne .ffs_bad
    mov ebx,eax
    # type=f32
    mov rdi,r13; lea rsi,[rip+k_type]; mov edx,k_type_end-k_type; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_STRING; jne .ffs_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_f32]; mov ecx,v_f32_end-v_f32; call span_eq
    test eax,eax; jz .ffs_bad
    # mode
    mov rdi,r13; lea rsi,[rip+k_mode]; mov edx,k_mode_end-k_mode; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_STRING; jne .ffs_bad
    mov r14,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_input]; mov ecx,v_input_end-v_input; call span_eq
    test eax,eax; jnz .ffs_mode_in
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_output]; mov ecx,v_output_end-v_output; call span_eq
    test eax,eax; jnz .ffs_mode_out
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_inout]; mov ecx,v_inout_end-v_inout; call span_eq
    test eax,eax; jz .ffs_bad
    mov dl,MODE_INOUT; jmp .ffs_mode_set
.ffs_mode_in: mov dl,MODE_INPUT; jmp .ffs_mode_set
.ffs_mode_out: mov dl,MODE_OUTPUT
.ffs_mode_set:
    mov rax,[rip+ff_field_mode_ptr]; mov [rax+rbx],dl
    # rank is one invocation-wide RankFact.  There is no language rank cap:
    # the parsed machine-word cardinality determines all axis metadata geometry.
    mov rdi,r13; lea rsi,[rip+k_rank]; mov edx,k_rank_end-k_rank; call obj_get
    call node_parse_u64; test edx,edx; jnz .ffs_bad
    test rax,rax; jz .ffs_bad
    mov rcx,[rip+ff_common_rank]
    test rcx,rcx
    jz .ffs_rank_first
    cmp rcx,rax
    jne .ffs_bad
    jmp .ffs_rank_ready
.ffs_rank_first:
    mov [rip+ff_common_rank],rax
.ffs_rank_ready:
    inc dword ptr [rip+ff_field_count]
    mov r13,[r13+32]; jmp .ffs_field_loop
.ffs_fields_done:
    cmp dword ptr [rip+ff_field_count],0; je .ffs_bad
    call ff_prepare_axis_arena
    test eax,eax; jnz .ffs_bad

    # accesses. access 0 is required to be identity because output stores use it.
    mov rdi,r12; lea rsi,[rip+k_accesses]; mov edx,k_accesses_end-k_accesses; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_ARRAY; jne .ffs_bad
    mov r13,[rax+24]
.ffs_access_loop:
    test r13,r13; jz .ffs_access_done
    mov eax,dword ptr [rip+ff_access_count]; cmp eax,dword ptr [rip+ff_instance_capacity]; jae .ffs_bad
    mov ebx,eax
    cmp qword ptr [r13],J_OBJECT; jne .ffs_bad
    mov rdi,r13; lea rsi,[rip+k_field]; mov edx,k_field_end-k_field; call obj_get
    call node_parse_u64; test edx,edx; jnz .ffs_bad
    cmp eax,dword ptr [rip+ff_field_count]; jae .ffs_bad
    mov rdx,[rip+ff_access_field_ptr]; mov [rdx+rbx],al
    # delta array exact current field rank
    mov rdi,r13; lea rsi,[rip+k_delta]; mov edx,k_delta_end-k_delta; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_ARRAY; jne .ffs_bad
    mov r14,[rax+24]
    mov r15,[rip+ff_common_rank]
    xor r11d,r11d
.ffs_delta_loop:
    cmp r11d,r15d; jae .ffs_delta_end
    test r14,r14; jz .ffs_bad
    mov rdi,r14; call ff_parse_i32_node
    test edx,edx; jnz .ffs_bad
    mov rdx,[rip+ff_access_delta_ptr]
    mov rcx,rbx
    imul rcx,qword ptr [rip+ff_access_delta_stride]
    lea rcx,[rcx+r11*4]
    mov [rdx+rcx],eax
    test ebx,ebx; jnz .ffs_delta_next
    test eax,eax; jnz .ffs_bad
.ffs_delta_next:
    mov r14,[r14+32]; inc r11d; jmp .ffs_delta_loop
.ffs_delta_end:
    test r14,r14; jnz .ffs_bad
    inc dword ptr [rip+ff_access_count]
    mov r13,[r13+32]; jmp .ffs_access_loop
.ffs_access_done:
    cmp dword ptr [rip+ff_access_count],0; je .ffs_bad

    # operations
    mov rdi,r12; lea rsi,[rip+k_ops]; mov edx,k_ops_end-k_ops; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_ARRAY; jne .ffs_bad
    mov r13,[rax+24]
.ffs_op_loop:
    test r13,r13; jz .ffs_ops_done
    mov eax,dword ptr [rip+ff_op_count]; cmp eax,dword ptr [rip+ff_graph_capacity]; jae .ffs_bad
    mov ebx,eax; imul rbx,OP_SIZE; mov r15,[rip+ff_ops_ptr]; add r15,rbx
    cmp qword ptr [r13],J_OBJECT; jne .ffs_bad
    mov rdi,r13; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .ffs_bad
    cmp qword ptr [rax],J_STRING; jne .ffs_bad
    mov r14,rax
    # classify
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_load]; mov ecx,v_load_end-v_load; call span_eq
    test eax,eax; jnz .ffs_op_load
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_const]; mov ecx,v_const_end-v_const; call span_eq
    test eax,eax; jnz .ffs_op_const
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jnz .ffs_op_add
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jnz .ffs_op_sub
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jnz .ffs_op_mul
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jnz .ffs_op_div
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax; jnz .ffs_op_sqrt
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_trunc]; mov ecx,v_trunc_end-v_trunc; call span_eq
    test eax,eax; jnz .ffs_op_trunc
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_store]; mov ecx,v_store_end-v_store; call span_eq
    test eax,eax; jnz .ffs_op_store
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_reduce]; mov ecx,v_reduce_end-v_reduce; call span_eq
    test eax,eax; jnz .ffs_op_reduce
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mov]; mov ecx,v_mov_end-v_mov; call span_eq
    test eax,eax; jnz .ffs_op_mov
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_iindex]; mov ecx,v_iindex_end-v_iindex; call span_eq
    test eax,eax; jnz .ffs_op_iindex
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_iadd_const]; mov ecx,v_iadd_const_end-v_iadd_const; call span_eq
    test eax,eax; jnz .ffs_op_iadd_const
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_isub_const]; mov ecx,v_isub_const_end-v_isub_const; call span_eq
    test eax,eax; jnz .ffs_op_isub_const
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_imul_const]; mov ecx,v_imul_const_end-v_imul_const; call span_eq
    test eax,eax; jnz .ffs_op_imul_const
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_idiv_const]; mov ecx,v_idiv_const_end-v_idiv_const; call span_eq
    test eax,eax; jnz .ffs_op_idiv_const
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_imod_const]; mov ecx,v_imod_const_end-v_imod_const; call span_eq
    test eax,eax; jnz .ffs_op_imod_const
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_itof32]; mov ecx,v_itof32_end-v_itof32; call span_eq
    test eax,eax; jnz .ffs_op_itof32
    jmp .ffs_bad
.ffs_op_load:
    mov dword ptr [r15],OP_LOAD
    mov rdi,r13; lea rsi,[rip+k_access]; mov edx,k_access_end-k_access; call obj_get
    call node_parse_u64; test edx,edx; jnz .ffs_bad
    cmp eax,dword ptr [rip+ff_access_count]; jae .ffs_bad
    mov [r15+16],eax
    mov rdi,r13; call ff_parse_dst; test edx,edx; jnz .ffs_bad
    mov [r15+4],eax; jmp .ffs_op_addrec
.ffs_op_const:
    mov dword ptr [r15],OP_CONST
    mov rdi,r13; call ff_parse_dst; test edx,edx; jnz .ffs_bad
    mov [r15+4],eax
    mov rdi,r13; lea rsi,[rip+k_value]; mov edx,k_value_end-k_value; call obj_get
    call node_parse_f64_bits; test edx,edx; jnz .ffs_bad
    movq xmm0,rax; cvtsd2ss xmm0,xmm0; movd eax,xmm0
    mov [r15+20],eax; jmp .ffs_op_addrec
.ffs_op_add: mov eax,OP_ADD; jmp .ffs_op_binary
.ffs_op_sub: mov eax,OP_SUB; jmp .ffs_op_binary
.ffs_op_mul: mov eax,OP_MUL; jmp .ffs_op_binary
.ffs_op_div: mov eax,OP_DIV
.ffs_op_binary:
    mov [r15],eax
    mov rdi,r13; call ff_parse_dst; test edx,edx; jnz .ffs_bad; mov [r15+4],eax
    mov rdi,r13; lea rsi,[rip+k_a]; mov edx,k_a_end-k_a; call obj_get; call ff_parse_reg_node; test edx,edx; jnz .ffs_bad; mov [r15+8],eax
    mov rdi,r13; lea rsi,[rip+k_b]; mov edx,k_b_end-k_b; call obj_get; call ff_parse_reg_node; test edx,edx; jnz .ffs_bad; mov [r15+12],eax
    jmp .ffs_op_addrec
.ffs_op_trunc:
    mov dword ptr [r15],OP_TRUNC
    mov rdi,r13; call ff_parse_dst; test edx,edx; jnz .ffs_bad; mov [r15+4],eax
    mov rdi,r13; lea rsi,[rip+k_a]; mov edx,k_a_end-k_a; call obj_get; call ff_parse_reg_node; test edx,edx; jnz .ffs_bad; mov [r15+8],eax
    mov dword ptr [r15+12],0
    jmp .ffs_op_addrec
.ffs_op_sqrt:
    mov dword ptr [r15],OP_SQRT
    mov rdi,r13; call ff_parse_dst; test edx,edx; jnz .ffs_bad; mov [r15+4],eax
    mov rdi,r13; lea rsi,[rip+k_a]; mov edx,k_a_end-k_a; call obj_get; call ff_parse_reg_node; test edx,edx; jnz .ffs_bad; mov [r15+8],eax
    mov dword ptr [r15+12],0
    jmp .ffs_op_addrec
.ffs_op_store:
    mov dword ptr [r15],OP_STORE
    mov rdi,r13; lea rsi,[rip+k_field]; mov edx,k_field_end-k_field; call obj_get; call node_parse_u64; test edx,edx; jnz .ffs_bad
    cmp eax,dword ptr [rip+ff_field_count]; jae .ffs_bad
    mov rdx,[rip+ff_field_mode_ptr]; cmp byte ptr [rdx+rax],MODE_INPUT; je .ffs_bad
    mov [r15+16],eax
    mov rdi,r13; lea rsi,[rip+k_src]; mov edx,k_src_end-k_src; call obj_get; call ff_parse_reg_node; test edx,edx; jnz .ffs_bad; mov [r15+8],eax
    jmp .ffs_op_addrec
.ffs_op_reduce:
    mov dword ptr [r15],OP_REDUCE
    mov rdi,r13; lea rsi,[rip+k_src]; mov edx,k_src_end-k_src; call obj_get; call ff_parse_reg_node; test edx,edx; jnz .ffs_bad; mov [r15+8],eax
    inc dword ptr [rip+ff_reduce_count]
    jmp .ffs_op_addrec
.ffs_op_mov:
    mov dword ptr [r15],OP_MOV
    mov rdi,r13; call ff_parse_dst; test edx,edx; jnz .ffs_bad; mov [r15+4],eax
    mov rdi,r13; lea rsi,[rip+k_src]; mov edx,k_src_end-k_src; call obj_get; call ff_parse_reg_node; test edx,edx; jnz .ffs_bad; mov [r15+8],eax
    jmp .ffs_op_addrec
.ffs_op_iindex:
    mov dword ptr [r15],OP_IINDEX
    mov rdi,r13; lea rsi,[rip+k_ireg]; mov edx,k_ireg_end-k_ireg; call obj_get; call ff_parse_ireg_node; test edx,edx; jnz .ffs_bad; mov [r15+4],eax
    jmp .ffs_op_addrec
.ffs_op_iadd_const: mov eax,OP_IADD_CONST; jmp .ffs_op_iconst_mut
.ffs_op_isub_const: mov eax,OP_ISUB_CONST; jmp .ffs_op_iconst_mut
.ffs_op_imul_const: mov eax,OP_IMUL_CONST; jmp .ffs_op_iconst_mut
.ffs_op_idiv_const: mov eax,OP_IDIV_CONST; jmp .ffs_op_iconst_mut
.ffs_op_imod_const: mov eax,OP_IMOD_CONST
.ffs_op_iconst_mut:
    mov [r15],eax
    mov rdi,r13; lea rsi,[rip+k_ireg]; mov edx,k_ireg_end-k_ireg; call obj_get; call ff_parse_ireg_node; test edx,edx; jnz .ffs_bad; mov [r15+4],eax
    mov rdi,r13; lea rsi,[rip+k_value]; mov edx,k_value_end-k_value; call obj_get; call node_parse_u64; test edx,edx; jnz .ffs_bad
    test rax,rax; jz .ffs_iconst_zero_check
    cmp rax,0x7fffffff; ja .ffs_bad
    mov [r15+20],eax
    jmp .ffs_op_addrec
.ffs_iconst_zero_check:
    # add/sub/mul may use zero; div/mod may not.
    cmp dword ptr [r15],OP_IDIV_CONST; je .ffs_bad
    cmp dword ptr [r15],OP_IMOD_CONST; je .ffs_bad
    mov dword ptr [r15+20],0
    jmp .ffs_op_addrec
.ffs_op_itof32:
    mov dword ptr [r15],OP_ITOF32
    mov rdi,r13; call ff_parse_dst; test edx,edx; jnz .ffs_bad; mov [r15+4],eax
    mov rdi,r13; lea rsi,[rip+k_ireg]; mov edx,k_ireg_end-k_ireg; call obj_get; call ff_parse_ireg_node; test edx,edx; jnz .ffs_bad; mov [r15+8],eax
.ffs_op_addrec:
    inc dword ptr [rip+ff_op_count]
    mov r13,[r13+32]; jmp .ffs_op_loop
.ffs_ops_done:
    cmp dword ptr [rip+ff_op_count],0; je .ffs_bad
    cmp dword ptr [rip+ff_reduce_count],0; je .ffs_bad

    # 1.3.3 Causal Physical Optimization. Tolerant contracts may replace a
    # transient multiply followed immediately by accumulator add with one FMA
    # when the temporary dies at the next definition. Strict graphs are byte-
    # order sovereign and never enter this rewrite. This is structural and
    # workload-name blind.
    call ff_optimize_arithmetic
    test eax,eax; jnz .ffs_bad
    # 1.3.24 common-factor ValueFact closure.  This does not introduce a
    # factor opcode or a second codegen lane: ordinary MUL/FMA_ACC records are
    # rewritten only when def/use facts prove that several accumulator terms
    # share the same immutable load fact and no intermediate accumulator value
    # is consumed.  The number of terms is not part of admission.
    call ff_contract_common_factors
    test eax,eax; jnz .ffs_bad
    # All tolerant arithmetic contraction now stays inside the same ValueFact/Physical-DAG authority.
    call ff_build_const_pool
    test eax,eax; jnz .ffs_bad
    # 1.3.6 Global Physical Reality: canonical versioned facts are built before
    # the Physical-DAG. Exact duplicate pure work is erased only when the fact
    # is still physically resident in a live logical carrier.
    call ff_build_global_physical_reality
    test eax,eax; jnz .ffs_bad

    # 1.3.0: materialize the field operation dependencies as a transient
    # Physical-DAG plan before any final ISA bytes are emitted.
    call ff_build_physical_plan
    test eax,eax; jnz .ffs_bad
    # 1.3.91 target projection: if and only if an exposed fabric target is
    # physically proved, serialize this same op-level Physical DAG for the
    # fabric bridge. No kernel extraction or second semantic graph is created.
    call ff_close_fabric_datapath_descriptor
    test eax,eax; jnz .ffs_bad
    call ff_codegen
    test eax,eax; jnz .ffs_bad
    call ff_emit_image
    jmp .ffs_done
.ffs_bad:
    cmp dword ptr [rip+ff_code_overflow],0
    je .ffs_bad_final
    mov rax,qword ptr [rip+ff_code_growth_factor]
    shl rax,1
    jc .ffs_bad_final
    test rax,rax
    jz .ffs_bad_final
    mov qword ptr [rip+ff_code_growth_factor],rax
    jmp .ffs_retry
.ffs_bad_final: mov eax,1
.ffs_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# 1.3.3 bounded local arithmetic physicalization.
# Recognize the generic pattern
#   t = a*b ; acc = acc+t ; <next op redefines t>
# and realize it as one accumulator FMA under the tolerant FP contract.
# This is not a workload-specific dispatch. It is a three-op def-use proof.
ff_optimize_arithmetic:
    # 1.3.24 generic tolerant ValueFact contraction.
    # Any immediately consumed multiply whose result has no later consumer
    # before redefinition may be folded into the accumulator update:
    #   t = a*b ; acc = acc+t  ->  acc = fma(a,b,acc)
    # Eligibility is def/use lifetime only. No field/access/term count, source
    # spelling, workload identity, or fixed AST sequence participates.
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp dword ptr [rip+ff_fp_tolerant],1
    jne .foa_ok
    xor ebx,ebx
.foa_loop:
    mov eax,dword ptr [rip+ff_op_count]
    lea ecx,[rbx+1]
    cmp ecx,eax
    jae .foa_ok
    mov rax,rbx
    imul rax,OP_SIZE
    mov r12,[rip+ff_ops_ptr]
    add r12,rax
    cmp dword ptr [r12],OP_MUL
    jne .foa_next
    lea r13,[r12+OP_SIZE]
    cmp dword ptr [r13],OP_ADD
    jne .foa_next

    mov r14d,[r12+4]                 # temporary product destination
    mov r15d,[r13+4]                 # accumulator destination
    cmp r14d,r15d
    je .foa_next
    # ADD must be accumulator-preserving and consume exactly the MUL result.
    mov eax,[r13+8]
    mov edx,[r13+12]
    cmp eax,r15d
    jne .foa_add_rev
    cmp edx,r14d
    jne .foa_next
    jmp .foa_lifetime
.foa_add_rev:
    cmp eax,r14d
    jne .foa_next
    cmp edx,r15d
    jne .foa_next

.foa_lifetime:
    # The product virtual register may disappear only if no later operation
    # reads its old version before the first redefinition.
    lea ecx,[rbx+2]
.foa_use_scan:
    cmp ecx,dword ptr [rip+ff_op_count]
    jae .foa_contract
    mov rax,rcx
    imul rax,OP_SIZE
    mov rdx,[rip+ff_ops_ptr]
    add rdx,rax
    mov eax,[rdx]
    cmp eax,OP_NOP
    je .foa_scan_next
    # read set
    cmp eax,OP_ADD; je .foa_read2
    cmp eax,OP_SUB; je .foa_read2
    cmp eax,OP_MUL; je .foa_read2
    cmp eax,OP_DIV; je .foa_read2
    cmp eax,OP_SQRT; je .foa_read1
    cmp eax,OP_TRUNC; je .foa_read1
    cmp eax,OP_FMA_ACC; je .foa_read_fma
    cmp eax,OP_MOV; je .foa_read1
    cmp eax,OP_STORE; je .foa_read1
    cmp eax,OP_REDUCE; je .foa_read1
    cmp eax,OP_ITOF32; je .foa_def_check
    jmp .foa_def_check
.foa_read2:
    cmp [rdx+8],r14d; je .foa_next
    cmp [rdx+12],r14d; je .foa_next
    jmp .foa_def_check
.foa_read_fma:
    cmp [rdx+4],r14d; je .foa_next     # accumulator old value is also read
    cmp [rdx+8],r14d; je .foa_next
    cmp [rdx+12],r14d; je .foa_next
    jmp .foa_def_check
.foa_read1:
    cmp [rdx+8],r14d; je .foa_next
.foa_def_check:
    # floating definitions terminate the old version's lifetime.
    cmp eax,OP_CONST; je .foa_maybe_def
    cmp eax,OP_LOAD; je .foa_maybe_def
    cmp eax,OP_ADD; je .foa_maybe_def
    cmp eax,OP_SUB; je .foa_maybe_def
    cmp eax,OP_MUL; je .foa_maybe_def
    cmp eax,OP_DIV; je .foa_maybe_def
    cmp eax,OP_SQRT; je .foa_maybe_def
    cmp eax,OP_TRUNC; je .foa_maybe_def
    cmp eax,OP_MOV; je .foa_maybe_def
    cmp eax,OP_ITOF32; je .foa_maybe_def
    cmp eax,OP_FMA_ACC; jne .foa_scan_next
.foa_maybe_def:
    cmp [rdx+4],r14d
    je .foa_contract
.foa_scan_next:
    inc ecx
    jmp .foa_use_scan

.foa_contract:
    # Preserve the pre-MUL operands as FMA inputs and accumulator as authority.
    mov eax,[r12+8]
    mov edx,[r12+12]
    mov dword ptr [r13],OP_FMA_ACC
    mov [r13+4],r15d
    mov [r13+8],eax
    mov [r13+12],edx
    mov dword ptr [r12],OP_NOP
    inc dword ptr [rip+ff_arith_fma_fused_count]
    add ebx,2
    jmp .foa_loop
.foa_next:
    inc ebx
    jmp .foa_loop
.foa_ok:
    xor eax,eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# 1.3.24 generic common-factor ValueFact contraction.
#
# This pass consumes only the existing tolerant OP_FMA_ACC graph.  It does not
# recognize field names, workload shapes, term counts, source adjacency templates or
# benchmark identities.  A candidate term is an accumulator FMA for which one
# input is an immutable load fact and the other is the current result of an
# ordinary multiply.  Consecutive accumulator epochs may be reassociated only
# while the accumulator has no intervening definition or consumer.
#
# If an otherwise-unused logical floating carrier exists, a run
#
#   acc += c0 * X
#   acc += c1 * X
#   ...
#
# is represented with the ordinary instruction vocabulary as
#
#   factor  = c0
#   factor += c1
#   ...
#   acc    += factor * X
#
# where the coefficient accumulation itself uses OP_FMA_ACC whenever the
# coefficient is a product.  No private factor opcode, side-channel emitter or
# compatibility route exists.  Failure simply preserves the original DAG.
ff_contract_common_factors:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp dword ptr [rip+ff_fp_tolerant],1
    jne .fcf_ok

    # Find a logical floating carrier that is absent from the source graph.
    # This is physical availability, not a state-count or workload threshold.
    xor r12d,r12d
.fcf_find_carrier:
    cmp r12d,FF_VREG_COUNT
    jae .fcf_ok                         # no spare carrier: preserve the DAG
    xor ebx,ebx
.fcf_carrier_scan:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fcf_have_carrier
    mov rax,rbx
    imul rax,OP_SIZE
    mov r13,[rip+ff_ops_ptr]
    add r13,rax
    mov eax,[r13]
    cmp eax,OP_NOP; je .fcf_carrier_next
    cmp eax,OP_LOAD; je .fcf_chk_def
    cmp eax,OP_CONST; je .fcf_chk_def
    cmp eax,OP_ADD; je .fcf_chk_bin
    cmp eax,OP_SUB; je .fcf_chk_bin
    cmp eax,OP_MUL; je .fcf_chk_bin
    cmp eax,OP_DIV; je .fcf_chk_bin
    cmp eax,OP_SQRT; je .fcf_chk_unary
    cmp eax,OP_TRUNC; je .fcf_chk_unary
    cmp eax,OP_MOV; je .fcf_chk_mov
    cmp eax,OP_STORE; je .fcf_chk_read1
    cmp eax,OP_REDUCE; je .fcf_chk_read1
    cmp eax,OP_ITOF32; je .fcf_chk_def
    cmp eax,OP_FMA_ACC; je .fcf_chk_fma
    jmp .fcf_carrier_next
.fcf_chk_def:
    cmp dword ptr [r13+4],r12d
    je .fcf_carrier_used
    jmp .fcf_carrier_next
.fcf_chk_bin:
    cmp dword ptr [r13+4],r12d
    je .fcf_carrier_used
    cmp dword ptr [r13+8],r12d
    je .fcf_carrier_used
    cmp dword ptr [r13+12],r12d
    je .fcf_carrier_used
    jmp .fcf_carrier_next
.fcf_chk_unary:
    cmp dword ptr [r13+4],r12d
    je .fcf_carrier_used
    cmp dword ptr [r13+8],r12d
    je .fcf_carrier_used
    jmp .fcf_carrier_next
.fcf_chk_mov:
    cmp dword ptr [r13+4],r12d
    je .fcf_carrier_used
    cmp dword ptr [r13+8],r12d
    je .fcf_carrier_used
    jmp .fcf_carrier_next
.fcf_chk_read1:
    cmp dword ptr [r13+8],r12d
    je .fcf_carrier_used
    jmp .fcf_carrier_next
.fcf_chk_fma:
    cmp dword ptr [r13+4],r12d
    je .fcf_carrier_used
    cmp dword ptr [r13+8],r12d
    je .fcf_carrier_used
    cmp dword ptr [r13+12],r12d
    je .fcf_carrier_used
.fcf_carrier_next:
    inc ebx
    jmp .fcf_carrier_scan
.fcf_carrier_used:
    inc r12d
    jmp .fcf_find_carrier

.fcf_have_carrier:
    mov dword ptr [rip+ff_cf_scratch],r12d
    mov dword ptr [rip+ff_cf_pending_valid],0
    mov dword ptr [rip+ff_cf_active],0
    mov dword ptr [rip+ff_cf_group_count],0
    mov dword ptr [rip+ff_cf_term_count],0
    lea rdi,[rip+ff_cf_last_def]
    mov eax,-1
    mov ecx,FF_VREG_COUNT
    rep stosd
    lea rdi,[rip+ff_cf_last_read]
    mov eax,-1
    mov ecx,FF_VREG_COUNT
    rep stosd

    xor ebx,ebx
.fcf_scan:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fcf_ok
    mov rax,rbx
    imul rax,OP_SIZE
    mov r13,[rip+ff_ops_ptr]
    add r13,rax
    mov eax,[r13]
    cmp eax,OP_FMA_ACC
    jne .fcf_update

    # Resolve the current FMA operands through the current version map.
    mov r14d,[r13+4]                    # accumulator
    mov eax,[r13+8]
    cmp eax,FF_VREG_MAX; ja .fcf_update
    mov edx,[r13+12]
    cmp edx,FF_VREG_MAX; ja .fcf_update
    lea rcx,[rip+ff_cf_last_def]
    mov r8d,[rcx+rax*4]                 # def(a)
    mov r9d,[rcx+rdx*4]                 # def(b)
    test r8d,r8d; js .fcf_candidate_fail
    test r9d,r9d; js .fcf_candidate_fail
    mov r10d,eax                        # reg a
    mov r11d,edx                        # reg b

    mov rax,r8
    imul rax,OP_SIZE
    mov r15,[rip+ff_ops_ptr]
    add r15,rax                         # op defining a
    mov rax,r9
    imul rax,OP_SIZE
    mov rdx,[rip+ff_ops_ptr]
    add rdx,rax                         # op defining b
    mov eax,[r15]
    mov ecx,[rdx]
    cmp eax,OP_LOAD
    jne .fcf_try_b_load
    cmp ecx,OP_MUL
    jne .fcf_candidate_fail
    mov dword ptr [rip+ff_cf_cur_xdef],r8d
    mov dword ptr [rip+ff_cf_cur_muldef],r9d
    mov dword ptr [rip+ff_cf_cur_xreg],r10d
    mov dword ptr [rip+ff_cf_cur_coeffreg],r11d
    mov r15,r15                         # x op already in r15
    mov rsi,rdx                         # mul op
    jmp .fcf_candidate_shape
.fcf_try_b_load:
    cmp eax,OP_MUL
    jne .fcf_candidate_fail
    cmp ecx,OP_LOAD
    jne .fcf_candidate_fail
    mov dword ptr [rip+ff_cf_cur_xdef],r9d
    mov dword ptr [rip+ff_cf_cur_muldef],r8d
    mov dword ptr [rip+ff_cf_cur_xreg],r11d
    mov dword ptr [rip+ff_cf_cur_coeffreg],r10d
    mov rsi,r15                         # mul op
    mov r15,rdx                         # x op

.fcf_candidate_shape:
    # The multiply must really define the FMA coefficient carrier.
    mov eax,dword ptr [rip+ff_cf_cur_coeffreg]
    cmp dword ptr [rsi+4],eax
    jne .fcf_candidate_fail
    # Shared factor must be an immutable input field.  Mutable versions are not
    # algebraically moved across an accumulator epoch.
    mov eax,[r15+16]
    cmp eax,dword ptr [rip+ff_access_count]
    jae .fcf_candidate_fail
    mov dword ptr [rip+ff_cf_cur_xaccess],eax
    mov rcx,[rip+ff_access_field_ptr]
    movzx eax,byte ptr [rcx+rax]
    cmp eax,dword ptr [rip+ff_field_count]
    jae .fcf_candidate_fail
    mov rcx,[rip+ff_field_mode_ptr]
    cmp byte ptr [rcx+rax],MODE_INPUT
    jne .fcf_candidate_fail

    # Never fold a coefficient that directly consumes the accumulator.  The
    # last-read authority below catches indirect accumulator use between terms;
    # this local guard handles the current coefficient itself.
    mov eax,[rsi+8]
    cmp eax,r14d; je .fcf_candidate_fail
    mov eax,[rsi+12]
    cmp eax,r14d; je .fcf_candidate_fail

    cmp dword ptr [rip+ff_cf_active],1
    jne .fcf_try_pending
    # Extend only if this is the same algebraic factor/accumulator epoch and the
    # previously published accumulator value has had no intervening consumer.
    cmp r14d,dword ptr [rip+ff_cf_acc]
    jne .fcf_break_to_pending
    mov eax,dword ptr [rip+ff_cf_cur_xaccess]
    cmp eax,dword ptr [rip+ff_cf_xaccess]
    jne .fcf_break_to_pending
    lea rcx,[rip+ff_cf_last_def]
    mov eax,[rcx+r14*4]
    cmp eax,dword ptr [rip+ff_cf_last_fma]
    jne .fcf_break_to_pending
    lea rcx,[rip+ff_cf_last_read]
    mov eax,[rcx+r14*4]
    cmp eax,dword ptr [rip+ff_cf_last_fma]
    jne .fcf_break_to_pending

    # The previous FMA ceases to publish the accumulator; the current one is
    # the new sole publication point.  Coefficient work is accumulated in the
    # spare carrier with the ordinary OP_FMA_ACC vocabulary.
    mov eax,dword ptr [rip+ff_cf_last_fma]
    imul rax,OP_SIZE
    mov rcx,[rip+ff_ops_ptr]
    add rcx,rax
    mov dword ptr [rcx],OP_NOP
    mov eax,dword ptr [rip+ff_cf_cur_muldef]
    imul rax,OP_SIZE
    mov rcx,[rip+ff_ops_ptr]
    add rcx,rax
    mov dword ptr [rcx],OP_FMA_ACC
    mov edx,dword ptr [rip+ff_cf_scratch]
    mov [rcx+4],edx
    # [8]/[12] remain the original multiply operands.
    mov [r13+8],edx
    mov eax,dword ptr [rip+ff_cf_cur_xreg]
    mov [r13+12],eax
    mov [rip+ff_cf_last_fma],ebx
    inc dword ptr [rip+ff_cf_term_count]
    mov eax,dword ptr [rip+ff_cf_cur_muldef]
    lea rcx,[rip+ff_cf_last_def]
    mov [rcx+rdx*4],eax
    lea rcx,[rip+ff_cf_last_read]
    mov [rcx+rdx*4],eax
    jmp .fcf_update

.fcf_try_pending:
    cmp dword ptr [rip+ff_cf_pending_valid],1
    jne .fcf_set_pending
    cmp r14d,dword ptr [rip+ff_cf_pending_acc]
    jne .fcf_set_pending
    mov eax,dword ptr [rip+ff_cf_cur_xaccess]
    cmp eax,dword ptr [rip+ff_cf_pending_xaccess]
    jne .fcf_set_pending
    lea rcx,[rip+ff_cf_last_def]
    mov eax,[rcx+r14*4]
    cmp eax,dword ptr [rip+ff_cf_pending_fma]
    jne .fcf_set_pending
    lea rcx,[rip+ff_cf_last_read]
    mov eax,[rcx+r14*4]
    cmp eax,dword ptr [rip+ff_cf_pending_fma]
    jne .fcf_set_pending

    # First two terms establish a factor group.  The first coefficient multiply
    # becomes the initial factor definition; the second becomes a factor FMA.
    mov eax,dword ptr [rip+ff_cf_pending_muldef]
    imul rax,OP_SIZE
    mov rcx,[rip+ff_ops_ptr]
    add rcx,rax
    mov edx,dword ptr [rip+ff_cf_scratch]
    mov [rcx+4],edx                     # factor = coeff0 product
    mov eax,dword ptr [rip+ff_cf_pending_fma]
    imul rax,OP_SIZE
    mov rcx,[rip+ff_ops_ptr]
    add rcx,rax
    mov dword ptr [rcx],OP_NOP

    mov eax,dword ptr [rip+ff_cf_cur_muldef]
    imul rax,OP_SIZE
    mov rcx,[rip+ff_ops_ptr]
    add rcx,rax
    mov dword ptr [rcx],OP_FMA_ACC
    mov [rcx+4],edx                     # factor += coeff1 product
    mov [r13+8],edx
    mov eax,dword ptr [rip+ff_cf_cur_xreg]
    mov [r13+12],eax                    # acc += factor * X

    mov dword ptr [rip+ff_cf_active],1
    mov [rip+ff_cf_acc],r14d
    mov eax,dword ptr [rip+ff_cf_cur_xaccess]
    mov [rip+ff_cf_xaccess],eax
    mov [rip+ff_cf_last_fma],ebx
    mov dword ptr [rip+ff_cf_pending_valid],0
    inc dword ptr [rip+ff_cf_group_count]
    add dword ptr [rip+ff_cf_term_count],2
    mov eax,dword ptr [rip+ff_cf_cur_muldef]
    lea rcx,[rip+ff_cf_last_def]
    mov [rcx+rdx*4],eax
    lea rcx,[rip+ff_cf_last_read]
    mov [rcx+rdx*4],eax
    jmp .fcf_update

.fcf_break_to_pending:
    mov dword ptr [rip+ff_cf_active],0
.fcf_set_pending:
    mov dword ptr [rip+ff_cf_pending_valid],1
    mov [rip+ff_cf_pending_fma],ebx
    mov eax,dword ptr [rip+ff_cf_cur_muldef]
    mov [rip+ff_cf_pending_muldef],eax
    mov [rip+ff_cf_pending_acc],r14d
    mov eax,dword ptr [rip+ff_cf_cur_xaccess]
    mov [rip+ff_cf_pending_xaccess],eax
    jmp .fcf_update

.fcf_candidate_fail:
    # A non-candidate FMA ends only the possibility of extending the current
    # factor run; the already-materialized final FMA remains valid.
    mov dword ptr [rip+ff_cf_active],0
    mov dword ptr [rip+ff_cf_pending_valid],0

.fcf_update:
    # Update the ordinary vreg version/read authorities using the (possibly
    # rewritten) current op.  Integer-only records do not participate.
    mov eax,[r13]
    cmp eax,OP_NOP; je .fcf_next
    cmp eax,OP_LOAD; je .fcf_up_def
    cmp eax,OP_CONST; je .fcf_up_def
    cmp eax,OP_ITOF32; je .fcf_up_def
    cmp eax,OP_ADD; je .fcf_up_bin
    cmp eax,OP_SUB; je .fcf_up_bin
    cmp eax,OP_MUL; je .fcf_up_bin
    cmp eax,OP_DIV; je .fcf_up_bin
    cmp eax,OP_SQRT; je .fcf_up_unary
    cmp eax,OP_TRUNC; je .fcf_up_unary
    cmp eax,OP_MOV; je .fcf_up_mov
    cmp eax,OP_STORE; je .fcf_up_read1
    cmp eax,OP_REDUCE; je .fcf_up_read1
    cmp eax,OP_FMA_ACC; je .fcf_up_fma
    jmp .fcf_next
.fcf_up_def:
    mov eax,[r13+4]
    cmp eax,FF_VREG_MAX; ja .fcf_next
    lea rdx,[rip+ff_cf_last_def]
    mov [rdx+rax*4],ebx
    jmp .fcf_next
.fcf_up_bin:
    mov eax,[r13+8]
    cmp eax,FF_VREG_MAX; ja .fcf_bin_b
    lea rdx,[rip+ff_cf_last_read]
    mov [rdx+rax*4],ebx
.fcf_bin_b:
    mov eax,[r13+12]
    cmp eax,FF_VREG_MAX; ja .fcf_bin_def
    lea rdx,[rip+ff_cf_last_read]
    mov [rdx+rax*4],ebx
.fcf_bin_def:
    mov eax,[r13+4]
    cmp eax,FF_VREG_MAX; ja .fcf_next
    lea rdx,[rip+ff_cf_last_def]
    mov [rdx+rax*4],ebx
    jmp .fcf_next
.fcf_up_unary:
    mov eax,[r13+8]
    cmp eax,FF_VREG_MAX; ja .fcf_unary_def
    lea rdx,[rip+ff_cf_last_read]
    mov [rdx+rax*4],ebx
.fcf_unary_def:
    mov eax,[r13+4]
    cmp eax,FF_VREG_MAX; ja .fcf_next
    lea rdx,[rip+ff_cf_last_def]
    mov [rdx+rax*4],ebx
    jmp .fcf_next
.fcf_up_mov:
    mov eax,[r13+8]
    cmp eax,FF_VREG_MAX; ja .fcf_mov_def
    lea rdx,[rip+ff_cf_last_read]
    mov [rdx+rax*4],ebx
.fcf_mov_def:
    mov eax,[r13+4]
    cmp eax,FF_VREG_MAX; ja .fcf_next
    lea rdx,[rip+ff_cf_last_def]
    mov [rdx+rax*4],ebx
    jmp .fcf_next
.fcf_up_read1:
    mov eax,[r13+8]
    cmp eax,FF_VREG_MAX; ja .fcf_next
    lea rdx,[rip+ff_cf_last_read]
    mov [rdx+rax*4],ebx
    jmp .fcf_next
.fcf_up_fma:
    mov eax,[r13+4]
    cmp eax,FF_VREG_MAX; ja .fcf_next
    lea rdx,[rip+ff_cf_last_read]
    mov [rdx+rax*4],ebx
    mov eax,[r13+8]
    cmp eax,FF_VREG_MAX; ja .fcf_fma_b
    mov [rdx+rax*4],ebx
.fcf_fma_b:
    mov eax,[r13+12]
    cmp eax,FF_VREG_MAX; ja .fcf_fma_def
    mov [rdx+rax*4],ebx
.fcf_fma_def:
    mov eax,[r13+4]
    lea rdx,[rip+ff_cf_last_def]
    mov [rdx+rax*4],ebx
.fcf_next:
    inc ebx
    jmp .fcf_scan

.fcf_ok:
    xor eax,eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Immutable-vector constant identity CSE for the proven cross-output path.
# Float bits, not decimal spelling, define identity.  Constants are broadcast
# once into the persistent generated-function stack frame and thereafter used
# directly as FMA memory operands.  No runtime search or lookup decision exists.
ff_build_const_pool:
    push rbx
    push r12
    push r13
    push r15
    mov dword ptr [rip+ff_const_pool_count],0
    mov rdi,[rip+ff_const_pool_use_count_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+ff_graph_capacity]
    rep stosd
    mov rdi,[rip+ff_const_pool_resident_reg_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_graph_capacity]
    rep stosd
    # Every OP_CONST receives one exact-bit ConstantFact identity when capacity
    # permits. There is no cross-output client class and no compatibility lane.
    mov rdi,[rip+ff_op_const_slot_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_graph_capacity]
    rep stosd
    xor ebx,ebx
.fbcp_generic_loop:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fbcp_ok
    mov rax,rbx
    imul rax,OP_SIZE
    mov r15,[rip+ff_ops_ptr]
    add r15,rax
    cmp dword ptr [r15],OP_CONST
    jne .fbcp_generic_next
    mov r12d,[r15+20]
    xor r13d,r13d
.fbcp_generic_search:
    cmp r13d,dword ptr [rip+ff_const_pool_count]
    jae .fbcp_generic_new
    mov rax,[rip+ff_const_pool_bits_ptr]
    cmp [rax+r13*4],r12d
    je .fbcp_generic_record
    inc r13d
    jmp .fbcp_generic_search
.fbcp_generic_new:
    cmp r13d,dword ptr [rip+ff_graph_capacity]
    jae .fbcp_generic_next
    mov rax,[rip+ff_const_pool_bits_ptr]
    mov [rax+r13*4],r12d
    inc dword ptr [rip+ff_const_pool_count]
.fbcp_generic_record:
    mov rax,[rip+ff_op_const_slot_ptr]
    mov [rax+rbx*4],r13d
    mov rax,[rip+ff_const_pool_use_count_ptr]
    inc dword ptr [rax+r13*4]
.fbcp_generic_next:
    inc ebx
    jmp .fbcp_generic_loop
.fbcp_ok:
    xor eax,eax
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

# 1.3.6 Global Physical Reality Unification.
#
# The graph owns exact compiler-time fact identity across constants, address/load
# versions, ordinary arithmetic, integer coordinate facts and conversion facts.
# It is deliberately not a runtime CSE table. A duplicate pure fact is erased
# only when an equal version is still resident in one of the three logical
# floating carriers; otherwise retain-vs-recompute remains a later physical
# decision. Stores increment only their field version and invalidate no unrelated
# facts. This is the anti-global-flush rule.
ff_build_global_physical_reality:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov dword ptr [rip+ff_global_fact_count],0
    mov dword ptr [rip+ff_global_fact_reuse_count],0
    mov dword ptr [rip+ff_global_rewritten_ops],0
    mov dword ptr [rip+ff_global_version_invalidations],0
    mov dword ptr [rip+ff_address_fact_count],0
    mov dword ptr [rip+ff_address_fact_reuse_count],0

    mov rdi,[rip+ff_op_global_fact_ptr]
    mov eax,PR_FACT_INVALID
    mov ecx,dword ptr [rip+ff_graph_capacity]
    rep stosd
    lea rdi,[rip+ff_global_vreg_fact]
    mov eax,PR_FACT_INVALID
    mov ecx,FF_VREG_COUNT
    rep stosd
    lea rdi,[rip+ff_global_ireg_fact]
    mov eax,PR_FACT_INVALID
    mov ecx,2
    rep stosd
    mov rdi,[rip+ff_field_version_fact_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov rdi,[rip+ff_field_written_fact_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosb
    mov rdi,[rip+ff_access_address_fact_ptr]
    mov eax,PR_FACT_INVALID
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov rdi,[rip+ff_address_fact_owner_ptr]
    mov eax,PR_FACT_INVALID
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd

    # Canonical AddressFact = exact field identity + complete Rank-N delta.
    xor ebx,ebx
.fgr_addr_i:
    cmp ebx,dword ptr [rip+ff_access_count]
    jae .fgr_ops_begin
    xor r12d,r12d                       # candidate AddressFact
.fgr_addr_search:
    cmp r12d,dword ptr [rip+ff_address_fact_count]
    jae .fgr_addr_new
    mov rax,[rip+ff_address_fact_owner_ptr]
    mov r13d,[rax+r12*4]
    cmp r13d,0
    jl .fgr_fail
    mov rax,[rip+ff_access_field_ptr]
    movzx edx,byte ptr [rax+rbx]
    movzx eax,byte ptr [rax+r13]
    cmp eax,edx
    jne .fgr_addr_next
    mov r14,rbx; imul r14,qword ptr [rip+ff_access_delta_stride]
    mov r15,r13; imul r15,qword ptr [rip+ff_access_delta_stride]
    xor ecx,ecx
.fgr_addr_delta:
    cmp rcx,qword ptr [rip+ff_common_rank]
    jae .fgr_addr_reuse
    mov rax,[rip+ff_access_delta_ptr]
    lea r10,[rax+r14]
    lea r11,[rax+r15]
    mov edx,[r10+rcx*4]
    cmp edx,[r11+rcx*4]
    jne .fgr_addr_next
    inc ecx
    jmp .fgr_addr_delta
.fgr_addr_next:
    inc r12d
    jmp .fgr_addr_search
.fgr_addr_new:
    cmp r12d,dword ptr [rip+ff_instance_capacity]
    jae .fgr_fail
    mov rax,[rip+ff_address_fact_owner_ptr]
    mov [rax+r12*4],ebx
    inc dword ptr [rip+ff_address_fact_count]
    jmp .fgr_addr_record
.fgr_addr_reuse:
    inc dword ptr [rip+ff_address_fact_reuse_count]
.fgr_addr_record:
    mov rax,[rip+ff_access_address_fact_ptr]
    mov [rax+rbx*4],r12d
    inc ebx
    jmp .fgr_addr_i

.fgr_ops_begin:
    xor ebx,ebx                         # original op index
.fgr_op_loop:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fgr_ok
    mov rax,rbx
    imul rax,OP_SIZE
    mov r12,[rip+ff_ops_ptr]
    add r12,rax
    mov eax,[r12]
    cmp eax,OP_NOP; je .fgr_next
    cmp eax,OP_CONST; je .fgr_const
    cmp eax,OP_LOAD; je .fgr_load
    cmp eax,OP_MOV; je .fgr_mov
    cmp eax,OP_ADD; je .fgr_bin
    cmp eax,OP_SUB; je .fgr_bin
    cmp eax,OP_MUL; je .fgr_bin
    cmp eax,OP_DIV; je .fgr_bin
    cmp eax,OP_SQRT; je .fgr_unary
    cmp eax,OP_TRUNC; je .fgr_unary
    cmp eax,OP_STORE; je .fgr_store
    cmp eax,OP_REDUCE; je .fgr_reduce
    cmp eax,OP_IINDEX; je .fgr_iindex
    cmp eax,OP_IADD_CONST; je .fgr_imut
    cmp eax,OP_ISUB_CONST; je .fgr_imut
    cmp eax,OP_IMUL_CONST; je .fgr_imut
    cmp eax,OP_IDIV_CONST; je .fgr_imut
    cmp eax,OP_IMOD_CONST; je .fgr_imut
    cmp eax,OP_ITOF32; je .fgr_itof
    cmp eax,OP_FMA_ACC; je .fgr_fma
    jmp .fgr_fail

.fgr_const:
    mov edi,OP_CONST
    mov esi,[r12+20]
    xor edx,edx
    xor ecx,ecx
    mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r13d,eax
    mov edi,r13d
    call ff_global_find_vreg_holder
    mov r14d,eax                        # holder before dst overwrite
    mov r15d,[r12+4]
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    cmp r14d,-1; je .fgr_const_keep
    cmp r14d,r15d; je .fgr_to_nop
    mov dword ptr [r12],OP_MOV
    mov [r12+8],r14d
    inc dword ptr [rip+ff_global_rewritten_ops]
.fgr_const_keep:
    lea rax,[rip+ff_global_vreg_fact]
    mov [rax+r15*4],r13d
    jmp .fgr_record

.fgr_load:
    mov r14d,[r12+16]                   # access
    cmp r14d,dword ptr [rip+ff_access_count]; jae .fgr_fail
    mov rax,[rip+ff_access_address_fact_ptr]
    mov esi,[rax+r14*4]
    cmp esi,0; jl .fgr_fail
    mov rax,[rip+ff_access_field_ptr]
    movzx r15d,byte ptr [rax+r14]
    cmp r15d,dword ptr [rip+ff_instance_capacity]; jae .fgr_fail
    mov rax,[rip+ff_field_version_fact_ptr]
    mov edx,[rax+r15*4]
    mov edi,OP_LOAD
    xor ecx,ecx
    mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r13d,eax
    mov edi,r13d
    call ff_global_find_vreg_holder
    mov r14d,eax
    mov r15d,[r12+4]
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    cmp r14d,-1; je .fgr_load_keep
    cmp r14d,r15d; je .fgr_to_nop
    mov dword ptr [r12],OP_MOV
    mov [r12+8],r14d
    inc dword ptr [rip+ff_global_rewritten_ops]
.fgr_load_keep:
    lea rax,[rip+ff_global_vreg_fact]
    mov [rax+r15*4],r13d
    jmp .fgr_record

.fgr_mov:
    mov r14d,[r12+8]
    mov r15d,[r12+4]
    cmp r14d,FF_VREG_MAX; ja .fgr_fail
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    lea rax,[rip+ff_global_vreg_fact]
    mov r13d,[rax+r14*4]
    cmp r13d,0; jl .fgr_fail
    mov edi,r13d; mov esi,ebx; call ff_global_touch_fact
    lea rax,[rip+ff_global_vreg_fact]
    cmp [rax+r15*4],r13d
    jne .fgr_mov_keep
    mov dword ptr [r12],OP_NOP
    inc dword ptr [rip+ff_global_rewritten_ops]
.fgr_mov_keep:
    lea rax,[rip+ff_global_vreg_fact]
    mov [rax+r15*4],r13d
    jmp .fgr_record_existing

.fgr_bin:
    mov r14d,[r12+8]
    mov r15d,[r12+12]
    cmp r14d,FF_VREG_MAX; ja .fgr_fail
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    lea rax,[rip+ff_global_vreg_fact]
    mov esi,[rax+r14*4]
    mov edx,[rax+r15*4]
    cmp esi,0; jl .fgr_fail
    cmp edx,0; jl .fgr_fail
    mov edi,esi; mov r13d,edx; mov esi,ebx; call ff_global_touch_fact
    mov edi,r13d; mov esi,ebx; call ff_global_touch_fact
    mov edi,[r12]
    lea rax,[rip+ff_global_vreg_fact]
    mov esi,[rax+r14*4]
    mov edx,[rax+r15*4]
    xor ecx,ecx
    mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r13d,eax
    mov edi,r13d
    call ff_global_find_vreg_holder
    mov r14d,eax
    mov r15d,[r12+4]
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    cmp r14d,-1; je .fgr_bin_keep
    cmp r14d,r15d; je .fgr_to_nop
    mov dword ptr [r12],OP_MOV
    mov [r12+8],r14d
    inc dword ptr [rip+ff_global_rewritten_ops]
.fgr_bin_keep:
    lea rax,[rip+ff_global_vreg_fact]
    mov [rax+r15*4],r13d
    jmp .fgr_record

.fgr_unary:
    mov r14d,[r12+8]
    cmp r14d,FF_VREG_MAX; ja .fgr_fail
    lea rax,[rip+ff_global_vreg_fact]
    mov esi,[rax+r14*4]
    cmp esi,0; jl .fgr_fail
    mov edi,esi; mov esi,ebx; call ff_global_touch_fact
    mov edi,[r12]
    lea rax,[rip+ff_global_vreg_fact]
    mov esi,[rax+r14*4]
    xor edx,edx; xor ecx,ecx; mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r13d,eax
    mov edi,r13d; call ff_global_find_vreg_holder
    mov r14d,eax
    mov r15d,[r12+4]
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    cmp r14d,-1; je .fgr_unary_keep
    cmp r14d,r15d; je .fgr_to_nop
    mov dword ptr [r12],OP_MOV
    mov [r12+8],r14d
    inc dword ptr [rip+ff_global_rewritten_ops]
.fgr_unary_keep:
    lea rax,[rip+ff_global_vreg_fact]
    mov [rax+r15*4],r13d
    jmp .fgr_record

.fgr_store:
    mov r14d,[r12+8]
    cmp r14d,FF_VREG_MAX; ja .fgr_fail
    lea rax,[rip+ff_global_vreg_fact]
    mov edi,[rax+r14*4]
    cmp edi,0; jl .fgr_fail
    mov esi,ebx; call ff_global_touch_fact
    mov r15d,[r12+16]
    cmp r15d,dword ptr [rip+ff_instance_capacity]; jae .fgr_fail
    mov rax,[rip+ff_field_version_fact_ptr]
    inc dword ptr [rax+r15*4]
    mov rax,[rip+ff_field_written_fact_ptr]
    mov byte ptr [rax+r15],1
    inc dword ptr [rip+ff_global_version_invalidations]
    jmp .fgr_next

.fgr_reduce:
    mov r14d,[r12+8]
    cmp r14d,FF_VREG_MAX; ja .fgr_fail
    lea rax,[rip+ff_global_vreg_fact]
    mov edi,[rax+r14*4]
    cmp edi,0; jl .fgr_fail
    mov esi,ebx; call ff_global_touch_fact
    jmp .fgr_next

.fgr_iindex:
    mov edi,OP_IINDEX
    xor esi,esi
    xor edx,edx
    xor ecx,ecx
    mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r14d,[r12+4]
    cmp r14d,1; ja .fgr_fail
    mov r13d,eax
    lea rdx,[rip+ff_global_ireg_fact]
    mov [rdx+r14*4],r13d
    jmp .fgr_record

.fgr_imut:
    mov r14d,[r12+4]
    cmp r14d,1; ja .fgr_fail
    lea rax,[rip+ff_global_ireg_fact]
    mov esi,[rax+r14*4]
    cmp esi,0; jl .fgr_fail
    mov edi,esi; mov esi,ebx; call ff_global_touch_fact
    mov edi,[r12]
    lea rax,[rip+ff_global_ireg_fact]
    mov esi,[rax+r14*4]
    mov edx,[r12+20]
    xor ecx,ecx
    mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r13d,eax
    lea rdx,[rip+ff_global_ireg_fact]
    mov [rdx+r14*4],r13d
    jmp .fgr_record

.fgr_itof:
    mov r14d,[r12+8]
    cmp r14d,1; ja .fgr_fail
    lea rax,[rip+ff_global_ireg_fact]
    mov esi,[rax+r14*4]
    cmp esi,0; jl .fgr_fail
    mov edi,esi; mov esi,ebx; call ff_global_touch_fact
    mov edi,OP_ITOF32
    lea rax,[rip+ff_global_ireg_fact]
    mov esi,[rax+r14*4]
    xor edx,edx
    xor ecx,ecx
    mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r13d,eax
    mov edi,r13d; call ff_global_find_vreg_holder
    mov r14d,eax
    mov r15d,[r12+4]
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    cmp r14d,-1; je .fgr_itof_keep
    cmp r14d,r15d; je .fgr_to_nop
    mov dword ptr [r12],OP_MOV
    mov [r12+8],r14d
    inc dword ptr [rip+ff_global_rewritten_ops]
.fgr_itof_keep:
    lea rax,[rip+ff_global_vreg_fact]
    mov [rax+r15*4],r13d
    jmp .fgr_record

.fgr_fma:
    mov r14d,[r12+4]
    mov r15d,[r12+8]
    mov r13d,[r12+12]
    cmp r14d,FF_VREG_MAX; ja .fgr_fail
    cmp r15d,FF_VREG_MAX; ja .fgr_fail
    cmp r13d,FF_VREG_MAX; ja .fgr_fail
    lea rax,[rip+ff_global_vreg_fact]
    mov edi,[rax+r14*4]; cmp edi,0; jl .fgr_fail
    mov esi,ebx; call ff_global_touch_fact
    lea rax,[rip+ff_global_vreg_fact]
    mov edi,[rax+r15*4]; cmp edi,0; jl .fgr_fail
    mov esi,ebx; call ff_global_touch_fact
    lea rax,[rip+ff_global_vreg_fact]
    mov edi,[rax+r13*4]; cmp edi,0; jl .fgr_fail
    mov esi,ebx; call ff_global_touch_fact
    mov edi,OP_FMA_ACC
    lea rax,[rip+ff_global_vreg_fact]
    mov esi,[rax+r14*4]
    mov edx,[rax+r15*4]
    mov ecx,[rax+r13*4]
    mov r8d,ebx
    call ff_global_intern_fact
    cmp eax,-1; je .fgr_fail
    mov r13d,eax
    lea rdx,[rip+ff_global_vreg_fact]
    mov [rdx+r14*4],r13d
    jmp .fgr_record

.fgr_to_nop:
    mov dword ptr [r12],OP_NOP
    inc dword ptr [rip+ff_global_rewritten_ops]
    lea rax,[rip+ff_global_vreg_fact]
    mov [rax+r15*4],r13d
    jmp .fgr_record

.fgr_record:
    mov rax,[rip+ff_op_global_fact_ptr]
    mov [rax+rbx*4],r13d
    jmp .fgr_next
.fgr_record_existing:
    mov rax,[rip+ff_op_global_fact_ptr]
    mov [rax+rbx*4],r13d
.fgr_next:
    inc ebx
    jmp .fgr_op_loop

.fgr_ok:
    xor eax,eax
    jmp .fgr_ret
.fgr_fail:
    mov eax,1
.fgr_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# edi=kind, esi=key0, edx=key1, ecx=key2, r8d=def op -> eax=fact/-1.
ff_global_intern_fact:
    push rbx
    mov ebx,dword ptr [rip+ff_global_fact_count]
    xor eax,eax
.fgif_search:
    cmp eax,ebx
    jae .fgif_new
    mov r9,[rip+ff_global_fact_kind_ptr]
    cmp [r9+rax*4],edi; jne .fgif_next
    mov r9,[rip+ff_global_fact_key0_ptr]
    cmp [r9+rax*4],esi; jne .fgif_next
    mov r9,[rip+ff_global_fact_key1_ptr]
    cmp [r9+rax*4],edx; jne .fgif_next
    mov r9,[rip+ff_global_fact_key2_ptr]
    cmp [r9+rax*4],ecx; jne .fgif_next
    inc dword ptr [rip+ff_global_fact_reuse_count]
    mov r9,[rip+ff_global_fact_last_op_ptr]
    mov [r9+rax*4],r8d
    pop rbx
    ret
.fgif_next:
    inc eax
    jmp .fgif_search
.fgif_new:
    cmp ebx,dword ptr [rip+ff_graph_capacity]
    jae .fgif_bad
    mov eax,ebx
    mov r9,[rip+ff_global_fact_kind_ptr]; mov [r9+rax*4],edi
    mov r9,[rip+ff_global_fact_key0_ptr]; mov [r9+rax*4],esi
    mov r9,[rip+ff_global_fact_key1_ptr]; mov [r9+rax*4],edx
    mov r9,[rip+ff_global_fact_key2_ptr]; mov [r9+rax*4],ecx
    mov r9,[rip+ff_global_fact_first_op_ptr]; mov [r9+rax*4],r8d
    mov r9,[rip+ff_global_fact_last_op_ptr]; mov [r9+rax*4],r8d
    mov r9,[rip+ff_global_fact_use_count_ptr]; mov dword ptr [r9+rax*4],0
    inc dword ptr [rip+ff_global_fact_count]
    pop rbx
    ret
.fgif_bad:
    mov eax,-1
    pop rbx
    ret

# edi=fact, esi=consumer op.
ff_global_touch_fact:
    cmp edi,0; jl .fgtf_ret
    cmp edi,dword ptr [rip+ff_global_fact_count]; jae .fgtf_ret
    mov rax,[rip+ff_global_fact_use_count_ptr]
    inc dword ptr [rax+rdi*4]
    mov rax,[rip+ff_global_fact_last_op_ptr]
    mov [rax+rdi*4],esi
.fgtf_ret:
    ret

# edi=fact -> eax=logical vreg holder or -1.
ff_global_find_vreg_holder:
    xor eax,eax
    lea rdx,[rip+ff_global_vreg_fact]
.fgfh_loop:
    cmp eax,FF_VREG_COUNT
    jae .fgfh_none
    cmp [rdx+rax*4],edi
    je .fgfh_ret
    inc eax
    jmp .fgfh_loop
.fgfh_none:
    mov eax,-1
.fgfh_ret:
    ret

# 1.3.0 Field Physical-DAG planning.
# The current field surface has three floating virtual registers and two integer
# coordinate carriers. We preserve source-visible hazards, record only true
# def-use edges, and hand codegen an explicit planned order. No runtime graph,
# interpreter or peer-aware runtime coordination fabric is created.
ff_build_physical_plan:
    push rbx
    push r12
    push r13
    push r14
    push r15

    # Versioned register hazards are represented as dependency depths rather
    # than source-order edges.  Definitions, reads, memory versions and strict
    # reductions each carry only the minimum predecessor depth needed to make
    # their semantics true.  No EMITTER_ORDER edge is ever manufactured.
    lea rdi,[rip+ff_physical_vdef]
    mov eax,-1
    mov ecx,FF_VREG_COUNT
    rep stosd
    lea rdi,[rip+ff_physical_vread]
    mov eax,-1
    mov ecx,FF_VREG_COUNT
    rep stosd
    lea rdi,[rip+ff_physical_idef]
    mov eax,-1
    mov ecx,2
    rep stosd
    lea rdi,[rip+ff_physical_iread]
    mov eax,-1
    mov ecx,2
    rep stosd
    mov rdi,[rip+ff_physical_mem_depth_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov dword ptr [rip+ff_physical_reduce_depth],-1
    mov rdi,[rip+ff_physical_depth_counts_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+ff_graph_capacity]; inc ecx
    rep stosd
    mov rdi,[rip+ff_physical_depth_cursor_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+ff_graph_capacity]; inc ecx
    rep stosd
    mov dword ptr [rip+ff_physical_edge_count],0
    mov dword ptr [rip+ff_physical_memory_barriers],0
    mov dword ptr [rip+ff_physical_max_depth],0
    mov dword ptr [rip+ff_physical_reordered_ops],0
    mov dword ptr [rip+ff_physical_artificial_edges],0
    mov eax,FIELD_LANES
    mov dword ptr [rip+ff_physical_tensor_lanes],eax

    xor ebx,ebx
.ffpd_loop:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .ffpd_build_order
    mov rax,rbx
    imul rax,OP_SIZE
    mov r12,[rip+ff_ops_ptr]
    add r12,rax
    xor r13d,r13d                    # candidate Physical-DAG depth
    mov eax,[r12]
    cmp eax,OP_NOP; je .ffpd_nop
    cmp eax,OP_LOAD; je .ffpd_load
    cmp eax,OP_CONST; je .ffpd_const
    cmp eax,OP_ADD; je .ffpd_bin_v
    cmp eax,OP_SUB; je .ffpd_bin_v
    cmp eax,OP_MUL; je .ffpd_bin_v
    cmp eax,OP_DIV; je .ffpd_bin_v
    cmp eax,OP_SQRT; je .ffpd_unary_v
    cmp eax,OP_TRUNC; je .ffpd_unary_v
    cmp eax,OP_STORE; je .ffpd_store_v
    cmp eax,OP_REDUCE; je .ffpd_reduce_v
    cmp eax,OP_MOV; je .ffpd_mov_v
    cmp eax,OP_IINDEX; je .ffpd_def_i
    cmp eax,OP_IADD_CONST; je .ffpd_mut_i
    cmp eax,OP_ISUB_CONST; je .ffpd_mut_i
    cmp eax,OP_IMUL_CONST; je .ffpd_mut_i
    cmp eax,OP_IDIV_CONST; je .ffpd_mut_i
    cmp eax,OP_IMOD_CONST; je .ffpd_mut_i
    cmp eax,OP_ITOF32; je .ffpd_itof
    cmp eax,OP_FMA_ACC; je .ffpd_fma_acc
    jmp .ffpd_fail

.ffpd_nop:
    xor r13d,r13d
    jmp .ffpd_commit

# Common floating definition hazards: WAW and every prior reader (WAR).
.ffpd_const:
    mov r14d,[r12+4]
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vread]
    mov eax,[rdx+r14*4]
    call ffpd_raise_eax
    jmp .ffpd_commit_vdef

.ffpd_load:
    mov r14d,[r12+4]
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vread]
    mov eax,[rdx+r14*4]
    call ffpd_raise_eax
    # Immutable input loads are already episode-prefetched and may occupy the
    # same DAG depth.  Mutable field versions retain exact per-field ordering.
    mov eax,[r12+16]
    cmp eax,dword ptr [rip+ff_access_count]; jae .ffpd_fail
    mov rdx,[rip+ff_access_field_ptr]
    movzx r15d,byte ptr [rdx+rax]
    cmp r15d,dword ptr [rip+ff_instance_capacity]; jae .ffpd_fail
    mov rdx,[rip+ff_field_mode_ptr]
    cmp byte ptr [rdx+r15],MODE_INPUT
    je .ffpd_commit_vdef
    mov rdx,[rip+ff_physical_mem_depth_ptr]
    mov eax,[rdx+r15*4]
    call ffpd_raise_eax
    mov [rdx+r15*4],r13d
    inc dword ptr [rip+ff_physical_memory_barriers]
.ffpd_commit_vdef:
    lea rdx,[rip+ff_physical_vdef]
    mov [rdx+r14*4],r13d
    lea rdx,[rip+ff_physical_vread]
    mov dword ptr [rdx+r14*4],-1
    jmp .ffpd_commit

.ffpd_bin_v:
    mov r14d,[r12+8]                 # a
    mov r15d,[r12+12]                # b
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    cmp r15d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r15*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    mov ecx,[r12+4]                   # dst
    cmp ecx,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+rcx*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vread]
    mov eax,[rdx+rcx*4]
    call ffpd_raise_eax
    # Readers of non-overwritten source versions must finish before a later
    # writer may recycle that architectural field virtual register.
    cmp r14d,ecx; je .ffpd_bin_skip_a_read
    lea rdx,[rip+ff_physical_vread]
    cmp [rdx+r14*4],r13d
    jge .ffpd_bin_skip_a_read
    mov [rdx+r14*4],r13d
.ffpd_bin_skip_a_read:
    cmp r15d,ecx; je .ffpd_bin_skip_b_read
    lea rdx,[rip+ff_physical_vread]
    cmp [rdx+r15*4],r13d
    jge .ffpd_bin_skip_b_read
    mov [rdx+r15*4],r13d
.ffpd_bin_skip_b_read:
    lea rdx,[rip+ff_physical_vdef]
    mov [rdx+rcx*4],r13d
    lea rdx,[rip+ff_physical_vread]
    mov dword ptr [rdx+rcx*4],-1
    jmp .ffpd_commit

.ffpd_unary_v:
    mov r14d,[r12+8]                 # source
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    mov ecx,[r12+4]                   # dst
    cmp ecx,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+rcx*4]; call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vread]
    mov eax,[rdx+rcx*4]; call ffpd_raise_eax
    cmp r14d,ecx; je .ffpd_unary_skip_read
    cmp [rdx+r14*4],r13d; jge .ffpd_unary_skip_read
    mov [rdx+r14*4],r13d
.ffpd_unary_skip_read:
    lea rdx,[rip+ff_physical_vdef]; mov [rdx+rcx*4],r13d
    lea rdx,[rip+ff_physical_vread]; mov dword ptr [rdx+rcx*4],-1
    jmp .ffpd_commit

.ffpd_fma_acc:
    # dst = dst + a*b. Tolerant-only internal op created by 1.3.3 rewrite.
    mov ecx,[r12+4]
    mov r14d,[r12+8]
    mov r15d,[r12+12]
    cmp ecx,FF_VREG_MAX; ja .ffpd_fail
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    cmp r15d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+rcx*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r15*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vread]
    mov eax,[rdx+rcx*4]
    call ffpd_raise_eax
    cmp r14d,ecx; je 1f
    cmp [rdx+r14*4],r13d
    jge 1f
    mov [rdx+r14*4],r13d
1:  cmp r15d,ecx; je 2f
    cmp [rdx+r15*4],r13d
    jge 2f
    mov [rdx+r15*4],r13d
2:  lea rdx,[rip+ff_physical_vdef]
    mov [rdx+rcx*4],r13d
    lea rdx,[rip+ff_physical_vread]
    mov dword ptr [rdx+rcx*4],-1
    jmp .ffpd_commit

.ffpd_mov_v:
    mov r14d,[r12+8]
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    mov ecx,[r12+4]
    cmp ecx,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+rcx*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vread]
    mov eax,[rdx+rcx*4]
    call ffpd_raise_eax
    cmp r14d,ecx; je .ffpd_mov_no_read
    lea rdx,[rip+ff_physical_vread]
    cmp [rdx+r14*4],r13d
    jge .ffpd_mov_no_read
    mov [rdx+r14*4],r13d
.ffpd_mov_no_read:
    lea rdx,[rip+ff_physical_vdef]
    mov [rdx+rcx*4],r13d
    lea rdx,[rip+ff_physical_vread]
    mov dword ptr [rdx+rcx*4],-1
    jmp .ffpd_commit

.ffpd_store_v:
    mov r14d,[r12+8]
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    mov r15d,[r12+16]                # direct field id
    cmp r15d,dword ptr [rip+ff_instance_capacity]; jae .ffpd_fail
    mov rdx,[rip+ff_physical_mem_depth_ptr]
    mov eax,[rdx+r15*4]
    call ffpd_raise_eax
    mov [rdx+r15*4],r13d
    lea rdx,[rip+ff_physical_vread]
    cmp [rdx+r14*4],r13d
    jge .ffpd_store_read_done
    mov [rdx+r14*4],r13d
.ffpd_store_read_done:
    inc dword ptr [rip+ff_physical_memory_barriers]
    jmp .ffpd_commit

.ffpd_reduce_v:
    mov r14d,[r12+8]
    cmp r14d,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    mov eax,dword ptr [rip+ff_physical_reduce_depth]
    call ffpd_raise_eax               # strict reduction chain is semantic
    mov dword ptr [rip+ff_physical_reduce_depth],r13d
    lea rdx,[rip+ff_physical_vread]
    cmp [rdx+r14*4],r13d
    jge .ffpd_reduce_read_done
    mov [rdx+r14*4],r13d
.ffpd_reduce_read_done:
    jmp .ffpd_commit

.ffpd_def_i:
    mov r14d,[r12+4]
    cmp r14d,1; ja .ffpd_fail
    lea rdx,[rip+ff_physical_idef]
    mov eax,[rdx+r14*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_iread]
    mov eax,[rdx+r14*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_idef]
    mov [rdx+r14*4],r13d
    lea rdx,[rip+ff_physical_iread]
    mov dword ptr [rdx+r14*4],-1
    jmp .ffpd_commit

.ffpd_mut_i:
    mov r14d,[r12+4]
    cmp r14d,1; ja .ffpd_fail
    lea rdx,[rip+ff_physical_idef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_iread]
    mov eax,[rdx+r14*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_idef]
    mov [rdx+r14*4],r13d
    lea rdx,[rip+ff_physical_iread]
    mov dword ptr [rdx+r14*4],-1
    jmp .ffpd_commit

.ffpd_itof:
    mov r14d,[r12+8]
    cmp r14d,1; ja .ffpd_fail
    lea rdx,[rip+ff_physical_idef]
    mov eax,[rdx+r14*4]
    cmp eax,-1; je .ffpd_fail
    call ffpd_raise_eax
    mov ecx,[r12+4]
    cmp ecx,FF_VREG_MAX; ja .ffpd_fail
    lea rdx,[rip+ff_physical_vdef]
    mov eax,[rdx+rcx*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_vread]
    mov eax,[rdx+rcx*4]
    call ffpd_raise_eax
    lea rdx,[rip+ff_physical_iread]
    cmp [rdx+r14*4],r13d
    jge .ffpd_itof_read_done
    mov [rdx+r14*4],r13d
.ffpd_itof_read_done:
    lea rdx,[rip+ff_physical_vdef]
    mov [rdx+rcx*4],r13d
    lea rdx,[rip+ff_physical_vread]
    mov dword ptr [rdx+rcx*4],-1

.ffpd_commit:
    cmp r13d,dword ptr [rip+ff_graph_capacity]
    jae .ffpd_fail
    mov rdx,[rip+ff_physical_depth_ptr]
    mov [rdx+rbx*4],r13d
    mov rdx,[rip+ff_physical_depth_counts_ptr]
    inc dword ptr [rdx+r13*4]
    cmp r13d,dword ptr [rip+ff_physical_max_depth]
    jbe .ffpd_next
    mov dword ptr [rip+ff_physical_max_depth],r13d
.ffpd_next:
    inc ebx
    jmp .ffpd_loop

# Stable counting sort by true dependency depth.  Independent operations become
# adjacent ISA candidates instead of inheriting arbitrary source/emitter order.
.ffpd_build_order:
    xor ebx,ebx                       # depth
    xor r12d,r12d                     # prefix/start
.ffpd_prefix:
    cmp ebx,dword ptr [rip+ff_physical_max_depth]
    ja .ffpd_fill_order
    mov rax,[rip+ff_physical_depth_cursor_ptr]
    mov [rax+rbx*4],r12d
    mov rdx,[rip+ff_physical_depth_counts_ptr]
    add r12d,[rdx+rbx*4]
    inc ebx
    jmp .ffpd_prefix
.ffpd_fill_order:
    xor ebx,ebx                       # source op
.ffpd_fill_loop:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .ffpd_ok
    mov rax,[rip+ff_physical_depth_ptr]
    mov r13d,[rax+rbx*4]
    mov rdx,[rip+ff_physical_depth_cursor_ptr]
    mov r14d,[rdx+r13*4]
    inc dword ptr [rdx+r13*4]
    mov rax,[rip+ff_physical_order_ptr]
    mov [rax+r14*4],ebx
    cmp r14d,ebx
    je .ffpd_fill_next
    inc dword ptr [rip+ff_physical_reordered_ops]
.ffpd_fill_next:
    inc ebx
    jmp .ffpd_fill_loop

.ffpd_ok:
    mov eax,dword ptr [rip+ff_op_count]
    mov dword ptr [rip+ff_physical_episode_ops],eax
    xor eax,eax
    jmp .ffpd_done
.ffpd_fail:
    mov eax,1
.ffpd_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# eax = predecessor depth or -1, r13d = current depth.  Every invocation here
# is a real RAW/WAR/WAW/memory/strict-reduction reason, never emitter order.
ffpd_raise_eax:
    cmp eax,-1
    je .ffpd_raise_ret
    inc dword ptr [rip+ff_physical_edge_count]
    inc eax
    cmp r13d,eax
    cmovb r13d,eax
.ffpd_raise_ret:
    ret

# parse dst from object, physical virtual regs 0..2 common to native256/native512.
ff_parse_dst:
    lea rsi,[rip+k_dst]; mov edx,k_dst_end-k_dst; call obj_get
    call ff_parse_reg_node
    ret
ff_parse_reg_node:
    call node_parse_u64
    test edx,edx; jnz .fpr_bad
    cmp eax,FF_VREG_MAX; ja .fpr_bad
    xor edx,edx; ret
.fpr_bad: mov edx,1; xor eax,eax; ret
ff_parse_ireg_node:
    call node_parse_u64
    test edx,edx; jnz .fpir_bad
    cmp eax,1; ja .fpir_bad
    xor edx,edx; ret
.fpir_bad: mov edx,1; xor eax,eax; ret

# signed decimal J_NUMBER -> eax i32, edx error.
# Compiler-only Field operation/fact storage is sized from the parsed source.
# Runtime field/rank/access/VREG ownership remains unchanged; this arena removes
# only the historical 8192-op / 64-constant frontend ceilings.
ff_prepare_graph_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .ffpga_have
    mov ebx,1
.ffpga_have:
    mov rax,rbx
    shr rax,32
    jnz .ffpga_fail
    mov rdi,[rip+ff_graph_arena_ptr]
    test rdi,rdi
    jz .ffpga_size
    mov rsi,[rip+ff_graph_arena_bytes]
    mov eax,SYS_munmap
    syscall
.ffpga_size:
    # 32-byte op record + eighteen dword vectors; two depth vectors own one
    # sentinel entry each.  104*N+8 exact bytes, cache-line rounded.
    mov rax,rbx
    imul rax,rax,104
    jo .ffpga_fail
    add rax,8
    jc .ffpga_fail
    add rax,63
    jc .ffpga_fail
    and rax,-64
    mov [rip+ff_graph_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .ffpga_fail
    mov [rip+ff_graph_arena_ptr],rax
    mov dword ptr [rip+ff_graph_capacity],ebx
    mov [rip+ff_ops_ptr],rax
    mov rcx,rbx; shl rcx,5; add rax,rcx
    mov rcx,rbx; shl rcx,2
    mov [rip+ff_op_global_fact_ptr],rax; add rax,rcx
    mov [rip+ff_global_fact_kind_ptr],rax; add rax,rcx
    mov [rip+ff_global_fact_key0_ptr],rax; add rax,rcx
    mov [rip+ff_global_fact_key1_ptr],rax; add rax,rcx
    mov [rip+ff_global_fact_key2_ptr],rax; add rax,rcx
    mov [rip+ff_global_fact_first_op_ptr],rax; add rax,rcx
    mov [rip+ff_global_fact_last_op_ptr],rax; add rax,rcx
    mov [rip+ff_global_fact_use_count_ptr],rax; add rax,rcx
    mov [rip+ff_physical_order_ptr],rax; add rax,rcx
    mov [rip+ff_physical_depth_ptr],rax; add rax,rcx
    mov [rip+ff_physical_depth_counts_ptr],rax
    lea rax,[rax+rcx+4]
    mov [rip+ff_physical_depth_cursor_ptr],rax
    lea rax,[rax+rcx+4]
    mov [rip+ff_op_const_slot_ptr],rax; add rax,rcx
    mov [rip+ff_const_pool_last_use_pos_ptr],rax; add rax,rcx
    mov [rip+ff_const_pool_transport_demand_ptr],rax; add rax,rcx
    mov [rip+ff_const_pool_bits_ptr],rax; add rax,rcx
    mov [rip+ff_const_pool_use_count_ptr],rax; add rax,rcx
    mov [rip+ff_const_pool_resident_reg_ptr],rax
    xor eax,eax
    pop rbx
    ret
.ffpga_fail:
    mov eax,1
    pop rbx
    ret

# Field/access fixed compiler metadata follows parsed instance cardinality.
# Rank-N axis metadata is allocated separately after the common RankFact is known.
ff_prepare_instance_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .ffpia_have
    mov ebx,1
.ffpia_have:
    mov rax,rbx
    shr rax,32
    jnz .ffpia_fail
    mov rdi,[rip+ff_instance_arena_ptr]
    test rdi,rdi
    jz .ffpia_size
    mov rsi,[rip+ff_instance_arena_bytes]
    mov eax,SYS_munmap
    syscall
.ffpia_size:
    # Fixed per-instance facts only. Axis deltas are not embedded here.
    mov rax,rbx
    imul rax,rax,56
    jo .ffpia_fail
    add rax,63
    jc .ffpia_fail
    and rax,-64
    mov [rip+ff_instance_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .ffpia_fail
    mov [rip+ff_instance_arena_ptr],rax
    mov dword ptr [rip+ff_instance_capacity],ebx
    mov [rip+ff_field_mode_ptr],rax; add rax,rbx
    mov [rip+ff_access_field_ptr],rax; add rax,rbx
    mov rcx,rbx; shl rcx,2
    mov [rip+ff_access_cache_slot_ptr],rax; add rax,rcx
    mov [rip+ff_cache_owner_ptr],rax; add rax,rcx
    mov [rip+ff_access_coord_slot_ptr],rax; add rax,rcx
    mov [rip+ff_coord_owner_ptr],rax; add rax,rcx
    mov [rip+ff_cache_use_count_ptr],rax; add rax,rcx
    mov [rip+ff_cache_resident_reg_ptr],rax; add rax,rcx
    mov [rip+ff_cache_last_load_pos_ptr],rax; add rax,rcx
    mov [rip+ff_access_address_fact_ptr],rax; add rax,rcx
    mov [rip+ff_address_fact_owner_ptr],rax; add rax,rcx
    mov [rip+ff_field_version_fact_ptr],rax; add rax,rcx
    mov [rip+ff_physical_mem_depth_ptr],rax; add rax,rcx
    mov [rip+ff_field_written_fact_ptr],rax; add rax,rbx
    mov [rip+ff_address_fact_gpr_ptr],rax
    xor eax,eax
    pop rbx
    ret
.ffpia_fail:
    mov eax,1
    pop rbx
    ret

# RankFact-derived axis metadata. One exact stride serves every AddressFact.
ff_prepare_axis_arena:
    push rbx
    mov rbx,[rip+ff_common_rank]
    test rbx,rbx
    jz .ffpaa_fail
    mov rax,rbx
    shl rax,2
    jc .ffpaa_fail
    mov [rip+ff_access_delta_stride],rax
    mov rcx,rax
    mov eax,dword ptr [rip+ff_instance_capacity]
    imul rax,rcx
    jo .ffpaa_fail
    add rax,63
    jc .ffpaa_fail
    and rax,-64
    mov [rip+ff_axis_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .ffpaa_fail
    mov [rip+ff_axis_arena_ptr],rax
    mov [rip+ff_access_delta_ptr],rax
    xor eax,eax
    pop rbx
    ret
.ffpaa_fail:
    mov eax,1
    pop rbx
    ret

ff_parse_i32_node:
    test rdi,rdi; jz .fpi_bad
    cmp qword ptr [rdi],J_NUMBER; jne .fpi_bad
    mov r8,[rdi+8]; mov rcx,[rdi+16]
    test rcx,rcx; jz .fpi_bad
    xor r9d,r9d
    cmp byte ptr [r8],'-'; jne .fpi_digits
    mov r9d,1; inc r8; dec rcx; jz .fpi_bad
.fpi_digits:
    xor rax,rax
.fpi_loop:
    test rcx,rcx; jz .fpi_done
    movzx edx,byte ptr [r8]; cmp dl,'0'; jb .fpi_bad; cmp dl,'9'; ja .fpi_bad
    imul rax,rax,10; sub edx,'0'; add rax,rdx
    mov r10,2147483648; cmp rax,r10; ja .fpi_bad
    inc r8; dec rcx; jmp .fpi_loop
.fpi_done:
    test r9d,r9d; jz .fpi_pos
    mov r10,2147483648; cmp rax,r10; ja .fpi_bad
    neg eax; xor edx,edx; ret
.fpi_pos:
    cmp rax,2147483647; ja .fpi_bad
    xor edx,edx; ret
.fpi_bad: xor eax,eax; mov edx,1; ret

# Stable code staging uses a source-seeded estimate only as the first attempt.
# If an emitter exhausts it, compile_field_source replays the whole AOT pass with
# a doubled mapping.  Thus no estimate or historical 1 MiB slot is an admission
# boundary, while rel32 patch pointers stay stable within every attempt.
ff_prepare_code_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .fpca_have
    mov ebx,1
.fpca_have:
    mov rax,rbx
    mul qword ptr [rip+ff_code_growth_factor]
    test rdx,rdx
    jnz .fpca_fail
    cmp rax,65536
    jae .fpca_align
    mov eax,65536
.fpca_align:
    add rax,4095
    jc .fpca_fail
    and rax,-4096
    mov [rip+ff_code_capacity],rax
    mov rdi,[rip+ff_code_ptr]
    test rdi,rdi
    jz .fpca_map
    mov rsi,[rip+ff_code_capacity_prev]
    mov eax,SYS_munmap
    syscall
.fpca_map:
    mov rsi,[rip+ff_code_capacity]
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .fpca_fail
    mov [rip+ff_code_ptr],rax
    mov rcx,[rip+ff_code_capacity]
    mov [rip+ff_code_capacity_prev],rcx
    xor eax,eax
    pop rbx
    ret
.fpca_fail:
    mov eax,1
    pop rbx
    ret

# ---------------- direct native code emission ----------------
ff_emit_u8:
    mov rax,[rip+ff_emit_ptr]; cmp rax,[rip+ff_emit_end]; jae .fe8_bad
    mov [rax],dil; inc rax; mov [rip+ff_emit_ptr],rax; xor eax,eax; ret
.fe8_bad: mov dword ptr [rip+ff_code_overflow],1; mov eax,1; ret
ff_emit_u32:
    mov rax,[rip+ff_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+ff_emit_end]; ja .fe32_bad
    mov [rax],edi; mov [rip+ff_emit_ptr],rcx; xor eax,eax; ret
.fe32_bad: mov dword ptr [rip+ff_code_overflow],1; mov eax,1; ret
ff_emit_bytes:
    # rdi ptr, rsi len
    mov rax,[rip+ff_emit_ptr]; lea rcx,[rax+rsi]; cmp rcx,[rip+ff_emit_end]; ja .feb_bad
    mov r8,rdi; mov rdi,rax; mov rcx,rsi; mov rsi,r8; rep movsb
    mov [rip+ff_emit_ptr],rdi; xor eax,eax; ret
.feb_bad: mov dword ptr [rip+ff_code_overflow],1; mov eax,1; ret

# call absolute fixed runtime VA in rax from generated stream.
ff_emit_call:
    push rbx
    mov rbx,rax
    mov dil,0xE8; call ff_emit_u8; test eax,eax; jnz .fec_bad
    mov rax,[rip+ff_emit_ptr]; mov rcx,[rip+ff_code_ptr]; sub rax,rcx
    add rax,FIELD_RUNTIME_GENERATED_VA
    add rax,4                         # after rel32 (opcode already emitted)
    sub rbx,rax
    mov edi,ebx; call ff_emit_u32
    pop rbx; ret
.fec_bad: pop rbx; mov eax,1; ret

# emit vector move dst edi <- src esi.
# Preserve the logical register IDs before feeding literal opcode bytes through
# DIL.  DIL aliases EDI: the old emitter accidentally overwrote dst while
# emitting the prefix/opcode, collapsing every non-zero destination to zmm/ymm0.
ff_emit_vmov:
    cmp edi,esi; je .fvm_ok
    push rbx
    push r12
    mov ebx,edi
    mov r12d,esi
.if FIELD_LANES == 16
    mov dil,0x62; call ff_emit_u8
    # EVEX inverted extension bits: R selects dst bit3, B selects src bit3.
    mov eax,0xF1
    test ebx,8; jz 1f; xor eax,0x80
1:  test ebx,16; jz 101f; xor eax,0x10
101: test r12d,8; jz 2f; xor eax,0x20
2:  test r12d,16; jz 102f; xor eax,0x40
102: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8; mov dil,0x48; call ff_emit_u8; mov dil,0x28; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov edx,r12d; and edx,7; or eax,edx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.else
    # VEX3 form is used deliberately so native256 can address the complete
    # architectural YMM0..15 bank rather than silently collapsing high regs.
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test ebx,8; jz 11f; xor eax,0x80
11: test r12d,8; jz 12f; xor eax,0x20
12: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x28; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov edx,r12d; and edx,7; or eax,edx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.endif
    pop r12
    pop rbx
.fvm_ok: xor eax,eax; ret

# Native unary sqrt on the existing f32 SIMD carrier. edi=dst, esi=src.
# No helper, libm call, or parallel math runtime exists.
ff_emit_vsqrt:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
.if FIELD_LANES == 16
    cmp ebx,31; ja .fevs_bad
    cmp r12d,31; ja .fevs_bad
    mov dil,0x62; call ff_emit_u8
    xor eax,eax
    mov r9d,ebx; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,7; or eax,r9d
    mov r9d,r12d; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,6; or eax,r9d
    mov r9d,r12d; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5; or eax,r9d
    mov r9d,ebx; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,4; or eax,r9d
    or eax,1; mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8       # W0, reserved vvvv, pp=none
    mov dil,0x48; call ff_emit_u8       # LL=512
    mov dil,0x51; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.else
    cmp ebx,15; ja .fevs_bad
    cmp r12d,15; ja .fevs_bad
    mov dil,0xC4; call ff_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx; or eax,1; mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8       # W0, reserved vvvv, L256, pp=none
    mov dil,0x51; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.endif
    xor eax,eax; jmp .fevs_done
.fevs_bad: mov eax,1
.fevs_done: pop r12; pop rbx; ret

# Native truncate-toward-zero on the existing f32 SIMD carrier. edi=dst, esi=src.
# AVX-512 uses VRNDSCALEPS, native256 uses VROUNDPS. No scalar fallback exists.
ff_emit_vtrunc:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
.if FIELD_LANES == 16
    cmp ebx,31; ja .fevt_bad
    cmp r12d,31; ja .fevt_bad
    mov dil,0x62; call ff_emit_u8
    xor eax,eax
    mov r9d,ebx; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,7; or eax,r9d
    mov r9d,r12d; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,6; or eax,r9d
    mov r9d,r12d; shr r9d,3; and r9d,1; xor r9d,1; shl r9d,5; or eax,r9d
    mov r9d,ebx; shr r9d,4; and r9d,1; xor r9d,1; shl r9d,4; or eax,r9d
    or eax,3; mov edi,eax; call ff_emit_u8
    mov dil,0x7D; call ff_emit_u8
    mov dil,0x48; call ff_emit_u8
    mov dil,0x08; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0; mov edi,eax; call ff_emit_u8
    mov dil,3; call ff_emit_u8
.else
    cmp ebx,15; ja .fevt_bad
    cmp r12d,15; ja .fevt_bad
    mov dil,0xC4; call ff_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx; or eax,3; mov edi,eax; call ff_emit_u8
    mov dil,0x7D; call ff_emit_u8
    mov dil,0x08; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0; mov edi,eax; call ff_emit_u8
    mov dil,3; call ff_emit_u8
.endif
    xor eax,eax; jmp .fevt_done
.fevt_bad: mov eax,1
.fevt_done: pop r12; pop rbx; ret

# vector binary: edi opcode (58 add,5c sub,59 mul,5e div), esi dst, edx=a, ecx=b
ff_emit_vbin:
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi
    mov r12d,esi                    # dst
    mov r13d,edx                    # src A / EVEX.vvvv
    mov r14d,ecx                    # src B / rm
.if FIELD_LANES == 16
    cmp r12d,31; ja .fevb_bad
    cmp r13d,31; ja .fevb_bad
    cmp r14d,31; ja .fevb_bad
    # EVEX.512 full ZMM0..31 register form. Policy never needs to know whether
    # a resident ValueFact landed in the low or high architectural bank.
    mov dil,0x62; call ff_emit_u8
    mov eax,1                       # map 0F
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx   # ~R
    mov ecx,r14d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx   # ~X (rm bit4)
    mov ecx,r14d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx   # ~B (rm bit3)
    mov ecx,r12d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx   # ~R'
    mov edi,eax; call ff_emit_u8
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3; or eax,4; mov edi,eax; call ff_emit_u8
    mov eax,r13d; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40; mov edi,eax; call ff_emit_u8
    mov edi,ebx; call ff_emit_u8
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r14d; and ecx,7; or eax,ecx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.else
    cmp r12d,15; ja .fevb_bad
    cmp r13d,15; ja .fevb_bad
    cmp r14d,15; ja .fevb_bad
    # VEX3 is required by the native256 physical register file.
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test r12d,8; jz 31f; xor eax,0x80
31: test r14d,8; jz 32f; xor eax,0x20
32: mov edi,eax; call ff_emit_u8
    mov eax,r13d; and eax,15; shl eax,3; mov edi,0x7C; sub edi,eax; call ff_emit_u8
    mov edi,ebx; call ff_emit_u8
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r14d; and ecx,7; or eax,ecx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.endif
    xor eax,eax
    jmp .fevb_done
.fevb_bad:
    mov eax,1
.fevb_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# edi=physical SIMD register -> eax=exact f32 bits, edx=1 when that
# carrier is an immutable ConstantFact, else edx=0.  This is compiler-only
# machine-fact lookup; no runtime table or second IR is created.
ff_const_bits_for_phys_reg:
    push rbx
    push r12
    mov r12d,edi
    xor ebx,ebx
.fcbpr_loop:
    cmp ebx,dword ptr [rip+ff_const_pool_count]
    jae .fcbpr_none
    mov rax,[rip+ff_const_pool_resident_reg_ptr]
    cmp dword ptr [rax+rbx*4],r12d
    jne .fcbpr_next
    mov rax,[rip+ff_const_pool_bits_ptr]
    mov eax,[rax+rbx*4]
    mov edx,1
    jmp .fcbpr_ret
.fcbpr_next:
    inc ebx
    jmp .fcbpr_loop
.fcbpr_none:
    xor eax,eax
    xor edx,edx
.fcbpr_ret:
    pop r12
    pop rbx
    ret

# accumulator FMA: edi=dst(acc), esi=a, edx=b.  The AVX2 VEX3 form
# supports the complete YMM0..15 source bank so bounded physical supernodes may
# keep coefficient scratch/X in high registers without synthetic spills.
ff_emit_vfma_acc:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    # 1.3.75 operator-form burn happens at the final MachineFact boundary.
    # The Physical DAG remains authoritative; exact immutable coefficients
    # +1/-1/0 simply cease to exist as multiplies under tolerant FP.
    cmp dword ptr [rip+ff_fp_tolerant],1
    jne .fevfa_normal
    mov edi,r13d
    call ff_const_bits_for_phys_reg
    test edx,edx
    jz .fevfa_try_a_const
    mov r14d,r12d
    cmp eax,0x3f800000
    je .fevfa_add
    cmp eax,0xbf800000
    je .fevfa_sub
    test eax,eax
    je .fevfa_zero
.fevfa_try_a_const:
    mov edi,r12d
    call ff_const_bits_for_phys_reg
    test edx,edx
    jz .fevfa_normal
    mov r14d,r13d
    cmp eax,0x3f800000
    je .fevfa_add
    cmp eax,0xbf800000
    je .fevfa_sub
    test eax,eax
    je .fevfa_zero
    jmp .fevfa_normal
.fevfa_add:
    mov edi,0x58
    mov esi,ebx
    mov edx,ebx
    mov ecx,r14d
    call ff_emit_vbin
    jmp .fevfa_fold_ret
.fevfa_sub:
    mov edi,0x5c
    mov esi,ebx
    mov edx,ebx
    mov ecx,r14d
    call ff_emit_vbin
    jmp .fevfa_fold_ret
.fevfa_zero:
    xor eax,eax
.fevfa_fold_ret:
    pop r13
    pop r12
    pop rbx
    ret
.fevfa_normal:
.if FIELD_LANES == 16
    # Full EVEX ZMM0..31 encoding.  GroupFact may keep independent packet
    # carriers in the high bank; burning causal independence must not force a
    # synthetic spill merely because the old one-packet emitter stopped at 15.
    cmp ebx,31; ja .fevfa_bad
    cmp r12d,31; ja .fevfa_bad
    cmp r13d,31; ja .fevfa_bad
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF2
    mov ecx,ebx; shr ecx,3; and ecx,1; test ecx,ecx; jz 201f; xor eax,0x80
201: mov ecx,r13d; shr ecx,4; and ecx,1; test ecx,ecx; jz 202f; xor eax,0x40
202: mov ecx,r13d; shr ecx,3; and ecx,1; test ecx,ecx; jz 203f; xor eax,0x20
203: mov ecx,ebx; shr ecx,4; and ecx,1; test ecx,ecx; jz 204f; xor eax,0x10
204: mov edi,eax; call ff_emit_u8
    mov eax,r12d; and eax,15; xor eax,15; shl eax,3; or eax,5; mov edi,eax; call ff_emit_u8
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40; mov edi,eax; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov edx,r13d; and edx,7; or eax,edx; or eax,0xC0; mov edi,eax; call ff_emit_u8
    jmp .fevfa_encoded
.fevfa_bad:
    pop r13
    pop r12
    pop rbx
    mov eax,1
    ret
.fevfa_encoded:
.else
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE2
    test ebx,8; jz 21f; xor eax,0x80
21: test r13d,8; jz 22f; xor eax,0x20
22: mov edi,eax; call ff_emit_u8
    mov eax,r12d; shl eax,3; mov edi,0x7D; sub edi,eax; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov edx,r13d; and edx,7; or eax,edx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.endif
    pop r13
    pop r12
    pop rbx
    xor eax,eax
    ret

# FMA with one canonical immutable value-cache vector directly from stack.
# edi=dst, esi=a(register), edx=value-cache slot.
ff_emit_vfma_acc_cacheslot:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    cmp r13d,dword ptr [rip+ff_cache_count]
    jae .fvfacs_bad
.if FIELD_LANES == 16
    cmp ebx,15; ja .fvfacs_bad
    cmp r12d,15; ja .fvfacs_bad
    # vfmadd231ps zmmDST,zmmA,[rsp+disp32]
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF2
    test ebx,8; jz 207f; xor eax,0x80
207: mov edi,eax; call ff_emit_u8
    mov eax,r12d; and eax,15; shl eax,3; mov edi,0x7D; sub edi,eax; call ff_emit_u8
    mov dil,0x48; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.else
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE2
    test ebx,8; jz 24f; xor eax,0x80
24: mov edi,eax; call ff_emit_u8
    mov eax,r12d; shl eax,3; mov edi,0x7D; sub edi,eax; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.endif
    mov edi,r13d; imul edi,edi,FIELD_LANES*4
    call ff_emit_u32
    test eax,eax; jnz .fvfacs_bad
    xor eax,eax
    jmp .fvfacs_done
.fvfacs_bad:
    mov eax,1
.fvfacs_done:
    pop r13
    pop r12
    pop rbx
    ret

# FMA with an immutable vector constant directly from the persistent
# generated-function stack pool. edi=dst, esi=a, edx=constant-pool slot.
ff_emit_vfma_acc_constslot:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    cmp r13d,dword ptr [rip+ff_const_pool_count]
    jae .fvfac_bad
.if FIELD_LANES == 16
    cmp ebx,15; ja .fvfac_bad
    cmp r12d,15; ja .fvfac_bad
    # vfmadd231ps zmmDST,zmmA,[rsp+disp32]
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF2
    test ebx,8; jz 208f; xor eax,0x80
208: mov edi,eax; call ff_emit_u8
    mov eax,r12d; and eax,15; shl eax,3; mov edi,0x7D; sub edi,eax; call ff_emit_u8
    mov dil,0x48; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.else
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE2
    test ebx,8; jz 31f; xor eax,0x80
31: mov edi,eax; call ff_emit_u8
    mov eax,r12d; shl eax,3; mov edi,0x7D; sub edi,eax; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.endif
    mov edi,dword ptr [rip+ff_cache_count]
    add edi,r13d
    imul edi,edi,FIELD_LANES*4
    call ff_emit_u32
    test eax,eax; jnz .fvfac_bad
    xor eax,eax
    jmp .fvfac_done
.fvfac_bad:
    mov eax,1
.fvfac_done:
    pop r13
    pop r12
    pop rbx
    ret

# constant f32 bits edi -> vector dst esi via stack broadcast.
ff_build_access_cache:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi,[rip+ff_access_cache_slot_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov rdi,[rip+ff_cache_owner_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov dword ptr [rip+ff_cache_count],0
    xor ebx,ebx                         # access i
.fbac_i:
    cmp ebx,dword ptr [rip+ff_access_count]
    jae .fbac_done
    mov rax,[rip+ff_access_field_ptr]
    movzx r12d,byte ptr [rax+rbx]
    mov rax,[rip+ff_field_mode_ptr]
    cmp byte ptr [rax+r12],MODE_INPUT
    je .fbac_version_safe
    # 1.3.6 Versioned LoadFact proof: a non-input field is cacheable only when
    # the complete post-optimization graph contains no store to that field.
    # One field's store never flushes another field's authority.
    mov rax,[rip+ff_field_written_fact_ptr]
    cmp byte ptr [rax+r12],0
    jne .fbac_next
.fbac_version_safe:
    xor r13d,r13d                       # prior access j
.fbac_search:
    cmp r13d,ebx
    jae .fbac_new
    mov rax,[rip+ff_access_cache_slot_ptr]
    cmp dword ptr [rax+r13*4],FF_CACHE_NONE
    je .fbac_search_next
    mov rax,[rip+ff_access_field_ptr]
    movzx eax,byte ptr [rax+r13]
    cmp eax,r12d
    jne .fbac_search_next
    # Access delta records have exactly RankFact axes, so comparing the complete
    # span canonicalizes structurally duplicate coordinate spellings.
    mov r14,rbx; imul r14,qword ptr [rip+ff_access_delta_stride]
    mov r15,r13; imul r15,qword ptr [rip+ff_access_delta_stride]
    xor ecx,ecx
.fbac_delta_cmp:
    cmp rcx,qword ptr [rip+ff_common_rank]
    jae .fbac_reuse
    mov rax,[rip+ff_access_delta_ptr]
    lea r10,[rax+r14]
    lea r11,[rax+r15]
    mov edx,[r10+rcx*4]
    cmp edx,[r11+rcx*4]
    jne .fbac_search_next
    inc ecx
    jmp .fbac_delta_cmp
.fbac_reuse:
    mov rax,[rip+ff_access_cache_slot_ptr]
    mov edx,[rax+r13*4]
    mov [rax+rbx*4],edx
    jmp .fbac_next
.fbac_search_next:
    inc r13d
    jmp .fbac_search
.fbac_new:
    mov edx,dword ptr [rip+ff_cache_count]
    cmp edx,dword ptr [rip+ff_instance_capacity]
    jae .fbac_fail
    mov rax,[rip+ff_access_cache_slot_ptr]
    mov [rax+rbx*4],edx
    mov rax,[rip+ff_cache_owner_ptr]
    mov [rax+rdx*4],ebx
    inc dword ptr [rip+ff_cache_count]
.fbac_next:
    inc ebx
    jmp .fbac_i
.fbac_done:
    xor eax,eax
    jmp .fbac_ret
.fbac_fail:
    mov eax,1
.fbac_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Coordinate identity is independent of field identity.  When runtime proves
# all immutable input fields share byte strides, equal Rank-N deltas can reuse
# one physical offset vector across different field bases.
ff_build_coord_cache:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi,[rip+ff_access_coord_slot_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov rdi,[rip+ff_coord_owner_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov dword ptr [rip+ff_coord_count],0
    xor ebx,ebx
.fbcc_i:
    cmp ebx,dword ptr [rip+ff_access_count]
    jae .fbcc_done
    mov rax,[rip+ff_access_field_ptr]
    movzx r12d,byte ptr [rax+rbx]
    mov rax,[rip+ff_field_mode_ptr]
    cmp byte ptr [rax+r12],MODE_INPUT
    jne .fbcc_next
    xor r13d,r13d
.fbcc_search:
    cmp r13d,ebx
    jae .fbcc_new
    mov rax,[rip+ff_access_coord_slot_ptr]
    cmp dword ptr [rax+r13*4],FF_CACHE_NONE
    je .fbcc_search_next
    mov r14,rbx; imul r14,qword ptr [rip+ff_access_delta_stride]
    mov r15,r13; imul r15,qword ptr [rip+ff_access_delta_stride]
    xor ecx,ecx
.fbcc_delta_cmp:
    cmp rcx,qword ptr [rip+ff_common_rank]
    jae .fbcc_reuse
    mov rax,[rip+ff_access_delta_ptr]
    lea r10,[rax+r14]
    lea r11,[rax+r15]
    mov edx,[r10+rcx*4]
    cmp edx,[r11+rcx*4]
    jne .fbcc_search_next
    inc ecx
    jmp .fbcc_delta_cmp
.fbcc_reuse:
    mov rax,[rip+ff_access_coord_slot_ptr]
    mov edx,[rax+r13*4]
    mov [rax+rbx*4],edx
    jmp .fbcc_next
.fbcc_search_next:
    inc r13d
    jmp .fbcc_search
.fbcc_new:
    mov edx,dword ptr [rip+ff_coord_count]
    cmp edx,dword ptr [rip+ff_instance_capacity]
    jae .fbcc_fail
    mov rax,[rip+ff_access_coord_slot_ptr]
    mov [rax+rbx*4],edx
    mov rax,[rip+ff_coord_owner_ptr]
    mov [rax+rdx*4],ebx
    inc dword ptr [rip+ff_coord_count]
.fbcc_next:
    inc ebx
    jmp .fbcc_i
.fbcc_done:
    xor eax,eax
    jmp .fbcc_ret
.fbcc_fail:
    mov eax,1
.fbcc_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Demand-weighted immutable LoadFact residency. Physical carriers are owned by
# causal lifetime, not by permanent subsystem labels. Address/load helpers finish
# before arithmetic begins; regular preload therefore writes a resident LoadFact
# directly into its final carrier. A stack reload authority exists only when the
# same immutable fact has a future OP_LOAD after the first arithmetic helper that
# can clobber SIMD state. No workload identity, stencil width, fixed access count,
# reuse threshold, or store-specific residency disable route owns this decision.
#
# The preload phase also has its own carrier lifetime: logical v0 has no
# arithmetic authority yet, so nonresident preload may borrow the profile's v0
# carrier as transport. Native256 additionally derives a reserved-carrier mask
# from actual persistent procedural-index facts; no workload name or width count
# participates. Native512 keeps its mature carrier table unchanged.
ff_assign_resident_loads:
    mov rdi,[rip+ff_cache_resident_reg_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov rdi,[rip+ff_cache_use_count_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov rdi,[rip+ff_const_pool_transport_demand_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+ff_graph_capacity]
    rep stosd
    mov rdi,[rip+ff_cache_last_load_pos_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov rdi,[rip+ff_const_pool_last_use_pos_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_graph_capacity]
    rep stosd
    push rbx
    push r12
    push r13
    push r14
    push r15
    # Physical carrier ownership starts empty; ISA-specific procedural roles add
    # only the carriers that really exist in the proven DAG.
    mov dword ptr [rip+ff_resident_reserved_mask],0
.if FIELD_LANES == 8
    # Native256 shares ordinary YMM carriers with procedural roles.
    lea rax,[rip+ff_physical_vdef]
    cmp dword ptr [rax+3*4],-1
    je .farl_no_v3_role
    lea rax,[rip+ff_vreg_phys_table]
    movzx ecx,byte ptr [rax+3]
    bts dword ptr [rip+ff_resident_reserved_mask],ecx
.farl_no_v3_role:
    lea rax,[rip+ff_physical_idef]
    cmp dword ptr [rax+0*4],-1
    je .farl_no_i0_role
    bts dword ptr [rip+ff_resident_reserved_mask],FF256_I0_REG
.farl_no_i0_role:
    cmp dword ptr [rax+1*4],-1
    je .farl_no_i1_role
    bts dword ptr [rip+ff_resident_reserved_mask],FF256_I1_REG
.farl_no_i1_role:
    cmp dword ptr [rip+ff_physical_reduce_depth],-1
    je .farl_no_reduce_role
    # Native256 strict reduction uses YMM0 as active-lane scratch and YMM5 as
    # the hidden recurrence. Outside a reduction DAG both carriers are ordinary
    # reloadable physical capacity.
    bts dword ptr [rip+ff_resident_reserved_mask],0
    bts dword ptr [rip+ff_resident_reserved_mask],FF256_REDUCE_REG
.farl_no_reduce_role:
.endif
    mov dword ptr [rip+ff_resident_limit],ff_resident_reg_table_end-ff_resident_reg_table
    mov dword ptr [rip+ff_first_resident_clobber_pos],0x7fffffff
    xor ebx,ebx
.farl_count:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .farl_choose
    # Residency lifetime follows emitted Physical Reality, not source order.
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov r12,[rip+ff_ops_ptr]
    add r12,rax
    mov eax,[r12]
    cmp eax,OP_STORE
    je .farl_mark_clobber
    cmp eax,OP_IINDEX
    jb .farl_maybe_load
    cmp eax,OP_ITOF32
    jbe .farl_mark_clobber
.farl_maybe_load:
    cmp eax,OP_CONST
    je .farl_count_const
    cmp eax,OP_LOAD
    jne .farl_count_next
    mov edi,[r12+16]
    cmp edi,dword ptr [rip+ff_access_count]
    jae .farl_mark_clobber
    mov rax,[rip+ff_access_cache_slot_ptr]
    mov r13d,[rax+rdi*4]
    cmp r13d,FF_CACHE_NONE
    je .farl_count_uncached_clobber
    # Score the transport that residency actually erases after consumer-local
    # folding.  A producer already consumed as the MUL rm operand has no
    # standalone stack reload to avoid, so it contributes zero register demand.
    mov edi,[r12+4]
    mov esi,ebx
    call ff_consumer_local_foldable
    test eax,eax
    jnz .farl_load_demand_done
    mov edi,[r12+16]
    call ff_count_access_use
.farl_load_demand_done:
    mov rax,[rip+ff_cache_last_load_pos_ptr]
    mov [rax+r13*4],ebx
    jmp .farl_count_next
.farl_count_uncached_clobber:
    # Mutable/uncached field loads execute a runtime helper in arithmetic.
    mov edi,[r12+16]
    call ff_count_access_use
    jmp .farl_count_next
.farl_count_const:
    # ConstantFact demand participates in the same immutable-carrier economy as
    # LoadFact demand.  Record its final emitted consumer position so helper
    # reloads stop exactly when the fact has no future consumer.
    mov rax,r12
    mov rdx,[rip+ff_ops_ptr]
    sub rax,rdx
    shr rax,5                           # OP_SIZE == 32
    mov rdx,[rip+ff_op_const_slot_ptr]
    mov eax,[rdx+rax*4]
    cmp eax,-1
    je .farl_count_next
    mov r13d,eax
    mov rdx,[rip+ff_const_pool_last_use_pos_ptr]
    mov [rdx+r13*4],ebx
    mov edi,[r12+4]
    mov esi,ebx
    call ff_consumer_local_foldable
    test eax,eax
    jnz .farl_count_next
    mov rdx,[rip+ff_const_pool_transport_demand_ptr]
    inc dword ptr [rdx+r13*4]
    jmp .farl_count_next
.farl_mark_clobber:
    mov eax,dword ptr [rip+ff_first_resident_clobber_pos]
    cmp ebx,eax
    jae .farl_count_next
    mov dword ptr [rip+ff_first_resident_clobber_pos],ebx
.farl_count_next:
    inc ebx
    jmp .farl_count
.farl_choose:
    # Unified sparse physical materialization: immutable LoadFacts and
    # ConstantFacts compete for the real carrier bank under one avoided-transport
    # score. ISA differences enter only through ff_resident_reg_table and the
    # reserved-role mask derived above.
    xor r14d,r14d
.farl_pick_unified:
    cmp r14d,dword ptr [rip+ff_resident_limit]
    jae .farl_done
.farl_find_carrier_unified:
    cmp r14d,dword ptr [rip+ff_resident_limit]
    jae .farl_done
    lea rax,[rip+ff_resident_reg_table]
    movzx edx,byte ptr [rax+r14]
    inc r14d
    bt dword ptr [rip+ff_resident_reserved_mask],edx
    jc .farl_find_carrier_unified

    mov r12d,-1
    xor r13d,r13d
    xor r15d,r15d                    # 0=LoadFact, 1=ConstantFact
    xor ebx,ebx
.farl_scan_load_unified:
    cmp ebx,dword ptr [rip+ff_cache_count]
    jae .farl_scan_const_begin_unified
    mov rax,[rip+ff_cache_resident_reg_ptr]
    cmp dword ptr [rax+rbx*4],FF_CACHE_NONE
    jne .farl_scan_load_next_unified
    mov rax,[rip+ff_cache_use_count_ptr]
    mov eax,[rax+rbx*4]
    cmp eax,r13d
    jbe .farl_scan_load_next_unified
    mov r13d,eax
    mov r12d,ebx
    xor r15d,r15d
.farl_scan_load_next_unified:
    inc ebx
    jmp .farl_scan_load_unified
.farl_scan_const_begin_unified:
    xor ebx,ebx
.farl_scan_const_unified:
    cmp ebx,dword ptr [rip+ff_const_pool_count]
    jae .farl_have_best_unified
    mov rax,[rip+ff_const_pool_resident_reg_ptr]
    cmp dword ptr [rax+rbx*4],-1
    jne .farl_scan_const_next_unified
    mov rax,[rip+ff_const_pool_transport_demand_ptr]
    mov eax,[rax+rbx*4]
    cmp eax,r13d
    jbe .farl_scan_const_next_unified
    mov r13d,eax
    mov r12d,ebx
    mov r15d,1
.farl_scan_const_next_unified:
    inc ebx
    jmp .farl_scan_const_unified
.farl_have_best_unified:
    cmp r12d,-1
    je .farl_done
    test r13d,r13d
    jz .farl_done
    test r15d,r15d
    jnz .farl_assign_const_unified
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov [rax+r12*4],edx
    jmp .farl_pick_unified
.farl_assign_const_unified:
    mov rax,[rip+ff_const_pool_resident_reg_ptr]
    mov [rax+r12*4],edx
    jmp .farl_pick_unified
.farl_done:
    xor eax,eax
    jmp .farl_ret
.farl_fail:
    mov eax,1
.farl_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# 1.3.74 burn-level AddressFact -> MachineFact allocation.
# The carrier bank is architectural capacity, never a workload threshold.  If
# the Physical DAG contains a helper-clobber edge, only callee-saved RBX is
# admitted; a helper-free hot Region may consume the full caller-saved bank.
ff_assign_address_gprs:
    push rbx
    push r12
    mov rdi,[rip+ff_address_fact_gpr_ptr]
    mov eax,-1
    mov ecx,dword ptr [rip+ff_instance_capacity]
    rep stosd
    mov r12d,ff_address_gpr_table_end-ff_address_gpr_table
    cmp dword ptr [rip+ff_first_resident_clobber_pos],0x7fffffff
    je .faag_have_limit
    mov r12d,1
.faag_have_limit:
    xor ebx,ebx
.faag_loop:
    cmp ebx,dword ptr [rip+ff_address_fact_count]
    jae .faag_done
    cmp ebx,r12d
    jae .faag_done
    lea rax,[rip+ff_address_gpr_table]
    movzx edx,byte ptr [rax+rbx]
    mov rax,[rip+ff_address_fact_gpr_ptr]
    mov [rax+rbx*4],edx
    inc ebx
    jmp .faag_loop
.faag_done:
    xor eax,eax
    pop r12
    pop rbx
    ret

# edi=access id -> eax=resident GPR id or -1.  AddressFact identity, not source
# access identity, owns the carrier so reused relations converge automatically.
ff_address_gpr_for_access:
    cmp edi,dword ptr [rip+ff_access_count]
    jae .fagfa_none
    mov rax,[rip+ff_access_address_fact_ptr]
    mov eax,[rax+rdi*4]
    test eax,eax
    js .fagfa_none
    cmp eax,dword ptr [rip+ff_addr_pool_count]
    jae .fagfa_none
    mov rdx,[rip+ff_address_fact_gpr_ptr]
    mov eax,[rdx+rax*4]
    ret
.fagfa_none:
    mov eax,-1
    ret

# Emit one Region-entry load for every AddressFact that owns a real GPR.  The
# stack pool remains the truthful cold/fallback authority, but a hot Region never
# re-reads it per packet.
ff_emit_address_gpr_residents:
    push rbx
    push r12
    xor ebx,ebx
.feagr_loop:
    cmp ebx,dword ptr [rip+ff_addr_pool_count]
    jae .feagr_done
    mov rax,[rip+ff_address_fact_gpr_ptr]
    mov r12d,[rax+rbx*4]
    cmp r12d,-1
    je .feagr_next
    mov eax,0x48
    test r12d,8
    jz 171f
    or eax,0x04
171: mov edi,eax; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov eax,r12d; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_cache_count]
    # The canonical frame-coordinate namespace remains reserved because constant
    # and transient helper stack offsets are one shared physical numbering domain.
    # Native512 no longer emits coord stores/loads, so these bytes are address
    # space only, not memory traffic; removing the namespace itself belongs to a
    # later whole-frame renumbering, not a partial compatibility shim.
    add edi,dword ptr [rip+ff_const_pool_count]
    imul edi,edi,FIELD_LANES*4
    lea edi,[rdi+rbx*8]
    call ff_emit_u32
    test eax,eax
    jnz .feagr_bad
.feagr_next:
    inc ebx
    jmp .feagr_loop
.feagr_done:
    xor eax,eax
    pop r12
    pop rbx
    ret
.feagr_bad:
    mov eax,1
    pop r12
    pop rbx
    ret

# Compiler-only carrier aliases. Immutable LoadFacts/ConstantFacts do not need
# to be copied into generic logical temporaries merely because the source syntax
# named a vreg.  Consumers resolve directly to the fact's sovereign SIMD carrier.
ff_codegen_alias_reset:
    lea rdi,[rip+ff_codegen_vreg_alias]
    mov eax,-1
    mov ecx,FF_VREG_COUNT
    rep stosd
    ret
ff_codegen_alias_set:
    cmp edi,FF_VREG_COUNT
    jae .fcas_ret
    lea rax,[rip+ff_codegen_vreg_alias]
    mov [rax+rdi*4],esi
.fcas_ret:
    ret
ff_codegen_alias_kill:
    cmp edi,FF_VREG_COUNT
    jae .fcak_ret
    lea rax,[rip+ff_codegen_vreg_alias]
    mov dword ptr [rax+rdi*4],-1
.fcak_ret:
    ret
# edi=logical vreg -> eax=physical source carrier.
ff_codegen_source_reg:
    cmp edi,FF_VREG_COUNT
    jae .fcsr_bad
    lea rax,[rip+ff_codegen_vreg_alias]
    mov eax,[rax+rdi*4]
    cmp eax,-1
    jne .fcsr_ret
.if FIELD_LANES == 16
    lea eax,[rdi+FF_VREG_BASE]
.else
    lea rax,[rip+ff_vreg_phys_table]
    movzx eax,byte ptr [rax+rdi]
.endif
.fcsr_ret:
    ret
.fcsr_bad:
    mov eax,-1
    ret

# FMA_ACC uniquely reads and defines its destination.  If the destination still
# denotes an immutable alias (for example the canonical zero ConstantFact), burn
# that one value into the logical destination once before the destructive FMA.
ff_codegen_materialize_acc:
    push rbx
    mov ebx,edi
    cmp ebx,FF_VREG_COUNT
    jae .fcma_bad
    lea rax,[rip+ff_codegen_vreg_alias]
    mov esi,[rax+rbx*4]
    cmp esi,-1
    je .fcma_ok
.if FIELD_LANES == 16
    lea edi,[rbx+FF_VREG_BASE]
.else
    lea rax,[rip+ff_vreg_phys_table]
    movzx edi,byte ptr [rax+rbx]
.endif
    call ff_emit_vmov
    test eax,eax
    jnz .fcma_bad
    mov edi,ebx
    call ff_codegen_alias_kill
.fcma_ok:
    xor eax,eax
    pop rbx
    ret
.fcma_bad:
    mov eax,1
    pop rbx
    ret

# Tolerant machine-fusion proof for a square immediately reduced into the hidden
# sum: t=x*x ; reduce(t) -> hidden=fma(x,x,hidden).  This is a def/use proof,
# not a sum-of-squares workload route. esi=current physical position -> eax 0/1.
ff_reduce_square_foldable:
    push rbx
    push r12
    push r13
    push r14
    cmp dword ptr [rip+ff_fp_tolerant],1
    jne .frsf_no
    mov ebx,esi
    lea ecx,[rbx+1]
    cmp ecx,dword ptr [rip+ff_op_count]
    jae .frsf_no
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov rdx,[rip+ff_ops_ptr]
    lea r12,[rdx+rax]
    cmp dword ptr [r12],OP_MUL
    jne .frsf_no
    mov eax,[r12+8]
    cmp eax,[r12+12]
    jne .frsf_no
    mov r13d,[r12+4]
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rcx*4]
    imul rax,OP_SIZE
    mov rdx,[rip+ff_ops_ptr]
    add rdx,rax
    cmp dword ptr [rdx],OP_REDUCE
    jne .frsf_no
    cmp dword ptr [rdx+8],r13d
    jne .frsf_no
    add ebx,2
.frsf_scan:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .frsf_yes
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov rdx,[rip+ff_ops_ptr]
    add rdx,rax
    mov r14d,[rdx]
    cmp r14d,OP_NOP; je .frsf_next
    cmp r14d,OP_ADD; je .frsf_read2
    cmp r14d,OP_SUB; je .frsf_read2
    cmp r14d,OP_MUL; je .frsf_read2
    cmp r14d,OP_DIV; je .frsf_read2
    cmp r14d,OP_FMA_ACC; je .frsf_readfma
    cmp r14d,OP_SQRT; je .frsf_read1
    cmp r14d,OP_TRUNC; je .frsf_read1
    cmp r14d,OP_MOV; je .frsf_read1
    cmp r14d,OP_STORE; je .frsf_read1_nodef
    cmp r14d,OP_REDUCE; je .frsf_read1_nodef
    jmp .frsf_defcheck
.frsf_read2:
    cmp dword ptr [rdx+8],r13d; je .frsf_no
    cmp dword ptr [rdx+12],r13d; je .frsf_no
    jmp .frsf_defcheck
.frsf_readfma:
    cmp dword ptr [rdx+4],r13d; je .frsf_no
    cmp dword ptr [rdx+8],r13d; je .frsf_no
    cmp dword ptr [rdx+12],r13d; je .frsf_no
    jmp .frsf_defcheck
.frsf_read1:
    cmp dword ptr [rdx+8],r13d; je .frsf_no
    jmp .frsf_defcheck
.frsf_read1_nodef:
    cmp dword ptr [rdx+8],r13d; je .frsf_no
    jmp .frsf_next
.frsf_defcheck:
    cmp r14d,OP_CONST; je .frsf_maybe_def
    cmp r14d,OP_LOAD; je .frsf_maybe_def
    cmp r14d,OP_ADD; je .frsf_maybe_def
    cmp r14d,OP_SUB; je .frsf_maybe_def
    cmp r14d,OP_MUL; je .frsf_maybe_def
    cmp r14d,OP_DIV; je .frsf_maybe_def
    cmp r14d,OP_SQRT; je .frsf_maybe_def
    cmp r14d,OP_TRUNC; je .frsf_maybe_def
    cmp r14d,OP_MOV; je .frsf_maybe_def
    cmp r14d,OP_ITOF32; je .frsf_maybe_def
    cmp r14d,OP_FMA_ACC; jne .frsf_next
.frsf_maybe_def:
    cmp dword ptr [rdx+4],r13d
    je .frsf_yes
.frsf_next:
    inc ebx
    jmp .frsf_scan
.frsf_yes:
    mov eax,1
    jmp .frsf_ret
.frsf_no:
    xor eax,eax
.frsf_ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# edi=access id. Count a use of its immutable canonical cache slot.
ff_count_access_use:
    cmp edi,dword ptr [rip+ff_access_count]
    jae .fcau_ret
    mov rax,[rip+ff_access_cache_slot_ptr]
    mov eax,[rax+rdi*4]
    cmp eax,FF_CACHE_NONE
    je .fcau_ret
    mov rdx,[rip+ff_cache_use_count_ptr]
    inc dword ptr [rdx+rax*4]
.fcau_ret:
    ret

# Materialize every selected resident from canonical stack authority. This is
# used only after the fallback preload paths, where runtime helpers produced the
# stack cache before any resident carrier existed.
ff_emit_materialize_all_residents:
    push rbx
    xor ebx,ebx
.fmatr_loop:
    cmp ebx,dword ptr [rip+ff_cache_count]
    jae .fmatr_done
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov edi,[rax+rbx*4]
    cmp edi,FF_CACHE_NONE
    je .fmatr_next
    mov esi,ebx
    call ff_emit_cache_load
    test eax,eax
    jnz .fmatr_fail
.fmatr_next:
    inc ebx
    jmp .fmatr_loop
.fmatr_done:
    xor eax,eax
    pop rbx
    ret
.fmatr_fail:
    mov eax,1
    pop rbx
    ret

# edi=physical SIMD register -> eax=1 when the runtime preload helpers preserve
# that carrier across later helper calls in the same boundary episode. This is
# ISA ownership, not a workload route. Native512 helpers scratch ZMM16..31 and
# return through ZMM0; Native256 helpers return through YMM0 and scratch
# YMM6..11/YMM13..15, leaving only the actually-sovereign candidate carriers.
ff_resident_survives_preload_helpers:
.if FIELD_LANES == 16
    cmp edi,1
    jb .frsph_no
    cmp edi,15
    ja .frsph_no
    jmp .frsph_yes
.else
    cmp edi,FF256_REDUCE_REG
    je .frsph_yes
    cmp edi,FF256_V3_REG
    je .frsph_yes
.endif
.frsph_no:
    xor eax,eax
    ret
.frsph_yes:
    mov eax,1
    ret

# Fallback preload paths materialize only residents that live in the helper
# clobber domain. Helper-sovereign residents were already named directly from
# SIMD0 when their load completed and therefore must not be reloaded from a
# stack copy that no longer exists.
ff_emit_materialize_helper_clobbered_residents:
    push rbx
    push r12
    xor ebx,ebx
.fmhcr_loop:
    cmp ebx,dword ptr [rip+ff_cache_count]
    jae .fmhcr_done
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov r12d,[rax+rbx*4]
    cmp r12d,FF_CACHE_NONE
    je .fmhcr_next
    mov edi,r12d
    call ff_resident_survives_preload_helpers
    test eax,eax
    jnz .fmhcr_next
    mov edi,r12d
    mov esi,ebx
    call ff_emit_cache_load
    test eax,eax
    jnz .fmhcr_fail
.fmhcr_next:
    inc ebx
    jmp .fmhcr_loop
.fmhcr_done:
    xor eax,eax
    pop r12
    pop rbx
    ret
.fmhcr_fail:
    mov eax,1
    pop r12
    pop rbx
    ret

# edi=current emitted physical-op position. Reload only resident immutable facts
# whose next/final OP_LOAD is still in the future. Their preload phase retained a
# stack authority exactly because the first clobber precedes that last load.
# Once the last consumer-copy has happened, the carrier may be clobbered without
# restoration: completion is the physical release event.
ff_emit_reload_residents:
    push rbx
    push r12
    mov r12d,edi
    xor ebx,ebx
.ferr_loop:
    cmp ebx,dword ptr [rip+ff_cache_count]
    jae .ferr_loads_done
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov edi,[rax+rbx*4]
    cmp edi,FF_CACHE_NONE
    je .ferr_next
    mov rax,[rip+ff_cache_last_load_pos_ptr]
    cmp dword ptr [rax+rbx*4],r12d
    jle .ferr_next
    mov esi,ebx
    call ff_emit_cache_load
    test eax,eax
    jnz .ferr_fail
.ferr_next:
    inc ebx
    jmp .ferr_loop
.ferr_loads_done:
    xor ebx,ebx
.ferr_const_loop:
    cmp ebx,dword ptr [rip+ff_const_pool_count]
    jae .ferr_done
    mov rax,[rip+ff_const_pool_resident_reg_ptr]
    mov edi,[rax+rbx*4]
    cmp edi,-1
    je .ferr_const_next
    mov rax,[rip+ff_const_pool_last_use_pos_ptr]
    cmp dword ptr [rax+rbx*4],r12d
    jle .ferr_const_next
    mov esi,dword ptr [rip+ff_cache_count]
    add esi,ebx
    call ff_emit_cache_load
    test eax,eax
    jnz .ferr_fail
.ferr_const_next:
    inc ebx
    jmp .ferr_const_loop
.ferr_done:
    xor eax,eax
    pop r12
    pop rbx
    ret
.ferr_fail:
    mov eax,1
    pop r12
    pop rbx
    ret

# Load immutable access edi into physical SIMD register esi from the
# compile-time episode cache, whether the cache slot is stack-backed or already
# resident. Used by 1.3.3 algebraic physicalizations without reissuing memory.
ff_emit_access_value:
    push rbx
    push r12
    mov ebx,edi
    mov r12d,esi
    cmp ebx,dword ptr [rip+ff_access_count]
    jae .feav_bad
    mov rax,[rip+ff_access_cache_slot_ptr]
    mov esi,[rax+rbx*4]
    cmp esi,FF_CACHE_NONE
    je .feav_bad
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov edx,[rax+rsi*4]
    cmp edx,FF_CACHE_NONE
    je .feav_stack
    mov edi,r12d
    mov esi,edx
    call ff_emit_vmov
    jmp .feav_done
.feav_stack:
    mov edi,r12d
    call ff_emit_cache_load
    jmp .feav_done
.feav_bad:
    mov eax,1
.feav_done:
    pop r12
    pop rbx
    ret

# 1.3.48 consumer-local immutable ValueFact fold.
#
# Physical demand and final emission share one liveness proof.  The planner asks
# whether a producer can disappear into the immediately following strict MUL;
# codegen consumes exactly the same answer.  This keeps resident selection and
# emitted transport from drifting into separate heuristics.
#
# ff_consumer_local_foldable:
#   edi=logical producer vreg, esi=current physical position -> eax=0/1.
# A fold is admitted only when the immediately following physical op is MUL,
# consumes the producer as operand B, does not also consume it as operand A, and
# no later consumer observes that version before redefinition.
ff_consumer_local_foldable:
    push rbx
    push r12
    push r13
    mov r12d,edi
    mov r13d,esi
    lea ebx,[r13d+1]
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fclf_fail
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov rdx,[rip+ff_ops_ptr]
    add rdx,rax
    cmp dword ptr [rdx],OP_MUL
    jne .fclf_fail
    cmp dword ptr [rdx+12],r12d
    jne .fclf_fail
    cmp dword ptr [rdx+8],r12d
    je .fclf_fail
    inc ebx
.fclf_scan:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fclf_accept
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov rdx,[rip+ff_ops_ptr]
    add rdx,rax
    mov eax,[rdx]
    cmp eax,OP_NOP; je .fclf_next
    cmp eax,OP_ADD; je .fclf_read2
    cmp eax,OP_SUB; je .fclf_read2
    cmp eax,OP_MUL; je .fclf_read2
    cmp eax,OP_DIV; je .fclf_read2
    cmp eax,OP_SQRT; je .fclf_read1_def
    cmp eax,OP_TRUNC; je .fclf_read1_def
    cmp eax,OP_MOV; je .fclf_read1_def
    cmp eax,OP_STORE; je .fclf_read1_nodef
    cmp eax,OP_REDUCE; je .fclf_read1_nodef
    cmp eax,OP_FMA_ACC; je .fclf_fma
    cmp eax,OP_LOAD; je .fclf_defonly
    cmp eax,OP_CONST; je .fclf_defonly
    cmp eax,OP_ITOF32; je .fclf_defonly
    jmp .fclf_next
.fclf_read2:
    cmp dword ptr [rdx+8],r12d; je .fclf_fail
    cmp dword ptr [rdx+12],r12d; je .fclf_fail
    cmp dword ptr [rdx+4],r12d; je .fclf_accept
    jmp .fclf_next
.fclf_read1_def:
    cmp dword ptr [rdx+8],r12d; je .fclf_fail
    cmp dword ptr [rdx+4],r12d; je .fclf_accept
    jmp .fclf_next
.fclf_read1_nodef:
    cmp dword ptr [rdx+8],r12d; je .fclf_fail
    jmp .fclf_next
.fclf_fma:
    cmp dword ptr [rdx+4],r12d; je .fclf_fail
    cmp dword ptr [rdx+8],r12d; je .fclf_fail
    cmp dword ptr [rdx+12],r12d; je .fclf_fail
    jmp .fclf_next
.fclf_defonly:
    cmp dword ptr [rdx+4],r12d; je .fclf_accept
.fclf_next:
    inc ebx
    jmp .fclf_scan
.fclf_accept:
    mov eax,1
    jmp .fclf_ret
.fclf_fail:
    xor eax,eax
.fclf_ret:
    pop r13
    pop r12
    pop rbx
    ret

# edi=logical producer vreg, esi=source kind (1=resident SIMD, 2=stack slot),
# edx=physical resident reg or absolute vector-stack slot, ecx=current physical
# position.  This is only the materialization side of the shared proof above.
ff_try_consumer_local_fold:
    push r12
    push r13
    push r14
    push r15
    mov r12d,edi
    mov r13d,esi
    mov r14d,edx
    mov r15d,ecx
    mov edi,r12d
    mov esi,r15d
    call ff_consumer_local_foldable
    test eax,eax
    jz .ftclf_fail
    lea eax,[r15d+1]
    mov dword ptr [rip+ff_fold_pending_consumer_pos],eax
    mov dword ptr [rip+ff_fold_pending_kind],r13d
    mov dword ptr [rip+ff_fold_pending_source],r14d
    inc dword ptr [rip+ff_consumer_local_fold_count]
    mov eax,1
    jmp .ftclf_ret
.ftclf_fail:
    xor eax,eax
.ftclf_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

# Native256 memory-source realization for the same strict binary arithmetic op.
# edi=opcode, esi=dst physical SIMD, edx=src-A physical SIMD, ecx=absolute
# vector stack slot.  Only the rm source moves from an explicit VMOVUPS into the
# existing VMULPS memory operand; arithmetic order and rounding are unchanged.
ff_emit_vbin_stack:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi                    # dst
    mov r13d,edx                    # src A
.if FIELD_LANES == 16
    cmp r12d,31; ja .fevbs_bad
    cmp r13d,31; ja .fevbs_bad
    # EVEX.512 dst,srcA,[rsp+disp32]. The memory ValueFact is consumed at its
    # frontier without first becoming a synthetic ZMM carrier.
    mov dil,0x62; call ff_emit_u8
    mov eax,0x61                    # base/index are low RSP: ~X=~B=1, map=1
    mov edx,r12d; shr edx,3; and edx,1; xor edx,1; shl edx,7; or eax,edx
    mov edx,r12d; shr edx,4; and edx,1; xor edx,1; shl edx,4; or eax,edx
    mov edi,eax; call ff_emit_u8
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3; or eax,4; mov edi,eax; call ff_emit_u8
    mov eax,r13d; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40; mov edi,eax; call ff_emit_u8
    mov edi,ebx; call ff_emit_u8
    mov eax,r12d; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,ecx; imul edi,edi,FIELD_LANES*4; call ff_emit_u32
.else
    cmp r12d,15; ja .fevbs_bad
    cmp r13d,15; ja .fevbs_bad
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test r12d,8; jz 13481f; xor eax,0x80
13481: mov edi,eax; call ff_emit_u8
    mov eax,r13d; and eax,15; shl eax,3; mov edi,0x7C; sub edi,eax; call ff_emit_u8
    mov edi,ebx; call ff_emit_u8
    mov eax,r12d; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,ecx; imul edi,edi,FIELD_LANES*4; call ff_emit_u32
.endif
    xor eax,eax
    jmp .fevbs_ret
.fevbs_bad:
    mov eax,1
.fevbs_ret:
    pop r13
    pop r12
    pop rbx
    ret

# Emit stack-frame allocation/release for the episode load cache. edi=bytes.
ff_emit_stack_sub:
    push rdi
    mov dil,0x48; call ff_emit_u8
    mov dil,0x81; call ff_emit_u8
    mov dil,0xEC; call ff_emit_u8
    pop rdi
    call ff_emit_u32
    ret
ff_emit_stack_add:
    push rdi
    mov dil,0x48; call ff_emit_u8
    mov dil,0x81; call ff_emit_u8
    mov dil,0xC4; call ff_emit_u8
    pop rdi
    call ff_emit_u32
    ret

# Store runtime helper result SIMD0 into cache slot edi.
# Store physical SIMD register esi into cache slot edi. Preload and arithmetic
# phases may use different carriers; stack authority follows the actual source
# carrier rather than an implicit SIMD0 transport convention.
ff_emit_cache_store_from:
    push rbx
    push r12
    mov r12d,edi
    mov ebx,esi
.if FIELD_LANES == 16
    cmp ebx,31; ja .fecs_bad
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF1
    test ebx,8; jz 301f; xor eax,0x80
301: test ebx,16; jz 302f; xor eax,0x10
302: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x48; call ff_emit_u8
    mov dil,0x11; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.else
    cmp ebx,15; ja .fecs_bad
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test ebx,8; jz 303f; xor eax,0x80
303: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x11; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.endif
    mov edi,r12d
    imul edi,edi,FIELD_LANES*4
    call ff_emit_u32
    xor eax,eax
    pop r12
    pop rbx
    ret
.fecs_bad:
    mov eax,1
    pop r12
    pop rbx
    ret

# Runtime/gather helpers return their vector in SIMD0.  Name that current ABI
# explicitly; regular/preload machine facts use ff_emit_cache_store_from instead.
ff_emit_cache_store_simd0:
    xor esi,esi
    jmp ff_emit_cache_store_from

# edi=canonical cache slot. Runtime/gather helper result is currently SIMD0. If
# the chosen immutable resident is outside the helper clobber domain, name that
# carrier immediately instead of forcing SIMD0 -> stack -> resident transport. A
# stack authority is retained only when a later proved consumer crosses the first
# arithmetic/helper clobber. Otherwise boundary syntax adds no memory traffic.
ff_emit_accept_helper_result:
    push rbx
    push r12
    mov r12d,edi
    cmp r12d,dword ptr [rip+ff_cache_count]
    jae .feahr_bad
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov ebx,[rax+r12*4]
    cmp ebx,FF_CACHE_NONE
    je .feahr_stack
    mov edi,ebx
    call ff_resident_survives_preload_helpers
    test eax,eax
    jz .feahr_stack
    mov edi,ebx
    xor esi,esi
    call ff_emit_vmov
    test eax,eax
    jnz .feahr_bad
    mov rax,[rip+ff_cache_last_load_pos_ptr]
    mov eax,[rax+r12*4]
    cmp eax,dword ptr [rip+ff_first_resident_clobber_pos]
    jle .feahr_ok
    mov edi,r12d
    mov esi,ebx
    call ff_emit_cache_store_from
    test eax,eax
    jnz .feahr_bad
    jmp .feahr_ok
.feahr_stack:
    mov edi,r12d
    call ff_emit_cache_store_simd0
    test eax,eax
    jnz .feahr_bad
.feahr_ok:
    xor eax,eax
    pop r12
    pop rbx
    ret
.feahr_bad:
    mov eax,1
    pop r12
    pop rbx
    ret

# Load cached vector into physical SIMD register edi from cache slot esi.
ff_emit_cache_load:
    push rbx
    mov ebx,edi
.if FIELD_LANES == 16
    cmp ebx,31; ja .fecl_bad
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF1
    test ebx,8; jz 203f; xor eax,0x80
203: test ebx,16; jz 205f; xor eax,0x10
205: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8; mov dil,0x48; call ff_emit_u8; mov dil,0x10; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.else
    # vmovups ymmDST,[rsp+disp32], VEX3 so DST may be YMM8..15.
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test ebx,8; jz 13f; xor eax,0x80
13: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x10; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
.endif
    mov edi,esi; imul edi,edi,FIELD_LANES*4; call ff_emit_u32
    pop rbx
    ret
.fecl_bad:
    mov eax,1
    pop rbx
    ret

# Materialize each regular address fact exactly once per generated invocation.
# Each entry is field_base + fixed signed physical delta.  The hot loop later
# supplies only q as an indexed operand and never reconstructs the invariant.
# edi=0 canonical interior delta authority, edi=1 execution-local piecewise delta.
ff_emit_addr_pool_init:
    push rbx
    push r12
    push r13
    mov r13d,edi
    xor ebx,ebx
.feapi_loop:
    cmp ebx,dword ptr [rip+ff_addr_pool_count]
    jae .feapi_done
    mov rax,[rip+ff_address_fact_owner_ptr]
    mov r12d,[rax+rbx*4]                 # representative access for this fact
    cmp r12d,0
    jl .feapi_bad
    cmp r12d,dword ptr [rip+ff_access_count]
    jae .feapi_bad
    mov rax,[rip+ff_access_field_ptr]
    movzx edi,byte ptr [rax+r12]
    call ff_emit_field_base_rax          # runtime RAX = field base
    test eax,eax; jnz .feapi_bad
    test r13d,r13d
    jnz .feapi_local_delta
    # Canonical interior AddressFact: immutable runtime arena established once
    # from source topology.  It is shared read-only, never worker-published.
    mov dil,0x4C; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov dil,0x1D; call ff_emit_u8
    mov rdx,FIELD_RUNTIME_LINEAR_DELTA_PTR_VA
    mov rax,[rip+ff_emit_ptr]
    mov rcx,[rip+ff_code_ptr]; sub rax,rcx
    add rax,FIELD_RUNTIME_GENERATED_VA
    add rax,4
    sub rdx,rax
    mov edi,edx; call ff_emit_u32
    test eax,eax; jnz .feapi_bad
    mov dil,0x4D; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov dil,0x9B; call ff_emit_u8
    mov edi,r12d; shl edi,3; call ff_emit_u32
    test eax,eax; jnz .feapi_bad
    jmp .feapi_have_delta
.feapi_local_delta:
    # Piecewise RegionFact is execution-local. No CLONE_VM worker publishes
    # mutable address state through a shared arena.
    mov dil,0x4C; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov dil,0x9C; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_region_delta_stack_off]
    lea edi,[rdi+r12*8]
    call ff_emit_u32
    test eax,eax; jnz .feapi_bad
.feapi_have_delta:
    lea rdi,[rip+cg_regular_add_delta]; mov esi,cg_regular_add_delta_end-cg_regular_add_delta; call ff_emit_bytes
    test eax,eax; jnz .feapi_bad
    # mov [rsp+vector_pool_bytes + access*8],rax
    mov dil,0x48; call ff_emit_u8
    mov dil,0x89; call ff_emit_u8
    mov dil,0x84; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_cache_count]
    add edi,dword ptr [rip+ff_const_pool_count]
    imul edi,edi,FIELD_LANES*4
    lea edi,[rdi+rbx*8]
    call ff_emit_u32
    test eax,eax; jnz .feapi_bad
    inc ebx
    jmp .feapi_loop
.feapi_done:
    xor eax,eax
    pop r13
    pop r12
    pop rbx
    ret
.feapi_bad:
    mov eax,1
    pop r13
    pop r12
    pop rbx
    ret

# Materialize each unique immutable f32 vector constant exactly once per
# generated function invocation. The stack frame persists across every vector
# episode, so hot arithmetic never rebroadcasts compile-time constants.
ff_emit_const_pool_init:
    push rbx
    xor ebx,ebx
.fecpi_loop:
    cmp ebx,dword ptr [rip+ff_const_pool_count]
    jae .fecpi_done
    mov rax,[rip+ff_const_pool_bits_ptr]
    mov edi,[rax+rbx*4]
    xor esi,esi
    call ff_emit_const_real
    test eax,eax; jnz .fecpi_bad
    mov edi,dword ptr [rip+ff_cache_count]
    add edi,ebx
    call ff_emit_cache_store_simd0
    test eax,eax; jnz .fecpi_bad
    inc ebx
    jmp .fecpi_loop
.fecpi_done:
    xor eax,eax
    pop rbx
    ret
.fecpi_bad:
    mov eax,1
    pop rbx
    ret

# Reload immutable vector constants into the physical profile's resident bank.
# Native256 carrier availability is derived from the Physical DAG: reduction,
# v3, and procedural-index authorities reserve only the registers they actually
# occupy. Boundary/general helpers may clobber reloadable residents, so generated
# code restores them after helper edges instead of giving helpers permanent ownership.
ff_emit_const_residents:
    # 1.3.6 exact-bit constant authority is ISA-neutral; only encoding differs.
    push rbx
    xor ebx,ebx
.fecrl_loop:
    cmp ebx,dword ptr [rip+ff_const_pool_count]
    jae .fecrl_done
    mov rax,[rip+ff_const_pool_resident_reg_ptr]
    mov edi,[rax+rbx*4]
    cmp edi,-1
    je .fecrl_next
    mov esi,dword ptr [rip+ff_cache_count]
    add esi,ebx
    call ff_emit_cache_load
    test eax,eax; jnz .fecrl_bad
.fecrl_next:
    inc ebx
    jmp .fecrl_loop
.fecrl_done:
    xor eax,eax
    pop rbx
    ret
.fecrl_bad:
    mov eax,1
    pop rbx
    ret

# rax=absolute VA of a runtime pointer variable, edi=byte index.
ff_emit_movzx_eax_runtime_byte_ptr_array:
    push rbx
    push r12
    mov rbx,rax
    mov r12d,edi
    # mov rax,[rip+ptr]
    mov dil,0x48; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov dil,0x05; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]
    mov rcx,[rip+ff_code_ptr]; sub rax,rcx
    add rax,FIELD_RUNTIME_GENERATED_VA
    add rax,4
    sub rbx,rax
    mov edi,ebx; call ff_emit_u32
    test eax,eax; jnz .fmxpa_bad
    # movzx eax,byte ptr [rax+index]
    mov dil,0x0F; call ff_emit_u8
    mov dil,0xB6; call ff_emit_u8
    mov dil,0x80; call ff_emit_u8
    mov edi,r12d; call ff_emit_u32
    test eax,eax; jnz .fmxpa_bad
    xor eax,eax
    pop r12
    pop rbx
    ret
.fmxpa_bad:
    mov eax,1
    pop r12
    pop rbx
    ret

# edi=field index, emit runtime base lookup through the instance-sized field-data arena.
ff_emit_field_base_rax:
    push rbx
    mov ebx,edi
    # mov rax,[rip+g_field_data_ptr]
    mov dil,0x48; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov dil,0x05; call ff_emit_u8
    mov rdx,FIELD_RUNTIME_FIELD_DATA_PTR_VA
    mov rax,[rip+ff_emit_ptr]
    mov rcx,[rip+ff_code_ptr]; sub rax,rcx
    add rax,FIELD_RUNTIME_GENERATED_VA
    add rax,4
    sub rdx,rax
    mov edi,edx; call ff_emit_u32
    test eax,eax; jnz .fefb_bad
    # mov rax,[rax+field*8] with disp32 so field count has no encoding ceiling.
    mov dil,0x48; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov dil,0x80; call ff_emit_u8
    mov edi,ebx; shl edi,3; call ff_emit_u32
    test eax,eax; jnz .fefb_bad
    xor eax,eax
    pop rbx
    ret
.fefb_bad:
    mov eax,1
    pop rbx
    ret

# Materialize the execution-local canonical packet CoordinateFact arena into R8.
# Native256 uses this carrier because architectural SIMD pressure may remove a
# persistent Rank-N register bank; carrier scarcity must not duplicate semantics.
ff_emit_packet_coord_arena_r8:
    mov dil,0x4C; call ff_emit_u8
    mov dil,0x8D; call ff_emit_u8
    mov dil,0x84; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_packet_coord_stack_off]
    call ff_emit_u32
    ret


# Direct regular-neighborhood load. edi=field, esi=access. The current Region
# already proves the complete vector packet is inside its stable neighborhood
# interior and that every immutable input is contiguous row-major.
# Therefore the access is exactly base + q*4 + precomputed_signed_byte_delta.
# No vector index construction, gather, modulo, bounds mask, or helper call
# survives in this physical path.
# Emit RAX = persistent regular-address fact for access EDI.  The fact is
# field_base + fixed physical delta and is materialized once in the generated
# function prologue.  Current q remains a separate causal index in RDX.
ff_emit_addr_fact_load:
    cmp edi,dword ptr [rip+ff_access_count]
    jae .feafl_bad
    push rbx
    mov rax,[rip+ff_access_address_fact_ptr]
    mov ebx,[rax+rdi*4]                  # canonical AddressFact slot
    cmp ebx,0
    jl .feafl_bad_pop
    cmp ebx,dword ptr [rip+ff_addr_pool_count]
    jae .feafl_bad_pop
    mov dil,0x48; call ff_emit_u8
    mov dil,0x8B; call ff_emit_u8
    mov dil,0x84; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_cache_count]
    add edi,dword ptr [rip+ff_const_pool_count]
    imul edi,edi,FIELD_LANES*4
    lea edi,[rdi+rbx*8]
    call ff_emit_u32
    pop rbx
    ret
.feafl_bad_pop:
    mov eax,1
    pop rbx
    ret
.feafl_bad:
    mov eax,1
    ret

# edi=field, esi=access, edx=physical SIMD destination.  Native256 emits the
# regular unmasked load directly into the final consumer residency, so a causal
# value never needs an emitter-convenience YMM0 -> YMMx copy.
ff_emit_direct_regular_load_to:
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    cmp r12d,dword ptr [rip+ff_access_count]
    jae .fedrlt_bad
    # Prefer the Region-resident AddressFact carrier.  Facts beyond the actual
    # architectural GPR bank retain the truthful stack authority and materialize
    # into RAX; this is capacity fallback, not a second hot backend.
    mov edi,r12d
    call ff_address_gpr_for_access
    mov r14d,eax
    cmp r14d,-1
    jne .fedrlt_have_base
    mov edi,r12d
    call ff_emit_addr_fact_load
    test eax,eax; jnz .fedrlt_bad
    xor r14d,r14d                       # RAX x86 register id
.fedrlt_have_base:
.if FIELD_LANES == 16
    cmp r13d,31; ja .fedrlt_bad
    # vmovups zmmDST,[BASE+r12*4].  The direct Region already proves all lanes
    # valid, so no k-mask identity survives the burn-level path.
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF1
    test r13d,8; jz 204f; xor eax,0x80
204: test r13d,16; jz 206f; xor eax,0x10
206: xor eax,0x40                       # X=0 -> R12 is the SIB index
    test r14d,8; jz 207f; xor eax,0x20
207: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x48; call ff_emit_u8
    mov dil,0x10; call ff_emit_u8
    mov eax,r13d; and eax,7; shl eax,3; or eax,0x04; mov edi,eax; call ff_emit_u8
    mov eax,r14d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
    xor eax,eax
    jmp .fedrlt_done
.else
    cmp r13d,15; ja .fedrlt_bad
    # vmovups ymmDST,[BASE+r12*4], VEX3 with the same MachineFact lifetime.
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test r13d,8; jz 41f; xor eax,0x80
41: xor eax,0x40
    test r14d,8; jz 42f; xor eax,0x20
42: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x10; call ff_emit_u8
    mov eax,r13d; and eax,7; shl eax,3; or eax,0x04; mov edi,eax; call ff_emit_u8
    mov eax,r14d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
    xor eax,eax
    jmp .fedrlt_done
.endif
.fedrlt_bad:
    mov eax,1
.fedrlt_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# edi=contiguous output field, esi=physical SIMD source.  The regular episode
# already proves q is a valid contiguous SIMD window, so the existing value is
# consumed directly by the store.  No YMM0 relocation and no runtime helper call
# are permitted merely for emitter ABI convenience.
ff_emit_direct_regular_store_from:
    push rbx
    mov ebx,esi
.if FIELD_LANES == 16
    cmp ebx,31; ja .fedrs_bad
.else
    cmp ebx,15; ja .fedrs_bad
.endif
    call ff_emit_field_base_rax
    test eax,eax; jnz .fedrs_bad
.if FIELD_LANES == 16
    # vmovups [rax+rdx*4]{k1},zmmSRC, full ZMM0..31 source bank.
    mov dil,0x62; call ff_emit_u8
    mov eax,0x61                    # low base/index, map 0F
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x49; call ff_emit_u8
    mov dil,0x11; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x04; mov edi,eax; call ff_emit_u8
    mov dil,0x90; call ff_emit_u8
.else
    # vmaskmovps [rax+rdx*4],ymm4,ymmSRC
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE2
    test ebx,8; jz 73f; xor eax,0x80
73: mov edi,eax; call ff_emit_u8
    mov dil,0x5D; call ff_emit_u8
    mov dil,0x2E; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x04; mov edi,eax; call ff_emit_u8
    mov dil,0x90; call ff_emit_u8
.endif
    xor eax,eax
    pop rbx
    ret
.fedrs_bad:
    mov eax,1
    pop rbx
    ret

# edi=field.  Coordinate offset vector is already in zmm17/ymm7; gather direct
# from the materialized field base without re-running coordinate decomposition.
ff_emit_direct_gather:
    push rdi
    call ff_emit_field_base_rax
    pop rdi
.if FIELD_LANES == 16
    lea rdi,[rip+cg_direct_gather512]; mov esi,cg_direct_gather512_end-cg_direct_gather512; call ff_emit_bytes
.else
    lea rdi,[rip+cg_direct_gather256]; mov esi,cg_direct_gather256_end-cg_direct_gather256; call ff_emit_bytes
.endif
    ret

# 1.3.76 Field -> canonical GroupFact closure.  No private width exists.
# The direct machine body may replicate only when every op is helper-free and
# side-effect-free inside one proved Region.  The realized body factor is the
# lesser of true Physical-DAG causal depth and architectural SIMD carrier
# capacity.  Those are physical facts, not source/workload thresholds.
ff_derive_field_groupfact:
    push rbx
    push r12
    mov dword ptr [rip+ff_machine_group_safe],1
    mov dword ptr [rip+group_body_factor],1
    mov dword ptr [rip+group_carrier_factor],1
    mov dword ptr [rip+group_lane_factor],FIELD_LANES
    mov dword ptr [rip+group_relation_mask],GF_REL_INDEPENDENT|GF_REL_OPERATOR
    xor ebx,ebx
.fdfg_scan:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fdfg_safe
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov r12,[rip+ff_ops_ptr]
    add r12,rax
    mov eax,[r12]
    cmp eax,OP_NOP; je .fdfg_next
    cmp eax,OP_CONST; je .fdfg_next
    cmp eax,OP_ADD; je .fdfg_next
    cmp eax,OP_SUB; je .fdfg_next
    cmp eax,OP_MUL; je .fdfg_next
    cmp eax,OP_DIV; je .fdfg_next
    cmp eax,OP_SQRT; je .fdfg_next
    cmp eax,OP_TRUNC; je .fdfg_next
    cmp eax,OP_MOV; je .fdfg_next
    cmp eax,OP_FMA_ACC; je .fdfg_next
    cmp eax,OP_REDUCE; je .fdfg_reduce
    cmp eax,OP_LOAD; jne .fdfg_unsafe
    mov eax,[r12+16]
    cmp eax,dword ptr [rip+ff_access_count]; jae .fdfg_unsafe
    mov rdx,[rip+ff_access_field_ptr]
    movzx eax,byte ptr [rdx+rax]
    mov rdx,[rip+ff_field_mode_ptr]
    cmp byte ptr [rdx+rax],MODE_INPUT
    jne .fdfg_unsafe
    jmp .fdfg_next
.fdfg_reduce:
    or dword ptr [rip+group_relation_mask],GF_REL_REDUCTION
.fdfg_next:
    inc ebx
    jmp .fdfg_scan
.fdfg_unsafe:
    mov dword ptr [rip+ff_machine_group_safe],0
    xor eax,eax
    pop r12
    pop rbx
    ret
.fdfg_safe:
    # A strict reduction publishes one exact recurrence order. Independent packet
    # arithmetic may exist, but changing the physical reduction episode can change
    # IEEE rounding. Contract authority therefore degrades only this recurrence to
    # the mature one-packet Vector form; strict helper-free work without reduction
    # remains eligible for the same GroupFact carrier proof.
    cmp dword ptr [rip+ff_fp_tolerant],1
    je 300f
    test dword ptr [rip+group_relation_mask],GF_REL_REDUCTION
    jnz .fdfg_no_group
300:
    # Canonical machine Group capacity comes from the carrier graph that already
    # exists after AddressFact/ValueFact allocation.  Packet zero owns the mature
    # Vector carriers.  Additional packets may exist only if the *actual* unused
    # SIMD bank can hold every immutable LoadFact cache identity plus the four
    # logical floating carriers.  No 2/4/8 candidate set or workload threshold
    # exists: architectural capacity minus live facts is the authority.
    mov dword ptr [rip+ff_group_used_simd_mask],0
.if FIELD_LANES == 16
    # Mature logical v0..v3 and hidden reduction carrier.
    bts dword ptr [rip+ff_group_used_simd_mask],1
    bts dword ptr [rip+ff_group_used_simd_mask],2
    bts dword ptr [rip+ff_group_used_simd_mask],3
    bts dword ptr [rip+ff_group_used_simd_mask],4
    cmp dword ptr [rip+ff_physical_reduce_depth],-1
    je 301f
    bts dword ptr [rip+ff_group_used_simd_mask],5
301:
.else
    # Native256 derives the same truth from its explicit carrier table and
    # procedural-role reservation mask.
    mov eax,dword ptr [rip+ff_resident_reserved_mask]
    mov dword ptr [rip+ff_group_used_simd_mask],eax
    xor ecx,ecx
302:
    cmp ecx,FF_VREG_COUNT
    jae 303f
    lea rax,[rip+ff_vreg_phys_table]
    movzx edx,byte ptr [rax+rcx]
    bts dword ptr [rip+ff_group_used_simd_mask],edx
    inc ecx
    jmp 302b
303:
.endif
    # Packet-zero resident immutable LoadFacts/ConstantFacts remain live across
    # the Region and therefore own their mature carriers.  Later packet LoadFacts
    # remain AddressFacts until first consumption and do not reserve shadow SIMD
    # carriers merely because a source OP_LOAD exists.
    xor ecx,ecx
304:
    cmp ecx,dword ptr [rip+ff_cache_count]
    jae 305f
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov edx,[rax+rcx*4]
    # A depth-major Group may not resurrect a packet-zero stack carrier after
    # scheduling has started.  If an immutable LoadFact did not win a mature
    # resident carrier, the canonical Vector episode remains the truthful form.
    cmp edx,-1
    je .fdfg_no_group
    bts dword ptr [rip+ff_group_used_simd_mask],edx
    inc ecx
    jmp 304b
305:
    xor ecx,ecx
306:
    cmp ecx,dword ptr [rip+ff_const_pool_count]
    jae 307f
    mov rax,[rip+ff_const_pool_resident_reg_ptr]
    mov edx,[rax+rcx*4]
    cmp edx,-1
    je .fdfg_no_group          # Group packet must not invent a const reload IR.
    bts dword ptr [rip+ff_group_used_simd_mask],edx
    inc ecx
    jmp 306b
307:
    # Publish the ordered free carrier bank.  Its 32-byte storage is exactly the
    # architectural ZMM/YMM register namespace, not a language/group-size cap.
    xor ecx,ecx
    xor r8d,r8d
.if FIELD_LANES == 16
    mov r9d,32
.else
    mov r9d,16
.endif
308:
    cmp ecx,r9d
    jae 309f
    bt dword ptr [rip+ff_group_used_simd_mask],ecx
    jc 3081f
    lea rax,[rip+ff_group_free_regs]
    mov [rax+r8],cl
    inc r8d
3081:
    inc ecx
    jmp 308b
309:
    mov dword ptr [rip+ff_group_free_count],r8d
    mov eax,FF_VREG_COUNT
    mov dword ptr [rip+ff_group_bundle_regs],eax
    test eax,eax
    jz .fdfg_no_group
    # One mature packet already exists. Each complete free carrier bundle adds
    # one truly independent packet body from live logical-vreg pressure only;
    # immutable LoadFacts remain AddressFacts until an actual consumer.
    mov ecx,eax
    mov eax,r8d
    xor edx,edx
    div ecx
    inc eax
    mov dword ptr [rip+group_carrier_factor],eax
    # Causal depth is the structural maximum; the physical carrier proof may
    # only contract it.
    mov ecx,dword ptr [rip+ff_physical_max_depth]
    inc ecx
    cmp eax,ecx
    jbe 310f
    mov eax,ecx
310:
    test eax,eax
    jnz 311f
    mov eax,1
311:
    mov dword ptr [rip+group_body_factor],eax
    jmp .fdfg_store_done
.fdfg_no_group:
    mov dword ptr [rip+group_body_factor],1
    mov dword ptr [rip+group_carrier_factor],1
.fdfg_store_done:
    xor eax,eax
    pop r12
    pop rbx
    ret


# 1.3.77 mature packet-zero cache lookup.  Later packets no longer reserve one
# permanent SIMD carrier per immutable LoadFact: AddressFact is the sovereign
# identity until a true consumer needs it.  The consumer may take the AddressFact
# directly as an x86 memory operand, so a synthetic load carrier is not required.
# This removes cache-count pressure from Group width without a workload route.
# esi=cache slot -> eax=mature physical SIMD register / -1.
ff_group_packet0_cache_reg:
    cmp esi,dword ptr [rip+ff_cache_count]
    jae .fgp0cr_bad
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov eax,[rax+rsi*4]
    ret
.fgp0cr_bad:
    mov eax,-1
    ret

# edi=packet index, esi=logical vreg -> eax=physical SIMD register / -1.
# Packet zero retains the mature Vector mapping.  Every later packet consumes
# exactly one disjoint four-vreg bundle from the real free carrier bank.
ff_group_vreg_reg:
    cmp esi,FF_VREG_COUNT
    jae .fgvr_bad
    test edi,edi
    jnz .fgvr_later
.if FIELD_LANES == 16
    lea eax,[rsi+FF_VREG_BASE]
.else
    lea rax,[rip+ff_vreg_phys_table]
    movzx eax,byte ptr [rax+rsi]
.endif
    ret
.fgvr_later:
    dec edi
    imul edi,FF_VREG_COUNT
    add edi,esi
    cmp edi,dword ptr [rip+ff_group_free_count]
    jae .fgvr_bad
    lea rax,[rip+ff_group_free_regs]
    movzx eax,byte ptr [rax+rdi]
    ret
.fgvr_bad:
    mov eax,-1
    ret

# Compiler-only packet-local aliases.  Storage capacity follows the architectural
# SIMD identity namespace (32), not a Group width.  group_body_factor remains the
# sole live width authority and normally consumes only a small prefix.
ff_group_alias_reset_all:
    lea rdi,[rip+ff_group_vreg_alias]
    mov eax,-1
    mov ecx,32*FF_VREG_COUNT
    rep stosd
    lea rdi,[rip+ff_group_reduce_square_skip_pos]
    mov eax,-1
    mov ecx,32
    rep stosd
    ret
ff_group_alias_set:
    cmp edi,FF_VREG_COUNT
    jae .fgas_ret
    mov eax,dword ptr [rip+ff_group_emit_packet]
    cmp eax,32
    jae .fgas_ret
    imul eax,eax,FF_VREG_COUNT
    add eax,edi
    lea rdx,[rip+ff_group_vreg_alias]
    mov [rdx+rax*4],esi
.fgas_ret:
    ret
ff_group_alias_kill:
    cmp edi,FF_VREG_COUNT
    jae .fgak_ret
    mov eax,dword ptr [rip+ff_group_emit_packet]
    cmp eax,32
    jae .fgak_ret
    imul eax,eax,FF_VREG_COUNT
    add eax,edi
    lea rdx,[rip+ff_group_vreg_alias]
    mov dword ptr [rdx+rax*4],-1
.fgak_ret:
    ret
# edi=logical vreg -> eax=raw packet-local alias.  >=0 is a physical carrier,
# -1 means the logical carrier itself, <=-2 is deferred immutable cache identity.
ff_group_alias_raw:
    cmp edi,FF_VREG_COUNT
    jae .fgar_bad
    mov ecx,dword ptr [rip+ff_group_emit_packet]
    cmp ecx,32
    jae .fgar_bad
    imul eax,ecx,FF_VREG_COUNT
    add eax,edi
    lea rdx,[rip+ff_group_vreg_alias]
    mov eax,[rdx+rax*4]
    ret
.fgar_bad:
    mov eax,-1
    ret
# edi=logical vreg -> eax=packet-local physical source carrier.
# Alias values <= -2 encode an immutable cache slot as -(slot+2).  Such a fact
# has not been turned into a synthetic carrier yet.  Materialize it exactly at
# its first real consumer into this packet's own logical carrier, then replace
# the tag with that carrier for the remaining lifetime of this version.
ff_group_source_reg:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov dword ptr [rip+ff_group_source_logical_tmp],ebx
    cmp ebx,FF_VREG_COUNT
    jae .fgsr_bad
    mov r13d,dword ptr [rip+ff_group_emit_packet]
    cmp r13d,32
    jae .fgsr_bad
    imul eax,r13d,FF_VREG_COUNT
    add eax,ebx
    lea rdx,[rip+ff_group_vreg_alias]
    mov r12d,[rdx+rax*4]
    cmp r12d,-1
    je .fgsr_logical
    cmp r12d,-1
    jl .fgsr_materialize
    mov eax,r12d
    jmp .fgsr_ret
.fgsr_logical:
    mov esi,ebx
    mov edi,r13d
    call ff_group_vreg_reg
    jmp .fgsr_ret
.fgsr_materialize:
    # cache_slot = -alias - 2
    mov ecx,r12d
    neg ecx
    sub ecx,2
    cmp ecx,dword ptr [rip+ff_cache_count]
    jae .fgsr_bad
    mov rax,[rip+ff_cache_owner_ptr]
    mov r12d,[rax+rcx*4]               # representative access
    mov esi,ebx
    mov edi,r13d
    call ff_group_vreg_reg
    test eax,eax; js .fgsr_bad
    mov ebx,eax                         # destination carrier
    mov edi,r12d
    mov esi,ebx
    mov edx,r13d
    imul edx,FIELD_LANES*4
    call ff_emit_group_direct_load
    test eax,eax; jnz .fgsr_bad
    # Publish materialized carrier into this packet-local alias cell.
    mov eax,r13d
    imul eax,eax,FF_VREG_COUNT
    add eax,dword ptr [rip+ff_group_source_logical_tmp]
    # ff_group_source_logical_tmp is set below before any helper call.
    lea rdx,[rip+ff_group_vreg_alias]
    mov [rdx+rax*4],ebx
    mov eax,ebx
    jmp .fgsr_ret
.fgsr_bad:
    mov eax,-1
.fgsr_ret:
    pop r13
    pop r12
    pop rbx
    ret

# Direct stable-Region load for a later Group packet. edi=access, esi=physical
# SIMD destination, edx=positive byte displacement from the current q packet.
# AddressFact GPRs are already live; no coordinate/topology fact is resurrected.
ff_emit_group_direct_load:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d,edi
    mov r13d,esi
    mov r15d,edx
    cmp r12d,dword ptr [rip+ff_access_count]
    jae .fegdl_bad
    mov edi,r12d
    call ff_address_gpr_for_access
    mov r14d,eax
    cmp r14d,-1
    je .fegdl_bad                    # Group requires burned AddressFact carrier.
.if FIELD_LANES == 16
    cmp r13d,31; ja .fegdl_bad
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF1
    test r13d,8; jz 321f; xor eax,0x80
321: test r13d,16; jz 322f; xor eax,0x10
322: xor eax,0x40
    test r14d,8; jz 323f; xor eax,0x20
323: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x48; call ff_emit_u8
    mov dil,0x10; call ff_emit_u8
    mov eax,r13d; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov eax,r14d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
.else
    cmp r13d,15; ja .fegdl_bad
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test r13d,8; jz 324f; xor eax,0x80
324: xor eax,0x40
    test r14d,8; jz 325f; xor eax,0x20
325: mov edi,eax; call ff_emit_u8
    mov dil,0x7C; call ff_emit_u8
    mov dil,0x10; call ff_emit_u8
    mov eax,r13d; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov eax,r14d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
.endif
    mov edi,r15d
    call ff_emit_u32
    test eax,eax; jnz .fegdl_bad
    xor eax,eax
    jmp .fegdl_done
.fegdl_bad:
    mov eax,1
.fegdl_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


# Tolerant FMA_ACC with one deferred immutable LoadFact consumed directly as the
# x86 memory operand.  edi=dst accumulator, esi=other physical multiplicand,
# edx=access id, ecx=packet index.  Exact +1/-1/0 ConstantFacts collapse to
# ADD/SUB/no-op here, so no temporary LoadFact carrier is born at all.
ff_emit_group_fma_direct_mem:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi                         # dst
    mov r12d,esi                       # register multiplicand / coefficient
    mov r13d,edx                       # access
    mov r14d,ecx                       # packet
    mov edi,r13d
    call ff_address_gpr_for_access
    mov r15d,eax                       # base GPR
    cmp r15d,-1; je .fegfdm_bad
    # Only tolerant FMA_ACC reaches this fold.  Consume exact coefficient identity
    # before choosing the final opcode.
    mov edi,r12d
    call ff_const_bits_for_phys_reg
    test edx,edx
    jz .fegfdm_fma
    cmp eax,0x3f800000; je .fegfdm_add
    cmp eax,0xbf800000; je .fegfdm_sub
    test eax,eax; je .fegfdm_zero
.fegfdm_fma:
.if FIELD_LANES == 16
    cmp ebx,31; ja .fegfdm_bad
    cmp r12d,31; ja .fegfdm_bad
    mov dil,0x62; call ff_emit_u8
    mov eax,0xF2
    test ebx,8; jz 351f; xor eax,0x80
351: xor eax,0x40                    # index is R12 (bit3=1 -> ~X=0)
    test r15d,8; jz 352f; xor eax,0x20
352: test ebx,16; jz 353f; xor eax,0x10
353: mov edi,eax; call ff_emit_u8
    mov eax,r12d; and eax,15; xor eax,15; shl eax,3; or eax,5; mov edi,eax; call ff_emit_u8
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40; mov edi,eax; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov eax,r15d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
.else
    cmp ebx,15; ja .fegfdm_bad
    cmp r12d,15; ja .fegfdm_bad
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE2
    test ebx,8; jz 354f; xor eax,0x80
354: xor eax,0x40
    test r15d,8; jz 355f; xor eax,0x20
355: mov edi,eax; call ff_emit_u8
    mov eax,r12d; and eax,15; shl eax,3; mov edi,0x7D; sub edi,eax; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov eax,r15d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
.endif
    jmp .fegfdm_disp
.fegfdm_add:
    mov r13d,0x58
    jmp .fegfdm_vbin
.fegfdm_sub:
    mov r13d,0x5C
.fegfdm_vbin:
.if FIELD_LANES == 16
    cmp ebx,31; ja .fegfdm_bad
    mov dil,0x62; call ff_emit_u8
    mov eax,1
    test ebx,8; jz 356f; or eax,0x80
356: xor eax,0x80                    # normalize ~R from actual dst bit below
    # Rebuild inverted R explicitly; start map-only for clarity.
    mov eax,1
    mov edx,ebx; shr edx,3; and edx,1; xor edx,1; shl edx,7; or eax,edx
    # ~X=0 for R12 index.
    mov edx,r15d; shr edx,3; and edx,1; xor edx,1; shl edx,5; or eax,edx
    mov edx,ebx; shr edx,4; and edx,1; xor edx,1; shl edx,4; or eax,edx
    mov edi,eax; call ff_emit_u8
    mov eax,ebx; and eax,15; xor eax,15; shl eax,3; or eax,4; mov edi,eax; call ff_emit_u8
    mov eax,ebx; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x40; mov edi,eax; call ff_emit_u8
    mov edi,r13d; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov eax,r15d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
.else
    cmp ebx,15; ja .fegfdm_bad
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE1
    test ebx,8; jz 357f; xor eax,0x80
357: xor eax,0x40
    test r15d,8; jz 358f; xor eax,0x20
358: mov edi,eax; call ff_emit_u8
    mov eax,ebx; and eax,15; shl eax,3; mov edi,0x7C; sub edi,eax; call ff_emit_u8
    mov edi,r13d; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x84; mov edi,eax; call ff_emit_u8
    mov eax,r15d; and eax,7; or eax,0xA0; mov edi,eax; call ff_emit_u8
.endif
.fegfdm_disp:
    mov eax,r14d
    imul eax,FIELD_LANES*4
    mov edi,eax; call ff_emit_u32
    test eax,eax; jnz .fegfdm_bad
.fegfdm_zero:
    xor eax,eax
    jmp .fegfdm_ret
.fegfdm_bad:
    mov eax,1
.fegfdm_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Emit one operation of one already-proven Group packet.  EDI is packet index and
# ESI is the position in the sole depth-sorted Physical order.  Alias/lifetime
# state persists across calls, so the caller can walk Physical depth first and
# packets second without constructing a second scheduler IR.
ff_emit_group_packet_op:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword ptr [rip+ff_group_emit_packet],edi
    mov ebx,esi
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fegpb_bad
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov r15,[rip+ff_ops_ptr]
    add r15,rax
    mov eax,[r15]
    cmp eax,OP_NOP; je .fegpb_next
    cmp eax,OP_LOAD; je .fegpb_load
    cmp eax,OP_CONST; je .fegpb_const
    cmp eax,OP_ADD; je .fegpb_add
    cmp eax,OP_SUB; je .fegpb_sub
    cmp eax,OP_MUL; je .fegpb_mul
    cmp eax,OP_DIV; je .fegpb_div
    cmp eax,OP_SQRT; je .fegpb_sqrt
    cmp eax,OP_TRUNC; je .fegpb_trunc
    cmp eax,OP_MOV; je .fegpb_mov
    cmp eax,OP_FMA_ACC; je .fegpb_fma
    cmp eax,OP_REDUCE; je .fegpb_reduce
    jmp .fegpb_bad
.fegpb_load:
    mov eax,[r15+16]
    cmp eax,dword ptr [rip+ff_access_count]; jae .fegpb_bad
    mov rdx,[rip+ff_access_cache_slot_ptr]
    mov esi,[rdx+rax*4]
    cmp esi,FF_CACHE_NONE; je .fegpb_bad
    mov eax,dword ptr [rip+ff_group_emit_packet]
    test eax,eax
    jnz .fegpb_load_deferred
    call ff_group_packet0_cache_reg
    test eax,eax; js .fegpb_bad
    mov esi,eax
    jmp .fegpb_load_publish
.fegpb_load_deferred:
    # Preserve the immutable LoadFact as a direct-memory identity until its
    # actual consumer.  Tag = -(cache_slot+2); -1 remains the no-alias value.
    mov eax,esi
    add eax,2
    neg eax
    mov esi,eax
.fegpb_load_publish:
    mov edi,[r15+4]
    call ff_group_alias_set
    jmp .fegpb_next
.fegpb_const:
    mov rax,r15
    sub rax,[rip+ff_ops_ptr]
    shr rax,5
    mov rdx,[rip+ff_op_const_slot_ptr]
    mov eax,[rdx+rax*4]
    cmp eax,-1; je .fegpb_bad
    mov rdx,[rip+ff_const_pool_resident_reg_ptr]
    mov esi,[rdx+rax*4]
    cmp esi,-1; je .fegpb_bad
    mov edi,[r15+4]
    call ff_group_alias_set
    jmp .fegpb_next
.fegpb_add: mov r14d,0x58; jmp .fegpb_bin
.fegpb_sub: mov r14d,0x5C; jmp .fegpb_bin
.fegpb_mul: mov r14d,0x59; jmp .fegpb_bin
.fegpb_div: mov r14d,0x5E
.fegpb_bin:
    cmp r14d,0x59
    jne .fegpb_bin_normal
    mov esi,ebx
    call ff_reduce_square_foldable
    test eax,eax
    jz .fegpb_bin_normal
    mov edi,[r15+8]
    call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov edi,eax
    call ff_emit_reduce_square_fma
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
    lea edx,[rbx+1]
    mov eax,dword ptr [rip+ff_group_emit_packet]
    cmp eax,32; jae .fegpb_bad
    lea rcx,[rip+ff_group_reduce_square_skip_pos]
    mov [rcx+rax*4],edx
    jmp .fegpb_next
.fegpb_bin_normal:
    mov edi,[r15+8]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r12d,eax
    mov edi,[r15+12]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r13d,eax
    mov edi,[r15+4]; call ff_group_alias_kill
    mov esi,[r15+4]
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    test eax,eax; js .fegpb_bad
    mov esi,eax
    mov edi,r14d
    mov edx,r12d
    mov ecx,r13d
    call ff_emit_vbin
    test eax,eax; jnz .fegpb_bad
    jmp .fegpb_next
.fegpb_sqrt:
    mov edi,[r15+8]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r12d,eax
    mov esi,[r15+4]
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    test eax,eax; js .fegpb_bad
    mov edi,eax; mov esi,r12d
    call ff_emit_vsqrt
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
    jmp .fegpb_next
.fegpb_trunc:
    mov edi,[r15+8]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r12d,eax
    mov esi,[r15+4]
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    test eax,eax; js .fegpb_bad
    mov edi,eax; mov esi,r12d
    call ff_emit_vtrunc
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
    jmp .fegpb_next
.fegpb_mov:
    mov edi,[r15+8]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r12d,eax
    mov esi,[r15+4]
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    test eax,eax; js .fegpb_bad
    mov edi,eax; mov esi,r12d
    call ff_emit_vmov
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
    jmp .fegpb_next
.fegpb_fma:
    # Materialize an immutable accumulator alias into its packet-local writable
    # carrier once, then consume the same MachineFact operator-form burn as the
    # mature Vector body.
    mov edi,[r15+4]
    mov eax,dword ptr [rip+ff_group_emit_packet]
    cmp eax,32; jae .fegpb_bad
    imul eax,eax,FF_VREG_COUNT
    add eax,edi
    lea rdx,[rip+ff_group_vreg_alias]
    mov esi,[rdx+rax*4]
    cmp esi,-1
    je 331f
    push rsi
    mov esi,edi
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    mov edi,eax
    pop rsi
    test edi,edi; js .fegpb_bad
    call ff_emit_vmov
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
331:
    # Final operand-form burn: if exactly one multiplicand is still a deferred
    # immutable LoadFact and the other already has a physical carrier, consume
    # the LoadFact directly as the x86 memory operand.  FMA_ACC is tolerant-only,
    # so product operand exchange is contract-legal here.
    mov edi,[r15+8]; call ff_group_alias_raw
    mov r12d,eax
    mov edi,[r15+12]; call ff_group_alias_raw
    mov r13d,eax
    cmp r12d,-1
    jge .fegpb_fma_try_b_mem
    cmp r13d,-1
    jl .fegpb_fma_normal              # both memory: keep canonical materialize path
    # A is deferred memory; B becomes register.
    mov edi,[r15+12]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r13d,eax                      # register multiplicand
    mov eax,r12d; neg eax; sub eax,2 # cache slot
    cmp eax,dword ptr [rip+ff_cache_count]; jae .fegpb_bad
    mov rdx,[rip+ff_cache_owner_ptr]
    mov edx,[rdx+rax*4]
    mov esi,[r15+4]
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    test eax,eax; js .fegpb_bad
    mov edi,eax; mov esi,r13d; mov ecx,dword ptr [rip+ff_group_emit_packet]
    call ff_emit_group_fma_direct_mem
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
    jmp .fegpb_next
.fegpb_fma_try_b_mem:
    cmp r13d,-1
    jge .fegpb_fma_normal
    # B is deferred memory; A becomes register.
    mov edi,[r15+8]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r12d,eax
    mov eax,r13d; neg eax; sub eax,2
    cmp eax,dword ptr [rip+ff_cache_count]; jae .fegpb_bad
    mov rdx,[rip+ff_cache_owner_ptr]
    mov edx,[rdx+rax*4]
    mov esi,[r15+4]
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    test eax,eax; js .fegpb_bad
    mov edi,eax; mov esi,r12d; mov ecx,dword ptr [rip+ff_group_emit_packet]
    call ff_emit_group_fma_direct_mem
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
    jmp .fegpb_next
.fegpb_fma_normal:
    mov edi,[r15+8]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r12d,eax
    mov edi,[r15+12]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
    mov r13d,eax
    mov esi,[r15+4]
    mov edi,dword ptr [rip+ff_group_emit_packet]
    call ff_group_vreg_reg
    test eax,eax; js .fegpb_bad
    mov edi,eax; mov esi,r12d; mov edx,r13d
    call ff_emit_vfma_acc
    test eax,eax; jnz .fegpb_bad
    mov edi,[r15+4]; call ff_group_alias_kill
    jmp .fegpb_next
.fegpb_reduce:
    mov eax,dword ptr [rip+ff_group_emit_packet]
    cmp eax,32; jae .fegpb_bad
    lea rcx,[rip+ff_group_reduce_square_skip_pos]
    cmp dword ptr [rcx+rax*4],ebx
    jne 332f
    mov dword ptr [rcx+rax*4],-1
    jmp .fegpb_next
332:
    mov edi,[r15+8]; call ff_group_source_reg
    test eax,eax; js .fegpb_bad
.if FIELD_LANES == 16
    # Direct Group packets are full-lane by construction, so the masked generic
    # reduce degenerates exactly to an ordinary vector add into hidden carrier 5.
    mov ecx,eax
    mov edi,0x58; mov esi,5; mov edx,5
    call ff_emit_vbin
.else
    mov edi,eax
    call ff_emit_reduce
.endif
    test eax,eax; jnz .fegpb_bad
    jmp .fegpb_next
.fegpb_next:
    xor eax,eax
    jmp .fegpb_ret
.fegpb_bad:
    mov eax,1
.fegpb_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# 1.3.77 final schedule burn.  The existing Physical order is already stable-
# sorted by true dependency depth.  Emit that same order as the ISA time axis:
# for each Physical operation position, issue the corresponding operation for
# every independent packet before advancing to the next position.  Packet zero
# participates through its mature carriers instead of being byte-copied first.
# No late graph, candidate width table, or runtime issue policy exists.
ff_emit_group_depth_schedule:
    push rbx
    push r12
    call ff_group_alias_reset_all
    xor ebx,ebx                         # physical-order position
.fegds_pos:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fegds_done
    xor r12d,r12d                       # packet
.fegds_packet:
    cmp r12d,dword ptr [rip+group_body_factor]
    jae .fegds_next_pos
    mov edi,r12d
    mov esi,ebx
    call ff_emit_group_packet_op
    test eax,eax; jnz .fegds_bad
    inc r12d
    jmp .fegds_packet
.fegds_next_pos:
    inc ebx
    jmp .fegds_pos
.fegds_done:
    xor eax,eax
    pop r12
    pop rbx
    ret
.fegds_bad:
    mov eax,1
    pop r12
    pop rbx
    ret

# 1.3.91 Field fabric datapath projection. Descriptor layout is a direct
# serialization of already-authoritative facts:
#   header[64], op_record[N:32], physical_depth[N:u32], physical_order[N:u32].
# An unproved target emits zero bytes.
ff_close_fabric_datapath_descriptor:
    mov qword ptr [rip+ff_fabric_datapath_bytes],0
    mov dword ptr [rip+ff_fabric_datapath_enabled],0
    call fabric_target_facts_proved
    test eax,eax
    jz .fffd_done
    mov eax,dword ptr [rip+ff_op_count]
    test eax,eax
    jz .fffd_fail
    mov rdx,rax
    imul rdx,rdx,40
    jo .fffd_fail
    add rdx,64
    jc .fffd_fail
    mov qword ptr [rip+ff_fabric_datapath_bytes],rdx
    mov dword ptr [rip+ff_fabric_datapath_enabled],1
    mov qword ptr [rip+ff_fabric_datapath_header+0],1
    mov qword ptr [rip+ff_fabric_datapath_header+8],rax
    mov eax,dword ptr [rip+ff_physical_edge_count]
    mov qword ptr [rip+ff_fabric_datapath_header+16],rax
    mov eax,dword ptr [rip+ff_physical_max_depth]
    mov qword ptr [rip+ff_fabric_datapath_header+24],rax
    mov eax,dword ptr [rip+ff_physical_memory_barriers]
    mov qword ptr [rip+ff_fabric_datapath_header+32],rax
    mov qword ptr [rip+ff_fabric_datapath_header+40],0
    mov qword ptr [rip+ff_fabric_datapath_header+48],0
    mov qword ptr [rip+ff_fabric_datapath_header+56],rdx
.fffd_done:
    xor eax,eax
    ret
.fffd_fail:
    mov eax,1
    ret

# codegen
ff_codegen:
    call ff_build_access_cache
    test eax,eax; jnz .fcg_bad
    call ff_build_coord_cache
    test eax,eax; jnz .fcg_bad
    call ff_assign_resident_loads
    test eax,eax; jnz .fcg_bad
    call ff_assign_address_gprs
    test eax,eax; jnz .fcg_bad
    # 1.3.76 causal-depth burn.  Field consumes the same canonical GroupFact
    # body authority as Tensor.  The factor is derived only from the already-
    # proved Physical-DAG depth and the target architectural SIMD carrier bank.
    call ff_derive_field_groupfact
    test eax,eax; jnz .fcg_bad
    mov rax,[rip+ff_code_ptr]; mov [rip+ff_emit_ptr],rax
    add rax,[rip+ff_code_capacity]; jc .fcg_bad
    mov [rip+ff_emit_end],rax
    # push r12,r13; q=start,end; zero hidden accumulator vector5
    lea rdi,[rip+cg_prologue]; mov esi,cg_prologue_end-cg_prologue; call ff_emit_bytes; test eax,eax; jnz .fcg_bad
    # 1.3.6 Global AddressFact authority. Every admitted access receives one
    # invocation-stable field_base+delta identity. Regular AVX2 and AVX-512
    # paths consume it; irregular fallback remains independent and truthful.
    mov eax,dword ptr [rip+ff_address_fact_count]
    mov [rip+ff_addr_pool_count],eax
    mov edi,dword ptr [rip+ff_cache_count]
    add edi,dword ptr [rip+ff_const_pool_count]
    imul edi,edi,FIELD_LANES*4
    mov eax,dword ptr [rip+ff_addr_pool_count]
    lea edi,[rdi+rax*8]
    mov [rip+ff_region_delta_stack_off],edi
    mov eax,dword ptr [rip+ff_access_count]
    lea edi,[rdi+rax*8]                  # execution-local piecewise-affine deltas
    mov [rip+ff_region_class_stack_off],edi
    add edi,8                            # exact local class authority + padding
.if FIELD_LANES == 8
    # Native256 has no spare Rank-N SIMD bank.  Give the one canonical packet
    # CoordinateFact a compact execution-local stack carrier instead of
    # rediscovering q->axis coordinates independently for every AddressFact.
    add edi,31; jc .fcg_bad
    and edi,-32
    mov [rip+ff_packet_coord_stack_off],edi
    mov rax,[rip+ff_common_rank]
    shl rax,5                            # one YMM (8 x u32) per logical axis
    jc .fcg_bad
    add rax,8                            # cached packet-q authority
    jc .fcg_bad
    cmp rax,0x7fffffff
    ja .fcg_bad
    add edi,eax
    jc .fcg_bad
.else
    mov dword ptr [rip+ff_packet_coord_stack_off],-1
.endif
    add edi,31; jc .fcg_bad
    and edi,-32                           # preserve vector/ABI-friendly alignment
    mov [rip+ff_cache_bytes],edi
    test edi,edi; jz .fcg_no_cache_frame
    call ff_emit_stack_sub; test eax,eax; jnz .fcg_bad
    # mov dword ptr [rsp+class_off],-1 : no RegionFact has physical authority yet.
    mov dil,0xC7; call ff_emit_u8
    mov dil,0x84; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_region_class_stack_off]; call ff_emit_u32
    mov edi,-1; call ff_emit_u32
.if FIELD_LANES == 8
    # mov qword ptr [rsp+packet_coord_off],-1 : no packet CoordinateFact yet.
    mov dil,0x48; call ff_emit_u8
    mov dil,0xC7; call ff_emit_u8
    mov dil,0x84; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_packet_coord_stack_off]; call ff_emit_u32
    mov edi,-1; call ff_emit_u32
.endif
.fcg_no_cache_frame:
    # AddressFacts are RegionFacts in 1.3.81.  Their physical deltas may change
    # when a periodic piecewise-affine region changes wrap class, so the address
    # pool is refreshed only after the cold region proof below.  Constants remain
    # invocation facts and are still initialized once here.
    call ff_emit_const_pool_init; test eax,eax; jnz .fcg_bad
.if FIELD_LANES == 16
    lea rdi,[rip+cg_zero512]; mov esi,cg_zero512_end-cg_zero512; call ff_emit_bytes
.else
    lea rdi,[rip+cg_zero256]; mov esi,cg_zero256_end-cg_zero256; call ff_emit_bytes
.endif
    # 1.3.73 launch-static physical realization. EDX entered the generated
    # function as one cold-proved direct-layout mode bit and cg_prologue captured
    # it in R15D. The hot packet loop never reloads a global layout flag.
    lea rdi,[rip+cg_test_r15_direct]; mov esi,cg_test_r15_direct_end-cg_test_r15_direct; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x84; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_launch_generic_disp_ptr],rax
    xor edi,edi; call ff_emit_u32

    # Direct-layout Region transition.  The packet backedge never returns here
    # while q remains inside the proven run, so re-checking q<r14 at the cold
    # transition point was dead globality.  A real Region boundary alone asks
    # field_regular_run_end for the next physical interval.
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_regular_loop_ptr],rax
    lea rdi,[rip+cg_cmp]; mov esi,cg_cmp_end-cg_cmp; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x83; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_done_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
    # RDI = execution-local RegionFact delta arena in this generated frame.
    mov dil,0x48; call ff_emit_u8
    mov dil,0x8D; call ff_emit_u8
    mov dil,0xBC; call ff_emit_u8
    mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_region_delta_stack_off]; call ff_emit_u32
    test eax,eax; jnz .fcg_bad
    mov rax,FIELD_RUNTIME_REGULAR_RUN_END_VA
    call ff_emit_call; test eax,eax; jnz .fcg_bad
    lea rdi,[rip+cg_mov_r14_rax]; mov esi,cg_mov_r14_rax_end-cg_mov_r14_rax; call ff_emit_bytes
    lea rdi,[rip+cg_test_rax]; mov esi,cg_test_rax_end-cg_test_rax; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x84; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_regular_episode_fallback_disp_ptr],rax
    xor edi,edi; call ff_emit_u32

    # EDX=0 is the canonical interior RegionFact. EDX=1 is a piecewise wrap
    # RegionFact. Repeated interior rows retain the same AddressFact authority;
    # no re-materialization is allowed merely because a row boundary occurred.
    mov dil,0x85; call ff_emit_u8; mov dil,0xD2; call ff_emit_u8       # test edx,edx
    mov dil,0x0F; call ff_emit_u8; mov dil,0x85; call ff_emit_u8       # jne piecewise
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_region_piecewise_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    # cmp dword ptr [rsp+class_off],0
    mov dil,0x83; call ff_emit_u8; mov dil,0xBC; call ff_emit_u8; mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_region_class_stack_off]; call ff_emit_u32
    xor edi,edi; call ff_emit_u8
    mov dil,0x0F; call ff_emit_u8; mov dil,0x84; call ff_emit_u8       # je refresh_done
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_region_same_interior_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    xor edi,edi; call ff_emit_addr_pool_init; test eax,eax; jnz .fcg_bad
    # class = interior(0)
    mov dil,0xC7; call ff_emit_u8; mov dil,0x84; call ff_emit_u8; mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_region_class_stack_off]; call ff_emit_u32
    xor edi,edi; call ff_emit_u32
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_region_refresh_done_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    # Patch JNE to piecewise refresh.
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_region_piecewise_disp_ptr]; lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax
    mov edi,1; call ff_emit_addr_pool_init; test eax,eax; jnz .fcg_bad
    # class = piecewise(1); every piecewise region refreshes because its exact
    # affine deltas are the fact, not the coarse class bit.
    mov dil,0xC7; call ff_emit_u8; mov dil,0x84; call ff_emit_u8; mov dil,0x24; call ff_emit_u8
    mov edi,dword ptr [rip+ff_region_class_stack_off]; call ff_emit_u32
    mov edi,1; call ff_emit_u32
    # Patch repeated-interior JE and interior-refresh JMP to this shared point.
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_region_same_interior_disp_ptr]; lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_region_refresh_done_disp_ptr]; lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax

    # Burn immutable MachineFacts exactly once for this Region. AddressFacts
    # become GPR lifetimes; ConstantFacts become SIMD lifetimes. The packet loop
    # starts only after both carrier families are live.
    call ff_emit_address_gpr_residents; test eax,eax; jnz .fcg_bad
    call ff_emit_const_residents; test eax,eax; jnz .fcg_bad
.if FIELD_LANES == 16
    lea rdi,[rip+cg_fullmask512]; mov esi,cg_fullmask512_end-cg_fullmask512; call ff_emit_bytes
.else
    lea rdi,[rip+cg_fullmask256]; mov esi,cg_fullmask256_end-cg_fullmask256; call ff_emit_bytes
.endif
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_direct_loop_ptr],rax
    xor r14d,r14d
.fcg_regular_value_loop:
    cmp r14d,dword ptr [rip+ff_cache_count]
    jae .fcg_regular_done
    mov rax,[rip+ff_cache_owner_ptr]
    mov r13d,[rax+r14*4]
    mov rdx,[rip+ff_access_field_ptr]
    movzx ebx,byte ptr [rdx+r13]
    # A resident LoadFact is materialized directly into its final sovereign
    # carrier.  The old regular path first loaded to SIMD0, wrote a stack cache,
    # then copied into the resident carrier even when the stack copy had no
    # consumer in the regular episode.  That transport added no information.
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov edx,[rax+r14*4]
    cmp edx,FF_CACHE_NONE
    je .fcg_regular_stack_authority
    # Load directly into final resident authority. If a future consumer-copy
    # crosses the first arithmetic helper, preserve a stack reload authority
    # from that resident carrier itself. No SIMD0 transport alias exists.
    mov edi,ebx
    mov esi,r13d
    call ff_emit_direct_regular_load_to; test eax,eax; jnz .fcg_bad
    mov rax,[rip+ff_cache_last_load_pos_ptr]
    mov eax,[rax+r14*4]
    cmp eax,dword ptr [rip+ff_first_resident_clobber_pos]
    jle .fcg_regular_next
    mov edi,r14d
    mov rax,[rip+ff_cache_resident_reg_ptr]
    mov esi,[rax+r14*4]
    call ff_emit_cache_store_from; test eax,eax; jnz .fcg_bad
    jmp .fcg_regular_next
.fcg_regular_stack_authority:
    # During preload, logical v0 has not acquired arithmetic authority yet, so
    # borrow the profile's v0 carrier as phase-local transport. This cannot alias an
    # immutable resident and is released before the first logical op executes.
    mov edi,ebx
    mov esi,r13d
    mov edx,FF_PRELOAD_SCRATCH
    call ff_emit_direct_regular_load_to; test eax,eax; jnz .fcg_bad
    mov edi,r14d
    mov esi,FF_PRELOAD_SCRATCH
    call ff_emit_cache_store_from; test eax,eax; jnz .fcg_bad
.fcg_regular_next:
    inc r14d
    jmp .fcg_regular_value_loop
.fcg_regular_done:
    # Packet-zero preload is the mature Vector carrier realization.  GroupFact
    # now allocates disjoint carriers for later packets directly from the same
    # Physical DAG; no cloned preload byte frontier survives.
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_regular_done_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
.fcg_regular_emission_done:

    # Launch-generic invocations enter this loop once and remain generic. A
    # direct-layout invocation reaches the boundary body only when Region proof
    # truthfully fails. No old regular-layout compatibility branch survives.
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_generic_loop_ptr],rax
    mov rdx,[rip+ff_launch_generic_disp_ptr]
    lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax
    lea rdi,[rip+cg_cmp]; mov esi,cg_cmp_end-cg_cmp; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x83; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_generic_done_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_regular_episode_fallback_disp_ptr]
    lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax

    # Boundary/irregular episodes rematerialize lane validity once. Native512
    # also materializes the packet's canonical Rank-N CoordinateFact once into
    # ZMM24..31. Every neighborhood access below consumes that parent fact rather
    # than rediscovering q+[lane] and decomposing all axes independently.
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
.if FIELD_LANES == 16
    xor edi,edi                         # common WHFLD logical rank from field 0
    call ff_runtime_prepare_coords_va_for_field
    test rax,rax; jz .fcg_bad
    call ff_emit_call; test eax,eax; jnz .fcg_bad
.else
    mov rax,FIELD_RUNTIME_MASK_VA; call ff_emit_call; test eax,eax; jnz .fcg_bad
.endif
    # A launch-generic execution initializes CoordinateFact once above, then
    # returns here after exact Rank-N induction on each packet backedge. A
    # direct-layout boundary re-enters the full generic head and rebuilds from q.
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_generic_ready_ptr],rax

    # Runtime layout proof chooses between coordinate-CSE and the fully general
    # per-field path once per vector episode. Both paths are direct native SIMD.
    lea rdi,[rip+cg_test_r15_uniform]; mov esi,cg_test_r15_uniform_end-cg_test_r15_uniform; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x84; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_uniform_fallback_disp_ptr],rax
    xor edi,edi; call ff_emit_u32

    # Layout-equivalent immutable inputs share one offset identity per delta.
    # Both physical profiles now consume one canonical CoordinateFact per packet.
    # Native512 keeps its register realization; native256 uses the execution-local
    # packet carrier and never re-derives Rank-N coordinates per AddressFact.
    xor r14d,r14d                       # coordinate slot
.fcg_coord_prefetch:
    cmp r14d,dword ptr [rip+ff_coord_count]
    jae .fcg_fast_done
    mov rax,[rip+ff_coord_owner_ptr]
    mov r13d,[rax+r14*4]                # representative access
    mov rdx,[rip+ff_access_field_ptr]
    movzx edi,byte ptr [rdx+r13]
    call ff_emit_mov_edi_imm
    mov edi,r13d; call ff_emit_mov_esi_imm
.if FIELD_LANES == 8
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
    call ff_emit_packet_coord_arena_r8; test eax,eax; jnz .fcg_bad
.endif
    mov edi,r13d
    call ff_runtime_offsets_from_coords_va_for_access
    test rax,rax; jz .fcg_bad
    call ff_emit_call; test eax,eax; jnz .fcg_bad
    xor r12d,r12d                       # canonical cache slot
.fcg_coord_users:
    cmp r12d,dword ptr [rip+ff_cache_count]
    jae .fcg_coord_next
    mov rax,[rip+ff_cache_owner_ptr]
    mov r13d,[rax+r12*4]
    mov rax,[rip+ff_access_coord_slot_ptr]
    cmp dword ptr [rax+r13*4],r14d
    jne .fcg_coord_user_next
    mov rdx,[rip+ff_access_field_ptr]
    movzx edi,byte ptr [rdx+r13]
    call ff_emit_direct_gather; test eax,eax; jnz .fcg_bad
    mov edi,r12d; call ff_emit_accept_helper_result; test eax,eax; jnz .fcg_bad
.fcg_coord_user_next:
    inc r12d
    jmp .fcg_coord_users
.fcg_coord_next:
    inc r14d
    jmp .fcg_coord_prefetch
.fcg_fast_done:
    call ff_emit_materialize_helper_clobbered_residents; test eax,eax; jnz .fcg_bad
    call ff_emit_const_residents; test eax,eax; jnz .fcg_bad
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_uniform_done_disp_ptr],rax
    xor edi,edi; call ff_emit_u32

    # Patch JE target to the proven-general fallback below.
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_uniform_fallback_disp_ptr]
    lea rcx,[rdx+4]
    sub rax,rcx
    mov [rdx],eax

    # General-layout immutable inputs still share the same canonical logical
    # CoordinateFact. Native512 therefore changes only field stride/base while
    # retaining the packet coordinates; different layouts no longer force a
    # complete Rank-N rediscovery for every load.
    xor r14d,r14d
.fcg_prefetch:
    cmp r14d,dword ptr [rip+ff_cache_count]
    jae .fcg_prefetch_done
    mov rax,[rip+ff_cache_owner_ptr]
    mov r13d,[rax+r14*4]
    mov rdx,[rip+ff_access_field_ptr]
    movzx edi,byte ptr [rdx+r13]
    call ff_emit_mov_edi_imm
    mov edi,r13d; call ff_emit_mov_esi_imm
.if FIELD_LANES == 8
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
    call ff_emit_packet_coord_arena_r8; test eax,eax; jnz .fcg_bad
.endif
    mov edi,r13d
    call ff_runtime_offsets_from_coords_va_for_access
    test rax,rax; jz .fcg_bad
    call ff_emit_call; test eax,eax; jnz .fcg_bad
    mov rdx,[rip+ff_access_field_ptr]
    movzx edi,byte ptr [rdx+r13]
    call ff_emit_direct_gather; test eax,eax; jnz .fcg_bad
    mov edi,r14d; call ff_emit_accept_helper_result; test eax,eax; jnz .fcg_bad
.fcg_prefetch_next:
    inc r14d
    jmp .fcg_prefetch
.fcg_prefetch_done:
    call ff_emit_materialize_helper_clobbered_residents; test eax,eax; jnz .fcg_bad
    call ff_emit_const_residents; test eax,eax; jnz .fcg_bad
    # Patch fast-path jump over the fallback.
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_uniform_done_disp_ptr]
    lea rcx,[rdx+4]
    sub rax,rcx
    mov [rdx],eax
    # Direct-layout preload is patched after the shared single-packet body is
    # known: GroupFact may route it to the causal-depth burned Group dispatcher.
    mov rax,[rip+ff_emit_ptr]
    mov [rip+ff_ops_body_ptr],rax
    mov dword ptr [rip+ff_fold_pending_consumer_pos],-1
    mov dword ptr [rip+ff_fold_pending_kind],0
    mov dword ptr [rip+ff_fold_pending_source],0
    mov dword ptr [rip+ff_consumer_local_fold_count],0
    call ff_codegen_alias_reset
    mov dword ptr [rip+ff_reduce_square_skip_pos],-1
    xor ebx,ebx
.fcg_ops:
    cmp ebx,dword ptr [rip+ff_op_count]; jae .fcg_ops_done
    mov rax,[rip+ff_physical_order_ptr]
    mov eax,[rax+rbx*4]
    imul rax,OP_SIZE
    mov r15,[rip+ff_ops_ptr]
    add r15,rax
    mov eax,[r15]
    cmp eax,OP_NOP; je .fcg_next
    cmp eax,OP_LOAD; je .fcg_load
    cmp eax,OP_CONST; je .fcg_const
    cmp eax,OP_ADD; je .fcg_add
    cmp eax,OP_SUB; je .fcg_sub
    cmp eax,OP_MUL; je .fcg_mul
    cmp eax,OP_DIV; je .fcg_div
    cmp eax,OP_SQRT; je .fcg_sqrt
    cmp eax,OP_TRUNC; je .fcg_trunc
    cmp eax,OP_STORE; je .fcg_store
    cmp eax,OP_REDUCE; je .fcg_reduce
    cmp eax,OP_MOV; je .fcg_mov
    cmp eax,OP_IINDEX; je .fcg_iindex
    cmp eax,OP_IADD_CONST; je .fcg_iadd
    cmp eax,OP_ISUB_CONST; je .fcg_isub
    cmp eax,OP_IMUL_CONST; je .fcg_imul
    cmp eax,OP_IDIV_CONST; je .fcg_idiv
    cmp eax,OP_IMOD_CONST; je .fcg_imod
    cmp eax,OP_ITOF32; je .fcg_itof
    cmp eax,OP_FMA_ACC; je .fcg_fma_acc
    jmp .fcg_bad
.fcg_load:
    mov eax,[r15+16]                 # access
    mov rdx,[rip+ff_access_cache_slot_ptr]
    mov esi,[rdx+rax*4]
    cmp esi,FF_CACHE_NONE
    je .fcg_load_mutable
    mov rdx,[rip+ff_cache_resident_reg_ptr]
    mov edx,[rdx+rsi*4]
    cmp edx,FF_CACHE_NONE
    je .fcg_load_stack
    # Immutable resident LoadFact becomes the logical value by identity.  No
    # register-to-register transport is emitted; every consumer resolves the
    # logical name directly to this sovereign carrier.
    mov edi,[r15+4]
    mov esi,edx
    call ff_codegen_alias_set
    jmp .fcg_next
.fcg_load_stack:
    push rsi
    mov edx,esi
    mov edi,[r15+4]
    mov esi,2
    mov ecx,ebx
    call ff_try_consumer_local_fold
    mov ecx,eax
    pop rsi
    test ecx,ecx
    jz 180f
    mov edi,[r15+4]; call ff_codegen_alias_kill
    jmp .fcg_next
180:
    mov edi,[r15+4]
    push rsi
    call ff_codegen_alias_kill
    pop rsi
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi
    # esi still holds the canonical cache slot.
    call ff_emit_cache_load; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_load_mutable:
    mov r13d,[r15+16]
    mov rdx,[rip+ff_access_field_ptr]; movzx edi,byte ptr [rdx+r13]
    call ff_emit_mov_edi_imm
    mov edi,r13d; call ff_emit_mov_esi_imm
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
.if FIELD_LANES == 8
    call ff_emit_packet_coord_arena_r8; test eax,eax; jnz .fcg_bad
.endif
    mov edi,r13d
    call ff_runtime_offsets_va_for_access
    test rax,rax; jz .fcg_bad
    call ff_emit_call; test eax,eax; jnz .fcg_bad
    mov rdx,[rip+ff_access_field_ptr]; movzx edi,byte ptr [rdx+r13]
    call ff_emit_direct_gather; test eax,eax; jnz .fcg_bad
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi; xor esi,esi; call ff_emit_vmov
    mov edi,ebx; call ff_emit_reload_residents; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_const:
    # 1.3.6 ConstantFact: consume the invocation-persistent exact-bit pool when
    # this op has a canonical slot. Pool overflow is not a semantic failure;
    # such constants retain the historical local reconstruction path.
    mov rax,r15
    mov rdx,[rip+ff_ops_ptr]
    sub rax,rdx
    shr rax,5                           # OP_SIZE == 32
    mov rdx,[rip+ff_op_const_slot_ptr]
    mov esi,[rdx+rax*4]
    cmp esi,-1
    je .fcg_const_local
    mov rdx,[rip+ff_const_pool_resident_reg_ptr]
    mov edx,[rdx+rsi*4]
    cmp edx,-1
    je .fcg_const_stack
    # ConstantFact already owns an immutable SIMD carrier for the Region.
    mov edi,[r15+4]
    mov esi,edx
    call ff_codegen_alias_set
    jmp .fcg_next
.fcg_const_stack:
    add esi,dword ptr [rip+ff_cache_count]
    push rsi
    mov edx,esi
    mov edi,[r15+4]
    mov esi,2
    mov ecx,ebx
    call ff_try_consumer_local_fold
    mov ecx,eax
    pop rsi
    test ecx,ecx
    jz 181f
    mov edi,[r15+4]; call ff_codegen_alias_kill
    jmp .fcg_next
181:
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi
    call ff_emit_cache_load; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_const_local:
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov edi,[r15+20]; mov esi,[r15+4]; FF_MAP_VREG esi,rsi; call ff_emit_const_real; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_add: mov edi,0x58; jmp .fcg_bin
.fcg_sub: mov edi,0x5C; jmp .fcg_bin
.fcg_mul: mov edi,0x59; jmp .fcg_bin
.fcg_div: mov edi,0x5E
.fcg_bin:
    mov r14d,edi
    cmp r14d,0x59
    jne .fcg_bin_normal
    mov esi,ebx
    call ff_reduce_square_foldable
    test eax,eax
    jz .fcg_bin_not_reduce_square
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov edi,eax
    call ff_emit_reduce_square_fma; test eax,eax; jnz .fcg_bad
    mov edi,[r15+4]; call ff_codegen_alias_kill
    lea eax,[rbx+1]
    mov dword ptr [rip+ff_reduce_square_skip_pos],eax
    jmp .fcg_next
.fcg_bin_not_reduce_square:
    cmp dword ptr [rip+ff_fold_pending_consumer_pos],ebx
    jne .fcg_bin_normal
    mov dword ptr [rip+ff_fold_pending_consumer_pos],-1
    # Resolve the read side before killing a destructive dst alias: in-place
    # forms such as v1=v1*const must still read the immutable LoadFact carrier.
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r12d,eax
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov esi,[r15+4]; FF_MAP_VREG esi,rsi
    mov edx,r12d
    mov eax,dword ptr [rip+ff_fold_pending_kind]
    cmp eax,1
    je .fcg_bin_fold_reg
    cmp eax,2
    je .fcg_bin_fold_stack
    jmp .fcg_bad
.fcg_bin_fold_reg:
    mov ecx,dword ptr [rip+ff_fold_pending_source]
    mov edi,r14d
    call ff_emit_vbin; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_bin_fold_stack:
    mov ecx,dword ptr [rip+ff_fold_pending_source]
    mov edi,r14d
    call ff_emit_vbin_stack; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_bin_normal:
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r12d,eax
    mov edi,[r15+12]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r13d,eax
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov esi,[r15+4]; FF_MAP_VREG esi,rsi
    mov edi,r14d
    mov edx,r12d
    mov ecx,r13d
    call ff_emit_vbin; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_sqrt:
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r12d,eax
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi
    mov esi,r12d
    call ff_emit_vsqrt; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_trunc:
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r12d,eax
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi
    mov esi,r12d
    call ff_emit_vtrunc; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_fma_acc:
    mov edi,[r15+4]
    call ff_codegen_materialize_acc
    test eax,eax; jnz .fcg_bad
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r12d,eax
    mov edi,[r15+12]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r13d,eax
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi
    mov esi,r12d
    mov edx,r13d
    call ff_emit_vfma_acc; test eax,eax; jnz .fcg_bad
    mov edi,[r15+4]; call ff_codegen_alias_kill
    jmp .fcg_next
.fcg_mov:
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov r12d,eax
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi
    mov esi,r12d
    call ff_emit_vmov; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_store:
    # Contiguous store consumption uses the launch-static layout/NT facts.
    # Direct Region stores are unmasked because complete-packet validity was
    # already proved before this body was entered.
    mov edi,[r15+16]
    mov rax,FIELD_RUNTIME_FIELD_CONTIG_PTR_VA
    call ff_emit_movzx_eax_runtime_byte_ptr_array; test eax,eax; jnz .fcg_bad
    lea rdi,[rip+cg_test_eax]; mov esi,cg_test_eax_end-cg_test_eax; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x84; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_store_slow_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    lea rdi,[rip+cg_test_r15_nt]; mov esi,cg_test_r15_nt_end-cg_test_r15_nt; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x85; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_store_nt_slow_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov esi,eax
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov esi,eax
    mov edi,[r15+16]
    call ff_emit_direct_regular_store_from; test eax,eax; jnz .fcg_bad
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_store_done_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_store_slow_disp_ptr]
    lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax
    mov rdx,[rip+ff_store_nt_slow_disp_ptr]
    lea rcx,[rdx+4]; mov rax,[rip+ff_emit_ptr]; sub rax,rcx; mov [rdx],eax
.fcg_store_helper:
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    xor edi,edi; mov esi,eax; call ff_emit_vmov
    mov edi,[r15+16]; call ff_emit_mov_edi_imm
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
    mov edi,[r15+16]
    call ff_runtime_store_va_for_field
    test rax,rax; jz .fcg_bad
    call ff_emit_call; test eax,eax; jnz .fcg_bad
    mov edi,ebx; call ff_emit_reload_residents; test eax,eax; jnz .fcg_bad
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_store_done_disp_ptr]
    lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax
    jmp .fcg_next
.fcg_reduce:
    cmp dword ptr [rip+ff_reduce_square_skip_pos],ebx
    jne .fcg_reduce_normal
    mov dword ptr [rip+ff_reduce_square_skip_pos],-1
    jmp .fcg_next
.fcg_reduce_normal:
    mov edi,[r15+8]; call ff_codegen_source_reg
    test eax,eax; js .fcg_bad
    mov edi,eax; call ff_emit_reduce; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_iindex:
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
    cmp dword ptr [r15+4],0; jne 1f
    mov rax,FIELD_RUNTIME_IINDEX0_VA; jmp 2f
1:  mov rax,FIELD_RUNTIME_IINDEX1_VA
2:  call ff_emit_call; test eax,eax; jnz .fcg_bad
    mov edi,ebx; call ff_emit_reload_residents; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_iadd: mov r12d,FIELD_RUNTIME_IADD0_VA; mov r13d,FIELD_RUNTIME_IADD1_VA; jmp .fcg_iconst
.fcg_isub: mov r12d,FIELD_RUNTIME_ISUB0_VA; mov r13d,FIELD_RUNTIME_ISUB1_VA; jmp .fcg_iconst
.fcg_imul: mov r12d,FIELD_RUNTIME_IMUL0_VA; mov r13d,FIELD_RUNTIME_IMUL1_VA; jmp .fcg_iconst
.fcg_idiv: mov r12d,FIELD_RUNTIME_IDIV0_VA; mov r13d,FIELD_RUNTIME_IDIV1_VA; jmp .fcg_iconst
.fcg_imod: mov r12d,FIELD_RUNTIME_IMOD0_VA; mov r13d,FIELD_RUNTIME_IMOD1_VA
.fcg_iconst:
    mov edi,[r15+20]; call ff_emit_mov_edi_imm
    cmp dword ptr [r15+4],0; jne 3f
    mov eax,r12d; jmp 4f
3:  mov eax,r13d
4:  mov rax,rax; call ff_emit_call; test eax,eax; jnz .fcg_bad
    mov edi,ebx; call ff_emit_reload_residents; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_itof:
    cmp dword ptr [r15+8],0; jne 5f
    mov rax,FIELD_RUNTIME_ITOF0_VA; jmp 6f
5:  mov rax,FIELD_RUNTIME_ITOF1_VA
6:  call ff_emit_call; test eax,eax; jnz .fcg_bad
    mov edi,[r15+4]; call ff_codegen_alias_kill
    mov edi,[r15+4]; FF_MAP_VREG edi,rdi; xor esi,esi; call ff_emit_vmov
    mov edi,ebx; call ff_emit_reload_residents; test eax,eax; jnz .fcg_bad
    jmp .fcg_next
.fcg_next:
    inc ebx; jmp .fcg_ops
.fcg_ops_done:
    mov rax,[rip+ff_emit_ptr]
    mov [rip+ff_ops_body_end_ptr],rax
    # q += lanes. A direct Region loops straight back to its direct kernel head;
    # when the Region expires, only then does the immutable launch mode select
    # the next transition loop.
.if FIELD_LANES == 16
    lea rdi,[rip+cg_add16]; mov esi,cg_add16_end-cg_add16; call ff_emit_bytes
.else
    lea rdi,[rip+cg_add8]; mov esi,cg_add8_end-cg_add8; call ff_emit_bytes
.endif
    lea rdi,[rip+cg_cmp_q_regular_end]; mov esi,cg_cmp_q_regular_end_end-cg_cmp_q_regular_end; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x82; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_direct_backedge_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    lea rdi,[rip+cg_test_r15_direct]; mov esi,cg_test_r15_direct_end-cg_test_r15_direct; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x85; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_regular_backedge_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
.if FIELD_LANES == 16
    # Launch-generic: q advanced by one packet, so advance the already-live
    # canonical CoordinateFact instead of rediscovering Rank-N coordinates.
    # First guard the invocation end because the induction helper is pure
    # physical continuation and must never materialize a nonexistent packet.
    lea rdi,[rip+cg_cmp]; mov esi,cg_cmp_end-cg_cmp; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x83; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_generic_induction_done_disp_ptr],rax
    xor edi,edi; call ff_emit_u32
    lea rdi,[rip+cg_qend]; mov esi,cg_qend_end-cg_qend; call ff_emit_bytes
    xor edi,edi
    call ff_runtime_advance_coords_va_for_field
    test rax,rax; jz .fcg_bad
    call ff_emit_call; test eax,eax; jnz .fcg_bad
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; lea rcx,[rax+4]; mov rdx,[rip+ff_generic_ready_ptr]; sub rdx,rcx; mov edi,edx; call ff_emit_u32
.else
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; lea rcx,[rax+4]; mov rdx,[rip+ff_generic_loop_ptr]; sub rdx,rcx; mov edi,edx; call ff_emit_u32
.endif
    mov rdx,[rip+ff_direct_backedge_disp_ptr]
    lea rcx,[rdx+4]; mov rax,[rip+ff_direct_loop_ptr]; sub rax,rcx; mov [rdx],eax
    mov rdx,[rip+ff_regular_backedge_disp_ptr]
    lea rcx,[rdx+4]; mov rax,[rip+ff_regular_loop_ptr]; sub rax,rcx; mov [rdx],eax

    # 1.3.76 complete causal-depth burn.  Packet zero is the mature Vector
    # body.  Every additional Group packet owns only the logical MachineFact carrier
    # bundle demanded by its live values.  Immutable LoadFacts remain AddressFacts
    # until the exact dependency depth that consumes them, and tolerant operators
    # may burn those addresses directly into memory operands.  Independent causal
    # chains therefore coexist without a shadow load bank, byte cloning, fixed
    # unroll width, or second schedule IR.
    cmp dword ptr [rip+ff_machine_group_safe],1
    jne .fcg_patch_direct_single
    cmp dword ptr [rip+group_body_factor],1
    jbe .fcg_patch_direct_single

    mov rax,[rip+ff_emit_ptr]
    mov [rip+ff_group_dispatch_ptr],rax
    # Guard one whole Group inside the already-proved stable Region.
    lea rdi,[rip+cg_mov_rax_r12]; mov esi,cg_mov_rax_r12_end-cg_mov_rax_r12; call ff_emit_bytes
    mov dil,0x48; call ff_emit_u8
    mov dil,0x05; call ff_emit_u8
    mov eax,dword ptr [rip+group_body_factor]
    imul eax,eax,FIELD_LANES
    mov edi,eax; call ff_emit_u32
    lea rdi,[rip+cg_cmp_rax_r14]; mov esi,cg_cmp_rax_r14_end-cg_cmp_rax_r14; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x87; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; mov [rip+ff_group_single_disp_ptr],rax
    xor edi,edi; call ff_emit_u32

    # Packet zero already owns mature residents.  Later packets keep immutable
    # LoadFacts as AddressFact-backed memory identities until their true consumer;
    # the depth-major scheduler materializes them just in time into packet-local
    # logical carriers.  No preloaded shadow cache bank survives.
    call ff_emit_group_depth_schedule
    test eax,eax; jnz .fcg_bad
    # Advance q once for the complete Group episode.
    lea rdi,[rip+cg_add_r12_imm32]; mov esi,cg_add_r12_imm32_end-cg_add_r12_imm32; call ff_emit_bytes
    mov eax,dword ptr [rip+group_body_factor]
    imul eax,eax,FIELD_LANES
    mov edi,eax; call ff_emit_u32
    lea rdi,[rip+cg_cmp_q_regular_end]; mov esi,cg_cmp_q_regular_end_end-cg_cmp_q_regular_end; call ff_emit_bytes
    mov dil,0x0F; call ff_emit_u8; mov dil,0x82; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; lea rcx,[rax+4]; mov rdx,[rip+ff_direct_loop_ptr]; sub rdx,rcx; mov edi,edx; call ff_emit_u32
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; lea rcx,[rax+4]; mov rdx,[rip+ff_regular_loop_ptr]; sub rdx,rcx; mov edi,edx; call ff_emit_u32

    # Tail: packet zero is already preloaded, so preserve the canonical one-body
    # Vector degradation rather than inventing a compatibility backend.
    mov rax,[rip+ff_emit_ptr]
    mov rdx,[rip+ff_group_single_disp_ptr]
    lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax
    mov dil,0xE9; call ff_emit_u8
    mov rax,[rip+ff_emit_ptr]; lea rcx,[rax+4]; mov rdx,[rip+ff_ops_body_ptr]; sub rdx,rcx; mov edi,edx; call ff_emit_u32

    mov rdx,[rip+ff_regular_done_disp_ptr]
    lea rcx,[rdx+4]; mov rax,[rip+ff_group_dispatch_ptr]; sub rax,rcx; mov [rdx],eax
    jmp .fcg_direct_patch_done

.fcg_patch_direct_single:
    mov rdx,[rip+ff_regular_done_disp_ptr]
    lea rcx,[rdx+4]; mov rax,[rip+ff_ops_body_ptr]; sub rax,rcx; mov [rdx],eax
.fcg_direct_patch_done:
    # patch both forward JAE exits to the single epilogue
    mov rax,[rip+ff_emit_ptr]; mov rdx,[rip+ff_done_disp_ptr]; lea rcx,[rdx+4]; sub rax,rcx; mov [rdx],eax
    mov rdx,[rip+ff_generic_done_disp_ptr]; lea rcx,[rdx+4]; mov rax,[rip+ff_emit_ptr]; sub rax,rcx; mov [rdx],eax
.if FIELD_LANES == 16
    mov rdx,[rip+ff_generic_induction_done_disp_ptr]; test rdx,rdx; jz 91f
    lea rcx,[rdx+4]; mov rax,[rip+ff_emit_ptr]; sub rax,rcx; mov [rdx],eax
91:
.endif
    # horizontal reduction + return
    mov edi,dword ptr [rip+ff_cache_bytes]
    test edi,edi; jz .fcg_no_cache_release
    call ff_emit_stack_add; test eax,eax; jnz .fcg_bad
.fcg_no_cache_release:
.if FIELD_LANES == 16
    lea rdi,[rip+cg_epilogue512]; mov esi,cg_epilogue512_end-cg_epilogue512; call ff_emit_bytes
.else
    lea rdi,[rip+cg_epilogue256]; mov esi,cg_epilogue256_end-cg_epilogue256; call ff_emit_bytes
.endif
    xor eax,eax; ret
.fcg_bad: mov eax,1; ret

ff_emit_mov_edi_imm:
    push rdi; mov dil,0xBF; call ff_emit_u8; pop rdi; call ff_emit_u32; ret
ff_emit_mov_esi_imm:
    push rdi; mov dil,0xBE; call ff_emit_u8; pop rdi; call ff_emit_u32; ret

# Zero one physical SIMD register. Cross-output AVX2 accumulators and the
# coefficient carrier are deliberately low-register values; no helper ABI state
# is touched and no memory materialization is introduced.
ff_emit_vzero_reg:
    push rbx
    mov ebx,edi
.if FIELD_LANES == 16
    # EVEX vxorps zmmDST,zmmDST,zmmDST, low architectural bank used here.
    mov dil,0x62; call ff_emit_u8; mov dil,0xF1; call ff_emit_u8
    mov eax,ebx; shl eax,3; mov edi,0x7C; sub edi,eax; call ff_emit_u8
    mov dil,0x48; call ff_emit_u8; mov dil,0x57; call ff_emit_u8
    mov eax,ebx; shl eax,3; or eax,ebx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.else
    cmp ebx,7; ja .fvzr_bad
    mov dil,0xC5; call ff_emit_u8
    mov eax,ebx; shl eax,3; mov edi,0xFC; sub edi,eax; call ff_emit_u8
    mov dil,0x57; call ff_emit_u8
    mov eax,ebx; shl eax,3; or eax,ebx; or eax,0xC0; mov edi,eax; call ff_emit_u8
.endif
    xor eax,eax
    pop rbx
    ret
.fvzr_bad:
    mov eax,1
    pop rbx
    ret

# edi=f32 bits, esi=dst
ff_emit_const_real:
    push rbx
    mov ebx,esi
    push rdi
    mov dil,0x68; call ff_emit_u8
    pop rdi; call ff_emit_u32
.if FIELD_LANES == 16
    mov dil,0x62; call ff_emit_u8; mov dil,0xF2; call ff_emit_u8; mov dil,0x7D; call ff_emit_u8; mov dil,0x48; call ff_emit_u8; mov dil,0x18; call ff_emit_u8
    mov eax,ebx; shl eax,3; or eax,0x04; mov edi,eax; call ff_emit_u8; mov dil,0x24; call ff_emit_u8
.else
    mov dil,0xC4; call ff_emit_u8
    mov eax,0xE2
    test ebx,8; jz 23f; xor eax,0x80
23: mov edi,eax; call ff_emit_u8
    mov dil,0x7D; call ff_emit_u8; mov dil,0x18; call ff_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x04; mov edi,eax; call ff_emit_u8; mov dil,0x24; call ff_emit_u8
.endif
    lea rdi,[rip+cg_pop_const]; mov esi,cg_pop_const_end-cg_pop_const; call ff_emit_bytes
    pop rbx; ret

# edi=physical source. Tolerant square-reduction fusion keeps the same active-
# lane authority while deleting the synthetic square temporary.
ff_emit_reduce_square_fma:
.if FIELD_LANES == 16
    push rbx
    mov ebx,edi
    cmp ebx,31; ja .fersf_bad
    # vfmadd231ps zmm5{k1},zmmSRC,zmmSRC, full ZMM0..31 source bank.
    mov dil,0x62; call ff_emit_u8
    mov eax,0x92
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov edi,eax; call ff_emit_u8
    mov eax,ebx; and eax,15; xor eax,15; shl eax,3; or eax,5; mov edi,eax; call ff_emit_u8
    mov eax,ebx; shr eax,4; and eax,1; xor eax,1; shl eax,3; or eax,0x41; mov edi,eax; call ff_emit_u8
    mov dil,0xB8; call ff_emit_u8
    mov eax,5; shl eax,3
    mov edx,ebx; and edx,7; or eax,edx; or eax,0xC0; mov edi,eax; call ff_emit_u8
    xor eax,eax
    pop rbx
    ret
.fersf_bad:
    mov eax,1
    pop rbx
    ret
.else
    # Mask the active lanes into helper scratch YMM0, then fuse square+sum.
    push rdi
    mov dil,0xC5; call ff_emit_u8
    pop rdi; mov eax,edi; shl eax,3; mov edi,0xFC; sub edi,eax; call ff_emit_u8
    mov dil,0x54; call ff_emit_u8; mov dil,0xC4; call ff_emit_u8
    mov edi,5; xor esi,esi; xor edx,edx
    call ff_emit_vfma_acc
    ret
.endif

# edi=source register -> hidden vector5 accumulator, active lanes only.
ff_emit_reduce:
.if FIELD_LANES == 16
    # Native512 contract is unchanged.
    push rdi
    mov dil,0x62; call ff_emit_u8; mov dil,0xF1; call ff_emit_u8; mov dil,0x54; call ff_emit_u8; mov dil,0x49; call ff_emit_u8; mov dil,0x58; call ff_emit_u8
    pop rdi; mov eax,5; shl eax,3; or eax,edi; or eax,0xC0; mov edi,eax; call ff_emit_u8
.else
    # YMM0 is the native256 helper/reduction scratch and is deliberately absent
    # from the logical ValueFact table. Mask the active lanes, then accumulate
    # into the hidden YMM5 recurrence without clobbering any logical carrier.
    # vandps ymm0, ymmSRC, ymm4
    push rdi
    mov dil,0xC5; call ff_emit_u8
    pop rdi; mov eax,edi; shl eax,3; mov edi,0xFC; sub edi,eax; call ff_emit_u8
    mov dil,0x54; call ff_emit_u8; mov dil,0xC4; call ff_emit_u8
    # vaddps ymm5,ymm5,ymm0
    mov dil,0xC5; call ff_emit_u8; mov dil,0xD4; call ff_emit_u8; mov dil,0x58; call ff_emit_u8; mov dil,0xE8; call ff_emit_u8
.endif
    ret

# Rank is one canonical invocation fact.  Every admitted rank consumes the same
# native Rank-N address authority; the compiler never selects r1..r8 entry points.
ff_runtime_offsets_va_for_access:
    cmp edi,dword ptr [rip+ff_access_count]
    jae .ffrvo_bad
    mov rax,FIELD_RUNTIME_OFFSETS_VA
    ret
ff_runtime_offsets_va_for_field:
    cmp edi,dword ptr [rip+ff_field_count]
    jae .ffrvo_bad
    mov rax,FIELD_RUNTIME_OFFSETS_VA
    ret
.ffrvo_bad:
    xor eax,eax
    ret

# CoordinateFact preparation is now only packet-mask materialization.  Axis
# coordinates are local facts inside the one Rank-N offset relation rather than
# persistent ZMM24..31 semantic state.
ff_runtime_prepare_coords_va_for_field:
    cmp edi,dword ptr [rip+ff_field_count]
    jae .ffrpc_bad
    mov rax,FIELD_RUNTIME_MASK_VA
    ret
.ffrpc_bad:
    xor eax,eax
    ret

ff_runtime_offsets_from_coords_va_for_access:
    cmp edi,dword ptr [rip+ff_access_count]
    jae .ffrofc_bad
    mov rax,FIELD_RUNTIME_OFFSETS_VA
    ret
.ffrofc_bad:
    xor eax,eax
    ret

ff_runtime_advance_coords_va_for_field:
    cmp edi,dword ptr [rip+ff_field_count]
    jae .ffrac_bad
    mov rax,FIELD_RUNTIME_MASK_VA
    ret
.ffrac_bad:
    xor eax,eax
    ret


ff_runtime_store_va_for_field:
    cmp edi,dword ptr [rip+ff_field_count]
    jae .ffrvs_bad
    mov rax,FIELD_RUNTIME_STORE_VA
    ret
.ffrvs_bad:
    xor eax,eax
    ret

# 1.3.81 Traffic Reality.  Derive two facts over one 64-byte ownership quantum:
#   actual_traffic_lines: line-equivalent data-path operations the current
#       physicalization really emits (unique immutable preloads + mutable loads
#       + stores), used as a real outward-profitability resource floor;
#   transport_floor_lines: mathematical affine streams that must bring new data
#       into the advancing innermost-axis window, used as the structural lower
#       bound for later machine convergence/audit.
# Accesses belong to one stream exactly when field identity and every outer-axis
# affine delta are identical.  Innermost deltas are positions in one sliding
# stream, not independent data sources.  This is rank/AddressFact algebra only:
# no stencil matcher, fixed window width, extent threshold, or runtime manager.
ff_derive_transport_facts:
    push rbx
    push r12
    push r13
    push r14
    push r15

    # Actual current physical data-path line equivalents per ownership quantum.
    mov r12d,dword ptr [rip+ff_cache_count]   # one unique immutable preload
    xor ebx,ebx
.fdtf_actual_loop:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fdtf_actual_done
    mov rax,rbx
    imul rax,OP_SIZE
    mov r13,[rip+ff_ops_ptr]
    add r13,rax
    mov eax,dword ptr [r13]
    cmp eax,OP_STORE
    je .fdtf_actual_add
    cmp eax,OP_LOAD
    jne .fdtf_actual_next
    mov eax,dword ptr [r13+16]                # access id
    cmp eax,dword ptr [rip+ff_access_count]
    jae .fdtf_fail
    mov rdx,[rip+ff_access_cache_slot_ptr]
    cmp dword ptr [rdx+rax*4],FF_CACHE_NONE
    jne .fdtf_actual_next                     # already counted once in cache_count
.fdtf_actual_add:
    inc r12d
.fdtf_actual_next:
    inc ebx
    jmp .fdtf_actual_loop
.fdtf_actual_done:
    mov dword ptr [rip+ff_actual_traffic_lines],r12d

    # Count affine input streams.  Access i starts a new stream iff no previous
    # access shares its field and all outer-axis deltas.  Runtime extents are not
    # required for this identity; periodic congruence beyond exact affine
    # equality remains a launch-time RegionFact rather than an AOT guess.
    xor r12d,r12d                              # floor input streams
    xor ebx,ebx                                # i
.fdtf_i:
    cmp ebx,dword ptr [rip+ff_access_count]
    jae .fdtf_store_floor
    mov rax,[rip+ff_access_field_ptr]
    movzx r13d,byte ptr [rax+rbx]              # field_i
    xor r14d,r14d                              # j
.fdtf_j:
    cmp r14d,ebx
    jae .fdtf_new_stream
    mov rax,[rip+ff_access_field_ptr]
    movzx eax,byte ptr [rax+r14]
    cmp eax,r13d
    jne .fdtf_j_next
    # Same field: compare every axis except the innermost one.
    mov r15,[rip+ff_common_rank]
    test r15d,r15d
    jz .fdtf_fail
    dec r15d                                   # number of outer axes
    xor ecx,ecx
.fdtf_axis_cmp:
    cmp ecx,r15d
    jae .fdtf_duplicate_stream
    mov rdx,[rip+ff_access_delta_ptr]
    mov rax,rbx
    imul rax,qword ptr [rip+ff_access_delta_stride]
    lea r8,[rax+rcx*4]
    mov eax,dword ptr [rdx+r8]
    mov r8,r14
    imul r8,qword ptr [rip+ff_access_delta_stride]
    lea r8,[r8+rcx*4]
    cmp eax,dword ptr [rdx+r8]
    jne .fdtf_j_next
    inc ecx
    jmp .fdtf_axis_cmp
.fdtf_duplicate_stream:
    jmp .fdtf_i_next
.fdtf_j_next:
    inc r14d
    jmp .fdtf_j
.fdtf_new_stream:
    inc r12d
.fdtf_i_next:
    inc ebx
    jmp .fdtf_i

.fdtf_store_floor:
    # Every semantic store is a required outward stream at the current graph
    # contract.  Store coalescence is not guessed here because an intervening
    # inout read can make an earlier store observable inside the same episode.
    xor ebx,ebx
.fdtf_store_loop:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .fdtf_publish
    mov rax,rbx
    imul rax,OP_SIZE
    mov r13,[rip+ff_ops_ptr]
    cmp dword ptr [r13+rax],OP_STORE
    jne .fdtf_store_next
    inc r12d
.fdtf_store_next:
    inc ebx
    jmp .fdtf_store_loop
.fdtf_publish:
    # A theoretical transport floor is useful only while it remains a true
    # lower bound on the emitted traffic fact.  Contradiction is a compiler
    # proof failure, never a reason to clamp the theory upward/downward.
    mov eax,dword ptr [rip+ff_actual_traffic_lines]
    cmp r12d,eax
    ja .fdtf_fail
    mov dword ptr [rip+ff_transport_floor_lines],r12d
    imul rax,PRC_TRAFFIC_LINE_TICKS
    mov qword ptr [rip+ff_actual_traffic_ticks],rax
    mov eax,r12d
    imul rax,PRC_TRAFFIC_LINE_TICKS
    mov qword ptr [rip+ff_transport_floor_ticks],rax
    xor eax,eax
    jmp .fdtf_done
.fdtf_fail:
    mov dword ptr [rip+ff_actual_traffic_lines],-1
    mov dword ptr [rip+ff_transport_floor_lines],-1
    mov rax,0x7fffffffffffffff
    mov qword ptr [rip+ff_actual_traffic_ticks],rax
    mov qword ptr [rip+ff_transport_floor_ticks],rax
    mov eax,1
.fdtf_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# 1.3.18 AOT field chunk Physical Reality price.
# Counts the final field Physical OP graph in the same 1/12-cycle resource units
# used by the Tensor scheduler, then multiplies by the exact SIMD episodes/chunk.
# No element-count or chunk-count expansion threshold is encoded.
ff_derive_chunk_work_ticks:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call ff_derive_transport_facts
    test eax,eax
    jnz .ffdw_sat
    lea rdi,[rip+ff_work_counts]
    xor eax,eax
    mov ecx,10
    rep stosd
    xor ebx,ebx
.ffdw_loop:
    cmp ebx,dword ptr [rip+ff_op_count]
    jae .ffdw_bounds
    mov rax,rbx
    imul rax,OP_SIZE
    mov r12,[rip+ff_ops_ptr]
    add r12,rax
    mov eax,dword ptr [r12]
    cmp eax,OP_NOP; je .ffdw_next
    cmp eax,OP_LOAD; je .ffdw_load
    cmp eax,OP_CONST; je .ffdw_load
    cmp eax,OP_STORE; je .ffdw_load
    cmp eax,OP_ADD; je .ffdw_add
    cmp eax,OP_SUB; je .ffdw_add
    cmp eax,OP_REDUCE; je .ffdw_add
    cmp eax,OP_MUL; je .ffdw_mul
    cmp eax,OP_DIV; je .ffdw_div
    cmp eax,OP_SQRT; je .ffdw_div
    cmp eax,OP_TRUNC; je .ffdw_conv       # conservative long-latency FP resource slot
    cmp eax,OP_ITOF32; je .ffdw_conv
    cmp eax,OP_IINDEX; je .ffdw_ialu
    cmp eax,OP_IADD_CONST; je .ffdw_ialu
    cmp eax,OP_ISUB_CONST; je .ffdw_ialu
    cmp eax,OP_MOV; je .ffdw_ialu
    cmp eax,OP_IMUL_CONST; je .ffdw_imul
    cmp eax,OP_IDIV_CONST; je .ffdw_idiv
    cmp eax,OP_IMOD_CONST; je .ffdw_idiv
    cmp eax,OP_FMA_ACC; je .ffdw_fma
    jmp .ffdw_next
.ffdw_load:
    inc dword ptr [rip+ff_work_counts+7*4]
    inc dword ptr [rip+ff_work_counts+8*4]
    jmp .ffdw_next
.ffdw_add:
    inc dword ptr [rip+ff_work_counts+0*4]
    jmp .ffdw_next
.ffdw_mul:
    inc dword ptr [rip+ff_work_counts+1*4]
    jmp .ffdw_next
.ffdw_div:
    inc dword ptr [rip+ff_work_counts+2*4]
    jmp .ffdw_next
.ffdw_conv:
    inc dword ptr [rip+ff_work_counts+3*4]
    jmp .ffdw_next
.ffdw_ialu:
    inc dword ptr [rip+ff_work_counts+4*4]
    jmp .ffdw_next
.ffdw_imul:
    inc dword ptr [rip+ff_work_counts+5*4]
    jmp .ffdw_next
.ffdw_idiv:
    inc dword ptr [rip+ff_work_counts+6*4]
    jmp .ffdw_next
.ffdw_fma:
    inc dword ptr [rip+ff_work_counts+0*4]
    inc dword ptr [rip+ff_work_counts+1*4]
.ffdw_next:
    inc ebx
    jmp .ffdw_loop

.ffdw_bounds:
    # branch count is one canonical loop backedge per SIMD episode.
    mov dword ptr [rip+ff_work_counts+9*4],1
    xor r15d,r15d
    lea r14,[rip+ff_work_counts]
    # fp add 2/c => 6 ticks/op
    mov eax,[r14+0]; imul eax,eax,PRC_FP_ADD_TICKS; cmp eax,r15d; cmova r15d,eax
    # fp mul 2/c
    mov eax,[r14+4]; imul eax,eax,PRC_FP_MUL_TICKS; cmp eax,r15d; cmova r15d,eax
    # fp div 14c
    mov eax,[r14+8]; imul eax,eax,PRC_FP_DIV_TICKS; cmp eax,r15d; cmova r15d,eax
    # fp convert 1/c
    mov eax,[r14+12]; imul eax,eax,PRC_FP_CONV_TICKS; cmp eax,r15d; cmova r15d,eax
    # int ALU 4/c
    mov eax,[r14+16]; imul eax,eax,PRC_INT_ALU_TICKS; cmp eax,r15d; cmova r15d,eax
    # int mul 2/c
    mov eax,[r14+20]; imul eax,eax,PRC_INT_MUL_TICKS; cmp eax,r15d; cmova r15d,eax
    # int div 10c
    mov eax,[r14+24]; imul eax,eax,PRC_INT_DIV_TICKS; cmp eax,r15d; cmova r15d,eax
    # load 2/c
    mov eax,[r14+28]; imul eax,eax,PRC_LOAD_TICKS; cmp eax,r15d; cmova r15d,eax
    # AGU 3/c
    mov eax,[r14+32]; imul eax,eax,PRC_AGU_TICKS; cmp eax,r15d; cmova r15d,eax
    # branch 1/c
    mov eax,[r14+36]; imul eax,eax,PRC_BRANCH_TICKS; cmp eax,r15d; cmova r15d,eax
    test r15d,r15d
    jz .ffdw_sat

    # Publish one structural writable-ownership quantum, not a chunk. One cache
    # line is the indivisible mutable-ownership unit: 64 bytes / sizeof(f32)=16
    # elements. Launch-time Physical Reality chooses the balanced leaf geometry
    # from runtime N, target parallel width, and outward lifecycle price.
    mov r12d,r15d                  # ticks / vector episode
    mov eax,FF_TRAFFIC_QUANTUM_ELEMENTS # one Physical Reality traffic quantum
    xor edx,edx
    mov ecx,FIELD_LANES
    div ecx                        # vector episodes / ownership quantum: 1 or 2
    test edx,edx
    jnz .ffdw_sat
    test eax,eax
    jz .ffdw_sat
    mov r8d,eax
    mov eax,r12d
    mul r8d
    test edx,edx
    jnz .ffdw_sat
    test eax,eax
    jz .ffdw_sat
    # Data-path transport is a peer resource dimension, not hidden inside a
    # generic LOAD issue price.  Charge the current emitted line-equivalent
    # traffic as a lower bound on real work; the mathematical stream floor is
    # retained separately for theory-vs-machine convergence audits.
    mov rcx,qword ptr [rip+ff_actual_traffic_ticks]
    cmp rax,rcx
    cmovb rax,rcx
    mov qword ptr [rip+ff_chunk_elements],FF_TRAFFIC_QUANTUM_ELEMENTS
    mov qword ptr [rip+ff_chunk_work_ticks],rax
    jmp .ffdw_done
.ffdw_sat:
    mov qword ptr [rip+ff_chunk_elements],FF_TRAFFIC_QUANTUM_ELEMENTS
    mov rax,0x7fffffffffffffff
    mov qword ptr [rip+ff_chunk_work_ticks],rax

.ffdw_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- output image ----------------
ff_emit_image:
    push rbx
    push r12
    push r13
    call ff_derive_chunk_work_ticks
    mov r12,[rip+ff_emit_ptr]; mov rax,[rip+ff_code_ptr]; sub r12,rax
    test r12,r12; jz .fei_fail
    mov eax,SYS_openat; mov edi,AT_FDCWD; mov rsi,[rip+ff_output_path]; mov edx,OUT_FLAGS; mov r10d,0755; syscall
    test rax,rax; js .fei_fail
    mov rbx,rax
    mov eax,SYS_write; mov rdi,rbx; lea rsi,[rip+field_runtime_template_blob]; mov edx,FIELD_RUNTIME_TEMPLATE_SIZE; syscall
    cmp rax,FIELD_RUNTIME_TEMPLATE_SIZE; jne .fei_close_fail
    # erase section table
    mov qword ptr [rip+ff_zero],0
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_zero]; mov edx,8; mov r10d,FIELD_RUNTIME_ELF_SHOFF_OFF; syscall; cmp rax,8; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_zero]; mov edx,6; mov r10d,FIELD_RUNTIME_ELF_SHENTSIZE_OFF; syscall; cmp rax,6; jne .fei_close_fail
    # patch executor/counts/modes/ranks/deltas
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+execution_admission_capacity]; mov edx,4; mov r10d,FIELD_RUNTIME_EXECUTION_ADMISSION_OFF; syscall; cmp rax,4; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+sd_static_placement_required]; mov edx,4; mov r10d,FIELD_RUNTIME_STATIC_PLACEMENT_REQUIRED_OFF; syscall; cmp rax,4; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+sd_preferred_l3_mask_bytes]; mov edx,4; mov r10d,FIELD_RUNTIME_STATIC_PLACEMENT_MASK_BYTES_OFF; syscall; cmp rax,4; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+sd_preferred_l3_mask]; mov edx,128; mov r10d,FIELD_RUNTIME_STATIC_PLACEMENT_MASK_OFF; syscall; cmp rax,128; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+outward_materialization_ticks]; mov edx,8; mov r10d,FIELD_RUNTIME_OUTWARD_MATERIALIZATION_TICKS_OFF; syscall; cmp rax,8; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_chunk_work_ticks]; mov edx,8; mov r10d,FIELD_RUNTIME_CHUNK_WORK_TICKS_OFF; syscall; cmp rax,8; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_chunk_elements]; mov edx,8; mov r10d,FIELD_RUNTIME_CHUNK_ELEMENTS_OFF; syscall; cmp rax,8; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_field_count]; mov edx,4; mov r10d,FIELD_RUNTIME_FIELD_COUNT_OFF; syscall; cmp rax,4; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_access_count]; mov edx,4; mov r10d,FIELD_RUNTIME_ACCESS_COUNT_OFF; syscall; cmp rax,4; jne .fei_close_fail

    # Instance metadata is appended immediately after generated code.  The runtime
    # receives one pointer; field/access cardinality determines the record extent.
    mov rax,FIELD_RUNTIME_GENERATED_VA
    add rax,r12
    mov [rip+ff_metadata_va],rax
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_metadata_va]; mov edx,8; mov r10d,FIELD_RUNTIME_METADATA_VA_OFF; syscall; cmp rax,8; jne .fei_close_fail
    # Fabric descriptor admission facts. A normal x86 release has zero bytes.
    mov dword ptr [rip+ff_fabric_activation_abi_version],1
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_fabric_datapath_bytes]; mov edx,8; mov r10d,FIELD_RUNTIME_FABRIC_DATAPATH_BYTES_OFF; syscall; cmp rax,8; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_fabric_activation_bridge_present]; mov edx,4; mov r10d,FIELD_RUNTIME_FABRIC_BRIDGE_PRESENT_OFF; syscall; cmp rax,4; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_fabric_activation_abi_version]; mov edx,4; mov r10d,FIELD_RUNTIME_FABRIC_ACTIVATION_ABI_OFF; syscall; cmp rax,4; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_fabric_activation_entry]; mov edx,8; mov r10d,FIELD_RUNTIME_FABRIC_ACTIVATION_ENTRY_OFF; syscall; cmp rax,8; jne .fei_close_fail

    # generated direct machine code
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+ff_code_ptr]; mov rdx,r12; mov r10d,FIELD_RUNTIME_GENERATED_FILE_OFF; syscall; cmp rax,r12; jne .fei_close_fail

    mov r13d,dword ptr [rip+ff_field_count]
    mov r10,FIELD_RUNTIME_GENERATED_FILE_OFF
    add r10,r12
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_common_rank]; mov edx,8; syscall; cmp rax,8; jne .fei_close_fail
    add r10,8
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+ff_field_mode_ptr]; mov edx,r13d; syscall; cmp rax,r13; jne .fei_close_fail
    add r10,r13
    mov rax,[rip+ff_access_delta_stride]
    mov edx,dword ptr [rip+ff_access_count]
    imul rax,rdx
    jo .fei_close_fail
    mov [rip+ff_metadata_delta_bytes],rax
    mov rdx,rax
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+ff_access_delta_ptr]; syscall
    cmp rax,qword ptr [rip+ff_metadata_delta_bytes]; jne .fei_close_fail

    mov rax,r12
    add rax,8
    mov edx,r13d
    add rax,rdx
    add rax,qword ptr [rip+ff_metadata_delta_bytes]
    mov [rip+ff_generated_len],rax

    # Descriptor follows ordinary Field metadata and is outside the runtime's
    # semantic metadata extent. The bridge pointer is patched only when bytes>0.
    cmp qword ptr [rip+ff_fabric_datapath_bytes],0
    je .fei_no_fabric_descriptor
    mov rcx,FIELD_RUNTIME_GENERATED_VA
    add rcx,rax
    mov [rip+ff_fabric_datapath_va],rcx
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_fabric_datapath_va]; mov edx,8; mov r10d,FIELD_RUNTIME_FABRIC_DATAPATH_VA_OFF; syscall; cmp rax,8; jne .fei_close_fail
    # Header prices are finalized after chunk/traffic derivation.
    mov rax,[rip+ff_actual_traffic_ticks]; mov [rip+ff_fabric_datapath_header+40],rax
    mov rax,[rip+ff_chunk_work_ticks]; mov [rip+ff_fabric_datapath_header+48],rax
    mov r10,FIELD_RUNTIME_GENERATED_FILE_OFF
    add r10,[rip+ff_generated_len]
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_fabric_datapath_header]; mov edx,64; syscall; cmp rax,64; jne .fei_close_fail
    add r10,64
    mov eax,dword ptr [rip+ff_op_count]
    imul edx,eax,OP_SIZE
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+ff_ops_ptr]; syscall; cmp rax,rdx; jne .fei_close_fail
    add r10,rdx
    mov eax,dword ptr [rip+ff_op_count]
    lea edx,[rax*4]
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+ff_physical_depth_ptr]; syscall; cmp rax,rdx; jne .fei_close_fail
    add r10,rdx
    mov eax,dword ptr [rip+ff_op_count]
    lea edx,[rax*4]
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+ff_physical_order_ptr]; syscall; cmp rax,rdx; jne .fei_close_fail
    mov rax,[rip+ff_generated_len]
    add rax,[rip+ff_fabric_datapath_bytes]
    mov [rip+ff_generated_len],rax
.fei_no_fabric_descriptor:
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_generated_len]; mov edx,8; mov r10d,FIELD_RUNTIME_GENERATED_FILESZ_PHDR_OFF; syscall; cmp rax,8; jne .fei_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_generated_len]; mov edx,8; mov r10d,FIELD_RUNTIME_GENERATED_MEMSZ_PHDR_OFF; syscall; cmp rax,8; jne .fei_close_fail
    # runtime eval jump -> generated base
    mov rax,FIELD_RUNTIME_GENERATED_VA
    sub rax,FIELD_RUNTIME_EVAL_END_VA
    mov [rip+ff_disp],eax
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+ff_disp]; mov edx,4; mov r10d,FIELD_RUNTIME_EVAL_DISP_OFF; syscall; cmp rax,4; jne .fei_close_fail
    mov eax,SYS_fchmod; mov rdi,rbx; mov esi,0755; syscall
    mov eax,SYS_close; mov rdi,rbx; syscall
    xor eax,eax; pop r13; pop r12; pop rbx; ret
.fei_close_fail:
    mov eax,SYS_close; mov rdi,rbx; syscall
.fei_fail: mov eax,1; pop r13; pop r12; pop rbx; ret

.section .rodata
.if FIELD_LANES == 8
# Stable expression carriers: v0/v1/v2 remain in low YMM1..3; v3 uses YMM12,
# which native256 helpers no longer touch.
ff_vreg_phys_table: .byte FF256_V0_REG,FF256_V1_REG,FF256_V2_REG,FF256_V3_REG
.endif
# Burn-level AddressFact carrier bank.  These are real x86-64 register IDs,
# not workload slots.  R12..R15 retain q/end/Region/mode ownership; RAX remains
# free for stores/helpers.  RBX is callee-saved by the generated prologue.
# Caller-saved carriers are admitted only when the Physical DAG has no helper
# clobber; otherwise the allocator naturally collapses to RBX alone.
ff_address_gpr_table: .byte 3,1,7,6,8,9,10,11
ff_address_gpr_table_end:

.if FIELD_LANES == 16
ff_resident_reg_table: .byte 0,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
.else
# Native256 candidate bank. YMM0/YMM5 are reclaimed when no reduction authority
# exists; Physical-DAG ownership removes YMM12 only when v3 exists and YMM13/14
# only when the corresponding procedural index exists. Helper aliases are
# phase-separated and restored by existing reload edges.
ff_resident_reg_table: .byte 0,FF256_REDUCE_REG,6,7,8,9,10,11,FF256_V3_REG,FF256_I0_REG,FF256_I1_REG,FF256_PHASE_SCRATCH_REG
.endif
ff_resident_reg_table_end:
# Burn-level generated-function ownership. RBX/RBP are preserved once so the
# direct Region may dedicate the ordinary GPR bank to immutable AddressFacts;
# r12=q, r13=end, r14=exclusive direct-run end, r15d=launch-static mode.
# Six pushes preserve the SysV call alignment of the former four-push prologue.
cg_prologue: .byte 0x53,0x55,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x49,0x89,0xfc,0x49,0x89,0xf5,0x45,0x31,0xf6,0x41,0x89,0xd7
cg_prologue_end:
cg_zero512: .byte 0x62,0xf1,0x54,0x48,0x57,0xed
cg_zero512_end:
cg_zero256: .byte 0xc5,0xd4,0x57,0xed
cg_zero256_end:
cg_cmp: .byte 0x4d,0x39,0xec
cg_cmp_end:
cg_qend: .byte 0x4c,0x89,0xe2,0x4c,0x89,0xe9
cg_qend_end:
# cmp r12,r14 ; cached direct region remains authoritative while q < r14.
cg_cmp_q_regular_end: .byte 0x4d,0x39,0xf4
cg_cmp_q_regular_end_end:
# Group guard helpers: mov rax,r12 ; cmp rax,r14.  The body span itself is an
# emitted immediate derived from canonical GroupFact, never a runtime selector.
cg_mov_rax_r12: .byte 0x4c,0x89,0xe0
cg_mov_rax_r12_end:
cg_cmp_rax_r14: .byte 0x4c,0x39,0xf0
cg_cmp_rax_r14_end:
# mov r14,rax; helper returns zero or the exclusive direct-run end.
cg_mov_r14_rax: .byte 0x49,0x89,0xc6
cg_mov_r14_rax_end:
cg_test_rax: .byte 0x48,0x85,0xc0
cg_test_rax_end:
# Launch-static mode bits in R15D: bit0 direct layout, bit1 uniform input layout,
# bit2 non-temporal output policy. They are published once before field_eval_vec.
cg_test_r15_direct: .byte 0x41,0xf7,0xc7,0x01,0x00,0x00,0x00
cg_test_r15_direct_end:
cg_test_r15_uniform: .byte 0x41,0xf7,0xc7,0x02,0x00,0x00,0x00
cg_test_r15_uniform_end:
cg_test_r15_nt: .byte 0x41,0xf7,0xc7,0x04,0x00,0x00,0x00
cg_test_r15_nt_end:
# Stable direct regions contain complete packets only.
cg_fullmask512: .byte 0xc5,0xf4,0x46,0xc9       # kxnorw k1,k1,k1
cg_fullmask512_end:
cg_fullmask256: .byte 0xc5,0xdd,0x76,0xe4       # vpcmpeqd ymm4,ymm4,ymm4
cg_fullmask256_end:
# Direct regular address realization: rax = field_base + q*4 + signed_delta.
cg_regular_qaddr: .byte 0x48,0x8d,0x04,0x90
cg_regular_qaddr_end:
cg_regular_add_delta: .byte 0x4c,0x01,0xd8
cg_regular_add_delta_end:
cg_regular_load256: .byte 0xc4,0xe2,0x5d,0x2c,0x00
cg_regular_load256_end:
cg_regular_load512: .byte 0x62,0xf1,0x7c,0xc9,0x10,0x00
cg_regular_load512_end:
# cache store prefix through SIB; ff_emit_cache_store_simd0 appends disp32.
cg_cache_store512: .byte 0x62,0xf1,0x7c,0x48,0x11,0x84,0x24
cg_cache_store512_end:
cg_cache_store256: .byte 0xc5,0xfc,0x11,0x84,0x24
cg_cache_store256_end:
cg_coord_store512: .byte 0x62,0xe1,0x7c,0x48,0x11,0x8c,0x24
cg_coord_store512_end:
cg_coord_load512: .byte 0x62,0xe1,0x7c,0x48,0x10,0x8c,0x24
cg_coord_load512_end:
cg_coord_store256: .byte 0xc5,0xfc,0x11,0xbc,0x24
cg_coord_store256_end:
cg_coord_load256: .byte 0xc5,0xfc,0x10,0xbc,0x24
cg_coord_load256_end:
cg_direct_gather512:
.byte 0xc5,0xf8,0x90,0xd1
.byte 0x62,0xf1,0x7c,0x48,0x57,0xc0
.byte 0x62,0xf2,0x7d,0x42,0x92,0x04,0x08
cg_direct_gather512_end:
cg_direct_gather256:
.byte 0xc5,0x7c,0x28,0xfc
.byte 0xc5,0xfc,0x57,0xc0
.byte 0xc4,0xe2,0x05,0x92,0x04,0x38
cg_direct_gather256_end:
cg_test_eax: .byte 0x85,0xc0
cg_test_eax_end:
cg_add16: .byte 0x49,0x83,0xc4,0x10
cg_add16_end:
# add r12,imm32; GroupFact appends the exact episode advance.
cg_add_r12_imm32: .byte 0x49,0x81,0xc4
cg_add_r12_imm32_end:
cg_add8: .byte 0x49,0x83,0xc4,0x08
cg_add8_end:
cg_pop_const: .byte 0x48,0x83,0xc4,0x08
cg_pop_const_end:
cg_epilogue512:
.byte 0x62,0xf3,0x7d,0x48,0x1b,0xe8,0x01,0xc5,0xd4,0x58,0xe8
.byte 0xc4,0xe3,0x7d,0x19,0xe8,0x01,0xc5,0xd0,0x58,0xe8,0xc5,0xd3,0x7c,0xed,0xc5,0xd3,0x7c,0xed,0xc5,0xf8,0x28,0xc5
.byte 0x41,0x5f,0x41,0x5e,0x41,0x5d,0x41,0x5c,0x5d,0x5b,0xc3
cg_epilogue512_end:
cg_epilogue256:
.byte 0xc4,0xe3,0x7d,0x19,0xe8,0x01,0xc5,0xd0,0x58,0xe8,0xc5,0xd3,0x7c,0xed,0xc5,0xd3,0x7c,0xed,0xc5,0xf8,0x28,0xc5
.byte 0x41,0x5f,0x41,0x5e,0x41,0x5d,0x41,0x5c,0x5d,0x5b,0xc3
cg_epilogue256_end:

k_format:.ascii "format"; k_format_end:
v_field_format:.ascii "wheelchair.field/1"; v_field_format_end:
k_contracts:.ascii "contracts"; k_contracts_end:
k_floating_point:.ascii "floating_point"; k_floating_point_end:
v_strict:.ascii "strict"; v_strict_end:
v_tolerant:.ascii "tolerant"; v_tolerant_end:
k_fields:.ascii "fields"; k_fields_end:
k_type:.ascii "type"; k_type_end:
v_f32:.ascii "f32"; v_f32_end:
k_mode:.ascii "mode"; k_mode_end:
v_input:.ascii "input"; v_input_end:
v_output:.ascii "output"; v_output_end:
v_inout:.ascii "inout"; v_inout_end:
k_rank:.ascii "rank"; k_rank_end:
k_accesses:.ascii "accesses"; k_accesses_end:
k_field:.ascii "field"; k_field_end:
k_delta:.ascii "delta"; k_delta_end:
k_ops:.ascii "ops"; k_ops_end:
k_op:.ascii "op"; k_op_end:
k_access:.ascii "access"; k_access_end:
k_dst:.ascii "dst"; k_dst_end:
k_value:.ascii "value"; k_value_end:
k_a:.ascii "a"; k_a_end:
k_b:.ascii "b"; k_b_end:
k_src:.ascii "src"; k_src_end:
k_ireg:.ascii "ireg"; k_ireg_end:
v_load:.ascii "load"; v_load_end:
v_const:.ascii "const"; v_const_end:
v_add:.ascii "add"; v_add_end:
v_sub:.ascii "sub"; v_sub_end:
v_mul:.ascii "mul"; v_mul_end:
v_div:.ascii "div"; v_div_end:
v_sqrt:.ascii "sqrt"; v_sqrt_end:
v_trunc:.ascii "trunc"; v_trunc_end:
v_store:.ascii "store"; v_store_end:
v_reduce:.ascii "reduce"; v_reduce_end:
v_mov:.ascii "mov"; v_mov_end:
v_iindex:.ascii "iindex"; v_iindex_end:
v_iadd_const:.ascii "iadd_const"; v_iadd_const_end:
v_isub_const:.ascii "isub_const"; v_isub_const_end:
v_imul_const:.ascii "imul_const"; v_imul_const_end:
v_idiv_const:.ascii "idiv_const"; v_idiv_const_end:
v_imod_const:.ascii "imod_const"; v_imod_const_end:
v_itof32:.ascii "itof32"; v_itof32_end:

.p2align 3

.section .bss
.p2align 6
ff_output_path:.skip 8
ff_field_count:.skip 4
ff_access_count:.skip 4
ff_op_count:.skip 4
ff_reduce_count:.skip 4
ff_fp_tolerant:.skip 4
ff_arith_fma_fused_count:.skip 4
.p2align 4
# 1.2.17 compile-time locality map: access -> canonical episode-cache slot.
ff_cache_count:.skip 4
ff_coord_count:.skip 4
ff_cache_bytes:.skip 4
ff_addr_pool_count:.skip 4
ff_region_delta_stack_off:.skip 4
ff_region_class_stack_off:.skip 4
ff_packet_coord_stack_off:.skip 4
ff_resident_reserved_mask:.skip 4
ff_const_pool_last_use_pos_ptr:.skip 8
# Compile-time avoided-transport demand after consumer-local folding.  This is
# not a second cache policy; it is the physical cost seen by the shared resident
# allocator after zero-cost rm consumption has already erased standalone loads.
ff_const_pool_transport_demand_ptr:.skip 8
ff_fold_pending_consumer_pos:.skip 4
ff_fold_pending_kind:.skip 4
ff_fold_pending_source:.skip 4
ff_consumer_local_fold_count:.skip 4
# 1.3.74 compiler-only logical-vreg -> immutable physical-carrier aliases.
ff_codegen_vreg_alias:.skip FF_VREG_COUNT*4
ff_reduce_square_skip_pos:.skip 4
ff_resident_limit:.skip 4
ff_first_resident_clobber_pos:.skip 4
# 1.3.6 compiler-only Global Physical Reality graph.
ff_global_fact_count:.skip 4
ff_global_fact_reuse_count:.skip 4
ff_global_rewritten_ops:.skip 4
ff_global_version_invalidations:.skip 4
ff_address_fact_count:.skip 4
ff_address_fact_reuse_count:.skip 4
.p2align 4
ff_instance_arena_ptr:.skip 8
ff_instance_arena_bytes:.skip 8
ff_instance_capacity:.skip 4
ff_field_mode_ptr:.skip 8
ff_access_field_ptr:.skip 8
ff_access_delta_ptr:.skip 8
ff_axis_arena_ptr:.skip 8
ff_axis_arena_bytes:.skip 8
ff_common_rank:.skip 8
ff_access_delta_stride:.skip 8
ff_access_cache_slot_ptr:.skip 8
ff_cache_owner_ptr:.skip 8
ff_access_coord_slot_ptr:.skip 8
ff_coord_owner_ptr:.skip 8
ff_cache_use_count_ptr:.skip 8
ff_cache_resident_reg_ptr:.skip 8
ff_cache_last_load_pos_ptr:.skip 8
ff_access_address_fact_ptr:.skip 8
ff_address_fact_owner_ptr:.skip 8
ff_address_fact_gpr_ptr:.skip 8
ff_field_version_fact_ptr:.skip 8
ff_field_written_fact_ptr:.skip 8
ff_physical_mem_depth_ptr:.skip 8
ff_graph_arena_ptr:.skip 8
ff_graph_arena_bytes:.skip 8
ff_graph_capacity:.skip 4
ff_op_global_fact_ptr:.skip 8
ff_global_vreg_fact:.skip FF_VREG_COUNT*4
ff_global_ireg_fact:.skip 2*4
ff_global_fact_kind_ptr:.skip 8
ff_global_fact_key0_ptr:.skip 8
ff_global_fact_key1_ptr:.skip 8
ff_global_fact_key2_ptr:.skip 8
ff_global_fact_first_op_ptr:.skip 8
ff_global_fact_last_op_ptr:.skip 8
ff_global_fact_use_count_ptr:.skip 8
# 1.3.0 compile-time Physical-DAG plan consumed by final ISA emission.
ff_physical_order_ptr:.skip 8
ff_physical_depth_ptr:.skip 8
ff_physical_depth_counts_ptr:.skip 8
ff_physical_depth_cursor_ptr:.skip 8
ff_physical_vdef:.skip FF_VREG_COUNT*4
ff_physical_vread:.skip FF_VREG_COUNT*4
ff_physical_idef:.skip 2*4
ff_physical_iread:.skip 2*4
ff_physical_reduce_depth:.skip 4
ff_physical_edge_count:.skip 4
ff_physical_memory_barriers:.skip 4
ff_physical_tensor_lanes:.skip 4
ff_physical_episode_ops:.skip 4
ff_physical_max_depth:.skip 4
ff_physical_reordered_ops:.skip 4
ff_physical_artificial_edges:.skip 4
# 1.3.24 compile-time common-factor ValueFact closure.  These are proof
# authorities only; no runtime factor table or dispatch survives emission.
.p2align 4
ff_cf_last_def:.skip FF_VREG_COUNT*4
ff_cf_last_read:.skip FF_VREG_COUNT*4
ff_cf_scratch:.skip 4
ff_cf_pending_valid:.skip 4
ff_cf_pending_fma:.skip 4
ff_cf_pending_muldef:.skip 4
ff_cf_pending_acc:.skip 4
ff_cf_pending_xaccess:.skip 4
ff_cf_active:.skip 4
ff_cf_acc:.skip 4
ff_cf_xaccess:.skip 4
ff_cf_last_fma:.skip 4
ff_cf_cur_xdef:.skip 4
ff_cf_cur_muldef:.skip 4
ff_cf_cur_xreg:.skip 4
ff_cf_cur_coeffreg:.skip 4
ff_cf_cur_xaccess:.skip 4
ff_cf_group_count:.skip 4
ff_cf_term_count:.skip 4
# Generic multi-output physical supernode proof.  The mapping is compile-time
# only; no runtime scheduler, dispatcher, or benchmark identity is emitted.
.p2align 4
ff_const_pool_count:.skip 4
ff_const_pool_bits_ptr:.skip 8
ff_const_pool_use_count_ptr:.skip 8
ff_const_pool_resident_reg_ptr:.skip 8
ff_op_const_slot_ptr:.skip 8
# 1.3.5 physical-fact identity / profitable sovereignty.
.p2align 4
ff_work_counts:.skip 40
ff_actual_traffic_lines:.skip 4
ff_transport_floor_lines:.skip 4
.p2align 3
ff_actual_traffic_ticks:.skip 8
ff_transport_floor_ticks:.skip 8
.p2align 3
ff_chunk_work_ticks:.skip 8
ff_chunk_elements:.skip 8
.p2align 4
ff_ops_ptr:.skip 8
ff_emit_ptr:.skip 8
ff_emit_end:.skip 8
ff_regular_loop_ptr:.skip 8
ff_generic_loop_ptr:.skip 8
ff_generic_ready_ptr:.skip 8
ff_direct_loop_ptr:.skip 8
# 1.3.76 GroupFact-to-ISA burn frontiers.  These are compiler-time byte
# frontiers only; no runtime schedule or width table is emitted.
ff_ops_body_ptr:.skip 8
ff_ops_body_end_ptr:.skip 8
ff_group_dispatch_ptr:.skip 8
ff_group_single_disp_ptr:.skip 8
ff_machine_group_safe:.skip 4
# Architectural carrier namespace only: at most 32 SIMD register identities.
ff_group_used_simd_mask:.skip 4
ff_group_free_count:.skip 4
ff_group_bundle_regs:.skip 4
ff_group_emit_packet:.skip 4
ff_group_source_logical_tmp:.skip 4
# Per-packet compiler-only state is bounded by the 32 architectural SIMD
# identities, not by a Group width authority.
ff_group_reduce_square_skip_pos:.skip 32*4
ff_group_vreg_alias:.skip 32*FF_VREG_COUNT*4
ff_group_free_regs:.skip 32
ff_done_disp_ptr:.skip 8
ff_uniform_fallback_disp_ptr:.skip 8
ff_uniform_done_disp_ptr:.skip 8
ff_launch_generic_disp_ptr:.skip 8
ff_regular_episode_fallback_disp_ptr:.skip 8
ff_region_piecewise_disp_ptr:.skip 8
ff_region_same_interior_disp_ptr:.skip 8
ff_region_refresh_done_disp_ptr:.skip 8
ff_generic_done_disp_ptr:.skip 8
ff_generic_induction_done_disp_ptr:.skip 8
ff_direct_backedge_disp_ptr:.skip 8
ff_regular_backedge_disp_ptr:.skip 8
ff_regular_done_disp_ptr:.skip 8
ff_store_slow_disp_ptr:.skip 8
ff_store_nt_slow_disp_ptr:.skip 8
ff_store_done_disp_ptr:.skip 8
ff_generated_len:.skip 8
ff_metadata_va:.skip 8
ff_metadata_delta_bytes:.skip 8
.p2align 3
ff_fabric_datapath_va:.skip 8
ff_fabric_datapath_bytes:.skip 8
ff_fabric_activation_entry:.skip 8
ff_fabric_datapath_enabled:.skip 4
ff_fabric_activation_bridge_present:.skip 4
ff_fabric_activation_abi_version:.skip 4
.p2align 3
ff_fabric_datapath_header:.skip 64
ff_zero:.skip 8
ff_disp:.skip 4
.p2align 3
ff_code_ptr:.skip 8
ff_code_capacity:.skip 8
ff_code_capacity_prev:.skip 8
ff_code_growth_factor:.skip 8
ff_code_overflow:.skip 4
