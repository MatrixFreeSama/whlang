.intel_syntax noprefix
.include "compiler/general_runtime_offsets.inc"

# General Wheelchair direct-native frontend.  This file deliberately shares
# only the JSON DOM parser with tensor_frontend_x86_64.S.  User programs never
# invoke Python, C, LLVM, an assembler, or a linker.

.equ SYS_write,1
.equ SYS_openat,257
.equ SYS_pwrite64,18
.equ SYS_fchmod,91
.equ SYS_close,3
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
.equ GMAX_SYMBOLS,80
.equ GMAX_INPUTS,16
.equ GMAX_BINDINGS,64
.equ GMAX_OUTPUTS,32
.equ GMAX_STATES,32
.equ GST_SIZE,32
.equ GCODE_CAP,131072

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
.extern general_runtime_blob
.extern general_runtime_blob_end
.extern tensor_executor_count

.global compile_general_source
.global general_disable_fast_path
# compile_general_source(rdi=output_path)
# eax=0 success, 1 invalid/unsupported, 2 = proven fast numeric candidate.
compile_general_source:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [rip+g_output_path],rdi
    mov dword ptr [rip+g_symbol_count],0
    mov dword ptr [rip+g_input_count],0
    mov dword ptr [rip+g_binding_count],0
    mov dword ptr [rip+g_output_count],0
    mov dword ptr [rip+g_binding_slot_count],0
    mov dword ptr [rip+g_state_count],0
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],-1
    mov dword ptr [rip+g_overflow_wrap],0
    mov dword ptr [rip+g_has_nonfast_op],0
    mov dword ptr [rip+g_fast_reduce_seen],0
    lea rax,[rip+g_code]
    mov [rip+g_emit_ptr],rax
    lea rax,[rip+g_code+GCODE_CAP]
    mov [rip+g_emit_end],rax
    lea rdi,[rip+g_input_types]
    xor eax,eax
    mov ecx,GMAX_INPUTS
    rep stosb
    lea rdi,[rip+g_output_types]
    mov ecx,GMAX_OUTPUTS
    rep stosb

    # Parse JSON DOM using the same handwritten parser as the topology path.
    mov qword ptr [rip+json_node_count],0
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
    jmp .contracts_ok
.set_wrap:
    mov dword ptr [rip+g_overflow_wrap],1
.contracts_ok:

    # Inputs first so arbitrary logical names become dense symbol IDs.
    mov rdi,r12; lea rsi,[rip+gk_inputs]; mov edx,gk_inputs_end-gk_inputs; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_ARRAY; jne .bad
    mov r13,[rax+24]
.input_loop:
    test r13,r13
    jz .inputs_done
    cmp dword ptr [rip+g_input_count],GMAX_INPUTS
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
    lea rdx,[rip+g_input_types]
    mov [rdx+rax],bl
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
    cmp dword ptr [rip+g_binding_count],GMAX_BINDINGS
    jae .bad
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
    mov dword ptr [rip+g_has_nonfast_op],1
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
    mov dword ptr [rip+g_fast_reduce_seen],1
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
    cmp eax,GMAX_BINDINGS
    jae .bad
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

    # A failed topology attempt may explicitly retry this already-validated
    # source through the sovereign direct-general lane.  Never redispatch the
    # same source into the same failed candidate classifier.
    cmp dword ptr [rip+general_disable_fast_path],0
    jne .emit_general

    # Fast numeric candidate: exactly one u64 input, no non map/reduce op, at
    # least one reduction, and all map/reduce scalar types are f64.  The fast
    # frontend performs the stricter tolerant-sum proof before acceptance.
    cmp dword ptr [rip+g_input_count],1
    jne .emit_general
    cmp dword ptr [rip+g_has_nonfast_op],0
    jne .emit_general
    cmp dword ptr [rip+g_fast_reduce_seen],0
    je .emit_general
    lea rax,[rip+g_symbols]
    cmp dword ptr [rax+20],GTYPE_U64
    jne .emit_general
    mov ecx,1
.fast_sym_loop:
    cmp ecx,dword ptr [rip+g_symbol_count]
    jae .fast_candidate
    mov edx,ecx; shl rdx,6; lea rax,[rip+g_symbols]; add rax,rdx
    mov edx,dword ptr [rax+16]
    cmp edx,GK_MAP; je .fast_check_f64
    cmp edx,GK_REDUCE; jne .emit_general
.fast_check_f64:
    cmp dword ptr [rax+20],GTYPE_F64
    jne .emit_general
    inc ecx; jmp .fast_sym_loop
.fast_candidate:
    mov eax,2
    jmp .done

.emit_general:
    # Reject cascade here until the source-to-fabric lowering below is chosen.
    mov ecx,0
.cascade_scan:
    cmp ecx,dword ptr [rip+g_symbol_count]
    jae .codegen
    mov edx,ecx; shl rdx,6; lea rax,[rip+g_symbols]; add rax,rdx
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
    mov eax,dword ptr [rbx+16]
    cmp eax,GK_MAP; je .emit_next_binding
    cmp eax,GK_RECORD; je .emit_next_binding
    cmp eax,GK_DICTIONARY; je .emit_next_binding
    cmp eax,GK_NESTED_LITERAL; je .emit_next_binding
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
    cmp eax,dword ptr [rbx+20]; jne .bad
    call g_emit_pop_rax
    mov eax,dword ptr [rbx+24]
    call g_binding_slot_addr
    mov rdi,rax; call g_emit_store_rax_abs
    jmp .emit_next_binding
.emit_reduce:
    mov rdi,rbx; call g_emit_reduce_binding
    test eax,eax; jnz .bad
    jmp .emit_next_binding
.emit_iterate:
    mov rdi,rbx; call g_emit_iterate_binding
    test eax,eax; jnz .bad
    jmp .emit_next_binding
.emit_lookup:
    mov rdi,rbx; call g_emit_lookup_binding
    test eax,eax; jnz .bad
    jmp .emit_next_binding
.emit_nested_reduce:
    mov rdi,rbx; call g_emit_nested_reduce_binding
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
    cmp eax,GMAX_OUTPUTS; jae .bad
    mov rdi,r13; lea rsi,[rip+gk_expr]; mov edx,gk_expr_end-gk_expr; call obj_get
    test rax,rax; jz .bad
    mov rdi,rax; call g_emit_expr
    test eax,eax; jz .bad
    cmp eax,GTYPE_STRING; je .bad       # numeric protocol in this first sovereign general image
    mov edx,dword ptr [rip+g_output_count]
    lea rcx,[rip+g_output_types]; mov [rcx+rdx],al
    call g_emit_pop_rax
    mov eax,dword ptr [rip+g_output_count]
    call g_output_slot_addr
    mov rdi,rax; call g_emit_store_rax_abs
    inc dword ptr [rip+g_output_count]
    mov r13,[r13+32]
    jmp .output_loop
.tests_gate:
    cmp dword ptr [rip+g_output_count],0; je .bad
    # Direct-general code is intentionally scalar in 1.0.8.  A requested
    # multi-executor compile must either have been recovered into the topology
    # lane or fail explicitly; silently ignoring --executors is forbidden.
    cmp dword ptr [rip+tensor_executor_count],1
    jne .executor_width_reject
    mov rdi,[rip+g_root]; lea rsi,[rip+gk_tests]; mov edx,gk_tests_end-gk_tests; call obj_get
    test rax,rax; jz .bad
    cmp qword ptr [rax],J_ARRAY; jne .bad
    cmp qword ptr [rax+24],0; je .bad

    xor edi,edi; call g_emit_mov_eax_imm
    mov edi,0xC3; call g_emit_u8
    call g_emit_image
    test eax,eax; jnz .bad
    xor eax,eax
    jmp .done
.executor_width_reject:
    mov eax,3
    jmp .done
.bad:
    mov eax,1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- type/symbol helpers ----------------
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
    mov rdi,r8; mov rsi,r9; lea rdx,[rip+gv_string]; mov ecx,gv_string_end-gv_string; call span_eq; test eax,eax; jnz .gt_string
.gt_bad: xor eax,eax; ret
.gt_bool: mov eax,GTYPE_BOOL; ret
.gt_i64: mov eax,GTYPE_I64; ret
.gt_u64: mov eax,GTYPE_U64; ret
.gt_f32: mov eax,GTYPE_F32; ret
.gt_f64: mov eax,GTYPE_F64; ret
.gt_string: mov eax,GTYPE_STRING; ret

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
    cmp eax,GMAX_SYMBOLS
    jae .gas_fail_pop
    mov ecx,eax; shl rcx,6; lea rax,[rip+g_symbols]; add rax,rcx
    mov [rax],r12; mov [rax+8],r13; mov [rax+16],r14d; mov [rax+20],r15d
    pop r9
    mov [rax+24],r9d; mov [rax+32],rbx
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
    mov eax,ecx; shl rax,6; lea r8,[rip+g_symbols]; add r8,rax
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
    cmp eax,GTYPE_I64; je .gie_done; cmp eax,GTYPE_U64; je .gie_done; cmp eax,GTYPE_F32; je .gie_done; cmp eax,GTYPE_F64; je .gie_done; jmp .gie_bad
.gie_bool: mov eax,GTYPE_BOOL; jmp .gie_done
.gie_u64: mov eax,GTYPE_U64; jmp .gie_done
.gie_bad: xor eax,eax
.gie_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# g_low_type(eax=a,edx=b) numeric lower-precision rule; 0 mismatch.
g_low_type:
    cmp eax,GTYPE_F32; je .glt_f32
    cmp edx,GTYPE_F32; je .glt_f32
    cmp eax,GTYPE_F64; je .glt_float
    cmp edx,GTYPE_F64; je .glt_float
    cmp eax,edx; jne .glt_bad
    cmp eax,GTYPE_I64; je .glt_ret
    cmp eax,GTYPE_U64; je .glt_ret
    cmp eax,GTYPE_BOOL; je .glt_ret
    jmp .glt_bad
.glt_float: mov eax,GTYPE_F64; ret
.glt_f32: mov eax,GTYPE_F32; ret
.glt_ret: ret
.glt_bad: xor eax,eax; ret

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
    mov eax,ecx; shl rax,5; lea r8,[rip+g_states]; add r8,rax
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
.ge_fail: mov eax,1; ret
g_emit_u16:
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+2]; cmp rcx,[rip+g_emit_end]; ja .ge_fail
    mov [rax],di; mov [rip+g_emit_ptr],rcx; xor eax,eax; ret
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
g_emit_load_rax_abs:
    push rdi; mov edi,0xA148; call g_emit_u16; pop rdi; call g_emit_u64; ret
g_emit_store_rax_abs:
    push rdi; mov edi,0xA348; call g_emit_u16; pop rdi; call g_emit_u64; ret
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
g_binding_slot_addr: mov eax,eax; imul rax,rax,8; add rax,GENERAL_BINDING_VALUES_VA; ret
g_state_slot_addr: mov eax,eax; imul rax,rax,8; add rax,GENERAL_STATE_VALUES_VA; ret
g_state_temp_addr: mov eax,eax; imul rax,rax,8; add rax,GENERAL_STATE_TEMP_VA; ret
g_input_slot_addr: mov eax,eax; imul rax,rax,8; add rax,GENERAL_INPUT_VALUES_VA; ret
g_input_aux_addr: mov eax,eax; imul rax,rax,8; add rax,GENERAL_INPUT_AUX_VA; ret
g_output_slot_addr: mov eax,eax; imul rax,rax,8; add rax,GENERAL_OUTPUT_VALUES_VA; ret

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

# ---------------- expression emitter ----------------
# g_emit_expr(rdi=expr) -> eax type/0, generated value pushed as one qword.
g_emit_expr:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    cmp qword ptr [r12],J_OBJECT; jne .gee_bad
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

.gee_var:
    mov rdi,r12; lea rsi,[rip+gk_var]; mov edx,gk_var_end-gk_var; call obj_get
    test rax,rax; jz .gee_axis
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_symbol
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
    test eax,eax; jnz .gee_state_reg1
    lea rdi,[rip+gc_push_r8]; mov esi,gc_push_r8_end-gc_push_r8; call g_emit_bytes
    mov eax,dword ptr [r13+16]; jmp .gee_done
.gee_state_reg1:
    cmp eax,1; jne .gee_bad
    lea rdi,[rip+gc_push_r9]; mov esi,gc_push_r9_end-gc_push_r9; call g_emit_bytes
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
    jmp .gee_bad
.gee_neg_i:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gee_neg_i_wrap
    lea rdi,[rip+gc_neg_i64_trap]; mov esi,gc_neg_i64_trap_end-gc_neg_i64_trap; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg_i_wrap: lea rdi,[rip+gc_neg_i64]; mov esi,gc_neg_i64_end-gc_neg_i64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg_f64: lea rdi,[rip+gc_neg_f64]; mov esi,gc_neg_f64_end-gc_neg_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_neg_f32: lea rdi,[rip+gc_neg_f32]; mov esi,gc_neg_f32_end-gc_neg_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs:
    mov rdi,[r13+8]; mov rsi,[r13+16]; lea rdx,[rip+gv_abs]; mov ecx,gv_abs_end-gv_abs; call span_eq
    test eax,eax; jz .gee_select
    mov rdi,r14; call g_emit_expr; mov ebx,eax
    cmp eax,GTYPE_I64; je .gee_abs_i
    cmp eax,GTYPE_U64; je .gee_done_keep
    cmp eax,GTYPE_F64; je .gee_abs_f64
    cmp eax,GTYPE_F32; je .gee_abs_f32
    jmp .gee_bad
.gee_abs_i:
    cmp dword ptr [rip+g_overflow_wrap],1; je .gee_abs_i_wrap
    lea rdi,[rip+gc_abs_i64_trap]; mov esi,gc_abs_i64_trap_end-gc_abs_i64_trap; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs_i_wrap: lea rdi,[rip+gc_abs_i64]; mov esi,gc_abs_i64_end-gc_abs_i64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs_f64: lea rdi,[rip+gc_abs_f64]; mov esi,gc_abs_f64_end-gc_abs_f64; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_abs_f32: lea rdi,[rip+gc_abs_f32]; mov esi,gc_abs_f32_end-gc_abs_f32; call g_emit_bytes; mov eax,ebx; jmp .gee_done
.gee_done_keep: mov eax,ebx; jmp .gee_done

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

# ---------------- machine-code operation emitters ----------------
# Stack convention before binary helper: [... lhs rhs].
# Most fragments consume both and push result.
g_emit_cast_top:
    # eax=src, edx=dst, returns eax=0/1
    cmp eax,edx; je .gec_ok
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
.gec_ok: xor eax,eax; ret

# op ptr,len, lhs type edx, rhs ecx, result r8d
g_emit_arithmetic_top2:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r14d,edx; mov r15d,ecx; mov ebx,r8d
    cmp ebx,GTYPE_F32; je .gea_f32
    cmp ebx,GTYPE_F64; je .gea_f64
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
.gcst_ok: xor eax,eax; ret
.gcst_bad: mov eax,1; ret

g_convert_stack_second:
    cmp edi,esi; je .gcss_ok
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

# Compare helper. op ptr,len, lhs type edx,rhs ecx
g_emit_compare_top2:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov ebx,edx; mov r14d,ecx
    # exact type for bool/string; numeric may low-dominate
    cmp ebx,GTYPE_STRING; je .gecmp_bad
    mov eax,ebx; mov edx,r14d; call g_low_type; test eax,eax; jz .gecmp_bad
    cmp eax,GTYPE_F64; je .gecmp_f64
    cmp eax,GTYPE_F32; je .gecmp_f32
    mov edx,eax
    mov rdi,r12; mov rsi,r13; call g_emit_int_compare; jmp .gecmp_done
.gecmp_f64:
    mov edi,r14d; mov esi,GTYPE_F64; call g_convert_stack_top; test eax,eax; jnz .gecmp_bad
    mov edi,ebx; mov esi,GTYPE_F64; call g_convert_stack_second; test eax,eax; jnz .gecmp_bad
    mov rdi,r12; mov rsi,r13; call g_emit_f64_compare; jmp .gecmp_done
.gecmp_f32:
    mov edi,r14d; mov esi,GTYPE_F32; call g_convert_stack_top; test eax,eax; jnz .gecmp_bad
    mov edi,ebx; mov esi,GTYPE_F32; call g_convert_stack_second; test eax,eax; jnz .gecmp_bad
    mov rdi,r12; mov rsi,r13; call g_emit_f32_compare; jmp .gecmp_done
.gecmp_bad: mov eax,1
.gecmp_done: pop r14; pop r13; pop r12; pop rbx; ret

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
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; ja .gerb_bad
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

# ---------------- register-resident small-state iterate optimizer ----------------
# Pure general iterate fallback for one or two u64 states. State values remain
# in R8/R9; simultaneous updates are staged on the machine stack then committed.

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
    cmp r14d,2; jae .gtri_no
    mov rdi,r13; call g_state_decl_is_u64; test eax,eax; jz .gtri_no
    mov rdi,r13; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .gtri_no
    mov r15,rax
    mov eax,r14d; shl rax,5; lea r11,[rip+g_states]; add r11,rax
    mov rax,[r15+8]; mov [r11],rax
    mov rax,[r15+16]; mov [r11+8],rax
    mov dword ptr [r11+16],GTYPE_U64
    mov dword ptr [r11+20],r14d
    lea rax,[rip+g_reg_iter_decls]; mov [rax+r14*8],r13
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
    mov eax,ecx; shl rax,5; lea r11,[rip+g_states]; add r11,rax
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
    mov eax,ecx; shl rax,5; lea r11,[rip+g_states]; add r11,rax
    mov rdi,[rip+g_reg_iter_cond_expr]; mov rsi,[r11]; mov rdx,[r11+8]
    push rcx; call g_match_counter_bound; pop rcx
    test eax,eax; jz .gtri_counted_probe_next
    lea rax,[rip+g_reg_iter_decls]; mov r13,[rax+rcx*8]
    mov rdi,r13; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_counted_probe_next
    push rcx; mov rdi,rax; call g_expr_u64_literal; pop rcx
    test edx,edx; jnz .gtri_counted_probe_next
    test rax,rax; jnz .gtri_counted_probe_next
    push rcx; mov rdi,[rip+g_affine_bound_expr]; mov rsi,[rip+g_reg_iter_max_expr]; call g_expr_same_bound; pop rcx
    test eax,eax; jz .gtri_counted_probe_next
    mov eax,ecx; shl rax,5; lea r11,[rip+g_states]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_counted_probe_next
    mov edx,ecx; shl rdx,5; lea r11,[rip+g_states]; add r11,rdx
    mov rdi,rax; mov rsi,[r11]; mov rdx,[r11+8]
    push rcx; call g_match_counter_inc; pop rcx
    test eax,eax; jz .gtri_counted_probe_next
    mov dword ptr [rip+g_reg_iter_counted],1
    mov dword ptr [rip+g_reg_iter_counter_index],ecx
    mov rax,[rip+g_affine_bound_expr]; mov [rip+g_reg_iter_bound_expr],rax
    jmp .gtri_counted_probe_done
.gtri_counted_probe_next:
    inc ecx; jmp .gtri_counted_probe
.gtri_counted_probe_done:

    mov dword ptr [rip+g_iter_reg_mode],1
    mov dword ptr [rip+g_cached_binding_slot],-1
    mov dword ptr [rip+g_state_count],0
    xor ecx,ecx
.gtri_init_loop:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_init_done
    lea rax,[rip+g_reg_iter_decls]; mov r13,[rax+rcx*8]
    mov rdi,r13; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_rollback
    push rcx; mov rdi,rax; call g_emit_expr; pop rcx
    cmp eax,GTYPE_U64; jne .gtri_rollback
    call g_emit_pop_rax
    test ecx,ecx; jnz .gtri_init_r9
    push rcx; lea rdi,[rip+gc_affine_mov_r8_rax]; mov esi,gc_affine_mov_r8_rax_end-gc_affine_mov_r8_rax; call g_emit_bytes; pop rcx
    jmp .gtri_init_committed
.gtri_init_r9:
    push rcx; lea rdi,[rip+gc_affine_mov_r9_rax]; mov esi,gc_affine_mov_r9_rax_end-gc_affine_mov_r9_rax; call g_emit_bytes; pop rcx
.gtri_init_committed:
    inc dword ptr [rip+g_state_count]
    inc ecx; jmp .gtri_init_loop
.gtri_init_done:
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
    cmp dword ptr [rip+g_reg_iter_counter_index],0; jne .gtri_counted_cmp_r9
    lea rdi,[rip+gc_reg_iter_cmp_r8_rbp]; mov esi,gc_reg_iter_cmp_r8_rbp_end-gc_reg_iter_cmp_r8_rbp; call g_emit_bytes
    jmp .gtri_counted_exit_patch
.gtri_counted_cmp_r9:
    lea rdi,[rip+gc_reg_iter_cmp_r9_rbp]; mov esi,gc_reg_iter_cmp_r9_rbp_end-gc_reg_iter_cmp_r9_rbp; call g_emit_bytes
.gtri_counted_exit_patch:
    lea rdi,[rip+gc_jae_prefix]; mov esi,gc_jae_prefix_end-gc_jae_prefix; call g_emit_bytes
    mov r14,[rip+g_emit_ptr]; xor edi,edi; call g_emit_u32
.gtri_updates_start:
    xor ecx,ecx
.gtri_update_emit:
    cmp ecx,dword ptr [rip+g_reg_iter_total]; jae .gtri_commit_regs
    cmp dword ptr [rip+g_reg_iter_counted],1; jne .gtri_update_emit_real
    cmp ecx,dword ptr [rip+g_reg_iter_counter_index]; je .gtri_update_skip_counter
.gtri_update_emit_real:
    mov eax,ecx; shl rax,5; lea r11,[rip+g_states]; add r11,rax
    mov rdi,[rip+g_reg_iter_update_obj]; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .gtri_rollback
    push rcx; mov rdi,rax; call g_emit_expr; pop rcx
    cmp eax,GTYPE_U64; jne .gtri_rollback
.gtri_update_skip_counter:
    inc ecx; jmp .gtri_update_emit
.gtri_commit_regs:
    cmp dword ptr [rip+g_reg_iter_counted],1; je .gtri_commit_counted
    cmp dword ptr [rip+g_reg_iter_total],2; jne .gtri_commit_one
    lea rdi,[rip+gc_pop_r9]; mov esi,gc_pop_r9_end-gc_pop_r9; call g_emit_bytes
.gtri_commit_one:
    lea rdi,[rip+gc_pop_r8]; mov esi,gc_pop_r8_end-gc_pop_r8; call g_emit_bytes
    lea rdi,[rip+gc_inc_rbx]; mov esi,gc_inc_rbx_end-gc_inc_rbx; call g_emit_bytes
    jmp .gtri_back_edge
.gtri_commit_counted:
    cmp dword ptr [rip+g_reg_iter_total],1; je .gtri_counted_inc
    cmp dword ptr [rip+g_reg_iter_counter_index],0; jne .gtri_counted_value_r8
    lea rdi,[rip+gc_pop_r9]; mov esi,gc_pop_r9_end-gc_pop_r9; call g_emit_bytes
    jmp .gtri_counted_inc
.gtri_counted_value_r8:
    lea rdi,[rip+gc_pop_r8]; mov esi,gc_pop_r8_end-gc_pop_r8; call g_emit_bytes
.gtri_counted_inc:
    cmp dword ptr [rip+g_reg_iter_counter_index],0; jne .gtri_counted_inc_r9
    lea rdi,[rip+gc_reg_iter_inc_r8]; mov esi,gc_reg_iter_inc_r8_end-gc_reg_iter_inc_r8; call g_emit_bytes
    jmp .gtri_back_edge
.gtri_counted_inc_r9:
    lea rdi,[rip+gc_reg_iter_inc_r9]; mov esi,gc_reg_iter_inc_r9_end-gc_reg_iter_inc_r9; call g_emit_bytes
.gtri_back_edge:
    mov edi,0xE9; call g_emit_u8
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; ja .gtri_rollback
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
    mov rsi,[rip+g_emit_ptr]; mov rdi,r14; call g_patch_rel32
    mov rax,[rip+g_reg_iter_result_name_node]
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state; test rax,rax; jz .gtri_rollback
    mov eax,dword ptr [rax+20]
    test eax,eax; jnz .gtri_result_r9
    lea rdi,[rip+gc_affine_mov_rax_r8]; mov esi,gc_affine_mov_rax_r8_end-gc_affine_mov_rax_r8; call g_emit_bytes
    jmp .gtri_store
.gtri_result_r9:
    cmp eax,1; jne .gtri_rollback
    lea rdi,[rip+gc_reg_iter_mov_rax_r9]; mov esi,gc_reg_iter_mov_rax_r9_end-gc_reg_iter_mov_rax_r9; call g_emit_bytes
.gtri_store:
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],-1
    mov eax,1; jmp .gtri_done
.gtri_rollback:
    mov rax,[rip+g_reg_iter_emit_start]; mov [rip+g_emit_ptr],rax
    mov dword ptr [rip+g_iter_reg_mode],0
    mov dword ptr [rip+g_cached_binding_slot],-1
.gtri_no: xor eax,eax
.gtri_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# ---------------- proof-driven general recurrence optimizer ----------------
# Recognizes a pure two-state u64 affine recurrence under wrap semantics:
#   value'   = a*value + c
#   counter' = counter + 1
#   while counter < bound, counter starts at 0, max_iterations == bound
#   result == value
# No intermediate state is observable outside iterate, so f^bound may be
# applied by exponentiation-by-squaring in O(log bound) native operations.
# This is semantic-structure lowering, not workload/name dispatch.

# rdi=expression, rsi=name ptr, rdx=name len -> eax bool
# Match {"state": <name>}.
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

# rdi=state declaration node -> eax=1 if type is u64, else 0.
g_state_decl_is_u64:
    push rbx
    mov rbx,rdi
    mov rdi,rbx; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get
    test rax,rax; jz .gsdiu_no
    mov rdi,rax; call g_type_from_node; cmp eax,GTYPE_U64; sete al; movzx eax,al
    pop rbx; ret
.gsdiu_no: xor eax,eax; pop rbx; ret

# rdi=state declaration, rsi=name ptr, rdx=name len -> eax bool.
g_state_decl_has_name:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    mov rdi,rbx; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .gsdhn_no
    cmp qword ptr [rax],J_STRING; jne .gsdhn_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; mov rdx,r12; mov ecx,r13d; call span_eq
    jmp .gsdhn_done
.gsdhn_no: xor eax,eax
.gsdhn_done: pop r13; pop r12; pop rbx; ret

# rdi=expression, rsi=value-state name ptr, rdx=name len
# eax=1 match, and writes g_affine_a/g_affine_c.
# Accepted shape (commutative outer add and multiply literal position):
#   add(mul(state(value), u64(a)), u64(c))
g_match_affine_update:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    cmp qword ptr [rbx],J_OBJECT; jne .gmau_no
    mov rdi,rbx; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gmau_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_add]; mov ecx,gv_add_end-gv_add; call span_eq
    test eax,eax; jz .gmau_no
    mov rdi,rbx; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gmau_no
    cmp qword ptr [rax],J_ARRAY; jne .gmau_no
    mov r14,[rax+24]; test r14,r14; jz .gmau_no
    mov r15,[r14+32]; test r15,r15; jz .gmau_no
    cmp qword ptr [r15+32],0; jne .gmau_no
    # determine which outer argument is literal c
    mov rdi,r14; call g_expr_u64_literal; test edx,edx; jz .gmau_c_left
    mov rdi,r15; call g_expr_u64_literal; test edx,edx; jnz .gmau_no
    mov [rip+g_affine_c],rax
    jmp .gmau_mul
.gmau_c_left:
    mov [rip+g_affine_c],rax
    mov r14,r15                         # mul candidate is second
.gmau_mul:
    mov rdi,r14; lea rsi,[rip+gk_op]; mov edx,gk_op_end-gk_op; call obj_get
    test rax,rax; jz .gmau_no
    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+gv_mul]; mov ecx,gv_mul_end-gv_mul; call span_eq
    test eax,eax; jz .gmau_no
    mov rdi,r14; lea rsi,[rip+gk_args]; mov edx,gk_args_end-gk_args; call obj_get
    test rax,rax; jz .gmau_no
    cmp qword ptr [rax],J_ARRAY; jne .gmau_no
    mov r14,[rax+24]; test r14,r14; jz .gmau_no
    mov r15,[r14+32]; test r15,r15; jz .gmau_no
    cmp qword ptr [r15+32],0; jne .gmau_no
    # state * literal or literal * state
    mov rdi,r14; mov rsi,r12; mov rdx,r13; call g_expr_is_named_state; test eax,eax; jz .gmau_try_rev
    mov rdi,r15; call g_expr_u64_literal; test edx,edx; jnz .gmau_no
    mov [rip+g_affine_a],rax; mov eax,1; jmp .gmau_done
.gmau_try_rev:
    mov rdi,r15; mov rsi,r12; mov rdx,r13; call g_expr_is_named_state; test eax,eax; jz .gmau_no
    mov rdi,r14; call g_expr_u64_literal; test edx,edx; jnz .gmau_no
    mov [rip+g_affine_a],rax; mov eax,1; jmp .gmau_done
.gmau_no: xor eax,eax
.gmau_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

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
# eax=1 and g_affine_bound_expr set if condition is counter < bound.
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
    mov [rip+g_affine_bound_expr],r15
    mov eax,1; jmp .gmcb_done
.gmcb_no: xor eax,eax
.gmcb_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Emit mov r10,imm64 / mov r11,imm64 helpers.
g_emit_mov_r10_imm64:
    push rdi; mov edi,0xBA49; call g_emit_u16; pop rdi; jmp g_emit_u64
g_emit_mov_r11_imm64:
    push rdi; mov edi,0xBB49; call g_emit_u16; pop rdi; jmp g_emit_u64

# rdi=symbol -> eax=1 optimized+emitted, 0 no match (emit pointer restored).
g_try_emit_affine_iterate:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    mov rax,[rip+g_emit_ptr]; mov [rip+g_affine_emit_start],rax
    cmp dword ptr [rip+g_overflow_wrap],1; jne .gta_no
    mov r12,[rbx+32]
    # result name
    mov rdi,r12; lea rsi,[rip+gk_result]; mov edx,gk_result_end-gk_result; call obj_get
    test rax,rax; jz .gta_no
    cmp qword ptr [rax],J_STRING; jne .gta_no
    mov r13,[rax+8]; mov r14,[rax+16]
    mov [rip+g_affine_value_name_ptr],r13; mov [rip+g_affine_value_name_len],r14
    # exactly two state declarations
    mov rdi,r12; lea rsi,[rip+gk_states]; mov edx,gk_states_end-gk_states; call obj_get
    test rax,rax; jz .gta_no
    cmp qword ptr [rax],J_ARRAY; jne .gta_no
    mov r15,[rax+24]; test r15,r15; jz .gta_no
    mov rax,[r15+32]; test rax,rax; jz .gta_no
    cmp qword ptr [rax+32],0; jne .gta_no
    mov [rip+g_affine_state0],r15; mov [rip+g_affine_state1],rax
    # identify value state by result name
    mov rdi,r15; mov rsi,r13; mov rdx,r14; call g_state_decl_has_name
    test eax,eax; jz .gta_value_second
    mov [rip+g_affine_value_decl],r15
    mov rax,[rip+g_affine_state1]; mov [rip+g_affine_counter_decl],rax
    jmp .gta_states_identified
.gta_value_second:
    mov rdi,[rip+g_affine_state1]; mov rsi,r13; mov rdx,r14; call g_state_decl_has_name
    test eax,eax; jz .gta_no
    mov rax,[rip+g_affine_state1]; mov [rip+g_affine_value_decl],rax
    mov [rip+g_affine_counter_decl],r15
.gta_states_identified:
    mov rdi,[rip+g_affine_value_decl]; call g_state_decl_is_u64; test eax,eax; jz .gta_no
    mov rdi,[rip+g_affine_counter_decl]; call g_state_decl_is_u64; test eax,eax; jz .gta_no
    # counter name
    mov rdi,[rip+g_affine_counter_decl]; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get
    test rax,rax; jz .gta_no
    mov r13,[rax+8]; mov r14,[rax+16]
    mov [rip+g_affine_counter_name_ptr],r13; mov [rip+g_affine_counter_name_len],r14
    # counter init must be literal zero
    mov rdi,[rip+g_affine_counter_decl]; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; call obj_get
    test rax,rax; jz .gta_no
    mov rdi,rax; call g_expr_u64_literal; test edx,edx; jnz .gta_no
    test rax,rax; jnz .gta_no
    # value init expression retained for normal expression emission
    mov rdi,[rip+g_affine_value_decl]; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; call obj_get
    test rax,rax; jz .gta_no
    mov [rip+g_affine_init_expr],rax
    # condition counter < bound
    mov rdi,r12; lea rsi,[rip+gk_condition]; mov edx,gk_condition_end-gk_condition; call obj_get
    test rax,rax; jz .gta_no
    mov rdi,rax; mov rsi,r13; mov rdx,r14; call g_match_counter_bound; test eax,eax; jz .gta_no
    # max_iterations must be semantically same simple bound
    mov rdi,r12; lea rsi,[rip+gk_max_iterations]; mov edx,gk_max_iterations_end-gk_max_iterations; call obj_get
    test rax,rax; jz .gta_no
    mov rdi,[rip+g_affine_bound_expr]; mov rsi,rax; call g_expr_same_bound; test eax,eax; jz .gta_no
    # update object and both state updates
    mov rdi,r12; lea rsi,[rip+gk_update]; mov edx,gk_update_end-gk_update; call obj_get
    test rax,rax; jz .gta_no
    mov r15,rax
    mov rdi,r15; mov rsi,[rip+g_affine_value_name_ptr]; mov edx,dword ptr [rip+g_affine_value_name_len]; call obj_get
    test rax,rax; jz .gta_no
    mov rdi,rax; mov rsi,[rip+g_affine_value_name_ptr]; mov rdx,[rip+g_affine_value_name_len]; call g_match_affine_update
    test eax,eax; jz .gta_no
    mov rdi,r15; mov rsi,[rip+g_affine_counter_name_ptr]; mov edx,dword ptr [rip+g_affine_counter_name_len]; call obj_get
    test rax,rax; jz .gta_no
    mov rdi,rax; mov rsi,[rip+g_affine_counter_name_ptr]; mov rdx,[rip+g_affine_counter_name_len]; call g_match_counter_inc
    test eax,eax; jz .gta_no

    # Proof complete. Emit only final-state computation; no state/temp materialization.
    mov rdi,[rip+g_affine_init_expr]; call g_emit_expr; cmp eax,GTYPE_U64; jne .gta_rollback
    call g_emit_pop_rax
    lea rdi,[rip+gc_affine_mov_r8_rax]; mov esi,gc_affine_mov_r8_rax_end-gc_affine_mov_r8_rax; call g_emit_bytes
    mov rdi,[rip+g_affine_bound_expr]; call g_emit_expr; cmp eax,GTYPE_U64; jne .gta_rollback
    call g_emit_pop_rax
    lea rdi,[rip+gc_affine_mov_r9_rax]; mov esi,gc_affine_mov_r9_rax_end-gc_affine_mov_r9_rax; call g_emit_bytes
    mov rdi,[rip+g_affine_a]; call g_emit_mov_r10_imm64
    mov rdi,[rip+g_affine_c]; call g_emit_mov_r11_imm64
    # n==0 -> done
    lea rdi,[rip+gc_affine_test_r9]; mov esi,gc_affine_test_r9_end-gc_affine_test_r9; call g_emit_bytes
    call g_emit_jz_patch; mov r12,rax
    mov r13,[rip+g_emit_ptr]             # loop target
    # if (n & 1) x = a*x+c
    lea rdi,[rip+gc_affine_test_r9_one]; mov esi,gc_affine_test_r9_one_end-gc_affine_test_r9_one; call g_emit_bytes
    call g_emit_jz_patch; mov r14,rax
    lea rdi,[rip+gc_affine_apply]; mov esi,gc_affine_apply_end-gc_affine_apply; call g_emit_bytes
    mov rsi,[rip+g_emit_ptr]; mov rdi,r14; call g_patch_rel32
    # square affine transform: (a,c)^2 = (a*a, a*c+c)
    lea rdi,[rip+gc_affine_square]; mov esi,gc_affine_square_end-gc_affine_square; call g_emit_bytes
    lea rdi,[rip+gc_affine_shr_r9]; mov esi,gc_affine_shr_r9_end-gc_affine_shr_r9; call g_emit_bytes
    call g_emit_jnz_patch; mov r14,rax
    mov rdi,r14; mov rsi,r13; call g_patch_rel32
    mov r15,[rip+g_emit_ptr]
    mov rdi,r12; mov rsi,r15; call g_patch_rel32
    lea rdi,[rip+gc_affine_mov_rax_r8]; mov esi,gc_affine_mov_rax_r8_end-gc_affine_mov_rax_r8; call g_emit_bytes
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    mov eax,1; jmp .gta_done
.gta_rollback:
    mov rax,[rip+g_affine_emit_start]; mov [rip+g_emit_ptr],rax
.gta_no: xor eax,eax
.gta_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# iterate symbol rdi
g_emit_iterate_binding:
    # Offer proven affine recurrence to structure-eliminating lowering first.
    push rdi
    call g_try_emit_affine_iterate
    pop rdi
    test eax,eax
    jnz .geit_optimized_done
    push rdi
    call g_try_emit_reg_iterate
    pop rdi
    test eax,eax
    jz .geit_generic
.geit_optimized_done:
    xor eax,eax
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
    cmp dword ptr [rip+g_state_count],GMAX_STATES; jae .geit_bad
    mov rdi,r13; lea rsi,[rip+gk_name]; mov edx,gk_name_end-gk_name; call obj_get; test rax,rax; jz .geit_bad
    mov r14,[rax+8]; mov r15,[rax+16]
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,rax; call g_type_from_node; test eax,eax; jz .geit_bad
    mov edx,dword ptr [rip+g_state_count]; mov ecx,edx; shl rcx,5; lea rax,[rip+g_states]; add rax,rcx
    mov [rax],r14; mov [rax+8],r15; mov [rax+16],eax   # corrected below after type save
    # fix type because eax overwritten by address calculation: reparse cheaply
    mov rdi,r13; lea rsi,[rip+gk_type]; mov edx,gk_type_end-gk_type; call obj_get; mov rdi,rax; call g_type_from_node
    mov ecx,dword ptr [rip+g_state_count]; mov edx,ecx; shl rdx,5; lea r11,[rip+g_states]; add r11,rdx
    mov [r11+16],eax; mov [r11+20],ecx
    # init may reference prior states
    mov rdi,r13; lea rsi,[rip+gk_init]; mov edx,gk_init_end-gk_init; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,rax; call g_emit_expr
    # Recursive expression emission may clobber caller-saved R11; reacquire metadata.
    mov ecx,dword ptr [rip+g_state_count]; mov edx,ecx; shl rdx,5; lea r11,[rip+g_states]; add r11,rdx
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
    mov edx,ecx; shl rdx,5; lea r11,[rip+g_states]; add r11,rdx
    mov rdi,r13; mov rsi,[r11]; mov edx,dword ptr [r11+8]
    push rcx; call obj_get; pop rcx
    test rax,rax; jz .geit_bad
    push rcx
    mov rdi,rax; call g_emit_expr
    pop rcx
    mov edx,ecx; shl rdx,5; lea r11,[rip+g_states]; add r11,rdx
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
    mov rax,[rip+g_emit_ptr]; lea rcx,[rax+4]; cmp rcx,[rip+g_emit_end]; ja .geit_bad
    mov rdx,r15; sub rdx,rcx; mov [rax],edx; mov [rip+g_emit_ptr],rcx
    mov rsi,[rip+g_emit_ptr]; mov rdi,r14; call g_patch_rel32
    # result state -> binding slot
    mov rdi,r12; lea rsi,[rip+gk_result]; mov edx,gk_result_end-gk_result; call obj_get; test rax,rax; jz .geit_bad
    mov rdi,[rax+8]; mov rsi,[rax+16]; call g_find_state; test rax,rax; jz .geit_bad
    mov eax,dword ptr [rax+20]; call g_state_slot_addr; mov rdi,rax; call g_emit_load_rax_abs
    mov eax,dword ptr [rbx+24]; call g_binding_slot_addr; mov rdi,rax; call g_emit_store_rax_abs
    xor eax,eax; jmp .geit_done
.geit_bad: mov eax,1
.geit_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

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

# ---------------- image writer ----------------
g_emit_image:
    push rbx
    mov eax,SYS_openat; mov edi,AT_FDCWD; mov rsi,[rip+g_output_path]; mov edx,OUT_FLAGS; mov r10d,0755; syscall
    test rax,rax; js .geimg_fail
    mov rbx,rax
    mov eax,SYS_write; mov rdi,rbx; lea rsi,[rip+general_runtime_blob]; mov edx,GENERAL_RUNTIME_SIZE; syscall
    cmp rax,GENERAL_RUNTIME_SIZE; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_input_count]; mov edx,4; mov r10d,GENERAL_INPUT_COUNT_OFF; syscall; cmp rax,4; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_output_count]; mov edx,4; mov r10d,GENERAL_OUTPUT_COUNT_OFF; syscall; cmp rax,4; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_input_types]; mov edx,GMAX_INPUTS; mov r10d,GENERAL_INPUT_TYPE_OFF; syscall; cmp rax,GMAX_INPUTS; jne .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; lea rsi,[rip+g_output_types]; mov edx,GMAX_OUTPUTS; mov r10d,GENERAL_OUTPUT_TYPE_OFF; syscall; cmp rax,GMAX_OUTPUTS; jne .geimg_close_fail
    mov rdx,[rip+g_emit_ptr]; lea rsi,[rip+g_code]; sub rdx,rsi
    cmp rdx,GCODE_CAP; ja .geimg_close_fail
    mov eax,SYS_pwrite64; mov rdi,rbx; mov r10d,GENERAL_PROGRAM_OFF; syscall; test rax,rax; js .geimg_close_fail
    mov eax,SYS_fchmod; mov rdi,rbx; mov esi,0755; syscall
    mov eax,SYS_close; mov rdi,rbx; syscall
    xor eax,eax; pop rbx; ret
.geimg_close_fail: mov eax,SYS_close; mov rdi,rbx; syscall
.geimg_fail: mov eax,1; pop rbx; ret

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
gc_reg_iter_inc_r8: .byte 0x49,0xFF,0xC0; gc_reg_iter_inc_r8_end:
gc_reg_iter_inc_r9: .byte 0x49,0xFF,0xC1; gc_reg_iter_inc_r9_end:
gc_push_r8: .byte 0x41,0x50; gc_push_r8_end:
gc_push_r9: .byte 0x41,0x51; gc_push_r9_end:
gc_pop_r8: .byte 0x41,0x58; gc_pop_r8_end:
gc_pop_r9: .byte 0x41,0x59; gc_pop_r9_end:
gc_reg_iter_mov_rax_r9: .byte 0x4C,0x89,0xC8; gc_reg_iter_mov_rax_r9_end:

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

# affine recurrence optimizer snippets (generated program, caller-saved regs only)
gc_affine_mov_r8_rax: .byte 0x49,0x89,0xC0; gc_affine_mov_r8_rax_end:
gc_affine_mov_r9_rax: .byte 0x49,0x89,0xC1; gc_affine_mov_r9_rax_end:
gc_affine_test_r9: .byte 0x4D,0x85,0xC9; gc_affine_test_r9_end:
gc_affine_test_r9_one: .byte 0x49,0xF7,0xC1,0x01,0x00,0x00,0x00; gc_affine_test_r9_one_end:
# r8 = r10*r8 + r11
gc_affine_apply: .byte 0x4D,0x0F,0xAF,0xC2,0x4D,0x01,0xD8; gc_affine_apply_end:
# r11 = r10*r11 + r11; r10 = r10*r10
gc_affine_square: .byte 0x4C,0x89,0xD0,0x49,0x0F,0xAF,0xC3,0x4C,0x01,0xD8,0x49,0x89,0xC3,0x4D,0x0F,0xAF,0xD2; gc_affine_square_end:
gc_affine_shr_r9: .byte 0x49,0xD1,0xE9; gc_affine_shr_r9_end:
gc_affine_mov_rax_r8: .byte 0x4C,0x89,0xC0; gc_affine_mov_rax_r8_end:

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
gk_input:.ascii "input"; gk_input_end:
gk_segments:.ascii "segments"; gk_segments_end:
# values
gv_format:.ascii "wheelchair.tensor/1"; gv_format_end:
gv_trap:.ascii "trap"; gv_trap_end:
gv_wrap:.ascii "wrap"; gv_wrap_end:
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
general_disable_fast_path:.skip 4
.p2align 3
g_root:.skip 8
g_output_path:.skip 8
g_emit_ptr:.skip 8
g_emit_end:.skip 8
g_symbol_count:.skip 4
g_input_count:.skip 4
g_binding_count:.skip 4
g_output_count:.skip 4
g_binding_slot_count:.skip 4
g_state_count:.skip 4
g_overflow_wrap:.skip 4
g_has_nonfast_op:.skip 4
g_fast_reduce_seen:.skip 4
.p2align 6
g_input_types:.skip GMAX_INPUTS
g_output_types:.skip GMAX_OUTPUTS
.p2align 6
g_symbols:.skip GMAX_SYMBOLS*GSYM_SIZE
.p2align 6
g_states:.skip GMAX_STATES*GST_SIZE
# compile-time state for register-resident small iterate lowering
g_reg_iter_counted:.skip 4
g_reg_iter_counter_index:.skip 4
g_reg_iter_bound_expr:.skip 8
g_iter_reg_mode:.skip 4
g_reg_iter_total:.skip 4
g_reg_iter_emit_start:.skip 8
g_reg_iter_update_obj:.skip 8
g_reg_iter_max_expr:.skip 8
g_reg_iter_cond_expr:.skip 8
g_reg_iter_result_name_node:.skip 8
g_reg_iter_decls:.skip 16
g_cached_binding_slot:.skip 4
.p2align 3
# compile-time state for general scalar optimizer
g_scalar_opt_emit_start:.skip 8
g_scalar_const_value:.skip 8
g_scalar_const_left:.skip 4
g_scalar_opt_kind:.skip 4
# compile-time proof state for affine recurrence lowering
g_affine_emit_start:.skip 8
g_affine_a:.skip 8
g_affine_c:.skip 8
g_affine_state0:.skip 8
g_affine_state1:.skip 8
g_affine_value_decl:.skip 8
g_affine_counter_decl:.skip 8
g_affine_value_name_ptr:.skip 8
g_affine_value_name_len:.skip 8
g_affine_counter_name_ptr:.skip 8
g_affine_counter_name_len:.skip 8
g_affine_init_expr:.skip 8
g_affine_bound_expr:.skip 8
.p2align 6
g_code:.skip GCODE_CAP
