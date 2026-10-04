.intel_syntax noprefix
.include "compiler/native256_physical_profile.inc"
.equ TENSOR_PHYSICAL_LANES,4
.include "compiler/isa_capabilities.inc"
.include "compiler/shapefact_n.inc"
.include "compiler/physical_reality.inc"
.include "build/runtime_derived_native256_offsets.inc"
.include "compiler/tensor_frontend_common_blocks.inc"
.include "compiler/tensor_frontend_profile_blocks.inc"

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
TFC_tensor_prepare_code_arenas
tensor_prepare_optimizer_arena:
TFP_23_tensor_prepare_optimizer_arena
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
    mov qword ptr [rip+tensor_shape_static_product],0
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

    # Unified Group-aware shape authority. ShapeFact-N is preferred and may
    # carry any supported logical rank. Historical direct tensor/1 rank-1 input
    # is normalized here to the same facts with static_product=1; it is not a
    # second physicalizer or compatibility backend.
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
    mov dword ptr [rip+tensor_shape_active],1
    jmp .shape_input_done
.shape_rank1_input:
    mov dword ptr [rip+tensor_shape_rank],1
    mov qword ptr [rip+tensor_shape_static_product],1
    lea rax,[rip+v_n]
    mov qword ptr [rip+tensor_shape_runtime_name_ptr],rax
    mov qword ptr [rip+tensor_shape_runtime_name_len],1
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
    mov [rip+tensor_domain_min],rax
    mov rdi,r13
    lea rsi,[rip+k_max]
    mov edx,k_max_end-k_max
    call obj_get
    call node_parse_u64
    test edx,edx
    jnz .fail
    mov [rip+tensor_shape_extent_max],rax
    mov [rip+tensor_domain_max],rax
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
    mov dword ptr [rip+vec13_free],0      # YMM13 remains native256 scratch
    mov dword ptr [rip+vec11_borrowed],0
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .physical_carrier_reservation_ready
    btr dword ptr [rip+vec_reg_mask],11
.physical_carrier_reservation_ready:
    # The old copied high-register ownership pool is absent on native256; topology CSE and persistent
    # cross-vector induction.  Induction carriers reserve only actually-free
    # registers, so general expressions never lose capacity merely because the
    # feature exists.
    mov dword ptr [rip+vec_fused_mode],1
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
    # Canonical operation-native Group episode for derived native256. Probe one
    # real YMM packet; canonical width comes only from common Physical Reality.
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
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_finish_single
    lea rdi,[rip+vec_fused_finish_dual_fragment]
    mov esi,vec_fused_finish_dual_fragment_end-vec_fused_finish_dual_fragment
    jmp .vec_finish_emit
.vec_finish_single:
    lea rdi,[rip+vec_fused_finish_fragment]
    mov esi,vec_fused_finish_fragment_end-vec_fused_finish_fragment
.vec_finish_emit:
    call vec_emit_bytes
    test eax,eax
    jnz .fail
    # Initialization island. Runtime arguments are rdi=n, rsi=start, rdx=end.
    # Native256 immutable constants come from the RIP pool; here only
    # episode-varying state is established.
    mov rsi,[rip+vec_emit_ptr]
    mov rdi,[rip+vec_fused_entry_disp]
    call vec_patch_rel32
    test eax,eax
    jnz .fail
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .vec_init_single
    lea rdi,[rip+vec_fused_init_dual_fragment]
    mov esi,vec_fused_init_dual_fragment_end-vec_fused_init_dual_fragment
    jmp .vec_init_emit
.vec_init_single:
    lea rdi,[rip+vec_fused_init_fragment]
    mov esi,vec_fused_init_fragment_end-vec_fused_init_fragment
.vec_init_emit:
    call vec_emit_bytes
    test eax,eax
    jnz .fail
    lea rdi,[rip+vec_prefix_fragment]
    mov esi,vec_prefix_fragment_end-vec_prefix_fragment
    call vec_emit_bytes
    test eax,eax
    jnz .fail
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

    # Width is admitted from actual allocator pressure, not a benchmark or
    # source-pattern name.  YMM11 must remain unused by the pass-0 expression.
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
2:
    call synthesize_resource_schedule
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
    mov eax,dword ptr [rip+group_carrier_factor]
    cmp eax,dword ptr [rip+physical_realize_group_carriers]
    jne .fail
    mov eax,dword ptr [rip+group_body_factor]
    cmp eax,dword ptr [rip+physical_realize_group_body]
    jne .fail

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
TFC_json_skip_ws
json_prepare_arena:
TFC_json_prepare_arena
new_node:
TFC_new_node
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
TFC_json_parse_value
bytes_eq_n:
TFC_bytes_eq_n
span_eq:
TFC_span_eq
obj_get:
TFC_obj_get
node_parse_u64:
TFC_node_parse_u64
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
TFP_123_tensor_prepare_binding_arena
find_binding:
TFC_find_binding
alloc_gpr:
TFC_alloc_gpr
free_gpr:
    bts dword ptr [rip+emit_gpr_mask],edi
    ret
alloc_xmm:
TFC_alloc_xmm
free_xmm:
    bts dword ptr [rip+emit_xmm_mask],edi
    ret

# Instruction encoders. Return eax=0 success, 1 failure.
# gen_mov_ri64(edi=dst, rsi=imm)
gen_mov_ri64:
TFC_gen_mov_ri64
gen_rr_opcode:
TFC_gen_rr_opcode
gen_mov_rr:
TFC_gen_mov_rr
gen_alu_ri32:
TFC_gen_alu_ri32
gen_imul_rr:
TFC_gen_imul_rr
gen_imul_ri32:
TFC_gen_imul_ri32
gen_div_reg:
TFC_gen_div_reg
gen_cvtsi2sd:
TFC_gen_cvtsi2sd
gen_movq_xmm_gpr:
TFC_gen_movq_xmm_gpr
gen_sse_rr:
TFC_gen_sse_rr
gen_cmp_setcc:
TFC_gen_cmp_setcc
gen_ucomisd_setcc:
TFC_gen_ucomisd_setcc
gen_neg_gpr:
TFC_gen_neg_gpr
gen_sse66_rr:
TFC_gen_sse66_rr
gen_test_rr:
TFC_gen_test_rr
gen_cmovz:
TFC_gen_cmovz
expr_literal_u64:
TFC_expr_literal_u64
expr_literal_f64_bits:
TFC_expr_literal_f64_bits
expr_is_float_value:
TFC_expr_is_float_value
expr_mul_literal_other:
TFC_expr_mul_literal_other
recip_pow2_f64_bits:
TFC_recip_pow2_f64_bits
recip_u64_down_f64_bits:
    test rax,rax; jz .rudf256_fail
    mov rcx,0x0001000000000000
    cmp rax,rcx; jae .rudf256_fail
    cvtsi2sd xmm0,rax
    mov rdx,0x3ff0000000000000
    movq xmm1,rdx
    divsd xmm1,xmm0
    movq rax,xmm1
    test rax,rax; jz .rudf256_fail
    dec rax
    xor edx,edx
    ret
.rudf256_fail:
    xor eax,eax; mov edx,1; ret

# gen_load_f64_bits(edi=xmm, rsi=bits)
gen_load_f64_bits:
TFC_gen_load_f64_bits
emit_int_reg:
TFP_13_emit_int_reg
emit_float_reg:
TFC_emit_float_reg
vec_alloc:
TFP_23_vec_alloc
vec_free:
TFP_23_vec_free
vec_init_emit_u8:
TFC_vec_init_emit_u8
vec_emit_u8:
TFC_vec_emit_u8
vec_emit_bytes:
TFP_023_vec_emit_bytes
vec_emit_jmp_placeholder:
TFP_023_vec_emit_jmp_placeholder
vec_emit_jbe_placeholder:
TFP_023_vec_emit_jbe_placeholder
vec_emit_jb_placeholder:
TFP_023_vec_emit_jb_placeholder
vec_emit_je_placeholder:
TFP_023_vec_emit_je_placeholder
vec_emit_jae_placeholder:
TFP_023_vec_emit_jae_placeholder
vec_patch_rel32:
TFC_vec_patch_rel32
vec_emit_jmp_to:
TFC_vec_emit_jmp_to
vec_vex2_rrr:
TFP_23_vec_vex2_rrr
vec_sqrtpd:
TFP_23_vec_sqrtpd
vec_vex3_0f38_rrr:
TFC_vec_vex3_0f38_rrr
vec_mov_ext:
TFP_23_vec_mov_ext
vec_broadcast_imm64:
TFP_23_vec_broadcast_imm64
vec_const_intern:
TFC_vec_const_intern
vec_const_get_reg:
TFP_23_vec_const_get_reg
vec_emit_const_load_index:
TFP_23_vec_emit_const_load_index
vec_finalize_constants:
TFP_023_vec_finalize_constants
vec_vpmullq:
TFP_23_vec_vpmullq
vec_vpmullq_native:
TFC_vec_vpmullq_native
vec_vpmuludq:
TFC_vec_vpmuludq
vec_vpsllq_imm:
TFP_23_vec_vpsllq_imm
vec_vpsrlq_imm:
TFP_23_vec_vpsrlq_imm
vec_vpaddq_mem_const:
TFP_23_vec_vpaddq_mem_const
vec_vpandq_mem_const:
TFP_23_vec_vpandq_mem_const
vec_vpmullq_mem_const:
TFP_23_vec_vpmullq_mem_const
vec_vpmullq_mem_const_native:
TFP_23_vec_vpmullq_mem_const_native
vec_mul_const_strength:
TFP_23_vec_mul_const_strength
vec_vmulpd_mem_const:
TFP_23_vec_vmulpd_mem_const
vec_vfmadd231pd:
TFP_23_vec_vfmadd231pd
vec_vfmadd231pd_mem_const:
TFP_23_vec_vfmadd231pd_mem_const
vec_vpminuq:
TFP_23_vec_vpminuq
vec_vcvtqq2pd:
TFC_vec_vcvtqq2pd
vec_vcvtqq2pd_native:
TFC_vec_vcvtqq2pd_native
vec_vcvtqq2pd_synth:
TFP_23_vec_vcvtqq2pd_synth
vec_vpmovqd_ymm_from_zmm:
TFP_23_vec_vpmovqd_ymm_from_zmm
vec_vcvtdq2pd_zmm_from_ymm:
TFP_23_vec_vcvtdq2pd_zmm_from_ymm
vec_vpsrld_imm:
TFP_23_vec_vpsrld_imm
vec_roundpd_trunc_scalar_reg:
TFC_vec_roundpd_trunc_scalar_reg
vec_trunc_nonneg_pd_to_u64:
TFC_vec_trunc_nonneg_pd_to_u64
vec_trunc_nonneg_pd_to_u64_synth:
TFC_vec_trunc_nonneg_pd_to_u64_synth
vec_vrndscalepd_trunc:
TFP_23_vec_vrndscalepd_trunc
vec_vaddpd_mem_const:
TFP_23_vec_vaddpd_mem_const
vec_vcvttpd2qq:
TFC_vec_vcvttpd2qq
vec_cmp_eq_maskvec:
TFP_23_vec_cmp_eq_maskvec

vec_cmp_ge_u64_maskvec:
TFP_23_vec_cmp_ge_u64_maskvec
vec_cmp_f64_maskvec:
TFP_23_vec_cmp_f64_maskvec
expr_affine_axis_u64:
TFC_expr_affine_axis_u64
vec_interior_affine_residue_safe:
TFP_13_vec_interior_affine_residue_safe
expr_affine_axis_interior_u64:
TFP_13_expr_affine_axis_interior_u64
vec_axis_compose_from_index:
TFC_vec_axis_compose_from_index
vec_emit_affine_current:
TFP_23_vec_emit_affine_current
expr_affine_modn_form:
TFP_13_expr_affine_modn_form
vec_modn_fixed_normalize_d:
TFP_13_vec_modn_fixed_normalize_d
expr_index_key_u64:
TFP_13_expr_index_key_u64
vec_save_axis:
TFC_vec_save_axis
vec_restore_axis:
TFC_vec_restore_axis
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
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_shape_product]; mov ecx,v_shape_product_end-v_shape_product; call span_eq
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
TFP_23_vec_try_float_source
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
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_shape_product]; mov ecx,v_shape_product_end-v_shape_product; call span_eq
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
    # PredicateFact comparison closure. Floating relations share one VCMPPD
    # lowering; integer equality retains the same exact VPCMPEQQ relation.
    mov ebx,-1
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_eq]; mov ecx,v_eq_end-v_eq; call span_eq
    test eax,eax; jz .evi_cmp_ne; mov ebx,0; jmp .evi_compare
.evi_cmp_ne:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ne]; mov ecx,v_ne_end-v_ne; call span_eq
    test eax,eax; jz .evi_cmp_lt; mov ebx,12; jmp .evi_compare
.evi_cmp_lt:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_lt]; mov ecx,v_lt_end-v_lt; call span_eq
    test eax,eax; jz .evi_cmp_le; mov ebx,1; jmp .evi_compare
.evi_cmp_le:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_le]; mov ecx,v_le_end-v_le; call span_eq
    test eax,eax; jz .evi_cmp_gt; mov ebx,2; jmp .evi_compare
.evi_cmp_gt:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_gt]; mov ecx,v_gt_end-v_gt; call span_eq
    test eax,eax; jz .evi_cmp_ge; mov ebx,14; jmp .evi_compare
.evi_cmp_ge:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ge]; mov ecx,v_ge_end-v_ge; call span_eq
    test eax,eax; jz .evi_select; mov ebx,13
.evi_compare:
    push rbx
    mov rbx,[r15+32]; test rbx,rbx; jz .evi_compare_drop_fail
    mov rdi,r15; call expr_is_float_value
    test eax,eax; jz .evi_compare_integer
    call vec_alloc; cmp eax,-1; je .evi_compare_drop_fail; mov r12d,eax
    call vec_alloc; cmp eax,-1; je .evi_compare_fp_free_lhs_fail; mov r14d,eax
    mov rdi,r15; mov esi,r12d; call emit_vec_float; test eax,eax; jnz .evi_compare_fp_free2_fail
    mov rdi,rbx; mov esi,r14d; call emit_vec_float; test eax,eax; jnz .evi_compare_fp_free2_fail
    pop rcx
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call vec_cmp_f64_maskvec
    push rax
    mov edi,r14d; call vec_free
    mov edi,r12d; call vec_free
    pop rax
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_compare_fp_free2_fail:
    mov edi,r14d; call vec_free
.evi_compare_fp_free_lhs_fail:
    mov edi,r12d; call vec_free
    add rsp,8
    jmp .evi_fail
.evi_compare_integer:
    pop rcx
    test ecx,ecx
    jnz .evi_fail                   # non-equality integer relations are not in this tensor domain
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
    push rax
    mov edi,r14d; call vec_free
    pop rax
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_eq_rhs_temp_fail:
    mov edi,r14d; call vec_free
    jmp .evi_fail
.evi_eq_rhs_ready:
    mov edi,r13d; mov esi,r12d; mov edx,r14d; call vec_cmp_eq_maskvec
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_compare_drop_fail:
    add rsp,8
    jmp .evi_fail
.evi_select:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .evi_ushr
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
.evi_ushr:
    # Internal coordinate recovery. Only a compile-time immediate shift is
    # admitted; the AVX-512F VPSRLQ primitive already exists in the base frontend.
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ushr]; mov ecx,v_ushr_end-v_ushr; call span_eq
    test eax,eax; jz .evi_mod
    mov rbx,[r15+32]; test rbx,rbx; jz .evi_fail
    cmp qword ptr [rbx+32],0; jne .evi_fail
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .evi_fail
    cmp rax,63; ja .evi_fail
    mov ebx,eax
    mov rdi,r15; mov esi,r13d; call emit_vec_int
    test eax,eax; jnz .evi_fail
    mov edi,r13d; mov esi,r13d; mov edx,ebx; call vec_vpsrlq_imm
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_mod:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq
    test eax,eax; jz .evi_binary
    mov rbx,[r15+32]; test rbx,rbx; jz .evi_fail
    mov rdi,rbx; call expr_literal_u64
    test edx,edx; jnz .evi_mod_varn
    test rax,rax; jz .evi_fail
    mov r12,rax
    mov rcx,rax; dec rcx; test rax,rcx; jnz .evi_mod_literal_generic
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
.evi_mod_literal_generic:
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov edi,r13d; mov esi,r13d; mov rdx,r12; mov ecx,1
    call vec_udivmod_literal_exact
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_mod_varn:
    # RHS must be external extent n.
    mov rdi,rbx; lea rsi,[rip+k_var]; mov edx,k_var_end-k_var; call obj_get
    test rax,rax; jz .evi_fail
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_shape_product]; mov ecx,v_shape_product_end-v_shape_product; call span_eq
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
    mul qword ptr [rip+tensor_domain_min]
    test rdx,rdx; jnz .evi_fail
    cmp rax,r10; jb .evi_fail
.evi_mod_min_ok:
    # Conservative maximum: (c+q)*nmax + |d| < 2^50. This single stronger
    # bound implies both exact-integer and reciprocal-rounding requirements.
    mov rax,r12
    add rax,r11; jc .evi_fail
    mul qword ptr [rip+tensor_domain_max]
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
    test eax,eax; jz 3f; mov ebx,3; jmp 4f
3:  mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_div]; mov ecx,v_div_end-v_div; call span_eq
    test eax,eax; jz .evi_fail; mov ebx,4
4:
    mov r14,[r15+32]; test r14,r14; jz .evi_fail
    cmp ebx,4; je .evi_udiv_literal
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
.evi_udiv_literal:
    mov rdi,r14; call expr_literal_u64
    test edx,edx; jnz .evi_fail
    cmp rax,1; jb .evi_fail
    mov r12,rax
    mov rdi,r15; mov esi,r13d; call emit_vec_int
    test eax,eax; jnz .evi_fail
    mov rax,r12; mov rcx,rax; dec rcx; test rax,rcx; jnz .evi_udiv_generic
    bsf rcx,rax
    mov edi,r13d; mov esi,r13d; mov edx,ecx; call vec_vpsrlq_imm
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
.evi_udiv_generic:
    mov edi,r13d; mov esi,r13d; mov rdx,r12; xor ecx,ecx
    call vec_udivmod_literal_exact
    test eax,eax; jnz .evi_fail
    jmp .evi_ok
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

# vec_udivmod_literal_exact(edi=dst,esi=src,rdx=nonzero divisor,ecx=0 quotient/1 remainder)
# Generic exact constant-radix integer division for Rank-N coordinate recovery.
# It reuses the existing vector allocator and ISA recipes; no scalar/runtime path.
vec_udivmod_literal_exact:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12d,esi; mov r13,rdx; mov r14d,ecx
    test r13,r13; jz .vudm256_fail
    mov rax,[rip+tensor_domain_max]
    mov rcx,0x0001000000000000
    cmp rax,rcx; jae .vudm256_fail
    mov rax,r13; call recip_u64_down_f64_bits
    test edx,edx; jnz .vudm256_fail
    mov rsi,rax; call vec_const_intern
    cmp eax,-1; je .vudm256_fail
    mov r15d,eax
    mov rsi,r13; call vec_const_intern
    cmp eax,-1; je .vudm256_fail
    push rax
    mov rax,r13; neg rax; mov rsi,rax; call vec_const_intern
    cmp eax,-1; je .vudm256_fail_pop1
    push rax
    mov rsi,0x3fe0000000000000; call vec_const_intern
    cmp eax,-1; je .vudm256_fail_pop2
    push rax
    sub rsp,16
    mov qword ptr [rsp],-1
    mov qword ptr [rsp+8],-1
    call vec_alloc; cmp eax,-1; je .vudm256_cleanup_fail
    mov dword ptr [rsp],eax
    call vec_alloc; cmp eax,-1; je .vudm256_cleanup_fail
    mov dword ptr [rsp+8],eax
    mov edi,dword ptr [rsp]; mov esi,r12d; call vec_mov_ext
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp]; call vec_mov_ext
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_vcvtqq2pd
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; mov edx,r15d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_trunc_nonneg_pd_to_u64
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edx,dword ptr [rsp+32]
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_vpmullq_mem_const
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edi,0xFB; mov esi,ebx; mov edx,dword ptr [rsp]; mov ecx,dword ptr [rsp+8]; mov r8d,1; call vec_vex2_rrr
    mov edi,dword ptr [rsp+8]; mov esi,ebx; call vec_mov_ext
    mov edx,dword ptr [rsp+24]
    mov edi,dword ptr [rsp+8]; mov esi,dword ptr [rsp+8]; call vec_vpaddq_mem_const
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edi,ebx; mov esi,ebx; mov edx,ebx; mov ecx,dword ptr [rsp+8]; call vec_vpminuq
    test r14d,r14d; jnz .vudm256_cleanup_success
    mov edi,0xFB; mov esi,dword ptr [rsp]; mov edx,dword ptr [rsp]; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; call vec_vcvtqq2pd
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; mov edx,r15d; call vec_vmulpd_mem_const
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edx,dword ptr [rsp+16]
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; call vec_vaddpd_mem_const
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edi,dword ptr [rsp]; mov esi,dword ptr [rsp]; call vec_trunc_nonneg_pd_to_u64
    test eax,eax; jnz .vudm256_cleanup_fail
    mov edi,ebx; mov esi,dword ptr [rsp]; call vec_mov_ext
.vudm256_cleanup_success:
    mov edi,dword ptr [rsp+8]; call vec_free
    mov edi,dword ptr [rsp]; call vec_free
    add rsp,40
    xor eax,eax; jmp .vudm256_done
.vudm256_cleanup_fail:
    mov eax,dword ptr [rsp+8]; cmp eax,-1; je 1f; mov edi,eax; call vec_free
1:  mov eax,dword ptr [rsp]; cmp eax,-1; je 2f; mov edi,eax; call vec_free
2:  add rsp,40
    mov eax,1; jmp .vudm256_done
.vudm256_fail_pop2: add rsp,8
.vudm256_fail_pop1: add rsp,8
.vudm256_fail: mov eax,1
.vudm256_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx
    ret

# vec_emit_periodic_key(edi=dst,rsi=c,rdx=d,rcx=modtoken) -> eax=0/1.
# Materialize one canonical operator direction directly from the physical root
# ZMM6. This is a realization of the generic key, not a periodic-workload fast
# path. modtoken=-1 denotes external n; positive literal moduli use exact
# power-of-two masking in the current native slice.
.include "compiler/tensor_frontend_periodic_exact.inc"

vec_emit_periodic_key:
TFP_13_vec_emit_periodic_key
vec_linear_operator_expr:
TFC_vec_linear_operator_expr
vec_linear_modulus_value:
TFP_13_vec_linear_modulus_value
vec_linear_mul_mod:
TFC_vec_linear_mul_mod
vec_linear_add_mod:
TFC_vec_linear_add_mod
vec_linear_compose_key:
TFP_13_vec_linear_compose_key
vec_linear_add_term:
TFC_vec_linear_add_term
vec_linear_collect:
TFC_vec_linear_collect
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
TFP_123_vec_linear_emit_base_term
vec_linear_try_emit:
TFC_vec_linear_try_emit
vec_elim_free_carriers:
TFC_vec_elim_free_carriers
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
    test edx,edx; jnz .evfa_fallback
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
TFP_23_vec_stack_spill_push_128
vec_stack_spill_pop_128:
TFP_23_vec_stack_spill_pop_128
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
    test eax,eax; jz .evf_select_probe
    cmp qword ptr [r15+32],0; jne .evf_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov edi,r13d; mov esi,r13d; call vec_vrndscalepd_trunc
    test eax,eax; jnz .evf_fail
    xor eax,eax; jmp .evf_done
.evf_select_probe:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_select]; mov ecx,v_select_end-v_select; call span_eq
    test eax,eax; jz .evf_binary
    mov r14,r15
    mov r15,[r14+32]; test r15,r15; jz .evf_fail
    mov r12,[r15+32]; test r12,r12; jz .evf_fail
    # Native256 has no k-mask control authority.  It still consumes the same
    # support law: +0.0 outside support means only true & PredicateFact is
    # required, so false-arm realization and two blend operations are dead.
    mov rdi,r12; call expr_literal_f64_bits
    test edx,edx; jnz .evf_select_general
    test rax,rax; jnz .evf_select_general
    call vec_alloc; cmp eax,-1; je .evf_fail; mov ebx,eax
    mov rdi,r14; mov esi,ebx; call emit_vec_int; test eax,eax; jnz .evf_select_zero_free_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_select_zero_free_fail
    mov edi,0xDB; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; call vec_free
    xor eax,eax; jmp .evf_done
.evf_select_zero_free_fail:
    mov edi,ebx; call vec_free
    jmp .evf_fail
.evf_select_general:
    call vec_alloc; cmp eax,-1; je .evf_fail; mov ebx,eax
    call vec_alloc; cmp eax,-1; je .evf_select_free_cond_fail
    mov r11,r14
    mov r14d,eax
    mov rdi,r11; mov esi,ebx; call emit_vec_int; test eax,eax; jnz .evf_select_free2_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_select_free2_fail
    mov rdi,r12; mov esi,r14d; call emit_vec_float; test eax,eax; jnz .evf_select_free2_fail
    mov edi,0xDB; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    mov edi,0xDF; mov esi,ebx; mov edx,ebx; mov ecx,r14d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xEB; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    mov edi,r14d; call vec_free
    mov edi,ebx; call vec_free
    xor eax,eax; jmp .evf_done
.evf_select_free2_fail:
    mov edi,r14d; call vec_free
.evf_select_free_cond_fail:
    mov edi,ebx; call vec_free
    jmp .evf_fail
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
    test edx,edx; jnz .evf_normal_bin
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
    lea rdx,[rip+v_shape_product]
    mov ecx,v_shape_product_end-v_shape_product
    call span_eq
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
TFP_23_emit_u8
emit_u16:
TFP_23_emit_u16
emit_u24:
TFP_23_emit_u24
emit_u40:
TFP_23_emit_u40
emit_push_imm64:
TFP_23_emit_push_imm64
emit_bytes:
TFP_23_emit_bytes
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

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+physical_realize_group_carriers]
    mov edx,4
    mov r10d,RUNTIME_REALIZED_GROUP_CARRIER_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail
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

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_shape_static_product]
    mov edx,8
    mov r10d,RUNTIME_SHAPE_STATIC_PRODUCT_OFF
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

# Build one complete four-lane expression body with its boundary proof.  This
# routine only emits bytes; it never executes runtime scheduling.
emit_fused_vector_body:
TFP_23_emit_fused_vector_body
emit_fused_reduce_carrier:
    test edi,edi
    jnz .efrc_c1
    lea rdi,[rip+vec_fused_mask_reduce_fragment]
    mov esi,vec_fused_mask_reduce_fragment_end-vec_fused_mask_reduce_fragment
    jmp vec_emit_bytes
.efrc_c1:
    lea rdi,[rip+vec_fused_mask_reduce_carrier1_fragment]
    mov esi,vec_fused_mask_reduce_carrier1_fragment_end-vec_fused_mask_reduce_carrier1_fragment
    jmp vec_emit_bytes

# 1.3.1: SUB is both the remaining-count update and completion proof; no redundant CMP.
# Full-packet Group reduction. Group guard proves every packet in the hot
# episode has all four lanes, so tail-mask construction is dead work here.
emit_fused_reduce_carrier_full:
TFP_23_emit_fused_reduce_carrier_full
vec_emit_group_guard:
TFP_23_vec_emit_group_guard
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
TFP_23_vec_emit_group_countdown_backedge
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
    mov edx,eax; mov edi,6; mov esi,6
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa4_fail
.efa4_ok:
    mov rax,rbx
    jmp .efa4_done
.efa4_fail:
    xor eax,eax
.efa4_done:
    pop r12
    pop rbx
    ret

# Match the one physical-domain root used by the unified Group physicalizer.
# ShapeFact-N canonicalization uses __shape_product; direct rank-1 tensor/1
# normalizes to n. This changes only source identity, never physical policy.
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
TFP_23_vec_fused_mask_reduce_fragment
vec_fused_mask_reduce_fragment_end:

vec_fused_mask_reduce_carrier1_fragment:
TFP_23_vec_fused_mask_reduce_carrier1_fragment
vec_fused_mask_reduce_carrier1_fragment_end:

vec_fused_mask_reduce_resident_fragment:
TFP_23_vec_fused_mask_reduce_resident_fragment
vec_fused_mask_reduce_resident_fragment_end:

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
TFC_vec_fused_finish_fragment
vec_fused_finish_fragment_end:

vec_fused_finish_dual_fragment:
TFP_23_vec_fused_finish_dual_fragment
vec_fused_finish_dual_fragment_end:

vec_fused_finish_resident_fragment:
TFP_23_vec_fused_finish_resident_fragment
vec_fused_finish_resident_fragment_end:

vec_fused_init_fragment:
TFP_023_vec_fused_init_fragment
vec_fused_init_fragment_end:

vec_fused_init_dual_fragment:
TFP_23_vec_fused_init_dual_fragment
vec_fused_init_dual_fragment_end:

vec_fused_init_resident_fragment:
TFP_23_vec_fused_init_resident_fragment
vec_fused_init_resident_fragment_end:

vec_prefix_fragment:
TFP_23_vec_prefix_fragment
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
v_ne:.ascii "ne"; v_ne_end:
v_lt:.ascii "lt"; v_lt_end:
v_le:.ascii "le"; v_le_end:
v_gt:.ascii "gt"; v_gt_end:
v_ge:.ascii "ge"; v_ge_end:
v_select:.ascii "select"; v_select_end:
v_ushr:.ascii "ushr"; v_ushr_end:
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
tensor_shape_active:.skip 4
tensor_shape_extent_min:.skip 8
tensor_shape_extent_max:.skip 8
tensor_domain_min:.skip 8
tensor_domain_max:.skip 8
tensor_shape_static_product:.skip 8
tensor_shape_rank:.skip 4
.p2align 3
tensor_shape_runtime_name_ptr:.skip 8
tensor_shape_runtime_name_len:.skip 8
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
.p2align 3
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
.p2align 3
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
