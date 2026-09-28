.intel_syntax noprefix
.include "compiler/native256_physical_profile.inc"
.equ TENSOR_PHYSICAL_LANES,4
.include "compiler/isa_capabilities.inc"
.include "compiler/shapefact_n.inc"
.include "compiler/physical_reality.inc"
.include "build/runtime_native256_offsets.inc"

# 1.3.47 aged native256 Physical Profile. Base and wide remain one source.
# AVX2 owns exactly YMM0..15; the historical copied high-bank cache/constant
# domain is physically impossible and no longer participates in allocation.
.if N256_HAS_HIGH_SIMD_BANK
.error "native256 tensor profile may not expose a synthetic high SIMD bank"
.endif

# wheelchair.tensor/1 bounded structural front-end and direct native expression emitter.
# Handwritten x86-64 assembly.  No workload-name dispatch.
# Accepted structural slice:
#   - one u64 external extent n
#   - 1D f64 map bindings
#   - pure add/sub/mul/div, u64 mod, u64->f64 cast, eq, select
#   - pure indexed map loads (recursively fused)
#   - one terminal tolerant f64 sum reduction
# Output: standalone ELF64 runtime template with AOT-generated eval_point code.

.equ SYS_write, 1
.equ SYS_openat, 257
.equ SYS_pwrite64, 18
.equ SYS_fchmod, 91
.equ SYS_close, 3
.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ PROT_READ_WRITE, 3
.equ MAP_PRIVATE_ANON, 0x22
.equ AT_FDCWD, -100
.equ OUT_FLAGS, 577

.equ J_OBJECT,1
.equ J_ARRAY,2
.equ J_STRING,3
.equ J_NUMBER,4
.equ J_TRUE,5
.equ J_FALSE,6
.equ J_NULL,7
.equ NODE_SIZE,64
.equ BIND_SIZE,64
.equ TYPE_U64,1
.equ TYPE_F64,2
.equ OP_MAP,1
.equ OP_REDUCE,2

# Externals from topologyc core.
.extern source_ptr
.extern source_length
.extern execution_admission_capacity
.extern runtime_template_blob
.extern runtime_template_blob_end
.extern synthesize_resource_schedule
.extern synthesize_group_fact
.extern schedule_counts
.extern group_carrier_factor
.extern group_body_factor
.extern group_body_cap
.extern group_body_cost_ops
.extern group_body_cost_bytes
.extern derive_tensor_chunk_work_ticks
.extern tensor_chunk_work_ticks
.extern tensor_chunk_elements
.extern outward_materialization_ticks
.extern sd_static_placement_required
.extern sd_preferred_l3_mask_bytes
.extern sd_preferred_l3_mask
.extern group_carrier_cap
.extern group_logical_rank
.extern group_relation_mask
.extern group_lane_factor
.extern group_rank
.extern group_form
.extern feature_bits
.extern isa_cap_bits

.global compile_tensor_source
.global json_skip_ws
.global json_parse_value
.global obj_get
.global span_eq
.global node_parse_u64
.global node_parse_f64_bits
.global jcur
.global jend
.global json_node_count
.global json_prepare_arena

# 1.3.56 code-staging aging.  Generated-code workspace is an instance fact,
# not a compiler capability.  One movable compile-time arena owns scalar, vector
# and vector-init staging; overflow marks the current AOT pass for a full retry
# with a larger arena, so no emitted/fixup pointer survives relocation.
tensor_prepare_code_arenas:
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
tensor_prepare_optimizer_arena:
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
compile_tensor_source:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [rip+tensor_output_path],rdi
    mov qword ptr [rip+tensor_code_growth_factor],16
.tensor_compile_retry:
    mov dword ptr [rip+tensor_code_overflow],0
    call tensor_prepare_code_arenas
    test eax,eax
    jnz .fail_final
    mov qword ptr [rip+json_node_count],0
    call json_prepare_arena
    test eax,eax
    jnz .fail
    mov dword ptr [rip+tensor_binding_count],0
    mov qword ptr [rip+tensor_reduce_binding],0
    mov dword ptr [rip+tensor_error],0
    mov dword ptr [rip+tensor_tolerant_fp],0
    # native probe used only to derive the exact resource graph; pass 1 is the
    # canonical machine image. No probe byte can reach the emitted ELF.
    mov dword ptr [rip+physical_plan_pass],0
    mov dword ptr [rip+group_carrier_factor],1
    mov dword ptr [rip+group_body_factor],1
    mov dword ptr [rip+group_form],GF_FORM_SCALAR
    # Mature 1.0.11 symbolic root-axis domain. This is compile-time state only.
    mov dword ptr [rip+vec_axis_root_valid],1
    mov qword ptr [rip+vec_axis_root_c],1
    mov qword ptr [rip+vec_axis_root_d],0
    mov dword ptr [rip+tensor_vector_width],1
    lea rdi,[rip+schedule_counts]
    xor eax,eax
    mov ecx,10
    rep stosd

    mov rax,[rip+source_ptr]
    mov [rip+jcur],rax
    add rax,[rip+source_length]
    mov [rip+jend],rax
    call json_parse_value
    test rax,rax
    jz .fail
    mov r12,rax
    call json_skip_ws
    mov rax,[rip+jcur]
    cmp rax,[rip+jend]
    jne .fail
    cmp qword ptr [r12],J_OBJECT
    jne .fail
    call tensor_prepare_optimizer_arena
    test eax,eax
    jnz .fail

    # format == wheelchair.tensor/1
    mov rdi,r12
    lea rsi,[rip+k_format]
    mov edx,k_format_end-k_format
    call obj_get
    test rax,rax
    jz .fail
    cmp qword ptr [rax],J_STRING
    jne .fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    lea rdx,[rip+v_tensor_format]
    mov ecx,v_tensor_format_end-v_tensor_format
    call span_eq
    test eax,eax
    jz .fail

    # Optional whole-expression tolerant floating-point contract.  Existing
    # sources remain strict unless the value is explicitly "tolerant".
    mov rdi,r12
    lea rsi,[rip+k_contracts]
    mov edx,k_contracts_end-k_contracts
    call obj_get
    test rax,rax
    jz .contracts_done
    cmp qword ptr [rax],J_OBJECT
    jne .fail
    mov rdi,rax
    lea rsi,[rip+k_floating_point]
    mov edx,k_floating_point_end-k_floating_point
    call obj_get
    test rax,rax
    jz .contracts_done
    cmp qword ptr [rax],J_STRING
    jne .fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    lea rdx,[rip+v_tolerant]
    mov ecx,v_tolerant_end-v_tolerant
    call span_eq
    test eax,eax
    jz .contracts_done
    mov dword ptr [rip+tensor_tolerant_fp],1
.contracts_done:

    # ShapeFact-N is accepted directly by the base physicalizer when the
    # physical subset is rank-1/product-1.  This prevents the human Surface from
    # having to emit a second legacy descriptor merely because this executable
    # was invoked directly instead of through whexc.
    mov dword ptr [rip+tensor_shape_active],0
    mov rdi,r12
    lea rsi,[rip+shapefn_k_root]
    mov edx,shapefn_k_root_end-shapefn_k_root
    call obj_get
    test rax,rax
    jz .shape_rank1_input
    mov rdi,r12
    call shapefn_parse_root
    test eax,eax
    jnz .fail
    cmp dword ptr [rip+tensor_shape_rank],1
    jne .fail
    cmp qword ptr [rip+tensor_shape_static_product],1
    jne .fail
    mov dword ptr [rip+tensor_shape_active],1
    jmp .shape_input_done
.shape_rank1_input:
    mov rdi,r12
    lea rsi,[rip+k_inputs]
    mov edx,k_inputs_end-k_inputs
    call obj_get
    test rax,rax
    jz .fail
    cmp qword ptr [rax],J_ARRAY
    jne .fail
    mov r13,[rax+24]
    test r13,r13
    jz .fail
    cmp qword ptr [r13],J_OBJECT
    jne .fail
    mov rdi,r13
    lea rsi,[rip+k_type]
    mov edx,k_type_end-k_type
    call obj_get
    test rax,rax
    jz .fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    lea rdx,[rip+v_u64]
    mov ecx,v_u64_end-v_u64
    call span_eq
    test eax,eax
    jz .fail
    mov rdi,r13
    lea rsi,[rip+k_min]
    mov edx,k_min_end-k_min
    call obj_get
    call node_parse_u64
    test edx,edx
    jnz .fail
    mov [rip+tensor_shape_extent_min],rax
    mov rdi,r13
    lea rsi,[rip+k_max]
    mov edx,k_max_end-k_max
    call obj_get
    call node_parse_u64
    test edx,edx
    jnz .fail
    mov [rip+tensor_shape_extent_max],rax

.shape_input_done:

    # bindings[] structural extraction.
    mov rdi,r12
    lea rsi,[rip+k_bindings]
    mov edx,k_bindings_end-k_bindings
    call obj_get
    test rax,rax
    jz .fail
    cmp qword ptr [rax],J_ARRAY
    jne .fail
    mov r14,[rax+24]
    # Binding metadata is compile-time structure. Count the actual canonical
    # binding list and materialize exactly that many records instead of owning a
    # sixteen-entry compiler table.
    xor edi,edi
    mov rbx,r14
.tb_count_bindings:
    test rbx,rbx
    jz .tb_count_done
    inc edi
    jz .fail
    mov rbx,[rbx+32]
    jmp .tb_count_bindings
.tb_count_done:
    call tensor_prepare_binding_arena
    test eax,eax
    jnz .fail
.bind_loop:
    test r14,r14
    jz .bindings_done
    cmp qword ptr [r14],J_OBJECT
    jne .fail
    mov eax,dword ptr [rip+tensor_binding_count]
    cmp eax,dword ptr [rip+tensor_binding_capacity]
    jae .fail
    mov ecx,eax
    shl rcx,6
    mov r15,[rip+tensor_bindings_ptr]
    add r15,rcx
    # name
    mov rdi,r14
    lea rsi,[rip+k_name]
    mov edx,k_name_end-k_name
    call obj_get
    test rax,rax
    jz .fail
    cmp qword ptr [rax],J_STRING
    jne .fail
    mov rcx,[rax+8]
    mov [r15+0],rcx
    mov rcx,[rax+16]
    mov [r15+8],rcx
    # op
    mov rdi,r14
    lea rsi,[rip+k_op]
    mov edx,k_op_end-k_op
    call obj_get
    test rax,rax
    jz .fail
    mov rbx,rax
    mov rdi,[rbx+8]
    mov rsi,[rbx+16]
    lea rdx,[rip+v_map]
    mov ecx,v_map_end-v_map
    call span_eq
    test eax,eax
    jz .try_reduce
    mov dword ptr [r15+16],OP_MAP
    # map type must f64
    mov rdi,r14
    lea rsi,[rip+k_type]
    mov edx,k_type_end-k_type
    call obj_get
    test rax,rax
    jz .fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    lea rdx,[rip+v_f64]
    mov ecx,v_f64_end-v_f64
    call span_eq
    test eax,eax
    jz .fail
    mov dword ptr [r15+20],TYPE_F64
    jmp .binding_common
.try_reduce:
    mov rdi,[rbx+8]
    mov rsi,[rbx+16]
    lea rdx,[rip+v_reduce]
    mov ecx,v_reduce_end-v_reduce
    call span_eq
    test eax,eax
    jz .fail
    mov dword ptr [r15+16],OP_REDUCE
    mov dword ptr [r15+20],TYPE_F64
    # kind=sum
    mov rdi,r14
    lea rsi,[rip+k_kind]
    mov edx,k_kind_end-k_kind
    call obj_get
    test rax,rax
    jz .fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    lea rdx,[rip+v_sum]
    mov ecx,v_sum_end-v_sum
    call span_eq
    test eax,eax
    jz .fail
    # accumulator.mode=tolerant
    mov rdi,r14
    lea rsi,[rip+k_accumulator]
    mov edx,k_accumulator_end-k_accumulator
    call obj_get
    test rax,rax
    jz .fail
    mov rdi,rax
    lea rsi,[rip+k_mode]
    mov edx,k_mode_end-k_mode
    call obj_get
    test rax,rax
    jz .fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    lea rdx,[rip+v_tolerant]
    mov ecx,v_tolerant_end-v_tolerant
    call span_eq
    test eax,eax
    jz .fail
    mov [rip+tensor_reduce_binding],r15
.binding_common:
    # one axis: axes[0].name
    mov rdi,r14
    lea rsi,[rip+k_axes]
    mov edx,k_axes_end-k_axes
    call obj_get
    test rax,rax
    jz .fail
    cmp qword ptr [rax],J_ARRAY
    jne .fail
    mov rbx,[rax+24]
    test rbx,rbx
    jz .fail
    cmp qword ptr [rbx+32],0
    jne .fail                    # exactly one axis in current structural slice
    mov rdi,rbx
    lea rsi,[rip+k_name]
    mov edx,k_name_end-k_name
    call obj_get
    test rax,rax
    jz .fail
    mov rcx,[rax+8]
    mov [r15+24],rcx
    mov rcx,[rax+16]
    mov [r15+32],rcx
    # extent.var must n (structural single external extent)
    mov rdi,rbx
    lea rsi,[rip+k_extent]
    mov edx,k_extent_end-k_extent
    call obj_get
    test rax,rax
    jz .fail
    mov rdi,rax
    lea rsi,[rip+k_var]
    mov edx,k_var_end-k_var
    call obj_get
    test rax,rax
    jz .fail
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call tensor_domain_var_match
    test eax,eax
    jz .fail
    # expr
    mov rdi,r14
    lea rsi,[rip+k_expr]
    mov edx,k_expr_end-k_expr
    call obj_get
    test rax,rax
    jz .fail
    mov [r15+40],rax
    inc dword ptr [rip+tensor_binding_count]
    mov r14,[r14+32]
    jmp .bind_loop
.bindings_done:
    mov r15,[rip+tensor_reduce_binding]
    test r15,r15
    jz .fail

    # Mature WHEX tensor lane has no scalar-oracle compilation.  Building the
    # same tensor recursively as a scalar evaluator before parallel lowering was
    # dead work, imposed an artificial recursion ceiling, and violated the rule
    # that independent tensor semantics must not be serialized internally.
    # Keep the legacy buffer cursor at zero length for image-layout compatibility;
    # no scalar machine instruction is generated or copied into the final ELF.
    mov rax,[rip+tensor_eval_base]
    mov [rip+emit_ptr],rax
    lea rdi,[rip+schedule_counts]
    xor eax,eax
    mov ecx,10
    rep stosd
    mov dword ptr [rip+vector_schedule_attempted],1

    # Parallel-contract gate. Tensor/WHEX topology is semantically independent
    # across its axis domain, so the backend is forbidden to turn a failed
    # parallel realization into a hidden scalar evaluator.  The semantic gate is
    # capability-based: the current 512-bit realizer requires the tensor512 base
    # capability set, while extension-only operations may use native or proven
    # parallel synthesized recipes. Missing base capability is an explicit compile
    # rejection, never a semantic fallback.
    mov eax,dword ptr [rip+isa_cap_bits]
    mov ecx,ISA_CAP_TENSOR256_BASE
    and eax,ecx
    cmp eax,ecx
    jne .fail
.physical_codegen_pass:
    mov dword ptr [rip+vector_schedule_attempted],1
    lea rdi,[rip+schedule_counts]
    xor eax,eax
    mov ecx,10
    rep stosd
    mov rax,[rip+tensor_vec_base]
    mov [rip+vec_emit_ptr],rax
    mov rax,[rip+tensor_vec_init_base]
    mov [rip+vec_init_emit_ptr],rax
    mov dword ptr [rip+physical_realize_group_body],1
    mov dword ptr [rip+physical_realize_group_carriers],1
    cmp dword ptr [rip+physical_plan_pass],0
    je .physical_shape_ready
    mov eax,dword ptr [rip+group_body_factor]
    test eax,eax
    jnz .physical_body_shape_ready
    mov eax,1
.physical_body_shape_ready:
    mov dword ptr [rip+physical_realize_group_body],eax
.physical_carrier_shape:
    cmp dword ptr [rip+group_carrier_factor],2
    jb .physical_shape_ready
    mov dword ptr [rip+physical_realize_group_carriers],2
.physical_shape_ready:
    mov dword ptr [rip+vec_reg_mask],0x00000F3E  # YMM1..5,YMM8..11 short-lived arithmetic temps
    mov dword ptr [rip+vec13_free],0      # YMM13 remains native256 scalar/tail scratch
    mov dword ptr [rip+vec11_borrowed],0
    # Native256 has no high YMM bank.  A two-body episode therefore owns YMM11
    # as the second reduction carrier, but only when pass 0 proves the ordinary
    # expression allocator never needed it.
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .physical_carrier_reservation_ready
    btr dword ptr [rip+vec_reg_mask],11
.physical_carrier_reservation_ready:
    # The old copied high-register ownership pool is absent on native256; topology CSE and persistent
    # cross-vector induction.  Induction carriers reserve only actually-free
    # registers, so general expressions never lose capacity merely because the
    # feature exists.
    mov dword ptr [rip+vec_fused_mode],1
    mov dword ptr [rip+vec_product_subtract_contractions],0
    mov dword ptr [rip+vec_induct_count],0
    mov dword ptr [rip+vec_const_count],0
    mov dword ptr [rip+vec_fixup_count],0
    mov rdi,[rip+vec_const_reg_ptr]
    xor eax,eax
    mov ecx,512
    rep stosd
    # Generate one fused vector episode kernel per tensor expression.  The
    # generated kernel owns the complete chunk loop.  Boundary-sensitive axis
    # predicates are partitioned into two vector regions rather than poisoning
    # the whole domain: global boundary blocks use the fully general vector body,
    # while blocks proven strictly inside (0,n-1) use INTERIOR_PROVEN lowering.
    # Both paths are width-8 AVX-512 and converge before the masked reduction;
    # there is no scalar boundary oracle or per-element fallback.
    mov dword ptr [rip+vec_interior_mode],0
    mov dword ptr [rip+vec_axis_reg],6
    # Entry jumps forward to the initialization island emitted after the hot
    # loop. This lets affine induction carriers be discovered lazily while the
    # loop bodies are lowered.
    call vec_emit_jmp_placeholder
    test rax,rax
    jz .fail
    mov [rip+vec_fused_entry_disp],rax
    mov rax,[rip+vec_emit_ptr]
    mov [rip+vec_fused_loop_start],rax

    # 1.3.66 Group aging: emission consumes the canonical GroupFact body factor
    # directly. A zero finite-domain cap is a ShapeFact statement, not a second
    # codegen authority. Unbounded streams naturally realize the body already
    # priced by Physical Reality (normally the proved recurrence relation), and
    # body==1 is the mature Vector degeneration.
    # Canonical operation-native Group episode for native256. Probe one real YMM
    # packet, then let the common GroupFact body factor own canonical width.
    # Full groups share one back-edge; any remainder remains a masked YMM tail.
    cmp dword ptr [rip+physical_realize_group_body],1
    jbe .vec_group_single_episode
    call vec_emit_group_guard
    test rax,rax
    jz .fail
    mov [rip+vec_fused_tail_disp],rax
    mov rax,[rip+vec_emit_ptr]
    mov [rip+vec_group_body_start],rax
    mov dword ptr [rip+vec_group_emit_index],0
.vec_group_emit_loop:
    call emit_fused_vector_body
    test eax,eax
    jnz .fail
    xor edi,edi
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_group_carrier_ready
    mov eax,dword ptr [rip+vec_group_emit_index]
    and eax,1
    mov edi,eax
.vec_group_carrier_ready:
    call emit_fused_reduce_carrier_full
    test eax,eax
    jnz .fail
    call emit_fused_advance4_group_coordinates
    test eax,eax
    jnz .fail
    inc dword ptr [rip+vec_group_emit_index]
    mov eax,dword ptr [rip+vec_group_emit_index]
    cmp eax,dword ptr [rip+physical_realize_group_body]
    jb .vec_group_emit_loop
    call vec_emit_group_countdown_backedge
    test eax,eax
    jnz .fail
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_tail_disp]
    call vec_patch_rel32
    test eax,eax
    jnz .fail
    mov rax,[rip+vec_emit_ptr]
    mov [rip+vec_fused_tail_loop_start],rax
    lea rdi,[rip+vec_group_test_remaining_fragment]
    mov esi,vec_group_test_remaining_fragment_end-vec_group_test_remaining_fragment
    call vec_emit_bytes
    test eax,eax
    jnz .fail
    call vec_emit_je_placeholder
    test rax,rax
    jz .fail
    mov [rip+vec_fused_empty_finish_disp],rax
    call emit_fused_vector_body
    test eax,eax
    jnz .fail
    xor edi,edi
    call emit_fused_reduce_carrier
    test eax,eax
    jnz .fail
    call emit_fused_advance4
    test rax,rax
    jz .fail
    mov [rip+vec_fused_finish_disp],rax
    mov rsi,[rip+vec_fused_tail_loop_start]
    call vec_emit_jmp_to
    test eax,eax
    jnz .fail
    jmp .vec_group_patch_finish


.vec_stream_vector_episode:
    # Measure the complete one-Vector episode during probe pass. Canonical pass
    # may realize the proved second reduction carrier exactly as the historical
    # mature Vector path did, with one back-edge and no Group-tail fabric.
    mov rax,[rip+vec_emit_ptr]
    mov [rip+vec_group_cost_start_ptr],rax
    xor edx,edx
    xor ecx,ecx
    lea rax,[rip+schedule_counts]
.vec_stream_cost_before_loop:
    cmp ecx,10
    jae .vec_stream_cost_before_done
    add edx,dword ptr [rax+rcx*4]
    inc ecx
    jmp .vec_stream_cost_before_loop
.vec_stream_cost_before_done:
    mov dword ptr [rip+group_body_cost_ops],edx
    call emit_fused_vector_body
    test eax,eax
    jnz .fail
    xor edi,edi
    call emit_fused_reduce_carrier
    test eax,eax
    jnz .fail
    call emit_fused_advance4
    test rax,rax
    jz .fail
    mov [rip+vec_fused_finish_disp],rax

    # Exact one-Vector probe footprint.  This is the cost authority used by
    # Physical Reality; a later second recurrence body does not contaminate it.
    mov rax,[rip+vec_emit_ptr]
    sub rax,qword ptr [rip+vec_group_cost_start_ptr]
    mov dword ptr [rip+group_body_cost_bytes],eax
    xor edx,edx
    xor ecx,ecx
    lea rax,[rip+schedule_counts]
.vec_stream_cost_after_loop:
    cmp ecx,10
    jae .vec_stream_cost_after_done
    add edx,dword ptr [rax+rcx*4]
    inc ecx
    jmp .vec_stream_cost_after_loop
.vec_stream_cost_after_done:
    sub edx,dword ptr [rip+group_body_cost_ops]
    jns .vec_stream_cost_store
    xor edx,edx
.vec_stream_cost_store:
    # Add the unavoidable per-Vector structural front-end operations that do
    # not appear in expression schedule_counts: reduction, remaining update,
    # completion branch, scalar index advance, and vector-axis advance.  Live
    # induction carriers each contribute one additional vector update.
    inc edx
    inc edx
    inc edx
    inc edx
    inc edx
    add edx,dword ptr [rip+vec_induct_count]
    mov dword ptr [rip+group_body_cost_ops],edx

    cmp dword ptr [rip+physical_realize_group_body],2
    jne .vec_stream_bodies_done
    call emit_fused_vector_body
    test eax,eax
    jnz .fail
    xor edi,edi
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_stream_body1_carrier_ready
    mov edi,1
.vec_stream_body1_carrier_ready:
    call emit_fused_reduce_carrier
    test eax,eax
    jnz .fail
    call emit_fused_advance4
    test rax,rax
    jz .fail
    mov [rip+vec_fused_finish_disp1],rax
.vec_stream_bodies_done:
    mov rsi,[rip+vec_fused_loop_start]
    call vec_emit_jmp_to
    test eax,eax
    jnz .fail

    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_finish_disp]
    call vec_patch_rel32
    test eax,eax
    jnz .fail
    cmp dword ptr [rip+physical_realize_group_body],2
    jne .vec_finish_jump_patched
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_finish_disp1]
    call vec_patch_rel32
    test eax,eax
    jnz .fail
    jmp .vec_finish_jump_patched

.vec_group_single_episode:
    mov rax,[rip+vec_emit_ptr]
    mov [rip+vec_group_cost_start_ptr],rax
    xor edx,edx
    xor ecx,ecx
    lea rax,[rip+schedule_counts]
.vec_group_cost_before_loop:
    cmp ecx,10
    jae .vec_group_cost_before_done
    add edx,dword ptr [rax+rcx*4]
    inc ecx
    jmp .vec_group_cost_before_loop
.vec_group_cost_before_done:
    mov dword ptr [rip+group_body_cost_ops],edx
    call emit_fused_vector_body
    test eax,eax
    jnz .fail
    xor edi,edi
    call emit_fused_reduce_carrier
    test eax,eax
    jnz .fail
    call emit_fused_advance4
    test rax,rax
    jz .fail
    mov [rip+vec_fused_finish_disp],rax
    mov rax,[rip+vec_emit_ptr]
    sub rax,qword ptr [rip+vec_group_cost_start_ptr]
    mov dword ptr [rip+group_body_cost_bytes],eax
    xor edx,edx
    xor ecx,ecx
    lea rax,[rip+schedule_counts]
.vec_group_cost_after_loop:
    cmp ecx,10
    jae .vec_group_cost_after_done
    add edx,dword ptr [rax+rcx*4]
    inc ecx
    jmp .vec_group_cost_after_loop
.vec_group_cost_after_done:
    sub edx,dword ptr [rip+group_body_cost_ops]
    jns .vec_group_cost_store
    xor edx,edx
.vec_group_cost_store:
    # Add the unavoidable per-Vector structural front-end operations that do
    # not appear in expression schedule_counts: reduction, remaining update,
    # completion branch, scalar index advance, and vector-axis advance.  Live
    # induction carriers each contribute one additional vector update.
    inc edx
    inc edx
    inc edx
    inc edx
    inc edx
    add edx,dword ptr [rip+vec_induct_count]
    mov dword ptr [rip+group_body_cost_ops],edx
    mov rsi,[rip+vec_fused_loop_start]
    call vec_emit_jmp_to
    test eax,eax
    jnz .fail

.vec_group_patch_finish:
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_finish_disp]
    call vec_patch_rel32
    test eax,eax
    jnz .fail
    cmp dword ptr [rip+physical_realize_group_body],1
    jbe .vec_finish_jump_patched
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_empty_finish_disp]
    call vec_patch_rel32
    test eax,eax
    jnz .fail
.vec_finish_jump_patched:
    cmp dword ptr [rip+vec_product_subtract_contractions],0
    je .vec_finish_frozen_recipe
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_finish_resident_single
    lea rdi,[rip+vec_fused_finish_resident_dual_fragment]
    mov esi,vec_fused_finish_resident_dual_fragment_end-vec_fused_finish_resident_dual_fragment
    jmp .vec_finish_resident_emit
.vec_finish_resident_single:
    lea rdi,[rip+vec_fused_finish_resident_fragment]
    mov esi,vec_fused_finish_resident_fragment_end-vec_fused_finish_resident_fragment
.vec_finish_resident_emit:
    call vec_emit_bytes
    test eax,eax
    jnz .fail
    jmp .vec_finish_recipe_done
.vec_finish_frozen_recipe:
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_finish_frozen_single
    lea rdi,[rip+vec_fused_finish_dual_fragment]
    mov esi,vec_fused_finish_dual_fragment_end-vec_fused_finish_dual_fragment
    jmp .vec_finish_frozen_emit
.vec_finish_frozen_single:
    lea rdi,[rip+vec_fused_finish_fragment]
    mov esi,vec_fused_finish_fragment_end-vec_fused_finish_fragment
.vec_finish_frozen_emit:
    call vec_emit_bytes
    test eax,eax
    jnz .fail
.vec_finish_recipe_done:
    # Initialization island. Runtime arguments are rdi=n, rsi=start, rdx=end.
    # Native256 immutable constants come from the RIP pool; here only
    # episode-varying state is established.
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_entry_disp]
    call vec_patch_rel32
    test eax,eax
    jnz .fail
    cmp dword ptr [rip+vec_product_subtract_contractions],0
    je .vec_init_frozen_recipe
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_init_resident_single
    lea rdi,[rip+vec_fused_init_resident_dual_fragment]
    mov esi,vec_fused_init_resident_dual_fragment_end-vec_fused_init_resident_dual_fragment
    jmp .vec_init_resident_emit
.vec_init_resident_single:
    lea rdi,[rip+vec_fused_init_resident_fragment]
    mov esi,vec_fused_init_resident_fragment_end-vec_fused_init_resident_fragment
.vec_init_resident_emit:
    call vec_emit_bytes
    test eax,eax
    jnz .fail
    jmp .vec_init_recipe_done
.vec_init_frozen_recipe:
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_init_frozen_single
    lea rdi,[rip+vec_fused_init_dual_fragment]
    mov esi,vec_fused_init_dual_fragment_end-vec_fused_init_dual_fragment
    jmp .vec_init_frozen_emit
.vec_init_frozen_single:
    lea rdi,[rip+vec_fused_init_fragment]
    mov esi,vec_fused_init_fragment_end-vec_fused_init_fragment
.vec_init_frozen_emit:
    call vec_emit_bytes
    test eax,eax
    jnz .fail
.vec_init_recipe_done:
    lea rdi,[rip+vec_prefix_fragment]
    mov esi,vec_prefix_fragment_end-vec_prefix_fragment
    call vec_emit_bytes
    test eax,eax
    jnz .fail
    # Initialize every affine carrier from the initial root vector exactly once.
    xor r12d,r12d
.vec_fused_init_induct:
    cmp r12d,dword ptr [rip+vec_induct_count]
    jae .vec_fused_init_done
    lea rax,[rip+vec_induct_coeff]
    mov rdx,qword ptr [rax+r12*8]
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,6
    call vec_mul_const_strength
    test eax,eax
    jz .vec_fused_init_next
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    call vec_const_intern
    cmp eax,-1
    je .fail
    mov edx,eax
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,6
    call vec_vpmullq_mem_const
    test eax,eax
    jnz .fail
.vec_fused_init_next:
    inc r12d
    jmp .vec_fused_init_induct
.vec_fused_init_done:
    mov rsi,[rip+vec_fused_loop_start]
    call vec_emit_jmp_to
    test eax,eax
    jnz .fail
    # Worker-constant initialization remains once-per-worker and therefore
    # resident across every fused episode executed by that worker.
    mov edi,0xC3
    call vec_init_emit_u8
    test eax,eax
    jnz .fail
    call vec_finalize_constants
    test eax,eax
    jnz .fail
    mov dword ptr [rip+tensor_vector_width],4

    # No tensor scalar fallback exists after this point. A tensor program that
    # reached native realization must have preserved its independent vector
    # width all the way through lowering.
    cmp dword ptr [rip+tensor_vector_width],4
    jne .fail
.schedule_counts_ready:

    # 1.3.0 Physical DAG / Semantic ISA realization. The first native lowering
    # is deliberately disposable: it exposes the exact instruction-resource
    # structure without committing bytes to the output image. The scheduler runs
    # here, before the canonical pass. The second pass restores that plan and
    # encodes the final ISA directly.
    cmp dword ptr [rip+physical_plan_pass],0
    jne .physical_plan_realize

    # Native256 two-body realization is legal only when pass-0 register pressure
    # never reached YMM11. The plan therefore comes from actual allocator demand,
    # not a workload name or runtime profitability switch.
    mov dword ptr [rip+group_carrier_cap],1
    cmp dword ptr [rip+tensor_tolerant_fp],0
    je .physical_carrier_cap_ready
    mov dword ptr [rip+group_carrier_cap],2
.physical_carrier_cap_ready:
    mov dword ptr [rip+group_body_cap],0
    # 1.3.61 Automatic Grouping input facts. No user syntax selects a group.
    # ShapeFact-N owns logical axes; scalar operation analysis contributes only
    # relation/affinity facts. Group recovery is therefore workload-name blind.
    mov eax,dword ptr [rip+tensor_shape_rank]
    test eax,eax
    jnz 1f
    mov eax,1
1:  mov dword ptr [rip+group_logical_rank],eax
    mov dword ptr [rip+group_lane_factor],TENSOR_PHYSICAL_LANES
    mov dword ptr [rip+group_relation_mask],GF_REL_INDEPENDENT | GF_REL_REDUCTION
    cmp dword ptr [rip+vec_operator_compositions],0
    je 2f
    or dword ptr [rip+group_relation_mask],GF_REL_OPERATOR
2:  cmp dword ptr [rip+vec_induct_count],0
    je 3f
    or dword ptr [rip+group_relation_mask],GF_REL_AFFINE
3:
    call synthesize_resource_schedule

    # Resource scheduling proves a body factor. Exact allocator pressure then
    # closes the legal reduction-carrier relation. Only after both are known is
    # the operation-native GroupFact formed.
    mov dword ptr [rip+group_carrier_factor],1
    cmp dword ptr [rip+tensor_tolerant_fp],0
    je .physical_plan_width_done
    cmp dword ptr [rip+vec11_borrowed],0
    jne .physical_plan_width_done
    mov dword ptr [rip+group_carrier_factor],2
.physical_plan_width_done:
    call synthesize_group_fact
    lea rsi,[rip+schedule_counts]
    lea rdi,[rip+physical_plan_counts]
    mov ecx,10
    rep movsd
    mov dword ptr [rip+physical_plan_pass],1
    jmp .physical_codegen_pass

.physical_plan_realize:
    # Canonical codegen is governed by the already-computed physical plan.
    # No second scheduling pass is allowed to describe bytes after the fact.

    # 1.3.10: the former executor-partition condensation authority is retired.
    # Canonical causal subtrees own reduction structure; capacity never changes
    # which mathematical work exists.
    # 1.3.8 strict reduction repair: only tolerant FP may condense
    # cross-executor communication. Strict FP preserves the exact q=1
    # chunk-reduction tree across executor counts.
    # The canonical causal tree owns reduction structure directly; there is no
    # compatibility communication-control field in the runtime image.
.communication_plan_ready:

    # Emit runtime template and patch the structural plan.
    call emit_tensor_image
    test eax,eax
    jnz .fail
    xor eax,eax
    jmp .done
.fail:
    cmp dword ptr [rip+tensor_code_overflow],0
    je .fail_final
    mov rax,qword ptr [rip+tensor_code_growth_factor]
    shl rax,1
    jz .fail_final
    mov qword ptr [rip+tensor_code_growth_factor],rax
    jmp .tensor_compile_retry
.fail_final:
    mov eax,1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- JSON DOM parser ----------------
json_skip_ws:
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
json_prepare_arena:
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

new_node:
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
json_parse_string_raw:
    call json_skip_ws
    mov r8,[rip+jcur]
    cmp r8,[rip+jend]
    jae .jps_fail
    cmp byte ptr [r8],'"'
    jne .jps_fail
    inc r8
    mov rax,r8
.jps_loop:
    cmp r8,[rip+jend]
    jae .jps_fail
    mov dl,byte ptr [r8]
    cmp dl,'"'
    je .jps_done
    cmp dl,'\\'
    je .jps_fail                 # canonical structural slice has no escapes
    inc r8
    jmp .jps_loop
.jps_done:
    mov rcx,r8
    sub rcx,rax
    inc r8
    mov [rip+jcur],r8
    ret
.jps_fail:
    xor eax,eax
    xor ecx,ecx
    mov dword ptr [rip+tensor_error],1
    ret

json_parse_value:
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
bytes_eq_n:
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
span_eq:
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
obj_get:
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
node_parse_u64:
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
node_u64_to_f64:
    test rax,rax
    js .nu64_large
    cvtsi2sd xmm0,rax
    ret
.nu64_large:
    mov rdx,rax
    and edx,1
    shr rax,1
    or rax,rdx
    cvtsi2sd xmm0,rax
    addsd xmm0,xmm0
    ret

# parse f64 number node in rax -> rax IEEE bits, edx error.
# Decimal mantissa/scale are accumulated as unsigned u64. Values outside that
# exact structural slice are rejected instead of silently wrapping.
.include "compiler/numeric_literal_parser.inc"

# Exact compile-time binding arena.  Binding cardinality is represented by the
# canonical list itself; no independent sixteen-entry frontend ceiling remains.
tensor_prepare_binding_arena:
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
find_binding:
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

# ---------------- register-native expression emitter ----------------
# Generated-runtime register convention:
#   R8  = current coordinate
#   R9  = external extent n
#   RAX/RDX = reserved implicit divide/scratch
#   GPR pool = RCX,RSI,RDI,R10,R11
#   XMM pool = XMM1..XMM11; XMM0 is top-level result

alloc_gpr:
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
free_gpr:
    bts dword ptr [rip+emit_gpr_mask],edi
    ret
alloc_xmm:
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
free_xmm:
    bts dword ptr [rip+emit_xmm_mask],edi
    ret

# Instruction encoders. Return eax=0 success, 1 failure.
# gen_mov_ri64(edi=dst, rsi=imm)
gen_mov_ri64:
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
gen_rr_opcode:
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
gen_mov_rr:
    mov edx,esi
    mov esi,edi
    mov edi,0x89
    jmp gen_rr_opcode

# gen_alu_ri32(edi=extension, esi=dst, edx=imm32)
gen_alu_ri32:
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
gen_imul_rr:
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
gen_imul_ri32:
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
gen_div_reg:
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
gen_cvtsi2sd:
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
gen_movq_xmm_gpr:
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
gen_sse_rr:
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

# gen_cmp_sete(edi=dst, esi=lhs, edx=rhs)
gen_cmp_sete:
    push rbx
    mov ebx,edi
    mov edi,0x39
    # cmp lhs,rhs => dst_rm=lhs src=rhs
    push rbx
    mov edi,0x39
    call gen_rr_opcode
    pop rbx
    mov edi,0x0F; call emit_u8
    mov edi,0x94; call emit_u8
    mov edi,0xC0; call emit_u8          # sete al
    mov eax,ebx; shr eax,3; and eax,1; shl eax,2
    test eax,eax
    jz .gcs_no_rex
    or eax,0x40
    mov edi,eax; call emit_u8
.gcs_no_rex:
    mov edi,0x0F; call emit_u8
    mov edi,0xB6; call emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call emit_u8
    pop rbx
    ret

# gen_test_rr(edi=reg): test reg,reg
gen_test_rr:
    mov edx,edi
    mov esi,edi
    mov edi,0x85
    jmp gen_rr_opcode

# gen_cmovz(edi=dst,esi=src)
gen_cmovz:
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
expr_literal_u64:
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
expr_literal_f64_bits:
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

# match mul(f64_literal, expr) or mul(expr, f64_literal).
# rdi=expr -> rax=literal bits, rdx=other expr, ecx=1 success; ecx=0 otherwise.
expr_mul_literal_other:
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
recip_pow2_f64_bits:
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
tolerant_recip_f64_bits:
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
gen_load_f64_bits:
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
emit_int_reg:
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
    # eq
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax; jz .eir_select
    call alloc_gpr; cmp eax,-1; je .eir_fail; mov ebx,eax
    call alloc_gpr; cmp eax,-1; je .eir_free_b_fail; mov r14d,eax
    mov rdi,r15; mov esi,ebx; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov r15,[r15+32]; test r15,r15; jz .eir_free2_fail
    mov rdi,r15; mov esi,r14d; call emit_int_reg; test eax,eax; jnz .eir_free2_fail
    mov edi,r13d; mov esi,ebx; mov edx,r14d; call gen_cmp_sete
    mov edi,r14d; call free_gpr; mov edi,ebx; call free_gpr
    inc dword ptr [rip+schedule_counts+4*4] # int compare
    xor eax,eax; jmp .eir_done
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
emit_float_reg:
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
    test eax,eax; jz .efr_binary
    cmp qword ptr [r15+32],0; jne .efr_fail
    mov rdi,r15; mov esi,r13d; call emit_float_reg; test eax,eax; jnz .efr_fail
    mov edi,r13d; mov esi,r13d; call vec_roundpd_trunc_scalar_reg
    test eax,eax; jnz .efr_fail
    inc dword ptr [rip+schedule_counts+4*3]
    xor eax,eax; jmp .efr_done
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
# Runtime vector convention: YMM6 = [k..k+3], YMM7 = broadcast n.
# YMM0 is result; YMM12..15 are reserved by the native256 runtime/episode ABI.

vec_alloc:
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
vec_free:
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

vec_init_emit_u8:
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

# Constant initialization is not a native256 runtime concept; constants are loaded from the shared RIP pool.

vec_emit_u8:
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

vec_emit_bytes:
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
vec_emit_jmp_placeholder:
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

vec_emit_jbe_placeholder:
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
vec_emit_jb_placeholder:
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

vec_emit_je_placeholder:
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

vec_emit_jae_placeholder:
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
vec_patch_rel32:
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
vec_emit_jmp_to:
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
vec_vex2_rrr:
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
vec_sqrtpd:
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

vec_vex3_0f38_rrr:
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
# ingress/egress so native256 never invents YMM16+ carriers.
vec_mov_ext:
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

vec_broadcast_imm64:
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
vec_const_intern:
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
# vec_const_get_reg(rsi=qword bits) -> -1.
# Native256 intentionally has no immutable resident-register domain. Preserve
# the canonical pool-intern side effect, then report that no register exists.
vec_const_get_reg:
    call vec_const_intern
    mov eax,-1
    ret

# vec_emit_const_load_index(edi=dst zmm, r13d=constant index)
vec_emit_const_load_index:
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

vec_finalize_constants:
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
vec_vpmullq:
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

vec_vpmullq_native:
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
vec_vpmuludq:
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
vec_vpsllq_imm:
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

vec_vpsrlq_imm:
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

vec_vpaddq_mem_const:
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

vec_vpandq_mem_const:
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

vec_vpmullq_mem_const:
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

vec_vpmullq_mem_const_native:
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
vec_mul_const_strength:
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

vec_vmulpd_mem_const:
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

vec_vfmadd231pd:
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

vec_vfnmadd231pd:
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
vec_vfmadd231pd_mem_const:
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

vec_vpminuq:
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

vec_vcvtqq2pd:
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
vec_vcvtqq2pd_native:
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
vec_vcvtqq2pd_synth:
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

vec_vpmovqd_ymm_from_zmm:
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

vec_vcvtdq2pd_zmm_from_ymm:
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

vec_vpsrld_imm:
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
vec_roundpd_trunc_scalar_reg:
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

vec_trunc_nonneg_pd_to_u64:
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

vec_trunc_nonneg_pd_to_u64_synth:
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
vec_vrndscalepd_trunc:
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

vec_vaddpd_mem_const:
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

vec_vcvttpd2qq:
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
vec_cmp_eq_maskvec:
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

expr_affine_axis_u64:
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
vec_interior_affine_residue_safe:
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
expr_affine_axis_interior_u64:
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

# Compose local index a*x+b with current logical axis c*root+d. The physical
# root axis remains ZMM6 because this mature tree deliberately retains the
# proven 1.0.9 runtime ABI/prefix instead of silently assuming the later
# cross-vector recurrence ABI.
vec_axis_compose_from_index:
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

# Emit the affine value local_c*(logical axis)+local_d from the physical root
# ZMM6. In the fused-episode ABI, proven nontrivial composed coefficients may
# use persistent induction carriers from the real YMM0..15 ownership domain.
# Resource requirements are preflighted before the first hot evaluator byte is
# emitted, preventing partial-code fallback corruption.
#
# Mature 1.0.11 constant-pressure rule: exhausting the six resident immutable
# ZMM constant slots must never erase a proven symbolic root coordinate.  A
# non-resident multiplier/offset is kept in the existing read-only constant
# pool and consumed through EVEX qword broadcast memory operands.  Therefore
# register pressure changes only the physical realization, never the algebra.
#
# Operand encoding in r15d/r12d during preflight:
#   0x7fffffff       no explicit operand needed
#   0..31            resident immutable ZMM register
#   0x80000000|idx   constant-pool qword broadcast index
# edi=dst, rsi=local_c, rdx=local_d -> eax=0/1.
vec_emit_affine_current:
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
expr_affine_modn_form:
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
vec_modn_fixed_normalize_d:
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
expr_index_key_u64:
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
vec_save_axis:
    lea rdi,[rip+vec_save_axis_code]
    mov esi,vec_save_axis_code_end-vec_save_axis_code
    jmp vec_emit_bytes
vec_restore_axis:
    lea rdi,[rip+vec_restore_axis_code]
    mov esi,vec_restore_axis_code_end-vec_restore_axis_code
    jmp vec_emit_bytes

# Native256 has no persistent high-register CSE domain.
# vec_try_int_source(rdi=expr) -> eax physical YMM source or -1.
# Pure leaves can feed a 3-operand vector instruction directly without a copy node.
vec_try_int_source:
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
vec_try_float_source:
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
emit_vec_int:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13d,esi
    mov rdi,r12; call expr_literal_u64
    test edx,edx
    jnz .evi_axis
    mov rsi,rax; mov edi,r13d; call vec_broadcast_imm64
    jmp .evi_done
.evi_axis:
    mov rdi,r12; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .evi_var
    mov edi,r13d; mov esi,dword ptr [rip+vec_axis_reg]; call vec_mov_ext
    jmp .evi_ok
.evi_var:
    mov rdi,r12; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .evi_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_domain_var_match
    test eax,eax; jz .evi_fail
    mov edi,r13d; mov esi,7; call vec_mov_ext
    jmp .evi_ok
.evi_op:
    # Recover an affine coordinate as one structural object before recursive
    # lowering. This is general axis algebra, not a workload-specific case.
    cmp dword ptr [rip+vec_axis_root_valid],1
    jne .evi_op_regular
    mov rdi,r12
    call expr_affine_axis_u64
    test ecx,ecx
    jz .evi_op_regular
    mov edi,r13d
    mov rsi,rax
    call vec_emit_affine_current
    test eax,eax
    jz .evi_ok
.evi_op_regular:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .evi_fail
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .evi_fail
    mov r15,[rax+24]; test r15,r15; jz .evi_fail
    # eq: direct leaves feed the compare without synthetic moves.
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax; jz .evi_select
    mov rbx,[r15+32]; test rbx,rbx; jz .evi_fail
    mov rdi,r15; call vec_try_int_source
    mov r12d,eax
    cmp eax,-1; jne .evi_eq_lhs_ready
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov r12d,r13d
.evi_eq_lhs_ready:
    mov rdi,rbx; call vec_try_int_source
    mov r14d,eax
    cmp eax,-1; jne .evi_eq_rhs_ready
    call vec_alloc; cmp eax,-1; je .evi_fail; mov r14d,eax
    mov rdi,rbx; mov esi,r14d; call emit_vec_int; test eax,eax; jnz .evi_eq_rhs_temp_fail
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call vec_cmp_eq_maskvec
    mov edi,r14d; call vec_free
    jmp .evi_ok
.evi_eq_rhs_temp_fail:
    mov edi,r14d; call vec_free
    jmp .evi_fail
.evi_eq_rhs_ready:
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call vec_cmp_eq_maskvec
    jmp .evi_ok
.evi_select:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .evi_mod
.evi_select_general:
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov edi,r13d; call vec_stack_spill_push_128
    mov r15,[r15+32]; test r15,r15; jz .evi_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov edi,r13d; call vec_stack_spill_push_128
    mov r15,[r15+32]; test r15,r15; jz .evi_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    call vec_alloc; cmp eax,-1; je .evi_fail; mov ebx,eax
    mov edi,ebx; call vec_stack_spill_pop_128
    mov edi,13; call vec_stack_spill_pop_128
    mov edi,0xDB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,0xDF; mov esi,13; mov edx,13; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xEB; mov esi,r13d; mov edx,ebx; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; call vec_free
    jmp .evi_ok
.evi_mod:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .evi_binary
    mov rbx,[r15+32]; test rbx,rbx; jz .evi_fail
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .evi_mod_varn
    test rax,rax; jz .evi_fail
    mov rcx,rax; dec rcx; test rax,rcx; jnz .evi_fail
    mov r12,rcx
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov rsi,r12; call vec_const_get_reg
    cmp eax,-1; je .evi_mod_literal_mem
    mov ecx,eax
    mov edi,0xDB; mov esi,r13d; mov edx,r13d; mov r8d,1; call vec_vex2_rrr
    jmp .evi_ok
.evi_mod_literal_mem:
    # Literal power-of-two modulo is an AND mask. If immutable resident ZMM
    # space is exhausted, consume the same exact mask from the shared constant
    # pool with an EVEX qword broadcast. Register pressure must not reject an
    # otherwise proven vector topology or force a scalar realization.
    mov rsi,r12
    call vec_const_intern
    cmp eax,-1; je .evi_fail
    mov edx,eax
    mov edi,r13d
    mov esi,r13d
    call vec_vpandq_mem_const
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_mod_varn:
    # RHS must be external extent n.
    mov rdi,rbx; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .evi_fail
    mov rdi,[rax+8]; mov rsi,[rax+16]; call tensor_domain_var_match
    test eax,eax; jz .evi_fail
    # INTERIOR_PROVEN can make dynamic modulo physically disappear.  Ask the
    # generic interior affine recognizer about the complete mod expression; if
    # it proves the ring-normalized residue already lies in [0,n), emit exactly
    # that affine coordinate from the current root topology.  Boundary blocks
    # retain the full reciprocal/modulo correction path below.
    cmp dword ptr [rip+vec_interior_mode],1
    jne .evi_mod_varn_full
    mov rdi,r12
    call expr_affine_axis_interior_u64
    test ecx,ecx
    jz .evi_mod_varn_full
    mov rsi,rax
    mov rcx,rdx
    mov edi,r13d
    mov rdx,rcx
    call vec_emit_affine_current
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_mod_varn_full:
    # Prove the exact integer form c*axis + q*n + d.  The original vector LHS is
    # still emitted verbatim; this proof exists only to guarantee non-negativity,
    # exact FP64 conversion and reciprocal-mod rounding safety.
    mov rdi,r15; call expr_affine_modn_form
    test ecx,ecx; jz .evi_fail
    mov r12,rax                    # c >= 0
    mov r14,rdx                    # signed d
    mov r11,r8                     # signed q
    test r11,r11
    js .evi_fail                   # current proof requires q>=0
    # Minimum at axis=0 must be non-negative for every accepted n.
    test r14,r14
    jns .evi_mod_min_ok
    mov rax,r14
    neg rax                        # |d|
    mov r10,rax
    mov rax,r11
    mul qword ptr [rip+tensor_shape_extent_min]
    test rdx,rdx; jnz .evi_fail
    cmp rax,r10; jb .evi_fail
.evi_mod_min_ok:
    # Conservative maximum: (c+q)*nmax + |d| < 2^50. This single stronger
    # bound implies both exact-integer and reciprocal-rounding requirements.
    mov rax,r12
    add rax,r11; jc .evi_fail
    mul qword ptr [rip+tensor_shape_extent_max]
    test rdx,rdx; jnz .evi_fail
    mov r10,r14
    test r10,r10
    jns .evi_mod_abs_ready
    neg r10
.evi_mod_abs_ready:
    add rax,r10; jc .evi_fail
    mov rdx,0x0004000000000000     # 2^50
    cmp rax,rdx; jae .evi_fail
    # Exact reciprocal lowering under the proof above.  Because
    # (c+d)*n_max < 2^50, reciprocal/multiply rounding cannot cross the next
    # integer for a non-integral quotient.  Exact multiples may truncate one
    # low; the unsigned min correction maps r=n back to zero.
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    call vec_alloc; cmp eax,-1; je .evi_fail; mov ebx,eax       # quotient / q*n
    call vec_alloc; cmp eax,-1; je .evi_mod_free_q; mov r14d,eax # correction t
    mov edi,ebx; mov esi,r13d; call vec_vcvtqq2pd
    mov edi,0x59; mov esi,ebx; mov edx,ebx; mov ecx,15; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; mov esi,ebx; call vec_trunc_nonneg_pd_to_u64
    mov edi,ebx; mov esi,ebx; mov edx,ebx; mov ecx,7; call vec_vpmullq
    mov edi,0xFB; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    # t=r-n (wraps high when r<n); min_u(r,t) selects r or exact corrected remainder.
    mov edi,0xFB; mov esi,r14d; mov edx,r13d; mov ecx,7; mov r8d,1; call vec_vex2_rrr
    mov edi,r13d; mov esi,r13d; mov edx,r13d; mov ecx,r14d; call vec_vpminuq
    mov edi,r14d; call vec_free
    mov edi,ebx; call vec_free
    jmp .evi_ok
.evi_mod_free_q:
    mov edi,ebx; call vec_free
    jmp .evi_fail
.evi_binary:
    xor ebx,ebx
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz 1f; mov ebx,1; jmp 4f
1:  mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz 2f; mov ebx,2; jmp 4f
2:  mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz .evi_fail; mov ebx,3
4:
    mov r14,[r15+32]; test r14,r14; jz .evi_fail
    cmp ebx,3
    jne .evi_generic_bin
    # Multiplication by a simple literal is lowered before generic source
    # allocation so topology strides can bypass vpmullq entirely.
    mov rdi,r14
    call expr_literal_u64
    test edx,edx
    jnz .evi_try_lhs_literal
    push rax
    mov rdi,r15
    call vec_try_int_source
    mov r12d,eax
    pop rdx
    cmp r12d,-1
    je .evi_generic_bin
    mov edi,r13d; mov esi,r12d
    call vec_mul_const_strength
    test eax,eax
    jz .evi_ok
    jmp .evi_generic_bin
.evi_try_lhs_literal:
    mov rdi,r15
    call expr_literal_u64
    test edx,edx
    jnz .evi_generic_bin
    push rax
    mov rdi,r14
    call vec_try_int_source
    mov r12d,eax
    pop rdx
    cmp r12d,-1
    je .evi_generic_bin
    mov edi,r13d; mov esi,r12d
    call vec_mul_const_strength
    test eax,eax
    jz .evi_ok
.evi_generic_bin:
    # Sethi-Ullman plus direct leaf sources. No copy is emitted for axis/n/literal leaves.
    mov rdi,r15; call vec_try_int_source
    mov r12d,eax
    cmp eax,-1; jne .evi_lhs_source
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov r12d,r13d
.evi_lhs_source:
    mov rdi,r14; call vec_try_int_source
    mov r14d,eax
    cmp eax,-1; jne .evi_rhs_source
    call vec_alloc; cmp eax,-1; je .evi_fail; mov r14d,eax
    mov rdi,[r15+32]; mov esi,r14d; call emit_vec_int; test eax,eax; jnz .evi_rhs_temp_fail
    mov r10d,1
    jmp .evi_emit_bin
.evi_rhs_source:
    xor r10d,r10d
.evi_emit_bin:
    cmp ebx,1; je .evi_add2
    cmp ebx,2; je .evi_sub2
    mov edi,r13d; mov esi,r13d; mov edx,r12d; mov ecx,r14d; call vec_vpmullq
    jmp .evi_bin2_done
.evi_add2:
    mov edi,0xD4; mov esi,r13d; mov edx,r12d; mov ecx,r14d; mov r8d,1; call vec_vex2_rrr
    jmp .evi_bin2_done
.evi_sub2:
    mov edi,0xFB; mov esi,r13d; mov edx,r12d; mov ecx,r14d; mov r8d,1; call vec_vex2_rrr
.evi_bin2_done:
    test r10d,r10d; jz .evi_ok
    mov edi,r14d; call vec_free
    jmp .evi_ok
.evi_rhs_temp_fail:
    mov edi,r14d; call vec_free
    jmp .evi_fail
.evi_free2_fail:
    mov edi,r14d; call vec_free
.evi_free_b_fail:
    mov edi,ebx; call vec_free
.evi_fail:
    mov eax,1
    jmp .evi_done
.evi_ok:
    xor eax,eax
.evi_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# vec_emit_periodic_key(edi=dst,rsi=c,rdx=d,rcx=modtoken) -> eax=0/1.
# Materialize one canonical operator direction directly from the physical root
# ZMM6. This is a realization of the generic key, not a periodic-workload fast
# path. modtoken=-1 denotes external n; positive literal moduli use exact
# power-of-two masking in the current native slice.
vec_emit_periodic_key:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,edi
    mov r12,rsi                    # c
    mov r13,rdx                    # d
    mov r14,rcx                    # mod token

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
    # Same exact reciprocal proof used by ordinary vector modulo lowering.
    mov rax,r12
    mul qword ptr [rip+tensor_shape_extent_max]
    test rdx,rdx; jnz .vepk_fail
    add rax,r13; jc .vepk_fail
    mov rdx,0x0020000000000000
    cmp rax,rdx; jae .vepk_fail
    mov rax,r12
    add rax,r13; jc .vepk_fail
    mul qword ptr [rip+tensor_shape_extent_max]
    test rdx,rdx; jnz .vepk_fail
    mov rdx,0x0004000000000000
    cmp rax,rdx; jae .vepk_fail

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
vec_linear_operator_expr:
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
vec_linear_modulus_value:
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
vec_linear_mul_mod:
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
vec_linear_add_mod:
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
vec_linear_compose_key:
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
vec_linear_add_term:
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
vec_linear_collect:
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
vec_linear_txn_begin:
    mov rax,qword ptr [rip+vec_emit_ptr]; mov qword ptr [rip+vec_txn_emit_ptr],rax
    mov rax,qword ptr [rip+vec_init_emit_ptr]; mov qword ptr [rip+vec_txn_init_ptr],rax
    mov eax,dword ptr [rip+vec_reg_mask]; mov dword ptr [rip+vec_txn_reg_mask],eax
    mov eax,dword ptr [rip+vec13_free]; mov dword ptr [rip+vec_txn_13_free],eax
    mov eax,dword ptr [rip+vec_const_count]; mov dword ptr [rip+vec_txn_const_count],eax
    mov eax,dword ptr [rip+vec_fixup_count]; mov dword ptr [rip+vec_txn_fixup_count],eax
    mov eax,dword ptr [rip+vec_axis_root_valid]; mov dword ptr [rip+vec_txn_axis_valid],eax
    mov rax,qword ptr [rip+vec_axis_root_c]; mov qword ptr [rip+vec_txn_axis_c],rax
    mov rax,qword ptr [rip+vec_axis_root_d]; mov qword ptr [rip+vec_txn_axis_d],rax
    mov eax,dword ptr [rip+vec_axis_reg]; mov dword ptr [rip+vec_txn_axis_reg],eax
    mov eax,dword ptr [rip+vec_induct_count]; mov dword ptr [rip+vec_txn_induct_count],eax
    mov rax,qword ptr [rip+vec_induct_coeff]; mov qword ptr [rip+vec_txn_induct_coeff],rax
    mov rax,qword ptr [rip+vec_induct_coeff+8]; mov qword ptr [rip+vec_txn_induct_coeff+8],rax
    mov rax,qword ptr [rip+vec_induct_reg]; mov qword ptr [rip+vec_txn_induct_reg],rax
    lea rsi,[rip+schedule_counts]
    lea rdi,[rip+vec_txn_schedule]
    mov ecx,10
    rep movsd
    ret

vec_linear_txn_rollback:
    mov rax,qword ptr [rip+vec_txn_emit_ptr]; mov qword ptr [rip+vec_emit_ptr],rax
    mov rax,qword ptr [rip+vec_txn_init_ptr]; mov qword ptr [rip+vec_init_emit_ptr],rax
    mov eax,dword ptr [rip+vec_txn_reg_mask]; mov dword ptr [rip+vec_reg_mask],eax
    mov eax,dword ptr [rip+vec_txn_13_free]; mov dword ptr [rip+vec13_free],eax
    mov eax,dword ptr [rip+vec_txn_const_count]; mov dword ptr [rip+vec_const_count],eax
    mov eax,dword ptr [rip+vec_txn_fixup_count]; mov dword ptr [rip+vec_fixup_count],eax
    mov eax,dword ptr [rip+vec_txn_axis_valid]; mov dword ptr [rip+vec_axis_root_valid],eax
    mov rax,qword ptr [rip+vec_txn_axis_c]; mov qword ptr [rip+vec_axis_root_c],rax
    mov rax,qword ptr [rip+vec_txn_axis_d]; mov qword ptr [rip+vec_axis_root_d],rax
    mov eax,dword ptr [rip+vec_txn_axis_reg]; mov dword ptr [rip+vec_axis_reg],eax
    mov eax,dword ptr [rip+vec_txn_induct_count]; mov dword ptr [rip+vec_induct_count],eax
    mov rax,qword ptr [rip+vec_txn_induct_coeff]; mov qword ptr [rip+vec_induct_coeff],rax
    mov rax,qword ptr [rip+vec_txn_induct_coeff+8]; mov qword ptr [rip+vec_induct_coeff+8],rax
    mov rax,qword ptr [rip+vec_txn_induct_reg]; mov qword ptr [rip+vec_induct_reg],rax
    lea rsi,[rip+vec_txn_schedule]
    lea rdi,[rip+schedule_counts]
    mov ecx,10
    rep movsd
    mov dword ptr [rip+vec_linear_active],0
    ret

# vec_linear_emit_base_term(rdi=binding,esi=dst,rdx=c,rcx=d,r8=mod)
# -> eax=0/1.  Canonical base directions are realized from their structural key;
# the caller never needs a workload-specific workload-specific branch.
vec_linear_emit_base_term:
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
vec_linear_try_emit:
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
vec_elim_free_carriers:
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
emit_vec_float_accum:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13d,esi
    cmp qword ptr [r12],J_OBJECT
    jne .evfa_fallback
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .evfa_fallback
    mov r14,rax
    # add(a,b): recursively accumulate both children into the same destination.
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz .evfa_try_mul
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .evfa_fallback
    mov r14,[rax+24]; test r14,r14; jz .evfa_fallback
    mov r15,[r14+32]; test r15,r15; jz .evfa_fallback
    cmp qword ptr [r15+32],0; jne .evfa_fallback
    mov rdi,r14; mov esi,r13d; call emit_vec_float_accum
    test eax,eax; jnz .evfa_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float_accum
    jmp .evfa_done
.evfa_try_mul:
    # literal * expr (either side) => one FMA into dst.
    mov rdi,r12; call expr_mul_literal_other
    test ecx,ecx; jz .evfa_try_div
    mov r14,rax                    # coefficient bits
    mov r15,rdx                    # multiplicand
    jmp .evfa_scaled
.evfa_try_div:
    # expr / exact positive power-of-two literal => reciprocal-scale FMA.
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .evfa_fallback
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .evfa_fallback
    mov r15,[rax+24]; test r15,r15; jz .evfa_fallback   # numerator
    mov rbx,[r15+32]; test rbx,rbx; jz .evfa_fallback  # denominator
    cmp qword ptr [rbx+32],0; jne .evfa_fallback
    mov rdi,rbx; call expr_literal_f64_bits
    test edx,edx; jnz .evfa_fallback
    call recip_pow2_f64_bits
    test edx,edx; jz .evfa_div_have_recip
    mov rdi,rbx; call expr_literal_f64_bits
    test edx,edx; jnz .evfa_fallback
    call tolerant_recip_f64_bits
    test edx,edx; jnz .evfa_fallback
.evfa_div_have_recip:
    mov r14,rax
.evfa_scaled:
    # Preserve the live tolerant accumulator as a whole vector while lowering
    # the scaled nonlinear leaf. Only after the leaf has the full register pool
    # do we reserve one short-lived YMM to keep it across accumulator restore.
    mov edi,r13d; call vec_stack_spill_push_128
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evfa_fail
    call vec_alloc
    cmp eax,-1; je .evfa_fail
    mov ebx,eax
    mov edi,ebx; mov esi,r13d; call vec_mov_ext
    mov edi,r13d; call vec_stack_spill_pop_128
    mov rsi,r14; call vec_const_get_reg
    cmp eax,-1; je .evfa_scaled_mem
    mov ecx,eax
    mov edi,r13d; mov esi,r13d; mov edx,ebx; call vec_vfmadd231pd
    mov edi,ebx; call vec_free
    xor eax,eax
    jmp .evfa_done
.evfa_scaled_mem:
    mov rsi,r14; call vec_const_intern
    cmp eax,-1; je .evfa_scaled_free_fail
    mov edx,eax
    mov edi,r13d; mov esi,ebx; call vec_vfmadd231pd_mem_const
    test eax,eax; jnz .evfa_scaled_free_fail
    mov edi,ebx; call vec_free
    xor eax,eax
    jmp .evfa_done
.evfa_scaled_free_fail:
    mov edi,ebx; call vec_free
    jmp .evfa_fail
.evfa_fallback:
    mov edi,r13d; call vec_stack_spill_push_128
    mov rdi,r12; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evfa_fail
    call vec_alloc
    cmp eax,-1; je .evfa_fail
    mov ebx,eax
    mov edi,ebx; call vec_stack_spill_pop_128
    mov edi,0x58; mov esi,r13d; mov edx,ebx; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; call vec_free
    xor eax,eax
    jmp .evfa_done
.evfa_leaf_free_fail:
    mov edi,ebx; call vec_free
.evfa_fail:
    mov eax,1
.evfa_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


# Whole-YMM stack spill. No scalar lane is introduced. Nested fractures are
# naturally LIFO and each reserves exactly one 32-byte vector slot.
vec_stack_spill_push_128:
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

vec_stack_spill_pop_128:
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
emit_vec_float:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13d,esi
    mov rdi,r12; call expr_literal_f64_bits
    test edx,edx; jnz .evf_load
    mov rsi,rax; mov edi,r13d; call vec_broadcast_imm64
    jmp .evf_done
.evf_load:
    mov rdi,r12; lea rsi,[rip+k_load]; mov edx,k_load_end-k_load; call obj_get
    test rax,rax; jz .evf_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call find_binding
    test rax,rax; jz .evf_fail
    mov r14,rax
    cmp dword ptr [r14+16],OP_MAP; jne .evf_fail
    mov rdi,r12; lea rsi,[rip+k_indices]; mov edx,k_indices_end-k_indices; call obj_get
    test rax,rax; jz .evf_fail
    mov r15,[rax+24]; test r15,r15; jz .evf_fail

    # Direct current-axis load: native256 realizes directly in the caller-owned destination.
    mov rdi,r15; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .evf_load_indexed
    mov rdi,[r14+40]; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_fail
    xor eax,eax; jmp .evf_done

.evf_load_indexed:
    # No ghost high-register cache exists. The index uses a real temporary from
    # the primary YMM ownership set, then the nested map is emitted directly.
    call vec_alloc; cmp eax,-1; je .evf_fail; mov ebx,eax
    mov rdi,r15; mov esi,ebx; call emit_vec_int
    test eax,eax; jnz .evf_index_meta_fail
    mov eax,dword ptr [rip+vec_axis_reg]
    push rax
    mov dword ptr [rip+vec_axis_reg],ebx
    mov eax,dword ptr [rip+vec_axis_root_valid]
    push rax
    mov rax,qword ptr [rip+vec_axis_root_c]
    push rax
    mov rax,qword ptr [rip+vec_axis_root_d]
    push rax
    mov rdi,r15
    call vec_axis_compose_from_index
    mov rdi,[r14+40]; mov esi,r13d; call emit_vec_float
    push rax
    pop rdx
    pop rax
    mov qword ptr [rip+vec_axis_root_d],rax
    pop rax
    mov qword ptr [rip+vec_axis_root_c],rax
    pop rax
    mov dword ptr [rip+vec_axis_root_valid],eax
    pop rax
    mov dword ptr [rip+vec_axis_reg],eax
    mov edi,ebx; call vec_free
    test edx,edx; jnz .evf_fail
    xor eax,eax; jmp .evf_done
.evf_index_meta_fail:
    mov edi,ebx; call vec_free
    jmp .evf_fail

.evf_op:
    mov rdi,r12; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .evf_fail
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .evf_fail
    mov r15,[rax+24]; test r15,r15; jz .evf_fail
    # cast u64->f64
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_cast]; mov ecx,v_cast_end-v_cast; call span_eq
    test eax,eax; jz .evf_sqrt_probe
    call vec_alloc; cmp eax,-1; je .evf_fail; mov ebx,eax
    mov rdi,r15; mov esi,ebx; call emit_vec_int; test eax,eax; jnz .evf_free_b_fail
    mov edi,r13d; mov esi,ebx; call vec_vcvtqq2pd
    mov edi,ebx; call vec_free
    xor eax,eax; jmp .evf_done
.evf_sqrt_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sqrt]; mov ecx,v_sqrt_end-v_sqrt; call span_eq
    test eax,eax; jz .evf_square_probe
    cmp qword ptr [r15+32],0; jne .evf_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov edi,r13d; mov esi,r13d; call vec_sqrtpd
    test eax,eax; jnz .evf_fail
    xor eax,eax; jmp .evf_done
.evf_square_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_square]; mov ecx,v_square_end-v_square; call span_eq
    test eax,eax; jz .evf_trunc_probe
    cmp qword ptr [r15+32],0; jne .evf_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov edi,0x59; mov esi,r13d; mov edx,r13d; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    test eax,eax; jnz .evf_fail
    inc dword ptr [rip+schedule_counts+4]
    xor eax,eax; jmp .evf_done
.evf_trunc_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_trunc]; mov ecx,v_trunc_end-v_trunc; call span_eq
    test eax,eax; jz .evf_binary
    cmp qword ptr [r15+32],0; jne .evf_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov edi,r13d; mov esi,r13d; call vec_vrndscalepd_trunc
    test eax,eax; jnz .evf_fail
    xor eax,eax; jmp .evf_done
.evf_binary:
    xor ebx,ebx
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_add]; mov ecx,v_add_end-v_add; call span_eq
    test eax,eax; jz 11f; mov ebx,0x58; jmp 15f
11: mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_sub]; mov ecx,v_sub_end-v_sub; call span_eq
    test eax,eax; jz 12f; mov ebx,0x5C; jmp 15f
12: mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    test eax,eax; jz 13f; mov ebx,0x59; jmp 15f
13: mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .evf_fail; mov ebx,0x5E
15:
    mov r14,[r15+32]; test r14,r14; jz .evf_fail
    # Exact power-of-two division becomes multiply by exact reciprocal.
    cmp ebx,0x5E; jne .evf_normal_bin
    mov rdi,r14; call expr_literal_f64_bits
    test edx,edx; jnz .evf_normal_bin
    call recip_pow2_f64_bits
    test edx,edx; jz .evf_div_have_recip
    cmp dword ptr [rip+tensor_tolerant_fp],0
    je .evf_normal_bin
    mov rdi,r14; call expr_literal_f64_bits
    test edx,edx; jnz .evf_normal_bin
    call tolerant_recip_f64_bits
    test edx,edx; jnz .evf_normal_bin
.evf_div_have_recip:
    mov r12,rax
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov rsi,r12; call vec_const_get_reg
    cmp eax,-1; je .evf_pow2_div_mem
    mov ecx,eax
    mov edi,0x59; mov esi,r13d; mov edx,r13d; mov r8d,1; call vec_vex2_rrr
    xor eax,eax; jmp .evf_done
.evf_pow2_div_mem:
    # Exact reciprocal multiplication remains one vmulpd in strict mode.  The
    # constant is consumed from the read-only pool when residency is exhausted;
    # no reassociation, scalar fallback, or extra floating-point rounding point
    # is introduced.
    mov rsi,r12; call vec_const_intern
    cmp eax,-1; je .evf_fail
    mov edx,eax
    mov edi,r13d; mov esi,r13d; call vec_vmulpd_mem_const
    test eax,eax; jnz .evf_fail
    xor eax,eax; jmp .evf_done
.evf_normal_bin:
    # Tolerant sums use a single accumulation chain.  This is intentionally
    # disabled for strict IEEE mode because reassociation changes rounding.
    cmp dword ptr [rip+tensor_tolerant_fp],0
    je .evf_pairwise_tol_check
    cmp ebx,0x58
    jne .evf_pairwise_tol_check
    # First attempt topology-aware compile-time coefficient aggregation on the
    # whole add root. Nested representative loads are guarded by active=1.
    cmp dword ptr [rip+vec_linear_active],0
    jne .evf_tol_plain_chain
    mov rdi,r12; mov esi,r13d; call vec_linear_try_emit
    test eax,eax; jz .evf_done
.evf_tol_plain_chain:
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_fail
    mov rdi,r14; mov esi,r13d; call emit_vec_float_accum
    test eax,eax; jnz .evf_fail
    xor eax,eax; jmp .evf_done
.evf_pairwise_tol_check:
    # Tolerant-only contraction: add(lhs, literal*expr) -> FMA.  Strict mode
    # preserves source rounding order exactly.
    cmp dword ptr [rip+tensor_tolerant_fp],0
    je .evf_no_tol_fma
    cmp ebx,0x58
    jne .evf_no_tol_fma
    mov rdi,r14; call expr_mul_literal_other
    test ecx,ecx; jz .evf_no_tol_fma
    push rax                    # coefficient bits
    push rdx                    # multiplicand expr
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_tol_restore_fail
    call vec_alloc; cmp eax,-1; je .evf_tol_restore_fail
    mov ebx,eax
    pop rdi
    pop r12
    mov esi,ebx; call emit_vec_float
    test eax,eax; jnz .evf_tol_free_x
    mov rsi,r12; call vec_const_get_reg
    cmp eax,-1; je .evf_tol_const_temp
    mov ecx,eax
    mov edi,r13d; mov esi,r13d; mov edx,ebx; call vec_vfmadd231pd
    mov edi,ebx; call vec_free
    xor eax,eax; jmp .evf_done
.evf_tol_const_temp:
    # Coefficient is not resident: consume it directly as an EVEX embedded
    # qword broadcast from the constant pool.
    mov rsi,r12; call vec_const_intern
    cmp eax,-1; je .evf_tol_free_x
    mov edx,eax
    mov edi,r13d; mov esi,ebx; call vec_vfmadd231pd_mem_const
    test eax,eax; jnz .evf_tol_free_x
    mov edi,ebx; call vec_free
    xor eax,eax; jmp .evf_done
.evf_tol_free_c:
.evf_tol_free_x:
    mov edi,ebx; call vec_free
    jmp .evf_fail
.evf_tol_restore_fail:
    add rsp,16
    jmp .evf_fail
.evf_no_tol_fma:
    # If RHS is an immutable resident leaf, consume it directly.
    mov rdi,r14; call vec_try_float_source
    mov r12d,eax
    cmp eax,-1; je .evf_try_comm_lhs
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r12d; mov r8d,1; call vec_vex2_rrr
    xor eax,eax; jmp .evf_done
.evf_try_comm_lhs:
    # add/mul are commutative: a resident LHS may be consumed after compiling RHS into dst.
    cmp ebx,0x58; je .evf_comm_lhs
    cmp ebx,0x59; jne .evf_regular_two
.evf_comm_lhs:
    mov rdi,r15; call vec_try_float_source
    mov r12d,eax
    cmp eax,-1; je .evf_regular_two
    mov rdi,r14; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r12d; mov r8d,1; call vec_vex2_rrr
    xor eax,eax; jmp .evf_done
.evf_regular_two:
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    # Generic post-materialization ValueFact reuse. Avoid a spill/reload whenever
    # the completed left subtree establishes the right operand's authority.
    mov rdi,r14; call vec_try_float_source
    cmp eax,-1; je .evf_regular_two_no_post_source
    mov r12d,eax
    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax; jmp .evf_done
.evf_regular_two_no_post_source:
    mov edi,r13d; call vec_stack_spill_push_128
    mov rdi,r14; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    call vec_alloc; cmp eax,-1; je .evf_fail; mov r12d,eax
    mov edi,r12d; call vec_stack_spill_pop_128
    mov edi,ebx; mov esi,r13d; mov edx,r12d; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    mov edi,r12d; call vec_free
    xor eax,eax; jmp .evf_done
.evf_free_x_fail:
    mov edi,r12d; call vec_free
    jmp .evf_fail
.evf_free_b_fail:
    mov edi,ebx; call vec_free
.evf_fail:
    mov eax,1
.evf_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- native expression emitter ----------------
# emit_expr(rdi=json object, rsi=current axis name ptr, rdx=len) -> eax type or 0
emit_expr:
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
emit_u8:
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
emit_u16:
    mov rax,[rip+emit_ptr]; lea rcx,[rax+2]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_17
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_17:
    mov [rax],di; mov [rip+emit_ptr],rcx; xor eax,eax; ret
emit_u24:
    mov rax,[rip+emit_ptr]; lea rcx,[rax+3]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_18
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_18:
    mov [rax],di; shr edi,16; mov [rax+2],dil; mov [rip+emit_ptr],rcx; xor eax,eax; ret
emit_u40:
    mov rax,[rip+emit_ptr]; lea rcx,[rax+5]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_19
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_19:
    mov [rax],edi; shr rdi,32; mov [rax+4],dil; mov [rip+emit_ptr],rcx; xor eax,eax; ret
emit_push_imm64:
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
emit_bytes:
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
emit_tensor_image:
    push rbx
    push r12
    push r13
    push r14
    push r15

    # Measure only machine code that is reachable in this generated image.
    mov r12,[rip+emit_ptr]
    mov rax,[rip+tensor_eval_base]
    sub r12,rax                     # compile-time scalar oracle bytes
    # Mature WHEX parallel contract: the scalar oracle is compiler-local only.
    # It is not reachable runtime code and is physically erased from the final
    # RX payload once the authoritative vector lowering exists.
    cmp dword ptr [rip+tensor_vector_width],4
    jne .eti_fail
    xor r12d,r12d                   # runtime scalar evaluator bytes = 0

    xor r13d,r13d                   # vector bytes
    xor r14d,r14d                   # vector-init bytes
    cmp dword ptr [rip+tensor_vector_width],4
    jne .eti_lengths_ready
    mov r13,[rip+vec_emit_ptr]
    mov rax,[rip+tensor_vec_base]
    sub r13,rax
    mov r14,[rip+vec_init_emit_ptr]
    mov rax,[rip+tensor_vec_init_base]
    sub r14,rax
.eti_lengths_ready:
    mov r15,r12
    add r15,r13
    add r15,r14
    test r15,r15
    jz .eti_fail
    mov [rip+image_eval_len],r12
    mov [rip+image_vec_len],r13
    mov [rip+image_init_len],r14
    mov [rip+image_generated_len],r15

    mov eax,SYS_openat
    mov edi,AT_FDCWD
    mov rsi,[rip+tensor_output_path]
    mov edx,OUT_FLAGS
    mov r10d,0755
    syscall
    test rax,rax
    js .eti_fail
    mov rbx,rax

    # Write only the loadable runtime prefix.  Section/symbol tables and the
    # one-byte link-time .generated anchor are not copied into the final image.
    mov eax,SYS_write
    mov rdi,rbx
    lea rsi,[rip+runtime_template_blob]
    mov edx,RUNTIME_TEMPLATE_SIZE
    syscall
    cmp rax,RUNTIME_TEMPLATE_SIZE
    jne .eti_close_fail

    # Final image deliberately has no section table.  Runtime loaders need only
    # ELF + PHDRs, and dead compiler/debug metadata must not survive AOT output.
    mov qword ptr [rip+image_zero_qword],0
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+image_zero_qword]
    mov edx,8
    mov r10d,RUNTIME_ELF_SHOFF_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+image_zero_qword]
    mov edx,6
    mov r10d,RUNTIME_ELF_SHENTSIZE_OFF
    syscall
    cmp rax,6
    jne .eti_close_fail

    # Structural plan patches.
    # 1.3.18 AOT emergent-expansion prices.
    mov edi,dword ptr [rip+tensor_vector_width]
    call derive_tensor_chunk_work_ticks

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+execution_admission_capacity]
    mov edx,4
    mov r10d,RUNTIME_EXECUTION_ADMISSION_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    # Reduction semantics are an AOT contract fact.  Runtime admission may change
    # ownership multiplicity, never this strict/tolerant mathematical authority.
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_tolerant_fp]
    mov edx,4
    mov r10d,RUNTIME_REDUCTION_TOLERANT_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    # Burn the exact compile-time silicon-domain placement witness into the
    # executable. Runtime only applies this inherited mask once; it never
    # discovers, scores, or reallocates silicon.
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+sd_static_placement_required]
    mov edx,4
    mov r10d,RUNTIME_STATIC_PLACEMENT_REQUIRED_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+sd_preferred_l3_mask_bytes]
    mov edx,4
    mov r10d,RUNTIME_STATIC_PLACEMENT_MASK_BYTES_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+sd_preferred_l3_mask]
    mov edx,128
    mov r10d,RUNTIME_STATIC_PLACEMENT_MASK_OFF
    syscall
    cmp rax,128
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+outward_materialization_ticks]
    mov edx,8
    mov r10d,RUNTIME_OUTWARD_MATERIALIZATION_TICKS_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_chunk_work_ticks]
    mov edx,8
    mov r10d,RUNTIME_CHUNK_WORK_TICKS_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_chunk_elements]
    mov edx,8
    mov r10d,RUNTIME_CHUNK_ELEMENTS_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_vector_width]
    mov edx,4
    mov r10d,RUNTIME_VECTOR_WIDTH_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+group_carrier_factor]
    mov edx,4
    mov r10d,RUNTIME_GROUP_CARRIER_FACTOR_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+group_body_factor]
    mov edx,4
    mov r10d,RUNTIME_GROUP_BODY_FACTOR_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    # Independent realized-carrier contract.
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+physical_realize_group_carriers]
    mov edx,4
    mov r10d,RUNTIME_REALIZED_GROUP_CARRIER_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    # Independent execution-contract byte: corrupting both plan fields cannot
    # disguise the Physical Tensor width actually realized by code generation.
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+physical_realize_group_body]
    mov edx,4
    mov r10d,RUNTIME_REALIZED_GROUP_BODY_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_shape_extent_min]
    mov edx,8
    mov r10d,RUNTIME_EXTENT_MIN_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_shape_extent_max]
    mov edx,8
    mov r10d,RUNTIME_EXTENT_MAX_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail

    # Append exact reachable AOT code: scalar evaluator, then optional vector
    # evaluator and vector initialization.  No fixed evaluator capacity exists.
    mov eax,SYS_pwrite64
    mov rdi,rbx
    mov rsi,[rip+tensor_eval_base]
    mov rdx,r12
    mov r10d,RUNTIME_GENERATED_FILE_OFF
    syscall
    cmp rax,r12
    jne .eti_close_fail

    test r13,r13
    jz .eti_no_vec_payload
    mov r10,RUNTIME_GENERATED_FILE_OFF
    add r10,r12
    mov eax,SYS_pwrite64
    mov rdi,rbx
    mov rsi,[rip+tensor_vec_base]
    mov rdx,r13
    syscall
    cmp rax,r13
    jne .eti_close_fail

    mov r10,RUNTIME_GENERATED_FILE_OFF
    add r10,r12
    add r10,r13
    mov eax,SYS_pwrite64
    mov rdi,rbx
    mov rsi,[rip+tensor_vec_init_base]
    mov rdx,r14
    syscall
    cmp rax,r14
    jne .eti_close_fail
.eti_no_vec_payload:

    # Make the generated RX segment exactly the appended byte length.
    mov [rip+image_generated_len],r15
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+image_generated_len]
    mov edx,8
    mov r10d,RUNTIME_GENERATED_FILESZ_PHDR_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+image_generated_len]
    mov edx,8
    mov r10d,RUNTIME_GENERATED_MEMSZ_PHDR_OFF
    syscall
    cmp rax,8
    jne .eti_close_fail

    # Direct rel32 AOT jumps.  No runtime function-pointer lookup or interpreter.
    mov rax,RUNTIME_GENERATED_VA
    sub rax,(0x400000 + RUNTIME_EVAL_OFF + 5)
    mov dword ptr [rip+image_disp],eax
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+image_disp]
    mov edx,4
    mov r10d,RUNTIME_EVAL_DISP_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    test r13,r13
    jz .eti_jumps_done
    mov rax,RUNTIME_GENERATED_VA
    add rax,r12
    sub rax,(0x400000 + RUNTIME_VEC_OFF + 5)
    mov dword ptr [rip+image_disp],eax
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+image_disp]
    mov edx,4
    mov r10d,RUNTIME_VEC_DISP_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    mov rax,RUNTIME_GENERATED_VA
    add rax,r12
    add rax,r13
    sub rax,(0x400000 + RUNTIME_VEC_INIT_OFF + 5)
    mov dword ptr [rip+image_disp],eax
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+image_disp]
    mov edx,4
    mov r10d,RUNTIME_VEC_INIT_DISP_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail
.eti_jumps_done:

    mov eax,SYS_fchmod
    mov rdi,rbx
    mov esi,0755
    syscall
    mov eax,SYS_close
    mov rdi,rbx
    syscall
    xor eax,eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.eti_close_fail:
    mov eax,SYS_close
    mov rdi,rbx
    syscall
.eti_fail:
    mov eax,1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

emit_fused_vector_body:
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

emit_fused_reduce_carrier:
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

# 1.3.1: SUB is both the remaining-count update and completion proof; no redundant CMP.
# Full-packet Group reduction. Group guard proves every packet in the hot
# episode has all four lanes, so tail-mask construction is dead work here.
emit_fused_reduce_carrier_full:
    test edi,edi
    jnz .efrcf_1
    lea rdi,[rip+vec_fused_full_reduce_fragment]
    mov esi,vec_fused_full_reduce_fragment_end-vec_fused_full_reduce_fragment
    jmp vec_emit_bytes
.efrcf_1:
    lea rdi,[rip+vec_fused_full_reduce_carrier1_fragment]
    mov esi,vec_fused_full_reduce_carrier1_fragment_end-vec_fused_full_reduce_carrier1_fragment
    jmp vec_emit_bytes

vec_emit_group_guard:
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
emit_fused_advance4_group_coordinates:
    push r12
    lea rdi,[rip+vec_fused_add_index8_fragment]
    mov esi,vec_fused_add_index8_fragment_end-vec_fused_add_index8_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efa4gc_fail
    mov rsi,4
    call vec_const_intern
    cmp eax,-1; je .efa4gc_fail
    mov edx,eax; mov edi,6; mov esi,6
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa4gc_fail
    xor r12d,r12d
.efa4gc_induct:
    cmp r12d,dword ptr [rip+vec_induct_count]
    jae .efa4gc_ok
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    mov rax,rsi
    mov rcx,4
    mul rcx
    test rdx,rdx; jnz .efa4gc_fail
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1; je .efa4gc_fail
    mov edx,eax
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa4gc_fail
    inc r12d
    jmp .efa4gc_induct
.efa4gc_ok:
    xor eax,eax
    pop r12
    ret
.efa4gc_fail:
    mov eax,1
    pop r12
    ret


# One remaining-count update and one back-edge per complete Group episode.
vec_emit_group_countdown_backedge:
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

emit_fused_advance4:
    push rbx
    push r12
    lea rdi,[rip+vec_fused_sub8_fragment]
    mov esi,vec_fused_sub8_fragment_end-vec_fused_sub8_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efa4_fail
    call vec_emit_jbe_placeholder
    test rax,rax; jz .efa4_fail
    mov rbx,rax
    lea rdi,[rip+vec_fused_add_index8_fragment]
    mov esi,vec_fused_add_index8_fragment_end-vec_fused_add_index8_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efa4_fail
    mov rsi,4
    call vec_const_intern
    cmp eax,-1; je .efa4_fail
    mov edx,eax
    mov edi,6
    mov esi,6
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa4_fail
    xor r12d,r12d
.efa4_induct:
    cmp r12d,dword ptr [rip+vec_induct_count]
    jae .efa4_ok
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    mov rax,rsi
    mov rcx,4
    mul rcx
    test rdx,rdx; jnz .efa4_fail
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1; je .efa4_fail
    mov edx,eax
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa4_fail
    inc r12d
    jmp .efa4_induct
.efa4_ok:
    mov rax,rbx
    jmp .efa4_done
.efa4_fail:
    xor eax,eax
.efa4_done:
    pop r12
    pop rbx
    ret

# Match the physical-domain extent variable under the active canonical shape.
# Direct canonical tensor/1 keeps historical `n`; ShapeFact-N uses one synthetic
# product identity so arbitrary source extent names do not leak into codegen.
tensor_domain_var_match:
    cmp dword ptr [rip+tensor_shape_active],0
    je .tdvm_legacy
    lea rdx,[rip+v_shape_product]
    mov ecx,v_shape_product_end-v_shape_product
    jmp span_eq
.tdvm_legacy:
    lea rdx,[rip+v_n]
    mov ecx,v_n_end-v_n
    jmp span_eq

.include "compiler/shapefact_n_frontend.inc"

.section .rodata
# Four-lane native256 fused episode. All tail work remains vectorized.
vec_fused_full_reduce_fragment:
    vaddpd ymm12,ymm12,ymm0
vec_fused_full_reduce_fragment_end:

vec_fused_full_reduce_carrier1_fragment:
    vaddpd ymm11,ymm11,ymm0
vec_fused_full_reduce_carrier1_fragment_end:

vec_fused_mask_reduce_fragment:
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
vec_fused_mask_reduce_fragment_end:

vec_fused_mask_reduce_resident_fragment:
    cmp r8,4
    jae .Lvfmrr256_full
    vmovq xmm10,r8
    vpbroadcastq ymm10,xmm10
    vpcmpgtq ymm10,ymm10,ymmword ptr [rip+.Lvfmr256_lanes]
    vandpd ymm0,ymm0,ymm10
.Lvfmrr256_full:
    vaddpd ymm12,ymm12,ymm0
vec_fused_mask_reduce_resident_fragment_end:


vec_fused_mask_reduce_carrier1_fragment:
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
vec_fused_mask_reduce_carrier1_fragment_end:

vec_fused_mask_reduce_resident_carrier1_fragment:
    cmp r8,4
    jae .Lvfmrr1_256_full
    vmovq xmm10,r8
    vpbroadcastq ymm10,xmm10
    vpcmpgtq ymm10,ymm10,ymmword ptr [rip+.Lvfmr1_256_lanes]
    vandpd ymm0,ymm0,ymm10
.Lvfmrr1_256_full:
    vaddpd ymm11,ymm11,ymm0
vec_fused_mask_reduce_resident_carrier1_fragment_end:

vec_fused_cmp8_fragment:
    cmp r8,4
vec_fused_cmp8_fragment_end:

vec_group_test_remaining_fragment:
    test r8,r8
vec_group_test_remaining_fragment_end:

vec_fused_sub8_fragment:
    sub r8,4
vec_fused_sub8_fragment_end:

vec_fused_boundary_test_zero_fragment:
    test rsi,rsi
vec_fused_boundary_test_zero_fragment_end:

vec_fused_boundary_test_end_fragment:
    lea rax,[rsi+4]
    cmp rax,rdi
vec_fused_boundary_test_end_fragment_end:

vec_fused_add_index8_fragment:
    add rsi,4
vec_fused_add_index8_fragment_end:

vec_fused_finish_fragment:
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
vec_fused_finish_fragment_end:

vec_fused_finish_resident_fragment:
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
vec_fused_finish_resident_fragment_end:


vec_fused_finish_dual_fragment:
    vaddpd ymm12,ymm12,ymm11
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
vec_fused_finish_dual_fragment_end:

vec_fused_finish_resident_dual_fragment:
    vaddpd ymm12,ymm12,ymm11
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
vec_fused_finish_resident_dual_fragment_end:

vec_fused_init_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
vec_fused_init_fragment_end:

vec_fused_init_resident_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
vec_fused_init_resident_fragment_end:


vec_fused_init_dual_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
    vxorpd ymm11,ymm11,ymm11
vec_fused_init_dual_fragment_end:

vec_fused_init_resident_dual_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
    vxorpd ymm11,ymm11,ymm11
vec_fused_init_resident_dual_fragment_end:

vec_prefix_fragment:
    jmp .Lvec_prefix256_code
.Lvec_offsets256:
    .quad 0,1,2,3
.Lvec_prefix256_code:
    vmovq xmm6,rsi
    vpbroadcastq ymm6,xmm6
    vpaddq ymm6,ymm6,ymmword ptr [rip+.Lvec_offsets256]
    vmovq xmm7,rdi
    vpbroadcastq ymm7,xmm7
vec_prefix_fragment_end:
vec_movabs_rax: .byte 0x48,0xB8
vec_movabs_rax_end:
vec_save_axis_code:
    sub rsp,32
    vmovdqu ymmword ptr [rsp],ymm6
vec_save_axis_code_end:
vec_restore_axis_code:
    vmovdqu ymm6,ymmword ptr [rsp]
    add rsp,32
vec_restore_axis_code_end:
# stack-machine native code fragments
code_eval_reg_prologue: .byte 0x49,0x89,0xF0,0x49,0x89,0xF9
code_eval_reg_prologue_end:
code_movq_xmm0_rax: .byte 0x66,0x48,0x0F,0x6E,0xC0
code_movq_xmm0_rax_end:
code_cast_u64_f64: .byte 0x58,0xF2,0x48,0x0F,0x2A,0xC0,0x66,0x48,0x0F,0x7E,0xC0,0x50
code_cast_u64_f64_end:
# f64 unary sqrt: pop bits -> xmm0, SQRTSD, push bits
code_sqrt_f64: .byte 0x58,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x51,0xC0,0x66,0x48,0x0F,0x7E,0xC0,0x50
code_sqrt_f64_end:
code_square_f64: .byte 0x58,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x59,0xC0,0x66,0x48,0x0F,0x7E,0xC0,0x50
code_square_f64_end:
code_trunc_f64: .byte 0x58,0x66,0x48,0x0F,0x6E,0xC0,0x66,0x0F,0x3A,0x0B,0xC0,0x03,0x66,0x48,0x0F,0x7E,0xC0,0x50
code_trunc_f64_end:
code_eq_u64: .byte 0x59,0x58,0x48,0x39,0xC8,0x0F,0x94,0xC0,0x0F,0xB6,0xC0,0x50
code_eq_u64_end:
code_select_bits: .byte 0x5A,0x59,0x58,0x48,0x85,0xC0,0x48,0x0F,0x44,0xCA,0x51
code_select_bits_end:
code_mod_u64: .byte 0x59,0x58,0x31,0xD2,0x48,0xF7,0xF1,0x52
code_mod_u64_end:
code_add_u64: .byte 0x59,0x58,0x48,0x01,0xC8,0x50
code_add_u64_end:
code_sub_u64: .byte 0x59,0x58,0x48,0x29,0xC8,0x50
code_sub_u64_end:
code_mul_u64: .byte 0x59,0x58,0x48,0x0F,0xAF,0xC1,0x50
code_mul_u64_end:
# f64: pop rhs->xmm1, lhs->xmm0, op, push bits
.macro F64FRAG name, opc
\name:
 .byte 0x58,0x66,0x48,0x0F,0x6E,0xC8, 0x58,0x66,0x48,0x0F,0x6E,0xC0, 0xF2,0x0F,\opc,0xC1, 0x66,0x48,0x0F,0x7E,0xC0,0x50
\name\()_end:
.endm
F64FRAG code_add_f64,0x58
F64FRAG code_sub_f64,0x5C
F64FRAG code_mul_f64,0x59
F64FRAG code_div_f64,0x5E

lit_true: .ascii "true"
lit_false: .ascii "false"
lit_null: .ascii "null"

# key/value constants
k_format:.ascii "format"; k_format_end:
k_contracts:.ascii "contracts"; k_contracts_end:
k_floating_point:.ascii "floating_point"; k_floating_point_end:
k_inputs:.ascii "inputs"; k_inputs_end:
k_bindings:.ascii "bindings"; k_bindings_end:
k_name:.ascii "name"; k_name_end:
k_type:.ascii "type"; k_type_end:
k_min:.ascii "min"; k_min_end:
k_max:.ascii "max"; k_max_end:
k_op:.ascii "op"; k_op_end:
k_kind:.ascii "kind"; k_kind_end:
k_accumulator:.ascii "accumulator"; k_accumulator_end:
k_mode:.ascii "mode"; k_mode_end:
k_axes:.ascii "axes"; k_axes_end:
k_extent:.ascii "extent"; k_extent_end:
k_var:.ascii "var"; k_var_end:
k_expr:.ascii "expr"; k_expr_end:
k_literal:.ascii "literal"; k_literal_end:
k_axis:.ascii "axis"; k_axis_end:
k_load:.ascii "load"; k_load_end:
k_indices:.ascii "indices"; k_indices_end:
k_args:.ascii "args"; k_args_end:

v_tensor_format:.ascii "wheelchair.tensor/1"; v_tensor_format_end:
v_u64:.ascii "u64"; v_u64_end:
v_f64:.ascii "f64"; v_f64_end:
v_n:.ascii "n"; v_n_end:
v_shape_product:.ascii "__shape_product"; v_shape_product_end:
v_map:.ascii "map"; v_map_end:
v_reduce:.ascii "reduce"; v_reduce_end:
v_sum:.ascii "sum"; v_sum_end:
v_tolerant:.ascii "tolerant"; v_tolerant_end:
v_cast:.ascii "cast"; v_cast_end:
v_eq:.ascii "eq"; v_eq_end:
v_select:.ascii "select"; v_select_end:
v_mod:.ascii "mod"; v_mod_end:
v_add:.ascii "add"; v_add_end:
v_sub:.ascii "sub"; v_sub_end:
v_mul:.ascii "mul"; v_mul_end:
v_div:.ascii "div"; v_div_end:
v_sqrt:.ascii "sqrt"; v_sqrt_end:
v_square:.ascii "square"; v_square_end:
v_trunc:.ascii "trunc"; v_trunc_end:

.section .bss
.p2align 6
jcur:.skip 8
jend:.skip 8
json_node_count:.skip 8
tensor_error:.skip 4
tensor_tolerant_fp:.skip 4
tensor_binding_count:.skip 4
tensor_reduce_binding:.skip 8
tensor_output_path:.skip 8
tensor_shape_extent_min:.skip 8
tensor_shape_extent_max:.skip 8
tensor_shape_active:.skip 4
tensor_shape_rank:.skip 4
tensor_shape_static_product:.skip 8
tensor_shape_runtime_name_ptr:.skip 8
tensor_shape_runtime_name_len:.skip 8
tensor_domain_min:.skip 8
tensor_domain_max:.skip 8
image_eval_len:.skip 8
image_vec_len:.skip 8
image_init_len:.skip 8
image_generated_len:.skip 8
image_zero_qword:.skip 8
image_disp:.skip 4
emit_ptr:.skip 8
emit_end:.skip 8
emit_gpr_mask:.skip 4
emit_xmm_mask:.skip 4
tensor_vector_width:.skip 4
vector_schedule_attempted:.skip 4
# 1.3.0 transient Physical-DAG plan. This state exists only inside the compiler.
physical_plan_pass:.skip 4
physical_realize_group_carriers:.skip 4
physical_realize_group_body:.skip 4
physical_plan_counts:.skip 40
scalar_schedule_counts:.skip 40
vec_reg_mask:.skip 4
vec13_free:.skip 4
vec11_borrowed:.skip 4
vec_axis_root_valid:.skip 4
.p2align 3
vec_axis_root_c:.skip 8
vec_axis_root_d:.skip 8
vec_fused_mode:.skip 4
vec_product_subtract_contractions:.skip 4
vec_induct_count:.skip 4
.p2align 3
vec_induct_coeff:.skip 2*8
vec_induct_reg:.skip 2*4
vec_affine_induct_reg:.skip 4
.p2align 3
vec_fused_entry_disp:.skip 8
vec_fused_finish_disp:.skip 8
vec_fused_finish_disp1:.skip 8
vec_fused_tail_disp:.skip 8
vec_fused_empty_finish_disp:.skip 8
vec_fused_loop_start:.skip 8
vec_group_body_start:.skip 8
vec_fused_tail_loop_start:.skip 8
vec_group_cost_start_ptr:.skip 8
vec_group_emit_index:.skip 4
vec_fused_safe_zero_disp:.skip 8
vec_fused_safe_end_disp:.skip 8
vec_fused_common_disp:.skip 8
vec_emit_ptr:.skip 8
vec_emit_end:.skip 8
vec_init_emit_ptr:.skip 8
vec_init_emit_end:.skip 8
vec_const_count:.skip 4
vec_fixup_count:.skip 4
.p2align 3
vec_const_bits_ptr:.skip 8
vec_const_reg_ptr:.skip 8
vec_const_addr_ptr:.skip 8
vec_interior_mode:.skip 4
vec_axis_reg:.skip 4
.p2align 3
.p2align 3
vec_txn_emit_ptr:.skip 8
vec_txn_init_ptr:.skip 8
vec_txn_reg_mask:.skip 4
vec_txn_13_free:.skip 4
vec_txn_const_count:.skip 4
vec_txn_fixup_count:.skip 4
vec_txn_axis_valid:.skip 4
vec_txn_axis_reg:.skip 4
vec_txn_induct_count:.skip 4
.p2align 3
vec_txn_induct_coeff:.skip 2*8
vec_txn_induct_reg:.skip 2*4
vec_txn_axis_c:.skip 8
vec_txn_axis_d:.skip 8
vec_txn_schedule:.skip 40
.p2align 3
vec_linear_count:.skip 4
vec_linear_raw_count:.skip 4
vec_linear_live_count:.skip 4
vec_linear_active:.skip 4
vec_elim_carriers:.skip 4
vec_elim_carrier1:.skip 4
vec_elim_carrier2:.skip 4
vec_elim_carrier3:.skip 4
vec_elim_emit_ordinal:.skip 4
vec_elim_span_before:.skip 4
vec_elim_span_after:.skip 4
.p2align 3
vec_linear_ctx_c:.skip 8
vec_linear_ctx_d:.skip 8
vec_linear_ctx_mod:.skip 8
vec_linear_term_mode:.skip 4
vec_operator_inline_depth:.skip 4
vec_operator_max_depth:.skip 4
vec_operator_compositions:.skip 4
vec_operator_check_depth:.skip 4
vec_linear_binding_ptr:.skip 8
vec_linear_key_a_ptr:.skip 8
vec_linear_key_b_ptr:.skip 8
vec_linear_key_c_ptr:.skip 8
vec_linear_expr_ptr:.skip 8
vec_linear_coeff_ptr:.skip 8
vec_linear_mode_ptr:.skip 8
.p2align 6
tensor_optimizer_arena_ptr:.skip 8
tensor_optimizer_arena_bytes:.skip 8
tensor_optimizer_capacity:.skip 4
.p2align 3
json_nodes_ptr:.skip 8
json_nodes_bytes:.skip 8
json_node_capacity:.skip 8
.p2align 6
tensor_bindings_ptr:.skip 8
tensor_binding_arena_bytes:.skip 8
tensor_binding_capacity:.skip 4
.p2align 6
tensor_code_arena_ptr:.skip 8
tensor_code_arena_bytes:.skip 8
tensor_code_lane_bytes:.skip 8
tensor_eval_base:.skip 8
tensor_vec_base:.skip 8
tensor_vec_init_base:.skip 8
tensor_code_growth_factor:.skip 8
tensor_code_overflow:.skip 4
tensor_fixup_ptr_base:.skip 8
tensor_fixup_const_base:.skip 8
tensor_fixup_capacity:.skip 4
