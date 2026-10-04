.intel_syntax noprefix
.equ TENSOR_PHYSICAL_LANES,8
.include "compiler/isa_capabilities.inc"
.include "compiler/shapefact_n.inc"
.include "compiler/physical_reality.inc"
.include "compiler/runtime_offsets.inc"
.include "compiler/tensor_frontend_common_blocks.inc"
.include "compiler/tensor_frontend_profile_blocks.inc"

# 1.3.49 unified native512 physical carrier bank. ZMM16..31 are one real
# architectural ownership domain. Persistent BindingFacts, AffineFacts,
# ConstantFacts and short-lived topology/value CSE all compete for this bank;
# no base/wide profile or fixed class partition survives. Pass-0 observed
# transient pressure limits long-lived residency before canonical pass 1.
.equ TENSOR_HIGH_BASE,16
.equ TENSOR_HIGH_LAST,31
.equ TENSOR_HIGH_COUNT,16
.equ TENSOR_HIGH_MASK_INIT,0x0000FFFF

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
    imul rsi,rsi,184                 # twenty-three instance-derived 8-byte lanes/fact
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
    add rax,rdx
    mov qword ptr [rip+tensor_affine_profile_coeff_ptr],rax
    add rax,rdx
    mov qword ptr [rip+tensor_affine_profile_offset_ptr],rax
    add rax,rdx
    mov qword ptr [rip+tensor_affine_profile_mod_ptr],rax
    add rax,rdx
    mov qword ptr [rip+tensor_affine_profile_uses_ptr],rax
    add rax,rdx
    mov qword ptr [rip+tensor_const_profile_bits_ptr],rax
    add rax,rdx
    mov qword ptr [rip+tensor_const_profile_score_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_cache_binding_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_cache_gen_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_cache_reg_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_cache_kind_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_cache_key_a_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_cache_key_b_ptr],rax
    add rax,rdx
    mov qword ptr [rip+vec_cache_key_c_ptr],rax
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
    mov qword ptr [rip+vec_axis_root_mod],0
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

    # 1.3.7 Tensor Physical Reality use graph. Count structurally reachable
    # binding uses once per distinct binding definition expansion. This is AOT
    # compile-time authority only; it creates no runtime manager or scheduler.
    mov rdi,[rip+tensor_binding_uses_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+tensor_binding_count]
    rep stosd
    mov rdi,[rip+tensor_binding_expanded_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+tensor_binding_count]
    rep stosd
    mov dword ptr [rip+tensor_affine_profile_count],0
    mov dword ptr [rip+tensor_induct_selected_count],0
    mov dword ptr [rip+tensor_const_profile_count],0
    mov dword ptr [rip+tensor_const_selected_count],0
    mov dword ptr [rip+tensor_transient_peak],0
    mov dword ptr [rip+tensor_transient_borrow_mask],0
    mov dword ptr [rip+tensor_persistent_budget],0
    mov dword ptr [rip+tensor_persistent_remaining],0
    mov rdi,[r15+40]
    call tensor_analyze_expr

    # PredicateFact -> SupportFact topology closure. This proves only whether a
    # zero-false reduction has one contiguous axis support (or is identically
    # +0); unsupported shapes keep the existing full-domain realization.
    mov rdi,[r15+40]
    call tensor_support_analyze_root

    # Mature WHEX tensor lane has no scalar-oracle compilation.  Building the
    # same tensor recursively as a scalar evaluator before parallel lowering was
    # dead work, imposed an artificial recursion ceiling, and violated the rule
    # that independent tensor semantics must not be serialized internally.
    # Keep the legacy buffer cursor at zero length for image-layout compatibility;
    # no scalar machine instruction is generated or copied into the final ELF.
    mov rax,[rip+tensor_eval_base]
    mov [rip+emit_ptr],rax
    # eval_slot is no longer a scalar oracle. When SupportFact proves one
    # contiguous support, reuse the dormant slot as one cold predicate/basin
    # witness for exact runtime boundary discovery.
    call tensor_emit_support_probe
    test eax,eax
    jz .support_probe_ready
    mov dword ptr [rip+tensor_support_mode],0
    mov rax,[rip+tensor_eval_base]
    mov [rip+emit_ptr],rax
.support_probe_ready:
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
    mov ecx,ISA_CAP_TENSOR512_BASE
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
    mov dword ptr [rip+vec_reg_mask],0x00000F3E  # ZMM1..5,ZMM8..11 primary short-lived arithmetic temps
    mov dword ptr [rip+vec13_free],1
    mov dword ptr [rip+vec13_borrowed],0
    # 1.3.1: a two-body Physical Tensor episode owns ZMM13 as its second
    # architectural reduction carrier.  Pass 0 leaves it borrowable solely to
    # prove whether the expression itself needs that register under pressure.
    cmp dword ptr [rip+physical_realize_group_carriers],2
    jne .physical_carrier_reservation_ready
    mov dword ptr [rip+vec13_free],0
.physical_carrier_reservation_ready:
    # ZMM16..25 form one ownership pool shared by topology CSE and persistent
    # cross-vector induction.  Induction carriers reserve only actually-free
    # registers, so general expressions never lose capacity merely because the
    # feature exists.
    # One architectural high-ZMM bank, partitioned by proven lifetime domain
    # only after pass 0.  Pass 0 lends the whole bank to transient probing.  In
    # canonical pass, the exact selected persistent count owns the upper slots
    # from loop entry to loop exit; generation-scoped facts own the remainder.
    # The split size is a DAG result, not a profile or ISA-name branch.
    mov dword ptr [rip+vec_cache_reg_mask],TENSOR_HIGH_MASK_INIT
    mov dword ptr [rip+vec_persistent_reg_mask],0
    cmp dword ptr [rip+physical_plan_pass],0
    je .physical_high_bank_ready
    xor eax,eax                         # persistent mask
    mov edx,TENSOR_HIGH_MASK_INIT         # transient mask
    mov ecx,dword ptr [rip+tensor_persistent_remaining]
    cmp ecx,TENSOR_HIGH_COUNT
    jbe .physical_high_count_ok
    mov ecx,TENSOR_HIGH_COUNT
.physical_high_count_ok:
    mov r9d,TENSOR_HIGH_COUNT-1
.physical_high_split_loop:
    test ecx,ecx
    jz .physical_high_split_done
    bts eax,r9d
    btr edx,r9d
    dec r9d
    dec ecx
    jmp .physical_high_split_loop
.physical_high_split_done:
    mov dword ptr [rip+vec_persistent_reg_mask],eax
    mov dword ptr [rip+vec_cache_reg_mask],edx
.physical_high_bank_ready:
    mov dword ptr [rip+vec_fused_mode],1
    mov dword ptr [rip+vec_product_subtract_contractions],0
    mov dword ptr [rip+vec_induct_count],0
    mov dword ptr [rip+vec_const_count],0
    mov dword ptr [rip+vec_fixup_count],0
    mov rdi,[rip+vec_const_reg_ptr]
    xor eax,eax
    mov ecx,512
    rep stosd
    mov dword ptr [rip+vec_cache_count],0
    mov dword ptr [rip+vec_current_gen],1
    mov dword ptr [rip+vec_gen_counter],1
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
    # Canonical operation-native Group episode. Pass 0 measures exactly one
    # vector packet. Canonical pass consumes the GroupFact body factor without
    # an implementation width ceiling. Full groups use one back-edge; any
    # remainder stays vectorized in the same generated kernel.
    cmp dword ptr [rip+physical_realize_group_body],1
    jbe .vec_group_single_episode

    # Full-group guard: remaining < body_factor*lanes falls into the vector tail.
    call vec_emit_group_guard
    test rax,rax
    jz .fail
    mov [rip+vec_fused_tail_disp],rax
    # The guard proves the entire Group episode legal. Loop back-edges land
    # here, after the guard, because the group-tail countdown itself proves
    # that another complete episode remains.
    mov rax,[rip+vec_emit_ptr]
    mov [rip+vec_group_body_start],rax
    mov dword ptr [rip+vec_group_emit_index],0
.vec_group_emit_loop:
    # Only Group edges can touch a global boundary.  Every strictly interior
    # packet is proven interior by contiguous group geometry, so compile those
    # packets without per-vector boundary tests or a duplicate safe body.
    mov eax,dword ptr [rip+vec_group_emit_index]
    test eax,eax
    jz .vec_group_emit_edge_body
    mov ecx,dword ptr [rip+physical_realize_group_body]
    dec ecx
    cmp eax,ecx
    je .vec_group_emit_edge_body
    call emit_fused_vector_body_interior
    jmp .vec_group_emit_body_ready
.vec_group_emit_edge_body:
    call emit_fused_vector_body
.vec_group_emit_body_ready:
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
    call emit_fused_advance8_group_coordinates
    test eax,eax
    jnz .fail
    inc dword ptr [rip+vec_group_emit_index]
    mov eax,dword ptr [rip+vec_group_emit_index]
    cmp eax,dword ptr [rip+physical_realize_group_body]
    jb .vec_group_emit_loop
    # Count the whole Group once. This replaces one remaining-count update
    # per Vector packet with one Group-level proof and one Group-level branch.
    call vec_emit_group_countdown_backedge
    test eax,eax
    jnz .fail

    # Remainder target. Empty remainder goes directly to the common finish;
    # otherwise the historical masked vector packet loop consumes it exactly.
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
    call emit_fused_advance8
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
    call emit_fused_advance8
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
    call emit_fused_advance8
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
    # Probe and naturally-degenerated Vector form. Measure the complete repeated
    # packet cost once so Physical Reality can price a wider canonical Group.
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
    call emit_fused_advance8
    test rax,rax
    jz .fail
    mov [rip+vec_fused_finish_disp],rax
    # Exact one-packet probe footprint.
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
    # Finish target. Resident and frozen recipes both return one scalar using
    # fixed tree folds; no central runtime reduction loop is introduced.
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
    # Immutable ZMM26..31 values were initialized once per worker; here only
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
    # Initialize every retained AffineFact exactly once. Plain affine facts keep
    # the mature c*root carrier. Periodic facts initialize both the exact value
    # and the packet step; neither exact expansion appears in the hot loop.
    xor r12d,r12d
.vec_fused_init_induct:
    cmp r12d,dword ptr [rip+vec_induct_count]
    jae .vec_fused_init_done
    lea rax,[rip+vec_induct_mod]
    cmp qword ptr [rax+r12*8],-1
    je .vec_fused_init_periodic

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
    jmp .vec_fused_init_next

.vec_fused_init_periodic:
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    lea rax,[rip+vec_induct_offset]
    mov rdx,qword ptr [rax+r12*8]
    call vec_emit_periodic_exact
    test eax,eax
    jnz .fail

    # step = (c * physical_lanes) mod n. Reduce c once, then double in the ring
    # according to the hardware lane fact instead of materializing c*lanes in
    # host u64 arithmetic.
    lea rax,[rip+vec_induct_step_reg]
    mov edi,dword ptr [rax+r12*4]
    cmp edi,-1
    je .fail
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    call vec_emit_u64_literal_mod_n
    test eax,eax
    jnz .fail
    mov r13d,TENSOR_PHYSICAL_LANES
.vec_fused_init_periodic_step:
    cmp r13d,1
    jbe .vec_fused_init_next
    lea rax,[rip+vec_induct_step_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    mov edx,edi
    call vec_modadd_n
    test eax,eax
    jnz .fail
    shr r13d,1
    jmp .vec_fused_init_periodic_step

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
    mov dword ptr [rip+tensor_vector_width],8

    # No tensor scalar fallback exists after this point. A tensor program that
    # reached native realization must have preserved its independent vector
    # width all the way through lowering.
    cmp dword ptr [rip+tensor_vector_width],8
    jne .fail
.schedule_counts_ready:

    # 1.3.0 Physical DAG / Semantic ISA realization. The first native lowering
    # is deliberately disposable: it exposes the exact instruction-resource
    # structure without committing bytes to the output image. The scheduler runs
    # here, before the canonical pass. The second pass restores that plan and
    # encodes the final ISA directly.
    cmp dword ptr [rip+physical_plan_pass],0
    jne .physical_plan_realize

    # 1.3.1: the backend can physically realize two body instances and two
    # independent reduction recurrences. Pass-0 register allocation is itself
    # the pressure proof: if it ever had to borrow ZMM13, the second carrier is
    # not legal and the plan remains width one. Otherwise the execution tensor
    # is physically expanded to width two, regardless of whether recurrence
    # latency alone would have demanded the extra chain. This is tensor batching,
    # not a post-codegen fiction.
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
    cmp dword ptr [rip+vec13_borrowed],0
    jne .physical_plan_width_done
    mov dword ptr [rip+group_carrier_factor],2
.physical_plan_width_done:
    call synthesize_group_fact
    lea rsi,[rip+schedule_counts]
    lea rdi,[rip+physical_plan_counts]
    mov ecx,10
    rep movsd
    # Pass 0 has now observed the complete Tensor expression. Select affine
    # induction facts by measured structural reuse and remaining persistent-bank
    # capacity before canonical pass 1. No workload name or coefficient value is
    # privileged.
    # One pass-0 competition across BindingFact/AffineFact/ConstantFact. The
    # budget is real high-bank capacity minus the transient peak observed while
    # lowering this exact DAG; no fixed reserve, use-count threshold, or
    # base/wide profile participates.
    call tensor_select_persistent_facts
    mov dword ptr [rip+physical_plan_pass],1
    jmp .physical_codegen_pass

.physical_plan_realize:
    # Canonical codegen is governed by the already-computed physical plan.
    # No second scheduling pass is allowed to describe bytes after the fact.

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

# Exact compile-time binding arena.  The use/expanded vectors share one mmap
# with the binding records so one represented list owns one physical allocation.
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
    imul rax,rax,72
    jo .tpba_fail
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
    mov ecx,ebx
    shl rcx,6
    lea rdx,[rax+rcx]
    mov [rip+tensor_binding_uses_ptr],rdx
    mov ecx,ebx
    shl rcx,2
    add rdx,rcx
    mov [rip+tensor_binding_expanded_ptr],rdx
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
TFC_find_binding
tensor_analyze_expr:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    test r12,r12
    jz .t_analyze_expr_done
    cmp qword ptr [r12],J_OBJECT
    jne .t_analyze_expr_done

    # Load node: count the referenced binding and recursively inspect that
    # binding's definition only on its first reachable occurrence.
    mov rdi,r12
    lea rsi,[rip+k_load]
    mov edx,k_load_end-k_load
    call obj_get
    test rax,rax
    jz .t_analyze_expr_args
    mov rdi,[rax+8]
    mov rsi,[rax+16]
    call find_binding
    test rax,rax
    jz .t_analyze_expr_done
    mov r13,rax
    mov r14,[rip+tensor_bindings_ptr]
    mov rax,r13
    sub rax,r14
    shr rax,6
    cmp eax,dword ptr [rip+tensor_binding_count]
    jae .t_analyze_expr_done
    mov r15d,eax
    mov r14,[rip+tensor_binding_uses_ptr]
    inc dword ptr [r14+r15*4]
    mov r14,[rip+tensor_binding_expanded_ptr]
    cmp dword ptr [r14+r15*4],0
    jne .t_analyze_expr_done
    mov dword ptr [r14+r15*4],1
    mov rdi,[r13+40]
    call tensor_analyze_expr
    jmp .t_analyze_expr_done

.t_analyze_expr_args:
    # Generic expression operator: traverse every argument. This covers add,
    # sub, mul, div, cast, select and future ordinary n-ary expression nodes
    # without workload names or formula recognition.
    mov rdi,r12
    lea rsi,[rip+k_args]
    mov edx,k_args_end-k_args
    call obj_get
    test rax,rax
    jz .t_analyze_expr_done
    cmp qword ptr [rax],J_ARRAY
    jne .t_analyze_expr_done
    mov r13,[rax+24]
.t_analyze_expr_arg_loop:
    test r13,r13
    jz .t_analyze_expr_done
    mov rdi,r13
    call tensor_analyze_expr
    mov r13,[r13+32]
    jmp .t_analyze_expr_arg_loop
.t_analyze_expr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# tensor_binding_cache_profitable(rdi=binding) -> eax 0/1.
# Persistent register authority is admitted only for a structurally repeated
# reachable binding. It is intentionally conservative: the ordinary allocator
# may still refuse retention under pressure, in which case recompute wins.
tensor_binding_cache_profitable:
    mov rax,[rip+tensor_bindings_ptr]
    mov rcx,rdi
    sub rcx,rax
    test rcx,rcx
    js .t_binding_cache_profitable_no
    shr rcx,6
    cmp ecx,dword ptr [rip+tensor_binding_count]
    jae .t_binding_cache_profitable_no
    # Binding/value copies are generation-scoped ValueFacts, not long-lived
    # persistent facts. A future consumer is the semantic prerequisite for
    # reuse; physical residence is attempted only at that consumer frontier.
    mov rax,[rip+tensor_binding_uses_ptr]
    cmp dword ptr [rax+rcx*4],1
    seta al
    movzx eax,al
    ret
.t_binding_cache_profitable_no:
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
tolerant_recip_f64_bits:
TFP_02_tolerant_recip_f64_bits
gen_load_f64_bits:
TFC_gen_load_f64_bits
emit_int_reg:
TFP_02_emit_int_reg
emit_float_reg:
TFC_emit_float_reg
tensor_mark_transient_borrow:
    # ecx = high-bank slot 0..15. Only vec_alloc calls this; optional CSE does
    # not contribute to mandatory transient pressure.
    cmp dword ptr [rip+physical_plan_pass],0
    jne .t_mark_borrow_done
    bts dword ptr [rip+tensor_transient_borrow_mask],ecx
    mov eax,dword ptr [rip+tensor_transient_borrow_mask]
    and eax,TENSOR_HIGH_MASK_INIT
    xor edx,edx
    mov ecx,TENSOR_HIGH_COUNT
.t_mark_borrow_count:
    test eax,1
    jz .t_mark_borrow_next
    inc edx
.t_mark_borrow_next:
    shr eax,1
    dec ecx
    jnz .t_mark_borrow_count
    cmp edx,dword ptr [rip+tensor_transient_peak]
    jbe .t_mark_borrow_done
    mov dword ptr [rip+tensor_transient_peak],edx
.t_mark_borrow_done:
    ret

tensor_release_transient_borrow:
    # edi = high-bank slot 0..15 after subtracting TENSOR_HIGH_BASE.
    cmp dword ptr [rip+physical_plan_pass],0
    jne .t_release_borrow_done
    btr dword ptr [rip+tensor_transient_borrow_mask],edi
.t_release_borrow_done:
    ret

# Count free high-bank carriers in EAX from vec_cache_reg_mask.
tensor_high_free_count:
    mov eax,dword ptr [rip+vec_cache_reg_mask]
    and eax,TENSOR_HIGH_MASK_INIT
    xor edx,edx
    mov ecx,TENSOR_HIGH_COUNT
.t_high_free_loop:
    test eax,1
    jz .t_high_free_next
    inc edx
.t_high_free_next:
    shr eax,1
    dec ecx
    jnz .t_high_free_loop
    mov eax,edx
    ret


vec_alloc:
    mov eax,dword ptr [rip+vec_reg_mask]
    test eax,eax
    jz .va_try13
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+vec_reg_mask],eax
    mov eax,ecx
    ret
.va_try13:
    # ZMM13 is dead while eval_vec4 executes; the runtime only consumes XMM13
    # after the call while folding the YMM12 carrier. Borrow it first so
    # low-pressure kernels preserve their historical allocation order.
    cmp dword ptr [rip+vec13_free],0
    je .va_try_cache_pool
    mov dword ptr [rip+vec13_free],0
    mov dword ptr [rip+vec13_borrowed],1
    mov eax,13
    ret
.va_try_cache_pool:
    # The CSE/topology ownership domain ZMM16..29 is a shared physical pool.
    # A zero bit means the register is already held by persistent state; a one
    # bit is provably free and may therefore be borrowed as a short-lived temp.
    # This changes only resource realization, never expression semantics.
    mov eax,dword ptr [rip+vec_cache_reg_mask]
    test eax,eax
    jz .va_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+vec_cache_reg_mask],eax
    push rcx
    call tensor_mark_transient_borrow
    pop rcx
    lea eax,[ecx+TENSOR_HIGH_BASE]
    ret
.va_fail:
    mov eax,-1
    ret
vec_free:
    cmp edi,13
    je .vf_13
    cmp edi,16
    jb .vf_primary
    cmp edi,TENSOR_HIGH_LAST
    jbe .vf_cache_pool
    # Any register outside the allocator-owned domains is a compiler bug.
    ret
.vf_13:
    mov dword ptr [rip+vec13_free],1
    ret
.vf_cache_pool:
    sub edi,TENSOR_HIGH_BASE
    push rdi
    call tensor_release_transient_borrow
    pop rdi
    bts dword ptr [rip+vec_cache_reg_mask],edi
    ret
.vf_primary:
    bts dword ptr [rip+vec_reg_mask],edi
    ret

# One architectural high-ZMM bank with two DAG-derived lifetime domains.
# Persistent facts and generation-scoped CSE share one capacity authority but
# never alias across runtime lifetime because pass 1 reserves disjoint carriers.
vec_persistent_reg_alloc:
    # Long-lived selected facts draw only from the lifetime-reserved carrier
    # domain established before canonical bytes are emitted.  This prevents a
    # later-discovered init-hoisted constant/induction from aliasing an earlier
    # generation-scoped cache in runtime time.
    mov eax,dword ptr [rip+vec_persistent_reg_mask]
    test eax,eax
    jz .vpra_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+vec_persistent_reg_mask],eax
    cmp dword ptr [rip+physical_plan_pass],0
    je .vpra_ret
    cmp dword ptr [rip+tensor_persistent_remaining],0
    jle .vpra_ret
    dec dword ptr [rip+tensor_persistent_remaining]
.vpra_ret:
    lea eax,[ecx+TENSOR_HIGH_BASE]
    ret
.vpra_fail:
    mov eax,-1
    ret

vec_persistent_reg_free:
    sub edi,TENSOR_HIGH_BASE
    cmp edi,TENSOR_HIGH_COUNT-1
    ja .vprf_done
    bts dword ptr [rip+vec_persistent_reg_mask],edi
    cmp dword ptr [rip+physical_plan_pass],0
    je .vprf_done
    inc dword ptr [rip+tensor_persistent_remaining]
.vprf_done:
    ret

vec_cache_reg_alloc:
    # Generation-scoped ValueFacts borrow only the transient lifetime domain.
    # Pass 0 uses the entire high bank and records the exact simultaneous peak;
    # pass 1 receives precisely that many slots from the lifetime split above.
    mov eax,dword ptr [rip+vec_cache_reg_mask]
    test eax,eax
    jz .vcra_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+vec_cache_reg_mask],eax
    cmp dword ptr [rip+physical_plan_pass],0
    jne .vcra_no_probe
    push rcx
    call tensor_mark_transient_borrow
    pop rcx
.vcra_no_probe:
    lea eax,[ecx+TENSOR_HIGH_BASE]
    ret
.vcra_fail:
    mov eax,-1
    ret

vec_cache_reg_free:
    sub edi,TENSOR_HIGH_BASE
    cmp edi,TENSOR_HIGH_COUNT-1
    ja .vcrf_done
    push rdi
    call tensor_release_transient_borrow
    pop rdi
    bts dword ptr [rip+vec_cache_reg_mask],edi
.vcrf_done:
    ret

vec_init_emit_u8:
TFC_vec_init_emit_u8
vec_emit_init_const:
    push rbx
    push r12
    mov ebx,edi
    mov r12,rsi
    # movabs rax,imm64
    mov edi,0x48; call vec_init_emit_u8
    mov edi,0xB8; call vec_init_emit_u8
    mov rax,[rip+vec_init_emit_ptr]
    lea rcx,[rax+8]
    cmp rcx,[rip+vec_init_emit_end]
    jbe .tcgrow_ok_5
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .veic_fail
.tcgrow_ok_5:
    mov [rax],r12
    mov [rip+vec_init_emit_ptr],rcx
    # Generic scalar->vector broadcast.  Use the 512-bit GPR-source form
    # directly instead of staging through XMM20..31.  This removes the old
    # accidental AVX512VL dependency: 512-bit tensor episodes only require the
    # foundation broadcast capability, not 128/256-bit EVEX vector-length forms.
    # Encoding: vpbroadcastq zmmD,rax (AVX512F).
    mov edi,0x62; call vec_init_emit_u8
    # Generic EVEX P0 for destination ZMM0..31. The previous emitter assumed
    # constants lived only in ZMM16..31; 1.3.7 also uses otherwise-idle
    # ZMM14..15, so both inverted R and R' destination bits are encoded.
    mov eax,0xF2
    test ebx,8
    jz .veic_gpr_no_r
    and eax,0x7F
.veic_gpr_no_r:
    test ebx,16
    jz .veic_gpr_p0
    and eax,0xEF
.veic_gpr_p0:
    mov edi,eax
    call vec_init_emit_u8
    mov edi,0xFD; call vec_init_emit_u8
    mov edi,0x48; call vec_init_emit_u8
    mov edi,0x7C; call vec_init_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call vec_init_emit_u8
    xor eax,eax
    pop r12
    pop rbx
    ret
.veic_fail:
    mov eax,1
    pop r12
    pop rbx
    ret

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
TFP_01_vec_vex2_rrr
vec_sqrtpd:
TFP_01_vec_sqrtpd
vec_vex3_0f38_rrr:
TFC_vec_vex3_0f38_rrr
vec_mov_ext:
TFP_01_vec_mov_ext
vec_keep_k1_zero:
TFP_01_vec_keep_k1_zero
vec_kortest_k1:
TFP_01_vec_kortest_k1
vec_broadcast_imm64:
    # Constants are deduplicated twice: once in the RIP-relative qword pool and,
    # when a persistent ZMM16..31 register is available, once in the physical
    # register file.  Reuses become a single register move instead of another
    # front-end broadcast/load.
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi                     # requested destination
    mov r12,rsi                     # qword bits
    cmp dword ptr [rip+physical_plan_pass],0
    jne .vbc_profile_done
    mov rsi,r12
    mov edi,PRC_LOAD_AGU_TICKS      # avoided hot constant load + address generation
    call tensor_profile_constant
.vbc_profile_done:
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
    # Existing resident constant?
    mov r8,[rip+vec_const_reg_ptr]
    mov eax,dword ptr [r8+r13*4]
    test eax,eax
    jz .vbc_try_resident
    dec eax
    mov esi,eax
    mov edi,ebx
    call vec_mov_ext
    xor eax,eax
    jmp .vbc_done
.vbc_try_resident:
    cmp dword ptr [rip+physical_plan_pass],0
    je .vbc_direct
    mov rsi,r12
    call tensor_const_selected
    test eax,eax; jz .vbc_direct
    call vec_persistent_reg_alloc
    cmp eax,-1
    je .vbc_direct
    mov r14d,eax                    # persistent physical constant register
    mov r8,[rip+vec_const_reg_ptr]
    lea eax,[r14d+1]
    mov dword ptr [r8+r13*4],eax
    mov edi,r14d
    mov rsi,r12
    call vec_emit_init_const
    test eax,eax
    jnz .vbc_resident_fail
    cmp ebx,r14d
    je .vbc_ok
    mov edi,ebx
    mov esi,r14d
    call vec_mov_ext
.vbc_ok:
    xor eax,eax
    jmp .vbc_done
.vbc_resident_fail:
    mov r8,[rip+vec_const_reg_ptr]
    mov dword ptr [r8+r13*4],0
    mov edi,r14d
    call vec_persistent_reg_free
    jmp .vbc_fail
.vbc_direct:
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
TFC_vec_const_intern
vec_const_get_reg:
    push rbx
    push r12
    push r13
    mov r12,rsi
    cmp dword ptr [rip+physical_plan_pass],0
    jne .vcgr_profile_done
    mov rsi,r12
    mov edi,PRC_LOAD_AGU_TICKS      # avoided memory-broadcast load + address generation
    call tensor_profile_constant
    mov eax,-1
    jmp .vcgr_done
.vcgr_profile_done:
    xor r13d,r13d
    mov ecx,dword ptr [rip+vec_const_count]
    mov r8,[rip+vec_const_bits_ptr]
.vcgr_find:
    cmp r13d,ecx
    jae .vcgr_new
    cmp qword ptr [r8+r13*8],r12
    je .vcgr_have
    inc r13d
    jmp .vcgr_find
.vcgr_new:
    cmp ecx,dword ptr [rip+tensor_optimizer_capacity]
    jae .vcgr_fail
    mov qword ptr [r8+rcx*8],r12
    mov r13d,ecx
    inc ecx
    mov dword ptr [rip+vec_const_count],ecx
.vcgr_have:
    mov r8,[rip+vec_const_reg_ptr]
    mov eax,dword ptr [r8+r13*4]
    test eax,eax
    jz .vcgr_allocate
    dec eax
    jmp .vcgr_done
.vcgr_allocate:
    mov rsi,r12
    call tensor_const_selected
    test eax,eax; jz .vcgr_fail
    call vec_persistent_reg_alloc
    cmp eax,-1
    je .vcgr_fail
    mov ebx,eax
    mov r8,[rip+vec_const_reg_ptr]
    lea ecx,[ebx+1]
    mov dword ptr [r8+r13*4],ecx
    mov edi,ebx
    mov rsi,r12
    call vec_emit_init_const
    test eax,eax
    jnz .vcgr_alloc_fail
    mov eax,ebx
    jmp .vcgr_done
.vcgr_alloc_fail:
    mov r8,[rip+vec_const_reg_ptr]
    mov dword ptr [r8+r13*4],0
    mov edi,ebx
    call vec_persistent_reg_free
.vcgr_fail:
    mov eax,-1
.vcgr_done:
    pop r13
    pop r12
    pop rbx
    ret

# vec_emit_const_load_index(edi=dst zmm, r13d=constant index)
vec_emit_const_load_index:
    push rbx
    push r12
    mov ebx,edi
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_cap_ok_1
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vecli_fail
.tfix_cap_ok_1:
    mov r12d,eax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov edi,0xFD; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
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
    jmp .vecli_fail
.tcgrow_ok_12:
    mov dword ptr [rax],0
    mov [rip+vec_emit_ptr],rcx
    inc dword ptr [rip+schedule_counts+4*7] # hot constant load
    inc dword ptr [rip+schedule_counts+4*8] # RIP-relative AGU
    xor eax,eax
    pop r12
    pop rbx
    ret
.vecli_fail:
    mov eax,1
    pop r12
    pop rbx
    ret

vec_finalize_constants:
TFP_023_vec_finalize_constants
vec_vpmullq:
TFP_01_vec_vpmullq
vec_vpmullq_native:
TFC_vec_vpmullq_native
vec_vpmuludq:
TFC_vec_vpmuludq
vec_vpsllq_imm:
TFP_01_vec_vpsllq_imm
vec_vpsrlq_imm:
TFP_01_vec_vpsrlq_imm
vec_vpaddq_mem_const:
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
    jmp .vpaqmc_fail
.tcgrow_ok_14:
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_direct_ok_1
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpaqmc_fail
.tfix_direct_ok_1:
    push rax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    # P0: dst R/R', memory X/B=1, map=0F(1).
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    # P1: W=1, ~src1.vvvv, pp=66h.
    mov eax,r12d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    # P2: 512-bit + embedded qword broadcast + src1.V'.
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x50
    mov edi,eax; call vec_emit_u8
    mov edi,0xD4; call vec_emit_u8
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
    jmp .vpaqmc_fail_nostack
.tcgrow_ok_15:
    mov dword ptr [rcx],0
    mov [rip+vec_emit_ptr],r8
    inc dword ptr [rip+schedule_counts+4*4] # AVX-512 integer ALU
    inc dword ptr [rip+schedule_counts+4*7] # qword constant load
    inc dword ptr [rip+schedule_counts+4*8] # RIP-relative AGU
    xor eax,eax
    jmp .vpaqmc_done
.vpaqmc_fail:
    mov eax,1
    jmp .vpaqmc_done
.vpaqmc_fail_nostack:
    mov eax,1
.vpaqmc_done:
    pop r13
    pop r12
    pop rbx
    ret

# EVEX vpandq zmm dst,src1,QWORD BCST [rip+const].
# Generic immutable-mask realization used by canonical modulo keys when the
# resident constant bank is full. edi=dst, esi=src1, edx=pool index.
vec_vpandq_mem_const:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+10]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_16
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpaqm_fail
.tcgrow_ok_16:
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_direct_ok_2
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpaqm_fail
.tfix_direct_ok_2:
    push rax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,r12d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x50
    mov edi,eax; call vec_emit_u8
    mov edi,0xDB; call vec_emit_u8
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
    jbe .tcgrow_ok_17
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpaqm_fail_nostack
.tcgrow_ok_17:
    mov dword ptr [rcx],0
    mov [rip+vec_emit_ptr],r8
    inc dword ptr [rip+schedule_counts+4*4]
    inc dword ptr [rip+schedule_counts+4*7]
    inc dword ptr [rip+schedule_counts+4*8]
    xor eax,eax
    jmp .vpaqm_done
.vpaqm_fail:
    mov eax,1
    jmp .vpaqm_done
.vpaqm_fail_nostack:
    mov eax,1
.vpaqm_done:
    pop r13
    pop r12
    pop rbx
    ret

# EVEX vpmullq zmm dst,src1,QWORD BCST [rip+const].
# edi=dst, esi=src1, edx=constant-pool index -> eax=0/1.
vec_vpmullq_mem_const:
TFP_01_vec_vpmullq_mem_const
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
    jbe .tcgrow_ok_18
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmqmc_native_fail
.tcgrow_ok_18:
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_direct_ok_3
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmqmc_native_fail
.tfix_direct_ok_3:
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
    jbe .tcgrow_ok_19
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vpmqmc_native_fail_nostack
.tcgrow_ok_19:
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
    mov ebx,edi
    mov r12d,esi
    mov r13,rdx
    test r13,r13
    jnz .vmcs_one
    mov edi,0xFB; mov esi,ebx; mov edx,r12d; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr              # src-src = 0
    xor eax,eax
    jmp .vmcs_done
.vmcs_one:
    cmp r13,1
    jne .vmcs_pow2
    cmp ebx,r12d
    je .vmcs_ok
    mov edi,ebx; mov esi,r12d; call vec_mov_ext
.vmcs_ok:
    xor eax,eax
    jmp .vmcs_done
.vmcs_pow2:
    lea rax,[r13-1]
    test rax,r13
    jnz .vmcs_pow2_pm1
    bsf rcx,r13
    mov edi,ebx; mov esi,r12d; mov edx,ecx; call vec_vpsllq_imm
    xor eax,eax
    jmp .vmcs_done
.vmcs_pow2_pm1:
    # Generic strength reduction for c = 2^k +/- 1. Two simple integer
    # vector operations can be preferable to a wide qword multiply and require
    # no extra persistent fact. This is coefficient-shape algebra, not a table.
    lea rax,[r13-1]
    test rax,rax
    jz .vmcs_unsupported
    mov rcx,rax
    dec rcx
    test rax,rcx
    jnz .vmcs_try_minus1
    bsf rcx,rax
    mov edi,ebx; mov esi,r12d; mov edx,ecx; call vec_vpsllq_imm
    test eax,eax; jnz .vmcs_unsupported
    mov edi,0xD4; mov esi,ebx; mov edx,ebx; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs_done
.vmcs_try_minus1:
    lea rax,[r13+1]
    test rax,rax
    jz .vmcs_unsupported
    mov rcx,rax
    dec rcx
    test rax,rcx
    jnz .vmcs_unsupported
    bsf rcx,rax
    mov edi,ebx; mov esi,r12d; mov edx,ecx; call vec_vpsllq_imm
    test eax,eax; jnz .vmcs_unsupported
    mov edi,0xFB; mov esi,ebx; mov edx,ebx; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .vmcs_done
.vmcs_unsupported:
    mov eax,1
.vmcs_done:
    pop r13
    pop r12
    pop rbx
    ret

# EVEX vmulpd zmm dst,src1,QWORD BCST [rip+const].
# edi=dst, esi=src1, edx=constant-pool index -> eax=0/1.
# Strict floating-point lowering uses this when an exact multiplicative constant
# is not resident.  It preserves the original operation and rounding point while
# removing the old "resident ZMM or reject" resource dependency.
vec_vmulpd_mem_const:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    # Preflight the complete 10-byte EVEX RIP-relative instruction and fixup.
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+10]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_20
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vmpdmc_fail
.tcgrow_ok_20:
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_direct_ok_4
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vmpdmc_fail
.tfix_direct_ok_4:
    push rax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    # P0: dst R/R', memory X/B=1, map=0F(1).
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    # P1: W=1, ~src1.vvvv, pp=66h. P2: 512-bit + qword broadcast.
    mov eax,r12d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x50
    mov edi,eax; call vec_emit_u8
    mov edi,0x59; call vec_emit_u8
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
    jbe .tcgrow_ok_21
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vmpdmc_fail_nostack
.tcgrow_ok_21:
    mov dword ptr [rcx],0
    mov [rip+vec_emit_ptr],r8
    inc dword ptr [rip+schedule_counts+4]     # FP multiply
    inc dword ptr [rip+schedule_counts+4*7]   # qword constant load
    inc dword ptr [rip+schedule_counts+4*8]   # RIP-relative AGU
    xor eax,eax
    jmp .vmpdmc_done
.vmpdmc_fail:
    mov eax,1
    jmp .vmpdmc_done
.vmpdmc_fail_nostack:
    mov eax,1
.vmpdmc_done:
    pop r13
    pop r12
    pop rbx
    ret

# EVEX vfmadd231pd zmm dst,src1,src2: dst = src1*src2 + dst.
# Operand encoding is validated against GNU as for low/high ZMM combinations.
vec_vfmadd231pd:
TFP_01_vec_vfmadd231pd
vec_vfnmadd231pd:
TFP_02_vec_vfnmadd231pd
vec_vfmadd231pd_mem_const:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_direct_ok_5
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vfmcm_fail
.tfix_direct_ok_5:
    push rax                       # fixup index
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    # P0: dst R/R', memory X/B are both 1, map=0F38(2).
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,2
    mov edi,eax; call vec_emit_u8
    # P1: W=1, ~src1 in vvvv, pp=66h.
    mov eax,r12d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    # P2: 512-bit + embedded qword broadcast + src1.V'.
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x50
    mov edi,eax; call vec_emit_u8
    mov edi,0xB8; call vec_emit_u8
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
    jbe .tcgrow_ok_22
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vfmcm_fail_nostack
.tcgrow_ok_22:
    mov dword ptr [rcx],0
    mov [rip+vec_emit_ptr],r8
    inc dword ptr [rip+schedule_counts+0]     # fused add
    inc dword ptr [rip+schedule_counts+4]     # fused multiply
    inc dword ptr [rip+schedule_counts+4*7]   # qword constant load
    inc dword ptr [rip+schedule_counts+4*8]   # RIP-relative AGU
    xor eax,eax
    jmp .vfmcm_done
.vfmcm_fail:
    # fixup index was not pushed when capacity was already exhausted.
    mov eax,1
    jmp .vfmcm_done
.vfmcm_fail_nostack:
    mov eax,1
.vfmcm_done:
    pop r13
    pop r12
    pop rbx
    ret

# EVEX vpminuq zmm dst,src1,src2. Used by exact reciprocal-mod correction.
vec_vpminuq:
TFP_01_vec_vpminuq
vec_vcvtqq2pd:
TFC_vec_vcvtqq2pd
vec_vcvtqq2pd_native:
TFC_vec_vcvtqq2pd_native
vec_vcvtqq2pd_synth:
TFP_01_vec_vcvtqq2pd_synth
vec_vpmovqd_ymm_from_zmm:
TFP_01_vec_vpmovqd_ymm_from_zmm
vec_vcvtdq2pd_zmm_from_ymm:
TFP_01_vec_vcvtdq2pd_zmm_from_ymm
vec_vpsrld_imm:
TFP_01_vec_vpsrld_imm
vec_roundpd_trunc_scalar_reg:
TFC_vec_roundpd_trunc_scalar_reg
vec_trunc_nonneg_pd_to_u64:
TFC_vec_trunc_nonneg_pd_to_u64
vec_trunc_nonneg_pd_to_u64_synth:
TFC_vec_trunc_nonneg_pd_to_u64_synth
vec_vrndscalepd_trunc:
TFP_01_vec_vrndscalepd_trunc
vec_vaddpd_mem_const:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+10]
    cmp rcx,[rip+vec_emit_end]
    jbe .tcgrow_ok_23
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vapdmc_fail
.tcgrow_ok_23:
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,dword ptr [rip+tensor_fixup_capacity]
    jb .tfix_direct_ok_6
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vapdmc_fail
.tfix_direct_ok_6:
    push rax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0x62; call vec_emit_u8
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,r12d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov eax,r12d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    or eax,0x50
    mov edi,eax; call vec_emit_u8
    mov edi,0x58; call vec_emit_u8
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
    jbe .tcgrow_ok_24
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .vapdmc_fail_nostack
.tcgrow_ok_24:
    mov dword ptr [rcx],0
    mov [rip+vec_emit_ptr],r8
    inc dword ptr [rip+schedule_counts+0]
    inc dword ptr [rip+schedule_counts+4*7]
    inc dword ptr [rip+schedule_counts+4*8]
    xor eax,eax
    jmp .vapdmc_done
.vapdmc_fail:
    mov eax,1
    jmp .vapdmc_done
.vapdmc_fail_nostack:
    mov eax,1
.vapdmc_done:
    pop r13
    pop r12
    pop rbx
    ret

vec_vcvttpd2qq:
TFC_vec_vcvttpd2qq
vec_cmp_eq_maskvec:
TFP_01_vec_cmp_eq_maskvec

vec_cmp_ge_u64_maskvec:
TFP_01_vec_cmp_ge_u64_maskvec
vec_cmp_f64_k1:
TFP_01_vec_cmp_f64_k1
vec_cmp_f64_maskvec:
TFP_01_vec_cmp_f64_maskvec
vec_mask_k1_to_qvec:
TFP_01_vec_mask_k1_to_qvec
expr_affine_axis_u64:
TFC_expr_affine_axis_u64
vec_interior_affine_residue_safe:
TFP_02_vec_interior_affine_residue_safe
expr_affine_axis_interior_u64:
TFP_02_expr_affine_axis_interior_u64
vec_axis_compose_key:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    cmp dword ptr [rip+vec_axis_root_valid],1
    jne .vack_no
    mov rdi,r12
    call expr_index_key_u64
    test ecx,ecx
    jz .vack_no
    mov r12,rax
    mov r13,rdx
    mov r14,r8
    # Reuse the one canonical affine/periodic composition authority.  Save the
    # aggregation context because map lowering may be nested inside its caller.
    mov rax,qword ptr [rip+vec_linear_ctx_c]; push rax
    mov rax,qword ptr [rip+vec_linear_ctx_d]; push rax
    mov rax,qword ptr [rip+vec_linear_ctx_mod]; push rax
    mov rax,qword ptr [rip+vec_axis_root_c]; mov qword ptr [rip+vec_linear_ctx_c],rax
    mov rax,qword ptr [rip+vec_axis_root_d]; mov qword ptr [rip+vec_linear_ctx_d],rax
    mov rax,qword ptr [rip+vec_axis_root_mod]; mov qword ptr [rip+vec_linear_ctx_mod],rax
    mov rdi,r12
    mov rsi,r13
    mov rdx,r14
    call vec_linear_compose_key
    mov r12,rax
    mov r13,rdx
    mov r14,r8
    mov r15d,ecx
    pop rax; mov qword ptr [rip+vec_linear_ctx_mod],rax
    pop rax; mov qword ptr [rip+vec_linear_ctx_d],rax
    pop rax; mov qword ptr [rip+vec_linear_ctx_c],rax
    mov rax,r12
    mov rdx,r13
    mov r8,r14
    mov ecx,r15d
    test ecx,ecx
    jz .vack_done
    # The physical root is already a canonical representative in [0,n).
    # (1*root+0) mod n is therefore the identity CoordinateFact, not a
    # periodic operation that deserves a runtime realization.
    cmp rax,1
    jne .vack_done
    test rdx,rdx
    jne .vack_done
    cmp r8,-1
    jne .vack_done
    xor r8d,r8d
    jmp .vack_done
.vack_no:
    xor eax,eax
    xor edx,edx
    xor r8d,r8d
    xor ecx,ecx
.vack_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Historical plain-affine helper retained only for nonperiodic callers.
# Periodic indexed maps use vec_axis_compose_key above.
vec_axis_compose_from_index:
TFC_vec_axis_compose_from_index
tensor_profile_constant:
    push rbx
    push r12
    push r13
    mov rbx,rsi
    mov r13d,edi
    mov ecx,dword ptr [rip+tensor_const_profile_count]
    xor r12d,r12d
.t_profile_constant_find:
    cmp r12d,ecx
    jae .t_profile_constant_add
    mov rax,qword ptr [rip+tensor_const_profile_bits_ptr]
    cmp qword ptr [rax+r12*8],rbx
    je .t_profile_constant_hit
    inc r12d
    jmp .t_profile_constant_find
.t_profile_constant_add:
    cmp ecx,dword ptr [rip+tensor_optimizer_capacity]
    jae .t_profile_constant_done
    mov rax,qword ptr [rip+tensor_const_profile_bits_ptr]
    mov qword ptr [rax+rcx*8],rbx
    mov rax,qword ptr [rip+tensor_const_profile_score_ptr]
    mov dword ptr [rax+rcx*4],r13d
    inc ecx
    mov dword ptr [rip+tensor_const_profile_count],ecx
    jmp .t_profile_constant_done
.t_profile_constant_hit:
    mov rax,qword ptr [rip+tensor_const_profile_score_ptr]
    add dword ptr [rax+r12*4],r13d
.t_profile_constant_done:
    pop r13
    pop r12
    pop rbx
    ret

# 1.3.49 unified Sparse Physical Materialization selector.
# Persistent budget is not a profile or count threshold: it is the architectural
# high-bank capacity minus the transient peak measured by the disposable pass-0
# lowering of this exact DAG. BindingFact, AffineFact and ConstantFact compete
# in one positive-savings order; no category owns reserved carriers.
tensor_select_persistent_facts:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword ptr [rip+tensor_induct_selected_count],0
    mov dword ptr [rip+tensor_const_selected_count],0
    # One measured architectural bank.  A plain AffineFact owns one carrier;
    # a periodic AffineFact owns value+step and therefore consumes two real
    # registers.  Capacity is physical ownership, not a workload threshold.
    mov eax,TENSOR_HIGH_COUNT
    sub eax,dword ptr [rip+tensor_transient_peak]
    jns .t_select_persistent_budget_ok
    xor eax,eax
.t_select_persistent_budget_ok:
    mov dword ptr [rip+tensor_persistent_budget],eax
    mov dword ptr [rip+tensor_persistent_remaining],0
    xor ebx,ebx                    # real registers already committed
.t_select_persistent_pick:
    cmp ebx,dword ptr [rip+tensor_persistent_budget]
    jae .t_select_persistent_done
    mov r12d,-1                    # 0=AffineFact, 1=ConstantFact
    mov r13d,-1                    # candidate index
    xor r14d,r14d                  # best positive saved-work ticks

    xor r15d,r15d
.t_select_persistent_affine_scan:
    cmp r15d,dword ptr [rip+tensor_affine_profile_count]
    jae .t_select_persistent_const_begin
    mov rax,qword ptr [rip+tensor_affine_profile_uses_ptr]
    mov eax,dword ptr [rax+r15*4]
    test eax,eax
    jle .t_select_persistent_affine_next
    # Periodic recurrence needs value+step.  Admit it only when both real
    # carriers fit the same measured bank; no spill/compatibility route exists.
    mov r10d,1
    mov rax,qword ptr [rip+tensor_affine_profile_mod_ptr]
    cmp qword ptr [rax+r15*8],-1
    jne .t_select_persistent_affine_fit
    mov r10d,2
.t_select_persistent_affine_fit:
    mov eax,dword ptr [rip+tensor_persistent_budget]
    sub eax,ebx
    cmp eax,r10d
    jb .t_select_persistent_affine_next
    mov rax,qword ptr [rip+tensor_affine_profile_uses_ptr]
    mov eax,dword ptr [rax+r15*4]
    imul eax,eax,PRC_INT_MUL_LOAD_AGU_TICKS
    sub eax,PRC_INT_ALU_TICKS
    jle .t_select_persistent_affine_next
    cmp eax,r14d
    jbe .t_select_persistent_affine_next
    mov r14d,eax
    xor r12d,r12d
    mov r13d,r15d
.t_select_persistent_affine_next:
    inc r15d
    jmp .t_select_persistent_affine_scan

.t_select_persistent_const_begin:
    mov eax,dword ptr [rip+tensor_persistent_budget]
    sub eax,ebx
    test eax,eax
    jz .t_select_persistent_have_best
    xor r15d,r15d
.t_select_persistent_const_scan:
    cmp r15d,dword ptr [rip+tensor_const_profile_count]
    jae .t_select_persistent_have_best
    mov rax,qword ptr [rip+tensor_const_profile_score_ptr]
    mov eax,dword ptr [rax+r15*4]
    test eax,eax
    jle .t_select_persistent_const_next
    cmp eax,r14d
    jbe .t_select_persistent_const_next
    mov r14d,eax
    mov r12d,1
    mov r13d,r15d
.t_select_persistent_const_next:
    inc r15d
    jmp .t_select_persistent_const_scan

.t_select_persistent_have_best:
    cmp r12d,-1
    je .t_select_persistent_done
    test r14d,r14d
    jz .t_select_persistent_done
    test r12d,r12d
    jz .t_select_persistent_mark_affine
    mov rax,qword ptr [rip+tensor_const_profile_bits_ptr]
    mov rdx,qword ptr [rax+r13*8]
    mov rax,qword ptr [rip+tensor_const_profile_score_ptr]
    mov dword ptr [rax+r13*4],0
    mov ecx,dword ptr [rip+tensor_const_selected_count]
    lea rax,[rip+tensor_const_selected_bits]
    mov qword ptr [rax+rcx*8],rdx
    inc ecx
    mov dword ptr [rip+tensor_const_selected_count],ecx
    inc ebx
    jmp .t_select_persistent_pick

.t_select_persistent_mark_affine:
    mov rax,qword ptr [rip+tensor_affine_profile_coeff_ptr]
    mov rdx,qword ptr [rax+r13*8]
    mov rax,qword ptr [rip+tensor_affine_profile_uses_ptr]
    mov dword ptr [rax+r13*4],0
    mov ecx,dword ptr [rip+tensor_induct_selected_count]
    lea rax,[rip+tensor_induct_selected_coeff]
    mov qword ptr [rax+rcx*8],rdx
    mov rax,qword ptr [rip+tensor_affine_profile_offset_ptr]
    mov rdx,qword ptr [rax+r13*8]
    lea rax,[rip+tensor_induct_selected_offset]
    mov qword ptr [rax+rcx*8],rdx
    mov rax,qword ptr [rip+tensor_affine_profile_mod_ptr]
    mov rdx,qword ptr [rax+r13*8]
    lea rax,[rip+tensor_induct_selected_mod]
    mov qword ptr [rax+rcx*8],rdx
    inc ecx
    mov dword ptr [rip+tensor_induct_selected_count],ecx
    inc ebx
    cmp rdx,-1
    jne .t_select_persistent_pick
    inc ebx                         # periodic step carrier
    jmp .t_select_persistent_pick
.t_select_persistent_done:
    mov dword ptr [rip+tensor_persistent_remaining],ebx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# rsi=exact qword bits -> eax 1 iff pass-0 profitability selected residency.
tensor_const_selected:
    xor ecx,ecx
.t_const_selected_loop:
    cmp ecx,dword ptr [rip+tensor_const_selected_count]
    jae .t_const_selected_no
    lea rax,[rip+tensor_const_selected_bits]
    cmp qword ptr [rax+rcx*8],rsi
    je .t_const_selected_yes
    inc ecx
    jmp .t_const_selected_loop
.t_const_selected_yes:
    mov eax,1
    ret
.t_const_selected_no:
    xor eax,eax
    ret

# 1.3.7 pass-0 affine-use profiler. rsi=nontrivial composed coefficient.
# Exact coefficient bits are identity only; no numeric coefficient is privileged.
tensor_profile_affine_coeff:
    push rbx
    push r12
    push r13
    push r14
    mov rbx,rsi                    # coefficient
    mov r13,rdx                    # offset identity
    mov r14,rcx                    # modulus identity
    mov ecx,dword ptr [rip+tensor_affine_profile_count]
    xor r12d,r12d
.t_profile_affine_find:
    cmp r12d,ecx
    jae .t_profile_affine_add
    mov rax,qword ptr [rip+tensor_affine_profile_coeff_ptr]
    cmp qword ptr [rax+r12*8],rbx
    jne .t_profile_affine_next
    mov rax,qword ptr [rip+tensor_affine_profile_offset_ptr]
    cmp qword ptr [rax+r12*8],r13
    jne .t_profile_affine_next
    mov rax,qword ptr [rip+tensor_affine_profile_mod_ptr]
    cmp qword ptr [rax+r12*8],r14
    je .t_profile_affine_hit
.t_profile_affine_next:
    inc r12d
    jmp .t_profile_affine_find
.t_profile_affine_add:
    cmp ecx,dword ptr [rip+tensor_optimizer_capacity]
    jae .t_profile_affine_done
    mov rax,qword ptr [rip+tensor_affine_profile_coeff_ptr]
    mov qword ptr [rax+rcx*8],rbx
    mov rax,qword ptr [rip+tensor_affine_profile_offset_ptr]
    mov qword ptr [rax+rcx*8],r13
    mov rax,qword ptr [rip+tensor_affine_profile_mod_ptr]
    mov qword ptr [rax+rcx*8],r14
    mov rax,qword ptr [rip+tensor_affine_profile_uses_ptr]
    mov dword ptr [rax+rcx*4],1
    inc ecx
    mov dword ptr [rip+tensor_affine_profile_count],ecx
    jmp .t_profile_affine_done
.t_profile_affine_hit:
    mov rax,qword ptr [rip+tensor_affine_profile_uses_ptr]
    inc dword ptr [rax+r12*4]
.t_profile_affine_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# rsi=coefficient, rdx=offset identity, rcx=modulus identity -> eax 1 iff selected.
tensor_induct_selected:
    xor r8d,r8d
.t_induct_selected_loop:
    cmp r8d,dword ptr [rip+tensor_induct_selected_count]
    jae .t_induct_selected_no
    lea rax,[rip+tensor_induct_selected_coeff]
    cmp qword ptr [rax+r8*8],rsi
    jne .t_induct_selected_next
    lea rax,[rip+tensor_induct_selected_offset]
    cmp qword ptr [rax+r8*8],rdx
    jne .t_induct_selected_next
    lea rax,[rip+tensor_induct_selected_mod]
    cmp qword ptr [rax+r8*8],rcx
    je .t_induct_selected_yes
.t_induct_selected_next:
    inc r8d
    jmp .t_induct_selected_loop
.t_induct_selected_yes:
    mov eax,1
    ret
.t_induct_selected_no:
    xor eax,eax
    ret

# vec_induct_get_reg(rsi=coefficient, rdx=offset identity, rcx=modulus identity)
# -> eax=persistent value carrier or -1.  Plain affine facts use (c,0,0).
# Periodic facts use (c,d,-1) and own one additional persistent step carrier;
# both are allocated from the same measured high-bank authority.
vec_induct_get_reg:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx,rsi                    # c
    mov r14,rdx                    # d identity
    mov r15,rcx                    # mod identity
    cmp dword ptr [rip+vec_fused_mode],1
    jne .vigr_fail
    cmp r15,-1
    je .vigr_identity_ok
    cmp rbx,1
    jbe .vigr_fail
.vigr_identity_ok:

    cmp dword ptr [rip+physical_plan_pass],0
    jne .vigr_canonical
    mov rsi,rbx
    mov rdx,r14
    mov rcx,r15
    call tensor_profile_affine_coeff
    jmp .vigr_fail

.vigr_canonical:
    mov rsi,rbx
    mov rdx,r14
    mov rcx,r15
    call tensor_induct_selected
    test eax,eax
    jz .vigr_fail
    mov ecx,dword ptr [rip+vec_induct_count]
    xor r12d,r12d
.vigr_find:
    cmp r12d,ecx
    jae .vigr_add
    lea rax,[rip+vec_induct_coeff]
    cmp qword ptr [rax+r12*8],rbx
    jne .vigr_next
    lea rax,[rip+vec_induct_offset]
    cmp qword ptr [rax+r12*8],r14
    jne .vigr_next
    lea rax,[rip+vec_induct_mod]
    cmp qword ptr [rax+r12*8],r15
    je .vigr_found
.vigr_next:
    inc r12d
    jmp .vigr_find
.vigr_add:
    cmp ecx,TENSOR_HIGH_COUNT
    jae .vigr_fail
    mov r12d,ecx
    cmp r15,-1
    je .vigr_alloc
    mov rax,rbx
    mov rdx,8
    mul rdx
    test rdx,rdx
    jnz .vigr_fail
.vigr_alloc:
    call vec_persistent_reg_alloc
    cmp eax,-1
    je .vigr_fail
    mov r13d,eax                   # value carrier
    mov edx,-1                     # step carrier absent for plain affine
    cmp r15,-1
    jne .vigr_store
    call vec_persistent_reg_alloc
    cmp eax,-1
    jne .vigr_have_step
    mov edi,r13d
    call vec_persistent_reg_free
    jmp .vigr_fail
.vigr_have_step:
    mov edx,eax
.vigr_store:
    lea rax,[rip+vec_induct_coeff]
    mov qword ptr [rax+r12*8],rbx
    lea rax,[rip+vec_induct_offset]
    mov qword ptr [rax+r12*8],r14
    lea rax,[rip+vec_induct_mod]
    mov qword ptr [rax+r12*8],r15
    lea rax,[rip+vec_induct_reg]
    mov dword ptr [rax+r12*4],r13d
    lea rax,[rip+vec_induct_step_reg]
    mov dword ptr [rax+r12*4],edx
    mov eax,r12d
    inc eax
    mov dword ptr [rip+vec_induct_count],eax
.vigr_found:
    lea rax,[rip+vec_induct_reg]
    mov eax,dword ptr [rax+r12*4]
    jmp .vigr_done
.vigr_fail:
    mov eax,-1
.vigr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Emit the affine value local_c*(logical axis)+local_d from the physical root
# ZMM6. In the fused-episode ABI, proven nontrivial composed coefficients may
# use persistent induction carriers from the shared ZMM16..25 ownership pool.
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

    # Prefer a cross-vector carrier for nontrivial composed coefficients.  The
    # carrier contains c*root for the current SIMD block and is advanced by c*8
    # at the fused-loop back edge.
    mov dword ptr [rip+vec_affine_induct_reg],-1
    mov rsi,r14
    xor edx,edx
    xor ecx,ecx
    call vec_induct_get_reg
    mov dword ptr [rip+vec_affine_induct_reg],eax

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
    # When an offset follows an induction carrier, AVX-512 can realize
    # dst = carrier + offset directly. Do not create a copy merely to make the
    # old two-address-shaped emitter comfortable.
    test r13,r13
    jz .veac_induct_copy_only
    test r12d,r12d
    js .veac_induct_add_mem
    cmp r12d,0x7fffffff
    je .veac_fail
    mov edi,0xD4; mov esi,ebx; mov edx,eax; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    jmp .veac_ok
.veac_induct_add_mem:
    mov edx,r12d
    and edx,0x7fffffff
    mov edi,ebx
    mov esi,eax
    call vec_vpaddq_mem_const
    test eax,eax
    jnz .veac_fail
    jmp .veac_ok
.veac_induct_copy_only:
    mov edi,ebx
    mov esi,eax
    call vec_mov_ext
    jmp .veac_have_product
.veac_no_induct:
    # Unit coefficient plus nonzero offset is likewise one 3-operand VPADDQ,
    # not MOV(root,dst) followed by ADD(dst,offset).
    cmp r14,1
    jne .veac_no_unit_direct
    test r13,r13
    jz .veac_no_unit_direct
    test r12d,r12d
    js .veac_unit_add_mem
    cmp r12d,0x7fffffff
    je .veac_fail
    mov edi,0xD4; mov esi,ebx; mov edx,6; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    jmp .veac_ok
.veac_unit_add_mem:
    mov edx,r12d
    and edx,0x7fffffff
    mov edi,ebx
    mov esi,6
    call vec_vpaddq_mem_const
    test eax,eax
    jnz .veac_fail
    jmp .veac_ok
.veac_no_unit_direct:
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
TFP_02_expr_affine_modn_form
vec_modn_fixed_normalize_d:
TFP_02_vec_modn_fixed_normalize_d
expr_index_key_u64:
TFP_02_expr_index_key_u64
vec_save_axis:
TFC_vec_save_axis
vec_restore_axis:
TFC_vec_restore_axis
vec_cache_lookup:
TFP_01_vec_cache_lookup
vec_cache_add:
TFP_01_vec_cache_add
vec_index_cache_lookup:
TFP_01_vec_index_cache_lookup
vec_index_cache_add:
TFP_01_vec_index_cache_add
vec_index_value_cache_lookup:
TFP_01_vec_index_value_cache_lookup
vec_index_value_cache_add:
TFP_01_vec_index_value_cache_add
vec_cache_free_current:
TFP_01_vec_cache_free_current
vec_try_int_source:
TFP_02_vec_try_int_source
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
    mov rdi,rbx; lea rsi,[rip+k_load]; mov edx,k_load_end-k_load; call obj_get
    test rax,rax; jz .vtfs_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call find_binding
    test rax,rax; jz .vtfs_no
    mov r12,rax
    cmp dword ptr [r12+16],OP_MAP; jne .vtfs_no
    mov rdi,rbx; lea rsi,[rip+k_indices]; mov edx,k_indices_end-k_indices; call obj_get
    test rax,rax; jz .vtfs_no
    mov rbx,[rax+24]; test rbx,rbx; jz .vtfs_no
    cmp qword ptr [rbx+32],0; jne .vtfs_no
    mov rdi,rbx; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .vtfs_indexed
    mov rdi,r12
    call vec_cache_lookup
    jmp .vtfs_done
.vtfs_indexed:
    # 1.3.7: an indexed ValueFact already resident in the parent generation is
    # also a legal direct three-operand source. Do not copy it merely because
    # the consumer asked through a different expression subtree.
    mov rdi,rbx
    call expr_index_key_u64
    test ecx,ecx; jz .vtfs_no
    push rax; push rdx; push r8
    mov rdi,r12
    mov rsi,[rsp+16]
    mov rdx,[rsp+8]
    mov rcx,[rsp]
    call vec_index_value_cache_lookup
    add rsp,24
    jmp .vtfs_done
.vtfs_no:
    mov eax,-1
.vtfs_done:
    pop r12
    pop rbx
    ret

# emit_vec_predicate_k1(rdi=expr) -> eax: 0 emitted, 1 unsupported, 2 failure
# This is the control authority of the same Rank-N PredicateFact represented by
# emit_vec_int for value consumers.  The initial closure is the complete f64
# comparison family; unsupported boolean algebra simply keeps the ordinary
# exact-bit value path rather than growing a compatibility backend.
emit_vec_predicate_k1:
TFP_01_emit_vec_predicate_k1
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
    cmp dword ptr [rip+vec_axis_root_valid],1; jne .evi_axis_copy
    cmp qword ptr [rip+vec_axis_root_c],1; jne .evi_axis_fact
    cmp qword ptr [rip+vec_axis_root_d],0; jne .evi_axis_fact
    cmp qword ptr [rip+vec_axis_root_mod],0; jne .evi_axis_fact
.evi_axis_copy:
    mov edi,r13d; mov esi,dword ptr [rip+vec_axis_reg]; call vec_mov_ext
    jmp .evi_ok
.evi_axis_fact:
    mov edi,r13d
    mov rsi,qword ptr [rip+vec_axis_root_c]
    mov rdx,qword ptr [rip+vec_axis_root_d]
    mov rcx,qword ptr [rip+vec_axis_root_mod]
    call vec_emit_periodic_key
    test eax,eax; jnz .evi_fail
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
    cmp qword ptr [rip+vec_axis_root_mod],0
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
    test eax,eax; jz .evi_mod
.evi_select_general:
    call vec_alloc; cmp eax,-1; je .evi_fail; mov ebx,eax       # cond
    call vec_alloc; cmp eax,-1; je .evi_free_b_fail; mov r14d,eax # false
    mov rdi,r15; mov esi,ebx; call emit_vec_int; test eax,eax; jnz .evi_free2_fail
    mov r15,[r15+32]; test r15,r15; jz .evi_free2_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_free2_fail
    mov r15,[r15+32]; test r15,r15; jz .evi_free2_fail
    mov rdi,r15; mov esi,r14d; call emit_vec_int; test eax,eax; jnz .evi_free2_fail
    # true &= cond
    mov edi,0xDB; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    # cond = ~cond & false
    mov edi,0xDF; mov esi,ebx; mov edx,ebx; mov ecx,r14d; mov r8d,1; call vec_vex2_rrr
    # true |= cond
    mov edi,0xEB; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
    mov edi,r14d; call vec_free; mov edi,ebx; call vec_free
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

# Physical capability hook for periodic AffineFact residency. AVX-512 reuses
# the unified persistent AffineFact authority; profiles without such a carrier
# domain expose the same hook and naturally retain exact materialization.
vec_periodic_induct_get_reg:
    jmp vec_induct_get_reg

# vec_emit_periodic_key(edi=dst,rsi=c,rdx=d,rcx=modtoken) -> eax=0/1.
# Materialize one canonical operator direction directly from the physical root
# ZMM6. This is a realization of the generic key, not a periodic-workload fast
# path. modtoken=-1 denotes external n; positive literal moduli use exact
# power-of-two masking in the current native slice.
.include "compiler/tensor_frontend_periodic_exact.inc"

vec_emit_periodic_key:
TFP_02_vec_emit_periodic_key
vec_linear_operator_expr:
TFC_vec_linear_operator_expr
vec_linear_modulus_value:
TFP_02_vec_linear_modulus_value
vec_linear_mul_mod:
TFC_vec_linear_mul_mod
vec_linear_add_mod:
TFC_vec_linear_add_mod
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
    # Coordinate offsets are signed representatives in Z/nZ.  Keep coefficient
    # multiplication exact, but compose the offset in the signed domain so
    # (+c) followed by (-c) canonicalizes instead of leaking unsigned carry
    # into a false structural rejection.
    mov rax,qword ptr [rip+vec_linear_ctx_d]
    imul rax,r12
    jo .vlck_no
    add rax,r13
    jo .vlck_no
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
    mov rax,qword ptr [rip+vec_linear_ctx_d]
    imul rax,r12
    jo .vlck_no
    add rax,r13
    jo .vlck_no
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
TFC_vec_linear_add_term
vec_linear_collect:
TFC_vec_linear_collect
vec_linear_txn_begin:
    mov rax,qword ptr [rip+vec_emit_ptr]; mov qword ptr [rip+vec_txn_emit_ptr],rax
    mov rax,qword ptr [rip+vec_init_emit_ptr]; mov qword ptr [rip+vec_txn_init_ptr],rax
    mov eax,dword ptr [rip+vec_reg_mask]; mov dword ptr [rip+vec_txn_reg_mask],eax
    mov eax,dword ptr [rip+vec13_free]; mov dword ptr [rip+vec_txn_13_free],eax
    mov eax,dword ptr [rip+vec_cache_reg_mask]; mov dword ptr [rip+vec_txn_cache_reg_mask],eax
    mov eax,dword ptr [rip+vec_const_count]; mov dword ptr [rip+vec_txn_const_count],eax
    mov eax,dword ptr [rip+vec_fixup_count]; mov dword ptr [rip+vec_txn_fixup_count],eax
    mov eax,dword ptr [rip+vec_cache_count]; mov dword ptr [rip+vec_txn_cache_count],eax
    mov eax,dword ptr [rip+vec_current_gen]; mov dword ptr [rip+vec_txn_current_gen],eax
    mov eax,dword ptr [rip+vec_gen_counter]; mov dword ptr [rip+vec_txn_gen_counter],eax
    mov eax,dword ptr [rip+vec_axis_root_valid]; mov dword ptr [rip+vec_txn_axis_valid],eax
    mov rax,qword ptr [rip+vec_axis_root_c]; mov qword ptr [rip+vec_txn_axis_c],rax
    mov rax,qword ptr [rip+vec_axis_root_d]; mov qword ptr [rip+vec_txn_axis_d],rax
    mov rax,qword ptr [rip+vec_axis_root_mod]; mov qword ptr [rip+vec_txn_axis_mod],rax
    mov eax,dword ptr [rip+vec_axis_reg]; mov dword ptr [rip+vec_txn_axis_reg],eax
    mov eax,dword ptr [rip+vec_induct_count]; mov dword ptr [rip+vec_txn_induct_count],eax
    lea rsi,[rip+vec_induct_coeff]; lea rdi,[rip+vec_txn_induct_coeff]; mov ecx,8; rep movsq
    lea rsi,[rip+vec_induct_offset]; lea rdi,[rip+vec_txn_induct_offset]; mov ecx,8; rep movsq
    lea rsi,[rip+vec_induct_mod]; lea rdi,[rip+vec_txn_induct_mod]; mov ecx,8; rep movsq
    lea rsi,[rip+vec_induct_reg]; lea rdi,[rip+vec_txn_induct_reg]; mov ecx,8; rep movsd
    lea rsi,[rip+vec_induct_step_reg]; lea rdi,[rip+vec_txn_induct_step_reg]; mov ecx,8; rep movsd
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
    mov eax,dword ptr [rip+vec_txn_cache_reg_mask]; mov dword ptr [rip+vec_cache_reg_mask],eax
    mov eax,dword ptr [rip+vec_txn_const_count]; mov dword ptr [rip+vec_const_count],eax
    mov eax,dword ptr [rip+vec_txn_fixup_count]; mov dword ptr [rip+vec_fixup_count],eax
    mov eax,dword ptr [rip+vec_txn_cache_count]; mov dword ptr [rip+vec_cache_count],eax
    mov eax,dword ptr [rip+vec_txn_current_gen]; mov dword ptr [rip+vec_current_gen],eax
    mov eax,dword ptr [rip+vec_txn_gen_counter]; mov dword ptr [rip+vec_gen_counter],eax
    mov eax,dword ptr [rip+vec_txn_axis_valid]; mov dword ptr [rip+vec_axis_root_valid],eax
    mov rax,qword ptr [rip+vec_txn_axis_c]; mov qword ptr [rip+vec_axis_root_c],rax
    mov rax,qword ptr [rip+vec_txn_axis_d]; mov qword ptr [rip+vec_axis_root_d],rax
    mov rax,qword ptr [rip+vec_txn_axis_mod]; mov qword ptr [rip+vec_axis_root_mod],rax
    mov eax,dword ptr [rip+vec_txn_axis_reg]; mov dword ptr [rip+vec_axis_reg],eax
    mov eax,dword ptr [rip+vec_txn_induct_count]; mov dword ptr [rip+vec_induct_count],eax
    lea rsi,[rip+vec_txn_induct_coeff]; lea rdi,[rip+vec_induct_coeff]; mov ecx,8; rep movsq
    lea rsi,[rip+vec_txn_induct_offset]; lea rdi,[rip+vec_induct_offset]; mov ecx,8; rep movsq
    lea rsi,[rip+vec_txn_induct_mod]; lea rdi,[rip+vec_induct_mod]; mov ecx,8; rep movsq
    lea rsi,[rip+vec_txn_induct_reg]; lea rdi,[rip+vec_induct_reg]; mov ecx,8; rep movsd
    lea rsi,[rip+vec_txn_induct_step_reg]; lea rdi,[rip+vec_induct_step_reg]; mov ecx,8; rep movsd
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
    mov rax,qword ptr [rip+vec_axis_root_mod]; push rax
    mov dword ptr [rip+vec_axis_root_valid],1
    mov qword ptr [rip+vec_axis_root_c],r14
    mov qword ptr [rip+vec_axis_root_d],r15
    mov qword ptr [rip+vec_axis_root_mod],0
    mov rdi,[r12+40]
    mov esi,r13d
    call emit_vec_float
    mov r10d,eax
    pop rax; mov qword ptr [rip+vec_axis_root_mod],rax
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
    mov rax,qword ptr [rip+vec_axis_root_mod]; push rax
    mov dword ptr [rip+vec_axis_reg],r14d
    mov dword ptr [rip+vec_axis_root_valid],0
    mov qword ptr [rip+vec_axis_root_mod],0
    mov rdi,[r12+40]
    mov esi,r13d
    call emit_vec_float
    mov r10d,eax
    pop rax; mov qword ptr [rip+vec_axis_root_mod],rax
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
    test edx,edx; jz .evfa_div_have_recip
    mov rdi,rbx; call expr_literal_f64_bits
    test edx,edx; jnz .evfa_fallback
    call tolerant_recip_f64_bits
    test edx,edx; jnz .evfa_fallback
.evfa_div_have_recip:
    mov r14,rax
.evfa_scaled:
    call vec_alloc
    cmp eax,-1; je .evfa_fail
    mov ebx,eax
    mov rdi,r15; mov esi,ebx; call emit_vec_float
    test eax,eax; jnz .evfa_scaled_free_fail
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
    # General leaf: materialize once and add it.  This preserves support for
    # nonlinear leaves while still flattening the surrounding tolerant sum.
    call vec_alloc
    cmp eax,-1; je .evfa_fail
    mov ebx,eax
    mov rdi,r12; mov esi,ebx; call emit_vec_float
    test eax,eax; jnz .evfa_leaf_free_fail
    mov edi,0x58; mov esi,r13d; mov edx,r13d; mov ecx,ebx; mov r8d,1; call vec_vex2_rrr
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

    # Direct current-axis load: use generation-scoped CSE and avoid axis save entirely.
    mov rdi,r15; lea rsi,[rip+k_axis]; mov edx,k_axis_end-k_axis; call obj_get
    test rax,rax; jz .evf_load_indexed
    mov rdi,r14; call vec_cache_lookup
    cmp eax,-1; je .evf_direct_miss
    mov edi,r13d; mov esi,eax; call vec_mov_ext
    xor eax,eax; jmp .evf_done
.evf_direct_miss:
    # 1.3.7 Demand-Causal lifetime: a binding used once in the reachable Tensor
    # Physical Reality graph has no future consumer and therefore has no right
    # to occupy persistent ZMM authority. Compute it directly into the caller
    # destination instead of creating a speculative side copy.
    mov rdi,r14
    call tensor_binding_cache_profitable
    test eax,eax; jz .evf_direct_nocache
    # Repeated facts may retain one persistent authority copy when a register is
    # physically available; failure simply falls back to direct realization.
    call vec_cache_reg_alloc; cmp eax,-1; je .evf_direct_nocache
    mov r12d,eax
    # Direct pure-map expansion at the same current axis stays in the parent
    # coordinate generation.  This lets sibling direct maps share proven
    # topology-coordinate CSE (e.g. overlapping FEM neighborhoods) instead of
    # flushing the index cache at every map boundary.
    mov rdi,[r14+40]; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_direct_cache_fail
    mov edi,r12d; mov esi,r13d; call vec_mov_ext
    mov rdi,r14; mov esi,r12d; call vec_cache_add
    test eax,eax; jnz .evf_direct_cacheadd_fail
    xor eax,eax; jmp .evf_done
.evf_direct_cacheadd_fail:
    mov edi,r12d; call vec_cache_reg_free
    jmp .evf_fail
.evf_direct_cache_fail:
    mov edi,r12d; call vec_cache_reg_free
    jmp .evf_fail
.evf_direct_nocache:
    mov rdi,[r14+40]; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_fail
    xor eax,eax; jmp .evf_done

.evf_load_indexed:
    # Canonical CoordinateFact path.  If the index is affine/periodic in the
    # current logical coordinate, compose it symbolically and recurse without
    # manufacturing an intermediate SIMD index carrier.  This makes source
    # nesting depth a compile-time algebra property rather than a ZMM capacity.
    mov rdi,r15
    call vec_axis_compose_key
    test ecx,ecx
    jz .evf_index_materialized
    mov r12,rax
    mov r11,rdx
    mov r9,r8
    mov eax,dword ptr [rip+vec_axis_root_valid]; push rax
    mov rax,qword ptr [rip+vec_axis_root_c]; push rax
    mov rax,qword ptr [rip+vec_axis_root_d]; push rax
    mov rax,qword ptr [rip+vec_axis_root_mod]; push rax
    mov eax,dword ptr [rip+vec_current_gen]; push rax
    mov qword ptr [rip+vec_axis_root_c],r12
    mov qword ptr [rip+vec_axis_root_d],r11
    mov qword ptr [rip+vec_axis_root_mod],r9
    mov dword ptr [rip+vec_axis_root_valid],1
    inc dword ptr [rip+vec_gen_counter]
    mov eax,dword ptr [rip+vec_gen_counter]
    mov dword ptr [rip+vec_current_gen],eax
    mov rdi,[r14+40]; mov esi,r13d; call emit_vec_float
    mov r10d,eax
    call vec_cache_free_current
    pop rax; mov dword ptr [rip+vec_current_gen],eax
    pop rax; mov qword ptr [rip+vec_axis_root_mod],rax
    pop rax; mov qword ptr [rip+vec_axis_root_d],rax
    pop rax; mov qword ptr [rip+vec_axis_root_c],rax
    pop rax; mov dword ptr [rip+vec_axis_root_valid],eax
    mov eax,r10d
    jmp .evf_done
.evf_index_materialized:
    # First try strict-safe value CSE for the entire pure map load. This avoids
    # recursively rebuilding an identical indexed map even when tolerant
    # reassociation is disabled.
    mov rdi,r15
    call expr_index_key_u64
    test ecx,ecx
    jz .evf_index_value_miss
    push rax; push rdx; push r8
    mov rdi,r14
    mov rsi,[rsp+16]
    mov rdx,[rsp+8]
    mov rcx,[rsp]
    call vec_index_value_cache_lookup
    add rsp,24
    cmp eax,-1
    je .evf_index_value_miss
    mov edi,r13d; mov esi,eax; call vec_mov_ext
    xor eax,eax; jmp .evf_done
.evf_index_value_miss:
    # Then try a topology-coordinate cache. Equivalent affine/modulo index
    # expressions across sibling fields reuse one persistent ZMM index value.
    mov rdi,r15
    call expr_index_key_u64
    test ecx,ecx
    jz .evf_index_uncached
    push rax                       # c
    push rdx                       # d
    push r8                        # modulus token
    mov rdi,rax; mov rsi,rdx; mov rdx,r8
    call vec_index_cache_lookup
    cmp eax,-1
    jne .evf_index_cache_hit
    call vec_cache_reg_alloc
    cmp eax,-1
    je .evf_index_cache_no_reg
    mov ebx,eax
    mov rdi,r15; mov esi,ebx; call emit_vec_int
    test eax,eax
    jnz .evf_index_cache_emit_fail
    mov rdi,[rsp+16]
    mov rsi,[rsp+8]
    mov rdx,[rsp]
    mov ecx,ebx
    call vec_index_cache_add
    test eax,eax
    jnz .evf_index_cache_add_fail
    add rsp,24
    mov r10d,1                    # parent generation owns cached register
    jmp .evf_index_ready
.evf_index_cache_hit:
    mov ebx,eax
    add rsp,24
    mov r10d,1
    jmp .evf_index_ready
.evf_index_cache_add_fail:
    add rsp,24
    mov r10d,0                    # use as temporary, then release
    jmp .evf_index_ready
.evf_index_cache_emit_fail:
    add rsp,24
    mov edi,ebx; call vec_cache_reg_free
    jmp .evf_fail
.evf_index_cache_no_reg:
    add rsp,24
.evf_index_uncached:
    call vec_alloc; cmp eax,-1; je .evf_fail; mov ebx,eax
    mov rdi,r15; mov esi,ebx; call emit_vec_int
    test eax,eax; jnz .evf_index_meta_fail
    xor r10d,r10d
.evf_index_ready:
    push r10                       # ownership flag survives recursive lowering
    mov eax,dword ptr [rip+vec_axis_reg]
    push rax
    mov dword ptr [rip+vec_axis_reg],ebx
    mov eax,dword ptr [rip+vec_current_gen]
    push rax
    mov eax,dword ptr [rip+vec_axis_root_valid]
    push rax
    mov rax,qword ptr [rip+vec_axis_root_c]
    push rax
    mov rax,qword ptr [rip+vec_axis_root_d]
    push rax
    mov rdi,r15
    call vec_axis_compose_from_index
    inc dword ptr [rip+vec_gen_counter]
    mov eax,dword ptr [rip+vec_gen_counter]
    mov dword ptr [rip+vec_current_gen],eax
    mov rdi,[r14+40]; mov esi,r13d; call emit_vec_float
    push rax
    call vec_cache_free_current
    pop rdx
    pop rax
    mov qword ptr [rip+vec_axis_root_d],rax
    pop rax
    mov qword ptr [rip+vec_axis_root_c],rax
    pop rax
    mov dword ptr [rip+vec_axis_root_valid],eax
    pop rax
    mov dword ptr [rip+vec_current_gen],eax
    pop rax
    mov dword ptr [rip+vec_axis_reg],eax
    pop rcx
    test ecx,ecx
    jnz .evf_index_keep
    # Temporary may come from either primary or cache domain.
    cmp ebx,16
    jb .evf_index_free_primary
    mov edi,ebx; call vec_cache_reg_free
    jmp .evf_index_keep
.evf_index_free_primary:
    mov edi,ebx; call vec_free
.evf_index_keep:
    test edx,edx; jnz .evf_fail
    # Cache the completed pure-map value only when the AOT use graph proves a
    # future consumer. One-use values die immediately after this consumer.
    mov rdi,r14
    call tensor_binding_cache_profitable
    test eax,eax; jz .evf_index_value_done
    mov rdi,r15
    call expr_index_key_u64
    test ecx,ecx; jz .evf_index_value_done
    push rax; push rdx; push r8
    call vec_cache_reg_alloc
    cmp eax,-1; je .evf_index_value_drop_keys
    mov r11d,eax
    mov edi,r11d; mov esi,r13d; call vec_mov_ext
    mov rdi,r14
    mov rsi,[rsp+16]
    mov rdx,[rsp+8]
    mov rcx,[rsp]
    mov r8d,r11d
    call vec_index_value_cache_add
    test eax,eax; jz .evf_index_value_cached
    mov edi,r11d; call vec_cache_reg_free
.evf_index_value_cached:
    add rsp,24
    jmp .evf_index_value_done
.evf_index_value_drop_keys:
    add rsp,24
.evf_index_value_done:
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
    mov r14,r15                    # condition node
    mov r15,[r14+32]; test r15,r15; jz .evf_fail      # true expr
    mov r12,[r15+32]; test r12,r12; jz .evf_fail      # false expr

    # +0.0 false support is a true guarded Region. If the condition can retain
    # native k1 authority, an empty packet never realizes the true expression.
    # There is no density threshold: support emptiness is a mathematical fact.
    mov rdi,r12; call expr_literal_f64_bits
    test edx,edx; jnz .evf_select_general
    test rax,rax; jnz .evf_select_general
    mov rdi,r14; call emit_vec_predicate_k1
    cmp eax,1; je .evf_select_general
    cmp eax,2; je .evf_fail
    call vec_kortest_k1
    test eax,eax; jnz .evf_fail
    call vec_emit_je_placeholder
    test rax,rax; jz .evf_fail
    push rax
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evf_select_support_true_fail
    mov edi,r13d; call vec_keep_k1_zero
    test eax,eax; jnz .evf_select_support_true_fail
    call vec_emit_jmp_placeholder
    test rax,rax; jz .evf_select_support_true_fail
    push rax
    mov rdi,[rsp+8]
    mov rsi,qword ptr [rip+vec_emit_ptr]
    call vec_patch_rel32
    test eax,eax; jnz .evf_select_support_patch_fail
    mov edi,0xEF; mov esi,r13d; mov edx,r13d; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    mov rdi,[rsp]
    mov rsi,qword ptr [rip+vec_emit_ptr]
    call vec_patch_rel32
    test eax,eax; jnz .evf_select_support_patch_fail
    add rsp,16
    xor eax,eax; jmp .evf_done
.evf_select_support_patch_fail:
    add rsp,16
    jmp .evf_fail
.evf_select_support_true_fail:
    add rsp,8
    jmp .evf_fail

.evf_select_general:
    # Non-zero false arms and predicates without native control authority keep
    # the ordinary exact-bit ValueFact realization.
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

    # 1.3.7 tolerant exact-doubling realization. In tolerant FP only, a literal
    # 2.0 multiply is one VADDPD source,self instead of retaining/broadcasting a
    # constant plus VMULPD. Strict FP never enters this transform.
    cmp ebx,0x59
    jne .evf_not_exact_double
    cmp dword ptr [rip+tensor_tolerant_fp],0
    je .evf_not_exact_double
    mov rdi,r12
    call expr_mul_literal_other
    test ecx,ecx
    jz .evf_not_exact_double
    mov r11,0x4000000000000000
    cmp rax,r11
    jne .evf_not_exact_double
    mov rdi,rdx
    mov esi,r13d
    call emit_vec_float
    test eax,eax
    jnz .evf_fail
    mov edi,0x58
    mov esi,r13d
    mov edx,r13d
    mov ecx,r13d
    mov r8d,1
    call vec_vex2_rrr
    xor eax,eax
    jmp .evf_done
.evf_not_exact_double:

    # Repeated pure-load ValueFacts are handled by generation-scoped binding CSE;
    # no operator-specific square admission exists.
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
    # If both operands already have live PhysicalFact authority, issue the true
    # three-operand instruction directly. No cache->temporary copy is justified.
    mov rdi,r15; call vec_try_float_source
    mov r12d,eax
    cmp eax,-1; je .evf_one_source_paths
    mov rdi,r14; call vec_try_float_source
    mov r11d,eax
    cmp eax,-1; je .evf_one_source_paths
    mov edi,ebx; mov esi,r13d; mov edx,r12d; mov ecx,r11d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax; jmp .evf_done
.evf_one_source_paths:
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

    # 1.3.24 generic post-materialization ValueFact reuse.  Materializing the
    # left operand may establish a resident authority that is also the right
    # operand (or otherwise makes the right ValueFact resident).  Re-query the
    # ordinary ValueFact source after the left subtree is complete and consume
    # it directly; no operator kind, use-count, or workload shape is involved.
    mov rdi,r14; call vec_try_float_source
    cmp eax,-1; je .evf_regular_two_after_lhs_source
    mov r12d,eax
    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r12d; mov r8d,1
    call vec_vex2_rrr
    xor eax,eax; jmp .evf_done
.evf_regular_two_after_lhs_source:

    # Generic tolerant Product-Subtract Contraction. This is structural algebra,
    # not workload dispatch: sub(lhs, mul(a,b)) becomes one VFNMADD after lhs is
    # materialized. Strict mode retains original multiply + subtract rounding.
    # Resource shortage keeps the existing vector recipe; scalar fallback is not
    # introduced.
    cmp dword ptr [rip+tensor_tolerant_fp],0
    je .evf_regular_two_old
    cmp ebx,0x5C
    jne .evf_regular_two_old
    mov rdi,r14; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get
    test rax,rax; jz .evf_regular_two_old
    push rax
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq
    pop rax
    test eax,eax; jz .evf_regular_two_old
    mov rdi,r14; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get
    test rax,rax; jz .evf_regular_two_old
    mov r15,[rax+24]; test r15,r15; jz .evf_regular_two_old
    mov r14,[r15+32]; test r14,r14; jz .evf_regular_two_old
    cmp qword ptr [r14+32],0; jne .evf_regular_two_old

    call vec_alloc; cmp eax,-1; je .evf_regular_two_old
    mov r12d,eax
    call vec_alloc; cmp eax,-1; je .evf_product_sub_free_a
    mov ebx,eax
    mov rdi,r15; mov esi,r12d; call emit_vec_float
    test eax,eax; jnz .evf_product_sub_free_b_fail
    mov rdi,r14; mov esi,ebx; call emit_vec_float
    test eax,eax; jnz .evf_product_sub_free_b_fail
    mov edi,r13d; mov esi,r13d; mov edx,r12d; mov ecx,ebx; call vec_vfnmadd231pd
    mov edi,ebx; call vec_free
    mov edi,r12d; call vec_free
    inc dword ptr [rip+vec_product_subtract_contractions]
    xor eax,eax; jmp .evf_done
.evf_product_sub_free_b_fail:
    mov edi,ebx; call vec_free
.evf_product_sub_free_a_fail:
    mov edi,r12d; call vec_free
    jmp .evf_fail
.evf_product_sub_free_a:
    mov edi,r12d; call vec_free
.evf_regular_two_old:
    call vec_alloc; cmp eax,-1; je .evf_fail; mov r12d,eax
    mov rdi,r14; mov esi,r12d; call emit_vec_float; test eax,eax; jnz .evf_free_x_fail
    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r12d; mov r8d,1; call vec_vex2_rrr
    mov edi,r12d; call vec_free
    xor eax,eax; jmp .evf_done
.evf_free_x2_fail:
    mov edi,r14d; call vec_free
    jmp .evf_fail
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
TFP_02_emit_expr
emit_u8:
    mov rax,[rip+emit_ptr]
    cmp rax,[rip+emit_end]
    jb .tcgrow_ok_25
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_25:
    mov [rax],dil
    inc rax
    mov [rip+emit_ptr],rax
    xor eax,eax
    ret
.eu_fail: mov eax,1; ret
emit_u16:
    mov rax,[rip+emit_ptr]; lea rcx,[rax+2]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_26
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_26:
    mov [rax],di; mov [rip+emit_ptr],rcx; xor eax,eax; ret
emit_u24:
    mov rax,[rip+emit_ptr]; lea rcx,[rax+3]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_27
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_27:
    mov [rax],di; shr edi,16; mov [rax+2],dil; mov [rip+emit_ptr],rcx; xor eax,eax; ret
emit_u40:
    mov rax,[rip+emit_ptr]; lea rcx,[rax+5]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_28
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eu_fail
.tcgrow_ok_28:
    mov [rax],edi; shr rdi,32; mov [rax+4],dil; mov [rip+emit_ptr],rcx; xor eax,eax; ret
emit_push_imm64:
    push rdi
    mov edi,0xB848                  # 48 b8
    call emit_u16
    pop rdi
    mov rax,[rip+emit_ptr]; lea rcx,[rax+8]; cmp rcx,[rip+emit_end]
    jbe .tcgrow_ok_29
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .epi_fail
.tcgrow_ok_29:
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
    jbe .tcgrow_ok_30
    mov dword ptr [rip+tensor_code_overflow],1
    jmp .eb_fail
.tcgrow_ok_30:
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

.include "compiler/tensor_support_frontend.inc"

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
    cmp dword ptr [rip+tensor_vector_width],8
    jne .eti_fail
    cmp dword ptr [rip+tensor_support_mode],SUPPORT_INTERVAL
    je .eti_support_probe_kept
    xor r12d,r12d                   # no runtime scalar evaluator exists
.eti_support_probe_kept:

    xor r13d,r13d                   # vector bytes
    xor r14d,r14d                   # vector-init bytes
    cmp dword ptr [rip+tensor_vector_width],8
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

    # SupportFact is an AOT topology fact. Runtime only discovers exact IEEE
    # boundaries through the original predicate when this mode is nonzero.
    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_support_mode]
    mov edx,4
    mov r10d,RUNTIME_SUPPORT_MODE_OFF
    syscall
    cmp rax,4
    jne .eti_close_fail

    mov eax,SYS_pwrite64
    mov rdi,rbx
    lea rsi,[rip+tensor_support_count]
    mov edx,4
    mov r10d,RUNTIME_SUPPORT_COUNT_OFF
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

# 1.3.1 compile-time Physical Tensor body materializer.  It emits one complete
# boundary/interior vector body and frees only compile-time temporary ownership
# after ZMM0 has become the body result.  Persistent affine/constant carriers
# are not released.
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
    call vec_cache_free_current

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
    call vec_cache_free_current
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

# Group-internal packet body.  A packet strictly between the first and last
# packet of one contiguous Group cannot touch either global boundary.  This is
# a structural relation fact, so eliminate both boundary tests and the safe
# duplicate body at AOT rather than re-asking the same question at runtime.
emit_fused_vector_body_interior:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword ptr [rip+vec_interior_mode],1
    mov rax,[rip+tensor_reduce_binding]
    mov rdi,[rax+40]
    xor esi,esi
    call emit_vec_float
    test eax,eax; jnz .efvbi_fail
    call vec_cache_free_current
    mov dword ptr [rip+vec_interior_mode],0
    xor eax,eax
    jmp .efvbi_done
.efvbi_fail:
    mov dword ptr [rip+vec_interior_mode],0
    mov eax,1
.efvbi_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# edi=0/1 selects the true architectural reduction carrier.
emit_fused_reduce_carrier:
TFP_02_emit_fused_reduce_carrier
emit_fused_reduce_carrier_full:
    push rbx
    mov ebx,edi
    cmp dword ptr [rip+vec_product_subtract_contractions],0
    je .efrcf_frozen
    test ebx,ebx
    jnz .efrcf_resident_1
    lea rdi,[rip+vec_fused_full_reduce_resident_fragment]
    mov esi,vec_fused_full_reduce_resident_fragment_end-vec_fused_full_reduce_resident_fragment
    jmp .efrcf_emit
.efrcf_resident_1:
    lea rdi,[rip+vec_fused_full_reduce_resident_carrier1_fragment]
    mov esi,vec_fused_full_reduce_resident_carrier1_fragment_end-vec_fused_full_reduce_resident_carrier1_fragment
    jmp .efrcf_emit
.efrcf_frozen:
    test ebx,ebx
    jnz .efrcf_frozen_1
    lea rdi,[rip+vec_fused_full_reduce_fragment]
    mov esi,vec_fused_full_reduce_fragment_end-vec_fused_full_reduce_fragment
    jmp .efrcf_emit
.efrcf_frozen_1:
    lea rdi,[rip+vec_fused_full_reduce_carrier1_fragment]
    mov esi,vec_fused_full_reduce_carrier1_fragment_end-vec_fused_full_reduce_carrier1_fragment
.efrcf_emit:
    call vec_emit_bytes
    pop rbx
    ret

# Emit one eight-lane coordinate advance and return the JBE rel32 field in RAX.
# 1.3.1 execution-purity rule: SUB itself proves completion (borrow-or-zero),
# so no separate CMP is emitted on the hot control spine.
# The caller decides whether another body follows or whether this is the loop
# back-edge, so batching never introduces a runtime scheduler.
# Emit `remaining < group_body*8` as a forward tail edge. Return rel32 slot.
vec_emit_group_guard:
    mov rax,[rip+vec_emit_ptr]
    lea rcx,[rax+13]
    cmp rcx,[rip+vec_emit_end]
    jbe .vegg_space
    mov dword ptr [rip+tensor_code_overflow],1
    xor eax,eax
    ret
.vegg_space:
    mov word ptr [rax],0xB848       # movabs rax,imm64
    mov rdx,8
    mov ecx,dword ptr [rip+physical_realize_group_body]
    imul rdx,rcx
    mov qword ptr [rax+2],rdx
    mov byte ptr [rax+10],0x49      # cmp r8,rax
    mov byte ptr [rax+11],0x39
    mov byte ptr [rax+12],0xC0
    lea rdx,[rax+13]
    mov [rip+vec_emit_ptr],rdx
    call vec_emit_jb_placeholder
    ret

# Advance coordinates by one AVX-512 packet inside a proven full Group.
# Remaining-count ownership belongs to the Group episode, not its Vector
# members, so this helper deliberately emits no SUB/finish branch.
emit_fused_advance8_group_coordinates:
    push r12
    lea rdi,[rip+vec_fused_add_index8_fragment]
    mov esi,vec_fused_add_index8_fragment_end-vec_fused_add_index8_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efa8gc_fail
    mov rsi,8
    call vec_const_intern
    cmp eax,-1; je .efa8gc_fail
    mov edx,eax; mov edi,6; mov esi,6
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa8gc_fail
    xor r12d,r12d
.efa8gc_induct:
    cmp r12d,dword ptr [rip+vec_induct_count]
    jae .efa8gc_ok
    lea rax,[rip+vec_induct_mod]
    cmp qword ptr [rax+r12*8],-1
    je .efa8gc_periodic
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    mov rax,rsi
    mov rcx,TENSOR_PHYSICAL_LANES
    mul rcx
    test rdx,rdx; jnz .efa8gc_fail
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1; je .efa8gc_fail
    mov edx,eax
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa8gc_fail
    jmp .efa8gc_next
.efa8gc_periodic:
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    lea rax,[rip+vec_induct_step_reg]
    mov edx,dword ptr [rax+r12*4]
    cmp edx,-1; je .efa8gc_fail
    call vec_modadd_n
    test eax,eax; jnz .efa8gc_fail
.efa8gc_next:
    inc r12d
    jmp .efa8gc_induct
.efa8gc_ok:
    xor eax,eax
    pop r12
    ret
.efa8gc_fail:
    mov eax,1
    pop r12
    ret


# Emit the Group-level remaining-count update and back-edge.  The initial
# guard proves the first episode; after subtracting one complete Group, the
# comparison itself proves whether another complete Group remains.  No runtime
# scheduler or fixed-width candidate participates.
vec_emit_group_countdown_backedge:
    push rbx
    mov edx,8
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

emit_fused_advance8:
    push rbx
    push r12
    lea rdi,[rip+vec_fused_sub8_fragment]
    mov esi,vec_fused_sub8_fragment_end-vec_fused_sub8_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efa8_fail
    call vec_emit_jbe_placeholder
    test rax,rax; jz .efa8_fail
    mov rbx,rax
    lea rdi,[rip+vec_fused_add_index8_fragment]
    mov esi,vec_fused_add_index8_fragment_end-vec_fused_add_index8_fragment
    call vec_emit_bytes
    test eax,eax; jnz .efa8_fail
    mov rsi,8
    call vec_const_intern
    cmp eax,-1; je .efa8_fail
    mov edx,eax
    mov edi,6
    mov esi,6
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa8_fail
    xor r12d,r12d
.efa8_induct:
    cmp r12d,dword ptr [rip+vec_induct_count]
    jae .efa8_ok
    lea rax,[rip+vec_induct_mod]
    cmp qword ptr [rax+r12*8],-1
    je .efa8_periodic
    lea rax,[rip+vec_induct_coeff]
    mov rsi,qword ptr [rax+r12*8]
    mov rax,rsi
    mov rcx,TENSOR_PHYSICAL_LANES
    mul rcx
    test rdx,rdx; jnz .efa8_fail
    mov rsi,rax
    call vec_const_intern
    cmp eax,-1; je .efa8_fail
    mov edx,eax
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    call vec_vpaddq_mem_const
    test eax,eax; jnz .efa8_fail
    jmp .efa8_next
.efa8_periodic:
    lea rax,[rip+vec_induct_reg]
    mov edi,dword ptr [rax+r12*4]
    mov esi,edi
    lea rax,[rip+vec_induct_step_reg]
    mov edx,dword ptr [rax+r12*4]
    cmp edx,-1; je .efa8_fail
    call vec_modadd_n
    test eax,eax; jnz .efa8_fail
.efa8_next:
    inc r12d
    jmp .efa8_induct
.efa8_ok:
    mov rax,rbx
    jmp .efa8_done
.efa8_fail:
    xor eax,eax
.efa8_done:
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
# Relocatable fused-episode fragments. They contain only internal branches, so
# their relative displacements remain valid after byte-for-byte copy.
vec_fused_full_reduce_fragment:
TFP_01_vec_fused_full_reduce_fragment
vec_fused_full_reduce_fragment_end:

vec_fused_full_reduce_resident_fragment:
    vaddpd zmm12,zmm12,zmm0
vec_fused_full_reduce_resident_fragment_end:

vec_fused_full_reduce_carrier1_fragment:
    vextractf64x4 ymm3,zmm0,1
    vaddpd ymm13,ymm13,ymm0
    vaddpd ymm13,ymm13,ymm3
vec_fused_full_reduce_carrier1_fragment_end:

vec_fused_full_reduce_resident_carrier1_fragment:
    vaddpd zmm13,zmm13,zmm0
vec_fused_full_reduce_resident_carrier1_fragment_end:

vec_fused_mask_reduce_fragment:
TFP_01_vec_fused_mask_reduce_fragment
vec_fused_mask_reduce_fragment_end:

vec_fused_mask_reduce_resident_fragment:
    cmp r8,8
    jae .Lvfmrr_full
    mov rcx,r8
    mov rax,1
    shl rax,cl
    dec rax
    kmovq k1,rax
    vmovapd zmm0{k1}{z},zmm0
.Lvfmrr_full:
    vaddpd zmm12,zmm12,zmm0
vec_fused_mask_reduce_resident_fragment_end:


vec_fused_mask_reduce_carrier1_fragment:
    cmp r8,8
    jae .Lvfmr1_full
    mov rcx,r8
    mov rax,1
    shl rax,cl
    dec rax
    kmovq k1,rax
    vmovapd zmm0{k1}{z},zmm0
.Lvfmr1_full:
    vextractf64x4 ymm3,zmm0,1
    vaddpd ymm13,ymm13,ymm0
    vaddpd ymm13,ymm13,ymm3
vec_fused_mask_reduce_carrier1_fragment_end:

vec_fused_mask_reduce_resident_carrier1_fragment:
    cmp r8,8
    jae .Lvfmrr1_full
    mov rcx,r8
    mov rax,1
    shl rax,cl
    dec rax
    kmovq k1,rax
    vmovapd zmm0{k1}{z},zmm0
.Lvfmrr1_full:
    vaddpd zmm13,zmm13,zmm0
vec_fused_mask_reduce_resident_carrier1_fragment_end:

vec_fused_cmp8_fragment:
    cmp r8,8
vec_fused_cmp8_fragment_end:

vec_group_test_remaining_fragment:
    test r8,r8
vec_group_test_remaining_fragment_end:

vec_fused_sub8_fragment:
    sub r8,8
vec_fused_sub8_fragment_end:

# Boundary-region discriminator. RSI is the current global first-lane index and
# RDI is n. The fast path is valid iff start>0 and start+8<n.
vec_fused_boundary_test_zero_fragment:
    test rsi,rsi
vec_fused_boundary_test_zero_fragment_end:

vec_fused_boundary_test_end_fragment:
    lea rax,[rsi+8]
    cmp rax,rdi
vec_fused_boundary_test_end_fragment_end:

vec_fused_add_index8_fragment:
    add rsi,8
vec_fused_add_index8_fragment_end:

vec_fused_finish_fragment:
TFC_vec_fused_finish_fragment
vec_fused_finish_fragment_end:

vec_fused_finish_resident_fragment:
    vextractf64x4 ymm13,zmm12,1
    vaddpd ymm12,ymm12,ymm13
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
    vaddpd ymm12,ymm12,ymm13
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
    vaddpd zmm12,zmm12,zmm13
    vextractf64x4 ymm13,zmm12,1
    vaddpd ymm12,ymm12,ymm13
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
TFP_023_vec_fused_init_fragment
vec_fused_init_fragment_end:

vec_fused_init_resident_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd zmm12,zmm12,zmm12
vec_fused_init_resident_fragment_end:


vec_fused_init_dual_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
    vxorpd ymm13,ymm13,ymm13
vec_fused_init_dual_fragment_end:

vec_fused_init_resident_dual_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd zmm12,zmm12,zmm12
    vxorpd zmm13,zmm13,zmm13
vec_fused_init_resident_dual_fragment_end:

# Relocatable copied vector prologue. Relative displacement remains valid after copy.
vec_prefix_fragment:
TFP_01_vec_prefix_fragment
vec_prefix_fragment_end:
vec_movabs_rax: .byte 0x48,0xB8
vec_movabs_rax_end:
vec_save_axis_code:
    sub rsp,64
    vmovdqu64 zmmword ptr [rsp],zmm6
vec_save_axis_code_end:
vec_restore_axis_code:
    vmovdqu64 zmm6,zmmword ptr [rsp]
    add rsp,64
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
tensor_support_mode:.skip 4
tensor_support_count:.skip 4
tensor_support_emit_index:.skip 4
.p2align 3
tensor_support_predicate:.skip 8
tensor_support_basin:.skip 8
tensor_support_dispatch_base:.skip 8
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
vec13_borrowed:.skip 4
vec_cache_reg_mask:.skip 4
vec_persistent_reg_mask:.skip 4
vec_axis_root_valid:.skip 4
.p2align 3
vec_axis_root_c:.skip 8
vec_axis_root_d:.skip 8
vec_axis_root_mod:.skip 8
vec_fused_mode:.skip 4
vec_product_subtract_contractions:.skip 4
vec_induct_count:.skip 4
.p2align 3
vec_induct_coeff:.skip TENSOR_HIGH_COUNT*8
vec_induct_offset:.skip TENSOR_HIGH_COUNT*8
vec_induct_mod:.skip TENSOR_HIGH_COUNT*8
vec_induct_reg:.skip TENSOR_HIGH_COUNT*4
vec_induct_step_reg:.skip TENSOR_HIGH_COUNT*4
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
vec_cache_count:.skip 4
vec_current_gen:.skip 4
vec_gen_counter:.skip 4
vec_interior_mode:.skip 4
vec_axis_reg:.skip 4
.p2align 3
vec_cache_binding_ptr:.skip 8
vec_cache_gen_ptr:.skip 8
vec_cache_reg_ptr:.skip 8
vec_cache_kind_ptr:.skip 8
vec_cache_key_a_ptr:.skip 8
vec_cache_key_b_ptr:.skip 8
vec_cache_key_c_ptr:.skip 8
.p2align 3
vec_txn_emit_ptr:.skip 8
vec_txn_init_ptr:.skip 8
vec_txn_reg_mask:.skip 4
vec_txn_13_free:.skip 4
vec_txn_cache_reg_mask:.skip 4
vec_txn_const_count:.skip 4
vec_txn_fixup_count:.skip 4
vec_txn_cache_count:.skip 4
vec_txn_current_gen:.skip 4
vec_txn_gen_counter:.skip 4
vec_txn_axis_valid:.skip 4
vec_txn_axis_reg:.skip 4
vec_txn_induct_count:.skip 4
.p2align 3
vec_txn_induct_coeff:.skip 8*8
vec_txn_induct_offset:.skip 8*8
vec_txn_induct_mod:.skip 8*8
vec_txn_induct_reg:.skip 8*4
vec_txn_induct_step_reg:.skip 8*4
vec_txn_axis_c:.skip 8
vec_txn_axis_d:.skip 8
vec_txn_axis_mod:.skip 8
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
tensor_binding_uses_ptr:.skip 8
tensor_binding_expanded_ptr:.skip 8
tensor_affine_profile_count:.skip 4
.p2align 3
tensor_affine_profile_coeff_ptr:.skip 8
tensor_affine_profile_offset_ptr:.skip 8
tensor_affine_profile_mod_ptr:.skip 8
tensor_affine_profile_uses_ptr:.skip 8
tensor_induct_selected_count:.skip 4
tensor_induct_selected_coeff:.skip TENSOR_HIGH_COUNT*8
tensor_induct_selected_offset:.skip TENSOR_HIGH_COUNT*8
tensor_induct_selected_mod:.skip TENSOR_HIGH_COUNT*8
tensor_const_profile_count:.skip 4
.p2align 3
tensor_const_profile_bits_ptr:.skip 8
tensor_const_profile_score_ptr:.skip 8
tensor_const_selected_count:.skip 4
tensor_const_selected_bits:.skip TENSOR_HIGH_COUNT*8
tensor_transient_peak:.skip 4
tensor_transient_borrow_mask:.skip 4
tensor_persistent_budget:.skip 4
tensor_persistent_remaining:.skip 4
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
