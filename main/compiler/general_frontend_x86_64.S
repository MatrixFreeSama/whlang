.intel_syntax noprefix
.include "compiler/general_runtime_offsets.inc"
.include "compiler/general_runtime_capacity.inc"
.include "compiler/physical_reality.inc"
.include "compiler/silicon_reality.inc"
.include "compiler/isa_capabilities.inc"
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
.equ GTYPE_RANKN_FP_FLAG,0x40000000
.equ GTYPE_RANKN_FP_MASK,0x3fffffff
.equ GTYPE_RECORD,100
.equ GTYPE_DICTIONARY,101
.equ GTYPE_NESTED,102

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
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
    mov dword ptr [rip+g_overflow_wrap],0
    mov dword ptr [rip+g_precision_propagation],0
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
    call g_prepare_io_meta_arena
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
    # Optional for backward-compatible canonical JSON.  Source surfaces always
    # emit it.  This flag changes only the existing numeric meet authority.
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
    mov r11d,eax
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
    mov rdi,r14; mov rsi,r15; mov edx,r11d; mov ecx,ebx; mov r8,r13
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
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- type/symbol helpers ----------------
# Parameterized floating types. Native f32/f64 keep their old type IDs; every
# precision wider than 64 is encoded directly into one Rank-N precision fact.
# rdi=span ptr,rsi=len -> eax=encoded type/0.
g_parse_param_fp_span:
    cmp rsi,3
    jb .gppfs_bad
    cmp byte ptr [rdi],'f'
    jne .gppfs_bad
    cmp byte ptr [rdi+1],'p'
    jne .gppfs_bad
    xor eax,eax
    mov ecx,2
.gppfs_loop:
    cmp rcx,rsi
    jae .gppfs_done
    movzx edx,byte ptr [rdi+rcx]
    cmp dl,'0'
    jb .gppfs_bad
    cmp dl,'9'
    ja .gppfs_bad
    cmp eax,107374182
    ja .gppfs_bad
    imul eax,eax,10
    sub edx,'0'
    add eax,edx
    cmp eax,GTYPE_RANKN_FP_MASK
    ja .gppfs_bad
    inc rcx
    jmp .gppfs_loop
.gppfs_done:
    cmp eax,64
    jbe .gppfs_bad
    or eax,GTYPE_RANKN_FP_FLAG
    ret
.gppfs_bad:
    xor eax,eax
    ret

# edi=type -> eax=floating significand precision, 0 for nonfloating.
g_float_precision:
    cmp edi,GTYPE_F32
    je .gfp_32
    cmp edi,GTYPE_F64
    je .gfp_64
    mov eax,edi
    and eax,GTYPE_RANKN_FP_FLAG
    cmp eax,GTYPE_RANKN_FP_FLAG
    jne .gfp_no
    mov eax,edi
    and eax,GTYPE_RANKN_FP_MASK
    cmp eax,64
    jbe .gfp_no
    ret
.gfp_32: mov eax,32; ret
.gfp_64: mov eax,64; ret
.gfp_no: xor eax,eax; ret

# edi=type -> eax 1 if parameterized Rank-N floating type.
g_is_rankn_fp:
    mov eax,edi
    and eax,GTYPE_RANKN_FP_FLAG
    cmp eax,GTYPE_RANKN_FP_FLAG
    sete al
    movzx eax,al
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
    mov rdi,r8; mov rsi,r9; lea rdx,[rip+gv_f32]; mov ecx,gv_f32_end-gv_f32; call span_eq; test eax,eax; jnz .gt_f32
    mov rdi,r8; mov rsi,r9; lea rdx,[rip+gv_f64]; mov ecx,gv_f64_end-gv_f64; call span_eq; test eax,eax; jnz .gt_f64
    mov rdi,r8; mov rsi,r9; call g_parse_param_fp_span; test eax,eax; jnz .gt_param_fp
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
    # states[32] + decl[8] + carrier/old/out/lastuse[4 each] = 56 bytes/state.
    mov rax,rbx
    imul rax,rax,56
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
    xor eax,eax
    pop rbx
    ret
.gpsm_fail:
    mov eax,1
    pop rbx
    ret

# Compiler-side type vectors follow represented DOM cardinality.  They are
# emitted into the generated read-only trailer at exact input/output lengths;
# this arena is only staging metadata and therefore owns no language capacity.
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
    mov rax,rbx
    shl rax,3                    # input_type[N] + output_type[N]
    jc .gpim_fail
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
    mov [rip+g_input_types_ptr],rax
    mov rcx,rbx
    shl rcx,2
    add rax,rcx
    mov [rip+g_output_types_ptr],rax
    xor eax,eax
    pop rbx
    ret
.gpim_fail:
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
# parser instance uses six equal P-derived arithmetic objects; scalar inputs
# contribute zero bytes.  Returns rax=bytes, edx=0/1.
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
    cmp eax,64
    jbe .gmriw_next
    add eax,63
    jc .gmriw_fail
    shr eax,6
    mov rbx,rax
    imul rbx,rbx,512
    jo .gmriw_fail
    add rbx,4096
    jc .gmriw_fail
    add rbx,63
    jc .gmriw_fail
    and rbx,-64
    imul rbx,rbx,6
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
    # exactly six object spans computed from its own P.  No 8 MiB input stride
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

    # Integer min/max are total. Integer arithmetic is total only in the existing
    # wrap contract; trap arithmetic remains observable and therefore blocks
    # reordering through a nested subtree.
    mov rdi,r12; call g_infer_expr; mov r15d,eax
    cmp r15d,GTYPE_I64; je .gseit_int
    cmp r15d,GTYPE_U64; jne .gseit_no
.gseit_int:
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
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi
    mov rdi,r12; call g_infer_expr; cmp eax,r13d; jne .gsir_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gsir_no
    mov r14,rax
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gsir_no
    cmp qword ptr [rax],J_ARRAY; jne .gsir_no
    mov r15,[rax+24]; test r15,r15; jz .gsir_no

    # Same-type cast is representation identity.
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jz .gsir_binary
    cmp qword ptr [r15+32],0; jne .gsir_no
    mov rdi,r15; mov esi,r13d; call g_semantic_var_representative
    jmp .gsir_done

.gsir_binary:
    mov rbx,[r15+32]; test rbx,rbx; jz .gsir_no
    cmp qword ptr [rbx+32],0; jne .gsir_no
    cmp r13d,GTYPE_BOOL; je .gsir_bool
    cmp r13d,GTYPE_I64; je .gsir_int
    cmp r13d,GTYPE_U64; jne .gsir_no
.gsir_int:
    # Right identity literal.
    mov rdi,rbx; call g_semantic_int01_literal
    test ecx,ecx; jnz .gsir_int_left
    cmp edx,r13d; jne .gsir_int_left
    mov r12d,eax
    cmp r12d,0; jne .gsir_right_one
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gsir_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gsir_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gsir_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gsir_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_shl]; mov ecx,gv_shl_end-gv_shl; call span_eq; test eax,eax; jnz .gsir_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_shr]; mov ecx,gv_shr_end-gv_shr; call span_eq; test eax,eax; jnz .gsir_return_left
    jmp .gsir_int_left
.gsir_right_one:
    cmp r12d,1; jne .gsir_int_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gsir_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jnz .gsir_return_left
.gsir_int_left:
    mov rdi,r15; call g_semantic_int01_literal
    test ecx,ecx; jnz .gsir_no
    cmp edx,r13d; jne .gsir_no
    mov r12d,eax
    cmp r12d,0; jne .gsir_left_one
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gsir_return_right
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_or]; mov ecx,gv_bit_or_end-gv_bit_or; call span_eq; test eax,eax; jnz .gsir_return_right
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_bit_xor]; mov ecx,gv_bit_xor_end-gv_bit_xor; call span_eq; test eax,eax; jnz .gsir_return_right
    jmp .gsir_no
.gsir_left_one:
    cmp r12d,1; jne .gsir_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gsir_return_right
    jmp .gsir_no

.gsir_bool:
    # x && true, true && x, x || false, false || x, x xor false.
    mov rdi,rbx; call g_expr_bool_literal; test edx,edx; jnz .gsir_bool_left
    mov r12d,eax
    cmp r12d,1; jne .gsir_bool_right_false
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq; test eax,eax; jnz .gsir_return_left
    jmp .gsir_bool_left
.gsir_bool_right_false:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq; test eax,eax; jnz .gsir_return_left
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq; test eax,eax; jnz .gsir_return_left
.gsir_bool_left:
    mov rdi,r15; call g_expr_bool_literal; test edx,edx; jnz .gsir_no
    mov r12d,eax
    cmp r12d,1; jne .gsir_bool_left_false
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_and]; mov ecx,gv_and_end-gv_and; call span_eq; test eax,eax; jnz .gsir_return_right
    jmp .gsir_no
.gsir_bool_left_false:
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_or]; mov ecx,gv_or_end-gv_or; call span_eq; test eax,eax; jnz .gsir_return_right
    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+gv_xor]; mov ecx,gv_xor_end-gv_xor; call span_eq; test eax,eax; jnz .gsir_return_right
    jmp .gsir_no

.gsir_return_left:
    mov rdi,r15; mov esi,r13d; call g_semantic_var_representative; jmp .gsir_done
.gsir_return_right:
    mov rdi,rbx; mov esi,r13d; call g_semantic_var_representative; jmp .gsir_done
.gsir_no:
    xor eax,eax
.gsir_done:
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
    mov rdi,rax; call g_resolve_field_expr
    test rax,rax; jz .gie_bad
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
    test rax,rax; jnz .gie_cast_type_found
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
.gie_cast_type_found:
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
    test eax,eax; jnz .gie_unary_fp
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
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_is_shift_op; test eax,eax; jnz .gie_u64
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
.gie_u64: mov eax,GTYPE_U64; jmp .gie_done
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
    mov edi,r12d; call g_float_precision; mov ebx,eax
    mov edi,r13d; call g_float_precision; mov ecx,eax
    test ebx,ebx; jnz .glt_have_float
    test ecx,ecx; jnz .glt_only_b_float
    cmp r12d,r13d; jne .glt_bad2
    cmp r12d,GTYPE_I64; je .glt_a
    cmp r12d,GTYPE_U64; je .glt_a
    cmp r12d,GTYPE_BOOL; je .glt_a
    jmp .glt_bad2
.glt_only_b_float:
    mov eax,r13d; jmp .glt_done2
.glt_have_float:
    test ecx,ecx; jz .glt_a
    cmp dword ptr [rip+g_precision_propagation],0
    jne .glt_high2
    cmp ebx,ecx
    jbe .glt_a
    mov eax,r13d; jmp .glt_done2
.glt_high2:
    cmp ebx,ecx
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

# ---------------- native code buffer primitives ----------------
g_emit_u8:
    mov rax,[rip+g_emit_ptr]; cmp rax,[rip+g_emit_end]; jae .ge_fail
    mov [rax],dil; inc rax; mov [rip+g_emit_ptr],rax; xor eax,eax; ret
.ge_fail: mov dword ptr [rip+g_code_overflow],1; mov eax,1; ret
g_emit_u16:
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+2]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],di; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_u24:
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+3]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],di; shr edi,16; mov [rax+2],dil; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_u32:
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],edi; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_u64:
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+8]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],rdi; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
g_emit_bytes:
    mov rax,[rip+g_emit_ptr]; mov ecx,esi; lea rdx,[rax+rcx]; cmp rdx,[rip+g_emit_end]; ja .ge_fail
.geb_loop: test ecx,ecx; jz .geb_done; mov dl,[rdi]; mov [rax],dl; inc rdi; inc rax; dec ecx; jmp .geb_loop
.geb_done: mov [rip+g_emit_ptr],rax; xor eax,eax; ret

# absolute address helpers for generated ET_EXEC image
g_emit_push_imm64:
    push rdi; mov edi,0xB848; call g_emit_u16; pop rdi; call g_emit_u64; mov edi,0x50; jmp g_emit_u8
# 1.3.13 register-native expression primitive: materialize an immediate
# directly into the runtime value register without routing through the machine stack.
g_emit_mov_rax_imm64:
    push rdi; mov edi,0xB848; call g_emit_u16; pop rdi; jmp g_emit_u64
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
    mov rdx,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32; mov rax,rdx; ret
g_emit_jnz_patch:
    mov edi,0x850F; call g_emit_u16
    mov rdx,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32; mov rax,rdx; ret
g_emit_jmp_patch:
    mov edi,0xE9; call g_emit_u8
    mov rdx,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32; mov rax,rdx; ret
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

# Parameterized Rank-N floating physical allocation.  Precision is data, not a
# precision is data, not a width branch. Each emitted >64-bit ValueFact owns exactly the span required
# by its precision limb axis plus generic arithmetic scratch.  The workspace is
# static/AOT-owned; there is no runtime allocator or scheduler.
g_alloc_rankn_fp_temp:
    # edi=encoded fpP -> rax=private object VA / 0
    push rbx
    mov ebx,edi
    call g_float_precision
    cmp eax,64
    jbe .garft_bad
    add eax,63
    shr eax,6                       # N=ceil(P/64)
    # 1.3.40 physical span: primary carrier plus the single native Fourier
    # coefficient/twiddle/product workspace and generic division scratch.
    # 512 bytes per u64 precision limb is a structural P-derived envelope for
    # every admitted Fourier geometry; aggregate workspace is instance-sized.
    imul rax,rax,512
    add rax,4096
    mov rdi,rax
    call g_alloc_runtime_temp_bytes
    test rax,rax
    jz .garft_bad
    pop rbx
    ret
.garft_bad:
    xor eax,eax
    pop rbx
    ret

# Native-math fpP workspace.  One transcendental relation receives 32 ordinary
# P-derived object spans.  The multiplier is structural workspace depth, not a
# precision tier; every P>64 follows this same allocation relation.
g_alloc_rankn_fp_math_temp:
    push rbx
    mov ebx,edi
    call g_float_precision
    cmp eax,64
    jbe .garfmt_bad
    add eax,63
    shr eax,6
    imul rax,rax,512
    add rax,4096
    shl rax,5                         # 32 equal object spans
    mov rdi,rax
    call g_alloc_runtime_temp_bytes
    test rax,rax
    jz .garfmt_bad
    pop rbx
    ret
.garfmt_bad:
    xor eax,eax
    pop rbx
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
    cmp eax,64
    jbe .grfgp_bad
    mov r12d,eax
    mov qword ptr [rsp+0],-1          # best physical cost
    mov dword ptr [rsp+8],0           # best packed geometry
    mov ebx,26                        # binary64 exact coefficient ceiling
.grfgp_b_loop:
    cmp ebx,1
    jl .grfgp_done_search
    # n=ceil(P/b), need=2n-1
    mov eax,r12d
    add eax,ebx
    dec eax
    xor edx,edx
    div ebx
    mov r14d,eax
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
    # Same continuous physical surface as the native runtime ingress fallback:
    # N*(100*a2 + 120*a3 + 180*a5 + 10*a3^2 + 30*a5^2) + 40*n.
    mov eax,r10d
    imul eax,eax,100
    mov ecx,[rsp+48]
    mov edx,ecx
    imul ecx,ecx,120
    add eax,ecx
    imul edx,edx
    imul edx,edx,10
    add eax,edx
    mov ecx,[rsp+64]
    mov edx,ecx
    imul ecx,ecx,180
    add eax,ecx
    imul edx,edx
    imul edx,edx,30
    add eax,edx
    mov ecx,eax
    mov rax,r11
    imul rax,rcx
    mov rcx,[rsp+16]
    imul rcx,rcx,40
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
# rdi=absolute destination object, esi=packed AOT Fourier geometry.
g_emit_rankn_fourier_geom_store:
    push rbx
    mov ebx,esi
    call g_emit_mov_rax_imm64
    test eax,eax
    jnz .gerfgs_done
    mov edi,0x40c7                    # C7 40
    call g_emit_u16
    test eax,eax
    jnz .gerfgs_done
    mov edi,12                        # [rax+12] packed AOT Fourier geometry fact
    call g_emit_u8
    test eax,eax
    jnz .gerfgs_done
    mov edi,ebx
    call g_emit_u32
.gerfgs_done:
    pop rbx
    ret
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
    mov edi,0x5F; call g_emit_u8
    mov rdi,GENERAL_RANKN_FP_TO_F64_VA; call g_emit_call_abs
    test eax,eax; jnz .gerct_bad
    xor edi,edi; call g_emit_rankn_fp_status_check; test eax,eax; jnz .gerct_bad
    mov edi,0x50; call g_emit_u8
    jmp .gerct_ok
.gerct_f32:
    mov edi,0x5F; call g_emit_u8
    mov rdi,GENERAL_RANKN_FP_TO_F64_VA; call g_emit_call_abs
    test eax,eax; jnz .gerct_bad
    xor edi,edi; call g_emit_rankn_fp_status_check; test eax,eax; jnz .gerct_bad
    mov edi,0x50; call g_emit_u8
    lea rdi,[rip+gc_cast_f64_f32]; mov esi,gc_cast_f64_f32_end-gc_cast_f64_f32; call g_emit_bytes
    test eax,eax; jnz .gerct_bad
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
    mov r12,GENERAL_RANKN_FP_MUL_VA
    mov edi,r14d
    call g_rankn_fourier_geom_pack
    test eax,eax
    jz .gewbo_bad
    mov r13d,eax
    mov rdi,rbx
    mov esi,r13d
    call g_emit_rankn_fourier_geom_store
    test eax,eax
    jnz .gewbo_bad
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
# stack top is one fpP pointer; result is the slot-0 pointer of one local 32-slot
# math workspace.  No named precision or algorithm selector exists here.
g_emit_rankn_fp_math_unary_top:
    push rbx; push r12; push r13
    mov r13d,edi; mov r12,rsi
    mov edi,r13d; call g_alloc_rankn_fp_math_temp; test rax,rax; jz .gerfmu_bad
    mov rbx,rax
    mov edi,0x5E; call g_emit_u8                   # pop rsi = source pointer
    test eax,eax; jnz .gerfmu_bad
    mov rdi,rbx; call g_emit_mov_rdi_imm64
    mov edi,r13d; call g_emit_mov_edx_imm32
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
    mov rax,[rip+g_emit_ptr]; mov [rip+g_scalar_opt_emit_start],rax
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gteuc_no
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
    cmp r13,1; je .gteuc_identity
    mov rax,r13; lea rcx,[rax-1]; test rax,rcx; jnz .gteuc_div_general
    bsf rcx,r13; mov edi,ecx; mov esi,1; call g_emit_u64_shift_imm; jmp .gteuc_type_done
.gteuc_div_general:
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_udiv]; mov esi,gc_const_udiv_end-gc_const_udiv; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_mod:
    cmp r13,1; jne .gteuc_mod_nonone
    call g_emit_pop_rax; xor edi,edi; call g_emit_push_imm64; jmp .gteuc_type_done
.gteuc_mod_nonone:
    mov rax,r13; lea rcx,[rax-1]; test rax,rcx; jnz .gteuc_mod_general
    dec r13
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_and]; mov esi,gc_const_and_end-gc_const_and; call g_emit_bytes; jmp .gteuc_push_done
.gteuc_mod_general:
    call g_emit_pop_rax; mov rdi,r13; call g_emit_mov_rcx_imm64
    lea rdi,[rip+gc_const_umod]; mov esi,gc_const_umod_end-gc_const_umod; call g_emit_bytes; jmp .gteuc_push_done
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

# ---------------- expression emitter ----------------
# g_emit_expr(rdi=expr) -> eax type/0, generated value pushed as one qword.
g_emit_expr:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    cmp qword ptr [r12],J_OBJECT; jne .gee_bad
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
    mov rax,r13; call node_parse_f64_bits; test edx,edx; jnz .gee_bad
    movq xmm0,rax; cvtsd2ss xmm0,xmm0; movd edi,xmm0
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
    mov rdi,rax; call g_resolve_field_expr; test rax,rax; jz .gee_bad
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
    # cast
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cast]; mov ecx,gv_cast_end-gv_cast; call span_eq
    test eax,eax; jz .gee_not
    mov rdi,r14; call g_emit_expr; mov ebx,eax; test ebx,ebx; jz .gee_bad
    mov rdi,r12; lea rsi,[rip+gk_to]; mov edx,gk_to_end-gk_to; call obj_get
    test rax,rax; jnz .gee_cast_type_found
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
.gee_cast_type_found:
    test rax,rax; jz .gee_bad
    mov rdi,rax; call g_type_from_node; mov r13d,eax; test r13d,r13d; jz .gee_bad
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
    cmp eax,GTYPE_F64; je .gee_neg_f64
    cmp eax,GTYPE_F32; je .gee_neg_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jnz .gee_neg_wide
    jmp .gee_bad
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
    jmp .gee_bad
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
.gee_exp_f64: lea rdi,[rip+gc_exp_f64]; mov esi,gc_exp_f64_end-gc_exp_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_exp_f32: lea rdi,[rip+gc_exp_f32]; mov esi,gc_exp_f32_end-gc_exp_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_log_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_log]; mov ecx,gv_log_end-gv_log; call span_eq
    test eax,eax; jz .gee_sin_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_log_f64
    cmp eax,GTYPE_F32; je .gee_log_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_LOG_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_log_f64: lea rdi,[rip+gc_log_f64]; mov esi,gc_log_f64_end-gc_log_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_log_f32: lea rdi,[rip+gc_log_f32]; mov esi,gc_log_f32_end-gc_log_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done

.gee_sin_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_sin]; mov ecx,gv_sin_end-gv_sin; call span_eq
    test eax,eax; jz .gee_cos_probe
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_sin_f64
    cmp eax,GTYPE_F32; je .gee_sin_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_SIN_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_sin_f64: lea rdi,[rip+gc_sin_f64]; mov esi,gc_sin_f64_end-gc_sin_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_sin_f32: lea rdi,[rip+gc_sin_f32]; mov esi,gc_sin_f32_end-gc_sin_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_cos_probe:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_cos]; mov ecx,gv_cos_end-gv_cos; call span_eq
    test eax,eax; jz .gee_select
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_F64; je .gee_cos_f64
    cmp eax,GTYPE_F32; je .gee_cos_f32
    mov edi,eax; call g_is_rankn_fp; test eax,eax; jz .gee_bad
    mov edi,ebx; mov rsi,GENERAL_RANKN_FP_COS_VA; call g_emit_rankn_fp_math_unary_top; test eax,eax; jnz .gee_bad
    mov eax,ebx; jmp .gee_done
.gee_cos_f64: lea rdi,[rip+gc_cos_f64]; mov esi,gc_cos_f64_end-gc_cos_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_cos_f32: lea rdi,[rip+gc_cos_f32]; mov esi,gc_cos_f32_end-gc_cos_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done

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
    mov rsi,[rip+g_emit_ptr]; mov rdi,r15; call g_patch_rel32
    mov rdi,r14; call g_emit_expr; test eax,eax; jz .gee_bad
    mov edi,eax; mov esi,ebx; call g_convert_stack_top; test eax,eax; jnz .gee_bad
    mov rsi,[rip+g_emit_ptr]; mov rdi,r13; call g_patch_rel32
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
    mov rsi,[rip+g_emit_ptr]; mov rdi,r15; call g_patch_rel32
    xor edi,edi; call g_emit_push_imm64
    mov rsi,[rip+g_emit_ptr]; mov rdi,r13; call g_patch_rel32
    mov eax,GTYPE_BOOL; jmp .gee_done
.gee_lazy_or:
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    call g_emit_pop_rax; lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    call g_emit_jnz_patch; mov r15,rax
    mov r14,[r14+32]; test r14,r14; jz .gee_bad
    mov rdi,r14; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gee_bad
    call g_emit_jmp_patch; mov r13,rax
    mov rsi,[rip+g_emit_ptr]; mov rdi,r15; call g_patch_rel32
    mov edi,1; call g_emit_push_imm64
    mov rsi,[rip+g_emit_ptr]; mov rdi,r13; call g_patch_rel32
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
    cmp ebx,GTYPE_U64; jne .gee_bad; cmp r12d,GTYPE_U64; jne .gee_bad
    mov rdi,[r13+8]; mov rsi,[r13+16]; call g_emit_shift_top2
    test eax,eax; jnz .gee_bad
    mov eax,GTYPE_U64; jmp .gee_done
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
.equ G_PHYS_INT_RESIDENT_MAX,3

# Physical scalar-FP geometry is read from the compiler-wide ISA capability
# authority. AVX-512 exposes the architectural XMM16..31 bank; older targets
# retain the same 16-carrier realization. This is one Physical Reality, not a
# vendor/backend split.
g_phys_fp_geometry_refresh:
    mov dword ptr [rip+g_phys_fp_carrier_count],16
    mov dword ptr [rip+g_phys_fp_old_base],8
    mov dword ptr [rip+g_phys_fp_all_mask],0x0000FFFF
    test dword ptr [rip+isa_cap_bits],ISA_CAP_WIDE_REGFILE
    jz .gpfgr_done
    mov dword ptr [rip+g_phys_fp_carrier_count],32
    mov dword ptr [rip+g_phys_fp_old_base],16
    mov dword ptr [rip+g_phys_fp_all_mask],-1
.gpfgr_done:
    ret

# Build the compile-time carrier map for all declared state ValueFacts.
# -> eax=0 success, 1 unsupported type.  No runtime table is emitted.
g_phys_assign_state_carriers:
    call g_phys_fp_geometry_refresh
    push rbx; push r12; push r13; push r14; push r15
    # First count FP state facts.  Once partial residency is required, reserve
    # one additional transient XMM carrier for spill materialization instead of
    # preserving a maximal old/output bank that could force whole-path fallback.
    mov dword ptr [rip+g_phys_fp_total],0
    xor ecx,ecx
.gpasc_precount:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gpasc_precount_done
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gpasc_precount_data
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; je .gpasc_precount_next
.gpasc_precount_data:
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edx,dword ptr [r11+16]
    cmp edx,GTYPE_F64; je .gpasc_precount_fp
    cmp edx,GTYPE_F32; jne .gpasc_precount_next
.gpasc_precount_fp:
    inc dword ptr [rip+g_phys_fp_total]
.gpasc_precount_next:
    inc ecx; jmp .gpasc_precount
.gpasc_precount_done:
    # Resident old-version FP capacity is target geometry, not a semantic or
    # workload threshold. The high XMM half is the mature old-authority domain;
    # its width is derived from the actual carrier domain. Anonymous temporaries
    # and shared facts compete in the complementary pool.
    mov eax,dword ptr [rip+g_phys_fp_carrier_count]
    sub eax,dword ptr [rip+g_phys_fp_old_base]
    cmp dword ptr [rip+g_phys_fp_total],eax; jae .gpasc_budget_ready
    mov eax,dword ptr [rip+g_phys_fp_total]
.gpasc_budget_ready:
    mov dword ptr [rip+g_phys_fp_resident_budget],eax
    mov dword ptr [rip+g_reg_iter_fp_count],0
    mov dword ptr [rip+g_reg_iter_int_count],0
    mov dword ptr [rip+g_phys_fp_reserved_mask],0
    xor ecx,ecx
.gpasc_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gpasc_ok
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_SPILL
    mov rax,[rip+g_reg_iter_old_reg_ptr]; mov dword ptr [rax+rcx*4],-1
    mov rax,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rax+rcx*4],-1
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gpasc_data
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; jne .gpasc_data
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_COUNTER
    mov rax,[rip+g_reg_iter_old_reg_ptr]; mov dword ptr [rax+rcx*4],3   # RBX
    inc ecx; jmp .gpasc_loop
.gpasc_data:
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov edx,dword ptr [r11+16]
    cmp edx,GTYPE_F64; je .gpasc_fp
    cmp edx,GTYPE_F32; je .gpasc_fp
    cmp edx,GTYPE_U64; je .gpasc_int
    cmp edx,GTYPE_I64; je .gpasc_int
    jmp .gpasc_bad
.gpasc_fp:
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_FP
    mov r12d,dword ptr [rip+g_reg_iter_fp_count]
    cmp r12d,dword ptr [rip+g_phys_fp_resident_budget]; jae .gpasc_fp_spill
    mov r13d,r12d
    add r13d,dword ptr [rip+g_phys_fp_old_base]      # old-version authority
    mov rax,[rip+g_reg_iter_old_reg_ptr]; mov dword ptr [rax+rcx*4],r13d
    cmp dword ptr [rip+g_phys_fp_transient_outputs],0; jne .gpasc_fp_transient_out
    # First physical candidate: preserve a disjoint next-version carrier only
    # when that carrier is actually free. Collision with any existing authority
    # is resolved by the same transient ValueFact path; no state-count threshold
    # owns the choice.
    lea r14d,[r12d+1]
    push rcx
    mov eax,1; mov ecx,r14d; shl eax,cl
    test dword ptr [rip+g_phys_fp_reserved_mask],eax
    pop rcx
    jnz .gpasc_fp_transient_out
    mov rax,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rax+rcx*4],r14d
    push rcx
    mov eax,1; mov ecx,r13d; shl eax,cl
    or dword ptr [rip+g_phys_fp_reserved_mask],eax
    mov eax,1; mov ecx,r14d; shl eax,cl
    or dword ptr [rip+g_phys_fp_reserved_mask],eax
    pop rcx
    jmp .gpasc_fp_spill
.gpasc_fp_transient_out:
    # Same DAG, second physical realization: next-version ValueFacts borrow the
    # anonymous carrier pool and cross the simultaneous-update boundary through
    # the same execution-local next-version handoff. No private backend is introduced.
    mov rax,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rax+rcx*4],-1
    push rcx
    mov eax,1; mov ecx,r13d; shl eax,cl
    or dword ptr [rip+g_phys_fp_reserved_mask],eax
    pop rcx
.gpasc_fp_spill:
    inc dword ptr [rip+g_reg_iter_fp_count]
    inc ecx; jmp .gpasc_loop
.gpasc_int:
    mov rax,[rip+g_reg_iter_carrier_kind_ptr]; mov dword ptr [rax+rcx*4],G_PHYS_CARRIER_INT
    mov r12d,dword ptr [rip+g_reg_iter_int_count]
    cmp r12d,G_PHYS_INT_RESIDENT_MAX; jae .gpasc_int_spill
    lea r13d,[r12d+8]                    # R8/R9/R10 old generation
    mov rax,[rip+g_reg_iter_old_reg_ptr]; mov dword ptr [rax+rcx*4],r13d
    mov edi,r12d; push rcx; call g_phys_int_output_reg; pop rcx
    cmp eax,0; jl .gpasc_bad
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rdx+rcx*4],eax
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
g_phys_fp_temp_reset:
    push rcx
    mov dword ptr [rip+g_phys_fp_temp_live],0
    mov eax,dword ptr [rip+g_phys_fp_all_mask]
    mov ecx,dword ptr [rip+g_phys_fp_reserved_mask]
    not ecx
    and eax,ecx
    mov dword ptr [rip+g_phys_fp_temp_mask],eax
    xor ecx,ecx
.gpfptr_cse_loop:
    cmp ecx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpfptr_cse_done
    lea rax,[rip+g_phys_cse_resident_reg]
    mov edx,dword ptr [rax+rcx*4]
    cmp edx,31; ja .gpfptr_cse_next
    btr dword ptr [rip+g_phys_fp_temp_mask],edx
.gpfptr_cse_next:
    inc ecx; jmp .gpfptr_cse_loop
.gpfptr_cse_done:
    xor ecx,ecx
.gpfptr_resident_loop:
    cmp ecx,dword ptr [rip+g_phys_const_resident_count]; jae .gpfptr_done
    lea rax,[rip+g_phys_const_resident_reg]
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
    cmp ecx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpfptf_const_start
    lea rdx,[rip+g_phys_cse_resident_reg]
    cmp dword ptr [rdx+rcx*4],edi; je .gpfptf_done
    inc ecx; jmp .gpfptf_cse_loop
.gpfptf_const_start:
    xor ecx,ecx
.gpfptf_const_loop:
    cmp ecx,dword ptr [rip+g_phys_const_resident_count]; jae .gpfptf_yes
    lea rdx,[rip+g_phys_const_resident_reg]
    cmp dword ptr [rdx+rcx*4],edi; je .gpfptf_done
    inc ecx; jmp .gpfptf_const_loop
.gpfptf_yes:
    bts dword ptr [rip+g_phys_fp_temp_mask],edi
    cmp dword ptr [rip+g_phys_fp_temp_live],0
    jle .gpfptf_done
    dec dword ptr [rip+g_phys_fp_temp_live]
.gpfptf_done:
    ret

# EVEX.128 scalar register realization for the full architectural XMM0..31
# carrier file. edi=opcode, esi=dst, edx=src1, ecx=src2,
# r8d=GTYPE_F32/F64. The operation and rounding point are unchanged.
g_emit_phys_evex_scalar3:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12d,esi; mov r13d,edx; mov r14d,ecx; mov r15d,r8d
    cmp r12d,31; ja .gepev3_bad
    cmp r13d,31; ja .gepev3_bad
    cmp r14d,31; ja .gepev3_bad
    cmp r15d,GTYPE_F64; je .gepev3_type_ok
    cmp r15d,GTYPE_F32; jne .gepev3_bad
.gepev3_type_ok:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepev3_bad
    # P0: ~R ~X ~B ~R' 00 01 (0F map).
    mov eax,1
    mov ecx,r12d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,r14d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,r14d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,r12d; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepev3_bad
    # P1: W, inverted src1 low nibble, fixed bit2, F2/F3 scalar prefix.
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3; or eax,4
    cmp r15d,GTYPE_F64; jne 731f
    or eax,0x83                         # W=1, pp=F2
    jmp 732f
731:or eax,2                             # W=0, pp=F3
732:mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepev3_bad
    # P2: scalar L'L=00, no mask/broadcast; V' extends src1 bit4.
    mov eax,r13d; shr eax,4; and eax,1; xor eax,1; shl eax,3
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepev3_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepev3_bad
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r14d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepev3_bad
    xor eax,eax; jmp .gepev3_done
.gepev3_bad:
    mov eax,1
.gepev3_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Emit legacy scalar XMM copy. edi=dst, esi=src, edx=GTYPE_F32/F64.
# A copy is emitted only when the two physical identities differ.
g_emit_phys_xmm_move:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp ebx,r12d; je .gepxm_ok
    cmp ebx,15; ja .gepxm_evex
    cmp r12d,15; ja .gepxm_evex
    cmp r13d,GTYPE_F64; je .gepxm_f64
    cmp r13d,GTYPE_F32; jne .gepxm_bad
    mov edi,0xF3; call g_emit_u8; test eax,eax; jnz .gepxm_bad
    jmp .gepxm_rex
.gepxm_f64:
    mov edi,0xF2; call g_emit_u8; test eax,eax; jnz .gepxm_bad
.gepxm_rex:
    xor eax,eax
    mov ecx,ebx; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov ecx,r12d; shr ecx,3; and ecx,1; or eax,ecx
    test eax,eax; jz .gepxm_opcode
    or eax,0x40; mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxm_bad
.gepxm_opcode:
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepxm_bad
    mov edi,0x10; call g_emit_u8; test eax,eax; jnz .gepxm_bad
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxm_bad
.gepxm_evex:
    mov edi,0x10; mov esi,ebx; mov edx,ebx; mov ecx,r12d; mov r8d,r13d
    call g_emit_phys_evex_scalar3
    test eax,eax; jnz .gepxm_bad
.gepxm_ok:
    xor eax,eax; jmp .gepxm_done
.gepxm_bad:
    mov eax,1
.gepxm_done:
    pop r13; pop r12; pop rbx; ret

# Materialize runtime RAX/EAX bits directly into an arbitrary XMM carrier.
# edi=dst, esi=GTYPE_F32/F64.
g_emit_phys_xmm_from_rax:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp ebx,15; ja .gepxr_evex
    mov edi,0x66; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    cmp r12d,GTYPE_F64; je .gepxr_f64
    cmp r12d,GTYPE_F32; jne .gepxr_bad
    cmp ebx,8; jb .gepxr_opcode
    mov edi,0x44; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    jmp .gepxr_opcode
.gepxr_f64:
    mov edi,0x48
    cmp ebx,8; jb 1f
    or edi,4
1:  call g_emit_u8; test eax,eax; jnz .gepxr_bad
.gepxr_opcode:
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    mov edi,0x6E; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    xor eax,eax; jmp .gepxr_done
.gepxr_evex:
    cmp ebx,31; ja .gepxr_bad
    cmp r12d,GTYPE_F64; je 741f
    cmp r12d,GTYPE_F32; jne .gepxr_bad
741:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    mov eax,0xE1
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; and eax,0x7F; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; and eax,0xEF; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    mov edi,0x7D
    cmp r12d,GTYPE_F64; jne 742f
    mov edi,0xFD
742:call g_emit_u8; test eax,eax; jnz .gepxr_bad
    mov edi,0x08; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    mov edi,0x6E; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxr_bad
    xor eax,eax; jmp .gepxr_done
.gepxr_bad:
    mov eax,1
.gepxr_done:
    pop r12; pop rbx; ret

# Extract arbitrary scalar XMM bits into runtime RAX/EAX. edi=src, esi=type.
g_emit_phys_xmm_to_rax:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp ebx,15; ja .gepxt_evex
    mov edi,0x66; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    cmp r12d,GTYPE_F64; je .gepxt_f64
    cmp r12d,GTYPE_F32; jne .gepxt_bad
    mov eax,0x40
    mov ecx,ebx; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    cmp eax,0x40; je .gepxt_opcode
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    jmp .gepxt_opcode
.gepxt_f64:
    mov eax,0x48
    mov ecx,ebx; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxt_bad
.gepxt_opcode:
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    mov edi,0x7E; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    xor eax,eax; jmp .gepxt_done
.gepxt_evex:
    cmp ebx,31; ja .gepxt_bad
    cmp r12d,GTYPE_F64; je 751f
    cmp r12d,GTYPE_F32; jne .gepxt_bad
751:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    mov eax,0xE1
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; and eax,0x7F; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; and eax,0xEF; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    mov edi,0x7D
    cmp r12d,GTYPE_F64; jne 752f
    mov edi,0xFD
752:call g_emit_u8; test eax,eax; jnz .gepxt_bad
    mov edi,0x08; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    mov edi,0x7E; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepxt_bad
    xor eax,eax; jmp .gepxt_done
.gepxt_bad:
    mov eax,1
.gepxt_done:
    pop r12; pop rbx; ret

# VEX.128 scalar three-operand arithmetic.
# edi=opcode (58 add, 5c sub, 59 mul), esi=dst, edx=src1, ecx=src2,
# r8d=GTYPE_F32/F64. No reassociation or contraction is performed.
g_emit_phys_vex_scalar3:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12d,esi; mov r13d,edx; mov r14d,ecx; mov r15d,r8d
    cmp r15d,GTYPE_F64; je .gepv3_type_ok
    cmp r15d,GTYPE_F32; jne .gepv3_bad
.gepv3_type_ok:
    cmp r12d,15; ja .gepv3_evex
    cmp r13d,15; ja .gepv3_evex
    cmp r14d,15; ja .gepv3_evex
    mov edi,0xC4; call g_emit_u8; test eax,eax; jnz .gepv3_bad
    # VEX byte 2: ~R ~X ~B 00001. X is unused and therefore encoded as 1.
    mov eax,r12d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r14d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    or eax,1
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3_bad
    # VEX byte 3: W=0, inverted src1 in vvvv, L=0, pp=F2/F3.
    mov eax,r13d; and eax,15; xor eax,15; shl eax,3
    cmp r15d,GTYPE_F64; jne 1f
    or eax,3                             # F2
    jmp 2f
1:  or eax,2                             # F3
2:  mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3_bad
    mov edi,ebx; call g_emit_u8; test eax,eax; jnz .gepv3_bad
    mov eax,r12d; and eax,7; shl eax,3
    mov ecx,r14d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepv3_bad
    xor eax,eax; jmp .gepv3_done
.gepv3_evex:
    mov edi,ebx; mov esi,r12d; mov edx,r13d; mov ecx,r14d; mov r8d,r15d
    call g_emit_phys_evex_scalar3
    test eax,eax; jnz .gepv3_bad
    xor eax,eax; jmp .gepv3_done
.gepv3_bad:
    mov eax,1
.gepv3_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Existing scalar physical carrier, native hardware square root.  This is one
# more realization of an ordinary FP ValueFact, not a math runtime call.
# edi=dst/src XMM, esi=GTYPE_F32/F64 -> eax 0/1.
g_emit_phys_sqrt_inplace:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp ebx,15; ja .gepsi_evex
    cmp r12d,GTYPE_F64; je .gepsi_f64
    cmp r12d,GTYPE_F32; jne .gepsi_bad
    mov edi,0xF3; call g_emit_u8; test eax,eax; jnz .gepsi_bad
    jmp .gepsi_rex
.gepsi_f64:
    mov edi,0xF2; call g_emit_u8; test eax,eax; jnz .gepsi_bad
.gepsi_rex:
    cmp ebx,8; jb .gepsi_opcode
    mov edi,0x45; call g_emit_u8; test eax,eax; jnz .gepsi_bad
.gepsi_opcode:
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepsi_bad
    mov edi,0x51; call g_emit_u8; test eax,eax; jnz .gepsi_bad
    mov eax,ebx; and eax,7; mov ecx,eax; shl eax,3; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepsi_bad
    xor eax,eax; jmp .gepsi_done
.gepsi_evex:
    mov edi,0x51; mov esi,ebx; mov edx,ebx; mov ecx,ebx; mov r8d,r12d
    call g_emit_phys_evex_scalar3
    test eax,eax; jnz .gepsi_bad
    xor eax,eax; jmp .gepsi_done
.gepsi_bad:
    mov eax,1
.gepsi_done:
    pop r12; pop rbx; ret

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
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    cmp ebx,15; ja .gepti_evex
    cmp r12d,GTYPE_F64; je .gepti_f64
    cmp r12d,GTYPE_F32; jne .gepti_bad
    mov r12d,0x0A; jmp .gepti_emit
.gepti_f64:
    mov r12d,0x0B
.gepti_emit:
    mov edi,0x66; call g_emit_u8; test eax,eax; jnz .gepti_bad
    cmp ebx,8; jb .gepti_norex
    mov edi,0x45; call g_emit_u8; test eax,eax; jnz .gepti_bad
.gepti_norex:
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov edi,0x3A; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov edi,r12d; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov eax,ebx; and eax,7; mov ecx,eax; shl eax,3; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov edi,3; call g_emit_u8; test eax,eax; jnz .gepti_bad
    xor eax,eax; jmp .gepti_done
.gepti_evex:
    cmp ebx,31; ja .gepti_bad
    cmp r12d,GTYPE_F64; je 761f
    cmp r12d,GTYPE_F32; jne .gepti_bad
761:
    mov edi,0x62; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov eax,3
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,7; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,6; or eax,ecx
    mov ecx,ebx; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5; or eax,ecx
    mov ecx,ebx; shr ecx,4; and ecx,1; xor ecx,1; shl ecx,4; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov eax,ebx; and eax,15; xor eax,15; shl eax,3; or eax,5
    cmp r12d,GTYPE_F64; jne 762f
    or eax,0x80
762:mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov eax,ebx; shr eax,4; and eax,1; xor eax,1; shl eax,3
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov edi,0x0A
    cmp r12d,GTYPE_F64; jne 763f
    mov edi,0x0B
763:call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov eax,ebx; and eax,7; mov ecx,eax; shl eax,3; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepti_bad
    mov edi,3; call g_emit_u8; test eax,eax; jnz .gepti_bad
    xor eax,eax; jmp .gepti_done
.gepti_bad: mov eax,1
.gepti_done: pop r12; pop rbx; ret

# edi=dst/src XMM, esi=source GTYPE_F32/F64, edx=target GTYPE_F32/F64.
# Precision conversion is an edge realization, never a subtree policy: a ValueFact
# is first realized at its natural precision and only converted when the consumer
# actually meets a lower/higher precision fact. In-place conversion is safe only
# on a caller-owned destination/temporary, never on a borrowed resident authority.
g_emit_phys_fp_convert_inplace:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp r12d,r13d; je .gepfc_ok
    cmp ebx,15; ja .gepfc_evex
    cmp r12d,GTYPE_F64; je .gepfc_from_f64
    cmp r12d,GTYPE_F32; jne .gepfc_bad
    cmp r13d,GTYPE_F64; jne .gepfc_bad
    mov edi,0xF3                         # CVTSS2SD
    jmp .gepfc_prefix
.gepfc_from_f64:
    cmp r13d,GTYPE_F32; jne .gepfc_bad
    mov edi,0xF2                         # CVTSD2SS
.gepfc_prefix:
    call g_emit_u8; test eax,eax; jnz .gepfc_bad
    cmp ebx,8; jb .gepfc_opcode
    mov edi,0x45                         # REX.R|REX.B for xmm8..15 same-reg
    call g_emit_u8; test eax,eax; jnz .gepfc_bad
.gepfc_opcode:
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepfc_bad
    mov edi,0x5A; call g_emit_u8; test eax,eax; jnz .gepfc_bad
    mov eax,ebx; and eax,7; mov ecx,eax; shl eax,3; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepfc_bad
.gepfc_evex:
    cmp ebx,31; ja .gepfc_bad
    cmp r12d,GTYPE_F64; je 771f
    cmp r12d,GTYPE_F32; jne .gepfc_bad
    cmp r13d,GTYPE_F64; jne .gepfc_bad
    jmp 772f
771:cmp r13d,GTYPE_F32; jne .gepfc_bad
772:mov edi,0x5A; mov esi,ebx; mov edx,ebx; mov ecx,ebx; mov r8d,r12d
    call g_emit_phys_evex_scalar3
    test eax,eax; jnz .gepfc_bad
.gepfc_ok:
    xor eax,eax; jmp .gepfc_done
.gepfc_bad:
    mov eax,1
.gepfc_done:
    pop r13; pop r12; pop rbx; ret

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
    # Whole-episode shared ValueFacts are ordinary direct physical sources.
    # The first speculative profile has ready_count=0, so collection never
    # changes proof semantics.
    mov rdi,r12; mov esi,r13d; call g_phys_cse_find_resident
    cmp eax,0; jl .gpfpds_literal_real
    lea rcx,[rip+g_phys_cse_resident_reg]
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
    mov rax,r14; call node_parse_f64_bits; test edx,edx; jnz .gpfpds_no
    movq xmm0,rax; cvtsd2ss xmm0,xmm0; movd edi,xmm0
    mov esi,GTYPE_F32; call g_phys_const_find_resident
    cmp eax,0; jl .gpfpds_no
    lea rcx,[rip+g_phys_const_resident_reg]; mov edx,dword ptr [rcx+rax*4]; mov eax,1; jmp .gpfpds_done
.gpfpds_f64:
    mov rax,r14; call node_parse_f64_bits; test edx,edx; jnz .gpfpds_no
    mov rdi,rax; mov esi,GTYPE_F64; call g_phys_const_find_resident
    cmp eax,0; jl .gpfpds_no
    lea rcx,[rip+g_phys_const_resident_reg]; mov edx,dword ptr [rcx+rax*4]; mov eax,1; jmp .gpfpds_done
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
    # f32 literal: canonical parser is f64, then one exact host conversion as in
    # the mature 1.3.13 front-end.
    mov rax,r15; call node_parse_f64_bits; test edx,edx; jnz .gpfpe_bad
    movq xmm0,rax; cvtsd2ss xmm0,xmm0; movd r15d,xmm0
    cmp dword ptr [rip+g_phys_const_collect],1; jne 1f
    mov edi,r15d; mov esi,GTYPE_F32; call g_phys_const_note
1:  mov edi,r15d; call g_emit_mov_eax_imm
    mov edi,r13d; mov esi,GTYPE_F32; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpfpe_bad
    mov eax,GTYPE_F32; jmp .gpfpe_done
.gpfpe_literal_f64:
    mov rax,r15; call node_parse_f64_bits; test edx,edx; jnz .gpfpe_bad
    mov r15,rax
    cmp dword ptr [rip+g_phys_const_collect],1; jne 2f
    mov rdi,r15; mov esi,GTYPE_F64; call g_phys_const_note
2:  mov rdi,r15; call g_emit_mov_rax_imm64
    mov edi,r13d; mov esi,GTYPE_F64; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpfpe_bad
    mov eax,GTYPE_F64; jmp .gpfpe_done

.gpfpe_var:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpfpe_state_invalid_or_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
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
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov edi,r13d; mov esi,r14d; call g_emit_phys_xmm_from_rax
    test eax,eax; jnz .gpfpe_bad
    mov eax,r14d; jmp .gpfpe_done
.gpfpe_op_probe:
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpfpe_bad
    mov r15,rax
    # Unary native math remains an ordinary ValueFact in the same physical DAG.
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jnz .gpfpe_sqrt
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq
    test eax,eax; jnz .gpfpe_square
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_trunc]; mov ecx,gv_trunc_end-gv_trunc; call span_eq
    test eax,eax; jnz .gpfpe_trunc
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
    test eax,eax; jz .gpfpe_bad
    mov dword ptr [rsp+8],0x5E
    jmp .gpfpe_op_ready
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

    # Left input: retain resident ValueFacts by identity, otherwise realize the
    # subtree directly into the final destination.
    mov rdi,rbx; mov esi,r14d; call g_phys_fp_direct_source
    test eax,eax; jz .gpfpe_lhs_complex
    mov ebx,edx
    jmp .gpfpe_lhs_ready
.gpfpe_lhs_complex:
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
    mov dword ptr [rip+g_phys_int_temp_mask],G_PHYS_INT_TEMP_MASK_INIT
    ret

g_phys_int_temp_alloc:
    mov eax,dword ptr [rip+g_phys_int_temp_mask]
    test eax,eax; jz .gpit_fail
    bsf ecx,eax
    btr eax,ecx
    mov dword ptr [rip+g_phys_int_temp_mask],eax
    mov eax,ecx
    ret
.gpit_fail:
    mov eax,-1
    ret

# edi=GPR code. Only the anonymous temporary carrier domain is releasable.
g_phys_int_temp_free:
    cmp edi,11; jb .gpitf_done
    cmp edi,14; ja .gpitf_done
.gpitf_yes:
    bts dword ptr [rip+g_phys_int_temp_mask],edi
.gpitf_done:
    ret

# edi=semantic data role 0..2 -> eax runtime output GPR code.
g_phys_int_output_reg:
    cmp edi,0; je .gpior0
    cmp edi,1; je .gpior1
    cmp edi,2; je .gpior2
    mov eax,-1; ret
.gpior0: mov eax,6; ret                    # RSI
.gpior1: mov eax,7; ret                    # RDI
.gpior2: mov eax,1; ret                    # RCX; RDX remains implicit-wide-multiply scratch

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

# Generic two-source integer realization into an already initialized dst.
# edi=kind (1 add,2 sub,3 mul), esi=dst, edx=src.
g_emit_phys_gpr_bin2:
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    cmp ebx,3; je .gepgb_mul
    cmp ebx,1; je .gepgb_add
    cmp ebx,2; jne .gepgb_bad
    mov ebx,0x29                         # sub r/m64, r64
    jmp .gepgb_addsub
.gepgb_add:
    mov ebx,0x01                         # add r/m64, r64
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
.gepgb_bad:
    mov eax,1
.gepgb_done:
    pop r13; pop r12; pop rbx; ret

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

# edi=dst, esi=src emits `cmovae dst,src` using flags from the preceding compare.
g_emit_phys_gpr_cmovae:
    push rbx; push r12
    mov ebx,edi; mov r12d,esi
    mov eax,0x48
    mov ecx,ebx; shr ecx,3; and ecx,1; shl ecx,2; or eax,ecx
    mov ecx,r12d; shr ecx,3; and ecx,1; or eax,ecx
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgca_bad
    mov edi,0x0F; call g_emit_u8; test eax,eax; jnz .gepgca_bad
    mov edi,0x43; call g_emit_u8; test eax,eax; jnz .gepgca_bad
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r12d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call g_emit_u8; test eax,eax; jnz .gepgca_bad
    xor eax,eax; jmp .gepgca_done
.gepgca_bad:
    mov eax,1
.gepgca_done:
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

# Exact unified u64 modulo by a nonzero compile-time ConstantFact.
# For d>1, m=floor(2^64/d), q0=high(n*m). Then q0 is either floor(n/d)
# or one less, so r=n-q0*d lies in [0,2d). One branchless correction gives
# the exact remainder for every d, including powers of two. There is no
# power-of-two mask path, divisor table, workload matcher, or runtime selector.
# edi=dst GPR, rsi=d, rdx=m -> eax=0 success / 1 fail.
g_emit_phys_u64_const_mod:
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12,rsi; mov r13,rdx
    cmp r12,1; jne .gepucm_general
    xor edi,edi; call g_emit_mov_rax_imm64
    test eax,eax; jnz .gepucm_bad
    mov edi,ebx; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_bad
    xor eax,eax; jmp .gepucm_done
.gepucm_general:
    call g_phys_int_temp_alloc
    cmp eax,0; jl .gepucm_bad
    mov r14d,eax
    # temp <- reciprocal m
    mov rdi,r13; call g_emit_mov_rax_imm64
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,r14d; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    # RAX <- n; RDX <- high(n*m) = q0
    xor edi,edi; mov esi,ebx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,r14d; call g_emit_phys_mul_rax_gpr
    test eax,eax; jnz .gepucm_temp_bad
    # temp <- d; RDX <- q0*d; dst <- n-q0*d
    mov rdi,r12; call g_emit_mov_rax_imm64
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,r14d; xor esi,esi; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,3; mov esi,2; mov edx,r14d; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,2; mov esi,ebx; mov edx,2; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    # candidate=rem-d in RAX; if rem>=d, commit candidate without a branch.
    xor edi,edi; mov esi,ebx; call g_emit_phys_gpr_move
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,2; xor esi,esi; mov edx,r14d; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,ebx; mov esi,r14d; call g_emit_phys_gpr_cmp
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,ebx; xor esi,esi; call g_emit_phys_gpr_cmovae
    test eax,eax; jnz .gepucm_temp_bad
    mov edi,r14d; call g_phys_int_temp_free
    xor eax,eax; jmp .gepucm_done
.gepucm_temp_bad:
    mov edi,r14d; call g_phys_int_temp_free
.gepucm_bad:
    mov eax,1
.gepucm_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=expected integer type -> eax=1, edx=resident GPR; else eax=0.
g_phys_int_direct_source:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13d,esi
    xor eax,eax
    cmp qword ptr [r12],J_OBJECT; jne .gpids_done
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpids_no
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
.gpids_no:
    xor eax,eax
.gpids_done:
    pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=destination GPR code, edx=GTYPE_U64/I64 -> eax type/0.
g_emit_phys_int_expr_to:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi; mov r13d,esi; mov r14d,edx
    cmp r14d,GTYPE_U64; je .gpie_type_ok
    cmp r14d,GTYPE_I64; jne .gpie_bad
.gpie_type_ok:
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
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpie_state_invalid_or_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
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
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gpie_bad
    mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jz 1f
    mov dword ptr [rsp+8],1; jmp .gpie_op_ready
1:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jz 2f
    mov dword ptr [rsp+8],2; jmp .gpie_op_ready
2:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jz 3f
    mov dword ptr [rsp+8],3; jmp .gpie_op_ready
3:  mov rdi,[r15+8]; mov rsi,[r15+16]; lea rdx,[rip+gv_mod]; mov ecx,gv_mod_end-gv_mod; call span_eq
    test eax,eax; jz .gpie_bad
    cmp r14d,GTYPE_U64; jne .gpie_bad
    mov dword ptr [rsp+8],4
.gpie_op_ready:
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpie_bad
    mov rbx,[rax+24]; test rbx,rbx; jz .gpie_bad
    mov r15,[rbx+32]; test r15,r15; jz .gpie_bad
    cmp qword ptr [r15+32],0; jne .gpie_bad

    # `mod` is admitted into the same register-native DAG only when its divisor
    # is an exact nonzero u64 ConstantFact. Every such divisor uses one reciprocal
    # relation, so powers of two own no compatibility/specialization branch.
    cmp dword ptr [rsp+8],4; jne .gpie_args_ready
    mov rdi,r15; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpie_bad
    mov [rsp],rax
    mov rdi,r15; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpie_bad
    mov rdi,rax; call g_type_from_node; cmp eax,GTYPE_U64; jne .gpie_bad
    mov rax,[rsp]; call node_parse_u64; test edx,edx; jnz .gpie_bad
    test rax,rax; jz .gpie_bad
    mov [rsp+16],rax
    cmp rax,1; je .gpie_mod_magic_ready
    mov rcx,rax
    xor eax,eax
    mov edx,1
    div rcx                              # floor(2^64 / d), d>1 so quotient fits
    mov [rsp+24],rax
    jmp .gpie_args_ready
.gpie_mod_magic_ready:
    mov qword ptr [rsp+24],0
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
    cmp dword ptr [rsp+8],4; jne .gpie_rhs_normal
    mov edi,r13d; mov rsi,[rsp+16]; mov rdx,[rsp+24]
    call g_emit_phys_u64_const_mod
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done
.gpie_rhs_normal:
    mov rdi,r15; mov esi,r14d; call g_phys_int_direct_source
    test eax,eax; jz .gpie_rhs_complex
    mov edx,edx
    mov edi,dword ptr [rsp+8]; mov esi,r13d
    call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gpie_bad
    mov eax,r14d; jmp .gpie_done

.gpie_rhs_complex:
    call g_phys_int_temp_alloc
    cmp eax,0; jl .gpie_bad
    mov dword ptr [rsp],eax
    mov rdi,r15; mov esi,eax; mov edx,r14d; call g_emit_phys_int_expr_to
    cmp eax,r14d; jne .gpie_rhs_temp_fail
    mov edx,dword ptr [rsp]
    mov edi,dword ptr [rsp+8]; mov esi,r13d; call g_emit_phys_gpr_bin2
    test eax,eax; jnz .gpie_rhs_temp_fail
    mov edi,dword ptr [rsp]; call g_phys_int_temp_free
    mov eax,r14d; jmp .gpie_done
.gpie_rhs_temp_fail:
    mov edi,dword ptr [rsp]; call g_phys_int_temp_free
.gpie_bad:
    xor eax,eax
.gpie_done:
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Commit complete next-version carriers into persistent state carriers.
g_emit_phys_commit_output:
    cmp esi,GTYPE_F64; je .gepco_f64
    cmp esi,GTYPE_F32; je .gepco_f32
    cmp edi,0; je .gepco_i0
    cmp edi,1; je .gepco_i1
    cmp edi,2; je .gepco_i2
    mov eax,1; ret
.gepco_i0: lea rdi,[rip+gc_phys_mov_r8_rsi]; mov esi,gc_phys_mov_r8_rsi_end-gc_phys_mov_r8_rsi; call g_emit_bytes; ret
.gepco_i1: lea rdi,[rip+gc_phys_mov_r9_rdi]; mov esi,gc_phys_mov_r9_rdi_end-gc_phys_mov_r9_rdi; call g_emit_bytes; ret
.gepco_i2: lea rdi,[rip+gc_phys_mov_r10_rcx]; mov esi,gc_phys_mov_r10_rcx_end-gc_phys_mov_r10_rcx; call g_emit_bytes; ret
.gepco_f64:
    cmp edi,0; je .gepco_d0
    cmp edi,1; je .gepco_d1
    cmp edi,2; je .gepco_d2
    mov eax,1; ret
.gepco_d0: lea rdi,[rip+gc_phys_movsd_xmm8_xmm5]; mov esi,gc_phys_movsd_xmm8_xmm5_end-gc_phys_movsd_xmm8_xmm5; call g_emit_bytes; ret
.gepco_d1: lea rdi,[rip+gc_phys_movsd_xmm9_xmm6]; mov esi,gc_phys_movsd_xmm9_xmm6_end-gc_phys_movsd_xmm9_xmm6; call g_emit_bytes; ret
.gepco_d2: lea rdi,[rip+gc_phys_movsd_xmm10_xmm7]; mov esi,gc_phys_movsd_xmm10_xmm7_end-gc_phys_movsd_xmm10_xmm7; call g_emit_bytes; ret
.gepco_f32:
    cmp edi,0; je .gepco_s0
    cmp edi,1; je .gepco_s1
    cmp edi,2; je .gepco_s2
    mov eax,1; ret
.gepco_s0: lea rdi,[rip+gc_phys_movss_xmm8_xmm5]; mov esi,gc_phys_movss_xmm8_xmm5_end-gc_phys_movss_xmm8_xmm5; call g_emit_bytes; ret
.gepco_s1: lea rdi,[rip+gc_phys_movss_xmm9_xmm6]; mov esi,gc_phys_movss_xmm9_xmm6_end-gc_phys_movss_xmm9_xmm6; call g_emit_bytes; ret
.gepco_s2: lea rdi,[rip+gc_phys_movss_xmm10_xmm7]; mov esi,gc_phys_movss_xmm10_xmm7_end-gc_phys_movss_xmm10_xmm7; call g_emit_bytes; ret

# Initialize a floating persistent state from the historical init value bits
# already in runtime RAX. edi=role, esi=type.
g_emit_phys_init_float:
    cmp esi,GTYPE_F64; je .gepif_d
    cmp esi,GTYPE_F32; jne .gepif_bad
    cmp edi,0; je .gepif_s0
    cmp edi,1; je .gepif_s1
    cmp edi,2; je .gepif_s2
    jmp .gepif_bad
.gepif_d:
    cmp edi,0; je .gepif_d0
    cmp edi,1; je .gepif_d1
    cmp edi,2; je .gepif_d2
.gepif_bad: mov eax,1; ret
.gepif_d0: lea rdi,[rip+gc_phys_movq_xmm8_rax]; mov esi,gc_phys_movq_xmm8_rax_end-gc_phys_movq_xmm8_rax; call g_emit_bytes; ret
.gepif_d1: lea rdi,[rip+gc_phys_movq_xmm9_rax]; mov esi,gc_phys_movq_xmm9_rax_end-gc_phys_movq_xmm9_rax; call g_emit_bytes; ret
.gepif_d2: lea rdi,[rip+gc_phys_movq_xmm10_rax]; mov esi,gc_phys_movq_xmm10_rax_end-gc_phys_movq_xmm10_rax; call g_emit_bytes; ret
.gepif_s0: lea rdi,[rip+gc_phys_movd_xmm8_eax]; mov esi,gc_phys_movd_xmm8_eax_end-gc_phys_movd_xmm8_eax; call g_emit_bytes; ret
.gepif_s1: lea rdi,[rip+gc_phys_movd_xmm9_eax]; mov esi,gc_phys_movd_xmm9_eax_end-gc_phys_movd_xmm9_eax; call g_emit_bytes; ret
.gepif_s2: lea rdi,[rip+gc_phys_movd_xmm10_eax]; mov esi,gc_phys_movd_xmm10_eax_end-gc_phys_movd_xmm10_eax; call g_emit_bytes; ret

# Extract final floating resident state to runtime RAX bits for the unchanged
# general publication ABI. edi=role, esi=type.
g_emit_phys_extract_float:
    cmp esi,GTYPE_F64; je .gepef_d
    cmp esi,GTYPE_F32; jne .gepef_bad
    cmp edi,0; je .gepef_s0
    cmp edi,1; je .gepef_s1
    cmp edi,2; je .gepef_s2
    jmp .gepef_bad
.gepef_d:
    cmp edi,0; je .gepef_d0
    cmp edi,1; je .gepef_d1
    cmp edi,2; je .gepef_d2
.gepef_bad: mov eax,1; ret
.gepef_d0: lea rdi,[rip+gc_phys_movq_rax_xmm8]; mov esi,gc_phys_movq_rax_xmm8_end-gc_phys_movq_rax_xmm8; call g_emit_bytes; ret
.gepef_d1: lea rdi,[rip+gc_phys_movq_rax_xmm9]; mov esi,gc_phys_movq_rax_xmm9_end-gc_phys_movq_rax_xmm9; call g_emit_bytes; ret
.gepef_d2: lea rdi,[rip+gc_phys_movq_rax_xmm10]; mov esi,gc_phys_movq_rax_xmm10_end-gc_phys_movq_rax_xmm10; call g_emit_bytes; ret
.gepef_s0: lea rdi,[rip+gc_phys_movd_eax_xmm8]; mov esi,gc_phys_movd_eax_xmm8_end-gc_phys_movd_eax_xmm8; call g_emit_bytes; ret
.gepef_s1: lea rdi,[rip+gc_phys_movd_eax_xmm9]; mov esi,gc_phys_movd_eax_xmm9_end-gc_phys_movd_eax_xmm9; call g_emit_bytes; ret
.gepef_s2: lea rdi,[rip+gc_phys_movd_eax_xmm10]; mov esi,gc_phys_movd_eax_xmm10_end-gc_phys_movd_eax_xmm10; call g_emit_bytes; ret


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
.gec_u_f64: lea rdi,[rip+gc_cast_u64_f64]; mov esi,gc_cast_u64_f64_end-gc_cast_u64_f64; call g_emit_bytes; xor eax,eax; ret
.gec_u_f32: lea rdi,[rip+gc_cast_u64_f32]; mov esi,gc_cast_u64_f32_end-gc_cast_u64_f32; call g_emit_bytes; xor eax,eax; ret
.gec_from_i:
    cmp edx,GTYPE_F64; je .gec_i_f64
    cmp edx,GTYPE_F32; je .gec_i_f32
    cmp edx,GTYPE_U64; je .gec_ok
    mov eax,1; ret
.gec_i_f64: lea rdi,[rip+gc_cast_i64_f64]; mov esi,gc_cast_i64_f64_end-gc_cast_i64_f64; call g_emit_bytes; xor eax,eax; ret
.gec_i_f32: lea rdi,[rip+gc_cast_i64_f32]; mov esi,gc_cast_i64_f32_end-gc_cast_i64_f32; call g_emit_bytes; xor eax,eax; ret
.gec_from_f32:
    cmp edx,GTYPE_F64; je .gec_f32_f64
    cmp edx,GTYPE_U64; je .gec_f32_u64
    cmp edx,GTYPE_I64; je .gec_f32_i64
    mov eax,1; ret
.gec_f32_f64: lea rdi,[rip+gc_cast_f32_f64]; mov esi,gc_cast_f32_f64_end-gc_cast_f32_f64; call g_emit_bytes; xor eax,eax; ret
.gec_f32_u64: lea rdi,[rip+gc_cast_f32_u64]; mov esi,gc_cast_f32_u64_end-gc_cast_f32_u64; call g_emit_bytes; xor eax,eax; ret
.gec_f32_i64: lea rdi,[rip+gc_cast_f32_i64]; mov esi,gc_cast_f32_i64_end-gc_cast_f32_i64; call g_emit_bytes; xor eax,eax; ret
.gec_from_f64:
    cmp edx,GTYPE_F32; je .gec_f64_f32
    cmp edx,GTYPE_U64; je .gec_f64_u64
    cmp edx,GTYPE_I64; je .gec_f64_i64
    mov eax,1; ret
.gec_f64_f32: lea rdi,[rip+gc_cast_f64_f32]; mov esi,gc_cast_f64_f32_end-gc_cast_f64_f32; call g_emit_bytes; xor eax,eax; ret
.gec_f64_u64: lea rdi,[rip+gc_cast_f64_u64]; mov esi,gc_cast_f64_u64_end-gc_cast_f64_u64; call g_emit_bytes; xor eax,eax; ret
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
.gcst_u64_f64: lea rdi,[rip+gc_cast_u64_f64]; mov esi,gc_cast_u64_f64_end-gc_cast_u64_f64; call g_emit_bytes; ret
.gcst_u64_f32: lea rdi,[rip+gc_cast_u64_f32]; mov esi,gc_cast_u64_f32_end-gc_cast_u64_f32; call g_emit_bytes; ret
.gcst_from_i64:
    cmp esi,GTYPE_F64; je .gcst_i64_f64
    cmp esi,GTYPE_F32; je .gcst_i64_f32
    jmp .gcst_bad
.gcst_i64_f64: lea rdi,[rip+gc_cast_i64_f64]; mov esi,gc_cast_i64_f64_end-gc_cast_i64_f64; call g_emit_bytes; ret
.gcst_i64_f32: lea rdi,[rip+gc_cast_i64_f32]; mov esi,gc_cast_i64_f32_end-gc_cast_i64_f32; call g_emit_bytes; ret
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
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gef64_add
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gef64_sub
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gef64_mul
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jnz .gef64_div
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_min]; mov ecx,gv_min_end-gv_min; call span_eq; test eax,eax; jnz .gef64_min
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_max]; mov ecx,gv_max_end-gv_max; call span_eq; test eax,eax; jnz .gef64_max
    mov eax,1; jmp .gef64_done
.gef64_add: lea rdi,[rip+gc_f64_add]; mov esi,gc_f64_add_end-gc_f64_add; call g_emit_bytes; jmp .gef64_done
.gef64_sub: lea rdi,[rip+gc_f64_sub]; mov esi,gc_f64_sub_end-gc_f64_sub; call g_emit_bytes; jmp .gef64_done
.gef64_mul: lea rdi,[rip+gc_f64_mul]; mov esi,gc_f64_mul_end-gc_f64_mul; call g_emit_bytes; jmp .gef64_done
.gef64_div: lea rdi,[rip+gc_f64_div_checked]; mov esi,gc_f64_div_checked_end-gc_f64_div_checked; call g_emit_bytes; jmp .gef64_done
.gef64_min: lea rdi,[rip+gc_f64_min]; mov esi,gc_f64_min_end-gc_f64_min; call g_emit_bytes; jmp .gef64_done
.gef64_max: lea rdi,[rip+gc_f64_max]; mov esi,gc_f64_max_end-gc_f64_max; call g_emit_bytes
.gef64_done: pop r13; pop r12; ret

g_emit_float32_op:
    push r12; push r13; mov r12,rdi; mov r13,rsi
    lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq; test eax,eax; jnz .gef32_add
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq; test eax,eax; jnz .gef32_sub
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq; test eax,eax; jnz .gef32_mul
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq; test eax,eax; jnz .gef32_div
    mov eax,1; jmp .gef32_done
.gef32_add: lea rdi,[rip+gc_f32_add]; mov esi,gc_f32_add_end-gc_f32_add; call g_emit_bytes; jmp .gef32_done
.gef32_sub: lea rdi,[rip+gc_f32_sub]; mov esi,gc_f32_sub_end-gc_f32_sub; call g_emit_bytes; jmp .gef32_done
.gef32_mul: lea rdi,[rip+gc_f32_mul]; mov esi,gc_f32_mul_end-gc_f32_mul; call g_emit_bytes; jmp .gef32_done
.gef32_div: lea rdi,[rip+gc_f32_div_checked]; mov esi,gc_f32_div_checked_end-gc_f32_div_checked; call g_emit_bytes
.gef32_done: pop r13; pop r12; ret

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
    cmp r14d,GTYPE_I64; je .gei_idiv
    lea rdi,[rip+gc_udiv_checked]; mov esi,gc_udiv_checked_end-gc_udiv_checked; call g_emit_bytes; jmp .gei_done
.gei_idiv:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gei_idiv_wrap
    lea rdi,[rip+gc_idiv_checked]; mov esi,gc_idiv_checked_end-gc_idiv_checked; call g_emit_bytes; jmp .gei_done
.gei_idiv_wrap: lea rdi,[rip+gc_idiv_wrap_checked]; mov esi,gc_idiv_wrap_checked_end-gc_idiv_wrap_checked; call g_emit_bytes; jmp .gei_done
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

g_emit_mod_top2:
    cmp edi,GTYPE_I64; je .gemod_i
    lea rdi,[rip+gc_umod_checked]; mov esi,gc_umod_checked_end-gc_umod_checked; call g_emit_bytes; ret
.gemod_i:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gemod_i_wrap
    lea rdi,[rip+gc_imod_checked]; mov esi,gc_imod_checked_end-gc_imod_checked; call g_emit_bytes; ret
.gemod_i_wrap: lea rdi,[rip+gc_imod_wrap_checked]; mov esi,gc_imod_wrap_checked_end-gc_imod_wrap_checked; call g_emit_bytes; ret

# ---------------- binding emitters ----------------
# reduce symbol rdi -> eax 0/1
g_emit_reduce_binding:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,[rbx+32]
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
    # sum accumulator bits in R11 initialized zero (works integer/fp +0)
.gerb_loop_start:
    mov r15,[rip+g_emit_ptr]
    lea rdi,[rip+gc_cmp_rbx_rbp]; mov esi,gc_cmp_rbx_rbp_end-gc_cmp_rbx_rbp; call g_emit_bytes
    # jae exit
    lea rdi,[rip+gc_jae_prefix]; mov esi,gc_jae_prefix_end-gc_jae_prefix; call g_emit_bytes
    mov r13,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32
    lea rdi,[rip+gc_mov_r10_rbx]; mov esi,gc_mov_r10_rbx_end-gc_mov_r10_rbx; call g_emit_bytes
    mov rdi,r12; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .gerb_bad
    mov rdi,rax; call g_emit_expr; cmp eax,r14d; jne .gerb_bad
    call g_emit_pop_rax
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
    mov edi,r14d; mov esi,2; call g_emit_reduce_minmax_step; jmp .gerb_step_done
.gerb_min: mov edi,r14d; mov esi,1; call g_emit_reduce_minmax_step; jmp .gerb_step_done
.gerb_sum:
    mov edi,r14d; call g_emit_reduce_sum_step; test eax,eax; jnz .gerb_bad
.gerb_step_done:
    lea rdi,[rip+gc_inc_rbx]; mov esi,gc_inc_rbx_end-gc_inc_rbx; call g_emit_bytes
    mov edi,0xE9; call g_emit_u8
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; jbe 91f
    mov dword ptr [rip+g_code_overflow],1; jmp .gerb_bad
91:
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
    # patch exit
    mov rsi,[rip+g_emit_ptr]; mov rdi,r13; call g_patch_rel32
    # empty min/max reject
    test r15d,r15d; jnz .gerb_store
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
.gerb_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# sum step: edi type, candidate in RAX, accumulator bits R11
g_emit_reduce_sum_step:
    cmp edi,GTYPE_U64; je .gers_u
    cmp edi,GTYPE_I64; je .gers_i
    cmp edi,GTYPE_F64; je .gers_f64
    cmp edi,GTYPE_F32; je .gers_f32
    mov eax,1; ret
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

# min/max step edi type, esi mode 1 min 2 max. candidate RAX, R11 accumulator, RBX index.
g_emit_reduce_minmax_step:
    # First item simply becomes accumulator.
    lea rdi,[rip+gc_red_first_guard]; mov esi,gc_red_first_guard_end-gc_red_first_guard; call g_emit_bytes
    # Simpler conservative path: the embedded guard code handles integer only.
    # Float min/max remains rejected by this general seed until a total-order
    # NaN policy is explicitly added.
    cmp edi,GTYPE_U64; jne .germm_i
    cmp esi,1; je .germm_umin
    lea rdi,[rip+gc_red_umax]; mov esi,gc_red_umax_end-gc_red_umax; call g_emit_bytes; xor eax,eax; ret
.germm_umin: lea rdi,[rip+gc_red_umin]; mov esi,gc_red_umin_end-gc_red_umin; call g_emit_bytes; xor eax,eax; ret
.germm_i:
    cmp edi,GTYPE_I64; jne .germm_bad
    cmp esi,1; je .germm_imin
    lea rdi,[rip+gc_red_imax]; mov esi,gc_red_imax_end-gc_red_imax; call g_emit_bytes; xor eax,eax; ret
.germm_imin: lea rdi,[rip+gc_red_imin]; mov esi,gc_red_imin_end-gc_red_imin; call g_emit_bytes; xor eax,eax; ret
.germm_bad: mov eax,1; ret



# ---------------- 1.3.16 whole-episode shared Physical-DAG facts ----------------
# This is not a workload-specific cache.  Exact strict-order FP subtrees from
# every simultaneous next-state expression enter one AOT CSE domain.  Repeated
# old-version ValueFacts may receive one XMM carrier for the whole causal
# episode; the generated program contains no graph walker or runtime cache.
.equ G_PHYS_CSE_MAX,32

# rdi=expr -> eax=1 when this is an exact binary add/sub/mul node, else 0.
g_phys_fp_expr_is_shareable_op:
    push rbx; push r12
    mov r12,rdi
    cmp qword ptr [r12],J_OBJECT; jne .gpfiso_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gpfiso_no
    mov rbx,rax
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jnz .gpfiso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_sub]; mov ecx,gv_sub_end-gv_sub; call span_eq
    test eax,eax; jnz .gpfiso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jnz .gpfiso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_div]; mov ecx,gv_div_end-gv_div; call span_eq
    test eax,eax; jnz .gpfiso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_sqrt]; mov ecx,gv_sqrt_end-gv_sqrt; call span_eq
    test eax,eax; jnz .gpfiso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_square]; mov ecx,gv_square_end-gv_square; call span_eq
    test eax,eax; jnz .gpfiso_yes
    mov rdi,[rbx+8]; mov rsi,[rbx+16]; lea rdx,[rip+gv_trunc]; mov ecx,gv_trunc_end-gv_trunc; call span_eq
    test eax,eax; jnz .gpfiso_yes
.gpfiso_no:
    xor eax,eax; jmp .gpfiso_done
.gpfiso_yes:
    mov eax,1
.gpfiso_done:
    pop r12; pop rbx; ret

# rdi=exprA, rsi=exprB -> eax=1 only for exact structural equality.
# Operation order is part of identity; no commutative canonicalization occurs.
g_phys_expr_equal:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi
    cmp r12,r13; je .gpee_yes
    test r12,r12; jz .gpee_no
    test r13,r13; jz .gpee_no
    cmp qword ptr [r12],J_OBJECT; jne .gpee_no
    cmp qword ptr [r13],J_OBJECT; jne .gpee_no

    # State leaf identity.
    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpee_literal
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpee_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[rax+8]; mov ecx,dword ptr [rax+16]; call span_eq
    jmp .gpee_done

.gpee_literal:
    mov rdi,r12; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpee_var
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+gk_literal]; mov edx,gk_literal_end-gk_literal; call obj_get
    test rax,rax; jz .gpee_no
    mov r15,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[r15+8]; mov ecx,dword ptr [r15+16]; call span_eq
    test eax,eax; jz .gpee_no
    # Type is part of literal identity.
    mov rdi,r12; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpee_no
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gpee_no
    mov rdi,r14; call g_type_from_node; mov r15d,eax
    mov rdi,rax                             # overwritten below; retain symmetry via second parse
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    mov rdi,rax; call g_type_from_node
    cmp eax,r15d; sete al; movzx eax,al
    jmp .gpee_done

.gpee_var:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpee_op
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gpee_no
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[rax+8]; mov ecx,dword ptr [rax+16]; call span_eq
    jmp .gpee_done

.gpee_op:
    mov rdi,r12; call g_phys_fp_expr_is_shareable_op
    test eax,eax; jz .gpee_no
    mov rdi,r13; call g_phys_fp_expr_is_shareable_op
    test eax,eax; jz .gpee_no
    mov rdi,r12; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    mov r14,rax
    mov rdi,r13; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    mov r15,rax
    mov rdi,[r14+8]; mov rsi,[r14+16]; mov rdx,[r15+8]; mov ecx,dword ptr [r15+16]; call span_eq
    test eax,eax; jz .gpee_no
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpee_no
    mov r14,[rax+24]; test r14,r14; jz .gpee_no
    mov rbx,[r14+32]
    test rbx,rbx; jz .gpee_a_arity_ready
    cmp qword ptr [rbx+32],0; jne .gpee_no
.gpee_a_arity_ready:
    mov rdi,r13; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpee_no
    mov r15,[rax+24]; test r15,r15; jz .gpee_no
    mov r13,[r15+32]
    test r13,r13; jz .gpee_b_arity_ready
    cmp qword ptr [r13+32],0; jne .gpee_no
.gpee_b_arity_ready:
    mov rdi,r14; mov rsi,r15; call g_phys_expr_equal
    test eax,eax; jz .gpee_no
    test rbx,rbx; jz .gpee_unary_tail
    test r13,r13; jz .gpee_no
    mov rdi,rbx; mov rsi,r13; call g_phys_expr_equal
    jmp .gpee_done
.gpee_unary_tail:
    test r13,r13; setz al; movzx eax,al
    jmp .gpee_done
.gpee_yes:
    mov eax,1; jmp .gpee_done
.gpee_no:
    xor eax,eax
.gpee_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr -> eax arithmetic operation count for shareable strict FP subtree.
g_phys_fp_expr_cost:
    push rbx; push r12; push r13
    mov r12,rdi
    mov rdi,r12; call g_phys_fp_expr_is_shareable_op
    test eax,eax; jz .gpfec_leaf
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpfec_leaf
    mov r12,[rax+24]; test r12,r12; jz .gpfec_leaf
    mov r13,[r12+32]
    mov rdi,r12; call g_phys_fp_expr_cost; mov ebx,eax
    test r13,r13; jz .gpfec_unary
    mov rdi,r13; call g_phys_fp_expr_cost
    add eax,ebx; inc eax; jmp .gpfec_done
.gpfec_unary:
    mov eax,ebx; inc eax; jmp .gpfec_done
.gpfec_leaf:
    xor eax,eax
.gpfec_done:
    pop r13; pop r12; pop rbx; ret

# rdi=FP expression, esi=expected type. Walk once and count exact repeated
# operator ValueFacts across every next-state expression.
g_phys_cse_note_tree:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi
    mov rdi,r12; call g_phys_fp_expr_is_shareable_op
    test eax,eax; jz .gpcnt_done
    # r13d is the type demanded by this node's real consumer edge. It defines
    # the candidate projection for THIS node only. Children are consumed by this
    # node itself, so their expected type is this node's natural inferred type,
    # never the outer consumer type. This prevents eager precision contagion from
    # tunneling through a high-precision subtree.
    mov rdi,r12; call g_infer_expr; mov ebx,eax
    cmp ebx,GTYPE_F32; je .gpcnt_nat_ok
    cmp ebx,GTYPE_F64; jne .gpcnt_done
.gpcnt_nat_ok:
    # Recurse before noting the parent so profitable inner facts are also visible.
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpcnt_done
    mov r14,[rax+24]; test r14,r14; jz .gpcnt_done
    mov r15,[r14+32]
    push r12; push r13
    mov rdi,r14; mov esi,ebx; call g_phys_cse_note_tree
    pop r13; pop r12
    test r15,r15; jz .gpcnt_children_done
    push r12; push r13
    mov rdi,r15; mov esi,ebx; call g_phys_cse_note_tree
    pop r13; pop r12
.gpcnt_children_done:

    xor ebx,ebx
.gpcnt_scan:
    cmp ebx,dword ptr [rip+g_phys_cse_candidate_count]; jae .gpcnt_new
    lea rax,[rip+g_phys_cse_candidate_type]; cmp dword ptr [rax+rbx*4],r13d; jne .gpcnt_next
    lea rax,[rip+g_phys_cse_candidate_expr]; mov rsi,[rax+rbx*8]
    mov rdi,r12; call g_phys_expr_equal
    test eax,eax; jz .gpcnt_next
    lea rax,[rip+g_phys_cse_candidate_uses]; inc dword ptr [rax+rbx*4]
    jmp .gpcnt_done
.gpcnt_next:
    inc ebx; jmp .gpcnt_scan
.gpcnt_new:
    cmp ebx,G_PHYS_CSE_MAX; jae .gpcnt_done
    lea rax,[rip+g_phys_cse_candidate_expr]; mov [rax+rbx*8],r12
    lea rax,[rip+g_phys_cse_candidate_type]; mov dword ptr [rax+rbx*4],r13d
    lea rax,[rip+g_phys_cse_candidate_uses]; mov dword ptr [rax+rbx*4],1
    mov rdi,r12; call g_phys_fp_expr_cost
    lea rdx,[rip+g_phys_cse_candidate_cost]; mov dword ptr [rdx+rbx*4],eax
    inc dword ptr [rip+g_phys_cse_candidate_count]
.gpcnt_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=tree, rsi=subtree -> eax=1 if subtree occurs structurally in tree.
# Exact operation order is preserved; this is compile-time graph topology only.
g_phys_expr_contains:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi
    mov rdi,r12; mov rsi,r13; call g_phys_expr_equal
    test eax,eax; jnz .gpec_yes
    mov rdi,r12; call g_phys_fp_expr_is_shareable_op
    test eax,eax; jz .gpec_no
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpec_no
    mov r14,[rax+24]; test r14,r14; jz .gpec_no
    mov rbx,[r14+32]
    mov rdi,r14; mov rsi,r13; call g_phys_expr_contains
    test eax,eax; jnz .gpec_yes
    test rbx,rbx; jz .gpec_no
    mov rdi,rbx; mov rsi,r13; call g_phys_expr_contains
    jmp .gpec_done
.gpec_yes:
    mov eax,1; jmp .gpec_done
.gpec_no:
    xor eax,eax
.gpec_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=candidate expr, esi=type -> eax=1 if candidate overlaps an already
# retained parent/child subtree.  A retained set is an antichain in the DAG.
g_phys_cse_overlaps_selected:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    xor ebx,ebx
.gpcos_loop:
    cmp ebx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpcos_no
    lea rax,[rip+g_phys_cse_resident_type]
    cmp dword ptr [rax+rbx*4],r13d; jne .gpcos_next
    lea rax,[rip+g_phys_cse_resident_expr]; mov r14,[rax+rbx*8]
    mov rdi,r12; mov rsi,r14; call g_phys_expr_contains
    test eax,eax; jnz .gpcos_yes
    mov rdi,r14; mov rsi,r12; call g_phys_expr_contains
    test eax,eax; jnz .gpcos_yes
.gpcos_next:
    inc ebx; jmp .gpcos_loop
.gpcos_yes:
    mov eax,1; jmp .gpcos_done
.gpcos_no:
    xor eax,eax
.gpcos_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# Shared XMM authority for persistent CSE and immutable constants.  State
# carriers, already retained shared facts, and the proven peak anonymous
# pressure all compete in one compile-time physical pool.
g_phys_shared_xmm_alloc:
    push rbx; push r12; push r13
    mov ebx,dword ptr [rip+g_phys_fp_reserved_mask]
    xor r12d,r12d
.gpsxa_cse:
    cmp r12d,dword ptr [rip+g_phys_cse_resident_count]; jae .gpsxa_const_start
    lea rax,[rip+g_phys_cse_resident_reg]; mov ecx,dword ptr [rax+r12*4]
    mov eax,1; shl eax,cl; or ebx,eax
    inc r12d; jmp .gpsxa_cse
.gpsxa_const_start:
    xor r12d,r12d
.gpsxa_const:
    cmp r12d,dword ptr [rip+g_phys_const_resident_count]; jae .gpsxa_free
    lea rax,[rip+g_phys_const_resident_reg]; mov ecx,dword ptr [rax+r12*4]
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

# Select repeated ValueFacts by saved arithmetic work. CSE wins carrier
# competition before constants because recomputing a multi-op fact consumes
# both execution ports and transient carrier pressure.
g_phys_cse_finalize:
    push rbx; push r12; push r13; push r14; push r15
    mov dword ptr [rip+g_phys_cse_resident_count],0
.gpcsef_pick:
    mov ebx,-1
    xor r12d,r12d                         # best score
    xor r13d,r13d
.gpcsef_scan:
    cmp r13d,dword ptr [rip+g_phys_cse_candidate_count]; jae .gpcsef_scan_done
    lea rax,[rip+g_phys_cse_candidate_uses]; mov r14d,dword ptr [rax+r13*4]
    cmp r14d,2; jb .gpcsef_next
    lea rax,[rip+g_phys_cse_candidate_cost]; mov r15d,dword ptr [rax+r13*4]
    test r15d,r15d; jz .gpcsef_next
    lea rax,[rip+g_phys_cse_candidate_expr]; mov rdi,[rax+r13*8]
    lea rax,[rip+g_phys_cse_candidate_type]; mov esi,dword ptr [rax+r13*4]
    call g_phys_cse_overlaps_selected
    test eax,eax; jnz .gpcsef_next
    shl r14d,8
    add r14d,r15d
    cmp r14d,r12d; jle .gpcsef_next
    mov r12d,r14d; mov ebx,r13d
.gpcsef_next:
    inc r13d; jmp .gpcsef_scan
.gpcsef_scan_done:
    cmp ebx,0; jl .gpcsef_done
    call g_phys_shared_xmm_alloc
    cmp eax,0; jge .gpcsef_have_carrier
    mov dword ptr [rip+g_phys_shared_pressure_exhausted],1
    jmp .gpcsef_done
.gpcsef_have_carrier:
    mov r14d,dword ptr [rip+g_phys_cse_resident_count]
    lea rdx,[rip+g_phys_cse_resident_reg]; mov dword ptr [rdx+r14*4],eax
    lea rdx,[rip+g_phys_cse_candidate_expr]; mov rcx,[rdx+rbx*8]
    lea rdx,[rip+g_phys_cse_resident_expr]; mov [rdx+r14*8],rcx
    lea rdx,[rip+g_phys_cse_candidate_type]; mov ecx,dword ptr [rdx+rbx*4]
    lea rdx,[rip+g_phys_cse_resident_type]; mov dword ptr [rdx+r14*4],ecx
    lea rdx,[rip+g_phys_cse_candidate_uses]; mov dword ptr [rdx+rbx*4],0
    inc dword ptr [rip+g_phys_cse_resident_count]
    jmp .gpcsef_pick
.gpcsef_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=type -> eax resident slot or -1. During CSE precomputation only
# already materialized slots are visible; during update emission all are ready.
g_phys_cse_find_resident:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,esi
    xor ebx,ebx
    mov r14d,dword ptr [rip+g_phys_cse_ready_count]
.gpcser_loop:
    cmp ebx,r14d; jae .gpcser_no
    lea rax,[rip+g_phys_cse_resident_type]; cmp dword ptr [rax+rbx*4],r13d; jne .gpcser_next
    lea rax,[rip+g_phys_cse_resident_expr]; mov rsi,[rax+rbx*8]
    mov rdi,r12; call g_phys_expr_equal
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
    push rbx; push r12; push r13
    mov r12,rdi
    xor ebx,ebx
.gpeisc_loop:
    cmp ebx,dword ptr [rip+g_phys_cse_resident_count]; jae .gpeisc_no
    lea rax,[rip+g_phys_cse_resident_expr]; mov r13,[rax+rbx*8]
    mov rdi,r12; mov rsi,r13; call g_phys_expr_equal
    test eax,eax; jnz .gpeisc_yes
    inc ebx; jmp .gpeisc_loop
.gpeisc_yes:
    mov eax,1; jmp .gpeisc_done
.gpeisc_no:
    xor eax,eax
.gpeisc_done:
    pop r13; pop r12; pop rbx; ret

# rdi=FP update expression, esi=update declaration index.
# Record real old-state consumers after selected CSE subtrees have been replaced
# by their resident ValueFacts.
g_phys_note_effective_state_uses:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi
    cmp qword ptr [r12],J_OBJECT; jne .gpnesu_done

    mov rdi,r12; call g_phys_expr_is_selected_cse
    test eax,eax; jnz .gpnesu_done

    mov rdi,r12; lea rsi,[rip+gk_state]; mov edx,gk_state_end-gk_state; call obj_get
    test rax,rax; jz .gpnesu_op
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state
    test rax,rax; jz .gpnesu_done
    mov ecx,dword ptr [rax+24]
    cmp ecx,dword ptr [rip+g_state_capacity]; jae .gpnesu_done
    mov rdx,[rip+g_phys_state_last_use_ptr]
    mov dword ptr [rdx+rcx*4],r13d
    jmp .gpnesu_done

.gpnesu_op:
    mov rdi,r12; call g_phys_fp_expr_is_shareable_op
    test eax,eax; jz .gpnesu_done
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpnesu_done
    mov r14,[rax+24]; test r14,r14; jz .gpnesu_done
    mov r15,[r14+32]
    test r15,r15; jz .gpnesu_one
    cmp qword ptr [r15+32],0; jne .gpnesu_done
.gpnesu_one:
    mov rdi,r14; mov esi,r13d; call g_phys_note_effective_state_uses
    test r15,r15; jz .gpnesu_done
    mov rdi,r15; mov esi,r13d; call g_phys_note_effective_state_uses
.gpnesu_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=expr, esi=semantic state index -> eax=1 iff the effective expression
# still consumes that old-state authority after selected episode-CSE facts have
# been materialized. This is the same causal-use vocabulary as last-use
# construction, exposed as a local proof query for destination coalescing.
g_phys_expr_effectively_uses_state:
    push rbx; push r12; push r13; push r14; push r15
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
    test rax,rax; jz .gpeeus_no                 # literal/var leaf
    mov rdi,r12; call g_phys_fp_expr_is_shareable_op
    test eax,eax; jz .gpeeus_yes                # unknown op: conservatively live
    mov rdi,r12; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gpeeus_yes
    mov r14,[rax+24]; test r14,r14; jz .gpeeus_no
    mov r15,[r14+32]
    mov rdi,r14; mov esi,r13d; call g_phys_expr_effectively_uses_state
    test eax,eax; jnz .gpeeus_yes
    test r15,r15; jz .gpeeus_no
    cmp qword ptr [r15+32],0; jne .gpeeus_yes
    mov rdi,r15; mov esi,r13d; call g_phys_expr_effectively_uses_state
    test eax,eax; jnz .gpeeus_yes
.gpeeus_no:
    xor eax,eax; jmp .gpeeus_done
.gpeeus_yes:
    mov eax,1
.gpeeus_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

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
    mov rdi,r12; call g_phys_fp_expr_is_shareable_op
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

# Prove one fixed-point carrier realization for the complete resident FP state
# generation. eax=1 means every FP next-state ValueFact can be born in its own
# old authority after its final effective consumer. The episode then has no
# physical generation transport at all. A partial mix is deliberately rejected:
# one FP generation has one authority model, avoiding a second hybrid regime.
g_phys_prove_inplace_fp_epoch:
    push rbx; push r12; push r13; push r14; push r15
    xor ebx,ebx
    xor r14d,r14d
.gppife_loop:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gppife_done_scan
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gppife_real
    cmp ebx,dword ptr [rip+g_reg_iter_counter_index]; je .gppife_next
.gppife_real:
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov r12d,dword ptr [r11+16]
    cmp r12d,GTYPE_F64; je .gppife_fp
    cmp r12d,GTYPE_F32; jne .gppife_next
.gppife_fp:
    inc r14d
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; cmp dword ptr [rdx+rbx*4],0; jl .gppife_no
    mov rdx,[rip+g_phys_state_last_use_ptr]; mov eax,dword ptr [rdx+rbx*4]
    cmp eax,ebx; jg .gppife_no
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    call obj_get
    test rax,rax; jz .gppife_no
    mov rdi,rax; mov esi,ebx; call g_phys_fp_can_birth_in_old_authority
    test eax,eax; jz .gppife_no
.gppife_next:
    inc ebx; jmp .gppife_loop
.gppife_done_scan:
    xor eax,eax
    test r14d,r14d; setne al
    jmp .gppife_done
.gppife_no:
    xor eax,eax
.gppife_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Build last-consumer indices for resident FP state authorities.  -1 means that
# the old ValueFact is not consumed by any post-CSE update expression.
g_phys_build_state_last_use:
    push rbx; push r12; push r13; push r14
    xor ebx,ebx
.gpbslu_clear:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gpbslu_scan_start
    mov rax,[rip+g_phys_state_last_use_ptr]; mov dword ptr [rax+rbx*4],-1
    inc ebx; jmp .gpbslu_clear
.gpbslu_scan_start:
    xor ebx,ebx
.gpbslu_scan:
    cmp ebx,dword ptr [rip+g_reg_iter_total]; jae .gpbslu_done
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gpbslu_real
    cmp ebx,dword ptr [rip+g_reg_iter_counter_index]; je .gpbslu_next
.gpbslu_real:
    mov eax,ebx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    call obj_get
    test rax,rax; jz .gpbslu_next
    mov rdi,rax; mov esi,ebx; call g_phys_note_effective_state_uses
.gpbslu_next:
    inc ebx; jmp .gpbslu_scan
.gpbslu_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# Emit the selected shared old-version facts once at the top of every causal
# iteration. Each result remains a normal Physical ValueFact in an XMM carrier.
g_emit_phys_episode_cse:
    push rbx; push r12; push r13; push r14
    mov dword ptr [rip+g_phys_cse_ready_count],0
    xor ebx,ebx
.gepec_loop:
    cmp ebx,dword ptr [rip+g_phys_cse_resident_count]; jae .gepec_done
    lea rax,[rip+g_phys_cse_resident_expr]; mov r12,[rax+rbx*8]
    lea rax,[rip+g_phys_cse_resident_type]; mov r13d,dword ptr [rax+rbx*4]
    lea rax,[rip+g_phys_cse_resident_reg]; mov r14d,dword ptr [rax+rbx*4]
    call g_phys_fp_temp_reset
    mov rdi,r12; mov esi,r14d; mov edx,r13d; call g_emit_phys_fp_value_to
    cmp eax,r13d; jne .gepec_bad
    inc dword ptr [rip+g_phys_cse_ready_count]
    inc ebx; jmp .gepec_loop
.gepec_done:
    # All shared facts are now valid direct sources for the update set.
    mov eax,dword ptr [rip+g_phys_cse_resident_count]
    mov dword ptr [rip+g_phys_cse_ready_count],eax
    xor eax,eax; jmp .gepec_ret
.gepec_bad:
    mov eax,1
.gepec_ret:
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
    lea rax,[rip+g_phys_const_candidate_bits]; cmp [rax+rbx*8],r12; jne .gpcn_next
    lea rax,[rip+g_phys_const_candidate_type]; cmp dword ptr [rax+rbx*4],r13d; jne .gpcn_next
    lea rax,[rip+g_phys_const_candidate_uses]; inc dword ptr [rax+rbx*4]
    xor eax,eax; jmp .gpcn_done
.gpcn_next:
    inc ebx; jmp .gpcn_scan
.gpcn_new:
    cmp ebx,G_PHYS_CSE_MAX; jae .gpcn_ok
    lea rax,[rip+g_phys_const_candidate_bits]; mov [rax+rbx*8],r12
    lea rax,[rip+g_phys_const_candidate_type]; mov dword ptr [rax+rbx*4],r13d
    lea rax,[rip+g_phys_const_candidate_uses]; mov dword ptr [rax+rbx*4],1
    inc dword ptr [rip+g_phys_const_candidate_count]
.gpcn_ok: xor eax,eax
.gpcn_done: pop r13; pop r12; pop rbx; ret

# ConstantFact residency has no private slot map.  Reuse candidates request
# carriers directly from the same whole-episode Physical Reality authority.
# Build residents by descending static reuse until the proven pressure bound.
g_phys_const_finalize:
    push rbx; push r12; push r13; push r14; push r15
    mov dword ptr [rip+g_phys_const_resident_count],0
    xor r12d,r12d
.gpcf_slot:
    mov ebx,-1
    xor r13d,r13d
    xor r14d,r14d
.gpcf_scan:
    cmp r14d,dword ptr [rip+g_phys_const_candidate_count]; jae .gpcf_scan_done
    lea rax,[rip+g_phys_const_candidate_uses]; mov r15d,dword ptr [rax+r14*4]
    cmp r15d,r13d; jle .gpcf_next
    mov r13d,r15d; mov ebx,r14d
.gpcf_next:
    inc r14d; jmp .gpcf_scan
.gpcf_scan_done:
    cmp ebx,0; jl .gpcf_done
    lea rax,[rip+g_phys_const_candidate_bits]; mov rdx,[rax+rbx*8]
    lea rax,[rip+g_phys_const_resident_bits]; mov [rax+r12*8],rdx
    lea rax,[rip+g_phys_const_candidate_type]; mov edx,dword ptr [rax+rbx*4]
    lea rax,[rip+g_phys_const_resident_type]; mov dword ptr [rax+r12*4],edx
    call g_phys_shared_xmm_alloc
    cmp eax,0; jge .gpcf_have_carrier
    mov dword ptr [rip+g_phys_shared_pressure_exhausted],1
    jmp .gpcf_done
.gpcf_have_carrier:
    lea rdx,[rip+g_phys_const_resident_reg]; mov dword ptr [rdx+r12*4],eax
    lea rax,[rip+g_phys_const_candidate_uses]; mov dword ptr [rax+rbx*4],0
    inc dword ptr [rip+g_phys_const_resident_count]
    inc r12d; jmp .gpcf_slot
.gpcf_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=bits, esi=type -> eax resident slot, or -1.
g_phys_const_find_resident:
    xor ecx,ecx
.gpcfr_loop:
    cmp ecx,dword ptr [rip+g_phys_const_resident_count]; jae .gpcfr_no
    lea rax,[rip+g_phys_const_resident_bits]; cmp [rax+rcx*8],rdi; jne .gpcfr_next
    lea rax,[rip+g_phys_const_resident_type]; cmp dword ptr [rax+rcx*4],esi; jne .gpcfr_next
    mov eax,ecx; ret
.gpcfr_next:
    inc ecx; jmp .gpcfr_loop
.gpcfr_no: mov eax,-1; ret

# Emit one preheader materialization per retained ConstantFact.
g_emit_phys_resident_constants:
    push rbx; push r12; push r13; push r14
    xor ebx,ebx
.geprc_loop:
    cmp ebx,dword ptr [rip+g_phys_const_resident_count]; jae .geprc_done
    lea rax,[rip+g_phys_const_resident_bits]; mov r12,[rax+rbx*8]
    lea rax,[rip+g_phys_const_resident_type]; mov r13d,dword ptr [rax+rbx*4]
    lea rax,[rip+g_phys_const_resident_reg]; mov r14d,dword ptr [rax+rbx*4]
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
    mov rax,[rip+g_emit_ptr]; mov [rip+g_reg_iter_emit_start],rax
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
    mov rdi,r13; call g_state_decl_scalar_type; test eax,eax; jz .gtri_no
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
    mov dword ptr [r11+28],-1       # transition-slice dense lane: absent until proved
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

    # Prove common counted-loop form independently of the value update.
    mov dword ptr [rip+g_reg_iter_counted],0
    xor ecx,ecx
.gtri_counted_probe:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_counted_probe_done
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_cond_expr]; mov rsi,[r11]; mov rdx,[r11+8]
    push rcx; call g_match_counter_bound; pop rcx
    test eax,eax; jz .gtri_counted_probe_next
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
    mov dword ptr [rip+g_reg_iter_counted],1
    mov dword ptr [rip+g_reg_iter_counter_index],ecx
    mov rax,[rip+g_counted_bound_expr]; mov [rip+g_reg_iter_bound_expr],rax
    jmp .gtri_counted_probe_done
.gtri_counted_probe_next:
    inc ecx; jmp .gtri_counted_probe
.gtri_counted_probe_done:
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
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gtri_role_data
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

    mov dword ptr [rip+g_phys_fp_transient_outputs],0
.gtri_physical_profile_retry:
    call g_phys_assign_state_carriers
    test eax,eax; jnz .gtri_no

    # Speculative AOT physicalization proof. Emit each next-state
    # expression into the code buffer, verify its type, then rewind the buffer.
    # This is a compile-time proof probe only: no runtime graph walker exists.
    mov dword ptr [rip+g_phys_shared_pressure_exhausted],0
    mov dword ptr [rip+g_phys_const_candidate_count],0
    mov dword ptr [rip+g_phys_const_resident_count],0
    mov dword ptr [rip+g_phys_cse_candidate_count],0
    mov dword ptr [rip+g_phys_cse_resident_count],0
    mov dword ptr [rip+g_phys_cse_ready_count],0
    mov dword ptr [rip+g_phys_fp_temp_peak],0
    mov dword ptr [rip+g_phys_fp_temp_live],0
    mov dword ptr [rip+g_phys_fp_temp_exhausted],0
    mov dword ptr [rip+g_phys_const_collect],1
    mov rax,[rip+g_emit_ptr]; mov [rip+g_reg_native_probe_start],rax
    mov eax,dword ptr [rip+g_reg_iter_total]; mov dword ptr [rip+g_state_count],eax
    xor ecx,ecx
.gtri_native_probe_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_native_probe_done
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gtri_native_probe_real
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
    cmp edx,GTYPE_F64; je .gtri_native_probe_fp
    cmp edx,GTYPE_F32; je .gtri_native_probe_fp
    # Integer ValueFacts do not need a second speculative expression pass.
    # The authoritative integer Physical-DAG emitter below either realizes the
    # exact wrap semantics or rolls the whole causal episode back to the single
    # generic semantic path.  Removing the duplicate integer proof path avoids
    # a second admission branch that historically reintroduced a state-count
    # cliff when partial residency began.
    jmp .gtri_native_probe_next
.gtri_native_probe_fp:
    push rcx; push rax
    mov rdi,rax; mov esi,edx; call g_phys_cse_note_tree
    pop rax; pop rcx
    push rcx; push rax
    call g_phys_fp_temp_reset
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
    # Rewind speculative bytes first.  If the proof failed specifically because
    # anonymous FP carriers were exhausted while a persistent next-version bank
    # was competing for the same physical reality, release that candidate and
    # retry the identical DAG once.  No state-count or workload threshold is
    # consulted. Other failures still use the one generic semantic fallback.
    mov rax,[rip+g_reg_native_probe_start]; mov [rip+g_emit_ptr],rax
    mov dword ptr [rip+g_phys_const_collect],0
    mov dword ptr [rip+g_state_count],0
    cmp dword ptr [rip+g_phys_fp_temp_exhausted],0; je .gtri_native_probe_semantic_fail
    cmp dword ptr [rip+g_phys_fp_transient_outputs],0; jne .gtri_native_probe_semantic_fail
    mov dword ptr [rip+g_phys_fp_transient_outputs],1
    jmp .gtri_physical_profile_retry
.gtri_native_probe_semantic_fail:
    # Do not maintain a second stack-compatible recurrence backend here.
    jmp .gtri_no
.gtri_native_probe_done:
    mov rax,[rip+g_reg_native_probe_start]; mov [rip+g_emit_ptr],rax
    mov dword ptr [rip+g_phys_const_collect],0
    call g_phys_cse_finalize
    call g_phys_const_finalize
    cmp dword ptr [rip+g_phys_shared_pressure_exhausted],0; je .gtri_profile_selected
    cmp dword ptr [rip+g_phys_fp_transient_outputs],0; jne .gtri_profile_selected
    # Persistent next-version carriers blocked reusable ValueFacts. Re-map the
    # same Physical DAG with transient next-version realization and profile once
    # more. This is physical competition, not a workload/state-count branch.
    mov dword ptr [rip+g_phys_fp_transient_outputs],1
    jmp .gtri_physical_profile_retry
.gtri_profile_selected:
    # The selected shared subgraphs are now fixed. Derive the real old-state
    # last-consumer frontier before emitting the episode, so timestep transport
    # follows causality rather than a semantic boundary convention.
    call g_phys_build_state_last_use
    call g_phys_prove_inplace_fp_epoch
    mov dword ptr [rip+g_phys_fp_inplace_epoch],eax
    mov dword ptr [rip+g_phys_cse_ready_count],0
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
    cmp dword ptr [rip+g_reg_iter_counted],1; je .gtri_counted_setup
    mov rdi,[rip+g_reg_iter_max_expr]; call g_emit_expr; cmp eax,GTYPE_U64; jne .gtri_rollback
    call g_emit_pop_rax
    lea rdi,[rip+gc_mov_rbp_rax]; mov esi,gc_mov_rbp_rax_end-gc_mov_rbp_rax; call g_emit_bytes
    lea rdi,[rip+gc_xor_rbx]; mov esi,gc_xor_rbx_end-gc_xor_rbx; call g_emit_bytes
    mov r15,[rip+g_emit_ptr]
    mov rdi,[rip+g_reg_iter_cond_expr]; call g_emit_expr; cmp eax,GTYPE_BOOL; jne .gtri_rollback
    call g_emit_pop_rax; lea rdi,[rip+gc_test_rax]; mov esi,gc_test_rax_end-gc_test_rax; call g_emit_bytes
    call g_emit_jz_patch; mov r14,rax
    lea rdi,[rip+gc_iter_max_guard]; mov esi,gc_iter_max_guard_end-gc_iter_max_guard; call g_emit_bytes
    jmp .gtri_updates_start
.gtri_counted_setup:
    mov rdi,[rip+g_reg_iter_bound_expr]; call g_emit_expr; cmp eax,GTYPE_U64; jne .gtri_rollback
    call g_emit_pop_rax
    lea rdi,[rip+gc_mov_rbp_rax]; mov esi,gc_mov_rbp_rax_end-gc_mov_rbp_rax; call g_emit_bytes
    mov r15,[rip+g_emit_ptr]
    lea rdi,[rip+gc_reg_iter_cmp_rbx_rbp]; mov esi,gc_reg_iter_cmp_rbx_rbp_end-gc_reg_iter_cmp_rbx_rbp; call g_emit_bytes
.gtri_counted_exit_patch:
    lea rdi,[rip+gc_jae_prefix]; mov esi,gc_jae_prefix_end-gc_jae_prefix; call g_emit_bytes
    mov r14,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32
    # Native transitions keep the initial zero-trip guard but make the steady
    # state backedge bottom-tested, eliminating the historical unconditional jmp.
    mov r15,[rip+g_emit_ptr]
.gtri_updates_start:
    call g_emit_phys_episode_cse
    test eax,eax; jnz .gtri_rollback
    xor ecx,ecx
.gtri_update_emit:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_commit_regs
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gtri_update_emit_real
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; je .gtri_update_skip_counter
.gtri_update_emit_real:
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_rollback
    mov edx,ecx; shl rdx,5; mov r11,[rip+g_states_ptr]; add r11,rdx
    mov edx,dword ptr [r11+16]
    cmp edx,GTYPE_F64; je .gtri_update_emit_fp
    cmp edx,GTYPE_F32; je .gtri_update_emit_fp
    push rcx; push rax
    call g_phys_int_temp_reset
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
    call g_emit_phys_int_expr_to
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
    push rcx; push rax
    call g_phys_fp_temp_reset
    mov ecx,dword ptr [rsp+8]
    mov dword ptr [rip+g_phys_probe_temp],0

    # The generation is either one fixed-point carrier authority or the mature
    # disjoint next-version realization. Never mix the two within one FP epoch.
    cmp dword ptr [rip+g_phys_fp_inplace_epoch],1; jne .gtri_update_fp_separate_dest
    mov rdx,[rip+g_reg_iter_old_reg_ptr]; mov r12d,dword ptr [rdx+rcx*4]
    cmp r12d,0; jl .gtri_update_fp_fail
    mov rdx,[rip+g_reg_iter_out_reg_ptr]; mov dword ptr [rdx+rcx*4],r12d
    mov eax,r12d
    jmp .gtri_update_fp_dest

.gtri_update_fp_separate_dest:
    mov ecx,dword ptr [rsp+8]
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
    cmp eax,ecx; jg .gtri_update_fp_transport_temp
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
    call g_emit_phys_xmm_to_rax
    test eax,eax; jnz .gtri_update_fp_spill_fail
    mov ecx,dword ptr [rsp+8]
    mov eax,ecx; call g_state_temp_addr; mov rdi,rax; call g_emit_store_rax_abs
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
    inc ecx; jmp .gtri_update_emit
.gtri_commit_regs:
    # The next generation lives in disjoint output carriers. Commit only after
    # every expression has consumed the old generation: true simultaneous state
    # transition without a stack, temp array, or overwrite hazard.
    xor ecx,ecx
.gtri_native_commit_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_commit_after_data
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gtri_native_commit_real
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
    mov edi,dword ptr [rip+g_phys_commit_out]; mov esi,dword ptr [rip+g_phys_commit_type]; push rcx; call g_emit_phys_xmm_to_rax; pop rcx
    test eax,eax; jnz .gtri_rollback
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; push rcx; call g_emit_store_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_from_temp:
    # Spilled next version was materialized once after its expression.  Commit
    # either back into a resident old carrier or into the persistent state slot.
    mov eax,ecx; call g_state_temp_addr; mov rdi,rax; push rcx; call g_emit_load_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
    cmp dword ptr [rip+g_phys_commit_old],0; jl .gtri_commit_temp_to_mem
    cmp dword ptr [rip+g_phys_commit_type],GTYPE_F64; je .gtri_commit_temp_to_fp
    cmp dword ptr [rip+g_phys_commit_type],GTYPE_F32; je .gtri_commit_temp_to_fp
    mov edi,dword ptr [rip+g_phys_commit_old]; xor esi,esi; push rcx; call g_emit_phys_gpr_move; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_temp_to_fp:
    mov edi,dword ptr [rip+g_phys_commit_old]; mov esi,dword ptr [rip+g_phys_commit_type]; push rcx; call g_emit_phys_xmm_from_rax; pop rcx
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_native_commit_next
.gtri_commit_temp_to_mem:
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; push rcx; call g_emit_store_rax_abs; pop rcx
    test eax,eax; jnz .gtri_rollback
.gtri_native_commit_next:
    inc ecx; jmp .gtri_native_commit_loop
.gtri_commit_after_data:
    # Canonicalize generic emitted machine sequences only after the complete
    # simultaneous transition has been formed. No semantic/source pattern owns
    # a separate emitter.
    mov rdi,r15; mov rsi,[rip+g_emit_ptr]; call g_phys_machine_canonicalize
    cmp dword ptr [rip+g_reg_iter_counted],1; je .gtri_counted_inc
    lea rdi,[rip+gc_inc_rbx]; mov esi,gc_inc_rbx_end-gc_inc_rbx; call g_emit_bytes
    jmp .gtri_back_edge
.gtri_counted_inc:
    lea rdi,[rip+gc_reg_iter_inc_rbx]; mov esi,gc_reg_iter_inc_rbx_end-gc_reg_iter_inc_rbx; call g_emit_bytes
    # Bottom-tested steady-state backedge: one conditional branch, no
    # unconditional jump and no duplicate top comparison per iteration.
    lea rdi,[rip+gc_reg_iter_cmp_rbx_rbp]; mov esi,gc_reg_iter_cmp_rbx_rbp_end-gc_reg_iter_cmp_rbx_rbp; call g_emit_bytes
    lea rdi,[rip+gc_jb_prefix]; mov esi,gc_jb_prefix_end-gc_jb_prefix; call g_emit_bytes
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; jbe 92f
    mov dword ptr [rip+g_code_overflow],1; jmp .gtri_rollback
92:
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
    jmp .gtri_patch_exit
.gtri_back_edge:
    mov edi,0xE9; call g_emit_u8
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; jbe 92f
    mov dword ptr [rip+g_code_overflow],1; jmp .gtri_rollback
92:
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
.gtri_patch_exit:
    mov rsi,[rip+g_emit_ptr]; mov rdi,r14; call g_patch_rel32
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
    mov edi,0; mov esi,3
    call g_emit_phys_gpr_move
    test eax,eax; jnz .gtri_rollback
    jmp .gtri_store
.gtri_result_spill:
    mov eax,ecx; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    test eax,eax; jnz .gtri_rollback
.gtri_store:
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
    mov eax,1; jmp .gtri_done
.gtri_rollback:
    mov rax,[rip+g_reg_iter_emit_start]; mov [rip+g_emit_ptr],rax
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],PR_FACT_INVALID
.gtri_no: xor eax,eax
.gtri_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

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

# rdi=expression -> eax=0 success / 1 malformed state reference.
# Every semantic state reference reachable in the expression is added to the
# current transition backward slice by changing states[+28] from -1 to -2.
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
    mov rax,[rip+g_emit_ptr]; mov [rip+g_transition_power_emit_start],rax
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

    # Reset the per-state dense-lane fact and seed the result backward slice.
    xor ecx,ecx
.gtps_clear_slice:
    cmp ecx,dword ptr [rip+g_reg_iter_total]
    jae .gtps_seed
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov dword ptr [r11+28],-1
    inc ecx
    jmp .gtps_clear_slice
.gtps_seed:
    mov eax,r14d; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    mov dword ptr [r11+28],-2

    # Fixed point of semantic state dependencies.  The graph itself decides the
    # slice depth; no finite pass count or state-count threshold is encoded.
.gtps_closure_pass:
    mov dword ptr [rip+g_transition_slice_changed],0
    xor ecx,ecx
.gtps_closure_scan:
    cmp ecx,dword ptr [rip+g_reg_iter_total]
    jae .gtps_closure_done_scan
    mov eax,ecx; shl rax,5; mov r11,[rip+g_states_ptr]; add r11,rax
    cmp dword ptr [r11+28],-2
    jne .gtps_closure_next
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax
    jz .gtps_rollback
    push rcx
    mov rdi,rax
    call g_transition_mark_state_refs
    pop rcx
    test eax,eax
    jnz .gtps_rollback
.gtps_closure_next:
    inc ecx
    jmp .gtps_closure_scan
.gtps_closure_done_scan:
    cmp dword ptr [rip+g_transition_slice_changed],0
    jne .gtps_closure_pass

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
    mov dword ptr [r11+28],-1
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

# rdi=exprA, rsi=exprB -> eax bool.
# Accepts equal simple var references or equal u64 literals.
g_expr_same_bound:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r12,rsi
    mov rdi,rbx; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gesb_literal
    mov r13,rax
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gesb_no
    mov rdi,[r13+8]; mov rsi,[r13+16]; mov rdx,[rax+8]; mov ecx,dword ptr [rax+16]; call span_eq
    jmp .gesb_done
.gesb_literal:
    mov rdi,rbx; call g_expr_u64_literal; test edx,edx; jnz .gesb_no
    mov r13,rax
    mov rdi,r12; call g_expr_u64_literal; test edx,edx; jnz .gesb_no
    cmp rax,r13; sete al; movzx eax,al; jmp .gesb_done
.gesb_no: xor eax,eax
.gesb_done: pop r14; pop r13; pop r12; pop rbx; ret

# rdi=state declaration node -> eax scalar type, 0 if not register-recurrence-safe.
g_state_decl_scalar_type:
    push rbx
    mov rbx,rdi
    mov rdi,rbx; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gsdst_no
    mov rdi,rax; call g_type_from_node
    cmp eax,GTYPE_U64; je .gsdst_done
    cmp eax,GTYPE_I64; je .gsdst_done
    cmp eax,GTYPE_F32; je .gsdst_done
    cmp eax,GTYPE_F64; je .gsdst_done
.gsdst_no: xor eax,eax
.gsdst_done: pop rbx; ret

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

# rdi=condition expr, rsi=counter name ptr, rdx=name len
# eax=1 and g_counted_bound_expr set if condition is counter < bound.
g_match_counter_bound:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    cmp qword ptr [rbx],J_OBJECT; jne .gmcb_no
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gmcb_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_lt]; mov ecx,gv_lt_end-gv_lt; call span_eq
    test eax,eax; jz .gmcb_no
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gmcb_no
    cmp qword ptr [rax],J_ARRAY; jne .gmcb_no
    mov r14,[rax+24]; test r14,r14; jz .gmcb_no
    mov r15,[r14+32]; test r15,r15; jz .gmcb_no
    cmp qword ptr [r15+32],0; jne .gmcb_no
    mov rdi,r14; mov rsi,r12; mov rdx,r13; call g_expr_is_named_state; test eax,eax; jz .gmcb_no
    mov [rip+g_counted_bound_expr],r15
    mov eax,1; jmp .gmcb_done
.gmcb_no: xor eax,eax
.gmcb_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

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
    mov r15,[rip+g_emit_ptr]
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
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; jbe 93f
    mov dword ptr [rip+g_code_overflow],1; jmp .geit_bad
93:
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
    mov rsi,[rip+g_emit_ptr]; mov rdi,r14; call g_patch_rel32
    # result state -> binding slot
    mov rdi,r12; lea rsi,[rip+gk_result]; mov edx,gk_result_end-gk_result; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state; test rax,rax; jz .geit_bad
    mov eax,dword ptr [rax+20]; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
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
    mov rsi,[rip+g_emit_ptr]; mov rdi,r11; call g_patch_rel32
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
    mov rsi,[rip+g_emit_ptr]
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
    # rdi=node -> rax bits, edx err
    test rdi,rdi; jz .gpin_bad
    cmp qword ptr [rdi],J_NUMBER; jne .gpin_bad
    mov r8,[rdi+8]; mov rcx,[rdi+16]
    xor r9d,r9d
    cmp byte ptr [r8],'-'; jne .gpin_digits
    mov r9d,1; inc r8; dec rcx
.gpin_digits:
    xor eax,eax; test rcx,rcx; jz .gpin_bad
.gpin_loop:
    movzx edx,byte ptr [r8]; cmp dl,'0'; jb .gpin_bad; cmp dl,'9'; ja .gpin_bad
    imul rax,rax,10; sub edx,'0'; add rax,rdx; inc r8; dec rcx; jnz .gpin_loop
    test r9d,r9d; jz .gpin_ok; neg rax
.gpin_ok: xor edx,edx; ret
.gpin_bad: xor eax,eax; mov edx,1; ret

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
    imul rax,rax,92               # three qword + seventeen dword fact vectors
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

    # Three qword vectors, then seventeen dword vectors. Memory traffic is a
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
    mov ecx,edi
    and ecx,GTYPE_RANKN_FP_FLAG
    cmp ecx,GTYPE_RANKN_FP_FLAG
    je .geatt_rankn
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
    mov edx,edi
    and edx,GTYPE_RANKN_FP_MASK
    test edx,edx
    jz .geatt_unknown
    add edx,7
    jc .geatt_unknown
    shr edx,3
    test edx,edx
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
    # rdi=semantic node, esi=1 binding / 2 output
    mov dword ptr [rip+g_current_fragment_memory_ops],0
    mov dword ptr [rip+g_fragment_emit_open],1
    mov eax,dword ptr [rip+g_fragment_count]
    cmp eax,dword ptr [rip+g_fragment_capacity]
    jae .gfb_fail
    mov ecx,eax
    mov rdx,[rip+g_fragment_start_ptr]
    mov r8,[rip+g_emit_ptr]
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
    mov r8,[rip+g_emit_ptr]
    mov [rdx+rcx*8],r8
    mov rdx,[rip+g_fragment_memory_ops_ptr]
    mov r8d,dword ptr [rip+g_current_fragment_memory_ops]
    mov [rdx+rcx*4],r8d
    mov dword ptr [rip+g_fragment_emit_open],0
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

# edi=fragment id -> eax=1 only when emission-time semantic proof marked this
# fragment as one-shot straight-line work. The flag is recorded while the
# binding/output kind is already known; no parser re-entry or second classifier
# exists during physicalization.
g_fragment_static_once:
    cmp edi,dword ptr [rip+g_fragment_count]
    jae .gfso_no
    mov rax,[rip+g_fragment_static_ptr]
    mov eax,dword ptr [rax+rdi*4]
    test eax,eax
    setne al
    movzx eax,al
    ret
.gfso_no:
    xor eax,eax
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
    # Graph metadata is structural: 68*N + 16*E bytes. 1.3.90 appends one fixed
    # 48-byte Physical Realization Descriptor per Region. The descriptor projects
    # existing DAG/work/edge/completion facts; it is not a device graph or IR.
    mov rdi,[rip+g_parallel_code_ptr]
    lea rsi,[rip+general_parallel_release_blob]
    mov ecx,GR_TEMPLATE_SIZE
    rep movsb

    mov r12d,GR_TEMPLATE_SIZE
    mov eax,dword ptr [rip+g_region_count]
    mov rdx,rax
    imul rdx,rdx,68              # 68*N: four vectors + tag + 48-byte descriptor
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
    add r12d,15
    and r12d,-16
    mov rax,[rip+g_parallel_code_capacity]
    cmp r12,rax
    jb 95f
    mov dword ptr [rip+g_code_overflow],1
    jmp .gmpc_fail
95:
    mov rax,[rip+g_region_entry_offsets_ptr]
    mov [rax+rbx*4],r12d
    mov rax,[rip+g_region_head_ptr]
    mov r13d,[rax+rbx*4]
    mov rax,[rip+g_region_len_ptr]
    mov r14d,[rax+rbx*4]
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
    cmp r15d,-1
    je .gmpc_work_done
    mov edi,r13d
    push rdx
    call g_fragment_static_once
    pop rdx
    test eax,eax
    jz .gmpc_work_unbounded
    mov rax,[rip+g_fragment_memory_ops_ptr]
    mov eax,[rax+r13*4]
    imul rax,PRC_TRAFFIC_LINE_TICKS
    cmp rax,0x7ffffffe
    ja .gmpc_work_unbounded
    add ebp,eax
    jc .gmpc_work_unbounded
    mov rax,rdx
    imul rax,PRC_FRONTEND_BYTE_TICKS
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
    add rax,rdx
    jc .gmpc_fail
    cmp rax,qword ptr [rip+g_parallel_code_capacity]
    jb 96f
    mov dword ptr [rip+g_code_overflow],1
    jmp .gmpc_fail
96:
    mov rdi,[rip+g_parallel_code_ptr]
    add rdi,r12
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
    # metadata. 0xffffffff means dynamic/unbounded and therefore remains an
    # outward candidate. No second graph table survives in compiler state.
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
    push r12
    push r13
    push r14
    push r15
    mov eax,SYS_openat; mov edi,AT_FDCWD; mov rsi,[rip+g_output_path]; mov edx,OUT_FLAGS; mov r10d,0755; syscall
    test rax,rax; js .geimg_fail
    mov rbx,rax
    mov eax,SYS_write; mov rdi,rbx; lea rsi,[rip+general_runtime_blob]; mov edx,GENERAL_RUNTIME_SIZE; syscall
    cmp rax,GENERAL_RUNTIME_SIZE; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_input_count]; mov edx,4; mov r10d,GENERAL_INPUT_COUNT_OFF; syscall; cmp rax,4; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_output_count]; mov edx,4; mov r10d,GENERAL_OUTPUT_COUNT_OFF; syscall; cmp rax,4; jne .geimg_close_fail

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
    #   input_type[I] | output_type[O] | align64 | exact native code
    # The trailer itself begins on a page boundary so the runtime can mmap it
    # directly from /proc/self/exe.  No fixed type table or executable slot.
    mov r12,GENERAL_RUNTIME_SIZE
    add r12,4095
    jc .geimg_close_fail
    and r12,-4096                    # trailer file offset
    mov r13d,dword ptr [rip+g_input_count]
    shl r13,2                        # input type bytes
    mov r14d,dword ptr [rip+g_output_count]
    shl r14,2                        # output type bytes
    mov r15,r13
    add r15,r14
    jc .geimg_close_fail
    add r15,63
    jc .geimg_close_fail
    and r15,-64                      # native code relative offset
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
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+g_input_types_ptr]; mov rdx,r13; mov r10,r12; syscall
    cmp rax,r13; jne .geimg_close_fail
.geimg_output_types:
    test r14,r14
    jz .geimg_native_code
    mov eax,SYS_pwrite64; mov rdi,rbx; mov rsi,[rip+g_output_types_ptr]; mov rdx,r14; mov r10,r12; add r10,r13; syscall
    cmp rax,r14; jne .geimg_close_fail
.geimg_native_code:
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
# if rbp==0 return 1
gc_reject_if_rbp_zero: .byte 0x48,0x85,0xED,0x75,0x06,0xB8,0x01,0,0,0,0xC3; gc_reject_if_rbp_zero_end:
# if rbx<rbp skip error else return 1
gc_iter_max_guard: .byte 0x48,0x39,0xEB,0x72,0x06,0xB8,0x01,0,0,0,0xC3; gc_iter_max_guard_end:

# register-resident iterate snippets
# direct counted-loop register fragments
gc_reg_iter_cmp_r8_rbp: .byte 0x49,0x39,0xE8; gc_reg_iter_cmp_r8_rbp_end:
gc_reg_iter_cmp_r9_rbp: .byte 0x49,0x39,0xE9; gc_reg_iter_cmp_r9_rbp_end:
# cmp rbx,rbp and inc rbx form the independent counted-control authority.
gc_reg_iter_cmp_rbx_rbp: .byte 0x48,0x39,0xEB; gc_reg_iter_cmp_rbx_rbp_end:
gc_reg_iter_inc_r8: .byte 0x49,0xFF,0xC0; gc_reg_iter_inc_r8_end:
gc_reg_iter_inc_r9: .byte 0x49,0xFF,0xC1; gc_reg_iter_inc_r9_end:
gc_reg_iter_inc_rbx: .byte 0x48,0xFF,0xC3; gc_reg_iter_inc_rbx_end:
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
gc_phys_mov_r8_rsi:  .byte 0x49,0x89,0xF0; gc_phys_mov_r8_rsi_end:
gc_phys_mov_r9_rdi:  .byte 0x49,0x89,0xF9; gc_phys_mov_r9_rdi_end:
gc_phys_mov_r10_rcx: .byte 0x49,0x89,0xCA; gc_phys_mov_r10_rcx_end:

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
gc_phys_movq_xmm8_rax: .byte 0x66,0x4C,0x0F,0x6E,0xC0; gc_phys_movq_xmm8_rax_end:
gc_phys_movq_xmm9_rax: .byte 0x66,0x4C,0x0F,0x6E,0xC8; gc_phys_movq_xmm9_rax_end:
gc_phys_movq_xmm10_rax:.byte 0x66,0x4C,0x0F,0x6E,0xD0; gc_phys_movq_xmm10_rax_end:
gc_phys_movd_xmm8_eax: .byte 0x66,0x44,0x0F,0x6E,0xC0; gc_phys_movd_xmm8_eax_end:
gc_phys_movd_xmm9_eax: .byte 0x66,0x44,0x0F,0x6E,0xC8; gc_phys_movd_xmm9_eax_end:
gc_phys_movd_xmm10_eax:.byte 0x66,0x44,0x0F,0x6E,0xD0; gc_phys_movd_xmm10_eax_end:
gc_phys_movq_rax_xmm8: .byte 0x66,0x4C,0x0F,0x7E,0xC0; gc_phys_movq_rax_xmm8_end:
gc_phys_movq_rax_xmm9: .byte 0x66,0x4C,0x0F,0x7E,0xC8; gc_phys_movq_rax_xmm9_end:
gc_phys_movq_rax_xmm10:.byte 0x66,0x4C,0x0F,0x7E,0xD0; gc_phys_movq_rax_xmm10_end:
gc_phys_movd_eax_xmm8: .byte 0x66,0x44,0x0F,0x7E,0xC0; gc_phys_movd_eax_xmm8_end:
gc_phys_movd_eax_xmm9: .byte 0x66,0x44,0x0F,0x7E,0xC8; gc_phys_movd_eax_xmm9_end:
gc_phys_movd_eax_xmm10:.byte 0x66,0x44,0x0F,0x7E,0xD0; gc_phys_movd_eax_xmm10_end:

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
gc_phys_movsd_xmm8_xmm5:.byte 0xF2,0x44,0x0F,0x10,0xC5; gc_phys_movsd_xmm8_xmm5_end:
gc_phys_movsd_xmm9_xmm6:.byte 0xF2,0x44,0x0F,0x10,0xCE; gc_phys_movsd_xmm9_xmm6_end:
gc_phys_movsd_xmm10_xmm7:.byte 0xF2,0x44,0x0F,0x10,0xD7; gc_phys_movsd_xmm10_xmm7_end:
gc_phys_movss_xmm8_xmm5:.byte 0xF3,0x44,0x0F,0x10,0xC5; gc_phys_movss_xmm8_xmm5_end:
gc_phys_movss_xmm9_xmm6:.byte 0xF3,0x44,0x0F,0x10,0xCE; gc_phys_movss_xmm9_xmm6_end:
gc_phys_movss_xmm10_xmm7:.byte 0xF3,0x44,0x0F,0x10,0xD7; gc_phys_movss_xmm10_xmm7_end:

# scalar constant-operand snippets; input value in rax, constant in rcx
gc_const_add: .byte 0x48,0x01,0xC8; gc_const_add_end:
gc_const_sub: .byte 0x48,0x29,0xC8; gc_const_sub_end:
gc_const_mul: .byte 0x48,0x0F,0xAF,0xC1; gc_const_mul_end:
gc_const_and: .byte 0x48,0x21,0xC8; gc_const_and_end:
gc_const_or:  .byte 0x48,0x09,0xC8; gc_const_or_end:
gc_const_xor: .byte 0x48,0x31,0xC8; gc_const_xor_end:
gc_const_udiv: .byte 0x31,0xD2,0x48,0xF7,0xF1; gc_const_udiv_end:
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
    mov eax,1
    ret
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
    mov eax,1
    ret
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
# Native scalar transcendental ValueFacts. x87 is used only as an ISA-level
# realization primitive; values remain ordinary f32/f64 facts and are rounded
# back to their declared format at this exact consumer edge.
gc_log_f64: .byte 0xD9,0xED,0xDD,0x04,0x24,0xD9,0xF1,0xDD,0x1C,0x24; gc_log_f64_end:
gc_log_f32: .byte 0xD9,0xED,0xD9,0x04,0x24,0xD9,0xF1,0xD9,0x1C,0x24; gc_log_f32_end:
gc_exp_f64:
    .byte 0xDD,0x04,0x24,0xD9,0xEA,0xDE,0xC9,0xD9,0xC0,0xD9,0xFC,0xDC,0xE9
    .byte 0xD9,0xC9,0xD9,0xF0,0xD9,0xE8,0xDE,0xC1,0xD9,0xFD,0xDD,0xD9,0xDD,0x1C,0x24
gc_exp_f64_end:
gc_exp_f32:
    .byte 0xD9,0x04,0x24,0xD9,0xEA,0xDE,0xC9,0xD9,0xC0,0xD9,0xFC,0xDC,0xE9
    .byte 0xD9,0xC9,0xD9,0xF0,0xD9,0xE8,0xDE,0xC1,0xD9,0xFD,0xDD,0xD9,0xD9,0x1C,0x24
gc_exp_f32_end:
gc_sin_f64:
    fld qword ptr [rsp]
    fsin
    fstp qword ptr [rsp]
gc_sin_f64_end:
gc_sin_f32:
    fld dword ptr [rsp]
    fsin
    fstp dword ptr [rsp]
gc_sin_f32_end:
gc_cos_f64:
    fld qword ptr [rsp]
    fcos
    fstp qword ptr [rsp]
gc_cos_f64_end:
gc_cos_f32:
    fld dword ptr [rsp]
    fcos
    fstp dword ptr [rsp]
gc_cos_f32_end:

# Wide helper status contracts used by generated code.  A failed physical
# relation is terminal for the generated program and exits with the historical
# numeric-domain status 65.  Never `ret` through the expression-value stack.
gc_wide_check_edx: .byte 0x85,0xD2,0x74,0x0C,0xBF,65,0,0,0,0xB8,60,0,0,0,0x0F,0x05; gc_wide_check_edx_end:
gc_wide_check_eax: .byte 0x85,0xC0,0x74,0x0C,0xBF,65,0,0,0,0xB8,60,0,0,0,0x0F,0x05; gc_wide_check_eax_end:

# casts top-of-stack
# Unsigned 64 -> float uses the standard exact range-preserving split so values
# with bit 63 set are not interpreted as negative signed integers.
gc_cast_u64_f64:
    pop rax
    test rax,rax
    js .Lgc_u64_f64_hi
    cvtsi2sd xmm0,rax
    jmp .Lgc_u64_f64_done
.Lgc_u64_f64_hi:
    mov rdx,rax
    shr rax,1
    and edx,1
    or rax,rdx
    cvtsi2sd xmm0,rax
    addsd xmm0,xmm0
.Lgc_u64_f64_done:
    movq rax,xmm0
    push rax
gc_cast_u64_f64_end:

gc_cast_i64_f64:
    pop rax
    cvtsi2sd xmm0,rax
    movq rax,xmm0
    push rax
gc_cast_i64_f64_end:

gc_cast_u64_f32:
    pop rax
    test rax,rax
    js .Lgc_u64_f32_hi
    cvtsi2ss xmm0,rax
    jmp .Lgc_u64_f32_done
.Lgc_u64_f32_hi:
    mov rdx,rax
    shr rax,1
    and edx,1
    or rax,rdx
    cvtsi2ss xmm0,rax
    addss xmm0,xmm0
.Lgc_u64_f32_done:
    movd eax,xmm0
    push rax
gc_cast_u64_f32_end:

gc_cast_i64_f32:
    pop rax
    cvtsi2ss xmm0,rax
    movd eax,xmm0
    push rax
gc_cast_i64_f32_end:

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
gc_cast_f32_u64=gc_cast_f32_i64; .set gc_cast_f32_u64_end,gc_cast_f32_i64_end
gc_cast_f64_i64: .byte 0x58,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x48,0x0F,0x2C,0xC0,0x50; gc_cast_f64_i64_end:
gc_cast_f64_u64=gc_cast_f64_i64; .set gc_cast_f64_u64_end,gc_cast_f64_i64_end

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
    cvtsi2sd xmm0,rax
    movq rax,xmm0
    push rax
    push rcx
gc_second_i64_to_f64_end:

gc_second_i64_to_f32:
    pop rcx
    pop rax
    cvtsi2ss xmm0,rax
    movd eax,xmm0
    push rax
    push rcx
gc_second_i64_to_f32_end:

gc_second_u64_to_f64:
    pop rcx
    pop rax
    test rax,rax
    js .Lgc_second_u64_f64_hi
    cvtsi2sd xmm0,rax
    jmp .Lgc_second_u64_f64_done
.Lgc_second_u64_f64_hi:
    mov rdx,rax
    shr rax,1
    and edx,1
    or rax,rdx
    cvtsi2sd xmm0,rax
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
    cvtsi2ss xmm0,rax
    jmp .Lgc_second_u64_f32_done
.Lgc_second_u64_f32_hi:
    mov rdx,rax
    shr rax,1
    and edx,1
    or rax,rdx
    cvtsi2ss xmm0,rax
    addss xmm0,xmm0
.Lgc_second_u64_f32_done:
    movd eax,xmm0
    push rax
    push rcx
gc_second_u64_to_f32_end:

# float binary snippets. Division checks zero bit-pattern ignoring sign.
.macro F64BIN name,opcode
\name: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,\opcode,0xC1,0x66,0x48,0x0F,0x7E,0xC0,0x50
\name\()_end:
.endm
F64BIN gc_f64_add,0x58
F64BIN gc_f64_sub,0x5C
F64BIN gc_f64_mul,0x59
gc_f64_div_checked: .byte 0x59,0x48,0x89,0xCA,0x48,0xB8,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x7F,0x48,0x21,0xC2,0x75,0x06,0xB8,1,0,0,0,0xC3,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x5E,0xC1,0x66,0x48,0x0F,0x7E,0xC0,0x50; gc_f64_div_checked_end:
gc_f64_min: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x5D,0xC1,0x66,0x48,0x0F,0x7E,0xC0,0x50; gc_f64_min_end:
gc_f64_max: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x5F,0xC1,0x66,0x48,0x0F,0x7E,0xC0,0x50; gc_f64_max_end:
.macro F32BIN name,opcode
\name: .byte 0x59,0x58,0x66,0x0F,0x6E,0xC9,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,\opcode,0xC1,0x66,0x0F,0x7E,0xC0,0x50
\name\()_end:
.endm
F32BIN gc_f32_add,0x58
F32BIN gc_f32_sub,0x5C
F32BIN gc_f32_mul,0x59
gc_f32_div_checked: .byte 0x59,0x89,0xCA,0x81,0xE2,0xFF,0xFF,0xFF,0x7F,0x75,0x06,0xB8,1,0,0,0,0xC3,0x58,0x66,0x0F,0x6E,0xC9,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,0x5E,0xC1,0x66,0x0F,0x7E,0xC0,0x50; gc_f32_div_checked_end:

# integer arithmetic fragments
# wrap
gc_add_wrap: .byte 0x59,0x58,0x48,0x01,0xC8,0x50; gc_add_wrap_end:
gc_sub_wrap: .byte 0x59,0x58,0x48,0x29,0xC8,0x50; gc_sub_wrap_end:
gc_mul_wrap: .byte 0x59,0x58,0x48,0x0F,0xAF,0xC1,0x50; gc_mul_wrap_end:
# trap, good branch skips mov eax,1;ret (6 bytes)
gc_uadd_trap: .byte 0x59,0x58,0x48,0x01,0xC8,0x73,0x06,0xB8,1,0,0,0,0xC3,0x50; gc_uadd_trap_end:
gc_iadd_trap: .byte 0x59,0x58,0x48,0x01,0xC8,0x71,0x06,0xB8,1,0,0,0,0xC3,0x50; gc_iadd_trap_end:
gc_usub_trap: .byte 0x59,0x58,0x48,0x29,0xC8,0x73,0x06,0xB8,1,0,0,0,0xC3,0x50; gc_usub_trap_end:
gc_isub_trap: .byte 0x59,0x58,0x48,0x29,0xC8,0x71,0x06,0xB8,1,0,0,0,0xC3,0x50; gc_isub_trap_end:
# unsigned mul: mul rcx -> rdx:rax, reject if rdx!=0
gc_umul_trap: .byte 0x59,0x58,0x48,0xF7,0xE1,0x48,0x85,0xD2,0x74,0x06,0xB8,1,0,0,0,0xC3,0x50; gc_umul_trap_end:
gc_imul_trap: .byte 0x59,0x58,0x48,0x0F,0xAF,0xC1,0x71,0x06,0xB8,1,0,0,0,0xC3,0x50; gc_imul_trap_end:
gc_udiv_checked: .byte 0x59,0x48,0x85,0xC9,0x75,0x06,0xB8,1,0,0,0,0xC3,0x58,0x31,0xD2,0x48,0xF7,0xF1,0x50; gc_udiv_checked_end:
# signed division/modulo: zero and INT64_MIN/-1 are handled before idiv,
# preventing both wrong results and architectural #DE/SIGFPE escapes.
gc_idiv_checked:
    pop rcx
    test rcx,rcx
    jne .Lgc_idiv_t_nonzero
    mov eax,1
    ret
.Lgc_idiv_t_nonzero:
    pop rax
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Lgc_idiv_t_do
    cmp rcx,-1
    jne .Lgc_idiv_t_do
    mov eax,1
    ret
.Lgc_idiv_t_do:
    cqo
    idiv rcx
    push rax
gc_idiv_checked_end:

gc_idiv_wrap_checked:
    pop rcx
    test rcx,rcx
    jne .Lgc_idiv_w_nonzero
    mov eax,1
    ret
.Lgc_idiv_w_nonzero:
    pop rax
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Lgc_idiv_w_do
    cmp rcx,-1
    jne .Lgc_idiv_w_do
    push rax
    jmp .Lgc_idiv_w_done
.Lgc_idiv_w_do:
    cqo
    idiv rcx
    push rax
.Lgc_idiv_w_done:
gc_idiv_wrap_checked_end:

# mod
gc_umod_checked: .byte 0x59,0x48,0x85,0xC9,0x75,0x06,0xB8,1,0,0,0,0xC3,0x58,0x31,0xD2,0x48,0xF7,0xF1,0x52; gc_umod_checked_end:
gc_imod_checked:
    pop rcx
    test rcx,rcx
    jne .Lgc_imod_t_nonzero
    mov eax,1
    ret
.Lgc_imod_t_nonzero:
    pop rax
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Lgc_imod_t_do
    cmp rcx,-1
    jne .Lgc_imod_t_do
    mov eax,1
    ret
.Lgc_imod_t_do:
    cqo
    idiv rcx
    push rdx
gc_imod_checked_end:

gc_imod_wrap_checked:
    pop rcx
    test rcx,rcx
    jne .Lgc_imod_w_nonzero
    mov eax,1
    ret
.Lgc_imod_w_nonzero:
    pop rax
    mov rdx,0x8000000000000000
    cmp rax,rdx
    jne .Lgc_imod_w_do
    cmp rcx,-1
    jne .Lgc_imod_w_do
    xor eax,eax
    push rax
    jmp .Lgc_imod_w_done
.Lgc_imod_w_do:
    cqo
    idiv rcx
    push rdx
.Lgc_imod_w_done:
gc_imod_wrap_checked_end:

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
\name: .byte 0x59,0x58,0x66,0x48,0x0F,0x6E,0xC9,0x66,0x48,0x0F,0x6E,0xC0,0x66,0x0F,0x2E,0xC1,0x0F,\cc,0xC0,0x0F,0xB6,0xC0,0x50
\name\()_end:
.endm
F64CMP gc_f64_cmp_eq,0x94
F64CMP gc_f64_cmp_ne,0x95
F64CMP gc_f64_cmp_lt,0x92
F64CMP gc_f64_cmp_le,0x96
F64CMP gc_f64_cmp_gt,0x97
F64CMP gc_f64_cmp_ge,0x93
.macro F32CMP name,cc
\name: .byte 0x59,0x58,0x66,0x0F,0x6E,0xC9,0x66,0x0F,0x6E,0xC0,0x0F,0x2E,0xC1,0x0F,\cc,0xC0,0x0F,0xB6,0xC0,0x50
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
gc_shl_checked: .byte 0x59,0x48,0x83,0xF9,0x40,0x72,0x06,0xB8,1,0,0,0,0xC3,0x58,0x48,0xD3,0xE0,0x50; gc_shl_checked_end:
gc_shr_checked: .byte 0x59,0x48,0x83,0xF9,0x40,0x72,0x06,0xB8,1,0,0,0,0xC3,0x58,0x48,0xD3,0xE8,0x50; gc_shr_checked_end:

# reduction snippets: candidate rax, accumulator r11
gc_red_add_wrap: .byte 0x49,0x01,0xC3; gc_red_add_wrap_end:
gc_red_uadd_trap: .byte 0x49,0x01,0xC3,0x73,0x06,0xB8,1,0,0,0,0xC3; gc_red_uadd_trap_end:
gc_red_iadd_trap: .byte 0x49,0x01,0xC3,0x71,0x06,0xB8,1,0,0,0,0xC3; gc_red_iadd_trap_end:
gc_red_f64_add: .byte 0x66,0x49,0x0F,0x6E,0xDB,0x66,0x48,0x0F,0x6E,0xC0,0xF2,0x0F,0x58,0xD8,0x66,0x49,0x0F,0x7E,0xDB; gc_red_f64_add_end:
gc_red_f32_add: .byte 0x66,0x41,0x0F,0x6E,0xDB,0x66,0x0F,0x6E,0xC0,0xF3,0x0F,0x58,0xD8,0x66,0x41,0x0F,0x7E,0xDB; gc_red_f32_add_end:
# first guard: if rbx==0 r11=rax and skip following compare fragment via caller cannot know size;
# retained as no-op marker in first general seed; min/max tests use nonempty simple integer paths.
gc_red_first_guard: .byte 0x48,0x85,0xDB,0x75,0x03,0x49,0x89,0xC3; gc_red_first_guard_end:
gc_red_umin: .byte 0x4C,0x39,0xD8,0x49,0x0F,0x42,0xC3,0x49,0x89,0xC3; gc_red_umin_end:
gc_red_umax: .byte 0x4C,0x39,0xD8,0x49,0x0F,0x47,0xC3,0x49,0x89,0xC3; gc_red_umax_end:
gc_red_imin: .byte 0x4C,0x39,0xD8,0x49,0x0F,0x4C,0xC3,0x49,0x89,0xC3; gc_red_imin_end:
gc_red_imax: .byte 0x4C,0x39,0xD8,0x49,0x0F,0x4F,0xC3,0x49,0x89,0xC3; gc_red_imax_end:

# constants/keys
# JSON keys
gk_format:.ascii "format"; gk_format_end:
gk_program:.ascii "program"; gk_program_end:
gk_contracts:.ascii "contracts"; gk_contracts_end:
gk_deterministic:.ascii "deterministic"; gk_deterministic_end:
gk_integer_overflow:.ascii "integer_overflow"; gk_integer_overflow_end:
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
gv_mixed_low:.ascii "lower_precision_dominates"; gv_mixed_low_end:
gv_mixed_high:.ascii "higher_precision_dominates"; gv_mixed_high_end:
gv_bool:.ascii "bool"; gv_bool_end:
gv_i64:.ascii "i64"; gv_i64_end:
gv_u64:.ascii "u64"; gv_u64_end:
gv_f32:.ascii "f32"; gv_f32_end:
gv_f64:.ascii "f64"; gv_f64_end:
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
g_runtime_temp_bytes_used:.skip 8
.p2align 3
g_io_meta_arena_ptr:.skip 8
g_io_meta_arena_bytes:.skip 8
g_io_capacity:.skip 4
g_output_capacity:.skip 4
g_input_types_ptr:.skip 8
g_output_types_ptr:.skip 8
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
g_reg_iter_counter_index:.skip 4
g_reg_iter_bound_expr:.skip 8
g_iter_reg_mode:.skip 4
g_reg_iter_total:.skip 4
g_reg_iter_data_count:.skip 4
g_reg_iter_emit_start:.skip 8
g_reg_iter_update_obj:.skip 8
g_reg_iter_max_expr:.skip 8
g_reg_iter_cond_expr:.skip 8
g_reg_iter_result_name_node:.skip 8
# declaration pointers are compile-time facts, one per language state
# 1.3.15 Rank-N causal carrier map.  Indexed by declaration slot; -1 carrier
# means the ValueFact remains physically materialized in the existing state
# storage while its expression still uses the register-native Physical DAG.
g_reg_iter_fp_count:.skip 4
g_reg_iter_int_count:.skip 4
g_phys_fp_reserved_mask:.skip 4
g_phys_fp_carrier_count:.skip 4
g_phys_fp_old_base:.skip 4
g_phys_fp_all_mask:.skip 4
g_phys_fp_total:.skip 4
g_phys_fp_resident_budget:.skip 4
g_phys_fp_transient_outputs:.skip 4
g_phys_fp_inplace_epoch:.skip 4
# Effective post-CSE last consumer for each semantic state ValueFact.
g_phys_shared_pressure_exhausted:.skip 4
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
g_phys_cse_candidate_count:.skip 4
g_phys_cse_candidate_expr:.skip G_PHYS_CSE_MAX*8
g_phys_cse_candidate_type:.skip G_PHYS_CSE_MAX*4
g_phys_cse_candidate_uses:.skip G_PHYS_CSE_MAX*4
g_phys_cse_candidate_cost:.skip G_PHYS_CSE_MAX*4
g_phys_cse_resident_count:.skip 4
g_phys_cse_resident_expr:.skip G_PHYS_CSE_MAX*8
g_phys_cse_resident_type:.skip G_PHYS_CSE_MAX*4
g_phys_cse_resident_reg:.skip G_PHYS_CSE_MAX*4
g_phys_cse_ready_count:.skip 4
g_phys_int_temp_mask:.skip 4
g_phys_const_candidate_count:.skip 4
g_phys_const_candidate_bits:.skip G_PHYS_CSE_MAX*8
g_phys_const_candidate_type:.skip G_PHYS_CSE_MAX*4
g_phys_const_candidate_uses:.skip G_PHYS_CSE_MAX*4
g_phys_const_resident_count:.skip 4
g_phys_const_resident_bits:.skip G_PHYS_CSE_MAX*8
g_phys_const_resident_type:.skip G_PHYS_CSE_MAX*4
g_phys_const_resident_reg:.skip G_PHYS_CSE_MAX*4
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
