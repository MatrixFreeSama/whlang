# -----------------------------------------------------------------------------
# Wheelchair 1.2.18 native materialized-field human surface.
#
# This is included by surface_lowerer_x86_64.S so it reuses the sovereign
# handwritten lexer/expression AST.  It is compile-time only.  It lowers WH/WHEX
# field declarations into the existing wheelchair.field/1 canonical graph and
# therefore adds no runtime layer, no C/LLVM/JIT path, no scalar fallback and no
# scheduling policy.
# -----------------------------------------------------------------------------

.include "compiler/field_runtime_capacity.inc"
.equ SFH_MAX_RANK,FIELD_RUNTIME_RANK_CAP
.equ SFH_MODE_INPUT,0
.equ SFH_MODE_OUTPUT,1
.equ SFH_MODE_INOUT,2
.equ SFH_NO_AST,0
.equ SFH_ERR_GENERIC,1
.equ SFH_ERR_BOUNDARY,2
.equ SFH_ERR_DOMAIN,3
.equ SFH_ERR_TYPE,4
.equ SFH_ERR_EXPR,5

.section .text
.global surface_field_lower_to_json
.global surface_field_error_code
.global surface_field_recognized

# surface_field_lower_to_json(rdi=source path, globals source_ptr/source_length)
# eax=0 success and globals point at wheelchair.field/1 canonical bytes.
# eax=1 means "not this surface / unsupported" and leaves source globals intact.
surface_field_lower_to_json:
    push rbx; push r12; push r13; push r14; push r15
    call s_diag_reset_for_path
    mov r12,[rip+source_ptr]
    mov r13,[rip+source_length]
    mov [rip+sfh_orig_source_ptr],r12
    mov [rip+sfh_orig_source_len],r13

    # The field human shell shares the sovereign Surface AST/fact allocator.
    # Prepare the same dynamic arenas before any AST-producing parse path; this
    # keeps field classification independent of the historical static slabs.
    mov qword ptr [rip+s_ast_cur],0
    mov qword ptr [rip+s_ast_end],0
    mov qword ptr [rip+s_ast_next_slab_bytes],0
    mov qword ptr [rip+s_struct_temp_cur],0
    mov qword ptr [rip+s_struct_temp_end],0
    mov qword ptr [rip+s_struct_temp_next_slab_bytes],0
    call s_prepare_surface_arenas
    test eax,eax; jnz .sfh_lower_alloc_fail

    # Scalar extent names and reduction declarations are compile-time Surface
    # metadata, not Field runtime records.  Size them from this source instance
    # instead of preserving the historical 32/8 parser ceilings.
    mov eax,dword ptr [rip+s_fact_cap]
    mov rsi,rax; imul rsi,112
    jo .sfh_lower_alloc_fail
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .sfh_lower_alloc_fail
    mov [rip+sfh_meta_arena],rax
    mov rcx,[rip+sfh_meta_arena]
    mov [rip+sfh_scalar_ptr],rcx
    mov eax,dword ptr [rip+s_fact_cap]
    mov rdx,rax; shl rdx,3
    add rcx,rdx; mov [rip+sfh_scalar_len],rcx
    add rcx,rdx; mov [rip+sfh_reduce_name_ptr],rcx
    add rcx,rdx; mov [rip+sfh_reduce_name_len],rcx
    add rcx,rdx; mov [rip+sfh_reduce_expr],rcx
    add rcx,rdx; mov [rip+sfh_field_name_ptr_ptr],rcx
    add rcx,rdx; mov [rip+sfh_field_name_len_ptr],rcx
    mov rdx,rax
    add rcx,rdx; mov [rip+sfh_field_mode_ptr],rcx
    add rcx,rdx; mov [rip+sfh_field_rank_ptr],rcx
    add rcx,rdx
    mov rdx,rax; shl rdx,3
    mov [rip+sfh_field_expr_ptr],rcx; add rcx,rdx
    mov rdx,rax; imul rdx,SFH_MAX_RANK
    mov [rip+sfh_field_periodic_ptr],rcx; add rcx,rdx
    mov rdx,rax
    mov [rip+sfh_access_field_ptr],rcx; add rcx,rdx
    mov rdx,rax; imul rdx,SFH_MAX_RANK*4
    mov [rip+sfh_access_delta_ptr],rcx

    # Reset shared lexer/AST state without touching the ordinary tensor buffers.
    mov dword ptr [rip+s_error],0
    mov dword ptr [rip+s_ast_count],0
    mov dword ptr [rip+s_decl_count],0
    mov dword ptr [rip+s_struct_decl_count],0
    mov dword ptr [rip+s_state_count],0
    mov dword ptr [rip+s_function_count],0
    call s_axis_scope_clear
    mov rax,r12; mov [rip+s_src],rax; mov [rip+s_cur],rax
    add rax,r13; mov [rip+s_end],rax

    mov dword ptr [rip+sfh_field_count],0
    mov dword ptr [rip+sfh_scalar_count],0
    mov dword ptr [rip+sfh_domain_rank],0
    mov dword ptr [rip+sfh_output_count],0
    mov dword ptr [rip+sfh_reduce_count],0
    mov dword ptr [rip+sfh_access_count],0
    mov dword ptr [rip+sfh_op_count],0
    mov dword ptr [rip+sfh_fp_tolerant],0
    mov dword ptr [rip+sfh_saw_field_surface],0
    mov dword ptr [rip+surface_field_recognized],0
    mov dword ptr [rip+surface_field_error_code],0

    # Compile-time op stream is accumulated in the same growable serialization
    # arena discipline as the ordinary Surface streams.  This buffer has no
    # independent language-capacity ceiling; only real allocation failure stops it.
    lea rbx,[rip+sfh_ops_buf]; lea r12,[rip+sfh_ops_cap]
    call s_alloc_stream_arena; test eax,eax; jnz .sfh_lower_alloc_fail
    lea rax,[rip+sfh_ops_buf]; mov [rip+s_active_base_var],rax
    lea rax,[rip+sfh_ops_end]; mov [rip+s_active_end_var],rax
    lea rax,[rip+sfh_ops_cap]; mov [rip+s_active_cap_var],rax
    mov rax,[rip+sfh_ops_buf]; mov [rip+s_out_ptr],rax
    add rax,[rip+sfh_ops_cap]; mov [rip+s_out_limit],rax

    call sfh_parse_program
    test eax,eax; jnz .sfh_lower_fail
    cmp dword ptr [rip+sfh_saw_field_surface],0; je .sfh_lower_fail
    cmp dword ptr [rip+sfh_field_count],0; je .sfh_lower_fail

    # access[0] is the canonical identity access required by the field backend.
    mov dword ptr [rip+sfh_access_count],1
    mov rax,[rip+sfh_access_field_ptr]; mov byte ptr [rax],0

    call sfh_compile_outputs
    test eax,eax; jnz .sfh_lower_fail
    call sfh_compile_reductions
    test eax,eax; jnz .sfh_lower_fail
    call sfh_capture_ops_end
    cmp dword ptr [rip+sfh_output_count],0; je .sfh_lower_fail
    call sfh_emit_final_json
    test eax,eax; jnz .sfh_lower_fail

    mov rax,[rip+surface_json_buffer]
    mov [rip+source_ptr],rax
    mov rax,[rip+surface_json_length]
    mov [rip+source_length],rax
    xor eax,eax
    jmp .sfh_lower_done
.sfh_lower_alloc_fail:
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_GENERIC
.sfh_lower_fail:
    call s_diag_note_error_cursor
    mov rax,[rip+sfh_orig_source_ptr]; mov [rip+source_ptr],rax
    mov rax,[rip+sfh_orig_source_len]; mov [rip+source_length],rax
    mov dword ptr [rip+s_error],0
    cmp dword ptr [rip+surface_field_error_code],0
    jne .sfh_lower_have_error
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_GENERIC
.sfh_lower_have_error:
    mov eax,1
    cmp dword ptr [rip+surface_field_recognized],0
    je .sfh_lower_done
    mov eax,2
.sfh_lower_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx
    ret

# -----------------------------------------------------------------------------
# Program/declaration parser
# -----------------------------------------------------------------------------
sfh_parse_program:
.sfh_pp_loop:
    call s_skip
    mov rax,[rip+s_cur]; cmp rax,[rip+s_end]; jae .sfh_pp_ok

    lea rdi,[rip+sfh_kw_program]; mov esi,7; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_program
    lea rdi,[rip+sfh_kw_strict]; mov esi,6; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_strict
    lea rdi,[rip+sfh_kw_tolerance]; mov esi,9; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_tolerance
    lea rdi,[rip+sfh_kw_let]; mov esi,3; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_let
    lea rdi,[rip+sfh_kw_input]; mov esi,5; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_input
    lea rdi,[rip+sfh_kw_output]; mov esi,6; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_output
    lea rdi,[rip+sfh_kw_inout]; mov esi,5; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_inout
    lea rdi,[rip+sfh_kw_pure]; mov esi,4; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_pure
    lea rdi,[rip+sfh_kw_region]; mov esi,6; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_region
    lea rdi,[rip+sfh_kw_for]; mov esi,3; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_for
    lea rdi,[rip+sfh_kw_sum]; mov esi,3; mov edx,1; call s_match_token
    test eax,eax; jnz .sfh_pp_sum
    # A top-level assignment is accepted after declarations as compact WHEX.
    call sfh_parse_assignment
    test eax,eax; jz .sfh_pp_loop
    mov eax,1; ret

.sfh_pp_program:
    call s_parse_name; test edx,edx; jnz .sfh_pp_fail
    call s_optional_semicolon
    jmp .sfh_pp_loop
.sfh_pp_strict:
    mov dword ptr [rip+sfh_fp_tolerant],0
    call s_optional_semicolon
    jmp .sfh_pp_loop
.sfh_pp_tolerance:
    call s_parse_number_span; test edx,edx; jnz .sfh_pp_fail
    mov dword ptr [rip+sfh_fp_tolerant],1
    call s_optional_semicolon
    jmp .sfh_pp_loop
.sfh_pp_let:
    call sfh_parse_static_struct_let; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_input:
    lea rdi,[rip+sfh_kw_field]; mov esi,5; mov edx,1; call s_match_token
    test eax,eax; jz .sfh_pp_scalar
    mov edi,SFH_MODE_INPUT; call sfh_parse_field_decl; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_scalar:
    call sfh_parse_scalar_input; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_output:
    lea rdi,[rip+sfh_kw_field]; mov esi,5; mov edx,1; call s_match_token
    test eax,eax; jz .sfh_pp_scalar_output
    mov edi,SFH_MODE_OUTPUT; call sfh_parse_field_decl; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_scalar_output:
    call sfh_parse_scalar_output; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_inout:
    lea rdi,[rip+sfh_kw_field]; mov esi,5; mov edx,1; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pp_fail
    mov edi,SFH_MODE_INOUT; call sfh_parse_field_decl; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_pure:
    call s_parse_pure_function; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_region:
    call sfh_parse_region; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_for:
    call sfh_parse_for; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_sum:
    call sfh_parse_reduce_decl; test eax,eax; jnz .sfh_pp_fail
    jmp .sfh_pp_loop
.sfh_pp_ok: xor eax,eax; ret
.sfh_pp_fail: mov eax,1; ret

# A field-program `let` may bind an existing Structured Fact as compile-time
# data.  It emits no field/scalar/runtime binding: the wrapper exists only long
# enough for shared expression lowering (for example matrix + mget + contract)
# to erase it into the same scalar AST that a hand-expanded source would make.
sfh_parse_static_struct_let:
    push rbx; push r12; push r13; push r14
    call s_parse_name; test edx,edx; jnz .sfh_pssl_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .sfh_pssl_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pssl_fail
    # Field classification must not speculatively execute arbitrary general
    # Structured Facts (for example RootFact) just because a program starts
    # with `let`.  This bridge is only for the existing compile-time MatrixFact
    # coefficient family used by field expressions; general lets stay owned by
    # the sovereign general surface.
    mov rbx,[rip+s_cur]
    lea rdi,[rip+sfh_kw_matrix]; mov esi,6; mov edx,1; call s_match_token
    mov [rip+s_cur],rbx
    test eax,eax; jz .sfh_pssl_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sfh_pssl_fail
    mov r14,rax
    cmp dword ptr [r14+SN_KIND],NK_STRUCT; jne .sfh_pssl_fail
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_struct_decl_add
    test eax,eax; jnz .sfh_pssl_fail
    call s_optional_semicolon
    xor eax,eax; jmp .sfh_pssl_done
.sfh_pssl_fail:
    mov eax,1
.sfh_pssl_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# Scalar extent inputs are surface-only shape names.  Runtime extents come from
# the native field descriptors, so these declarations generate no ABI argument.
sfh_parse_scalar_input:
    push rbx; push r12; push r13
    call s_parse_name; test edx,edx; jnz .sfh_psi_fail
    mov r12,rax; mov r13,rcx
    mov ebx,dword ptr [rip+sfh_scalar_count]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .sfh_psi_fail
    mov rax,[rip+sfh_scalar_ptr]; mov [rax+rbx*8],r12
    mov rax,[rip+sfh_scalar_len]; mov [rax+rbx*8],r13
    inc dword ptr [rip+sfh_scalar_count]
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sfh_psi_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+sfh_ty_u64]; mov ecx,3; call s_span_eq
    test eax,eax; jz .sfh_psi_fail
    # Optional range MIN..MAX is documentation/admission metadata for the human
    # surface.  The field descriptor remains the runtime source of shape truth.
    lea rdi,[rip+sfh_kw_range]; mov esi,5; mov edx,1; call s_match_token
    test eax,eax; jz .sfh_psi_done
    call s_parse_number_span; test edx,edx; jnz .sfh_psi_fail
    lea rdi,[rip+tok_dotdot]; mov esi,2; xor edx,edx; call s_expect_token
    call s_parse_number_span; test edx,edx; jnz .sfh_psi_fail
.sfh_psi_done:
    call s_optional_semicolon; xor eax,eax; jmp .sfh_psi_exit
.sfh_psi_fail: mov eax,1
.sfh_psi_exit: pop r13; pop r12; pop rbx; ret


# Materialized-field scalar reduction surface.  It maps to the existing runtime
# checksum reduction; the name is a human/WHEX symbol and creates no new ABI.
# Grammar: NAME[axis in extent, ...]: f32 = expression
sfh_parse_reduce_decl:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,dword ptr [rip+sfh_reduce_count]
    cmp ebx,dword ptr [rip+s_fact_cap]; jae .sfh_prd_fail
    call s_parse_name; test edx,edx; jnz .sfh_prd_fail
    mov rdx,[rip+sfh_reduce_name_ptr]; mov [rdx+rbx*8],rax
    mov rdx,[rip+sfh_reduce_name_len]; mov [rdx+rbx*8],rcx
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_prd_fail
    xor r14d,r14d
.sfh_prd_axis:
    cmp r14d,dword ptr [rip+sfh_domain_rank]; jae .sfh_prd_fail
    call s_parse_name; test edx,edx; jnz .sfh_prd_fail
    mov r12,rax; mov r13,rcx
    lea rax,[rip+sfh_axis_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+sfh_axis_len]; mov rsi,[rax+r14*8]
    mov rdx,r12; mov rcx,r13; call s_span_eq; test eax,eax; jz .sfh_prd_domain
    lea rdi,[rip+sfh_kw_in]; mov esi,2; mov edx,1; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_prd_fail
    call s_parse_name; test edx,edx; jnz .sfh_prd_fail
    mov r12,rax; mov r13,rcx
.sfh_prd_extent_ready:
    lea rax,[rip+sfh_extent_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+sfh_extent_len]; mov rsi,[rax+r14*8]
    mov rdx,r12; mov rcx,r13; call s_span_eq; test eax,eax; jz .sfh_prd_domain
    inc r14d
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sfh_prd_axis
    cmp r14d,dword ptr [rip+sfh_domain_rank]; jne .sfh_prd_domain
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sfh_prd_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+sfh_ty_f32]; mov ecx,3; call s_span_eq
    test eax,eax; jz .sfh_prd_type
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sfh_prd_expr
    mov rdx,[rip+sfh_reduce_expr]; mov [rdx+rbx*8],rax
    inc dword ptr [rip+sfh_reduce_count]
    call s_optional_semicolon
    xor eax,eax; jmp .sfh_prd_done
.sfh_prd_domain:
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_DOMAIN; jmp .sfh_prd_fail
.sfh_prd_type:
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_TYPE; jmp .sfh_prd_fail
.sfh_prd_expr:
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_EXPR
.sfh_prd_fail: mov eax,1
.sfh_prd_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

sfh_find_reduce:
    # rdi ptr,rsi len -> eax index / -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sfh_fr_loop:
    cmp r13d,dword ptr [rip+sfh_reduce_count]; jae .sfh_fr_no
    mov rax,[rip+sfh_reduce_name_ptr]; mov rdi,[rax+r13*8]
    mov rax,[rip+sfh_reduce_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sfh_fr_yes
    inc r13d; jmp .sfh_fr_loop
.sfh_fr_yes: mov eax,r13d; jmp .sfh_fr_done
.sfh_fr_no: mov eax,-1
.sfh_fr_done: pop r13; pop r12; pop rbx; ret

# `output total` / `output total = total` merely publishes the reduction already
# represented by the field runtime checksum. No scalar host ABI is manufactured.
sfh_parse_scalar_output:
    push rbx; push r12; push r13
    call s_parse_name; test edx,edx; jnz .sfh_pso_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call sfh_find_reduce
    cmp eax,-1; je .sfh_pso_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .sfh_pso_ok
    call s_parse_name; test edx,edx; jnz .sfh_pso_fail
    mov rdi,rax; mov rsi,rcx; mov rdx,r12; mov rcx,r13; call s_span_eq
    test eax,eax; jz .sfh_pso_fail
.sfh_pso_ok:
    call s_optional_semicolon; xor eax,eax; jmp .sfh_pso_done
.sfh_pso_fail: mov eax,1
.sfh_pso_done: pop r13; pop r12; pop rbx; ret

# edi=mode. Grammar:
#   NAME[axis in extent [periodic], ...]: f32 [= expression]
sfh_parse_field_decl:
    push rbx; push r12; push r13; push r14; push r15
    mov dword ptr [rip+sfh_saw_field_surface],1
    mov dword ptr [rip+surface_field_recognized],1
    mov r15d,edi
    mov ebx,dword ptr [rip+sfh_field_count]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .sfh_pfd_fail
    call s_parse_name; test edx,edx; jnz .sfh_pfd_fail
    mov r12,rax; mov r13,rcx
    # duplicate names are not legal in the materialized field surface
    mov rdi,r12; mov rsi,r13; call sfh_find_field
    cmp eax,-1; jne .sfh_pfd_fail
    mov rax,[rip+sfh_field_name_ptr_ptr]; mov [rax+rbx*8],r12
    mov rax,[rip+sfh_field_name_len_ptr]; mov [rax+rbx*8],r13
    mov rax,[rip+sfh_field_mode_ptr]; mov [rax+rbx],r15b
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .sfh_pfd_fail

    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pfd_fail
    xor r14d,r14d
.sfh_pfd_axis:
    cmp r14d,SFH_MAX_RANK; jae .sfh_pfd_fail
    call s_parse_name; test edx,edx; jnz .sfh_pfd_fail
    mov [rip+sfh_tmp_axis_ptr],rax
    mov [rip+sfh_tmp_axis_len],rcx
    lea rdi,[rip+sfh_kw_in]; mov esi,2; mov edx,1; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pfd_fail
    call s_parse_name; test edx,edx; jnz .sfh_pfd_domain_fail
    mov [rip+sfh_tmp_extent_ptr],rax
    mov [rip+sfh_tmp_extent_len],rcx
    mov rdi,rax; mov rsi,rcx; call sfh_find_scalar
    test eax,eax; js .sfh_pfd_domain_fail
.sfh_pfd_extent_ready:
    lea rdi,[rip+sfh_kw_periodic]; mov esi,8; mov edx,1; call s_match_token
    mov byte ptr [rip+sfh_tmp_periodic],al

    cmp dword ptr [rip+sfh_domain_rank],0; jne .sfh_pfd_compare_axis
    # First field establishes the common logical domain and axis scope.
    mov r8,[rip+sfh_tmp_axis_ptr]; mov r9,[rip+sfh_tmp_axis_len]
    mov r10,[rip+sfh_tmp_extent_ptr]; mov r11,[rip+sfh_tmp_extent_len]
    lea rax,[rip+sfh_axis_ptr]; mov [rax+r14*8],r8
    lea rax,[rip+sfh_axis_len]; mov [rax+r14*8],r9
    lea rax,[rip+sfh_extent_ptr]; mov [rax+r14*8],r10
    lea rax,[rip+sfh_extent_len]; mov [rax+r14*8],r11
    mov rdi,r8; mov rsi,r9; call s_axis_add
    jmp .sfh_pfd_store_boundary
.sfh_pfd_compare_axis:
    cmp r14d,dword ptr [rip+sfh_domain_rank]; jb 1f
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_DOMAIN; jmp .sfh_pfd_fail
1:
    lea rax,[rip+sfh_axis_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+sfh_axis_len]; mov rsi,[rax+r14*8]
    mov rdx,[rip+sfh_tmp_axis_ptr]; mov rcx,[rip+sfh_tmp_axis_len]
    call s_span_eq; test eax,eax; jnz 1f
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_DOMAIN; jmp .sfh_pfd_fail
1:  lea rax,[rip+sfh_extent_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+sfh_extent_len]; mov rsi,[rax+r14*8]
    mov rdx,[rip+sfh_tmp_extent_ptr]; mov rcx,[rip+sfh_tmp_extent_len]
    call s_span_eq; test eax,eax; jnz 1f
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_DOMAIN; jmp .sfh_pfd_fail
1:
.sfh_pfd_store_boundary:
    mov rax,[rip+sfh_field_periodic_ptr]
    mov edx,ebx; shl edx,3; add edx,r14d
    mov cl,byte ptr [rip+sfh_tmp_periodic]; mov [rax+rdx],cl
    inc r14d
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sfh_pfd_axis
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pfd_fail
    test r14d,r14d; jz .sfh_pfd_fail
    cmp dword ptr [rip+sfh_domain_rank],0; jne .sfh_pfd_rank_known
    mov [rip+sfh_domain_rank],r14d
.sfh_pfd_rank_known:
    cmp r14d,dword ptr [rip+sfh_domain_rank]; je 1f
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_DOMAIN; jmp .sfh_pfd_fail
1:  mov rax,[rip+sfh_field_rank_ptr]; mov [rax+rbx],r14b

    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sfh_pfd_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+sfh_ty_f32]; mov ecx,3; call s_span_eq
    test eax,eax; jnz 1f
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_TYPE; jmp .sfh_pfd_fail
1:  inc dword ptr [rip+sfh_field_count]

    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .sfh_pfd_done
    cmp r15d,SFH_MODE_INPUT; je .sfh_pfd_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sfh_pfd_fail
    mov rdx,[rip+sfh_field_expr_ptr]; mov [rdx+rbx*8],rax
.sfh_pfd_done:
    call s_optional_semicolon
    xor eax,eax; jmp .sfh_pfd_exit
.sfh_pfd_domain_fail:
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_DOMAIN
.sfh_pfd_fail: mov eax,1
.sfh_pfd_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Parse region NAME effect [pure] parallel { assignments }.
sfh_parse_region:
    push rbx
    call s_parse_name; test edx,edx; jnz .sfh_pr_fail
    lea rdi,[rip+sfh_kw_effect]; mov esi,6; mov edx,1; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pr_fail
    lea rdi,[rip+sfh_kw_pure]; mov esi,4; mov edx,1; call s_match_token
    lea rdi,[rip+sfh_kw_parallel]; mov esi,8; mov edx,1; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pr_fail
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pr_fail
.sfh_pr_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sfh_pr_ok
    call sfh_parse_assignment; test eax,eax; jnz .sfh_pr_fail
    jmp .sfh_pr_loop
.sfh_pr_ok: call s_optional_semicolon; xor eax,eax; jmp .sfh_pr_exit
.sfh_pr_fail: mov eax,1
.sfh_pr_exit: pop rbx; ret

# WH `for` is purely a human spelling of the already-declared data domain.
# No loop object or sequential execution survives this function.
sfh_parse_for:
    push rbx; push r12; push r13; push r14
    xor r14d,r14d
.sfh_pf_axis:
    cmp r14d,dword ptr [rip+sfh_domain_rank]; jae .sfh_pf_fail
    call s_parse_name; test edx,edx; jnz .sfh_pf_fail
    mov r12,rax; mov r13,rcx
    lea rax,[rip+sfh_axis_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+sfh_axis_len]; mov rsi,[rax+r14*8]
    mov rdx,r12; mov rcx,r13; call s_span_eq; test eax,eax; jz .sfh_pf_fail
    lea rdi,[rip+sfh_kw_in]; mov esi,2; mov edx,1; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pf_fail
    call s_parse_name; test edx,edx; jnz .sfh_pf_fail
    mov r12,rax; mov r13,rcx
.sfh_pf_extent_ready:
    lea rax,[rip+sfh_extent_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+sfh_extent_len]; mov rsi,[rax+r14*8]
    mov rdx,r12; mov rcx,r13; call s_span_eq; test eax,eax; jz .sfh_pf_fail
    inc r14d
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sfh_pf_axis
    cmp r14d,dword ptr [rip+sfh_domain_rank]; jne .sfh_pf_fail
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.sfh_pf_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sfh_pf_ok
    call sfh_parse_assignment; test eax,eax; jnz .sfh_pf_fail
    jmp .sfh_pf_loop
.sfh_pf_ok: call s_optional_semicolon; xor eax,eax; jmp .sfh_pf_exit
.sfh_pf_fail: mov eax,1
.sfh_pf_exit: pop r14; pop r13; pop r12; pop rbx; ret

# NAME[identity axes] = expression
sfh_parse_assignment:
    push rbx; push r12; push r13; push r14; push r15
    mov r15,[rip+s_cur]
    call s_parse_name; test edx,edx; jnz .sfh_pa_restore_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call sfh_find_field
    cmp eax,-1; je .sfh_pa_restore_fail
    mov ebx,eax
    mov rax,[rip+sfh_field_mode_ptr]; cmp byte ptr [rax+rbx],SFH_MODE_INPUT; je .sfh_pa_restore_fail
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pa_fail
    xor r14d,r14d
.sfh_pa_idx:
    cmp r14d,dword ptr [rip+sfh_domain_rank]; jae .sfh_pa_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sfh_pa_fail
    mov rdi,rax; mov esi,r14d; call sfh_index_delta
    test edx,edx; jnz .sfh_pa_fail
    test eax,eax; jnz .sfh_pa_fail
    inc r14d
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sfh_pa_idx
    cmp r14d,dword ptr [rip+sfh_domain_rank]; jne .sfh_pa_fail
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sfh_pa_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sfh_pa_fail
    mov rdx,[rip+sfh_field_expr_ptr]; cmp qword ptr [rdx+rbx*8],0; jne .sfh_pa_fail
    mov [rdx+rbx*8],rax
    call s_optional_semicolon
    xor eax,eax; jmp .sfh_pa_exit
.sfh_pa_restore_fail:
    mov [rip+s_cur],r15
    mov dword ptr [rip+s_error],0
.sfh_pa_fail: mov eax,1
.sfh_pa_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Surface symbol helpers
# -----------------------------------------------------------------------------
sfh_find_scalar:
    # rdi ptr,rsi len -> eax index / -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sfh_fs_loop:
    cmp r13d,dword ptr [rip+sfh_scalar_count]; jae .sfh_fs_no
    mov rax,[rip+sfh_scalar_ptr]; mov rdi,[rax+r13*8]
    mov rax,[rip+sfh_scalar_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sfh_fs_yes
    inc r13d; jmp .sfh_fs_loop
.sfh_fs_yes: mov eax,r13d; jmp .sfh_fs_done
.sfh_fs_no: mov eax,-1
.sfh_fs_done: pop r13; pop r12; pop rbx; ret

sfh_find_field:
    # rdi ptr,rsi len -> eax index / -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sfh_ff_loop:
    cmp r13d,dword ptr [rip+sfh_field_count]; jae .sfh_ff_no
    mov rax,[rip+sfh_field_name_ptr_ptr]; mov rdi,[rax+r13*8]
    mov rax,[rip+sfh_field_name_len_ptr]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sfh_ff_yes
    inc r13d; jmp .sfh_ff_loop
.sfh_ff_yes: mov eax,r13d; jmp .sfh_ff_done
.sfh_ff_no: mov eax,-1
.sfh_ff_done: pop r13; pop r12; pop rbx; ret

# rdi=node, esi=axis position -> eax signed delta, edx error, ecx explicit periodic
sfh_index_delta:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12d,esi; xor r13d,r13d
    # Explicit periodic(expr, extent) is parsed as mod(expr, extent).
    cmp dword ptr [rbx+SN_KIND],NK_BINARY; jne .sfh_id_affine
    cmp dword ptr [rbx+SN_OP],OP_MOD; jne .sfh_id_affine
    mov r14,[rbx+SN_B]
    cmp dword ptr [r14+SN_KIND],NK_VAR; jne .sfh_id_affine
    lea rax,[rip+sfh_extent_ptr]; mov rdi,[rax+r12*8]
    lea rax,[rip+sfh_extent_len]; mov rsi,[rax+r12*8]
    mov rdx,[r14+SN_PTR]; mov rcx,[r14+SN_LEN]; call s_span_eq
    test eax,eax; jz .sfh_id_affine
    mov rbx,[rbx+SN_A]; mov r13d,1
.sfh_id_affine:
    # Human-shell affine normalization: after static contraction substitution,
    # accept an axis plus/minus any AOT-static integer expression.  Only the
    # final signed delta reaches the old field canonical graph/backend.
    mov rdi,rbx; mov esi,r12d; call sfh_index_affine_delta
    test edx,edx; jnz .sfh_id_fail
    mov ecx,r13d; jmp .sfh_id_done
.sfh_id_fail: xor eax,eax; mov edx,1; xor ecx,ecx
.sfh_id_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# sfh_index_affine_delta(rdi=node, esi=domain-axis) -> eax=signed delta, edx=0 ok.
# This is surface-only normalization. It recognizes exactly one domain axis and
# folds only compile-time integer subexpressions around it; no runtime address
# algebra or new field opcode is introduced.
sfh_index_affine_delta:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12d,esi
    test rbx,rbx; jz .sfh_iad_fail
    cmp dword ptr [rbx+SN_KIND],NK_AXIS; jne .sfh_iad_binary
    mov rdi,rbx; mov esi,r12d; call sfh_node_matches_axis
    test eax,eax; jz .sfh_iad_fail
    xor eax,eax; xor edx,edx; jmp .sfh_iad_done
.sfh_iad_binary:
    cmp dword ptr [rbx+SN_KIND],NK_BINARY; jne .sfh_iad_fail
    mov r15d,dword ptr [rbx+SN_OP]
    cmp r15d,OP_ADD; je .sfh_iad_add
    cmp r15d,OP_SUB; je .sfh_iad_sub
    jmp .sfh_iad_fail
.sfh_iad_add:
    # First try affine(lhs) + static(rhs).
    mov rdi,[rbx+SN_A]; mov esi,r12d; call sfh_index_affine_delta
    test edx,edx; jnz .sfh_iad_add_rhs_affine
    movsxd r13,eax
    mov rdi,[rbx+SN_B]; call s_eval_static_u64; test edx,edx; jnz .sfh_iad_fail
    cmp rax,0x7fffffff; ja .sfh_iad_fail
    add r13,rax
    cmp r13,0x7fffffff; jg .sfh_iad_fail
    cmp r13,-2147483648; jl .sfh_iad_fail
    mov eax,r13d; xor edx,edx; jmp .sfh_iad_done
.sfh_iad_add_rhs_affine:
    # Then static(lhs) + affine(rhs).
    mov rdi,[rbx+SN_B]; mov esi,r12d; call sfh_index_affine_delta
    test edx,edx; jnz .sfh_iad_fail
    movsxd r13,eax
    mov rdi,[rbx+SN_A]; call s_eval_static_u64; test edx,edx; jnz .sfh_iad_fail
    cmp rax,0x7fffffff; ja .sfh_iad_fail
    add r13,rax
    cmp r13,0x7fffffff; jg .sfh_iad_fail
    cmp r13,-2147483648; jl .sfh_iad_fail
    mov eax,r13d; xor edx,edx; jmp .sfh_iad_done
.sfh_iad_sub:
    # Only affine(lhs) - static(rhs) preserves the domain-axis coefficient +1.
    mov rdi,[rbx+SN_A]; mov esi,r12d; call sfh_index_affine_delta
    test edx,edx; jnz .sfh_iad_fail
    movsxd r13,eax
    mov rdi,[rbx+SN_B]; call s_eval_static_u64; test edx,edx; jnz .sfh_iad_fail
    cmp rax,0x7fffffff; ja .sfh_iad_fail
    sub r13,rax
    cmp r13,0x7fffffff; jg .sfh_iad_fail
    cmp r13,-2147483648; jl .sfh_iad_fail
    mov eax,r13d; xor edx,edx; jmp .sfh_iad_done
.sfh_iad_fail:
    xor eax,eax; mov edx,1
.sfh_iad_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

sfh_node_matches_axis:
    # rdi=node, esi=axis -> eax bool
    cmp dword ptr [rdi+SN_KIND],NK_AXIS; jne .sfh_nma_no
    mov r8,rdi
    lea rax,[rip+sfh_axis_ptr]; mov rdi,[rax+rsi*8]
    lea rax,[rip+sfh_axis_len]; mov rsi,[rax+rsi*8]
    mov rdx,[r8+SN_PTR]; mov rcx,[r8+SN_LEN]; jmp s_span_eq
.sfh_nma_no: xor eax,eax; ret

# -----------------------------------------------------------------------------
# Access discovery and AST -> canonical op lowering
# -----------------------------------------------------------------------------
sfh_compile_outputs:
    push rbx; push r12
    xor ebx,ebx
.sfh_co_loop:
    cmp ebx,dword ptr [rip+sfh_field_count]; jae .sfh_co_done
    mov rax,[rip+sfh_field_mode_ptr]; movzx eax,byte ptr [rax+rbx]
    cmp eax,SFH_MODE_INPUT; je .sfh_co_next
    mov rax,[rip+sfh_field_expr_ptr]; mov r12,[rax+rbx*8]
    test r12,r12; jz .sfh_co_next
    mov rdi,r12; call sfh_compute_need
    test edx,edx; jnz .sfh_co_fail
    cmp eax,4; ja .sfh_co_fail
    mov rdi,r12; xor esi,esi; mov edx,1; mov ecx,2; mov r8d,3; call sfh_compile_node
    test eax,eax; jnz .sfh_co_fail
    mov edi,ebx; xor esi,esi; call sfh_emit_store
    test eax,eax; jnz .sfh_co_fail
    xor edi,edi; call sfh_emit_reduce
    test eax,eax; jnz .sfh_co_fail
    inc dword ptr [rip+sfh_output_count]
.sfh_co_next: inc ebx; jmp .sfh_co_loop
.sfh_co_done: xor eax,eax; jmp .sfh_co_exit
.sfh_co_fail:
    cmp dword ptr [rip+surface_field_error_code],0; jne 1f
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_EXPR
1:  mov eax,1
.sfh_co_exit: pop r12; pop rbx; ret


sfh_compile_reductions:
    push rbx; push r12
    xor ebx,ebx
.sfh_cr_loop:
    cmp ebx,dword ptr [rip+sfh_reduce_count]; jae .sfh_cr_ok
    mov rax,[rip+sfh_reduce_expr]; mov r12,[rax+rbx*8]
    test r12,r12; jz .sfh_cr_fail
    mov rdi,r12; call sfh_compute_need; test edx,edx; jnz .sfh_cr_fail
    cmp eax,4; ja .sfh_cr_fail
    mov rdi,r12; xor esi,esi; mov edx,1; mov ecx,2; mov r8d,3; call sfh_compile_node
    test eax,eax; jnz .sfh_cr_fail
    xor edi,edi; call sfh_emit_reduce; test eax,eax; jnz .sfh_cr_fail
    inc dword ptr [rip+sfh_output_count]
    inc ebx; jmp .sfh_cr_loop
.sfh_cr_ok: xor eax,eax; jmp .sfh_cr_done
.sfh_cr_fail:
    cmp dword ptr [rip+surface_field_error_code],0; jne 1f
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_EXPR
1:  mov eax,1
.sfh_cr_done: pop r12; pop rbx; ret

# need(node) -> eax registers, edx error. Pure f32 arithmetic and native unary
# math facts such as sqrt enter the same sovereign field lane; other WH constructs remain in
# the ordinary tensor/general lanes rather than being silently reinterpreted.
sfh_compute_need:
    push rbx; push r12; push r13
    mov rbx,rdi
    test rbx,rbx; jz .sfh_cn_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .sfh_cn_leaf
    cmp eax,NK_IMM_F64_BITS; je .sfh_cn_leaf
    cmp eax,NK_LOAD; je .sfh_cn_leaf
    cmp eax,NK_UNARY; je .sfh_cn_unary
    cmp eax,NK_BINARY; jne .sfh_cn_fail
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_ADD; je .sfh_cn_bin
    cmp eax,OP_SUB; je .sfh_cn_bin
    cmp eax,OP_MUL; je .sfh_cn_bin
    cmp eax,OP_DIV; jne .sfh_cn_fail
.sfh_cn_unary:
    cmp dword ptr [rbx+SN_OP],OP_SQRT; je .sfh_cn_unary_ok
    cmp dword ptr [rbx+SN_OP],OP_SQUARE; je .sfh_cn_unary_ok
    cmp dword ptr [rbx+SN_OP],OP_TRUNC; jne .sfh_cn_fail
.sfh_cn_unary_ok:
    mov rdi,[rbx+SN_A]; call sfh_compute_need; test edx,edx; jnz .sfh_cn_fail
    xor edx,edx; jmp .sfh_cn_done
.sfh_cn_bin:
    mov rdi,[rbx+SN_A]; call sfh_compute_need; test edx,edx; jnz .sfh_cn_fail
    mov r12d,eax
    mov rdi,[rbx+SN_B]; call sfh_compute_need; test edx,edx; jnz .sfh_cn_fail
    mov r13d,eax
    mov eax,r12d; cmp r12d,r13d; jne .sfh_cn_max
    inc eax; jmp .sfh_cn_ok
.sfh_cn_max: cmp eax,r13d; cmovb eax,r13d
.sfh_cn_ok: xor edx,edx; jmp .sfh_cn_done
.sfh_cn_leaf: mov eax,1; xor edx,edx; jmp .sfh_cn_done
.sfh_cn_fail: xor eax,eax; mov edx,1
.sfh_cn_done: pop r13; pop r12; pop rbx; ret

# compile(node,target,free1,free2,free3) -> eax 0 success
# 1.3.11 adds one sovereign logical Field carrier for complex human expressions.
# It is still direct AOT lowering into the canonical op graph; no runtime stack
# interpreter or expression scheduler is introduced.
sfh_compile_node:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov rbx,rdi; mov r12d,esi; mov r13d,edx; mov r14d,ecx
    mov dword ptr [rsp+8],r8d
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .sfh_cc_num
    cmp eax,NK_IMM_F64_BITS; je .sfh_cc_num
    cmp eax,NK_LOAD; je .sfh_cc_load
    cmp eax,NK_UNARY; je .sfh_cc_unary
    cmp eax,NK_BINARY; jne .sfh_cc_fail
    mov r15d,dword ptr [rbx+SN_OP]
    mov rdi,[rbx+SN_A]; call sfh_compute_need; test edx,edx; jnz .sfh_cc_fail
    mov dword ptr [rsp],eax
    mov rdi,[rbx+SN_B]; call sfh_compute_need; test edx,edx; jnz .sfh_cc_fail
    mov dword ptr [rsp+4],eax
    xor r10d,r10d
    cmp r13d,0; jl 1f; inc r10d
1:  cmp r14d,0; jl 2f; inc r10d
2:  cmp dword ptr [rsp+8],0; jl 3f; inc r10d
3:  cmp dword ptr [rsp+4],r10d; ja .sfh_cc_right_first
    mov rdi,[rbx+SN_A]; mov esi,r12d; mov edx,r13d; mov ecx,r14d; mov r8d,[rsp+8]; call sfh_compile_node
    test eax,eax; jnz .sfh_cc_fail
    cmp r13d,0; jl .sfh_cc_fail
    mov rdi,[rbx+SN_B]; mov esi,r13d; mov edx,r14d; mov ecx,[rsp+8]; mov r8d,-1; call sfh_compile_node
    test eax,eax; jnz .sfh_cc_fail
    mov edi,r15d; mov esi,r12d; mov edx,r13d; mov ecx,r12d; call sfh_emit_binary
    jmp .sfh_cc_exit
.sfh_cc_right_first:
    mov rdi,[rbx+SN_B]; mov esi,r12d; mov edx,r13d; mov ecx,r14d; mov r8d,[rsp+8]; call sfh_compile_node
    test eax,eax; jnz .sfh_cc_fail
    cmp r13d,0; jl .sfh_cc_fail
    mov rdi,[rbx+SN_A]; mov esi,r13d; mov edx,r14d; mov ecx,[rsp+8]; mov r8d,-1; call sfh_compile_node
    test eax,eax; jnz .sfh_cc_fail
    mov edi,r15d; mov esi,r13d; mov edx,r12d; mov ecx,r12d; call sfh_emit_binary
    jmp .sfh_cc_exit
.sfh_cc_unary:
    mov r15d,dword ptr [rbx+SN_OP]
    cmp r15d,OP_SQRT; je .sfh_cc_unary_ok
    cmp r15d,OP_SQUARE; je .sfh_cc_unary_ok
    cmp r15d,OP_TRUNC; jne .sfh_cc_fail
.sfh_cc_unary_ok:
    mov rdi,[rbx+SN_A]; mov esi,r12d; mov edx,r13d; mov ecx,r14d; mov r8d,[rsp+8]; call sfh_compile_node
    test eax,eax; jnz .sfh_cc_fail
    cmp r15d,OP_SQUARE; je .sfh_cc_square_emit
    mov edi,r15d; mov esi,r12d; mov edx,r12d; call sfh_emit_unary
    jmp .sfh_cc_exit
.sfh_cc_square_emit:
    # Square is one surface ValueFact but reuses the old field MUL authority.
    # The child is compiled once and consumed twice from the same carrier.
    mov edi,OP_MUL; mov esi,r12d; mov edx,r12d; mov ecx,r12d; call sfh_emit_binary
    jmp .sfh_cc_exit
.sfh_cc_num:
    mov rdi,rbx; mov esi,r12d; call sfh_emit_const_ast; jmp .sfh_cc_exit
.sfh_cc_load:
    mov rdi,rbx; call sfh_access_for_load
    test edx,edx; jnz .sfh_cc_fail
    mov edi,eax; mov esi,r12d; call sfh_emit_load; jmp .sfh_cc_exit
.sfh_cc_fail: mov eax,1
.sfh_cc_exit: add rsp,32; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=NK_LOAD -> eax access, edx error
sfh_access_for_load:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call sfh_find_field
    cmp eax,-1; je .sfh_afl_fail
    mov r12d,eax
    mov rax,[rip+sfh_field_rank_ptr]; movzx r13d,byte ptr [rax+r12]
    mov r14,[rbx+SN_A]; xor r15d,r15d
    lea rdi,[rip+sfh_delta_temp]; xor eax,eax; mov ecx,SFH_MAX_RANK; rep stosd
.sfh_afl_idx:
    cmp r15d,r13d; jae .sfh_afl_idx_done
    test r14,r14; jz .sfh_afl_fail
    mov rdi,r14; mov esi,r15d; call sfh_index_delta
    test edx,edx; jnz .sfh_afl_fail
    mov r11d,ecx                         # explicit periodic
    mov r10d,eax
    test r10d,r10d; jz .sfh_afl_boundary_ok
    test r11d,r11d; jnz .sfh_afl_boundary_ok
    mov rax,[rip+sfh_field_periodic_ptr]
    mov edx,r12d; shl edx,3; add edx,r15d
    cmp byte ptr [rax+rdx],0; jne .sfh_afl_boundary_ok
    mov dword ptr [rip+surface_field_error_code],SFH_ERR_BOUNDARY
    jmp .sfh_afl_fail
.sfh_afl_boundary_ok:
    lea rax,[rip+sfh_delta_temp]; mov [rax+r15*4],r10d
    mov r14,[r14+SN_NEXT]; inc r15d; jmp .sfh_afl_idx
.sfh_afl_idx_done:
    test r14,r14; jnz .sfh_afl_fail
    # Reuse an existing canonical access when field and all Rank-N deltas agree.
    xor r15d,r15d
.sfh_afl_find:
    cmp r15d,dword ptr [rip+sfh_access_count]; jae .sfh_afl_add
    mov rax,[rip+sfh_access_field_ptr]; movzx eax,byte ptr [rax+r15]
    cmp eax,r12d; jne .sfh_afl_find_next
    xor ecx,ecx
.sfh_afl_cmp_axis:
    cmp ecx,r13d; jae .sfh_afl_found
    mov rax,[rip+sfh_access_delta_ptr]
    mov edx,r15d; shl edx,5; lea rdx,[rdx+rcx*4]
    mov eax,[rax+rdx]
    lea rdx,[rip+sfh_delta_temp]; cmp eax,[rdx+rcx*4]; jne .sfh_afl_find_next
    inc ecx; jmp .sfh_afl_cmp_axis
.sfh_afl_find_next: inc r15d; jmp .sfh_afl_find
.sfh_afl_found: mov eax,r15d; xor edx,edx; jmp .sfh_afl_done
.sfh_afl_add:
    mov eax,dword ptr [rip+sfh_access_count]; cmp eax,dword ptr [rip+s_fact_cap]; jae .sfh_afl_fail
    mov r15d,eax
    mov rdx,[rip+sfh_access_field_ptr]; mov [rdx+r15],r12b
    xor ecx,ecx
.sfh_afl_copy:
    cmp ecx,r13d; jae .sfh_afl_added
    lea rax,[rip+sfh_delta_temp]; mov r10d,[rax+rcx*4]
    mov rax,[rip+sfh_access_delta_ptr]
    mov edx,r15d; shl edx,5; lea rdx,[rdx+rcx*4]
    mov [rax+rdx],r10d
    inc ecx; jmp .sfh_afl_copy
.sfh_afl_added:
    inc dword ptr [rip+sfh_access_count]
    mov eax,r15d; xor edx,edx; jmp .sfh_afl_done
.sfh_afl_fail: xor eax,eax; mov edx,1
.sfh_afl_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Canonical op text emission
# -----------------------------------------------------------------------------
sfh_op_prefix:
    cmp dword ptr [rip+sfh_op_count],0; je .sfh_opp_first
    mov dil,','; call s_out_byte
.sfh_opp_first: ret

sfh_emit_load:
    # edi=access, esi=dst
    push rbx; push r12
    mov ebx,edi; mov r12d,esi; call sfh_op_prefix
    lea rdi,[rip+sfh_j_load]; call s_out_cstr
    mov edi,ebx; call s_emit_u64_decimal
    lea rdi,[rip+sfh_j_dst]; call s_out_cstr
    mov edi,r12d; call s_emit_u64_decimal
    mov dil,'}'; call s_out_byte
    inc dword ptr [rip+sfh_op_count]
    xor eax,eax; pop r12; pop rbx; ret

sfh_emit_const_ast:
    # rdi=numeric/immediate-f64-bits AST, esi=dst
    push rbx; push r12
    mov rbx,rdi; mov r12d,esi; call sfh_op_prefix
    lea rdi,[rip+sfh_j_const]; call s_out_cstr
    cmp dword ptr [rbx+SN_KIND],NK_IMM_F64_BITS; je .sfh_eca_bits
    cmp qword ptr [rbx+SN_AUX],0; je .sfh_eca_unsigned
    mov dil,'-'; call s_out_byte
.sfh_eca_unsigned:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_span
    jmp .sfh_eca_value_done
.sfh_eca_bits:
    mov dil,'"'; call s_out_byte
    lea rdi,[rip+lit_f64bits_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_AUX]; call s_emit_u64_decimal
    mov dil,'"'; call s_out_byte
.sfh_eca_value_done:
    lea rdi,[rip+sfh_j_dst]; call s_out_cstr
    mov edi,r12d; call s_emit_u64_decimal
    mov dil,'}'; call s_out_byte
    inc dword ptr [rip+sfh_op_count]
    xor eax,eax; pop r12; pop rbx; ret

sfh_emit_unary:
    # edi=surface OP_*, esi=a, edx=dst. Math stays in the existing canonical op stream.
    push rbx; push r12; push r13
    mov ebx,edi; mov r12d,esi; mov r13d,edx
    call sfh_op_prefix
    cmp ebx,OP_SQRT; je .sfh_eu_sqrt
    cmp ebx,OP_TRUNC; je .sfh_eu_trunc
    jmp .sfh_eu_fail
.sfh_eu_sqrt: lea rdi,[rip+sfh_j_sqrt]; jmp .sfh_eu_name
.sfh_eu_trunc: lea rdi,[rip+sfh_j_trunc]
.sfh_eu_name: call s_out_cstr
    mov edi,r12d; call s_emit_u64_decimal
    lea rdi,[rip+sfh_j_dst]; call s_out_cstr
    mov edi,r13d; call s_emit_u64_decimal
    mov dil,'}'; call s_out_byte
    inc dword ptr [rip+sfh_op_count]
    xor eax,eax; jmp .sfh_eu_done
.sfh_eu_fail: mov eax,1
.sfh_eu_done: pop r13; pop r12; pop rbx; ret

sfh_emit_binary:
    # edi=surface OP_*, esi=a, edx=b, ecx=dst
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12d,esi; mov r13d,edx; mov r14d,ecx
    call sfh_op_prefix
    cmp ebx,OP_ADD; je .sfh_eb_add
    cmp ebx,OP_SUB; je .sfh_eb_sub
    cmp ebx,OP_MUL; je .sfh_eb_mul
    cmp ebx,OP_DIV; je .sfh_eb_div
    mov eax,1; jmp .sfh_eb_exit
.sfh_eb_add: lea rdi,[rip+sfh_j_add]; jmp .sfh_eb_name
.sfh_eb_sub: lea rdi,[rip+sfh_j_sub]; jmp .sfh_eb_name
.sfh_eb_mul: lea rdi,[rip+sfh_j_mul]; jmp .sfh_eb_name
.sfh_eb_div: lea rdi,[rip+sfh_j_div]
.sfh_eb_name:
    call s_out_cstr
    mov edi,r12d; call s_emit_u64_decimal
    lea rdi,[rip+sfh_j_b]; call s_out_cstr
    mov edi,r13d; call s_emit_u64_decimal
    lea rdi,[rip+sfh_j_dst]; call s_out_cstr
    mov edi,r14d; call s_emit_u64_decimal
    mov dil,'}'; call s_out_byte
    inc dword ptr [rip+sfh_op_count]
    xor eax,eax
.sfh_eb_exit: pop r14; pop r13; pop r12; pop rbx; ret

sfh_emit_store:
    # edi=field, esi=src
    push rbx; push r12
    mov ebx,edi; mov r12d,esi; call sfh_op_prefix
    lea rdi,[rip+sfh_j_store]; call s_out_cstr
    mov edi,ebx; call s_emit_u64_decimal
    lea rdi,[rip+sfh_j_src]; call s_out_cstr
    mov edi,r12d; call s_emit_u64_decimal
    mov dil,'}'; call s_out_byte
    inc dword ptr [rip+sfh_op_count]
    xor eax,eax; pop r12; pop rbx; ret

sfh_emit_reduce:
    # edi=src
    push rbx
    mov ebx,edi; call sfh_op_prefix
    lea rdi,[rip+sfh_j_reduce]; call s_out_cstr
    mov edi,ebx; call s_emit_u64_decimal
    mov dil,'}'; call s_out_byte
    inc dword ptr [rip+sfh_op_count]
    xor eax,eax; pop rbx; ret

# -----------------------------------------------------------------------------
# Final wheelchair.field/1 JSON
# -----------------------------------------------------------------------------
sfh_emit_final_json:
    push rbx; push r12; push r13; push r14
    lea rax,[rip+surface_json_buffer]; mov [rip+s_active_base_var],rax
    mov qword ptr [rip+s_active_end_var],0
    lea rax,[rip+surface_json_cap]; mov [rip+s_active_cap_var],rax
    mov rax,[rip+surface_json_buffer]; mov [rip+s_out_ptr],rax
    add rax,[rip+surface_json_cap]; mov [rip+s_out_limit],rax
    lea rdi,[rip+sfh_j_root_strict];
    cmp dword ptr [rip+sfh_fp_tolerant],0; je .sfh_efj_root
    lea rdi,[rip+sfh_j_root_tolerant]
.sfh_efj_root: call s_out_cstr
    xor ebx,ebx
.sfh_efj_fields:
    cmp ebx,dword ptr [rip+sfh_field_count]; jae .sfh_efj_fields_done
    test ebx,ebx; jz .sfh_efj_field_nocomma
    mov dil,','; call s_out_byte
.sfh_efj_field_nocomma:
    lea rdi,[rip+sfh_j_field_mode]; call s_out_cstr
    mov rax,[rip+sfh_field_mode_ptr]; movzx eax,byte ptr [rax+rbx]
    cmp eax,SFH_MODE_INPUT; je .sfh_efj_mode_in
    cmp eax,SFH_MODE_OUTPUT; je .sfh_efj_mode_out
    lea rdi,[rip+sfh_s_inout]; mov esi,5; jmp .sfh_efj_mode_emit
.sfh_efj_mode_in: lea rdi,[rip+sfh_s_input]; mov esi,5; jmp .sfh_efj_mode_emit
.sfh_efj_mode_out: lea rdi,[rip+sfh_s_output]; mov esi,6
.sfh_efj_mode_emit:
    call s_out_quote_span
    lea rdi,[rip+sfh_j_field_type]; call s_out_cstr
    lea rdi,[rip+sfh_s_f32]; mov esi,3; call s_out_quote_span
    lea rdi,[rip+sfh_j_field_rank]; call s_out_cstr
    mov rax,[rip+sfh_field_rank_ptr]; movzx edi,byte ptr [rax+rbx]; call s_emit_u64_decimal
    mov dil,'}'; call s_out_byte
    inc ebx; jmp .sfh_efj_fields
.sfh_efj_fields_done:
    lea rdi,[rip+sfh_j_accesses]; call s_out_cstr
    xor ebx,ebx
.sfh_efj_access:
    cmp ebx,dword ptr [rip+sfh_access_count]; jae .sfh_efj_access_done
    test ebx,ebx; jz .sfh_efj_access_nocomma
    mov dil,','; call s_out_byte
.sfh_efj_access_nocomma:
    lea rdi,[rip+sfh_j_access_field]; call s_out_cstr
    mov rax,[rip+sfh_access_field_ptr]; movzx edi,byte ptr [rax+rbx]; call s_emit_u64_decimal
    lea rdi,[rip+sfh_j_delta]; call s_out_cstr
    xor r12d,r12d
.sfh_efj_delta_axis:
    cmp r12d,dword ptr [rip+sfh_domain_rank]; jae .sfh_efj_delta_done
    test r12d,r12d; jz .sfh_efj_delta_nocomma
    mov dil,','; call s_out_byte
.sfh_efj_delta_nocomma:
    mov rax,[rip+sfh_access_delta_ptr]
    mov edx,ebx; shl edx,5; lea rdx,[rdx+r12*4]
    mov edi,[rax+rdx]; call sfh_emit_i32
    inc r12d; jmp .sfh_efj_delta_axis
.sfh_efj_delta_done:
    lea rdi,[rip+sfh_j_access_close]; call s_out_cstr
    inc ebx; jmp .sfh_efj_access
.sfh_efj_access_done:
    lea rdi,[rip+sfh_j_ops]; call s_out_cstr
    mov rdi,[rip+sfh_ops_buf]; mov rsi,[rip+sfh_ops_end]; sub rsi,rdi; call s_out_span
    lea rdi,[rip+sfh_j_root_close]; call s_out_cstr
    mov rax,[rip+s_out_ptr]; mov rcx,[rip+surface_json_buffer]; sub rax,rcx
    mov [rip+surface_json_length],rax
    xor eax,eax
    pop r14; pop r13; pop r12; pop rbx; ret

sfh_emit_i32:
    # edi signed
    push rbx
    mov ebx,edi; test ebx,ebx; jns .sfh_ei_pos
    mov dil,'-'; call s_out_byte
    mov eax,ebx; neg eax; mov edi,eax; call s_emit_u64_decimal; pop rbx; ret
.sfh_ei_pos: mov edi,ebx; call s_emit_u64_decimal; pop rbx; ret

# Save the current end of the operation stream after every output append.  The
# general output primitive already advanced s_out_ptr, so this helper is folded
# into op-count mutation by aliasing sfh_ops_end at finalization time.
# We materialize it through a tiny interposed definition below by keeping the
# canonical end synchronized in the callers' common epilogue via this symbol.

# Override point used by finalizer: if no separate write happened, s_out_ptr is
# exactly the end of sfh_ops_buf after compilation.
sfh_capture_ops_end:
    mov rax,[rip+s_out_ptr]; mov [rip+sfh_ops_end],rax; ret

.section .rodata
sfh_kw_program:.ascii "program"
sfh_kw_strict:.ascii "strict"
sfh_kw_tolerance:.ascii "tolerance"
sfh_kw_let:.ascii "let"
sfh_kw_matrix:.ascii "matrix"
sfh_kw_input:.ascii "input"
sfh_kw_output:.ascii "output"
sfh_kw_inout:.ascii "inout"
sfh_kw_pure:.ascii "pure"
sfh_kw_field:.ascii "field"
sfh_kw_range:.ascii "range"
sfh_kw_in:.ascii "in"
sfh_kw_periodic:.ascii "periodic"
sfh_kw_region:.ascii "region"
sfh_kw_effect:.ascii "effect"
sfh_kw_parallel:.ascii "parallel"
sfh_kw_for:.ascii "for"
sfh_kw_sum:.ascii "sum"
sfh_ty_u64:.ascii "u64"
sfh_ty_f32:.ascii "f32"
sfh_s_input:.ascii "input"
sfh_s_output:.ascii "output"
sfh_s_inout:.ascii "inout"
sfh_s_f32:.ascii "f32"

sfh_j_load:.asciz "{\"op\":\"load\",\"access\":"
sfh_j_const:.asciz "{\"op\":\"const\",\"value\":"
sfh_j_add:.asciz "{\"op\":\"add\",\"a\":"
sfh_j_sub:.asciz "{\"op\":\"sub\",\"a\":"
sfh_j_mul:.asciz "{\"op\":\"mul\",\"a\":"
sfh_j_div:.asciz "{\"op\":\"div\",\"a\":"
sfh_j_sqrt:.asciz "{\"op\":\"sqrt\",\"a\":"
sfh_j_trunc:.asciz "{\"op\":\"trunc\",\"a\":"
sfh_j_b:.asciz ",\"b\":"
sfh_j_dst:.asciz ",\"dst\":"
sfh_j_store:.asciz "{\"op\":\"store\",\"field\":"
sfh_j_src:.asciz ",\"src\":"
sfh_j_reduce:.asciz "{\"op\":\"reduce\",\"src\":"

sfh_j_root_strict:.asciz "{\"format\":\"wheelchair.field/1\",\"contracts\":{\"floating_point\":\"strict\"},\"fields\":["
sfh_j_root_tolerant:.asciz "{\"format\":\"wheelchair.field/1\",\"contracts\":{\"floating_point\":\"tolerant\"},\"fields\":["
sfh_j_field_mode:.asciz "{\"mode\":"
sfh_j_field_type:.asciz ",\"type\":"
sfh_j_field_rank:.asciz ",\"rank\":"
sfh_j_accesses:.asciz "],\"accesses\":["
sfh_j_access_field:.asciz "{\"field\":"
sfh_j_delta:.asciz ",\"delta\":["
sfh_j_access_close:.asciz "]}"
sfh_j_ops:.asciz "],\"ops\":["
sfh_j_root_close:.asciz "]}"

.section .bss
.p2align 6
surface_field_error_code:.skip 4
surface_field_recognized:.skip 4
sfh_orig_source_ptr:.skip 8
sfh_orig_source_len:.skip 8
sfh_field_count:.skip 4
sfh_scalar_count:.skip 4
sfh_domain_rank:.skip 4
sfh_output_count:.skip 4
sfh_reduce_count:.skip 4
sfh_access_count:.skip 4
sfh_op_count:.skip 4
sfh_fp_tolerant:.skip 4
sfh_saw_field_surface:.skip 4
sfh_tmp_periodic:.skip 1
.p2align 3
sfh_tmp_axis_ptr:.skip 8
sfh_tmp_axis_len:.skip 8
sfh_tmp_extent_ptr:.skip 8
sfh_tmp_extent_len:.skip 8
sfh_ops_end:.skip 8
sfh_reduce_name_ptr:.skip 8
sfh_reduce_name_len:.skip 8
sfh_reduce_expr:.skip 8
sfh_scalar_ptr:.skip 8
sfh_scalar_len:.skip 8
sfh_meta_arena:.skip 8
sfh_field_name_ptr_ptr:.skip 8
sfh_field_name_len_ptr:.skip 8
sfh_field_mode_ptr:.skip 8
sfh_field_rank_ptr:.skip 8
sfh_field_expr_ptr:.skip 8
sfh_field_periodic_ptr:.skip 8
sfh_access_field_ptr:.skip 8
sfh_access_delta_ptr:.skip 8
sfh_axis_ptr:.skip SFH_MAX_RANK*8
sfh_axis_len:.skip SFH_MAX_RANK*8
sfh_extent_ptr:.skip SFH_MAX_RANK*8
sfh_extent_len:.skip SFH_MAX_RANK*8
.p2align 4
sfh_delta_temp:.skip SFH_MAX_RANK*4
.p2align 6
sfh_ops_buf:.skip 8
sfh_ops_cap:.skip 8
