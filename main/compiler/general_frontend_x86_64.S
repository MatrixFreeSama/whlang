.intel_syntax noprefix
.include "compiler/general_runtime_offsets.inc"
.include "compiler/general_runtime_capacity.inc"
.include "compiler/physical_reality.inc"
.include "compiler/silicon_reality.inc"
.include "compiler/isa_capabilities.inc"
.include "compiler/groupfact.inc"
.include "compiler/physical_predicate.inc"
.include "build/general_parallel_release_offsets.inc"

# General Wheelchair direct-native semantic frontend. General, Tensor and Field
# now share the compiler-wide Physical Reality vocabulary; this file contributes
# semantic Axis/Operator/ValueFact facts and never owns a runtime scheduler.
# User programs never invoke Python, C, LLVM, an assembler, or a linker.

.equ SYS_write,1
.equ SYS_openat,257
.equ SYS_pwrite64,18
.equ SYS_fchmod,91
.equ SYS_close,3
.equ SYS_mmap,9
.equ SYS_munmap,11
.equ SYS_mremap,25
.equ MREMAP_MAYMOVE,1
.equ PROT_READ_WRITE,3
.equ MAP_PRIVATE_ANON,0x22
.equ AT_FDCWD,-100
.equ OUT_FLAGS,577

.equ J_OBJECT,1
.equ J_ARRAY,2
.equ J_STRING,3
.equ J_NUMBER,4
.equ J_TRUE,5
.equ J_FALSE,6
.equ J_NULL,7

.equ GTYPE_BOOL,1
.equ GTYPE_I64,2
.equ GTYPE_U64,3
.equ GTYPE_F32,4
.equ GTYPE_F64,5
.equ GTYPE_STRING,6
.equ GTYPE_RECORD,100
.equ GTYPE_DICTIONARY,101
.equ GTYPE_NESTED,102
.equ GTYPE_STATIC_LAST,GTYPE_NESTED
.equ GTYPE_RANKN_FP_BASE,GTYPE_STATIC_LAST+1

.equ GK_INPUT,1
.equ GK_COMPUTE,2
.equ GK_MAP,3
.equ GK_REDUCE,4
.equ GK_ITERATE,5
.equ GK_RECORD,6
.equ GK_DICTIONARY,7
.equ GK_LOOKUP,8
.equ GK_NESTED_LITERAL,9
.equ GK_NESTED_REDUCE,10
.equ GK_CASCADE,11

.equ GSYM_SIZE,64
.equ GST_SIZE,32
# Mutable iterate StateFacts are execution-local.  One 16-byte cell carries the
# current and next-version scalar authorities for one state.  The frame itself
# lives on the already-existing causal execution stack, so simultaneous
# executions are disjoint without locks, ownership tables, or a runtime pool.
.equ GSTATE_LOCAL_STRIDE,16
.equ GSTATE_LOCAL_TAG,0xffff000000000000

.extern source_ptr
.extern source_length
.extern json_skip_ws
.extern json_parse_value
.extern obj_get
.extern span_eq
.extern node_parse_u64
.extern node_parse_f64_bits
.extern node_parse_f32_bits
.extern jcur
.extern jend
.extern json_node_count
.extern json_prepare_arena
.extern general_runtime_blob
.extern general_runtime_blob_end
.extern execution_admission_capacity
.extern outward_materialization_ticks
.extern sd_static_placement_required
.extern sd_preferred_l3_mask_bytes
.extern sd_preferred_l3_mask
.extern general_parallel_release_blob
.extern general_parallel_release_blob_end
.extern surface_note_convergence_name
.extern fabric_target_facts_proved
.extern ft_compute_ticks_num
.extern ft_compute_ticks_den
.extern ft_activation_ticks
.extern ft_transport_fixed_ticks
.extern ft_transport_ticks_per_byte
.extern isa_cap_bits

.global compile_general_source
# compile_general_source(rdi=output_path)
# eax=0 success, 1 invalid/unsupported, 2 = proven fast numeric candidate.
compile_general_source:
    push rbx
    push r12
    push r13
    push r14
    push r15
    # One stable declaration-kind slot. Binding classification survives all
    # inference/type-physicalization calls without borrowing caller-saved state.
    sub rsp,8
    mov [rip+g_output_path],rdi
    mov qword ptr [rip+g_code_growth_factor],64
.compile_retry:
    mov dword ptr [rip+g_code_overflow],0
    mov dword ptr [rip+g_symbol_count],0
    mov dword ptr [rip+g_input_count],0
    mov dword ptr [rip+g_binding_count],0
    mov dword ptr [rip+g_output_count],0
    mov dword ptr [rip+g_binding_slot_count],0
    mov dword ptr [rip+g_state_count],0
    mov dword ptr [rip+g_iter_projection_count],0
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
    mov dword ptr [rip+g_overflow_wrap],0
    mov dword ptr [rip+g_precision_propagation],0
    mov dword ptr [rip+g_fp_tolerance_active],0
    mov qword ptr [rip+g_fp_tolerance_exp2],0
    mov dword ptr [rip+g_rankn_type_count],0
    mov qword ptr [rip+g_runtime_temp_bytes_used],0
    mov dword ptr [rip+g_fragment_count],0
    mov dword ptr [rip+g_parallel_error],0
    mov rdi,[rip+source_length]
    call g_prepare_code_arenas
    test eax,eax
    jnz .bad
    mov qword ptr [rip+g_image_code_len],0

    # Parse JSON DOM using the same handwritten parser as the topology path.
    mov qword ptr [rip+json_node_count],0
    call json_prepare_arena
    test eax,eax; jnz .bad
    mov rax,[rip+source_ptr]
    mov [rip+jcur],rax
    add rax,[rip+source_length]
    mov [rip+jend],rax
    call json_parse_value
    test rax,rax
    jz .bad
    mov r12,rax
    mov [rip+g_root],rax
    call json_skip_ws
    mov rax,[rip+jcur]
    cmp rax,[rip+jend]
    jne .bad
    cmp qword ptr [r12],J_OBJECT
    jne .bad

    # format
    mov rdi,r12
    lea rsi,[rip+gk_format]
    mov edx,gk_format_end-gk_format
    call obj_get
    test rax,rax
    jz .bad
    cmp qword ptr [rax],J_STRING
    jne .bad
    mov rdi,[rax+8]; mov rsi,[rax+16]
    lea rdx,[rip+gv_format]; mov ecx,gv_format_end-gv_format
    call span_eq
    test eax,eax
    jz .bad

    # One parsed semantic DOM owns the compiler symbol arena. Every symbol is
    # represented by at least one DOM node, so the actual parsed node count is a
    # structural upper bound and replaces the historical 512-symbol table.
    mov rdi,[rip+json_node_count]
    call g_prepare_symbol_arena
    test eax,eax; jnz .bad
    mov rdi,[rip+json_node_count]
    call g_prepare_state_meta_arena
    test eax,eax; jnz .bad
    mov rdi,[rip+json_node_count]
    call g_prepare_iter_projection_arena
    test eax,eax; jnz .bad
    mov rdi,[rip+json_node_count]
    call g_prepare_io_meta_arena
    test eax,eax; jnz .bad
    mov rdi,[rip+json_node_count]
    call g_prepare_phys_fact_arena
    test eax,eax; jnz .bad

    # contracts: deterministic true, overflow trap/wrap. The general direct
    # path preserves source FP order and therefore needs no tolerant rewrite.
    mov rdi,r12; lea rsi,[rip+gk_contracts]; mov edx,gk_contracts_end-gk_contracts; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_OBJECT; jne .bad
    mov r13,rax
    mov rdi,r13; lea rsi,[rip+gk_deterministic]; mov edx,gk_deterministic_end-gk_deterministic; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_TRUE; jne .bad
    mov rdi,r13; lea rsi,[rip+gk_integer_overflow]; mov edx,gk_integer_overflow_end-gk_integer_overflow; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_STRING; jne .bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_wrap]; mov ecx,gv_wrap_end-gv_wrap; call span_eq
    test eax,eax; jnz .set_wrap
    # span_eq returns a Boolean in eax, so reacquire the field node before
    # testing the alternative contract.  Never dereference the Boolean result.
    mov rdi,r13; lea rsi,[rip+gk_integer_overflow]; mov edx,gk_integer_overflow_end-gk_integer_overflow; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_trap]; mov ecx,gv_trap_end-gv_trap; call span_eq
    test eax,eax; jz .bad
    jmp .parse_mixed_precision
.set_wrap:
    mov dword ptr [rip+g_overflow_wrap],1
.parse_mixed_precision:
    # Floating tolerance is an error-bound fact, never a fast-math switch.
    # Strict/absent contracts keep the exact Rank-N path. A tolerant contract
    # carries one numeric bound; we conservatively project it to a power-of-two
    # bound no larger than the source value. Relations may stop local propagation
    # only after proving their unpropagated remainder lies below that bound.
    mov rdi,r13; lea rsi,[rip+gk_floating_point]; mov edx,gk_floating_point_end-gk_floating_point; call obj_get
    test rax,rax; jz .parse_mixed_precision_policy
    cmp qword ptr [rax],J_STRING; jne .bad
    mov rbx,rax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_fp_strict]; mov ecx,gv_fp_strict_end-gv_fp_strict; call span_eq
    test eax,eax; jnz .parse_mixed_precision_policy
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_fp_tolerant]; mov ecx,gv_fp_tolerant_end-gv_fp_tolerant; call span_eq
    test eax,eax; jz .bad
    mov rdi,r13; lea rsi,[rip+gk_floating_tolerance]; mov edx,gk_floating_tolerance_end-gk_floating_tolerance; call obj_get
    test rax,rax; jz .bad
    call node_parse_f64_bits
    test edx,edx; jnz .parse_mixed_precision_policy
    call g_tolerance_exp_from_f64_bits
    test edx,edx; jnz .parse_mixed_precision_policy
    mov qword ptr [rip+g_fp_tolerance_exp2],rax
    mov dword ptr [rip+g_fp_tolerance_active],1
.parse_mixed_precision_policy:
    # Mixed precision remains the existing consumer-edge numeric meet authority.
    mov rdi,r13; lea rsi,[rip+gk_mixed_precision]; mov edx,gk_mixed_precision_end-gk_mixed_precision; call obj_get
    test rax,rax; jz .contracts_ok
    cmp qword ptr [rax],J_STRING; jne .bad
    mov rbx,rax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_mixed_low]; mov ecx,gv_mixed_low_end-gv_mixed_low; call span_eq
    test eax,eax; jnz .contracts_ok
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_mixed_high]; mov ecx,gv_mixed_high_end-gv_mixed_high; call span_eq
    test eax,eax; jz .bad
    mov dword ptr [rip+g_precision_propagation],1
.contracts_ok:

    # Inputs first so arbitrary logical names become dense symbol IDs.
    mov rdi,r12; lea rsi,[rip+gk_inputs]; mov edx,gk_inputs_end-gk_inputs; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_ARRAY; jne .bad
    mov r13,[rax+24]
.input_loop:
    test r13,r13
    jz .inputs_done
    mov eax,dword ptr [rip+g_input_count]
    cmp eax,dword ptr [rip+g_io_capacity]
    jae .bad
    cmp qword ptr [r13],J_OBJECT; jne .bad
    mov rdi,r13; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_STRING; jne .bad
    mov r14,[rax+8]; mov r15,[rax+16]
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .bad
    mov rdi,rax; call g_type_from_node
    test eax,eax; jz .bad
    mov ebx,eax
    mov rdi,r14; mov rsi,r15; mov edx,GK_INPUT; mov ecx,ebx; mov r8,r13
    mov r9d,dword ptr [rip+g_input_count]
    call g_add_symbol
    test eax,eax; jnz .bad
    mov eax,dword ptr [rip+g_input_count]
    mov rdx,[rip+g_input_types_ptr]
    mov [rdx+rax*4],ebx
    mov edx,eax; imul rdx,rdx,24; add rdx,[rip+g_input_ranges_ptr]
    mov rdi,r13; mov esi,ebx; call physical_input_range_parse
    test eax,eax; jnz .bad
    inc dword ptr [rip+g_input_count]
    mov r13,[r13+32]
    jmp .input_loop
.inputs_done:

    # Binding declarations and type inference in source order.
    mov rdi,r12; lea rsi,[rip+gk_bindings]; mov edx,gk_bindings_end-gk_bindings; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_ARRAY; jne .bad
    mov r13,[rax+24]
.binding_decl_loop:
    test r13,r13
    jz .binding_decl_done
        cmp qword ptr [r13],J_OBJECT; jne .bad
    mov rdi,r13; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .bad
    mov r14,[rax+8]; mov r15,[rax+16]
    mov rdi,r13; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .bad
    mov rbx,rax
    # classify op -> edx kind
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; call g_classify_binding_op
    test eax,eax; jz .bad
    mov dword ptr [rsp],eax
    cmp eax,GK_MAP; je .decl_map
    cmp eax,GK_REDUCE; je .decl_reduce
    cmp eax,GK_COMPUTE; je .decl_compute
    cmp eax,GK_ITERATE; je .decl_iterate
    cmp eax,GK_RECORD; je .decl_record
    cmp eax,GK_DICTIONARY; je .decl_dict
    cmp eax,GK_LOOKUP; je .decl_lookup
    cmp eax,GK_NESTED_LITERAL; je .decl_nested
    cmp eax,GK_NESTED_REDUCE; je .decl_nested_reduce
    cmp eax,GK_CASCADE; je .decl_cascade
    jmp .bad
.decl_compute:
    mov rdi,r13; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .bad
    mov rdi,rax; call g_infer_expr
    test eax,eax; jz .bad
    mov ebx,eax
    # A declared compute type is a consumer-edge representation request, not a
    # second inference tree.  Reuse the old binding authority and realize any
    # numeric conversion only when the value crosses this binding boundary.
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .decl_compute_type_ready
    mov rdi,rax; call g_type_from_node
    test eax,eax; jz .bad
    mov ebx,eax
.decl_compute_type_ready:
    jmp .decl_scalar_slot
.decl_map:
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .bad
    mov rdi,rax; call g_type_from_node
    test eax,eax; jz .bad
    mov ebx,eax
    # general path supports one axis; fast path owns the same 1D numeric shape.
    mov rdi,r13; call g_validate_one_axis
    test eax,eax; jnz .bad
    mov eax,-1
    jmp .decl_add
.decl_reduce:
    mov rdi,r13; call g_validate_one_axis
    test eax,eax; jnz .bad
    mov rdi,r13; lea rsi,[rip+gk_accumulator]; mov edx,gk_accumulator_end-gk_accumulator; call obj_get
    test rax,rax; jz .bad
    mov rdi,rax; call g_type_from_node
    test eax,eax; jz .bad
    mov ebx,eax
    jmp .decl_scalar_slot
.decl_iterate:
    mov rdi,r13; call g_iterate_result_type
    test eax,eax; jz .bad
    mov ebx,eax
    jmp .decl_scalar_slot
.decl_record:
    mov ebx,GTYPE_RECORD
    mov eax,-1
    jmp .decl_add
.decl_dict:
    mov ebx,GTYPE_DICTIONARY
    mov eax,-1
    jmp .decl_add
.decl_lookup:
    mov rdi,r13; call g_lookup_value_type
    test eax,eax; jz .bad
    mov ebx,eax
    jmp .decl_scalar_slot
.decl_nested:
    mov ebx,GTYPE_NESTED
    mov eax,-1
    jmp .decl_add
.decl_nested_reduce:
    mov rdi,r13; call g_nested_reduce_type
    test eax,eax; jz .bad
    mov ebx,eax
    jmp .decl_scalar_slot
.decl_cascade:
    # Dynamic goal programs are compiled by the dedicated causal-fabric source
    # lowering added after the scalar core. Do not silently reinterpret them.
    mov ebx,GTYPE_RECORD
    mov eax,-1
    jmp .decl_add
.decl_scalar_slot:
    mov eax,dword ptr [rip+g_binding_slot_count]
    cmp eax,-1
    je .bad                         # only the dword representation/real resources remain
    inc dword ptr [rip+g_binding_slot_count]
.decl_add:
    mov r9d,eax
    mov rdi,r14; mov rsi,r15; mov edx,dword ptr [rsp]; mov ecx,ebx; mov r8,r13
    call g_add_symbol
    test eax,eax; jnz .bad
    inc dword ptr [rip+g_binding_count]
    mov r13,[r13+32]
    jmp .binding_decl_loop
.binding_decl_done:
    # Human-source variation is collapsed before any fragment exists.  This is a
    # monotone semantic representative closure over the already-typed symbol DAG:
    # no algorithm name, rewrite budget, source-size threshold, or second IR is
    # introduced.  Failure means the source cannot be proven, never a fallback.
    call g_semantic_converge_symbols
    test eax,eax; jnz .bad

    # Downstream structural field consumers define the iterate boundary live-set.
    # Discovery happens after all symbols exist but before runtime binding layout,
    # so only actually consumed final StateFacts receive projection slots.
    mov rdi,[rip+g_root]
    call g_discover_iterate_projections_node
    test eax,eax; jnz .bad

    # 1.3.24: every validated general program stays in the same sovereign
    # Physical-Reality path. Source-shape candidate routing is erased.

.emit_general:
    # Reject cascade here until the source-to-fabric lowering below is chosen.
    mov ecx,0
.cascade_scan:
    cmp ecx,dword ptr [rip+g_symbol_count]
    jae .codegen
    mov edx,ecx; shl rdx,6; mov rax,[rip+g_symbols_ptr]; add rax,rdx
    cmp dword ptr [rax+16],GK_CASCADE
    je .bad
    # Dynamic dictionary lookup still lacks a fully proven native string/value
    # comparison path.  Closed literal-key lookups are eliminated by the .wh
    # compile-time pass; any remaining lookup must reject rather than crash or
    # fabricate a value.
    cmp dword ptr [rax+16],GK_LOOKUP
    je .bad
    inc ecx; jmp .cascade_scan

.codegen:
    # Output ownership is known before code emission.  Count represented output
    # entries once so the target arena can be laid out from exact program
    # cardinality rather than a runtime ABI table width.
    mov rdi,[rip+g_root]
    lea rsi,[rip+gk_outputs]
    mov edx,gk_outputs_end-gk_outputs
    call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_ARRAY; jne .bad
    mov rax,[rax+24]
    xor ecx,ecx
.goc_loop:
    test rax,rax
    jz .goc_done
    cmp ecx,-1
    je .bad
    inc ecx
    mov rax,[rax+32]
    jmp .goc_loop
.goc_done:
    test ecx,ecx
    jz .bad
    cmp ecx,dword ptr [rip+g_io_capacity]
    ja .bad
    mov dword ptr [rip+g_output_capacity],ecx

    # One source-sized runtime arena owns inputs, Rank-N ingress, bindings,
    # mutable iterate state and outputs.  Measure the largest represented
    # iterate state set before code emission so runtime storage is derived from
    # semantic structure rather than from a late lowering counter.
    call g_measure_runtime_state_capacity
    test eax,eax; jnz .bad
    call g_prepare_runtime_arena_layout
    test eax,eax; jnz .bad
    # Compiler-only causal metadata is sized from the represented symbol set.
    # The runtime output ABI contributes only its already-existing output slots.
    call g_prepare_graph_arena
    test eax,eax; jnz .bad
    # Emit bindings in source order.  Maps are structural and materialize
    # nothing; loads recursively fuse their expressions.
    mov rdi,[rip+g_root]; lea rsi,[rip+gk_bindings]; mov edx,gk_bindings_end-gk_bindings; call obj_get
    mov r13,[rax+24]
.binding_emit_loop:
    test r13,r13
    jz .outputs
    mov rdi,r13; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .bad
    mov rbx,rax
    # A converged compute owns no second materialization.  All consumers resolve
    # through the same symbol representative and therefore reach the original
    # immutable ValueFact/fragment authority directly.
    cmp dword ptr [rbx+16],GK_COMPUTE; jne .emit_binding_not_converged
    mov rdi,rbx; call g_semantic_resolve_symbol
    cmp rax,rbx; jne .emit_next_binding
.emit_binding_not_converged:
    mov eax,dword ptr [rbx+16]
    cmp eax,GK_MAP; je .emit_next_binding
    cmp eax,GK_RECORD; je .emit_next_binding
    cmp eax,GK_DICTIONARY; je .emit_next_binding
    cmp eax,GK_NESTED_LITERAL; je .emit_next_binding
    mov rdi,r13
    mov esi,1
    call g_fragment_begin
    test eax,eax; jnz .bad
    mov eax,dword ptr [rbx+16]
    cmp eax,GK_COMPUTE; je .emit_binding_mark_static
    cmp eax,GK_LOOKUP; je .emit_binding_mark_static
    jmp .emit_binding_dispatch
.emit_binding_mark_static:
    mov rdx,[rip+g_fragment_static_ptr]
    mov ecx,dword ptr [rip+g_fragment_count]
    mov dword ptr [rdx+rcx*4],1
.emit_binding_dispatch:
    mov eax,dword ptr [rbx+16]
    cmp eax,GK_COMPUTE; je .emit_compute
    cmp eax,GK_REDUCE; je .emit_reduce
    cmp eax,GK_ITERATE; je .emit_iterate
    cmp eax,GK_LOOKUP; je .emit_lookup
    cmp eax,GK_NESTED_REDUCE; je .emit_nested_reduce
    jmp .bad
.emit_compute:
    mov rdi,r13; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .bad
    mov rdi,rax; call g_emit_expr
    test eax,eax; jz .bad
    mov edx,dword ptr [rbx+20]
    cmp eax,edx; je .emit_compute_type_ready
    mov edi,eax; mov esi,edx; call g_convert_stack_top
    test eax,eax; jnz .bad
.emit_compute_type_ready:
    call g_emit_pop_rax
    mov eax,dword ptr [rbx+24]
    call g_binding_slot_addr
    mov rdi,rax; call g_emit_store_rax_abs
    jmp .emit_materialized_done
.emit_reduce:
    mov rdi,rbx; call g_emit_reduce_binding
    test eax,eax; jnz .bad
    jmp .emit_materialized_done
.emit_iterate:
    mov rdi,rbx; call g_emit_iterate_binding
    test eax,eax; jnz .bad
    jmp .emit_materialized_done
.emit_lookup:
    mov rdi,rbx; call g_emit_lookup_binding
    test eax,eax; jnz .bad
    jmp .emit_materialized_done
.emit_nested_reduce:
    mov rdi,rbx; call g_emit_nested_reduce_binding
    test eax,eax; jnz .bad
.emit_materialized_done:
    call g_fragment_finish
    test eax,eax; jnz .bad
.emit_next_binding:
    mov r13,[r13+32]
    jmp .binding_emit_loop

.outputs:
    mov rdi,[rip+g_root]; lea rsi,[rip+gk_outputs]; mov edx,gk_outputs_end-gk_outputs; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_ARRAY; jne .bad
    mov r13,[rax+24]
.output_loop:
    test r13,r13
    jz .tests_gate
    mov eax,dword ptr [rip+g_output_count]
    cmp eax,dword ptr [rip+g_output_capacity]
    jae .bad
    mov rdi,r13
    mov esi,2
    call g_fragment_begin
    test eax,eax; jnz .bad
    mov rdx,[rip+g_fragment_static_ptr]
    mov ecx,dword ptr [rip+g_fragment_count]
    mov dword ptr [rdx+rcx*4],1
    mov rdi,r13; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .bad
    mov rdi,rax; call g_emit_expr
    test eax,eax; jz .bad
    cmp eax,GTYPE_STRING; je .bad       # numeric protocol in this first sovereign general image
    mov edx,dword ptr [rip+g_output_count]
    mov rcx,[rip+g_output_types_ptr]; mov [rcx+rdx*4],eax
    call g_emit_pop_rax
    mov eax,dword ptr [rip+g_output_count]
    call g_output_slot_addr
    mov rdi,rax; call g_emit_store_rax_abs
    call g_fragment_finish
    test eax,eax; jnz .bad
    inc dword ptr [rip+g_output_count]
    mov r13,[r13+32]
    jmp .output_loop
.tests_gate:
    cmp dword ptr [rip+g_output_count],0; je .bad
    mov rdi,[rip+g_root]; lea rsi,[rip+gk_tests]; mov edx,gk_tests_end-gk_tests; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_ARRAY; jne .bad
    # Embedded tests are optional validation metadata.  An executable program
    # is defined by its inputs/bindings/outputs; the General backend must not
    # make a nonempty test vector a semantic precondition.

    # Image form follows the causal graph, never the compiler host's temporary
    # affinity width. Invocation admission is refreshed by the release itself;
    # width==1 simply keeps every ready Region local through the same image.
    call g_build_parallel_image
    test eax,eax; jnz .bad
.write_image:
    call g_emit_image
    test eax,eax; jnz .bad
    xor eax,eax
    jmp .done
.bad:
    cmp dword ptr [rip+g_code_overflow],0
    je .bad_final
    mov rax,qword ptr [rip+g_code_growth_factor]
    shl rax,1
    jc .bad_final
    test rax,rax
    jz .bad_final
    mov qword ptr [rip+g_code_growth_factor],rax
    jmp .compile_retry
.bad_final:
    mov eax,1
.done:
    add rsp,8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- type/symbol helpers ----------------
.include "compiler/rankn_type_layout.inc"
# Parameterized floating types. Native f32/f64 keep their compact IDs. Every
# wider precision is interned into one represented-program TypePhysicalFact:
#   +0 u64 PrecisionFact P
#   +8 packed geometry, +16 span, +24 limb count, +32 Fourier stage facts
# Type identity, precision, and physical geometry therefore have one authority;
# geometry is planned once by AOT and is never attached to individual values.
# rdi=P -> eax=interned semantic type/0.
g_intern_rankn_precision:
    push rbx
    push r12
    mov r12,rdi
    cmp r12,64
    jbe .girp_bad
    xor ecx,ecx
    mov r8,[rip+g_rankn_type_facts_ptr]
.girp_scan:
    cmp ecx,dword ptr [rip+g_rankn_type_count]
    jae .girp_append
    mov rax,rcx
    imul rax,rax,RPF_FACT_BYTES
    cmp qword ptr [r8+rax],r12
    je .girp_found
    inc ecx
    jmp .girp_scan
.girp_append:
    cmp ecx,dword ptr [rip+g_rankn_type_capacity]
    jae .girp_bad
    mov ebx,ecx
    add ebx,GTYPE_RANKN_FP_BASE
    jc .girp_bad
    mov rax,rcx
    imul rax,rax,RPF_FACT_BYTES
    mov [r8+rax],r12
    mov qword ptr [r8+rax+8],0
    inc dword ptr [rip+g_rankn_type_count]
    # Materialize the one Fourier Physical Fact for this fpP type. A zero
    # geometry remains a valid type fact and only rejects multiplication that
    # cannot be physically realized; it never rejects the precision itself.
    mov edi,ebx
    call g_rankn_fourier_geom_pack
    mov r8,[rip+g_rankn_type_facts_ptr]
    mov ecx,ebx
    sub ecx,GTYPE_RANKN_FP_BASE
    mov rdx,rcx
    imul rdx,rdx,RPF_FACT_BYTES
    mov dword ptr [r8+rdx+8],eax
    mov edi,ebx
    call g_materialize_rankn_fp_layout
    test rax,rax; jz .girp_bad
    mov eax,ebx
    jmp .girp_done
.girp_found:
    mov eax,ecx
    add eax,GTYPE_RANKN_FP_BASE
    jc .girp_bad
    jmp .girp_done
.girp_bad:
    xor eax,eax
.girp_done:
    pop r12
    pop rbx
    ret

# rdi=span ptr,rsi=len -> eax=interned type/0.
g_parse_float_type_span:
    call g_parse_float_precision_span
    cmp rax,32; je .gt_f32
    cmp rax,64; je .gt_f64
    test rax,rax; jz .gt_bad
    mov rdi,rax
    jmp g_intern_rankn_precision
.include "compiler/float_type_fact.inc"
FLOAT_TYPE_PRECISION g_parse_float_precision_span

# edi=type -> rax=floating significand precision, 0 for nonfloating.
g_float_precision:
    cmp edi,GTYPE_F32
    je .gfp_32
    cmp edi,GTYPE_F64
    je .gfp_64
    cmp edi,GTYPE_RANKN_FP_BASE
    jb .gfp_no
    mov eax,edi
    sub eax,GTYPE_RANKN_FP_BASE
    jc .gfp_no
    cmp eax,dword ptr [rip+g_rankn_type_count]
    jae .gfp_no
    mov rdx,[rip+g_rankn_type_facts_ptr]
    imul rax,rax,RPF_FACT_BYTES
    mov rax,[rdx+rax]
    cmp rax,64
    jbe .gfp_no
    ret
.gfp_32: mov eax,32; ret
.gfp_64: mov eax,64; ret
.gfp_no: xor eax,eax; ret

# edi=type -> eax 1 iff it names an interned parameterized Rank-N type.
g_is_rankn_fp:
    cmp edi,GTYPE_RANKN_FP_BASE
    jb .girf_no
    mov eax,edi
    sub eax,GTYPE_RANKN_FP_BASE
    jc .girf_no
    cmp eax,dword ptr [rip+g_rankn_type_count]
    setb al
    movzx eax,al
    ret
.girf_no:
    xor eax,eax
    ret

# rax=positive finite f64 tolerance bits -> rax conservative binary exponent k,
# edx=0 success / 1 cannot exploit. The returned fact guarantees 2^k <= the
# source tolerance even if decimal->f64 rounded upward: one full binary exponent
# of slack is reserved. Zero/NaN/Inf/negative values fall back to strict.
g_tolerance_exp_from_f64_bits:
    mov rcx,rax
    bt rcx,63
    jc .gtefb_bad
    mov rdx,rcx
    shr rdx,52
    and edx,0x7ff
    cmp edx,0x7ff
    je .gtefb_bad
    mov r8,rcx
    mov rax,0x000fffffffffffff
    and r8,rax
    test edx,edx
    jz .gtefb_subnormal
    sub edx,1023
    movsxd rax,edx
    dec rax
    xor edx,edx
    ret
.gtefb_subnormal:
    test r8,r8
    jz .gtefb_bad
    bsr rcx,r8
    lea rax,[rcx-1075]
    xor edx,edx
    ret
.gtefb_bad:
    xor eax,eax
    mov edx,1
    ret

# g_type_from_node(rdi=node) -> eax type/0. Object tolerant types use base.
g_type_from_node:
    test rdi,rdi; jz .gt_bad
    cmp qword ptr [rdi],J_STRING; je .gt_string_node
    cmp qword ptr [rdi],J_OBJECT; jne .gt_bad
    push rdi
    lea rsi,[rip+gk_base]; mov edx,gk_base_end-gk_base; call obj_get
    pop rdi
    test rax,rax; jz .gt_bad
    mov rdi,rax
.gt_string_node:
    mov r8,[rdi+8]; mov r9,[rdi+16]
    mov rdi,r8; mov rsi,r9; lea rdx,[rip+gv_bool]; mov ecx,gv_bool_end-gv_bool; call span_eq; test eax,eax; jnz .gt_bool
    mov rdi,r8; mov rsi,r9; lea rdx,[rip+gv_i64]; mov ecx,gv_i64_end-gv_i64; call span_eq; test eax,eax; jnz .gt_i64
    mov rdi,r8; mov rsi,r9; lea rdx,[rip+gv_u64]; mov ecx,gv_u64_end-gv_u64; call span_eq; test eax,eax; jnz .gt_u64
    mov rdi,r8; mov rsi,r9; call g_parse_float_type_span; test eax,eax; jnz .gt_param_fp
    mov rdi,r8; mov rsi,r9; lea rdx,[rip+gv_string]; mov ecx,gv_string_end-gv_string; call span_eq; test eax,eax; jnz .gt_string
.gt_bad: xor eax,eax; ret
.gt_bool: mov eax,GTYPE_BOOL; ret
.gt_i64: mov eax,GTYPE_I64; ret
.gt_u64: mov eax,GTYPE_U64; ret
.gt_f32: mov eax,GTYPE_F32; ret
.gt_f64: mov eax,GTYPE_F64; ret
.gt_param_fp: ret
.gt_string: mov eax,GTYPE_STRING; ret

# Materialize compile-time symbols from represented DOM size, not a language
# constant.  Counts remain dword-indexed because symbol IDs in the existing
# compiler representation are 32-bit facts; that width is the only retained
# frontier here.
g_prepare_symbol_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jz .gpsa_fail
    mov rax,rbx
    shr rax,32
    jnz .gpsa_fail
    mov rdi,[rip+g_symbols_ptr]
    test rdi,rdi
    jz .gpsa_size
    mov rsi,[rip+g_symbols_bytes]
    mov eax,SYS_munmap
    syscall
.gpsa_size:
    mov rax,rbx
    shl rax,6
    mov [rip+g_symbols_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gpsa_fail
    mov [rip+g_symbols_ptr],rax
    mov dword ptr [rip+g_symbol_capacity],ebx
    xor eax,eax
    pop rbx
    ret
.gpsa_fail:
    mov eax,1
    pop rbx
    ret


# Compiler-only iterate metadata follows represented DOM cardinality.  One mmap
# owns all per-state arrays so state count is a structural property rather than
# an assembly-time table width.
g_prepare_state_meta_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .gpsm_have
    mov ebx,1
.gpsm_have:
    mov rax,rbx
    shr rax,32
    jnz .gpsm_fail
    mov rdi,[rip+g_state_meta_arena_ptr]
    test rdi,rdi
    jz .gpsm_size
    mov rsi,[rip+g_state_meta_arena_bytes]
    mov eax,SYS_munmap
    syscall
.gpsm_size:
    # states/decl/carriers plus one update expression, order, position and pending-use frontier = 84 bytes/state.
    # Guard identity is compile-time Physical-Region metadata only.
    mov rax,rbx
    imul rax,rax,84
    jo .gpsm_fail
    add rax,63
    jc .gpsm_fail
    and rax,-64
    mov [rip+g_state_meta_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gpsm_fail
    mov [rip+g_state_meta_arena_ptr],rax
    mov dword ptr [rip+g_state_capacity],ebx
    mov [rip+g_states_ptr],rax
    mov rcx,rbx
    shl rcx,5
    add rax,rcx
    mov [rip+g_reg_iter_decls_ptr],rax
    mov rcx,rbx
    shl rcx,3
    add rax,rcx
    mov [rip+g_reg_iter_carrier_kind_ptr],rax
    mov rcx,rbx
    shl rcx,2
    add rax,rcx
    mov [rip+g_reg_iter_old_reg_ptr],rax
    add rax,rcx
    mov [rip+g_reg_iter_out_reg_ptr],rax
    add rax,rcx
    mov [rip+g_phys_state_last_use_ptr],rax
    add rax,rcx
    mov [rip+g_phys_state_guard_ptr],rax
    add rax,rcx
    mov [rip+g_phys_update_order_ptr],rax
    add rax,rcx
    mov [rip+g_phys_update_position_ptr],rax
    add rax,rcx
    mov [rip+g_phys_update_pending_ptr],rax
    add rax,rcx
    mov [rip+g_phys_update_total_ptr],rax
    add rax,rcx
    mov [rip+g_phys_update_expr_ptr],rax
    xor eax,eax
    pop rbx
    ret
.gpsm_fail:
    mov eax,1
    pop rbx
    ret

# Compiler-side type metadata follows represented DOM cardinality. One arena
# stages input/output type identities plus one immutable Rank-N TypePhysicalFact
# per interned fpP type. Distinct fpP types therefore consume only represented-
# source space; precision and Fourier geometry share one AOT authority.

# Compiler-only final-StateFact projection metadata. A projection exists only
# when some downstream expression actually consumes iterate.field. Capacity is
# represented DOM cardinality; no state-count or FOM-specific table exists.
g_prepare_iter_projection_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .gpipa_have
    mov ebx,1
.gpipa_have:
    mov rax,rbx
    shr rax,32
    jnz .gpipa_fail
    mov rdi,[rip+g_iter_projection_arena_ptr]
    test rdi,rdi
    jz .gpipa_size
    mov rsi,[rip+g_iter_projection_arena_bytes]
    mov eax,SYS_munmap
    syscall
.gpipa_size:
    # iter_symbol[8] + state_name[8] + state_len[8] + slot/type/state_index[4 each]
    mov rax,rbx
    imul rax,rax,36
    jo .gpipa_fail
    add rax,63
    jc .gpipa_fail
    and rax,-64
    mov [rip+g_iter_projection_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gpipa_fail
    mov [rip+g_iter_projection_arena_ptr],rax
    mov dword ptr [rip+g_iter_projection_capacity],ebx
    mov [rip+g_iter_projection_symbol_ptr],rax
    mov rcx,rbx; shl rcx,3; add rax,rcx
    mov [rip+g_iter_projection_name_ptr],rax
    add rax,rcx
    mov [rip+g_iter_projection_name_len],rax
    add rax,rcx
    mov rcx,rbx; shl rcx,2
    mov [rip+g_iter_projection_slot_ptr],rax
    add rax,rcx
    mov [rip+g_iter_projection_type_ptr],rax
    add rax,rcx
    mov [rip+g_iter_projection_state_index_ptr],rax
    mov dword ptr [rip+g_iter_projection_count],0
    xor eax,eax
    pop rbx
    ret
.gpipa_fail:
    mov eax,1
    pop rbx
    ret

g_prepare_io_meta_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .gpim_have
    mov ebx,1
.gpim_have:
    mov rax,rbx
    shr rax,32
    jnz .gpim_fail
    mov rdi,[rip+g_io_meta_arena_ptr]
    test rdi,rdi
    jz .gpim_size
    mov rsi,[rip+g_io_meta_arena_bytes]
    mov eax,SYS_munmap
    syscall
.gpim_size:
    imul rax,rbx,(32+RPF_FACT_BYTES) # input/output metadata plus immutable type facts
    jo .gpim_fail
    add rax,63
    jc .gpim_fail
    and rax,-64
    mov [rip+g_io_meta_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gpim_fail
    mov [rip+g_io_meta_arena_ptr],rax
    mov dword ptr [rip+g_io_capacity],ebx
    mov dword ptr [rip+g_rankn_type_capacity],ebx
    mov [rip+g_input_types_ptr],rax
    mov rcx,rbx
    shl rcx,2
    add rax,rcx
    mov [rip+g_input_ranges_ptr],rax
    imul rdx,rbx,24
    add rax,rdx
    mov [rip+g_output_types_ptr],rax
    add rax,rcx
    mov [rip+g_rankn_type_facts_ptr],rax
    xor eax,eax
    pop rbx
    ret
.gpim_fail:
    mov eax,1
    pop rbx
    ret

# Whole-episode CSE and ConstantFact metadata are bounded by the parsed DOM
# population, because every candidate originates at a represented node.  One
# mmap owns all candidate/resident lanes; register pressure, not a table width,
# decides how many facts survive to residency.
g_prepare_phys_fact_arena:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .gppfa_have
    mov ebx,1
.gppfa_have:
    mov rax,rbx
    shr rax,32
    jnz .gppfa_fail
    mov rdi,[rip+g_phys_fact_arena_ptr]
    test rdi,rdi
    jz .gppfa_size
    mov rsi,[rip+g_phys_fact_arena_bytes]
    mov eax,SYS_munmap
    syscall
.gppfa_size:
    mov rsi,rbx
    imul rsi,rsi,140                 # fact cost, copy demand and causal frontier
    jo .gppfa_fail
    add rsi,63
    jc .gppfa_fail
    and rsi,-64
    mov [rip+g_phys_fact_arena_bytes],rsi
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gppfa_fail
    mov [rip+g_phys_fact_arena_ptr],rax
    mov dword ptr [rip+g_phys_fact_capacity],ebx
    mov rdx,rbx
    shl rdx,3
    mov [rip+g_phys_cse_candidate_expr_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_candidate_type_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_candidate_uses_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_candidate_cost_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_resident_expr_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_resident_type_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_resident_reg_ptr],rax
    add rax,rdx
    mov [rip+g_phys_const_candidate_bits_ptr],rax
    add rax,rdx
    mov [rip+g_phys_const_candidate_type_ptr],rax
    add rax,rdx
    mov [rip+g_phys_const_candidate_uses_ptr],rax
    add rax,rdx
    mov [rip+g_phys_const_candidate_pool_ptr],rax
    add rax,rdx
    mov [rip+g_phys_const_resident_bits_ptr],rax
    add rax,rdx
    mov [rip+g_phys_const_resident_type_ptr],rax
    add rax,rdx
    mov [rip+g_phys_const_resident_reg_ptr],rax
    add rax,rdx
    mov [rip+g_phys_guard_region_uses_ptr],rax
    add rax,rdx
    mov [rip+g_packet_fact_scope_ptr],rax
    lea rdx,[rbx*4]; add rax,rdx
    mov [rip+g_packet_fact_mixed_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_resident_cost_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_candidate_moves_ptr],rax
    add rax,rdx
    mov [rip+g_phys_cse_resident_frontier_ptr],rax
    xor eax,eax
    pop rbx
    ret
.gppfa_fail:
    mov eax,1
    pop rbx
    ret

# Code staging is owned by the represented source rather than an assembly-time
# executable slot.  Source bytes seed an initial virtual/lazy estimate.  If an
# emitter reaches that estimate, the whole AOT pass is replayed with a doubled
# stable arena, so no estimate ratio participates in language admission.  Stable
# pointers keep all rel32 patch sites valid within each pass.
g_prepare_code_arenas:
    push rbx
    mov rbx,rdi
    test rbx,rbx
    jnz .gpca_have
    mov ebx,1
.gpca_have:
    mov rax,rbx
    mul qword ptr [rip+g_code_growth_factor]
    test rdx,rdx
    jnz .gpca_fail
    cmp rax,65536                # allocator floor, never a semantic ceiling
    jae .gpca_align
    mov eax,65536
.gpca_align:
    add rax,4095
    jc .gpca_fail
    and rax,-4096
    mov [rip+g_code_capacity],rax

    mov rdi,[rip+g_code_ptr]
    test rdi,rdi
    jz .gpca_map_serial
    mov rsi,[rip+g_code_capacity_prev]
    mov eax,SYS_munmap
    syscall
.gpca_map_serial:
    mov rsi,[rip+g_code_capacity]
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gpca_fail
    mov [rip+g_code_ptr],rax
    mov [rip+g_emit_ptr],rax
    mov rcx,rax
    add rcx,[rip+g_code_capacity]
    jc .gpca_unmap_serial
    mov [rip+g_emit_end],rcx
    mov [rip+g_image_code_ptr],rax

    mov rdi,[rip+g_parallel_code_ptr]
    test rdi,rdi
    jz .gpca_map_parallel
    mov rsi,[rip+g_parallel_code_capacity_prev]
    mov eax,SYS_munmap
    syscall
.gpca_map_parallel:
    mov rsi,[rip+g_code_capacity]
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gpca_unmap_serial
    mov [rip+g_parallel_code_ptr],rax
    mov rcx,[rip+g_code_capacity]
    mov [rip+g_parallel_code_capacity],rcx
    mov [rip+g_code_capacity_prev],rcx
    mov [rip+g_parallel_code_capacity_prev],rcx
    xor eax,eax
    pop rbx
    ret
.gpca_unmap_serial:
    mov rdi,[rip+g_code_ptr]
    test rdi,rdi
    jz .gpca_fail
    mov rsi,[rip+g_code_capacity]
    mov eax,SYS_munmap
    syscall
    mov qword ptr [rip+g_code_ptr],0
.gpca_fail:
    mov eax,1
    pop rbx
    ret

# Sum exact Rank-N decimal-ingress workspace for all fpP inputs.  Each fpP
# parser instance uses five equal P-derived carriers: raw/normalized numerator,
# raw/normalized denominator, and result; scalar inputs contribute zero bytes.
# Returns rax=bytes, edx=0/1.
g_measure_rankn_input_workspace:
    push rbx
    push r12
    push r13
    xor r12,r12
    xor r13d,r13d
.gmriw_loop:
    cmp r13d,dword ptr [rip+g_input_count]
    jae .gmriw_ok
    mov rax,[rip+g_input_types_ptr]
    mov edi,dword ptr [rax+r13*4]
    call g_float_precision
    cmp rax,64
    jbe .gmriw_next
    mov rax,[rip+g_input_types_ptr]
    mov edi,dword ptr [rax+r13*4]
    call g_rankn_fp_object_span
    test rax,rax
    jz .gmriw_fail
    mov rbx,rax
    imul rbx,rbx,5
    jo .gmriw_fail
    add r12,rbx
    jc .gmriw_fail
.gmriw_next:
    inc r13d
    jmp .gmriw_loop
.gmriw_ok:
    mov rax,r12
    xor edx,edx
    pop r13
    pop r12
    pop rbx
    ret
.gmriw_fail:
    xor eax,eax
    mov edx,1
    pop r13
    pop r12
    pop rbx
    ret

# Measure the largest iterate state vector represented by this program. Every
# live iterate receives exactly this many execution-local state cells; sibling
# executions own disjoint stacks and sequential episodes reuse the same frame
# after causal death. No global state cardinality or owner table is required.
g_measure_runtime_state_capacity:
    push rbx
    push r12
    push r13
    xor r12d,r12d
    xor r13d,r13d
.gmrsc_symbol_loop:
    cmp r12d,dword ptr [rip+g_symbol_count]
    jae .gmrsc_done
    mov eax,r12d
    shl rax,6
    mov rbx,[rip+g_symbols_ptr]
    add rbx,rax
    cmp dword ptr [rbx+16],GK_ITERATE
    jne .gmrsc_next_symbol
    mov rdi,[rbx+32]
    test rdi,rdi
    jz .gmrsc_fail
    lea rsi,[rip+gk_states]
    mov edx,gk_states_end-gk_states
    call obj_get
    test rax,rax
    jz .gmrsc_fail
    cmp qword ptr [rax],J_ARRAY
    jne .gmrsc_fail
    mov rbx,[rax+24]
    xor ecx,ecx
.gmrsc_state_loop:
    test rbx,rbx
    jz .gmrsc_state_done
    cmp ecx,-1
    je .gmrsc_fail
    inc ecx
    mov rbx,[rbx+32]
    jmp .gmrsc_state_loop
.gmrsc_state_done:
    cmp r13d,ecx
    cmovb r13d,ecx
.gmrsc_next_symbol:
    inc r12d
    jmp .gmrsc_symbol_loop
.gmrsc_done:
    mov dword ptr [rip+g_runtime_state_capacity],r13d
    xor eax,eax
    pop r13
    pop r12
    pop rbx
    ret
.gmrsc_fail:
    mov eax,1
    pop r13
    pop r12
    pop rbx
    ret

# Derive the target program's mutable arena layout before code emission.  The
# Input workspace is proportional to actual input count. Mutable iterate state
# no longer occupies this shared arena: its current/next-version authorities are
# execution-local and die with the causal stack frame. fpP temporaries grow by
# exact object spans during AOT lowering.
g_prepare_runtime_arena_layout:
    push rbx
    mov rax,GENERAL_RUNTIME_DYNAMIC_ARENA_VA

    # Dense scalar/string ingress records.
    mov [rip+g_runtime_input_values_base_va],rax
    mov ecx,dword ptr [rip+g_input_count]
    mov rdx,rcx
    shl rdx,3
    jc .gpral_fail
    add rax,rdx
    jc .gpral_fail
    add rax,63
    jc .gpral_fail
    and rax,-64
    mov [rip+g_runtime_input_aux_base_va],rax
    add rax,rdx
    jc .gpral_fail
    add rax,63
    jc .gpral_fail
    and rax,-64

    # Rank-N decimal ingress is precision-derived as well: each fpP input owns
    # exactly five object spans computed from its own P.  No 8 MiB input stride
    # or 1 MiB object tier remains.
    mov [rip+g_runtime_rankn_input_base_va],rax
    mov rbx,rax
    call g_measure_rankn_input_workspace
    test edx,edx
    jnz .gpral_fail
    add rbx,rax
    jc .gpral_fail
    mov rax,rbx
    mov [rip+g_runtime_rankn_input_end_va],rax
    add rax,63
    jc .gpral_fail
    and rax,-64

    # Mutable iterate StateFacts do not live in the shared invocation arena.
    # They are execution-local and die with the causal execution stack.  The
    # global address space therefore carries no persistent state bank and no
    # next-version mailbox bank.

    # Existing binding ownership pages are fused into the same instance arena.
    mov [rip+g_runtime_binding_base_va],rax
    mov ecx,dword ptr [rip+g_binding_slot_count]
    mov rdx,rcx
    shl rdx,12
    jc .gpral_fail
    add rax,rdx
    jc .gpral_fail
    add rax,63
    jc .gpral_fail
    and rax,-64

    # Output ownership pages and string-length auxiliaries are exact-count
    # instance storage, not a 32-entry runtime record.
    mov [rip+g_runtime_output_pages_base_va],rax
    mov ecx,dword ptr [rip+g_output_capacity]
    mov rdx,rcx
    shl rdx,12
    jc .gpral_fail
    add rax,rdx
    jc .gpral_fail
    add rax,63
    jc .gpral_fail
    and rax,-64
    mov [rip+g_runtime_output_aux_base_va],rax
    mov ecx,dword ptr [rip+g_output_capacity]
    mov rdx,rcx
    shl rdx,3
    jc .gpral_fail
    add rax,rdx
    jc .gpral_fail
    add rax,63
    jc .gpral_fail
    and rax,-64

    mov [rip+g_runtime_rankn_temp_base_va],rax
    xor eax,eax
    pop rbx
    ret
.gpral_fail:
    mov eax,1
    pop rbx
    ret

# g_add_symbol(name ptr,len,kind,type,node,slot). eax=0 success/1 failure
g_add_symbol:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi; mov r13,rsi; mov r14d,edx; mov r15d,ecx; mov rbx,r8
    push r9
    call g_find_symbol
    test rax,rax
    jnz .gas_fail_pop
    mov eax,dword ptr [rip+g_symbol_count]
    cmp eax,dword ptr [rip+g_symbol_capacity]
    jae .gas_fail_pop
    mov ecx,eax; shl rcx,6; mov rax,[rip+g_symbols_ptr]; add rax,rcx
    mov [rax],r12; mov [rax+8],r13; mov [rax+16],r14d; mov [rax+20],r15d
    pop r9
    mov [rax+24],r9d; mov [rax+32],rbx
    # The tail of the existing 64-byte symbol record is the convergence witness.
    # +40 is the canonical semantic representative, +48 is reserved for an
    # optional proof fingerprint, +56 carries convergence facts.  No shadow IR.
    mov [rax+40],rax
    mov qword ptr [rax+48],0
    mov qword ptr [rax+56],0
    inc dword ptr [rip+g_symbol_count]
    xor eax,eax
    jmp .gas_done
.gas_fail_pop:
    add rsp,8
    mov eax,1
.gas_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# g_find_symbol(rdi=nameptr,rsi=len) -> rax/0
g_find_symbol:
    xor ecx,ecx
.gfs_loop:
    cmp ecx,dword ptr [rip+g_symbol_count]; jae .gfs_no
    mov eax,ecx; shl rax,6; mov r8,[rip+g_symbols_ptr]; add r8,rax
    cmp [r8+8],rsi; jne .gfs_next
    xor r9d,r9d
.gfs_cmp:
    cmp r9,rsi; jae .gfs_yes
    mov r10,[r8]; mov al,[r10+r9]; cmp al,[rdi+r9]; jne .gfs_next
    inc r9; jmp .gfs_cmp
.gfs_yes: mov rax,r8; ret
.gfs_next: inc ecx; jmp .gfs_loop
.gfs_no: xor eax,eax; ret

# g_classify_binding_op(rdi=ptr,rsi=len) -> eax kind/0
.macro OPCHK label,str,kind
\label:
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+\str]; mov ecx,\str\()_end-\str; call span_eq
    test eax,eax
    jz \label\()_next
    mov eax,\kind
    jmp .gcbo_done
\label\()_next:
.endm
g_classify_binding_op:
    push r12; push r13
    mov r12,rdi; mov r13,rsi
    OPCHK .op1,gv_compute,GK_COMPUTE
    OPCHK .op2,gv_map,GK_MAP
    OPCHK .op3,gv_reduce,GK_REDUCE
    OPCHK .op4,gv_iterate,GK_ITERATE
    OPCHK .op5,gv_record,GK_RECORD
    OPCHK .op6,gv_dictionary,GK_DICTIONARY
    OPCHK .op7,gv_lookup,GK_LOOKUP
    OPCHK .op8,gv_nested_literal,GK_NESTED_LITERAL
    OPCHK .op9,gv_nested_reduce,GK_NESTED_REDUCE
    OPCHK .op10,gv_cascade,GK_CASCADE
    xor eax,eax
.gcbo_done:
    pop r13; pop r12; ret

# one-axis validator. rdi=binding node -> eax 0 ok/1 bad
g_validate_one_axis:
    push rbx
    mov rbx,rdi
    lea rsi,[rip+gk_axes]; mov edx,gk_axes_end-gk_axes; call obj_get
    test rax,rax; jz .gvo_bad
    cmp qword ptr [rax],J_ARRAY; jne .gvo_bad
    mov rax,[rax+24]; test rax,rax; jz .gvo_bad
    cmp qword ptr [rax+32],0; jne .gvo_bad
    cmp qword ptr [rax],J_OBJECT; jne .gvo_bad
    xor eax,eax; pop rbx; ret
.gvo_bad: mov eax,1; pop rbx; ret


# ---------------- human semantic convergence ----------------
# The General frontend already owns a topologically ordered typed symbol DAG.
# Human spelling variation reaches one semantic representative before the first
# fragment is materialized.  1.3.69 ages the 1.3.68 identity proof into a small
# proof closure instead of adding an optimizer family:
#   * immutable aliases and exact pure trees still collapse;
#   * same-type casts and neutral integer/Boolean shells erase into old facts;
#   * total commutative relations may erase operand-order spelling;
#   * < / > and <= / >= dual spellings may converge after operand exchange;
#   * associative regrouping, strict-FP arithmetic reordering and effects remain
#     outside the proof.  Unproved structure stays on the old path.
# No retry count, rewrite budget, workload name or algorithm recognizer exists.

# rdi=symbol -> rax=canonical semantic representative (never follows a shadow IR).
g_semantic_resolve_symbol:
    test rdi,rdi
    jz .gsrs_no
    mov rax,[rdi+40]
    test rax,rax
    cmovz rax,rdi
    ret
.gsrs_no:
    xor eax,eax
    ret

# rdi=a ptr,rsi=a len,rdx=b ptr,rcx=b len -> eax=1/0.
g_semantic_span_equal:
    cmp rsi,rcx
    jne .gsse_no
    xor r8,r8
.gsse_loop:
    cmp r8,rsi
    jae .gsse_yes
    mov al,[rdi+r8]
    cmp al,[rdx+r8]
    jne .gsse_no
    inc r8
    jmp .gsse_loop
.gsse_yes:
    mov eax,1
    ret
.gsse_no:
    xor eax,eax
    ret

# rdi=node -> eax=1 iff the expression is immutable scalar semantic structure
# suitable for zero-flip convergence.  Non-scalar/mutable facts simply remain.
g_semantic_expr_is_pure:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    test r12,r12; jz .gseip_no
    cmp qword ptr [r12],J_OBJECT; jne .gseip_no
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jnz .gseip_yes
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gseip_op
    # A variable leaf is pure only when its authority is invocation-immutable.
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gseip_no
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gseip_no
    mov ecx,dword ptr [rax+16]
    cmp ecx,GK_INPUT; je .gseip_yes
    cmp ecx,GK_COMPUTE; je .gseip_yes
    jmp .gseip_no
.gseip_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gseip_no
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gseip_no
    cmp qword ptr [rax],J_ARRAY; jne .gseip_no
    mov r13,[rax+24]
    test r13,r13; jz .gseip_no
.gseip_arg_loop:
    mov rdi,r13; call g_semantic_expr_is_pure
    test eax,eax; jz .gseip_no
    mov r13,[r13+32]
    test r13,r13; jnz .gseip_arg_loop
.gseip_yes:
    mov eax,1; jmp .gseip_done
.gseip_no:
    xor eax,eax
.gseip_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=nodeA,rsi=nodeB -> eax=1 iff exact canonical JSON semantics are equal,
# except that a single-field {var:...} leaf compares semantic representatives.
# Object key order is already canonicalized by the human surface; preserving it
# here intentionally prevents this proof from becoming a rewrite engine.
g_semantic_json_equal:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi
    cmp r12,r13; je .gsje_yes
    test r12,r12; jz .gsje_no
    test r13,r13; jz .gsje_no
    mov rax,[r12]
    cmp rax,[r13]; jne .gsje_no
    cmp rax,J_STRING; je .gsje_span
    cmp rax,J_NUMBER; je .gsje_span
    cmp rax,J_TRUE; je .gsje_yes
    cmp rax,J_FALSE; je .gsje_yes
    cmp rax,J_NULL; je .gsje_yes
    cmp rax,J_ARRAY; je .gsje_array
    cmp rax,J_OBJECT; jne .gsje_no

    # Canonical var leaf: compare already-converged symbol identities, not names.
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gsje_object
    mov r14,rax
    cmp qword ptr [r12+24],r14; jne .gsje_object
    cmp qword ptr [r14+32],0; jne .gsje_object
    mov rdi,r13; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gsje_no
    cmp qword ptr [r13+24],rax; jne .gsje_object
    cmp qword ptr [rax+32],0; jne .gsje_object
    mov r15,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; call g_find_symbol
    test rax,rax; jz .gsje_no
    mov rdi,rax; call g_semantic_resolve_symbol; mov r14,rax
    mov rdi,[r15+8]; mov rsi,[r15+16]; call g_find_symbol
    test rax,rax; jz .gsje_no
    mov rdi,rax; call g_semantic_resolve_symbol
    cmp r14,rax; sete al; movzx eax,al
    jmp .gsje_done

.gsje_span:
    mov rdi,[r12+8]; mov rsi,[r12+16]
    mov rdx,[r13+8]; mov rcx,[r13+16]
    call g_semantic_span_equal
    jmp .gsje_done
.gsje_array:
    mov r14,[r12+24]; mov r15,[r13+24]
.gsje_array_loop:
    test r14,r14; jz .gsje_array_a_end
    test r15,r15; jz .gsje_no
    mov rdi,r14; mov rsi,r15; call g_semantic_json_equal
    test eax,eax; jz .gsje_no
    mov r14,[r14+32]; mov r15,[r15+32]
    jmp .gsje_array_loop
.gsje_array_a_end:
    test r15,r15; jnz .gsje_no
    jmp .gsje_yes

.gsje_object:
    mov r14,[r12+24]; mov r15,[r13+24]
.gsje_object_loop:
    test r14,r14; jz .gsje_object_a_end
    test r15,r15; jz .gsje_no
    mov rdi,[r14+40]; mov rsi,[r14+48]
    mov rdx,[r15+40]; mov rcx,[r15+48]
    call g_semantic_span_equal
    test eax,eax; jz .gsje_no
    mov rdi,r14; mov rsi,r15; call g_semantic_json_equal
    test eax,eax; jz .gsje_no
    mov r14,[r14+32]; mov r15,[r15+32]
    jmp .gsje_object_loop
.gsje_object_a_end:
    test r15,r15; jnz .gsje_no
.gsje_yes:
    mov eax,1; jmp .gsje_done
.gsje_no:
    xor eax,eax
.gsje_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret


# rdi=node, esi=expected GTYPE or 0 -> rax=canonical variable representative/0.
# This is a view over the existing symbol table, not a new semantic store.
g_semantic_var_representative:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13d,esi
    test r12,r12; jz .gsvr_no
    cmp qword ptr [r12],J_OBJECT; jne .gsvr_no
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gsvr_no
    mov rbx,rax
    cmp qword ptr [r12+24],rbx; jne .gsvr_no
    cmp qword ptr [rbx+32],0; jne .gsvr_no
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; call g_find_symbol
    test rax,rax; jz .gsvr_no
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gsvr_no
    test r13d,r13d; jz .gsvr_done
    cmp dword ptr [rax+20],r13d; jne .gsvr_no
    jmp .gsvr_done
.gsvr_no:
    xor eax,eax
.gsvr_done:
    pop r13; pop r12; pop rbx; ret

# rdi=expr -> eax=0/1, edx=GTYPE_I64/U64, ecx=0 success / 1 no-match.
# Only the algebraic identity literals are admitted; there is no constant-
# folding authority here.
g_semantic_int01_literal:
    push rbx; push r12
    mov rbx,rdi
    cmp qword ptr [rbx],J_OBJECT; jne .gsil_bad
    mov rdi,rbx; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gsil_bad
    mov rdi,rax; call g_type_from_node; mov r12d,eax
    cmp r12d,GTYPE_I64; je .gsil_type_ok
    cmp r12d,GTYPE_U64; jne .gsil_bad
.gsil_type_ok:
    mov rdi,rbx; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gsil_bad
    mov rdi,rax; call g_parse_i64_node
    test edx,edx; jnz .gsil_bad
    cmp rax,1; ja .gsil_bad
    mov edx,r12d; xor ecx,ecx; jmp .gsil_done
.gsil_bad:
    xor eax,eax; xor edx,edx; mov ecx,1
.gsil_done:
    pop r12; pop rbx; ret

# rdi=expr -> eax=1 iff evaluating the expression cannot introduce a language-
# visible trap/effect. Earlier compute references are already materialized facts,
# so a var leaf is a total load even if its producer had an earlier trap edge.
# This proof exists only to license operand-order erasure; it never emits code.
g_semantic_expr_is_total:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    test r12,r12; jz .gseit_no
    cmp qword ptr [r12],J_OBJECT; jne .gseit_no
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jnz .gseit_yes
    mov rdi,r12; xor esi,esi; call g_semantic_var_representative
    test rax,rax; jnz .gseit_yes
    # Total StateFact reads do not imply immutable invocation purity.
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gseit_coordinate
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jnz .gseit_yes
    jmp .gseit_no
.gseit_coordinate:
    # Independent coordinates and identity pullbacks are immutable values.
    mov rdi,r12; lea rsi,[rip+gk_axis]; mov edx,gk_axis_end-gk_axis; call obj_get
    test rax,rax; jnz .gseit_yes
    mov rdi,r12; lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gseit_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gseit_no
    cmp dword ptr [rax+16],GK_MAP; jne .gseit_no
    mov rbx,[rax+32]
    mov rdi,r12; call g_phys_identity_axis_episode
    test eax,eax; jz .gseit_no
    mov rdi,rbx; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gseit_no
    mov rdi,rax; call g_semantic_expr_is_total
    jmp .gseit_done
.gseit_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gseit_no
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gseit_no
    cmp qword ptr [rax],J_ARRAY; jne .gseit_no
    mov r14,[rax+24]; test r14,r14; jz .gseit_no
.gseit_args:
    mov rdi,r14; call g_semantic_expr_is_total
    test eax,eax; jz .gseit_no
    mov r14,[r14+32]; test r14,r14; jnz .gseit_args

    # Boolean relations and exact bit relations are total once their children are.
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_compare_op; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_bit_not]; mov ecx,gv_bit_not_end-gv_bit_not; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_bit_binary; test eax,eax; jnz .gseit_yes

    # Lazy selection may reorder only total children. Native floating-point
    # operations produce values (including NaN/infinity), not language traps.
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,r12; call g_infer_expr; mov r15d,eax
    cmp eax,GTYPE_F32; je .gseit_fp
    cmp eax,GTYPE_F64; jne .gseit_numeric
.gseit_fp:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_exp]; mov ecx,gv_exp_end-gv_exp; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_log]; mov ecx,gv_log_end-gv_log; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sin]; mov ecx,gv_sin_end-gv_sin; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cos]; mov ecx,gv_cos_end-gv_cos; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_fma]; mov ecx,3; call span_eq; test eax,eax; jnz .gseit_yes
    jmp .gseit_no
.gseit_numeric:
    # Integer min/max are total. Integer arithmetic is total only in the existing
    # wrap contract; trap arithmetic remains observable and therefore blocks
    # reordering through a nested subtree.
    mov rdi,r12; call g_infer_expr; mov r15d,eax
    cmp r15d,GTYPE_I64; je .gseit_int
    cmp r15d,GTYPE_U64; jne .gseit_no
.gseit_int:
    cmp r15d,GTYPE_U64; jne .gseit_int_regular
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq; test eax,eax; jnz .gseit_unsigned_divisor
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jz .gseit_int_regular
.gseit_unsigned_divisor:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    mov rdi,[rax+24]; mov rdi,[rdi+32]; test rdi,rdi; jz .gseit_no
    cmp qword ptr [rdi+32],0; jne .gseit_no
    call g_expr_u64_literal; test edx,edx; jnz .gseit_no
    test rax,rax; jz .gseit_no
    jmp .gseit_yes
.gseit_int_regular:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq; test eax,eax; jnz .gseit_yes
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gseit_no
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq; test eax,eax; jnz .gseit_yes
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq; test eax,eax; jnz .gseit_yes
    jmp .gseit_no
.gseit_yes:
    mov eax,1; jmp .gseit_done
.gseit_no:
    xor eax,eax
.gseit_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=declared result type -> rax=existing semantic representative/0
# when the expression is only an identity shell around a direct fact. This is
# proof-directed erasure, not AST rewriting: the source node remains untouched.
g_semantic_identity_representative:
    push rbx
    mov ebx,esi
    call g_semantic_identity_operand
    test rax,rax; jz .gsir_done
    mov rdi,rax; mov esi,ebx; call g_semantic_var_representative
.gsir_done: pop rbx; ret

# rdi=expression, esi=natural type -> rax=proper identity operand or zero.
# No node rewrite, alternative IR, reassociation or eager arm execution occurs.
g_semantic_identity_operand:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi
    mov rdi,r12; call g_infer_expr; cmp eax,r13d; jne .gsio_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gsio_no
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gsio_no
    cmp qword ptr [rax],J_ARRAY; jne .gsio_no
    mov r15,[rax+24]; test r15,r15; jz .gsio_no

    # Same-type cast is representation identity.
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jz .gsio_binary
    cmp qword ptr [r15+32],0; jne .gsio_no
    mov rax,r15; jmp .gsio_operand_type

.gsio_binary:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gsio_binary_pair
    mov rbx,[r15+32]; test rbx,rbx; jz .gsio_no
    mov r14,[rbx+32]; test r14,r14; jz .gsio_no
    cmp qword ptr [r14+32],0; jne .gsio_no
    mov rdi,r15; call g_expr_bool_literal; test edx,edx; jnz .gsio_no
    test eax,eax; jnz .gsio_return_right
    mov rax,r14; jmp .gsio_operand_type
.gsio_binary_pair:
    mov rbx,[r15+32]; test rbx,rbx; jz .gsio_no
    cmp qword ptr [rbx+32],0; jne .gsio_no
    cmp r13d,GTYPE_BOOL; je .gsio_bool
    cmp r13d,GTYPE_I64; je .gsio_int
    cmp r13d,GTYPE_U64; jne .gsio_no
.gsio_int:
    # Right identity literal.
    mov rdi,rbx; call g_semantic_int01_literal
    test ecx,ecx; jnz .gsio_int_left
    cmp edx,r13d; jne .gsio_int_left
    mov r12d,eax
    cmp r12d,0; jne .gsio_right_one
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gsio_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gsio_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gsio_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gsio_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq; test eax,eax; jnz .gsio_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq; test eax,eax; jnz .gsio_return_left
    jmp .gsio_int_left
.gsio_right_one:
    cmp r12d,1; jne .gsio_int_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gsio_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jnz .gsio_return_left
.gsio_int_left:
    mov rdi,r15; call g_semantic_int01_literal
    test ecx,ecx; jnz .gsio_no
    cmp edx,r13d; jne .gsio_no
    mov r12d,eax
    cmp r12d,0; jne .gsio_left_one
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gsio_return_right
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gsio_return_right
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gsio_return_right
    jmp .gsio_no
.gsio_left_one:
    cmp r12d,1; jne .gsio_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gsio_return_right
    jmp .gsio_no

.gsio_bool:
    # x && true, true && x, x || false, false || x, x xor false.
    mov rdi,rbx; call g_expr_bool_literal; test edx,edx; jnz .gsio_bool_left
    mov r12d,eax
    cmp r12d,1; jne .gsio_bool_right_false
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq; test eax,eax; jnz .gsio_return_left
    jmp .gsio_bool_left
.gsio_bool_right_false:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq; test eax,eax; jnz .gsio_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq; test eax,eax; jnz .gsio_return_left
.gsio_bool_left:
    mov rdi,r15; call g_expr_bool_literal; test edx,edx; jnz .gsio_no
    mov r12d,eax
    cmp r12d,1; jne .gsio_bool_left_false
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq; test eax,eax; jnz .gsio_return_right
    jmp .gsio_no
.gsio_bool_left_false:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq; test eax,eax; jnz .gsio_return_right
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq; test eax,eax; jnz .gsio_return_right
    jmp .gsio_no

.gsio_return_left:
    mov rax,r15; jmp .gsio_operand_type
.gsio_return_right:
    mov rax,rbx; jmp .gsio_operand_type
.gsio_operand_type:
    mov r12,rax; mov rdi,rax; call g_infer_expr
    cmp eax,r13d; jne .gsio_no
    mov rax,r12; jmp .gsio_done
.gsio_no:
    xor eax,eax
.gsio_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=nodeA,rsi=nodeB -> eax=1 iff equivalence follows from the existing typed
# semantic facts. Exact equality is the base case. The only additional closure is
# operand-order erasure for total commutative relations and comparison duality.
# Associative regrouping is intentionally absent, so strict FP structure remains.
g_semantic_prove_equal:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,48
    mov r12,rdi; mov r13,rsi
    call g_semantic_json_equal
    test eax,eax; jnz .gspe_yes
    test r12,r12; jz .gspe_no
    test r13,r13; jz .gspe_no
    cmp qword ptr [r12],J_OBJECT; jne .gspe_no
    cmp qword ptr [r13],J_OBJECT; jne .gspe_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gspe_no
    mov [rsp],rax
    mov rdi,r13; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gspe_no
    mov [rsp+8],rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gspe_no
    cmp qword ptr [rax],J_ARRAY; jne .gspe_no
    mov r14,[rax+24]; test r14,r14; jz .gspe_no
    mov r15,[r14+32]; test r15,r15; jz .gspe_no
    cmp qword ptr [r15+32],0; jne .gspe_no
    mov [rsp+16],r14; mov [rsp+24],r15
    mov rdi,r13; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gspe_no
    cmp qword ptr [rax],J_ARRAY; jne .gspe_no
    mov r14,[rax+24]; test r14,r14; jz .gspe_no
    mov r15,[r14+32]; test r15,r15; jz .gspe_no
    cmp qword ptr [r15+32],0; jne .gspe_no
    mov [rsp+32],r14; mov [rsp+40],r15

    # Same relation: first propagate already-proved child equivalence in source
    # order. This allows proof facts to compose without any global rewrite pass.
    mov rax,[rsp]; mov rbx,[rsp+8]
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov rdx,[rbx+8]; mov rcx,[rbx+16]; call g_semantic_span_equal
    test eax,eax; jz .gspe_inverse_probe
    mov rdi,[rsp+16]; mov rsi,[rsp+32]; call g_semantic_prove_equal
    test eax,eax; jz .gspe_same_commute
    mov rdi,[rsp+24]; mov rsi,[rsp+40]; call g_semantic_prove_equal
    test eax,eax; jnz .gspe_yes

.gspe_same_commute:
    # Reordering is allowed only when all children are total semantic facts.
    mov rdi,[rsp+16]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
    mov rdi,[rsp+24]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
    mov rdi,[rsp+32]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
    mov rdi,[rsp+40]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
    mov rax,[rsp]
    # eq/ne are symmetric for every admitted total scalar domain.
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq; test eax,eax; jnz .gspe_swap
    # Boolean relations.
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq; test eax,eax; jnz .gspe_swap
    # Exact integer relations only. Floating add/mul/min/max never reach this law.
    mov rdi,r12; call g_infer_expr; mov ebx,eax
    cmp ebx,GTYPE_I64; je .gspe_int_comm
    cmp ebx,GTYPE_U64; jne .gspe_no
.gspe_int_comm:
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_bit_and]; mov ecx,gv_bit_and_end-gv_bit_and; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gspe_swap
    mov rax,[rsp]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gspe_swap
    jmp .gspe_no

.gspe_inverse_probe:
    # a<b == b>a and a<=b == b>=a, but only across total children.
    mov rax,[rsp]; mov rbx,[rsp+8]
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq
    test eax,eax; jz .gspe_inv_gt
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq; test eax,eax; jnz .gspe_inverse_total
.gspe_inv_gt:
    mov rax,[rsp]; mov rbx,[rsp+8]
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq
    test eax,eax; jz .gspe_inv_le
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gspe_inverse_total
.gspe_inv_le:
    mov rax,[rsp]; mov rbx,[rsp+8]
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq
    test eax,eax; jz .gspe_inv_ge
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gspe_inverse_total
.gspe_inv_ge:
    mov rax,[rsp]; mov rbx,[rsp+8]
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq
    test eax,eax; jz .gspe_no
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq; test eax,eax; jz .gspe_no
.gspe_inverse_total:
    mov rdi,[rsp+16]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
    mov rdi,[rsp+24]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
    mov rdi,[rsp+32]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
    mov rdi,[rsp+40]; call g_semantic_expr_is_total; test eax,eax; jz .gspe_no
.gspe_swap:
    mov rdi,[rsp+16]; mov rsi,[rsp+40]; call g_semantic_prove_equal
    test eax,eax; jz .gspe_no
    mov rdi,[rsp+24]; mov rsi,[rsp+32]; call g_semantic_prove_equal
    test eax,eax; jnz .gspe_yes
.gspe_no:
    xor eax,eax; jmp .gspe_done
.gspe_yes:
    mov eax,1
.gspe_done:
    add rsp,48
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# One topological closure over represented symbols.  eax=0 success.
g_semantic_converge_symbols:
    push rbx; push r12; push r13; push r14; push r15
    xor ebx,ebx
.gscs_symbol_loop:
    cmp ebx,dword ptr [rip+g_symbol_count]; jae .gscs_ok
    mov eax,ebx; shl rax,6; mov r12,[rip+g_symbols_ptr]; add r12,rax
    cmp dword ptr [r12+16],GK_COMPUTE; jne .gscs_next
    mov rdi,[r12+32]; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gscs_fail
    mov r13,rax
    mov rdi,r13; call g_semantic_expr_is_pure
    test eax,eax; jz .gscs_next
    or qword ptr [r12+56],1

    # Proof-level identity shells disappear into the same old representative.
    # This covers same-type casts and literal neutral elements without rewriting
    # the expression tree or introducing a new optimizer authority.
    mov rdi,r13; mov esi,dword ptr [r12+20]; call g_semantic_identity_representative
    test rax,rax; jz .gscs_alias_probe
    mov [r12+40],rax
    or qword ptr [r12+56],6
    mov rdi,[r12]; mov rsi,[r12+8]; call surface_note_convergence_name
    jmp .gscs_next

.gscs_alias_probe:
    # Direct aliases disappear first.  Equal type is mandatory because a declared
    # compute type is a real consumer-edge representation request.
    mov rdi,r13; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gscs_equal_scan
    cmp qword ptr [r13+24],rax; jne .gscs_equal_scan
    cmp qword ptr [rax+32],0; jne .gscs_equal_scan
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gscs_fail
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gscs_fail
    mov ecx,dword ptr [rax+20]
    cmp ecx,dword ptr [r12+20]; jne .gscs_equal_scan
    mov [r12+40],rax
    or qword ptr [r12+56],2
    mov rdi,[r12]; mov rsi,[r12+8]; call surface_note_convergence_name
    jmp .gscs_next

.gscs_equal_scan:
    # Only earlier canonical compute representatives can own this fact.  Source
    # order is already a causal topological order, so no repeated global pass is
    # needed to reach the fixed point.
    xor r14d,r14d
.gscs_candidate_loop:
    cmp r14d,ebx; jae .gscs_next
    mov eax,r14d; shl rax,6; mov r15,[rip+g_symbols_ptr]; add r15,rax
    cmp dword ptr [r15+16],GK_COMPUTE; jne .gscs_candidate_next
    mov rdi,r15; call g_semantic_resolve_symbol
    cmp rax,r15; jne .gscs_candidate_next
    mov ecx,dword ptr [r15+20]
    cmp ecx,dword ptr [r12+20]; jne .gscs_candidate_next
    test qword ptr [r15+56],1; jz .gscs_candidate_next
    mov rdi,[r15+32]; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gscs_candidate_next
    mov rdi,r13; mov rsi,rax; call g_semantic_prove_equal
    test eax,eax; jz .gscs_candidate_next
    mov [r12+40],r15
    or qword ptr [r12+56],10
    mov rdi,[r12]; mov rsi,[r12+8]; call surface_note_convergence_name
    jmp .gscs_next
.gscs_candidate_next:
    inc r14d
    jmp .gscs_candidate_loop
.gscs_next:
    inc ebx
    jmp .gscs_symbol_loop
.gscs_ok:
    xor eax,eax; jmp .gscs_done
.gscs_fail:
    mov eax,1
.gscs_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- expression type inference ----------------
# g_infer_expr(rdi=expr) -> eax type/0. State context is g_state table.
g_infer_expr:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    test r12,r12; jz .gie_bad
    cmp qword ptr [r12],J_OBJECT; jne .gie_bad
    # literal
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gie_var
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gie_bad
    mov rdi,rax; call g_type_from_node; jmp .gie_done
.gie_var:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gie_axis
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gie_bad
    mov eax,dword ptr [rax+20]; jmp .gie_done
.gie_axis:
    mov rdi,r12; lea rsi,[rip+gk_axis]; mov edx,gk_axis_end-gk_axis; call obj_get
    test rax,rax; jz .gie_state
    mov eax,GTYPE_U64; jmp .gie_done
.gie_state:
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gie_field
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gie_bad
    mov eax,dword ptr [rax+16]; jmp .gie_done
.gie_field:
    mov rdi,r12; lea rsi,[rip+gk_field]; mov edx,gk_field_end-gk_field; call obj_get
    test rax,rax; jz .gie_load
    mov r13,rax
    mov rdi,r13; call g_resolve_field_expr
    test rax,rax; jnz .gie_field_static
    mov rdi,r13; call g_iter_field_info
    test rax,rax; jz .gie_bad
    mov eax,ecx; jmp .gie_done
.gie_field_static:
    mov rdi,rax; call g_infer_expr; jmp .gie_done
.gie_load:
    mov rdi,r12; lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gie_dictlookup
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gie_bad
    cmp dword ptr [rax+16],GK_MAP; jne .gie_bad
    mov eax,dword ptr [rax+20]; jmp .gie_done
.gie_dictlookup:
    mov rdi,r12; lea rsi,[rip+gk_dictionary_lookup]; mov edx,gk_dictionary_lookup_end-gk_dictionary_lookup; call obj_get
    test rax,rax; jz .gie_op
    mov rdi,rax; call g_dictlookup_value_type; jmp .gie_done
.gie_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gie_bad
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gie_bad
    mov r14,[rax+24]; test r14,r14; jz .gie_bad
    # unary ops/cast/not/bit_not/neg/abs handled first
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jz 1f
    mov rdi,r12; lea rsi,[rip+gk_to]; mov edx,gk_to_end-gk_to; call obj_get
    test rax,rax; jz .gie_bad
    mov rdi,rax; call g_type_from_node; jmp .gie_done
1:  mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq
    test eax,eax; jnz .gie_bool
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_bit_not]; mov ecx,gv_bit_not_end-gv_bit_not; call span_eq
    test eax,eax; jz 2f
    mov rdi,r14; call g_infer_expr; cmp eax,GTYPE_I64; je .gie_done; cmp eax,GTYPE_U64; je .gie_done; jmp .gie_bad
2:  mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq
    test eax,eax; jnz .gie_unary_num
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jnz .gie_unary_num
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jnz .gie_unary_fp_wide
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq
    test eax,eax; jnz .gie_unary_fp_wide
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_trunc]; mov ecx,gv_trunc_end-gv_trunc; call span_eq
    test eax,eax; jnz .gie_unary_fp
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_exp]; mov ecx,gv_exp_end-gv_exp; call span_eq
    test eax,eax; jnz .gie_unary_fp_wide
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_log]; mov ecx,gv_log_end-gv_log; call span_eq
    test eax,eax; jnz .gie_unary_fp_wide
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sin]; mov ecx,gv_sin_end-gv_sin; call span_eq
    test eax,eax; jnz .gie_unary_fp_wide
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cos]; mov ecx,gv_cos_end-gv_cos; call span_eq
    test eax,eax; jnz .gie_unary_fp_wide
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_fma]; mov ecx,3; call span_eq
    test eax,eax; jz .gie_select_probe
    mov r15,r14; xor ebx,ebx
.gie_fma_operand:
    mov rdi,r15; call g_infer_expr; test eax,eax; jz .gie_bad
    test ebx,ebx; jz .gie_fma_first
    mov edx,eax; mov eax,ebx; call g_low_type
.gie_fma_first: mov ebx,eax
    mov r15,[r15+32]; test r15,r15; jnz .gie_fma_operand
    cmp ebx,GTYPE_F32; je .gie_fma_done
    cmp ebx,GTYPE_F64; jne .gie_bad
.gie_fma_done: mov eax,ebx; jmp .gie_done
.gie_select_probe:
    # select has 3 args; result branch low-dominant
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gie_binary
    mov rdi,r14; call g_infer_expr; cmp eax,GTYPE_BOOL; jne .gie_bad
    mov r14,[r14+32]; test r14,r14; jz .gie_bad
    mov rdi,r14; call g_infer_expr; mov ebx,eax; test ebx,ebx; jz .gie_bad
    mov r14,[r14+32]; test r14,r14; jz .gie_bad
    mov rdi,r14; call g_infer_expr; mov ecx,eax; test ecx,ecx; jz .gie_bad
    mov eax,ebx; mov edx,ecx; call g_low_type; jmp .gie_done
.gie_binary:
    mov rdi,r14; call g_infer_expr; mov ebx,eax; test ebx,ebx; jz .gie_bad
    mov r15,[r14+32]; test r15,r15; jz .gie_bad
    mov rdi,r15; call g_infer_expr; mov r14d,eax; test r14d,r14d; jz .gie_bad
    # comparisons
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_compare_op; test eax,eax; jnz .gie_bool
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_bool_binary; test eax,eax; jnz .gie_bool
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_shift_op; test eax,eax; jnz .gie_shift
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_bit_binary; test eax,eax; jnz .gie_int_low
    mov eax,ebx; mov edx,r14d; call g_low_type; jmp .gie_done
.gie_int_low:
    mov eax,ebx; mov edx,r14d; call g_low_type
    cmp eax,GTYPE_I64; je .gie_done; cmp eax,GTYPE_U64; je .gie_done; jmp .gie_bad
.gie_unary_num:
    mov rdi,r14; call g_infer_expr
    cmp eax,GTYPE_I64; je .gie_done; cmp eax,GTYPE_U64; je .gie_done; cmp eax,GTYPE_F32; je .gie_done; cmp eax,GTYPE_F64; je .gie_done
    mov ebx,eax; mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gie_bad; mov eax,ebx; jmp .gie_done
.gie_unary_fp:
    mov rdi,r14; call g_infer_expr
    cmp eax,GTYPE_F32; je .gie_done; cmp eax,GTYPE_F64; je .gie_done; jmp .gie_bad
.gie_unary_fp_wide:
    mov rdi,r14; call g_infer_expr
    cmp eax,GTYPE_F32; je .gie_done; cmp eax,GTYPE_F64; je .gie_done
    mov ebx,eax; mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gie_bad; mov eax,ebx; jmp .gie_done
.gie_bool: mov eax,GTYPE_BOOL; jmp .gie_done
.gie_shift:
    cmp ebx,GTYPE_U64; je 1f; cmp ebx,GTYPE_I64; jne .gie_bad
1:  cmp r14d,GTYPE_U64; je 2f; cmp r14d,GTYPE_I64; jne .gie_bad
2:  mov eax,ebx; jmp .gie_done
.gie_bad: xor eax,eax
.gie_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# g_low_type(eax=a,edx=b) numeric precision-meet authority; 0 mismatch.
# precision_propagation=0 (default): lower FP precision dominates.
# precision_propagation=1: higher FP precision dominates.
# In both modes the policy applies only at the exact consumer edge where the two
# ValueFacts meet; it never tunnels into either child subtree.
g_low_type:
    push rbx
    push r12
    push r13
    mov r12d,eax
    mov r13d,edx
    mov edi,r12d; call g_float_precision; mov rbx,rax
    mov edi,r13d; call g_float_precision; mov rcx,rax
    test rbx,rbx; jnz .glt_have_float
    test rcx,rcx; jnz .glt_only_b_float
    cmp r12d,r13d; jne .glt_bad2
    cmp r12d,GTYPE_I64; je .glt_a
    cmp r12d,GTYPE_U64; je .glt_a
    cmp r12d,GTYPE_BOOL; je .glt_a
    jmp .glt_bad2
.glt_only_b_float:
    mov eax,r13d; jmp .glt_done2
.glt_have_float:
    test rcx,rcx; jz .glt_a
    cmp dword ptr [rip+g_precision_propagation],0
    jne .glt_high2
    cmp rbx,rcx
    jbe .glt_a
    mov eax,r13d; jmp .glt_done2
.glt_high2:
    cmp rbx,rcx
    jae .glt_a
    mov eax,r13d; jmp .glt_done2
.glt_a:
    mov eax,r12d
    jmp .glt_done2
.glt_bad2:
    xor eax,eax
.glt_done2:
    pop r13
    pop r12
    pop rbx
    ret

# comparison/operator recognizers return eax 1/0
.macro ANYOP fname, listprefix
\fname:
    push r12; push r13
    mov r12,rdi; mov r13,rsi
.endm
# Explicit helpers keep the emitted compiler small and auditable.
g_is_compare_op:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq; test eax,eax; jnz .gio_yes
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq; test eax,eax; jnz .gio_yes
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gio_yes
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq; test eax,eax; jnz .gio_yes
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq; test eax,eax; jnz .gio_yes
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gio_yes
    xor eax,eax; jmp .gio_done
.gio_yes: mov eax,1
.gio_done: pop r13; pop r12; ret
g_is_bool_binary:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq; test eax,eax; jnz .gio_yes2
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq; test eax,eax; jnz .gio_yes2
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq; test eax,eax; jnz .gio_yes2
    xor eax,eax; jmp .gio_done2
.gio_yes2: mov eax,1
.gio_done2: pop r13; pop r12; ret
g_is_bit_binary:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_bit_and]; mov ecx,gv_bit_and_end-gv_bit_and; call span_eq; test eax,eax; jnz .gio_yes3
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gio_yes3
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gio_yes3
    xor eax,eax; jmp .gio_done3
.gio_yes3: mov eax,1
.gio_done3: pop r13; pop r12; ret
g_is_shift_op:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq; test eax,eax; jnz .gio_yes4
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq; test eax,eax; jnz .gio_yes4
    xor eax,eax; jmp .gio_done4
.gio_yes4: mov eax,1
.gio_done4: pop r13; pop r12; ret

# ---------------- declared binding type helpers ----------------
g_iterate_result_type:
    push rbx; push r12; push r13
    mov rbx,rdi
    mov rdi,rbx; lea rsi,[rip+gk_states]; mov edx,gk_states_end-gk_states; call obj_get
    test rax,rax; jz .girt_bad
    cmp qword ptr [rax],J_ARRAY; jne .girt_bad
    mov r12,[rax+24]; test r12,r12; jz .girt_bad
    mov rdi,rbx; lea rsi,[rip+gk_result]; mov edx,gk_result_end-gk_result; call obj_get
    test rax,rax; jz .girt_bad
    mov r13,rax
.girt_loop:
    test r12,r12; jz .girt_bad
    mov rdi,r12; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .girt_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov rdx,[r13+8]; mov rcx,[r13+16]; call span_eq
    test eax,eax; jz .girt_next
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .girt_bad
    mov rdi,rax; call g_type_from_node; jmp .girt_done
.girt_next: mov r12,[r12+32]; jmp .girt_loop
.girt_bad: xor eax,eax
.girt_done: pop r13; pop r12; pop rbx; ret

g_lookup_value_type:
    push rbx
    mov rbx,rdi
    lea rsi,[rip+gk_dictionary]; mov edx,gk_dictionary_end-gk_dictionary; call obj_get
    test rax,rax; jz .glvt_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .glvt_bad
    cmp dword ptr [rax+16],GK_DICTIONARY; jne .glvt_bad
    mov rbx,[rax+32]
    mov rdi,rbx; lea rsi,[rip+gk_value_type]; mov edx,gk_value_type_end-gk_value_type; call obj_get
    test rax,rax; jz .glvt_bad
    mov rdi,rax; call g_type_from_node; pop rbx; ret
.glvt_bad: xor eax,eax; pop rbx; ret

g_nested_reduce_type:
    # count/segment_count are u64; sum uses accumulator or nested element type.
    push rbx
    mov rbx,rdi
    lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    test rax,rax; jz .gnrt_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_count]; mov ecx,gv_count_end-gv_count; call span_eq
    test eax,eax; jnz .gnrt_u64
    mov rdi,rbx; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_segment_count]; mov ecx,gv_segment_count_end-gv_segment_count; call span_eq
    test eax,eax; jnz .gnrt_u64
    mov rdi,rbx; lea rsi,[rip+gk_accumulator]; mov edx,gk_accumulator_end-gk_accumulator; call obj_get
    test rax,rax; jz .gnrt_from_input
    mov rdi,rax; call g_type_from_node; pop rbx; ret
.gnrt_from_input:
    mov rdi,rbx; lea rsi,[rip+gk_input]; mov edx,gk_input_end-gk_input; call obj_get
    test rax,rax; jz .gnrt_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gnrt_bad
    mov rbx,[rax+32]
    mov rdi,rbx; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gnrt_bad
    mov rdi,rax; call g_type_from_node; pop rbx; ret
.gnrt_u64: mov eax,GTYPE_U64; pop rbx; ret
.gnrt_bad: xor eax,eax; pop rbx; ret

# ---------------- state/field/dictionary lookup helpers ----------------
g_find_state:
    xor ecx,ecx
.gfst_loop:
    cmp ecx,dword ptr [rip+g_state_count]; jae .gfst_no
    mov eax,ecx; shl rax,5; mov r8,[rip+g_states_ptr]; add r8,rax
    cmp [r8+8],rsi; jne .gfst_next
    xor r9d,r9d
.gfst_cmp:
    cmp r9,rsi; jae .gfst_yes
    mov r10,[r8]; mov al,[r10+r9]; cmp al,[rdi+r9]; jne .gfst_next
    inc r9; jmp .gfst_cmp
.gfst_yes: mov rax,r8; ret
.gfst_next: inc ecx; jmp .gfst_loop
.gfst_no: xor eax,eax; ret


# field object -> rax=iterate symbol/0, edx=state declaration index, ecx=state type.
# Static records are deliberately not accepted here; they retain the old
# compile-time structural expansion authority.
g_iter_field_info:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    mov rdi,rbx; lea rsi,[rip+gk_record]; mov edx,gk_record_end-gk_record; call obj_get
    test rax,rax; jz .gifi_no
    cmp qword ptr [rax],J_STRING; jne .gifi_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gifi_no
    cmp dword ptr [rax+16],GK_ITERATE; jne .gifi_no
    mov r12,rax
    mov rdi,rbx; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .gifi_no
    cmp qword ptr [rax],J_STRING; jne .gifi_no
    mov r13,[rax+8]; mov r15,[rax+16]
    mov rdi,[r12+32]; lea rsi,[rip+gk_states]; mov edx,gk_states_end-gk_states; call obj_get
    test rax,rax; jz .gifi_no
    cmp qword ptr [rax],J_ARRAY; jne .gifi_no
    mov rbx,[rax+24]; xor r14d,r14d
.gifi_state_loop:
    test rbx,rbx; jz .gifi_no
    mov rdi,rbx; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .gifi_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov rdx,r13; mov rcx,r15; call span_eq
    test eax,eax; jnz .gifi_found
    inc r14d; mov rbx,[rbx+32]; jmp .gifi_state_loop
.gifi_found:
    mov rdi,rbx; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gifi_no
    mov rdi,rax; call g_type_from_node
    test eax,eax; jz .gifi_no
    mov r15d,eax
    mov rax,r12; mov edx,r14d; mov ecx,r15d
    jmp .gifi_done
.gifi_no:
    xor eax,eax; xor edx,edx; xor ecx,ecx
.gifi_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=iterate symbol -> eax=result state declaration index, or -1.
g_iter_result_state_index:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    mov rdi,[r12+32]; lea rsi,[rip+gk_result]; mov edx,gk_result_end-gk_result; call obj_get
    test rax,rax; jz .girsi_no
    cmp qword ptr [rax],J_STRING; jne .girsi_no
    mov r13,[rax+8]; mov r14,[rax+16]
    mov rdi,[r12+32]; lea rsi,[rip+gk_states]; mov edx,gk_states_end-gk_states; call obj_get
    test rax,rax; jz .girsi_no
    mov rbx,[rax+24]; xor r12d,r12d
.girsi_loop:
    test rbx,rbx; jz .girsi_no
    mov rdi,rbx; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .girsi_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov rdx,r13; mov rcx,r14; call span_eq
    test eax,eax; jnz .girsi_yes
    inc r12d; mov rbx,[rbx+32]; jmp .girsi_loop
.girsi_yes:
    mov eax,r12d; jmp .girsi_done
.girsi_no:
    mov eax,-1
.girsi_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=iterate symbol, esi=state index -> eax=projection index or -1.
g_iter_projection_find_key:
    xor ecx,ecx
.gipfk_loop:
    cmp ecx,dword ptr [rip+g_iter_projection_count]; jae .gipfk_no
    mov rax,[rip+g_iter_projection_symbol_ptr]
    cmp qword ptr [rax+rcx*8],rdi; jne .gipfk_next
    mov rax,[rip+g_iter_projection_state_index_ptr]
    cmp dword ptr [rax+rcx*4],esi; je .gipfk_yes
.gipfk_next:
    inc ecx; jmp .gipfk_loop
.gipfk_yes:
    mov eax,ecx; ret
.gipfk_no:
    mov eax,-1; ret

# rdi=canonical field object. Register one unique downstream iterate-StateFact
# projection. -> eax=0 success/no-op, 1 malformed iterate projection/resource.
g_iter_projection_ensure:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    call g_iter_field_info
    test rax,rax; jz .gipe_ok                 # static/non-iterate field
    mov r12,rax; mov r13d,edx; mov r14d,ecx
    mov rdi,r12; mov esi,r13d; call g_iter_projection_find_key
    cmp eax,-1; jne .gipe_ok
    mov r15d,dword ptr [rip+g_iter_projection_count]
    cmp r15d,dword ptr [rip+g_iter_projection_capacity]; jae .gipe_bad
    mov rax,[rip+g_iter_projection_symbol_ptr]; mov [rax+r15*8],r12
    mov rdi,rbx; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .gipe_bad
    mov rdx,[rip+g_iter_projection_name_ptr]; mov rcx,[rax+8]; mov [rdx+r15*8],rcx
    mov rdx,[rip+g_iter_projection_name_len]; mov rcx,[rax+16]; mov [rdx+r15*8],rcx
    mov rax,[rip+g_iter_projection_type_ptr]; mov [rax+r15*4],r14d
    mov rax,[rip+g_iter_projection_state_index_ptr]; mov [rax+r15*4],r13d
    mov rdi,r12; call g_iter_result_state_index
    cmp eax,r13d; jne .gipe_new_slot
    mov eax,dword ptr [r12+24]
    jmp .gipe_store_slot
.gipe_new_slot:
    mov eax,dword ptr [rip+g_binding_slot_count]
    cmp eax,-1; je .gipe_bad
    inc dword ptr [rip+g_binding_slot_count]
.gipe_store_slot:
    mov rdx,[rip+g_iter_projection_slot_ptr]; mov [rdx+r15*4],eax
    inc dword ptr [rip+g_iter_projection_count]
.gipe_ok:
    xor eax,eax; jmp .gipe_done
.gipe_bad:
    mov eax,1
.gipe_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=canonical field object -> eax=projection index+1, or 0.
g_iter_projection_lookup_field:
    push rbx; push r12
    mov rbx,rdi
    call g_iter_field_info
    test rax,rax; jz .giplf_no
    mov r12,rax
    mov rdi,r12; mov esi,edx; call g_iter_projection_find_key
    cmp eax,-1; je .giplf_no
    inc eax; jmp .giplf_done
.giplf_no:
    xor eax,eax
.giplf_done:
    pop r12; pop rbx; ret

# Recursive represented-DOM scan. Only real iterate field consumers allocate
# runtime publication slots; declaration/state cardinality alone cannot do so.
g_discover_iterate_projections_node:
    push rbx; push r12
    mov rbx,rdi
    test rbx,rbx; jz .gdipn_ok
    mov rax,[rbx]
    cmp rax,J_OBJECT; je .gdipn_obj
    cmp rax,J_ARRAY; je .gdipn_arr
    jmp .gdipn_ok
.gdipn_obj:
    mov rdi,rbx; lea rsi,[rip+gk_field]; mov edx,gk_field_end-gk_field; call obj_get
    test rax,rax; jz .gdipn_obj_recurse
    cmp qword ptr [rax],J_OBJECT; jne .gdipn_bad
    mov rdi,rax; call g_iter_projection_ensure
    test eax,eax; jnz .gdipn_bad
.gdipn_obj_recurse:
    mov r12,[rbx+24]
.gdipn_obj_loop:
    test r12,r12; jz .gdipn_ok
    mov rdi,r12; call g_discover_iterate_projections_node
    test eax,eax; jnz .gdipn_bad
    mov r12,[r12+32]; jmp .gdipn_obj_loop
.gdipn_arr:
    mov r12,[rbx+24]
.gdipn_arr_loop:
    test r12,r12; jz .gdipn_ok
    mov rdi,r12; call g_discover_iterate_projections_node
    test eax,eax; jnz .gdipn_bad
    mov r12,[r12+32]; jmp .gdipn_arr_loop
.gdipn_ok:
    xor eax,eax; jmp .gdipn_done
.gdipn_bad:
    mov eax,1
.gdipn_done:
    pop r12; pop rbx; ret

# field object -> underlying expression node
g_resolve_field_expr:
    push rbx; push r12
    mov rbx,rdi
    lea rsi,[rip+gk_record]; mov edx,gk_record_end-gk_record; call obj_get
    test rax,rax; jz .grfe_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .grfe_bad
    cmp dword ptr [rax+16],GK_RECORD; jne .grfe_bad
    mov r12,[rax+32]
    mov rdi,r12; lea rsi,[rip+gk_fields]; mov edx,gk_fields_end-gk_fields; call obj_get
    test rax,rax; jz .grfe_bad
    mov r12,rax
    mov rdi,rbx; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .grfe_bad
    mov rsi,[rax+8]; mov rdx,[rax+16]
    mov rdi,r12
    xchg rsi,rdi                    # wrong shape corrected below
    # obj_get(obj=r12,key=ptr,len)
    mov rdi,r12
    mov rsi,[rax+8]
    mov edx,dword ptr [rax+16]
    call obj_get
    jmp .grfe_done
.grfe_bad: xor eax,eax
.grfe_done: pop r12; pop rbx; ret

# dictionary_lookup object -> value type
g_dictlookup_value_type:
    push rbx
    mov rbx,rdi
    lea rsi,[rip+gk_dictionary]; mov edx,gk_dictionary_end-gk_dictionary; call obj_get
    test rax,rax; jz .gdlvt_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gdlvt_bad
    cmp dword ptr [rax+16],GK_DICTIONARY; jne .gdlvt_bad
    mov rbx,[rax+32]
    mov rdi,rbx; lea rsi,[rip+gk_value_type]; mov edx,gk_value_type_end-gk_value_type; call obj_get
    test rax,rax; jz .gdlvt_bad
    mov rdi,rax; call g_type_from_node; pop rbx; ret
.gdlvt_bad: xor eax,eax; pop rbx; ret

# A code-position consumer is an emission frontier just like an opaque byte
# primitive. Settle the current scalar window before publishing any label,
# patch target, cursor comparison, rollback point or measured byte extent.
# The window's internal cursor observations remain private to its encoder.
.macro G_EMIT_POSITION reg
    call g_phys_window_barrier
    mov \reg,[rip+g_emit_ptr]
.endm

# Loop entry is a physical emission boundary. The existing target cache-line
# geometry fixes its byte phase independently of carrier/encoding choices.
# Padding precedes the published backedge target, never the steady-state body.
.macro G_EMIT_LOOP_POSITION reg, failure
    call g_emit_loop_align
    test eax,eax; jnz \failure
    mov \reg,[rip+g_emit_ptr]
.endm

# ---------------- native code buffer primitives ----------------
# One entry-only layout primitive for General folds and transitions. The AOT
# payload preserves each source fragment's cache-line phase. Architectural
# multi-byte NOPs minimize cold fallthrough work; there is no runtime selector.
g_emit_loop_align:
    call g_phys_window_barrier
    mov rdi,[rip+g_emit_ptr]
    mov rax,rdi; sub rax,[rip+g_code_ptr]
    neg eax; and eax,PRC_CACHE_LINE_BYTES-1
    lea rcx,[rdi+rax]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov esi,eax; call g_phys_fill_nops
    mov [rip+g_emit_ptr],rdi
    xor eax,eax; ret

# rdi=proved byte span, esi=length -> rdi=end. Shared by direct emission and
# Region composition; callers own arena bounds. No flags/value is consumed.
g_phys_fill_nops:
    push rbx; push r12
    mov r12d,esi
.gpfn_next:
    test r12d,r12d; jz .gpfn_done
    mov ebx,9; cmp r12d,ebx; cmovb ebx,r12d
    lea rax,[rip+gc_nop_offsets]; movzx eax,byte ptr [rax+rbx]
    lea rsi,[rip+gc_nop_bytes]; add rsi,rax
    mov ecx,ebx; rep movsb
    sub r12d,ebx; jmp .gpfn_next
.gpfn_done: pop r12; pop rbx; ret
.pushsection .rodata
gc_nop_offsets: .byte 0,0,1,3,6,10,15,21,28,36
gc_nop_bytes:
    .byte 0x90
    .byte 0x66,0x90
    .byte 0x0f,0x1f,0x00
    .byte 0x0f,0x1f,0x40,0x00
    .byte 0x0f,0x1f,0x44,0x00,0x00
    .byte 0x66,0x0f,0x1f,0x44,0x00,0x00
    .byte 0x0f,0x1f,0x80,0x00,0x00,0x00,0x00
    .byte 0x0f,0x1f,0x84,0x00,0x00,0x00,0x00,0x00
    .byte 0x66,0x0f,0x1f,0x84,0x00,0x00,0x00,0x00,0x00
.popsection
g_emit_u8:
    call g_phys_window_barrier
    mov rax,[rip+g_emit_ptr]; cmp rax,[rip+g_emit_end]; jae .ge_fail
    mov [rax],dil; inc rax; mov [rip+g_emit_ptr],rax; xor eax,eax; ret
.ge_fail: mov dword ptr [rip+g_code_overflow],1; mov eax,1; ret
g_emit_u16:
    call g_phys_window_barrier
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+2]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],di; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_u24:
    call g_phys_window_barrier
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+3]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],di; shr edi,16; mov [rax+2],dil; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_u32:
    call g_phys_window_barrier
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],edi; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_u64:
    call g_phys_window_barrier
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+8]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],rdi; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_bytes:
    call g_phys_window_barrier
    mov rax,[rip+g_emit_ptr]; mov ecx,esi; lea rdx,[rax+rcx]; cmp rdx,[rip+g_emit_end]; ja .ge_fail
.geb_loop: test ecx,ecx; jz .geb_done; mov dl,[rdi]; mov [rax],dl; inc rdi; inc rax; dec ecx; jmp .geb_loop
.geb_done: mov [rip+g_emit_ptr],rax; xor eax,eax; ret

# absolute address helpers for generated ET_EXEC image
g_emit_push_imm64:
    push rdi; mov edi,0xB848; call g_emit_u16; pop rdi; call g_emit_u64; mov edi,0x50; jmp g_emit_u8
# 1.3.13 register-native expression primitive: materialize an immediate
# directly into the runtime value register without routing through the machine stack.
g_emit_mov_rax_imm64:
    mov rsi,rdi; xor edi,edi
    jmp g_emit_phys_gpr_literal
# edi=owned GPR, rsi=exact literal bits. Every literal uses the same encoder;
# no RAX staging carrier is born for a literal consumed in another register.
g_emit_phys_gpr_literal:
    push rbx; push r12
    mov ebx,edi; mov r12,rsi
    mov eax,ebx; shr eax,3; and eax,1; or eax,0x48
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgl_done
    mov eax,ebx; and eax,7; add eax,0xB8
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgl_done
    mov rdi,r12; call g_emit_u64
.gepgl_done: pop r12; pop rbx; ret
g_emit_load_rax_abs:
    cmp dword ptr [rip+g_fragment_emit_open],0
    je 901f
    inc dword ptr [rip+g_current_fragment_memory_ops]
901:
    # Tagged StateFact: mov rax,[r15+disp32].  R15 is reserved target-side as
    # the execution-local mutable-state frame authority.
    mov rax,rdi
    shr rax,48
    cmp eax,0xffff
    jne .gelra_absolute
    push rdi
    mov edi,0x878B49                 # bytes 49 8B 87
    call g_emit_u24
    pop rdi
    jmp g_emit_u32
.gelra_absolute:
    push rdi; mov edi,0xA148; call g_emit_u16; pop rdi; call g_emit_u64; ret
g_emit_store_rax_abs:
    cmp dword ptr [rip+g_fragment_emit_open],0
    je 902f
    inc dword ptr [rip+g_current_fragment_memory_ops]
902:
    # Tagged StateFact: mov [r15+disp32],rax.
    mov rax,rdi
    shr rax,48
    cmp eax,0xffff
    jne .gesra_absolute
    push rdi
    mov edi,0x878949                 # bytes 49 89 87
    call g_emit_u24
    pop rdi
    jmp g_emit_u32
.gesra_absolute:
    push rdi; mov edi,0xA348; call g_emit_u16; pop rdi; call g_emit_u64; ret

# Compile-time machine-sequence canonicalization.  This is a generic emitted-code
# peephole, not a recurrence/state-count route.  Any generated sequence with
# exactly the same register semantics may collapse to the ISA's native multi-
# result primitive.  Code size is kept fixed so surrounding branch addresses do
# not move. rdi=start, rsi=end.
g_phys_machine_canonicalize:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13,rsi
.gpmc_scan:
    lea rax,[r12+15]; cmp rax,r13; ja .gpmc_done
    # mov rsi,r9 ; mov rdi,r8 ; add rdi,r9 ; mov r8,rsi ; mov r9,rdi
    cmp word ptr [r12],0x894c; jne .gpmc_next
    cmp byte ptr [r12+2],0xce; jne .gpmc_next
    cmp word ptr [r12+3],0x894c; jne .gpmc_next
    cmp byte ptr [r12+5],0xc7; jne .gpmc_next
    cmp word ptr [r12+6],0x014c; jne .gpmc_next
    cmp byte ptr [r12+8],0xcf; jne .gpmc_next
    cmp word ptr [r12+9],0x8949; jne .gpmc_next
    cmp byte ptr [r12+11],0xf0; jne .gpmc_next
    cmp word ptr [r12+12],0x8949; jne .gpmc_next
    cmp byte ptr [r12+14],0xf9; jne .gpmc_next
    # xadd r9,r8, followed by one architectural multi-byte NOP filling the
    # removed bytes.  Semantics are identical to the five-instruction sequence.
    mov dword ptr [r12],0xc1c10f4d
    mov dword ptr [r12+4],0x0f2e6666
    mov dword ptr [r12+8],0x0000841f
    mov word ptr [r12+12],0x0000
    mov byte ptr [r12+14],0x00
    add r12,15
    jmp .gpmc_scan
.gpmc_next:
    inc r12; jmp .gpmc_scan
.gpmc_done:
    pop r13; pop r12; pop rbx; ret
g_emit_pop_rax: mov edi,0x58; jmp g_emit_u8
g_emit_mov_eax_imm:
    push rdi; mov edi,0xB8; call g_emit_u8; pop rdi; jmp g_emit_u32

# near branch helpers. Return rax = displacement field pointer.
g_emit_jz_patch:
    mov edi,0x840F; call g_emit_u16
    G_EMIT_POSITION rdx; xor edi,edi; call g_emit_u32; mov rax,rdx; ret
g_emit_jnz_patch:
    mov edi,0x850F; call g_emit_u16
    G_EMIT_POSITION rdx; xor edi,edi; call g_emit_u32; mov rax,rdx; ret
# edi=near-Jcc second opcode byte (80..8F). Return displacement pointer.
g_emit_jcc_patch_byte:
    push rbx
    mov ebx,edi
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gejpb_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gejpb_bad
    G_EMIT_POSITION rbx; xor edi,edi; call g_emit_u32; test eax,eax; jnz .gejpb_bad
    inc qword ptr [rip+g_phys_control_edge_serial]
    mov rax,rbx; pop rbx; ret
.gejpb_bad:
    xor eax,eax; pop rbx; ret
g_emit_jmp_patch:
    inc qword ptr [rip+g_phys_control_edge_serial]
    mov edi,0xE9; call g_emit_u8
    G_EMIT_POSITION rdx; xor edi,edi; call g_emit_u32; mov rax,rdx; ret
g_patch_rel32:
    # rdi=disp ptr, rsi=target
    mov rax,rsi; sub rax,rdi; sub rax,4; mov [rdi],eax; ret

# address calculators: eax slot -> rax VA
g_binding_slot_addr: mov eax,eax; shl rax,12; add rax,[rip+g_runtime_binding_base_va]; ret
# Mutable StateFact addresses are compiler-only tagged local offsets.  The
# generated instruction consumes them relative to R15, the current causal
# execution's private state-frame base.  current=16*i, next-version=16*i+8.
# No absolute shared state address survives into the target image.
g_state_slot_addr:
    mov eax,eax
    shl rax,4
    mov rdx,GSTATE_LOCAL_TAG
    or rax,rdx
    ret
g_state_temp_addr:
    mov eax,eax
    shl rax,4
    add rax,8
    mov rdx,GSTATE_LOCAL_TAG
    or rax,rdx
    ret
g_input_slot_addr: mov eax,eax; imul rax,rax,8; add rax,[rip+g_runtime_input_values_base_va]; ret
g_input_aux_addr: mov eax,eax; imul rax,rax,8; add rax,[rip+g_runtime_input_aux_base_va]; ret
g_output_slot_addr: mov eax,eax; shl rax,12; add rax,[rip+g_runtime_output_pages_base_va]; ret

# One compile-time allocator owns all exact runtime scratch below the Rank-N
# temporary base. Consumers derive byte demand from semantic structure; there is
# no runtime allocator, size tier, or subsystem-private temporary arena.
# rdi=requested bytes -> rax=64-byte-aligned private VA, 0 on overflow.
g_alloc_runtime_temp_bytes:
    mov rax,rdi
    add rax,63
    jc .gartb_bad
    and rax,-64
    mov rcx,[rip+g_runtime_temp_bytes_used]
    mov rdx,rcx
    add rdx,rax
    jc .gartb_bad
    mov [rip+g_runtime_temp_bytes_used],rdx
    mov rax,rcx
    add rax,[rip+g_runtime_rankn_temp_base_va]
    jc .gartb_bad
    ret
.gartb_bad:
    xor eax,eax
    ret

# One AOT physical-span authority for every fpP object.  The span is derived
# from PrecisionFact plus the already-authoritative Fourier geometry fact and
# is the exact maximum of the live add, multiply and compact-division layouts.
# No fixed bytes-per-limb envelope survives.
# edi=encoded fpP -> rax=64-byte aligned object span /0.
g_rankn_fp_object_span:
    mov eax,edi
    sub eax,GTYPE_RANKN_FP_BASE
    imul rax,rax,RPF_FACT_BYTES
    add rax,[rip+g_rankn_type_facts_ptr]
    mov rax,[rax+RPF_FACT_SPAN]
    ret

g_materialize_rankn_fp_layout:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,16
    mov ebx,edi
    call g_float_precision
    cmp rax,64
    jbe .grfos_bad
    mov r12,rax                              # P
    add rax,63
    jc .grfos_bad
    shr rax,6
    mov r13,rax                              # N
    mov eax,ebx
    sub eax,GTYPE_RANKN_FP_BASE
    imul rax,rax,RPF_FACT_BYTES
    add rax,[rip+g_rankn_type_facts_ptr]
    mov [rsp+8],rax                          # sole type-layout destination
    mov [rax+RPF_FACT_LIMBS],r13
    mov r14d,[rax+RPF_FACT_PACKED]
    test r14d,r14d; jz .grfos_bad

    # NFFT = 2^a2 * 3^a3 * 5^a5.
    mov ecx,r14d
    shr ecx,8
    and ecx,255
    cmp ecx,62
    ja .grfos_bad
    mov r15,1
    shl r15,cl
    mov edx,r14d
    shr edx,16
    and edx,255
.grfos_f3:
    test edx,edx
    jz .grfos_f5_start
    imul r15,r15,3
    jo .grfos_bad
    dec edx
    jmp .grfos_f3
.grfos_f5_start:
    mov edx,r14d
    shr edx,24
.grfos_f5:
    test edx,edx
    jz .grfos_have_fft
    imul r15,r15,5
    jo .grfos_bad
    dec edx
    jmp .grfos_f5
.grfos_have_fft:
    mov r8,[rsp+8]
    mov eax,r14d; and eax,255
    mov [r8+RPF_FACT_FOURIER],eax
    mov ecx,r14d; shr ecx,8; and ecx,255
    mov [r8+RPF_FACT_FOURIER+4],ecx
    mov ecx,r14d; shr ecx,16; and ecx,255
    mov [r8+RPF_FACT_FOURIER+8],ecx
    mov ecx,r14d; shr ecx,24
    mov [r8+RPF_FACT_FOURIER+12],ecx
    mov [r8+RPF_FACT_FOURIER+24],r15
    mov ecx,eax
    mov rax,r12; add rax,rcx; dec rax
    xor edx,edx; div rcx
    mov [r8+RPF_FACT_FOURIER+16],rax
    # primary_end = header + N payload limbs.
    mov rbx,r13
    shl rbx,3
    jc .grfos_bad
    add rbx,32
    jc .grfos_bad

    # Multiply scratch exactly mirrors rpf_fourier_mul_u64:
    # A=align64(primary_end), T=A+16F,
    # product=align64(T+8F+16), product limbs=(2N+4).
    mov rax,rbx
    add rax,63
    jc .grfos_bad
    and rax,-64
    mov rcx,r15
    shl rcx,4
    jc .grfos_bad
    add rax,rcx
    jc .grfos_bad
    add rax,63
    jc .grfos_bad
    and rax,-64
    mov rcx,r13
    shl rcx,4                              # 16N
    jc .grfos_bad
    add rcx,32                             # (2N+4)*8
    jc .grfos_bad
    add rax,rcx
    jc .grfos_bad
    mov [rsp],rax                          # max so far

    # Compact Knuth division scratch: U/Q use ucap u32 each, V uses nd+2 u32,
    # followed by an aligned u64 quotient carrier.  The quotient capacity is
    # derived from the same ucap fact, never a separate size tier.
    mov r8,r12
    add r8,31
    jc .grfos_bad
    shr r8,5                               # nd=ceil(P/32)
    mov r9,r12
    add r9,4
    jc .grfos_bad
    shr r9,5                               # qw=(P+4)>>5
    mov r10,r8
    add r10,r9
    jc .grfos_bad
    add r10,6                              # ucap
    jc .grfos_bad
    mov rax,rbx
    mov rcx,r10
    shl rcx,2
    jc .grfos_bad
    add rax,rcx                            # U
    jc .grfos_bad
    mov rcx,r8
    add rcx,2
    jc .grfos_bad
    shl rcx,2
    jc .grfos_bad
    add rax,rcx                            # V
    jc .grfos_bad
    mov rcx,r10
    shl rcx,2
    jc .grfos_bad
    add rax,rcx                            # Q
    jc .grfos_bad
    add rax,7
    jc .grfos_bad
    and rax,-8                             # Q64
    mov rcx,r10
    add rcx,1
    jc .grfos_bad
    shr rcx,1
    add rcx,1                              # ceil(ucap/2)+1 qwords
    jc .grfos_bad
    shl rcx,3
    jc .grfos_bad
    add rax,rcx
    jc .grfos_bad
    cmp rax,[rsp]
    jbe .grfos_add
    mov [rsp],rax
.grfos_add:
    # Add/sub owns exactly two (N+2)-limb local carriers.
    mov rax,r13
    add rax,2
    jc .grfos_bad
    shl rax,4
    jc .grfos_bad
    add rax,rbx
    jc .grfos_bad
    cmp rax,[rsp]
    jbe .grfos_align
    mov [rsp],rax
.grfos_align:
    mov rax,[rsp]
    add rax,63
    jc .grfos_bad
    and rax,-64
    mov r8,[rsp+8]
    mov [r8+RPF_FACT_SPAN],rax
    jmp .grfos_done
.grfos_bad:
    xor eax,eax
.grfos_done:
    add rsp,16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Parameterized Rank-N floating physical allocation.  Precision is data, not a
# precision is data, not a width branch. Each emitted >64-bit ValueFact owns exactly the span required
# by its precision limb axis plus generic arithmetic scratch.  The workspace is
# static/AOT-owned; there is no runtime allocator or scheduler.
g_alloc_rankn_fp_temp:
    # edi=encoded fpP -> rax=private object VA / 0
    call g_rankn_fp_object_span
    test rax,rax
    jz .garft_bad
    mov rdi,rax
    call g_alloc_runtime_temp_bytes
    test rax,rax
    jz .garft_bad
    ret
.garft_bad:
    xor eax,eax
    ret

# Native-math workspace consumes the source-derived live slot extent.
# P determines each carrier span; the capability determines their live count.
g_alloc_rankn_fp_math_temp:
    call g_rankn_fp_object_span
    test rax,rax
    jz .garfmt_bad
    imul rax,rsi                      # source-derived capability extent
    jo .garfmt_bad
    mov rdi,rax
    call g_alloc_runtime_temp_bytes
    test rax,rax
    jz .garfmt_bad
    ret
.garfmt_bad:
    xor eax,eax
    ret

# Compile-time native-Fourier geometry closure for P>64.
# edi=encoded fpP -> eax packed b|a2<<8|a3<<16|a5<<24, or 0.
# This is the AOT twin of the runtime ingress fallback.  It searches only one
# Fourier geometry family under one rounding inequality and one physical cost;
# it is not an algorithm selector and names no precision threshold.
g_rankn_fourier_ceil_log2:
    cmp rdi,1
    jbe .grfcl_zero
    dec rdi
    bsr rax,rdi
    inc eax
    ret
.grfcl_zero:
    xor eax,eax
    ret

g_rankn_fourier_geom_pack:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp,80
    call g_float_precision
    cmp rax,64
    jbe .grfgp_bad
    mov r12,rax
    mov qword ptr [rsp+0],-1          # best physical cost
    mov dword ptr [rsp+8],0           # best packed geometry
    mov ebx,26                        # binary64 exact coefficient ceiling
.grfgp_b_loop:
    cmp ebx,1
    jl .grfgp_done_search
    # n=ceil(P/b), need=2n-1
    mov rax,r12
    mov ecx,ebx
    add rax,rcx
    jc .grfgp_next_b
    dec rax
    xor edx,edx
    div rcx
    mov r14,rax
    mov [rsp+16],rax
    lea r15,[rax+rax-1]
    mov [rsp+24],r15
    # md2=(2^b-1)^2
    mov ecx,ebx
    mov rax,1
    shl rax,cl
    dec rax
    imul rax,rax
    mov [rsp+32],rax
    mov qword ptr [rsp+40],1          # 3^a3
    mov dword ptr [rsp+48],0
.grfgp_a3_loop:
    mov rax,[rsp+40]
    mov rcx,[rsp+24]
    shl rcx,1
    cmp rax,rcx
    ja .grfgp_next_b
    mov [rsp+56],rax                  # 3^a3 * 5^a5
    mov dword ptr [rsp+64],0
.grfgp_a5_loop:
    mov rbp,[rsp+56]
    mov rcx,[rsp+24]
    shl rcx,1
    cmp rbp,rcx
    ja .grfgp_a5_done
    # a2=ceil_log2(ceil(need/base))
    mov rax,[rsp+24]
    lea rax,[rax+rbp-1]
    xor edx,edx
    div rbp
    mov rdi,rax
    call g_rankn_fourier_ceil_log2
    mov r10d,eax
    cmp r10d,62
    ja .grfgp_candidate_next
    mov r11,rbp
    mov ecx,r10d
    shl r11,cl                       # N
    cmp r11,[rsp+24]
    jb .grfgp_candidate_next
    # Native SIMD safety: n*(2^b-1)^2*ceil_log2(N) < 2^51.
    mov rdi,r11
    call g_rankn_fourier_ceil_log2
    test eax,eax
    jz .grfgp_candidate_next
    mov r9d,eax
    mov rax,0x0007ffffffffffff
    xor edx,edx
    mov ecx,r9d
    div rcx
    mov r8,rax
    mov rax,[rsp+32]
    mul qword ptr [rsp+16]
    test rdx,rdx
    jnz .grfgp_candidate_next
    cmp rax,r8
    jae .grfgp_candidate_next
    # One cost vocabulary prices the stage DAG and coefficient traffic.
    # Independent quadratic radix penalties have no physical consumer.
    mov eax,r10d
    imul eax,eax,PRC_FOURIER_RADIX2_TICKS
    mov ecx,[rsp+48]
    imul ecx,ecx,PRC_FOURIER_RADIX3_TICKS
    add eax,ecx
    mov ecx,[rsp+64]
    imul ecx,ecx,PRC_FOURIER_RADIX5_TICKS
    add eax,ecx
    mov ecx,eax
    mov rax,r11
    imul rax,rcx
    mov rcx,[rsp+16]
    imul rcx,rcx,PRC_FOURIER_COEFFICIENT_TICKS
    add rax,rcx
    cmp rax,[rsp+0]
    jae .grfgp_candidate_next
    mov [rsp+0],rax
    mov edx,ebx
    mov ecx,r10d
    shl ecx,8
    or edx,ecx
    mov ecx,[rsp+48]
    shl ecx,16
    or edx,ecx
    mov ecx,[rsp+64]
    shl ecx,24
    or edx,ecx
    mov [rsp+8],edx
.grfgp_candidate_next:
    mov rax,[rsp+56]
    mov rcx,5
    mul rcx
    test rdx,rdx
    jnz .grfgp_a5_done
    mov [rsp+56],rax
    inc dword ptr [rsp+64]
    jmp .grfgp_a5_loop
.grfgp_a5_done:
    mov rax,[rsp+40]
    mov rcx,3
    mul rcx
    test rdx,rdx
    jnz .grfgp_next_b
    mov [rsp+40],rax
    inc dword ptr [rsp+48]
    jmp .grfgp_a3_loop
.grfgp_next_b:
    dec ebx
    jmp .grfgp_b_loop
.grfgp_done_search:
    mov eax,[rsp+8]
    jmp .grfgp_done
.grfgp_bad:
    xor eax,eax
.grfgp_done:
    add rsp,80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# Small native-emission helpers for the wide physical ABI.
g_emit_mov_rdi_imm64:
    push rdi; mov edi,0xBF48; call g_emit_u16; pop rdi; jmp g_emit_u64
g_emit_mov_esi_imm32:
    push rdi; mov edi,0xBE; call g_emit_u8; pop rdi; jmp g_emit_u32
g_emit_mov_edx_imm32:
    push rdi; mov edi,0xBA; call g_emit_u8; pop rdi; jmp g_emit_u32
g_emit_mov_ecx_imm32:
    push rdi; mov edi,0xB9; call g_emit_u8; pop rdi; jmp g_emit_u32
# ToleranceFact transport for Rank-N mathematical relations.  These registers
# carry only a proof bound; they do not select another arithmetic implementation.
g_emit_mov_r8d_imm32:
    push rdi; mov edi,0xB841; call g_emit_u16; pop rdi; jmp g_emit_u32
g_emit_mov_r9_imm64:
    push rdi; mov edi,0xB949; call g_emit_u16; pop rdi; jmp g_emit_u64
g_emit_clear_r8d:
    mov edi,0x3145; call g_emit_u16
    test eax,eax; jnz .gecr8_done
    mov edi,0xC0; call g_emit_u8
.gecr8_done: ret
g_emit_call_abs:
    call g_emit_mov_rax_imm64
    test eax,eax; jnz .geca_done
    mov edi,0xD0FF; call g_emit_u16
.geca_done: ret

# Emit a generated-runtime failure check while preserving the old program ABI.
# edi=0 tests EDX (conversion), edi=1 tests EAX (arithmetic status).
g_emit_rankn_fp_status_check:
    test edi,edi; jnz .gewsc_eax
    lea rdi,[rip+gc_wide_check_edx]; mov esi,gc_wide_check_edx_end-gc_wide_check_edx; jmp g_emit_bytes
.gewsc_eax:
    lea rdi,[rip+gc_wide_check_eax]; mov esi,gc_wide_check_eax_end-gc_wide_check_eax; jmp g_emit_bytes

# edi=source type, esi=destination type. Generated value is one qword: ordinary
# scalar bits for old types, or a pointer to a precision-derived Rank-N physical carrier.
# Precision policy is deliberately absent here: g_low_type already decided the
# real consumer-edge type before this physical conversion is requested.
g_emit_rankn_fp_cast_top:
    push rbx; push r12; push r13; push r14
    mov r12d,edi; mov r13d,esi
    cmp r12d,r13d; je .gerct_ok
    mov edi,r13d; call g_is_rankn_fp; test eax,eax; jnz .gerct_to_rankn
    mov edi,r12d; call g_is_rankn_fp; test eax,eax; jnz .gerct_from_rankn
    jmp .gerct_bad
.gerct_to_rankn:
    # f32 becomes exact f64 before the common wide lift.
    cmp r12d,GTYPE_F32; jne .gerct_alloc
    lea rdi,[rip+gc_cast_f32_f64]; mov esi,gc_cast_f32_f64_end-gc_cast_f32_f64; call g_emit_bytes
    test eax,eax; jnz .gerct_bad
    mov r12d,GTYPE_F64
.gerct_alloc:
    mov edi,r13d; call g_alloc_rankn_fp_temp; test rax,rax; jz .gerct_bad
    mov rbx,rax
    mov edi,0x5E; call g_emit_u8                  # pop rsi source payload/pointer
    mov rdi,rbx; call g_emit_mov_rdi_imm64
    mov edi,r13d; call g_emit_mov_edx_imm32
    cmp r12d,GTYPE_U64; je .gerct_u
    cmp r12d,GTYPE_I64; je .gerct_i
    cmp r12d,GTYPE_F64; je .gerct_d
    mov edi,r12d; call g_is_rankn_fp; test eax,eax; jnz .gerct_wide
    jmp .gerct_bad
.gerct_u: mov rdi,GENERAL_RANKN_FP_FROM_U64_VA; jmp .gerct_call
.gerct_i: mov rdi,GENERAL_RANKN_FP_FROM_I64_VA; jmp .gerct_call
.gerct_d: mov rdi,GENERAL_RANKN_FP_FROM_F64_VA; jmp .gerct_call
.gerct_wide: mov rdi,GENERAL_RANKN_FP_CONVERT_VA
.gerct_call:
    call g_emit_call_abs; test eax,eax; jnz .gerct_bad
    xor edi,edi; call g_emit_rankn_fp_status_check; test eax,eax; jnz .gerct_bad
    mov edi,0x50; call g_emit_u8
    test eax,eax; jnz .gerct_bad
    jmp .gerct_ok
.gerct_from_rankn:
    cmp r13d,GTYPE_F64; je .gerct_f64
    cmp r13d,GTYPE_F32; je .gerct_f32
    jmp .gerct_bad
.gerct_f64:
    mov r14,GENERAL_RANKN_FP_TO_F64_VA
    jmp .gerct_native
.gerct_f32:
    mov r14,GENERAL_RANKN_FP_TO_F32_VA
.gerct_native:
    mov edi,0x5F; call g_emit_u8
    mov rdi,r14; call g_emit_call_abs
    test eax,eax; jnz .gerct_bad
    mov edi,0x50; call g_emit_u8
    jmp .gerct_ok
.gerct_ok: xor eax,eax; jmp .gerct_done
.gerct_bad: mov eax,1
.gerct_done: pop r14; pop r13; pop r12; pop rbx; ret

# Convert the second runtime stack operand while preserving the current top in
# R11. All wide runtime helpers preserve R11 by ABI.
g_emit_rankn_fp_cast_second:
    push r12; push r13
    mov r12d,edi; mov r13d,esi
    mov edi,0x5B41; call g_emit_u16               # pop r11
    test eax,eax; jnz .gewcs_bad
    mov edi,r12d; mov esi,r13d; call g_emit_rankn_fp_cast_top
    test eax,eax; jnz .gewcs_bad
    mov edi,0x5341; call g_emit_u16               # push r11
    test eax,eax; jnz .gewcs_bad
    xor eax,eax; jmp .gewcs_done
.gewcs_bad: mov eax,1
.gewcs_done: pop r13; pop r12; ret

# rdi=operator span, rsi=len, edx=wide result type. Operands already converted.
g_emit_rankn_fp_binary_op:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    mov edi,r14d; call g_alloc_rankn_fp_temp; test rax,rax; jz .gewbo_bad
    mov rbx,rax
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jnz .gewbo_add
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jnz .gewbo_sub
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jnz .gewbo_mul
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jnz .gewbo_div
    jmp .gewbo_bad
.gewbo_add: mov r12,GENERAL_RANKN_FP_ADD_VA; jmp .gewbo_emit
.gewbo_sub: mov r12,GENERAL_RANKN_FP_SUB_VA; jmp .gewbo_emit
.gewbo_mul:
    mov edi,r14d; call g_require_rankn_twiddles
    mov r12,GENERAL_RANKN_FP_MUL_VA
    jmp .gewbo_emit
.gewbo_div: mov r12,GENERAL_RANKN_FP_DIV_VA
.gewbo_emit:
    mov edi,0x5A; call g_emit_u8                   # pop rdx = rhs pointer
    mov edi,0x5E; call g_emit_u8                   # pop rsi = lhs pointer
    mov rdi,rbx; call g_emit_mov_rdi_imm64
    mov edi,r14d; call g_emit_mov_ecx_imm32
    mov rdi,r12; call g_emit_call_abs
    test eax,eax; jnz .gewbo_bad
    mov edi,1; call g_emit_rankn_fp_status_check
    test eax,eax; jnz .gewbo_bad
    mov rdi,rbx; call g_emit_push_imm64            # wide helpers return status in eax
    test eax,eax; jnz .gewbo_bad
    xor eax,eax; jmp .gewbo_done
.gewbo_bad: mov eax,1
.gewbo_done: pop r14; pop r13; pop r12; pop rbx; ret

# edi=wide type, esi=0 neg / 1 abs.
g_emit_rankn_fp_unary_top:
    push rbx; push r12
    mov r12d,esi
    # incoming edi is the encoded result type
    call g_alloc_rankn_fp_temp; test rax,rax; jz .gewut_bad
    mov rbx,rax
    mov edi,0x5E; call g_emit_u8                   # pop rsi
    mov rdi,rbx; call g_emit_mov_rdi_imm64
    test r12d,r12d; jnz .gewut_abs
    mov rdi,GENERAL_RANKN_FP_NEG_VA; jmp .gewut_call
.gewut_abs: mov rdi,GENERAL_RANKN_FP_ABS_VA
.gewut_call:
    call g_emit_call_abs; test eax,eax; jnz .gewut_bad
    mov edi,0x50; call g_emit_u8                   # helper returns dst pointer
    test eax,eax; jnz .gewut_bad
    xor eax,eax; jmp .gewut_done
.gewut_bad: mov eax,1
.gewut_done: pop r12; pop rbx; ret

# edi=wide type, rsi=runtime transcendental authority VA.  Incoming generated
# stack top is one fpP pointer; result is the slot-0 pointer of one source-derived
# math workspace.  No named precision or algorithm selector exists here.
g_emit_rankn_fp_math_unary_top:
    push rbx; push r12; push r13
    mov r13d,edi; mov r12,rsi
    call g_require_rankn_twiddles
    lea rax,[rip+g_rankn_math_layout_facts]
.gerfmu_layout:
    cmp [rax],r12; je .gerfmu_layout_found
    add rax,16; jmp .gerfmu_layout
.gerfmu_layout_found:
    mov rsi,[rax+8]
    mov edi,r13d; call g_alloc_rankn_fp_math_temp; test rax,rax; jz .gerfmu_bad
    mov rbx,rax
    mov edi,0x5E; call g_emit_u8                   # pop rsi = source pointer
    test eax,eax; jnz .gerfmu_bad
    mov rdi,rbx; call g_emit_mov_rdi_imm64
    mov edi,r13d; call g_emit_mov_edx_imm32
    cmp dword ptr [rip+g_fp_tolerance_active],0; je .gerfmu_strict_fact
    mov edi,1; call g_emit_mov_r8d_imm32
    mov rdi,qword ptr [rip+g_fp_tolerance_exp2]; call g_emit_mov_r9_imm64
    jmp .gerfmu_tol_ready
.gerfmu_strict_fact:
    call g_emit_clear_r8d
.gerfmu_tol_ready:
    mov rdi,r12; call g_emit_call_abs
    test eax,eax; jnz .gerfmu_bad
    mov edi,1; call g_emit_rankn_fp_status_check
    test eax,eax; jnz .gerfmu_bad
    mov rdi,rbx; call g_emit_push_imm64
    test eax,eax; jnz .gerfmu_bad
    xor eax,eax; jmp .gerfmu_done
.gerfmu_bad: mov eax,1
.gerfmu_done: pop r13; pop r12; pop rbx; ret

# rdi=pure expression -> rax u64 value, edx=0 folded / 1 not foldable.
# Conservative: wrap-u64 literals and pure binary operators only.
g_try_fold_u64_const:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gtf_no
    mov rdi,rbx; call g_expr_u64_literal; test edx,edx; jz .gtf_done
    cmp qword ptr [rbx],J_OBJECT; jne .gtf_no
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gtf_no
    mov r14,[rax+8]; mov r15,[rax+16]
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gtf_no
    cmp qword ptr [rax],J_ARRAY; jne .gtf_no
    mov rbx,[rax+24]; test rbx,rbx; jz .gtf_no
    mov rax,[rbx+32]; test rax,rax; jz .gtf_no
    cmp qword ptr [rax+32],0; jne .gtf_no
    mov r13,rax
    mov rdi,rbx; call g_try_fold_u64_const; test edx,edx; jnz .gtf_no
    mov r12,rax
    mov rdi,r13; call g_try_fold_u64_const; test edx,edx; jnz .gtf_no
    mov r13,rax
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gtf_add
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gtf_sub
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gtf_mul
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_bit_and]; mov ecx,gv_bit_and_end-gv_bit_and; call span_eq; test eax,eax; jnz .gtf_and
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gtf_or
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gtf_xor
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq; test eax,eax; jnz .gtf_shl
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq; test eax,eax; jnz .gtf_shr
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq; test eax,eax; jnz .gtf_min
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq; test eax,eax; jnz .gtf_max
    jmp .gtf_no
.gtf_add: mov rax,r12; add rax,r13; jmp .gtf_ok
.gtf_sub: mov rax,r12; sub rax,r13; jmp .gtf_ok
.gtf_mul: mov rax,r12; imul rax,r13; jmp .gtf_ok
.gtf_and: mov rax,r12; and rax,r13; jmp .gtf_ok
.gtf_or:  mov rax,r12; or rax,r13; jmp .gtf_ok
.gtf_xor: mov rax,r12; xor rax,r13; jmp .gtf_ok
.gtf_shl:
    cmp r13,64; jae .gtf_no
    mov rax,r12; mov rcx,r13; shl rax,cl; jmp .gtf_ok
.gtf_shr:
    cmp r13,64; jae .gtf_no
    mov rax,r12; mov rcx,r13; shr rax,cl; jmp .gtf_ok
.gtf_min: mov rax,r12; cmp rax,r13; cmova rax,r13; jmp .gtf_ok
.gtf_max: mov rax,r12; cmp rax,r13; cmovb rax,r13; jmp .gtf_ok
.gtf_ok: xor edx,edx; jmp .gtf_done
.gtf_no: xor eax,eax; mov edx,1
.gtf_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expression -> eax bool value, edx=0 success / 1 no-match.
g_expr_bool_literal:
    push rbx
    mov rbx,rdi
    cmp qword ptr [rbx],J_OBJECT; jne .gebl_bad
    mov rdi,rbx; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gebl_bad
    mov rdi,rax; call g_type_from_node; cmp eax,GTYPE_BOOL; jne .gebl_bad
    mov rdi,rbx; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gebl_bad
    cmp qword ptr [rax],J_TRUE; je .gebl_true
    cmp qword ptr [rax],J_FALSE; jne .gebl_bad
    xor eax,eax; xor edx,edx; pop rbx; ret
.gebl_true: mov eax,1; xor edx,edx; pop rbx; ret
.gebl_bad: xor eax,eax; mov edx,1; pop rbx; ret

# emit mov rcx,imm64 (rdi=value)
g_emit_mov_rcx_imm64:
    push rdi; mov edi,0xB948; call g_emit_u16; pop rdi; jmp g_emit_u64

# Add one compile-time-known wrap-u64 contribution to an exact runtime cell.
# rdi=absolute qword address, rsi=contribution. Zero contributions erase.
g_emit_add_imm64_abs:
    test rsi,rsi
    jnz .geai_do
    xor eax,eax
    ret
.geai_do:
    push rbx
    mov rbx,rdi
    call g_emit_load_rax_abs
    test eax,eax; jnz .geai_bad
    mov rdi,rsi
    call g_emit_mov_rcx_imm64
    test eax,eax; jnz .geai_bad
    lea rdi,[rip+gc_const_add]; mov esi,gc_const_add_end-gc_const_add; call g_emit_bytes
    test eax,eax; jnz .geai_bad
    mov rdi,rbx
    call g_emit_store_rax_abs
    test eax,eax; jnz .geai_bad
.geai_ok:
    xor eax,eax
    pop rbx
    ret
.geai_bad:
    mov eax,1
    pop rbx
    ret

# emit top-stack u64 shifted by constant. edi=count, esi=0 shl / 1 shr.
g_emit_u64_shift_imm:
    push rbx
    mov ebx,esi
    push rdi
    call g_emit_pop_rax
    mov edi,0xC148; call g_emit_u16
    pop rdi
    test ebx,ebx; jnz .geusi_shr
    mov esi,0xE0; jmp .geusi_modrm
.geusi_shr: mov esi,0xE8
.geusi_modrm:
    push rdi
    mov edi,esi; call g_emit_u8
    pop rdi
    call g_emit_u8
    mov edi,0x50; call g_emit_u8
    xor eax,eax; pop rbx; ret

# rdi=whole binary expression -> eax=GTYPE_U64 if emitted, 0 no optimization.
# Requires exactly one u64 literal operand. Conservative, wrap-u64 only.
g_try_emit_u64_const_binary:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    G_EMIT_POSITION rax; mov [rip+g_scalar_opt_emit_start],rax
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gteuc_no
    mov r14,[rax+8]; mov r15,[rax+16]
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gteuc_no
    cmp qword ptr [rax],J_ARRAY; jne .gteuc_no
    mov r12,[rax+24]; test r12,r12; jz .gteuc_no
    mov r13,[r12+32]; test r13,r13; jz .gteuc_no
    cmp qword ptr [r13+32],0; jne .gteuc_no
    mov dword ptr [rip+g_scalar_const_left],0
    mov rdi,r13; call g_expr_u64_literal; test edx,edx; jz .gteuc_const_ready
    mov rdi,r12; call g_expr_u64_literal; test edx,edx; jnz .gteuc_no
    mov dword ptr [rip+g_scalar_const_left],1
    xchg r12,r13
.gteuc_const_ready:
    mov [rip+g_scalar_const_value],rax
    mov rdi,r12; call g_expr_u64_literal; test edx,edx; jz .gteuc_no
    mov dword ptr [rip+g_scalar_opt_kind],0
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gteuc_k_add
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gteuc_k_sub
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gteuc_k_mul
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jnz .gteuc_k_div
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq; test eax,eax; jnz .gteuc_k_mod
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_bit_and]; mov ecx,gv_bit_and_end-gv_bit_and; call span_eq; test eax,eax; jnz .gteuc_k_and
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gteuc_k_or
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gteuc_k_xor
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq; test eax,eax; jnz .gteuc_k_shl
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq; test eax,eax; jnz .gteuc_k_shr
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq; test eax,eax; jnz .gteuc_k_min
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq; test eax,eax; jnz .gteuc_k_max
    jmp .gteuc_no
.gteuc_k_add: mov dword ptr [rip+g_scalar_opt_kind],1; jmp .gteuc_emit
.gteuc_k_sub:
    cmp dword ptr [rip+g_scalar_const_left],0; jne .gteuc_no
    mov dword ptr [rip+g_scalar_opt_kind],2; jmp .gteuc_emit
.gteuc_k_mul: mov dword ptr [rip+g_scalar_opt_kind],3; jmp .gteuc_emit
.gteuc_k_div:
    cmp dword ptr [rip+g_scalar_const_left],0; jne .gteuc_no
    cmp qword ptr [rip+g_scalar_const_value],0; je .gteuc_no
    mov dword ptr [rip+g_scalar_opt_kind],4; jmp .gteuc_emit
.gteuc_k_mod:
    cmp dword ptr [rip+g_scalar_const_left],0; jne .gteuc_no
    cmp qword ptr [rip+g_scalar_const_value],0; je .gteuc_no
    mov dword ptr [rip+g_scalar_opt_kind],5; jmp .gteuc_emit
.gteuc_k_and: mov dword ptr [rip+g_scalar_opt_kind],6; jmp .gteuc_emit
.gteuc_k_or: mov dword ptr [rip+g_scalar_opt_kind],7; jmp .gteuc_emit
.gteuc_k_xor: mov dword ptr [rip+g_scalar_opt_kind],8; jmp .gteuc_emit
.gteuc_k_shl:
    cmp dword ptr [rip+g_scalar_const_left],0; jne .gteuc_no
    cmp qword ptr [rip+g_scalar_const_value],64; jae .gteuc_no
    mov dword ptr [rip+g_scalar_opt_kind],9; jmp .gteuc_emit
.gteuc_k_shr:
    cmp dword ptr [rip+g_scalar_const_left],0; jne .gteuc_no
    cmp qword ptr [rip+g_scalar_const_value],64; jae .gteuc_no
    mov dword ptr [rip+g_scalar_opt_kind],10; jmp .gteuc_emit
.gteuc_k_min: mov dword ptr [rip+g_scalar_opt_kind],11; jmp .gteuc_emit
.gteuc_k_max: mov dword ptr [rip+g_scalar_opt_kind],12
.gteuc_emit:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gteuc_semantics_ready
    mov eax,dword ptr [rip+g_scalar_opt_kind]
    cmp eax,3; jbe .gteuc_no                 # add/sub/mul need original trap guards
.gteuc_semantics_ready:
    # preserve this recursion frame's constant/operator across nested emitter
    mov r13,[rip+g_scalar_const_value]
    mov r15d,dword ptr [rip+g_scalar_opt_kind]
    mov rdi,r12; call g_emit_expr; cmp eax,GTYPE_U64; jne .gteuc_rollback
    mov eax,r15d
    cmp eax,1; je .gteuc_add
    cmp eax,2; je .gteuc_sub
    cmp eax,3; je .gteuc_mul
    cmp eax,4; je .gteuc_div
    cmp eax,5; je .gteuc_mod
    cmp eax,6; je .gteuc_and
    cmp eax,7; je .gteuc_or
    cmp eax,8; je .gteuc_xor
    cmp eax,9; je .gteuc_shl
    cmp eax,10; je .gteuc_shr
    cmp eax,11; je .gteuc_min
    cmp eax,12; je .gteuc_max
    jmp .gteuc_rollback
.gteuc_identity: mov eax,GTYPE_U64; jmp .gteuc_done
.gteuc_add:
    test r13,r13; jz .gteuc_identity
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_add]; mov esi,gc_const_add_end-gc_const_add; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_sub:
    test r13,r13; jz .gteuc_identity
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_sub]; mov esi,gc_const_sub_end-gc_const_sub; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_mul:
    cmp r13,1; je .gteuc_identity
    test r13,r13; jz .gteuc_mul_general
    mov rax,r13; lea rcx,[rax-1]; test rax,rcx; jnz .gteuc_mul_general
    bsf rcx,r13; mov edi,ecx; xor esi,esi; call g_emit_u64_shift_imm; jmp .gteuc_type_done
.gteuc_mul_general:
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_mul]; mov esi,gc_const_mul_end-gc_const_mul; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_div:
.gteuc_mod:
    # The stack owns RAX already. The common emitter preserves only actual
    # implicit MUL conflicts; an in-place AND/SHR never borrows R10.
    call g_emit_pop_rax
    push qword ptr [rip+g_phys_int_reserved_mask]
    or dword ptr [rip+g_phys_int_reserved_mask],(1<<11)
    call g_phys_int_temp_reset
.gteuc_mod_reciprocal:
    mov ecx,r15d; sub ecx,4; xor ecx,1
    xor edi,edi; mov rsi,r13; call g_emit_phys_u64_const_divmod
    pop qword ptr [rip+g_phys_int_reserved_mask]
    test eax,eax; jnz .gteuc_rollback
    jmp .gteuc_push_done
.gteuc_and:
    cmp r13,-1; je .gteuc_identity
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_and]; mov esi,gc_const_and_end-gc_const_and; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_or:
    test r13,r13; jz .gteuc_identity
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_or]; mov esi,gc_const_or_end-gc_const_or; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_xor:
    test r13,r13; jz .gteuc_identity
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_xor]; mov esi,gc_const_xor_end-gc_const_xor; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_shl:
    test r13,r13; jz .gteuc_identity
    mov edi,r13d; xor esi,esi; call g_emit_u64_shift_imm; jmp .gteuc_type_done
.gteuc_shr:
    test r13,r13; jz .gteuc_identity
    mov edi,r13d; mov esi,1; call g_emit_u64_shift_imm; jmp .gteuc_type_done
.gteuc_min:
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_umin]; mov esi,gc_const_umin_end-gc_const_umin; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_max:
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_umax]; mov esi,gc_const_umax_end-gc_const_umax; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_push_done: mov edi,0x50; call g_emit_u8
.gteuc_type_done: mov eax,GTYPE_U64; jmp .gteuc_done
.gteuc_rollback: mov rax,[rip+g_scalar_opt_emit_start]; mov [rip+g_emit_ptr],rax
.gteuc_no: xor eax,eax
.gteuc_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- Predicate ValueFact persistence ----------------
# Boolean facts are ordinary immutable ValueFacts. Exact predicate structure may
# reuse an already-materialized compute binding until one of its inputs changes;
# top-level compute bindings are immutable for the invocation, so their fact is
# valid for every later consumer. No predicate-name, repetition threshold, or
# workload route exists here.

# rdi=a, rsi=b -> eax=1 iff exact predicate structure is equal.
# Numeric children reuse the existing exact ValueFact structural equality.
g_phys_predicate_equal:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi
    cmp r12,r13; je .gppe_yes
    test r12,r12; jz .gppe_no
    test r13,r13; jz .gppe_no
    mov rdi,r12; mov rsi,r13; call g_phys_expr_equal
    test eax,eax; jnz .gppe_yes
    cmp qword ptr [r12],J_OBJECT; jne .gppe_no
    cmp qword ptr [r13],J_OBJECT; jne .gppe_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gppe_no
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gppe_no
    mov r15,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[r15+8]; mov ecx,dword ptr [r15+16]; call span_eq
    test eax,eax; jz .gppe_no
    # Only predicate-producing operators participate. This is type semantics,
    # not a source-shape fast path.
    mov rdi,[r14+8]; mov rsi,[r14+16]; call g_is_compare_op
    test eax,eax; jnz .gppe_binary
    mov rdi,[r14+8]; mov rsi,[r14+16]; call g_is_bool_binary
    test eax,eax; jnz .gppe_binary
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq
    test eax,eax; jz .gppe_no
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gppe_no
    mov r14,[rax+24]; test r14,r14; jz .gppe_no
    cmp qword ptr [r14+32],0; jne .gppe_no
    mov rdi,r13; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gppe_no
    mov r15,[rax+24]; test r15,r15; jz .gppe_no
    cmp qword ptr [r15+32],0; jne .gppe_no
    mov rdi,r14; mov rsi,r15; call g_phys_predicate_equal
    jmp .gppe_done
.gppe_binary:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gppe_no
    mov r14,[rax+24]; test r14,r14; jz .gppe_no
    mov rbx,[r14+32]; test rbx,rbx; jz .gppe_no
    cmp qword ptr [rbx+32],0; jne .gppe_no
    mov rdi,r13; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gppe_no
    mov r15,[rax+24]; test r15,r15; jz .gppe_no
    mov r13,[r15+32]; test r13,r13; jz .gppe_no
    cmp qword ptr [r13+32],0; jne .gppe_no
    mov rdi,r14; mov rsi,r15; call g_phys_predicate_equal
    test eax,eax; jz .gppe_no
    mov rdi,rbx; mov rsi,r13; call g_phys_predicate_equal
    jmp .gppe_done
.gppe_yes:
    mov eax,1; jmp .gppe_done
.gppe_no:
    xor eax,eax
.gppe_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=predicate expr -> rax=already materialized bool compute symbol or 0.
# Existing symbol/fragments are the authority; no predicate cache table exists.
g_find_materialized_predicate_fact:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    mov rdi,r12; call g_infer_expr
    cmp eax,GTYPE_BOOL; jne .gfmpf_no
    xor ebx,ebx
.gfmpf_loop:
    cmp ebx,dword ptr [rip+g_symbol_count]; jae .gfmpf_no
    mov eax,ebx; shl rax,6; mov r13,[rip+g_symbols_ptr]; add r13,rax
    cmp dword ptr [r13+16],GK_COMPUTE; jne .gfmpf_next
    cmp dword ptr [r13+20],GTYPE_BOOL; jne .gfmpf_next
    cmp dword ptr [r13+24],0; jl .gfmpf_next
    mov rdi,r13; call g_fragment_for_symbol
    test edx,edx; jnz .gfmpf_next
    mov r14,[r13+32]
    mov rdi,r14; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gfmpf_next
    mov rdi,r12; mov rsi,rax; call g_phys_predicate_equal
    test eax,eax; jnz .gfmpf_yes
.gfmpf_next:
    inc ebx; jmp .gfmpf_loop
.gfmpf_yes:
    mov rax,r13; jmp .gfmpf_done
.gfmpf_no:
    xor eax,eax
.gfmpf_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# edi=source fragment, esi=current destination fragment. Adds a true physical
# dependency when code reuses a materialized ValueFact not named in source AST.
g_note_fragment_dependency:
    cmp edi,esi; je .gnfd_done
    call g_edge_add_unique
    test eax,eax; jnz .gnfd_bad
    # Physical reuse can originate below the source reference surface. Its
    # payload identity is not reconstructed here; mark transfer unknown rather
    # than pretending the cross-domain cost is zero.
    mov rdx,[rip+g_edge_transfer_ptr]
    mov qword ptr [rdx+rcx*8],-1
    jmp .gnfd_done
.gnfd_bad:
    mov dword ptr [rip+g_parallel_error],1
.gnfd_done:
    ret

# RangeFact: unsigned remainder by 0<d<=2^63 lies in [0,INT64_MAX].
# This fact changes only the conversion primitive, never signedness, overflow,
# division order or result bits. All other ranges keep the full u64 converter.
g_u64_expr_fits_signed:
    push rbx; push r12; push r13
    mov r12,rdi
    mov rdi,r12; call g_expr_u64_literal
    test edx,edx; jnz .guefs_mod
    test rax,rax; js .guefs_no
    jmp .guefs_yes
.guefs_mod:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .guefs_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq
    test eax,eax; jz .guefs_no
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .guefs_no
    mov rax,[rax+24]; test rax,rax; jz .guefs_no
    mov rdi,[rax+32]; test rdi,rdi; jz .guefs_no
    call g_expr_u64_literal
    test edx,edx; jnz .guefs_no
    test rax,rax; jz .guefs_no
    mov rcx,0x8000000000000000
    cmp rax,rcx; ja .guefs_no
.guefs_yes: mov eax,1; jmp .guefs_done
.guefs_no: xor eax,eax
.guefs_done: pop r13; pop r12; pop rbx; ret

# RAX numeric payload -> RAX floating bits; use the inner value recipe shared
# with the stack ABI. No operand-stack materialization belongs to this carrier.
# edi=source U64/I64, esi=F32/F64.
# edi=source integer type, esi=target FP type, edx=caller-owned XMM.
# RAX carries the integer. Conversion consumes that exact dependency edge;
# no fixed XMM scratch may overwrite another live ValueFact.
g_emit_phys_int_fp_value:
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp ebx,GTYPE_I64; je .gepifv_signed
    cmp ebx,GTYPE_U64; jne .gepifv_bad
    lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    mov edi,0x89; call g_emit_jcc_patch_byte; mov r14,rax
    lea rdi,[rip+gc_unsigned_fp_split]; mov esi,gc_unsigned_fp_split_end-gc_unsigned_fp_split; call g_emit_bytes
    mov edi,r13d; mov esi,r12d; call g_emit_phys_cvt_rax_fp
    test eax,eax; jnz .gepifv_bad
    mov edi,0x58; mov esi,r13d; mov edx,r13d; mov ecx,r13d; mov r8d,r12d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gepifv_bad
    call g_emit_jmp_patch; mov rbx,rax
    mov rdi,r14; G_EMIT_POSITION rsi; call g_patch_rel32
    mov edi,r13d; mov esi,r12d; call g_emit_phys_cvt_rax_fp
    test eax,eax; jnz .gepifv_bad
    mov rdi,rbx; G_EMIT_POSITION rsi; call g_patch_rel32
    xor eax,eax; jmp .gepifv_done
.gepifv_signed:
    mov edi,r13d; mov esi,r12d; call g_emit_phys_cvt_rax_fp
    jmp .gepifv_done
.gepifv_bad: mov eax,1
.gepifv_done: pop r14; pop r13; pop r12; pop rbx; ret

# edi=destination XMM, esi=FP type. Signed integer operand is always RAX/64.
# Only the ISA register geometry differs; one conversion/rounding relation.
g_emit_phys_cvt_rax_fp:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp ebx,31; ja .gepcaf_bad
    cmp r12d,GTYPE_F64; je .gepcaf_type_ok
    cmp r12d,GTYPE_F32; jne .gepcaf_bad
.gepcaf_type_ok:
    # A scalar conversion owns its low value only. A zero idiom closes the
    # unowned merge bits and removes every previous-iteration carrier edge.
    mov edi,0x157; cmp ebx,15; jbe 1f
    test dword ptr [rip+isa_cap_bits],ISA_CAP_WIDE_REGFILE; jz .gepcaf_bad
    or edi,0x8000
1:  mov esi,ebx; mov edx,ebx; mov ecx,ebx
    call physical_encode_rrr
    test edx,edx; jz .gepcaf_bad
    sub rsp,8; mov [rsp],rax; mov rdi,rsp; mov esi,edx; call g_emit_bytes; add rsp,8
    mov edi,0x192a; cmp r12d,GTYPE_F64; jne 2f
    mov edi,0x1d2a
2:  cmp ebx,15; jbe 3f
    or edi,0x8000
3:  mov esi,ebx; mov edx,ebx; xor ecx,ecx
    call physical_encode_rrr
    test edx,edx; jz .gepcaf_bad
    sub rsp,8; mov [rsp],rax; mov rdi,rsp; mov esi,edx; call g_emit_bytes; add rsp,8
    xor eax,eax; jmp .gepcaf_done
.gepcaf_bad: mov eax,1
.gepcaf_done: pop r12; pop rbx; ret

# edi=GPR destination, esi=local XMM source, edx=natural FP width.
# CVTT consumes the existing native value without precision promotion.
g_emit_phys_cvt_fp_i64:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp ebx,15; ja .gepcfi_bad
    cmp r12d,31; ja .gepcfi_bad
    cmp r13d,GTYPE_F32; je .gepcfi_type_ok
    cmp r13d,GTYPE_F64; jne .gepcfi_bad
.gepcfi_type_ok:
    cmp r12d,15; ja .gepcfi_evex
    mov edi,0xF2; cmp r13d,GTYPE_F64; je 1f; mov edi,0xF3
1:  call g_emit_u8
    mov eax,ebx; shr eax,3; shl eax,2; or eax,0x48
    mov ecx,r12d; shr ecx,3; or eax,ecx
    mov edi,eax; call g_emit_u8
    mov edi,0x2C0F; call g_emit_u16
    jmp .gepcfi_modrm
.gepcfi_evex:
    test dword ptr [rip+isa_cap_bits],ISA_CAP_WIDE_REGFILE; jz .gepcfi_bad
    mov edi,0x62; call g_emit_u8
    mov eax,0x11
    mov ecx,ebx; shr ecx,3; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,r12d; shr ecx,4; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov edi,eax; call g_emit_u8
    mov edi,0xFE; cmp r13d,GTYPE_F32; je 2f; mov edi,0xFF
2:  call g_emit_u8
    mov edi,8; call g_emit_u8
    mov edi,0x2C; call g_emit_u8
.gepcfi_modrm:
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; jmp .gepcfi_done
.gepcfi_bad: mov eax,1
.gepcfi_done: pop r13; pop r12; pop rbx; ret

# Natural FP payload -> U64. Signed CVTT remains a separate numeric relation.
g_emit_fp_u64_stack:
    push rbx
    mov ebx,edi; call g_emit_pop_rax
    mov edi,ebx; call g_emit_fp_u64_payload
    test eax,eax; jnz 1f
    mov edi,0x50; call g_emit_u8
1:  pop rbx; ret

g_emit_fp_u64_payload:
    mov esi,64; cmp edi,GTYPE_F64; je 1f
    mov esi,32; cmp edi,GTYPE_F32; jne 2f
1:  call physical_fp_u64_fragment
    test rax,rax; jz 2f
    mov rdi,rax; mov esi,ecx; jmp g_emit_bytes
2:  mov eax,1; ret

# edi=destination GPR, esi=source XMM, edx=natural FP type.
g_emit_phys_cvt_fp_u64:
    push rbx; push r12
    mov ebx,edi; mov r12d,edx
    mov edi,esi; mov esi,edx; call g_emit_phys_xmm_to_rax
    test eax,eax; jnz 1f
    mov edi,r12d; call g_emit_fp_u64_payload
    test eax,eax; jnz 1f
    mov edi,ebx; xor esi,esi; call g_emit_phys_gpr_move
1:  pop r12; pop rbx; ret

# Existing stack consumers project through the same conversion authority.
g_emit_int_fp_stack:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    call g_emit_pop_rax
    mov edi,ebx; mov esi,r12d; xor edx,edx; call g_emit_phys_int_fp_value
    test eax,eax; jnz .geifs_done
    xor edi,edi; mov esi,r12d; call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .geifs_done
    mov edi,0x50; call g_emit_u8
.geifs_done: pop r12; pop rbx; ret

# edi=resident ordinal, esi=natural type. Frame carrier -> exact RAX payload.
g_emit_packet_resident_rax:
    push rbx; push r12
    mov r12d,esi
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov edi,dword ptr [rcx+rdi*4]
    imul edi,dword ptr [rip+group_lane_factor]; shl edi,3
    mov eax,[rip+g_packet_scalar_lane]; shl eax,3
    cmp r12d,GTYPE_F32; jne 1f
    mov eax,[rip+g_packet_scalar_lane]; shl eax,2
1:  add edi,eax; mov ebx,edi
    mov edi,0x49; cmp r12d,GTYPE_F32; jne 2f
    mov edi,0x41
2:  call g_emit_u8
    mov edi,0x24848b; call g_emit_u24
    mov edi,ebx; call g_emit_u32
    pop r12; pop rbx; ret

# ---------------- expression emitter ----------------
# g_emit_expr(rdi=expr) -> eax type/0, generated value pushed as one qword.
g_emit_expr:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    cmp qword ptr [r12],J_OBJECT; jne .gee_bad
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gee_register_episode
    mov rdi,r12; call g_infer_expr; mov r14d,eax
    mov esi,eax; mov rdi,r12; call g_phys_cse_find_resident
    cmp eax,0; jl .gee_episode_fresh
    mov edi,eax; mov esi,r14d; call g_emit_packet_resident_rax
    jmp .gee_episode_push
.gee_register_episode:
    cmp dword ptr [rip+g_phys_stack_episode],1; jne .gee_episode_fresh
    mov rdi,r12; call g_infer_expr; mov r14d,eax
    mov esi,eax; mov rdi,r12; call g_phys_cse_find_resident
    cmp eax,0; jl .gee_episode_fresh
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov ebx,dword ptr [rcx+rax*4]
    cmp r14d,GTYPE_U64; je .gee_episode_int
    cmp r14d,GTYPE_I64; je .gee_episode_int
    mov edi,ebx; mov esi,r14d; call g_emit_phys_xmm_to_rax
    jmp .gee_episode_push
.gee_episode_int:
    mov edi,ebx; mov esi,GTYPE_F64; call g_emit_phys_xmm_to_rax
.gee_episode_push:
    mov edi,0x50; call g_emit_u8
    mov eax,r14d; jmp .gee_done
.gee_episode_fresh:
    # Reuse an already materialized immutable PredicateFact instead of
    # re-emitting the same comparison/boolean DAG. Preserve the new physical
    # dependency explicitly so parallel fragment execution remains truthful.
    mov rdi,r12; call g_find_materialized_predicate_fact
    test rax,rax; jz .gee_predicate_fresh
    mov r13,rax
    mov rdi,r13; call g_fragment_for_symbol
    test edx,edx; jnz .gee_predicate_fresh
    mov edi,eax; mov esi,dword ptr [rip+g_fragment_count]; call g_note_fragment_dependency
    mov eax,dword ptr [r13+24]; call g_binding_slot_addr
    mov rdi,rax; call g_emit_load_rax_abs
    test eax,eax; jnz .gee_bad
    mov edi,0x50; call g_emit_u8
    test eax,eax; jnz .gee_bad
    mov eax,GTYPE_BOOL; jmp .gee_done
.gee_predicate_fresh:
    # Conservative compile-time folding for pure wrap-u64 expression trees.
    mov rdi,r12; call g_try_fold_u64_const
    test edx,edx; jnz .gee_no_const_fold
    mov rdi,rax; call g_emit_push_imm64
    mov eax,GTYPE_U64; jmp .gee_done
.gee_no_const_fold:
    # literal
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gee_var
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gee_bad
    mov rdi,rax; call g_type_from_node; mov ebx,eax; test ebx,ebx; jz .gee_bad
    cmp ebx,GTYPE_U64; je .gee_lit_u64
    cmp ebx,GTYPE_I64; je .gee_lit_i64
    cmp ebx,GTYPE_BOOL; je .gee_lit_bool
    cmp ebx,GTYPE_F64; je .gee_lit_f64
    cmp ebx,GTYPE_F32; je .gee_lit_f32
    mov edi,ebx; call g_is_rankn_fp; test eax,eax; jnz .gee_lit_rankn_fp
    jmp .gee_bad
.gee_lit_u64:
    mov rax,r13; call node_parse_u64; test edx,edx; jnz .gee_bad
    mov rdi,rax; call g_emit_push_imm64; mov eax,GTYPE_U64; jmp .gee_done
.gee_lit_i64:
    mov rdi,r13; call g_parse_i64_node; test edx,edx; jnz .gee_bad
    mov rdi,rax; call g_emit_push_imm64; mov eax,GTYPE_I64; jmp .gee_done
.gee_lit_bool:
    cmp qword ptr [r13],J_TRUE; je 1f
    cmp qword ptr [r13],J_FALSE; jne .gee_bad
    xor edi,edi; jmp 2f
1:  mov edi,1
2:  call g_emit_push_imm64; mov eax,GTYPE_BOOL; jmp .gee_done
.gee_lit_f64:
    mov rax,r13; call node_parse_f64_bits; test edx,edx; jnz .gee_bad
    mov rdi,rax; call g_emit_push_imm64; mov eax,GTYPE_F64; jmp .gee_done
.gee_lit_f32:
    mov rax,r13; call node_parse_f32_bits; test edx,edx; jnz .gee_bad
    mov edi,eax
    call g_emit_push_imm64; mov eax,GTYPE_F32; jmp .gee_done
.gee_lit_rankn_fp:
    mov rax,r13; call node_parse_f64_bits; test edx,edx; jnz .gee_bad
    mov rdi,rax; call g_emit_push_imm64
    mov edi,GTYPE_F64; mov esi,ebx; call g_emit_rankn_fp_cast_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done

.gee_var:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gee_axis
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gee_bad
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gee_bad
    mov r13,rax; mov eax,dword ptr [r13+16]
    cmp eax,GK_INPUT; je .gee_var_input
    cmp dword ptr [r13+24],-1; je .gee_bad
    mov eax,dword ptr [r13+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov edi,0x50; call g_emit_u8
    mov eax,dword ptr [r13+20]; jmp .gee_done
.gee_var_input:
    mov eax,dword ptr [r13+24]; call g_input_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov edi,0x50; call g_emit_u8
    mov eax,dword ptr [r13+20]; jmp .gee_done

.gee_axis:
    mov rdi,r12; lea rsi,[rip+gk_axis]; mov edx,gk_axis_end-gk_axis; call obj_get
    test rax,rax; jz .gee_state
    # one-axis general path: current coordinate is R10
    mov edi,0x5241; call g_emit_u16       # push r10
    mov eax,GTYPE_U64; jmp .gee_done
.gee_state:
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gee_field
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gee_bad
    mov r13,rax
    cmp dword ptr [rip+g_iter_reg_mode],1; jne .gee_state_memory
    mov eax,dword ptr [r13+20]
    test eax,eax; jz .gee_state_reg0
    cmp eax,1; je .gee_state_reg1
    cmp eax,2; je .gee_state_reg2
    cmp eax,3; je .gee_state_reg3
    jmp .gee_bad
.gee_state_reg0:
    lea rdi,[rip+gc_push_r8]; mov esi,gc_push_r8_end-gc_push_r8; call g_emit_bytes
    mov eax,dword ptr [r13+16]; jmp .gee_done
.gee_state_reg1:
    lea rdi,[rip+gc_push_r9]; mov esi,gc_push_r9_end-gc_push_r9; call g_emit_bytes
    mov eax,dword ptr [r13+16]; jmp .gee_done
.gee_state_reg2:
    lea rdi,[rip+gc_push_r10]; mov esi,gc_push_r10_end-gc_push_r10; call g_emit_bytes
    mov eax,dword ptr [r13+16]; jmp .gee_done
.gee_state_reg3:
    lea rdi,[rip+gc_push_rbx]; mov esi,gc_push_rbx_end-gc_push_rbx; call g_emit_bytes
    mov eax,dword ptr [r13+16]; jmp .gee_done
.gee_state_memory:
    mov eax,dword ptr [r13+20]; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov edi,0x50; call g_emit_u8; mov eax,dword ptr [r13+16]; jmp .gee_done
.gee_field:
    mov rdi,r12; lea rsi,[rip+gk_field]; mov edx,gk_field_end-gk_field; call obj_get
    test rax,rax; jz .gee_load
    mov r13,rax
    mov rdi,r13; call g_resolve_field_expr; test rax,rax; jnz .gee_field_static
    mov rdi,r13; call g_iter_projection_lookup_field
    test eax,eax; jz .gee_bad
    dec eax; mov r14d,eax
    mov rdx,[rip+g_iter_projection_slot_ptr]; mov eax,dword ptr [rdx+r14*4]
    call g_binding_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov edi,0x50; call g_emit_u8
    mov rdx,[rip+g_iter_projection_type_ptr]; mov eax,dword ptr [rdx+r14*4]
    jmp .gee_done
.gee_field_static:
    mov rdi,rax; call g_emit_expr; jmp .gee_done
.gee_load:
    mov rdi,r12; lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gee_dictlookup
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gee_bad
    mov r13,rax; cmp dword ptr [r13+16],GK_MAP; jne .gee_bad
    mov rdi,r12; lea rsi,[rip+gk_indices]; mov edx,gk_indices_end-gk_indices; call obj_get
    test rax,rax; jz .gee_bad
    mov r14,[rax+24]; test r14,r14; jz .gee_bad
    cmp qword ptr [r14+32],0; jne .gee_bad
    mov edi,0x5241; call g_emit_u16       # push old r10
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_U64; jne .gee_bad
    call g_emit_pop_rax
    # mov r10,rax: 49 89 c2
    lea rdi,[rip+gc_mov_r10_rax]; mov esi,gc_mov_r10_rax_end-gc_mov_r10_rax; call g_emit_bytes
    mov r14,[r13+32]
    mov rdi,r14; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gee_bad
    mov rdi,rax; call g_emit_expr; mov ebx,eax; test ebx,ebx; jz .gee_bad
    # preserve result, restore r10, push result
    call g_emit_pop_rax
    mov edi,0x5A41; call g_emit_u16       # pop r10
    mov edi,0x50; call g_emit_u8
    mov eax,ebx; jmp .gee_done
.gee_dictlookup:
    mov rdi,r12; lea rsi,[rip+gk_dictionary_lookup]; mov edx,gk_dictionary_lookup_end-gk_dictionary_lookup; call obj_get
    test rax,rax; jz .gee_op
    mov rdi,rax; call g_emit_dictionary_lookup_expr; jmp .gee_done

.gee_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gee_bad
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gee_bad
    mov r14,[rax+24]; test r14,r14; jz .gee_bad
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_fma]; mov ecx,3; call span_eq
    test eax,eax; jz .gee_cast_probe
    test dword ptr [rip+isa_cap_bits],ISA_CAP_FMA; jz .gee_bad
    mov rdi,r12; call g_infer_expr; mov r15d,eax
    cmp eax,GTYPE_F32; je .gee_fma_ready
    cmp eax,GTYPE_F64; jne .gee_bad
.gee_fma_ready:
    xor ebx,ebx
.gee_fma_operand:
    test r14,r14; jz .gee_bad
    mov rdi,r14; call g_emit_expr; test eax,eax; jz .gee_bad
    mov edi,eax; mov esi,r15d; call g_convert_stack_top; test eax,eax; jnz .gee_bad
    mov r14,[r14+32]; inc ebx; cmp ebx,3; jb .gee_fma_operand
    test r14,r14; jnz .gee_bad
    mov edi,0; mov esi,r15d; call physical_fma_fragment
    test rax,rax; jz .gee_bad
    mov rdi,rax; mov esi,ecx; call g_emit_bytes
    mov eax,r15d; jmp .gee_done
.gee_cast_probe:
    # cast
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jz .gee_not
    mov rdi,r14; call g_emit_expr; mov ebx,eax; test ebx,ebx; jz .gee_bad
    mov rdi,r12; lea rsi,[rip+gk_to]; mov edx,gk_to_end-gk_to; call obj_get
    test rax,rax; jz .gee_bad
    mov rdi,rax; call g_type_from_node; mov r13d,eax; test r13d,r13d; jz .gee_bad
    cmp ebx,GTYPE_U64; jne .gee_cast_range_ready
    cmp r13d,GTYPE_F32; je .gee_cast_range_probe
    cmp r13d,GTYPE_F64; jne .gee_cast_range_ready
.gee_cast_range_probe:
    mov rdi,r14; call g_u64_expr_fits_signed
    test eax,eax; jz .gee_cast_range_ready
    mov ebx,GTYPE_I64
.gee_cast_range_ready:
    mov eax,ebx; mov edx,r13d; call g_emit_cast_top; test eax,eax; jnz .gee_bad
    mov eax,r13d; jmp .gee_done
.gee_not:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq
    test eax,eax; jz .gee_bitnot
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    lea rdi,[rip+gc_not_bool]; mov esi,gc_not_bool_end-gc_not_bool; call g_emit_bytes
    mov eax,GTYPE_BOOL; jmp .gee_done
.gee_bitnot:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_bit_not]; mov ecx,gv_bit_not_end-gv_bit_not; call span_eq
    test eax,eax; jz .gee_neg
    mov rdi,r14; call g_emit_expr; mov ebx,eax; cmp eax,GTYPE_U64; je 1f; cmp eax,GTYPE_I64; jne .gee_bad
1:  lea rdi,[rip+gc_bit_not]; mov esi,gc_bit_not_end-gc_bit_not; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq
    test eax,eax; jz .gee_abs
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_I64; je .gee_neg_i
    cmp eax,GTYPE_U64; je .gee_neg_u
    cmp eax,GTYPE_F64; je .gee_neg_f64
    cmp eax,GTYPE_F32; je .gee_neg_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jnz .gee_neg_wide
    jmp .gee_bad
.gee_neg_u:
    # Unsigned negation is the existing subtraction relation with zero lhs.
    lea rdi,[rip+gc_zero_lhs_stack]; mov esi,gc_zero_lhs_stack_end-gc_zero_lhs_stack; call g_emit_bytes
    lea rdi,[rip+gv_sub]; mov esi,gv_sub_end-gv_sub; mov edx,ebx; call g_emit_int_op
    test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_neg_i:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gee_neg_i_wrap
    lea rdi,[rip+gc_neg_i64_trap]; mov esi,gc_neg_i64_trap_end-gc_neg_i64_trap; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg_i_wrap: lea rdi,[rip+gc_neg_i64]; mov esi,gc_neg_i64_end-gc_neg_i64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg_f64: lea rdi,[rip+gc_neg_f64]; mov esi,gc_neg_f64_end-gc_neg_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg_f32: lea rdi,[rip+gc_neg_f32]; mov esi,gc_neg_f32_end-gc_neg_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg_wide: mov edi,ebx; xor esi,esi; call g_emit_rankn_fp_unary_top; test eax,eax; jnz .gee_bad; mov eax,ebx; jmp .gee_done
.gee_abs:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jz .gee_sqrt_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_I64; je .gee_abs_i
    cmp eax,GTYPE_U64; je .gee_done_keep
    cmp eax,GTYPE_F64; je .gee_abs_f64
    cmp eax,GTYPE_F32; je .gee_abs_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jnz .gee_abs_wide
    jmp .gee_bad
.gee_abs_i:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gee_abs_i_wrap
    lea rdi,[rip+gc_abs_i64_trap]; mov esi,gc_abs_i64_trap_end-gc_abs_i64_trap; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs_i_wrap: lea rdi,[rip+gc_abs_i64]; mov esi,gc_abs_i64_end-gc_abs_i64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs_f64: lea rdi,[rip+gc_abs_f64]; mov esi,gc_abs_f64_end-gc_abs_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs_f32: lea rdi,[rip+gc_abs_f32]; mov esi,gc_abs_f32_end-gc_abs_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs_wide: mov edi,ebx; mov esi,1; call g_emit_rankn_fp_unary_top; test eax,eax; jnz .gee_bad; mov eax,ebx; jmp .gee_done
.gee_done_keep: mov eax,ebx; jmp .gee_done

.gee_sqrt_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jz .gee_square_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_sqrt_f64
    cmp eax,GTYPE_F32; je .gee_sqrt_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_SQRT_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_sqrt_f64: lea rdi,[rip+gc_sqrt_f64]; mov esi,gc_sqrt_f64_end-gc_sqrt_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_sqrt_f32: lea rdi,[rip+gc_sqrt_f32]; mov esi,gc_sqrt_f32_end-gc_sqrt_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_square_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq
    test eax,eax; jz .gee_trunc_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_square_f64
    cmp eax,GTYPE_F32; je .gee_square_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    # Duplicate the immutable pointer, then consume the old MUL relation.
    mov edi,0x2434FF; call g_emit_u24     # push qword ptr [rsp]
    lea rdi,[rip+gv_mul]; mov esi,gv_mul_end-gv_mul; mov edx,ebx
    call g_emit_rankn_fp_binary_op; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_square_f64: lea rdi,[rip+gc_square_f64]; mov esi,gc_square_f64_end-gc_square_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_square_f32: lea rdi,[rip+gc_square_f32]; mov esi,gc_square_f32_end-gc_square_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_trunc_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_trunc]; mov ecx,gv_trunc_end-gv_trunc; call span_eq
    test eax,eax; jz .gee_exp_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_trunc_f64
    cmp eax,GTYPE_F32; je .gee_trunc_f32
    jmp .gee_bad
.gee_trunc_f64: lea rdi,[rip+gc_trunc_f64]; mov esi,gc_trunc_f64_end-gc_trunc_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_trunc_f32: lea rdi,[rip+gc_trunc_f32]; mov esi,gc_trunc_f32_end-gc_trunc_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_exp_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_exp]; mov ecx,gv_exp_end-gv_exp; call span_eq
    test eax,eax; jz .gee_log_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_exp_f64
    cmp eax,GTYPE_F32; je .gee_exp_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_EXP_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_exp_f64: lea rdi,[rip+gc_exp_f64]; mov esi,OFFSET FLAT:gc_exp_f64_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_exp_f32: lea rdi,[rip+gc_exp_f32]; mov esi,OFFSET FLAT:gc_exp_f32_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_log_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_log]; mov ecx,gv_log_end-gv_log; call span_eq
    test eax,eax; jz .gee_sin_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_log_f64
    cmp eax,GTYPE_F32; je .gee_log_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_LOG_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_log_f64: lea rdi,[rip+gc_log_f64]; mov esi,OFFSET FLAT:gc_log_f64_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_log_f32: lea rdi,[rip+gc_log_f32]; mov esi,OFFSET FLAT:gc_log_f32_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_sin_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sin]; mov ecx,gv_sin_end-gv_sin; call span_eq
    test eax,eax; jz .gee_cos_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_sin_f64
    cmp eax,GTYPE_F32; je .gee_sin_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_SIN_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_sin_f64: lea rdi,[rip+gc_sin_f64]; mov esi,OFFSET FLAT:gc_sin_f64_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_sin_f32: lea rdi,[rip+gc_sin_f32]; mov esi,OFFSET FLAT:gc_sin_f32_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_cos_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cos]; mov ecx,gv_cos_end-gv_cos; call span_eq
    test eax,eax; jz .gee_select
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_cos_f64
    cmp eax,GTYPE_F32; je .gee_cos_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_COS_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_cos_f64: lea rdi,[rip+gc_cos_f64]; mov esi,OFFSET FLAT:gc_cos_f64_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_cos_f32: lea rdi,[rip+gc_cos_f32]; mov esi,OFFSET FLAT:gc_cos_f32_size; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_select:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gee_andor
    # Resolve the three arguments and infer the common branch representation
    # before emitting either branch.  This prevents a select from carrying
    # integer bits on one edge and floating bits on the other.
    mov r12,r14                         # condition
    mov r13,[r12+32]; test r13,r13; jz .gee_bad   # true branch
    mov r14,[r13+32]; test r14,r14; jz .gee_bad   # false branch
    mov rdi,r12; call g_infer_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    mov rdi,r13; call g_infer_expr; mov ebx,eax; test ebx,ebx; jz .gee_bad
    mov rdi,r14; call g_infer_expr; mov edx,eax; test edx,edx; jz .gee_bad
    mov eax,ebx; call g_low_type; test eax,eax; jz .gee_bad
    mov ebx,eax                         # common result type

    # Fold literal condition, but still convert the selected representation.
    mov rdi,r12; call g_expr_bool_literal; test edx,edx; jnz .gee_select_dynamic
    test eax,eax; jz .gee_select_const_false
    mov rdi,r13; call g_emit_expr; test eax,eax; jz .gee_bad
    mov edi,eax; mov esi,ebx; call g_convert_stack_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_select_const_false:
    mov rdi,r14; call g_emit_expr; test eax,eax; jz .gee_bad
    mov edi,eax; mov esi,ebx; call g_convert_stack_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_select_dynamic:
    # Lazy select: condition; if false jump to false branch; both emitted
    # branches are normalized to the common inferred representation.
    mov rdi,r12; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    call g_emit_pop_rax
    lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    call g_emit_jz_patch; mov r15,rax
    mov rdi,r13; call g_emit_expr; test eax,eax; jz .gee_bad
    mov edi,eax; mov esi,ebx; call g_convert_stack_top; test eax,eax; jnz .gee_bad
    call g_emit_jmp_patch; mov r13,rax
    G_EMIT_POSITION rsi; mov rdi,r15; call g_patch_rel32
    mov rdi,r14; call g_emit_expr; test eax,eax; jz .gee_bad
    mov edi,eax; mov esi,ebx; call g_convert_stack_top; test eax,eax; jnz .gee_bad
    G_EMIT_POSITION rsi; mov rdi,r13; call g_patch_rel32
    mov eax,ebx; jmp .gee_done

.gee_andor:
    # lazy and/or, eager xor
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq
    test eax,eax; jnz .gee_lazy_and
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq
    test eax,eax; jnz .gee_lazy_or
    jmp .gee_binary
.gee_lazy_and:
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    call g_emit_pop_rax; lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    call g_emit_jz_patch; mov r15,rax
    mov r14,[r14+32]; test r14,r14; jz .gee_bad
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    call g_emit_jmp_patch; mov r13,rax
    G_EMIT_POSITION rsi; mov rdi,r15; call g_patch_rel32
    xor edi,edi; call g_emit_push_imm64
    G_EMIT_POSITION rsi; mov rdi,r13; call g_patch_rel32
    mov eax,GTYPE_BOOL; jmp .gee_done
.gee_lazy_or:
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    call g_emit_pop_rax; lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    call g_emit_jnz_patch; mov r15,rax
    mov r14,[r14+32]; test r14,r14; jz .gee_bad
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    call g_emit_jmp_patch; mov r13,rax
    G_EMIT_POSITION rsi; mov rdi,r15; call g_patch_rel32
    mov edi,1; call g_emit_push_imm64
    G_EMIT_POSITION rsi; mov rdi,r13; call g_patch_rel32
    mov eax,GTYPE_BOOL; jmp .gee_done

.gee_binary:
    mov rdi,r12; call g_try_emit_u64_const_binary
    test eax,eax; jnz .gee_done
    mov rdi,r14; call g_emit_expr; mov ebx,eax; test ebx,ebx; jz .gee_bad
    mov r15,[r14+32]; test r15,r15; jz .gee_bad
    cmp qword ptr [r15+32],0; jne .gee_bad
    mov rdi,r15; call g_emit_expr; mov r12d,eax; test r12d,r12d; jz .gee_bad
    # dispatch by operator bytes.
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq
    test eax,eax; jnz .gee_bool_xor
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_compare_op; test eax,eax; jnz .gee_compare
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_bit_binary; test eax,eax; jnz .gee_bit_binary
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_shift_op; test eax,eax; jnz .gee_shift
    # mod
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq
    test eax,eax; jnz .gee_mod
    # arithmetic add/sub/mul/div/min/max
    mov eax,ebx; mov edx,r12d; call g_low_type; mov r14d,eax; test r14d,r14d; jz .gee_bad
    mov rdi,[r13+8]; mov rsi,[r13+16]; mov edx,ebx; mov ecx,r12d; mov r8d,r14d
    call g_emit_arithmetic_top2
    test eax,eax; jnz .gee_bad
    mov eax,r14d; jmp .gee_done
.gee_bool_xor:
    cmp ebx,GTYPE_BOOL; jne .gee_bad; cmp r12d,GTYPE_BOOL; jne .gee_bad
    lea rdi,[rip+gc_xor_qword]; mov esi,gc_xor_qword_end-gc_xor_qword; call g_emit_bytes
    mov eax,GTYPE_BOOL; jmp .gee_done
.gee_compare:
    mov rdi,[r13+8]; mov rsi,[r13+16]; mov edx,ebx; mov ecx,r12d; call g_emit_compare_top2
    test eax,eax; jnz .gee_bad
    mov eax,GTYPE_BOOL; jmp .gee_done
.gee_bit_binary:
    cmp ebx,GTYPE_I64; je 1f; cmp ebx,GTYPE_U64; jne .gee_bad
1:  cmp r12d,ebx; jne .gee_bad
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_emit_bit_top2
    test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_shift:
    cmp ebx,GTYPE_U64; je 1f; cmp ebx,GTYPE_I64; jne .gee_bad
1:  cmp r12d,GTYPE_U64; je 2f; cmp r12d,GTYPE_I64; jne .gee_bad
2:  mov rdi,[r13+8]; mov rsi,[r13+16]; call g_emit_shift_top2
    test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_mod:
    cmp ebx,GTYPE_I64; je 1f; cmp ebx,GTYPE_U64; jne .gee_bad
1:  cmp r12d,ebx; jne .gee_bad
    mov edi,ebx; call g_emit_mod_top2; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_bad: xor eax,eax
.gee_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret


# ---------------- 1.3.15 Rank-N causal carrier vocabulary ----------------
# Physical capacity is a target property, never a semantic admission threshold.
# States beyond the profitable resident budget spill into the current
# execution-local StateFact frame while their expressions continue through the
# same register-native DAG.
.equ G_PHYS_CARRIER_SPILL,0
.equ G_PHYS_CARRIER_INT,1
.equ G_PHYS_CARRIER_FP,2
.equ G_PHYS_CARRIER_COUNTER,3

# Physical scalar-FP geometry is read from the compiler-wide ISA capability
# authority. AVX-512 exposes the architectural XMM16..31 bank; older targets
# retain the same 16-carrier realization. This is one Physical Reality, not a
# vendor/backend split.
g_phys_fp_geometry_refresh:
    mov dword ptr [rip+g_phys_fp_carrier_count],16
    mov dword ptr [rip+g_phys_fp_all_mask],0x0000FFFF
    test dword ptr [rip+isa_cap_bits],ISA_CAP_WIDE_REGFILE
    jz .gpfgr_done
    mov dword ptr [rip+g_phys_fp_carrier_count],32
    mov dword ptr [rip+g_phys_fp_all_mask],-1
.gpfgr_done:
    ret

# Build the compile-time carrier map for all declared state ValueFacts.
# -> eax=0 success, 1 unsupported type.  No runtime table is emitted.
g_phys_assign_state_carriers:
    call g_phys_fp_geometry_refresh
    push rbx; push r12; push r13; push r14; push r15
    # Start with the established frame authority. Shared facts and actual
    # anonymous pressure are proved before old/next residency is admitted.
    mov dword ptr [rip+g_reg_iter_fp_count],0
    mov dword ptr [rip+g_reg_iter_int_count],0
    mov dword ptr [rip+g_phys_fp_reserved_mask],0
    mov dword ptr [rip+g_phys_int_reserved_mask],0
    xor ecx,ecx
.gpasc_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gpasc_ok
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_SPILL
    mov rax,[rip+g_reg_iter_old_reg_ptr]; mov dword ptr [rax+rcx*4],-1
    mov rax,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rax+rcx*4],-1
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gpasc_dead
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gpasc_data
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; jne .gpasc_data
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_COUNTER
    mov rax,[rip+g_reg_iter_old_reg_ptr]; mov dword ptr [rax+rcx*4],3   # RBX
    inc ecx; jmp .gpasc_loop
.gpasc_dead:
    inc ecx; jmp .gpasc_loop
.gpasc_data:
    mov edx,dword ptr [r11+16]
    cmp edx,GTYPE_F64; je .gpasc_fp
    cmp edx,GTYPE_F32; je .gpasc_fp
    cmp edx,GTYPE_BOOL; je .gpasc_int
    cmp edx,GTYPE_U64; je .gpasc_int
    cmp edx,GTYPE_I64; je .gpasc_int
    jmp .gpasc_bad
.gpasc_fp:
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_FP
    inc dword ptr [rip+g_reg_iter_fp_count]
    inc ecx; jmp .gpasc_loop
.gpasc_int:
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_INT
    mov r12d,dword ptr [rip+g_reg_iter_int_count]
    # Integer StateFact residency is target GPR geometry, not a semantic count.
    # Ask the old/output carrier maps directly; when either domain is exhausted
    # this state naturally remains in the execution-local frame.  Roles that
    # borrow the anonymous R11..R14 pool are subtracted from that same pool.
    mov edi,r12d; push rcx; call g_phys_int_old_reg; pop rcx
    cmp eax,0; jl .gpasc_int_spill
    mov r13d,eax
    mov edi,r12d; push rcx; call g_phys_int_output_reg; pop rcx
    cmp eax,0; jl .gpasc_int_spill
    mov r14d,eax
    mov rax,[rip+g_reg_iter_old_reg_ptr]; mov dword ptr [rax+rcx*4],r13d
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rdx+rcx*4],r14d
    cmp r13d,11; jb .gpasc_int_mark_out
    cmp r13d,14; ja .gpasc_int_mark_out
    bts dword ptr [rip+g_phys_int_reserved_mask],r13d
.gpasc_int_mark_out:
    cmp r14d,11; jb .gpasc_int_spill
    cmp r14d,14; ja .gpasc_int_spill
    bts dword ptr [rip+g_phys_int_reserved_mask],r14d
.gpasc_int_spill:
    inc dword ptr [rip+g_reg_iter_int_count]
    inc ecx; jmp .gpasc_loop
.gpasc_ok:
    xor eax,eax; jmp .gpasc_done
.gpasc_bad:
    mov eax,1
.gpasc_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- 1.3.14 unified scalar FP Physical-DAG lowering ----------------
# A floating ValueFact is compiled directly into a requested physical XMM carrier.
# Leaves that are already resident (versioned state or retained constants) are
# consumed in place. Complex subtrees borrow from a compile-time free-carrier
# mask and release that carrier immediately after its final proved consumer.
# The generated program contains no allocator and no register-copy stack.


# Reset the anonymous FP carrier pool, then subtract any carrier retained by a
# constant ValueFact. Constant residency and temporary allocation therefore
# share one physical authority instead of owning disjoint hard-coded worlds.
# Every root can consume mixed numeric/BOOL children. One lifetime resets
# both anonymous domains; a result type never restricts child carrier types.
g_phys_temp_reset:
    call g_phys_fp_temp_reset
    jmp g_phys_int_temp_reset

g_phys_fp_temp_reset:
    push rcx
    mov dword ptr [rip+g_phys_fp_temp_live],0
    mov eax,dword ptr [rip+g_phys_fp_all_mask]
    mov ecx,dword ptr [rip+g_phys_fp_reserved_mask]
    not ecx
    and eax,ecx
    cmp dword ptr [rip+g_packet_ready],0; je 995f
    mov ecx,[rip+g_packet_register_live]; not ecx; and eax,ecx
995: mov dword ptr [rip+g_phys_fp_temp_mask],eax
    xor ecx,ecx
.gpfptr_cse_loop:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpfptr_cse_done
    cmp ecx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpfptr_cse_done
    mov rax,qword ptr [rip+g_phys_cse_resident_reg_ptr]
    mov edx,dword ptr [rax+rcx*4]
    cmp edx,31; ja .gpfptr_cse_next
    btr dword ptr [rip+g_phys_fp_temp_mask],edx
.gpfptr_cse_next:
    inc ecx; jmp .gpfptr_cse_loop
.gpfptr_cse_done:
    xor ecx,ecx
.gpfptr_resident_loop:
    cmp ecx,dword ptr [rip+g_phys_const_resident_count]; jae .gpfptr_done
    mov rax,qword ptr [rip+g_phys_const_resident_reg_ptr]
    mov edx,dword ptr [rax+rcx*4]
    cmp edx,31; ja .gpfptr_next
    btr dword ptr [rip+g_phys_fp_temp_mask],edx
.gpfptr_next:
    inc ecx; jmp .gpfptr_resident_loop
.gpfptr_done:
    pop rcx
    ret

g_phys_fp_temp_alloc:
    mov eax,dword ptr [rip+g_phys_fp_temp_mask]
    test eax,eax; jz .gpfpta_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+g_phys_fp_temp_mask],eax
    inc dword ptr [rip+g_phys_fp_temp_live]
    mov edx,dword ptr [rip+g_phys_fp_temp_live]
    cmp edx,dword ptr [rip+g_phys_fp_temp_peak]
    jbe .gpfpta_peak_done
    mov dword ptr [rip+g_phys_fp_temp_peak],edx
.gpfpta_peak_done:
    mov eax,ecx
    ret
.gpfpta_fail:
    # Record physical carrier exhaustion for the AOT realization probe.  The
    # caller may retry the same DAG after releasing a competing physical
    # candidate; this is not a semantic/backend failure.
    mov dword ptr [rip+g_phys_fp_temp_exhausted],1
    mov eax,-1
    ret

# edi=physical XMM. Only the anonymous temporary domain is releasable here.
g_phys_fp_temp_free:
    cmp edi,dword ptr [rip+g_phys_fp_carrier_count]; jae .gpfptf_done
    mov eax,1; mov ecx,edi; shl eax,cl
    test dword ptr [rip+g_phys_fp_reserved_mask],eax; jnz .gpfptf_done
    xor ecx,ecx
.gpfptf_cse_loop:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpfptf_const_start
    cmp ecx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpfptf_const_start
    mov rdx,qword ptr [rip+g_phys_cse_resident_reg_ptr]
    cmp dword ptr [rdx+rcx*4],edi; je .gpfptf_done
    inc ecx; jmp .gpfptf_cse_loop
.gpfptf_const_start:
    xor ecx,ecx
.gpfptf_const_loop:
    cmp ecx,dword ptr [rip+g_phys_const_resident_count]; jae .gpfptf_yes
    mov rdx,qword ptr [rip+g_phys_const_resident_reg_ptr]
    cmp dword ptr [rdx+rcx*4],edi; je .gpfptf_done
    inc ecx; jmp .gpfptf_const_loop
.gpfptf_yes:
    bts dword ptr [rip+g_phys_fp_temp_mask],edi
    cmp dword ptr [rip+g_phys_fp_temp_live],0
    jle .gpfptf_done
    dec dword ptr [rip+g_phys_fp_temp_live]
.gpfptf_done:
    ret

# Emit one scalar FP carrier copy through the existing VEX/EVEX authority.
# edi=dst, esi=src, edx=GTYPE_F32/F64; equal identities emit nothing.
g_emit_phys_xmm_move:
    cmp edi,esi
    je .gepxm_ok
    # A scalar ValueFact owns only its semantic low lane. Use the source as both
    # VMOV scalar inputs so the whole XMM carrier is renamed from src; preserving
    # dead high-lane bits from the old destination would create a false
    # cross-generation dependency with no semantic owner.
    mov r8d,edx
    mov ecx,esi
    mov edx,esi
    mov esi,edi
    mov edi,0x10
    call g_emit_phys_vex_scalar3
    ret
.gepxm_ok:
    xor eax,eax
    ret

# Materialize runtime RAX/EAX bits directly into an arbitrary XMM carrier.
# edi=dst, esi=GTYPE_F32/F64.
g_emit_phys_xmm_from_rax:
    mov edx,0x6e; jmp g_emit_phys_scalar_bits_transport

# Extract the same scalar payload through the common native encoder.
g_emit_phys_xmm_to_rax:
    mov edx,0x7e
g_emit_phys_scalar_bits_transport:
    mov r8d,esi
    mov esi,edi
    mov edi,edx; or edi,0x500
    cmp r8d,GTYPE_F64; je 1f
    cmp r8d,GTYPE_F32; jne 3f
    jmp 2f
1:  or edi,0x1000
2:  cmp esi,15; jbe 4f
    or edi,0x8000
4:  xor edx,edx; xor ecx,ecx; call physical_encode_rrr
    test edx,edx; jz 3f
    sub rsp,8; mov [rsp],rax
    mov rdi,rsp; mov esi,edx; call g_emit_bytes
    add rsp,8; ret
3:  mov eax,1; ret

# VEX.128 scalar three-operand arithmetic.
# edi=opcode (58 add, 5c sub, 59 mul), esi=dst, edx=src1, ecx=src2,
# r8d=GTYPE_F32/F64. No reassociation or contraction is performed.
g_emit_phys_vex_scalar3:
    mov eax,esi; or eax,edx; or eax,ecx
    cmp eax,15; jbe g_emit_phys_scalar3_shared
    or edi,0x8000
g_emit_phys_scalar3_shared:
    or edi,0x100
    cmp r8d,GTYPE_F64; je 1f
    cmp r8d,GTYPE_F32; jne 3f
    or edi,0x800; jmp 2f
1:  or edi,0xc00
    test edi,0x8000; jz 2f
    or edi,0x1000
2:  jmp g_phys_window_scalar_descriptor
g_emit_phys_rrr_descriptor:
    call physical_encode_rrr
    test edx,edx; jz 3f
    sub rsp,8; mov [rsp],rax
    mov rdi,rsp; mov esi,edx; call g_emit_bytes
    add rsp,8; ret
3:  mov eax,1; ret

# Load one immutable scalar ConstantFact directly from the generated
# RIP-relative pool into an XMM carrier.  This is the address form of the same
# ValueFact, not a constant-specific execution backend. edi=dst, esi=type,
# rdx=compile-time pool address or 0 during discarded proof emission.
g_emit_phys_xmm_from_const_mem:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13,rdx
    cmp ebx,31; ja .gepxcm_bad
    cmp r12d,GTYPE_F64; je .gepxcm_type_ok
    cmp r12d,GTYPE_F32; jne .gepxcm_bad
.gepxcm_type_ok:
    cmp ebx,15; ja .gepxcm_evex
    mov edi,0xC5; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    # Two-byte VEX VMOVQ/VMOVD from RIP-relative memory.  These forms define
    # the whole scalar carrier and therefore carry no dead-high-lane dependency.
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    cmp r12d,GTYPE_F64; jne 755f
    or eax,0x7A
    jmp 756f
755:or eax,0x79
756:mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    mov edi,0x7E; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    jmp .gepxcm_disp
.gepxcm_evex:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    mov eax,1
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    mov edi,0x7D
    cmp r12d,GTYPE_F64; jne 757f
    mov edi,0xFD
757:call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    mov edi,0x08; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    mov edi,0x6E; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxcm_bad
.gepxcm_disp:
    G_EMIT_POSITION rbx
    xor edi,edi; call g_emit_u32; test eax,eax; jnz .gepxcm_bad
    test r13,r13; jz .gepxcm_ok
    mov rdi,rbx; mov rsi,r13; call g_patch_rel32
.gepxcm_ok:
    xor eax,eax; jmp .gepxcm_done
.gepxcm_bad:
    mov eax,1
.gepxcm_done:
    pop r13; pop r12; pop rbx; ret

# Direct scalar StateFact frame transport.  Mutable state uses the tagged
# R15-relative AddressFact already owned by General Physical Reality; FP payloads
# move between that address and XMM without a synthetic GPR carrier.
# edi=XMM, esi=GTYPE_F32/F64, rdx=tagged state address -> eax 0/1.
g_emit_phys_xmm_to_state_mem:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13,rdx
    cmp ebx,31; ja .gepxsm_bad
    cmp r12d,GTYPE_F64; je .gepxsm_type_ok
    cmp r12d,GTYPE_F32; jne .gepxsm_bad
.gepxsm_type_ok:
    mov rax,r13; shr rax,48; cmp eax,0xffff; jne .gepxsm_bad
    cmp ebx,15; ja .gepxsm_evex
    mov edi,0xC4; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    # VEX3: R selects XMM, X unused=1, B extends R15 base and is therefore 0.
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40; or eax,1
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov edi,0x79; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov edi,0x7E
    cmp r12d,GTYPE_F64; jne 758f
    mov edi,0xD6
758:call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x87
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov edi,r13d; call g_emit_u32; test eax,eax; jnz .gepxsm_bad
    xor eax,eax; jmp .gepxsm_done
.gepxsm_evex:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov eax,1
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x40
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov edi,0x7D
    cmp r12d,GTYPE_F64; jne 759f
    mov edi,0xFD
759:call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov edi,0x08; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov edi,0x7E; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x87
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxsm_bad
    mov edi,r13d; call g_emit_u32; test eax,eax; jnz .gepxsm_bad
    xor eax,eax; jmp .gepxsm_done
.gepxsm_bad:
    mov eax,1
.gepxsm_done:
    pop r13; pop r12; pop rbx; ret

# edi=XMM destination, esi=GTYPE_F32/F64, rdx=tagged state address -> eax 0/1.
g_emit_phys_xmm_from_state_mem:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13,rdx
    cmp ebx,31; ja .gepxlm_bad
    cmp r12d,GTYPE_F64; je .gepxlm_type_ok
    cmp r12d,GTYPE_F32; jne .gepxlm_bad
.gepxlm_type_ok:
    mov rax,r13; shr rax,48; cmp eax,0xffff; jne .gepxlm_bad
    cmp ebx,15; ja .gepxlm_evex
    mov edi,0xC4; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40; or eax,1
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov edi,0x79
    cmp r12d,GTYPE_F64; jne 765f
    mov edi,0x7A
765:call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov edi,0x6E
    cmp r12d,GTYPE_F64; jne 766f
    mov edi,0x7E
766:call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x87
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov edi,r13d; call g_emit_u32; test eax,eax; jnz .gepxlm_bad
    xor eax,eax; jmp .gepxlm_done
.gepxlm_evex:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov eax,1
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x40
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov edi,0x7D
    cmp r12d,GTYPE_F64; jne 767f
    mov edi,0xFD
767:call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov edi,0x08; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov edi,0x6E; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x87
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxlm_bad
    mov edi,r13d; call g_emit_u32; test eax,eax; jnz .gepxlm_bad
    xor eax,eax; jmp .gepxlm_done
.gepxlm_bad:
    mov eax,1
.gepxlm_done:
    pop r13; pop r12; pop rbx; ret

# VEX/EVEX.128 scalar arithmetic with an immutable RIP-relative memory source.
# edi=opcode (58 add, 5c sub, 59 mul, 5e div, 5d min, 5f max),
# esi=dst, edx=src1, rcx=compile-time address of immutable scalar bits or 0
# during a discarded proof emission, r8d=GTYPE_F32/F64.  This is the same
# arithmetic authority as g_emit_phys_vex_scalar3; only the physical operand
# form differs.  No reassociation, contraction, or ConstantFact-specific
# arithmetic path exists here.
g_emit_phys_vex_scalar3_mem:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12d,esi; mov r13d,edx; mov r14,rcx; mov r15d,r8d
    cmp r12d,31; ja .gepv3m_bad
    cmp r13d,31; ja .gepv3m_bad
    cmp r15d,GTYPE_F64; je .gepv3m_type_ok
    cmp r15d,GTYPE_F32; jne .gepv3m_bad
.gepv3m_type_ok:
    cmp r12d,15; ja .gepv3m_evex
    cmp r13d,15; ja .gepv3m_evex
    mov edi,0xC4; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    # VEX byte 2: ~R, memory X/B=1, map=0F(1).
    mov eax,r12d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x60
    or eax,1
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    # VEX byte 3: W=0, inverted src1, scalar F2/F3 prefix.
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3
    cmp r15d,GTYPE_F64; jne 761f
    or eax,3
    jmp 762f
761:or eax,2
762:mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    mov eax,r12d; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    jmp .gepv3m_disp
.gepv3m_evex:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    # P0: ~R, memory X/B=1, ~R', map=0F(1).
    mov eax,1
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    or eax,0x60
    mov ecx,r12d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    # P1/P2 match the register form; only ModRM changes to RIP-relative memory.
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3; or eax,4
    cmp r15d,GTYPE_F64; jne 763f
    or eax,0x83
    jmp 764f
763:or eax,2
764:mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    mov eax,r13d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
    mov eax,r12d; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3m_bad
.gepv3m_disp:
    G_EMIT_POSITION rbx
    xor edi,edi; call g_emit_u32; test eax,eax; jnz .gepv3m_bad
    test r14,r14; jz .gepv3m_ok
    mov rdi,rbx; mov rsi,r14; call g_patch_rel32
.gepv3m_ok:
    xor eax,eax; jmp .gepv3m_done
.gepv3m_bad:
    mov eax,1
.gepv3m_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# VEX/EVEX.128 bitwise register realization over ordinary XMM carriers.
# edi=opcode (54 and, 57 xor), esi=dst, edx=src1, ecx=src2.
# The operation is deliberately type-neutral: sign ValueFacts transform bits,
# not arithmetic precision.  pp=00/W=0 therefore serves f32 and f64 alike.
g_emit_phys_vex_bits3:
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12d,esi; mov r13d,edx; mov r14d,ecx
    cmp r12d,31; ja .gepvb3_bad
    cmp r13d,31; ja .gepvb3_bad
    cmp r14d,31; ja .gepvb3_bad
    cmp r12d,15; ja .gepvb3_evex
    cmp r13d,15; ja .gepvb3_evex
    cmp r14d,15; ja .gepvb3_evex
    mov edi,0xC4; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    # VEX byte 2: ~R ~X ~B 00001 (0F map).
    mov eax,r12d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r14d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    or eax,1
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    # VEX byte 3: W=0, inverted src1, L=0, pp=00.
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r14d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    xor eax,eax; jmp .gepvb3_done
.gepvb3_evex:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    # P0: ~R ~X ~B ~R' 00 01 (0F map).
    mov eax,1
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,r14d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,r14d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,r12d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    # P1: W=0, inverted src1 low nibble, fixed bit2, pp=00.
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3; or eax,4
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    # P2: VL=128, no mask/broadcast; V' extends src1 bit4.
    mov eax,r13d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r14d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepvb3_bad
    xor eax,eax; jmp .gepvb3_done
.gepvb3_bad:
    mov eax,1
.gepvb3_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# Existing scalar physical carrier, native hardware square root.  This is one
# more realization of an ordinary FP ValueFact, not a math runtime call.
# edi=dst/src XMM, esi=GTYPE_F32/F64 -> eax 0/1.
g_emit_phys_sqrt_inplace:
    mov r8d,esi
    mov esi,edi; mov edx,edi; mov ecx,edi; mov edi,0x51
    jmp g_emit_phys_vex_scalar3

# Existing scalar physical carrier, square in-place.  This is multiplication of
# one ValueFact by itself, represented once so shared subtrees survive canonical
# serialization instead of being duplicated. edi=dst/src XMM, esi=FP type.
g_emit_phys_square_inplace:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp r12d,GTYPE_F32; je .gepsqi_emit
    cmp r12d,GTYPE_F64; jne .gepsqi_bad
.gepsqi_emit:
    mov edi,0x59; mov esi,ebx; mov edx,ebx; mov ecx,ebx; mov r8d,r12d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gepsqi_bad
    xor eax,eax; jmp .gepsqi_done
.gepsqi_bad: mov eax,1
.gepsqi_done: pop r12; pop rbx; ret

# Existing scalar physical carrier, truncate toward zero in-place.  This is the
# old ValueFact carrier path extended with one native rounding primitive; there is
# no math runtime, helper call, or precision side channel.
g_emit_phys_trunc_inplace:
    mov r8d,esi
    mov esi,edi; mov edx,edi; mov ecx,edi
    mov edi,0x70a
    cmp r8d,GTYPE_F64; je 1f
    cmp r8d,GTYPE_F32; jne .gepti_bad
    jmp 2f
1:  inc edi
2:  cmp esi,15; jbe 3f
    or edi,0x8000
    cmp r8d,GTYPE_F64; jne 3f
    or edi,0x1000
3:  call g_emit_phys_rrr_descriptor
    test eax,eax; jnz .gepti_bad
    mov edi,3; jmp g_emit_u8
.gepti_bad: mov eax,1; ret

# Unary sign ValueFacts stay inside the scalar Physical DAG.  Runtime RAX is an
# existing transient bit carrier for scalar FP materialization, so neg/abs need no
# second evaluator, helper ABI, or workload route. edi=dst/src XMM, esi=FP type,
# edx=0 neg / 1 abs -> eax 0/1.
g_emit_phys_fp_sign_inplace:
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp r13d,1; ja .gepfsi_bad
    cmp r12d,GTYPE_F64; je .gepfsi_mask_f64
    cmp r12d,GTYPE_F32; jne .gepfsi_bad
    test r13d,r13d; jnz .gepfsi_f32_abs_mask
    mov r14d,0x80000000
    jmp .gepfsi_mask_ready
.gepfsi_f32_abs_mask:
    mov r14d,0x7fffffff
    jmp .gepfsi_mask_ready
.gepfsi_mask_f64:
    mov r14,0x8000000000000000
    test r13d,r13d; jz .gepfsi_mask_ready
    mov r14,0x7fffffffffffffff
.gepfsi_mask_ready:
    # Sign masks are ordinary ConstantFacts.  Profiling notes their static use;
    # final emission consumes the same resident constant authority as literals.
    cmp dword ptr [rip+g_phys_const_collect],1; jne .gepfsi_find_mask
    mov rdi,r14; mov esi,r12d; call g_phys_const_note
.gepfsi_find_mask:
    mov rdi,r14; mov esi,r12d; call g_phys_const_find_resident
    cmp eax,0; jl .gepfsi_scalar_bits
    mov rcx,qword ptr [rip+g_phys_const_resident_reg_ptr]
    mov ecx,dword ptr [rcx+rax*4]
    mov edi,0x57
    test r13d,r13d; jz .gepfsi_emit_bits
    mov edi,0x54
.gepfsi_emit_bits:
    mov esi,ebx; mov edx,ebx; call g_emit_phys_vex_bits3
    test eax,eax; jnz .gepfsi_bad
    xor eax,eax; jmp .gepfsi_done
.gepfsi_scalar_bits:
    # Carrier pressure may make the mask nonresident.  Stay inside the same
    # Physical DAG and use the existing transient bit carrier rather than
    # falling back to a second evaluator.
    mov edi,ebx; mov esi,r12d; call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gepfsi_bad
    cmp r12d,GTYPE_F64; je .gepfsi_f64_scalar
    test r13d,r13d; jnz .gepfsi_f32_abs_scalar
    mov edi,0x35; call g_emit_u8; test eax,eax; jnz .gepfsi_bad
    mov edi,0x80000000; call g_emit_u32; test eax,eax; jnz .gepfsi_bad
    jmp .gepfsi_store
.gepfsi_f32_abs_scalar:
    mov edi,0x25; call g_emit_u8; test eax,eax; jnz .gepfsi_bad
    mov edi,0x7fffffff; call g_emit_u32; test eax,eax; jnz .gepfsi_bad
    jmp .gepfsi_store
.gepfsi_f64_scalar:
    mov edi,0x48; call g_emit_u8; test eax,eax; jnz .gepfsi_bad
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepfsi_bad
    mov edi,0xBA; call g_emit_u8; test eax,eax; jnz .gepfsi_bad
    mov edi,0xF8
    test r13d,r13d; jz 764f
    mov edi,0xF0
764:call g_emit_u8; test eax,eax; jnz .gepfsi_bad
    mov edi,63; call g_emit_u8; test eax,eax; jnz .gepfsi_bad
.gepfsi_store:
    mov edi,ebx; mov esi,r12d; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gepfsi_bad
    xor eax,eax; jmp .gepfsi_done
.gepfsi_bad:
    mov eax,1
.gepfsi_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# edi=dst/src XMM, esi=source GTYPE_F32/F64, edx=target GTYPE_F32/F64.
# Precision conversion is an edge realization, never a subtree policy: a ValueFact
# is first realized at its natural precision and only converted when the consumer
# actually meets a lower/higher precision fact. In-place conversion is safe only
# on a caller-owned destination/temporary, never on a borrowed resident authority.
g_emit_phys_fp_convert_inplace:
    cmp esi,edx; je .gepfc_ok
    cmp esi,GTYPE_F32; je 1f
    cmp esi,GTYPE_F64; jne .gepfc_bad
    cmp edx,GTYPE_F32; jne .gepfc_bad
    jmp 2f
1:  cmp edx,GTYPE_F64; jne .gepfc_bad
2:  mov r8d,esi
    mov esi,edi; mov edx,edi; mov ecx,edi; mov edi,0x5A
    jmp g_emit_phys_vex_scalar3
.gepfc_ok: xor eax,eax; ret
.gepfc_bad: mov eax,1; ret

# ---------------- unified physical predicate realization ----------------
# Predicates are ordinary Physical-DAG values.  They are materialized in RAX
# only for the lifetime of the consuming control edge; compare operands remain
# in their existing GPR/XMM carrier domains.  No source/workload matcher exists.

# edi=setcc opcode byte -> generated RAX=0/1.
g_emit_phys_setcc_rax:
    push rbx
    mov ebx,edi
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepsr_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepsr_bad
    mov edi,0xC0; call g_emit_u8; test eax,eax; jnz .gepsr_bad
.gepsr_normalize:
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepsr_bad
    mov edi,0xB6; call g_emit_u8; test eax,eax; jnz .gepsr_bad
    mov edi,0xC0; call g_emit_u8; test eax,eax; jnz .gepsr_bad
    xor eax,eax; jmp .gepsr_done
.gepsr_bad:
    mov eax,1
.gepsr_done:
    pop rbx; ret

# Same scalar PredicateFact fragment for every floating carrier and width.
g_emit_phys_fp_setcc_rax:
    push rbx
    call physical_fp_setcc_fragment
    test rax,rax; jz .gepsr_bad
    mov rdi,rax; mov esi,ecx; call g_emit_bytes
    test eax,eax; jnz .gepsr_bad
    jmp .gepsr_normalize

# edi=lhs XMM, esi=rhs XMM, edx=GTYPE_F32/F64. Emit flags for lhs ? rhs.
# VEX3 covers XMM0..15 on every AVX target; EVEX is used only when the existing
# compiler-wide wide-register-file capability already admitted XMM16..31.
g_emit_phys_fp_cmp_flags:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp ebx,31; ja .gepfcf_bad
    cmp r12d,31; ja .gepfcf_bad
    cmp r13d,GTYPE_F64; je .gepfcf_type_ok
    cmp r13d,GTYPE_F32; jne .gepfcf_bad
.gepfcf_type_ok:
    mov eax,ebx; or eax,r12d; cmp eax,15; ja .gepfcf_evex
    # C4 RXB m-mmmm, WvvvvLpp, 2E /r.  X is unused and therefore inverted 1.
    mov edi,0xC4; call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    mov eax,0x41
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    mov edi,0x78
    cmp r13d,GTYPE_F64; jne 7411f
    mov edi,0x79
7411:call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    jmp .gepfcf_opcode
.gepfcf_evex:
    test dword ptr [rip+isa_cap_bits],ISA_CAP_WIDE_REGFILE
    jz .gepfcf_bad
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    mov eax,1
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,r12d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    mov edi,0x7C
    cmp r13d,GTYPE_F64; jne 7412f
    mov edi,0xFD
7412:call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    mov edi,0x08; call g_emit_u8; test eax,eax; jnz .gepfcf_bad
.gepfcf_opcode:
    mov edi,0x2E; call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepfcf_bad
    xor eax,eax; jmp .gepfcf_done
.gepfcf_bad:
    mov eax,1
.gepfcf_done:
    pop r13; pop r12; pop rbx; ret

# One typed floating compare relation for FLAGS and BOOL value consumers.
# rdi=left, rsi=right, edx=consumer FP type, rcx=operator string node.
# Return RAX=canonical operator span (zero on failure), ECX=span length.
# Operands retain their original evaluation order. Only resident carrier order
# is exchanged: a<b becomes b>a, a<=b becomes b>=a. Ordered greater relations
# include IEEE unordered rejection in one ISA condition; no extra parity edge.
g_emit_phys_fp_compare_relation:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,40
    mov r12,rdi; mov r13,rsi; mov ebx,edx
    mov r14,[rcx+8]; mov r15,[rcx+16]
    mov dword ptr [rsp+8],0; mov dword ptr [rsp+12],0
    mov dword ptr [rsp+32],0
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq
    test eax,eax; jnz .gepfcr_greater
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq
    test eax,eax; jz .gepfcr_left
    lea r14,[rip+gv_ge]; mov r15d,gv_ge_end-gv_ge
    jmp .gepfcr_swap
.gepfcr_greater:
    lea r14,[rip+gv_gt]; mov r15d,gv_gt_end-gv_gt
.gepfcr_swap:
    mov dword ptr [rsp+32],1
.gepfcr_left:
    mov rdi,r12; mov esi,ebx; call g_phys_fp_direct_source
    test eax,eax; jz .gepfcr_left_temp
    mov [rsp],edx; jmp .gepfcr_right
.gepfcr_left_temp:
    call g_phys_fp_temp_alloc; test eax,eax; js .gepfcr_bad
    mov [rsp],eax; mov dword ptr [rsp+8],1
    mov rdi,r12; mov esi,eax; mov edx,ebx; call g_emit_phys_fp_value_to
    cmp eax,ebx; jne .gepfcr_bad
.gepfcr_right:
    mov rdi,r13; mov esi,ebx; call g_phys_fp_direct_source
    test eax,eax; jz .gepfcr_right_temp
    mov [rsp+4],edx; jmp .gepfcr_compare
.gepfcr_right_temp:
    call g_phys_fp_temp_alloc; test eax,eax; js .gepfcr_bad
    mov [rsp+4],eax; mov dword ptr [rsp+12],1
    mov rdi,r13; mov esi,eax; mov edx,ebx; call g_emit_phys_fp_value_to
    cmp eax,ebx; jne .gepfcr_bad
.gepfcr_compare:
    mov edi,[rsp]; mov esi,[rsp+4]; mov edx,ebx
    cmp dword ptr [rsp+32],0; je .gepfcr_flags
    xchg edi,esi
.gepfcr_flags:
    call g_emit_phys_fp_cmp_flags; test eax,eax; jnz .gepfcr_bad
    mov [rsp+16],r14; mov [rsp+24],r15
    jmp .gepfcr_release
.gepfcr_bad:
    mov qword ptr [rsp+16],0; mov qword ptr [rsp+24],0
.gepfcr_release:
    cmp dword ptr [rsp+12],0; je .gepfcr_release_left
    mov edi,[rsp+4]; call g_phys_fp_temp_free
.gepfcr_release_left:
    cmp dword ptr [rsp+8],0; je .gepfcr_return
    mov edi,[rsp]; call g_phys_fp_temp_free
.gepfcr_return:
    mov rax,[rsp+16]; mov ecx,[rsp+24]
    add rsp,40; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=operator span, rsi=len, edx=numeric comparison type -> generated RAX=0/1.
# Flags must already describe lhs-rhs.
g_emit_phys_cmp_result_rax:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; mov r13d,edx
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq
    test eax,eax; jnz .gepcr_eq
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq
    test eax,eax; jnz .gepcr_ne
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq
    test eax,eax; jnz .gepcr_lt
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq
    test eax,eax; jnz .gepcr_le
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq
    test eax,eax; jnz .gepcr_gt
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq
    test eax,eax; jnz .gepcr_ge
    jmp .gepcr_bad
.gepcr_eq: mov edi,0x94; jmp .gepcr_emit
.gepcr_ne: mov edi,0x95; jmp .gepcr_emit
.gepcr_lt:
    mov edi,0x92
    cmp r13d,GTYPE_I64; jne .gepcr_emit
    mov edi,0x9C; jmp .gepcr_emit
.gepcr_le:
    mov edi,0x96
    cmp r13d,GTYPE_I64; jne .gepcr_emit
    mov edi,0x9E; jmp .gepcr_emit
.gepcr_gt:
    mov edi,0x97
    cmp r13d,GTYPE_I64; jne .gepcr_emit
    mov edi,0x9F; jmp .gepcr_emit
.gepcr_ge:
    mov edi,0x93
    cmp r13d,GTYPE_I64; jne .gepcr_emit
    mov edi,0x9D
.gepcr_emit:
    cmp r13d,GTYPE_F32; je .gepcr_fp
    cmp r13d,GTYPE_F64; je .gepcr_fp
    call g_emit_phys_setcc_rax
    jmp .gepcr_done
.gepcr_fp:
    call g_emit_phys_fp_setcc_rax
    jmp .gepcr_done
.gepcr_bad:
    mov eax,1
.gepcr_done:
    pop r13; pop r12; pop rbx; ret

# rdi=op span, rsi=len, edx=type, r8d=branch truth -> RAX patch chain.
# IEEE unordered truth is consumed as a parity edge, without a 0/1 carrier.
g_emit_phys_cmp_branch_patch:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13d,edx; mov r14d,r8d
    xor r15d,r15d
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq
    test eax,eax; jnz .gepcbp_eq
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq
    test eax,eax; jnz .gepcbp_ne
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq
    test eax,eax; jnz .gepcbp_lt
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq
    test eax,eax; jnz .gepcbp_le
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq
    test eax,eax; jnz .gepcbp_gt
    mov rdi,rbx; mov rsi,r12; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq
    test eax,eax; jz .gepcbp_bad
    mov ebx,0x82; cmp r13d,GTYPE_I64; jne .gepcbp_emit
    mov ebx,0x8C; jmp .gepcbp_emit
.gepcbp_eq: mov ebx,0x85; mov r15d,1; jmp .gepcbp_emit
.gepcbp_ne: mov ebx,0x84; mov r15d,2; jmp .gepcbp_emit
.gepcbp_lt:
    mov ebx,0x83; mov r15d,1; cmp r13d,GTYPE_I64; jne .gepcbp_emit
    mov ebx,0x8D; jmp .gepcbp_emit
.gepcbp_le:
    mov ebx,0x87; mov r15d,1; cmp r13d,GTYPE_I64; jne .gepcbp_emit
    mov ebx,0x8F; jmp .gepcbp_emit
.gepcbp_gt:
    mov ebx,0x86; cmp r13d,GTYPE_I64; jne .gepcbp_emit
    mov ebx,0x8E
.gepcbp_emit:
    xor ebx,r14d
    cmp r13d,GTYPE_F32; je .gepcbp_fp
    cmp r13d,GTYPE_F64; jne .gepcbp_single
.gepcbp_fp:
    test r15d,r15d; jz .gepcbp_single
    # eq/lt/le are false unordered; ne is true unordered.
    dec r15d
    xor r15d,r14d
    mov edi,0x8A; call g_emit_jcc_patch_byte
    test rax,rax; jz .gepcbp_bad
    mov r12,rax
    mov edi,ebx; call g_emit_jcc_patch_byte
    test rax,rax; jz .gepcbp_bad
    test r15d,r15d; jnz .gepcbp_skip_unordered
    mov rdx,r12; sub rdx,rax; mov [rax],edx
    jmp .gepcbp_done
.gepcbp_skip_unordered:
    mov r13,rax
    mov rdi,r12; G_EMIT_POSITION rsi; call g_patch_rel32
    mov rax,r13; jmp .gepcbp_done
.gepcbp_single:
    mov edi,ebx; call g_emit_jcc_patch_byte; jmp .gepcbp_done
.gepcbp_bad: xor eax,eax
.gepcbp_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Compiler-only chain links occupy unresolved rel32 fields and disappear when
# their single consumer publishes the continuation. No runtime table survives.
g_phys_patch_chain:
    push rbx; push r12
    mov r12,rsi
.gpredchain_next:
    cmp rdi,-1; je .gpredchain_done
    test rdi,rdi; jz .gpredchain_done
    movsxd rbx,dword ptr [rdi]
    test rbx,rbx; jz .gpredchain_last
    add rbx,rdi
.gpredchain_last:
    mov rsi,r12; call g_patch_rel32
    mov rdi,rbx; jmp .gpredchain_next
.gpredchain_done: pop r12; pop rbx; ret

# rdi=head address, rsi=new chain. Append without creating a second fact table.
g_phys_chain_append:
    cmp rsi,-1; je .gpredappend_done
    test rsi,rsi; jz .gpredappend_done
    mov rax,rsi
.gpredappend_next:
    movsxd rdx,dword ptr [rax]
    test rdx,rdx; jz .gpredappend_tail
    add rax,rdx; jmp .gpredappend_next
.gpredappend_tail:
    mov rdx,[rdi]; test rdx,rdx; jz .gpredappend_head
    sub rdx,rax; mov [rax],edx
.gpredappend_head: mov [rdi],rsi
.gpredappend_done: ret

# edi=resident BOOL XMM (0..15). Emit VPTEST xmm,xmm so a control consumer
# reads the PredicateFact in its existing physical carrier without converting
# it through RAX. VPTEST has no EVEX form; wider carriers use the ordinary
# value extraction path below rather than introducing a second predicate ABI.
g_emit_phys_xmm_bool_test:
    push rbx
    mov ebx,edi
    cmp ebx,15; ja .gepxbt_bad
    mov edi,0xC4; call g_emit_u8; test eax,eax; jnz .gepxbt_bad
    # VEX3 byte2: ~R,~X=1,~B,map=0F38. reg and r/m are the same carrier.
    mov eax,0x42
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7
    and eax,0x7F; or eax,ecx
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    and eax,0xDF; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxbt_bad
    mov edi,0x79; call g_emit_u8; test eax,eax; jnz .gepxbt_bad
    mov edi,0x17; call g_emit_u8; test eax,eax; jnz .gepxbt_bad
    mov eax,ebx; and eax,7; mov ecx,eax; shl eax,3; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxbt_bad
    xor eax,eax; jmp .gepxbt_done
.gepxbt_bad:
    mov eax,1
.gepxbt_done:
    pop rbx; ret

# edi=resident BOOL CSE index -> near JZ patch in RAX, or 0 on failure.
# A Guarded Region and a scalar select consume the same PredicateFact authority.
g_emit_phys_resident_bool_jz_index:
    push rbx
    mov ebx,edi
    cmp ebx,0; jl .geprbji_bad
    cmp ebx,dword ptr [rip+g_phys_cse_resident_count]; jae .geprbji_bad
    mov rcx,qword ptr [rip+g_phys_cse_resident_type_ptr]
    cmp dword ptr [rcx+rbx*4],GTYPE_BOOL; jne .geprbji_bad
    mov rcx,qword ptr [rip+g_phys_cse_resident_reg_ptr]
    mov edi,dword ptr [rcx+rbx*4]
    test edi,edi; js .geprbji_control
    cmp edi,15; ja .geprbji_extract
    call g_emit_phys_xmm_bool_test
    test eax,eax; jnz .geprbji_bad
    call g_emit_jz_patch
    jmp .geprbji_done
.geprbji_extract:
    mov esi,GTYPE_F64
    call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .geprbji_bad
    lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    test eax,eax; jnz .geprbji_bad
    call g_emit_jz_patch
    jmp .geprbji_done
.geprbji_bad:
    xor eax,eax
    jmp .geprbji_done
.geprbji_control:
    # A control-only fact owns a continuation, not an observable 0/1 value.
    # Its children still consume the same already-produced shared facts.
    call g_phys_temp_reset
    mov rax,[rip+g_phys_cse_resident_expr_ptr]
    mov rdi,[rax+rbx*8]
    call g_emit_phys_bool_jz_patch
.geprbji_done:
    pop rbx; ret

# rdi=BOOL expr, rsi=true chain address, rdx=false chain address,
# ecx=fallthrough truth. The same lazy graph serves control and value consumers.
g_emit_phys_predicate_edges:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,48
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov ebx,ecx
    mov qword ptr [rsp],0
    mov qword ptr [rsp+8],0
    cmp qword ptr [r12],J_OBJECT; jne .geppe_bad
.geppe_identity:
    mov rdi,r12; mov esi,GTYPE_BOOL; call g_semantic_identity_operand
    test rax,rax; jz .geppe_source
    mov r12,rax; jmp .geppe_identity
.geppe_source:
    mov rdi,r12; mov esi,GTYPE_BOOL; call g_phys_cse_demand_resident
    mov rdi,r12; mov esi,GTYPE_BOOL; call g_phys_cse_find_resident
    cmp eax,0; jge .geppe_leaf
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .geppe_op
    cmp qword ptr [rax],J_TRUE; je .geppe_true
    cmp qword ptr [rax],J_FALSE; jne .geppe_bad
    xor eax,eax; jmp .geppe_literal
.geppe_true: mov eax,1
.geppe_literal:
    cmp eax,ebx; je .geppe_ok
    mov r15,r14; test eax,eax; jz .geppe_literal_emit
    mov r15,r13
.geppe_literal_emit:
    call g_emit_jmp_patch; test rax,rax; jz .geppe_bad
    mov rdi,r15; mov rsi,rax; call g_phys_chain_append; jmp .geppe_ok
.geppe_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .geppe_leaf
    mov r15,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .geppe_leaf
    mov rax,[rax+24]; mov [rsp+16],rax; test rax,rax; jz .geppe_bad
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq
    test eax,eax; jnz .geppe_not
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq
    test eax,eax; jnz .geppe_and
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq
    test eax,eax; jnz .geppe_or
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jnz .geppe_select
.geppe_leaf:
    mov esi,ebx; xor esi,1; mov rdi,r12; call g_emit_phys_bool_leaf_patch
    test rax,rax; jz .geppe_bad
    mov rdi,r14; test ebx,ebx; jnz .geppe_leaf_append
    mov rdi,r13
.geppe_leaf_append:
    mov rsi,rax; call g_phys_chain_append; jmp .geppe_ok
.geppe_not:
    mov rdi,[rsp+16]; cmp qword ptr [rdi+32],0; jne .geppe_bad
    mov rsi,r14; mov rdx,r13; mov ecx,ebx; xor ecx,1
    call g_emit_phys_predicate_edges; jmp .geppe_done
.geppe_and:
    mov rdi,[rsp+16]; mov rax,[rdi+32]; test rax,rax; jz .geppe_bad
    cmp qword ptr [rax+32],0; jne .geppe_bad
    mov [rsp+24],rax
    lea rsi,[rsp]; mov rdx,r14; mov ecx,1
    call g_emit_phys_predicate_edges; test eax,eax; jnz .geppe_bad
    mov rdi,[rsp]; G_EMIT_POSITION rsi; call g_phys_patch_chain
    jmp .geppe_tail
.geppe_or:
    mov rdi,[rsp+16]; mov rax,[rdi+32]; test rax,rax; jz .geppe_bad
    cmp qword ptr [rax+32],0; jne .geppe_bad
    mov [rsp+24],rax
    mov rsi,r13; lea rdx,[rsp]; xor ecx,ecx
    call g_emit_phys_predicate_edges; test eax,eax; jnz .geppe_bad
    mov rdi,[rsp]; G_EMIT_POSITION rsi; call g_phys_patch_chain
.geppe_tail:
    mov rdi,[rsp+24]; mov rsi,r13; mov rdx,r14; mov ecx,ebx
    inc dword ptr [rip+g_packet_fact_scope]
    call g_emit_phys_predicate_edges
    dec dword ptr [rip+g_packet_fact_scope]; jmp .geppe_done
.geppe_select:
    mov rdi,[rsp+16]; mov rax,[rdi+32]; test rax,rax; jz .geppe_bad
    mov [rsp+24],rax
    mov rax,[rax+32]; test rax,rax; jz .geppe_bad
    cmp qword ptr [rax+32],0; jne .geppe_bad
    mov [rsp+32],rax
    # A constant arm already is a continuation; bind it without a value or jump.
    mov rdi,rax; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .geppe_select_general
    cmp qword ptr [rax],J_TRUE; je .geppe_select_false_true
    cmp qword ptr [rax],J_FALSE; jne .geppe_bad
    mov rdi,[rsp+16]; lea rsi,[rsp]; mov rdx,r14; mov ecx,1
    jmp .geppe_select_constant_cond
.geppe_select_false_true:
    mov rdi,[rsp+16]; lea rsi,[rsp]; mov rdx,r13; mov ecx,1
.geppe_select_constant_cond:
    call g_emit_phys_predicate_edges; test eax,eax; jnz .geppe_bad
    mov rdi,[rsp]; G_EMIT_POSITION rsi; call g_phys_patch_chain
    jmp .geppe_tail
.geppe_select_general:
    mov rdi,[rsp+16]; lea rsi,[rsp]; lea rdx,[rsp+8]; mov ecx,1
    call g_emit_phys_predicate_edges; test eax,eax; jnz .geppe_bad
    mov rdi,[rsp]; G_EMIT_POSITION rsi; call g_phys_patch_chain
    mov rdi,[rsp+24]; mov rsi,r13; mov rdx,r14; mov ecx,ebx
    inc dword ptr [rip+g_packet_fact_scope]
    call g_emit_phys_predicate_edges
    dec dword ptr [rip+g_packet_fact_scope]; test eax,eax; jnz .geppe_bad
    call g_emit_jmp_patch; test rax,rax; jz .geppe_bad
    mov rdi,r14; test ebx,ebx; jz .geppe_select_merge
    mov rdi,r13
.geppe_select_merge:
    mov rsi,rax; call g_phys_chain_append
    mov rdi,[rsp+8]; G_EMIT_POSITION rsi; call g_phys_patch_chain
    mov rdi,[rsp+32]; mov rsi,r13; mov rdx,r14; mov ecx,ebx
    inc dword ptr [rip+g_packet_fact_scope]
    call g_emit_phys_predicate_edges
    dec dword ptr [rip+g_packet_fact_scope]; jmp .geppe_done
.geppe_ok: xor eax,eax; jmp .geppe_done
.geppe_bad: mov eax,1
.geppe_done:
    add rsp,48
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Existing consumers own one false continuation; true falls through in place.
g_emit_phys_bool_jz_patch:
    sub rsp,24
    mov qword ptr [rsp],0; mov qword ptr [rsp+8],0
    lea rsi,[rsp]; lea rdx,[rsp+8]; mov ecx,1
    call g_emit_phys_predicate_edges; test eax,eax; jnz .gepbw_bad
    mov rdi,[rsp]; G_EMIT_POSITION rsi; call g_phys_patch_chain
    mov rax,[rsp+8]; test rax,rax; jnz .gepbw_done
    # Empty continuation is a compile-time success token, never emitted code.
    mov rax,-1; jmp .gepbw_done
.gepbw_bad: xor eax,eax
.gepbw_done: add rsp,24; ret

g_emit_phys_bool_leaf_patch:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,48
    mov r12,rdi
    mov dword ptr [rsp+32],esi
    mov rdi,r12; mov esi,GTYPE_BOOL; call g_phys_cse_demand_resident
    mov rdi,r12; mov esi,GTYPE_BOOL; call g_phys_cse_find_resident
    cmp eax,0; jl .gepbjp_uncached
    mov edi,eax
    call g_emit_phys_resident_bool_jz_index
    test rax,rax; jz .gepbjp_bad
    mov edx,dword ptr [rsp+32]; xor byte ptr [rax-1],dl
    jmp .gepbjp_done
.gepbjp_uncached:
    cmp qword ptr [r12],J_OBJECT; jne .gepbjp_value_form
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gepbjp_value_form
    mov r13,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_compare_op
    test eax,eax; jz .gepbjp_value_form
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gepbjp_bad
    mov r14,[rax+24]; test r14,r14; jz .gepbjp_bad
    mov r15,[r14+32]; test r15,r15; jz .gepbjp_bad
    cmp qword ptr [r15+32],0; jne .gepbjp_bad
    mov rdi,r14; call g_infer_expr; mov ebx,eax; test ebx,ebx; jz .gepbjp_bad
    mov rdi,r15; call g_infer_expr; mov dword ptr [rsp+16],eax; test eax,eax; jz .gepbjp_bad
    mov eax,ebx; mov edx,dword ptr [rsp+16]; call g_low_type
    mov dword ptr [rsp+20],eax
    cmp eax,GTYPE_U64; je .gepbjp_int
    cmp eax,GTYPE_I64; je .gepbjp_int
    cmp eax,GTYPE_F32; je .gepbjp_fp
    cmp eax,GTYPE_F64; je .gepbjp_fp
    jmp .gepbjp_value_form

.gepbjp_int:
    cmp ebx,dword ptr [rsp+20]; jne .gepbjp_value_form
    cmp dword ptr [rsp+16],ebx; jne .gepbjp_value_form
    mov dword ptr [rsp+8],0
    # Prefer the exact immediate operand geometry when available.
    mov rdi,r15; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gepbjp_int_regs
    mov [rsp+24],rax
    mov rdi,r15; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gepbjp_int_regs
    mov rdi,rax; call g_type_from_node; cmp eax,ebx; jne .gepbjp_int_regs
    cmp ebx,GTYPE_U64; je .gepbjp_int_lit_u
    mov rdi,[rsp+24]; call g_parse_i64_node; test edx,edx; jnz .gepbjp_int_regs
    jmp .gepbjp_int_lit_exact
.gepbjp_int_lit_u:
    mov rax,[rsp+24]; call node_parse_u64; test edx,edx; jnz .gepbjp_int_regs
.gepbjp_int_lit_exact:
    movsxd rcx,eax
    cmp rcx,rax; jne .gepbjp_int_regs
    mov dword ptr [rsp+28],eax
    mov rdi,r14; mov esi,ebx; call g_phys_int_direct_source
    test eax,eax; jz .gepbjp_int_lit_temp
    mov dword ptr [rsp+24],edx
    jmp .gepbjp_int_lit_cmp
.gepbjp_int_lit_temp:
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepbjp_bad
    mov dword ptr [rsp+24],eax; mov dword ptr [rsp+8],1
    mov rdi,r14; mov esi,eax; mov edx,ebx; call g_emit_phys_int_expr_to
    cmp eax,ebx; jne .gepbjp_int_lit_free_bad
.gepbjp_int_lit_cmp:
    mov edi,dword ptr [rsp+24]; mov esi,dword ptr [rsp+28]; call g_emit_phys_gpr_cmp_imm32
    test eax,eax; jnz .gepbjp_int_lit_free_bad
    mov rdi,[r13+8]; mov rsi,[r13+16]; mov edx,ebx; mov r8d,dword ptr [rsp+32]; call g_emit_phys_cmp_branch_patch
    mov rbx,rax
    cmp dword ptr [rsp+8],1; jne .gepbjp_int_lit_ret
    mov edi,dword ptr [rsp+24]; call g_phys_int_temp_free
.gepbjp_int_lit_ret:
    mov rax,rbx; jmp .gepbjp_done
.gepbjp_int_lit_free_bad:
    cmp dword ptr [rsp+8],1; jne .gepbjp_bad
    mov edi,dword ptr [rsp+24]; call g_phys_int_temp_free
    jmp .gepbjp_bad

.gepbjp_int_regs:
    mov rdi,r14; mov rsi,r15; mov edx,ebx; call g_emit_phys_int_compare_flags
    test eax,eax; jnz .gepbjp_bad
    mov rdi,[r13+8]; mov rsi,[r13+16]; mov edx,ebx; mov r8d,dword ptr [rsp+32]; call g_emit_phys_cmp_branch_patch
    jmp .gepbjp_done

.gepbjp_fp:
    cmp ebx,GTYPE_F32; je 7441f
    cmp ebx,GTYPE_F64; jne .gepbjp_value_form
7441:cmp dword ptr [rsp+16],GTYPE_F32; je 7442f
    cmp dword ptr [rsp+16],GTYPE_F64; jne .gepbjp_value_form
7442:
    mov rdi,r14; mov rsi,r15; mov edx,dword ptr [rsp+20]; mov rcx,r13
    call g_emit_phys_fp_compare_relation
    test rax,rax; jz .gepbjp_bad
    mov rdi,rax; mov esi,ecx; mov edx,dword ptr [rsp+20]
    mov r8d,dword ptr [rsp+32]; call g_emit_phys_cmp_branch_patch
    jmp .gepbjp_done

.gepbjp_value_form:
    mov rdi,r12; call g_emit_phys_bool_expr_to_rax
    test eax,eax; jnz .gepbjp_bad
    lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    mov edi,0x84; xor edi,dword ptr [rsp+32]; call g_emit_jcc_patch_byte
    jmp .gepbjp_done
.gepbjp_bad:
    xor eax,eax
.gepbjp_done:
    add rsp,48
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=BOOL expression -> eax=0 success, generated runtime RAX=0/1.
# Value demand consumes the same lazy continuation graph. Resident predicates
# and semantic leaves retain their existing carrier authority.
g_emit_phys_bool_expr_to_rax:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi
    cmp qword ptr [r12],J_OBJECT; jne .gepbe_bad

    mov rdi,r12; mov esi,GTYPE_BOOL; call g_phys_cse_demand_resident
    # Episode-scoped PredicateFacts share the same Physical ValueFact authority
    # as repeated arithmetic.  BOOL payload bits live in an XMM carrier selected
    # by the existing whole-episode pressure model; consumers recover the exact
    # 0/1 representation without rebuilding the predicate DAG.
    mov rdi,r12; mov esi,GTYPE_BOOL; call g_phys_cse_find_resident
    cmp eax,0; jl .gepbe_uncached
    mov rcx,qword ptr [rip+g_phys_cse_resident_reg_ptr]
    mov edi,dword ptr [rcx+rax*4]
    mov esi,GTYPE_F64
    call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gepbe_bad
    xor eax,eax; jmp .gepbe_done
.gepbe_uncached:
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gepbe_var
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gepbe_bad
    cmp dword ptr [rax+16],GTYPE_BOOL; jne .gepbe_bad
    mov ebx,dword ptr [rax+24]
    mov rdi,r12; mov esi,GTYPE_BOOL; call g_phys_int_direct_source
    test eax,eax; jz .gepbe_state_spill
    xor edi,edi; mov esi,edx; call g_emit_phys_gpr_move
    jmp .gepbe_done
.gepbe_state_spill:
    mov eax,ebx; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    jmp .gepbe_done
.gepbe_var:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gepbe_literal
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gepbe_bad
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gepbe_bad
    cmp dword ptr [rax+20],GTYPE_BOOL; jne .gepbe_bad
    cmp dword ptr [rax+24],-1; je .gepbe_bad
    mov ebx,dword ptr [rax+16]
    mov eax,dword ptr [rax+24]
    cmp ebx,GK_INPUT; jne .gepbe_binding
    call g_input_slot_addr; jmp .gepbe_load
.gepbe_binding:
    call g_binding_slot_addr
.gepbe_load:
    mov rdi,rax; call g_emit_load_rax_abs; jmp .gepbe_done
.gepbe_literal:
    # Boolean literal.
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gepbe_op
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gepbe_bad
    mov rdi,rax; call g_type_from_node; cmp eax,GTYPE_BOOL; jne .gepbe_bad
    cmp qword ptr [r13],J_TRUE; je .gepbe_true
    cmp qword ptr [r13],J_FALSE; jne .gepbe_bad
    xor edi,edi; call g_emit_mov_rax_imm64; jmp .gepbe_done
.gepbe_true:
    mov edi,1; call g_emit_mov_rax_imm64; jmp .gepbe_done

.gepbe_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gepbe_bad
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gepbe_bad
    mov r14,[rax+24]; test r14,r14; jz .gepbe_bad

    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jnz .gepbe_control
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq
    test eax,eax; jnz .gepbe_not
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq
    test eax,eax; jnz .gepbe_control
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq
    test eax,eax; jnz .gepbe_control
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq
    test eax,eax; jnz .gepbe_xor
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_compare_op
    test eax,eax; jnz .gepbe_compare
    jmp .gepbe_bad

.gepbe_not:
    cmp qword ptr [r14+32],0; jne .gepbe_bad
    mov rdi,r14; call g_emit_phys_bool_expr_to_rax
    test eax,eax; jnz .gepbe_bad
    # The existing bool primitive owns normalized 0/1 inversion. Consume its
    # register relation directly; stack transport belongs only to stack users.
    lea rdi,[rip+gc_not_bool+1]
    mov esi,gc_not_bool_end-gc_not_bool-2
    call g_emit_bytes
    jmp .gepbe_done
.gepbe_control:
    mov rdi,r12; call g_emit_phys_bool_jz_patch
    test rax,rax; jz .gepbe_bad
    mov rbx,rax
    mov edi,1; call g_emit_mov_rax_imm64
    test eax,eax; jnz .gepbe_bad
    call g_emit_jmp_patch; mov [rsp+8],rax
    mov rdi,rbx; G_EMIT_POSITION rsi; call g_phys_patch_chain
    xor edi,edi; call g_emit_mov_rax_imm64
    test eax,eax; jnz .gepbe_bad
    mov rdi,[rsp+8]; G_EMIT_POSITION rsi; call g_patch_rel32
    xor eax,eax; jmp .gepbe_done

.gepbe_xor:
    mov r15,[r14+32]; test r15,r15; jz .gepbe_bad
    cmp qword ptr [r15+32],0; jne .gepbe_bad
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepbe_bad
    mov dword ptr [rsp+24],eax
    mov rdi,r14; call g_emit_phys_bool_expr_to_rax; test eax,eax; jnz .gepbe_xor_free
    mov edi,dword ptr [rsp+24]; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepbe_xor_free
    mov rdi,r15; call g_emit_phys_bool_expr_to_rax; test eax,eax; jnz .gepbe_xor_free
    mov edi,7; xor esi,esi; mov edx,dword ptr [rsp+24]; call g_emit_phys_gpr_bin2
    mov ebx,eax
    mov edi,dword ptr [rsp+24]; call g_phys_int_temp_free
    mov eax,ebx; jmp .gepbe_done
.gepbe_xor_free:
    mov edi,dword ptr [rsp+24]; call g_phys_int_temp_free
    jmp .gepbe_bad

.gepbe_compare:
    mov r15,[r14+32]; test r15,r15; jz .gepbe_bad
    cmp qword ptr [r15+32],0; jne .gepbe_bad
    mov rdi,r14; call g_infer_expr; mov ebx,eax; test ebx,ebx; jz .gepbe_bad
    mov rdi,r15; call g_infer_expr; mov dword ptr [rsp+16],eax; test eax,eax; jz .gepbe_bad
    mov eax,ebx; mov edx,dword ptr [rsp+16]; call g_low_type
    mov dword ptr [rsp+20],eax
    cmp eax,GTYPE_F64; je .gepbe_compare_fp
    cmp eax,GTYPE_F32; je .gepbe_compare_fp
    cmp eax,GTYPE_U64; je .gepbe_compare_int
    cmp eax,GTYPE_I64; je .gepbe_compare_int
    jmp .gepbe_bad

.gepbe_compare_int:
    # Integer compare stays in the GPR carrier pool. Mixed signedness is left to
    # the generic semantic path rather than inventing a second coercion regime.
    cmp ebx,dword ptr [rsp+20]; jne .gepbe_bad
    cmp dword ptr [rsp+16],ebx; jne .gepbe_bad

    # A literal comparison operand is consumed by CMP's own imm32 field when
    # its exact 64-bit value is that sign extension. This is one operand
    # geometry rule for every integer predicate, not a source-pattern route.
    mov rdi,r15; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gepbe_compare_int_regs
    mov [rsp+24],rax
    mov rdi,r15; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gepbe_compare_int_regs
    mov rdi,rax; call g_type_from_node; cmp eax,ebx; jne .gepbe_compare_int_regs
    cmp ebx,GTYPE_U64; je .gepbe_compare_int_lit_u
    mov rdi,[rsp+24]; call g_parse_i64_node; test edx,edx; jnz .gepbe_compare_int_regs
    jmp .gepbe_compare_int_lit_exact
.gepbe_compare_int_lit_u:
    mov rax,[rsp+24]; call node_parse_u64; test edx,edx; jnz .gepbe_compare_int_regs
.gepbe_compare_int_lit_exact:
    movsxd rcx,eax
    cmp rcx,rax; jne .gepbe_compare_int_regs
    mov dword ptr [rsp+28],eax
    mov dword ptr [rsp+8],0
    mov rdi,r14; mov esi,ebx; call g_phys_int_direct_source
    test eax,eax; jz .gepbe_compare_int_lit_lhs_temp
    mov dword ptr [rsp+24],edx
    jmp .gepbe_compare_int_lit_cmp
.gepbe_compare_int_lit_lhs_temp:
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepbe_bad
    mov dword ptr [rsp+24],eax
    mov dword ptr [rsp+8],1
    mov rdi,r14; mov esi,eax; mov edx,ebx; call g_emit_phys_int_expr_to
    cmp eax,ebx; jne .gepbe_compare_int_lit_free
.gepbe_compare_int_lit_cmp:
    mov edi,dword ptr [rsp+24]; mov esi,dword ptr [rsp+28]; call g_emit_phys_gpr_cmp_imm32
    test eax,eax; jnz .gepbe_compare_int_lit_free
    mov rdi,[r13+8]; mov rsi,[r13+16]; mov edx,ebx; call g_emit_phys_cmp_result_rax
    mov ebx,eax
    cmp dword ptr [rsp+8],1; jne .gepbe_compare_int_lit_done
    mov edi,dword ptr [rsp+24]; call g_phys_int_temp_free
.gepbe_compare_int_lit_done:
    mov eax,ebx; jmp .gepbe_done
.gepbe_compare_int_lit_free:
    cmp dword ptr [rsp+8],1; jne .gepbe_bad
    mov edi,dword ptr [rsp+24]; call g_phys_int_temp_free
    jmp .gepbe_bad

.gepbe_compare_int_regs:
    mov rdi,r14; mov rsi,r15; mov edx,ebx; call g_emit_phys_int_compare_flags
    test eax,eax; jnz .gepbe_bad
    mov rdi,[r13+8]; mov rsi,[r13+16]; mov edx,ebx; call g_emit_phys_cmp_result_rax
    jmp .gepbe_done

.gepbe_compare_fp:
    # Both operands must already be scalar FP; precision convergence is the same
    # one-edge low-type rule used by arithmetic Physical ValueFacts.
    cmp ebx,GTYPE_F32; je 7413f
    cmp ebx,GTYPE_F64; jne .gepbe_bad
7413:cmp dword ptr [rsp+16],GTYPE_F32; je 7414f
    cmp dword ptr [rsp+16],GTYPE_F64; jne .gepbe_bad
7414:
    mov rdi,r14; mov rsi,r15; mov edx,dword ptr [rsp+20]; mov rcx,r13
    call g_emit_phys_fp_compare_relation
    test rax,rax; jz .gepbe_bad
    mov rdi,rax; mov esi,ecx; mov edx,dword ptr [rsp+20]
    call g_emit_phys_cmp_result_rax
    jmp .gepbe_done

.gepbe_bad:
    mov eax,1
.gepbe_done:
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret


# Select is one typed continuation producer. Carrier primitives are its inputs;
# floating and integer consumers do not retain duplicate control emitters.
g_emit_phys_fp_select_to:
    lea r8,[rip+g_emit_phys_fp_value_to]
    lea r9,[rip+g_phys_fp_direct_source]
    jmp g_emit_phys_select_to
g_emit_phys_int_select_to:
    lea r8,[rip+g_emit_phys_int_expr_to]
    lea r9,[rip+g_phys_int_direct_source]
g_emit_phys_select_to:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,56
    mov r12,rdi; mov r13d,esi; mov r14d,edx
    mov [rsp+32],r8; mov [rsp+40],r9
    mov dword ptr [rsp+24],0
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gepst_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gepst_bad
    mov r15,[rbx+32]; test r15,r15; jz .gepst_bad
    mov rax,[r15+32]; test rax,rax; jz .gepst_bad
    cmp qword ptr [rax+32],0; jne .gepst_bad
    mov [rsp],r15; mov [rsp+8],rax
    mov rdi,rbx; call g_infer_expr; cmp eax,GTYPE_BOOL; jne .gepst_bad
    mov rdi,[rsp]; call g_infer_expr; mov [rsp+48],eax
    mov rdi,[rsp+8]; call g_infer_expr
    cmp r14d,GTYPE_F32; jb .gepst_integral_types
    cmp r14d,GTYPE_F64; ja .gepst_integral_types
    mov edx,eax; mov eax,[rsp+48]; call g_low_type
    cmp eax,r14d; jne .gepst_bad
    jmp .gepst_transport_proof
.gepst_integral_types:
    cmp eax,r14d; jne .gepst_bad
    cmp [rsp+48],r14d; jne .gepst_bad
.gepst_transport_proof:
    # A resident false arm owns only register transport. If both emitted arms
    # begin with that exact transport, it may precede a single compare edge.
    # No arithmetic, load, trap or unselected expression is speculated.
    mov rdi,[rsp+8]; mov esi,r14d; call qword ptr [rsp+40]
    test eax,eax; jz .gepst_predicate
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gepst_predicate
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_is_compare_op
    mov [rsp+24],eax
.gepst_predicate:
    mov rax,[rip+g_phys_control_edge_serial]; mov [rsp+48],rax
    mov rdi,rbx; call g_emit_phys_bool_jz_patch
    test rax,rax; jz .gepst_bad
    mov [rsp+16],rax
    # All generated continuation edges participate, including an IEEE parity
    # edge already patched inside a leaf. One unresolved edge alone is not proof.
    mov rcx,[rip+g_phys_control_edge_serial]; sub rcx,[rsp+48]
    cmp rcx,1; jne .gepst_no_meet
    lea rcx,[rax+4]; call g_phys_window_barrier; cmp rcx,[rip+g_emit_ptr]; jne .gepst_no_meet
    cmp dword ptr [rax],0; je .gepst_true
.gepst_no_meet:
    mov dword ptr [rsp+24],0
.gepst_true:
    inc dword ptr [rip+g_packet_fact_scope]
    mov rdi,[rsp]; mov esi,r13d; mov edx,r14d; call qword ptr [rsp+32]
    dec dword ptr [rip+g_packet_fact_scope]
    cmp eax,r14d; jne .gepst_bad
    call g_emit_jmp_patch; mov r15,rax
    G_EMIT_POSITION rsi; mov rdi,[rsp+16]; call g_phys_patch_chain
    inc dword ptr [rip+g_packet_fact_scope]
    mov rdi,[rsp+8]; mov esi,r13d; mov edx,r14d; call qword ptr [rsp+32]
    dec dword ptr [rip+g_packet_fact_scope]
    cmp eax,r14d; jne .gepst_bad
    G_EMIT_POSITION rsi; mov rdi,r15; call g_patch_rel32
    cmp dword ptr [rsp+24],0; je .gepst_result
    mov rdi,[rsp+16]; mov rsi,r15; G_EMIT_POSITION rdx
    call g_phys_meet_select_transport
.gepst_result:
    mov eax,r14d; jmp .gepst_done
.gepst_bad: xor eax,eax
.gepst_done:
    add rsp,56
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=single false-edge rel32, rsi=arm-end JMP rel32, rdx=emission end.
# The caller proves a numeric compare and a register-only false producer.
# Identical transport prefixes meet after FLAGS and before the compare branch.
# Existing true-arm interior addresses stay fixed; no machine-code decoder,
# branch relocation pass, source pattern or second semantic emitter is created.
g_phys_meet_select_transport:
    push rbx; push r12; push r13; push r14
    sub rsp,8
    lea r12,[rdi+4]
    lea r13,[rsi+4]
    lea r14,[rsi-1]
    mov rbx,rdx; sub rbx,r13
    test rbx,rbx; jz .gpmst_done
    mov rax,r14; sub rax,r12
    cmp rbx,rax; ja .gpmst_done
    mov rdi,r12; mov rsi,r13; mov rcx,rbx
    repe cmpsb
    jne .gpmst_done
    # Preserve the one near Jcc, then rotate the shared transport before it.
    mov eax,[r12-6]; mov [rsp],eax
    mov ax,[r12-2]; mov [rsp+4],ax
    lea rdi,[r12-6]; mov rsi,r13; mov rcx,rbx
    rep movsb
    mov eax,[rsp]; mov [rdi],eax
    mov ax,[rsp+4]; mov [rdi+4],ax
    mov rax,r14; lea rcx,[rdi+6]; sub rax,rcx
    mov [rdi+2],eax
    mov [rip+g_emit_ptr],r14
.gpmst_done:
    add rsp,8; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=caller-owned XMM destination, edx=consumer FP type.
# Realize the subtree at its own inferred precision first, then perform exactly
# one edge conversion if the consumer type differs. This is the low-precision
# contagion rule without eager whole-subtree truncation.
g_emit_phys_fp_value_to:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi; mov r14d,edx
    # A previously interned precision projection is already the exact ValueFact
    # required by this consumer. Borrow/copy it before rebuilding the natural
    # subtree; this is what makes repeated propagation zero-redundancy.
    mov rdi,r12; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gepfv_natural
    mov edi,r13d; mov esi,edx; mov edx,r14d; call g_emit_phys_xmm_move
    test eax,eax; jnz .gepfv_bad
    mov eax,r14d; jmp .gepfv_done
.gepfv_natural:
    mov rdi,r12; call g_infer_expr; mov ebx,eax
    cmp ebx,GTYPE_F32; je .gepfv_nat_ok
    cmp ebx,GTYPE_F64; jne .gepfv_bad
.gepfv_nat_ok:
    mov rdi,r12; mov esi,r13d; mov edx,ebx; call g_emit_phys_fp_expr_to
    cmp eax,ebx; jne .gepfv_bad
    cmp ebx,r14d; je .gepfv_ok
    mov edi,r13d; mov esi,ebx; mov edx,r14d; call g_emit_phys_fp_convert_inplace
    test eax,eax; jnz .gepfv_bad
.gepfv_ok:
    mov eax,r14d; jmp .gepfv_done
.gepfv_bad:
    xor eax,eax
.gepfv_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=expected FP type -> eax=1 and rdx=canonical scalar bits
# when expr is an exact literal of that type; eax=0 otherwise.  This is a
# semantic query only and emits no code.
g_phys_fp_literal_bits:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    cmp qword ptr [r12],J_OBJECT; jne .gpfplb_done
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpfplb_no
    mov rbx,rax
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpfplb_no
    mov rdi,rax; call g_type_from_node
    cmp eax,r13d; jne .gpfplb_no
    cmp r13d,GTYPE_F64; je .gpfplb_f64
    cmp r13d,GTYPE_F32; jne .gpfplb_no
    mov rax,rbx; call node_parse_f32_bits; test edx,edx; jnz .gpfplb_no
    mov edx,eax
    mov eax,1; jmp .gpfplb_done
.gpfplb_f64:
    mov rax,rbx; call node_parse_f64_bits; test edx,edx; jnz .gpfplb_no
    mov rdx,rax; mov eax,1; jmp .gpfplb_done
.gpfplb_no:
    xor eax,eax
.gpfplb_done:
    pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=expected FP type -> eax=1 and edx=resident XMM source,
# or eax=0 when the expression requires realization. No code is emitted.
g_phys_fp_direct_source:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    cmp qword ptr [r12],J_OBJECT; jne .gpfpds_done
    # Versioned causal state is already a physical source.
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpfpds_literal
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpfpds_done
    cmp dword ptr [rax+16],r13d; jne .gpfpds_no
    mov ecx,dword ptr [rax+24]
    mov rdx,[rip+g_reg_iter_carrier_kind_ptr]
    cmp dword ptr [rdx+rcx*4],G_PHYS_CARRIER_FP; jne .gpfpds_no
    mov rdx,[rip+g_reg_iter_old_reg_ptr]
    mov edx,dword ptr [rdx+rcx*4]
    cmp edx,0; jl .gpfpds_no
    mov eax,1; jmp .gpfpds_done
.gpfpds_literal:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpfpds_literal_real
    # Whole-episode shared ValueFacts are ordinary direct physical sources.
    # The first speculative profile has ready_count=0, so collection never
    # changes proof semantics.
    mov rdi,r12; mov esi,r13d; call g_phys_cse_find_resident
    cmp eax,0; jl .gpfpds_literal_real
    mov rcx,qword ptr [rip+g_phys_cse_resident_reg_ptr]
    mov edx,dword ptr [rcx+rax*4]
    mov eax,1; jmp .gpfpds_done
.gpfpds_literal_real:
    # During profiling, literals must flow through the ordinary literal path so
    # each static use is counted exactly once.
    cmp dword ptr [rip+g_phys_const_collect],1; je .gpfpds_no
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpfpds_no
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpfpds_no
    mov rdi,rax; call g_type_from_node; cmp eax,r13d; jne .gpfpds_no
    cmp r13d,GTYPE_F64; je .gpfpds_f64
    cmp r13d,GTYPE_F32; jne .gpfpds_no
    mov rax,r14; call node_parse_f32_bits; test edx,edx; jnz .gpfpds_no
    mov edi,eax
    mov esi,GTYPE_F32; call g_phys_const_find_resident
    cmp eax,0; jl .gpfpds_no
    mov rcx,qword ptr [rip+g_phys_const_resident_reg_ptr]; mov edx,dword ptr [rcx+rax*4]; mov eax,1; jmp .gpfpds_done
.gpfpds_f64:
    mov rax,r14; call node_parse_f64_bits; test edx,edx; jnz .gpfpds_no
    mov rdi,rax; mov esi,GTYPE_F64; call g_phys_const_find_resident
    cmp eax,0; jl .gpfpds_no
    mov rcx,qword ptr [rip+g_phys_const_resident_reg_ptr]; mov edx,dword ptr [rcx+rax*4]; mov eax,1; jmp .gpfpds_done
.gpfpds_no:
    xor eax,eax
.gpfpds_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=destination XMM, edx=expected GTYPE_F32/F64 -> eax type/0.
# The destination is a caller-owned physical carrier. Child temporaries are
# borrowed from the shared compile-time pool and returned at final consumption.
g_emit_phys_fp_expr_to:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov r12,rdi; mov r13d,esi; mov r14d,edx
    cmp r14d,GTYPE_F64; je .gpfpe_type_ok
    cmp r14d,GTYPE_F32; jne .gpfpe_bad
.gpfpe_type_ok:
    cmp r13d,dword ptr [rip+g_phys_fp_carrier_count]; jae .gpfpe_bad
    cmp qword ptr [r12],J_OBJECT; jne .gpfpe_bad

    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpfpe_register_source
    mov rdi,r12; mov esi,r14d; call g_phys_cse_find_resident
    cmp eax,0; jl .gpfpe_register_source
    mov edi,eax; mov esi,r14d; call g_emit_packet_resident_rax
    mov edi,r13d; mov esi,r14d; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_register_source:
    mov rdi,r12; mov esi,r14d; call g_phys_cse_demand_resident
    # If the ValueFact already owns a carrier, consume it without rebuilding it.
    mov rdi,r12; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gpfpe_literal
    mov edi,r13d; mov esi,edx; mov edx,r14d; call g_emit_phys_xmm_move
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_literal:
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpfpe_var
    mov r15,rax
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rdi,rax; call g_type_from_node; cmp eax,r14d; jne .gpfpe_bad
    cmp r14d,GTYPE_F64; je .gpfpe_literal_f64
    # Decimal f32 rounds directly at its target precision.
    mov rax,r15; call node_parse_f32_bits; test edx,edx; jnz .gpfpe_bad
    mov r15d,eax
    cmp dword ptr [rip+g_packet_ready],0; je 840f
    mov edi,r15d; call g_emit_mov_rax_imm64
    mov edi,r13d; mov esi,GTYPE_F32; call g_emit_phys_xmm_from_rax
    mov eax,GTYPE_F32; jmp .gpfpe_done
840:
    cmp dword ptr [rip+g_phys_const_collect],1; jne 1f
    mov edi,r15d; mov esi,GTYPE_F32; call g_phys_const_note
1:  mov edi,r15d; mov esi,GTYPE_F32; call g_phys_const_find_candidate
    cmp eax,0; jl .gpfpe_bad
    mov rdx,[rip+g_phys_const_candidate_pool_ptr]; mov rdx,[rdx+rax*8]
    cmp dword ptr [rip+g_phys_const_pool_ready],1; jne 11f
    test rdx,rdx; jz .gpfpe_bad
11: mov edi,r13d; mov esi,GTYPE_F32; call g_emit_phys_xmm_from_const_mem
    test eax,eax; jnz .gpfpe_bad
    mov eax,GTYPE_F32; jmp .gpfpe_done
.gpfpe_literal_f64:
    mov rax,r15; call node_parse_f64_bits; test edx,edx; jnz .gpfpe_bad
    mov r15,rax
    cmp dword ptr [rip+g_packet_ready],0; je 841f
    mov rdi,r15; call g_emit_mov_rax_imm64
    mov edi,r13d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
    mov eax,GTYPE_F64; jmp .gpfpe_done
841:
    cmp dword ptr [rip+g_phys_const_collect],1; jne 2f
    mov rdi,r15; mov esi,GTYPE_F64; call g_phys_const_note
2:  mov rdi,r15; mov esi,GTYPE_F64; call g_phys_const_find_candidate
    cmp eax,0; jl .gpfpe_bad
    mov rdx,[rip+g_phys_const_candidate_pool_ptr]; mov rdx,[rdx+rax*8]
    cmp dword ptr [rip+g_phys_const_pool_ready],1; jne 22f
    test rdx,rdx; jz .gpfpe_bad
22: mov edi,r13d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_const_mem
    test eax,eax; jnz .gpfpe_bad
    mov eax,GTYPE_F64; jmp .gpfpe_done

.gpfpe_var:
    mov rdi,r12; call g_phys_episode_load_source
    test rax,rax; jz .gpfpe_var_leaf
    mov rdi,rax; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    jmp .gpfpe_done
.gpfpe_var_leaf:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpfpe_state_invalid_or_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gpfpe_bad
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gpfpe_bad
    mov r15,rax
    cmp dword ptr [r15+20],r14d; jne .gpfpe_bad
    cmp dword ptr [r15+24],-1; je .gpfpe_bad
    cmp dword ptr [r15+16],GK_INPUT; je .gpfpe_var_input
    mov eax,dword ptr [r15+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    jmp .gpfpe_var_loaded
.gpfpe_var_input:
    mov eax,dword ptr [r15+24]; call g_input_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
.gpfpe_var_loaded:
    mov edi,r13d; mov esi,r14d; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_state_invalid_or_op:
    # A nonresident state remains part of the same Physical DAG.  Materialize
    # exactly that ValueFact from its established state slot into the requested
    # destination; do not fall back to the stack evaluator.
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpfpe_op_probe
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpfpe_bad
    cmp dword ptr [rax+16],r14d; jne .gpfpe_bad
    mov ecx,dword ptr [rax+24]
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; cmp dword ptr [rdx+rcx*4],0; jge .gpfpe_bad
    mov eax,ecx; call g_state_slot_addr; mov rdx,rax
    mov edi,r13d; mov esi,r14d; call g_emit_phys_xmm_from_state_mem
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_op_probe:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov r15,rax
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jnz .gpfpe_cast
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gpfpe_not_select
    mov rdi,r12; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_select_to
    jmp .gpfpe_done
.gpfpe_cast:
    mov rdi,r12; call g_infer_expr; cmp eax,r14d; jne .gpfpe_bad
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpfpe_bad
    cmp qword ptr [rbx+32],0; jne .gpfpe_bad
    mov rdi,rbx; call g_infer_expr; mov dword ptr [rsp+4],eax
    cmp eax,GTYPE_F32; je 440f
    cmp eax,GTYPE_F64; je 440f
    cmp eax,GTYPE_U64; je .gpfpe_cast_integer
    cmp eax,GTYPE_I64; jne .gpfpe_bad
.gpfpe_cast_integer:
    call g_phys_int_temp_alloc
    cmp eax,0; jl .gpfpe_bad
    mov dword ptr [rsp],eax
    mov esi,eax; mov rdi,rbx; mov edx,dword ptr [rsp+4]; call g_emit_phys_int_expr_to
    cmp eax,dword ptr [rsp+4]; jne .gpfpe_cast_integer_fail
    xor edi,edi; mov esi,dword ptr [rsp]; call g_emit_phys_gpr_move
    mov edi,dword ptr [rsp]; call g_phys_int_temp_free
    cmp dword ptr [rsp+4],GTYPE_U64; jne .gpfpe_cast_range_ready
    mov rdi,rbx; call g_u64_expr_fits_signed
    test eax,eax; jz .gpfpe_cast_range_ready
    mov dword ptr [rsp+4],GTYPE_I64
.gpfpe_cast_range_ready:
    mov edi,dword ptr [rsp+4]; mov esi,r14d; mov edx,r13d; call g_emit_phys_int_fp_value
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_cast_integer_fail:
    mov edi,dword ptr [rsp]; call g_phys_int_temp_free
    jmp .gpfpe_bad
440:mov rdi,rbx; mov esi,r13d; mov edx,dword ptr [rsp+4]; call g_emit_phys_fp_expr_to
    cmp eax,dword ptr [rsp+4]; jne .gpfpe_bad
    cmp eax,r14d; je 441f
    mov edi,r13d; mov esi,eax; mov edx,r14d; call g_emit_phys_fp_convert_inplace
    test eax,eax; jnz .gpfpe_bad
441:mov eax,r14d; jmp .gpfpe_done

.gpfpe_not_select:
    # Unary pure ValueFacts stay in the same physical DAG.
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq
    test eax,eax; jnz .gpfpe_neg
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jnz .gpfpe_abs
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jnz .gpfpe_sqrt
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq
    test eax,eax; jnz .gpfpe_square
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_trunc]; mov ecx,gv_trunc_end-gv_trunc; call span_eq
    test eax,eax; jnz .gpfpe_trunc
    # Native elementary relations consume a local memory operand on x87.
    # The same old ISA primitive rounds once at this node; every other live
    # XMM/GPR authority survives, including nested ordinary arithmetic.
    mov rdi,[r15+8]; mov rsi,[r15+16]; mov edx,r14d; call g_native_fp_math_fragment
    test rax,rax; jz .gpfpe_binary_probe
    mov r15,rax; mov dword ptr [rsp+8],ecx
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpfpe_bad
    cmp qword ptr [rbx+32],0; jne .gpfpe_bad
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edi,r13d; mov esi,r14d; call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gpfpe_bad
    mov edi,0x50; call g_emit_u8
    mov rdi,r15; mov esi,dword ptr [rsp+8]; call g_emit_bytes
    test eax,eax; jnz .gpfpe_bad
    call g_emit_pop_rax
    mov edi,r13d; mov esi,r14d; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_binary_probe:
    # Classify the exact binary operation before recursive emission. Strict
    # ordering is preserved: add/sub/mul only, no reassociation/FMA contraction.
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jz 3f
    mov dword ptr [rsp+8],0x58; jmp .gpfpe_op_ready
3:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jz 4f
    mov dword ptr [rsp+8],0x5C; jmp .gpfpe_op_ready
4:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jz 41f
    mov dword ptr [rsp+8],0x59
    jmp .gpfpe_op_ready
41: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jz 42f
    mov dword ptr [rsp+8],0x5E
    jmp .gpfpe_op_ready
42: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq
    test eax,eax; jz 43f
    mov dword ptr [rsp+8],0x5D
    jmp .gpfpe_op_ready
43: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq
    test eax,eax; jz .gpfpe_bad
    mov dword ptr [rsp+8],0x5F
    jmp .gpfpe_op_ready
.gpfpe_neg:
    mov dword ptr [rsp+8],0
    jmp .gpfpe_sign_unary
.gpfpe_abs:
    mov dword ptr [rsp+8],1
.gpfpe_sign_unary:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpfpe_bad
    cmp qword ptr [rbx+32],0; jne .gpfpe_bad
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edi,r13d; mov esi,r14d; mov edx,dword ptr [rsp+8]; call g_emit_phys_fp_sign_inplace
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_square:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpfpe_bad
    cmp qword ptr [rbx+32],0; jne .gpfpe_bad
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edi,r13d; mov esi,r14d; call g_emit_phys_square_inplace
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_trunc:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpfpe_bad
    cmp qword ptr [rbx+32],0; jne .gpfpe_bad
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edi,r13d; mov esi,r14d; call g_emit_phys_trunc_inplace
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_sqrt:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpfpe_bad
    cmp qword ptr [rbx+32],0; jne .gpfpe_bad
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edi,r13d; mov esi,r14d; call g_emit_phys_sqrt_inplace
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_op_ready:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpfpe_bad
    mov r15,[rbx+32]; test r15,r15; jz .gpfpe_bad
    cmp qword ptr [r15+32],0; jne .gpfpe_bad

    # Infer each child independently. The parent result must equal the existing
    # low-precision merge rule, but the child subtrees remain at their own natural
    # precision until this exact dependency edge. Equal-precision expressions keep
    # the mature zero-copy resident-source path below.
    mov rdi,rbx; call g_infer_expr; mov dword ptr [rsp+4],eax
    cmp eax,GTYPE_F32; je 5f
    cmp eax,GTYPE_F64; jne .gpfpe_bad
5:  mov rdi,r15; call g_infer_expr; mov dword ptr [rsp+12],eax
    cmp eax,GTYPE_F32; je 6f
    cmp eax,GTYPE_F64; jne .gpfpe_bad
6:  mov eax,dword ptr [rsp+4]; mov edx,dword ptr [rsp+12]; call g_low_type
    cmp eax,r14d; jne .gpfpe_bad
    cmp dword ptr [rsp+4],r14d; jne .gpfpe_mixed_op
    cmp dword ptr [rsp+12],r14d; jne .gpfpe_mixed_op

    mov rdi,rbx; mov rsi,r15; call g_phys_expr_equal
    test eax,eax; jz .gpfpe_distinct_children
    mov rdi,rbx; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jnz .gpfpe_shared_child_ready
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edx,r13d
.gpfpe_shared_child_ready:
    mov ecx,edx
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov r8d,r14d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_distinct_children:
    # Left input: retain resident ValueFacts by identity, otherwise realize the
    # subtree directly into the final destination.
    mov rdi,rbx; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gpfpe_lhs_complex
    mov ebx,edx
    jmp .gpfpe_lhs_ready
.gpfpe_lhs_complex:
    # x86 scalar arithmetic exposes only src2 as r/m.  A nonresident finite
    # literal on the source-left of exact add/mul therefore needs no synthetic
    # carrier: evaluating the other pure ValueFact into src1 and placing the
    # literal AddressFact in src2 preserves the same single IEEE operation and
    # rounding point.  Finite is required so operand placement cannot choose
    # between two NaN payloads; nonfinite literals retain source-position
    # materialization.  The AST, CSE identity and semantic operand order remain
    # untouched.
    mov eax,dword ptr [rsp+8]
    cmp eax,0x58; je .gpfpe_lhs_const_mem_probe
    cmp eax,0x59; jne .gpfpe_lhs_materialize
.gpfpe_lhs_const_mem_probe:
    mov rdi,rbx; mov esi,r14d; call g_phys_fp_literal_bits
    test eax,eax; jz .gpfpe_lhs_materialize
    mov r12,rdx
    cmp r14d,GTYPE_F64; jne .gpfpe_lhs_const_f32_finite
    mov rax,r12; shr rax,52; and eax,0x7ff; cmp eax,0x7ff; je .gpfpe_lhs_materialize
    jmp .gpfpe_lhs_const_finite
.gpfpe_lhs_const_f32_finite:
    mov eax,r12d; shr eax,23; and eax,0xff; cmp eax,0xff; je .gpfpe_lhs_materialize
.gpfpe_lhs_const_finite:
    cmp dword ptr [rip+g_phys_const_collect],1; jne .gpfpe_lhs_const_noted
    mov rdi,r12; mov esi,r14d; call g_phys_const_note
.gpfpe_lhs_const_noted:
    mov rdi,r12; mov esi,r14d; call g_phys_const_find_candidate
    cmp eax,0; jl .gpfpe_lhs_materialize
    mov rdx,[rip+g_phys_const_candidate_pool_ptr]
    mov rcx,[rdx+rax*8]
    cmp dword ptr [rip+g_phys_const_pool_ready],1; jne .gpfpe_lhs_const_addr_ready
    test rcx,rcx; jz .gpfpe_bad
.gpfpe_lhs_const_addr_ready:
    mov [rsp],rcx
    # Preserve an existing RHS carrier by identity; otherwise let the RHS be
    # born directly in the final destination.  No anonymous carrier is created
    # for the constant or for an operand swap.
    mov rdi,r15; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gpfpe_lhs_const_rhs_complex
    mov ebx,edx
    jmp .gpfpe_lhs_const_emit
.gpfpe_lhs_const_rhs_complex:
    mov rdi,r15; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov ebx,r13d
.gpfpe_lhs_const_emit:
    mov rcx,[rsp]
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,ebx; mov r8d,r14d
    call g_emit_phys_vex_scalar3_mem
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_lhs_materialize:
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov ebx,r13d
.gpfpe_lhs_ready:
    # Right direct source can be consumed immediately by a VEX three-operand op.
    mov rdi,r15; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gpfpe_rhs_complex
    mov ecx,edx
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,ebx; mov r8d,r14d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_rhs_complex:
    # An exact nonresident literal already owns an immutable address form.  Let
    # the arithmetic consumer read that ConstantFact directly instead of
    # manufacturing a synthetic XMM lifetime.  Proof emissions use a dummy
    # displacement until the preheader publishes the pool address.
    mov rdi,r15; mov esi,r14d; call g_phys_fp_literal_bits
    test eax,eax; jz .gpfpe_rhs_nonliteral
    mov r12,rdx
    cmp dword ptr [rip+g_phys_const_collect],1; jne .gpfpe_rhs_literal_noted
    mov rdi,r12; mov esi,r14d; call g_phys_const_note
.gpfpe_rhs_literal_noted:
    mov rdi,r12; mov esi,r14d; call g_phys_const_find_candidate
    cmp eax,0; jl .gpfpe_rhs_nonliteral
    mov rdx,[rip+g_phys_const_candidate_pool_ptr]
    mov rcx,[rdx+rax*8]
    cmp dword ptr [rip+g_phys_const_pool_ready],1; jne .gpfpe_rhs_literal_emit
    test rcx,rcx; jz .gpfpe_bad
.gpfpe_rhs_literal_emit:
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,ebx; mov r8d,r14d
    call g_emit_phys_vex_scalar3_mem
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_rhs_nonliteral:
    cmp ebx,r13d; je .gpfpe_rhs_temp
    # LHS is resident elsewhere, so RHS may be born directly in destination.
    mov rdi,r15; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,ebx; mov ecx,r13d; mov r8d,r14d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_rhs_temp:
    call g_phys_fp_temp_alloc
    cmp eax,0; jl .gpfpe_bad
    mov dword ptr [rsp],eax
    mov rdi,r15; mov esi,eax; mov edx,r14d; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gpfpe_rhs_temp_fail
    mov ecx,dword ptr [rsp]
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,r13d; mov r8d,r14d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gpfpe_rhs_temp_fail
    mov edi,dword ptr [rsp]; call g_phys_fp_temp_free
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_rhs_temp_fail:
    mov edi,dword ptr [rsp]; call g_phys_fp_temp_free
    jmp .gpfpe_bad

# Mixed f32/f64 binary realization. Precision contagion happens only here, at
# the actual parent edge. A same-type resident child stays borrowed in place;
# only a mismatched/complex edge receives a caller-owned carrier and at most one
# conversion. No whole-expression fallback, eager truncation, or duplicate cast.
.gpfpe_mixed_op:
    # LHS: borrow a same-result-type resident fact directly. Otherwise realize
    # its complete subtree into the final destination at natural precision and
    # convert exactly once at this edge.
    cmp dword ptr [rsp+4],r14d; jne .gpfpe_mixed_lhs_materialize
    mov rdi,rbx; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gpfpe_mixed_lhs_materialize
    mov ebx,edx
    jmp .gpfpe_mixed_lhs_ready
.gpfpe_mixed_lhs_materialize:
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_value_to
    cmp eax,r14d; jne .gpfpe_bad
    mov ebx,r13d
.gpfpe_mixed_lhs_ready:
    # RHS: same-result-type resident facts can also be consumed without a copy.
    cmp dword ptr [rsp+12],r14d; jne .gpfpe_mixed_rhs_materialize
    mov rdi,r15; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gpfpe_mixed_rhs_materialize
    mov ecx,edx
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,ebx; mov r8d,r14d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_mixed_rhs_materialize:
    # If LHS is borrowed elsewhere, destination is free and becomes the RHS
    # edge carrier. Otherwise borrow one anonymous lifetime-scoped temporary.
    cmp ebx,r13d; je .gpfpe_mixed_rhs_temp
    mov rdi,r15; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_value_to
    cmp eax,r14d; jne .gpfpe_bad
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,ebx; mov ecx,r13d; mov r8d,r14d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done

.gpfpe_mixed_rhs_temp:
    call g_phys_fp_temp_alloc
    cmp eax,0; jl .gpfpe_bad
    mov dword ptr [rsp],eax
    mov rdi,r15; mov esi,eax; mov edx,r14d; call g_emit_phys_fp_value_to
    cmp eax,r14d; jne .gpfpe_mixed_rhs_temp_fail
    mov ecx,dword ptr [rsp]
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov edx,r13d; mov r8d,r14d
    call g_emit_phys_vex_scalar3
    test eax,eax; jnz .gpfpe_mixed_rhs_temp_fail
    mov edi,dword ptr [rsp]; call g_phys_fp_temp_free
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_mixed_rhs_temp_fail:
    mov edi,dword ptr [rsp]; call g_phys_fp_temp_free
    jmp .gpfpe_bad

.gpfpe_bad:
    xor eax,eax
.gpfpe_done:
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret


# ---------------- 1.3.14 unified scalar integer Physical-DAG lowering ----------------
# Integer causal ValueFacts use the same lifetime discipline as FP.  The
# physical destination belongs to the caller; nested values borrow RAX/R11..R15
# only while they have future consumers.  No AST depth is a register identity.
.equ G_PHYS_INT_TEMP_MASK_INIT,0x00007800   # R11..R14; R15 owns execution-local StateFact frame

g_phys_int_temp_reset:
    mov dword ptr [rip+g_phys_int_temp_live],0
    mov eax,G_PHYS_INT_TEMP_MASK_INIT
    mov ecx,dword ptr [rip+g_phys_int_reserved_mask]
    not ecx; and eax,ecx
    mov dword ptr [rip+g_phys_int_temp_mask],eax
    ret

g_phys_int_temp_alloc:
    mov eax,dword ptr [rip+g_phys_int_temp_mask]
    test eax,eax; jz .gpit_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+g_phys_int_temp_mask],eax
    inc dword ptr [rip+g_phys_int_temp_live]
    mov edx,dword ptr [rip+g_phys_int_temp_live]
    cmp edx,dword ptr [rip+g_phys_int_temp_peak]; jbe .gpit_have
    mov dword ptr [rip+g_phys_int_temp_peak],edx
.gpit_have:
    mov eax,ecx
    ret
.gpit_fail:
    mov eax,-1
    ret

# edi=GPR code. Only the anonymous temporary carrier domain is releasable.
g_phys_int_temp_free:
    cmp edi,11; jb .gpitf_done
    cmp edi,14; ja .gpitf_done
    bts dword ptr [rip+g_phys_int_temp_mask],edi
    cmp dword ptr [rip+g_phys_int_temp_live],0; je .gpitf_done
    dec dword ptr [rip+g_phys_int_temp_live]
.gpitf_done:
    ret

# Integer StateFact carrier geometry.  These are physical ABI resources, not a
# language-level state-count threshold.  The fourth role borrows R11/R12 from
# the anonymous pool; g_phys_int_temp_reset removes them from temporary use.
# edi=semantic data role -> eax runtime old-authority GPR code, or -1.
g_phys_int_old_reg:
    cmp edi,0; je .gpior_old0
    cmp edi,1; je .gpior_old1
    cmp edi,2; je .gpior_old2
    cmp edi,3; je .gpior_old3
    mov eax,-1; ret
.gpior_old0: mov eax,8; ret                 # R8
.gpior_old1: mov eax,9; ret                 # R9
.gpior_old2: mov eax,10; ret                # R10
.gpior_old3: mov eax,11; ret                # R11, physically reserved from temp pool

# edi=semantic data role -> eax runtime next-authority GPR code, or -1.
g_phys_int_output_reg:
    cmp edi,0; je .gpior0
    cmp edi,1; je .gpior1
    cmp edi,2; je .gpior2
    cmp edi,3; je .gpior3
    mov eax,-1; ret
.gpior0: mov eax,6; ret                    # RSI
.gpior1: mov eax,7; ret                    # RDI
.gpior2: mov eax,1; ret                    # RCX; RDX remains implicit-wide-multiply scratch
.gpior3: mov eax,12; ret                   # R12, physically reserved from temp pool

# Generic runtime GPR copy. edi=dst, esi=src.
g_emit_phys_gpr_move:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp ebx,r12d; je .gepgm_ok
    mov eax,0x48
    mov ecx,r12d; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov ecx,ebx; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgm_bad
    mov edi,0x89; call g_emit_u8; test eax,eax; jnz .gepgm_bad
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgm_bad
.gepgm_ok:
    xor eax,eax; jmp .gepgm_done
.gepgm_bad:
    mov eax,1
.gepgm_done:
    pop r12; pop rbx; ret

# Exact unary integer ValueFact in an existing carrier. edi=kind (0 not,1 neg),
# esi=dst.  Trapping signed negation remains outside this helper; callers admit
# neg only when the existing wrap contract makes it total.
g_emit_phys_gpr_unary:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp ebx,1; ja .gepgu_bad
    mov eax,0x48
    mov ecx,r12d; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgu_bad
    mov edi,0xF7; call g_emit_u8; test eax,eax; jnz .gepgu_bad
    mov eax,r12d; and eax,7; or eax,0xD0
    test ebx,ebx; jz 780f
    or eax,0x08
780:mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgu_bad
    xor eax,eax; jmp .gepgu_done
.gepgu_bad: mov eax,1
.gepgu_done: pop r12; pop rbx; ret

# Wrap-mode signed abs using runtime RAX as the existing transient integer bit
# carrier: mask=x>>63; x=(x^mask)-mask. edi=dst GPR.
g_emit_phys_i64_abs_wrap_inplace:
    push rbx
    mov ebx,edi
    xor edi,edi; mov esi,ebx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepiaw_bad
    # sar rax,63
    mov edi,0x48; call g_emit_u8; test eax,eax; jnz .gepiaw_bad
    mov edi,0xC1; call g_emit_u8; test eax,eax; jnz .gepiaw_bad
    mov edi,0xF8; call g_emit_u8; test eax,eax; jnz .gepiaw_bad
    mov edi,63; call g_emit_u8; test eax,eax; jnz .gepiaw_bad
    # xor dst,rax then sub dst,rax
    mov edi,7; mov esi,ebx; xor edx,edx; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepiaw_bad
    mov edi,2; mov esi,ebx; xor edx,edx; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepiaw_bad
    xor eax,eax; jmp .gepiaw_done
.gepiaw_bad: mov eax,1
.gepiaw_done: pop rbx; ret

# Generic two-source integer realization into an already initialized dst.
# kind 1 add,2 sub,3 mul,5 and,6 or,7 xor,8 umin,9 umax,10 imin,11 imax.
g_emit_phys_gpr_bin2:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp ebx,3; je .gepgb_mul
    cmp ebx,5; je .gepgb_and
    cmp ebx,6; je .gepgb_or
    cmp ebx,7; je .gepgb_xor
    cmp ebx,8; jae .gepgb_minmax
    cmp ebx,1; je .gepgb_add
    cmp ebx,2; jne .gepgb_bad
    mov ebx,0x29                         # sub r/m64, r64
    jmp .gepgb_addsub
.gepgb_add:
    mov ebx,0x01                         # add r/m64, r64
    jmp .gepgb_addsub
.gepgb_and: mov ebx,0x21; jmp .gepgb_addsub
.gepgb_or:  mov ebx,0x09; jmp .gepgb_addsub
.gepgb_xor: mov ebx,0x31
.gepgb_addsub:
    mov eax,0x48
    mov ecx,r13d; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov ecx,r12d; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgb_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepgb_bad
    mov eax,r13d; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgb_bad
    xor eax,eax; jmp .gepgb_done
.gepgb_mul:
    # imul r64, r/m64 : REX.R follows destination, REX.B follows source.
    mov eax,0x48
    mov ecx,r12d; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov ecx,r13d; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgb_bad
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepgb_bad
    mov edi,0xAF; call g_emit_u8; test eax,eax; jnz .gepgb_bad
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r13d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgb_bad
    xor eax,eax; jmp .gepgb_done
.gepgb_minmax:
    cmp ebx,11; ja .gepgb_bad
    mov edi,r12d; mov esi,r13d; call g_emit_phys_gpr_cmp
    test eax,eax; jnz .gepgb_bad
    mov edi,0x47                         # umin: cmova
    cmp ebx,8; je 781f
    mov edi,0x42                         # umax: cmovb
    cmp ebx,9; je 781f
    mov edi,0x4F                         # imin: cmovg
    cmp ebx,10; je 781f
    mov edi,0x4C                         # imax: cmovl
781:mov esi,r12d; mov edx,r13d; call g_emit_phys_gpr_cmov
    jmp .gepgb_done
.gepgb_bad:
    mov eax,1
.gepgb_done:
    pop r13; pop r12; pop rbx; ret

# edi=condition opcode 0x40..0x4f, esi=destination, edx=source.
# Min/max and reciprocal correction consume the same completed flags edge.
g_emit_phys_gpr_cmov:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    mov eax,0x48
    mov ecx,r12d; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov ecx,r13d; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgcm_done
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepgcm_done
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepgcm_done
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r13d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8
.gepgcm_done: pop r13; pop r12; pop rbx; ret

# Immediate integer relation over an existing destination carrier. The literal
# is already proven to be exactly representable by the architectural sign-
# extended imm32 operand, so no temporary ValueFact carrier exists at runtime.
# Arithmetic and bit relations share this one ISA-operand authority; multiplication
# is the ordinary three-operand IMUL realization with src=dst, not a second backend.
# edi=kind (1 add,2 sub,3 mul,5 and,6 or,7 xor), esi=dst GPR, edx=imm32 bits.
g_emit_phys_gpr_imm32_bin2:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp ebx,3; je .gepgi_mul
    cmp ebx,1; je .gepgi_add
    cmp ebx,2; je .gepgi_sub
    cmp ebx,5; je .gepgi_and
    cmp ebx,6; je .gepgi_or
    cmp ebx,7; je .gepgi_xor
    jmp .gepgi_bad
.gepgi_mul:
    # imul dst,dst,imm32 : 69 /r id. Both ModRM operands are the same carrier.
    mov eax,0x48
    mov ecx,r12d; shr ecx,3; and ecx,1
    mov edx,ecx; shl ecx,2; or eax,ecx; or eax,edx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgi_bad
    mov edi,0x69; call g_emit_u8; test eax,eax; jnz .gepgi_bad
    mov eax,r12d; and eax,7
    mov ecx,eax; shl ecx,3; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgi_bad
    mov edi,r13d; call g_emit_u32; test eax,eax; jnz .gepgi_bad
    xor eax,eax; jmp .gepgi_done
.gepgi_add: mov ebx,0; jmp .gepgi_emit
.gepgi_or:  mov ebx,1; jmp .gepgi_emit
.gepgi_and: mov ebx,4; jmp .gepgi_emit
.gepgi_sub: mov ebx,5; jmp .gepgi_emit
.gepgi_xor: mov ebx,6
.gepgi_emit:
    mov eax,0x48
    mov ecx,r12d; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgi_bad
    mov edi,0x81; call g_emit_u8; test eax,eax; jnz .gepgi_bad
    mov eax,ebx; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgi_bad
    mov edi,r13d; call g_emit_u32; test eax,eax; jnz .gepgi_bad
    xor eax,eax; jmp .gepgi_done
.gepgi_bad:
    mov eax,1
.gepgi_done:
    pop r13; pop r12; pop rbx; ret

# Compare one resident integer ValueFact directly with an exact imm32 literal.
# edi=lhs GPR, esi=imm32 bits -> FLAGS as lhs-imm.
g_emit_phys_gpr_cmp_imm32:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov eax,0x48
    mov ecx,ebx; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgci_bad
    mov edi,0x81; call g_emit_u8; test eax,eax; jnz .gepgci_bad
    mov eax,ebx; and eax,7; or eax,0xF8       # mod=3, /7 cmp
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgci_bad
    mov edi,r12d; call g_emit_u32; test eax,eax; jnz .gepgci_bad
    xor eax,eax; jmp .gepgci_done
.gepgci_bad:
    mov eax,1
.gepgci_done:
    pop r12; pop rbx; ret

# edi=physical integer arithmetic kind (1 add,2 sub,3 mul), esi=GTYPE.
# Wrap needs no guard. Trap emits the architectural overflow relation directly;
# unsupported unsigned trapping multiply remains a proof miss instead of growing
# a second arithmetic backend.
g_emit_phys_int_overflow_guard:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gepiog_ok
    cmp edi,1; je .gepiog_addsub
    cmp edi,2; je .gepiog_addsub
    cmp edi,3; jne .gepiog_bad
    cmp esi,GTYPE_I64; jne .gepiog_bad
    mov edi,0x71                         # jno +6
    jmp .gepiog_emit
.gepiog_addsub:
    mov edi,0x73                         # jnc +6 for unsigned add/sub
    cmp esi,GTYPE_I64; jne .gepiog_emit
    mov edi,0x71                         # jno +6 for signed add/sub
.gepiog_emit:
    call g_emit_u8; test eax,eax; jnz .gepiog_bad
    mov edi,7; call g_emit_u8; test eax,eax; jnz .gepiog_bad
    lea rdi,[rip+gc_effect_reject]; mov esi,gc_effect_reject_end-gc_effect_reject; call g_emit_bytes
    test eax,eax; jnz .gepiog_bad
.gepiog_ok:
    xor eax,eax; ret
.gepiog_bad:
    mov eax,1; ret

# Same typed carrier relation for integer FLAGS and demanded BOOL values.
# rdi=left, rsi=right, edx=exact integer type -> eax=0 success.
# Resident operands are borrowed; only absent values allocate transient GPRs.
g_emit_phys_int_compare_flags:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov r12,rdi; mov r13,rsi; mov ebx,edx
    mov dword ptr [rsp],0; mov dword ptr [rsp+4],0
    mov rdi,r12; mov esi,ebx; call g_phys_int_direct_source
    test eax,eax; jz .gepicf_left_temp
    mov r14d,edx; jmp .gepicf_right
.gepicf_left_temp:
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepicf_fail
    mov r14d,eax; mov dword ptr [rsp],1
    mov rdi,r12; mov esi,r14d; mov edx,ebx; call g_emit_phys_int_expr_to
    cmp eax,ebx; jne .gepicf_fail
.gepicf_right:
    mov rdi,r13; mov esi,ebx; call g_phys_int_direct_source
    test eax,eax; jz .gepicf_right_temp
    mov r15d,edx; jmp .gepicf_compare
.gepicf_right_temp:
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepicf_fail
    mov r15d,eax; mov dword ptr [rsp+4],1
    mov rdi,r13; mov esi,r15d; mov edx,ebx; call g_emit_phys_int_expr_to
    cmp eax,ebx; jne .gepicf_fail
.gepicf_compare:
    mov edi,r14d; mov esi,r15d; call g_emit_phys_gpr_cmp
    jmp .gepicf_release
.gepicf_fail: mov eax,1
.gepicf_release:
    mov [rsp+8],eax
    cmp dword ptr [rsp+4],0; je .gepicf_release_left
    mov edi,r15d; call g_phys_int_temp_free
.gepicf_release_left:
    cmp dword ptr [rsp],0; je .gepicf_return
    mov edi,r14d; call g_phys_int_temp_free
.gepicf_return:
    mov eax,[rsp+8]
    add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Generic register compare. edi=lhs, esi=rhs emits `cmp lhs,rhs`.
# This is a physical primitive, not a semantic branch.
g_emit_phys_gpr_cmp:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov eax,0x48
    mov ecx,r12d; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov ecx,ebx; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgc_bad
    mov edi,0x39; call g_emit_u8; test eax,eax; jnz .gepgc_bad
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,ebx; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgc_bad
    xor eax,eax; jmp .gepgc_done
.gepgc_bad:
    mov eax,1
.gepgc_done:
    pop r12; pop rbx; ret


# edi=src emits unsigned `mul src`: RDX:RAX = RAX * src.
# RAX/RDX are deliberately scratch in the register-native integer episode.
g_emit_phys_mul_rax_gpr:
    push rbx
    mov ebx,edi
    mov eax,0x48
    mov ecx,ebx; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepma_bad
    mov edi,0xF7; call g_emit_u8; test eax,eax; jnz .gepma_bad
    mov eax,ebx; and eax,7; or eax,0xE0       # mod=3, /4, r/m=src
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepma_bad
    xor eax,eax; jmp .gepma_done
.gepma_bad:
    mov eax,1
.gepma_done:
    pop rbx; ret

# One exact quotient/remainder entity over a nonzero U64 ConstantFact.
# edi=dst GPR, rsi=d, ecx=0 remainder /1 quotient. The shared reciprocal fact
# owns demanded precision. Only implicit MUL conflicts require another carrier.
g_emit_phys_u64_const_divmod:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov ebx,edi; mov r12,rsi; mov r15d,ecx
    mov dword ptr [rsp+8],-1; mov [rsp+12],edi
    cmp r12,1; jne .gepucm_nonzero_bits
    test r15d,r15d; jnz .gepucm_ok
    xor edi,edi; call g_emit_mov_rax_imm64
    mov edi,ebx; xor esi,esi; call g_emit_phys_gpr_move
    jmp .gepucm_done
.gepucm_nonzero_bits:
    mov rdi,r12; call physical_u64_lowbits_mask
    test edx,edx; jz .gepucm_normalized
    test r15d,r15d; jz .gepucm_lowbits
    bsf rdx,r12
    mov edi,13; mov esi,ebx; call g_emit_phys_gpr_shift_imm
    jmp .gepucm_done
.gepucm_lowbits:
    mov r13,rax
    movsxd rdx,eax; cmp rdx,rax; jne .gepucm_lowbits_reg
    mov edi,5; mov esi,ebx; mov edx,eax; call g_emit_phys_gpr_imm32_bin2
    jmp .gepucm_done
.gepucm_lowbits_reg:
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepucm_bad
    mov r14d,eax
    mov edi,r14d; mov rsi,r13; call g_emit_phys_gpr_literal
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,5; mov esi,ebx; mov edx,r14d; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    jmp .gepucm_release
.gepucm_normalized:
    # RAX/RDX are architectural MUL outputs. Preserve a caller-owned value in
    # either only while it is live, using the same anonymous carrier allocator.
    cmp ebx,0; je .gepucm_preserve_mul
    cmp ebx,2; jne .gepucm_fact
.gepucm_preserve_mul:
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepucm_bad
    mov [rsp+8],eax
    mov edi,eax; mov esi,ebx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_bad
    mov ebx,[rsp+8]
.gepucm_fact:
    mov rdi,r12; mov esi,r15d; call physical_u64_division_fact
    mov r13,rax; mov [rsp],edx; mov [rsp+4],ecx
    call g_phys_int_temp_alloc; cmp eax,0; jl .gepucm_bad
    mov r14d,eax
    mov edi,r14d; mov rsi,r13; call g_emit_phys_gpr_literal
    test eax,eax; jnz .gepucm_temp_bad
    xor edi,edi; mov esi,ebx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,r14d; call g_emit_phys_mul_rax_gpr
    test eax,eax; jnz .gepucm_temp_bad
    cmp dword ptr [rsp+4],0; je .gepucm_shift
    xor edi,edi; mov esi,ebx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,2; xor esi,esi; mov edx,2; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,13; xor esi,esi; mov edx,1; call g_emit_phys_gpr_shift_imm
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,1; mov esi,2; xor edx,edx; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
.gepucm_shift:
    cmp dword ptr [rsp],0; je .gepucm_projection
    mov edi,13; mov esi,2; mov edx,[rsp]; call g_emit_phys_gpr_shift_imm
    test eax,eax; jnz .gepucm_temp_bad
.gepucm_projection:
    test r15d,r15d; jz .gepucm_remainder
    mov edi,ebx; mov esi,2; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    jmp .gepucm_release
.gepucm_remainder:
    mov edi,r14d; mov rsi,r12; call g_emit_phys_gpr_literal
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,3; mov esi,2; mov edx,r14d; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,2; mov esi,ebx; mov edx,2; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    # The bounded quotient is exact or one below it. One branch-free correction
    # realizes exact remainder for the entire U64 domain, for every d>1.
    xor edi,edi; mov esi,ebx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,2; xor esi,esi; mov edx,r14d; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,ebx; mov esi,r14d; call g_emit_phys_gpr_cmp
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,0x43; mov esi,ebx; xor edx,edx; call g_emit_phys_gpr_cmov
    test eax,eax; jnz .gepucm_temp_bad
.gepucm_release:
    mov edi,r14d; call g_phys_int_temp_free
.gepucm_ok:
    xor eax,eax; jmp .gepucm_done
.gepucm_temp_bad:
    mov edi,r14d; call g_phys_int_temp_free
.gepucm_bad:
    mov eax,1
.gepucm_done:
    cmp dword ptr [rsp+8],-1; je .gepucm_return
    push rax
    cmp eax,0; jne .gepucm_preserved_free
    mov edi,[rsp+20]; mov esi,ebx; call g_emit_phys_gpr_move
    mov [rsp],rax
.gepucm_preserved_free:
    mov edi,[rsp+16]; call g_phys_int_temp_free
    pop rax
.gepucm_return:
    add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Immediate SHL/SHR is the ConstantFact form of the same checked shift.
# edi=12/13, esi=dst, edx=proved count in [0,63].
g_emit_phys_gpr_shift_imm:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    test edx,edx; jz .gepsi_ok
    mov eax,r12d; shr eax,3; and eax,1; or eax,0x48
    mov edi,eax; call g_emit_u8
    mov edi,0xC1; call g_emit_u8
    mov eax,r12d; and eax,7; or eax,0xE0
    cmp ebx,12; je .gepsi_modrm
    or eax,8
.gepsi_modrm:
    mov edi,eax; call g_emit_u8
    mov edi,r13d; call g_emit_u8
.gepsi_ok:
    xor eax,eax
    pop r13; pop r12; pop rbx; ret

# edi=integer relation, esi=dst, edx=rhs GPR, ecx=type.
# RCX is also a next-StateFact carrier. Preserve it around the architectural
# CL/DIV operand; RAX/RDX are the established implicit scratch domain.
g_emit_phys_int_binary_relation:
    cmp edi,12; jae .gepibr_checked
    jmp g_emit_phys_gpr_bin2
.gepibr_checked:
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12d,esi; mov r13d,edx; mov r14d,ecx
    mov edi,0x51; call g_emit_u8                  # preserve next RCX
    xor edi,edi; mov esi,r12d; call g_emit_phys_gpr_move
    mov edi,1; mov esi,r13d; call g_emit_phys_gpr_move
    cmp ebx,13; jbe .gepibr_shift
    mov edi,r14d; call g_emit_int_divmod_core
    cmp ebx,15; jne .gepibr_result
    mov edi,0xD08948; call g_emit_u24       # mov rax,rdx
    jmp .gepibr_result
.gepibr_shift:
    lea rdi,[rip+gc_check_shift_rcx]; mov esi,gc_check_shift_rcx_end-gc_check_shift_rcx; call g_emit_bytes
    mov edi,0xD348; call g_emit_u16
    mov edi,0xE0; cmp ebx,12; je .gepibr_shift_opcode
    mov edi,0xE8
.gepibr_shift_opcode:
    call g_emit_u8
.gepibr_result:
    mov edi,0x59; call g_emit_u8                  # restore next RCX
    mov edi,r12d; xor esi,esi; call g_emit_phys_gpr_move
    xor eax,eax
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=expected integer type -> eax=1, edx=resident GPR; else eax=0.
g_phys_int_direct_source:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    cmp qword ptr [r12],J_OBJECT; jne .gpids_done
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpids_cse
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpids_no
    cmp dword ptr [rax+16],r13d; jne .gpids_no
    mov ecx,dword ptr [rax+24]
    mov rdx,[rip+g_reg_iter_carrier_kind_ptr]
    mov edx,dword ptr [rdx+rcx*4]
    cmp edx,G_PHYS_CARRIER_COUNTER; je .gpids_counter
    cmp edx,G_PHYS_CARRIER_INT; jne .gpids_no
    mov rdx,[rip+g_reg_iter_old_reg_ptr]
    mov edx,dword ptr [rdx+rcx*4]
    cmp edx,0; jl .gpids_no
    mov eax,1; jmp .gpids_done
.gpids_counter:
    mov edx,3                              # RBX
    mov eax,1; jmp .gpids_done
.gpids_cse:
.gpids_no:
    xor eax,eax
.gpids_done:
    pop r13; pop r12; pop rbx; ret

# The native word carrier accepts semantic predicates without another state ABI.
g_emit_phys_gpr_value_to:
    cmp edx,GTYPE_BOOL; jne g_emit_phys_int_expr_to
    push rbx
    mov ebx,esi
    call g_emit_phys_bool_expr_to_rax
    test eax,eax; jnz .gepgv_bad
    mov edi,ebx; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepgv_bad
    mov eax,GTYPE_BOOL; pop rbx; ret
.gepgv_bad: xor eax,eax; pop rbx; ret

# rdi=expr, esi=destination GPR code, edx=GTYPE_U64/I64 -> eax type/0.
g_emit_phys_int_expr_to:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi; mov r13d,esi; mov r14d,edx
    cmp r14d,GTYPE_U64; je .gpie_type_ok
    cmp r14d,GTYPE_I64; jne .gpie_bad
.gpie_type_ok:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpie_register_source
    mov rdi,r12; mov esi,r14d; call g_phys_cse_find_resident
    cmp eax,0; jl .gpie_register_source
    mov edi,eax; mov esi,r14d; call g_emit_packet_resident_rax
    mov edi,r13d; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done
.gpie_register_source:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpie_real_source
    mov rdi,r12; mov esi,r14d; call g_phys_cse_find_resident
    cmp eax,0; jl .gpie_real_source
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov edi,[rcx+rax*4]
    mov esi,GTYPE_F64; call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gpie_bad
    mov edi,r13d; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done
.gpie_real_source:
    cmp r13d,15; ja .gpie_bad
    cmp qword ptr [r12],J_OBJECT; jne .gpie_bad

    mov rdi,r12; mov esi,r14d; call g_phys_int_direct_source
    test eax,eax; jz .gpie_literal
    mov edi,r13d; mov esi,edx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done

.gpie_literal:
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpie_var
    mov r15,rax
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpie_bad
    mov rdi,rax; call g_type_from_node; cmp eax,r14d; jne .gpie_bad
    cmp r14d,GTYPE_U64; je .gpie_lit_u64
    mov rdi,r15; call g_parse_i64_node; test edx,edx; jnz .gpie_bad
    jmp .gpie_lit_emit
.gpie_lit_u64:
    mov rax,r15; call node_parse_u64; test edx,edx; jnz .gpie_bad
.gpie_lit_emit:
    mov rdi,rax; call g_emit_mov_rax_imm64
    test eax,eax; jnz .gpie_bad
    mov edi,r13d; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done

.gpie_var:
    mov rdi,r12; call g_phys_episode_load_source
    test rax,rax; jz .gpie_axis
    mov rdi,rax; mov esi,r13d; mov edx,r14d; call g_emit_phys_int_expr_to
    jmp .gpie_done
.gpie_axis:
    cmp dword ptr [rip+g_phys_stack_episode],0; je .gpie_var_leaf
    mov rdi,r12; lea rsi,[rip+gk_axis]; mov edx,gk_axis_end-gk_axis; call obj_get
    test rax,rax; jz .gpie_var_leaf
    mov edi,r13d; mov esi,10; call g_emit_phys_gpr_move
    mov eax,r14d; jmp .gpie_done
.gpie_var_leaf:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpie_state_invalid_or_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gpie_bad
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gpie_bad
    mov r15,rax
    cmp dword ptr [r15+20],r14d; jne .gpie_bad
    cmp dword ptr [r15+24],-1; je .gpie_bad
    cmp dword ptr [r15+16],GK_INPUT; je .gpie_var_input
    mov eax,dword ptr [r15+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    jmp .gpie_var_loaded
.gpie_var_input:
    mov eax,dword ptr [r15+24]; call g_input_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
.gpie_var_loaded:
    mov edi,r13d; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done

.gpie_state_invalid_or_op:
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpie_op_probe
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpie_bad
    cmp dword ptr [rax+16],r14d; jne .gpie_bad
    mov ecx,dword ptr [rax+24]
    mov rdx,[rip+g_reg_iter_carrier_kind_ptr]
    cmp dword ptr [rdx+rcx*4],G_PHYS_CARRIER_COUNTER; je .gpie_bad
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; cmp dword ptr [rdx+rcx*4],0; jge .gpie_bad
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov edi,r13d; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done
.gpie_op_probe:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpie_bad
    mov r15,rax
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jnz .gpie_cast
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gpie_not_select
    mov rdi,r12; mov esi,r13d; mov edx,r14d; call g_emit_phys_int_select_to
    jmp .gpie_done
.gpie_cast:
    mov rdi,r12; call g_infer_expr; cmp eax,r14d; jne .gpie_bad
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpie_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpie_bad
    cmp qword ptr [rbx+32],0; jne .gpie_bad
    mov rdi,rbx; call g_infer_expr; mov dword ptr [rsp+16],eax
    cmp eax,GTYPE_I64; je 782f
    cmp eax,GTYPE_U64; je 782f
    cmp eax,GTYPE_F32; je .gpie_cast_native_fp
    cmp eax,GTYPE_F64; jne .gpie_bad
.gpie_cast_native_fp:
    call g_phys_fp_temp_alloc; cmp eax,0; jl .gpie_bad
    mov dword ptr [rsp+20],eax
    mov rdi,rbx; mov esi,eax; mov edx,dword ptr [rsp+16]; call g_emit_phys_fp_value_to
    cmp eax,dword ptr [rsp+16]; jne .gpie_cast_fp_bad
    mov edi,r13d; mov esi,dword ptr [rsp+20]; mov edx,dword ptr [rsp+16]
    cmp r14d,GTYPE_U64; jne .gpie_cast_signed
    call g_emit_phys_cvt_fp_u64; jmp .gpie_cast_converted
.gpie_cast_signed:
    call g_emit_phys_cvt_fp_i64
.gpie_cast_converted:
    test eax,eax; jnz .gpie_cast_fp_bad
    mov edi,dword ptr [rsp+20]; call g_phys_fp_temp_free
    mov eax,r14d; jmp .gpie_done
.gpie_cast_fp_bad:
    mov edi,dword ptr [rsp+20]; call g_phys_fp_temp_free
    jmp .gpie_bad
782:mov rdi,rbx; mov esi,r13d; mov edx,dword ptr [rsp+16]; call g_emit_phys_int_expr_to
    cmp eax,dword ptr [rsp+16]; jne .gpie_bad
    mov eax,r14d; jmp .gpie_done

.gpie_not_select:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_bit_not]; mov ecx,gv_bit_not_end-gv_bit_not; call span_eq
    test eax,eax; jnz .gpie_bit_not
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq
    test eax,eax; jnz .gpie_neg
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jnz .gpie_abs
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jz 1f
    mov dword ptr [rsp+8],1; jmp .gpie_op_ready
1:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jz 2f
    mov dword ptr [rsp+8],2; jmp .gpie_op_ready
2:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jz 3f
    cmp dword ptr [rip+g_overflow_wrap],1; je 21f
    cmp r14d,GTYPE_U64; je .gpie_bad
21: mov dword ptr [rsp+8],3; jmp .gpie_op_ready
3:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_bit_and]; mov ecx,gv_bit_and_end-gv_bit_and; call span_eq
    test eax,eax; jz 31f
    mov dword ptr [rsp+8],5; jmp .gpie_op_ready
31: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq
    test eax,eax; jz 32f
    mov dword ptr [rsp+8],6; jmp .gpie_op_ready
32: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq
    test eax,eax; jz 33f
    mov dword ptr [rsp+8],7; jmp .gpie_op_ready
33: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq
    test eax,eax; jz 34f
    mov eax,8; cmp r14d,GTYPE_I64; jne 331f; mov eax,10
331:mov dword ptr [rsp+8],eax; jmp .gpie_op_ready
34: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq
    test eax,eax; jz 35f
    mov eax,9; cmp r14d,GTYPE_I64; jne 341f; mov eax,11
341:mov dword ptr [rsp+8],eax; jmp .gpie_op_ready
35: mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq
    test eax,eax; jz .gpie_probe_shr
    mov dword ptr [rsp+8],12; jmp .gpie_op_ready
.gpie_probe_shr:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq
    test eax,eax; jz .gpie_probe_div
    mov dword ptr [rsp+8],13; jmp .gpie_op_ready
.gpie_probe_div:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jz .gpie_probe_mod
    mov dword ptr [rsp+8],14; jmp .gpie_op_ready
.gpie_probe_mod:
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq
    test eax,eax; jz .gpie_bad
    cmp r14d,GTYPE_U64; jne .gpie_bad
    mov dword ptr [rsp+8],15
    jmp .gpie_op_ready
.gpie_bit_not:
    mov dword ptr [rsp+8],0
    jmp .gpie_unary_emit
.gpie_neg:
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gpie_bad
    mov dword ptr [rsp+8],1
    jmp .gpie_unary_emit
.gpie_abs:
    cmp r14d,GTYPE_U64; je .gpie_unary_identity
    cmp r14d,GTYPE_I64; jne .gpie_bad
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gpie_bad
    mov dword ptr [rsp+8],2
    jmp .gpie_unary_emit
.gpie_unary_identity:
    mov dword ptr [rsp+8],3
.gpie_unary_emit:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpie_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpie_bad
    cmp qword ptr [rbx+32],0; jne .gpie_bad
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_int_expr_to
    cmp eax,r14d; jne .gpie_bad
    cmp dword ptr [rsp+8],3; je .gpie_unary_done
    cmp dword ptr [rsp+8],2; je .gpie_abs_wrap_emit
    mov edi,dword ptr [rsp+8]; mov esi,r13d; call g_emit_phys_gpr_unary
    test eax,eax; jnz .gpie_bad
    jmp .gpie_unary_done
.gpie_abs_wrap_emit:
    mov edi,r13d; call g_emit_phys_i64_abs_wrap_inplace
    test eax,eax; jnz .gpie_bad
.gpie_unary_done:
    mov eax,r14d; jmp .gpie_done

.gpie_op_ready:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpie_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpie_bad
    mov r15,[rbx+32]; test r15,r15; jz .gpie_bad
    cmp qword ptr [r15+32],0; jne .gpie_bad

    # A nonzero unsigned ConstantFact projects to the existing exact reciprocal
    # authority. Dynamic/signed divisors retain the checked ISA divmod relation.
    mov eax,[rsp+8]; cmp eax,14; jb .gpie_args_ready
    cmp eax,15; ja .gpie_args_ready
    cmp r14d,GTYPE_U64; jne .gpie_args_ready
    mov rdi,r15; call g_expr_u64_literal; test edx,edx; jnz .gpie_args_ready
    test rax,rax; jz .gpie_args_ready
    mov ecx,[rsp+8]; sub ecx,14; xor ecx,1; mov [rsp+12],ecx
    mov dword ptr [rsp+8],4
    mov [rsp+16],rax
    jmp .gpie_args_ready
.gpie_args_ready:

    # Preserve the left-to-right AST relation. A resident LHS is copied once
    # into the final destination; a complex LHS is born there directly.
    mov rdi,rbx; mov esi,r14d; call g_phys_int_direct_source
    test eax,eax; jz .gpie_lhs_complex
    mov edi,r13d; mov esi,edx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gpie_bad
    jmp .gpie_lhs_ready
.gpie_lhs_complex:
    mov rdi,rbx; mov esi,r13d; mov edx,r14d; call g_emit_phys_int_expr_to
    cmp eax,r14d; jne .gpie_bad
.gpie_lhs_ready:
    cmp dword ptr [rsp+8],4; jne .gpie_rhs_literal_probe
    mov edi,r13d; mov rsi,[rsp+16]
    mov ecx,[rsp+12]; call g_emit_phys_u64_const_divmod
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done

.gpie_rhs_literal_probe:
    mov eax,dword ptr [rsp+8]
    cmp eax,12; je .gpie_shift_literal_probe
    cmp eax,13; jne .gpie_rhs_arithmetic_literal
.gpie_shift_literal_probe:
    mov rdi,r15; call g_expr_u64_literal; test edx,edx; jnz .gpie_rhs_normal
    cmp rax,64; jae .gpie_rhs_normal
    test rax,rax; jz .gpie_rhs_literal_done
    mov edx,eax; mov esi,r13d; mov edi,dword ptr [rsp+8]
    call g_emit_phys_gpr_shift_imm
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done
.gpie_rhs_arithmetic_literal:
    # A literal is an ISA operand form, not automatically a runtime ValueFact.
    # When its exact bits fit the architectural sign-extended imm32 field,
    # add/sub/mul/bitwise consume it in place and no transient GPR is born.
    mov eax,dword ptr [rsp+8]
    cmp eax,1; je .gpie_rhs_literal_type
    cmp eax,2; je .gpie_rhs_literal_type
    cmp eax,3; je .gpie_rhs_literal_type
    cmp eax,5; je .gpie_rhs_literal_type
    cmp eax,6; je .gpie_rhs_literal_type
    cmp eax,7; jne .gpie_rhs_normal
.gpie_rhs_literal_type:
    mov rdi,r15; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpie_rhs_normal
    mov [rsp+16],rax
    mov rdi,r15; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpie_rhs_normal
    mov rdi,rax; call g_type_from_node; cmp eax,r14d; jne .gpie_rhs_normal
    cmp r14d,GTYPE_U64; je .gpie_rhs_literal_u64
    mov rdi,[rsp+16]; call g_parse_i64_node; test edx,edx; jnz .gpie_rhs_normal
    jmp .gpie_rhs_literal_exact
.gpie_rhs_literal_u64:
    mov rax,[rsp+16]; call node_parse_u64; test edx,edx; jnz .gpie_rhs_normal
.gpie_rhs_literal_exact:
    mov ecx,[rsp+8]
    test rax,rax; jnz .gpie_nonzero_literal
    cmp ecx,1; je .gpie_rhs_literal_done
    cmp ecx,2; je .gpie_rhs_literal_done
    cmp ecx,6; je .gpie_rhs_literal_done
    cmp ecx,7; je .gpie_rhs_literal_done
.gpie_nonzero_literal:
    cmp ecx,3; jne .gpie_identity_and
    cmp rax,1; je .gpie_rhs_literal_done
.gpie_identity_and:
    cmp ecx,5; jne .gpie_imm32_projection
    cmp rax,-1; je .gpie_rhs_literal_done
.gpie_imm32_projection:
    movsxd rcx,eax
    cmp rcx,rax; jne .gpie_rhs_normal
    mov edx,eax
    mov edi,dword ptr [rsp+8]; mov esi,r13d
    call g_emit_phys_gpr_imm32_bin2
    test eax,eax; jnz .gpie_bad
    cmp dword ptr [rsp+8],3; ja .gpie_rhs_literal_done
    mov edi,dword ptr [rsp+8]; mov esi,r14d; call g_emit_phys_int_overflow_guard
    test eax,eax; jnz .gpie_bad
.gpie_rhs_literal_done:
    mov eax,r14d; jmp .gpie_done

.gpie_rhs_normal:
    mov rdi,r15; mov esi,r14d; call g_phys_int_direct_source
    test eax,eax; jz .gpie_rhs_complex
    mov edi,dword ptr [rsp+8]; mov esi,r13d
    mov ecx,r14d; call g_emit_phys_int_binary_relation
    test eax,eax; jnz .gpie_bad
    cmp dword ptr [rsp+8],3; ja .gpie_direct_no_guard
    mov edi,dword ptr [rsp+8]; mov esi,r14d; call g_emit_phys_int_overflow_guard
    test eax,eax; jnz .gpie_bad
.gpie_direct_no_guard:
    mov eax,r14d; jmp .gpie_done

.gpie_rhs_complex:
    call g_phys_int_temp_alloc
    cmp eax,0; jl .gpie_bad
    mov dword ptr [rsp],eax
    mov rdi,r15; mov esi,eax; mov edx,r14d; call g_emit_phys_int_expr_to
    cmp eax,r14d; jne .gpie_rhs_temp_fail
    mov edx,dword ptr [rsp]
    mov edi,dword ptr [rsp+8]; mov esi,r13d; mov ecx,r14d; call g_emit_phys_int_binary_relation
    test eax,eax; jnz .gpie_rhs_temp_fail
    cmp dword ptr [rsp+8],3; ja .gpie_temp_no_guard
    mov edi,dword ptr [rsp+8]; mov esi,r14d; call g_emit_phys_int_overflow_guard
    test eax,eax; jnz .gpie_rhs_temp_fail
.gpie_temp_no_guard:
    mov edi,dword ptr [rsp]; call g_phys_int_temp_free
    mov eax,r14d; jmp .gpie_done
.gpie_rhs_temp_fail:
    mov edi,dword ptr [rsp]; call g_phys_int_temp_free
.gpie_bad:
    xor eax,eax
.gpie_done:
    test eax,eax; jz .gpie_return
    push rax
    mov rdi,r12; mov esi,r14d; mov edx,r13d; call g_phys_cse_retain_integer
    pop rax
.gpie_return:
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret



# ---------------- machine-code operation emitters ----------------
# Stack convention before binary helper: [... lhs rhs].
# Most fragments consume both and push result.
g_emit_cast_top:
    # eax=src, edx=dst, returns eax=0/1
    cmp eax,edx; je .gec_ok
    push rax; push rdx
    mov edi,eax; call g_is_rankn_fp; mov ecx,eax
    mov edi,[rsp]; call g_is_rankn_fp; or ecx,eax
    pop rdx; pop rax
    test ecx,ecx; jnz .gec_wide
    cmp eax,GTYPE_U64; je .gec_from_u
    cmp eax,GTYPE_I64; je .gec_from_i
    cmp eax,GTYPE_F32; je .gec_from_f32
    cmp eax,GTYPE_F64; je .gec_from_f64
    mov eax,1; ret
.gec_from_u:
    cmp edx,GTYPE_F64; je .gec_u_f64
    cmp edx,GTYPE_F32; je .gec_u_f32
    cmp edx,GTYPE_I64; je .gec_ok
    mov eax,1; ret
.gec_u_f64: mov edi,GTYPE_U64; mov esi,GTYPE_F64; jmp g_emit_int_fp_stack
.gec_u_f32: mov edi,GTYPE_U64; mov esi,GTYPE_F32; jmp g_emit_int_fp_stack
.gec_from_i:
    cmp edx,GTYPE_F64; je .gec_i_f64
    cmp edx,GTYPE_F32; je .gec_i_f32
    cmp edx,GTYPE_U64; je .gec_ok
    mov eax,1; ret
.gec_i_f64: mov edi,GTYPE_I64; mov esi,GTYPE_F64; jmp g_emit_int_fp_stack
.gec_i_f32: mov edi,GTYPE_I64; mov esi,GTYPE_F32; jmp g_emit_int_fp_stack
.gec_from_f32:
    cmp edx,GTYPE_F64; je .gec_f32_f64
    cmp edx,GTYPE_U64; je .gec_f32_u64
    cmp edx,GTYPE_I64; je .gec_f32_i64
    mov eax,1; ret
.gec_f32_f64: lea rdi,[rip+gc_cast_f32_f64]; mov esi,gc_cast_f32_f64_end-gc_cast_f32_f64; call g_emit_bytes; xor eax,eax; ret
.gec_f32_u64: mov edi,GTYPE_F32; jmp g_emit_fp_u64_stack
.gec_f32_i64: lea rdi,[rip+gc_cast_f32_i64]; mov esi,gc_cast_f32_i64_end-gc_cast_f32_i64; call g_emit_bytes; xor eax,eax; ret
.gec_from_f64:
    cmp edx,GTYPE_F32; je .gec_f64_f32
    cmp edx,GTYPE_U64; je .gec_f64_u64
    cmp edx,GTYPE_I64; je .gec_f64_i64
    mov eax,1; ret
.gec_f64_f32: lea rdi,[rip+gc_cast_f64_f32]; mov esi,gc_cast_f64_f32_end-gc_cast_f64_f32; call g_emit_bytes; xor eax,eax; ret
.gec_f64_u64: mov edi,GTYPE_F64; jmp g_emit_fp_u64_stack
.gec_f64_i64: lea rdi,[rip+gc_cast_f64_i64]; mov esi,gc_cast_f64_i64_end-gc_cast_f64_i64; call g_emit_bytes; xor eax,eax; ret
.gec_wide:
    mov edi,eax; mov esi,edx; jmp g_emit_rankn_fp_cast_top
.gec_ok: xor eax,eax; ret

# op ptr,len, lhs type edx, rhs ecx, result r8d
g_emit_arithmetic_top2:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r14d,edx; mov r15d,ecx; mov ebx,r8d
    cmp ebx,GTYPE_F32; je .gea_f32
    cmp ebx,GTYPE_F64; je .gea_f64
    mov edi,ebx; call g_is_rankn_fp; test eax,eax; jnz .gea_rankn_fp
    cmp ebx,GTYPE_U64; je .gea_u64
    cmp ebx,GTYPE_I64; je .gea_i64
    jmp .gea_bad
.gea_f64:
    mov edi,r15d; mov esi,GTYPE_F64; call g_convert_stack_top; test eax,eax; jnz .gea_bad
    mov edi,r14d; mov esi,GTYPE_F64; call g_convert_stack_second; test eax,eax; jnz .gea_bad
    mov rdi,r12; mov rsi,r13; call g_emit_float64_op; jmp .gea_ret
.gea_f32:
    mov edi,r15d; mov esi,GTYPE_F32; call g_convert_stack_top; test eax,eax; jnz .gea_bad
    mov edi,r14d; mov esi,GTYPE_F32; call g_convert_stack_second; test eax,eax; jnz .gea_bad
    mov rdi,r12; mov rsi,r13; call g_emit_float32_op; jmp .gea_ret
.gea_rankn_fp:
    mov edi,r15d; mov esi,ebx; call g_convert_stack_top; test eax,eax; jnz .gea_bad
    mov edi,r14d; mov esi,ebx; call g_convert_stack_second; test eax,eax; jnz .gea_bad
    mov rdi,r12; mov rsi,r13; mov edx,ebx; call g_emit_rankn_fp_binary_op; jmp .gea_ret
.gea_u64:
    mov rdi,r12; mov rsi,r13; mov edx,GTYPE_U64; call g_emit_int_op; jmp .gea_ret
.gea_i64:
    mov rdi,r12; mov rsi,r13; mov edx,GTYPE_I64; call g_emit_int_op; jmp .gea_ret
.gea_bad: mov eax,1
.gea_ret: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Numeric representation conversions for mixed arithmetic/comparison.
# These are explicit because g_low_type may legally choose a floating common
# representation for integer/floating operands.  A failed conversion is never
# ignored by the callers.
g_convert_stack_top:
    cmp edi,esi; je .gcst_ok
    push rdi; push rsi
    call g_is_rankn_fp; mov edx,eax
    mov edi,[rsp]; call g_is_rankn_fp; or edx,eax
    pop rsi; pop rdi
    test edx,edx; jnz .gcst_rankn
    cmp edi,GTYPE_F64; je .gcst_from_f64
    cmp edi,GTYPE_F32; je .gcst_from_f32
    cmp edi,GTYPE_U64; je .gcst_from_u64
    cmp edi,GTYPE_I64; je .gcst_from_i64
    jmp .gcst_bad
.gcst_from_f64:
    cmp esi,GTYPE_F32; jne .gcst_bad
    lea rdi,[rip+gc_top_f64_to_f32]; mov esi,gc_top_f64_to_f32_end-gc_top_f64_to_f32; call g_emit_bytes; ret
.gcst_from_f32:
    cmp esi,GTYPE_F64; jne .gcst_bad
    lea rdi,[rip+gc_top_f32_to_f64]; mov esi,gc_top_f32_to_f64_end-gc_top_f32_to_f64; call g_emit_bytes; ret
.gcst_from_u64:
    cmp esi,GTYPE_F64; je .gcst_u64_f64
    cmp esi,GTYPE_F32; je .gcst_u64_f32
    jmp .gcst_bad
.gcst_u64_f64: jmp g_emit_int_fp_stack
.gcst_u64_f32: jmp g_emit_int_fp_stack
.gcst_from_i64:
    cmp esi,GTYPE_F64; je .gcst_i64_f64
    cmp esi,GTYPE_F32; je .gcst_i64_f32
    jmp .gcst_bad
.gcst_i64_f64: jmp g_emit_int_fp_stack
.gcst_i64_f32: jmp g_emit_int_fp_stack
.gcst_rankn: jmp g_emit_rankn_fp_cast_top
.gcst_ok: xor eax,eax; ret
.gcst_bad: mov eax,1; ret

g_convert_stack_second:
    cmp edi,esi; je .gcss_ok
    push rdi; push rsi
    call g_is_rankn_fp; mov edx,eax
    mov edi,[rsp]; call g_is_rankn_fp; or edx,eax
    pop rsi; pop rdi
    test edx,edx; jnz .gcss_rankn
    cmp edi,GTYPE_F64; je .gcss_from_f64
    cmp edi,GTYPE_F32; je .gcss_from_f32
    cmp edi,GTYPE_U64; je .gcss_from_u64
    cmp edi,GTYPE_I64; je .gcss_from_i64
    jmp .gcss_bad
.gcss_from_f64:
    cmp esi,GTYPE_F32; jne .gcss_bad
    lea rdi,[rip+gc_second_f64_to_f32]; mov esi,gc_second_f64_to_f32_end-gc_second_f64_to_f32; call g_emit_bytes; ret
.gcss_from_f32:
    cmp esi,GTYPE_F64; jne .gcss_bad
    lea rdi,[rip+gc_second_f32_to_f64]; mov esi,gc_second_f32_to_f64_end-gc_second_f32_to_f64; call g_emit_bytes; ret
.gcss_from_u64:
    cmp esi,GTYPE_F64; je .gcss_u64_f64
    cmp esi,GTYPE_F32; je .gcss_u64_f32
    jmp .gcss_bad
.gcss_u64_f64: lea rdi,[rip+gc_second_u64_to_f64]; mov esi,gc_second_u64_to_f64_end-gc_second_u64_to_f64; call g_emit_bytes; ret
.gcss_u64_f32: lea rdi,[rip+gc_second_u64_to_f32]; mov esi,gc_second_u64_to_f32_end-gc_second_u64_to_f32; call g_emit_bytes; ret
.gcss_from_i64:
    cmp esi,GTYPE_F64; je .gcss_i64_f64
    cmp esi,GTYPE_F32; je .gcss_i64_f32
    jmp .gcss_bad
.gcss_i64_f64: lea rdi,[rip+gc_second_i64_to_f64]; mov esi,gc_second_i64_to_f64_end-gc_second_i64_to_f64; call g_emit_bytes; ret
.gcss_i64_f32: lea rdi,[rip+gc_second_i64_to_f32]; mov esi,gc_second_i64_to_f32_end-gc_second_i64_to_f32; call g_emit_bytes; ret
.gcss_rankn: jmp g_emit_rankn_fp_cast_second
.gcss_ok: xor eax,eax; ret
.gcss_bad: mov eax,1; ret

g_emit_float64_op:
    mov edx,GTYPE_F64; jmp g_emit_native_fp_op
g_emit_float32_op:
    mov edx,GTYPE_F32
# Operator table is the one authority for both native FP widths.
g_emit_native_fp_op:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14d,edx; lea rbx,[rip+g_native_fp_op_table]
.genfo_find:
    cmp qword ptr [rbx],0; je .genfo_bad
    mov rdi,r12; mov rsi,r13; mov rdx,[rbx]; mov ecx,dword ptr [rbx+8]; call span_eq
    test eax,eax; jnz .genfo_found
    add rbx,48; jmp .genfo_find
.genfo_found:
    cmp r14d,GTYPE_F64; je 1f
    add rbx,16
1:  mov rdi,[rbx+16]; mov esi,dword ptr [rbx+24]; call g_emit_bytes
    jmp .genfo_done
.genfo_bad: mov eax,1
.genfo_done: pop r14; pop r13; pop r12; pop rbx; ret

# rdi=operator span,rsi=length,edx=natural FP type -> rax=old ISA fragment,
# ecx=bytes, or zero. This is the local primitive relation, not a solver route.
g_native_fp_math_fragment:
    cmp edx,GTYPE_F64; je 1f
    cmp edx,GTYPE_F32; jne 2f
    mov edx,32; jmp physical_math_fragment
1:  mov edx,64; jmp physical_math_fragment
2:  xor eax,eax; xor ecx,ecx; ret

# integer op including trap/wrap. rdi op ptr,rsi len,edx type
g_emit_int_op:
    push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gei_add
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gei_sub
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gei_mul
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jnz .gei_div
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq; test eax,eax; jnz .gei_min
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq; test eax,eax; jnz .gei_max
    mov eax,1; jmp .gei_done
.gei_add:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gei_add_wrap
    cmp r14d,GTYPE_I64; je .gei_add_signed
    lea rdi,[rip+gc_uadd_trap]; mov esi,gc_uadd_trap_end-gc_uadd_trap; call g_emit_bytes; jmp .gei_done
.gei_add_signed: lea rdi,[rip+gc_iadd_trap]; mov esi,gc_iadd_trap_end-gc_iadd_trap; call g_emit_bytes; jmp .gei_done
.gei_add_wrap: lea rdi,[rip+gc_add_wrap]; mov esi,gc_add_wrap_end-gc_add_wrap; call g_emit_bytes; jmp .gei_done
.gei_sub:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gei_sub_wrap
    cmp r14d,GTYPE_I64; je .gei_sub_signed
    lea rdi,[rip+gc_usub_trap]; mov esi,gc_usub_trap_end-gc_usub_trap; call g_emit_bytes; jmp .gei_done
.gei_sub_signed: lea rdi,[rip+gc_isub_trap]; mov esi,gc_isub_trap_end-gc_isub_trap; call g_emit_bytes; jmp .gei_done
.gei_sub_wrap: lea rdi,[rip+gc_sub_wrap]; mov esi,gc_sub_wrap_end-gc_sub_wrap; call g_emit_bytes; jmp .gei_done
.gei_mul:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gei_mul_wrap
    cmp r14d,GTYPE_I64; je .gei_mul_signed
    lea rdi,[rip+gc_umul_trap]; mov esi,gc_umul_trap_end-gc_umul_trap; call g_emit_bytes; jmp .gei_done
.gei_mul_signed: lea rdi,[rip+gc_imul_trap]; mov esi,gc_imul_trap_end-gc_imul_trap; call g_emit_bytes; jmp .gei_done
.gei_mul_wrap: lea rdi,[rip+gc_mul_wrap]; mov esi,gc_mul_wrap_end-gc_mul_wrap; call g_emit_bytes; jmp .gei_done
.gei_div:
    mov edi,0x5859; call g_emit_u16
    mov edi,r14d; call g_emit_int_divmod_core
    mov edi,0x50; call g_emit_u8
    jmp .gei_done
.gei_min:
    cmp r14d,GTYPE_I64; je .gei_min_i
    lea rdi,[rip+gc_umin]; mov esi,gc_umin_end-gc_umin; call g_emit_bytes; jmp .gei_done
.gei_min_i: lea rdi,[rip+gc_imin]; mov esi,gc_imin_end-gc_imin; call g_emit_bytes; jmp .gei_done
.gei_max:
    cmp r14d,GTYPE_I64; je .gei_max_i
    lea rdi,[rip+gc_umax]; mov esi,gc_umax_end-gc_umax; call g_emit_bytes; jmp .gei_done
.gei_max_i: lea rdi,[rip+gc_imax]; mov esi,gc_imax_end-gc_imax; call g_emit_bytes
.gei_done: pop r14; pop r13; pop r12; ret

# rdi=operator span,rsi=len.  Both runtime stack operands are already the same
# fpP representation.  The runtime authority returns only -1/0/+1; predicate
# projection is branchless and shared by every precision P>64.
g_emit_rankn_fp_compare_top2:
    push r12; push r13
    mov r12,rdi; mov r13,rsi
    mov edi,0x5E; call g_emit_u8                   # pop rsi = rhs pointer
    mov edi,0x5F; call g_emit_u8                   # pop rdi = lhs pointer
    mov rdi,GENERAL_RANKN_FP_CMP_VA; call g_emit_call_abs
    test eax,eax; jnz .gerfc_bad
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq; test eax,eax; jnz .gerfc_eq
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq; test eax,eax; jnz .gerfc_ne
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gerfc_lt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq; test eax,eax; jnz .gerfc_le
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq; test eax,eax; jnz .gerfc_gt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gerfc_ge
    jmp .gerfc_bad
.gerfc_eq: lea rdi,[rip+gc_rankn_cmp_eq]; mov esi,gc_rankn_cmp_eq_end-gc_rankn_cmp_eq; call g_emit_bytes; jmp .gerfc_ok
.gerfc_ne: lea rdi,[rip+gc_rankn_cmp_ne]; mov esi,gc_rankn_cmp_ne_end-gc_rankn_cmp_ne; call g_emit_bytes; jmp .gerfc_ok
.gerfc_lt: lea rdi,[rip+gc_rankn_cmp_lt]; mov esi,gc_rankn_cmp_lt_end-gc_rankn_cmp_lt; call g_emit_bytes; jmp .gerfc_ok
.gerfc_le: lea rdi,[rip+gc_rankn_cmp_le]; mov esi,gc_rankn_cmp_le_end-gc_rankn_cmp_le; call g_emit_bytes; jmp .gerfc_ok
.gerfc_gt: lea rdi,[rip+gc_rankn_cmp_gt]; mov esi,gc_rankn_cmp_gt_end-gc_rankn_cmp_gt; call g_emit_bytes; jmp .gerfc_ok
.gerfc_ge: lea rdi,[rip+gc_rankn_cmp_ge]; mov esi,gc_rankn_cmp_ge_end-gc_rankn_cmp_ge; call g_emit_bytes
.gerfc_ok: xor eax,eax; jmp .gerfc_done
.gerfc_bad: mov eax,1
.gerfc_done: pop r13; pop r12; ret

g_emit_compare_top2:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov ebx,edx; mov r14d,ecx
    # exact type for bool/string; numeric may low-dominate
    cmp ebx,GTYPE_STRING; je .gecmp_bad
    mov eax,ebx; mov edx,r14d; call g_low_type; test eax,eax; jz .gecmp_bad
    mov r15d,eax
    cmp r15d,GTYPE_F64; je .gecmp_f64
    cmp r15d,GTYPE_F32; je .gecmp_f32
    mov edi,r15d; call g_is_rankn_fp; test eax,eax; jnz .gecmp_rankn
    mov edx,r15d
    mov rdi,r12; mov rsi,r13; call g_emit_int_compare; jmp .gecmp_done
.gecmp_rankn:
    mov edi,r14d; mov esi,r15d; call g_convert_stack_top; test eax,eax; jnz .gecmp_bad
    mov edi,ebx; mov esi,r15d; call g_convert_stack_second; test eax,eax; jnz .gecmp_bad
    mov rdi,r12; mov rsi,r13; call g_emit_rankn_fp_compare_top2; jmp .gecmp_done
.gecmp_f64:
    mov edi,r14d; mov esi,GTYPE_F64; call g_convert_stack_top; test eax,eax; jnz .gecmp_bad
    mov edi,ebx; mov esi,GTYPE_F64; call g_convert_stack_second; test eax,eax; jnz .gecmp_bad
    mov rdi,r12; mov rsi,r13; call g_emit_f64_compare; jmp .gecmp_done
.gecmp_f32:
    mov edi,r14d; mov esi,GTYPE_F32; call g_convert_stack_top; test eax,eax; jnz .gecmp_bad
    mov edi,ebx; mov esi,GTYPE_F32; call g_convert_stack_second; test eax,eax; jnz .gecmp_bad
    mov rdi,r12; mov rsi,r13; call g_emit_f32_compare; jmp .gecmp_done
.gecmp_bad: mov eax,1
.gecmp_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi op ptr,rsi len,edx int type
g_emit_int_compare:
    push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    # Base fragment pops rhs rcx, lhs rax, cmp rax,rcx; then setcc al/movzx/push.
    lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq; test eax,eax; jnz .gic_eq
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq; test eax,eax; jnz .gic_ne
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gic_lt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq; test eax,eax; jnz .gic_le
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq; test eax,eax; jnz .gic_gt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gic_ge
    mov eax,1; jmp .gic_done
.gic_eq: lea rdi,[rip+gc_cmp_eq]; mov esi,gc_cmp_eq_end-gc_cmp_eq; call g_emit_bytes; jmp .gic_done
.gic_ne: lea rdi,[rip+gc_cmp_ne]; mov esi,gc_cmp_ne_end-gc_cmp_ne; call g_emit_bytes; jmp .gic_done
.gic_lt: cmp r14d,GTYPE_I64; je 1f; lea rdi,[rip+gc_cmp_b]; mov esi,gc_cmp_b_end-gc_cmp_b; call g_emit_bytes; jmp .gic_done
1: lea rdi,[rip+gc_cmp_l]; mov esi,gc_cmp_l_end-gc_cmp_l; call g_emit_bytes; jmp .gic_done
.gic_le: cmp r14d,GTYPE_I64; je 2f; lea rdi,[rip+gc_cmp_be]; mov esi,gc_cmp_be_end-gc_cmp_be; call g_emit_bytes; jmp .gic_done
2: lea rdi,[rip+gc_cmp_le]; mov esi,gc_cmp_le_end-gc_cmp_le; call g_emit_bytes; jmp .gic_done
.gic_gt: cmp r14d,GTYPE_I64; je 3f; lea rdi,[rip+gc_cmp_a]; mov esi,gc_cmp_a_end-gc_cmp_a; call g_emit_bytes; jmp .gic_done
3: lea rdi,[rip+gc_cmp_g]; mov esi,gc_cmp_g_end-gc_cmp_g; call g_emit_bytes; jmp .gic_done
.gic_ge: cmp r14d,GTYPE_I64; je 4f; lea rdi,[rip+gc_cmp_ae]; mov esi,gc_cmp_ae_end-gc_cmp_ae; call g_emit_bytes; jmp .gic_done
4: lea rdi,[rip+gc_cmp_ge]; mov esi,gc_cmp_ge_end-gc_cmp_ge; call g_emit_bytes
.gic_done: pop r14; pop r13; pop r12; ret

# Float comparisons emit ordered comparisons; NaN follows IEEE comparison results.
g_emit_f64_compare:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq; test eax,eax; jnz .gf64c_eq
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq; test eax,eax; jnz .gf64c_ne
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gf64c_lt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq; test eax,eax; jnz .gf64c_le
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq; test eax,eax; jnz .gf64c_gt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gf64c_ge
    mov eax,1; jmp .gf64c_done
.gf64c_eq: lea rdi,[rip+gc_f64_cmp_eq]; mov esi,gc_f64_cmp_eq_end-gc_f64_cmp_eq; call g_emit_bytes; jmp .gf64c_done
.gf64c_ne: lea rdi,[rip+gc_f64_cmp_ne]; mov esi,gc_f64_cmp_ne_end-gc_f64_cmp_ne; call g_emit_bytes; jmp .gf64c_done
.gf64c_lt: lea rdi,[rip+gc_f64_cmp_lt]; mov esi,gc_f64_cmp_lt_end-gc_f64_cmp_lt; call g_emit_bytes; jmp .gf64c_done
.gf64c_le: lea rdi,[rip+gc_f64_cmp_le]; mov esi,gc_f64_cmp_le_end-gc_f64_cmp_le; call g_emit_bytes; jmp .gf64c_done
.gf64c_gt: lea rdi,[rip+gc_f64_cmp_gt]; mov esi,gc_f64_cmp_gt_end-gc_f64_cmp_gt; call g_emit_bytes; jmp .gf64c_done
.gf64c_ge: lea rdi,[rip+gc_f64_cmp_ge]; mov esi,gc_f64_cmp_ge_end-gc_f64_cmp_ge; call g_emit_bytes
.gf64c_done: pop r13; pop r12; ret
g_emit_f32_compare:
    # Same opcode family with UCOMISS instead of UCOMISD.
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_eq]; mov ecx,gv_eq_end-gv_eq; call span_eq; test eax,eax; jnz .gf32c_eq
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ne]; mov ecx,gv_ne_end-gv_ne; call span_eq; test eax,eax; jnz .gf32c_ne
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gf32c_lt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq; test eax,eax; jnz .gf32c_le
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq; test eax,eax; jnz .gf32c_gt
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gf32c_ge
    mov eax,1; jmp .gf32c_done
.gf32c_eq: lea rdi,[rip+gc_f32_cmp_eq]; mov esi,gc_f32_cmp_eq_end-gc_f32_cmp_eq; call g_emit_bytes; jmp .gf32c_done
.gf32c_ne: lea rdi,[rip+gc_f32_cmp_ne]; mov esi,gc_f32_cmp_ne_end-gc_f32_cmp_ne; call g_emit_bytes; jmp .gf32c_done
.gf32c_lt: lea rdi,[rip+gc_f32_cmp_lt]; mov esi,gc_f32_cmp_lt_end-gc_f32_cmp_lt; call g_emit_bytes; jmp .gf32c_done
.gf32c_le: lea rdi,[rip+gc_f32_cmp_le]; mov esi,gc_f32_cmp_le_end-gc_f32_cmp_le; call g_emit_bytes; jmp .gf32c_done
.gf32c_gt: lea rdi,[rip+gc_f32_cmp_gt]; mov esi,gc_f32_cmp_gt_end-gc_f32_cmp_gt; call g_emit_bytes; jmp .gf32c_done
.gf32c_ge: lea rdi,[rip+gc_f32_cmp_ge]; mov esi,gc_f32_cmp_ge_end-gc_f32_cmp_ge; call g_emit_bytes
.gf32c_done: pop r13; pop r12; ret

# Bit operators
g_emit_bit_top2:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_bit_and]; mov ecx,gv_bit_and_end-gv_bit_and; call span_eq; test eax,eax; jnz .gebt_and
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gebt_or
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gebt_xor
    mov eax,1; jmp .gebt_done
.gebt_and: lea rdi,[rip+gc_and_qword]; mov esi,gc_and_qword_end-gc_and_qword; call g_emit_bytes; jmp .gebt_done
.gebt_or: lea rdi,[rip+gc_or_qword]; mov esi,gc_or_qword_end-gc_or_qword; call g_emit_bytes; jmp .gebt_done
.gebt_xor: lea rdi,[rip+gc_xor_qword]; mov esi,gc_xor_qword_end-gc_xor_qword; call g_emit_bytes
.gebt_done: pop r13; pop r12; ret

g_emit_shift_top2:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq; test eax,eax; jnz .gesh_l
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq; test eax,eax; jnz .gesh_r
    mov eax,1; jmp .gesh_done
.gesh_l: lea rdi,[rip+gc_shl_checked]; mov esi,gc_shl_checked_end-gc_shl_checked; call g_emit_bytes; jmp .gesh_done
.gesh_r: lea rdi,[rip+gc_shr_checked]; mov esi,gc_shr_checked_end-gc_shr_checked; call g_emit_bytes
.gesh_done: pop r13; pop r12; ret

# Runtime operands RAX/RCX; outputs quotient RAX, remainder RDX.
g_emit_int_divmod_core:
    cmp edi,GTYPE_I64; je .gedc_signed
    lea rdi,[rip+gc_udivmod_core]; mov esi,gc_udivmod_core_end-gc_udivmod_core
    jmp g_emit_bytes
.gedc_signed:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gedc_wrap
    lea rdi,[rip+gc_idivmod_trap_core]; mov esi,gc_idivmod_trap_core_end-gc_idivmod_trap_core
    jmp g_emit_bytes
.gedc_wrap:
    lea rdi,[rip+gc_idivmod_wrap_core]; mov esi,gc_idivmod_wrap_core_end-gc_idivmod_wrap_core
    jmp g_emit_bytes

g_emit_mod_top2:
    push rbx; mov ebx,edi
    mov edi,0x5859; call g_emit_u16
    mov edi,ebx; call g_emit_int_divmod_core
    mov edi,0x52; call g_emit_u8
    pop rbx; ret

# ---------------- binding emitters ----------------
# rdi=scalar graph -> eax=1 when all scalar effects are unconditional and
# every map pullback preserves the current AxisFact. This proof determines
# lifetime, never a workload/type-name route.
g_phys_identity_axis_episode:
    push rbx; push r12; push r13
    mov r12,rdi
    mov rdi,r12; call g_infer_expr
    cmp eax,GTYPE_BOOL; je .gpiae_load
    cmp eax,GTYPE_U64; je .gpiae_load
    cmp eax,GTYPE_I64; je .gpiae_load
    cmp eax,GTYPE_F32; je .gpiae_load
    cmp eax,GTYPE_F64; jne .gpiae_no
.gpiae_load:
    mov rdi,r12; lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gpiae_op
    mov rdi,r12; call g_phys_identity_load_source
    test rax,rax; jz .gpiae_no
    mov rdi,rax; call g_phys_identity_axis_episode
    jmp .gpiae_done
.gpiae_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpiae_leaf
    # A lazy edge enters packet lifetime only when its whole subtree is total.
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gpiae_select_proved
    mov rdi,r12; call g_semantic_expr_is_total
    test eax,eax; jz .gpiae_no
.gpiae_select_proved:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpiae_no
    mov rbx,[rax+24]
.gpiae_children:
    test rbx,rbx; jz .gpiae_yes
    mov r13,[rbx+32]
    mov rdi,rbx; call g_phys_identity_axis_episode
    test eax,eax; jz .gpiae_no
    mov rbx,r13; jmp .gpiae_children
.gpiae_leaf:
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jnz .gpiae_yes
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jnz .gpiae_yes
    mov rdi,r12; lea rsi,[rip+gk_axis]; mov edx,gk_axis_end-gk_axis; call obj_get
    test rax,rax; jz .gpiae_no
.gpiae_yes: mov eax,1; jmp .gpiae_done
.gpiae_no: xor eax,eax
.gpiae_done: pop r13; pop r12; pop rbx; ret

# rdi=scalar expression -> rax=identity-axis map producer or 0. Both numeric
# carriers, cost and CSE consume this proof without re-producing the index.
# Local validation also protects extent evaluation within a prepared episode.
g_phys_episode_load_source:
    cmp dword ptr [rip+g_phys_stack_episode],0; je .gpels_none
g_phys_identity_load_source:
    push rbx; push r12
    mov r12,rdi
    lea rsi,[rip+gk_load]; mov edx,gk_load_end-gk_load; call obj_get
    test rax,rax; jz .gpils_done
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gpils_done
    cmp dword ptr [rax+16],GK_MAP; jne .gpils_none
    mov rbx,[rax+32]
    mov rdi,r12; lea rsi,[rip+gk_indices]; mov edx,gk_indices_end-gk_indices; call obj_get
    test rax,rax; jz .gpils_done
    mov rdi,[rax+24]; test rdi,rdi; jz .gpils_none
    cmp qword ptr [rdi+32],0; jne .gpils_none
    lea rsi,[rip+gk_axis]; mov edx,gk_axis_end-gk_axis; call obj_get
    test rax,rax; jz .gpils_done
    mov rdi,rbx; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    jmp .gpils_done
.gpils_none: xor eax,eax
.gpils_done: pop r12; pop rbx; ret
.gpels_none: xor eax,eax
    ret

# rdi=reduce scalar root. Reset invocation-local lifetime, then reuse one CSE
# collection/selection authority with the actual General scratch ABI reserved.
g_phys_prepare_scalar_episode:
    push rbx; push r12; push r13
    mov dword ptr [rip+g_phys_cse_memory_carrier],0
    mov rbx,rdi
    mov dword ptr [rip+g_phys_stack_episode],0
    mov dword ptr [rip+g_phys_cse_candidate_count],0
    mov dword ptr [rip+g_phys_cse_resident_count],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov dword ptr [rip+g_phys_const_resident_count],0
    mov rdi,rbx; call g_phys_identity_axis_episode
    test eax,eax; jz .gppse_done
    call g_phys_fp_geometry_refresh
    mov dword ptr [rip+g_phys_fp_reserved_mask],15  # XMM0..3 are General scratch
    mov dword ptr [rip+g_phys_int_reserved_mask],(1<<11) # R11 accumulator
    mov dword ptr [rip+g_phys_fp_temp_peak],0
    mov dword ptr [rip+g_phys_int_temp_peak],0
    mov dword ptr [rip+g_phys_const_candidate_count],0
    mov dword ptr [rip+g_phys_const_pool_ready],0
    mov dword ptr [rip+g_phys_const_collect],1
    mov dword ptr [rip+g_phys_stack_episode],2
    G_EMIT_POSITION r12
    call g_phys_temp_reset
    mov rdi,rbx; call g_infer_expr; mov r13d,eax
    mov edx,eax; xor esi,esi; mov rdi,rbx
    cmp r13d,GTYPE_F64; je .gppse_probe_fp
    cmp r13d,GTYPE_F32; je .gppse_probe_fp
    mov esi,8; call g_emit_phys_int_expr_to
    jmp .gppse_probe_done
.gppse_probe_fp:
    call g_emit_phys_fp_expr_to
.gppse_probe_done:
    mov [rip+g_emit_ptr],r12
    mov dword ptr [rip+g_phys_const_collect],0
    cmp eax,r13d; je .gppse_note
    mov dword ptr [rip+g_phys_stack_episode],1
    mov dword ptr [rip+g_phys_const_candidate_count],0
.gppse_note:
    mov rdi,rbx; call g_infer_expr
    mov esi,eax; mov rdi,rbx; call g_phys_cse_note_tree
    call g_phys_cse_finalize
    call g_phys_cse_order_dependencies
    cmp dword ptr [rip+g_phys_stack_episode],2; jne .gppse_done
    call g_phys_const_finalize
.gppse_done:
    pop r13; pop r12; pop rbx; ret

.include "compiler/physical_packet_general.inc"

# reduce symbol rdi -> eax 0/1
g_emit_reduce_binding:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,[rbx+32]
    mov rdi,r12; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gerb_bad
    mov r15,rax
    # Sum exposes independent map nodes. Min/max retains its existing ordered
    # first-element authority until its packet fold proof is closed.
    mov dword ptr [rip+g_packet_ready],0
    mov dword ptr [rip+group_lane_factor],1
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_sum]; mov ecx,gv_sum_end-gv_sum; call span_eq
    test eax,eax; jz 81f
    mov rdi,r15; call g_prepare_packet_episode
81: cmp dword ptr [rip+g_packet_ready],0; jne 82f
    mov rdi,r15; call g_phys_prepare_scalar_episode
82:
    # extent expression = axes[0].extent
    mov rdi,r12; lea rsi,[rip+gk_axes]; mov edx,gk_axes_end-gk_axes; call obj_get
    mov rax,[rax+24]
    mov rdi,rax; lea rsi,[rip+gk_extent]; mov edx,gk_extent_end-gk_extent; call obj_get
    test rax,rax; jz .gerb_bad
    mov rdi,rax; call g_emit_expr; cmp eax,GTYPE_U64; jne .gerb_bad
    call g_emit_pop_rax
    lea rdi,[rip+gc_mov_rbp_rax]; mov esi,gc_mov_rbp_rax_end-gc_mov_rbp_rax; call g_emit_bytes
    lea rdi,[rip+gc_xor_rbx]; mov esi,gc_xor_rbx_end-gc_xor_rbx; call g_emit_bytes
    mov r14d,dword ptr [rbx+20]
    # init accumulator. sum=zero; min/max initialize on first element via r11 flag.
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    test rax,rax; jz .gerb_bad
    mov r13,rax
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_sum]; mov ecx,gv_sum_end-gv_sum; call span_eq
    mov r15d,eax
    lea rdi,[rip+gc_zero_r11]; mov esi,gc_zero_r11_end-gc_zero_r11; call g_emit_bytes
    test r15d,r15d; jz .gerb_loop_start
    cmp r14d,GTYPE_RANKN_FP_BASE; jb 83f
    mov edi,r14d; call g_alloc_rankn_fp_temp; test rax,rax; jz .gerb_bad
    push rax
    mov rdi,rax; call g_emit_mov_rdi_imm64
    xor edi,edi; call g_emit_mov_esi_imm32
    mov edi,r14d; call g_emit_mov_edx_imm32
    mov rdi,GENERAL_RANKN_FP_FROM_U64_VA; call g_emit_call_abs
    mov edi,0; call g_emit_rankn_fp_status_check
    pop rdi
    call g_emit_mov_rax_imm64
    mov edi,0xc38949; call g_emit_u24 # mov r11,rax, persistent wide accumulator
83:
    # accumulator retains one canonical value across the ordered fold.
.gerb_loop_start:
    cmp dword ptr [rip+g_phys_stack_episode],2; jne .gerb_invariants
    call g_emit_phys_resident_constants
    test eax,eax; jnz .gerb_bad
    call g_emit_phys_constant_pool
    test eax,eax; jnz .gerb_bad
.gerb_invariants:
    call g_emit_phys_episode_invariants
    test eax,eax; jnz .gerb_bad
    mov rdi,r12; mov esi,r14d; call g_emit_packet_reduce_prefix
    test eax,eax; jnz .gerb_bad
    G_EMIT_LOOP_POSITION r15,.gerb_bad
    lea rdi,[rip+gc_cmp_rbx_rbp]; mov esi,gc_cmp_rbx_rbp_end-gc_cmp_rbx_rbp; call g_emit_bytes
    # jae exit
    lea rdi,[rip+gc_jae_prefix]; mov esi,gc_jae_prefix_end-gc_jae_prefix; call g_emit_bytes
    G_EMIT_POSITION r13; xor edi,edi; call g_emit_u32
    lea rdi,[rip+gc_mov_r10_rbx]; mov esi,gc_mov_r10_rbx_end-gc_mov_r10_rbx; call g_emit_bytes
    cmp dword ptr [rip+g_phys_stack_episode],0; je .gerb_expr
    call g_emit_phys_episode_cse
    test eax,eax; jnz .gerb_bad
.gerb_expr:
    mov rdi,r12; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gerb_bad
    mov rdi,rax
    cmp dword ptr [rip+g_phys_stack_episode],2; jne .gerb_stack_expr
    push rdi
    call g_phys_temp_reset
    pop rdi
    mov edx,r14d
    cmp r14d,GTYPE_F32; je .gerb_fp_expr
    cmp r14d,GTYPE_F64; je .gerb_fp_expr
    mov esi,8; call g_emit_phys_int_expr_to
    cmp eax,r14d; jne .gerb_bad
    xor edi,edi; mov esi,8; call g_emit_phys_gpr_move
    jmp .gerb_candidate_ready
.gerb_fp_expr:
    xor esi,esi; call g_emit_phys_fp_expr_to
    cmp eax,r14d; jne .gerb_bad
    xor edi,edi; mov esi,r14d; call g_emit_phys_xmm_to_rax
    jmp .gerb_candidate_ready
.gerb_stack_expr:
    call g_emit_expr; cmp eax,r14d; jne .gerb_bad
    call g_emit_pop_rax
.gerb_candidate_ready:
    # accumulator operation selected by kind
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_sum]; mov ecx,gv_sum_end-gv_sum; call span_eq
    test eax,eax; jnz .gerb_sum
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq
    test eax,eax; jnz .gerb_min
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq
    test eax,eax; jz .gerb_bad
    mov edi,r14d; mov esi,2; call g_emit_reduce_minmax_step; test eax,eax; jnz .gerb_bad; jmp .gerb_step_done
.gerb_min: mov edi,r14d; mov esi,1; call g_emit_reduce_minmax_step; test eax,eax; jnz .gerb_bad; jmp .gerb_step_done
.gerb_sum:
    mov edi,r14d; call g_emit_reduce_sum_step; test eax,eax; jnz .gerb_bad
.gerb_step_done:
    lea rdi,[rip+gc_inc_rbx]; mov esi,gc_inc_rbx_end-gc_inc_rbx; call g_emit_bytes
    mov edi,0xE9; call g_emit_u8
    G_EMIT_POSITION rax; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; jbe 91f
    mov dword ptr [rip+g_code_overflow],1; jmp .gerb_bad
91:
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
    # patch exit
    G_EMIT_POSITION rsi; mov rdi,r13; call g_patch_rel32
    # The loop patch address is not the reduction kind. Empty extrema keep
    # their established rejection semantics; empty sum remains zero.
    # For min/max if RBP == 0 -> runtime reject. identify sum again to skip.
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_sum]; mov ecx,gv_sum_end-gv_sum; call span_eq
    test eax,eax; jnz .gerb_store
    lea rdi,[rip+gc_reject_if_rbp_zero]; mov esi,gc_reject_if_rbp_zero_end-gc_reject_if_rbp_zero; call g_emit_bytes
.gerb_store:
    # R11 contains accumulator bits.
    lea rdi,[rip+gc_mov_rax_r11]; mov esi,gc_mov_rax_r11_end-gc_mov_rax_r11; call g_emit_bytes
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    xor eax,eax; jmp .gerb_done
.gerb_bad: mov eax,1
.gerb_done:
    mov dword ptr [rip+g_phys_cse_memory_carrier],0
    mov dword ptr [rip+g_packet_ready],0
    mov dword ptr [rip+g_phys_stack_episode],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov dword ptr [rip+g_phys_cse_resident_count],0
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# sum step: edi type, candidate in RAX, accumulator bits R11
g_emit_reduce_sum_step:
    cmp edi,GTYPE_U64; je .gers_u
    cmp edi,GTYPE_I64; je .gers_i
    cmp edi,GTYPE_F64; je .gers_f64
    cmp edi,GTYPE_F32; je .gers_f32
    cmp edi,GTYPE_RANKN_FP_BASE; jae .gers_wide
    mov eax,1; ret
.gers_wide:
    push rbx; mov ebx,edi
    # Candidate and accumulator are canonical fpP objects. The existing add
    # primitive projects both before writing its destination, permitting alias.
    mov edi,0xc28948; call g_emit_u24 # mov rdx,rax
    mov edi,0xde894c; call g_emit_u24 # mov rsi,r11
    mov edi,0xdf894c; call g_emit_u24 # mov rdi,r11
    mov edi,ebx; call g_emit_mov_ecx_imm32
    mov rdi,GENERAL_RANKN_FP_ADD_VA; call g_emit_call_abs
    mov edi,1; call g_emit_rankn_fp_status_check
    pop rbx; ret
.gers_u:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gers_uw
    lea rdi,[rip+gc_red_uadd_trap]; mov esi,gc_red_uadd_trap_end-gc_red_uadd_trap; call g_emit_bytes; ret
.gers_uw: lea rdi,[rip+gc_red_add_wrap]; mov esi,gc_red_add_wrap_end-gc_red_add_wrap; call g_emit_bytes; ret
.gers_i:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gers_iw
    lea rdi,[rip+gc_red_iadd_trap]; mov esi,gc_red_iadd_trap_end-gc_red_iadd_trap; call g_emit_bytes; ret
.gers_iw: lea rdi,[rip+gc_red_add_wrap]; mov esi,gc_red_add_wrap_end-gc_red_add_wrap; call g_emit_bytes; ret
.gers_f64: lea rdi,[rip+gc_red_f64_add]; mov esi,gc_red_f64_add_end-gc_red_f64_add; call g_emit_bytes; ret
.gers_f32: lea rdi,[rip+gc_red_f32_add]; mov esi,gc_red_f32_add_end-gc_red_f32_add; call g_emit_bytes; ret

# min/max step: edi natural type, esi mode 1/2; RAX candidate, R11 prior.
# Fold the existing ordered binary relation. No private comparison fragments or
# independent NaN policy is allowed to drift from the common scalar consumer.
g_emit_reduce_minmax_step:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp edi,GTYPE_I64; jb .germm_bad
    cmp edi,GTYPE_F64; ja .germm_bad
    lea rdi,[rip+gc_red_first_guard]; mov esi,gc_red_first_guard_end-gc_red_first_guard; call g_emit_bytes
    mov edi,0x5341; call g_emit_u16 # push r11 = prior value
    mov edi,0x50; call g_emit_u8   # push rax = current candidate
    lea rdi,[rip+gv_min]; cmp r12d,1; je .germm_entity
    lea rdi,[rip+gv_max]
.germm_entity:
    mov esi,3; mov edx,ebx; mov ecx,ebx; mov r8d,ebx
    call g_emit_arithmetic_top2; test eax,eax; jnz .germm_bad
    call g_emit_pop_rax
    mov edi,0xc38949; call g_emit_u24 # mov r11,rax
    xor eax,eax; jmp .germm_done
.germm_bad: mov eax,1
.germm_done: pop r12; pop rbx; ret


# ---------------- 1.3.16 whole-episode shared Physical-DAG facts ----------------
# This is not a workload-specific cache.  Exact strict-order FP subtrees from
# every simultaneous next-state expression enter one AOT CSE domain.  Repeated
# old-version ValueFacts may receive one XMM carrier for the whole causal
# episode; the generated program contains no graph walker or runtime cache.

# rdi=ValueFact -> eax=1 exactly for an invocation-immutable scalar InputFact.
# Existing CSE identity, pressure and carriers serve both episode and invocation
# lifetimes. Loading an input has no rejection effect and may precede zero-trip.
g_phys_value_is_input:
    push rbx
    mov rbx,rdi
    cmp qword ptr [rbx],J_OBJECT; jne .gpvii_no
    mov rdi,rbx; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpvii_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
    test rax,rax; jz .gpvii_no
    mov rdi,rax; call g_semantic_resolve_symbol
    test rax,rax; jz .gpvii_no
    cmp dword ptr [rax+16],GK_INPUT; jne .gpvii_no
    mov ecx,dword ptr [rax+20]
    cmp ecx,GTYPE_U64; je .gpvii_yes
    cmp ecx,GTYPE_I64; je .gpvii_yes
    cmp ecx,GTYPE_F32; je .gpvii_yes
    cmp ecx,GTYPE_F64; jne .gpvii_no
.gpvii_yes: mov eax,1; pop rbx; ret
.gpvii_no: xor eax,eax; pop rbx; ret

# Invocation materialization and timestep refresh are two lifetimes of one
# selected typed ValueFact producer, with no compatibility producer.
g_emit_phys_episode_invariants:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gepei_memory
    xor edi,edi
    jmp g_emit_phys_episode_values
.gepei_memory: xor eax,eax; ret

# rdi=expr -> eax=1 when the typed ValueFact operator is exactly realizable by
# the existing scalar Physical-DAG emitter and therefore safe to retain across
# the causal episode. One authority covers floating and integer arithmetic;
# unsupported semantic relations never enter CSE as speculative compatibility.
g_phys_value_expr_is_shareable_op:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    test r12,r12; jz .gpviso_no
    cmp qword ptr [r12],J_OBJECT; jne .gpviso_no
    mov rdi,r12; call g_infer_expr; mov r13d,eax
    mov rdi,r12; call g_phys_value_is_input; test eax,eax; jnz .gpviso_yes
    mov rdi,r12; call g_phys_episode_load_source
    test rax,rax; jnz .gpviso_yes
.gpviso_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpviso_no
    mov rbx,rax
    cmp r13d,GTYPE_F32; je .gpviso_fp
    cmp r13d,GTYPE_F64; je .gpviso_fp
    cmp r13d,GTYPE_U64; je .gpviso_int
    cmp r13d,GTYPE_I64; jne .gpviso_no
.gpviso_int:
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_bit_and]; mov ecx,gv_bit_and_end-gv_bit_and; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_bit_not]; mov ecx,gv_bit_not_end-gv_bit_not; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq
    test eax,eax; jz .gpviso_no
    cmp r13d,GTYPE_U64; je .gpviso_yes
    jmp .gpviso_no
.gpviso_fp:
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_trunc]; mov ecx,gv_trunc_end-gv_trunc; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_neg]; mov ecx,gv_neg_end-gv_neg; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_exp]; mov ecx,gv_exp_end-gv_exp; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_log]; mov ecx,gv_log_end-gv_log; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_sin]; mov ecx,gv_sin_end-gv_sin; call span_eq
    test eax,eax; jnz .gpviso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_cos]; mov ecx,gv_cos_end-gv_cos; call span_eq
    test eax,eax; jnz .gpviso_yes
.gpviso_no:
    xor eax,eax; jmp .gpviso_done
.gpviso_yes:
    mov eax,1
.gpviso_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=exprA, rsi=exprB -> eax=1 only for exact structural equality.
# Operation order is part of identity; no commutative canonicalization occurs.
g_phys_expr_equal:
    lea rdx,[rip+g_infer_expr]
    jmp physical_value_expr_equal

# rdi=expr -> eax represented operation count for a shareable numeric ValueFact subtree.
g_phys_value_expr_cost:
    push rbx; push r12; push r13
    mov r12,rdi
    mov rdi,r12; call g_phys_value_expr_is_shareable_op
    test eax,eax; jz .gpfec_leaf
    mov rdi,r12; call g_phys_episode_load_source
    test rax,rax; jz .gpfec_args
    mov rdi,rax; call g_phys_value_expr_cost
    inc eax; jmp .gpfec_done
.gpfec_args:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfec_leaf
    mov r12,[rax+24]; test r12,r12; jz .gpfec_leaf
    mov r13,[r12+32]
    mov rdi,r12; call g_phys_value_expr_cost; mov ebx,eax
    test r13,r13; jz .gpfec_unary
    mov rdi,r13; call g_phys_value_expr_cost
    add eax,ebx; inc eax; jmp .gpfec_done
.gpfec_unary:
    mov eax,ebx; inc eax; jmp .gpfec_done
.gpfec_leaf:
    xor eax,eax
.gpfec_done:
    pop r13; pop r12; pop rbx; ret

# rdi=predicate expression -> eax represented operator work.  This score is
# compile-time profitability only; it neither changes semantics nor selects a
# workload algorithm.  Numeric children contribute their existing arithmetic
# cost and predicate children recurse through the same boolean graph.
g_phys_predicate_cost:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    test r12,r12; jz .gppc_zero
    cmp qword ptr [r12],J_OBJECT; jne .gppc_zero
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gppc_zero
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gppc_one
    mov r14,[rax+24]
    mov ebx,1
.gppc_child:
    test r14,r14; jz .gppc_value
    mov r13,[r14+32]
    mov rdi,r14; call g_infer_expr
    cmp eax,GTYPE_BOOL; je .gppc_child_bool
    cmp eax,GTYPE_F32; je .gppc_child_numeric
    cmp eax,GTYPE_F64; je .gppc_child_numeric
    cmp eax,GTYPE_U64; je .gppc_child_numeric
    cmp eax,GTYPE_I64; jne .gppc_child_next
.gppc_child_numeric:
    mov rdi,r14; call g_phys_value_expr_cost
    add ebx,eax
    jmp .gppc_child_next
.gppc_child_bool:
    mov rdi,r14; call g_phys_predicate_cost
    add ebx,eax
.gppc_child_next:
    mov r14,r13; jmp .gppc_child
.gppc_value:
    mov eax,ebx; jmp .gppc_done
.gppc_one:
    mov eax,1; jmp .gppc_done
.gppc_zero:
    xor eax,eax
.gppc_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=parent -> eax bit 0: borrowed children; bit 1: one equal-child evaluation.
# No mathematical rewrite, runtime metadata or alternative emitter is created.
g_phys_children_are_borrowed:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    call g_infer_expr; mov r13d,eax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpcab_no
    mov r14,[rax+24]; test r14,r14; jz .gpcab_no
    mov r15,[r14+32]; test r15,r15; jz .gpcab_no
    cmp qword ptr [r15+32],0; jne .gpcab_no
    mov rdi,r14; call g_infer_expr; mov ebx,eax
    mov rdi,r15; call g_infer_expr; cmp eax,ebx; jne .gpcab_no
    cmp r13d,GTYPE_BOOL; je .gpcab_compare
    cmp ebx,r13d; jne .gpcab_no
    cmp ebx,GTYPE_F32; je .gpcab_numeric
    cmp ebx,GTYPE_F64; jne .gpcab_no
.gpcab_numeric:
    mov rdi,r12; call g_phys_value_expr_is_shareable_op
    test eax,eax; jz .gpcab_done
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpcab_done
    mov rdi,r14; mov rsi,r15; call g_phys_expr_equal
    shl eax,1; or eax,1; jmp .gpcab_done
.gpcab_compare:
    cmp ebx,GTYPE_I64; jb .gpcab_no
    cmp ebx,GTYPE_F64; ja .gpcab_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpcab_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_is_compare_op; jmp .gpcab_done
.gpcab_no: xor eax,eax
.gpcab_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Shared top-level select guards already have one Physical-Region consumer.
# Count only members with current disjoint next carriers; no syntax is rewritten.
g_phys_predicate_guard_uses:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; xor r13d,r13d; xor ebx,ebx
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gppgu_done
    cmp dword ptr [rip+g_phys_stack_episode],0; jne .gppgu_done
.gppgu_loop:
    cmp ebx,[rip+g_reg_iter_total]; jae .gppgu_done
    # Repeated guard consumers are a logical relation. Carrier closure has
    # not run yet; querying next-register assignment here made this benefit
    # disappear merely because state residency now starts in the frame.
    # g_phys_build_guard_regions proves the completed physical map separately.
    mov eax,ebx; shl rax,5; mov r14,[rip+g_states_ptr]; add r14,rax
    cmp dword ptr [r14+28],-1; je .gppgu_next
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r14]; mov edx,[r14+8]; call obj_get
    test rax,rax; jz .gppgu_next
    mov r15,rax
    mov rdi,r15; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gppgu_next
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gppgu_next
    mov rdi,r15; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gppgu_next
    mov rdi,[rax+24]; mov rsi,r12; call g_phys_predicate_equal
    add r13d,eax
.gppgu_next: inc ebx; jmp .gppgu_loop
.gppgu_done: mov eax,r13d; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expression, esi=expected type. Walk once and count exact repeated
# operator ValueFacts across every next-state expression.
g_phys_cse_note_tree:
    mov edx,1
g_phys_cse_note_operand:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov eax,[rip+g_phys_cse_conditional_visit]; mov [rsp],eax
    mov [rsp+4],edx
    mov r12,rdi; mov r13d,esi
    test r12,r12; jz .gpcnt_done
    cmp qword ptr [r12],J_OBJECT; jne .gpcnt_done

    mov rdi,r12; call g_phys_episode_load_source
    test rax,rax; jz .gpcnt_args
    mov rdi,rax; mov esi,r13d; call g_phys_cse_note_tree
.gpcnt_args:
    # An episode-wide carrier cannot cross a lazy control edge. Only the
    # unconditional condition/left operand introduces facts into this lifetime.
    # Conditional children may consume those dominating facts, never introduce
    # an arm-local fact into unconditional residency. This admission fact is
    # shared by register and packet memory carriers.
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpcnt_eager_args
    mov r14,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jnz .gpcnt_control
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq
    test eax,eax; jnz .gpcnt_control
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq
    test eax,eax; jz .gpcnt_eager_args
.gpcnt_control:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpcnt_done
    mov rdi,[rax+24]; test rdi,rdi; jz .gpcnt_done
    mov r14,rdi; call g_infer_expr; mov esi,eax; mov rdi,r14; call g_phys_cse_note_tree
    mov r14,[r14+32]
    or dword ptr [rip+g_phys_cse_conditional_visit],1
.gpcnt_control_uses:
    test r14,r14; jz .gpcnt_control_self
    mov r15,[r14+32]
    mov rdi,r14; call g_infer_expr; mov esi,eax; mov rdi,r14; call g_phys_cse_note_tree
    mov r14,r15; jmp .gpcnt_control_uses
.gpcnt_control_self:
    mov eax,[rsp]; mov [rip+g_phys_cse_conditional_visit],eax
    jmp .gpcnt_note_self
.gpcnt_eager_args:
    mov rdi,r12; call g_phys_children_are_borrowed
    mov edx,eax; and eax,1; xor eax,1; mov [rsp+8],eax
    shr edx,1; mov [rsp+12],edx
    # Graph traversal and residency eligibility are separate facts. Every
    # operator edge is visited. Numeric arithmetic and BOOL predicates are
    # ordinary episode-scoped ValueFacts; select itself remains a control
    # consumer rather than a cacheable value.
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpcnt_note_self
    mov r14,[rax+24]
.gpcnt_child_loop:
    test r14,r14; jz .gpcnt_note_self
    mov r15,[r14+32]
    mov rdi,r14; call g_infer_expr; mov ebx,eax
    test ebx,ebx; jz .gpcnt_child_next
    mov rdi,r14; mov esi,ebx; mov edx,[rsp+8]; call g_phys_cse_note_operand
.gpcnt_child_next:
    cmp dword ptr [rsp+12],0; jne .gpcnt_note_self
    mov r14,r15; jmp .gpcnt_child_loop

.gpcnt_note_self:
    cmp r13d,GTYPE_BOOL; je .gpcnt_self_bool
    cmp r13d,GTYPE_F32; je .gpcnt_self_numeric
    cmp r13d,GTYPE_F64; je .gpcnt_self_numeric
    cmp r13d,GTYPE_U64; je .gpcnt_self_numeric
    cmp r13d,GTYPE_I64; jne .gpcnt_done
.gpcnt_self_numeric:
    mov rdi,r12; call g_phys_value_expr_is_shareable_op
    test eax,eax; jz .gpcnt_done
    jmp .gpcnt_scan_start
.gpcnt_self_bool:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpcnt_done
    # Only predicate-producing BOOL expressions are cacheable; literals and
    # arbitrary BOOL leaves remain direct operands.
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpcnt_done
    mov r14,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; call g_is_compare_op
    test eax,eax; jnz .gpcnt_scan_start
    mov rdi,[r14+8]; mov rsi,[r14+16]; call g_is_bool_binary
    test eax,eax; jnz .gpcnt_scan_start
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq
    test eax,eax; jz .gpcnt_done
.gpcnt_scan_start:
    xor ebx,ebx
.gpcnt_scan:
    cmp ebx,dword ptr [rip+g_phys_cse_candidate_count]; jae .gpcnt_new
    mov rax,qword ptr [rip+g_phys_cse_candidate_type_ptr]; cmp dword ptr [rax+rbx*4],r13d; jne .gpcnt_next
    mov rax,qword ptr [rip+g_phys_cse_candidate_expr_ptr]; mov rsi,[rax+rbx*8]
    mov rdi,r12
    cmp r13d,GTYPE_BOOL; je .gpcnt_equal_bool
    call g_phys_expr_equal
    jmp .gpcnt_equal_done
.gpcnt_equal_bool:
    call g_phys_predicate_equal
.gpcnt_equal_done:
    test eax,eax; jz .gpcnt_next
    # The condition can borrow only producers refreshed at its own frontier.
    test dword ptr [rip+g_phys_cse_conditional_visit],2; jz .gpcnt_use_admitted
    mov rdi,r12; call g_phys_plan_control
    test eax,eax; jz .gpcnt_done
.gpcnt_use_admitted:
    mov rax,qword ptr [rip+g_phys_cse_candidate_uses_ptr]; inc dword ptr [rax+rbx*4]
    mov rax,[rip+g_phys_cse_candidate_moves_ptr]; mov edx,[rsp+4]; add [rax+rbx*4],edx
    jmp .gpcnt_done
.gpcnt_next:
    inc ebx; jmp .gpcnt_scan
.gpcnt_new:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne 992f
    cmp dword ptr [rip+g_phys_cse_conditional_visit],0; je 992f
    mov rdi,r12; call g_phys_value_is_input
    test eax,eax; jnz 992f
    test dword ptr [rip+g_phys_cse_conditional_visit],2; jz .gpcnt_done
    mov rdi,r12; call g_phys_plan_control
    test eax,eax; jz .gpcnt_done
992:
    cmp ebx,dword ptr [rip+g_phys_fact_capacity]; jae .gpcnt_done
    mov rax,qword ptr [rip+g_phys_cse_candidate_expr_ptr]; mov [rax+rbx*8],r12
    mov rax,qword ptr [rip+g_phys_cse_candidate_type_ptr]; mov dword ptr [rax+rbx*4],r13d
    mov rax,qword ptr [rip+g_phys_cse_candidate_uses_ptr]; mov dword ptr [rax+rbx*4],1
    mov rax,[rip+g_phys_cse_candidate_moves_ptr]; mov edx,[rsp+4]; mov [rax+rbx*4],edx
    mov rdi,r12
    cmp r13d,GTYPE_BOOL; je .gpcnt_cost_bool
    call g_phys_value_expr_cost
    jmp .gpcnt_cost_done
.gpcnt_cost_bool:
    call g_phys_predicate_cost
.gpcnt_cost_done:
    test eax,eax; jnz .gpcnt_cost_ready
    mov rdi,r12; call g_phys_value_is_input
.gpcnt_cost_ready:
    mov rdx,qword ptr [rip+g_phys_cse_candidate_cost_ptr]; mov dword ptr [rdx+rbx*4],eax
    inc dword ptr [rip+g_phys_cse_candidate_count]
.gpcnt_done:
    mov eax,[rsp]; mov [rip+g_phys_cse_conditional_visit],eax
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Shared XMM authority for persistent scalar payloads, immutable constants,
# old-StateFacts and retained next-StateFacts. State carriers, already retained same-domain
# facts, and the measured anonymous peak compete in one compile-time physical
# pool. No fact class receives guessed pressure credit.
g_phys_shared_xmm_alloc:
    push rbx; push r12; push r13
    mov ebx,dword ptr [rip+g_phys_fp_reserved_mask]
    or ebx,edi                         # caller recipe role exclusions
    xor r12d,r12d
.gpsxa_cse:
    cmp r12d,dword ptr [rip+g_phys_cse_resident_count]; jae .gpsxa_const_start
    mov rax,qword ptr [rip+g_phys_cse_resident_reg_ptr]; mov ecx,dword ptr [rax+r12*4]
    test ecx,ecx; js .gpsxa_cse_next
    mov eax,1; shl eax,cl; or ebx,eax
.gpsxa_cse_next:
    inc r12d; jmp .gpsxa_cse
.gpsxa_const_start:
    xor r12d,r12d
.gpsxa_const:
    cmp r12d,dword ptr [rip+g_phys_const_resident_count]; jae .gpsxa_free
    mov rax,qword ptr [rip+g_phys_const_resident_reg_ptr]; mov ecx,dword ptr [rax+r12*4]
    mov eax,1; shl eax,cl; or ebx,eax
    inc r12d; jmp .gpsxa_const
.gpsxa_free:
    mov eax,ebx; not eax; and eax,dword ptr [rip+g_phys_fp_all_mask]
    mov r13d,eax
    xor r12d,r12d
.gpsxa_pc:
    test eax,eax; jz .gpsxa_pc_done
    lea ecx,[rax-1]; and eax,ecx; inc r12d; jmp .gpsxa_pc
.gpsxa_pc_done:
    mov ecx,dword ptr [rip+g_phys_fp_temp_peak]
    cmp r12d,ecx; jbe .gpsxa_none
    bsf eax,r13d; jmp .gpsxa_done
.gpsxa_none:
    mov eax,-1
.gpsxa_done:
    pop r13; pop r12; pop rbx; ret

# Compile-time Physical DAG residency. Search owns no new semantic IR.
g_phys_cse_finalize:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov dword ptr [rip+g_phys_cse_resident_count],0
    mov edi,[rip+g_phys_cse_candidate_count]
    mov [rsp+8],edi
    test edi,edi; jz .gpa_done
    call physical_plan_alloc
    test rax,rax; jz .gpa_done
    mov r12,rax
    xor r13d,r13d
    xor ebx,ebx
.gpa_build:
    cmp ebx,[rip+g_phys_cse_candidate_count]; jae .gpa_search
    mov rax,[rip+g_phys_cse_candidate_cost_ptr]
    cmp dword ptr [rax+rbx*4],0; je .gpa_next
    mov rax,[rip+g_phys_cse_candidate_type_ptr]
    mov r14d,[rax+rbx*4]
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpa_type_ok
    cmp r14d,GTYPE_I64; jb .gpa_next
    cmp r14d,GTYPE_F64; ja .gpa_next
.gpa_type_ok:
    mov rax,[rip+g_phys_cse_candidate_uses_ptr]
    mov r15d,[rax+rbx*4]
    mov rax,[rip+g_phys_cse_candidate_expr_ptr]
    mov rdi,[rax+rbx*8]
    call g_phys_plan_invariant
    mov [rsp],eax
    test eax,eax; jnz .gpa_admit
    cmp r15d,2; jb .gpa_next
.gpa_admit:
    mov rax,[rip+g_phys_cse_candidate_expr_ptr]
    mov rdi,[rax+rbx*8]
    call g_phys_plan_expr_ticks
    imul rdx,r13,PPR_SIZE
    lea rdx,[r12+rdx]
    mov [rdx+32],rax
    mov [rdx+24],ebx
    mov [rdx+28],r14d
    mov ecx,[rsp]
    mov [rdx+PPR_INVARIANT],ecx
    mov dword ptr [rdx+8],1
    mov dword ptr [rdx+12],0
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpa_gain
    mov dword ptr [rdx+12],1
.gpa_gain:
    mov ecx,r15d
    cmp dword ptr [rsp],0; jne .gpa_input_gain
    dec ecx
.gpa_input_gain:
    imul rax,rcx
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpa_move_price
    mov ecx,r15d
    cmp dword ptr [rsp],0; jne .gpa_memory_ticks
    inc ecx
.gpa_memory_ticks:
    imul rcx,rcx,PRC_LOAD_AGU_TICKS
    sub rax,rcx
    jmp .gpa_gain_ready
.gpa_move_price:
    mov ecx,PRC_FP_CONV_TICKS
    cmp r14d,GTYPE_U64; je .gpa_move_ticks
    cmp r14d,GTYPE_I64; je .gpa_move_ticks
    mov ecx,PRC_FP_ADD_TICKS
.gpa_move_ticks:
    mov rdi,[rip+g_phys_cse_candidate_moves_ptr]
    mov edi,[rdi+rbx*4]
    mov [rdx+56],edi
    imul rcx,rdi
    sub rax,rcx
.gpa_gain_ready:
    mov dword ptr [rdx+60],0
    cmp r14d,GTYPE_BOOL; jne .gpa_control_gain_ready
    push rax; push rdx
    mov rdi,[rip+g_phys_cse_candidate_expr_ptr]; mov rdi,[rdi+rbx*8]
    call g_phys_predicate_guard_uses
    pop rdx
    mov [rdx+60],eax
    cmp eax,1; jbe .gpa_control_gain_none
    dec eax; imul rax,rax,2*PRC_BRANCH_TICKS
    add [rsp],rax
.gpa_control_gain_none: pop rax
.gpa_control_gain_ready:
    test rax,rax; jle .gpa_next
    mov [rdx],rax
    inc r13d
.gpa_next:
    inc ebx; jmp .gpa_build
.gpa_search:
    mov rdi,r13
    imul rdi,r13
    shl rdi,3
    mov [rsp+24],rdi
    call physical_plan_bytes_alloc
    test rax,rax; jz .gpa_free
    mov [rsp+16],rax
    mov rdi,r12
    mov esi,r13d
    mov rdx,rax
    call g_phys_plan_relations
    call g_phys_plan_budgets
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpa_reg_budget
    mov edx,r13d
    xor ecx,ecx
.gpa_reg_budget:
    mov rdi,r12
    mov esi,r13d
    lea r8,[rip+g_phys_plan_score]
    mov r9,[rsp+16]
    xor eax,eax
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpa_final_cost_ready
    lea rax,[rip+g_phys_plan_packet_cost]
.gpa_final_cost_ready:
    sub rsp,16
    mov [rsp],rax
    call physical_plan_resolve
    add rsp,16
    mov rdi,r12
    mov esi,r13d
    mov rdx,[rsp+16]
    call g_phys_plan_score
    xor ebx,ebx
.gpa_realize:
    cmp ebx,r13d; jae .gpa_release_matrix
    imul r15,rbx,PPR_SIZE
    add r15,r12
    cmp dword ptr [r15+16],0; je .gpa_realize_next
    cmp dword ptr [r15+PPR_INVARIANT],0; je .gpa_fact_live
    cmp qword ptr [r15+40],0; je .gpa_realize_next
.gpa_fact_live:
    # Parent reuse can erase a child's independent consumers. With no scalar
    # reuse or shared-control benefit, the parent owns its one producer directly.
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpa_live_resident
    cmp dword ptr [r15+PPR_INVARIANT],0; jne .gpa_live_resident
    cmp qword ptr [r15+40],1; ja .gpa_live_resident
    cmp dword ptr [r15+60],1; jbe .gpa_realize_next
.gpa_live_resident:
    mov r14d,[r15+24]
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpa_alloc_reg
    mov eax,[rip+g_phys_cse_resident_count]
    jmp .gpa_assign
.gpa_alloc_reg:
    xor edi,edi
    call g_phys_shared_xmm_alloc
.gpa_assign:
    test eax,eax; js .gpa_realize_next
    mov ecx,[rip+g_phys_cse_resident_count]
    mov rdx,[rip+g_phys_cse_resident_reg_ptr]; mov [rdx+rcx*4],eax
    mov rdx,[rip+g_phys_cse_candidate_cost_ptr]; mov eax,[rdx+r14*4]
    mov rdx,[rip+g_phys_cse_resident_cost_ptr]; mov [rdx+rcx*4],eax
    mov rdx,[rip+g_phys_cse_candidate_expr_ptr]; mov rax,[rdx+r14*8]
    mov rdx,[rip+g_phys_cse_resident_expr_ptr]; mov [rdx+rcx*8],rax
    mov eax,[r15+28]
    mov rdx,[rip+g_phys_cse_resident_type_ptr]; mov [rdx+rcx*4],eax
    mov rdx,[rip+g_phys_cse_resident_expr_ptr]; mov rdi,[rdx+rcx*8]
    push rcx; call g_phys_plan_frontier; pop rcx
    mov rdx,[rip+g_phys_cse_resident_frontier_ptr]; mov [rdx+rcx*4],eax
    inc dword ptr [rip+g_phys_cse_resident_count]
.gpa_realize_next:
    inc ebx; jmp .gpa_realize
.gpa_release_matrix:
    mov rdi,[rsp+16]
    mov rsi,[rsp+24]
    call physical_plan_bytes_free
.gpa_free:
    mov rdi,r12
    mov esi,[rsp+8]
    call physical_plan_free
.gpa_done:
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Real bank slack, excluding existing semantic state, residents and measured
# transient peaks. Shared allocators remain the final physical authority.
g_phys_plan_budgets:
    mov r8d,G_PHYS_INT_TEMP_MASK_INIT
    mov eax,[rip+g_phys_int_reserved_mask]
    not eax; and r8d,eax
    mov r9d,[rip+g_phys_fp_reserved_mask]
    not r9d; and r9d,[rip+g_phys_fp_all_mask]
    xor ecx,ecx
.gpab_residents:
    cmp ecx,[rip+g_phys_cse_resident_count]; jae .gpab_const_start
    mov rax,[rip+g_phys_cse_resident_reg_ptr]
    mov eax,[rax+rcx*4]
    test eax,eax; js .gpab_resident_next
    btr r9d,eax
.gpab_resident_next:
    inc ecx; jmp .gpab_residents
.gpab_const_start:
    xor ecx,ecx
.gpab_const:
    cmp ecx,[rip+g_phys_const_resident_count]; jae .gpab_count
    mov rax,[rip+g_phys_const_resident_reg_ptr]
    mov eax,[rax+rcx*4]
    btr r9d,eax
    inc ecx; jmp .gpab_const
.gpab_count:
    xor edx,edx
.gpab_count_int:
    test r8d,r8d; jz .gpab_count_fp_start
    lea eax,[r8-1]; and r8d,eax
    inc edx; jmp .gpab_count_int
.gpab_count_fp_start:
    xor ecx,ecx
.gpab_count_fp:
    test r9d,r9d; jz .gpab_slack
    lea eax,[r9-1]; and r9d,eax
    inc ecx; jmp .gpab_count_fp
.gpab_slack:
    sub edx,[rip+g_phys_int_temp_peak]
    jns .gpab_fp_slack
    xor edx,edx
.gpab_fp_slack:
    sub ecx,[rip+g_phys_fp_temp_peak]
    jns .gpab_done
    xor ecx,ecx
.gpab_done: ret

# Target resource-tick estimate of the exact ordered subtree. This is a cost
# estimate, not a latency oracle. Identity loads price their actual source.
g_phys_plan_expr_ticks:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    call g_phys_value_is_input
    test eax,eax; jz .gpaw_op
    mov eax,PRC_LOAD_AGU_TICKS
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpaw_ret
    # Packet input production also broadcasts and materializes the uniform
    # value. Residency erases these actual transports from every hot packet.
    add eax,PRC_FP_CONV_TICKS+PRC_LOAD_AGU_TICKS
    jmp .gpaw_ret
.gpaw_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpaw_zero
    mov r14,rax
    mov rdi,r12; call g_phys_episode_load_source
    test rax,rax; jz .gpaw_price
    mov rdi,rax; call g_phys_plan_expr_ticks; jmp .gpaw_ret
.gpaw_price:
    mov rdi,r12; call g_infer_expr
    mov ebx,PRC_INT_ALU_TICKS
    cmp eax,GTYPE_F32; je .gpaw_fp
    cmp eax,GTYPE_F64; jne .gpaw_mul
.gpaw_fp:
    mov ebx,PRC_FP_ADD_TICKS
.gpaw_mul:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jz .gpaw_div
    mov ebx,PRC_INT_MUL_TICKS
    jmp .gpaw_children
.gpaw_div:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jnz .gpaw_div_price
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq
    test eax,eax; jz .gpaw_math
.gpaw_div_price:
    mov rdi,r12; call g_infer_expr
    mov ebx,PRC_INT_DIV_TICKS
    cmp eax,GTYPE_F32; je .gpaw_fp_div
    cmp eax,GTYPE_F64; jne .gpaw_math
.gpaw_fp_div:
    mov ebx,PRC_FP_DIV_TICKS
.gpaw_math:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jz .gpaw_after_sqrt
    mov ebx,PRC_FP_DIV_TICKS
    jmp .gpaw_children
.gpaw_after_sqrt:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_sin]; mov ecx,gv_sin_end-gv_sin; call span_eq
    test eax,eax; jz .gpaw_after_sin
    mov ebx,OFFSET FLAT:gc_sin_f64_size
    imul ebx,ebx,PRC_FRONTEND_BYTE_TICKS
    jmp .gpaw_children
.gpaw_after_sin:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_cos]; mov ecx,gv_cos_end-gv_cos; call span_eq
    test eax,eax; jz .gpaw_after_cos
    mov ebx,OFFSET FLAT:gc_cos_f64_size
    imul ebx,ebx,PRC_FRONTEND_BYTE_TICKS
    jmp .gpaw_children
.gpaw_after_cos:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_exp]; mov ecx,gv_exp_end-gv_exp; call span_eq
    test eax,eax; jz .gpaw_after_exp
    mov ebx,OFFSET FLAT:gc_exp_f64_size
    imul ebx,ebx,PRC_FRONTEND_BYTE_TICKS
    jmp .gpaw_children
.gpaw_after_exp:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_log]; mov ecx,gv_log_end-gv_log; call span_eq
    test eax,eax; jz .gpaw_after_log
    mov ebx,OFFSET FLAT:gc_log_f64_size
    imul ebx,ebx,PRC_FRONTEND_BYTE_TICKS
    jmp .gpaw_children
.gpaw_after_log:
.gpaw_children:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpaw_child_edges
    # The existing packet carrier writes each producer and reads its result.
    add ebx,2*PRC_LOAD_AGU_TICKS
.gpaw_child_edges:
    mov rdi,r12; call g_phys_children_are_borrowed; shr eax,1; mov r14d,eax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpaw_value
    mov r12,[rax+24]
.gpaw_child:
    test r12,r12; jz .gpaw_value
    mov r13,[r12+32]
    mov rdi,r12; call g_phys_plan_expr_ticks
    add rbx,rax
    test r14d,r14d; jnz .gpaw_value
    mov r12,r13; jmp .gpaw_child
.gpaw_value:
    mov rax,rbx; jmp .gpaw_ret
.gpaw_zero:
    xor eax,eax
.gpaw_ret:
    pop r14; pop r13; pop r12; pop rbx; ret

# Joint score: parent reuse removes the child occurrences which disappeared
# with it. Descending source-DAG order prevents counting shared work twice.
# Each retained input removes its remaining transports. Packet slots charge
# both materialization and every retained read; no free-memory pressure credit.
g_phys_plan_score:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov [rsp],rdx
    mov r12,rdi
    mov r13d,esi
    xor ebx,ebx
.gpas_init:
    cmp ebx,r13d; jae .gpas_start
    imul rax,rbx,PPR_SIZE
    mov ecx,[r12+rax+24]
    mov rdx,[rip+g_phys_cse_candidate_uses_ptr]
    mov edx,[rdx+rcx*4]
    mov [r12+rax+40],rdx
    inc ebx; jmp .gpas_init
.gpas_start:
    xor r15d,r15d
    mov ebx,r13d
.gpas_parent:
    dec ebx; js .gpas_done
    imul r14,rbx,PPR_SIZE
    add r14,r12
    cmp dword ptr [r14+16],0; je .gpas_parent
    mov eax,[r14+PPR_INVARIANT]
    mov rcx,[r14+40]
    test eax,eax; jnz .gpas_saved
    dec rcx
.gpas_saved:
    mov rax,[r14+32]
    imul rax,rcx
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpas_move_price
    mov rdx,[r14+40]
    cmp dword ptr [r14+PPR_INVARIANT],0; jne .gpas_memory_ticks
    inc rdx
.gpas_memory_ticks:
    imul rdx,rdx,PRC_LOAD_AGU_TICKS
    sub rax,rdx
    jmp .gpas_add
.gpas_move_price:
    mov edx,PRC_INT_ALU_TICKS
    cmp dword ptr [r14+28],GTYPE_U64; je .gpas_move_ticks
    cmp dword ptr [r14+28],GTYPE_I64; je .gpas_move_ticks
    mov edx,PRC_FP_ADD_TICKS
.gpas_move_ticks:
    mov ecx,[r14+56]; imul rdx,rcx
    sub rax,rdx
    mov ecx,[r14+60]; cmp ecx,1; jbe .gpas_add
    dec ecx; imul rcx,rcx,2*PRC_BRANCH_TICKS
    add rax,rcx
.gpas_add:
    add r15,rax
    mov rdx,[r14+40]
    cmp dword ptr [r14+PPR_INVARIANT],0; jne .gpas_removed
    dec rdx
.gpas_removed:
    test rdx,rdx; jle .gpas_parent
    mov rax,rbx
    imul rax,r13
    mov rsi,[rsp]
    lea rsi,[rsi+rax*8]
    xor ecx,ecx
.gpas_discount:
    cmp ecx,ebx; jae .gpas_parent
    mov rax,[rsi+rcx*8]
    imul rax,rdx
    imul rdi,rcx,PPR_SIZE
    mov r8,[r12+rdi+40]
    sub r8,rax
    jns .gpas_count_ready
    xor r8d,r8d
.gpas_count_ready:
    mov [r12+rdi+40],r8
    inc ecx; jmp .gpas_discount
.gpas_done:
    mov rax,r15
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Compile-time incidence projection of the SAME ordered ValueFact DAG. Rows
# count represented descendants. A proved child imports its completed row;
# search trials never reparse the source or repeat structural identity proofs.
g_phys_plan_relations:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    mov r13d,esi
    mov r14,rdx
    xor ebx,ebx
.gpar_row:
    cmp ebx,r13d; jae .gpar_done
    imul rax,rbx,PPR_SIZE
    mov eax,[r12+rax+24]
    mov rdi,[rip+g_phys_cse_candidate_expr_ptr]
    mov rdi,[rdi+rax*8]
    mov rsi,r12
    mov edx,ebx
    mov rcx,r14
    mov r8d,r13d
    call g_phys_plan_relation_children
    inc ebx; jmp .gpar_row
.gpar_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=node, rsi=records, edx=row index, rcx=matrix, r8d=row stride.
g_phys_plan_relation_children:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov r12,rsi
    mov r13d,edx
    mov r14,rcx
    mov r15,rdi
    mov [rsp+8],r8d
    mov dword ptr [rsp+12],0
    call g_phys_episode_load_source
    test rax,rax; jz .gpar_args
    mov rdi,rax
    xor r15d,r15d
    jmp .gpar_child
.gpar_args:
    # An arm-local cache dies at the control edge. Only the unconditional
    # predicate edge may discount dominating descendants; no lifetime credit
    # crosses select/and/or merely because the source subtrees are equal.
    mov rdi,r15; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpar_args_ready
    mov rbx,rax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    or [rsp+12],eax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq
    or [rsp+12],eax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq
    or [rsp+12],eax
.gpar_args_ready:
    mov rdi,r15; call g_phys_children_are_borrowed; shr eax,1; or [rsp+12],eax
    mov rdi,r15; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpar_ret
    mov r15,[rax+24]
.gpar_loop:
    test r15,r15; jz .gpar_ret
    mov rdi,r15
.gpar_child:
    mov [rsp],rdi
    xor ebx,ebx
.gpar_match:
    cmp ebx,r13d; jae .gpar_recurse
    imul rax,rbx,PPR_SIZE
    lea rcx,[r12+rax]
    mov eax,[rcx+24]
    mov rsi,[rip+g_phys_cse_candidate_expr_ptr]
    mov rsi,[rsi+rax*8]
    mov rdi,[rsp]
    cmp rdi,rsi; je .gpar_import
    cmp dword ptr [rcx+28],GTYPE_BOOL; je .gpar_bool
    call g_phys_expr_equal; jmp .gpar_equal
.gpar_bool:
    call g_phys_predicate_equal
.gpar_equal:
    test eax,eax; jnz .gpar_import
    inc ebx; jmp .gpar_match
.gpar_import:
    mov eax,[rsp+8]
    imul rax,r13
    lea rdi,[r14+rax*8]
    inc qword ptr [rdi+rbx*8]
    mov eax,[rsp+8]
    imul rax,rbx
    lea rsi,[r14+rax*8]
    xor ecx,ecx
.gpar_import_row:
    cmp ecx,ebx; jae .gpar_next
    mov rax,[rsi+rcx*8]
    add [rdi+rcx*8],rax
    inc ecx; jmp .gpar_import_row
.gpar_recurse:
    mov rdi,[rsp]
    mov rsi,r12
    mov edx,r13d
    mov rcx,r14
    mov r8d,[rsp+8]
    call g_phys_plan_relation_children
.gpar_next:
    cmp dword ptr [rsp+12],0; jne .gpar_ret
    test r15,r15; jz .gpar_ret
    mov r15,[r15+32]
    jmp .gpar_loop
.gpar_ret:
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Residency lifetime comes from the same proof used by actual materialization.
# A preheader fact removes ALL its hot computations, not only repeated ones.
g_phys_plan_invariant:
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; jne .gpai_packet
    push rbx; push r12; push r13
    mov r12,rdi
    call g_phys_value_is_input
    test eax,eax; jnz .gpai_done
    # The scalar episode has several unconditional roots. Each uses the same
    # shared proof as a packet root; state leaves never pass immutable purity.
    mov rdi,[rip+g_reg_iter_cond_expr]; mov rsi,r12
    call g_phys_fact_is_invariant
    test eax,eax; jnz .gpai_done
    xor ebx,ebx
.gpai_state:
    cmp ebx,[rip+g_reg_iter_total]; jae .gpai_no
    mov eax,ebx; shl rax,5; mov r13,[rip+g_states_ptr]; add r13,rax
    cmp dword ptr [r13+28],-1; je .gpai_next
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r13]; mov edx,[r13+8]
    call obj_get
    test rax,rax; jz .gpai_next
    mov rdi,rax; mov rsi,r12; call g_phys_fact_is_invariant
    test eax,eax; jnz .gpai_done
.gpai_next:
    inc ebx; jmp .gpai_state
.gpai_no: xor eax,eax
.gpai_done: pop r13; pop r12; pop rbx; ret
.gpai_packet:
    mov rsi,rdi
    mov rdi,[rip+g_phys_plan_root]
    jmp g_phys_fact_is_invariant

# Invocation, current-condition and current-update consumer frontiers derive
# from the same generation proof. No current value survives a commit unrefreshed.
g_phys_plan_frontier:
    push rbx
    mov rbx,rdi
    call g_phys_plan_invariant; test eax,eax; jnz .gppf_invariant
    mov rdi,rbx; call g_phys_plan_control
    pop rbx; ret
.gppf_invariant: mov eax,2; pop rbx; ret

# A total producer on an unconditional condition edge can be shared by the
# subsequent updates. Mutable reads stay separate from immutable purity.
g_phys_plan_control:
    push rbx
    mov rbx,rdi
    call g_phys_value_is_input; test eax,eax; jnz .gpctrl_ret
    cmp dword ptr [rip+g_phys_stack_episode],0; jne .gpctrl_no
    cmp qword ptr [rip+g_reg_iter_cond_expr],0; je .gpctrl_no
    mov rdi,rbx; call g_semantic_expr_is_total; test eax,eax; jz .gpctrl_ret
    mov rdi,[rip+g_reg_iter_cond_expr]; mov rsi,rbx; call g_phys_fact_dominates
    jmp .gpctrl_ret
.gpctrl_no: xor eax,eax
.gpctrl_ret: pop rbx; ret

# Same packet generator, disposable bytes. A static work estimate is admitted
# only after seed and resolved placement meet actual emitted transport/footprint
# cost. This is compiler work; neither candidate kernel enters the executable.
g_phys_plan_packet_cost:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi; mov r13d,esi
    G_EMIT_POSITION rax; mov [rsp],rax
    mov rax,[rip+g_runtime_temp_bytes_used]; mov [rsp+8],rax
    mov dword ptr [rip+g_phys_cse_resident_count],0
    xor ebx,ebx
.gpapc_install:
    cmp ebx,r13d; jae .gpapc_generate
    imul rax,rbx,PPR_SIZE
    lea r14,[r12+rax]
    cmp dword ptr [r14+16],0; je .gpapc_next
    mov eax,[rip+g_phys_cse_resident_count]
    mov rdx,[rip+g_phys_cse_resident_reg_ptr]; mov [rdx+rax*4],eax
    mov ecx,[r14+24]
    mov rdx,[rip+g_phys_cse_candidate_cost_ptr]; mov edi,[rdx+rcx*4]
    mov rdx,[rip+g_phys_cse_resident_cost_ptr]; mov [rdx+rax*4],edi
    mov rdx,[rip+g_phys_cse_candidate_expr_ptr]; mov rcx,[rdx+rcx*8]
    mov rdx,[rip+g_phys_cse_resident_expr_ptr]; mov [rdx+rax*8],rcx
    mov ecx,[r14+28]
    mov rdx,[rip+g_phys_cse_resident_type_ptr]; mov [rdx+rax*4],ecx
    inc dword ptr [rip+g_phys_cse_resident_count]
.gpapc_next:
    inc ebx; jmp .gpapc_install
.gpapc_generate:
    call g_phys_cse_order_dependencies
    mov rdi,[rip+g_packet_fact_scope_ptr]
    mov ecx,[rip+g_phys_cse_resident_count]; xor eax,eax; rep stosd
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov dword ptr [rip+g_packet_fact_scope],1
    mov dword ptr [rip+g_packet_register_live],0
    mov dword ptr [rip+g_packet_register_mask],0xfff0
    mov qword ptr [rip+g_packet_register_skip_expr],0
    mov qword ptr [rip+g_packet_last_store_end],0
    mov rdi,[rip+g_phys_plan_root]
    call g_packet_emit_invariant_root
    G_EMIT_POSITION r15              # preheader bytes are not hot work
    mov rdi,[rip+g_phys_plan_root]
    call g_emit_packet_root
    test eax,eax; jz .gpapc_invalid
    G_EMIT_POSITION rax
    sub rax,r15
    imul rax,rax,PRC_FRONTEND_BYTE_TICKS
    mov edx,[rip+g_phys_cse_resident_count]
    imul edx,[rip+group_lane_factor]
    shl edx,3
    add edx,PRC_TRAFFIC_LINE_BYTES-1
    shr edx,6
    imul rdx,rdx,PRC_TRAFFIC_LINE_TICKS
    add rax,rdx
    jmp .gpapc_rewind
.gpapc_invalid:
    mov rax,0x7fffffffffffffff
.gpapc_rewind:
    mov rdx,[rsp]; mov [rip+g_emit_ptr],rdx
    mov rdx,[rsp+8]; mov [rip+g_runtime_temp_bytes_used],rdx
    mov dword ptr [rip+g_phys_cse_resident_count],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov qword ptr [rip+g_packet_last_store_end],0
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Stable dependency order uses the already-proved structural work fact. The
# collector computed it once; sorting never recursively reprices the same DAG.
g_phys_cse_order_dependencies:
    push rbx; push r12; push r13; push r14; push r15
    xor ebx,ebx
.gpcod_outer:
    cmp ebx,[rip+g_phys_cse_resident_count]; jae .gpcod_done
    lea r12d,[rbx+1]
.gpcod_inner:
    cmp r12d,[rip+g_phys_cse_resident_count]; jae .gpcod_outer_next
    mov rax,[rip+g_phys_cse_resident_cost_ptr]
    mov r13d,[rax+rbx*4]
    mov r14d,[rax+r12*4]
    mov rax,[rip+g_phys_cse_resident_frontier_ptr]
    mov r15d,[rax+rbx*4]
    mov eax,[rax+r12*4]
    cmp eax,r15d; jb .gpcod_next
    ja .gpcod_swap
    cmp r14d,r13d; jae .gpcod_next
.gpcod_swap:
    mov rax,[rip+g_phys_cse_resident_frontier_ptr]
    mov edx,[rax+rbx*4]; mov ecx,[rax+r12*4]
    mov [rax+rbx*4],ecx; mov [rax+r12*4],edx
    mov rax,[rip+g_phys_cse_resident_cost_ptr]
    mov [rax+rbx*4],r14d
    mov [rax+r12*4],r13d
    mov rax,[rip+g_phys_cse_resident_expr_ptr]
    mov r14,[rax+rbx*8]; mov r15,[rax+r12*8]
    mov [rax+rbx*8],r15; mov [rax+r12*8],r14
    mov rax,[rip+g_phys_cse_resident_type_ptr]
    mov r14d,[rax+rbx*4]; mov r15d,[rax+r12*4]
    mov [rax+rbx*4],r15d; mov [rax+r12*4],r14d
    mov rax,[rip+g_phys_cse_resident_reg_ptr]
    mov r14d,[rax+rbx*4]; mov r15d,[rax+r12*4]
    mov [rax+rbx*4],r15d; mov [rax+r12*4],r14d
.gpcod_next:
    inc r12d; jmp .gpcod_inner
.gpcod_outer_next:
    inc ebx; jmp .gpcod_outer
.gpcod_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=type -> eax resident slot or -1. During CSE precomputation only
# already materialized slots are visible; during update emission all are ready.
g_phys_cse_find_resident:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    xor ebx,ebx
    mov r14d,dword ptr [rip+g_phys_cse_ready_count]
    cmp dword ptr [rip+g_phys_cse_memory_carrier],0; je .gpcser_loop
    mov r14d,[rip+g_phys_cse_resident_count]
.gpcser_loop:
    cmp ebx,r14d; jae .gpcser_no
    # Negative carrier is a proved control demand. It must never be borrowed
    # as a materialized value, even after its continuation has been emitted.
    mov rax,[rip+g_phys_cse_resident_reg_ptr]
    cmp dword ptr [rax+rbx*4],0; jl .gpcser_next
    mov rax,[rip+g_packet_fact_scope_ptr]; cmp dword ptr [rax+rbx*4],0; jle .gpcser_next
993: mov rax,qword ptr [rip+g_phys_cse_resident_type_ptr]; cmp dword ptr [rax+rbx*4],r13d; jne .gpcser_next
    mov rax,qword ptr [rip+g_phys_cse_resident_expr_ptr]; mov rsi,[rax+rbx*8]
    mov rdi,r12
    cmp r13d,GTYPE_BOOL; je .gpcser_equal_bool
    call g_phys_expr_equal
    jmp .gpcser_equal_done
.gpcser_equal_bool:
    call g_phys_predicate_equal
.gpcser_equal_done:
    test eax,eax; jnz .gpcser_yes
.gpcser_next:
    inc ebx; jmp .gpcser_loop
.gpcser_yes:
    mov eax,ebx; jmp .gpcser_done
.gpcser_no:
    mov eax,-1
.gpcser_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- physical ValueFact transport sparsification ----------------
# A next-generation state does not need to cross a memory handoff merely because
# the semantic timestep boundary was reached.  The only physical constraint is
# causality: an old-version authority may be overwritten immediately after its
# final real consumer.  Selected episode-CSE subtrees are already consumed before
# the update sequence, so their internal state references do not keep an old
# authority live during the update phase.
#
# This is one extension of the existing Physical Reality lifetime model.  It has
# no workload name, state-count threshold, update-index threshold, or private
# transition backend.

# rdi=expr -> eax=1 iff expr is one of the selected episode-CSE ValueFacts.
g_phys_expr_is_selected_cse:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    call g_semantic_expr_is_total
    test eax,eax; jz .gpeisc_no
    mov rdi,r12; call g_infer_expr; mov r14d,eax
    xor ebx,ebx
.gpeisc_loop:
    cmp ebx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpeisc_no
    mov rax,qword ptr [rip+g_phys_cse_resident_type_ptr]
    cmp dword ptr [rax+rbx*4],r14d; jne .gpeisc_next
    mov rax,qword ptr [rip+g_phys_cse_resident_expr_ptr]; mov r13,[rax+rbx*8]
    mov rdi,r12; mov rsi,r13
    cmp r14d,GTYPE_BOOL; je .gpeisc_equal_bool
    call g_phys_expr_equal
    jmp .gpeisc_equal_done
.gpeisc_equal_bool:
    call g_phys_predicate_equal
.gpeisc_equal_done:
    test eax,eax; jnz .gpeisc_yes
.gpeisc_next:
    inc ebx; jmp .gpeisc_loop
.gpeisc_yes:
    mov eax,1; jmp .gpeisc_done
.gpeisc_no:
    xor eax,eax
.gpeisc_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=update expression, esi=semantic consumer identity. Record real
# old-state consumers after selected CSE subtrees have been replaced
# by their resident ValueFacts.
g_phys_note_effective_state_uses:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    test r12,r12; jz .gpnesu_done
    cmp qword ptr [r12],J_OBJECT; jne .gpnesu_done

    mov rdi,r12; call g_phys_expr_is_selected_cse
    test eax,eax; jnz .gpnesu_done

    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpnesu_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpnesu_done
    mov ecx,dword ptr [rax+24]
    cmp ecx,dword ptr [rip+g_state_capacity]; jae .gpnesu_done
    mov edi,ecx; mov esi,r13d; call g_phys_record_state_consumer
    jmp .gpnesu_done

.gpnesu_op:
    # Liveness follows the whole represented graph, not only arithmetic nodes.
    # This makes compare/boolean/select edges ordinary causal consumers.
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpnesu_done
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpnesu_done
    mov r14,[rax+24]
.gpnesu_arg_loop:
    test r14,r14; jz .gpnesu_done
    mov rbx,[r14+32]
    mov rdi,r14; mov esi,r13d; call g_phys_note_effective_state_uses
    mov r14,rbx; jmp .gpnesu_arg_loop
.gpnesu_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=semantic state index -> eax=1 iff the effective expression
# still consumes that old-state authority after selected episode-CSE facts have
# been materialized. This is the same causal-use vocabulary as last-use
# construction, exposed as a local proof query for destination coalescing.
g_phys_expr_effectively_uses_state:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    test r12,r12; jz .gpeeus_done
    cmp qword ptr [r12],J_OBJECT; jne .gpeeus_done

    mov rdi,r12; call g_phys_expr_is_selected_cse
    test eax,eax; jnz .gpeeus_no

    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpeeus_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpeeus_no
    cmp dword ptr [rax+24],r13d; sete al; movzx eax,al
    jmp .gpeeus_done

.gpeeus_op:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpeeus_no
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpeeus_no
    mov r14,[rax+24]
.gpeeus_arg_loop:
    test r14,r14; jz .gpeeus_no
    mov rbx,[r14+32]
    mov rdi,r14; mov esi,r13d; call g_phys_expr_effectively_uses_state
    test eax,eax; jnz .gpeeus_yes
    mov r14,rbx; jmp .gpeeus_arg_loop
.gpeeus_no:
    xor eax,eax; jmp .gpeeus_done
.gpeeus_yes:
    mov eax,1
.gpeeus_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expression, esi=semantic state index -> eax=1 iff the source graph
# contains that exact StateFact.  This is raw semantic reachability: unlike
# last-consumer analysis it deliberately does not erase selected CSE roots,
# because a counted Axis cannot change representation while any per-episode
# ValueFact still observes its numeric coordinate.
g_expr_uses_semantic_state:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    test r12,r12; jz .geuss_done
    cmp qword ptr [r12],J_OBJECT; jne .geuss_done
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .geuss_args
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .geuss_no
    cmp dword ptr [rax+24],r13d; sete al; movzx eax,al
    jmp .geuss_done
.geuss_args:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .geuss_no
    mov r14,[rax+24]
.geuss_arg_loop:
    test r14,r14; jz .geuss_no
    mov rbx,[r14+32]
    mov rdi,r14; mov esi,r13d; call g_expr_uses_semantic_state
    test eax,eax; jnz .geuss_yes
    mov r14,rbx; jmp .geuss_arg_loop
.geuss_yes:
    mov eax,1; jmp .geuss_done
.geuss_no:
    xor eax,eax
.geuss_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# -> eax=1 when no transition data consumes the increasing ordinal. The
# remaining distance then owns the loop coordinate; an exact counted exit
# publishes the original bound. Final-only consumers do not require an ordinal
# to be maintained on every transition.
g_phys_prove_countdown_axis:
    push rbx; push r12; push r13; push r14
    xor eax,eax
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gppca_done
    mov r13d,dword ptr [rip+g_reg_iter_counter_index]

    xor ebx,ebx
.gppca_scan:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gppca_yes
    cmp ebx,r13d; je .gppca_next
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gppca_next
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    call obj_get
    test rax,rax; jz .gppca_done
    mov rdi,rax; mov esi,r13d; call g_expr_uses_semantic_state
    test eax,eax; jnz .gppca_no
.gppca_next:
    inc ebx; jmp .gppca_scan
.gppca_yes:
    mov eax,1; jmp .gppca_done
.gppca_no:
    xor eax,eax
.gppca_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=next-state expression, esi=its semantic state index -> eax=1 only when
# the current strict emitter can realize the next ValueFact directly in the
# same old-state carrier without destroying an input that is still needed.
# The proof is intentionally structural and generic: the top-level left source
# must be that exact state authority, while the right subtree must have no
# effective use of it after selected episode-CSE replacement. No commutation,
# reassociation, workload matcher, or alternate recurrence backend is involved.
g_phys_fp_can_birth_in_old_authority:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    test r12,r12; jz .gpfcbioa_done
    cmp qword ptr [r12],J_OBJECT; jne .gpfcbioa_done
    mov rdi,r12; call g_phys_value_expr_is_shareable_op
    test eax,eax; jz .gpfcbioa_done
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfcbioa_done
    mov r14,[rax+24]; test r14,r14; jz .gpfcbioa_done
    mov r15,[r14+32]; test r15,r15; jz .gpfcbioa_done
    cmp qword ptr [r15+32],0; jne .gpfcbioa_done

    # The emitter evaluates/borrows the left edge first. Requiring the exact
    # old-state leaf here makes aliasing the destination safe without changing
    # the expression's strict operation order.
    mov rdi,r14; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpfcbioa_done
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpfcbioa_done
    cmp dword ptr [rax+24],r13d; jne .gpfcbioa_done

    # Any remaining effective use on the right would observe the overwritten
    # value. Selected CSE subtrees are already materialized before updates and
    # therefore correctly disappear from this live-use query.
    mov rdi,r15; mov esi,r13d; call g_phys_expr_effectively_uses_state
    test eax,eax; jnz .gpfcbioa_done
    mov eax,1
.gpfcbioa_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Finalize FP StateFact carriers from actual episode liveness after shared facts
# have converged. This is one carrier authority, not an in-place/disjoint mode:
# each state either keeps its old carrier once that value is dead, retains one
# genuinely spare next carrier while the old value is still live, or remains a
# transient next ValueFact when physical pressure leaves no spare carrier.
#
# Re-profile anonymous pressure with retained CSE/ConstantFacts already fixed.
# The speculative bytes are discarded; only g_phys_fp_temp_peak survives.
g_phys_reprofile_fp_pressure:
    push rbx; push r12; push r13; push r14; push r15
    G_EMIT_POSITION r15
    mov dword ptr [rip+g_phys_fp_temp_peak],0
    mov dword ptr [rip+g_phys_fp_temp_live],0
    mov dword ptr [rip+g_phys_fp_temp_exhausted],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov eax,dword ptr [rip+g_reg_iter_total]
    mov dword ptr [rip+g_state_count],eax

    # Both current-generation frontiers share this exact pressure probe.
    call g_emit_phys_episode_control
    test eax,eax; jnz .gprfpp_fail
    call g_emit_phys_episode_cse
    test eax,eax; jnz .gprfpp_fail

    xor ebx,ebx
.gprfpp_loop:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gprfpp_ok
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gprfpp_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gprfpp_real
    cmp ebx,dword ptr [rip+g_reg_iter_counter_index]; je .gprfpp_next
.gprfpp_real:
    mov r13d,dword ptr [r11+16]
    cmp r13d,GTYPE_F64; je .gprfpp_fp
    cmp r13d,GTYPE_F32; jne .gprfpp_next
.gprfpp_fp:
    mov rax,[rip+g_phys_update_expr_ptr]; mov r12,[rax+rbx*8]
    call g_phys_temp_reset
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov r14d,dword ptr [rdx+rbx*4]
    cmp r14d,0; jge .gprfpp_have_dest
    call g_phys_fp_temp_alloc
    cmp eax,0; jl .gprfpp_fail
    mov r14d,eax
    mov rdi,r12; mov esi,r14d; mov edx,r13d; call g_emit_phys_fp_expr_to
    cmp eax,r13d; jne .gprfpp_fail_free
    mov edi,r14d; call g_phys_fp_temp_free
    jmp .gprfpp_next
.gprfpp_have_dest:
    mov rdi,r12; mov esi,r14d; mov edx,r13d; call g_emit_phys_fp_expr_to
    cmp eax,r13d; jne .gprfpp_fail
.gprfpp_next:
    inc ebx; jmp .gprfpp_loop
.gprfpp_fail_free:
    mov edi,r14d; call g_phys_fp_temp_free
.gprfpp_fail:
    mov [rip+g_emit_ptr],r15
    mov eax,1
    jmp .gprfpp_done
.gprfpp_ok:
    mov [rip+g_emit_ptr],r15
    mov eax,dword ptr [rip+g_phys_cse_resident_count]
    mov dword ptr [rip+g_phys_cse_ready_count],eax
    xor eax,eax
.gprfpp_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Collapse safe next-StateFacts into their old carriers, then retain disjoint
# output carriers only from slack beyond the re-profiled anonymous requirement.
# No state count, equation family, benchmark identity or workload threshold is
# consulted.
g_phys_finalize_fp_state_carriers:
    push rbx; push r12; push r13; push r14; push r15
    call g_phys_reprofile_fp_pressure
    test eax,eax; jnz .gpffsc_fail
    xor ebx,ebx
.gpffsc_promote:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gpffsc_promoted
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]
    cmp dword ptr [rax+rbx*4],G_PHYS_CARRIER_FP; jne .gpffsc_promote_next
    # Scalar stack recipes used while initializing later states and the bound
    # really clobber XMM0/1; scalar fold also owns XMM3. These concrete recipe
    # roles, rather than a fixed half-bank, constrain persistent old values.
    mov edi,(1<<0)|(1<<1)|(1<<3)
    call g_phys_shared_xmm_alloc
    cmp eax,0; jl .gpffsc_promote_next
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov [rdx+rbx*4],eax
    bts dword ptr [rip+g_phys_fp_reserved_mask],eax
.gpffsc_promote_next:
    inc ebx; jmp .gpffsc_promote
.gpffsc_promoted:
    # Prove the completed residency once, rather than re-emitting the whole
    # episode for every admitted owner. Actual exhaustion ages one old owner
    # back into its established frame authority and repeats the same proof.
    call g_phys_reprofile_fp_pressure
    test eax,eax; jz .gpffsc_old_proved
    cmp dword ptr [rip+g_phys_fp_temp_exhausted],0; je .gpffsc_fail
    mov ebx,dword ptr [rip+g_reg_iter_total]
.gpffsc_old_release:
    dec ebx; js .gpffsc_fail
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]
    cmp dword ptr [rax+rbx*4],G_PHYS_CARRIER_FP; jne .gpffsc_old_release
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov eax,[rdx+rbx*4]
    cmp eax,0; jl .gpffsc_old_release
    mov dword ptr [rdx+rbx*4],-1
    btr dword ptr [rip+g_phys_fp_reserved_mask],eax
    jmp .gpffsc_promoted
.gpffsc_old_proved:
    xor ebx,ebx
.gpffsc_birth_loop:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gpffsc_reprofile
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gpffsc_birth_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gpffsc_birth_real
    cmp ebx,dword ptr [rip+g_reg_iter_counter_index]; je .gpffsc_birth_next
.gpffsc_birth_real:
    mov r13d,dword ptr [r11+16]
    cmp r13d,GTYPE_F64; je .gpffsc_birth_fp
    cmp r13d,GTYPE_F32; jne .gpffsc_birth_next
.gpffsc_birth_fp:
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov r12d,dword ptr [rdx+rbx*4]
    cmp r12d,0; jl .gpffsc_birth_next
    mov rdx,[rip+g_phys_state_last_use_ptr]; mov eax,dword ptr [rdx+rbx*4]
    mov rcx,[rip+g_phys_update_position_ptr]
    cmp eax,[rcx+rbx*4]; jl .gpffsc_birth_safe
    jne .gpffsc_birth_next
    # The update itself is the final consumer. Direct birth is safe only when
    # the existing structural proof shows the emitter consumes the old value
    # before overwriting that carrier.
    mov rax,[rip+g_phys_update_expr_ptr]
    mov rdi,[rax+rbx*8]; mov esi,ebx; call g_phys_fp_can_birth_in_old_authority
    test eax,eax; jz .gpffsc_birth_next
.gpffsc_birth_safe:
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov r14d,dword ptr [rdx+rbx*4]
    cmp r14d,0; jl .gpffsc_birth_publish
    cmp r14d,r12d; je .gpffsc_birth_publish
    btr dword ptr [rip+g_phys_fp_reserved_mask],r14d
.gpffsc_birth_publish:
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rdx+rbx*4],r12d
.gpffsc_birth_next:
    inc ebx; jmp .gpffsc_birth_loop

.gpffsc_reprofile:
    call g_phys_reprofile_fp_pressure
    test eax,eax; jnz .gpffsc_fail
    xor ebx,ebx
.gpffsc_retain_loop:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gpffsc_verify
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gpffsc_retain_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gpffsc_retain_real
    cmp ebx,dword ptr [rip+g_reg_iter_counter_index]; je .gpffsc_retain_next
.gpffsc_retain_real:
    mov r13d,dword ptr [r11+16]
    cmp r13d,GTYPE_F64; je .gpffsc_retain_fp
    cmp r13d,GTYPE_F32; jne .gpffsc_retain_next
.gpffsc_retain_fp:
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; cmp dword ptr [rdx+rbx*4],0; jl .gpffsc_retain_next
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; cmp dword ptr [rdx+rbx*4],0; jge .gpffsc_retain_next
    # Retention is admitted only from carrier slack beyond the full measured
    # anonymous peak; no destination-shaped credit is inferred from that scalar.
    xor edi,edi
    call g_phys_shared_xmm_alloc
    cmp eax,0; jl .gpffsc_retain_next
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rdx+rbx*4],eax
    bts dword ptr [rip+g_phys_fp_reserved_mask],eax
.gpffsc_retain_next:
    inc ebx; jmp .gpffsc_retain_loop
.gpffsc_verify:
    # Carrier identity changes operand realization and anonymous lifetimes.
    # Prove the completed map once. Only actual carrier exhaustion invalidates
    # residency and requires another realization of this same Physical DAG.
    call g_phys_reprofile_fp_pressure
    test eax,eax; jz .gpffsc_ok
    cmp dword ptr [rip+g_phys_fp_temp_exhausted],0; je .gpffsc_fail
    mov ebx,dword ptr [rip+g_reg_iter_total]
.gpffsc_release:
    dec ebx; js .gpffsc_fail
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov eax,dword ptr [r11+16]
    cmp eax,GTYPE_F32; je .gpffsc_release_fp
    cmp eax,GTYPE_F64; jne .gpffsc_release
.gpffsc_release_fp:
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov eax,dword ptr [rdx+rbx*4]
    cmp eax,0; jl .gpffsc_release
    mov rcx,[rip+g_reg_iter_old_reg_ptr]
    cmp eax,dword ptr [rcx+rbx*4]; je .gpffsc_release
    # A disjoint next-version carrier competes with anonymous expressions.
    # Its established transient handoff preserves simultaneous-state semantics.
    # Each failed proof removes one owner; finite ownership bounds the search.
    mov dword ptr [rdx+rbx*4],-1
    btr dword ptr [rip+g_phys_fp_reserved_mask],eax
    jmp .gpffsc_verify
.gpffsc_ok:
    xor eax,eax; jmp .gpffsc_done
.gpffsc_fail:
    mov eax,1
.gpffsc_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Erase declaration order only inside an already-proved total frontier. The
# immutable old generation has no update-to-update mathematical edge; its real
# consumers decide when each physical authority can be reused. The existing
# growable edge arena stages this incidence temporarily, then resumes its
# fragment role unchanged. No extra graph, scheduler or search survives AOT.
g_phys_order_state_updates:
    push rbp; push rbx; push r12; push r13; push r14; push r15
    mov ebp,[rip+g_edge_count]
    mov dword ptr [rip+g_phys_update_order_error],0
    mov r14d,[rip+g_reg_iter_total]
    xor ebx,ebx
.gposu_clear:
    cmp ebx,r14d; jae .gposu_collect_start
    mov rax,[rip+g_phys_update_position_ptr]; mov dword ptr [rax+rbx*4],-1
    mov rax,[rip+g_phys_update_pending_ptr]; mov dword ptr [rax+rbx*4],0
    mov rax,[rip+g_phys_state_last_use_ptr]; mov dword ptr [rax+rbx*4],-1
    mov rax,[rip+g_phys_update_total_ptr]; mov dword ptr [rax+rbx*4],0
    inc ebx; jmp .gposu_clear
.gposu_collect_start:
    xor ebx,ebx
.gposu_collect:
    cmp ebx,r14d; jae .gposu_order_start
    mov eax,ebx; shl rax,5; mov r12,[rip+g_states_ptr]; add r12,rax
    cmp dword ptr [r12+28],-1; je .gposu_collect_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gposu_collect_real
    cmp ebx,[rip+g_reg_iter_counter_index]; je .gposu_collect_next
.gposu_collect_real:
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r12]; mov edx,[r12+8]; call obj_get
    test rax,rax; jz .gposu_fail
    mov r13,rax
    mov rdx,[rip+g_phys_update_expr_ptr]; mov [rdx+rbx*8],rax
    mov rdi,r13; call g_semantic_expr_is_total
    mov rdx,[rip+g_phys_update_total_ptr]; mov [rdx+rbx*4],eax
    # Already-selected guard Regions emit before this update frontier. Keep
    # their source frontier fixed rather than invent a second control schedule.
    mov rdi,r13; call g_phys_top_select_guard_index
    cmp eax,0; jl .gposu_incidence
    mov rdx,[rip+g_phys_update_total_ptr]; mov dword ptr [rdx+rbx*4],0
.gposu_incidence:
    mov rdi,r13; mov esi,ebx; call g_phys_note_effective_state_uses
    cmp dword ptr [rip+g_phys_update_order_error],0; jne .gposu_fail
.gposu_collect_next:
    inc ebx; jmp .gposu_collect
.gposu_order_start:
    xor ebx,ebx
.gposu_frontier:
    cmp ebx,r14d; jae .gposu_last_use
    mov rax,[rip+g_phys_update_total_ptr]
    cmp dword ptr [rax+rbx*4],0; je .gposu_fixed
    mov r15d,ebx
.gposu_end:
    cmp r15d,r14d; jae .gposu_ready_start
    cmp dword ptr [rax+r15*4],0; je .gposu_ready_start
    inc r15d; jmp .gposu_end
.gposu_ready_start:
    mov r13d,ebx
.gposu_ready:
    cmp r13d,r15d; jae .gposu_next_frontier
    mov ecx,ebx; mov r10d,-1; mov r12d,-1
    mov r8,[rip+g_phys_update_position_ptr]
    mov r9,[rip+g_phys_update_pending_ptr]
.gposu_choose:
    cmp ecx,r15d; jae .gposu_publish
    cmp dword ptr [r8+rcx*4],0; jge .gposu_choose_next
    mov edx,[r9+rcx*4]
    cmp edx,r10d; jae .gposu_choose_next
    mov r10d,edx; mov r12d,ecx
.gposu_choose_next:
    inc ecx; jmp .gposu_choose
.gposu_publish:
    cmp r12d,0; jl .gposu_fail
    mov rax,[rip+g_phys_update_order_ptr]; mov [rax+r13*4],r12d
    mov rax,[rip+g_phys_update_position_ptr]; mov [rax+r12*4],r13d
    call .gposu_consume
    inc r13d; jmp .gposu_ready
.gposu_next_frontier:
    mov ebx,r15d; jmp .gposu_frontier
.gposu_fixed:
    mov rax,[rip+g_phys_update_order_ptr]; mov [rax+rbx*4],ebx
    mov rax,[rip+g_phys_update_position_ptr]; mov [rax+rbx*4],ebx
    mov r12d,ebx; call .gposu_consume
    inc ebx; jmp .gposu_frontier
.gposu_consume:
    mov ecx,ebp
    mov r8,[rip+g_edge_u_ptr]; mov r9,[rip+g_edge_v_ptr]
    mov r10,[rip+g_phys_update_pending_ptr]
.gposu_consume_edge:
    cmp ecx,[rip+g_edge_count]; jae .gposu_consume_done
    cmp [r9+rcx*4],r12d; jne .gposu_consume_next
    mov eax,[r8+rcx*4]; cmp eax,r12d; je .gposu_consume_next
    dec dword ptr [r10+rax*4]
.gposu_consume_next:
    inc ecx; jmp .gposu_consume_edge
.gposu_consume_done:
    ret
.gposu_last_use:
    # Project the completed permutation onto the same incidence once. No
    # source rewalk, identity reproof or second liveness graph is needed.
    mov ecx,ebp
    mov r8,[rip+g_edge_u_ptr]; mov r9,[rip+g_edge_v_ptr]
    mov r10,[rip+g_phys_update_position_ptr]
    mov r11,[rip+g_phys_state_last_use_ptr]
.gposu_last_edge:
    cmp ecx,[rip+g_edge_count]; jae .gposu_done
    mov eax,[r8+rcx*4]; mov edx,[r9+rcx*4]; mov edx,[r10+rdx*4]
    cmp edx,[r11+rax*4]; jle .gposu_last_next
    mov [r11+rax*4],edx
.gposu_last_next:
    inc ecx; jmp .gposu_last_edge
.gposu_fail:
    mov dword ptr [rip+g_phys_update_order_error],1
.gposu_done:
    mov [rip+g_edge_count],ebp
    mov eax,[rip+g_phys_update_order_error]
    pop r15; pop r14; pop r13; pop r12; pop rbx; pop rbp; ret

# edi=old StateFact, esi=consumer. Self use cannot prevent placement of its
# own expression; the existing native birth proof separately decides aliasing.
g_phys_record_state_consumer:
    cmp dword ptr [rip+g_phys_update_order_error],0; jne .gprsc_done
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov eax,[rip+g_edge_count]
    cmp eax,[rip+g_edge_capacity]; jb .gprsc_room
    call g_grow_edge_arena
    test eax,eax; jnz .gprsc_fail
    mov eax,[rip+g_edge_count]
.gprsc_room:
    mov rdx,[rip+g_edge_u_ptr]; mov [rdx+rax*4],ebx
    mov rdx,[rip+g_edge_v_ptr]; mov [rdx+rax*4],r12d
    inc dword ptr [rip+g_edge_count]
    cmp ebx,r12d; je .gprsc_return
    mov rdx,[rip+g_phys_update_pending_ptr]; inc dword ptr [rdx+rbx*4]
    jmp .gprsc_return
.gprsc_fail:
    mov dword ptr [rip+g_phys_update_order_error],1
.gprsc_return:
    pop r12; pop rbx
.gprsc_done:
    ret

# rdi=BOOL expression, esi=destination XMM -> eax=0 when a selected binary
# PredicateFact was realized directly from already-resident children, 1 otherwise.
# AND/OR/XOR are bit relations over canonical 0/1 payloads, so the mathematical
# BOOL DAG maps directly to one VEX/EVEX bitwise relation without control detours.
g_emit_phys_bool_binary_cse_to_xmm:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov r12,rdi; mov r13d,esi
    cmp qword ptr [r12],J_OBJECT; jne .gepbbcx_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gepbbcx_no
    mov r14,rax
    mov dword ptr [rsp],0
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq
    test eax,eax; jz .gepbbcx_try_or
    mov dword ptr [rsp],0x54; jmp .gepbbcx_args
.gepbbcx_try_or:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq
    test eax,eax; jz .gepbbcx_try_xor
    mov dword ptr [rsp],0x56; jmp .gepbbcx_args
.gepbbcx_try_xor:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq
    test eax,eax; jz .gepbbcx_no
    mov dword ptr [rsp],0x57
.gepbbcx_args:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gepbbcx_no
    mov r14,[rax+24]; test r14,r14; jz .gepbbcx_no
    mov r15,[r14+32]; test r15,r15; jz .gepbbcx_no
    cmp qword ptr [r15+32],0; jne .gepbbcx_no
    mov rdi,r14; mov esi,GTYPE_BOOL; call g_phys_cse_find_resident
    cmp eax,0; jl .gepbbcx_no
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov ebx,dword ptr [rcx+rax*4]
    mov rdi,r15; mov esi,GTYPE_BOOL; call g_phys_cse_find_resident
    cmp eax,0; jl .gepbbcx_no
    mov rcx,[rip+g_phys_cse_resident_reg_ptr]; mov ecx,dword ptr [rcx+rax*4]
    mov edi,dword ptr [rsp]; mov esi,r13d; mov edx,ebx
    call g_emit_phys_vex_bits3
    test eax,eax; jnz .gepbbcx_no
    xor eax,eax; jmp .gepbbcx_done
.gepbbcx_no:
    mov eax,1
.gepbbcx_done:
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Emit the selected shared old-version facts once at the top of every causal
# iteration. Numeric demands retain normal Physical ValueFact carriers:
# XMM for immutable scalar bits, with ordinary GPR integer producers. A proved control-only fact has no
# numeric producer; its existing continuation is consumed at the guard frontier.
g_emit_phys_episode_control:
    mov edi,2
    jmp g_emit_phys_episode_values
g_emit_phys_episode_cse:
    mov edi,1
g_emit_phys_episode_values:
    push rbx; push r12; push r13; push r14
    sub rsp,16
    mov [rsp],edi
    mov dword ptr [rip+g_packet_fact_scope],1
    xor ebx,ebx
.gepec_reset:
    cmp ebx,[rip+g_phys_cse_resident_count]; jae .gepec_reset_done
    mov rax,[rip+g_phys_cse_resident_frontier_ptr]; mov eax,[rax+rbx*4]
    cmp dword ptr [rsp],0; je .gepec_clear
    cmp eax,2; je .gepec_reset_next
    cmp dword ptr [rsp],2; je .gepec_clear
    cmp eax,1; je .gepec_reset_next
.gepec_clear:
    mov rax,[rip+g_packet_fact_scope_ptr]; mov dword ptr [rax+rbx*4],0
.gepec_reset_next:
    inc ebx; jmp .gepec_reset
.gepec_reset_done:
    mov dword ptr [rip+g_phys_cse_ready_count],0
    xor ebx,ebx
    cmp edi,1; jne .gepec_loop
    cmp dword ptr [rip+g_phys_stack_episode],0; jne .gepec_loop
    mov ebx,[rip+g_phys_cse_control_ready_count]
    mov [rip+g_phys_cse_ready_count],ebx
.gepec_loop:
    cmp ebx,dword ptr [rip+g_phys_cse_resident_count]; jae .gepec_done
    mov rax,qword ptr [rip+g_phys_cse_resident_expr_ptr]; mov r12,[rax+rbx*8]
    mov rax,qword ptr [rip+g_phys_cse_resident_type_ptr]; mov r13d,dword ptr [rax+rbx*4]
    mov rax,qword ptr [rip+g_phys_cse_resident_reg_ptr]; mov r14d,dword ptr [rax+rbx*4]
    mov rax,[rip+g_phys_cse_resident_frontier_ptr]; mov eax,[rax+rbx*4]
    cmp dword ptr [rsp],0; je .gepec_preheader
    cmp eax,2; je .gepec_ready
    cmp dword ptr [rsp],2; jne .gepec_produce
    test eax,eax; jz .gepec_done
    jmp .gepec_produce
.gepec_preheader:
    cmp eax,2; jne .gepec_done
.gepec_produce:
    test r14d,r14d; js .gepec_ready
    mov rdi,r12; call g_semantic_expr_is_total
    test eax,eax; jz .gepec_ready
    call g_phys_temp_reset
    cmp dword ptr [rip+g_phys_stack_episode],1; je .gepec_general
    cmp r13d,GTYPE_U64; je .gepec_int
    cmp r13d,GTYPE_I64; je .gepec_int
    cmp r13d,GTYPE_BOOL; je .gepec_bool
    mov rdi,r12; mov esi,r14d; mov edx,r13d; call g_emit_phys_fp_value_to
    cmp eax,r13d; jne .gepec_bad
    jmp .gepec_materialized
.gepec_int:
    call g_phys_int_temp_alloc; test eax,eax; js .gepec_bad
    mov [rsp+4],eax
    mov rdi,r12; mov esi,eax; mov edx,r13d; call g_emit_phys_int_expr_to
    cmp eax,r13d; jne .gepec_bad
    xor edi,edi; mov esi,[rsp+4]; call g_emit_phys_gpr_move
    mov edi,[rsp+4]; call g_phys_int_temp_free
    mov edi,r14d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gepec_bad
    jmp .gepec_materialized
.gepec_bool:
    mov rdi,r12; mov esi,r14d; call g_emit_phys_bool_binary_cse_to_xmm
    test eax,eax; jz .gepec_materialized
    mov rdi,r12; call g_emit_phys_bool_expr_to_rax
    test eax,eax; jnz .gepec_bad
    mov edi,r14d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gepec_bad
    jmp .gepec_materialized
.gepec_general:
    mov rdi,r12; call g_emit_expr
    cmp eax,r13d; jne .gepec_bad
    call g_emit_pop_rax
    cmp r13d,GTYPE_U64; je .gepec_general_int
    cmp r13d,GTYPE_I64; je .gepec_general_int
    mov edi,r14d; mov esi,r13d; call g_emit_phys_xmm_from_rax
    jmp .gepec_materialized
.gepec_general_int:
    mov edi,r14d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
.gepec_materialized:
    mov rax,[rip+g_packet_fact_scope_ptr]; mov dword ptr [rax+rbx*4],1
.gepec_ready:
    inc dword ptr [rip+g_phys_cse_ready_count]
    inc ebx; jmp .gepec_loop
.gepec_done:
    cmp dword ptr [rsp],2; jne .gepec_no_control_publish
    mov eax,[rip+g_phys_cse_ready_count]; mov [rip+g_phys_cse_control_ready_count],eax
.gepec_no_control_publish:
    # Only the materialized prefix is visible. A condition emitted before
    # timestep refresh cannot read any old-generation shared state value.
    xor eax,eax; jmp .gepec_ret
.gepec_bad:
    mov eax,1
.gepec_ret:
    add rsp,16
    pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- unified scalar constant Physical Reality ----------------
# ConstantFacts share the same compile-time fact capacity and carrier authority
# as episode CSE. Residency is selected AOT by reuse; there is no separate
# constant bank, source-order eight-value cliff, or runtime cache manager.
# Anonymous reserve equals the exact peak lifetime proven over the episode.

# rdi=bits, esi=type. Notes one static use.
g_phys_const_note:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13d,esi
    xor ebx,ebx
.gpcn_scan:
    cmp ebx,dword ptr [rip+g_phys_const_candidate_count]; jae .gpcn_new
    mov rax,qword ptr [rip+g_phys_const_candidate_bits_ptr]; cmp [rax+rbx*8],r12; jne .gpcn_next
    mov rax,qword ptr [rip+g_phys_const_candidate_type_ptr]; cmp dword ptr [rax+rbx*4],r13d; jne .gpcn_next
    mov rax,qword ptr [rip+g_phys_const_candidate_uses_ptr]; inc dword ptr [rax+rbx*4]
    xor eax,eax; jmp .gpcn_done
.gpcn_next:
    inc ebx; jmp .gpcn_scan
.gpcn_new:
    cmp ebx,dword ptr [rip+g_phys_fact_capacity]; jae .gpcn_ok
    mov rax,qword ptr [rip+g_phys_const_candidate_bits_ptr]; mov [rax+rbx*8],r12
    mov rax,qword ptr [rip+g_phys_const_candidate_type_ptr]; mov dword ptr [rax+rbx*4],r13d
    mov rax,qword ptr [rip+g_phys_const_candidate_uses_ptr]; mov dword ptr [rax+rbx*4],1
    inc dword ptr [rip+g_phys_const_candidate_count]
.gpcn_ok: xor eax,eax
.gpcn_done: pop r13; pop r12; pop rbx; ret

# ConstantFacts consume the same shared bank and the same compile-time planner;
# their static pool and late state-carrier lifetime proofs remain authoritative.
g_phys_const_finalize:
    push rbx; push r12; push r13; push r14; push r15
    mov dword ptr [rip+g_phys_const_resident_count],0
    mov edi,[rip+g_phys_const_candidate_count]
    mov r15d,edi
    test edi,edi; jz .gpca_done
    call physical_plan_alloc
    test rax,rax; jz .gpca_done
    mov r12,rax
    xor r13d,r13d
    xor ebx,ebx
.gpca_build:
    cmp ebx,r15d; jae .gpca_search
    mov rax,[rip+g_phys_const_candidate_uses_ptr]
    mov eax,[rax+rbx*4]
    test eax,eax; jz .gpca_next
    imul rax,rax,PRC_LOAD_AGU_TICKS-PRC_FP_ADD_TICKS
    imul rdx,r13,PPR_SIZE
    lea rdx,[r12+rdx]
    mov [rdx],rax
    mov [rdx+24],ebx
    mov dword ptr [rdx+8],1
    inc r13d
.gpca_next:
    inc ebx; jmp .gpca_build
.gpca_search:
    call g_phys_plan_budgets
    mov edx,ecx
    xor ecx,ecx
    xor r8d,r8d
    xor r9d,r9d
    mov rdi,r12
    mov esi,r13d
    sub rsp,16
    mov qword ptr [rsp],0
    call physical_plan_resolve
    add rsp,16
    xor ebx,ebx
.gpca_realize:
    cmp ebx,r13d; jae .gpca_free
    imul rax,rbx,PPR_SIZE
    cmp dword ptr [r12+rax+16],0; je .gpca_realize_next
    mov r14d,[r12+rax+24]
    xor edi,edi
    call g_phys_shared_xmm_alloc
    test eax,eax; js .gpca_realize_next
    mov ecx,[rip+g_phys_const_resident_count]
    mov rdx,[rip+g_phys_const_resident_reg_ptr]; mov [rdx+rcx*4],eax
    mov rdx,[rip+g_phys_const_candidate_bits_ptr]; mov rax,[rdx+r14*8]
    mov rdx,[rip+g_phys_const_resident_bits_ptr]; mov [rdx+rcx*8],rax
    mov rdx,[rip+g_phys_const_candidate_type_ptr]; mov eax,[rdx+r14*4]
    mov rdx,[rip+g_phys_const_resident_type_ptr]; mov [rdx+rcx*4],eax
    inc dword ptr [rip+g_phys_const_resident_count]
.gpca_realize_next:
    inc ebx; jmp .gpca_realize
.gpca_free:
    mov rdi,r12
    mov esi,r15d
    call physical_plan_free
.gpca_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=bits, esi=type -> eax resident slot, or -1.
g_phys_const_find_resident:
    xor ecx,ecx
.gpcfr_loop:
    cmp ecx,dword ptr [rip+g_phys_const_resident_count]; jae .gpcfr_no
    mov rax,qword ptr [rip+g_phys_const_resident_bits_ptr]; cmp [rax+rcx*8],rdi; jne .gpcfr_next
    mov rax,qword ptr [rip+g_phys_const_resident_type_ptr]; cmp dword ptr [rax+rcx*4],esi; jne .gpcfr_next
    mov eax,ecx; ret
.gpcfr_next:
    inc ecx; jmp .gpcfr_loop
.gpcfr_no: mov eax,-1; ret

# rdi=bits, esi=type -> eax candidate slot, or -1.  Candidate identity is
# the single immutable ConstantFact identity used by both register residency and
# static-address realization.
g_phys_const_find_candidate:
    xor ecx,ecx
.gpcfc_loop:
    cmp ecx,dword ptr [rip+g_phys_const_candidate_count]; jae .gpcfc_no
    mov rax,qword ptr [rip+g_phys_const_candidate_bits_ptr]; cmp [rax+rcx*8],rdi; jne .gpcfc_next
    mov rax,qword ptr [rip+g_phys_const_candidate_type_ptr]; cmp dword ptr [rax+rcx*4],esi; jne .gpcfc_next
    mov eax,ecx; ret
.gpcfc_next:
    inc ecx; jmp .gpcfc_loop
.gpcfc_no:
    mov eax,-1; ret

# Emit one immutable scalar literal pool into the generated image and jump over
# it once in the preheader.  Every candidate gets one stable RIP-relative
# address; resident constants and memory-consumed constants therefore share the
# same ConstantFact identity rather than separate banks.
g_emit_phys_constant_pool:
    push rbx; push r12; push r13; push r14
    mov dword ptr [rip+g_phys_const_pool_ready],0
    cmp dword ptr [rip+g_phys_const_candidate_count],0; je .gepcp_empty
    call g_emit_jmp_patch
    test rax,rax; jz .gepcp_bad
    mov r12,rax
    xor ebx,ebx
.gepcp_loop:
    cmp ebx,dword ptr [rip+g_phys_const_candidate_count]; jae .gepcp_finish
    G_EMIT_POSITION rax
    mov rdx,[rip+g_phys_const_candidate_pool_ptr]
    mov [rdx+rbx*8],rax
    mov rax,[rip+g_phys_const_candidate_type_ptr]
    mov r13d,dword ptr [rax+rbx*4]
    mov rax,[rip+g_phys_const_candidate_bits_ptr]
    mov r14,[rax+rbx*8]
    cmp r13d,GTYPE_F64; je .gepcp_f64
    cmp r13d,GTYPE_F32; jne .gepcp_bad
    mov edi,r14d; call g_emit_u32; test eax,eax; jnz .gepcp_bad
    jmp .gepcp_next
.gepcp_f64:
    mov rdi,r14; call g_emit_u64; test eax,eax; jnz .gepcp_bad
.gepcp_next:
    inc ebx; jmp .gepcp_loop
.gepcp_finish:
    G_EMIT_POSITION rsi; mov rdi,r12; call g_patch_rel32
    mov dword ptr [rip+g_phys_const_pool_ready],1
.gepcp_empty:
    xor eax,eax; jmp .gepcp_done
.gepcp_bad:
    mov eax,1
.gepcp_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# Emit one preheader materialization per retained ConstantFact.
g_emit_phys_resident_constants:
    push rbx; push r12; push r13; push r14
    xor ebx,ebx
.geprc_loop:
    cmp ebx,dword ptr [rip+g_phys_const_resident_count]; jae .geprc_done
    mov rax,qword ptr [rip+g_phys_const_resident_bits_ptr]; mov r12,[rax+rbx*8]
    mov rax,qword ptr [rip+g_phys_const_resident_type_ptr]; mov r13d,dword ptr [rax+rbx*4]
    mov rax,qword ptr [rip+g_phys_const_resident_reg_ptr]; mov r14d,dword ptr [rax+rbx*4]
    cmp r13d,GTYPE_F64; je .geprc_f64
    cmp r13d,GTYPE_F32; jne .geprc_fail
    mov edi,r12d; call g_emit_mov_eax_imm
    mov edi,r14d; mov esi,GTYPE_F32; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .geprc_fail
    jmp .geprc_next
.geprc_f64:
    mov rdi,r12; call g_emit_mov_rax_imm64
    mov edi,r14d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .geprc_fail
.geprc_next:
    inc ebx; jmp .geprc_loop
.geprc_fail:
    mov eax,1; jmp .geprc_ret
.geprc_done: xor eax,eax
.geprc_ret: pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- Guarded Physical Regions ----------------
# A repeated top-level select predicate is not a scalar decoration on each state;
# it is one causal control edge with multiple next-StateFact consumers.  Region
# formation below is driven only by exact PredicateFact identity and existing
# disjoint next-version carriers.  No source name, workload, state count, or
# benchmark shape participates.

# rdi=expression -> eax=resident BOOL PredicateFact index, or -1.
g_phys_top_select_guard_index:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    mov eax,-1
    test r12,r12; jz .gptsgi_done
    cmp qword ptr [r12],J_OBJECT; jne .gptsgi_done
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gptsgi_done
    mov r13,rax
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gptsgi_none
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gptsgi_none
    mov rbx,[rax+24]; test rbx,rbx; jz .gptsgi_none
    mov r14,[rbx+32]; test r14,r14; jz .gptsgi_none
    mov rax,[r14+32]; test rax,rax; jz .gptsgi_none
    cmp qword ptr [rax+32],0; jne .gptsgi_none
    mov rdi,rbx; call g_semantic_expr_is_total
    test eax,eax; jz .gptsgi_none
    xor r14d,r14d
.gptsgi_scan_selected:
    cmp r14d,dword ptr [rip+g_phys_cse_resident_count]; jae .gptsgi_none
    mov rax,[rip+g_phys_cse_resident_type_ptr]
    cmp dword ptr [rax+r14*4],GTYPE_BOOL; jne .gptsgi_scan_next
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov rsi,[rax+r14*8]
    mov rdi,rbx; call g_phys_predicate_equal
    test eax,eax; jnz .gptsgi_found
.gptsgi_scan_next:
    inc r14d; jmp .gptsgi_scan_selected
.gptsgi_found:
    mov eax,r14d
    jmp .gptsgi_done
.gptsgi_none:
    mov eax,-1
.gptsgi_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=top-level select expression, esi=1 true arm / 0 false arm -> rax arm or 0.
g_phys_select_arm:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    test r12,r12; jz .gpsa_done
    cmp qword ptr [r12],J_OBJECT; jne .gpsa_done
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpsa_done
    mov r14,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jz .gpsa_none
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpsa_none
    mov rbx,[rax+24]; test rbx,rbx; jz .gpsa_none
    mov r14,[rbx+32]; test r14,r14; jz .gpsa_none
    mov rax,[r14+32]; test rax,rax; jz .gpsa_none
    cmp qword ptr [rax+32],0; jne .gpsa_none
    test r13d,r13d
    mov rax,r14
    jnz .gpsa_done
    mov rax,[r14+32]
    jmp .gpsa_done
.gpsa_none:
    xor eax,eax
.gpsa_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expression, esi=semantic state index -> eax=1 iff expression is exactly
# that StateFact leaf. This is a physical zero-work proof: x'=x needs neither
# a next carrier write nor a commit on that guarded arm. No algebraic rewrite,
# source name matcher, or workload identity participates.
g_phys_expr_is_exact_state:
    push rbx; push r12
    mov rbx,rdi; mov r12d,esi
    xor eax,eax
    test rbx,rbx; jz .gpeies_done
    cmp qword ptr [rbx],J_OBJECT; jne .gpeies_done
    mov rdi,rbx; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpeies_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpeies_no
    cmp dword ptr [rax+24],r12d; sete al; movzx eax,al
    jmp .gpeies_done
.gpeies_no:
    xor eax,eax
.gpeies_done:
    pop r12; pop rbx; ret

# Build one compile-time guard identity per state. Only states with an already
# assigned disjoint next carrier can enter a Region; spilled/transient states
# continue through the same scalar Physical-DAG emitter. Singleton guards are
# erased because there is no control relation to fuse.
g_phys_build_guard_regions:
    push rbx; push r12; push r13; push r14; push r15
    xor ebx,ebx
.gpbgr_zero_uses:
    cmp ebx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpbgr_state_start
    mov rax,[rip+g_phys_guard_region_uses_ptr]; mov dword ptr [rax+rbx*4],0
    inc ebx; jmp .gpbgr_zero_uses
.gpbgr_state_start:
    xor ebx,ebx
.gpbgr_state_loop:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gpbgr_filter_start
    mov rax,[rip+g_phys_state_guard_ptr]; mov dword ptr [rax+rbx*4],-1
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gpbgr_not_counter
    cmp ebx,dword ptr [rip+g_reg_iter_counter_index]; je .gpbgr_state_next
.gpbgr_not_counter:
    mov rax,[rip+g_reg_iter_out_reg_ptr]; cmp dword ptr [rax+rbx*4],0; jl .gpbgr_state_next
    # This frontier executes before ordinary updates. Only a disjoint next
    # authority may enter it; an aged old carrier must wait for its real last
    # consumer in the common update sequence.
    mov edx,[rax+rbx*4]
    mov rax,[rip+g_reg_iter_old_reg_ptr]
    cmp edx,[rax+rbx*4]; je .gpbgr_state_next
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    call obj_get
    test rax,rax; jz .gpbgr_state_next
    mov rdi,rax; call g_phys_top_select_guard_index
    cmp eax,0; jl .gpbgr_state_next
    mov r12d,eax
    mov rdx,[rip+g_phys_state_guard_ptr]; mov dword ptr [rdx+rbx*4],r12d
    mov rdx,[rip+g_phys_guard_region_uses_ptr]; inc dword ptr [rdx+r12*4]
.gpbgr_state_next:
    inc ebx; jmp .gpbgr_state_loop
.gpbgr_filter_start:
    xor ebx,ebx
.gpbgr_filter_loop:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gpbgr_done
    mov rax,[rip+g_phys_state_guard_ptr]; mov r12d,dword ptr [rax+rbx*4]
    cmp r12d,0; jl .gpbgr_filter_next
    mov rdx,[rip+g_phys_guard_region_uses_ptr]
    cmp dword ptr [rdx+r12*4],2; jae .gpbgr_filter_next
    mov dword ptr [rax+rbx*4],-1
.gpbgr_filter_next:
    inc ebx; jmp .gpbgr_filter_loop
.gpbgr_done:
    xor eax,eax
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# edi=state index, esi=1 true arm / 0 false arm -> eax=0 success / 1 failure.
# Region members always own a disjoint next carrier, so old authorities remain
# immutable until the common commit boundary regardless of region scheduling.
g_emit_phys_guard_arm_state:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov ebx,edi; mov r12d,esi
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gepga_bad
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov r14d,dword ptr [r11+16]
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov r13d,dword ptr [rdx+rbx*4]
    cmp r13d,0; jl .gepga_bad
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    call obj_get
    test rax,rax; jz .gepga_bad
    mov rdi,rax; mov esi,r12d; call g_phys_select_arm
    test rax,rax; jz .gepga_bad
    mov r15,rax
    mov rdi,r15; mov esi,ebx; call g_phys_expr_is_exact_state
    test eax,eax; jnz .gepga_identity
    call g_phys_temp_reset
    cmp r14d,GTYPE_F64; je .gepga_fp
    cmp r14d,GTYPE_F32; je .gepga_fp
    cmp r14d,GTYPE_BOOL; je .gepga_int
    cmp r14d,GTYPE_U64; je .gepga_int
    cmp r14d,GTYPE_I64; jne .gepga_bad
.gepga_int:
    mov rdi,r15; mov esi,r13d; mov edx,r14d; call g_emit_phys_gpr_value_to
    cmp eax,r14d; jne .gepga_bad
    xor eax,eax; jmp .gepga_done
.gepga_fp:
    mov rdi,r15; mov esi,r13d; mov edx,r14d; call g_emit_phys_fp_value_to
    cmp eax,r14d; jne .gepga_bad
    xor eax,eax; jmp .gepga_done
.gepga_identity:
    xor eax,eax; jmp .gepga_done
.gepga_bad:
    mov eax,1
.gepga_done:
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# A complete conditional transition may commit inside its selected arm once
# every old-value consumer has finished. Otherwise the same phase emitter keeps
# the common commit frontier. No update count or workload controls this proof.
# edi=guard -> eax=1 iff all live non-axis updates belong to this guard.
g_phys_guard_covers_transition:
    mov r8d,edi
    xor ecx,ecx
.gpgct_scan:
    cmp ecx,[rip+g_reg_iter_total]; jae .gpgct_yes
    mov eax,ecx; shl rax,5; add rax,[rip+g_states_ptr]
    cmp dword ptr [rax+28],-1; je .gpgct_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gpgct_member
    cmp ecx,[rip+g_reg_iter_counter_index]; je .gpgct_next
.gpgct_member:
    mov rax,[rip+g_phys_state_guard_ptr]
    cmp [rax+rcx*4],r8d; jne .gpgct_no
.gpgct_next: inc ecx; jmp .gpgct_scan
.gpgct_yes: mov eax,1; ret
.gpgct_no: xor eax,eax; ret

# edi=guard -> eax=1 when its complete false continuation is an absorbing
# state relation. The existing Region cover proof is supplied by the caller.
# Exact counted completion owns the final bound. Every live data state must be
# its own exact old authority on this edge, and the total predicate must not
# consume the changing ordinal. No dynamic convergence test or runtime flag is
# introduced: the existing false continuation simply joins loop completion.
g_phys_guard_false_is_fixed:
    push rbx; push r12; push r13
    mov r12d,edi
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gpgfif_no
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov r13,[rax+r12*8]
    mov rdi,r13; call g_semantic_expr_is_total
    test eax,eax; jz .gpgfif_no
    mov rdi,r13; mov esi,[rip+g_reg_iter_counter_index]
    call g_expr_uses_semantic_state
    test eax,eax; jnz .gpgfif_no
    xor ebx,ebx
.gpgfif_state:
    cmp ebx,[rip+g_reg_iter_total]; jae .gpgfif_yes
    cmp ebx,[rip+g_reg_iter_counter_index]; je .gpgfif_next
    mov eax,ebx; shl rax,5; add rax,[rip+g_states_ptr]
    cmp dword ptr [rax+28],-1; je .gpgfif_next
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[rax]; mov edx,[rax+8]
    call obj_get
    test rax,rax; jz .gpgfif_no
    mov rdi,rax; xor esi,esi; call g_phys_select_arm
    test rax,rax; jz .gpgfif_no
    mov rdi,rax; mov esi,ebx; call g_phys_expr_is_exact_state
    test eax,eax; jz .gpgfif_no
.gpgfif_next: inc ebx; jmp .gpgfif_state
.gpgfif_yes: mov eax,1; jmp .gpgfif_done
.gpgfif_no: xor eax,eax
.gpgfif_done: pop r13; pop r12; pop rbx; ret

# edi=guard, esi=arm, edx/ecx=first/last phase. One parameterized consumer
# emits all producers before any transfer, preserving simultaneous semantics.
g_emit_phys_guard_phase_arm:
    push rbx; push r12; push r13; push r14; push r15
    mov r12d,edi; mov r13d,esi; mov r14d,edx; mov r15d,ecx
.gepgpa_phase:
    xor ebx,ebx
.gepgpa_state:
    cmp ebx,[rip+g_reg_iter_total]; jae .gepgpa_next_phase
    mov rax,[rip+g_phys_state_guard_ptr]
    cmp [rax+rbx*4],r12d; jne .gepgpa_next_state
    mov edi,ebx; mov esi,r13d
    lea rax,[rip+g_phys_guard_phase_emitters]
    call qword ptr [rax+r14*8]
    test eax,eax; jnz .gepgpa_bad
.gepgpa_next_state: inc ebx; jmp .gepgpa_state
.gepgpa_next_phase:
    inc r14d; cmp r14d,r15d; jbe .gepgpa_phase
    xor eax,eax; jmp .gepgpa_done
.gepgpa_bad: mov eax,1
.gepgpa_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret
.pushsection .rodata
.p2align 3
g_phys_guard_phase_emitters:
    .quad g_emit_phys_guard_arm_state,g_emit_phys_guard_commit_state
.popsection

# rdi=expression, rsi=PredicateFact -> eax=1 if any value subtree consumes it.
# This demand walk includes lazy arms; it is not a runtime
# test or a source-pattern rewrite. Predicate identity remains the existing one.
g_phys_expr_contains_predicate:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi
    test r12,r12; jz .gpecp_no
    cmp qword ptr [r12],J_OBJECT; jne .gpecp_no
    mov rdi,r12; call g_infer_expr
    cmp eax,GTYPE_BOOL; jne .gpecp_args
    mov rdi,r12; mov rsi,r13; call g_phys_predicate_equal
    test eax,eax; jnz .gpecp_yes
.gpecp_args:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpecp_no
    mov r14,[rax+24]
.gpecp_child:
    test r14,r14; jz .gpecp_no
    mov rdi,r14; mov rsi,r13; call g_phys_expr_contains_predicate
    test eax,eax; jnz .gpecp_yes
    mov r14,[r14+32]; jmp .gpecp_child
.gpecp_yes: mov eax,1; jmp .gpecp_done
.gpecp_no: xor eax,eax
.gpecp_done: pop r14; pop r13; pop r12; pop rbx; ret

# A complete guarded transition has one current-generation control consumer.
# Retire its numeric carrier only when neither arm, the loop condition, nor
# another selected fact demands that value. Partial transitions retain their
# carrier because their second transfer frontier can outlive old-state reuse.
# The existing carrier slot records absence as -1; no parallel fact table,
# predicate ABI or alternate transition emitter is introduced.
g_phys_retire_control_materializations:
    push rbx; push r12; push r13; push r14; push r15
    xor ebx,ebx
.gprcm_fact:
    cmp ebx,[rip+g_phys_cse_resident_count]; jae .gprcm_done
    mov rax,[rip+g_phys_cse_resident_type_ptr]
    cmp dword ptr [rax+rbx*4],GTYPE_BOOL; jne .gprcm_next
    mov rax,[rip+g_phys_cse_resident_frontier_ptr]
    cmp dword ptr [rax+rbx*4],0; jne .gprcm_next
    mov rax,[rip+g_phys_guard_region_uses_ptr]
    cmp dword ptr [rax+rbx*4],2; jb .gprcm_next
    mov edi,ebx; call g_phys_guard_covers_transition
    test eax,eax; jz .gprcm_next
    mov rax,[rip+g_phys_cse_resident_expr_ptr]; mov r12,[rax+rbx*8]
    mov rdi,[rip+g_reg_iter_cond_expr]; mov rsi,r12
    call g_phys_expr_contains_predicate
    test eax,eax; jnz .gprcm_next
    xor r13d,r13d
.gprcm_parent:
    cmp r13d,[rip+g_phys_cse_resident_count]; jae .gprcm_states
    cmp r13d,ebx; je .gprcm_parent_next
    mov rax,[rip+g_phys_cse_resident_expr_ptr]
    mov rdi,[rax+r13*8]; mov rsi,r12; call g_phys_expr_contains_predicate
    test eax,eax; jnz .gprcm_next
.gprcm_parent_next: inc r13d; jmp .gprcm_parent
.gprcm_states:
    xor r13d,r13d
.gprcm_state:
    cmp r13d,[rip+g_reg_iter_total]; jae .gprcm_retire
    mov eax,r13d; shl rax,5; add rax,[rip+g_states_ptr]
    cmp dword ptr [rax+28],-1; je .gprcm_state_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gprcm_update
    cmp r13d,[rip+g_reg_iter_counter_index]; je .gprcm_state_next
.gprcm_update:
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[rax]; mov edx,[rax+8]
    call obj_get; mov r14,rax
    # The complete-region proof owns each top-level select condition. Its two
    # arms must have no numeric or nested-control demand for this same fact.
    mov rdi,r14; mov esi,1; call g_phys_select_arm
    test rax,rax; jz .gprcm_next
    mov rdi,rax; mov rsi,r12; call g_phys_expr_contains_predicate
    test eax,eax; jnz .gprcm_next
    mov rdi,r14; xor esi,esi; call g_phys_select_arm
    test rax,rax; jz .gprcm_next
    mov rdi,rax; mov rsi,r12; call g_phys_expr_contains_predicate
    test eax,eax; jnz .gprcm_next
.gprcm_state_next: inc r13d; jmp .gprcm_state
.gprcm_retire:
    mov rax,[rip+g_phys_cse_resident_reg_ptr]
    mov dword ptr [rax+rbx*4],-1
.gprcm_next: inc ebx; jmp .gprcm_fact
.gprcm_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# edi=0 producers / 1 pending transfers. The existing signed use marker owns
# readiness; zero retires a complete in-arm transition from the later frontier.
g_emit_phys_guard_regions:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,24
    mov [rsp],edi
    xor ebx,ebx
.gepgr_outer:
    cmp ebx,[rip+g_reg_iter_total]; jae .gepgr_ok
    mov rax,[rip+g_phys_state_guard_ptr]; mov r12d,[rax+rbx*4]
    test r12d,r12d; js .gepgr_next
    mov rdx,[rip+g_phys_guard_region_uses_ptr]; mov eax,[rdx+r12*4]
    cmp dword ptr [rsp],0; je .gepgr_producers
    neg eax; test eax,eax; jle .gepgr_next
    mov [rdx+r12*4],eax
    mov dword ptr [rsp+8],1; mov dword ptr [rsp+12],1
    jmp .gepgr_emit
.gepgr_producers:
    test eax,eax; jle .gepgr_next
    neg eax; mov [rdx+r12*4],eax
    mov dword ptr [rsp+8],0; mov dword ptr [rsp+12],0
    mov edi,r12d; call g_phys_guard_covers_transition
    test eax,eax; jz .gepgr_emit
    mov dword ptr [rsp+12],1
    mov rdx,[rip+g_phys_guard_region_uses_ptr]
    mov dword ptr [rdx+r12*4],0
.gepgr_emit:
    mov dword ptr [rsp+4],0
    cmp dword ptr [rsp],0; jne .gepgr_condition
    cmp dword ptr [rsp+12],1; jne .gepgr_condition
    mov edi,r12d; call g_phys_guard_false_is_fixed
    mov [rsp+4],eax
.gepgr_condition:
    mov edi,r12d; call g_emit_phys_resident_bool_jz_index
    test rax,rax; jz .gepgr_bad
    mov r13,rax
    cmp dword ptr [rsp+4],0; je .gepgr_true_arm
    lea rdi,[rip+g_reg_iter_exit_chain]; mov rsi,r13; call g_phys_chain_append
.gepgr_true_arm:
    mov edi,r12d; mov esi,1; mov edx,[rsp+8]; mov ecx,[rsp+12]
    call g_emit_phys_guard_phase_arm
    test eax,eax; jnz .gepgr_bad
    cmp dword ptr [rsp+4],0; jne .gepgr_next
    call g_emit_jmp_patch
    test rax,rax; jz .gepgr_bad
    mov r14,rax
    # Keep the complete false continuation unresolved until its arm's final
    # span is known. A lazy predicate may own more than one false edge.
    mov edi,r12d; xor esi,esi; mov edx,[rsp+8]; mov ecx,[rsp+12]
    call g_emit_phys_guard_phase_arm
    test eax,eax; jnz .gepgr_bad
    G_EMIT_POSITION rsi
    lea rax,[r14+4]; cmp rsi,rax; jne .gepgr_false_work
    # An empty false arm owns no bytes. Its true-to-end jump has no execution
    # demand either; erase it before publishing the same false-edge target.
    lea rsi,[r14-1]; mov [rip+g_emit_ptr],rsi
    mov rdi,r13; call g_phys_patch_chain
    jmp .gepgr_next
.gepgr_false_work:
    mov [rsp+16],rsi
    lea rsi,[r14+4]; mov rdi,r13; call g_phys_patch_chain
    mov rsi,[rsp+16]; mov rdi,r14; call g_patch_rel32
.gepgr_next: inc ebx; jmp .gepgr_outer
.gepgr_ok: xor eax,eax; jmp .gepgr_done
.gepgr_bad: mov eax,1
.gepgr_done:
    add rsp,24
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# edi=state index, esi=1 true arm / 0 false arm -> eax=0 success / 1 failure.
# Commit is emitted only for an arm whose selected next expression is not the
# exact old StateFact. All expression regions have already been emitted before
# this runs, preserving simultaneous-generation semantics.
g_emit_phys_guard_commit_state:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12d,esi
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gepgcs_bad
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov r14d,dword ptr [r11+16]
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov r13d,dword ptr [rdx+rbx*4]
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov r15d,dword ptr [rdx+rbx*4]
    cmp r15d,0; jl .gepgcs_bad

    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    call obj_get
    test rax,rax; jz .gepgcs_bad
    mov rdi,rax; mov esi,r12d; call g_phys_select_arm
    test rax,rax; jz .gepgcs_bad
    mov rdi,rax; mov esi,ebx; call g_phys_expr_is_exact_state
    test eax,eax; jnz .gepgcs_ok

    cmp r14d,GTYPE_F64; je .gepgcs_fp
    cmp r14d,GTYPE_F32; je .gepgcs_fp
    cmp r14d,GTYPE_BOOL; je .gepgcs_int
    cmp r14d,GTYPE_U64; je .gepgcs_int
    cmp r14d,GTYPE_I64; jne .gepgcs_bad
.gepgcs_int:
    cmp r13d,0; jl .gepgcs_int_mem
    mov edi,r13d; mov esi,r15d; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepgcs_bad
    jmp .gepgcs_ok
.gepgcs_int_mem:
    xor edi,edi; mov esi,r15d; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepgcs_bad
    mov eax,ebx; call g_state_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .gepgcs_bad
    jmp .gepgcs_ok
.gepgcs_fp:
    cmp r13d,0; jl .gepgcs_fp_mem
    mov edi,r13d; mov esi,r15d; mov edx,r14d; call g_emit_phys_xmm_move
    test eax,eax; jnz .gepgcs_bad
    jmp .gepgcs_ok
.gepgcs_fp_mem:
    mov edi,r15d; mov esi,r14d; call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gepgcs_bad
    mov eax,ebx; call g_state_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .gepgcs_bad
.gepgcs_ok:
    xor eax,eax; jmp .gepgcs_done
.gepgcs_bad:
    mov eax,1
.gepgcs_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- unified transition Physical Reality ----------------
# 1.3.20 removes the historical 2-state xadd and 3-state shift/add private
# transition emitters.  Every recurrence shape now enters the same Rank-N
# causal register-DAG / Physical Reality lowering.  Algebraic elimination may
# still occur through generic ValueFact proofs, never through state-count shape
# dispatch.

# ---------------- causal-state register recurrence optimizer ----------------
# 1.3.13: source variables do not automatically own persistent physical state.
# Causal scalar state is now a Rank-N Physical Reality episode. Profitable
# ValueFacts remain resident in target carriers; excess facts stay in their
# execution-local StateFact frame while the same register-native DAG continues.
# A proven counted control is independent Axis authority in RBX. No duplicate
# stack-compatible recurrence backend is retained.

# rdi=symbol -> eax=1 emitted, 0 no match/rollback.
g_try_emit_reg_iterate:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    mov [rip+g_reg_iter_symbol],rbx
    G_EMIT_POSITION rax; mov [rip+g_reg_iter_emit_start],rax
    mov r12,[rbx+32]
    mov dword ptr [rip+g_state_count],0
    mov dword ptr [rip+g_reg_iter_total],0
    mov rdi,r12; lea rsi,[rip+gk_states]; mov edx,gk_states_end-gk_states; call obj_get
    test rax,rax; jz .gtri_no
    cmp qword ptr [rax],J_ARRAY; jne .gtri_no
    mov r13,[rax+24]; test r13,r13; jz .gtri_no
    xor r14d,r14d
.gtri_decl_scan:
    test r13,r13; jz .gtri_decl_done
    cmp r14d,dword ptr [rip+g_state_capacity]; jae .gtri_no
    mov rdi,r13; call g_state_decl_type; test eax,eax; jz .gtri_no
    mov r10d,eax
    mov rdi,r13; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .gtri_no
    mov r15,rax
    mov eax,r14d; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rax,[r15+8]; mov [r11],rax
    mov rax,[r15+16]; mov [r11+8],rax
    mov dword ptr [r11+16],r10d
    mov dword ptr [r11+20],-1
    mov dword ptr [r11+24],r14d
    mov dword ptr [r11+28],-1       # recurrence causal slice: -1 dead, -2 live, >=0 dense lane
    mov rax,[rip+g_reg_iter_decls_ptr]; mov [rax+r14*8],r13
    inc r14d
    mov r13,[r13+32]; jmp .gtri_decl_scan
.gtri_decl_done:
    test r14d,r14d; jz .gtri_no
    mov dword ptr [rip+g_reg_iter_total],r14d
    mov rdi,r12; lea rsi,[rip+gk_update]; mov edx,gk_update_end-gk_update; call obj_get
    test rax,rax; jz .gtri_no
    mov [rip+g_reg_iter_update_obj],rax
    xor ecx,ecx
.gtri_update_verify:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_struct_ok
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_no
    inc ecx; jmp .gtri_update_verify
.gtri_struct_ok:
    mov rdi,r12; lea rsi,[rip+gk_max_iterations]; mov edx,gk_max_iterations_end-gk_max_iterations; call obj_get
    test rax,rax; jz .gtri_no
    mov [rip+g_reg_iter_max_expr],rax
    mov rdi,r12; lea rsi,[rip+gk_condition]; mov edx,gk_condition_end-gk_condition; call obj_get
    test rax,rax; jz .gtri_no
    mov [rip+g_reg_iter_cond_expr],rax
    mov rdi,r12; lea rsi,[rip+gk_result]; mov edx,gk_result_end-gk_result; call obj_get
    test rax,rax; jz .gtri_no
    cmp qword ptr [rax],J_STRING; jne .gtri_no
    mov [rip+g_reg_iter_result_name_node],rax

    mov eax,[rip+g_reg_iter_total]; mov [rip+g_state_count],eax
    # Prove common counted-loop form independently of the value update.
    mov dword ptr [rip+g_reg_iter_counted],0
    xor ecx,ecx
.gtri_counted_probe:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_counted_probe_done
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_cond_expr]; mov rsi,[r11]; mov rdx,[r11+8]
    push rcx; call g_match_counter_bound; pop rcx
    test eax,eax; jz .gtri_counted_probe_next
    mov [rip+g_counted_proof_kind],eax
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+16],GTYPE_U64; jne .gtri_counted_probe_next
    mov rax,[rip+g_reg_iter_decls_ptr]; mov r13,[rax+rcx*8]
    mov rdi,r13; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_counted_probe_next
    push rcx; mov rdi,rax; call g_expr_u64_literal; pop rcx
    test edx,edx; jnz .gtri_counted_probe_next
    test rax,rax; jnz .gtri_counted_probe_next
    push rcx; mov rdi,[rip+g_counted_bound_expr]; mov rsi,[rip+g_reg_iter_max_expr]; call g_expr_same_bound; pop rcx
    test eax,eax; jz .gtri_counted_probe_next
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_counted_probe_next
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    mov rdi,rax; mov rsi,[r11]; mov rdx,[r11+8]
    push rcx; call g_match_counter_inc; pop rcx
    test eax,eax; jz .gtri_counted_probe_next
    mov eax,[rip+g_counted_proof_kind]
    mov dword ptr [rip+g_reg_iter_counted],eax
    mov dword ptr [rip+g_reg_iter_counter_index],ecx
    mov rax,[rip+g_counted_bound_expr]; mov [rip+g_reg_iter_bound_expr],rax
    jmp .gtri_counted_probe_done
.gtri_counted_probe_next:
    inc ecx; jmp .gtri_counted_probe
.gtri_counted_probe_done:
    # The published StateFact and the loop-control relation own one causal
    # backward slice for every recurrence realization.  Dead semantic states
    # never enter carrier assignment, episode CSE, guards, or timestep updates.
    # states[+28]: -1 dead, -2 live, >=0 temporary dense Rank-N lane.
    mov eax,dword ptr [rip+g_reg_iter_total]
    mov dword ptr [rip+g_state_count],eax
    call g_build_iterate_live_slice
    test eax,eax; jnz .gtri_no

    # 1.3.15: semantic data role is no longer a physical register identity.
    # Any finite represented state set enters the
    # same causal Physical Reality episode.  The counted induction fact is an
    # Axis authority, not persistent model state, and therefore receives no
    # data role.  Physical carrier pressure is handled separately below.
    mov dword ptr [rip+g_reg_iter_data_count],0
    xor ecx,ecx
.gtri_role_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_role_done
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; jne .gtri_role_live
    mov dword ptr [r11+20],-1
    jmp .gtri_role_next
.gtri_role_live:
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gtri_role_data
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; jne .gtri_role_data
    mov dword ptr [r11+20],-1
    jmp .gtri_role_next
.gtri_role_data:
    mov eax,dword ptr [rip+g_reg_iter_data_count]
    mov dword ptr [r11+20],eax
    inc dword ptr [rip+g_reg_iter_data_count]
.gtri_role_next:
    inc ecx; jmp .gtri_role_loop
.gtri_role_done:
    # The semantic state vector is now complete. Expose its exact cardinality to
    # generic state-identity helpers before any Physical Reality proof consumes it.
    mov eax,dword ptr [rip+g_reg_iter_total]
    mov dword ptr [rip+g_state_count],eax

    # 1.3.67: transition-power reduction is the Rank-N affine closure of the
    # same counted Physical Reality episode.  The published ValueFact grows its
    # exact backward state slice; if the simultaneous wrap-u64 relation proves
    # x'=A*x+b, the causal chain is represented as F^N.  Scalar affine power is
    # only the one-lane degeneration.  Unrelated semantic states, including
    # non-affine ones, create no physical work for this published result.
    mov rdi,rbx
    call g_try_emit_transition_power_slice
    test eax,eax
    jnz .gtri_done

    mov dword ptr [rip+g_phys_const_pool_ready],0
    call g_phys_assign_state_carriers
    test eax,eax; jnz .gtri_no

    # Speculative AOT physicalization proof. Emit each next-state
    # expression into the code buffer, verify its type, then rewind the buffer.
    # This is a compile-time proof probe only: no runtime graph walker exists.
    mov dword ptr [rip+g_phys_const_candidate_count],0
    mov dword ptr [rip+g_phys_const_resident_count],0
    mov dword ptr [rip+g_phys_cse_candidate_count],0
    mov dword ptr [rip+g_phys_cse_resident_count],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov dword ptr [rip+g_phys_fp_temp_peak],0
    mov dword ptr [rip+g_phys_fp_temp_live],0
    mov dword ptr [rip+g_phys_int_temp_peak],0
    mov dword ptr [rip+g_phys_int_temp_live],0
    mov dword ptr [rip+g_phys_fp_temp_exhausted],0
    mov dword ptr [rip+g_phys_const_collect],1
    G_EMIT_POSITION rax; mov [rip+g_reg_native_probe_start],rax
    mov eax,dword ptr [rip+g_reg_iter_total]; mov dword ptr [rip+g_state_count],eax
    xor ecx,ecx
.gtri_native_probe_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_native_probe_done
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gtri_native_probe_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gtri_native_probe_real
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; je .gtri_native_probe_next
.gtri_native_probe_real:
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_native_probe_fail
    # Scalar FP enters the same lifetime-driven Physical Reality discipline as
    # Tensor: resident leaves are consumed in place and temporary carriers are
    # allocated from future-use lifetime, not expression depth. Integer wrap
    # arithmetic keeps the mature register-DAG path.
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    mov edx,dword ptr [r11+16]
    # One compile-time ValueFact walk spans every state root. Integer roots are
    # still emitted only by the authoritative pass, but their repeated BOOL/FP
    # children participate in the same episode CSE instead of a second graph.
    push rcx; push rax
    mov rdi,rax; mov esi,edx; call g_phys_cse_note_tree
    call g_phys_temp_reset
    pop rax; pop rcx
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    mov edx,dword ptr [r11+16]
    cmp edx,GTYPE_F64; je .gtri_native_probe_fp
    cmp edx,GTYPE_F32; je .gtri_native_probe_fp
    cmp edx,GTYPE_BOOL; je .gtri_native_probe_int
    cmp edx,GTYPE_U64; je .gtri_native_probe_int
    cmp edx,GTYPE_I64; je .gtri_native_probe_int
    jmp .gtri_native_probe_fail
.gtri_native_probe_int:
    # Integer roots participate in this same single physical profile pass. This
    # measures real anonymous GPR pressure for shared-ValueFact admission; it is
    # not a second integer backend or a workload/state-count admission branch.
    push rcx; push rax
    mov ecx,dword ptr [rsp+8]
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov eax,dword ptr [rdx+rcx*4]
    mov dword ptr [rip+g_phys_probe_temp],0
    cmp eax,0; jge .gtri_native_probe_int_dest
    call g_phys_int_temp_alloc
    cmp eax,0; jl .gtri_native_probe_int_fail
    mov dword ptr [rip+g_phys_probe_temp],1
.gtri_native_probe_int_dest:
    mov ecx,dword ptr [rsp+8]
    mov dword ptr [rip+g_phys_probe_dest],eax
    mov esi,eax
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edx,dword ptr [r11+16]
    pop rdi
    call g_emit_phys_gpr_value_to
    push rax
    cmp dword ptr [rip+g_phys_probe_temp],1; jne .gtri_native_probe_int_done
    mov edi,dword ptr [rip+g_phys_probe_dest]; call g_phys_int_temp_free
.gtri_native_probe_int_done:
    pop rax; pop rcx
    jmp .gtri_native_probe_typecheck
.gtri_native_probe_int_fail:
    pop rax; pop rcx
    jmp .gtri_native_probe_fail
.gtri_native_probe_fp:
    push rcx; push rax
    mov ecx,dword ptr [rsp+8]
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov eax,dword ptr [rdx+rcx*4]
    mov dword ptr [rip+g_phys_probe_temp],0
    cmp eax,0; jge .gtri_native_probe_fp_dest
    call g_phys_fp_temp_alloc
    cmp eax,0; jl .gtri_native_probe_fp_fail
    mov dword ptr [rip+g_phys_probe_temp],1
.gtri_native_probe_fp_dest:
    mov ecx,dword ptr [rsp+8]
    mov dword ptr [rip+g_phys_probe_dest],eax
    mov esi,eax
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edx,dword ptr [r11+16]
    pop rdi
    call g_emit_phys_fp_expr_to
    cmp dword ptr [rip+g_phys_probe_temp],1; jne .gtri_native_probe_fp_done
    push rax; mov edi,dword ptr [rip+g_phys_probe_dest]; call g_phys_fp_temp_free; pop rax
.gtri_native_probe_fp_done:
    pop rcx
    jmp .gtri_native_probe_typecheck
.gtri_native_probe_fp_fail:
    pop rax; pop rcx
    jmp .gtri_native_probe_fail
.gtri_native_probe_typecheck:
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    cmp eax,dword ptr [r11+16]; jne .gtri_native_probe_fail
.gtri_native_probe_next:
    inc ecx; jmp .gtri_native_probe_loop
.gtri_native_probe_fail:
    mov rax,[rip+g_reg_native_probe_start]; mov [rip+g_emit_ptr],rax
    mov dword ptr [rip+g_phys_const_collect],0
    mov dword ptr [rip+g_state_count],0
.gtri_native_probe_semantic_fail:
    # Do not maintain a second stack-compatible recurrence backend here.
    jmp .gtri_no
.gtri_native_probe_done:
    cmp dword ptr [rip+g_reg_iter_counted],1; je .gtri_control_collected
    # Control collection may retain immutable inputs, but introduces no new
    # state-dependent producer into the update lifetime. The actual condition
    # sees only the already-materialized invariant prefix, never stale values.
    mov dword ptr [rip+g_phys_cse_conditional_visit],2
    mov rdi,[rip+g_reg_iter_cond_expr]; mov esi,GTYPE_BOOL; call g_phys_cse_note_tree
    mov dword ptr [rip+g_phys_cse_conditional_visit],0
.gtri_control_collected:
    call g_phys_temp_reset
    mov rdi,[rip+g_reg_iter_cond_expr]; call g_emit_phys_bool_jz_patch
    test rax,rax; jz .gtri_native_probe_fail
    mov rax,[rip+g_reg_native_probe_start]; mov [rip+g_emit_ptr],rax
    mov dword ptr [rip+g_phys_const_collect],0
    call g_phys_cse_finalize
    call g_phys_cse_order_dependencies
    # Repeated PredicateFacts with independent next carriers become one guarded
    # Physical Region before liveness/authority decisions. This is a projection
    # of the existing DAG, not a second control IR.
    # The selected shared subgraphs are now fixed. Derive the real old-state
    # last-consumer frontier, then age each FP next-StateFact into the smallest
    # carrier relation admitted by that liveness.
    call g_phys_order_state_updates
    test eax,eax; jnz .gtri_native_probe_semantic_fail
    call g_phys_finalize_fp_state_carriers
    test eax,eax; jnz .gtri_native_probe_semantic_fail
    call g_phys_const_finalize
    call g_phys_build_guard_regions
    test eax,eax; jnz .gtri_native_probe_semantic_fail
    call g_phys_retire_control_materializations
    call g_phys_prove_countdown_axis
    mov dword ptr [rip+g_reg_iter_countdown],eax
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov dword ptr [rip+g_phys_cse_control_ready_count],0
    mov dword ptr [rip+g_state_count],0

    mov dword ptr [rip+g_iter_reg_mode],1
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
    mov dword ptr [rip+g_state_count],0
    xor ecx,ecx
.gtri_init_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_init_done
    mov rax,[rip+g_reg_iter_decls_ptr]; mov r13,[rax+rcx*8]
    mov rdi,r13; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_rollback
    push rcx; mov rdi,rax; call g_emit_expr; pop rcx
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    cmp eax,dword ptr [r11+16]; jne .gtri_rollback
    call g_emit_pop_rax
    # Initialize according to the compile-time carrier map.  Nonresident facts
    # are kept in their existing state slot; this is partial residency, not a
    # rejection of the entire causal episode.
    mov rdx,[rip+g_reg_iter_carrier_kind_ptr]; mov eax,dword ptr [rdx+rcx*4]
    cmp eax,G_PHYS_CARRIER_COUNTER; je .gtri_init_counter
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov edi,dword ptr [rdx+rcx*4]
    cmp edi,0; jl .gtri_init_spill
    mov esi,dword ptr [r11+16]
    cmp eax,G_PHYS_CARRIER_FP; je .gtri_init_fp_resident
    cmp eax,G_PHYS_CARRIER_INT; jne .gtri_rollback
    xor esi,esi                         # runtime RAX source code
    push rcx; call g_emit_phys_gpr_move; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_init_committed
.gtri_init_fp_resident:
    push rcx; call g_emit_phys_xmm_from_rax; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_init_committed
.gtri_init_counter:
    mov edi,3; xor esi,esi              # RBX <- RAX
    push rcx; call g_emit_phys_gpr_move; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_init_committed
.gtri_init_spill:
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax
    push rcx; call g_emit_store_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
.gtri_init_committed:
    inc dword ptr [rip+g_state_count]
    inc ecx; jmp .gtri_init_loop
.gtri_init_done:
    call g_emit_phys_resident_constants
    test eax,eax; jnz .gtri_rollback
    call g_emit_phys_constant_pool
    test eax,eax; jnz .gtri_rollback
    cmp dword ptr [rip+g_reg_iter_counted],1; je .gtri_counted_setup
    # General lazy control can consume invocation facts itself. Its established
    # demand frontier precedes the condition; counted entry needs no such fact.
    call g_emit_phys_episode_invariants
    test eax,eax; jnz .gtri_rollback
    cmp dword ptr [rip+g_reg_iter_counted],0; jne .gtri_lazy_setup
    mov rdi,[rip+g_reg_iter_max_expr]; call g_emit_expr; cmp eax,GTYPE_U64; jne .gtri_rollback
    call g_emit_pop_rax
    lea rdi,[rip+gc_mov_rbp_rax]; mov esi,gc_mov_rbp_rax_end-gc_mov_rbp_rax; call g_emit_bytes
    lea rdi,[rip+gc_xor_rbx]; mov esi,gc_xor_rbx_end-gc_xor_rbx; call g_emit_bytes
.gtri_lazy_setup:
    # A bounded semantic ordinal already owns RBX. Retain the original lazy
    # condition; its true edge proves both increment safety and limit safety.
    G_EMIT_LOOP_POSITION r15,.gtri_rollback
    call g_emit_phys_episode_control
    test eax,eax; jnz .gtri_rollback
    call g_phys_temp_reset
    mov rdi,[rip+g_reg_iter_cond_expr]; call g_emit_phys_bool_jz_patch
    test rax,rax; jz .gtri_rollback
    mov r14,rax
    cmp dword ptr [rip+g_reg_iter_counted],0; jne .gtri_updates_start
    lea rdi,[rip+gc_iter_max_guard]; mov esi,gc_iter_max_guard_end-gc_iter_max_guard; call g_emit_bytes
    jmp .gtri_updates_start
.gtri_counted_setup:
    mov rdi,[rip+g_reg_iter_bound_expr]; call g_emit_expr; cmp eax,GTYPE_U64; jne .gtri_rollback
    call g_emit_pop_rax
    cmp dword ptr [rip+g_reg_iter_countdown],1; je .gtri_countdown_setup
    lea rdi,[rip+gc_mov_rbp_rax]; mov esi,gc_mov_rbp_rax_end-gc_mov_rbp_rax; call g_emit_bytes
    G_EMIT_POSITION r15
    lea rdi,[rip+gc_reg_iter_cmp_rbx_rbp]; mov esi,gc_reg_iter_cmp_rbx_rbp_end-gc_reg_iter_cmp_rbx_rbp; call g_emit_bytes
.gtri_counted_exit_patch:
    lea rdi,[rip+gc_jae_prefix]; mov esi,gc_jae_prefix_end-gc_jae_prefix; call g_emit_bytes
    G_EMIT_POSITION r14; xor edi,edi; call g_emit_u32
    jmp .gtri_counted_setup_done
.gtri_countdown_setup:
    lea rdi,[rip+gc_mov_rbp_rax]; mov esi,gc_mov_rbp_rax_end-gc_mov_rbp_rax; call g_emit_bytes
    lea rdi,[rip+gc_reg_iter_mov_rbx_rax]; mov esi,gc_reg_iter_mov_rbx_rax_end-gc_reg_iter_mov_rbx_rax; call g_emit_bytes
    G_EMIT_POSITION r15
    lea rdi,[rip+gc_reg_iter_test_rbx_rbx]; mov esi,gc_reg_iter_test_rbx_rbx_end-gc_reg_iter_test_rbx_rbx; call g_emit_bytes
    lea rdi,[rip+gc_je_prefix]; mov esi,gc_je_prefix_end-gc_je_prefix; call g_emit_bytes
    G_EMIT_POSITION r14; xor edi,edi; call g_emit_u32
.gtri_counted_setup_done:
    # A proved counted entry has no update demand at zero. Materialize the same
    # invocation prefix only on its true edge, before the steady-state backedge.
    call g_emit_phys_episode_invariants
    test eax,eax; jnz .gtri_rollback
    # Native transitions keep the initial zero-trip guard but make the steady
    # state backedge bottom-tested, eliminating the historical unconditional jmp.
    G_EMIT_LOOP_POSITION r15,.gtri_rollback
.gtri_updates_start:
    mov [rip+g_reg_iter_exit_chain],r14
    mov dword ptr [rip+g_phys_window_active],1
    mov dword ptr [rip+g_phys_window_count],0
    call g_emit_phys_episode_cse
    test eax,eax; jnz .gtri_rollback
    xor edi,edi
    call g_emit_phys_guard_regions
    test eax,eax; jnz .gtri_rollback
    mov dword ptr [rip+g_phys_update_position],0
.gtri_update_emit:
    mov eax,[rip+g_phys_update_position]
    cmp eax,dword ptr [rip+g_reg_iter_total]; jae .gtri_commit_regs
    mov rdx,[rip+g_phys_update_order_ptr]; mov ecx,[rdx+rax*4]
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gtri_update_skip_counter
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gtri_update_guard_check
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; je .gtri_update_skip_counter
.gtri_update_guard_check:
    mov rax,[rip+g_phys_state_guard_ptr]
    cmp dword ptr [rax+rcx*4],0; jge .gtri_update_skip_counter
.gtri_update_emit_real:
    mov rax,[rip+g_phys_update_expr_ptr]; mov rax,[rax+rcx*8]
    push rcx; push rax
    call g_phys_temp_reset
    mov ecx,dword ptr [rsp+8]
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    mov edx,dword ptr [r11+16]
    cmp edx,GTYPE_F64; je .gtri_update_emit_fp
    cmp edx,GTYPE_F32; je .gtri_update_emit_fp
    mov ecx,dword ptr [rsp+8]
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov eax,dword ptr [rdx+rcx*4]
    mov dword ptr [rip+g_phys_probe_temp],0
    cmp eax,0; jge .gtri_update_int_dest
    call g_phys_int_temp_alloc
    cmp eax,0; jl .gtri_update_int_fail
    mov dword ptr [rip+g_phys_probe_temp],1
.gtri_update_int_dest:
    mov ecx,dword ptr [rsp+8]
    mov dword ptr [rip+g_phys_probe_dest],eax
    mov esi,eax
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edx,dword ptr [r11+16]
    pop rdi
    call g_emit_phys_gpr_value_to
    push rax
    cmp dword ptr [rip+g_phys_probe_temp],1; jne .gtri_update_int_ready
    # Next-version spill: RAX receives the physical result bits only after the
    # expression has consumed all old-state facts, then the dedicated temp slot
    # carries the version boundary until commit.
    mov edi,0; mov esi,dword ptr [rip+g_phys_probe_dest]; call g_emit_phys_gpr_move
    test eax,eax; jnz .gtri_update_int_spill_fail
    mov ecx,dword ptr [rsp+8]
    mov eax,ecx; call g_state_temp_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .gtri_update_int_spill_fail
    mov edi,dword ptr [rip+g_phys_probe_dest]; call g_phys_int_temp_free
.gtri_update_int_ready:
    pop rax; pop rcx
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    cmp eax,dword ptr [r11+16]; jne .gtri_rollback
    jmp .gtri_update_skip_counter
.gtri_update_int_spill_fail:
    pop rax; pop rcx
    jmp .gtri_rollback
.gtri_update_int_fail:
    pop rax; pop rcx
    jmp .gtri_rollback
.gtri_update_emit_fp:
    mov ecx,dword ptr [rsp+8]
    mov dword ptr [rip+g_phys_probe_temp],0

    # Carrier identity was finalized once from post-CSE liveness. A nonnegative
    # output is the unique persistent destination (possibly the old carrier);
    # otherwise this next ValueFact is transient until the common commit.
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov eax,dword ptr [rdx+rcx*4]
    cmp eax,0; jge .gtri_update_fp_dest
    call g_phys_fp_temp_alloc
    cmp eax,0; jl .gtri_update_fp_fail
    mov dword ptr [rip+g_phys_probe_temp],1
.gtri_update_fp_dest:
    mov ecx,dword ptr [rsp+8]
    mov dword ptr [rip+g_phys_probe_dest],eax
    mov esi,eax
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edx,dword ptr [r11+16]
    pop rdi
    call g_emit_phys_fp_expr_to
    push rax
    cmp dword ptr [rip+g_phys_probe_temp],1; jne .gtri_update_fp_ready
    # The result currently owns an anonymous carrier. If this state's old
    # authority has reached its final real consumer, recycle that authority now
    # and keep the next version register-resident across the timestep boundary.
    # Otherwise preserve simultaneous-update semantics through the existing
    # execution-local next-version handoff. This decision is pure liveness, never state shape.
    mov ecx,dword ptr [rsp+8]
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov r12d,dword ptr [rdx+rcx*4]
    cmp r12d,0; jl .gtri_update_fp_transport_temp
    mov rdx,[rip+g_phys_state_last_use_ptr]; mov eax,dword ptr [rdx+rcx*4]
    cmp eax,[rip+g_phys_update_position]; jg .gtri_update_fp_transport_temp
    mov edi,r12d; mov esi,dword ptr [rip+g_phys_probe_dest]
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edx,dword ptr [r11+16]
    call g_emit_phys_xmm_move
    test eax,eax; jnz .gtri_update_fp_spill_fail
    # The output authority and old authority are now the same physical carrier.
    # Commit sees an identity move and emits no transport.
    mov ecx,dword ptr [rsp+8]
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rdx+rcx*4],r12d
    mov edi,dword ptr [rip+g_phys_probe_dest]; call g_phys_fp_temp_free
    jmp .gtri_update_fp_ready
.gtri_update_fp_transport_temp:
    mov ecx,dword ptr [rsp+8]
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edi,dword ptr [rip+g_phys_probe_dest]; mov esi,dword ptr [r11+16]
    mov eax,ecx; call g_state_temp_addr; mov rdx,rax
    call g_emit_phys_xmm_to_state_mem
    test eax,eax; jnz .gtri_update_fp_spill_fail
    mov edi,dword ptr [rip+g_phys_probe_dest]; call g_phys_fp_temp_free
.gtri_update_fp_ready:
    pop rax; pop rcx
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    cmp eax,dword ptr [r11+16]; jne .gtri_rollback
    jmp .gtri_update_skip_counter
.gtri_update_fp_spill_fail:
    pop rax; pop rcx
    jmp .gtri_rollback
.gtri_update_fp_fail:
    pop rax; pop rcx
    jmp .gtri_rollback
.gtri_update_skip_counter:
    inc dword ptr [rip+g_phys_update_position]; jmp .gtri_update_emit
.gtri_commit_regs:
    call g_phys_window_barrier
    mov dword ptr [rip+g_phys_window_active],0
    # The next generation lives in disjoint output carriers. Commit only after
    # every expression has consumed the old generation: true simultaneous state
    # transition without a stack, temp array, or overwrite hazard. Guarded
    # Regions transfer only changed authorities; exact identity arms are zero work.
    mov edi,1
    call g_emit_phys_guard_regions
    test eax,eax; jnz .gtri_rollback
    xor ecx,ecx
.gtri_native_commit_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_commit_after_data
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-1; je .gtri_native_commit_next
    mov rax,[rip+g_phys_state_guard_ptr]; cmp dword ptr [rax+rcx*4],0; jge .gtri_native_commit_next
    cmp dword ptr [rip+g_reg_iter_counted],0; je .gtri_native_commit_real
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; je .gtri_native_commit_next
.gtri_native_commit_real:
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov eax,dword ptr [rdx+rcx*4]; mov dword ptr [rip+g_phys_commit_old],eax
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov eax,dword ptr [rdx+rcx*4]; mov dword ptr [rip+g_phys_commit_out],eax
    mov eax,dword ptr [r11+16]; mov dword ptr [rip+g_phys_commit_type],eax
    cmp dword ptr [rip+g_phys_commit_out],0; jl .gtri_commit_from_temp
    # Next value is still resident in its output carrier.
    cmp dword ptr [rip+g_phys_commit_type],GTYPE_F64; je .gtri_commit_resident_fp
    cmp dword ptr [rip+g_phys_commit_type],GTYPE_F32; je .gtri_commit_resident_fp
    cmp dword ptr [rip+g_phys_commit_old],0; jl .gtri_commit_out_int_to_mem
    mov edi,dword ptr [rip+g_phys_commit_old]; mov esi,dword ptr [rip+g_phys_commit_out]; push rcx; call g_emit_phys_gpr_move; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_out_int_to_mem:
    mov edi,0; mov esi,dword ptr [rip+g_phys_commit_out]; push rcx; call g_emit_phys_gpr_move; pop rcx
    test eax,eax; jnz .gtri_rollback
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; push rcx; call g_emit_store_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_resident_fp:
    cmp dword ptr [rip+g_phys_commit_old],0; jl .gtri_commit_out_fp_to_mem
    mov edi,dword ptr [rip+g_phys_commit_old]; mov esi,dword ptr [rip+g_phys_commit_out]; mov edx,dword ptr [rip+g_phys_commit_type]; push rcx; call g_emit_phys_xmm_move; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_out_fp_to_mem:
    mov eax,ecx; call g_state_slot_addr; mov rdx,rax
    mov edi,dword ptr [rip+g_phys_commit_out]; mov esi,dword ptr [rip+g_phys_commit_type]; push rcx; call g_emit_phys_xmm_to_state_mem; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_from_temp:
    # The temp slot is already an AddressFact.  FP next-StateFacts move directly
    # between that address and their resident carrier; integers retain the GPR
    # form because RAX is their existing physical value authority.
    cmp dword ptr [rip+g_phys_commit_type],GTYPE_F64; je .gtri_commit_from_temp_fp
    cmp dword ptr [rip+g_phys_commit_type],GTYPE_F32; je .gtri_commit_from_temp_fp
    mov eax,ecx; call g_state_temp_addr; mov rdi,rax; push rcx; call g_emit_load_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
    cmp dword ptr [rip+g_phys_commit_old],0; jl .gtri_commit_temp_to_mem
    mov edi,dword ptr [rip+g_phys_commit_old]; xor esi,esi; push rcx; call g_emit_phys_gpr_move; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_from_temp_fp:
    cmp dword ptr [rip+g_phys_commit_old],0; jl .gtri_commit_temp_fp_to_mem
    mov eax,ecx; call g_state_temp_addr; mov rdx,rax
    mov edi,dword ptr [rip+g_phys_commit_old]; mov esi,dword ptr [rip+g_phys_commit_type]; push rcx; call g_emit_phys_xmm_from_state_mem; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_temp_fp_to_mem:
    mov eax,ecx; call g_state_temp_addr; mov rdi,rax; push rcx; call g_emit_load_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
.gtri_commit_temp_to_mem:
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; push rcx; call g_emit_store_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
.gtri_native_commit_next:
    inc ecx; jmp .gtri_native_commit_loop
.gtri_commit_after_data:
    # Canonicalize generic emitted machine sequences only after the complete
    # simultaneous transition has been formed. No semantic/source pattern owns
    # a separate emitter.
    mov rdi,r15; G_EMIT_POSITION rsi; call g_phys_machine_canonicalize
    cmp dword ptr [rip+g_reg_iter_countdown],1; je .gtri_countdown_backedge
    lea rdi,[rip+gc_inc_rbx]; mov esi,gc_inc_rbx_end-gc_inc_rbx; call g_emit_bytes
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gtri_back_edge
    # Bottom-tested steady-state backedge: one conditional branch, no
    # unconditional jump and no duplicate top comparison per iteration.
    lea rdi,[rip+gc_reg_iter_cmp_rbx_rbp]; mov esi,gc_reg_iter_cmp_rbx_rbp_end-gc_reg_iter_cmp_rbx_rbp; call g_emit_bytes
    mov esi,0x72
    jmp .gtri_counted_patch_backedge
.gtri_countdown_backedge:
    lea rdi,[rip+gc_reg_iter_dec_rbx]; mov esi,gc_reg_iter_dec_rbx_end-gc_reg_iter_dec_rbx; call g_emit_bytes
    mov esi,0x75
.gtri_counted_patch_backedge:
    mov rdi,r15; call g_emit_known_backedge
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_patch_exit
.gtri_back_edge:
    mov edi,0xE9; call g_emit_u8
    G_EMIT_POSITION rax; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; jbe 92f
    mov dword ptr [rip+g_code_overflow],1; jmp .gtri_rollback
92:
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
.gtri_patch_exit:
    G_EMIT_POSITION rax
    sub rax,r15
    imul rax,PRC_FRONTEND_BYTE_TICKS
    mov edx,0xffffffff; cmp rax,rdx; ja 987f
    mov [rip+g_current_loop_work_ticks],eax
987:
    G_EMIT_POSITION rsi; mov rdi,[rip+g_reg_iter_exit_chain]; call g_phys_patch_chain
    mov rax,[rip+g_reg_iter_result_name_node]
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state; test rax,rax; jz .gtri_rollback
    mov r11,rax
    mov ecx,dword ptr [r11+24]
    mov rdx,[rip+g_reg_iter_carrier_kind_ptr]; mov eax,dword ptr [rdx+rcx*4]
    cmp eax,G_PHYS_CARRIER_COUNTER; je .gtri_result_counter
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov edi,dword ptr [rdx+rcx*4]
    cmp edi,0; jl .gtri_result_spill
    mov esi,dword ptr [r11+16]
    cmp eax,G_PHYS_CARRIER_FP; je .gtri_result_fp_resident
    cmp eax,G_PHYS_CARRIER_INT; jne .gtri_rollback
    # Publication ABI consumes RAX; coalesce from the actual resident GPR.
    xchg edi,esi
    mov edi,0
    call g_emit_phys_gpr_move
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_store
.gtri_result_fp_resident:
    call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_store
.gtri_result_counter:
    call g_emit_phys_final_counter
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_store
.gtri_result_spill:
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    test eax,eax; jnz .gtri_rollback
.gtri_store:
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .gtri_rollback
    mov rdi,rbx; call g_emit_reg_iter_projection_stores
    test eax,eax; jnz .gtri_rollback
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
    mov eax,1; jmp .gtri_done
.gtri_rollback:
    mov dword ptr [rip+g_current_loop_work_ticks],0
    mov dword ptr [rip+g_phys_window_active],0
    mov dword ptr [rip+g_phys_window_count],0
    mov rax,[rip+g_reg_iter_emit_start]; mov [rip+g_emit_ptr],rax
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
.gtri_no: xor eax,eax
.gtri_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# The final ordinal of a proved zero-based exact counted loop is its bound,
# including the zero-trip edge. Both publication paths consume this authority.
g_emit_phys_final_counter:
    xor edi,edi; mov esi,3
    cmp dword ptr [rip+g_reg_iter_counted],1; jne 1f
    mov esi,5
1:  jmp g_emit_phys_gpr_move

# rdi=already bound backward target, esi=short Jcc opcode. Choose encoding from
# signed displacement alone. No labels move and no hot padding is introduced.
g_emit_known_backedge:
    push rbx; push r12
    mov rbx,rdi; mov r12d,esi
    call g_phys_window_barrier
    mov rax,[rip+g_emit_ptr]
    lea rcx,[rax+2]; mov rdx,rbx; sub rdx,rcx
    cmp rdx,-128; jl .gekbe_near
    cmp rdx,127; jg .gekbe_near
    cmp rcx,[rip+g_emit_end]; ja .gekbe_fail
    mov [rax],r12b; mov [rax+1],dl
    jmp .gekbe_commit
.gekbe_near:
    lea rcx,[rax+6]; cmp rcx,[rip+g_emit_end]; ja .gekbe_fail
    mov byte ptr [rax],0x0f
    add r12d,0x10; mov [rax+1],r12b
    sub rbx,rcx; mov [rax+2],ebx
.gekbe_commit:
    mov [rip+g_emit_ptr],rcx; xor eax,eax
    pop r12; pop rbx; ret
.gekbe_fail:
    mov dword ptr [rip+g_code_overflow],1; mov eax,1
    pop r12; pop rbx; ret

# ---------------- generic counted recurrence proof helpers ----------------
# rdi=expression, rsi=state name ptr, rdx=name len -> eax bool.
# Generic counted-state identity proof helper; not a specialized lowering route.
g_expr_is_named_state:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    mov rdi,rbx; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .geins_no
    cmp qword ptr [rax],J_STRING; jne .geins_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov rdx,r12; mov ecx,r13d; call span_eq
    jmp .geins_done
.geins_no: xor eax,eax
.geins_done: pop r13; pop r12; pop rbx; ret

# rdi=expression -> rax literal, edx=0 success / 1 no-match.
# Strictly accepts a u64 literal object.
g_expr_u64_literal:
    push rbx; push r12
    mov rbx,rdi
    cmp qword ptr [rbx],J_OBJECT; jne .geul_bad
    mov rdi,rbx; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .geul_bad
    mov rdi,rax; call g_type_from_node; cmp eax,GTYPE_U64; jne .geul_bad
    mov rdi,rbx; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .geul_bad
    call node_parse_u64
    test edx,edx; jnz .geul_bad
    xor edx,edx; jmp .geul_done
.geul_bad: xor eax,eax; mov edx,1
.geul_done: pop r12; pop rbx; ret


# Publish exactly the downstream-consumed final StateFacts of one native
# recurrence. The ordinary result slot was already stored by the caller.
# rdi=iterate symbol -> eax=0/1.
g_emit_reg_iter_projection_stores:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; xor r12d,r12d
.gerips_loop:
    cmp r12d,dword ptr [rip+g_iter_projection_count]; jae .gerips_ok
    mov rax,[rip+g_iter_projection_symbol_ptr]
    cmp qword ptr [rax+r12*8],rbx; jne .gerips_next
    mov rax,[rip+g_iter_projection_slot_ptr]; mov r14d,dword ptr [rax+r12*4]
    cmp r14d,dword ptr [rbx+24]; je .gerips_next
    mov rax,[rip+g_iter_projection_state_index_ptr]; mov r15d,dword ptr [rax+r12*4]
    cmp r15d,dword ptr [rip+g_reg_iter_total]; jae .gerips_bad
    mov eax,r15d; shl rax,5; mov r13,[rip+g_states_ptr]; add r13,rax
    mov rdx,[rip+g_reg_iter_carrier_kind_ptr]; mov eax,dword ptr [rdx+r15*4]
    cmp eax,G_PHYS_CARRIER_COUNTER; je .gerips_counter
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov edi,dword ptr [rdx+r15*4]
    cmp edi,0; jl .gerips_spill
    cmp eax,G_PHYS_CARRIER_FP; je .gerips_fp
    cmp eax,G_PHYS_CARRIER_INT; jne .gerips_bad
    mov esi,edi; xor edi,edi
    call g_emit_phys_gpr_move
    test eax,eax; jnz .gerips_bad
    jmp .gerips_store
.gerips_fp:
    mov esi,dword ptr [r13+16]
    call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gerips_bad
    jmp .gerips_store
.gerips_counter:
    call g_emit_phys_final_counter
    test eax,eax; jnz .gerips_bad
    jmp .gerips_store
.gerips_spill:
    mov eax,r15d; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    test eax,eax; jnz .gerips_bad
.gerips_store:
    mov eax,r14d; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .gerips_bad
.gerips_next:
    inc r12d; jmp .gerips_loop
.gerips_ok:
    xor eax,eax; jmp .gerips_done
.gerips_bad:
    mov eax,1
.gerips_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Generic recurrence uses the same projection metadata; final states already
# reside in the execution-local frame after the last simultaneous commit.
g_emit_generic_iter_projection_stores:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; xor r12d,r12d
.gegips_loop:
    cmp r12d,dword ptr [rip+g_iter_projection_count]; jae .gegips_ok
    mov rax,[rip+g_iter_projection_symbol_ptr]
    cmp qword ptr [rax+r12*8],rbx; jne .gegips_next
    mov rax,[rip+g_iter_projection_slot_ptr]; mov r13d,dword ptr [rax+r12*4]
    cmp r13d,dword ptr [rbx+24]; je .gegips_next
    mov rax,[rip+g_iter_projection_state_index_ptr]; mov r14d,dword ptr [rax+r12*4]
    cmp r14d,dword ptr [rip+g_state_count]; jae .gegips_bad
    mov eax,r14d; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    test eax,eax; jnz .gegips_bad
    mov eax,r13d; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .gegips_bad
.gegips_next:
    inc r12d; jmp .gegips_loop
.gegips_ok:
    xor eax,eax; jmp .gegips_done
.gegips_bad:
    mov eax,1
.gegips_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# Transition-power already leaves the whole final dense StateFact vector in x[].
# Publish projected lanes from that same scratch authority; do not rerun or clone
# the recurrence merely because more than one downstream field is consumed.
g_emit_transition_projection_stores:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; xor r12d,r12d
.getps_loop:
    cmp r12d,dword ptr [rip+g_iter_projection_count]; jae .getps_ok
    mov rax,[rip+g_iter_projection_symbol_ptr]
    cmp qword ptr [rax+r12*8],rbx; jne .getps_next
    mov rax,[rip+g_iter_projection_slot_ptr]; mov r13d,dword ptr [rax+r12*4]
    cmp r13d,dword ptr [rbx+24]; je .getps_next
    mov rax,[rip+g_iter_projection_state_index_ptr]; mov r14d,dword ptr [rax+r12*4]
    cmp r14d,dword ptr [rip+g_reg_iter_total]; jae .getps_bad
    mov eax,r14d; shl rax,5; mov r15,[rip+g_states_ptr]; add r15,rax
    mov ecx,dword ptr [r15+28]
    test ecx,ecx; js .getps_bad
    mov rdi,[rip+g_transition_power_scratch_base]
    lea rdi,[rdi+rcx*8]
    call g_emit_load_rax_abs
    test eax,eax; jnz .getps_bad
    mov eax,r13d; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .getps_bad
.getps_next:
    inc r12d; jmp .getps_loop
.getps_ok:
    xor eax,eax; jmp .getps_done
.getps_bad:
    mov eax,1
.getps_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- 1.3.67 Rank-N transition-power algebra ----------------
# Transition power is no longer a scalar self-map authority.  The published
# result owns a causal backward slice over the existing semantic state vector.
# Every state in that slice receives one dense Rank-N lane in states[+28], and
# the whole simultaneous update is proved as
#
#     x' = A*x + b  (mod 2^64)
#
# before one generic native power kernel realizes F^N.  N is structural data:
# no state-count dispatch, fixed dimension, workload identity, or repetition
# threshold exists.  A one-state recurrence is simply Rank-N with N=1.

# Build the one recurrence-wide causal state slice.  The published result and
# loop-control expressions seed the slice; state-update dependencies close it to
# a fixed point.  The graph decides depth/cardinality. No workload name, state
# count, timestep ratio, or dynamics class participates.
# -> eax=0 success / 1 malformed semantic state reference.
g_build_iterate_live_slice:
    push rbx
    push r12
    push r13
    xor ebx,ebx
.gbils_clear:
    cmp ebx,dword ptr [rip+g_reg_iter_total]
    jae .gbils_seed_result
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov dword ptr [r11+28],-1
    inc ebx
    jmp .gbils_clear
.gbils_seed_result:
    mov rax,[rip+g_reg_iter_result_name_node]
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gbils_bad
    mov dword ptr [rax+28],-2

    # Downstream field consumers are additional publication roots of the same
    # recurrence. They seed the old backward slice; no separate bundle/live-set
    # authority exists. Unconsumed final StateFacts remain causally dead.
    xor r12d,r12d
.gbils_projection_seed:
    cmp r12d,dword ptr [rip+g_iter_projection_count]; jae .gbils_projection_done
    mov rax,[rip+g_iter_projection_symbol_ptr]
    mov r13,[rip+g_reg_iter_symbol]
    cmp qword ptr [rax+r12*8],r13; jne .gbils_projection_next
    mov rax,[rip+g_iter_projection_state_index_ptr]; mov ecx,dword ptr [rax+r12*4]
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gbils_bad
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov dword ptr [r11+28],-2
.gbils_projection_next:
    inc r12d; jmp .gbils_projection_seed
.gbils_projection_done:

    # Control is part of causality: a StateFact that determines whether another
    # transition occurs is live even when it is not in the published value DAG.
    mov rdi,[rip+g_reg_iter_cond_expr]
    call g_transition_mark_state_refs
    test eax,eax; jnz .gbils_bad
    mov rdi,[rip+g_reg_iter_max_expr]
    call g_transition_mark_state_refs
    test eax,eax; jnz .gbils_bad

.gbils_closure_pass:
    mov dword ptr [rip+g_transition_slice_changed],0
    xor ebx,ebx
.gbils_closure_scan:
    cmp ebx,dword ptr [rip+g_reg_iter_total]
    jae .gbils_closure_done
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-2
    jne .gbils_next
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    call obj_get
    test rax,rax; jz .gbils_bad
    mov rdi,rax
    call g_transition_mark_state_refs
    test eax,eax; jnz .gbils_bad
.gbils_next:
    inc ebx
    jmp .gbils_closure_scan
.gbils_closure_done:
    cmp dword ptr [rip+g_transition_slice_changed],0
    jne .gbils_closure_pass
    xor eax,eax
    jmp .gbils_done
.gbils_bad:
    mov eax,1
.gbils_done:
    pop r13
    pop r12
    pop rbx
    ret

# rdi=expression -> eax=0 success / 1 malformed state reference.
# Every semantic state reference reachable in the expression is added to the
# current recurrence causal slice by changing states[+28] from -1 to -2.
g_transition_mark_state_refs:
    push rbx
    push r12
    push r13
    mov rbx,rdi
    cmp qword ptr [rbx],J_OBJECT
    jne .gtmsr_ok
    mov rdi,rbx; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax
    jz .gtmsr_args
    cmp qword ptr [rax],J_STRING
    jne .gtmsr_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax
    jz .gtmsr_bad
    cmp dword ptr [rax+28],-1
    jne .gtmsr_ok
    mov dword ptr [rax+28],-2
    mov dword ptr [rip+g_transition_slice_changed],1
    jmp .gtmsr_ok
.gtmsr_args:
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax
    jz .gtmsr_ok
    cmp qword ptr [rax],J_ARRAY
    jne .gtmsr_bad
    mov r12,[rax+24]
.gtmsr_loop:
    test r12,r12
    jz .gtmsr_ok
    mov rdi,r12
    call g_transition_mark_state_refs
    test eax,eax
    jnz .gtmsr_bad
    mov r12,[r12+32]
    jmp .gtmsr_loop
.gtmsr_ok:
    xor eax,eax
    jmp .gtmsr_done
.gtmsr_bad:
    mov eax,1
.gtmsr_done:
    pop r13
    pop r12
    pop rbx
    ret

# rdi=expression -> eax=1 if any semantic state reference is reachable.
# Powered initial values may depend on immutable inputs/bindings/literals, but
# they may not depend on another iterate state that has not yet been realized.
g_expr_has_state_ref:
    push rbx; push r12; push r13
    mov rbx,rdi
    cmp qword ptr [rbx],J_OBJECT; jne .gehsr_no
    mov rdi,rbx; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jnz .gehsr_yes
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gehsr_no
    cmp qword ptr [rax],J_ARRAY; jne .gehsr_no
    mov r12,[rax+24]
.gehsr_loop:
    test r12,r12; jz .gehsr_no
    mov rdi,r12; call g_expr_has_state_ref
    test eax,eax; jnz .gehsr_yes
    mov r12,[r12+32]; jmp .gehsr_loop
.gehsr_yes:
    mov eax,1; jmp .gehsr_done
.gehsr_no:
    xor eax,eax
.gehsr_done:
    pop r13; pop r12; pop rbx; ret

# rdi=affine expression, esi=dense destination row, rdx=wrap-u64 scale.
# Emits only initialization of the generic Rank-N A/b scratch.  The syntax
# proof and coefficient materialization are the same traversal, so there is no
# shadow AST matcher to drift from code generation.  Returns eax=0/1.
g_transition_emit_affine_terms:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    mov r12d,esi
    mov r13,rdx

    # Any selected state is one affine basis lane.
    cmp qword ptr [rbx],J_OBJECT
    jne .gteat_fail
    mov rdi,rbx; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax
    jz .gteat_literal
    cmp qword ptr [rax],J_STRING
    jne .gteat_fail
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax
    jz .gteat_fail
    cmp dword ptr [rax+16],GTYPE_U64
    jne .gteat_fail
    mov ecx,dword ptr [rax+28]
    test ecx,ecx
    js .gteat_fail
    mov eax,r12d
    mov edx,dword ptr [rip+g_transition_power_slice_count]
    imul rax,rdx
    add rax,rcx
    shl rax,3
    add rax,[rip+g_transition_power_matrix_base]
    mov rdi,rax
    mov rsi,r13
    call g_emit_add_imm64_abs
    jmp .gteat_done

.gteat_literal:
    mov rdi,rbx
    call g_expr_u64_literal
    test edx,edx
    jnz .gteat_object
    imul rax,r13
    mov r15,rax
    mov eax,r12d
    shl rax,3
    add rax,[rip+g_transition_power_bias_base]
    mov rdi,rax
    mov rsi,r15
    call g_emit_add_imm64_abs
    jmp .gteat_done

.gteat_object:
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax
    jz .gteat_fail
    mov rbp,rax
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax
    jz .gteat_fail
    cmp qword ptr [rax],J_ARRAY
    jne .gteat_fail
    mov r14,[rax+24]
    test r14,r14
    jz .gteat_fail
    mov r15,[r14+32]
    test r15,r15
    jz .gteat_fail
    cmp qword ptr [r15+32],0
    jne .gteat_fail

    mov rdi,[rbp+8]; mov rsi,[rbp+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax
    jnz .gteat_add
    mov rdi,[rbp+8]; mov rsi,[rbp+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax
    jnz .gteat_sub
    mov rdi,[rbp+8]; mov rsi,[rbp+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax
    jnz .gteat_mul
    jmp .gteat_fail

.gteat_add:
    mov rdi,r14; mov esi,r12d; mov rdx,r13; call g_transition_emit_affine_terms
    test eax,eax; jnz .gteat_fail
    mov rdi,r15; mov esi,r12d; mov rdx,r13; call g_transition_emit_affine_terms
    jmp .gteat_done

.gteat_sub:
    mov rdi,r14; mov esi,r12d; mov rdx,r13; call g_transition_emit_affine_terms
    test eax,eax; jnz .gteat_fail
    mov rdx,r13
    neg rdx
    mov rdi,r15; mov esi,r12d; call g_transition_emit_affine_terms
    jmp .gteat_done

.gteat_mul:
    # Multiplication remains affine only when one operand is a literal.  The
    # literal folds into the traversal scale; no runtime coefficient selector.
    mov rdi,r14
    call g_expr_u64_literal
    test edx,edx
    jnz .gteat_mul_right
    imul rax,r13
    mov rdx,rax
    mov rdi,r15; mov esi,r12d; call g_transition_emit_affine_terms
    jmp .gteat_done
.gteat_mul_right:
    mov rdi,r15
    call g_expr_u64_literal
    test edx,edx
    jnz .gteat_fail
    imul rax,r13
    mov rdx,rax
    mov rdi,r14; mov esi,r12d; call g_transition_emit_affine_terms
    jmp .gteat_done

.gteat_fail:
    mov eax,1
.gteat_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# rdi=iterate symbol -> eax=1 if the published causal slice is a closed Rank-N
# affine relation and has been fully emitted.  Failure rewinds both emitted code
# and exact runtime-scratch ownership, then the same ordinary causal DAG handles
# the recurrence.  There is no retained scalar transition-power backend.
g_try_emit_transition_power_slice:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    G_EMIT_POSITION rax; mov [rip+g_transition_power_emit_start],rax
    mov rax,[rip+g_runtime_temp_bytes_used]; mov [rip+g_transition_power_temp_start],rax
    cmp dword ptr [rip+g_reg_iter_counted],1
    jne .gtps_no
    cmp dword ptr [rip+g_overflow_wrap],1
    jne .gtps_no

    # Locate the published semantic state through the already-built Rank-N state
    # authority.  Declaration order and total cardinality have no special case.
    mov rax,[rip+g_reg_iter_result_name_node]
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax
    jz .gtps_no
    cmp dword ptr [rax+16],GTYPE_U64
    jne .gtps_no
    mov r14d,dword ptr [rax+24]
    mov dword ptr [rip+g_transition_power_result_index],r14d

    # The ordinary StateFact episode already owns the exact causal backward
    # slice. Transition power is only another physical realization of those
    # same live facts; it may assign temporary dense lanes but never rebuild a
    # second dependency slice.
    cmp dword ptr [rax+28],-1
    je .gtps_no

    # Replace the temporary -2 mark with one dense Rank-N lane.  All reachable
    # states must share wrap-u64 algebra; unrelated states remain absent (-1).
    xor r12d,r12d
    xor ecx,ecx
.gtps_dense_scan:
    cmp ecx,dword ptr [rip+g_reg_iter_total]
    jae .gtps_dense_done
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-2
    jne .gtps_dense_next
    cmp dword ptr [r11+16],GTYPE_U64
    jne .gtps_rollback
    mov dword ptr [r11+28],r12d
    cmp ecx,r14d
    jne .gtps_dense_not_result
    mov dword ptr [rip+g_transition_power_result_dense],r12d
.gtps_dense_not_result:
    inc r12d
.gtps_dense_next:
    inc ecx
    jmp .gtps_dense_scan
.gtps_dense_done:
    test r12d,r12d
    jz .gtps_rollback
    mov dword ptr [rip+g_transition_power_slice_count],r12d

    # Exact scratch demand for x,A,b,tmp_x,tmp_A,tmp_b:
    #     (2*N*N + 4*N) qwords.
    mov eax,r12d
    mov rcx,rax
    mul rcx
    test rdx,rdx
    jnz .gtps_rollback
    shl rax,1
    jc .gtps_rollback
    mov ecx,r12d
    shl rcx,2
    jc .gtps_rollback
    add rax,rcx
    jc .gtps_rollback
    shl rax,3
    jc .gtps_rollback
    mov rdi,rax
    call g_alloc_runtime_temp_bytes
    test rax,rax
    jz .gtps_rollback
    mov [rip+g_transition_power_scratch_base],rax
    mov ecx,r12d
    lea rdx,[rax+rcx*8]
    mov [rip+g_transition_power_matrix_base],rdx
    mov r8,rcx
    imul r8,rcx
    lea rdx,[rdx+r8*8]
    mov [rip+g_transition_power_bias_base],rdx

    # Materialize x0 for every state in the causal slice. Initial values must be
    # independent of sibling mutable state, exactly as simultaneous iterate
    # semantics require before the first transition.
    xor ecx,ecx
.gtps_init_scan:
    cmp ecx,dword ptr [rip+g_reg_iter_total]
    jae .gtps_coeff_scan_begin
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov r13d,dword ptr [r11+28]
    test r13d,r13d
    js .gtps_init_next
    mov rax,[rip+g_reg_iter_decls_ptr]; mov r15,[rax+rcx*8]
    mov rdi,r15; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; push rcx; call obj_get; pop rcx
    test rax,rax
    jz .gtps_rollback
    mov r15,rax
    push rcx
    mov rdi,r15; call g_expr_has_state_ref
    pop rcx
    test eax,eax
    jnz .gtps_rollback
    push rcx
    mov rdi,r15; call g_emit_expr
    pop rcx
    cmp eax,GTYPE_U64
    jne .gtps_rollback
    push rcx
    call g_emit_pop_rax
    pop rcx
    mov eax,r13d; shl rax,3; add rax,[rip+g_transition_power_scratch_base]
    mov rdi,rax
    push rcx
    call g_emit_store_rax_abs
    pop rcx
    test eax,eax
    jnz .gtps_rollback
.gtps_init_next:
    inc ecx
    jmp .gtps_init_scan

    # The same recursive algebra traversal proves closure and emits A/b.  Thus
    # proof and realization cannot disagree about what "affine" means.
.gtps_coeff_scan_begin:
    xor ecx,ecx
.gtps_coeff_scan:
    cmp ecx,dword ptr [rip+g_reg_iter_total]
    jae .gtps_call
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov r13d,dword ptr [r11+28]
    test r13d,r13d
    js .gtps_coeff_next
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax
    jz .gtps_rollback
    push rcx
    mov rdi,rax; mov esi,r13d; mov edx,1; call g_transition_emit_affine_terms
    pop rcx
    test eax,eax
    jnz .gtps_rollback
.gtps_coeff_next:
    inc ecx
    jmp .gtps_coeff_scan

.gtps_call:
    # N is the already-proved counted-axis bound.  The generic native helper
    # consumes the exact Rank-N transform and returns only the published lane.
    mov rdi,[rip+g_reg_iter_bound_expr]
    call g_emit_expr
    cmp eax,GTYPE_U64
    jne .gtps_rollback
    call g_emit_pop_rax
    lea rdi,[rip+gc_transition_power_mov_rdx_rax]; mov esi,gc_transition_power_mov_rdx_rax_end-gc_transition_power_mov_rdx_rax; call g_emit_bytes
    test eax,eax
    jnz .gtps_rollback
    mov rdi,[rip+g_transition_power_scratch_base]
    call g_emit_mov_rdi_imm64
    test eax,eax
    jnz .gtps_rollback
    mov edi,dword ptr [rip+g_transition_power_slice_count]
    call g_emit_mov_esi_imm32
    test eax,eax
    jnz .gtps_rollback
    mov edi,dword ptr [rip+g_transition_power_result_dense]
    call g_emit_mov_ecx_imm32
    test eax,eax
    jnz .gtps_rollback
    mov rdi,GENERAL_RANKN_AFFINE_POWER_U64_VA
    call g_emit_call_abs
    test eax,eax
    jnz .gtps_rollback
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax
    jnz .gtps_rollback
    mov rdi,rbx; call g_emit_transition_projection_stores
    test eax,eax; jnz .gtps_rollback
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
    mov eax,1
    jmp .gtps_done

.gtps_rollback:
    mov rax,[rip+g_transition_power_emit_start]; mov [rip+g_emit_ptr],rax
    mov rax,[rip+g_transition_power_temp_start]; mov [rip+g_runtime_temp_bytes_used],rax
    xor ecx,ecx
.gtps_rollback_slice:
    cmp ecx,dword ptr [rip+g_reg_iter_total]
    jae .gtps_no
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],0
    jl .gtps_rollback_next
    mov dword ptr [r11+28],-2
.gtps_rollback_next:
    inc ecx
    jmp .gtps_rollback_slice
.gtps_no:
    xor eax,eax
.gtps_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# rdi=boundA, rsi=boundB -> eax=1 for equal immutable total u64 facts.
g_expr_same_bound:
    push r12; push r13
    mov r12,rdi; mov r13,rsi
    mov rdi,r12; call g_infer_expr; cmp eax,GTYPE_U64; jne .gesb_no
    mov rdi,r13; call g_infer_expr; cmp eax,GTYPE_U64; jne .gesb_no
    mov rdi,r12; call g_semantic_expr_is_pure; test eax,eax; jz .gesb_no
    mov rdi,r13; call g_semantic_expr_is_pure; test eax,eax; jz .gesb_no
    mov rdi,r12; call g_semantic_expr_is_total; test eax,eax; jz .gesb_no
    mov rdi,r13; call g_semantic_expr_is_total; test eax,eax; jz .gesb_no
    mov rdi,r12; mov rsi,r13; call g_semantic_prove_equal; jmp .gesb_done
.gesb_no: xor eax,eax
.gesb_done: pop r13; pop r12; ret

# rdi=semantic state declaration -> eax natural type, before live-slice admission.
g_state_decl_type:
    lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gsdt_done
    mov rdi,rax; jmp g_type_from_node
.gsdt_done: ret

# rdi=expression, rsi=counter name ptr, rdx=name len -> eax bool
# Match add(state(counter), 1), allowing argument reversal.
g_match_counter_inc:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    cmp qword ptr [rbx],J_OBJECT; jne .gmci_no
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gmci_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jz .gmci_no
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gmci_no
    cmp qword ptr [rax],J_ARRAY; jne .gmci_no
    mov r14,[rax+24]; test r14,r14; jz .gmci_no
    mov r15,[r14+32]; test r15,r15; jz .gmci_no
    cmp qword ptr [r15+32],0; jne .gmci_no
    mov rdi,r14; mov rsi,r12; mov rdx,r13; call g_expr_is_named_state; test eax,eax; jz .gmci_rev
    mov rdi,r15; call g_expr_u64_literal; test edx,edx; jnz .gmci_no
    cmp rax,1; sete al; movzx eax,al; jmp .gmci_done
.gmci_rev:
    mov rdi,r15; mov rsi,r12; mov rdx,r13; call g_expr_is_named_state; test eax,eax; jz .gmci_no
    mov rdi,r14; call g_expr_u64_literal; test edx,edx; jnz .gmci_no
    cmp rax,1; sete al; movzx eax,al; jmp .gmci_done
.gmci_no: xor eax,eax
.gmci_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=condition, rsi=counter name, rdx=name len -> eax=control form.
# 0 unknown; 1 exact i<limit; 2 original lazy guard entails i<limit.
# The existing zero-init/unit-increment proof closes the ordinal relation.
g_match_counter_bound:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
.gmcb_identity:
    mov rdi,rbx; mov esi,GTYPE_BOOL; call g_semantic_identity_operand
    test rax,rax; jz .gmcb_prove
    mov rbx,rax; jmp .gmcb_identity
.gmcb_prove:
    mov rdi,rbx; mov rsi,r12; mov rdx,r13; mov ecx,1
    call g_predicate_entails_counter_bound
    cmp eax,1; jne .gmcb_no
    mov rax,[rip+g_reg_iter_max_expr]; mov [rip+g_counted_bound_expr],rax
    # Only an exact guard may become bottom-tested counted control. A compound
    # guard keeps its original short-circuit control and all state consumers.
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gmcb_guarded
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq
    test eax,eax; jz .gmcb_guarded
    mov eax,1; jmp .gmcb_done
.gmcb_guarded: mov eax,2; jmp .gmcb_done
.gmcb_no: xor eax,eax
.gmcb_done: pop r13; pop r12; pop rbx; ret

# One Boolean truth-edge fact, derived without changing evaluation order.
# rdi=predicate, rsi=counter name, rdx=len, ecx=edge truth.
# eax=0 unknown, 1 entails counter<immutable limit, 2 impossible edge.
# AND/OR use the same intersection/union law; SELECT composes two guarded paths.
g_predicate_entails_counter_bound:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov [rsp],ecx
    test rbx,rbx; jz .gpecb_no
    mov rdi,rbx; call g_expr_bool_literal
    test edx,edx; jnz .gpecb_op
    cmp eax,[rsp]; je .gpecb_no
    mov eax,2; jmp .gpecb_done
.gpecb_op:
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpecb_no
    mov [rsp+8],rax
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpecb_no
    mov r14,[rax+24]; test r14,r14; jz .gpecb_no
    mov r15,[r14+32]
    mov rax,[rsp+8]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_not]; mov ecx,gv_not_end-gv_not; call span_eq
    test eax,eax; jz .gpecb_binary
    test r15,r15; jnz .gpecb_no
    mov rdi,r14; mov rsi,r12; mov rdx,r13; mov ecx,[rsp]; xor ecx,1
    call g_predicate_entails_counter_bound; jmp .gpecb_done
.gpecb_binary:
    test r15,r15; jz .gpecb_no
    mov rax,[rsp+8]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_select]; mov ecx,gv_select_end-gv_select; call span_eq
    test eax,eax; jnz .gpecb_select
    cmp qword ptr [r15+32],0; jne .gpecb_no
    mov rax,[rsp+8]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq
    test eax,eax; jnz .gpecb_and
    mov rax,[rsp+8]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq
    test eax,eax; jz .gpecb_relation
    mov eax,[rsp]; xor eax,1; mov [rsp+4],eax; jmp .gpecb_pair
.gpecb_and: mov eax,[rsp]; mov [rsp+4],eax
.gpecb_pair:
    mov rdi,r14; mov rsi,r12; mov rdx,r13; mov ecx,[rsp]
    call g_predicate_entails_counter_bound; mov [rsp+16],eax
    mov rdi,r15; mov rsi,r12; mov rdx,r13; mov ecx,[rsp]
    call g_predicate_entails_counter_bound
    cmp dword ptr [rsp+4],1; je .gpecb_intersection
    mov edx,[rsp+16]; jmp .gpecb_union
.gpecb_intersection:
    # A conjunction edge is impossible if either side is impossible; otherwise
    # any bound suffices. Unknown proofs never erase a runtime condition.
    cmp eax,2; je .gpecb_done
    cmp dword ptr [rsp+16],2; je .gpecb_impossible
    or eax,[rsp+16]; jmp .gpecb_done
.gpecb_union:
    test eax,eax; jz .gpecb_done
    test edx,edx; jz .gpecb_no
    cmp eax,2; jne .gpecb_yes
    mov eax,edx; jmp .gpecb_done
.gpecb_select:
    mov rax,[r15+32]; test rax,rax; jz .gpecb_no
    cmp qword ptr [rax+32],0; jne .gpecb_no
    mov [rsp+24],rax
    # true path = condition(true) AND true-arm(demanded truth).
    mov rdi,r14; mov rsi,r12; mov rdx,r13; mov ecx,1
    call g_predicate_entails_counter_bound; mov [rsp+16],eax
    mov rdi,r15; mov rsi,r12; mov rdx,r13; mov ecx,[rsp]
    call g_predicate_entails_counter_bound
    cmp eax,2; je .gpecb_true_path
    cmp dword ptr [rsp+16],2; je .gpecb_true_impossible
    or eax,[rsp+16]; jmp .gpecb_true_path
.gpecb_true_impossible: mov eax,2
.gpecb_true_path: mov [rsp+20],eax
    # false path = condition(false) AND false-arm(demanded truth).
    mov rdi,r14; mov rsi,r12; mov rdx,r13; xor ecx,ecx
    call g_predicate_entails_counter_bound; mov [rsp+16],eax
    mov rdi,[rsp+24]; mov rsi,r12; mov rdx,r13; mov ecx,[rsp]
    call g_predicate_entails_counter_bound
    cmp eax,2; je .gpecb_paths
    cmp dword ptr [rsp+16],2; je .gpecb_false_impossible
    or eax,[rsp+16]; jmp .gpecb_paths
.gpecb_false_impossible: mov eax,2
.gpecb_paths: mov edx,[rsp+20]; jmp .gpecb_union
.gpecb_relation:
    # Integer comparison duality only; no IEEE complement or arithmetic bound
    # rewriting is assumed. Both comparison operands must be exact U64 facts.
    mov rdi,r14; call g_infer_expr; cmp eax,GTYPE_U64; jne .gpecb_no
    mov rdi,r15; call g_infer_expr; cmp eax,GTYPE_U64; jne .gpecb_no
    mov rax,[rsp+8]; mov rdi,[rax+8]; mov rsi,[rax+16]
    cmp dword ptr [rsp],0; je .gpecb_false_relation
    lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq; test eax,eax; jnz .gpecb_bound
    mov rax,[rsp+8]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_gt]; mov ecx,gv_gt_end-gv_gt; call span_eq
    test eax,eax; jz .gpecb_no
    xchg r14,r15; jmp .gpecb_bound
.gpecb_false_relation:
    lea rdx,[rip+gv_ge]; mov ecx,gv_ge_end-gv_ge; call span_eq; test eax,eax; jnz .gpecb_bound
    mov rax,[rsp+8]; mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_le]; mov ecx,gv_le_end-gv_le; call span_eq
    test eax,eax; jz .gpecb_no
    xchg r14,r15
.gpecb_bound:
    mov rdi,r14; mov rsi,r12; mov rdx,r13; call g_expr_is_named_state
    test eax,eax; jz .gpecb_no
    mov rdi,r15; mov rsi,[rip+g_reg_iter_max_expr]; call g_expr_same_bound
    test eax,eax; jz .gpecb_no
.gpecb_yes: mov eax,1; jmp .gpecb_done
.gpecb_impossible: mov eax,2; jmp .gpecb_done
.gpecb_no: xor eax,eax
.gpecb_done: add rsp,32; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Emit one execution-local mutable StateFact frame around an iterate episode.
# The frame size is the largest represented state vector, exactly the amount one
# live iterate can require.  Concurrent causal executions already have disjoint
# stacks; sequential episodes reuse the same bytes after causal death.
g_emit_state_frame_enter:
    mov eax,dword ptr [rip+g_runtime_state_capacity]
    shl eax,4
    add eax,15
    and eax,-16
    test eax,eax
    jz .gesfe_fail
    mov dword ptr [rip+g_state_local_frame_bytes],eax
    # sub rsp,imm32
    lea rdi,[rip+gc_state_frame_sub_prefix]
    mov esi,gc_state_frame_sub_prefix_end-gc_state_frame_sub_prefix
    call g_emit_bytes
    mov edi,dword ptr [rip+g_state_local_frame_bytes]
    call g_emit_u32
    # mov r15,rsp
    lea rdi,[rip+gc_state_frame_base]
    mov esi,gc_state_frame_base_end-gc_state_frame_base
    call g_emit_bytes
    xor eax,eax
    ret
.gesfe_fail:
    mov eax,1
    ret

g_emit_state_frame_leave:
    lea rdi,[rip+gc_state_frame_add_prefix]
    mov esi,gc_state_frame_add_prefix_end-gc_state_frame_add_prefix
    call g_emit_bytes
    mov edi,dword ptr [rip+g_state_local_frame_bytes]
    call g_emit_u32
    ret

# iterate symbol rdi
g_emit_iterate_binding:
    # One causal-state architecture only. Mutable state authority is local to
    # this causal execution; no shared invocation state arena survives.
    push rdi
    call g_emit_state_frame_enter
    pop rdi
    test eax,eax
    jnz .geit_frame_bad
    push rdi
    call g_try_emit_reg_iterate
    pop rdi
    test eax,eax
    jz .geit_generic
    call g_emit_state_frame_leave
    xor eax,eax
    ret
.geit_frame_bad:
    mov eax,1
    ret
.geit_generic:
    mov dword ptr [rip+g_iter_reg_mode],0
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,[rbx+32]
    mov dword ptr [rip+g_state_count],0
    # states declarations + init
    mov rdi,r12; lea rsi,[rip+gk_states]; mov edx,gk_states_end-gk_states; call obj_get
    test rax,rax; jz .geit_bad
    mov r13,[rax+24]
.state_decl_loop:
    test r13,r13; jz .state_decl_done
    mov eax,dword ptr [rip+g_state_count]; cmp eax,dword ptr [rip+g_state_capacity]; jae .geit_bad
    mov rdi,r13; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get; test rax,rax; jz .geit_bad
    mov r14,[rax+8]; mov r15,[rax+16]
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,rax; call g_type_from_node; test eax,eax; jz .geit_bad
    mov edx,dword ptr [rip+g_state_count]; mov ecx,edx; shl rcx,5; mov rax,[rip+g_states_ptr]; add rax,rcx
    mov [rax],r14; mov [rax+8],r15; mov [rax+16],eax   # corrected below after type save
    # fix type because eax overwritten by address calculation: reparse cheaply
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get; mov rdi,rax; call g_type_from_node
    mov ecx,dword ptr [rip+g_state_count]; mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    mov [r11+16],eax; mov [r11+20],ecx
    # init may reference prior states
    mov rdi,r13; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,rax; call g_emit_expr
    # Recursive expression emission may clobber caller-saved R11; reacquire metadata.
    mov ecx,dword ptr [rip+g_state_count]; mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    cmp eax,dword ptr [r11+16]; jne .geit_bad
    call g_emit_pop_rax
    mov eax,dword ptr [rip+g_state_count]; call g_state_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    inc dword ptr [rip+g_state_count]
    mov r13,[r13+32]; jmp .state_decl_loop
.state_decl_done:
    # max iterations -> RBP
    mov rdi,r12; lea rsi,[rip+gk_max_iterations]; mov edx,gk_max_iterations_end-gk_max_iterations; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,rax; call g_emit_expr; cmp eax,GTYPE_U64; jne .geit_bad
    call g_emit_pop_rax; lea rdi,[rip+gc_mov_rbp_rax]; mov esi,gc_mov_rbp_rax_end-gc_mov_rbp_rax; call g_emit_bytes
    lea rdi,[rip+gc_xor_rbx]; mov esi,gc_xor_rbx_end-gc_xor_rbx; call g_emit_bytes
    G_EMIT_LOOP_POSITION r15,.geit_bad
    # condition
    mov rdi,r12; lea rsi,[rip+gk_condition]; mov edx,gk_condition_end-gk_condition; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,rax; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .geit_bad
    call g_emit_pop_rax; lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    call g_emit_jz_patch; mov r14,rax
    # max guard: if rbx < rbp continue else reject
    lea rdi,[rip+gc_iter_max_guard]; mov esi,gc_iter_max_guard_end-gc_iter_max_guard; call g_emit_bytes
    # updates object
    mov rdi,r12; lea rsi,[rip+gk_update]; mov edx,gk_update_end-gk_update; call obj_get; test rax,rax; jz .geit_bad
    mov r13,rax
    xor ecx,ecx
.update_eval_loop:
    cmp ecx,dword ptr [rip+g_state_count]; jae .update_commit
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    mov rdi,r13; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .geit_bad
    push rcx
    mov rdi,rax; call g_emit_expr
    pop rcx
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    cmp eax,dword ptr [r11+16]; jne .geit_bad
    push rcx; call g_emit_pop_rax; pop rcx
    mov eax,ecx; call g_state_temp_addr; mov rdi,rax
    push rcx; call g_emit_store_rax_abs; pop rcx
    inc ecx; jmp .update_eval_loop
.update_commit:
    xor ecx,ecx
.update_commit_loop:
    cmp ecx,dword ptr [rip+g_state_count]; jae .update_next_iter
    mov eax,ecx; call g_state_temp_addr; mov rdi,rax
    push rcx; call g_emit_load_rax_abs; pop rcx
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax
    push rcx; call g_emit_store_rax_abs; pop rcx
    inc ecx; jmp .update_commit_loop
.update_next_iter:
    lea rdi,[rip+gc_inc_rbx]; mov esi,gc_inc_rbx_end-gc_inc_rbx; call g_emit_bytes
    mov edi,0xE9; call g_emit_u8
    G_EMIT_POSITION rax; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; jbe 93f
    mov dword ptr [rip+g_code_overflow],1; jmp .geit_bad
93:
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
    G_EMIT_POSITION rsi; mov rdi,r14; call g_patch_rel32
    # result state -> binding slot
    mov rdi,r12; lea rsi,[rip+gk_result]; mov edx,gk_result_end-gk_result; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state; test rax,rax; jz .geit_bad
    mov eax,dword ptr [rax+20]; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    test eax,eax; jnz .geit_bad
    mov rdi,rbx; call g_emit_generic_iter_projection_stores
    test eax,eax; jnz .geit_bad
    xor eax,eax; jmp .geit_done
.geit_bad: mov eax,1
.geit_done:
    test eax,eax
    jnz .geit_done_pop
    call g_emit_state_frame_leave
.geit_done_pop:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# lookup binding symbol rdi
g_emit_lookup_binding:
    push rbx; mov rbx,rdi
    mov rdi,[rbx+32]; call g_emit_lookup_from_binding_node
    test eax,eax; jz .gelb_bad
    cmp eax,dword ptr [rbx+20]; jne .gelb_bad
    call g_emit_pop_rax
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    xor eax,eax; pop rbx; ret
.gelb_bad: mov eax,1; pop rbx; ret

# nested reduce compile-time for literal nested tensors.
g_emit_nested_reduce_binding:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r12,[rbx+32]
    mov rdi,r12; lea rsi,[rip+gk_input]; mov edx,gk_input_end-gk_input; call obj_get; test rax,rax; jz .genr_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol; test rax,rax; jz .genr_bad
    cmp dword ptr [rax+16],GK_NESTED_LITERAL; jne .genr_bad
    mov r13,[rax+32]
    mov rdi,r13; lea rsi,[rip+gk_segments]; mov edx,gk_segments_end-gk_segments; call obj_get; test rax,rax; jz .genr_bad
    mov r13,[rax+24]
    xor r14,r14                     # sum/count
    xor r11,r11                     # segment count
    # kind
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get; test rax,rax; jz .genr_bad
    mov r10,rax
.segment_loop:
    test r13,r13; jz .segments_done
    inc r11
    cmp qword ptr [r13],J_ARRAY; jne .genr_bad
    mov r9,[r13+24]
.value_loop:
    test r9,r9; jz .next_segment
    mov rax,r9; call node_parse_u64; test edx,edx; jnz .genr_bad
    add r14,rax
    mov r9,[r9+32]; jmp .value_loop
.next_segment: mov r13,[r13+32]; jmp .segment_loop
.segments_done:
    # rewalk for count if needed
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_segment_count]; mov ecx,gv_segment_count_end-gv_segment_count; call span_eq
    test eax,eax; jnz .use_segments
    mov rdi,r12; lea rsi,[rip+gk_kind]; mov edx,gk_kind_end-gk_kind; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_count]; mov ecx,gv_count_end-gv_count; call span_eq
    test eax,eax; jz .use_sum
    # count total values by rewalk
    xor r14,r14
    mov rdi,[rbx+32]; lea rsi,[rip+gk_input]; mov edx,gk_input_end-gk_input; call obj_get
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol; mov r13,[rax+32]
    mov rdi,r13; lea rsi,[rip+gk_segments]; mov edx,gk_segments_end-gk_segments; call obj_get; mov r13,[rax+24]
.count_seg: test r13,r13; jz .use_sum; mov r9,[r13+24]
.count_val: test r9,r9; jz .count_next; inc r14; mov r9,[r9+32]; jmp .count_val
.count_next: mov r13,[r13+32]; jmp .count_seg
.use_segments: mov r14,r11
.use_sum:
    mov rdi,r14; call g_emit_push_imm64; call g_emit_pop_rax
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    xor eax,eax; jmp .genr_done
.genr_bad: mov eax,1
.genr_done: pop r14; pop r13; pop r12; pop rbx; ret

# Dictionary source helpers. Binding lookup node includes dictionary/key/default.
g_emit_lookup_from_binding_node:
    push rbx; push r12; push r13
    mov rbx,rdi
    lea rsi,[rip+gk_dictionary]; mov edx,gk_dictionary_end-gk_dictionary; call obj_get; test rax,rax; jz .geln_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol; test rax,rax; jz .geln_bad
    cmp dword ptr [rax+16],GK_DICTIONARY; jne .geln_bad
    mov r12,[rax+32]
    mov rdi,rbx; lea rsi,[rip+gk_key]; mov edx,gk_key_end-gk_key; call obj_get; test rax,rax; jz .geln_bad
    mov r13,rax
    mov rdi,rbx; lea rsi,[rip+gk_default]; mov edx,gk_default_end-gk_default; call obj_get; test rax,rax; jz .geln_bad
    mov rdx,rax
    mov rdi,r12; mov rsi,r13; call g_emit_dictionary_lookup_core
    jmp .geln_done
.geln_bad: xor eax,eax
.geln_done: pop r13; pop r12; pop rbx; ret

# dictionary_lookup expression object rdi
g_emit_dictionary_lookup_expr:
    push rbx; push r12; push r13
    mov rbx,rdi
    lea rsi,[rip+gk_dictionary]; mov edx,gk_dictionary_end-gk_dictionary; call obj_get; test rax,rax; jz .gedle_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol; test rax,rax; jz .gedle_bad
    cmp dword ptr [rax+16],GK_DICTIONARY; jne .gedle_bad
    mov r12,[rax+32]
    mov rdi,rbx; lea rsi,[rip+gk_key]; mov edx,gk_key_end-gk_key; call obj_get; test rax,rax; jz .gedle_bad
    mov r13,rax
    mov rdi,rbx; lea rsi,[rip+gk_default]; mov edx,gk_default_end-gk_default; call obj_get; test rax,rax; jz .gedle_bad
    mov rdx,rax
    mov rdi,r12; mov rsi,r13; call g_emit_dictionary_lookup_core
    jmp .gedle_done
.gedle_bad: xor eax,eax
.gedle_done: pop r13; pop r12; pop rbx; ret

# rdi=dict binding node, rsi=key expr node, rdx=default expr -> eax value type/0
g_emit_dictionary_lookup_core:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    # value type
    mov rdi,rbx; lea rsi,[rip+gk_value_type]; mov edx,gk_value_type_end-gk_value_type; call obj_get; test rax,rax; jz .gedlc_bad
    mov rdi,rax; call g_type_from_node; mov r14d,eax; test r14d,r14d; jz .gedlc_bad
    # entries
    mov rdi,rbx; lea rsi,[rip+gk_entries]; mov edx,gk_entries_end-gk_entries; call obj_get; test rax,rax; jz .gedlc_bad
    mov r15,[rax+24]
    # key type
    mov rdi,rbx; lea rsi,[rip+gk_key_type]; mov edx,gk_key_type_end-gk_key_type; call obj_get; test rax,rax; jz .gedlc_bad
    mov rdi,rax; call g_type_from_node; mov ebx,eax; test ebx,ebx; jz .gedlc_bad
.entry_loop:
    test r15,r15; jz .dict_default
    mov rdi,r15; lea rsi,[rip+gk_key]; mov edx,gk_key_end-gk_key; call obj_get; test rax,rax; jz .gedlc_bad
    mov rdi,r12; mov rsi,rax; mov edx,ebx; call g_emit_key_equal
    test eax,eax; jnz .gedlc_bad
    call g_emit_pop_rax; lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    call g_emit_jz_patch; mov r11,rax
    mov rdi,r15; lea rsi,[rip+gk_value]; mov edx,gk_value_end-gk_value; call obj_get; test rax,rax; jz .gedlc_bad
    mov rdi,rax; call g_emit_expr; cmp eax,r14d; jne .gedlc_bad
    call g_emit_jmp_patch; push rax
    G_EMIT_POSITION rsi; mov rdi,r11; call g_patch_rel32
    mov r15,[r15+32]
    jmp .entry_loop
.dict_default:
    mov rdi,r13; call g_emit_expr; cmp eax,r14d; jne .gedlc_bad
    # Patch all accumulated end jumps. We pushed one pointer per entry; count
    # them by re-reading entries length and popping until exhausted.
    mov rdi,[rip+g_root]            # not useful for count; use dict entries again below
    # We cannot safely discover stack count now without an explicit counter;
    # this first implementation instead rejects multi-entry chain here.
    # (Single-entry still useful for proof; multi-entry support is added below.)
    # fall through is replaced by dedicated helper in later patch.
    mov eax,r14d
    jmp .gedlc_done
.gedlc_bad: xor eax,eax
.gedlc_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# key expr rdi, entry key JSON node rsi, key type edx -> eax 0 success/1 fail; pushes bool.
g_emit_key_equal:
    cmp edx,GTYPE_STRING; je .geke_string
    push rsi
    call g_emit_expr
    pop rsi
    cmp eax,edx; jne .geke_bad
    # entry numeric key isn't an expression object; create immediate directly.
    cmp edx,GTYPE_U64; je .geke_u64
    cmp edx,GTYPE_I64; je .geke_i64
    jmp .geke_bad
.geke_u64:
    mov rax,rsi; call node_parse_u64; test edx,edx; jnz .geke_bad
    mov rdi,rax; call g_emit_push_imm64; lea rdi,[rip+gc_cmp_eq]; mov esi,gc_cmp_eq_end-gc_cmp_eq; call g_emit_bytes; xor eax,eax; ret
.geke_i64:
    mov rdi,rsi; call g_parse_i64_node; test edx,edx; jnz .geke_bad
    mov rdi,rax; call g_emit_push_imm64; lea rdi,[rip+gc_cmp_eq]; mov esi,gc_cmp_eq_end-gc_cmp_eq; call g_emit_bytes; xor eax,eax; ret
.geke_string:
    # string key expression must be literal or external string variable.
    mov r8,rdi; mov r9,rsi
    mov rdi,r8; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .geke_string_var
    cmp qword ptr [rax],J_STRING; jne .geke_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov rdx,[r9+8]; mov rcx,[r9+16]; call span_eq
    mov edi,eax; call g_emit_push_imm64; xor eax,eax; ret
.geke_string_var:
    mov rdi,r8; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get; test rax,rax; jz .geke_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol; test rax,rax; jz .geke_bad
    cmp dword ptr [rax+16],GK_INPUT; jne .geke_bad
    cmp dword ptr [rax+20],GTYPE_STRING; jne .geke_bad
    mov ecx,dword ptr [rax+24]
    mov eax,ecx; call g_input_slot_addr; mov r10,rax
    mov eax,ecx; call g_input_aux_addr; mov r11,rax
    mov rdi,r10; mov rsi,r11; mov rdx,[r9+8]; mov rcx,[r9+16]; call g_emit_string_input_eq
    xor eax,eax; ret
.geke_bad: mov eax,1; ret

# Emit runtime comparison of input string pointer/len addresses against compile-time key bytes.
g_emit_string_input_eq:
    # rdi ptr-slot VA, rsi len-slot VA, rdx key ptr, rcx key len
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov rbx,rcx
    # default eax=0, load len to rdx, compare immediate, jump false
    lea rdi,[rip+gc_xor_eax]; mov esi,gc_xor_eax_end-gc_xor_eax; call g_emit_bytes
    mov rdi,r13; call g_emit_load_rax_abs
    # cmp rax, imm32 only keys <=2^31 bytes by source bound
    mov edi,0x3D48; call g_emit_u16; mov edi,ebx; call g_emit_u32
    call g_emit_jnz_patch; push rax
    mov rdi,r12; call g_emit_load_rax_abs
    xor r13d,r13d
.strcmp_loop:
    cmp r13,rbx; jae .strcmp_true
    # cmp byte ptr [rax+disp8/32], imm8
    cmp r13,127; ja .gesie_bad
    mov edi,0xB680; call g_emit_u16        # 80 b6? corrected below with explicit bytes
    # The generic byte compare encoder is patched below; fail for now if reached.
    jmp .gesie_bad
.strcmp_true:
    mov edi,1; call g_emit_mov_eax_imm
    G_EMIT_POSITION rsi
    pop rdi; call g_patch_rel32
    mov edi,0x50; call g_emit_u8
    xor eax,eax; jmp .gesie_done
.gesie_bad:
    # clean any branch pointer pushed
    add rsp,8
    mov eax,1
.gesie_done: pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- small node parser ----------------
g_parse_i64_node:
    jmp physical_parse_i64_node

# Compiler-only causal storage is sized from represented structure.  No user
# program cardinality is inferred from a fixed fragment/edge table.
g_prepare_graph_arena:
    push rbx
    mov eax,dword ptr [rip+g_symbol_capacity]
    add eax,dword ptr [rip+g_output_capacity]
    jc .gpga_fail
    test eax,eax
    jz .gpga_fail
    mov dword ptr [rip+g_fragment_capacity],eax
    mov ebx,eax

    mov rdi,[rip+g_graph_arena_ptr]
    test rdi,rdi
    jz .gpga_size
    mov rsi,[rip+g_graph_arena_bytes]
    mov eax,SYS_munmap
    syscall
.gpga_size:
    mov eax,ebx
    imul rax,rax,108              # five qword + seventeen dword fact vectors
    jo .gpga_fail
    mov ecx,dword ptr [rip+g_symbol_capacity]
    add rax,rcx
    jc .gpga_fail
    mov [rip+g_graph_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gpga_fail
    mov [rip+g_graph_arena_ptr],rax

    # Source and lifetime vectors include two qword work projections. Traffic is a
    # property of the emitted fragment itself, not a second scheduling graph.
    mov [rip+g_fragment_start_ptr],rax
    mov ecx,ebx; shl rcx,3; add rax,rcx
    mov [rip+g_fragment_end_ptr_ptr],rax
    add rax,rcx
    mov [rip+g_fragment_nodes_ptr],rax
    add rax,rcx
    mov ecx,ebx; shl rcx,2
    mov [rip+g_fragment_kind_ptr],rax; add rax,rcx
    mov [rip+g_fragment_static_ptr],rax; add rax,rcx
    mov [rip+g_fragment_memory_ops_ptr],rax; add rax,rcx
    mov [rip+g_orig_indegree_ptr],rax; add rax,rcx
    mov [rip+g_work_indegree_ptr],rax; add rax,rcx
    mov [rip+g_succ_count_ptr],rax; add rax,rcx
    mov [rip+g_sole_succ_ptr],rax; add rax,rcx
    mov [rip+g_topo_queue_ptr],rax; add rax,rcx
    mov [rip+g_topo_order_ptr],rax; add rax,rcx
    mov [rip+g_region_of_ptr],rax; add rax,rcx
    mov [rip+g_region_head_ptr],rax; add rax,rcx
    mov [rip+g_region_len_ptr],rax; add rax,rcx
    mov [rip+g_region_indegree_ptr],rax; add rax,rcx
    mov [rip+g_region_first_out_ptr],rax; add rax,rcx
    mov [rip+g_region_entry_offsets_ptr],rax; add rax,rcx
    mov [rip+g_region_realization_ptr],rax; add rax,rcx
    mov [rip+g_fragment_work_source_ptr],rax; add rax,rcx; add rax,rcx
    mov [rip+g_fragment_work_kind_ptr],rax; add rax,rcx; add rax,rcx
    mov [rip+g_dep_visit_ptr],rax

    mov dword ptr [rip+g_edge_count],0
    mov edi,ebx
    call g_prepare_edge_arena
    test eax,eax
    jnz .gpga_fail
    xor eax,eax
    pop rbx
    ret
.gpga_fail:
    mov eax,1
    pop rbx
    ret

# Original causal edges grow geometrically as relations are discovered. Growth
# is allocator policy only; it never rejects a program at a fixed relation count.
g_prepare_edge_arena:
    push rbx
    mov ebx,edi
    test ebx,ebx
    jnz .gpea_have
    mov ebx,1
.gpea_have:
    mov rdi,[rip+g_edge_u_ptr]
    test rdi,rdi
    jz .gpea_alloc
    mov rsi,[rip+g_edge_arena_bytes]
    mov eax,SYS_munmap
    syscall
    mov rdi,[rip+g_edge_v_ptr]
    mov rsi,[rip+g_edge_arena_bytes]
    mov eax,SYS_munmap
    syscall
    mov rdi,[rip+g_edge_transfer_ptr]
    test rdi,rdi
    jz .gpea_alloc
    mov rsi,[rip+g_edge_transfer_arena_bytes]
    mov eax,SYS_munmap
    syscall
.gpea_alloc:
    mov eax,ebx
    shl rax,2
    mov [rip+g_edge_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE; mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .gpea_fail
    mov [rip+g_edge_u_ptr],rax
    mov rsi,[rip+g_edge_arena_bytes]
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE; mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .gpea_fail
    mov [rip+g_edge_v_ptr],rax
    mov eax,ebx
    shl rax,3
    mov [rip+g_edge_transfer_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE; mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .gpea_fail
    mov [rip+g_edge_transfer_ptr],rax
    mov dword ptr [rip+g_edge_capacity],ebx
    xor eax,eax; pop rbx; ret
.gpea_fail:
    mov eax,1; pop rbx; ret

g_grow_edge_arena:
    push rbx
    push r12
    mov ebx,dword ptr [rip+g_edge_capacity]
    test ebx,ebx; jz .ggea_fail
    mov eax,ebx
    add eax,eax
    jc .ggea_fail
    mov r12d,eax
    mov rsi,[rip+g_edge_arena_bytes]
    mov rdx,r12
    shl rdx,2
    mov rdi,[rip+g_edge_u_ptr]
    mov eax,SYS_mremap
    mov r10d,MREMAP_MAYMOVE
    syscall
    test rax,rax; js .ggea_fail
    mov [rip+g_edge_u_ptr],rax
    mov rsi,[rip+g_edge_arena_bytes]
    mov rdx,r12
    shl rdx,2
    mov rdi,[rip+g_edge_v_ptr]
    mov eax,SYS_mremap
    mov r10d,MREMAP_MAYMOVE
    syscall
    test rax,rax; js .ggea_fail
    mov [rip+g_edge_v_ptr],rax
    mov rsi,[rip+g_edge_transfer_arena_bytes]
    mov rdx,r12
    shl rdx,3
    mov rdi,[rip+g_edge_transfer_ptr]
    mov eax,SYS_mremap
    mov r10d,MREMAP_MAYMOVE
    syscall
    test rax,rax; js .ggea_fail
    mov [rip+g_edge_transfer_ptr],rax
    mov rax,r12; shl rax,2
    mov [rip+g_edge_arena_bytes],rax
    mov rax,r12; shl rax,3
    mov [rip+g_edge_transfer_arena_bytes],rax
    mov dword ptr [rip+g_edge_capacity],r12d
    xor eax,eax; pop r12; pop rbx; ret
.ggea_fail:
    mov eax,1; pop r12; pop rbx; ret

# edi=src fragment, esi=dst fragment -> eax=0 success, ecx=edge index. Duplicate
# relations collapse here. The returned edge identity lets semantic references
# accumulate one Physical Edge transfer fact without a second dependency graph.
g_edge_add_unique:
    push rbx; push r12; push r13
    mov r12d,edi; mov r13d,esi
    cmp r12d,dword ptr [rip+g_fragment_capacity]; jae .geau_fail
    cmp r13d,dword ptr [rip+g_fragment_capacity]; jae .geau_fail
    xor ebx,ebx
.geau_scan:
    cmp ebx,dword ptr [rip+g_edge_count]; jae .geau_append
    mov rax,[rip+g_edge_u_ptr]
    cmp dword ptr [rax+rbx*4],r12d; jne .geau_next
    mov rax,[rip+g_edge_v_ptr]
    cmp dword ptr [rax+rbx*4],r13d; jne .geau_next
    mov ecx,ebx
    jmp .geau_ok
.geau_next:
    inc ebx; jmp .geau_scan
.geau_append:
    mov eax,dword ptr [rip+g_edge_count]
    cmp eax,dword ptr [rip+g_edge_capacity]
    jb .geau_room
    call g_grow_edge_arena
    test eax,eax; jnz .geau_fail
    mov eax,dword ptr [rip+g_edge_count]
.geau_room:
    mov ecx,eax
    mov rdx,[rip+g_edge_u_ptr]; mov [rdx+rax*4],r12d
    mov rdx,[rip+g_edge_v_ptr]; mov [rdx+rax*4],r13d
    mov rdx,[rip+g_edge_transfer_ptr]; mov qword ptr [rdx+rax*8],0
    inc dword ptr [rip+g_edge_count]
.geau_ok:
    xor eax,eax; jmp .geau_done
.geau_fail:
    mov eax,1
.geau_done:
    pop r13; pop r12; pop rbx; ret

# edi=semantic GTYPE, esi=edge index. Accumulate a represented payload lower
# bound for this true dependency. Rank-N precision carries its byte width
# directly; unsupported/non-scalar payloads saturate to unknown rather than
# inventing a transport size. This is a Physical Edge Fact, not an execution
# count and not a device-offload heuristic.
g_edge_accumulate_type_transfer:
    cmp esi,dword ptr [rip+g_edge_count]
    jae .geatt_done
    mov r8,[rip+g_edge_transfer_ptr]
    mov rax,qword ptr [r8+rsi*8]
    cmp rax,-1
    je .geatt_done
    mov edx,8
    cmp edi,GTYPE_F32
    je .geatt_f32
    cmp edi,GTYPE_BOOL
    je .geatt_bool
    push rdi
    call g_is_rankn_fp
    pop rdi
    test eax,eax
    jnz .geatt_rankn
    cmp edi,GTYPE_I64
    je .geatt_add
    cmp edi,GTYPE_U64
    je .geatt_add
    cmp edi,GTYPE_F64
    je .geatt_add
    jmp .geatt_unknown
.geatt_f32:
    mov edx,4
    jmp .geatt_add
.geatt_bool:
    mov edx,1
    jmp .geatt_add
.geatt_rankn:
    push rax
    call g_float_precision
    mov rdx,rax
    pop rax
    test rdx,rdx
    jz .geatt_unknown
    add rdx,7
    jc .geatt_unknown
    shr rdx,3
    test rdx,rdx
    jz .geatt_unknown
.geatt_add:
    add rax,rdx
    jc .geatt_unknown
    mov qword ptr [r8+rsi*8],rax
    ret
.geatt_unknown:
    mov qword ptr [r8+rsi*8],-1
.geatt_done:
    ret

# Condensed-region edges are a subset of original edges, so the completed
# original relation count is an exact upper bound for this compile-time arena.
g_prepare_region_edge_arena:
    push rbx
    mov ebx,dword ptr [rip+g_edge_count]
    test ebx,ebx; jnz .gpre_have
    mov ebx,1
.gpre_have:
    mov rdi,[rip+g_region_edge_arena_ptr]
    test rdi,rdi; jz .gpre_alloc
    mov rsi,[rip+g_region_edge_arena_bytes]
    mov eax,SYS_munmap; syscall
.gpre_alloc:
    mov eax,ebx
    imul rax,rax,24
    jo .gpre_fail
    mov [rip+g_region_edge_arena_bytes],rax
    mov rsi,rax
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE; mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .gpre_fail
    mov [rip+g_region_edge_arena_ptr],rax
    mov [rip+g_region_edge_u_ptr],rax
    mov ecx,ebx; shl rcx,2; add rax,rcx
    mov [rip+g_region_edge_v_ptr],rax
    add rax,rcx
    mov [rip+g_region_next_edge_ptr],rax
    # Keep one dword-width pad so the qword Physical Edge transfer vector is
    # naturally aligned after four dword vectors. The pad has no authority.
    add rax,rcx
    add rax,rcx
    mov [rip+g_region_edge_transfer_ptr],rax
    mov dword ptr [rip+g_region_edge_capacity],ebx
    xor eax,eax; pop rbx; ret
.gpre_fail:
    mov eax,1; pop rbx; ret

# ---------------- native blind-release physicalizer ----------------
# These routines run only at AOT compile time.  They derive causality directly
# from the already parsed semantic DOM and preserve the runtime contract:
# finite region -> true dependency publication -> return.  The releaser never
# selects or queries a resource consumer.

g_fragment_begin:
    mov dword ptr [rip+g_current_loop_work_ticks],0
    # rdi=semantic node, esi=1 binding / 2 output
    mov dword ptr [rip+g_current_fragment_memory_ops],0
    mov dword ptr [rip+g_fragment_emit_open],1
    mov eax,dword ptr [rip+g_fragment_count]
    cmp eax,dword ptr [rip+g_fragment_capacity]
    jae .gfb_fail
    mov ecx,eax
    mov rdx,[rip+g_fragment_start_ptr]
    G_EMIT_POSITION r8
    mov [rdx+rcx*8],r8
    mov rdx,[rip+g_fragment_nodes_ptr]
    mov [rdx+rcx*8],rdi
    mov rdx,[rip+g_fragment_kind_ptr]
    mov [rdx+rcx*4],esi
    xor eax,eax
    ret
.gfb_fail:
    mov eax,1
    ret

g_fragment_finish:
    mov eax,dword ptr [rip+g_fragment_count]
    cmp eax,dword ptr [rip+g_fragment_capacity]
    jae .gfe_fail
    mov ecx,eax
    mov rdx,[rip+g_fragment_end_ptr_ptr]
    G_EMIT_POSITION r8
    mov [rdx+rcx*8],r8
    mov rdx,[rip+g_fragment_memory_ops_ptr]
    mov r8d,dword ptr [rip+g_current_fragment_memory_ops]
    mov [rdx+rcx*4],r8d
    mov dword ptr [rip+g_fragment_emit_open],0
    call g_fragment_work_fact
    inc dword ptr [rip+g_fragment_count]
    xor eax,eax
    ret
.gfe_fail:
    mov eax,1
    ret

# rdi=symbol pointer -> eax=fragment index, edx=0; edx=1 if structural/nonmaterialized.
g_fragment_for_symbol:
    push rbx
    mov rbx,[rdi+32]
    xor ecx,ecx
.gffs_loop:
    cmp ecx,dword ptr [rip+g_fragment_count]
    jae .gffs_no
    mov rax,[rip+g_fragment_kind_ptr]
    cmp dword ptr [rax+rcx*4],1
    jne .gffs_next
    mov rax,[rip+g_fragment_nodes_ptr]
    cmp qword ptr [rax+rcx*8],rbx
    je .gffs_yes
.gffs_next:
    inc ecx
    jmp .gffs_loop
.gffs_yes:
    mov eax,ecx
    xor edx,edx
    pop rbx
    ret
.gffs_no:
    xor eax,eax
    mov edx,1
    pop rbx
    ret

# rdi=name ptr, rsi=len, edx=current fragment, ecx=depth.
g_collect_ref_span:
    push rbx
    push r12
    push r13
    push r14
    mov r12d,edx
    mov r13d,ecx
    call g_find_symbol
    test rax,rax
    jz .gcr_done
    mov rdi,rax
    call g_semantic_resolve_symbol
    test rax,rax
    jz .gcr_done
    mov rbx,rax
    mov eax,dword ptr [rbx+16]
    cmp eax,GK_INPUT
    je .gcr_done
    cmp eax,GK_COMPUTE
    je .gcr_materialized
    cmp eax,GK_REDUCE
    je .gcr_materialized
    cmp eax,GK_ITERATE
    je .gcr_materialized
    cmp eax,GK_NESTED_REDUCE
    je .gcr_materialized
    cmp eax,GK_MAP
    je .gcr_structural
    cmp eax,GK_RECORD
    je .gcr_structural
    cmp eax,GK_DICTIONARY
    je .gcr_structural
    cmp eax,GK_NESTED_LITERAL
    je .gcr_structural
    jmp .gcr_done
.gcr_materialized:
    mov rdi,rbx
    call g_fragment_for_symbol
    test edx,edx
    jnz .gcr_done
    cmp eax,r12d
    je .gcr_done
    mov edi,eax
    mov esi,r12d
    call g_edge_add_unique
    test eax,eax
    jnz .gcr_cycle
    mov esi,ecx
    mov edi,dword ptr [rbx+20]
    call g_edge_accumulate_type_transfer
    jmp .gcr_done
.gcr_structural:
    # Structural expansion is guarded by the actual symbol identity set rather
    # than a two-qword 128-symbol visit mask.
    mov r14,[rip+g_symbols_ptr]
    mov rax,rbx
    sub rax,r14
    shr rax,6
    cmp eax,dword ptr [rip+g_symbol_count]
    jae .gcr_cycle
    mov rcx,[rip+g_dep_visit_ptr]
    cmp byte ptr [rcx+rax],0
    jne .gcr_cycle
    mov byte ptr [rcx+rax],1
    push rax
    mov rdi,[rbx+32]
    mov esi,r12d
    lea edx,[r13d+1]
    call g_collect_deps_node
    pop rax
    mov rcx,[rip+g_dep_visit_ptr]
    mov byte ptr [rcx+rax],0
    jmp .gcr_done
.gcr_cycle:
    mov dword ptr [rip+g_parallel_error],1
.gcr_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# rdi=JSON node, esi=current fragment, edx=depth.
g_collect_deps_node:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx,rdi
    mov r12d,esi
    mov r13d,edx
    test rbx,rbx
    jz .gcdn_done
    # DOM recursion is bounded by the represented tree and the host call stack;
    # no independent semantic depth number is imposed here.
    mov rax,[rbx]
    cmp rax,J_OBJECT
    je .gcdn_obj
    cmp rax,J_ARRAY
    je .gcdn_arr
    jmp .gcdn_done
.gcdn_obj:
    # Structural field dependencies must follow the represented owner. Static
    # records recurse into their old expression; iterate fields point directly
    # at the producing recurrence fragment and carry the projected scalar type.
    mov rdi,rbx; lea rsi,[rip+gk_field]; mov edx,gk_field_end-gk_field; call obj_get
    test rax,rax; jz .gcdn_obj_plain
    cmp qword ptr [rax],J_OBJECT; jne .gcdn_bad
    mov r15,rax
    mov rdi,r15; call g_resolve_field_expr
    test rax,rax; jz .gcdn_field_iterate
    mov rdi,rax; mov esi,r12d; lea edx,[r13d+1]; call g_collect_deps_node
    jmp .gcdn_done
.gcdn_field_iterate:
    mov rdi,r15; call g_iter_field_info
    test rax,rax; jz .gcdn_bad
    mov r14,rax; mov r15d,ecx
    mov rdi,r14; call g_fragment_for_symbol
    test edx,edx; jnz .gcdn_bad
    cmp eax,r12d; je .gcdn_done
    mov edi,eax; mov esi,r12d; call g_edge_add_unique
    test eax,eax; jnz .gcdn_bad
    mov edi,r15d; mov esi,r13d; call g_edge_accumulate_type_transfer
    jmp .gcdn_done
.gcdn_obj_plain:
    mov r14,[rbx+24]
.gcdn_obj_loop:
    test r14,r14
    jz .gcdn_done
    # A reference is semantic only for the canonical ref-bearing keys.  This
    # deliberately ignores declaration names, operator names, labels and types.
    xor r15d,r15d
    mov rdi,[r14+40]; mov rsi,[r14+48]; lea rdx,[rip+gk_var]; mov ecx,gk_var_end-gk_var; call span_eq
    test eax,eax; jnz .gcdn_ref
    mov rdi,[r14+40]; mov rsi,[r14+48]; lea rdx,[rip+gk_load]; mov ecx,gk_load_end-gk_load; call span_eq
    test eax,eax; jnz .gcdn_ref
    mov rdi,[r14+40]; mov rsi,[r14+48]; lea rdx,[rip+gk_value]; mov ecx,gk_value_end-gk_value; call span_eq
    test eax,eax; jnz .gcdn_ref
    mov rdi,[r14+40]; mov rsi,[r14+48]; lea rdx,[rip+gk_base]; mov ecx,gk_base_end-gk_base; call span_eq
    test eax,eax; jnz .gcdn_ref
    mov rdi,[r14+40]; mov rsi,[r14+48]; lea rdx,[rip+gk_source_ref]; mov ecx,gk_source_ref_end-gk_source_ref; call span_eq
    test eax,eax; jnz .gcdn_ref
    mov rdi,[r14+40]; mov rsi,[r14+48]; lea rdx,[rip+gk_target_ref]; mov ecx,gk_target_ref_end-gk_target_ref; call span_eq
    test eax,eax; jz .gcdn_recurse
.gcdn_ref:
    cmp qword ptr [r14],J_STRING
    jne .gcdn_recurse
    mov rdi,[r14+8]
    mov rsi,[r14+16]
    mov edx,r12d
    mov ecx,r13d
    call g_collect_ref_span
.gcdn_recurse:
    mov rdi,r14
    mov esi,r12d
    lea edx,[r13d+1]
    call g_collect_deps_node
    cmp dword ptr [rip+g_parallel_error],0
    jne .gcdn_done
    mov r14,[r14+32]
    jmp .gcdn_obj_loop
.gcdn_arr:
    mov r14,[rbx+24]
.gcdn_arr_loop:
    test r14,r14
    jz .gcdn_done
    mov rdi,r14
    mov esi,r12d
    lea edx,[r13d+1]
    call g_collect_deps_node
    cmp dword ptr [rip+g_parallel_error],0
    jne .gcdn_done
    mov r14,[r14+32]
    jmp .gcdn_arr_loop
.gcdn_bad:
    mov dword ptr [rip+g_parallel_error],1
.gcdn_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Build original causal edges and topological order from explicit relation facts.
# Physical-reuse edges may already have been recorded during code emission;
# source-visible dependencies are merged into the same deduplicated relation set.
g_build_causal_graph:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword ptr [rip+g_parallel_error],0
    mov rdi,[rip+g_orig_indegree_ptr]; xor eax,eax; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_work_indegree_ptr]; xor eax,eax; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_succ_count_ptr]; xor eax,eax; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_sole_succ_ptr]; mov eax,-1; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_dep_visit_ptr]; xor eax,eax; mov ecx,dword ptr [rip+g_symbol_count]; rep stosb

    xor ebx,ebx
.gbcg_collect:
    cmp ebx,dword ptr [rip+g_fragment_count]
    jae .gbcg_edges
    mov rax,[rip+g_fragment_nodes_ptr]
    mov rdi,[rax+rbx*8]
    mov esi,ebx
    xor edx,edx
    call g_collect_deps_node
    cmp dword ptr [rip+g_parallel_error],0
    jne .gbcg_fail
    inc ebx
    jmp .gbcg_collect

.gbcg_edges:
    # Convert the completed relation set into indegree/successor facts once.
    xor r13d,r13d
.gbcg_edge_facts:
    cmp r13d,dword ptr [rip+g_edge_count]
    jae .gbcg_topo_init
    mov rax,[rip+g_edge_u_ptr]; mov r15d,[rax+r13*4]
    mov rax,[rip+g_edge_v_ptr]; mov r12d,[rax+r13*4]
    cmp r15d,dword ptr [rip+g_fragment_count]; jae .gbcg_fail
    cmp r12d,dword ptr [rip+g_fragment_count]; jae .gbcg_fail
    mov rax,[rip+g_orig_indegree_ptr]; inc dword ptr [rax+r12*4]
    mov rax,[rip+g_work_indegree_ptr]; inc dword ptr [rax+r12*4]
    mov rax,[rip+g_succ_count_ptr]; inc dword ptr [rax+r15*4]
    mov rax,[rip+g_sole_succ_ptr]; mov [rax+r15*4],r12d
    inc r13d
    jmp .gbcg_edge_facts

.gbcg_topo_init:
    xor r12d,r12d                 # queue tail
    xor r13d,r13d                 # node scan
.gbcg_seed:
    cmp r13d,dword ptr [rip+g_fragment_count]
    jae .gbcg_topo_run
    mov rax,[rip+g_work_indegree_ptr]
    cmp dword ptr [rax+r13*4],0
    jne .gbcg_seed_next
    mov rax,[rip+g_topo_queue_ptr]
    mov [rax+r12*4],r13d
    inc r12d
.gbcg_seed_next:
    inc r13d
    jmp .gbcg_seed
.gbcg_topo_run:
    xor ebx,ebx                    # queue head
    xor r14d,r14d                  # order count
.gbcg_pop:
    cmp ebx,r12d
    jae .gbcg_topo_done
    mov rax,[rip+g_topo_queue_ptr]
    mov r15d,[rax+rbx*4]
    inc ebx
    mov rax,[rip+g_topo_order_ptr]
    mov [rax+r14*4],r15d
    inc r14d
    xor r13d,r13d                  # edge scan
.gbcg_dec_edges:
    cmp r13d,dword ptr [rip+g_edge_count]
    jae .gbcg_pop
    mov rax,[rip+g_edge_u_ptr]
    cmp dword ptr [rax+r13*4],r15d
    jne .gbcg_dec_next
    mov rax,[rip+g_edge_v_ptr]
    mov ecx,[rax+r13*4]
    mov rax,[rip+g_work_indegree_ptr]
    sub dword ptr [rax+rcx*4],1
    jne .gbcg_dec_next
    mov rax,[rip+g_topo_queue_ptr]
    mov [rax+r12*4],ecx
    inc r12d
.gbcg_dec_next:
    inc r13d
    jmp .gbcg_dec_edges
.gbcg_topo_done:
    cmp r14d,dword ptr [rip+g_fragment_count]
    jne .gbcg_fail
    xor eax,eax
    jmp .gbcg_done
.gbcg_fail:
    mov eax,1
.gbcg_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Contract only u->v where outdegree(u)==1 and indegree(v)==1.
g_build_regions:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi,[rip+g_region_of_ptr]; mov eax,-1; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_region_head_ptr]; mov eax,-1; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_region_len_ptr]; xor eax,eax; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov dword ptr [rip+g_region_count],0
    xor ebx,ebx
.gbr_order:
    cmp ebx,dword ptr [rip+g_fragment_count]
    jae .gbr_edges
    mov rax,[rip+g_topo_order_ptr]
    mov r12d,[rax+rbx*4]
    inc ebx
    mov rax,[rip+g_region_of_ptr]
    cmp dword ptr [rax+r12*4],-1
    jne .gbr_order
    mov r13d,dword ptr [rip+g_region_count]
    cmp r13d,dword ptr [rip+g_fragment_count]
    jae .gbr_fail
    mov rax,[rip+g_region_head_ptr]
    mov [rax+r13*4],r12d
    xor r14d,r14d
.gbr_chain:
    mov rax,[rip+g_region_of_ptr]
    mov [rax+r12*4],r13d
    inc r14d
    mov rax,[rip+g_succ_count_ptr]
    cmp dword ptr [rax+r12*4],1
    jne .gbr_chain_end
    mov rax,[rip+g_sole_succ_ptr]
    mov r15d,[rax+r12*4]
    cmp r15d,-1
    je .gbr_chain_end
    mov rax,[rip+g_orig_indegree_ptr]
    cmp dword ptr [rax+r15*4],1
    jne .gbr_chain_end
    mov rax,[rip+g_region_of_ptr]
    cmp dword ptr [rax+r15*4],-1
    jne .gbr_chain_end
    mov r12d,r15d
    jmp .gbr_chain
.gbr_chain_end:
    mov rax,[rip+g_region_len_ptr]
    mov [rax+r13*4],r14d
    inc dword ptr [rip+g_region_count]
    jmp .gbr_order

.gbr_edges:
    call g_prepare_region_edge_arena
    test eax,eax; jnz .gbr_fail
    mov dword ptr [rip+g_region_edge_count],0
    mov rdi,[rip+g_region_indegree_ptr]; xor eax,eax; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_region_first_out_ptr]; mov eax,-1; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    xor ebx,ebx
.gbr_edge_scan:
    cmp ebx,dword ptr [rip+g_edge_count]
    jae .gbr_sort_edges
    mov rax,[rip+g_edge_u_ptr]; mov r12d,[rax+rbx*4]
    mov rax,[rip+g_edge_v_ptr]; mov r13d,[rax+rbx*4]
    mov rax,[rip+g_edge_transfer_ptr]; mov r11,[rax+rbx*8]
    mov rax,[rip+g_region_of_ptr]; mov r12d,[rax+r12*4]; mov r13d,[rax+r13*4]
    cmp r12d,r13d
    je .gbr_edge_next
    # Deduplicate region edges.
    xor r14d,r14d
.gbr_dup:
    cmp r14d,dword ptr [rip+g_region_edge_count]
    jae .gbr_add_region_edge
    mov rax,[rip+g_region_edge_u_ptr]; cmp dword ptr [rax+r14*4],r12d; jne .gbr_dup_next
    mov rax,[rip+g_region_edge_v_ptr]; cmp dword ptr [rax+r14*4],r13d; jne .gbr_dup_next
    mov rax,[rip+g_region_edge_transfer_ptr]
    mov rcx,qword ptr [rax+r14*8]
    cmp rcx,-1
    je .gbr_edge_next
    cmp r11,-1
    je .gbr_dup_unknown
    add rcx,r11
    jc .gbr_dup_unknown
    mov qword ptr [rax+r14*8],rcx
    jmp .gbr_edge_next
.gbr_dup_unknown:
    mov qword ptr [rax+r14*8],-1
    jmp .gbr_edge_next
.gbr_dup_next:
    inc r14d
    jmp .gbr_dup
.gbr_add_region_edge:
    mov r14d,dword ptr [rip+g_region_edge_count]
    cmp r14d,dword ptr [rip+g_region_edge_capacity]
    jae .gbr_fail
    mov rax,[rip+g_region_edge_u_ptr]; mov [rax+r14*4],r12d
    mov rax,[rip+g_region_edge_v_ptr]; mov [rax+r14*4],r13d
    mov rax,[rip+g_region_edge_transfer_ptr]; mov qword ptr [rax+r14*8],r11
    mov rax,[rip+g_region_indegree_ptr]; inc dword ptr [rax+r13*4]
    mov rax,[rip+g_region_first_out_ptr]; mov r15d,[rax+r12*4]
    mov rax,[rip+g_region_next_edge_ptr]; mov [rax+r14*4],r15d
    mov rax,[rip+g_region_first_out_ptr]; mov [rax+r12*4],r14d
    inc dword ptr [rip+g_region_edge_count]
.gbr_edge_next:
    inc ebx
    jmp .gbr_edge_scan
.gbr_sort_edges:
    # Deterministic AOT geometry: lexicographic (region_u,region_v), matching the
    # canonical causal-set order rather than discovery order.
    xor r12d,r12d
.gbr_sort_i:
    mov eax,dword ptr [rip+g_region_edge_count]
    cmp r12d,eax
    jae .gbr_rebuild
    mov r13d,r12d
    inc r13d
.gbr_sort_j:
    cmp r13d,dword ptr [rip+g_region_edge_count]
    jae .gbr_sort_next_i
    mov rax,[rip+g_region_edge_u_ptr]; mov r14d,[rax+r12*4]; mov r15d,[rax+r13*4]
    cmp r15d,r14d
    jb .gbr_swap
    ja .gbr_sort_j_next
    mov rax,[rip+g_region_edge_v_ptr]; mov r14d,[rax+r12*4]; mov r15d,[rax+r13*4]
    cmp r15d,r14d
    jae .gbr_sort_j_next
.gbr_swap:
    mov rax,[rip+g_region_edge_u_ptr]
    mov r14d,[rax+r12*4]; mov r15d,[rax+r13*4]
    mov [rax+r12*4],r15d; mov [rax+r13*4],r14d
    mov rax,[rip+g_region_edge_v_ptr]
    mov r14d,[rax+r12*4]; mov r15d,[rax+r13*4]
    mov [rax+r12*4],r15d; mov [rax+r13*4],r14d
    mov rax,[rip+g_region_edge_transfer_ptr]
    mov r14,qword ptr [rax+r12*8]; mov r15,qword ptr [rax+r13*8]
    mov qword ptr [rax+r12*8],r15; mov qword ptr [rax+r13*8],r14
.gbr_sort_j_next:
    inc r13d
    jmp .gbr_sort_j
.gbr_sort_next_i:
    inc r12d
    jmp .gbr_sort_i
.gbr_rebuild:
    mov rdi,[rip+g_region_indegree_ptr]; xor eax,eax; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    mov rdi,[rip+g_region_first_out_ptr]; mov eax,-1; mov ecx,dword ptr [rip+g_fragment_count]; rep stosd
    xor r12d,r12d
.gbr_rebuild_loop:
    cmp r12d,dword ptr [rip+g_region_edge_count]
    jae .gbr_ok
    mov rax,[rip+g_region_edge_u_ptr]; mov r13d,[rax+r12*4]
    mov rax,[rip+g_region_edge_v_ptr]; mov r14d,[rax+r12*4]
    mov rax,[rip+g_region_indegree_ptr]; inc dword ptr [rax+r14*4]
    mov rax,[rip+g_region_first_out_ptr]; mov r15d,[rax+r13*4]
    mov rax,[rip+g_region_next_edge_ptr]; mov [rax+r12*4],r15d
    mov rax,[rip+g_region_first_out_ptr]; mov [rax+r13*4],r12d
    inc r12d
    jmp .gbr_rebuild_loop
.gbr_ok:
    xor eax,eax
    jmp .gbr_done
.gbr_fail:
    mov eax,1
.gbr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


# 1.2.12 Causal Mesh Coarsening proof gate.
# Re-walk every materialized region before code emission.  A region is valid
# only if it is an exact chain whose every internal edge preserves the original
# outdegree==1 / indegree==1 contraction contract.  Forks and joins therefore
# remain physical frontiers; no parallel width can be hidden inside a region.
g_verify_causal_mesh:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12d,r12d                 # region id
    xor r15d,r15d                 # total verified fragments
.gvcm_region:
    cmp r12d,dword ptr [rip+g_region_count]
    jae .gvcm_total
    mov rax,[rip+g_region_head_ptr]
    mov r13d,[rax+r12*4]
    cmp r13d,0
    jl .gvcm_fail
    cmp r13d,dword ptr [rip+g_fragment_count]
    jae .gvcm_fail
    mov rax,[rip+g_region_len_ptr]
    mov r14d,[rax+r12*4]
    test r14d,r14d
    jz .gvcm_fail
.gvcm_member:
    mov rax,[rip+g_region_of_ptr]
    cmp dword ptr [rax+r13*4],r12d
    jne .gvcm_fail
    inc r15d
    dec r14d
    jz .gvcm_next_region

    # Every edge hidden inside a physical region must be a one-to-one causal
    # continuation.  This is the hard no-hidden-serialism boundary.
    mov rax,[rip+g_succ_count_ptr]
    cmp dword ptr [rax+r13*4],1
    jne .gvcm_fail
    mov rax,[rip+g_sole_succ_ptr]
    mov ebx,[rax+r13*4]
    cmp ebx,0
    jl .gvcm_fail
    cmp ebx,dword ptr [rip+g_fragment_count]
    jae .gvcm_fail
    mov rax,[rip+g_orig_indegree_ptr]
    cmp dword ptr [rax+rbx*4],1
    jne .gvcm_fail
    mov r13d,ebx
    jmp .gvcm_member

.gvcm_next_region:
    inc r12d
    jmp .gvcm_region

.gvcm_total:
    cmp r15d,dword ptr [rip+g_fragment_count]
    jne .gvcm_fail
    xor eax,eax
    jmp .gvcm_done
.gvcm_fail:
    mov eax,1
.gvcm_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Copy template + fused fragment regions into g_parallel_code and patch runtime tables.
# Close one proved Region DAG against x86 plus an externally proved fabric
# domain. This is deterministic compile-time coordinate descent on one physical
# cost: Region work versus fabric compute/activation plus Physical Edge crossing
# cost. Every accepted flip strictly lowers the same finite binary-domain energy,
# so convergence needs no round limit or workload threshold. The plan is metadata
# only until a fabric activation emitter exists; normal production facts are zero.
g_close_heterogeneous_placement:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rdi,[rip+g_region_realization_ptr]
    mov eax,SR_REALIZATION_X86_ISA
    mov ecx,dword ptr [rip+g_region_count]
    rep stosd

    call fabric_target_facts_proved
    test eax,eax
    jz .gchp_ok

    # work_ticks[] lives after indegree/first_out/entry_offsets in the compact
    # metadata already populated while materializing each Region body.
    mov r15,[rip+g_parallel_code_ptr]
    add r15,GR_TEMPLATE_SIZE
    mov eax,dword ptr [rip+g_region_count]
    lea rcx,[rax+rax*2]
    lea r15,[r15+rcx*4]

.gchp_pass:
    xor ebp,ebp                      # changed
    xor ebx,ebx                      # Region id
.gchp_region:
    cmp ebx,dword ptr [rip+g_region_count]
    jae .gchp_pass_done

    # Static fabric placement has no invocation bound consumer. A finite base
    # is not proof that a Region with an iterative term is one-shot work.
    call g_region_work_fact_ptr
    cmp dword ptr [rax+12],0; jne .gchp_next_region
    mov eax,dword ptr [r15+rbx*4]
    cmp eax,-1                       # dynamic/unbounded stays on ISA
    je .gchp_next_region
    mov r12,rax                      # x86 unary cost

    # fabric unary cost = ceil(work*num/den) + activation.
    mov rax,r12
    mul qword ptr [rip+ft_compute_ticks_num]
    test rdx,rdx
    jnz .gchp_fabric_inf
    mov rcx,qword ptr [rip+ft_compute_ticks_den]
    mov r8,rcx
    dec r8
    add rax,r8
    jc .gchp_fabric_inf
    xor edx,edx
    div rcx
    add rax,qword ptr [rip+ft_activation_ticks]
    jc .gchp_fabric_inf
    mov r13,rax
    jmp .gchp_edges_init
.gchp_fabric_inf:
    mov r13,-1

.gchp_edges_init:
    xor r14d,r14d
.gchp_edges:
    cmp r14d,dword ptr [rip+g_region_edge_count]
    jae .gchp_choose

    mov rax,[rip+g_region_edge_u_ptr]
    mov r9d,dword ptr [rax+r14*4]
    cmp r9d,ebx
    je .gchp_neighbor_v
    mov rax,[rip+g_region_edge_v_ptr]
    cmp dword ptr [rax+r14*4],ebx
    jne .gchp_edge_next
    mov rax,[rip+g_region_edge_u_ptr]
    mov r9d,dword ptr [rax+r14*4]
    jmp .gchp_have_neighbor
.gchp_neighbor_v:
    mov rax,[rip+g_region_edge_v_ptr]
    mov r9d,dword ptr [rax+r14*4]
.gchp_have_neighbor:
    cmp r9d,dword ptr [rip+g_region_count]
    jae .gchp_fail
    mov rax,[rip+g_region_realization_ptr]
    mov r11d,dword ptr [rax+r9*4]
    cmp r11d,SR_REALIZATION_X86_ISA
    je .gchp_neighbor_x86
    cmp r11d,SR_REALIZATION_RECONFIGURABLE_FABRIC
    jne .gchp_fail

    # Neighbor is fabric: only the x86 candidate crosses this edge.
    mov rax,[rip+g_region_edge_transfer_ptr]
    mov rax,qword ptr [rax+r14*8]
    cmp rax,-1
    je .gchp_x86_inf
    mul qword ptr [rip+ft_transport_ticks_per_byte]
    test rdx,rdx
    jnz .gchp_x86_inf
    add rax,qword ptr [rip+ft_transport_fixed_ticks]
    jc .gchp_x86_inf
    add r12,rax
    jc .gchp_x86_inf
    jmp .gchp_edge_next
.gchp_x86_inf:
    mov r12,-1
    jmp .gchp_edge_next

.gchp_neighbor_x86:
    # Neighbor is x86: only the fabric candidate crosses this edge.
    mov rax,[rip+g_region_edge_transfer_ptr]
    mov rax,qword ptr [rax+r14*8]
    cmp rax,-1
    je .gchp_set_fabric_inf
    mul qword ptr [rip+ft_transport_ticks_per_byte]
    test rdx,rdx
    jnz .gchp_set_fabric_inf
    add rax,qword ptr [rip+ft_transport_fixed_ticks]
    jc .gchp_set_fabric_inf
    cmp r13,-1
    je .gchp_edge_next
    add r13,rax
    jc .gchp_set_fabric_inf
    jmp .gchp_edge_next
.gchp_set_fabric_inf:
    mov r13,-1
.gchp_edge_next:
    inc r14d
    jmp .gchp_edges

.gchp_choose:
    mov rax,[rip+g_region_realization_ptr]
    mov edx,dword ptr [rax+rbx*4]   # current, retained on exact tie
    mov ecx,edx

    cmp r13,-1
    je .gchp_consider_x86
    cmp r12,-1
    je .gchp_choose_fabric
    cmp r13,r12
    jb .gchp_choose_fabric
.gchp_consider_x86:
    cmp r12,-1
    je .gchp_keep
    cmp r13,-1
    je .gchp_choose_x86
    cmp r12,r13
    jb .gchp_choose_x86
    jmp .gchp_keep
.gchp_choose_fabric:
    mov ecx,SR_REALIZATION_RECONFIGURABLE_FABRIC
    jmp .gchp_commit
.gchp_choose_x86:
    mov ecx,SR_REALIZATION_X86_ISA
.gchp_commit:
    cmp ecx,edx
    je .gchp_next_region
    mov dword ptr [rax+rbx*4],ecx
    mov ebp,1
    jmp .gchp_next_region
.gchp_keep:
.gchp_next_region:
    inc ebx
    jmp .gchp_region

.gchp_pass_done:
    test ebp,ebp
    jnz .gchp_pass
.gchp_ok:
    xor eax,eax
    jmp .gchp_done
.gchp_fail:
    mov eax,1
.gchp_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# Serialize one compact target descriptor for each already-closed Region.
# Layout (48 bytes):
#   +0  u32 region_id
#   +4  u32 realization_tag
#   +8  u64 work_ticks (UINT64_MAX for dynamic/unbounded)
#   +16 u64 incident_transfer_bytes (UINT64_MAX on unknown/overflow)
#   +24 u64 shared_completion_entry_offset
#   +32 u64 incident_edge_count
#   +40 u64 descriptor_format (=1)
# This is a projection of the existing Physical DAG. No operation is duplicated
# and no target-owned graph is created.
g_emit_fabric_realization_descriptors:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15,[rip+g_parallel_code_ptr]
    add r15,GR_TEMPLATE_SIZE
    mov eax,dword ptr [rip+g_region_count]
    mov r12,rax
    mov edx,dword ptr [rip+g_region_edge_count]
    mov r13,rdx
    # descriptor base = metadata + 20*N + 16*E.
    mov rax,r12
    imul rax,rax,20
    lea r14,[r15+rax]
    mov rax,r13
    shl rax,4
    add r14,rax

    # work_ticks base = metadata + 12*N.
    mov rax,r12
    imul rax,rax,12
    lea rbp,[r15+rax]

    xor ebx,ebx
    xor r11d,r11d                    # proved fabric Region count
.gefrd_node:
    cmp rbx,r12
    jae .gefrd_patch_count
    mov rax,rbx
    imul rax,rax,48
    lea r10,[r14+rax]
    mov dword ptr [r10],ebx
    mov rax,[rip+g_region_realization_ptr]
    mov ecx,dword ptr [rax+rbx*4]
    mov dword ptr [r10+4],ecx
    cmp ecx,SR_REALIZATION_RECONFIGURABLE_FABRIC
    jne .gefrd_not_fabric
    inc r11d
.gefrd_not_fabric:
    mov eax,dword ptr [rbp+rbx*4]
    cmp eax,-1
    jne .gefrd_work_known
    mov rax,-1
    jmp .gefrd_work_store
.gefrd_work_known:
    mov eax,eax
.gefrd_work_store:
    mov qword ptr [r10+8],rax

    xor r8d,r8d                       # incident edge count
    xor r9d,r9d                       # incident transfer sum
    xor ecx,ecx                       # edge id
.gefrd_edge:
    cmp rcx,r13
    jae .gefrd_edges_done
    mov rax,[rip+g_region_edge_u_ptr]
    cmp dword ptr [rax+rcx*4],ebx
    je .gefrd_incident
    mov rax,[rip+g_region_edge_v_ptr]
    cmp dword ptr [rax+rcx*4],ebx
    jne .gefrd_edge_next
.gefrd_incident:
    inc r8d
    cmp r9,-1
    je .gefrd_edge_next
    mov rax,[rip+g_region_edge_transfer_ptr]
    mov rax,qword ptr [rax+rcx*8]
    cmp rax,-1
    je .gefrd_transfer_unknown
    add r9,rax
    jnc .gefrd_edge_next
.gefrd_transfer_unknown:
    mov r9,-1
.gefrd_edge_next:
    inc ecx
    jmp .gefrd_edge
.gefrd_edges_done:
    mov qword ptr [r10+16],r9
    mov qword ptr [r10+24],GR_PUBLISH_COMPLETION_EXTERNAL_OFF
    mov qword ptr [r10+32],r8
    mov qword ptr [r10+40],SR_FABRIC_REALIZATION_DESCRIPTOR_VERSION
    inc ebx
    jmp .gefrd_node

.gefrd_patch_count:
    mov rax,[rip+g_parallel_code_ptr]
    mov dword ptr [rax+GR_FABRIC_REGION_COUNT_OFF],r11d
    xor eax,eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

g_materialize_parallel_code:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # Parallel staging shares the same source-sized stable arena authority.
    # Graph metadata is structural: 84*N + 16*E bytes, including the existing
    # 48-byte domain descriptor and one 16-byte work projection. These project
    # existing DAG/work/edge/completion facts; it is not a device graph or IR.
    mov rdi,[rip+g_parallel_code_ptr]
    lea rsi,[rip+general_parallel_release_blob]
    mov ecx,GR_TEMPLATE_SIZE
    rep movsb

    mov r12d,GR_TEMPLATE_SIZE
    mov eax,dword ptr [rip+g_region_count]
    mov rdx,rax
    imul rdx,rdx,84              # shared graph/domain records + 16-byte work fact
    mov eax,dword ptr [rip+g_region_edge_count]
    mov rcx,rax
    shl rcx,4                    # 16*E: edge_v/next + qword transfer fact
    add rdx,rcx
    jc .gmpc_fail
    mov eax,r12d
    add rax,rdx
    cmp rax,qword ptr [rip+g_parallel_code_capacity]
    jb 94f
    mov dword ptr [rip+g_code_overflow],1
    jmp .gmpc_fail
94:
    mov r12d,eax                 # first byte after compact graph metadata

    xor ebx,ebx                  # region id
.gmpc_region:
    cmp ebx,dword ptr [rip+g_region_count]
    jae .gmpc_patch
    # Preserve the emitted byte phase when a Region is placed after metadata.
    # Its first gap is unreachable; entry points directly at the first fragment.
    mov rax,[rip+g_region_head_ptr]; mov r13d,[rax+rbx*4]
    mov rax,[rip+g_fragment_start_ptr]; mov rcx,[rax+r13*8]
    sub rcx,[rip+g_code_ptr]; sub rcx,r12
    and ecx,PRC_CACHE_LINE_BYTES-1; add r12,rcx
    mov rax,[rip+g_parallel_code_capacity]
    cmp r12,rax
    jb 95f
    mov dword ptr [rip+g_code_overflow],1
    jmp .gmpc_fail
95:
    mov rax,[rip+g_region_entry_offsets_ptr]
    mov [rax+rbx*4],r12d
    mov rax,[rip+g_region_len_ptr]
    mov r14d,[rax+rbx*4]
    call g_region_work_fact
    mov r10d,eax                   # the existing iterative work projection
    xor r15d,r15d                 # straight-line front-end physical work ticks
    xor ebp,ebp                   # same Region's emitted memory-traffic ticks
.gmpc_member:
    test r14d,r14d
    jz .gmpc_region_ret
    mov rax,[rip+g_fragment_start_ptr]; mov rsi,[rax+r13*8]
    mov rax,[rip+g_fragment_end_ptr_ptr]; mov rdx,[rax+r13*8]
    sub rdx,rsi
    test rdx,rdx
    jz .gmpc_fail
    # Fused members can have different source phases. Restore that relation
    # outside their own loops, rather than silently undoing emission layout.
    mov r9,rsi; sub r9,[rip+g_code_ptr]; sub r9,r12
    and r9d,PRC_CACHE_LINE_BYTES-1
    cmp r15d,-1
    je .gmpc_work_done
    mov rax,[rip+g_fragment_static_ptr]
    mov eax,[rax+r13*4]
    or eax,r10d                    # known iteration owns its one-shot base too
    test eax,eax
    jz .gmpc_work_unbounded
    mov rax,[rip+g_fragment_memory_ops_ptr]
    mov eax,[rax+r13*4]
    imul rax,PRC_TRAFFIC_LINE_TICKS
    cmp rax,0x7ffffffe
    ja .gmpc_work_unbounded
    add ebp,eax
    jc .gmpc_work_unbounded
    mov rax,rdx; add rax,r9
    imul rax,PRC_FRONTEND_BYTE_TICKS
    test r10d,r10d; jz .gmpc_base_priced
    mov rcx,[rip+g_fragment_work_kind_ptr]
    mov ecx,[rcx+r13*8+4]
    sub rax,rcx
.gmpc_base_priced:
    cmp rax,0x7ffffffe
    ja .gmpc_work_unbounded
    add eax,r15d
    jc .gmpc_work_unbounded
    mov r15d,eax
    jmp .gmpc_work_done
.gmpc_work_unbounded:
    mov r15d,-1
.gmpc_work_done:
    mov rax,r12
    add rax,r9
    jc .gmpc_fail
    add rax,rdx
    jc .gmpc_fail
    cmp rax,qword ptr [rip+g_parallel_code_capacity]
    jb 96f
    mov dword ptr [rip+g_code_overflow],1
    jmp .gmpc_fail
96:
    mov r8,rsi
    mov rdi,[rip+g_parallel_code_ptr]; add rdi,r12
    mov esi,r9d; call g_phys_fill_nops
    add r12,r9
    mov rsi,r8
    mov rcx,rdx
    rep movsb
    add r12,rdx
    dec r14d
    jz .gmpc_region_ret
    mov rax,[rip+g_sole_succ_ptr]
    mov r13d,[rax+r13*4]
    cmp r13d,-1
    je .gmpc_fail
    jmp .gmpc_member
.gmpc_region_ret:
    cmp r15d,-1
    je 981f
    cmp r15d,ebp
    cmovb r15d,ebp                  # resource max, never additive double-counting
981:
    # Publish the AOT lower-bound work price directly into the compact runtime
    # metadata. A proved iterative projection uses this price as its one-shot
    # base; unknown dynamic work retains 0xffffffff. No second graph survives.
    mov rax,[rip+g_parallel_code_ptr]
    add rax,GR_TEMPLATE_SIZE
    mov ecx,dword ptr [rip+g_region_count]
    lea rcx,[rcx+rcx*2]           # 3*N dwords before work_ticks[]
    lea rax,[rax+rcx*4]
    mov dword ptr [rax+rbx*4],r15d
    mov rax,[rip+g_parallel_code_capacity]
    lea rdx,[r12+1]
    cmp rdx,rax
    jbe 97f
    mov dword ptr [rip+g_code_overflow],1
    jmp .gmpc_fail
97:
    mov rax,[rip+g_parallel_code_ptr]
    mov byte ptr [rax+r12],0xC3
    inc r12d
    inc ebx
    jmp .gmpc_region

.gmpc_patch:
    # Close the already-proved Region DAG against any externally proved fabric
    # target facts. The result is an AOT physical-domain plan only; the normal
    # release still executes x86 until a fabric activation emitter/bridge exists.
    call g_close_heterogeneous_placement
    test eax,eax
    jnz .gmpc_fail
    mov r15,[rip+g_parallel_code_ptr]
    mov eax,dword ptr [rip+g_region_count]
    mov dword ptr [r15+GR_NODE_COUNT_OFF],eax
    mov eax,dword ptr [rip+g_region_edge_count]
    mov dword ptr [r15+GR_EDGE_COUNT_OFF],eax
    mov rax,qword ptr [rip+outward_materialization_ticks]
    mov qword ptr [r15+GR_OUTWARD_MATERIALIZATION_TICKS_OFF],rax
    mov eax,dword ptr [rip+execution_admission_capacity]
    mov dword ptr [r15+GR_EXECUTION_ADMISSION_CAPACITY_OFF],eax

    mov eax,dword ptr [rip+sd_static_placement_required]
    mov dword ptr [r15+GR_STATIC_PLACEMENT_REQUIRED_OFF],eax
    mov eax,dword ptr [rip+sd_preferred_l3_mask_bytes]
    mov dword ptr [r15+GR_STATIC_PLACEMENT_MASK_BYTES_OFF],eax
    lea rsi,[rip+sd_preferred_l3_mask]
    lea rdi,[r15+GR_STATIC_PLACEMENT_MASK_OFF]
    mov ecx,GR_STATIC_PLACEMENT_MASK_SIZE
    rep movsb

    # Variable metadata immediately follows the runtime template:
    # indegree[N], first_out[N], entry_offsets[N], work_ticks[N],
    # edge_v[E], next_edge[E], edge_transfer_bytes[E], realization_tag[N],
    # fabric_descriptor[N:48].
    lea r8,[r15+GR_TEMPLATE_SIZE]
    mov eax,dword ptr [rip+g_region_count]
    lea r9,[r8+rax*4]
    lea r10,[r9+rax*4]
    lea r11,[r10+rax*4]           # work_ticks[] (already published above)
    lea r13,[r11+rax*4]           # edge_v[]
    mov edx,dword ptr [rip+g_region_edge_count]
    lea r14,[r13+rdx*4]           # next_edge[]
    lea rsi,[r14+rdx*4]           # edge_transfer_bytes[]
    lea rcx,[rsi+rdx*8]           # realization_tag[]

    xor ebx,ebx
.gmpc_patch_nodes:
    cmp ebx,dword ptr [rip+g_region_count]
    jae .gmpc_patch_edges
    mov rax,[rip+g_region_indegree_ptr]; mov edx,[rax+rbx*4]
    mov dword ptr [r8+rbx*4],edx
    mov rax,[rip+g_region_first_out_ptr]; mov edx,[rax+rbx*4]
    mov dword ptr [r9+rbx*4],edx
    mov rax,[rip+g_region_entry_offsets_ptr]; mov edx,[rax+rbx*4]
    mov dword ptr [r10+rbx*4],edx
    # The physical-domain plan is target data, not source syntax. Production
    # defaults remain x86 when no fabric facts are proved.
    mov rax,[rip+g_region_realization_ptr]
    mov edx,dword ptr [rax+rbx*4]
    mov dword ptr [rcx+rbx*4],edx
    inc ebx
    jmp .gmpc_patch_nodes
.gmpc_patch_edges:
    xor ebx,ebx
.gmpc_patch_edge_loop:
    cmp ebx,dword ptr [rip+g_region_edge_count]
    jae .gmpc_patch_descriptors
    mov rax,[rip+g_region_edge_v_ptr]; mov edx,[rax+rbx*4]
    mov dword ptr [r13+rbx*4],edx
    mov rax,[rip+g_region_next_edge_ptr]; mov edx,[rax+rbx*4]
    mov dword ptr [r14+rbx*4],edx
    mov rax,[rip+g_region_edge_transfer_ptr]; mov rdx,qword ptr [rax+rbx*8]
    mov qword ptr [rsi+rbx*8],rdx
    inc ebx
    jmp .gmpc_patch_edge_loop
.gmpc_patch_descriptors:
    call g_emit_fabric_realization_descriptors
    test eax,eax
    jnz .gmpc_fail
.gmpc_done:
    mov rax,[rip+g_parallel_code_ptr]
    mov [rip+g_image_code_ptr],rax
    mov [rip+g_image_code_len],r12
    xor eax,eax
    jmp .gmpc_exit
.gmpc_fail:
    mov eax,1
.gmpc_exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

g_build_parallel_image:
    # Causal image identity is independent of compile-host execution width.
    # Runtime invocation admission decides only how many ready x86 Regions may
    # be simultaneously materialized; it never selects a second semantic image.
    cmp dword ptr [rip+g_fragment_count],0; je .gbpi_fail
    call g_build_causal_graph
    test eax,eax; jnz .gbpi_fail
    call g_build_regions
    test eax,eax; jnz .gbpi_fail
    call g_verify_causal_mesh
    test eax,eax; jnz .gbpi_fail
    call g_materialize_parallel_code
    ret
.gbpi_fail:
    mov eax,1
    ret

# ---------------- image writer ----------------
g_emit_image:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    call g_prepare_rankn_twiddle_facts
    test eax,eax; jnz .geimg_fail
    mov eax,SYS_openat; mov edi,AT_FDCWD; mov rsi,[rip+g_output_path]; mov edx,OUT_FLAGS; mov r10d,0755; syscall
    test rax,rax; js .geimg_fail
    mov rbx,rax
    mov eax,SYS_write; mov rdi,rbx; lea rsi,[rip+general_runtime_blob]; mov edx,GENERAL_RUNTIME_SIZE; syscall
    cmp rax,GENERAL_RUNTIME_SIZE; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_input_count]; mov edx,4; mov r10d,GENERAL_INPUT_COUNT_OFF; syscall; cmp rax,4; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_output_count]; mov edx,4; mov r10d,GENERAL_OUTPUT_COUNT_OFF; syscall; cmp rax,4; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_rankn_type_count]; mov edx,4; mov r10d,GENERAL_RANKN_TYPE_COUNT_OFF; syscall; cmp rax,4; jne .geimg_close_fail

    # Patch exact mutable arena bases consumed by the runtime parser/printer.
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_runtime_input_values_base_va]; mov edx,8; mov r10d,GENERAL_INPUT_VALUES_BASE_OFF; syscall; cmp rax,8; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_runtime_input_aux_base_va]; mov edx,8; mov r10d,GENERAL_INPUT_AUX_BASE_OFF; syscall; cmp rax,8; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_runtime_rankn_input_base_va]; mov edx,8; mov r10d,GENERAL_RANKN_INPUT_BASE_OFF; syscall; cmp rax,8; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_runtime_rankn_input_end_va]; mov edx,8; mov r10d,GENERAL_RANKN_INPUT_END_OFF; syscall; cmp rax,8; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_runtime_output_pages_base_va]; mov edx,8; mov r10d,GENERAL_OUTPUT_PAGES_BASE_OFF; syscall; cmp rax,8; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_runtime_output_aux_base_va]; mov edx,8; mov r10d,GENERAL_OUTPUT_AUX_BASE_OFF; syscall; cmp rax,8; jne .geimg_close_fail

    # Patch exactly the represented mutable prefix plus actually materialized
    # fpP temporary demand. No input/binding/state/output record owns capacity.
    mov rax,[rip+g_runtime_rankn_temp_base_va]
    mov rdx,GENERAL_RUNTIME_DYNAMIC_ARENA_VA
    sub rax,rdx
    jc .geimg_close_fail
    add rax,[rip+g_runtime_temp_bytes_used]
    jc .geimg_close_fail
    add rax,4095
    jc .geimg_close_fail
    and rax,-4096
    mov [rip+g_runtime_arena_bytes],rax
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_runtime_arena_bytes]; mov edx,8; mov r10d,GENERAL_DYNAMIC_ARENA_BYTES_OFF; syscall
    cmp rax,8; jne .geimg_close_fail

    # Read-only trailer layout:
    #   input_type[I] | InputRange[I][24] | output_type[O] | RankNPrecision[R] | align64 | native code
    # PrecisionFacts are represented-source metadata, not a runtime capacity table.
    mov r12,GENERAL_RUNTIME_SIZE
    add r12,4095
    jc .geimg_close_fail
    and r12,-4096                    # trailer file offset
    mov r13d,dword ptr [rip+g_input_count]
    imul r13,r13,28                   # input type + range bytes
    mov r14d,dword ptr [rip+g_output_count]
    shl r14,2                        # output type bytes
    mov ebp,dword ptr [rip+g_rankn_type_count]
    imul rbp,rbp,RPF_FACT_BYTES           # interned TypePhysicalFact bytes
    mov r15,r13
    add r15,r14
    jc .geimg_close_fail
    add r15,rbp
    jc .geimg_close_fail
    add r15,[rip+g_rankn_twiddle_bytes]
    jc .geimg_close_fail
    add r15,PRC_CACHE_LINE_BYTES-1
    jc .geimg_close_fail
    and r15,-PRC_CACHE_LINE_BYTES                      # native code relative offset
    mov rax,r15
    add rax,[rip+g_image_code_len]
    jc .geimg_close_fail             # total trailer map bytes

    sub rsp,24
    mov qword ptr [rsp],r12
    mov qword ptr [rsp+8],rax
    mov qword ptr [rsp+16],r15
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rsp]; mov edx,8; mov r10d,GENERAL_PROGRAM_TRAILER_FILE_OFFSET_OFF; syscall
    cmp rax,8; jne .geimg_trailer_patch_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rsp+8]; mov edx,8; mov r10d,GENERAL_PROGRAM_TRAILER_SIZE_OFF; syscall
    cmp rax,8; jne .geimg_trailer_patch_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rsp+16]; mov edx,8; mov r10d,GENERAL_PROGRAM_CODE_REL_OFFSET_OFF; syscall
    cmp rax,8; jne .geimg_trailer_patch_fail
    add rsp,24

    test r13,r13
    jz .geimg_output_types
    mov eax,dword ptr [rip+g_input_count]; shl rax,2
    push rax
    mov rdx,rax; mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+g_input_types_ptr]; mov r10,r12; syscall
    pop rdx
    cmp rax,rdx; jne .geimg_close_fail
    mov r10,r12; add r10,rdx
    mov rdx,r13; mov eax,dword ptr [rip+g_input_count]; shl rax,2; sub rdx,rax
    push rdx
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+g_input_ranges_ptr]; syscall
    pop rdx
    cmp rax,rdx; jne .geimg_close_fail
.geimg_output_types:
    test r14,r14
    jz .geimg_rankn_facts
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+g_output_types_ptr]; mov rdx,r14; mov r10,r12; add r10,r13; syscall
    cmp rax,r14; jne .geimg_close_fail
.geimg_rankn_facts:
    test rbp,rbp
    jz .geimg_native_code
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+g_rankn_type_facts_ptr]; mov rdx,rbp; mov r10,r12; add r10,r13; add r10,r14; syscall
    cmp rax,rbp; jne .geimg_close_fail
.geimg_native_code:
    mov rdx,[rip+g_rankn_twiddle_bytes]
    test rdx,rdx; jz .geimg_code_payload
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+g_rankn_twiddle_ptr]
    mov r10,r12; add r10,r13; add r10,r14; add r10,rbp
    syscall
    cmp rax,[rip+g_rankn_twiddle_bytes]; jne .geimg_close_fail
.geimg_code_payload:
    mov rsi,[rip+g_image_code_ptr]
    mov rdx,[rip+g_image_code_len]
    mov r10,r12
    add r10,r15
    jc .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; syscall
    cmp rax,rdx; jne .geimg_close_fail
    mov eax,SYS_fchmod; mov rdi,rbx; mov esi,0755; syscall
    mov eax,SYS_close; mov rdi,rbx; syscall
    xor eax,eax
    jmp .geimg_done
.geimg_trailer_patch_fail:
    add rsp,24
.geimg_close_fail:
    mov eax,SYS_close; mov rdi,rbx; syscall
.geimg_fail:
    mov eax,1
.geimg_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# Target execution-local StateFact frame fragments.
# sub rsp,imm32 / mov r15,rsp / add rsp,imm32
gc_state_frame_sub_prefix: .byte 0x48,0x81,0xEC
gc_state_frame_sub_prefix_end:
gc_state_frame_base: .byte 0x49,0x89,0xE7
gc_state_frame_base_end:
gc_state_frame_add_prefix: .byte 0x48,0x81,0xC4
gc_state_frame_add_prefix_end:

# ---------------- runtime code fragments ----------------
.section .rodata
gc_mov_r10_rax: .byte 0x49,0x89,0xC2; gc_mov_r10_rax_end:
gc_test_rax: .byte 0x48,0x85,0xC0; gc_test_rax_end:
gc_xor_eax: .byte 0x31,0xC0; gc_xor_eax_end:
gc_mov_rbp_rax: .byte 0x48,0x89,0xC5; gc_mov_rbp_rax_end:
gc_xor_rbx: .byte 0x48,0x31,0xDB; gc_xor_rbx_end:
gc_zero_r11: .byte 0x4D,0x31,0xDB; gc_zero_r11_end:
gc_cmp_rbx_rbp: .byte 0x48,0x39,0xEB; gc_cmp_rbx_rbp_end:
gc_jae_prefix: .byte 0x0F,0x83; gc_jae_prefix_end:
gc_mov_r10_rbx: .byte 0x49,0x89,0xDA; gc_mov_r10_rbx_end:
gc_inc_rbx: .byte 0x48,0xFF,0xC3; gc_inc_rbx_end:
gc_mov_rax_r11: .byte 0x4C,0x89,0xD8; gc_mov_rax_r11_end:
# Reject when the execution limit is exhausted.
# One invocation-terminal Effect relation; stack/state frames have no successor.
.macro EFFECT_REJECT
    mov eax,GENERAL_RUNTIME_REJECT_VA
    jmp rax
.endm
gc_effect_reject: EFFECT_REJECT
gc_effect_reject_end:
gc_check_shift_rcx: cmp rcx,64; jb 991f; EFFECT_REJECT
991:
gc_check_shift_rcx_end:

gc_reject_if_rbp_zero: .byte 0x48,0x85,0xED,0x75,7; EFFECT_REJECT; gc_reject_if_rbp_zero_end:
# Continue below the execution limit; otherwise reject the invocation.
gc_iter_max_guard: .byte 0x48,0x39,0xEB,0x72,7; EFFECT_REJECT; gc_iter_max_guard_end:

# register-resident iterate snippets
# direct counted-loop register fragments
gc_reg_iter_cmp_r8_rbp: .byte 0x49,0x39,0xE8; gc_reg_iter_cmp_r8_rbp_end:
gc_reg_iter_cmp_r9_rbp: .byte 0x49,0x39,0xE9; gc_reg_iter_cmp_r9_rbp_end:
# cmp rbx,rbp and inc rbx form the independent counted-control authority.
gc_reg_iter_cmp_rbx_rbp: .byte 0x48,0x39,0xEB; gc_reg_iter_cmp_rbx_rbp_end:
gc_reg_iter_test_rbx_rbx: .byte 0x48,0x85,0xDB; gc_reg_iter_test_rbx_rbx_end:
gc_reg_iter_dec_rbx: .byte 0x48,0xFF,0xCB; gc_reg_iter_dec_rbx_end:
gc_reg_iter_inc_r8: .byte 0x49,0xFF,0xC0; gc_reg_iter_inc_r8_end:
gc_reg_iter_inc_r9: .byte 0x49,0xFF,0xC1; gc_reg_iter_inc_r9_end:
gc_push_r8: .byte 0x41,0x50; gc_push_r8_end:
gc_push_r9: .byte 0x41,0x51; gc_push_r9_end:
gc_push_r10: .byte 0x41,0x52; gc_push_r10_end:
gc_push_rbx: .byte 0x53; gc_push_rbx_end:
gc_pop_r8: .byte 0x41,0x58; gc_pop_r8_end:
gc_pop_r9: .byte 0x41,0x59; gc_pop_r9_end:
gc_pop_r10: .byte 0x41,0x5A; gc_pop_r10_end:
gc_reg_iter_mov_r10_rax: .byte 0x49,0x89,0xC2; gc_reg_iter_mov_r10_rax_end:
gc_reg_iter_mov_rbx_rax: .byte 0x48,0x89,0xC3; gc_reg_iter_mov_rbx_rax_end:
gc_reg_iter_mov_rax_r9: .byte 0x4C,0x89,0xC8; gc_reg_iter_mov_rax_r9_end:
gc_reg_iter_mov_rax_r10: .byte 0x4C,0x89,0xD0; gc_reg_iter_mov_rax_r10_end:
gc_reg_iter_mov_rax_rbx: .byte 0x48,0x89,0xD8; gc_reg_iter_mov_rax_rbx_end:

# 1.3.13 physical register-DAG fragments. These are emitted into the target
# program; none execute inside the compiler.
gc_jb_prefix: .byte 0x0F,0x82; gc_jb_prefix_end:
gc_je_prefix: .byte 0x0F,0x84; gc_je_prefix_end:
gc_jne_prefix: .byte 0x0F,0x85; gc_jne_prefix_end:
# mov rax,r8; add rax,r9; add rax,r10; mov r8,r9; mov r9,r10; mov r10,rax

gc_phys_mov_rax_r8:  .byte 0x4C,0x89,0xC0; gc_phys_mov_rax_r8_end:
gc_phys_mov_rax_r9:  .byte 0x4C,0x89,0xC8; gc_phys_mov_rax_r9_end:
gc_phys_mov_rax_r10: .byte 0x4C,0x89,0xD0; gc_phys_mov_rax_r10_end:
gc_phys_mov_rax_rbx: .byte 0x48,0x89,0xD8; gc_phys_mov_rax_rbx_end:
gc_phys_mov_r11_rax: .byte 0x49,0x89,0xC3; gc_phys_mov_r11_rax_end:
gc_phys_mov_r12_rax: .byte 0x49,0x89,0xC4; gc_phys_mov_r12_rax_end:
gc_phys_mov_r13_rax: .byte 0x49,0x89,0xC5; gc_phys_mov_r13_rax_end:
gc_phys_mov_r14_rax: .byte 0x49,0x89,0xC6; gc_phys_mov_r14_rax_end:
gc_phys_mov_r15_rax: .byte 0x49,0x89,0xC7; gc_phys_mov_r15_rax_end:
gc_phys_add_rax_r11: .byte 0x4C,0x01,0xD8; gc_phys_add_rax_r11_end:
gc_phys_add_rax_r12: .byte 0x4C,0x01,0xE0; gc_phys_add_rax_r12_end:
gc_phys_add_rax_r13: .byte 0x4C,0x01,0xE8; gc_phys_add_rax_r13_end:
gc_phys_add_rax_r14: .byte 0x4C,0x01,0xF0; gc_phys_add_rax_r14_end:
gc_phys_add_rax_r15: .byte 0x4C,0x01,0xF8; gc_phys_add_rax_r15_end:
gc_phys_sub_r11_rax_mov_rax_r11: .byte 0x49,0x29,0xC3,0x4C,0x89,0xD8; gc_phys_sub_r11_rax_mov_rax_r11_end:
gc_phys_sub_r12_rax_mov_rax_r12: .byte 0x49,0x29,0xC4,0x4C,0x89,0xE0; gc_phys_sub_r12_rax_mov_rax_r12_end:
gc_phys_sub_r13_rax_mov_rax_r13: .byte 0x49,0x29,0xC5,0x4C,0x89,0xE8; gc_phys_sub_r13_rax_mov_rax_r13_end:
gc_phys_sub_r14_rax_mov_rax_r14: .byte 0x49,0x29,0xC6,0x4C,0x89,0xF0; gc_phys_sub_r14_rax_mov_rax_r14_end:
gc_phys_sub_r15_rax_mov_rax_r15: .byte 0x49,0x29,0xC7,0x4C,0x89,0xF8; gc_phys_sub_r15_rax_mov_rax_r15_end:
gc_phys_imul_rax_r11: .byte 0x49,0x0F,0xAF,0xC3; gc_phys_imul_rax_r11_end:
gc_phys_imul_rax_r12: .byte 0x49,0x0F,0xAF,0xC4; gc_phys_imul_rax_r12_end:
gc_phys_imul_rax_r13: .byte 0x49,0x0F,0xAF,0xC5; gc_phys_imul_rax_r13_end:
gc_phys_imul_rax_r14: .byte 0x49,0x0F,0xAF,0xC6; gc_phys_imul_rax_r14_end:
gc_phys_imul_rax_r15: .byte 0x49,0x0F,0xAF,0xC7; gc_phys_imul_rax_r15_end:

gc_phys_mov_rsi_rax: .byte 0x48,0x89,0xC6; gc_phys_mov_rsi_rax_end:
gc_phys_mov_rdi_rax: .byte 0x48,0x89,0xC7; gc_phys_mov_rdi_rax_end:
gc_phys_mov_rdx_rax: .byte 0x48,0x89,0xC2; gc_phys_mov_rdx_rax_end:

gc_phys_movq_xmm0_rax: .byte 0x66,0x48,0x0F,0x6E,0xC0; gc_phys_movq_xmm0_rax_end:
gc_phys_movd_xmm0_eax: .byte 0x66,0x0F,0x6E,0xC0; gc_phys_movd_xmm0_eax_end:
gc_phys_movq_xmm2_rax: .byte 0x66,0x48,0x0F,0x6E,0xD0; gc_phys_movq_xmm2_rax_end:
gc_phys_movq_xmm3_rax: .byte 0x66,0x48,0x0F,0x6E,0xD8; gc_phys_movq_xmm3_rax_end:
gc_phys_movq_xmm4_rax: .byte 0x66,0x48,0x0F,0x6E,0xE0; gc_phys_movq_xmm4_rax_end:
gc_phys_movd_xmm2_eax: .byte 0x66,0x0F,0x6E,0xD0; gc_phys_movd_xmm2_eax_end:
gc_phys_movd_xmm3_eax: .byte 0x66,0x0F,0x6E,0xD8; gc_phys_movd_xmm3_eax_end:
gc_phys_movd_xmm4_eax: .byte 0x66,0x0F,0x6E,0xE0; gc_phys_movd_xmm4_eax_end:
gc_phys_movsd_xmm0_xmm2: .byte 0xF2,0x0F,0x10,0xC2; gc_phys_movsd_xmm0_xmm2_end:
gc_phys_movsd_xmm0_xmm3: .byte 0xF2,0x0F,0x10,0xC3; gc_phys_movsd_xmm0_xmm3_end:
gc_phys_movsd_xmm0_xmm4: .byte 0xF2,0x0F,0x10,0xC4; gc_phys_movsd_xmm0_xmm4_end:
gc_phys_movss_xmm0_xmm2: .byte 0xF3,0x0F,0x10,0xC2; gc_phys_movss_xmm0_xmm2_end:
gc_phys_movss_xmm0_xmm3: .byte 0xF3,0x0F,0x10,0xC3; gc_phys_movss_xmm0_xmm3_end:
gc_phys_movss_xmm0_xmm4: .byte 0xF3,0x0F,0x10,0xC4; gc_phys_movss_xmm0_xmm4_end:

gc_phys_movsd_xmm0_xmm8: .byte 0xF2,0x41,0x0F,0x10,0xC0; gc_phys_movsd_xmm0_xmm8_end:
gc_phys_movsd_xmm0_xmm9: .byte 0xF2,0x41,0x0F,0x10,0xC1; gc_phys_movsd_xmm0_xmm9_end:
gc_phys_movsd_xmm0_xmm10:.byte 0xF2,0x41,0x0F,0x10,0xC2; gc_phys_movsd_xmm0_xmm10_end:
gc_phys_movss_xmm0_xmm8: .byte 0xF3,0x41,0x0F,0x10,0xC0; gc_phys_movss_xmm0_xmm8_end:
gc_phys_movss_xmm0_xmm9: .byte 0xF3,0x41,0x0F,0x10,0xC1; gc_phys_movss_xmm0_xmm9_end:
gc_phys_movss_xmm0_xmm10:.byte 0xF3,0x41,0x0F,0x10,0xC2; gc_phys_movss_xmm0_xmm10_end:

gc_phys_movsd_xmm11_xmm0:.byte 0xF2,0x44,0x0F,0x10,0xD8; gc_phys_movsd_xmm11_xmm0_end:
gc_phys_movsd_xmm12_xmm0:.byte 0xF2,0x44,0x0F,0x10,0xE0; gc_phys_movsd_xmm12_xmm0_end:
gc_phys_movsd_xmm13_xmm0:.byte 0xF2,0x44,0x0F,0x10,0xE8; gc_phys_movsd_xmm13_xmm0_end:
gc_phys_movsd_xmm14_xmm0:.byte 0xF2,0x44,0x0F,0x10,0xF0; gc_phys_movsd_xmm14_xmm0_end:
gc_phys_movsd_xmm15_xmm0:.byte 0xF2,0x44,0x0F,0x10,0xF8; gc_phys_movsd_xmm15_xmm0_end:
gc_phys_movss_xmm11_xmm0:.byte 0xF3,0x44,0x0F,0x10,0xD8; gc_phys_movss_xmm11_xmm0_end:
gc_phys_movss_xmm12_xmm0:.byte 0xF3,0x44,0x0F,0x10,0xE0; gc_phys_movss_xmm12_xmm0_end:
gc_phys_movss_xmm13_xmm0:.byte 0xF3,0x44,0x0F,0x10,0xE8; gc_phys_movss_xmm13_xmm0_end:
gc_phys_movss_xmm14_xmm0:.byte 0xF3,0x44,0x0F,0x10,0xF0; gc_phys_movss_xmm14_xmm0_end:
gc_phys_movss_xmm15_xmm0:.byte 0xF3,0x44,0x0F,0x10,0xF8; gc_phys_movss_xmm15_xmm0_end:

# Scalar FP arithmetic against scratch bank.
gc_phys_addsd_xmm0_xmm11:.byte 0xF2,0x41,0x0F,0x58,0xC3; gc_phys_addsd_xmm0_xmm11_end:
gc_phys_addsd_xmm0_xmm12:.byte 0xF2,0x41,0x0F,0x58,0xC4; gc_phys_addsd_xmm0_xmm12_end:
gc_phys_addsd_xmm0_xmm13:.byte 0xF2,0x41,0x0F,0x58,0xC5; gc_phys_addsd_xmm0_xmm13_end:
gc_phys_addsd_xmm0_xmm14:.byte 0xF2,0x41,0x0F,0x58,0xC6; gc_phys_addsd_xmm0_xmm14_end:
gc_phys_addsd_xmm0_xmm15:.byte 0xF2,0x41,0x0F,0x58,0xC7; gc_phys_addsd_xmm0_xmm15_end:
gc_phys_mulsd_xmm0_xmm11:.byte 0xF2,0x41,0x0F,0x59,0xC3; gc_phys_mulsd_xmm0_xmm11_end:
gc_phys_mulsd_xmm0_xmm12:.byte 0xF2,0x41,0x0F,0x59,0xC4; gc_phys_mulsd_xmm0_xmm12_end:
gc_phys_mulsd_xmm0_xmm13:.byte 0xF2,0x41,0x0F,0x59,0xC5; gc_phys_mulsd_xmm0_xmm13_end:
gc_phys_mulsd_xmm0_xmm14:.byte 0xF2,0x41,0x0F,0x59,0xC6; gc_phys_mulsd_xmm0_xmm14_end:
gc_phys_mulsd_xmm0_xmm15:.byte 0xF2,0x41,0x0F,0x59,0xC7; gc_phys_mulsd_xmm0_xmm15_end:
gc_phys_subsd_xmm11_xmm0_mov_xmm0_xmm11:.byte 0xF2,0x44,0x0F,0x5C,0xD8,0xF2,0x41,0x0F,0x10,0xC3; gc_phys_subsd_xmm11_xmm0_mov_xmm0_xmm11_end:
gc_phys_subsd_xmm12_xmm0_mov_xmm0_xmm12:.byte 0xF2,0x44,0x0F,0x5C,0xE0,0xF2,0x41,0x0F,0x10,0xC4; gc_phys_subsd_xmm12_xmm0_mov_xmm0_xmm12_end:
gc_phys_subsd_xmm13_xmm0_mov_xmm0_xmm13:.byte 0xF2,0x44,0x0F,0x5C,0xE8,0xF2,0x41,0x0F,0x10,0xC5; gc_phys_subsd_xmm13_xmm0_mov_xmm0_xmm13_end:
gc_phys_subsd_xmm14_xmm0_mov_xmm0_xmm14:.byte 0xF2,0x44,0x0F,0x5C,0xF0,0xF2,0x41,0x0F,0x10,0xC6; gc_phys_subsd_xmm14_xmm0_mov_xmm0_xmm14_end:
gc_phys_subsd_xmm15_xmm0_mov_xmm0_xmm15:.byte 0xF2,0x44,0x0F,0x5C,0xF8,0xF2,0x41,0x0F,0x10,0xC7; gc_phys_subsd_xmm15_xmm0_mov_xmm0_xmm15_end:

gc_phys_addss_xmm0_xmm11:.byte 0xF3,0x41,0x0F,0x58,0xC3; gc_phys_addss_xmm0_xmm11_end:
gc_phys_addss_xmm0_xmm12:.byte 0xF3,0x41,0x0F,0x58,0xC4; gc_phys_addss_xmm0_xmm12_end:
gc_phys_addss_xmm0_xmm13:.byte 0xF3,0x41,0x0F,0x58,0xC5; gc_phys_addss_xmm0_xmm13_end:
gc_phys_addss_xmm0_xmm14:.byte 0xF3,0x41,0x0F,0x58,0xC6; gc_phys_addss_xmm0_xmm14_end:
gc_phys_addss_xmm0_xmm15:.byte 0xF3,0x41,0x0F,0x58,0xC7; gc_phys_addss_xmm0_xmm15_end:
gc_phys_mulss_xmm0_xmm11:.byte 0xF3,0x41,0x0F,0x59,0xC3; gc_phys_mulss_xmm0_xmm11_end:
gc_phys_mulss_xmm0_xmm12:.byte 0xF3,0x41,0x0F,0x59,0xC4; gc_phys_mulss_xmm0_xmm12_end:
gc_phys_mulss_xmm0_xmm13:.byte 0xF3,0x41,0x0F,0x59,0xC5; gc_phys_mulss_xmm0_xmm13_end:
gc_phys_mulss_xmm0_xmm14:.byte 0xF3,0x41,0x0F,0x59,0xC6; gc_phys_mulss_xmm0_xmm14_end:
gc_phys_mulss_xmm0_xmm15:.byte 0xF3,0x41,0x0F,0x59,0xC7; gc_phys_mulss_xmm0_xmm15_end:
gc_phys_subss_xmm11_xmm0_mov_xmm0_xmm11:.byte 0xF3,0x44,0x0F,0x5C,0xD8,0xF3,0x41,0x0F,0x10,0xC3; gc_phys_subss_xmm11_xmm0_mov_xmm0_xmm11_end:
gc_phys_subss_xmm12_xmm0_mov_xmm0_xmm12:.byte 0xF3,0x44,0x0F,0x5C,0xE0,0xF3,0x41,0x0F,0x10,0xC4; gc_phys_subss_xmm12_xmm0_mov_xmm0_xmm12_end:
gc_phys_subss_xmm13_xmm0_mov_xmm0_xmm13:.byte 0xF3,0x44,0x0F,0x5C,0xE8,0xF3,0x41,0x0F,0x10,0xC5; gc_phys_subss_xmm13_xmm0_mov_xmm0_xmm13_end:
gc_phys_subss_xmm14_xmm0_mov_xmm0_xmm14:.byte 0xF3,0x44,0x0F,0x5C,0xF0,0xF3,0x41,0x0F,0x10,0xC6; gc_phys_subss_xmm14_xmm0_mov_xmm0_xmm14_end:
gc_phys_subss_xmm15_xmm0_mov_xmm0_xmm15:.byte 0xF3,0x44,0x0F,0x5C,0xF8,0xF3,0x41,0x0F,0x10,0xC7; gc_phys_subss_xmm15_xmm0_mov_xmm0_xmm15_end:

gc_phys_movsd_xmm5_xmm0:.byte 0xF2,0x0F,0x10,0xE8; gc_phys_movsd_xmm5_xmm0_end:
gc_phys_movsd_xmm6_xmm0:.byte 0xF2,0x0F,0x10,0xF0; gc_phys_movsd_xmm6_xmm0_end:
gc_phys_movsd_xmm7_xmm0:.byte 0xF2,0x0F,0x10,0xF8; gc_phys_movsd_xmm7_xmm0_end:
gc_phys_movss_xmm5_xmm0:.byte 0xF3,0x0F,0x10,0xE8; gc_phys_movss_xmm5_xmm0_end:
gc_phys_movss_xmm6_xmm0:.byte 0xF3,0x0F,0x10,0xF0; gc_phys_movss_xmm6_xmm0_end:
gc_phys_movss_xmm7_xmm0:.byte 0xF3,0x0F,0x10,0xF8; gc_phys_movss_xmm7_xmm0_end:

# scalar constant-operand snippets; input value in rax, constant in rcx
gc_const_add: .byte 0x48,0x01,0xC8; gc_const_add_end:
gc_const_sub: .byte 0x48,0x29,0xC8; gc_const_sub_end:
gc_const_mul: .byte 0x48,0x0F,0xAF,0xC1; gc_const_mul_end:
gc_const_and: .byte 0x48,0x21,0xC8; gc_const_and_end:
gc_const_or:  .byte 0x48,0x09,0xC8; gc_const_or_end:
gc_const_xor: .byte 0x48,0x31,0xC8; gc_const_xor_end:
gc_const_umod: .byte 0x31,0xD2,0x48,0xF7,0xF1,0x48,0x89,0xD0; gc_const_umod_end:
gc_const_umin: .byte 0x48,0x39,0xC8,0x48,0x0F,0x47,0xC1; gc_const_umin_end:
gc_const_umax: .byte 0x48,0x39,0xC8,0x48,0x0F,0x42,0xC1; gc_const_umax_end:

# 1.3.67 Rank-N transition-power call preparation.  Matrix composition itself
# lives in the one handwritten native runtime kernel exposed by the same static
# runtime image; no scalar power snippets or dimension-specific code paths remain.
gc_transition_power_mov_rdx_rax: .byte 0x48,0x89,0xC2; gc_transition_power_mov_rdx_rax_end:

# unary/bit snippets
gc_not_bool: .byte 0x58,0x48,0x83,0xF0,0x01,0x50; gc_not_bool_end:
gc_bit_not: .byte 0x58,0x48,0xF7,0xD0,0x50; gc_bit_not_end:
gc_neg_i64: .byte 0x58,0x48,0xF7,0xD8,0x50; gc_neg_i64_end:
gc_neg_i64_trap:
    pop rax
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Lgc_neg_i64_ok
    EFFECT_REJECT
.Lgc_neg_i64_ok:
    neg rax
    push rax
gc_neg_i64_trap_end:
gc_neg_f64: .byte 0x58,0x48,0xB9,0,0,0,0,0,0,0,0x80,0x48,0x31,0xC8,0x50; gc_neg_f64_end:
gc_neg_f32: .byte 0x58,0x48,0x81,0xF0,0,0,0,0x80,0x50; gc_neg_f32_end:
gc_abs_i64: .byte 0x58,0x48,0x89,0xC1,0x48,0xC1,0xF9,0x3F,0x48,0x31,0xC8,0x48,0x29,0xC8,0x50; gc_abs_i64_end:
gc_abs_i64_trap:
    pop rax
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Lgc_abs_i64_ok
    EFFECT_REJECT
.Lgc_abs_i64_ok:
    mov rcx,rax
    sar rcx,63
    xor rax,rcx
    sub rax,rcx
    push rax
gc_abs_i64_trap_end:
gc_abs_f64: .byte 0x58,0x48,0xB9,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x7F,0x48,0x21,0xC8,0x50; gc_abs_f64_end:
gc_abs_f32: .byte 0x58,0x48,0x25,0xFF,0xFF,0xFF,0x7F,0x50; gc_abs_f32_end:
gc_sqrt_f64: .byte 0x58,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x51,0xC0,0x66,0x48,0x0F,0x7E,0xC0,0x50; gc_sqrt_f64_end:
gc_sqrt_f32: .byte 0x58,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,0x51,0xC0,0x66,0x0F,0x7E,0xC0,0x50; gc_sqrt_f32_end:
gc_square_f64: .byte 0x58,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x59,0xC0,0x66,0x48,0x0F,0x7E,0xC0,0x50; gc_square_f64_end:
gc_square_f32: .byte 0x58,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,0x59,0xC0,0x66,0x0F,0x7E,0xC0,0x50; gc_square_f32_end:
gc_trunc_f64:
    pop rax
    movq xmm0,rax
    roundsd xmm0,xmm0,3
    movq rax,xmm0
    push rax
gc_trunc_f64_end:
gc_trunc_f32:
    pop rax
    movd xmm0,eax
    roundss xmm0,xmm0,3
    movd eax,xmm0
    push rax
gc_trunc_f32_end:
# Wide helper status contracts used by generated code.  A failed physical
# relation is terminal for the generated program and exits with the historical
# numeric-domain status 65.  Never `ret` through the expression-value stack.
gc_wide_check_edx: .byte 0x85,0xD2,0x74,7; EFFECT_REJECT; gc_wide_check_edx_end:
gc_wide_check_eax: .byte 0x85,0xC0,0x74,7; EFFECT_REJECT; gc_wide_check_eax_end:

# casts top-of-stack
# Unsigned magnitude normalization shared by all native FP consumers.
gc_unsigned_fp_split:
    mov rdx,rax
    shr rax,1
    and edx,1
    or rax,rdx
gc_unsigned_fp_split_end:

gc_cast_f32_f64:
    pop rax
    movd xmm0,eax
    cvtss2sd xmm0,xmm0
    movq rax,xmm0
    push rax
gc_cast_f32_f64_end:

gc_cast_f64_f32:
    pop rax
    movq xmm0,rax
    cvtsd2ss xmm0,xmm0
    movd eax,xmm0
    push rax
gc_cast_f64_f32_end:

# Float-to-integer casts retain the historical signed conversion contract for
# now; the explicit general regression gate constrains values to its valid
# representable range rather than silently redefining out-of-range behavior.
gc_cast_f32_i64: .byte 0x58,0x66,0x0F,0x6E,0xC0,0xF3,0x48,0x0F,0x2C,0xC0,0x50; gc_cast_f32_i64_end:
gc_cast_f64_i64: .byte 0x58,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x48,0x0F,0x2C,0xC0,0x50; gc_cast_f64_i64_end:

# mixed precision stack conversions
gc_top_f64_to_f32:
    pop rax
    movq xmm0,rax
    cvtsd2ss xmm0,xmm0
    movd eax,xmm0
    push rax
gc_top_f64_to_f32_end:

gc_top_f32_to_f64:
    pop rax
    movd xmm0,eax
    cvtss2sd xmm0,xmm0
    movq rax,xmm0
    push rax
gc_top_f32_to_f64_end:

# second operand conversion preserves the current top in rcx.  The u64 split
# uses rdx as its temporary so the untouched top remains intact.
gc_second_f64_to_f32:
    pop rcx
    pop rax
    movq xmm0,rax
    cvtsd2ss xmm0,xmm0
    movd eax,xmm0
    push rax
    push rcx
gc_second_f64_to_f32_end:

gc_second_f32_to_f64:
    pop rcx
    pop rax
    movd xmm0,eax
    cvtss2sd xmm0,xmm0
    movq rax,xmm0
    push rax
    push rcx
gc_second_f32_to_f64_end:

gc_second_i64_to_f64:
    pop rcx
    pop rax
    vxorps xmm0,xmm0,xmm0
    vcvtsi2sd xmm0,xmm0,rax
    movq rax,xmm0
    push rax
    push rcx
gc_second_i64_to_f64_end:

gc_second_i64_to_f32:
    pop rcx
    pop rax
    vxorps xmm0,xmm0,xmm0
    vcvtsi2ss xmm0,xmm0,rax
    movd eax,xmm0
    push rax
    push rcx
gc_second_i64_to_f32_end:

gc_second_u64_to_f64:
    pop rcx
    pop rax
    test rax,rax
    js .Lgc_second_u64_f64_hi
    vxorps xmm0,xmm0,xmm0
    vcvtsi2sd xmm0,xmm0,rax
    jmp .Lgc_second_u64_f64_done
.Lgc_second_u64_f64_hi:
    mov rdx,rax
    shr rax,1
    and edx,1
    or rax,rdx
    vxorps xmm0,xmm0,xmm0
    vcvtsi2sd xmm0,xmm0,rax
    addsd xmm0,xmm0
.Lgc_second_u64_f64_done:
    movq rax,xmm0
    push rax
    push rcx
gc_second_u64_to_f64_end:

gc_second_u64_to_f32:
    pop rcx
    pop rax
    test rax,rax
    js .Lgc_second_u64_f32_hi
    vxorps xmm0,xmm0,xmm0
    vcvtsi2ss xmm0,xmm0,rax
    jmp .Lgc_second_u64_f32_done
.Lgc_second_u64_f32_hi:
    mov rdx,rax
    shr rax,1
    and edx,1
    or rax,rdx
    vxorps xmm0,xmm0,xmm0
    vcvtsi2ss xmm0,xmm0,rax
    addss xmm0,xmm0
.Lgc_second_u64_f32_done:
    movd eax,xmm0
    push rax
    push rcx
gc_second_u64_to_f32_end:

# IEEE float binary snippets; zero/nonfinite operands follow DIVSD/DIVSS semantics.
.macro F64BIN name,opcode
\name: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,\opcode,0xC1,0x66,0x48,0x0F,0x7E,0xC0,0x50
\name\()_end:
.endm
F64BIN gc_f64_add,0x58
F64BIN gc_f64_sub,0x5C
F64BIN gc_f64_mul,0x59
F64BIN gc_f64_div,0x5E

.p2align 3

.p2align 3
g_native_fp_op_table:
    .quad gv_add; .long gv_add_end-gv_add,0; .quad gc_f64_add; .long gc_f64_add_end-gc_f64_add,0; .quad gc_f32_add; .long gc_f32_add_end-gc_f32_add,0
    .quad gv_sub; .long gv_sub_end-gv_sub,0; .quad gc_f64_sub; .long gc_f64_sub_end-gc_f64_sub,0; .quad gc_f32_sub; .long gc_f32_sub_end-gc_f32_sub,0
    .quad gv_mul; .long gv_mul_end-gv_mul,0; .quad gc_f64_mul; .long gc_f64_mul_end-gc_f64_mul,0; .quad gc_f32_mul; .long gc_f32_mul_end-gc_f32_mul,0
    .quad gv_div; .long gv_div_end-gv_div,0; .quad gc_f64_div; .long gc_f64_div_end-gc_f64_div,0; .quad gc_f32_div; .long gc_f32_div_end-gc_f32_div,0
    .quad gv_min; .long gv_min_end-gv_min,0; .quad gc_f64_min; .long gc_f64_min_end-gc_f64_min,0; .quad gc_f32_min; .long gc_f32_min_end-gc_f32_min,0
    .quad gv_max; .long gv_max_end-gv_max,0; .quad gc_f64_max; .long gc_f64_max_end-gc_f64_max,0; .quad gc_f32_max; .long gc_f32_max_end-gc_f32_max,0
    .quad 0
gc_f64_min: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x5D,0xC1,0x66,0x48,0x0F,0x7E,0xC0,0x50; gc_f64_min_end:
gc_f64_max: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x5F,0xC1,0x66,0x48,0x0F,0x7E,0xC0,0x50; gc_f64_max_end:
.macro F32BIN name,opcode
\name: .byte 0x59,0x58,0x66,0x0F,0x6E,0xC9,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,\opcode,0xC1,0x66,0x0F,0x7E,0xC0,0x50
\name\()_end:
.endm
F32BIN gc_f32_add,0x58
F32BIN gc_f32_sub,0x5C
F32BIN gc_f32_mul,0x59
F32BIN gc_f32_div,0x5E

# integer arithmetic fragments
# wrap
gc_add_wrap: .byte 0x59,0x58,0x48,0x01,0xC8,0x50; gc_add_wrap_end:
gc_sub_wrap: .byte 0x59,0x58,0x48,0x29,0xC8,0x50; gc_sub_wrap_end:
gc_mul_wrap: .byte 0x59,0x58,0x48,0x0F,0xAF,0xC1,0x50; gc_mul_wrap_end:
# trap, good branch skips mov eax,1;ret (6 bytes)
gc_uadd_trap: .byte 0x59,0x58,0x48,0x01,0xC8,0x73,7; EFFECT_REJECT; .byte 0x50; gc_uadd_trap_end:
gc_iadd_trap: .byte 0x59,0x58,0x48,0x01,0xC8,0x71,7; EFFECT_REJECT; .byte 0x50; gc_iadd_trap_end:
gc_usub_trap: .byte 0x59,0x58,0x48,0x29,0xC8,0x73,7; EFFECT_REJECT; .byte 0x50; gc_usub_trap_end:
gc_isub_trap: .byte 0x59,0x58,0x48,0x29,0xC8,0x71,7; EFFECT_REJECT; .byte 0x50; gc_isub_trap_end:
# unsigned mul: mul rcx -> rdx:rax, reject if rdx!=0
gc_umul_trap: .byte 0x59,0x58,0x48,0xF7,0xE1,0x48,0x85,0xD2,0x74,7; EFFECT_REJECT; .byte 0x50; gc_umul_trap_end:
gc_imul_trap: .byte 0x59,0x58,0x48,0x0F,0xAF,0xC1,0x71,7; EFFECT_REJECT; .byte 0x50; gc_imul_trap_end:
# The single register relation also serves stack consumers via their own ABI.
gc_udivmod_core:
    test rcx,rcx
    jne .Ludm_nonzero
    EFFECT_REJECT
.Ludm_nonzero:
    xor edx,edx
    div rcx
gc_udivmod_core_end:
gc_idivmod_trap_core:
    test rcx,rcx
    jne .Litdm_nonzero
    EFFECT_REJECT
.Litdm_nonzero:
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Litdm_do
    cmp rcx,-1
    jne .Litdm_do
    EFFECT_REJECT
.Litdm_do:
    cqo
    idiv rcx
gc_idivmod_trap_core_end:
gc_idivmod_wrap_core:
    test rcx,rcx
    jne .Liwdm_nonzero
    EFFECT_REJECT
.Liwdm_nonzero:
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Liwdm_do
    cmp rcx,-1
    jne .Liwdm_do
    xor edx,edx
    jmp .Liwdm_done
.Liwdm_do:
    cqo
    idiv rcx
.Liwdm_done:
gc_idivmod_wrap_core_end:

# min/max ints
gc_umin: .byte 0x59,0x58,0x48,0x39,0xC8,0x48,0x0F,0x47,0xC1,0x50; gc_umin_end:
gc_umax: .byte 0x59,0x58,0x48,0x39,0xC8,0x48,0x0F,0x42,0xC1,0x50; gc_umax_end:
gc_imin: .byte 0x59,0x58,0x48,0x39,0xC8,0x48,0x0F,0x4F,0xC1,0x50; gc_imin_end:
gc_imax: .byte 0x59,0x58,0x48,0x39,0xC8,0x48,0x0F,0x4C,0xC1,0x50; gc_imax_end:

# comparisons: common pop/cmp/setcc/push
.macro ICMP name,cc
\name: .byte 0x59,0x58,0x48,0x39,0xC8,0x0F,\cc,0xC0,0x0F,0xB6,0xC0,0x50
\name\()_end:
.endm
ICMP gc_cmp_eq,0x94
ICMP gc_cmp_ne,0x95
ICMP gc_cmp_b,0x92
ICMP gc_cmp_be,0x96
ICMP gc_cmp_a,0x97
ICMP gc_cmp_ae,0x93
ICMP gc_cmp_l,0x9C
ICMP gc_cmp_le,0x9E
ICMP gc_cmp_g,0x9F
ICMP gc_cmp_ge,0x9D

# fpP comparison helper returns -1/0/+1 in EAX.  Projection to a boolean
# remains branchless and does not inspect precision or carrier provenance.
.macro RPFRESCMP name,cc
\name:
    test eax,eax
    set\cc al
    movzx eax,al
    push rax
\name\()_end:
.endm
RPFRESCMP gc_rankn_cmp_eq,e
RPFRESCMP gc_rankn_cmp_ne,ne
RPFRESCMP gc_rankn_cmp_lt,l
RPFRESCMP gc_rankn_cmp_le,le
RPFRESCMP gc_rankn_cmp_gt,g
RPFRESCMP gc_rankn_cmp_ge,ge

# Float cmp fragments: ordered setcc after ucomi lhs,rhs.
.macro F64CMP name,cc
\name: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0x66,0x0F,0x2E,0xC1
    PHYSICAL_FP_SETCC \cc
    .byte 0x0F,0xB6,0xC0,0x50
\name\()_end:
.endm
F64CMP gc_f64_cmp_eq,0x94
F64CMP gc_f64_cmp_ne,0x95
F64CMP gc_f64_cmp_lt,0x92
F64CMP gc_f64_cmp_le,0x96
F64CMP gc_f64_cmp_gt,0x97
F64CMP gc_f64_cmp_ge,0x93
.macro F32CMP name,cc
\name: .byte 0x59,0x58,0x66,0x0F,0x6E,0xC9,0x66,0x0F,0x6E,0xC0,0x0F,0x2E,0xC1
    PHYSICAL_FP_SETCC \cc
    .byte 0x0F,0xB6,0xC0,0x50
\name\()_end:
.endm
F32CMP gc_f32_cmp_eq,0x94
F32CMP gc_f32_cmp_ne,0x95
F32CMP gc_f32_cmp_lt,0x92
F32CMP gc_f32_cmp_le,0x96
F32CMP gc_f32_cmp_gt,0x97
F32CMP gc_f32_cmp_ge,0x93

# bit and shifts
gc_and_qword: .byte 0x59,0x58,0x48,0x21,0xC8,0x50; gc_and_qword_end:
gc_or_qword: .byte 0x59,0x58,0x48,0x09,0xC8,0x50; gc_or_qword_end:
gc_xor_qword: .byte 0x59,0x58,0x48,0x31,0xC8,0x50; gc_xor_qword_end:
gc_shl_checked: .byte 0x59,0x48,0x83,0xF9,0x40,0x72,7; EFFECT_REJECT; .byte 0x58,0x48,0xD3,0xE0,0x50; gc_shl_checked_end:
gc_shr_checked: .byte 0x59,0x48,0x83,0xF9,0x40,0x72,7; EFFECT_REJECT; .byte 0x58,0x48,0xD3,0xE8,0x50; gc_shr_checked_end:

# reduction snippets: candidate rax, accumulator r11
gc_red_add_wrap: .byte 0x49,0x01,0xC3; gc_red_add_wrap_end:
gc_red_uadd_trap: .byte 0x49,0x01,0xC3,0x73,7; EFFECT_REJECT; gc_red_uadd_trap_end:
gc_red_iadd_trap: .byte 0x49,0x01,0xC3,0x71,7; EFFECT_REJECT; gc_red_iadd_trap_end:
gc_red_f64_add:
    vmovq xmm3,r11
    vmovq xmm0,rax
    vaddsd xmm3,xmm3,xmm0
    vmovq r11,xmm3
gc_red_f64_add_end:
gc_red_f32_add:
    vmovd xmm3,r11d
    vmovd xmm0,eax
    vaddss xmm3,xmm3,xmm0
    vmovd r11d,xmm3
gc_red_f32_add_end:
# First nonempty candidate initializes the same ordered binary fold.
gc_red_first_guard: .byte 0x48,0x85,0xDB,0x75,0x03,0x49,0x89,0xC3; gc_red_first_guard_end:

# constants/keys
# JSON keys
gk_format:.ascii "format"; gk_format_end:
gk_program:.ascii "program"; gk_program_end:
gk_contracts:.ascii "contracts"; gk_contracts_end:
gk_deterministic:.ascii "deterministic"; gk_deterministic_end:
gk_integer_overflow:.ascii "integer_overflow"; gk_integer_overflow_end:
gk_floating_point:.ascii "floating_point"; gk_floating_point_end:
gk_floating_tolerance:.ascii "floating_tolerance"; gk_floating_tolerance_end:
gk_mixed_precision:.ascii "mixed_precision"; gk_mixed_precision_end:
gk_inputs:.ascii "inputs"; gk_inputs_end:
gk_bindings:.ascii "bindings"; gk_bindings_end:
gk_outputs:.ascii "outputs"; gk_outputs_end:
gk_tests:.ascii "tests"; gk_tests_end:
gk_name:.ascii "name"; gk_name_end:
gk_type:.ascii "type"; gk_type_end:
gk_base:.ascii "base"; gk_base_end:
gk_op:.ascii "op"; gk_op_end:
gk_expr:.ascii "expr"; gk_expr_end:
gk_literal:.ascii "literal"; gk_literal_end:
gk_var:.ascii "var"; gk_var_end:
gk_axis:.ascii "axis"; gk_axis_end:
gk_state:.ascii "state"; gk_state_end:
gk_field:.ascii "field"; gk_field_end:
gk_record:.ascii "record"; gk_record_end:
gk_fields:.ascii "fields"; gk_fields_end:
gk_load:.ascii "load"; gk_load_end:
gk_indices:.ascii "indices"; gk_indices_end:
gk_args:.ascii "args"; gk_args_end:
gk_to:.ascii "to"; gk_to_end:
gk_axes:.ascii "axes"; gk_axes_end:
gk_extent:.ascii "extent"; gk_extent_end:
gk_accumulator:.ascii "accumulator"; gk_accumulator_end:
gk_kind:.ascii "kind"; gk_kind_end:
gk_states:.ascii "states"; gk_states_end:
gk_init:.ascii "init"; gk_init_end:
gk_condition:.ascii "condition"; gk_condition_end:
gk_update:.ascii "update"; gk_update_end:
gk_result:.ascii "result"; gk_result_end:
gk_max_iterations:.ascii "max_iterations"; gk_max_iterations_end:
gk_dictionary:.ascii "dictionary"; gk_dictionary_end:
gk_dictionary_lookup:.ascii "dictionary_lookup"; gk_dictionary_lookup_end:
gk_key:.ascii "key"; gk_key_end:
gk_default:.ascii "default"; gk_default_end:
gk_key_type:.ascii "key_type"; gk_key_type_end:
gk_value_type:.ascii "value_type"; gk_value_type_end:
gk_entries:.ascii "entries"; gk_entries_end:
gk_value:.ascii "value"; gk_value_end:
gk_source_ref:.ascii "source"; gk_source_ref_end:
gk_target_ref:.ascii "target"; gk_target_ref_end:
gk_input:.ascii "input"; gk_input_end:
gk_segments:.ascii "segments"; gk_segments_end:
# values
gv_format:.ascii "wheelchair.tensor/1"; gv_format_end:
gv_trap:.ascii "trap"; gv_trap_end:
gv_wrap:.ascii "wrap"; gv_wrap_end:
gv_fp_strict:.ascii "strict_by_default"; gv_fp_strict_end:
gv_fp_tolerant:.ascii "tolerant"; gv_fp_tolerant_end:
gv_mixed_low:.ascii "lower_precision_dominates"; gv_mixed_low_end:
gv_mixed_high:.ascii "higher_precision_dominates"; gv_mixed_high_end:
gv_bool:.ascii "bool"; gv_bool_end:
gv_i64:.ascii "i64"; gv_i64_end:
gv_u64:.ascii "u64"; gv_u64_end:
gv_string:.ascii "string"; gv_string_end:
gv_compute:.ascii "compute"; gv_compute_end:
gv_map:.ascii "map"; gv_map_end:
gv_reduce:.ascii "reduce"; gv_reduce_end:
gv_iterate:.ascii "iterate"; gv_iterate_end:
gv_record:.ascii "record"; gv_record_end:
gv_dictionary:.ascii "dictionary"; gv_dictionary_end:
gv_lookup:.ascii "lookup"; gv_lookup_end:
gv_nested_literal:.ascii "nested_literal"; gv_nested_literal_end:
gv_nested_reduce:.ascii "nested_reduce"; gv_nested_reduce_end:
gv_cascade:.ascii "cascade"; gv_cascade_end:
gv_add:.ascii "add"; gv_add_end:
gv_sub:.ascii "sub"; gv_sub_end:
gv_mul:.ascii "mul"; gv_mul_end:
gv_div:.ascii "div"; gv_div_end:
gv_mod:.ascii "mod"; gv_mod_end:
gv_min:.ascii "min"; gv_min_end:
gv_max:.ascii "max"; gv_max_end:
gv_neg:.ascii "neg"; gv_neg_end:
gv_abs:.ascii "abs"; gv_abs_end:
gv_sqrt:.ascii "sqrt"; gv_sqrt_end:
gv_square:.ascii "square"; gv_square_end:
gv_trunc:.ascii "trunc"; gv_trunc_end:
gv_exp:.ascii "exp"; gv_exp_end:
gv_log:.ascii "log"; gv_log_end:
gv_sin:.ascii "sin"; gv_sin_end:
gv_cos:.ascii "cos"; gv_cos_end:
gv_eq:.ascii "eq"; gv_eq_end:
gv_ne:.ascii "ne"; gv_ne_end:
gv_lt:.ascii "lt"; gv_lt_end:
gv_le:.ascii "le"; gv_le_end:
gv_gt:.ascii "gt"; gv_gt_end:
gv_ge:.ascii "ge"; gv_ge_end:
gv_and:.ascii "and"; gv_and_end:
gv_or:.ascii "or"; gv_or_end:
gv_xor:.ascii "xor"; gv_xor_end:
gv_not:.ascii "not"; gv_not_end:
gv_bit_and:.ascii "bit_and"; gv_bit_and_end:
gv_bit_or:.ascii "bit_or"; gv_bit_or_end:
gv_bit_xor:.ascii "bit_xor"; gv_bit_xor_end:
gv_bit_not:.ascii "bit_not"; gv_bit_not_end:
gv_shl:.ascii "shl"; gv_shl_end:
gv_shr:.ascii "shr"; gv_shr_end:
gv_select:.ascii "select"; gv_select_end:
gv_cast:.ascii "cast"; gv_cast_end:
gv_sum:.ascii "sum"; gv_sum_end:
gv_count:.ascii "count"; gv_count_end:
gv_segment_count:.ascii "segment_count"; gv_segment_count_end:

.section .bss
.p2align 6
.p2align 3
g_root:.skip 8
g_output_path:.skip 8
g_emit_ptr:.skip 8
g_emit_end:.skip 8
g_code_growth_factor:.skip 8
g_code_overflow:.skip 4
g_symbol_count:.skip 4
g_input_count:.skip 4
g_binding_count:.skip 4
g_output_count:.skip 4
g_binding_slot_count:.skip 4
g_state_count:.skip 4
g_runtime_state_capacity:.skip 4
g_state_local_frame_bytes:.skip 4
g_overflow_wrap:.skip 4
g_precision_propagation:.skip 4
g_fp_tolerance_active:.skip 4
.p2align 3
g_fp_tolerance_exp2:.skip 8
g_runtime_temp_bytes_used:.skip 8
.p2align 3
g_io_meta_arena_ptr:.skip 8
g_io_meta_arena_bytes:.skip 8
g_io_capacity:.skip 4
g_output_capacity:.skip 4
g_input_types_ptr:.skip 8
g_input_ranges_ptr:.skip 8
g_output_types_ptr:.skip 8
g_rankn_type_facts_ptr:.skip 8
g_rankn_type_count:.skip 4
g_rankn_type_capacity:.skip 4
.p2align 6
g_symbols_ptr:.skip 8
g_symbols_bytes:.skip 8
g_symbol_capacity:.skip 4
.p2align 6
g_state_meta_arena_ptr:.skip 8
g_state_meta_arena_bytes:.skip 8
g_state_capacity:.skip 4
g_states_ptr:.skip 8
g_reg_iter_decls_ptr:.skip 8
g_reg_iter_carrier_kind_ptr:.skip 8
g_reg_iter_old_reg_ptr:.skip 8
g_reg_iter_out_reg_ptr:.skip 8
g_phys_state_last_use_ptr:.skip 8
g_phys_state_guard_ptr:.skip 8
g_phys_update_order_ptr:.skip 8
g_phys_update_position_ptr:.skip 8
g_phys_update_pending_ptr:.skip 8
g_phys_update_total_ptr:.skip 8
g_phys_update_expr_ptr:.skip 8
g_phys_update_position:.skip 4
g_phys_update_order_error:.skip 4
.p2align 3
g_iter_projection_arena_ptr:.skip 8
g_iter_projection_arena_bytes:.skip 8
g_iter_projection_capacity:.skip 4
g_iter_projection_count:.skip 4
g_iter_projection_symbol_ptr:.skip 8
g_iter_projection_name_ptr:.skip 8
g_iter_projection_name_len:.skip 8
g_iter_projection_slot_ptr:.skip 8
g_iter_projection_type_ptr:.skip 8
g_iter_projection_state_index_ptr:.skip 8
# Per-program runtime arena layout facts, known to AOT code generation.
g_runtime_input_values_base_va:.skip 8
g_runtime_input_aux_base_va:.skip 8
g_runtime_rankn_input_base_va:.skip 8
g_runtime_rankn_input_end_va:.skip 8
g_runtime_binding_base_va:.skip 8
g_runtime_output_pages_base_va:.skip 8
g_runtime_output_aux_base_va:.skip 8
g_runtime_rankn_temp_base_va:.skip 8
g_runtime_arena_bytes:.skip 8
# compile-time state for register-resident small iterate lowering
g_reg_iter_counted:.skip 4
g_counted_proof_kind:.skip 4
g_reg_iter_countdown:.skip 4
g_reg_iter_counter_index:.skip 4
g_reg_iter_bound_expr:.skip 8
# One AOT patch chain for the ordinary bound edge and proved completed Regions.
g_reg_iter_exit_chain:.skip 8
g_iter_reg_mode:.skip 4
g_reg_iter_total:.skip 4
g_reg_iter_data_count:.skip 4
g_reg_iter_emit_start:.skip 8
g_reg_iter_update_obj:.skip 8
g_reg_iter_max_expr:.skip 8
g_reg_iter_cond_expr:.skip 8
g_reg_iter_result_name_node:.skip 8
g_reg_iter_symbol:.skip 8
# declaration pointers are compile-time facts, one per language state
# 1.3.15 Rank-N causal carrier map.  Indexed by declaration slot; -1 carrier
# means the ValueFact remains physically materialized in the existing state
# storage while its expression still uses the register-native Physical DAG.
g_reg_iter_fp_count:.skip 4
g_reg_iter_int_count:.skip 4
g_phys_fp_reserved_mask:.skip 4
g_phys_fp_carrier_count:.skip 4
g_phys_fp_all_mask:.skip 4
# Effective post-CSE last consumer for each semantic state ValueFact.
g_phys_stack_episode:.skip 4
g_phys_probe_dest:.skip 4
g_phys_probe_temp:.skip 4
g_phys_commit_old:.skip 4
g_phys_commit_out:.skip 4
g_phys_commit_type:.skip 4
g_reg_native_probe_start:.skip 8
# Compile-time constant-profitability facts share the existing whole-episode fact arena.
g_phys_const_collect:.skip 4
g_phys_fp_temp_mask:.skip 4
g_phys_fp_temp_live:.skip 4
g_phys_fp_temp_peak:.skip 4
g_phys_fp_temp_exhausted:.skip 4
# Whole-episode strict structural CSE authority (compile-time only).
g_phys_fact_arena_ptr:.skip 8
g_phys_fact_arena_bytes:.skip 8
g_phys_fact_capacity:.skip 4
g_phys_cse_candidate_count:.skip 4
g_phys_plan_root:.skip 8
g_phys_cse_candidate_expr_ptr:.skip 8
g_phys_cse_candidate_type_ptr:.skip 8
g_phys_cse_candidate_uses_ptr:.skip 8
g_phys_cse_candidate_cost_ptr:.skip 8
g_phys_cse_resident_count:.skip 4
g_phys_cse_resident_cost_ptr:.skip 8
g_phys_cse_candidate_moves_ptr:.skip 8
g_phys_cse_resident_frontier_ptr:.skip 8
g_phys_cse_control_ready_count:.skip 4
g_phys_cse_resident_expr_ptr:.skip 8
g_phys_cse_resident_type_ptr:.skip 8
g_phys_cse_resident_reg_ptr:.skip 8
g_phys_guard_region_uses_ptr:.skip 8
g_phys_cse_ready_count:.skip 4
g_phys_int_temp_mask:.skip 4
g_phys_int_temp_live:.skip 4
g_phys_int_temp_peak:.skip 4
g_phys_int_reserved_mask:.skip 4
g_phys_const_candidate_count:.skip 4
g_phys_const_candidate_bits_ptr:.skip 8
g_phys_const_candidate_type_ptr:.skip 8
g_phys_const_candidate_uses_ptr:.skip 8
g_phys_const_candidate_pool_ptr:.skip 8
g_phys_const_pool_ready:.skip 4
g_phys_const_resident_count:.skip 4
g_phys_const_resident_bits_ptr:.skip 8
g_phys_const_resident_type_ptr:.skip 8
g_phys_const_resident_reg_ptr:.skip 8
g_cached_binding_slot:.skip 4
.p2align 3
# compile-time state for general scalar optimizer
g_scalar_opt_emit_start:.skip 8
g_scalar_const_value:.skip 8
g_scalar_const_left:.skip 4
g_scalar_opt_kind:.skip 4
# compile-time proof state for generic counted-axis recognition
g_counted_bound_expr:.skip 8
# Rank-N transition-power facts attached to the same counted recurrence Physical
# Reality.  Dense slice lanes reuse state metadata; these globals own only the
# current proof/realization episode and exact scratch addresses.
g_transition_power_emit_start:.skip 8
g_transition_power_temp_start:.skip 8
g_transition_power_result_index:.skip 4
g_transition_power_result_dense:.skip 4
g_transition_power_slice_count:.skip 4
g_transition_slice_changed:.skip 4
.p2align 3
g_transition_power_scratch_base:.skip 8
g_transition_power_matrix_base:.skip 8
g_transition_power_bias_base:.skip 8
.p2align 6
g_fragment_count:.skip 4
g_parallel_error:.skip 4
g_image_code_ptr:.skip 8
g_image_code_len:.skip 8
g_graph_arena_ptr:.skip 8
g_graph_arena_bytes:.skip 8
g_fragment_capacity:.skip 4
g_fragment_start_ptr:.skip 8
g_fragment_end_ptr_ptr:.skip 8
g_fragment_nodes_ptr:.skip 8
g_fragment_kind_ptr:.skip 8
g_fragment_static_ptr:.skip 8
g_fragment_memory_ops_ptr:.skip 8
g_current_fragment_memory_ops:.skip 4
g_fragment_emit_open:.skip 4
g_orig_indegree_ptr:.skip 8
g_work_indegree_ptr:.skip 8
g_succ_count_ptr:.skip 8
g_sole_succ_ptr:.skip 8
g_topo_queue_ptr:.skip 8
g_topo_order_ptr:.skip 8
g_region_of_ptr:.skip 8
g_region_head_ptr:.skip 8
g_region_len_ptr:.skip 8
g_region_indegree_ptr:.skip 8
g_region_first_out_ptr:.skip 8
g_region_entry_offsets_ptr:.skip 8
g_region_realization_ptr:.skip 8
g_dep_visit_ptr:.skip 8
g_edge_u_ptr:.skip 8
g_edge_v_ptr:.skip 8
g_edge_transfer_ptr:.skip 8
g_edge_arena_bytes:.skip 8
g_edge_transfer_arena_bytes:.skip 8
g_edge_capacity:.skip 4
g_edge_count:.skip 4
g_region_count:.skip 4
g_region_edge_u_ptr:.skip 8
g_region_edge_v_ptr:.skip 8
g_region_next_edge_ptr:.skip 8
g_region_edge_transfer_ptr:.skip 8
g_region_edge_arena_ptr:.skip 8
g_region_edge_arena_bytes:.skip 8
g_region_edge_capacity:.skip 4
g_region_edge_count:.skip 4
.p2align 3
g_code_ptr:.skip 8
g_code_capacity:.skip 8
g_code_capacity_prev:.skip 8
g_parallel_code_ptr:.skip 8
g_parallel_code_capacity:.skip 8
g_parallel_code_capacity_prev:.skip 8

.section .rodata
gc_f32_min: .byte 0x59,0x58,0x66,0x0F,0x6E,0xC9,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,0x5D,0xC1,0x66,0x0F,0x7E,0xC0,0x50; gc_f32_min_end:

.section .rodata
gc_f32_max: .byte 0x59,0x58,0x66,0x0F,0x6E,0xC9,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,0x5F,0xC1,0x66,0x0F,0x7E,0xC0,0x50; gc_f32_max_end:

.section .rodata
gc_zero_lhs_stack: pop rcx; xor eax,eax; push rax; push rcx; gc_zero_lhs_stack_end:

.bss
.p2align 3
g_packet_ready:.skip 4
g_packet_native_nodes:.skip 4

g_packet_axis_offsets_ptr:.skip 8

.bss
.p2align 2
g_phys_cse_memory_carrier:.skip 4
g_packet_scalar_lane:.skip 4
g_packet_slot_memory_base:.skip 4

.section .rodata
gv_fma: .ascii "fma"

.bss
.p2align 2
g_phys_cse_conditional_visit:.skip 4
.text

.bss
.p2align 3
g_packet_fact_scope_ptr:.skip 8
g_packet_fact_mixed_ptr:.skip 8

.pushsection .rodata
.balign 8
g_rankn_math_layout_facts:
    .quad GENERAL_RANKN_FP_SQRT_VA,GENERAL_RANKN_FP_SQRT_SPANS
    .quad GENERAL_RANKN_FP_EXP_VA,GENERAL_RANKN_FP_EXP_SPANS
    .quad GENERAL_RANKN_FP_LOG_VA,GENERAL_RANKN_FP_LOG_SPANS
    .quad GENERAL_RANKN_FP_SIN_VA,GENERAL_RANKN_FP_SINCOS_SPANS
    .quad GENERAL_RANKN_FP_COS_VA,GENERAL_RANKN_FP_SINCOS_SPANS
.popsection

.include "compiler/rankn_twiddle_fact.inc"

.bss
.p2align 3
# Compiler-only emitted-control fact; no metadata enters the target program.
g_phys_control_edge_serial:.skip 8
.text

.include "compiler/physical_scalar_facts.inc"
.include "compiler/physical_scalar_window.inc"

.include "compiler/physical_region_work.inc"
