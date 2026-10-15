# WH and WHEX share ShapeFact-N coordinates/strides. General keeps logical
# input cardinalities; Tensor's product-input consumer keeps its existing basis.
# No source-workload identity or user parallel annotation participates.
.text
s_wh_record_shape_axis:
    push rbx; push r12; push r13
    mov r12,rdi; mov ebx,esi
    mov rax,[rip+s_axis_ptrs]; mov rcx,[rax+rbx*8]
    mov rax,[rip+s_shape_axis_ptrs]; mov [rax+rbx*8],rcx
    mov rax,[rip+s_axis_lens]; mov rcx,[rax+rbx*8]
    mov rax,[rip+s_shape_axis_lens]; mov [rax+rbx*8],rcx
    lea eax,[rbx+1]; mov [rip+s_shape_rank],eax
    cmp dword ptr [r12+SN_KIND],NK_VAR; jne .swrs_static
    mov rax,[rip+s_shape_extent_kind]; mov dword ptr [rax+rbx*4],1
    mov rcx,[r12+SN_PTR]; mov rax,[rip+s_shape_extent_ptrs]; mov [rax+rbx*8],rcx
    mov rcx,[r12+SN_LEN]; mov rax,[rip+s_shape_extent_lens]; mov [rax+rbx*8],rcx
    mov rax,[rip+s_shape_extent_static]; mov qword ptr [rax+rbx*8],0
    jmp .swrs_done
.swrs_static:
    mov rdi,r12; call s_eval_static_u64
    test edx,edx; jnz .swrs_unrepresented
    test rax,rax; jz .swrs_unrepresented
    mov r13,rax
    mov rax,[rip+s_shape_extent_kind]; mov dword ptr [rax+rbx*4],0
    mov rax,[rip+s_shape_extent_static]; mov [rax+rbx*8],r13
    mov rax,[rip+s_shape_extent_ptrs]; mov qword ptr [rax+rbx*8],0
    mov rax,[rip+s_shape_extent_lens]; mov qword ptr [rax+rbx*8],0
    jmp .swrs_done
.swrs_unrepresented:
    mov dword ptr [rip+s_wh_shape_record_valid],0
.swrs_done:
    mov rax,r12; pop r13; pop r12; pop rbx; ret

s_wh_shape_prepare:
    push rbx; push r12
    cmp dword ptr [rip+s_wh_shape_record_valid],1; jne .swsp_ok
    mov rax,[rip+s_shape_extent_kind]; cmp dword ptr [rax],1; jne .swsp_ok
    mov ebx,1
1:  cmp ebx,[rip+s_shape_rank]; jae .swsp_prepare
    cmp dword ptr [rax+rbx*4],0; jne .swsp_ok
    inc ebx; jmp 1b
.swsp_prepare:
    call s_tensor_shapefact_prepare
    cmp eax,-1; je .swsp_fail
    cmp dword ptr [rip+s_shape_rank],1; je .swsp_extent_proven
    cmp dword ptr [rip+s_overflow_wrap],0; je .swsp_extent_proven
    # InputFact is now enforced before native execution. Only an admitted
    # upper bound whose product fits u64 can prove a wrapping extent safe.
    cmp qword ptr [rip+s_shape_static_product],1; je .swsp_extent_proven
    mov rdi,[rip+s_shape_runtime_extent_ptr]; mov rsi,[rip+s_shape_runtime_extent_len]
    call s_decl_lookup_exact
    cmp eax,-1; je .swsp_fail
    mov rcx,[rip+s_decl_range_max]; mov rax,[rcx+rax*8]
    cmp rax,-1; je .swsp_fail
    mul qword ptr [rip+s_shape_static_product]
    test rdx,rdx; jnz .swsp_fail
.swsp_extent_proven:
    call s_store_decl_shape_meta; test eax,eax; jnz .swsp_fail
    mov dword ptr [rip+s_wh_shape_basis],1
    cmp dword ptr [rip+s_shape_rank],1; je .swsp_ok
    # General consumes an ordinary product extent and one ordinary physical
    # coordinate. Existing ShapeFact-N rewrites every source coordinate/load.
    mov rax,[rip+s_wh_axis_output_start]; mov [rip+s_out_ptr],rax
    mov dil,'['; call s_out_byte
    lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    lea rdi,[rip+shape_q_name]; mov esi,SHAPEFN_Q_NAME_LEN; call s_out_quote_span
    lea rdi,[rip+js_extent_mid]; call s_out_cstr
    call s_ast_shape_product_new; test rax,rax; jz .swsp_fail
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .swsp_fail
    mov dil,'}'; call s_out_byte; mov dil,']'; call s_out_byte
.swsp_ok: xor eax,eax; jmp .swsp_done
.swsp_fail: mov eax,1
.swsp_done: pop r12; pop rbx; ret

# Same product relation, parameterized by the consumer's input-cardinality basis.
s_wh_shape_product_new:
    push rbx; push r12
    call s_new_ast; test rax,rax; jz .swpn_done
    mov dword ptr [rax+SN_KIND],NK_VAR
    mov rcx,[rip+s_shape_runtime_extent_ptr]; mov [rax+SN_PTR],rcx
    mov rcx,[rip+s_shape_runtime_extent_len]; mov [rax+SN_LEN],rcx
    mov r12,rax; mov rbx,[rip+s_shape_static_product]
    cmp rbx,1; je .swpn_done
    mov rdi,rbx; call s_ast_u64_imm
    mov rdx,rax; mov rsi,r12; mov edi,OP_MUL; call s_ast_binary_new
.swpn_done: pop r12; pop rbx; ret

s_emit_wh_shape_ast:
    cmp dword ptr [rip+s_wh_shape_basis],0; je s_emit_ast
    call s_shapefact_rewrite; test rax,rax; jz .sewsa_fail
    mov rdi,rax; jmp s_emit_ast
.sewsa_fail: mov eax,1; ret

.pushsection .bss
.p2align 3
s_wh_axis_output_start:.skip 8
s_wh_shape_record_valid:.skip 4
s_wh_shape_basis:.skip 4
.popsection
