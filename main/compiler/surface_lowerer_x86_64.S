.intel_syntax noprefix
.include "compiler/shapefact_n.inc"

.global surface_diag_active
.global surface_diag_repaired
.global surface_diag_repair_line
.global surface_diag_cheesed
.global surface_diag_cheese_line
.global surface_diag_error_line
.global surface_note_convergence_name

# Native WH/WHEX human-surface lowerer.
# Compile-time only: text -> canonical wheelchair.tensor/1 bytes in memory.
# It owns no runtime scheduling policy and never assigns a resource recipient.

.equ SAST_SIZE,64
# 1.3.54 structural-aging allocation policy.  These numbers are growth quanta,
# never source-language cardinality ceilings.
.equ SYS_mmap,9
.equ SYS_mremap,25
.equ PROT_READ_WRITE,3
.equ MAP_PRIVATE_ANON,0x22
.equ MREMAP_MAYMOVE,1
.equ SURFACE_STREAM_INITIAL_BYTES,65536
.equ SURFACE_AST_INITIAL_BYTES,1048576
.equ SURFACE_FACT_RECORD_BYTES,432
.equ SN_KIND,0
.equ SN_OP,4
.equ SN_PTR,8
.equ SN_LEN,16
.equ SN_A,24
.equ SN_B,32
.equ SN_C,40
.equ SN_NEXT,48
.equ SN_AUX,56

.equ NK_NUM,1
.equ NK_STRING,2
.equ NK_BOOL,3
.equ NK_VAR,4
.equ NK_AXIS,5
.equ NK_STATE,6
.equ NK_UNARY,7
.equ NK_BINARY,8
.equ NK_CAST,9
.equ NK_LOAD,10
.equ NK_IMM_U64,11
.equ NK_GOAL_RESULT,12
.equ NK_IMM_F64_BITS,13
.equ NK_STRUCT,14
.equ NK_STRUCT_ELEM,15
.equ NK_STATIC_MGET,16   # surface-only; must erase before canonical emission
.equ NK_RECUR_CALL,17    # surface-only self-recursive semantic relation call
.equ NK_RECUR_DEF,18     # surface-only pure recursive definition wrapper
.equ NK_RECUR_APPLY,19   # surface-only invocation; must converge to old iterate facts
.equ NK_CALL_ARG,20      # surface-only arbitrary-arity call-argument chain

# Compile-time Structured Fact tags. Structured facts never enter canonical IR;
# they are containers of existing scalar AST/ValueFacts and disappear through
# projection or structural mathematics before serialization.
.equ STF_COMPLEX,1
.equ STF_ROOT,2
# Structured matrix/vector families encode their dimension in the tag.
# matrix2/3/4 and vec2/3/4 are legacy surface aliases only; the algorithms
# consume one dimension-bearing family rather than three named species.
.equ STF_MATRIX_BASE,0x40000000
.equ STF_VECTOR_BASE,0x80000000
.equ STF_MAT2,STF_MATRIX_BASE+2
.equ STF_MAT3,STF_MATRIX_BASE+3
.equ STF_MAT4,STF_MATRIX_BASE+4
.equ STF_VEC2,STF_VECTOR_BASE+2
.equ STF_VEC3,STF_VECTOR_BASE+3
.equ STF_VEC4,STF_VECTOR_BASE+4

.equ OP_OR,1
.equ OP_AND,2
.equ OP_BIT_OR,3
.equ OP_BIT_XOR,4
.equ OP_BIT_AND,5
.equ OP_EQ,6
.equ OP_NE,7
.equ OP_LT,8
.equ OP_LE,9
.equ OP_GT,10
.equ OP_GE,11
.equ OP_SHL,12
.equ OP_SHR,13
.equ OP_ADD,14
.equ OP_SUB,15
.equ OP_MUL,16
.equ OP_DIV,17
.equ OP_MOD,18
.equ OP_NOT,19
.equ OP_BIT_NOT,20
.equ OP_NEG,21
.equ OP_SELECT,22
.equ OP_MIN,23
.equ OP_MAX,24
.equ OP_ABS,25
.equ OP_USHR,26
.equ OP_SQRT,27
.equ OP_TRUNC,28
.equ OP_SQUARE,29
.equ OP_EXP,30
.equ OP_LOG,31
.equ OP_SIN,32
.equ OP_COS,33

# Surface-only native mathematics IDs. These are compile-time semantics, not
# runtime opcodes. Every entry disappears into existing ValueFact operations.
.equ MB_SIN,1
.equ MB_COS,2
.equ MB_TAN,3
.equ MB_ASIN,4
.equ MB_ACOS,5
.equ MB_ATAN,6
.equ MB_EXP,7
.equ MB_LOG,8
.equ MB_EXP2,9
.equ MB_LOG2,10
.equ MB_LOG10,11
.equ MB_EXPM1,12
.equ MB_LOG1P,13
.equ MB_SINH,14
.equ MB_COSH,15
.equ MB_TANH,16
.equ MB_ASINH,17
.equ MB_ACOSH,18
.equ MB_ATANH,19
.equ MB_SEC,20
.equ MB_CSC,21
.equ MB_COT,22
.equ MB_SECH,23
.equ MB_CSCH,24
.equ MB_COTH,25
.equ MB_RSQRT,26
.equ MB_RECIP,27
.equ MB_SQUARE,28
.equ MB_CUBE,29
.equ MB_HYPOT,30
.equ MB_ERF,31
.equ MB_ERFC,32
.equ MB_GAMMA,33
.equ MB_LGAMMA,34
.equ MB_BETA,35
.equ MB_LAMBERTW,36
.equ MB_BESSELJ0,37
.equ MB_BESSELJ1,38
.equ MB_BESSELI0,39
.equ MB_ZETA,40
.equ MB_POLYLOG,41
.equ MB_ELLIPTICK,42
.equ MB_ELLIPTICE,43
.equ MB_SINC,44
.equ MB_FMA,45
.equ MB_CLAMP,46
.equ MB_LERP,47
.equ MB_FACTORIAL,48
.equ MB_BINOMIAL,49
.equ MB_RISING,50
.equ MB_FALLING,51
.equ MB_DIGAMMA,52
.equ MB_TRIGAMMA,53
.equ MB_ERFINV,54
.equ MB_NORMALPDF,55
.equ MB_NORMALCDF,56
.equ MB_TETRATION,57
.equ MB_DET2,58
.equ MB_DET3,59
.equ MB_BESSELI1,60
.equ MB_COMPLEX,61
.equ MB_REAL,62
.equ MB_IMAG,63
.equ MB_CONJ,64
.equ MB_CABS,65
.equ MB_CEXP,66
.equ MB_CLOG,67
.equ MB_COMPONENT,68
.equ MB_MATRIX2,69
.equ MB_MATRIX3,70
.equ MB_MATRIX4,71
.equ MB_MGET,72
.equ MB_MTRANSPOSE,73
.equ MB_MTRACE,74
.equ MB_MAKE_SPD,75
.equ MB_CHOLESKY,76
.equ MB_ORTHOGONALIZE,77
.equ MB_QR_R,78
.equ MB_LU_L,79
.equ MB_LU_U,80
.equ MB_LDLT_L,81
.equ MB_LDLT_D,82
.equ MB_MATRIX_EXP,83
.equ MB_MATRIX_LOG,84
.equ MB_MATRIX_SQRT,85
.equ MB_EIG_VALUES,86
.equ MB_EIG_VECTORS,87
.equ MB_SVD_VALUES,88
.equ MB_SVD_U,89
.equ MB_SVD_V,90
.equ MB_MATRIX_INV,91
.equ MB_HADAMARD,92
.equ MB_CSIN,93
.equ MB_CCOS,94
.equ MB_CSQRT,95
.equ MB_ROOT_VALID,96
.equ MB_LAST,96

# Semantic Registry flags.  These describe mathematical identity only; they do
# not create a runtime class or execution branch.  Every registered semantic is
# still realized by the existing ValueFact/Rank-N/Physical-DAG authorities.
.equ MSF_PURE,1
.equ MSF_DIFFERENTIABLE,2
.equ MSF_NATIVE_VALUEFACT,4
.equ MSF_STATIC_ARG0,8
.equ MSF_SPECIAL,16
.equ MSF_STATIC_ARG1,32
.equ MSF_OPTIONAL_ITER,64

# Historical defaults are fallback policy only.  They do not define semantic
# capacity: every flagged advanced semantic may accept one final AOT-static
# iteration argument, exactly like root(...[,iterations]).
.equ MATH_DEFAULT_ROOT_ITER,5
.equ MATH_DEFAULT_INTEGRAL_PANELS,1
.equ MATH_DEFAULT_LAMBERTW_ITER,3
.equ MATH_DEFAULT_ERFINV_ITER,2
.equ MATH_DEFAULT_DIGAMMA_SHIFT,8
.equ MATH_DEFAULT_TRIGAMMA_SHIFT,8
.equ MATH_DEFAULT_ZETA_TERMS,16
.equ MATH_DEFAULT_POLYLOG_TERMS,24
.equ MATH_DEFAULT_ELLIPTIC_ITER,6
.equ MATH_DEFAULT_MATRIX_EXP_TERMS,12
.equ MATH_DEFAULT_MATRIX_LOG_ITER,9
.equ MATH_DEFAULT_MATRIX_SQRT_ITER,6
.equ MATH_DEFAULT_EIG_ITER,20
# Unified Semantic Parse Authority.  A semantic entry declares the syntactic
# shape it needs; the primary parser never grows a name-specific branch again.
# Parse classes are structural families, not execution backends.
.equ MSC_STATIC_SUM,1
.equ MSC_STATIC_PRODUCT_SUM,2
.equ MSC_STATIC_SQNORM,3
.equ MSC_STATIC_NORM,4
.equ MSC_STATIC_SQDIST,5
.equ MSC_STATIC_DIST,6
.equ MSC_STATIC_MEAN,7
.equ MSC_STATIC_RMS,8
.equ MSC_STATIC_VARIANCE,9
.equ MSC_DERIVATIVE,10
.equ MSC_SECOND_DERIVATIVE,11
.equ MSC_HESSIAN_COMPONENT,12
.equ MSC_LAPLACIAN2,13
.equ MSC_INTEGRAL,14
.equ MSC_ROOT,15
.equ MSC_POW,16
.equ MSC_MATRIX,17
.equ MSC_LAST,17
.equ KID_PROGRAM,1
.equ KID_CONTRACT,2
.equ KID_INPUT,3
.equ KID_RANGE,4
.equ KID_LET,5
.equ KID_TENSOR,6
.equ KID_REDUCE,7
.equ KID_SUM,8
.equ KID_ITERATE,9
.equ KID_LIMIT,10
.equ KID_STATE,11
.equ KID_WHILE,12
.equ KID_UPDATE,13
.equ KID_RESULT,14
.equ KID_RECORD,15
.equ KID_AXIS,16
.equ KID_PURE,17
.equ KID_GENERIC,18
.equ KID_FN,19
.equ KID_REGION,20
.equ KID_EFFECT,21
.equ KID_PARALLEL,22
.equ KID_FOR,23
.equ KID_IF,24
.equ KID_ELSE,25
.equ KID_TOLERANCE,26
.equ KID_STRICT,27
.equ KID_FIELD,28
.equ KID_IN,29
.equ KID_OUTPUT,30
.equ KID_PUBLISH,31
.equ KID_TEST,32
.equ KID_TRUE,33
.equ KID_FALSE,34
.equ KID_CAST,35
.equ KID_SELECT,36
.equ KID_MIN,37
.equ KID_MAX,38
.equ KID_ABS,39
.equ KID_PERIODIC,40
.equ KID_DICTIONARY,41
.equ KID_LOOKUP,42
.equ KID_DEFAULT,43
.equ KID_NESTED,44
.equ KID_NESTED_REDUCE,45
.equ KID_CASCADE,46
.equ KID_EVENTS,47
.equ KID_GOAL,48
.equ KID_WORK,49
.equ KID_RELATION,50
.equ KID_TO,51
.equ KID_GOAL_RESULT,52
.equ KID_EACH,53
.equ KID_PRECISION_PROPAGATION,54

.extern source_ptr
.extern source_length

.global surface_lower_to_json
.global surface_json_buffer
.global surface_json_length

# -----------------------------------------------------------------------------
# Structural-aging arenas
# -----------------------------------------------------------------------------
# Source-index metadata capacity is derived from this source instance.  The
# generated AST and generated names use non-moving slabs and therefore have no
# source-cardinality ceiling.
s_prepare_surface_arenas:
    push rbx; push r12; push r13
    mov rax,[rip+source_length]
    shr rax,1
    add rax,64
    cmp rax,1024
    jae .spsa_cap_ready
    mov eax,1024
.spsa_cap_ready:
    mov rcx,0xffffffff; cmp rax,rcx
    ja .spsa_fail
    mov dword ptr [rip+s_fact_cap],eax
    mov r12,rax
    imul rsi,rax,SURFACE_FACT_RECORD_BYTES
    jo .spsa_fail
    mov [rip+s_fact_arena_bytes],rsi
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .spsa_fail
    mov [rip+s_fact_arena],rax
    mov rbx,rax
    mov [rip+s_math_call_args],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_axis_ptrs],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_axis_lens],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_state_ptrs],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_state_lens],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_state_name_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_state_name_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_state_type_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_state_type_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_state_init_ast],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_update_name_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_update_name_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_iter_update_ast],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_shape_axis_ptrs],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_shape_axis_lens],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_shape_extent_ptrs],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_shape_extent_lens],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_shape_extent_kind],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_shape_extent_static],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_shape_low_bit],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_shape_stride_static],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_record_name_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_record_name_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_record_field_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_record_field_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_record_value_ast],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_function_name_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_function_name_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_function_param_offset],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_function_param_count],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_function_param_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_function_param_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_function_expr_ast],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_struct_decl_ptrs],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_struct_decl_lens],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_struct_decl_nodes],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_decl_ptrs],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_decl_lens],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_decl_shape_rank],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_decl_shape_offset],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_decl_shape_stride_pool],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_dictionary_name_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_dictionary_name_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_dictionary_entry_dict],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_dictionary_entry_key],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_dictionary_entry_value],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_nested_name_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_nested_name_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_nested_sum_ast],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_nested_item_count],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_nested_segment_count],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_cascade_goal_name_ptr],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_cascade_goal_name_len],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_cascade_goal_work_ast],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_cascade_goal_expr_ast],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    mov [rip+s_cascade_edge_from],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_cascade_edge_to],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_cascade_goal_done],rbx
    mov rax,r12; imul rax,4; add rbx,rax
    mov [rip+s_cascade_goal_result],rbx
    mov rax,r12; imul rax,8; add rbx,rax
    # The source-derived fact arena is one structural layout.  Its byte authority
    # must equal the columns actually laid above; a future column addition may
    # not silently outrun the mapped arena.
    mov rax,[rip+s_fact_arena]
    add rax,[rip+s_fact_arena_bytes]
    cmp rbx,rax
    jne .spsa_fail
    # Type capture contains source spelling only, never expanded AST text.
    mov rsi,[rip+source_length]
    add rsi,4096
    jc .spsa_fail
    mov [rip+s_type_capture_cap],rsi
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .spsa_fail
    mov [rip+s_type_capture_buf],rax
    # Serialization capacities are allocator state, not semantic limits.
    lea rbx,[rip+s_inputs_buf]; lea r12,[rip+s_inputs_cap]; call s_alloc_stream_arena; test eax,eax; jnz .spsa_fail
    lea rbx,[rip+s_bindings_buf]; lea r12,[rip+s_bindings_cap]; call s_alloc_stream_arena; test eax,eax; jnz .spsa_fail
    lea rbx,[rip+s_outputs_buf]; lea r12,[rip+s_outputs_cap]; call s_alloc_stream_arena; test eax,eax; jnz .spsa_fail
    lea rbx,[rip+s_tests_buf]; lea r12,[rip+s_tests_cap]; call s_alloc_stream_arena; test eax,eax; jnz .spsa_fail
    lea rbx,[rip+surface_json_buffer]; lea r12,[rip+surface_json_cap]; call s_alloc_stream_arena; test eax,eax; jnz .spsa_fail
    xor eax,eax
    pop r13; pop r12; pop rbx; ret
.spsa_fail:
    mov eax,1
    pop r13; pop r12; pop rbx; ret

# rbx=&base pointer, r12=&capacity
s_alloc_stream_arena:
    mov rsi,SURFACE_STREAM_INITIAL_BYTES
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .sasa_fail
    mov [rbx],rax
    mov qword ptr [r12],SURFACE_STREAM_INITIAL_BYTES
    xor eax,eax; ret
.sasa_fail:
    mov eax,1; ret

# edi=additional bytes from the current cursor.  The active stream can move;
# all persistent cursors are repaired from offsets after mremap.
s_out_reserve:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,[rip+s_active_base_var]
    mov r12,[rip+s_active_cap_var]
    test rbx,rbx; jz .sor_fail
    test r12,r12; jz .sor_fail
    mov r13,[rbx]
    mov r14,[r12]
    mov r15,[rip+s_out_ptr]
    sub r15,r13
    mov rcx,r15; add rcx,rdi; jc .sor_fail
    mov rdx,r14
.sor_grow:
    cmp rdx,rcx; jae .sor_remap
    add rdx,rdx; jc .sor_fail
    jmp .sor_grow
.sor_remap:
    mov rdi,r13; mov rsi,r14
    mov eax,SYS_mremap; mov r10d,MREMAP_MAYMOVE; syscall
    test rax,rax; js .sor_fail
    mov [rbx],rax
    lea rcx,[rax+r15]; mov [rip+s_out_ptr],rcx
    lea rcx,[rax+rdx]; mov [rip+s_out_limit],rcx
    mov [r12],rdx
    mov r9,[rip+s_active_end_var]
    test r9,r9; jz .sor_ok
    mov rcx,[r9]; sub rcx,r13; add rcx,rax; mov [r9],rcx
.sor_ok:
    xor eax,eax
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret
.sor_fail:
    mov eax,1
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Stable 32-byte generated names use non-moving slabs because AST variables hold
# direct pointers to the spelling.
s_alloc_struct_temp_name:
    mov rax,[rip+s_struct_temp_cur]
    lea rcx,[rax+32]
    cmp rcx,[rip+s_struct_temp_end]
    jbe .sastn_have
    push rbx
    mov rbx,[rip+s_struct_temp_next_slab_bytes]
    test rbx,rbx; jnz .sastn_size
    mov rbx,65536
.sastn_size:
    mov eax,SYS_mmap; xor edi,edi; mov rsi,rbx; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .sastn_fail
    mov [rip+s_struct_temp_cur],rax
    lea rcx,[rax+rbx]; mov [rip+s_struct_temp_end],rcx
    mov rcx,rbx; add rcx,rcx; jc .sastn_keep
    mov [rip+s_struct_temp_next_slab_bytes],rcx
    jmp .sastn_alloc
.sastn_keep:
    mov [rip+s_struct_temp_next_slab_bytes],rbx
.sastn_alloc:
    pop rbx
    mov rax,[rip+s_struct_temp_cur]
    lea rcx,[rax+32]
.sastn_have:
    mov [rip+s_struct_temp_cur],rcx
    ret
.sastn_fail:
    xor eax,eax
    pop rbx
    ret

# rdi=compiler-lifetime pointer-workset bytes -> rax base /0.  Matrix and
# structured lowering scratch is derived from the represented object rather than
# a fixed small-matrix tier.  The compiler process is one-shot, so these arenas
# deliberately share its lifetime and need no semantic free operation.
s_alloc_pointer_workset:
    test rdi,rdi; jz .sapw_fail
    mov rsi,rdi
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .sapw_fail
    ret
.sapw_fail:
    xor eax,eax; ret

# -----------------------------------------------------------------------------
# Output primitives
# -----------------------------------------------------------------------------
s_out_byte:
    # dil=byte. Active serialization streams grow geometrically.
    mov rax,[rip+s_out_ptr]
    cmp rax,[rip+s_out_limit]
    jb .sob_room
    push rdi
    mov edi,1
    call s_out_reserve
    pop rdi
    test eax,eax; jnz .sob_fail
    mov rax,[rip+s_out_ptr]
.sob_room:
    mov [rax],dil
    inc rax
    mov [rip+s_out_ptr],rax
    xor eax,eax
    ret
.sob_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1
    ret

s_out_span:
    # rdi=ptr, rsi=len
    mov rax,[rip+s_out_ptr]
    mov rcx,rax
    add rcx,rsi
    jc .sos_fail
    cmp rcx,[rip+s_out_limit]
    jbe .sos_room
    push rdi; push rsi
    mov rdi,rsi
    call s_out_reserve
    pop rsi; pop rdi
    test eax,eax; jnz .sos_fail
    mov rax,[rip+s_out_ptr]
.sos_room:
    mov rdx,rdi
    mov rdi,rax
    mov rcx,rsi
    mov rsi,rdx
    rep movsb
    mov [rip+s_out_ptr],rdi
    xor eax,eax
    ret
.sos_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1
    ret

s_out_cstr:
    # rdi=zero-terminated ASCII constant
    push rdi
    xor esi,esi
.soc_len:
    cmp byte ptr [rdi+rsi],0
    je .soc_go
    inc rsi
    jmp .soc_len
.soc_go:
    pop rdi
    jmp s_out_span

s_out_quote_span:
    # rdi=identifier/content ptr, rsi=len. Human identifiers may not contain quote/backslash.
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    mov dil,'"'; call s_out_byte
    test eax,eax; jnz .soqs_fail
    xor rcx,rcx
.soqs_scan:
    cmp rcx,r12
    jae .soqs_body
    mov al,[rbx+rcx]
    cmp al,'"'; je .soqs_fail
    cmp al,'\\'; je .soqs_fail
    cmp al,0; je .soqs_fail
    inc rcx
    jmp .soqs_scan
.soqs_body:
    mov rdi,rbx; mov rsi,r12; call s_out_span
    test eax,eax; jnz .soqs_fail
    mov dil,'"'; call s_out_byte
    jmp .soqs_done
.soqs_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1
.soqs_done:
    pop r12
    pop rbx
    ret

# -----------------------------------------------------------------------------
# Human-shell diagnostics.  One fused state per class: repair, convergence,
# error.  These facts report what the existing parser/proofs already did; they
# own no semantic rewrite, retry path, optimizer family, or runtime policy.
# WH enables them, WHEX/canonical inputs remain expert-silent.
# -----------------------------------------------------------------------------
s_diag_reset_for_path:
    # rdi=source path
    push rdi
    mov dword ptr [rip+surface_diag_active],0
    mov dword ptr [rip+surface_diag_repaired],0
    mov qword ptr [rip+surface_diag_repair_line],0
    mov dword ptr [rip+surface_diag_cheesed],0
    mov qword ptr [rip+surface_diag_cheese_line],0
    mov qword ptr [rip+surface_diag_error_line],0
    mov qword ptr [rip+s_peek_repair_ptr],0
    pop rdi
    call s_path_is_whex
    test eax,eax
    setz al
    movzx eax,al
    mov dword ptr [rip+surface_diag_active],eax
    ret

# rdi=pointer into current human source -> rax=1-based line, 0 if unavailable.
s_diag_line_from_ptr:
    cmp dword ptr [rip+surface_diag_active],0
    je .sdlp_none
    mov r8,[rip+s_src]
    mov r9,[rip+s_end]
    test r8,r8
    jz .sdlp_none
    cmp rdi,r8
    jb .sdlp_none
    cmp rdi,r9
    jbe .sdlp_bound
    mov rdi,r9
.sdlp_bound:
    mov rax,1
.sdlp_scan:
    cmp r8,rdi
    jae .sdlp_done
    cmp byte ptr [r8],10
    jne .sdlp_next
    inc rax
.sdlp_next:
    inc r8
    jmp .sdlp_scan
.sdlp_done:
    ret
.sdlp_none:
    xor eax,eax
    ret

# rdi=source token pointer.  First location is the single human-shell witness.
s_diag_note_repair_ptr:
    push rax; push rdi
    cmp dword ptr [rip+surface_diag_active],0
    je .sdnrp_done
    mov dword ptr [rip+surface_diag_repaired],1
    cmp qword ptr [rip+surface_diag_repair_line],0
    jne .sdnrp_done
    call s_diag_line_from_ptr
    mov [rip+surface_diag_repair_line],rax
.sdnrp_done:
    pop rdi; pop rax
    ret

# rdi=source token pointer.  Convergence is one successful exit, no subtype.
s_diag_note_cheese_ptr:
    push rax; push rdi
    cmp dword ptr [rip+surface_diag_active],0
    je .sdncp_done
    mov dword ptr [rip+surface_diag_cheesed],1
    cmp qword ptr [rip+surface_diag_cheese_line],0
    jne .sdncp_done
    call s_diag_line_from_ptr
    mov [rip+surface_diag_cheese_line],rax
.sdncp_done:
    pop rdi; pop rax
    ret

# General semantic convergence reports the converged symbol name here.  Surface
# resolves that name back to the original declaration spelling solely for line
# reporting; the semantic representative remains owned by General.
surface_note_convergence_name:
    push rax; push rbx; push rcx; push rdx; push rdi; push rsi; push r12; push r13
    cmp dword ptr [rip+surface_diag_active],0
    je .sncn_done
    mov dword ptr [rip+surface_diag_cheesed],1
    cmp qword ptr [rip+surface_diag_cheese_line],0
    jne .sncn_done
    mov r12,rdi
    mov r13,rsi
    xor ebx,ebx
.sncn_scan:
    cmp ebx,dword ptr [rip+s_decl_count]
    jae .sncn_done
    mov rax,[rip+s_decl_ptrs]
    mov rdi,[rax+rbx*8]
    mov rax,[rip+s_decl_lens]
    mov rsi,[rax+rbx*8]
    mov rdx,r12
    mov rcx,r13
    call s_span_eq
    test eax,eax
    jnz .sncn_found
    inc ebx
    jmp .sncn_scan
.sncn_found:
    mov rax,[rip+s_decl_ptrs]
    mov rdi,[rax+rbx*8]
    call s_diag_line_from_ptr
    mov [rip+surface_diag_cheese_line],rax
.sncn_done:
    pop r13; pop r12; pop rsi; pop rdi; pop rdx; pop rcx; pop rbx; pop rax
    ret

# Capture the parser cursor once when a human-surface failure becomes final.
s_diag_note_error_cursor:
    push rax; push rdi
    cmp dword ptr [rip+surface_diag_active],0
    je .sdnec_done
    cmp qword ptr [rip+surface_diag_error_line],0
    jne .sdnec_done
    mov rdi,[rip+s_cur]
    call s_diag_line_from_ptr
    mov [rip+surface_diag_error_line],rax
.sdnec_done:
    pop rdi; pop rax
    ret

# -----------------------------------------------------------------------------
# Source cursor primitives
# -----------------------------------------------------------------------------
s_skip:
    mov rax,[rip+s_cur]
    mov rdx,[rip+s_end]
.ss_loop:
    cmp rax,rdx
    jae .ss_done
    mov cl,[rax]
    cmp cl,' '; je .ss_one
    cmp cl,9; je .ss_one
    cmp cl,10; je .ss_one
    cmp cl,13; je .ss_one
    cmp cl,'#'; je .ss_hash
    cmp cl,'/'; jne .ss_done
    lea rcx,[rax+1]
    cmp rcx,rdx; jae .ss_done
    mov cl,[rax+1]
    cmp cl,'/'; je .ss_slash
    cmp cl,'*'; je .ss_block
    jmp .ss_done
.ss_one:
    inc rax
    jmp .ss_loop
.ss_hash:
    inc rax
.ss_hash_loop:
    cmp rax,rdx; jae .ss_done
    cmp byte ptr [rax],10; je .ss_one
    inc rax; jmp .ss_hash_loop
.ss_slash:
    add rax,2
.ss_slash_loop:
    cmp rax,rdx; jae .ss_done
    cmp byte ptr [rax],10; je .ss_one
    inc rax; jmp .ss_slash_loop
.ss_block:
    add rax,2
.ss_block_loop:
    lea rcx,[rax+1]
    cmp rcx,rdx; jae .ss_bad
    cmp byte ptr [rax],'*'; jne .ss_block_next
    cmp byte ptr [rax+1],'/'; je .ss_block_close
.ss_block_next:
    inc rax; jmp .ss_block_loop
.ss_block_close:
    add rax,2
    jmp .ss_loop
.ss_bad:
    mov dword ptr [rip+s_error],1
.ss_done:
    mov [rip+s_cur],rax
    ret

s_is_ident_byte:
    # dil -> eax bool (ASCII letters/digits/_ or UTF-8 non-ASCII byte)
    movzx eax,dil
    cmp al,0x80; jae .siib_yes
    cmp al,'A'; jb .siib_low
    cmp al,'Z'; jbe .siib_yes
.siib_low:
    cmp al,'a'; jb .siib_digit
    cmp al,'z'; jbe .siib_yes
.siib_digit:
    cmp al,'0'; jb .siib_us
    cmp al,'9'; jbe .siib_yes
.siib_us:
    cmp al,'_'; je .siib_yes
    xor eax,eax; ret
.siib_yes:
    mov eax,1; ret


# rdi=source pointer -> eax byte length when a handwritten Unicode math token
# starts here, else 0. Unquoted identifiers stop at these spellings; quoted
# identifiers remain fully permissive. This keeps π² and a×b lexical rather
# than accidentally absorbing the operator bytes into an UTF-8 identifier.
s_unicode_math_token_len:
    cmp rdi,[rip+s_end]; jae .sumtl_no
    movzx eax,byte ptr [rdi]
    cmp al,0xC2; je .sumtl_c2
    cmp al,0xC3; je .sumtl_c3
    cmp al,0xE2; je .sumtl_e2
    cmp al,0xEF; je .sumtl_ef
.sumtl_no: xor eax,eax; ret
.sumtl_c2:
    lea rcx,[rdi+1]; cmp rcx,[rip+s_end]; jae .sumtl_no
    movzx eax,byte ptr [rdi+1]
    cmp al,0xB2; je .sumtl_two       # ²
    cmp al,0xB3; je .sumtl_two       # ³
    cmp al,0xB7; je .sumtl_two       # ·
    cmp al,0xAC; je .sumtl_two       # ¬
    jmp .sumtl_no
.sumtl_c3:
    lea rcx,[rdi+1]; cmp rcx,[rip+s_end]; jae .sumtl_no
    movzx eax,byte ptr [rdi+1]
    cmp al,0x97; je .sumtl_two       # ×
    cmp al,0xB7; je .sumtl_two       # ÷
    jmp .sumtl_no
.sumtl_e2:
    lea rcx,[rdi+2]; cmp rcx,[rip+s_end]; jae .sumtl_no
    movzx eax,byte ptr [rdi+1]
    cmp al,0x81; je .sumtl_e281
    cmp al,0x88; je .sumtl_e288
    cmp al,0x89; je .sumtl_e289
    cmp al,0x8B; je .sumtl_e28b
    jmp .sumtl_no
.sumtl_e281:
    cmp byte ptr [rdi+2],0x84; je .sumtl_three  # ⁄ U+2044
    jmp .sumtl_no
.sumtl_e288:
    movzx eax,byte ptr [rdi+2]
    cmp al,0x92; je .sumtl_three     # −
    cmp al,0x95; je .sumtl_three     # ∕
    cmp al,0x97; je .sumtl_three     # ∗
    cmp al,0x99; je .sumtl_three     # ∙
    cmp al,0x9A; je .sumtl_three     # √
    cmp al,0xA7; je .sumtl_three     # ∧
    cmp al,0xA8; je .sumtl_three     # ∨
    jmp .sumtl_no
.sumtl_e289:
    movzx eax,byte ptr [rdi+2]
    cmp al,0xA0; je .sumtl_three     # ≠
    cmp al,0xA4; je .sumtl_three     # ≤
    cmp al,0xA5; je .sumtl_three     # ≥
    jmp .sumtl_no
.sumtl_e28b:
    cmp byte ptr [rdi+2],0x85; je .sumtl_three  # ⋅
    jmp .sumtl_no
.sumtl_ef:
    lea rcx,[rdi+2]; cmp rcx,[rip+s_end]; jae .sumtl_no
    cmp byte ptr [rdi+1],0xBC; jne .sumtl_no
    movzx eax,byte ptr [rdi+2]
    cmp al,0x8B; je .sumtl_three     # ＋
    cmp al,0x8D; je .sumtl_three     # －
    cmp al,0x8A; je .sumtl_three     # ＊
    cmp al,0x8F; je .sumtl_three     # ／
    cmp al,0xBE; je .sumtl_three     # ＾
    jmp .sumtl_no
.sumtl_two: mov eax,2; ret
.sumtl_three: mov eax,3; ret

s_match_token:
    # rdi=literal ptr, esi=len, edx=boundary(1 keyword /0 operator). eax=1 consumed /0
    push rbx
    push r12
    push r13
    mov rbx,rdi; mov r12d,esi; mov r13d,edx
    call s_skip
    mov r8,[rip+s_cur]
    mov r9,r8
    add r9,r12
    cmp r9,[rip+s_end]
    ja .smt_no
    xor ecx,ecx
.smt_cmp:
    cmp ecx,r12d; jae .smt_boundary
    mov al,[r8+rcx]
    cmp al,[rbx+rcx]; jne .smt_no
    inc ecx; jmp .smt_cmp
.smt_boundary:
    test r13d,r13d; jz .smt_yes
    cmp r9,[rip+s_end]; jae .smt_yes
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jnz .smt_no
.smt_yes:
    mov [rip+s_cur],r9
    mov eax,1
    jmp .smt_done
.smt_no:
    xor eax,eax
.smt_done:
    pop r13; pop r12; pop rbx; ret

s_expect_token:
    call s_match_token
    test eax,eax; jnz .set_ok
    mov dword ptr [rip+s_error],1
.set_ok:
    ret

s_match_kw_id:
    push rbx; push r12; push r13; push r14
    mov ebx,edi
    lea r12,[rip+s_kw_alias_table]
.smki_loop:
    mov rax,[r12]; test rax,rax; jz .smki_split
    cmp dword ptr [r12+12],ebx; jne .smki_next
    mov rdi,rax; mov esi,dword ptr [r12+8]; mov edx,1; call s_match_token
    test eax,eax; jnz .smki_yes
.smki_next: add r12,16; jmp .smki_loop
.smki_split:
    mov edi,ebx; call s_match_kw_split_id
    test eax,eax; jnz .smki_yes
    mov r14,[rip+s_cur]
    mov r13d,[rip+s_error]
    call s_parse_name
    test edx,edx; jnz .smki_restore
    mov rdi,rax; mov rsi,rcx; call s_keyword_edit_repair
    cmp eax,ebx; jne .smki_restore
    mov rdi,rdx; call s_diag_note_repair_ptr
    jmp .smki_yes
.smki_restore:
    mov [rip+s_cur],r14
    mov [rip+s_error],r13d
    xor eax,eax; jmp .smki_done
.smki_yes: mov eax,1
.smki_done: pop r14; pop r13; pop r12; pop rbx; ret

s_expect_kw_id:
    call s_match_kw_id
    test eax,eax; jnz .seki_ok
    mov dword ptr [rip+s_error],1
.seki_ok: ret

s_span_kw_id:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r12,rsi; mov r13d,edx
    lea r14,[rip+s_kw_alias_table]
.sski_loop:
    mov rax,[r14]; test rax,rax; jz .sski_repair
    cmp dword ptr [r14+12],r13d; jne .sski_next
    mov rdi,rbx; mov rsi,r12; mov rdx,rax; mov ecx,dword ptr [r14+8]; call s_span_eq
    test eax,eax; jnz .sski_yes
.sski_next: add r14,16; jmp .sski_loop
.sski_repair:
    mov rdi,rbx; mov rsi,r12; call s_keyword_edit_repair
    cmp eax,r13d; jne .sski_no
    mov rdi,rdx; call s_diag_note_repair_ptr
    mov eax,1; jmp .sski_done
.sski_no: xor eax,eax; jmp .sski_done
.sski_yes: mov eax,1
.sski_done: pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Conservative English-only surface repair.
# These helpers never rewrite source bytes. They redirect a token only when the
# repair is unique. Chinese/mixed/emoji identifiers are exact-only.
# -----------------------------------------------------------------------------
s_span_ascii:
    xor ecx,ecx
.ssa_loop:
    cmp rcx,rsi; jae .ssa_yes
    cmp byte ptr [rdi+rcx],0x80; jae .ssa_no
    inc rcx; jmp .ssa_loop
.ssa_yes: mov eax,1; ret
.ssa_no: xor eax,eax; ret

s_edit1_ascii:
    # rdi=a,rsi=alen,rdx=b,rcx=blen -> eax exactly one insertion/deletion/substitution.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov r14,rcx
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .se1_no
    mov rdi,r13; mov rsi,r14; call s_span_ascii; test eax,eax; jz .se1_no
    mov rax,r12; sub rax,r14
    cmp rax,1; je .se1_del_a
    cmp rax,-1; je .se1_del_b
    test rax,rax; jne .se1_no
    xor r15d,r15d; xor ecx,ecx
.se1_sub_loop:
    cmp rcx,r12; jae .se1_sub_done
    mov al,[rbx+rcx]; cmp al,[r13+rcx]; je .se1_sub_next
    inc r15d; cmp r15d,1; ja .se1_no
.se1_sub_next: inc rcx; jmp .se1_sub_loop
.se1_sub_done: cmp r15d,1; sete al; movzx eax,al; jmp .se1_done
.se1_del_a:
    xor ecx,ecx; xor r15d,r15d; xor r8d,r8d
.se1_da_loop:
    cmp r8,r14; jae .se1_da_tail
    mov al,[rbx+rcx]; cmp al,[r13+r8]; je .se1_da_eq
    inc r15d; cmp r15d,1; ja .se1_no
    inc rcx; jmp .se1_da_loop
.se1_da_eq: inc rcx; inc r8; jmp .se1_da_loop
.se1_da_tail:
    mov rax,r12; sub rax,rcx; add r15d,eax
    cmp r15d,1; sete al; movzx eax,al; jmp .se1_done
.se1_del_b:
    xor ecx,ecx; xor r15d,r15d; xor r8d,r8d
.se1_db_loop:
    cmp rcx,r12; jae .se1_db_tail
    mov al,[rbx+rcx]; cmp al,[r13+r8]; je .se1_db_eq
    inc r15d; cmp r15d,1; ja .se1_no
    inc r8; jmp .se1_db_loop
.se1_db_eq: inc rcx; inc r8; jmp .se1_db_loop
.se1_db_tail:
    mov rax,r14; sub rax,r8; add r15d,eax
    cmp r15d,1; sete al; movzx eax,al; jmp .se1_done
.se1_no: xor eax,eax
.se1_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_decl_add:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sda_scan:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .sda_new
    mov rax,[rip+s_decl_ptrs]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_decl_lens]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sda_ok
    inc r13d; jmp .sda_scan
.sda_new:
    cmp r13d,dword ptr [rip+s_fact_cap]; jae .sda_fail
    mov rax,[rip+s_decl_ptrs]; mov [rax+r13*8],rbx
    mov rax,[rip+s_decl_lens]; mov [rax+r13*8],r12
    mov rax,[rip+s_decl_shape_rank]; mov dword ptr [rax+r13*4],0
    inc dword ptr [rip+s_decl_count]
.sda_ok:
    mov dword ptr [rip+s_last_decl_index],r13d
    xor eax,eax; jmp .sda_done
.sda_fail: mov dword ptr [rip+s_error],1; mov eax,1
.sda_done: pop r13; pop r12; pop rbx; ret

# Exact declaration identity lookup. Unlike typo repair this never changes spelling.
# rdi=name ptr,rsi=len -> eax declaration index or -1.
s_decl_lookup_exact:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sdle_loop:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .sdle_no
    mov rax,[rip+s_decl_ptrs]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_decl_lens]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq
    test eax,eax; jnz .sdle_yes
    inc r13d; jmp .sdle_loop
.sdle_yes: mov eax,r13d; jmp .sdle_done
.sdle_no: mov eax,-1
.sdle_done: pop r13; pop r12; pop rbx; ret

# Persist the current ShapeFact-N shape on the declaration that was just added.
# This is compile-time metadata only. It lets a lower-rank consumer index a
# higher-rank source without pretending the consumer's layout is the source's.
s_store_decl_shape_meta:
    # Persist source-shape strides in one flat metadata pool.  Total stored axes
    # are bounded only by the common Surface fact arena; declaration_count*rank
    # is not a second rectangular capacity law.
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,dword ptr [rip+s_last_decl_index]
    cmp ebx,dword ptr [rip+s_fact_cap]; jae .sdrm_fail
    mov r12d,dword ptr [rip+s_shape_rank]
    mov rax,[rip+s_decl_shape_rank]; mov [rax+rbx*4],r12d
    mov r15d,dword ptr [rip+s_decl_shape_stride_count]
    mov rax,[rip+s_decl_shape_offset]; mov [rax+rbx*4],r15d
    mov eax,r15d; add eax,r12d; jc .sdrm_fail
    cmp eax,dword ptr [rip+s_fact_cap]; ja .sdrm_fail
    xor r13d,r13d
.sdrm_loop:
    cmp r13d,r12d; jae .sdrm_ok
    mov rax,[rip+s_shape_stride_static]; mov r14,[rax+r13*8]
    mov rdx,[rip+s_decl_shape_stride_pool]; mov [rdx+r15*8],r14
    inc r15d; inc r13d; jmp .sdrm_loop
.sdrm_ok:
    mov dword ptr [rip+s_decl_shape_stride_count],r15d
    xor eax,eax; jmp .sdrm_done
.sdrm_fail: mov dword ptr [rip+s_error],1; mov eax,1
.sdrm_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Structured declaration identity.  Structured Facts remain compile-time values;
# a let-binding stores their AST identity here instead of manufacturing a runtime
# scalar slot.  Every later use reuses the same component facts.
s_struct_decl_add:
    # rdi=name ptr,rsi=len,rdx=structured AST -> eax 0 success
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r12,rsi; mov r14,rdx; xor r13d,r13d
.ssda_scan:
    cmp r13d,dword ptr [rip+s_struct_decl_count]; jae .ssda_new
    mov rax,[rip+s_struct_decl_ptrs]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_struct_decl_lens]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .ssda_replace
    inc r13d; jmp .ssda_scan
.ssda_new:
    cmp r13d,dword ptr [rip+s_fact_cap]; jae .ssda_fail
    inc dword ptr [rip+s_struct_decl_count]
.ssda_replace:
    mov rax,[rip+s_struct_decl_ptrs]; mov [rax+r13*8],rbx
    mov rax,[rip+s_struct_decl_lens]; mov [rax+r13*8],r12
    mov rax,[rip+s_struct_decl_nodes]; mov [rax+r13*8],r14
    xor eax,eax; jmp .ssda_done
.ssda_fail: mov dword ptr [rip+s_error],1; mov eax,1
.ssda_done: pop r14; pop r13; pop r12; pop rbx; ret

s_struct_decl_lookup:
    # rdi=name ptr,rsi=len -> rax structured AST /0
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.ssdl_loop:
    cmp r13d,dword ptr [rip+s_struct_decl_count]; jae .ssdl_no
    mov rax,[rip+s_struct_decl_ptrs]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_struct_decl_lens]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .ssdl_yes
    inc r13d; jmp .ssdl_loop
.ssdl_yes: mov rax,[rip+s_struct_decl_nodes]; mov rax,[rax+r13*8]; jmp .ssdl_done
.ssdl_no: xor eax,eax
.ssdl_done: pop r13; pop r12; pop rbx; ret

s_try_decl_repair:
    # rdi=parsed ptr,rsi=len; current cursor is immediately after first token.
    # Returns rax=canonical ptr,rcx=len; edx=1 only when repaired.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi
    xor r13d,r13d
.stdr_exact:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .stdr_split
    mov rax,[rip+s_decl_ptrs]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_decl_lens]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .stdr_exact_yes
    inc r13d; jmp .stdr_exact
.stdr_exact_yes:
    mov rax,[rip+s_decl_ptrs]; mov rax,[rax+r13*8]
    mov rcx,[rip+s_decl_lens]; mov rcx,[rcx+r13*8]
    xor edx,edx; jmp .stdr_done

.stdr_split:
    mov r14,[rip+s_cur]; mov r15,r14
    cmp r15,[rip+s_end]; jae .stdr_edit
    cmp byte ptr [r15],13; jne .stdr_split_lf
    inc r15; cmp r15,[rip+s_end]; jae .stdr_edit
    cmp byte ptr [r15],10; jne .stdr_edit
    inc r15; jmp .stdr_split_scan
.stdr_split_lf:
    cmp byte ptr [r15],10; jne .stdr_edit
    inc r15
.stdr_split_scan:
    mov r8,r15
.stdr_split_tail:
    cmp r8,[rip+s_end]; jae .stdr_split_have
    mov dil,[r8]; call s_is_ident_byte; test eax,eax; jz .stdr_split_have
    inc r8; jmp .stdr_split_tail
.stdr_split_have:
    cmp r8,r15; je .stdr_edit
    mov r9,r8; sub r9,r15
    mov [rip+s_repair_split_end],r8
    mov [rip+s_repair_split_len],r9
    xor r13d,r13d; mov r10d,-1; xor r11d,r11d
.stdr_split_candidates:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .stdr_split_decide
    mov rax,[rip+s_decl_lens]; mov rcx,[rax+r13*8]
    mov rax,r12; add rax,[rip+s_repair_split_len]; cmp rcx,rax; jne .stdr_split_next
    mov rax,[rip+s_decl_ptrs]; mov rdx,[rax+r13*8]
    mov rdi,rbx; mov rsi,r12; mov rcx,r12; call s_span_eq; test eax,eax; jz .stdr_split_next
    mov rax,[rip+s_decl_ptrs]; mov rdx,[rax+r13*8]; add rdx,r12
    mov rdi,r15; mov rsi,[rip+s_repair_split_len]; mov rcx,rsi; call s_span_eq; test eax,eax; jz .stdr_split_next
    mov r10d,r13d; inc r11d
.stdr_split_next: inc r13d; jmp .stdr_split_candidates
.stdr_split_decide:
    cmp r11d,1; jne .stdr_edit
    mov rax,[rip+s_repair_split_end]; mov [rip+s_cur],rax
    mov rdi,rbx; call s_diag_note_repair_ptr
    mov rax,[rip+s_decl_ptrs]; mov rax,[rax+r10*8]
    mov rcx,[rip+s_decl_lens]; mov rcx,[rcx+r10*8]
    mov edx,1; jmp .stdr_done

.stdr_edit:
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .stdr_orig
    xor r13d,r13d; mov r14d,-1; xor r15d,r15d
.stdr_edit_loop:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .stdr_edit_decide
    mov rax,[rip+s_decl_ptrs]; mov rdx,[rax+r13*8]
    mov rax,[rip+s_decl_lens]; mov rcx,[rax+r13*8]
    mov rdi,rbx; mov rsi,r12; call s_edit1_ascii
    test eax,eax; jz .stdr_edit_next
    mov r14d,r13d; inc r15d
.stdr_edit_next: inc r13d; jmp .stdr_edit_loop
.stdr_edit_decide:
    cmp r15d,1; je .stdr_repaired
    cmp r15d,1; jbe .stdr_orig
    mov dword ptr [rip+s_error],1
    jmp .stdr_orig
.stdr_repaired:
    mov rdi,rbx; call s_diag_note_repair_ptr
    mov rax,[rip+s_decl_ptrs]; mov rax,[rax+r14*8]
    mov rcx,[rip+s_decl_lens]; mov rcx,[rcx+r14*8]
    mov edx,1; jmp .stdr_done
.stdr_orig: mov rax,rbx; mov rcx,r12; xor edx,edx
.stdr_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_keyword_edit_repair:
    # rdi=token ptr,rsi=len -> eax unique KID or 0. English aliases only.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .sker_no
    lea r13,[rip+s_kw_alias_table]; xor r14d,r14d; xor r15d,r15d
.sker_loop:
    mov rax,[r13]; test rax,rax; jz .sker_decide
    mov rdi,rax; mov esi,dword ptr [r13+8]; call s_span_ascii; test eax,eax; jz .sker_next
    mov rdi,rbx; mov rsi,r12; mov rdx,[r13]; mov ecx,dword ptr [r13+8]; call s_edit1_ascii
    test eax,eax; jz .sker_next
    mov r14d,dword ptr [r13+12]; inc r15d
.sker_next: add r13,16; jmp .sker_loop
.sker_decide:
    cmp r15d,1; jne .sker_no
    mov eax,r14d; mov rdx,rbx; jmp .sker_done
.sker_no: xor eax,eax; xor edx,edx
.sker_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_match_kw_split_id:
    # edi=KID -> eax=1 if an ASCII canonical alias is split by exactly one CR/LF.
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; call s_skip; mov r12,[rip+s_cur]
    lea r13,[rip+s_kw_alias_table]
.smksi_alias:
    mov rax,[r13]; test rax,rax; jz .smksi_no
    cmp dword ptr [r13+12],ebx; jne .smksi_next
    mov rdi,rax; mov esi,dword ptr [r13+8]; call s_span_ascii; test eax,eax; jz .smksi_next
    mov r14,[r13]; mov r15d,dword ptr [r13+8]
    xor ecx,ecx; mov r8,r12; xor r9d,r9d
.smksi_cmp:
    cmp ecx,r15d; jae .smksi_end
    cmp r8,[rip+s_end]; jae .smksi_next
    mov al,[r8]
    cmp al,13; je .smksi_cr
    cmp al,10; je .smksi_lf
    cmp al,[r14+rcx]; jne .smksi_next
    inc r8; inc ecx; jmp .smksi_cmp
.smksi_cr:
    test r9d,r9d; jnz .smksi_next
    inc r8; cmp r8,[rip+s_end]; jae .smksi_next
    cmp byte ptr [r8],10; jne .smksi_next
    inc r8; mov r9d,1; jmp .smksi_cmp
.smksi_lf:
    test r9d,r9d; jnz .smksi_next
    inc r8; mov r9d,1; jmp .smksi_cmp
.smksi_end:
    test r9d,r9d; jz .smksi_next
    cmp r8,[rip+s_end]; jae .smksi_yes
    mov dil,[r8]; call s_is_ident_byte; test eax,eax; jnz .smksi_next
.smksi_yes:
    mov [rip+s_cur],r8
    mov rdi,r12; call s_diag_note_repair_ptr
    mov eax,1; jmp .smksi_done
.smksi_next: add r13,16; jmp .smksi_alias
.smksi_no: xor eax,eax
.smksi_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret


s_builtin_repair:
    # rdi=ASCII callable typo,rsi=len -> eax=OP_*, edx=arity, or eax=0.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .sbr_no
    lea r13,[rip+s_builtin_repair_table]; xor r14d,r14d; xor r15d,r15d
    xor r9d,r9d
.sbr_loop:
    mov rax,[r13]; test rax,rax; jz .sbr_decide
    mov rdi,rbx; mov rsi,r12; mov rdx,rax; mov ecx,dword ptr [r13+8]; call s_edit1_ascii
    test eax,eax; jz .sbr_next
    mov r14d,dword ptr [r13+12]
    mov r9d,dword ptr [r13+16]
    inc r15d
.sbr_next: add r13,24; jmp .sbr_loop
.sbr_decide:
    cmp r15d,1; jne .sbr_no
    mov rdi,rbx; call s_diag_note_repair_ptr
    mov eax,r14d; mov edx,r9d; jmp .sbr_done
.sbr_no: xor eax,eax; xor edx,edx
.sbr_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Native constant evaluation. No irrational digit table exists. First use computes
# the constant, target f64 rounding is the only truncation, and the result is cached.
s_const_pi_bits:
    cmp dword ptr [rip+s_const_pi_ready],0; je .scpi_compute
    mov rax,[rip+s_const_pi_value]; ret
.scpi_compute:
    # Chudnovsky recurrence in f64. It is intentionally stopped by bitwise
    # stabilization, not by an epsilon or decimal digit count.
    mov rax,1; cvtsi2sd xmm0,rax              # M
    mov rax,13591409; cvtsi2sd xmm1,rax       # L
    mov rax,1; cvtsi2sd xmm2,rax              # X
    mov rax,6; cvtsi2sd xmm3,rax              # K
    movapd xmm4,xmm1                          # S
    mov rax,1; cvtsi2sd xmm5,rax              # k
    xorpd xmm6,xmm6                           # previous pi
    xor ecx,ecx
.scpi_loop:
    # M *= (K^3 - 16K) / k^3
    movapd xmm7,xmm3; mulsd xmm7,xmm3; mulsd xmm7,xmm3
    movapd xmm8,xmm3; mov rax,16; cvtsi2sd xmm9,rax; mulsd xmm8,xmm9; subsd xmm7,xmm8
    movapd xmm8,xmm5; mulsd xmm8,xmm5; mulsd xmm8,xmm5
    divsd xmm7,xmm8; mulsd xmm0,xmm7
    # L += 545140134
    mov rax,545140134; cvtsi2sd xmm7,rax; addsd xmm1,xmm7
    # X *= -262537412640768000
    mov rax,-262537412640768000; cvtsi2sd xmm7,rax; mulsd xmm2,xmm7
    # S += M*L/X
    movapd xmm7,xmm0; mulsd xmm7,xmm1; divsd xmm7,xmm2; addsd xmm4,xmm7
    # pi = 426880*sqrt(10005)/S
    mov rax,10005; cvtsi2sd xmm7,rax; sqrtsd xmm7,xmm7
    mov rax,426880; cvtsi2sd xmm8,rax; mulsd xmm7,xmm8; divsd xmm7,xmm4
    movq rax,xmm7; movq rdx,xmm6; cmp rax,rdx; je .scpi_stable
    movapd xmm6,xmm7
    mov rax,12; cvtsi2sd xmm8,rax; addsd xmm3,xmm8
    mov rax,1; cvtsi2sd xmm8,rax; addsd xmm5,xmm8
    inc ecx; cmp ecx,32; jb .scpi_loop
    mov dword ptr [rip+s_error],1; xor eax,eax; ret
.scpi_stable:
    mov [rip+s_const_pi_value],rax
    mov dword ptr [rip+s_const_pi_ready],1
    ret

s_const_e_bits:
    cmp dword ptr [rip+s_const_e_ready],0; je .sce_compute
    mov rax,[rip+s_const_e_value]; ret
.sce_compute:
    # Euler's simple continued fraction. Convergents are evaluated in native
    # f64 and stop only when two consecutive values have identical f64 bits.
    xorpd xmm0,xmm0                           # h[-2]
    mov rax,1; cvtsi2sd xmm1,rax              # h[-1]
    mov rax,1; cvtsi2sd xmm2,rax              # k[-2]
    xorpd xmm3,xmm3                           # k[-1]
    xorpd xmm4,xmm4                           # previous e
    xor r10d,r10d                             # n
.sce_loop:
    test r10d,r10d; jnz .sce_after_a0
    mov eax,2; jmp .sce_have_a
.sce_after_a0:
    mov eax,r10d; xor edx,edx; mov ecx,3; div ecx
    cmp edx,2; jne .sce_a_one
    lea eax,[r10d+1]; xor edx,edx; mov ecx,3; div ecx; shl eax,1; jmp .sce_have_a
.sce_a_one: mov eax,1
.sce_have_a:
    cdqe; cvtsi2sd xmm5,rax                    # a_n
    movapd xmm6,xmm5; mulsd xmm6,xmm1; addsd xmm6,xmm0   # h
    movapd xmm7,xmm5; mulsd xmm7,xmm3; addsd xmm7,xmm2   # k
    movapd xmm8,xmm6; divsd xmm8,xmm7                         # convergent
    test r10d,r10d; jz .sce_advance
    movq rax,xmm8; movq rdx,xmm4; cmp rax,rdx; je .sce_stable
.sce_advance:
    movapd xmm4,xmm8
    movapd xmm0,xmm1; movapd xmm1,xmm6
    movapd xmm2,xmm3; movapd xmm3,xmm7
    inc r10d; cmp r10d,128; jb .sce_loop
    mov dword ptr [rip+s_error],1; xor eax,eax; ret
.sce_stable:
    mov [rip+s_const_e_value],rax
    mov dword ptr [rip+s_const_e_ready],1
    ret

s_parse_name:
    # rax=ptr, rcx=len, edx=0 success. Numeric-leading UTF-8 names and quoted
    # identifiers are first-class; no Python normalization layer is required.
    call s_skip
    mov r8,[rip+s_cur]
    cmp r8,[rip+s_end]; jae .spn_fail
    mov al,[r8]
    cmp al,'`'; je .spn_quoted
    # A run of ASCII digits is a legal numeric identifier. If it is followed by
    # another identifier byte (e.g. 123🔥输入), continue as one UTF-8 name.
    cmp al,'0'; jb .spn_ident
    cmp al,'9'; ja .spn_ident
    mov r9,r8
.spn_numloop:
    cmp r9,[rip+s_end]; jae .spn_done
    mov al,[r9]; cmp al,'0'; jb .spn_num_tail; cmp al,'9'; ja .spn_num_tail
    inc r9; jmp .spn_numloop
.spn_num_tail:
    mov rdi,r9; call s_unicode_math_token_len; test eax,eax; jnz .spn_done
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jnz .spn_loop
    jmp .spn_done
.spn_ident:
    mov dil,[r8]; call s_is_ident_byte
    test eax,eax; jz .spn_fail
    mov r9,r8
.spn_loop:
    cmp r9,[rip+s_end]; jae .spn_done
    mov rdi,r9; call s_unicode_math_token_len; test eax,eax; jnz .spn_done
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jz .spn_done
    inc r9; jmp .spn_loop
.spn_quoted:
    lea r9,[r8+1]
    mov r10,r9
.spn_qloop:
    cmp r10,[rip+s_end]; jae .spn_fail
    mov al,[r10]
    cmp al,'`'; je .spn_qdone
    cmp al,10; je .spn_fail
    cmp al,13; je .spn_fail
    cmp al,'\\'; je .spn_fail       # escaping is rejected rather than guessed
    inc r10; jmp .spn_qloop
.spn_qdone:
    lea r11,[r10+1]
    mov [rip+s_cur],r11
    mov rax,r9
    mov rcx,r10; sub rcx,r9
    xor edx,edx
    ret
.spn_done:
    mov [rip+s_cur],r9
    mov rax,r8
    mov rcx,r9
    sub rcx,r8
    xor edx,edx
    ret
.spn_fail:
    xor eax,eax; xor ecx,ecx; mov edx,1
    mov dword ptr [rip+s_error],1
    ret

s_parse_number_span:
    # unsigned number token, including 0x/0b/decimal/fraction/exponent. rax ptr rcx len edx err
    call s_skip
    mov r8,[rip+s_cur]
    mov r9,r8
    cmp r9,[rip+s_end]; jae .spns_fail
    cmp byte ptr [r9],'0'; jne .spns_dec
    lea r10,[r9+2]; cmp r10,[rip+s_end]; ja .spns_dec
    mov al,[r9+1]
    cmp al,'x'; je .spns_hex
    cmp al,'X'; je .spns_hex
    cmp al,'b'; je .spns_bin
    cmp al,'B'; je .spns_bin
.spns_dec:
    xor r10d,r10d
.spns_digs:
    cmp r9,[rip+s_end]; jae .spns_frac
    mov al,[r9]; cmp al,'0'; jb .spns_frac; cmp al,'9'; ja .spns_frac
    inc r9; inc r10d; jmp .spns_digs
.spns_frac:
    test r10d,r10d; jz .spns_fail
    cmp r9,[rip+s_end]; jae .spns_done
    cmp byte ptr [r9],'.'; jne .spns_exp
    # '..' is a range operator, not a decimal point.
    lea r10,[r9+1]; cmp r10,[rip+s_end]; jae .spns_done
    cmp byte ptr [r9+1],'.'; je .spns_done
    inc r9
    xor r10d,r10d
.spns_fdigs:
    cmp r9,[rip+s_end]; jae .spns_done
    mov al,[r9]; cmp al,'0'; jb .spns_exp2; cmp al,'9'; ja .spns_exp2
    inc r9; inc r10d; jmp .spns_fdigs
.spns_exp2:
    test r10d,r10d; jz .spns_fail
.spns_exp:
    cmp r9,[rip+s_end]; jae .spns_done
    mov al,[r9]; cmp al,'e'; je .spns_expgo; cmp al,'E'; jne .spns_done
.spns_expgo:
    inc r9
    cmp r9,[rip+s_end]; jae .spns_fail
    mov al,[r9]; cmp al,'+'; je .spns_expsign; cmp al,'-'; jne .spns_edigs0
.spns_expsign: inc r9
.spns_edigs0:
    xor r10d,r10d
.spns_edigs:
    cmp r9,[rip+s_end]; jae .spns_edone
    mov al,[r9]; cmp al,'0'; jb .spns_edone; cmp al,'9'; ja .spns_edone
    inc r9; inc r10d; jmp .spns_edigs
.spns_edone:
    test r10d,r10d; jz .spns_fail
    jmp .spns_done
.spns_hex:
    add r9,2; xor r10d,r10d
.spns_hloop:
    cmp r9,[rip+s_end]; jae .spns_basedone
    mov al,[r9]
    cmp al,'0'; jb .spns_basedone; cmp al,'9'; jbe .spns_hok
    cmp al,'A'; jb .spns_hlow; cmp al,'F'; jbe .spns_hok
.spns_hlow: cmp al,'a'; jb .spns_basedone; cmp al,'f'; ja .spns_basedone
.spns_hok: inc r9; inc r10d; jmp .spns_hloop
.spns_bin:
    add r9,2; xor r10d,r10d
.spns_bloop:
    cmp r9,[rip+s_end]; jae .spns_basedone
    mov al,[r9]; cmp al,'0'; je .spns_bok; cmp al,'1'; jne .spns_basedone
.spns_bok: inc r9; inc r10d; jmp .spns_bloop
.spns_basedone:
    test r10d,r10d; jz .spns_fail
.spns_done:
    mov [rip+s_cur],r9
    mov rax,r8; mov rcx,r9; sub rcx,r8; xor edx,edx; ret
.spns_fail:
    xor eax,eax; xor ecx,ecx; mov edx,1
    mov dword ptr [rip+s_error],1
    ret

# -----------------------------------------------------------------------------
# AST allocation/scopes
# -----------------------------------------------------------------------------
s_new_ast:
    mov rax,[rip+s_ast_cur]
    lea rcx,[rax+SAST_SIZE]
    cmp rcx,[rip+s_ast_end]
    jbe .sna_have
    call s_grow_ast_slab
    test rax,rax
    jz .sna_fail
    mov rax,[rip+s_ast_cur]
    lea rcx,[rax+SAST_SIZE]
.sna_have:
    mov [rip+s_ast_cur],rcx
    inc dword ptr [rip+s_ast_count]
    pxor xmm0,xmm0
    movdqu [rax],xmm0; movdqu [rax+16],xmm0; movdqu [rax+32],xmm0; movdqu [rax+48],xmm0
    ret
.sna_fail:
    mov dword ptr [rip+s_error],1
    xor eax,eax; ret

# Pointer-linked AST nodes use non-moving slabs.  There is no node-count cap;
# only mmap/address-space exhaustion can stop growth.
s_grow_ast_slab:
    push rbx
    mov rbx,[rip+s_ast_next_slab_bytes]
    test rbx,rbx
    jnz .sgas_size
    mov rbx,SURFACE_AST_INITIAL_BYTES
.sgas_size:
    mov eax,SYS_mmap; xor edi,edi; mov rsi,rbx; mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON; mov r8,-1; xor r9d,r9d; syscall
    test rax,rax; js .sgas_fail
    mov [rip+s_ast_cur],rax
    lea rcx,[rax+rbx]; mov [rip+s_ast_end],rcx
    mov rcx,rbx; add rcx,rcx; jc .sgas_keep
    mov [rip+s_ast_next_slab_bytes],rcx
    pop rbx; ret
.sgas_keep:
    mov [rip+s_ast_next_slab_bytes],rbx
    pop rbx; ret
.sgas_fail:
    xor eax,eax; pop rbx; ret

s_span_eq:
    # rdi ptr,rsi len,rdx ptr,rcx len -> eax bool
    cmp rsi,rcx; jne .sseq_no
    xor r8d,r8d
.sseq_loop:
    cmp r8,rcx; jae .sseq_yes
    mov al,[rdi+r8]; cmp al,[rdx+r8]; jne .sseq_no
    inc r8; jmp .sseq_loop
.sseq_yes: mov eax,1; ret
.sseq_no: xor eax,eax; ret

s_classify_ref:
    # rdi=name ptr,rsi=len -> eax NK_VAR/NK_AXIS/NK_STATE
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi
    mov ecx,dword ptr [rip+s_state_count]
    test ecx,ecx; jz .scr_axis
    dec ecx
.scr_state_loop:
    mov rax,[rip+s_state_ptrs]; mov rdi,[rax+rcx*8]
    mov rax,[rip+s_state_lens]; mov rsi,[rax+rcx*8]
    mov rdx,rbx; mov r13,rcx; mov rcx,r12; call s_span_eq
    mov rcx,r13
    test eax,eax; jnz .scr_state_yes
    test ecx,ecx; jz .scr_axis
    dec ecx; jmp .scr_state_loop
.scr_state_yes: mov eax,NK_STATE; jmp .scr_done
.scr_axis:
    mov ecx,dword ptr [rip+s_axis_count]
    test ecx,ecx; jz .scr_var
    dec ecx
.scr_axis_loop:
    mov rax,[rip+s_axis_ptrs]; mov rdi,[rax+rcx*8]
    mov rax,[rip+s_axis_lens]; mov rsi,[rax+rcx*8]
    mov rdx,rbx; mov r13,rcx; mov rcx,r12; call s_span_eq
    mov rcx,r13
    test eax,eax; jnz .scr_axis_yes
    test ecx,ecx; jz .scr_var
    dec ecx; jmp .scr_axis_loop
.scr_axis_yes: mov eax,NK_AXIS; jmp .scr_done
.scr_var: mov eax,NK_VAR
.scr_done:
    pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Expression parser
# -----------------------------------------------------------------------------
s_peek_binop:
    # eax=op code, edx=precedence, ecx=token bytes, 0 if none. Does not consume.
    mov qword ptr [rip+s_peek_repair_ptr],0
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spb_none
    mov r10b,[r8]
    # two-byte first. Never use AH here: r8 addressing requires a REX prefix.
    lea r9,[r8+1]; cmp r9,[rip+s_end]; jae .spb_one
    mov r11b,[r8+1]
    # One newline may split a multi-character operator in the human shell.
    # The repair is lexical only; canonical AST still sees one operator.
    cmp r11b,10; je .spb_split_lf
    cmp r11b,13; je .spb_split_cr
    jmp .spb_contiguous2
.spb_split_lf:
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spb_one
    mov r11b,[r9]; mov ecx,3; jmp .spb_split_eval
.spb_split_cr:
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spb_one
    cmp byte ptr [r9],10; jne .spb_one
    lea r9,[r8+3]; cmp r9,[rip+s_end]; jae .spb_one
    mov r11b,[r9]; mov ecx,4
.spb_split_eval:
    mov [rip+s_peek_repair_ptr],r8
    cmp r10b,'|'; jne .spbs1; cmp r11b,'|'; jne .spbs1; mov eax,OP_OR; mov edx,1; ret
.spbs1: cmp r10b,'&'; jne .spbs2; cmp r11b,'&'; jne .spbs2; mov eax,OP_AND; mov edx,2; ret
.spbs2: cmp r10b,'='; jne .spbs3; cmp r11b,'='; jne .spbs3; mov eax,OP_EQ; mov edx,6; ret
.spbs3: cmp r10b,'!'; jne .spbs4; cmp r11b,'='; jne .spbs4; mov eax,OP_NE; mov edx,6; ret
.spbs4: cmp r10b,'<'; jne .spbs5; cmp r11b,'='; jne .spbs4sh; mov eax,OP_LE; mov edx,7; ret
.spbs4sh: cmp r11b,'<'; jne .spbs5; mov eax,OP_SHL; mov edx,8; ret
.spbs5: cmp r10b,'>'; jne .spb_one; cmp r11b,'='; jne .spbs5sh; mov eax,OP_GE; mov edx,7; ret
.spbs5sh: cmp r11b,'>'; jne .spb_one; mov eax,OP_SHR; mov edx,8; ret
.spb_contiguous2:
    cmp r10b,'|'; jne 1f; cmp r11b,'|'; je .spb_or
1:  cmp r10b,'&'; jne 2f; cmp r11b,'&'; je .spb_and
2:  cmp r10b,'='; jne 3f; cmp r11b,'='; je .spb_eq
3:  cmp r10b,'!'; jne 4f; cmp r11b,'='; je .spb_ne
4:  cmp r10b,'<'; jne 5f; cmp r11b,'='; je .spb_le; cmp r11b,'<'; je .spb_shl
5:  cmp r10b,'>'; jne .spb_one; cmp r11b,'='; je .spb_ge; cmp r11b,'>'; je .spb_shr
.spb_one:
    mov r10b,[r8]
    # 1.3.29 handwritten-math compatibility. These UTF-8 spellings map to the
    # existing arithmetic/comparison OPs; no compatibility runtime survives.
    cmp r10b,0xC2; je .spb_utf_c2
    cmp r10b,0xC3; je .spb_utf_c3
    cmp r10b,0xE2; je .spb_utf_e2
    cmp r10b,0xEF; je .spb_utf_ef
    cmp r10b,'|'; je .spb_bitor
    cmp r10b,'&'; je .spb_bitand
    cmp r10b,'<'; je .spb_lt
    cmp r10b,'>'; je .spb_gt
    cmp r10b,'+'; je .spb_add
    cmp r10b,'-'; je .spb_sub
    cmp r10b,'*'; je .spb_mul
    cmp r10b,'/'; je .spb_div
    cmp r10b,'%'; je .spb_mod
    jmp .spb_none
# UTF-8 operator aliases. ecx is the exact source-byte length consumed.
.spb_utf_c2:
    lea r9,[r8+1]; cmp r9,[rip+s_end]; jae .spb_none
    cmp byte ptr [r9],0xB7; je .spb_mul2       # · U+00B7
    jmp .spb_none
.spb_utf_c3:
    lea r9,[r8+1]; cmp r9,[rip+s_end]; jae .spb_none
    cmp byte ptr [r9],0x97; je .spb_mul2       # × U+00D7
    cmp byte ptr [r9],0xB7; je .spb_div2       # ÷ U+00F7
    jmp .spb_none
.spb_utf_e2:
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spb_none
    cmp byte ptr [r8+1],0x81; jne 0f
    cmp byte ptr [r8+2],0x84; je .spb_div3     # ⁄ U+2044
0:  cmp byte ptr [r8+1],0x8B; jne 1f
    cmp byte ptr [r8+2],0x85; je .spb_mul3     # ⋅ U+22C5
1:  cmp byte ptr [r8+1],0x88; jne 2f
    cmp byte ptr [r8+2],0x99; je .spb_mul3     # ∙ U+2219
    cmp byte ptr [r8+2],0x95; je .spb_div3     # ∕ U+2215
    cmp byte ptr [r8+2],0x97; je .spb_mul3     # ∗ U+2217
    cmp byte ptr [r8+2],0x92; je .spb_sub3     # − U+2212
    cmp byte ptr [r8+2],0xA7; je .spb_and3     # ∧ U+2227
    cmp byte ptr [r8+2],0xA8; je .spb_or3      # ∨ U+2228
2:  cmp byte ptr [r8+1],0x89; jne .spb_none
    cmp byte ptr [r8+2],0xA4; je .spb_le3      # ≤ U+2264
    cmp byte ptr [r8+2],0xA5; je .spb_ge3      # ≥ U+2265
    cmp byte ptr [r8+2],0xA0; je .spb_ne3      # ≠ U+2260
    jmp .spb_none
.spb_utf_ef:
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spb_none
    cmp byte ptr [r8+1],0xBC; jne .spb_none
    cmp byte ptr [r8+2],0x8B; je .spb_add3     # ＋ U+FF0B
    cmp byte ptr [r8+2],0x8D; je .spb_sub3     # － U+FF0D
    cmp byte ptr [r8+2],0x8A; je .spb_mul3     # ＊ U+FF0A
    cmp byte ptr [r8+2],0x8F; je .spb_div3     # ／ U+FF0F
    jmp .spb_none
.spb_mul2: mov eax,OP_MUL; mov edx,10; mov ecx,2; ret
.spb_div2: mov eax,OP_DIV; mov edx,10; mov ecx,2; ret
.spb_add3: mov eax,OP_ADD; mov edx,9;  mov ecx,3; ret
.spb_sub3: mov eax,OP_SUB; mov edx,9;  mov ecx,3; ret
.spb_mul3: mov eax,OP_MUL; mov edx,10; mov ecx,3; ret
.spb_div3: mov eax,OP_DIV; mov edx,10; mov ecx,3; ret
.spb_le3:  mov eax,OP_LE;  mov edx,7;  mov ecx,3; ret
.spb_ge3:  mov eax,OP_GE;  mov edx,7;  mov ecx,3; ret
.spb_ne3:  mov eax,OP_NE;  mov edx,6;  mov ecx,3; ret
.spb_and3: mov eax,OP_AND; mov edx,2; mov ecx,3; ret
.spb_or3:  mov eax,OP_OR;  mov edx,1; mov ecx,3; ret

.spb_or: mov eax,OP_OR; mov edx,1; mov ecx,2; ret
.spb_and: mov eax,OP_AND; mov edx,2; mov ecx,2; ret
.spb_bitor: mov eax,OP_BIT_OR; mov edx,3; mov ecx,1; ret
.spb_bitxor: mov eax,OP_BIT_XOR; mov edx,4; mov ecx,1; ret
.spb_bitand: mov eax,OP_BIT_AND; mov edx,5; mov ecx,1; ret
.spb_eq: mov eax,OP_EQ; mov edx,6; mov ecx,2; ret
.spb_ne: mov eax,OP_NE; mov edx,6; mov ecx,2; ret
.spb_lt: mov eax,OP_LT; mov edx,7; mov ecx,1; ret
.spb_le: mov eax,OP_LE; mov edx,7; mov ecx,2; ret
.spb_gt: mov eax,OP_GT; mov edx,7; mov ecx,1; ret
.spb_ge: mov eax,OP_GE; mov edx,7; mov ecx,2; ret
.spb_shl: mov eax,OP_SHL; mov edx,8; mov ecx,2; ret
.spb_shr: mov eax,OP_SHR; mov edx,8; mov ecx,2; ret
.spb_add: mov eax,OP_ADD; mov edx,9; mov ecx,1; ret
.spb_sub: mov eax,OP_SUB; mov edx,9; mov ecx,1; ret
.spb_mul: mov eax,OP_MUL; mov edx,10; mov ecx,1; ret
.spb_div: mov eax,OP_DIV; mov edx,10; mov ecx,1; ret
.spb_mod: mov eax,OP_MOD; mov edx,10; mov ecx,1; ret
.spb_none: xor eax,eax; xor edx,edx; xor ecx,ecx; ret

s_parse_expr:
    # edi=min precedence -> rax AST/0
    push rbx; push r12; push r13; push r14; push r15
    mov r15d,edi
    call s_parse_unary
    test rax,rax; jz .spe_fail
    mov r12,rax
.spe_loop:
    call s_peek_binop
    test eax,eax; jz .spe_ok
    cmp edx,r15d; jb .spe_ok
    mov r13d,eax; mov r14d,edx
    cmp ecx,2; jbe .spe_consume
    mov rdi,[rip+s_peek_repair_ptr]; test rdi,rdi; jz .spe_consume
    call s_diag_note_repair_ptr
.spe_consume:
    add qword ptr [rip+s_cur],rcx
    lea edi,[r14d+1]
    call s_parse_expr
    test rax,rax; jz .spe_fail
    mov rbx,rax
    mov edi,r13d; mov rsi,r12; mov rdx,rbx; call s_ast_binary_new
    test rax,rax; jz .spe_fail
    mov r12,rax
    jmp .spe_loop
.spe_ok: mov rax,r12; jmp .spe_done
.spe_fail: xor eax,eax
.spe_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Power is right-associative and binds more tightly than unary minus. The
# handwritten spellings ^ and ** vanish here into the existing multiply DAG.
s_parse_power:
    push rbx; push r12
    call s_parse_postfix
    test rax,rax; jz .sppow_fail
    mov r12,rax
    call s_match_power_token
    test eax,eax; jz .sppow_base
    call s_parse_unary
    test rax,rax; jz .sppow_fail
    mov rdi,r12; mov rsi,rax; call s_expand_pow_ast
    test rax,rax; jz .sppow_fail
    jmp .sppow_done
.sppow_base: mov rax,r12; jmp .sppow_done
.sppow_fail: xor eax,eax
.sppow_done: pop r12; pop rbx; ret

# eax=1 and consumes ^, **, or fullwidth ＾; otherwise eax=0.
s_match_power_token:
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .smpt_no
    cmp byte ptr [r8],'^'; je .smpt_one
    cmp byte ptr [r8],'*'; jne .smpt_full
    lea r9,[r8+1]; cmp r9,[rip+s_end]; jae .smpt_no
    cmp byte ptr [r9],'*'; jne .smpt_no
    add r8,2; mov [rip+s_cur],r8; mov eax,1; ret
.smpt_one: inc r8; mov [rip+s_cur],r8; mov eax,1; ret
.smpt_full:
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .smpt_no
    cmp byte ptr [r8],0xEF; jne .smpt_no
    cmp byte ptr [r8+1],0xBC; jne .smpt_no
    cmp byte ptr [r8+2],0xBE; jne .smpt_no   # ＾ U+FF3E
    add r8,3; mov [rip+s_cur],r8; mov eax,1; ret
.smpt_no: xor eax,eax; ret

s_parse_unary:
    push rbx
    # Handwritten unary aliases disappear into the existing unary OPs.
    lea rdi,[rip+tok_sqrt_math]; mov esi,3; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_sqrt
    lea rdi,[rip+tok_not_math]; mov esi,2; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_not
    lea rdi,[rip+tok_bang]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_not
    lea rdi,[rip+tok_tilde]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_bitnot
    lea rdi,[rip+tok_minus]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_neg
    lea rdi,[rip+tok_minus_math]; mov esi,3; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_neg
    call s_parse_power
    pop rbx; ret
.spu_sqrt: mov ebx,OP_SQRT; jmp .spu_make
.spu_not: mov ebx,OP_NOT; jmp .spu_make
.spu_bitnot: mov ebx,OP_BIT_NOT; jmp .spu_make
.spu_neg: mov ebx,OP_NEG
.spu_make:
    call s_parse_unary
    test rax,rax; jz .spu_fail
    # Canonical negative numeric literals stay literals. Do not manufacture an
    # extra runtime negation node merely because the human surface used '-'.
    cmp ebx,OP_NEG; jne .spu_make_node
    cmp dword ptr [rax+SN_KIND],NK_NUM; jne .spu_make_node
    cmp qword ptr [rax+SN_AUX],0; jne .spu_make_node
    mov qword ptr [rax+SN_AUX],1
    pop rbx; ret
.spu_make_node:
    push rax
    call s_new_ast
    pop rcx
    test rax,rax; jz .spu_fail
    mov dword ptr [rax+SN_KIND],NK_UNARY
    mov dword ptr [rax+SN_OP],ebx
    mov [rax+SN_A],rcx
    pop rbx; ret
.spu_fail: xor eax,eax; pop rbx; ret

s_parse_postfix:
    push rbx; push r12; push r13
    call s_parse_primary
    test rax,rax; jz .spp_fail
    mov r12,rax
.spp_loop:
    lea rdi,[rip+tok_sup2]; mov esi,2; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_pow2
    lea rdi,[rip+tok_sup3]; mov esi,2; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_pow3
    lea rdi,[rip+tok_dot]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_field
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spp_done
    cmp dword ptr [r12+SN_KIND],NK_VAR
    jne .spp_fail
    xor r13d,r13d
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_index_done
.spp_index_loop:
    xor edi,edi; call s_parse_expr
    test rax,rax; jz .spp_fail
    mov qword ptr [rax+SN_NEXT],0
    test r13,r13; jz .spp_first_idx
    mov [rbx+SN_NEXT],rax; jmp .spp_idx_linked
.spp_first_idx: mov r13,rax
.spp_idx_linked: mov rbx,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_index_loop
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spp_fail
.spp_index_done:
    call s_new_ast
    test rax,rax; jz .spp_fail
    mov dword ptr [rax+SN_KIND],NK_LOAD
    mov rcx,[r12+SN_PTR]; mov [rax+SN_PTR],rcx
    mov rcx,[r12+SN_LEN]; mov [rax+SN_LEN],rcx
    mov [rax+SN_A],r13
    mov r12,rax
    jmp .spp_loop
.spp_field:
    cmp dword ptr [r12+SN_KIND],NK_VAR; jne .spp_fail
    call s_parse_name; test edx,edx; jnz .spp_fail
    mov rdx,rax; mov rcx,rcx
    mov rdi,[r12+SN_PTR]; mov rsi,[r12+SN_LEN]; call s_record_lookup
    test rax,rax; jz .spp_fail
    mov r12,rax; jmp .spp_loop
.spp_pow2:
    mov rdi,r12; mov esi,2; call s_expand_pow_u64; test rax,rax; jz .spp_fail
    mov r12,rax; jmp .spp_loop
.spp_pow3:
    mov rdi,r12; mov esi,3; call s_expand_pow_u64; test rax,rax; jz .spp_fail
    mov r12,rax; jmp .spp_loop
.spp_done: mov rax,r12; jmp .spp_exit
.spp_fail: xor eax,eax
.spp_exit: pop r13; pop r12; pop rbx; ret

# Parse function name helpers by exact ASCII identifier spans.
s_parse_primary:
    push rbx; push r12; push r13; push r14; push r15
    call s_skip
    mov r8,[rip+s_cur]
    cmp r8,[rip+s_end]; jae .sppp_fail
    mov al,[r8]
    cmp al,'('; je .sppp_group
    cmp al,'"'; je .sppp_string
    cmp al,'0'; jb .sppp_word
    cmp al,'9'; jbe .sppp_number
.sppp_word:
    xor r15d,r15d
    cmp byte ptr [r8],'`'; sete r15b
    call s_parse_name
    test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    # WH structural if cond { yes } else { no } is a dataflow select, never
    # permission to emit a runtime branch object.
    mov rdi,r12; mov rsi,r13; mov edx,KID_IF; call s_span_kw_id
    test eax,eax; jnz .sppp_if
    # true/false
    mov rdi,r12; mov rsi,r13; mov edx,KID_TRUE; call s_span_kw_id
    test eax,eax; jnz .sppp_true
    mov rdi,r12; mov rsi,r13; mov edx,KID_FALSE; call s_span_kw_id
    test eax,eax; jnz .sppp_false
    # Existing lexical identities outrank mathematical constants. This keeps
    # old structural code such as `e in n` valid: a bound axis/state/declaration
    # named e is that binding; only an otherwise-unbound bare e denotes Euler's
    # constant. The rule is structural and applies before any typo repair.
    mov rdi,r12; mov rsi,r13; call s_classify_ref
    cmp eax,NK_AXIS; je .sppp_scoped_ref
    cmp eax,NK_STATE; je .sppp_scoped_ref
    mov rdi,r12; mov rsi,r13; call s_decl_lookup_exact
    test eax,eax; js .sppp_maybe_math_const
    # A structured let-binding outranks ordinary scalar reference formation.
    mov rdi,r12; mov rsi,r13; call s_struct_decl_lookup; test rax,rax; jnz .sppp_done
    jmp .sppp_not_math_const
.sppp_maybe_math_const:
    # Native irrational constants are reserved only when unquoted and unbound.
    # Their exact target f64 bit pattern is computed on first use by old, fast
    # convergence methods and then interned as an ordinary immediate ValueFact.
    test r15d,r15d; jnz .sppp_not_math_const
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_pi]; mov ecx,2; call s_span_eq
    test eax,eax; jnz .sppp_const_pi
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_pi_utf8]; mov ecx,2; call s_span_eq
    test eax,eax; jnz .sppp_const_pi
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_e]; mov ecx,1; call s_span_eq
    test eax,eax; jnz .sppp_const_e
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_e_script]; mov ecx,3; call s_span_eq
    test eax,eax; jnz .sppp_const_e
.sppp_not_math_const:
    # Lexical repair must never rewrite an exact axis/state identity.  Axis names
    # are intentionally short (i/j/k/...), so edit-distance repair against
    # ordinary declarations would otherwise fabricate ambiguity or silently turn
    # an axis into a tensor/variable name.  Scope identity therefore outranks the
    # optional human-shell typo repair.
    mov rdi,r12; mov rsi,r13; call s_classify_ref
    cmp eax,NK_AXIS; je .sppp_scoped_ref
    cmp eax,NK_STATE; je .sppp_scoped_ref
    # Exact function identity outranks declaration typo repair.  This matters for
    # mathematical one-letter names such as f/r: edit-distance repair must not
    # rewrite an exact callable to a nearby input name before call lookahead.
    mov rdi,r12; mov rsi,r13; call s_function_lookup
    cmp eax,-1; jne .sppp_exact_function_name
    # Resolve declared-name typo/newline repair before any lookahead can consume
    # the separating newline. Non-declared function names are left unchanged.
    mov rdi,r12; mov rsi,r13; call s_try_decl_repair
    mov r12,rax; mov r13,rcx
    cmp dword ptr [rip+s_error],0; jne .sppp_fail
.sppp_exact_function_name:
    # Function call?
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sppp_call
    # bare ref. Any conservative declared-name repair has already happened
    # before lookahead, so whitespace/newline state cannot hide it.
    mov rdi,r12; mov rsi,r13; call s_classify_ref
    mov ebx,eax
    jmp .sppp_make_ref
.sppp_scoped_ref:
    mov ebx,eax
.sppp_make_ref:
    call s_new_ast
    test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],ebx
    mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    jmp .sppp_done
.sppp_const_pi:
    call s_const_pi_bits
    cmp dword ptr [rip+s_error],0; jne .sppp_fail
    mov rdi,rax; call s_ast_f64_bits_imm; test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_const_e:
    call s_const_e_bits
    cmp dword ptr [rip+s_error],0; jne .sppp_fail
    mov rdi,rax; call s_ast_f64_bits_imm; test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_if:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r13,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    mov edi,KID_ELSE; call s_expect_kw_id
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r15,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],OP_SELECT
    mov [rax+SN_A],r12; mov [rax+SN_B],r13; mov [rax+SN_C],r15
    jmp .sppp_done
.sppp_true: mov ebx,1; jmp .sppp_bool
.sppp_false: xor ebx,ebx
.sppp_bool:
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_BOOL; mov dword ptr [rax+SN_AUX],ebx
    jmp .sppp_done
.sppp_number:
    # A digit-leading UTF-8 identifier (e.g. 123🔥输入) is a name, not a
    # numeric literal. Scan only the initial decimal run to disambiguate.
    mov r9,[rip+s_cur]
.sppp_num_probe:
    cmp r9,[rip+s_end]; jae .sppp_number_real
    mov al,[r9]; cmp al,'0'; jb .sppp_num_tail; cmp al,'9'; ja .sppp_num_tail
    inc r9; jmp .sppp_num_probe
.sppp_num_tail:
    # `e`/`E` after a digit run is numeric only when it opens a syntactically
    # complete decimal exponent.  This preserves digit-leading UTF identifiers
    # while making 1e-13 and 1E+6 the same numeric family as 1.0e-13.
    mov al,[r9]
    cmp al,'e'; je .sppp_num_exp_probe
    cmp al,'E'; je .sppp_num_exp_probe
.sppp_num_ident_probe:
    mov rdi,r9; call s_unicode_math_token_len; test eax,eax; jnz .sppp_number_real
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jnz .sppp_word
    jmp .sppp_number_real
.sppp_num_exp_probe:
    lea r10,[r9+1]
    cmp r10,[rip+s_end]; jae .sppp_num_ident_probe
    mov al,[r10]
    cmp al,'+'; je .sppp_num_exp_after_sign
    cmp al,'-'; jne .sppp_num_exp_digit
.sppp_num_exp_after_sign:
    inc r10
    cmp r10,[rip+s_end]; jae .sppp_num_ident_probe
    mov al,[r10]
.sppp_num_exp_digit:
    cmp al,'0'; jb .sppp_num_ident_probe
    cmp al,'9'; ja .sppp_num_ident_probe
.sppp_number_real:
    call s_parse_number_span
    test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_NUM; mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    jmp .sppp_done
.sppp_string:
    mov r12,r8
    inc r8
.sppp_str_loop:
    cmp r8,[rip+s_end]; jae .sppp_fail
    mov al,[r8]
    cmp al,'\\'; je .sppp_str_escape
    cmp al,'"'; je .sppp_str_close
    cmp al,10; je .sppp_fail
    inc r8; jmp .sppp_str_loop
.sppp_str_escape:
    add r8,2; jmp .sppp_str_loop
.sppp_str_close:
    inc r8
    mov [rip+s_cur],r8
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_STRING
    lea rcx,[r12+1]; mov [rax+SN_PTR],rcx
    mov rcx,r8; sub rcx,r12; sub rcx,2; mov [rax+SN_LEN],rcx
    jmp .sppp_done
.sppp_group:
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr
    mov r12,rax
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov rax,r12
    jmp .sppp_done
.sppp_call:
    # Unified Semantic Parse Authority.  Special mathematical syntax is table
    # driven just like ordinary Semantic Registry calls.  Adding a new alias or
    # moving an operation between structural families edits data, not parser
    # control flow.  The target family still erases into the existing AST/Rank-N.
    mov rdi,r12; mov rsi,r13; call s_semantic_parse_lookup
    test eax,eax; jz .sppp_nonsemantic_call
    cmp eax,MSC_LAST; ja .sppp_fail
    lea rdx,[rip+s_semantic_parse_jump_table]
    jmp qword ptr [rdx+rax*8]
.sppp_nonsemantic_call:
    # cast(type,expr)
    mov rdi,r12; mov rsi,r13; mov edx,KID_CAST; call s_span_kw_id
    test eax,eax; jnz .sppp_cast
    mov rdi,r12; mov rsi,r13; mov edx,KID_GOAL_RESULT; call s_span_kw_id
    test eax,eax; jnz .sppp_goal_result
    # Exact Semantic Registry identity outranks one-edit repair of shorter
    # core callables (for example cabs must never collapse to abs).  Repair is
    # still available only after every exact mathematical identity has lost.
    mov rdi,r12; mov rsi,r13; call s_math_builtin_lookup
    test eax,eax; jz .sppp_no_exact_native_math
    mov ebx,eax; mov r14d,edx; jmp .sppp_math_call_args
.sppp_no_exact_native_math:
    # Determine supported function opcode/arity. periodic(x,n) is the
    # canonical ring normalization mod(x,n), not a runtime helper.
    xor ebx,ebx; xor r14d,r14d
    mov rdi,r12; mov rsi,r13; mov edx,KID_PERIODIC; call s_span_kw_id
    test eax,eax; jz 0f; mov ebx,OP_MOD; mov r14d,2; jmp .sppp_call_args
0:  mov rdi,r12; mov rsi,r13; mov edx,KID_SELECT; call s_span_kw_id
    test eax,eax; jz 1f; mov ebx,OP_SELECT; mov r14d,3; jmp .sppp_call_args
1:  mov rdi,r12; mov rsi,r13; mov edx,KID_MIN; call s_span_kw_id
    test eax,eax; jz 2f; mov ebx,OP_MIN; mov r14d,2; jmp .sppp_call_args
2:  mov rdi,r12; mov rsi,r13; mov edx,KID_MAX; call s_span_kw_id
    test eax,eax; jz 3f; mov ebx,OP_MAX; mov r14d,2; jmp .sppp_call_args
3:  mov rdi,r12; mov rsi,r13; mov edx,KID_ABS; call s_span_kw_id
    test eax,eax; jz .sppp_try_sqrt; mov ebx,OP_ABS; mov r14d,1; jmp .sppp_call_args
.sppp_try_sqrt:
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_sqrt]; mov ecx,4; call s_span_eq
    test eax,eax; jz .sppp_try_trunc; mov ebx,OP_SQRT; mov r14d,1; jmp .sppp_call_args
.sppp_try_trunc:
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_trunc]; mov ecx,5; call s_span_eq
    test eax,eax; jz .sppp_try_native_math; mov ebx,OP_TRUNC; mov r14d,1; jmp .sppp_call_args
.sppp_try_native_math:
    # Large mathematical vocabulary, one compile-time expansion authority.
    # eax=id, edx=arity; no mathematical runtime/backend survives this call.
    mov dword ptr [rip+surface_debug_stage],300
    mov rdi,r12; mov rsi,r13; call s_math_builtin_lookup
    test eax,eax; jz 4f
    mov dword ptr [rip+surface_debug_stage],301
    mov ebx,eax; mov r14d,edx; jmp .sppp_math_call_args
4:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_xor]; mov ecx,3; call s_span_eq
    test eax,eax; jz 5f; mov ebx,OP_BIT_XOR; mov r14d,2; jmp .sppp_call_args
5:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_bit_and]; mov ecx,7; call s_span_eq
    test eax,eax; jz 6f; mov ebx,OP_BIT_AND; mov r14d,2; jmp .sppp_call_args
6:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_bit_or]; mov ecx,6; call s_span_eq
    test eax,eax; jz 7f; mov ebx,OP_BIT_OR; mov r14d,2; jmp .sppp_call_args
7:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_bit_xor]; mov ecx,7; call s_span_eq
    test eax,eax; jz 8f; mov ebx,OP_BIT_XOR; mov r14d,2; jmp .sppp_call_args
8:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_shl]; mov ecx,3; call s_span_eq
    test eax,eax; jz 9f; mov ebx,OP_SHL; mov r14d,2; jmp .sppp_call_args
9:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_shr]; mov ecx,3; call s_span_eq
    test eax,eax; jnz .sppp_shr_builtin
    # Built-in English callables use the same unique one-edit repair rule.
    mov rdi,r12; mov rsi,r13; call s_builtin_repair
    test eax,eax; jz .sppp_pure_lookup
    mov ebx,eax; mov r14d,edx; jmp .sppp_call_args
.sppp_pure_lookup:
    # Compile-time pure function expansion. Parameter count is a lexical fact,
    # not a one-argument Surface tier; every argument disappears through the
    # same substitution authority before canonical emission.
    mov rdi,r12; mov rsi,r13; call s_function_lookup
    cmp eax,-1; je .sppp_fail
    mov ebx,eax
    mov rdx,[rip+s_function_param_count]; mov r14d,[rdx+rbx*4]
    xor r15d,r15d
    test r14d,r14d; jz .sppp_pure_args_done
.sppp_pure_arg_loop:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail
    mov rdx,[rip+s_math_call_args]; mov [rdx+r15*8],rax
    inc r15d
    cmp r15d,r14d; jae .sppp_pure_args_done
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sppp_fail
    jmp .sppp_pure_arg_loop
.sppp_pure_args_done:
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sppp_fail
    mov rdx,[rip+s_function_expr_ast]; mov rdi,[rdx+rbx*8]
    test rdi,rdi; jz .sppp_recursive_self_call
    cmp dword ptr [rdi+SN_KIND],NK_RECUR_DEF; je .sppp_recursive_apply
    mov rdx,[rip+s_function_param_offset]; mov esi,[rdx+rbx*4]
    mov edx,r14d
    call s_clone_subst_pure_multi
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_recursive_self_call:
    cmp ebx,dword ptr [rip+s_pure_function_index]; jne .sppp_fail
    mov edi,r14d; call s_build_call_arg_chain; test rax,rax; jz .sppp_fail
    mov r12,rax
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_RECUR_CALL
    mov [rax+SN_A],r12; mov dword ptr [rax+SN_AUX],ebx
    jmp .sppp_done
.sppp_recursive_apply:
    mov edi,r14d; call s_build_call_arg_chain; test rax,rax; jz .sppp_fail
    mov r12,rax
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_RECUR_APPLY
    mov [rax+SN_A],r12; mov dword ptr [rax+SN_AUX],ebx
    jmp .sppp_done
.sppp_static_sum:
    mov edi,1; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_static_product_sum:
    mov edi,2; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done

.sppp_static_sqnorm:
    mov edi,3; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_static_norm:
    mov edi,3; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_static_sqdistance:
    mov edi,4; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_static_distance:
    mov edi,4; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_static_mean:
    mov edi,1; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    mov r12,rax; mov rdi,rdx; call s_math_small_u64_f64
    mov edi,OP_DIV; mov rsi,r12; mov rdx,rax; call s_ast_binary_new
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_static_rms:
    mov edi,3; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    mov r12,rax; mov rdi,rdx; call s_math_small_u64_f64
    mov edi,OP_DIV; mov rsi,r12; mov rdx,rax; call s_ast_binary_new
    mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_static_variance:
    mov edi,5; call s_parse_static_axis_reduce_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done

.sppp_derivative:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppp_fail; mov r13,rax; mov r14,rcx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_ast_diff
    test rax,rax; jz .sppp_fail
    jmp .sppp_done

.sppp_second_derivative:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppp_fail; mov r13,rax; mov r14,rcx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_ast_diff; test rax,rax; jz .sppp_fail
    mov rdi,rax; mov rsi,r13; mov rdx,r14; call s_ast_diff; test rax,rax; jz .sppp_fail
    jmp .sppp_done

.sppp_hessian_component:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppp_fail; mov r13,rax; mov r14,rcx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppp_fail; mov r15,rax
    sub rsp,8; mov [rsp],rcx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_ast_diff; test rax,rax; jz .sppp_hessian_fail
    mov rdi,rax; mov rsi,r15; mov rdx,[rsp]; call s_ast_diff
    add rsp,8; test rax,rax; jz .sppp_fail; jmp .sppp_done
.sppp_hessian_fail:
    add rsp,8; jmp .sppp_fail

.sppp_laplacian2:
    # laplacian(expr,x,y): d2/dx2 + d2/dy2. Higher-dimensional fields compose
    # the same primitive explicitly, keeping one differentiation authority.
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppp_fail; mov r13,rax; mov r14,rcx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppp_fail; mov r15,rax
    sub rsp,16; mov [rsp],rcx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_ast_diff; test rax,rax; jz .sppp_lap_fail
    mov rdi,rax; mov rsi,r13; mov rdx,r14; call s_ast_diff; test rax,rax; jz .sppp_lap_fail
    mov [rsp+8],rax
    mov rdi,r12; mov rsi,r15; mov rdx,[rsp]; call s_ast_diff; test rax,rax; jz .sppp_lap_fail
    mov rdi,rax; mov rsi,r15; mov rdx,[rsp]; call s_ast_diff; test rax,rax; jz .sppp_lap_fail
    mov rdx,rax; mov rsi,[rsp+8]; mov edi,OP_ADD; call s_ast_binary_new
    add rsp,16; test rax,rax; jz .sppp_fail; jmp .sppp_done
.sppp_lap_fail:
    add rsp,16; jmp .sppp_fail

.sppp_integral:
    call s_parse_integral_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done

.sppp_root:
    call s_parse_root_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done

.sppp_matrix_relation:
    call s_parse_matrix_relation_call
    test rax,rax; jz .sppp_fail
    jmp .sppp_done

.sppp_math_call_args:
    # Semantic Registry owns the required arity.  Advanced iterative semantics
    # may additionally accept one final AOT-static iteration count.  Omission
    # preserves the historical default; presence is ordinary user data and is
    # consumed by the same old compile-time expansion loop.
    #
    # Arguments live in this parser frame so a nested mathematical call cannot
    # overwrite an outer call's operands.  Immediately before dispatch the frame
    # is mirrored into the shared vector; no runtime solver/configuration object
    # survives.
    mov dword ptr [rip+surface_debug_stage],302
    cmp r14d,1; jb .sppp_fail
    cmp r14d,dword ptr [rip+s_fact_cap]; ja .sppp_fail
    mov edi,ebx; call s_math_semantic_flags_by_id
    mov r12d,eax                         # registry flags survive nested parsing
    mov r13,r14
    test r12d,MSF_OPTIONAL_ITER; jz .sppp_math_alloc_count_ready
    inc r13                              # one possible optional AST slot
.sppp_math_alloc_count_ready:
    shl r13,3
    add r13,15
    and r13,-16
    sub rsp,r13
    xor r15d,r15d
.sppp_math_arg_loop:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_math_local_fail
    mov [rsp+r15*8],rax
    inc r15d
    cmp r15d,r14d; jae .sppp_math_optional_iter
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sppp_math_local_fail
    jmp .sppp_math_arg_loop
.sppp_math_optional_iter:
    test r12d,MSF_OPTIONAL_ITER; jz .sppp_math_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .sppp_math_close
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_math_local_fail
    # Keep the value as an AST fact.  The common iteration authority validates
    # that it is AOT-static when the semantic consumes it.
    mov [rsp+r15*8],rax
    inc r15d
.sppp_math_close:
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sppp_math_local_fail
    mov dword ptr [rip+surface_debug_stage],303
    mov r12d,r15d                        # actual argc, required or required+1
    mov dword ptr [rip+s_math_call_argc],r12d
    xor r15d,r15d
    mov r10,[rip+s_math_call_args]
.sppp_math_publish_args:
    cmp r15d,r12d; jae .sppp_math_dispatch
    mov rax,[rsp+r15*8]; mov [r10+r15*8],rax
    inc r15d; jmp .sppp_math_publish_args
.sppp_math_dispatch:
    mov edi,ebx; mov rsi,[rsp]; mov rdx,[rsp+8]; mov rcx,[rsp+16]; mov r8,[rsp+24]
    call s_expand_math_builtin
    mov r11,rax
    add rsp,r13
    mov dword ptr [rip+surface_debug_stage],304
    mov rax,r11; test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_math_local_fail:
    add rsp,r13
    jmp .sppp_fail

.sppp_goal_result:
    # Closed-cascade dependency reference. It is a compile-time-only AST kind
    # and is never serialised into the runtime graph.
    call s_parse_name; test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_GOAL_RESULT
    mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    jmp .sppp_done
.sppp_shr_builtin:
    mov ebx,OP_SHR; mov r14d,2
.sppp_call_args:
    # Every operand carrier is initialized before parsing.  Unary calls must not
    # leak parser scratch (historically the callee-name length in r13) into an
    # unused AST child.  All later pure-function cloning may therefore traverse
    # A/B/C without encountering non-AST garbage.
    xor r12d,r12d
    xor r13d,r13d
    xor r15d,r15d
    # up to three args in stack locals via registers r12/r13/r15.
    cmp r14d,0; je .sppp_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    cmp r14d,1; je .sppp_call_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r13,rax
    cmp r14d,2; je .sppp_call_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r15,rax
.sppp_call_close:
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY
    cmp r14d,1; jne .sppp_call_kind_ready
    mov dword ptr [rax+SN_KIND],NK_UNARY
.sppp_call_kind_ready:
    mov dword ptr [rax+SN_OP],ebx
    mov [rax+SN_A],r12; mov [rax+SN_B],r13; mov [rax+SN_C],r15
    jmp .sppp_done
.sppp_pow:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r13,rax
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov rdi,r12; mov rsi,r13; call s_expand_pow_ast
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_cast:
    call s_parse_name
    test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail
    mov r14,rax
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_CAST
    mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13; mov [rax+SN_A],r14
    jmp .sppp_done
.sppp_fail:
    mov dword ptr [rip+s_error],1
    xor eax,eax
.sppp_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# AST serializer and ShapeFact-N expression transform helpers
# -----------------------------------------------------------------------------
s_op_name:
    # edi op -> rax ptr, ecx len
    lea rax,[rip+op_or]; mov ecx,2; cmp edi,OP_OR; je .son_ret
    lea rax,[rip+op_and]; mov ecx,3; cmp edi,OP_AND; je .son_ret
    lea rax,[rip+op_bit_or]; mov ecx,6; cmp edi,OP_BIT_OR; je .son_ret
    lea rax,[rip+op_bit_xor]; mov ecx,7; cmp edi,OP_BIT_XOR; je .son_ret
    lea rax,[rip+op_bit_and]; mov ecx,7; cmp edi,OP_BIT_AND; je .son_ret
    lea rax,[rip+op_eq]; mov ecx,2; cmp edi,OP_EQ; je .son_ret
    lea rax,[rip+op_ne]; mov ecx,2; cmp edi,OP_NE; je .son_ret
    lea rax,[rip+op_lt]; mov ecx,2; cmp edi,OP_LT; je .son_ret
    lea rax,[rip+op_le]; mov ecx,2; cmp edi,OP_LE; je .son_ret
    lea rax,[rip+op_gt]; mov ecx,2; cmp edi,OP_GT; je .son_ret
    lea rax,[rip+op_ge]; mov ecx,2; cmp edi,OP_GE; je .son_ret
    lea rax,[rip+op_shl]; mov ecx,3; cmp edi,OP_SHL; je .son_ret
    lea rax,[rip+op_shr]; mov ecx,3; cmp edi,OP_SHR; je .son_ret
    lea rax,[rip+op_add]; mov ecx,3; cmp edi,OP_ADD; je .son_ret
    lea rax,[rip+op_sub]; mov ecx,3; cmp edi,OP_SUB; je .son_ret
    lea rax,[rip+op_mul]; mov ecx,3; cmp edi,OP_MUL; je .son_ret
    lea rax,[rip+op_div]; mov ecx,3; cmp edi,OP_DIV; je .son_ret
    lea rax,[rip+op_mod]; mov ecx,3; cmp edi,OP_MOD; je .son_ret
    lea rax,[rip+op_not]; mov ecx,3; cmp edi,OP_NOT; je .son_ret
    lea rax,[rip+op_bit_not]; mov ecx,7; cmp edi,OP_BIT_NOT; je .son_ret
    lea rax,[rip+op_neg]; mov ecx,3; cmp edi,OP_NEG; je .son_ret
    lea rax,[rip+op_select]; mov ecx,6; cmp edi,OP_SELECT; je .son_ret
    lea rax,[rip+op_min]; mov ecx,3; cmp edi,OP_MIN; je .son_ret
    lea rax,[rip+op_max]; mov ecx,3; cmp edi,OP_MAX; je .son_ret
    lea rax,[rip+op_abs]; mov ecx,3; cmp edi,OP_ABS; je .son_ret
    lea rax,[rip+op_sqrt]; mov ecx,4; cmp edi,OP_SQRT; je .son_ret
    lea rax,[rip+op_trunc]; mov ecx,5; cmp edi,OP_TRUNC; je .son_ret
    lea rax,[rip+op_square]; mov ecx,6; cmp edi,OP_SQUARE; je .son_ret
    lea rax,[rip+op_exp]; mov ecx,3; cmp edi,OP_EXP; je .son_ret
    lea rax,[rip+op_log]; mov ecx,3; cmp edi,OP_LOG; je .son_ret
    lea rax,[rip+op_sin]; mov ecx,3; cmp edi,OP_SIN; je .son_ret
    lea rax,[rip+op_cos]; mov ecx,3; cmp edi,OP_COS; je .son_ret
    lea rax,[rip+op_ushr]; mov ecx,4; cmp edi,OP_USHR; je .son_ret
    xor eax,eax; xor ecx,ecx
.son_ret: ret

s_emit_ast:
    # rdi=node
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    test rbx,rbx; jz .sea_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .sea_num
    cmp eax,NK_STRING; je .sea_string
    cmp eax,NK_BOOL; je .sea_bool
    cmp eax,NK_VAR; je .sea_var
    cmp eax,NK_AXIS; je .sea_axis
    cmp eax,NK_STATE; je .sea_state
    cmp eax,NK_UNARY; je .sea_op
    cmp eax,NK_BINARY; je .sea_op
    cmp eax,NK_CAST; je .sea_cast
    cmp eax,NK_LOAD; je .sea_load
    cmp eax,NK_IMM_U64; je .sea_imm_u64
    cmp eax,NK_IMM_F64_BITS; je .sea_imm_f64_bits
    jmp .sea_fail
.sea_imm_f64_bits:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    mov dil,'"'; call s_out_byte
    lea rdi,[rip+lit_f64bits_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_AUX]; call s_emit_u64_decimal
    mov dil,'"'; call s_out_byte
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    lea rdi,[rip+ty_f64]; mov esi,3; call s_out_quote_span
    jmp .sea_close
.sea_imm_u64:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_AUX]; call s_emit_u64_decimal
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    lea rdi,[rip+ty_u64]; mov esi,3; call s_out_quote_span
    jmp .sea_close
.sea_num:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    cmp qword ptr [rbx+SN_AUX],0; je .sea_num_unsigned
    mov dil,'-'; call s_out_byte
.sea_num_unsigned:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_span
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    # Decimal point/e/E -> f64. Otherwise u64 (negative is represented by unary neg in human AST).
    mov r12,[rbx+SN_PTR]; mov r13,[rbx+SN_LEN]; xor r14d,r14d; xor r15d,r15d
.sea_numscan:
    cmp r15,r13; jae .sea_numtype
    mov al,[r12+r15]; cmp al,'.'; je .sea_isf; cmp al,'e'; je .sea_isf; cmp al,'E'; je .sea_isf
    inc r15; jmp .sea_numscan
.sea_isf: mov r14d,1
.sea_numtype:
    test r14d,r14d; jnz .sea_emit_f64
    # A source negative integer is a signed scalar fact. The old u64 spelling
    # was a latent surface bug exposed by native power on negative bases.
    cmp qword ptr [rbx+SN_AUX],0; jne .sea_emit_i64
    lea rdi,[rip+ty_u64]; mov esi,3; call s_out_quote_span; jmp .sea_close
.sea_emit_i64: lea rdi,[rip+ty_i64]; mov esi,3; call s_out_quote_span; jmp .sea_close
.sea_emit_f64: lea rdi,[rip+ty_f64]; mov esi,3; call s_out_quote_span; jmp .sea_close
.sea_string:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    lea rdi,[rip+ty_string]; mov esi,6; call s_out_quote_span; jmp .sea_close
.sea_bool:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
cmp dword ptr [rbx+SN_AUX],0; je .sea_bool_false
    lea rdi,[rip+lit_true]; call s_out_cstr; jmp .sea_bool_type
.sea_bool_false: lea rdi,[rip+lit_false]; call s_out_cstr
.sea_bool_type:
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    lea rdi,[rip+ty_bool]; mov esi,4; call s_out_quote_span; jmp .sea_close
.sea_var:
    lea rdi,[rip+js_var_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span; jmp .sea_close
.sea_axis:
    lea rdi,[rip+js_axis_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span; jmp .sea_close
.sea_state:
    lea rdi,[rip+js_state_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span; jmp .sea_close
.sea_op:
    lea rdi,[rip+js_op_prefix]; call s_out_cstr
    mov edi,dword ptr [rbx+SN_OP]; call s_op_name
    test rax,rax; jz .sea_fail
    mov rdi,rax; mov rsi,rcx; call s_out_quote_span
    lea rdi,[rip+js_args_mid]; call s_out_cstr
    mov rdi,[rbx+SN_A]; call s_emit_ast; test eax,eax; jnz .sea_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_UNARY; je .sea_args_close
    mov dil,','; call s_out_byte
    mov rdi,[rbx+SN_B]; call s_emit_ast; test eax,eax; jnz .sea_fail
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_SELECT; jne .sea_args_close
    mov dil,','; call s_out_byte
    mov rdi,[rbx+SN_C]; call s_emit_ast; test eax,eax; jnz .sea_fail
.sea_args_close:
    lea rdi,[rip+js_arr_obj_close]; call s_out_cstr
    jmp .sea_ok
.sea_cast:
    lea rdi,[rip+js_cast_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span
    lea rdi,[rip+js_cast_mid]; call s_out_cstr
    mov rdi,[rbx+SN_A]; call s_emit_ast; test eax,eax; jnz .sea_fail
    lea rdi,[rip+js_arr_obj_close]; call s_out_cstr
    jmp .sea_ok
.sea_load:
    lea rdi,[rip+js_load_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span
    lea rdi,[rip+js_indices_mid]; call s_out_cstr
    mov r12,[rbx+SN_A]; xor r13d,r13d
.sea_idx_loop:
    test r12,r12; jz .sea_idx_done
    test r13d,r13d; jz .sea_idx_no_comma
    mov dil,','; call s_out_byte
.sea_idx_no_comma:
    mov rdi,r12; call s_emit_ast; test eax,eax; jnz .sea_fail
    mov r12,[r12+SN_NEXT]; mov r13d,1; jmp .sea_idx_loop
.sea_idx_done:
    lea rdi,[rip+js_arr_obj_close]; call s_out_cstr
    jmp .sea_ok
.sea_close:
    mov dil,'}'; call s_out_byte
.sea_ok:
    xor eax,eax; jmp .sea_done
.sea_fail:
    mov dword ptr [rip+s_error],1; mov eax,1
.sea_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Create literal-u64 AST from immediate rdi.
s_ast_u64_imm:
    # Native immediate AST owns the numeric value. It never aliases mutable text
    # scratch, so multiple Rank-N coordinates remain independent until emission.
    push rbx
    mov rbx,rdi
    call s_new_ast
    test rax,rax; jz .saui_done
    mov dword ptr [rax+SN_KIND],NK_IMM_U64
    mov [rax+SN_AUX],rbx
.saui_done:
    pop rbx
    ret

# Existing literal authority, extended to exact native f64 bits. This is an AST
# literal, not a math subsystem or runtime object.
s_ast_f64_bits_imm:
    push rbx
    mov rbx,rdi
    call s_new_ast
    test rax,rax; jz .safbi_done
    mov dword ptr [rax+SN_KIND],NK_IMM_F64_BITS
    mov [rax+SN_AUX],rbx
.safbi_done: pop rbx; ret

# integral(x,a,b,expr[,panels]): composite 8-point Gauss-Legendre.
# Omission preserves the historical single-panel expansion byte-for-byte at the
# mathematical AST level.  An explicit positive AOT-static panel count repeats
# the same old GL8 template over equal sub-intervals; there is no second
# integrator, runtime loop, callback, or algorithm selector.
s_parse_integral_call:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,128
    mov eax,dword ptr [rip+s_axis_count]; mov [rsp],rax
    mov qword ptr [rsp+64],MATH_DEFAULT_INTEGRAL_PANELS # historical default
    call s_parse_name; test edx,edx; jnz .spic_fail
    mov [rsp+8],rax; mov [rsp+16],rcx
    mov rdi,rax; mov rsi,rcx; call s_axis_add; cmp eax,-1; je .spic_fail
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spic_fail; mov [rsp+24],rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spic_fail; mov [rsp+32],rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spic_fail; mov [rsp+40],rax
    # Optional final refinement count follows the same contract as root():
    # absent -> old default, present -> user-owned AOT-static value.
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spic_close
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spic_fail
    mov rdi,rax; call s_eval_static_u64; test edx,edx; jnz .spic_fail
    test rax,rax; jz .spic_fail          # zero panels has no quadrature meaning
    mov [rsp+64],rax
.spic_close:
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov eax,dword ptr [rsp]; mov dword ptr [rip+s_axis_count],eax
    cmp dword ptr [rip+s_error],0; jne .spic_fail_restored
    cmp qword ptr [rsp+64],1; jne .spic_composite

    # Historical one-panel expansion.  Keep this path structurally identical so
    # omitting the optional argument does not perturb existing generated math.
    # c=(a+b)/2, h=(b-a)/2
    mov edi,OP_ADD; mov rsi,[rsp+24]; mov rdx,[rsp+32]; call s_ast_binary_new; mov r12,rax
    mov edi,2; call s_ast_u64_imm; mov edi,OP_DIV; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r12,rax
    mov edi,OP_SUB; mov rsi,[rsp+32]; mov rdx,[rsp+24]; call s_ast_binary_new; mov r13,rax
    mov edi,2; call s_ast_u64_imm; mov edi,OP_DIV; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov r13,rax
    xor ebx,ebx                         # weighted sum
    xor r15d,r15d
.spic_pair:
    cmp r15d,4; jae .spic_pairs_done
    lea rax,[rip+s_gl8_nodes]; mov rdi,[rax+r15*8]; call s_math_const_bits; mov r14,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r14,rax # h*t
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov [rsp+48],rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov [rsp+56],rax
    mov rdi,[rsp+40]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,[rsp+48]; call s_clone_subst; test rax,rax; jz .spic_fail_restored
    mov r14,rax
    mov rdi,[rsp+40]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,[rsp+56]; call s_clone_subst; test rax,rax; jz .spic_fail_restored
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    lea rax,[rip+s_gl8_weights]; mov rdi,[rax+r15*8]; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    test rbx,rbx; jz .spic_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; mov rbx,rax; jmp .spic_next
.spic_first: mov rbx,r14
.spic_next: inc r15d; jmp .spic_pair
.spic_pairs_done:
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new
    jmp .spic_done

.spic_composite:
    # width=(b-a)/N, half=width/2.  All N-dependent identities are exact integer
    # semantic facts, so representation selection stays with the old consumer.
    mov edi,OP_SUB; mov rsi,[rsp+32]; mov rdx,[rsp+24]; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r12,rax
    mov rdi,[rsp+64]; call s_ast_u64_imm; test rax,rax; jz .spic_fail_restored
    mov edi,OP_DIV; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov [rsp+72],rax
    mov edi,2; call s_ast_u64_imm; mov edi,OP_DIV; mov rsi,[rsp+72]; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov [rsp+80],rax
    mov qword ptr [rsp+88],0             # panel index
    mov qword ptr [rsp+96],0             # global accumulated AST
.spic_panel_loop:
    mov rax,[rsp+88]; cmp rax,[rsp+64]; jae .spic_panel_done
    # left=a+p*width (p=0 reuses a exactly); right=left+width; center=(l+r)/2.
    test rax,rax; jz .spic_panel_left_a
    mov rdi,rax; call s_ast_u64_imm; test rax,rax; jz .spic_fail_restored
    mov edi,OP_MUL; mov rsi,[rsp+72]; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored
    mov edi,OP_ADD; mov rsi,[rsp+24]; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored
    mov r12,rax; jmp .spic_panel_left_ready
.spic_panel_left_a:
    mov r12,[rsp+24]
.spic_panel_left_ready:
    mov edi,OP_ADD; mov rsi,r12; mov rdx,[rsp+72]; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r14,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r12,rax
    mov edi,2; call s_ast_u64_imm; mov edi,OP_DIV; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r12,rax
    mov r13,[rsp+80]
    xor ebx,ebx
    xor r15d,r15d
.spic_panel_pair:
    cmp r15d,4; jae .spic_panel_pairs_done
    lea rax,[rip+s_gl8_nodes]; mov rdi,[rax+r15*8]; call s_math_const_bits; mov r14,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r14,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov [rsp+48],rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov [rsp+56],rax
    mov rdi,[rsp+40]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,[rsp+48]; call s_clone_subst; test rax,rax; jz .spic_fail_restored; mov r14,rax
    mov rdi,[rsp+40]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,[rsp+56]; call s_clone_subst; test rax,rax; jz .spic_fail_restored
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r14,rax
    lea rax,[rip+s_gl8_weights]; mov rdi,[rax+r15*8]; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r14,rax
    test rbx,rbx; jz .spic_panel_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov rbx,rax; jmp .spic_panel_next
.spic_panel_first:
    mov rbx,r14
.spic_panel_next:
    inc r15d; jmp .spic_panel_pair
.spic_panel_pairs_done:
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,[rsp+80]; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov r14,rax
    mov rbx,[rsp+96]; test rbx,rbx; jz .spic_panel_acc_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .spic_fail_restored; mov [rsp+96],rax; jmp .spic_panel_advance
.spic_panel_acc_first:
    mov [rsp+96],r14
.spic_panel_advance:
    inc qword ptr [rsp+88]
    jmp .spic_panel_loop
.spic_panel_done:
    mov rax,[rsp+96]
    jmp .spic_done
.spic_fail:
    mov eax,dword ptr [rsp]; mov dword ptr [rip+s_axis_count],eax
.spic_fail_restored:
    mov dword ptr [rip+s_error],1; xor eax,eax
.spic_done:
    add rsp,128; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Root-relation structural helpers.  They are compile-time only and exist to
# rebuild substituted arithmetic through the existing Structured Fact authority;
# no real/complex solver fork or runtime algorithm selector is introduced.
# Precision-neutral root identities are integer semantic facts.  They inherit
# the consumer representation at the exact edge, so fp65/fp127/fp521 all reuse
# one RootRelation without a wide-root branch.
s_root_zero_const:
    xor edi,edi
    jmp s_ast_u64_imm
s_root_one_const:
    mov edi,1
    jmp s_ast_u64_imm

# rdi=scalar-or-complex AST -> boolean exact-zero fact.
s_root_zero_ast:
    push rbx; push r12; push r13
    mov rbx,rdi
    test rbx,rbx; jz .srza_fail
    cmp dword ptr [rbx+SN_KIND],NK_STRUCT; jne .srza_scalar
    cmp qword ptr [rbx+SN_AUX],STF_COMPLEX; jne .srza_fail
    mov rdi,rbx; xor esi,esi; call s_struct_component; mov r12,rax
    mov rdi,rbx; mov esi,1; call s_struct_component; mov r13,rax
    test r12,r12; jz .srza_fail; test r13,r13; jz .srza_fail
    call s_root_zero_const; mov rbx,rax
    mov edi,OP_EQ; mov rsi,r12; mov rdx,rbx; call s_ast_scalar_binary_new; mov r12,rax
    call s_root_zero_const
    mov edi,OP_EQ; mov rsi,r13; mov rdx,rax; call s_ast_scalar_binary_new
    mov edi,OP_AND; mov rsi,r12; mov rdx,rax; call s_ast_scalar_binary_new
    jmp .srza_done
.srza_scalar:
    call s_root_zero_const
    mov edi,OP_EQ; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
    jmp .srza_done
.srza_fail: xor eax,eax
.srza_done: pop r13; pop r12; pop rbx; ret

# rdi=scalar-or-complex AST -> boolean numerical-nonzero fact.
s_root_nonzero_ast:
    push rbx; push r12; push r13
    mov rbx,rdi
    test rbx,rbx; jz .srna_fail
    cmp dword ptr [rbx+SN_KIND],NK_STRUCT; jne .srna_scalar
    cmp qword ptr [rbx+SN_AUX],STF_COMPLEX; jne .srna_fail
    mov rdi,rbx; xor esi,esi; call s_struct_component; mov r12,rax
    mov rdi,rbx; mov esi,1; call s_struct_component; mov r13,rax
    test r12,r12; jz .srna_fail; test r13,r13; jz .srna_fail
    call s_root_zero_const; mov rbx,rax
    mov edi,OP_NE; mov rsi,r12; mov rdx,rbx; call s_ast_scalar_binary_new; mov r12,rax
    call s_root_zero_const
    mov edi,OP_NE; mov rsi,r13; mov rdx,rax; call s_ast_scalar_binary_new
    mov edi,OP_OR; mov rsi,r12; mov rdx,rax; call s_ast_scalar_binary_new
    jmp .srna_done
.srna_scalar:
    call s_root_zero_const
    mov edi,OP_NE; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
    jmp .srna_done
.srna_fail: xor eax,eax
.srna_done: pop r13; pop r12; pop rbx; ret

# rdi=scalar AST value,rsi=positive scale AST -> bool.  A value is negligible
# exactly when adding its magnitude cannot alter the current representation.
# This is a representation fact, not a tolerance and not a precision threshold.
s_root_negligible_ast:
    push rbx; push r12
    mov rbx,rdi; mov r12,rsi
    mov edi,OP_ABS; mov rsi,rbx; call s_ast_unary_new; test rax,rax; jz .srneg_fail
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .srneg_fail
    mov edi,OP_EQ; mov rsi,rax; mov rdx,r12; call s_ast_scalar_binary_new
    jmp .srneg_done
.srneg_fail: xor eax,eax
.srneg_done: pop r12; pop rbx; ret

# rdi=scalar-or-complex -> complex, with precision-neutral zero imaginary fact.
s_root_complex_lift:
    push rbx; sub rsp,16
    mov rbx,rdi
    cmp dword ptr [rbx+SN_KIND],NK_STRUCT; je .srcl_same
    mov [rsp],rbx
    call s_root_zero_const; test rax,rax; jz .srcl_fail
    mov [rsp+8],rax
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build
    jmp .srcl_done
.srcl_same:
    cmp qword ptr [rbx+SN_AUX],STF_COMPLEX; jne .srcl_fail
    mov rax,rbx; jmp .srcl_done
.srcl_fail: xor eax,eax
.srcl_done: add rsp,16; pop rbx; ret

s_root_abs_ast:
    # rdi=scalar-or-complex AST -> scalar magnitude /0
    push rbx; push r12
    mov rbx,rdi
    test rbx,rbx; jz .sraa_fail
    cmp dword ptr [rbx+SN_KIND],NK_STRUCT; jne .sraa_scalar
    cmp qword ptr [rbx+SN_AUX],STF_COMPLEX; jne .sraa_fail
    mov rdi,rbx; xor esi,esi; call s_struct_component; mov r12,rax
    mov rdi,rbx; mov esi,1; call s_struct_component; test rax,rax; jz .sraa_fail
    mov rsi,rax; mov rdi,r12; call s_expand_scaled_hypot_ast; jmp .sraa_done
.sraa_scalar:
    mov edi,OP_ABS; mov rsi,rbx; call s_ast_unary_new; jmp .sraa_done
.sraa_fail: xor eax,eax
.sraa_done: pop r12; pop rbx; ret

s_root_select_new:
    # rdi=condition,rsi=true scalar/struct,rdx=false scalar/struct -> same shape.
    # Structured select scratch follows the selected fact width rather than a
    # fixed component tier.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; je .srsn_struct
    cmp dword ptr [r13+SN_KIND],NK_STRUCT; je .srsn_struct
    mov rdi,rbx; mov rsi,r12; mov rdx,r13; call s_ast_select_new; jmp .srsn_epilogue
.srsn_struct:
    mov r14d,-1
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .srsn_lift_a
    mov r14d,dword ptr [r12+SN_AUX]; jmp .srsn_have_tag
.srsn_lift_a:
    mov r14d,dword ptr [r13+SN_AUX]
    mov rdi,r12; mov esi,r14d; call s_struct_scalar_lift; test rax,rax; jz .srsn_fail_nostack
    mov r12,rax
.srsn_have_tag:
    cmp dword ptr [r13+SN_KIND],NK_STRUCT; je .srsn_b_struct
    mov rdi,r13; mov esi,r14d; call s_struct_scalar_lift; test rax,rax; jz .srsn_fail_nostack
    mov r13,rax
.srsn_b_struct:
    cmp r14d,dword ptr [r13+SN_AUX]; jne .srsn_fail
    mov r15d,dword ptr [r12+SN_OP]; cmp r15d,dword ptr [r13+SN_OP]; jne .srsn_fail_nostack
    test r15d,r15d; jz .srsn_fail_nostack
    mov eax,r15d; shl rax,3; add rax,15; and rax,-16
    sub rsp,rax
    xor ecx,ecx
.srsn_loop:
    cmp ecx,r15d; jae .srsn_build
    push rcx
    mov rdi,r12; mov esi,ecx; call s_struct_component; mov r8,rax
    pop rcx; push rcx; push r8
    mov rdi,r13; mov esi,ecx; call s_struct_component; mov r9,rax
    pop r8; pop rcx
    test r8,r8; jz .srsn_fail; test r9,r9; jz .srsn_fail
    push rcx
    mov rdi,rbx; mov rsi,r8; mov rdx,r9; call s_ast_select_new
    pop rcx; test rax,rax; jz .srsn_fail
    mov [rsp+rcx*8],rax
    inc ecx; jmp .srsn_loop
.srsn_build:
    mov edi,r14d; mov esi,r15d; mov rdx,rsp; call s_struct_build; jmp .srsn_done
.srsn_fail: xor eax,eax
.srsn_done:
    mov edx,r15d; shl rdx,3; add rdx,15; and rdx,-16
    add rsp,rdx
    jmp .srsn_epilogue
.srsn_fail_nostack: xor eax,eax
.srsn_epilogue:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_clone_subst_root:
    # rdi=node,rsi=name ptr,rdx=name len,rcx=candidate -> rebuilt scalar/struct AST.
    # Arithmetic is reconstructed through old constructors so a scalar lexical
    # coordinate may grow into a complex fact without a second Newton engine.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov r14,rcx
    test rbx,rbx; jz .scsr_fail
    mov eax,dword ptr [rbx+SN_KIND]
    # Preserve semantic identity while the root coordinate grows from R into C.
    # Only primitives that already have one native complex authority are lifted;
    # composite functions continue to descend into their existing arithmetic and
    # therefore parasitize these same primitives instead of gaining root variants.
    cmp eax,NK_UNARY; je .scsr_origin_probe
    cmp eax,NK_BINARY; jne .scsr_origin_skip
.scsr_origin_probe:
    mov r15d,dword ptr [rbx+SN_AUX]
    cmp r15d,MB_EXP; je .scsr_origin_arg
    cmp r15d,MB_LOG; je .scsr_origin_arg
    cmp r15d,MB_SIN; je .scsr_origin_arg
    cmp r15d,MB_COS; je .scsr_origin_arg
.scsr_origin_skip:
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_VAR; je .scsr_name
    cmp eax,NK_AXIS; je .scsr_name
    cmp eax,NK_BINARY; je .scsr_binary
    cmp eax,NK_UNARY; je .scsr_unary
    # Structured literals and all immutable scalar leaves can reuse the generic
    # cloning authority.  Any nested arithmetic that needs structural growth is
    # handled by the explicit cases above.
    mov rdi,rbx; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    jmp .scsr_done
.scsr_origin_arg:
    mov rdi,[rbx+SN_C]; test rdi,rdi; jz .scsr_fail
    mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst_root
    test rax,rax; jz .scsr_fail
    mov rsi,rax; xor edx,edx; xor ecx,ecx
    cmp r15d,MB_EXP; je .scsr_origin_exp
    cmp r15d,MB_LOG; je .scsr_origin_log
    cmp r15d,MB_SIN; je .scsr_origin_sin
    mov edi,MB_CCOS; call s_expand_math_builtin; jmp .scsr_done
.scsr_origin_exp: mov edi,MB_CEXP; call s_expand_math_builtin; jmp .scsr_done
.scsr_origin_log: mov edi,MB_CLOG; call s_expand_math_builtin; jmp .scsr_done
.scsr_origin_sin: mov edi,MB_CSIN; call s_expand_math_builtin; jmp .scsr_done
.scsr_name:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; mov rdx,r12; mov rcx,r13; call s_span_eq
    test eax,eax; jz .scsr_generic
    # Root substitution is immutable DAG substitution.  Reuse the candidate fact
    # directly: unlike tuple/index cloning, Newton never mutates SN_NEXT.
    mov rax,r14; jmp .scsr_done
.scsr_generic:
    mov rdi,rbx; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    jmp .scsr_done
.scsr_binary:
    mov r15d,dword ptr [rbx+SN_OP]
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst_root
    test rax,rax; jz .scsr_fail; mov [rsp],rax
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst_root
    test rax,rax; jz .scsr_fail; mov [rsp+8],rax
    cmp r15d,OP_SELECT; je .scsr_select
    mov edi,r15d; mov rsi,[rsp]; mov rdx,[rsp+8]; call s_ast_binary_new
    jmp .scsr_done
.scsr_select:
    mov rdi,[rbx+SN_C]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst_root
    test rax,rax; jz .scsr_fail
    mov rdi,[rsp]; mov rsi,[rsp+8]; mov rdx,rax; call s_root_select_new
    jmp .scsr_done
.scsr_unary:
    mov r15d,dword ptr [rbx+SN_OP]
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst_root
    test rax,rax; jz .scsr_fail; mov [rsp],rax
    cmp dword ptr [rax+SN_KIND],NK_STRUCT; jne .scsr_unary_scalar
    cmp qword ptr [rax+SN_AUX],STF_COMPLEX; jne .scsr_fail
    cmp r15d,OP_NEG; je .scsr_unary_neg
    cmp r15d,OP_SQUARE; je .scsr_unary_square
    cmp r15d,OP_ABS; je .scsr_unary_abs
    cmp r15d,OP_SQRT; je .scsr_unary_sqrt
    jmp .scsr_fail
.scsr_unary_neg:
    call s_struct_zero; mov edi,OP_SUB; mov rsi,rax; mov rdx,[rsp]; call s_ast_binary_new; jmp .scsr_done
.scsr_unary_square:
    mov edi,OP_MUL; mov rsi,[rsp]; mov rdx,[rsp]; call s_ast_binary_new; jmp .scsr_done
.scsr_unary_abs:
    mov rdi,[rsp]; call s_root_abs_ast; jmp .scsr_done
.scsr_unary_sqrt:
    mov edi,MB_CSQRT; mov rsi,[rsp]; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; jmp .scsr_done
.scsr_unary_scalar:
    mov edi,r15d; mov rsi,[rsp]; call s_ast_unary_new; jmp .scsr_done
.scsr_fail: xor eax,eax
.scsr_done:
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# root(x,expr,guess[,iterations]) / newton(...): one branchless RootRelation.
# The lexical coordinate is differentiated once, then Newton is expanded at AOT
# through the existing scalar/Structured Fact arithmetic.  A scalar seed is not
# a type declaration: it is lifted into one complex search coordinate using the
# scale-derived imaginary direction 1/(1+abs(seed)).  The final RootFact stores
# [valid,real,imag]; precision-neutral identities and representation-stability
# evidence let the same relation flow through native f32/f64 or any fpP, P>64.
# Omitted iterations means five.  No real-root engine, complex fallback engine,
# runtime solver object, tolerance knob or algorithm selector exists.
s_parse_root_call:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,192
    mov eax,dword ptr [rip+s_axis_count]; mov [rsp],rax
    call s_parse_name; test edx,edx; jnz .sprtc_fail
    mov [rsp+8],rax; mov [rsp+16],rcx
    mov rdi,rax; mov rsi,rcx; call s_axis_add; cmp eax,-1; je .sprtc_fail
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprtc_fail; mov [rsp+24],rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprtc_fail; mov [rsp+48],rax
    mov qword ptr [rsp+40],MATH_DEFAULT_ROOT_ITER
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .sprtc_close
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprtc_fail
    mov rdi,rax; call s_eval_static_u64; test edx,edx; jnz .sprtc_fail
    mov [rsp+40],rax
.sprtc_close:
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov eax,dword ptr [rsp]; mov dword ptr [rip+s_axis_count],eax
    cmp dword ptr [rip+s_error],0; jne .sprtc_fail_restored

    # One symbolic derivative authority, before the lexical coordinate grows
    # into a structured search fact.
    mov rdi,[rsp+24]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; call s_ast_diff
    test rax,rax; jz .sprtc_fail_restored
    mov [rsp+32],rax
    # Seed -> one complex search coordinate.  An explicitly complex seed reuses
    # its components; a scalar seed receives a scale-derived non-real direction.
    mov r15,[rsp+48]
    cmp dword ptr [r15+SN_KIND],NK_STRUCT; jne .sprtc_seed_scalar
    cmp qword ptr [r15+SN_AUX],STF_COMPLEX; jne .sprtc_fail_restored
    jmp .sprtc_seed_ready
.sprtc_seed_scalar:
    mov edi,OP_ABS; mov rsi,r15; call s_ast_unary_new; test rax,rax; jz .sprtc_fail_restored
    mov [rsp+56],rax
    call s_root_one_const; mov [rsp+64],rax
    mov edi,OP_ADD; mov rsi,[rsp+56]; mov rdx,[rsp+64]; call s_ast_scalar_binary_new
    test rax,rax; jz .sprtc_fail_restored
    mov edi,OP_DIV; mov rsi,[rsp+64]; mov rdx,rax; call s_ast_scalar_binary_new
    test rax,rax; jz .sprtc_fail_restored
    mov [rsp+8*0+144],r15
    mov [rsp+8*1+144],rax
    lea rdx,[rsp+144]; mov edi,STF_COMPLEX; mov esi,2; call s_struct_build
    test rax,rax; jz .sprtc_fail_restored
    mov r15,rax
.sprtc_seed_ready:
    mov rbx,[rsp+40]
    test rbx,rbx; jz .sprtc_after_iterations
.sprtc_iter:
    mov rdi,[rsp+24]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,r15; call s_clone_subst_root
    test rax,rax; jz .sprtc_fail_restored; mov r12,rax
    mov rdi,[rsp+32]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,r15; call s_clone_subst_root
    test rax,rax; jz .sprtc_fail_restored; mov r13,rax
    # Zero derivative is not a solver fork and must not turn "no candidate" into
    # a runtime divide failure.  Build one branchless validity fact, select a
    # harmless unit denominator when invalid, then select the old candidate back.
    # The same Newton relation therefore covers ordinary, singular and empty work.
    mov rdi,r13; call s_root_nonzero_ast; test rax,rax; jz .sprtc_fail_restored; mov [rsp+80],rax
    call s_root_one_const; mov [rsp+88],rax
    mov rdi,[rsp+80]; mov rsi,r13; mov rdx,[rsp+88]; call s_root_select_new
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+96],rax
    mov edi,OP_DIV; mov rsi,r12; mov rdx,[rsp+96]; call s_ast_binary_new
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+104],rax
    mov edi,OP_SUB; mov rsi,r15; mov rdx,[rsp+104]; call s_ast_binary_new
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+112],rax
    mov rdi,[rsp+80]; mov rsi,[rsp+112]; mov rdx,r15; call s_root_select_new
    test rax,rax; jz .sprtc_fail_restored
    # Each Newton generation immediately collapses its structured carriers into
    # the old scalar compute-binding/ValueFact authority.  This is sparse DAG
    # checkpointing, not a solver state object, and prevents algebraic regrowth.
    mov rdi,rax; call s_materialize_struct; test rax,rax; jz .sprtc_fail_restored
    mov r15,rax
    dec rbx; jnz .sprtc_iter
.sprtc_after_iterations:
    mov [rsp+56],r15                         # final complex candidate

    # Precision-native acceptance.  Reuse the Newton correction itself as the
    # backward-error witness: a candidate is accepted when f is exactly zero,
    # or when df is nonzero and the correction is no longer representable at
    # the candidate's own scale.  No DBL_EPSILON, DBL_MAX, width table or
    # user tolerance survives this relation.
    mov rdi,[rsp+24]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,r15; call s_clone_subst_root
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+64],rax       # f
    mov rdi,[rsp+32]; mov rsi,[rsp+8]; mov rdx,[rsp+16]; mov rcx,r15; call s_clone_subst_root
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+72],rax       # df
    mov rdi,[rsp+64]; call s_root_zero_ast; test rax,rax; jz .sprtc_fail_restored; mov [rsp+80],rax
    mov rdi,[rsp+72]; call s_root_nonzero_ast; test rax,rax; jz .sprtc_fail_restored; mov [rsp+88],rax
    call s_root_one_const; mov [rsp+96],rax
    mov rdi,[rsp+88]; mov rsi,[rsp+72]; mov rdx,[rsp+96]; call s_root_select_new
    test rax,rax; jz .sprtc_fail_restored
    mov edi,OP_DIV; mov rsi,[rsp+64]; mov rdx,rax; call s_ast_binary_new
    test rax,rax; jz .sprtc_fail_restored
    mov rdi,rax; call s_root_complex_lift; test rax,rax; jz .sprtc_fail_restored; mov [rsp+104],rax

    # Candidate scale = 1 + |re| + |im|.  Integer one is representation-neutral.
    mov rdi,r15; xor esi,esi; call s_struct_component; test rax,rax; jz .sprtc_fail_restored; mov [rsp+152],rax
    mov rdi,r15; mov esi,1; call s_struct_component; test rax,rax; jz .sprtc_fail_restored; mov [rsp+160],rax
    mov edi,OP_ABS; mov rsi,[rsp+152]; call s_ast_unary_new; test rax,rax; jz .sprtc_fail_restored; mov [rsp+112],rax
    call s_root_one_const
    mov edi,OP_ADD; mov rsi,[rsp+112]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sprtc_fail_restored; mov [rsp+112],rax
    mov edi,OP_ABS; mov rsi,[rsp+160]; call s_ast_unary_new; test rax,rax; jz .sprtc_fail_restored
    mov edi,OP_ADD; mov rsi,[rsp+112]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sprtc_fail_restored; mov [rsp+112],rax

    # Both correction components must be invisible at that same representation scale.
    mov rdi,[rsp+104]; xor esi,esi; call s_struct_component; test rax,rax; jz .sprtc_fail_restored
    mov rdi,rax; mov rsi,[rsp+112]; call s_root_negligible_ast; test rax,rax; jz .sprtc_fail_restored; mov [rsp+120],rax
    mov rdi,[rsp+104]; mov esi,1; call s_struct_component; test rax,rax; jz .sprtc_fail_restored
    mov rdi,rax; mov rsi,[rsp+112]; call s_root_negligible_ast; test rax,rax; jz .sprtc_fail_restored
    mov edi,OP_AND; mov rsi,[rsp+120]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sprtc_fail_restored
    mov edi,OP_AND; mov rsi,[rsp+88]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sprtc_fail_restored
    mov edi,OP_OR; mov rsi,[rsp+80]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sprtc_fail_restored; mov [rsp+136],rax

    # Real projection uses the same current-representation rule: if |imag| can no
    # longer alter 1+|real|, the imaginary carrier is structurally zeroed.
    mov edi,OP_ABS; mov rsi,[rsp+152]; call s_ast_unary_new; mov r12,rax
    call s_root_one_const
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sprtc_fail_restored; mov [rsp+128],rax
    mov rdi,[rsp+160]; mov rsi,[rsp+128]; call s_root_negligible_ast; test rax,rax; jz .sprtc_fail_restored; mov [rsp+120],rax
    call s_root_zero_const; mov [rsp+144],rax
    mov rdi,[rsp+120]; mov rsi,[rsp+144]; mov rdx,[rsp+160]; call s_ast_select_new
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+160],rax

    # Empty is one sparse validity fact; payload carriers are zeroed without a
    # real/complex solver fork.  Their representation is inherited at select.
    mov rdi,[rsp+136]; mov rsi,[rsp+152]; mov rdx,[rsp+144]; call s_ast_select_new
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+152],rax
    mov rdi,[rsp+136]; mov rsi,[rsp+160]; mov rdx,[rsp+144]; call s_ast_select_new
    test rax,rax; jz .sprtc_fail_restored; mov [rsp+160],rax
    mov rax,[rsp+136]; mov [rsp],rax
    mov rax,[rsp+152]; mov [rsp+8],rax
    mov rax,[rsp+160]; mov [rsp+16],rax
    mov edi,STF_ROOT; mov esi,3; mov rdx,rsp; call s_struct_build
    test rax,rax; jz .sprtc_fail_restored
    jmp .sprtc_done
.sprtc_fail:
    mov eax,dword ptr [rsp]; mov dword ptr [rip+s_axis_count],eax
.sprtc_fail_restored:
    mov dword ptr [rip+s_error],1; xor eax,eax
.sprtc_done:
    add rsp,192; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Generic square-matrix relation.  Called after `matrix(` has been consumed.
# Syntax: matrix(n, a00, a01, ..., a[n*n-1]).  The dimension is an AOT-static
# structural fact.  Elements are linked directly into the existing Structured
# Fact list, so construction has no matrix-size scratch table or runtime object.
s_parse_matrix_relation_call:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    # dimension expression
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spmrc_fail
    mov rdi,rax; call s_eval_static_u64; test edx,edx; jnz .spmrc_fail
    test rax,rax; jz .spmrc_fail
    mov r14,rax
    mov rax,r14; mul r14
    test rdx,rdx; jnz .spmrc_fail
    test rax,rax; jz .spmrc_fail
    mov edx,eax; shr rax,32; jnz .spmrc_fail # component cardinality is the dword Structured-Fact frontier
    mov dword ptr [rsp+8],edx                # expected component count
    mov rdi,r14; call s_matrix_tag_from_n; test eax,eax; jz .spmrc_fail
    mov dword ptr [rsp],eax                  # matrix family tag
    mov qword ptr [rsp+16],0                 # head
    mov qword ptr [rsp+24],0                 # tail
    xor r15d,r15d
.spmrc_component:
    cmp r15d,dword ptr [rsp+8]; jae .spmrc_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spmrc_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spmrc_fail
    mov r12,rax
    call s_new_ast; test rax,rax; jz .spmrc_fail
    mov dword ptr [rax+SN_KIND],NK_STRUCT_ELEM
    mov [rax+SN_A],r12
    mov qword ptr [rax+SN_NEXT],0
    mov r13,[rsp+24]; test r13,r13; jz .spmrc_first
    mov [r13+SN_NEXT],rax
    mov [rsp+24],rax
    jmp .spmrc_next
.spmrc_first:
    mov [rsp+16],rax
    mov [rsp+24],rax
.spmrc_next:
    inc r15d
    jmp .spmrc_component
.spmrc_close:
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spmrc_fail
    call s_new_ast; test rax,rax; jz .spmrc_fail
    mov dword ptr [rax+SN_KIND],NK_STRUCT
    mov ecx,dword ptr [rsp+8]; mov dword ptr [rax+SN_OP],ecx
    mov ecx,dword ptr [rsp]; mov [rax+SN_AUX],rcx
    mov rcx,[rsp+16]; mov [rax+SN_A],rcx
    jmp .spmrc_done
.spmrc_fail:
    mov dword ptr [rip+s_error],1
    xor eax,eax
.spmrc_done:
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx
    ret

# Static selected-axis contraction parser/expander.
# Called after NAME '(' has been consumed. edi=1 sum-one-expression,
# edi=2 multiply-two-expressions then sum. The axis is lexical only and vanishes
# before canonical JSON, so the existing Tensor/Physical Reality stays sovereign.
s_parse_static_axis_reduce_call:
    mov dword ptr [rip+surface_debug_stage],1
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,48
    mov dword ptr [rsp+0],edi              # mode
    mov eax,dword ptr [rip+s_axis_count]
    mov dword ptr [rsp+8],eax              # old lexical axis count
    call s_parse_name
    test edx,edx; jnz .spsarc_fail
    mov [rsp+16],rax; mov [rsp+24],rcx     # axis spelling
    mov dword ptr [rip+surface_debug_stage],2
    mov rdi,rax; mov rsi,rcx; call s_axis_add
    cmp eax,-1; je .spsarc_fail
    mov edi,KID_IN; call s_expect_kw_id
    cmp dword ptr [rip+s_error],0; jne .spsarc_fail
    call s_parse_number_span
    test edx,edx; jnz .spsarc_fail
    xor r14,r14; xor r10d,r10d
.spsarc_extent_loop:
    cmp r10,rcx; jae .spsarc_extent_done
    movzx edx,byte ptr [rax+r10]
    cmp dl,'0'; jb .spsarc_fail; cmp dl,'9'; ja .spsarc_fail
    mov r11,r14; imul r11,r11,10; jo .spsarc_fail
    sub edx,'0'; add r11,rdx; jc .spsarc_fail
    mov r14,r11; inc r10; jmp .spsarc_extent_loop
.spsarc_extent_done:
    test r14,r14; jz .spsarc_fail
    mov [rsp+32],r14
    mov dword ptr [rip+surface_debug_stage],3
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr
    test rax,rax; jz .spsarc_fail
    mov r12,rax                            # body / lhs
    mov dword ptr [rip+surface_debug_stage],4
    mov eax,dword ptr [rsp+0]
    cmp eax,2; je .spsarc_parse_rhs_mul
    cmp eax,4; je .spsarc_parse_rhs_dist
    cmp eax,3; je .spsarc_square_body
    jmp .spsarc_body_ready
.spsarc_parse_rhs_mul:
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr
    test rax,rax; jz .spsarc_fail
    mov rdx,rax; mov rsi,r12; mov edi,OP_MUL; call s_ast_binary_new
    test rax,rax; jz .spsarc_fail
    mov r12,rax; jmp .spsarc_body_ready
.spsarc_parse_rhs_dist:
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr
    test rax,rax; jz .spsarc_fail
    mov rdx,rax; mov rsi,r12; mov edi,OP_SUB; call s_ast_binary_new
    test rax,rax; jz .spsarc_fail
    mov r12,rax
.spsarc_square_body:
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r12; call s_ast_binary_new
    test rax,rax; jz .spsarc_fail
    mov r12,rax
.spsarc_body_ready:
    mov dword ptr [rip+surface_debug_stage],5
    mov [rsp+40],r12
    mov dword ptr [rip+surface_debug_stage],6
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spsarc_fail
    mov eax,dword ptr [rsp+8]
    mov dword ptr [rip+s_axis_count],eax   # contraction axis erases here
    xor r15d,r15d                          # k
    xor ebx,ebx                            # primary accumulator AST
    xor r13d,r13d                          # secondary accumulator for variance
.spsarc_expand:
    cmp r15,[rsp+32]; jae .spsarc_ok
    mov rdi,r15; call s_ast_u64_imm
    test rax,rax; jz .spsarc_fail
    mov rcx,rax
    mov eax,r15d; add eax,70; mov dword ptr [rip+surface_debug_stage],eax
    mov rdi,[rsp+40]; mov rsi,[rsp+16]; mov rdx,[rsp+24]; call s_clone_subst
    test rax,rax; jz .spsarc_fail
    cmp dword ptr [rsp+0],5; jne .spsarc_acc_primary
    # variance tracks sum(x) and sum(x*x) in the same contraction traversal.
    mov r14,rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,r14; call s_ast_binary_new; mov r12,rax
    test rbx,rbx; jz .spsarc_var_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_ADD; mov rsi,r13; mov rdx,r12; call s_ast_binary_new; mov r13,rax
    jmp .spsarc_next
.spsarc_var_first:
    mov rbx,r14; mov r13,r12; jmp .spsarc_next
.spsarc_acc_primary:
    test rbx,rbx; jz .spsarc_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new
    test rax,rax; jz .spsarc_fail
    mov rbx,rax; jmp .spsarc_next
.spsarc_first:
    mov rbx,rax
.spsarc_next:
    inc r15; jmp .spsarc_expand
.spsarc_ok:
    cmp dword ptr [rsp+0],5; jne .spsarc_return_sum
    # population variance = mean(x^2) - mean(x)^2.
    mov rdi,[rsp+32]; call s_math_small_u64_f64; mov r14,rax
    mov edi,OP_DIV; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; mov r12,rax
    mov edi,OP_DIV; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r13,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r12; call s_ast_binary_new; mov r12,rax
    mov edi,OP_SUB; mov rsi,r13; mov rdx,r12; call s_ast_binary_new
    jmp .spsarc_return_with_extent
.spsarc_return_sum:
    mov rax,rbx
.spsarc_return_with_extent:
    mov rdx,[rsp+32]                       # expose static extent to wrappers
    mov dword ptr [rip+surface_debug_stage],99
    jmp .spsarc_done
.spsarc_fail:
    mov eax,dword ptr [rsp+8]
    mov dword ptr [rip+s_axis_count],eax
    mov dword ptr [rip+s_error],1
    xor eax,eax
.spsarc_done:
    add rsp,48
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=base AST, rsi=positive u64 exponent -> existing multiply DAG.
# Exponentiation by squaring minimizes emitted multiplication structure.
s_expand_pow_u64:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi
    test r12,r12; jz .sepu_fail
    test r13,r13; jz .sepu_fail        # zero needs type-preserving one_like; do not fake it
    mov r14,r12                        # current squared factor
    xor ebx,ebx                        # accumulator AST / none
.sepu_loop:
    test r13,1; jz .sepu_no_acc
    test rbx,rbx; jnz .sepu_mul_acc
    mov rbx,r14; jmp .sepu_no_acc
.sepu_mul_acc:
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new
    test rax,rax; jz .sepu_fail
    mov rbx,rax
.sepu_no_acc:
    shr r13,1; jz .sepu_ok
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new
    test rax,rax; jz .sepu_fail
    mov r14,rax; jmp .sepu_loop
.sepu_ok: mov rax,rbx; jmp .sepu_done
.sepu_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.sepu_done: pop r14; pop r13; pop r12; pop rbx; ret

# rdi=base AST,rsi=exponent AST. Positive compile-time integer exponents use
# exponentiation-by-squaring. Every other real exponent lowers to exp(y*log(x))
# through the same native mathematical AST authority; no pow runtime exists.
s_expand_pow_ast:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi
    mov rdi,r12; call s_eval_static_u64
    test edx,edx; jnz .sepa_real
    test rax,rax; jz .sepa_real
    mov rsi,rax; mov rdi,rbx; call s_expand_pow_u64
    jmp .sepa_done
.sepa_real:
    mov rdi,rbx; call s_expand_log_ast; test rax,rax; jz .sepa_fail
    mov r13,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .sepa_fail
    mov rdi,rax; call s_expand_exp_ast
    jmp .sepa_done
.sepa_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.sepa_done: pop r13; pop r12; pop rbx; ret


# ----------------------------------------------------------------------------
# Native mathematical surface expansion.
# The table below is only a parser vocabulary.  Every mathematical word is
# erased here into existing arithmetic/sqrt/trunc ValueFacts; no Math IR,
# runtime, scheduler, executor, or library call is introduced.
# ----------------------------------------------------------------------------
# rdi=name,rsi=len -> eax=semantic parse class, zero if not a structural
# mathematics spelling.  Entries are {ptr,len,class}; aliases share a class.
s_semantic_parse_lookup:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; lea r13,[rip+s_semantic_parse_table]
.sspl_loop:
    mov rax,[r13]; test rax,rax; jz .sspl_no
    mov rdi,rbx; mov rsi,r12; mov rdx,rax; mov ecx,dword ptr [r13+8]
    call s_span_eq; test eax,eax; jnz .sspl_yes
    add r13,16; jmp .sspl_loop
.sspl_yes:
    mov eax,dword ptr [r13+12]; jmp .sspl_done
.sspl_no: xor eax,eax
.sspl_done: pop r13; pop r12; pop rbx; ret

s_math_builtin_lookup:
    # rdi=name,rsi=len -> eax=id, edx=arity; eax=0 if not native math.
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; lea r13,[rip+s_math_builtin_table]
.smbl_loop:
    mov rax,[r13]; test rax,rax; jz .smbl_no
    mov rdi,rbx; mov rsi,r12; mov rdx,rax; mov ecx,dword ptr [r13+8]
    call s_span_eq; test eax,eax; jnz .smbl_yes
    add r13,24; jmp .smbl_loop
.smbl_yes:
    mov eax,dword ptr [r13+12]; mov edx,dword ptr [r13+16]; mov ecx,dword ptr [r13+20]; jmp .smbl_done
.smbl_no: xor eax,eax; xor edx,edx; xor ecx,ecx
.smbl_done: pop r13; pop r12; pop rbx; ret

# edi=semantic id -> eax=Semantic Registry flags, zero if invalid.  IDs are
# deliberately dense so this is O(1) and independent of vocabulary size.
s_math_semantic_flags_by_id:
    cmp edi,1; jb .smsf_no
    cmp edi,MB_LAST; ja .smsf_no
    mov eax,edi; dec eax
    imul eax,eax,24
    lea rdx,[rip+s_math_builtin_table]
    mov eax,dword ptr [rdx+rax+20]
    ret
.smsf_no: xor eax,eax; ret

# Shared optional-iteration authority. edi=required arity, rsi=historical default.
# Returns rax=chosen u64 count, edx=0 on success.  The optional argument is a
# compile-time fact exactly like root's explicit iteration parameter; there is
# no runtime algorithm selector and no per-function parser branch.
s_math_iteration_count:
    push rbx; push r12
    mov ebx,edi; mov r12,rsi
    mov eax,dword ptr [rip+s_math_call_argc]
    cmp eax,ebx; jbe .smic_default
    mov rdx,[rip+s_math_call_args]
    mov rdi,[rdx+rbx*8]
    call s_eval_static_u64
    test edx,edx; jnz .smic_fail
    xor edx,edx; jmp .smic_done
.smic_default:
    mov rax,r12; xor edx,edx; jmp .smic_done
.smic_fail:
    xor eax,eax; mov edx,1
.smic_done:
    pop r12; pop rbx; ret

s_ast_unary_new:
    # edi=op,rsi=a -> rax
    push rbx; push r12
    mov ebx,edi; mov r12,rsi
    call s_new_ast; test rax,rax; jz .saun_done
    mov dword ptr [rax+SN_KIND],NK_UNARY; mov dword ptr [rax+SN_OP],ebx
    mov [rax+SN_A],r12
.saun_done: pop r12; pop rbx; ret

s_math_const_bits:
    jmp s_ast_f64_bits_imm

# rdi=u64 -> f64 immediate AST; compile-time only.  The high-bit path folds
# unsigned conversion from the same shift/double identity instead of imposing a
# signed-small source ceiling.
s_math_small_u64_f64:
    test rdi,rdi
    jns .smsu64_direct
    mov rax,rdi
    and eax,1
    shr rdi,1
    cvtsi2sd xmm0,rdi
    addsd xmm0,xmm0
    test eax,eax
    jz .smsu64_bits
    mov ecx,1
    cvtsi2sd xmm1,rcx
    addsd xmm0,xmm1
    jmp .smsu64_bits
.smsu64_direct:
    cvtsi2sd xmm0,rdi
.smsu64_bits:
    movq rdi,xmm0
    jmp s_ast_f64_bits_imm

# rdi=x AST,rsi=coeff table high->low,edx=count -> Horner AST.
s_math_poly_horner:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r14d,edx; xor r15d,r15d
    test r14d,r14d; jz .smph_fail
    mov rdi,[r13]; call s_math_const_bits; test rax,rax; jz .smph_fail
    mov rbx,rax; mov r15d,1
.smph_loop:
    cmp r15d,r14d; jae .smph_ok
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r12; call s_ast_binary_new; test rax,rax; jz .smph_fail
    mov rbx,rax
    mov rdi,[r13+r15*8]; call s_math_const_bits; test rax,rax; jz .smph_fail
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .smph_fail
    mov rbx,rax; inc r15d; jmp .smph_loop
.smph_ok: mov rax,rbx; jmp .smph_done
.smph_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.smph_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Shared Euler/Lambert exp seed. rdi=x -> rax=q where q approximates
# exp(x/64)-1 directly.  The subtraction-free q form is the common fact:
# exp consumes 1+q and exact squaring; expm1 consumes q and q*(q+2).
# No second approximation family and no near-zero cancellation are introduced.
s_expand_exp_seed_q_ast:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    mov rdi,0x4050000000000000; call s_math_const_bits # 64
    mov edi,OP_DIV; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .seesq_fail
    mov r12,rax                              # y=x/64
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r14,rax # y2
    mov rdi,0x4050800000000000; call s_math_const_bits # 66
    mov rbx,rax; mov r15d,15
.seesq_cf:
    mov edi,OP_DIV; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new; mov rbx,rax
    mov eax,r15d; shl eax,2; add eax,2
    cvtsi2sd xmm0,eax; movq rdi,xmm0; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rax; mov rdx,rbx; call s_ast_binary_new; mov rbx,rax
    dec r15d; jnz .seesq_cf
    mov edi,OP_DIV; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new; mov r13,rax
    mov rdi,0x4000000000000000; call s_math_const_bits; mov r14,rax # 2
    mov edi,OP_SUB; mov rsi,r14; mov rdx,r12; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,r12; call s_ast_binary_new; mov r13,rax
    mov edi,OP_DIV; mov rsi,r13; mov rdx,rbx; call s_ast_binary_new
    jmp .seesq_done
.seesq_fail: xor eax,eax
.seesq_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# exp(x): the general scalar lane retains its one native OP_EXP ValueFact. Other
# lanes consume the same shared q seed and the historical six squarings.
s_expand_exp_ast:
    cmp dword ptr [rip+s_general_lane],0
    je .seea_expand_recipe
    mov rsi,rdi
    mov edi,OP_EXP
    jmp s_ast_unary_new
.seea_expand_recipe:
    push rbx; push r12; push r13; push r14; push r15
    call s_expand_exp_seed_q_ast; test rax,rax; jz .seea_fail; mov rbx,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rax; mov rdx,rbx; call s_ast_binary_new; mov rbx,rax
    mov r15d,6
.seea_sq:
    mov edi,OP_SQUARE; mov rsi,rbx; call s_ast_unary_new; test rax,rax; jz .seea_fail
    mov rbx,rax; dec r15d; jnz .seea_sq
    mov rax,rbx; jmp .seea_done
.seea_fail: xor eax,eax
.seea_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# expm1(x): same q seed, but square in the shifted coordinate q=e^x-1:
# (1+q)^2-1 = q*(q+2).  The identity is global, branchless, and preserves tiny
# x that exp(x)-1 would round to zero.
s_expand_expm1_ast:
    push rbx; push r12; push r13; push r14; push r15
    call s_expand_exp_seed_q_ast; test rax,rax; jz .seem1_fail; mov rbx,rax
    mov r15d,6
.seem1_sq:
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .seem1_fail
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .seem1_fail
    mov rbx,rax; dec r15d; jnz .seem1_sq
    mov rax,rbx; jmp .seem1_done
.seem1_fail: xor eax,eax
.seem1_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# log(x): ten square roots reduce every positive finite f64 to a tiny interval;
# then atanh transform plus a rational tail. x=0 naturally reaches -Inf and
# negative x naturally becomes NaN through sqrt, without a runtime branch.
s_expand_log_ast:
    # General scalar mathematics keeps log as one native ValueFact; no libm or
    # second math runtime is introduced.  Other lanes retain the existing
    # arithmetic realization recipe.
    cmp dword ptr [rip+s_general_lane],0
    je .sela_expand_recipe
    mov rsi,rdi
    mov edi,OP_LOG
    jmp s_ast_unary_new
.sela_expand_recipe:
    # Repeated sqrt is an old, branch-free range contraction. Fourteen roots
    # make u=(z-1)/(z+1) tiny for every positive finite f64. Seven odd atanh
    # terms plus a geometric tail close the remainder; x=0 drives the tail
    # denominator to zero and therefore produces -Inf by native FP semantics.
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov rbx,r12; mov r13d,14
.sela_sqrt:
    mov edi,OP_SQRT; mov rsi,rbx; call s_ast_unary_new; test rax,rax; jz .sela_fail
    mov rbx,rax; dec r13d; jnz .sela_sqrt
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov r13,rax
    mov edi,OP_SUB; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov r14,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov r15,rax
    mov edi,OP_DIV; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sela_fail
    mov r12,rax                         # u
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r12; call s_ast_binary_new; mov r13,rax # z=u^2
    mov rdi,r13; lea rsi,[rip+s_math_log_coeff]; mov edx,7; call s_math_poly_horner; test rax,rax; jz .sela_fail
    mov r14,rax
    # z^7, built as a linear recurrence rather than exponentiation-by-squaring;
    # canonical serialization therefore grows linearly and preserves less-work.
    mov r15,r13; mov ebx,6
.sela_zpow:
    mov edi,OP_MUL; mov rsi,r15; mov rdx,r13; call s_ast_binary_new; mov r15,rax
    dec ebx; jnz .sela_zpow
    mov rdi,0x402e000000000000; call s_math_const_bits; mov rbx,rax # 15
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov rdx,rax
    mov edi,OP_SUB; mov rsi,rdx; mov rdx,r13; call s_ast_binary_new; mov r13,rax
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov r13,rax
    mov edi,OP_DIV; mov rsi,r15; mov rdx,r13; call s_ast_binary_new; mov r15,rax
    mov edi,OP_ADD; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; mov r14,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov rdi,0x40e0000000000000; call s_math_const_bits # 32768 = 2*16384
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new
    jmp .sela_done
.sela_fail: xor eax,eax
.sela_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Compensated log1p authority.  Kahan's correction keeps x alive when 1+x
# rounds to 1: y=1+x, c=y-1, log1p(x)=log(y)*x/c.  Only c=0 needs a
# protected denominator and sparse select; there is no runtime control branch
# and no second approximation family.
s_expand_log1p_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,64
    mov [rsp],rdi                            # x
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov [rsp+8],rax # one
    mov edi,OP_ADD; mov rsi,[rsp]; mov rdx,[rsp+8]; call s_ast_binary_new; test rax,rax; jz .sel1p_fail; mov [rsp+16],rax # y
    mov edi,OP_SUB; mov rsi,[rsp+16]; mov rdx,[rsp+8]; call s_ast_binary_new; test rax,rax; jz .sel1p_fail; mov [rsp+24],rax # c
    call s_struct_zero
    mov edi,OP_EQ; mov rsi,[rsp+24]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sel1p_fail; mov [rsp+32],rax
    call s_struct_one; mov rdi,[rsp+32]; mov rsi,rax; mov rdx,[rsp+24]; call s_ast_select_new; test rax,rax; jz .sel1p_fail; mov [rsp+40],rax
    mov edi,OP_DIV; mov rsi,[rsp]; mov rdx,[rsp+40]; call s_ast_scalar_binary_new; test rax,rax; jz .sel1p_fail; mov [rsp+48],rax
    mov rdi,[rsp+16]; call s_expand_log_ast; test rax,rax; jz .sel1p_fail
    mov edi,OP_MUL; mov rsi,rax; mov rdx,[rsp+48]; call s_ast_scalar_binary_new; test rax,rax; jz .sel1p_fail
    mov rdi,[rsp+32]; mov rsi,[rsp]; mov rdx,rax; call s_ast_select_new
    jmp .sel1p_done
.sel1p_fail: xor eax,eax
.sel1p_done: add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Shared Cody-Waite style reduction for sin/cos; rdi=x -> rax=reduced r.
s_math_reduce_tau:
    push rbx; push r12; push r13; push r14
    mov r12,rdi
    mov rdi,0x3fc45f306dc9c883; call s_math_const_bits # 1/(2pi)
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r13,rax
    mov edi,OP_TRUNC; mov rsi,r13; call s_ast_unary_new; test rax,rax; jz .smrt_fail
    mov r13,rax # q
    mov rdi,0x401921fb54440000; call s_math_const_bits; mov r14,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov r12,rax
    mov rdi,0x3da68c234c4c6629; call s_math_const_bits; mov r14,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r14; call s_ast_binary_new
    jmp .smrt_done
.smrt_fail: xor eax,eax
.smrt_done: pop r14; pop r13; pop r12; pop rbx; ret

s_expand_sin_ast:
    # General lane keeps sine as one ValueFact so fpP can consume the same
    # precision-bearing semantic.  Non-general lanes retain the old arithmetic
    # recipe and therefore do not acquire a second math runtime.
    cmp dword ptr [rip+s_general_lane],0
    je .sesa_expand_recipe
    mov rsi,rdi
    mov edi,OP_SIN
    jmp s_ast_unary_new
.sesa_expand_recipe:
    push rbx; push r12
    call s_math_reduce_tau; test rax,rax; jz .sesa_fail; mov r12,rax
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov rbx,rax
    mov rdi,rbx; lea rsi,[rip+s_math_sin_coeff]; mov edx,16; call s_math_poly_horner; test rax,rax; jz .sesa_fail
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; jmp .sesa_done
.sesa_fail: xor eax,eax
.sesa_done: pop r12; pop rbx; ret

s_expand_cos_ast:
    # Same single semantic authority as sine; precision is decided only at the
    # consumer edge in the general frontend.
    cmp dword ptr [rip+s_general_lane],0
    je .smcos_expand_recipe
    mov rsi,rdi
    mov edi,OP_COS
    jmp s_ast_unary_new
.smcos_expand_recipe:
    push rbx; push r12
    call s_math_reduce_tau; test rax,rax; jz .smcos_fail; mov r12,rax
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov rbx,rax
    mov rdi,rbx; lea rsi,[rip+s_math_cos_coeff]; mov edx,16; call s_math_poly_horner
    jmp .smcos_done
.smcos_fail: xor eax,eax
.smcos_done: pop r12; pop rbx; ret

# atan(x): repeated half-angle contraction, then odd Taylor on a tiny argument.
s_expand_atan_ast:
    # Two half-angle contractions put ordinary finite simulation arguments into
    # a rapidly convergent odd series without a branch/piecewise runtime.
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r13d,2
.seaa_half:
    mov edi,OP_SQUARE; mov rsi,rbx; call s_ast_unary_new; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SQRT; mov rsi,r14; call s_ast_unary_new; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_DIV; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .seaa_fail
    mov rbx,rax; dec r13d; jnz .seaa_half
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,rbx; call s_ast_binary_new; mov r12,rax
    mov rdi,r12; lea rsi,[rip+s_math_atan13_coeff]; mov edx,13; call s_math_poly_horner; test rax,rax; jz .seaa_fail
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; mov rbx,rax
    mov rdi,0x4010000000000000; call s_math_const_bits # 4
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; jmp .seaa_done
.seaa_fail: xor eax,eax
.seaa_done: pop r14; pop r13; pop r12; pop rbx; ret

# tanh(x): Lambert continued fraction x/(1+x²/(3+x²/(5+...))).
# 64 levels keep large ordinary simulation arguments stable without exp overflow.
s_expand_tanh_ast:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r14,rax # x2
    mov r13d,41
    mov rdi,r13; call s_math_small_u64_f64; mov rbx,rax # denominator tail
    mov r15d,20
.seta_cf:
    mov edi,OP_DIV; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new; mov rbx,rax
    lea edi,[r15*2-1]; mov rdi,rdi; call s_math_small_u64_f64
    mov edi,OP_ADD; mov rsi,rax; mov rdx,rbx; call s_ast_binary_new; mov rbx,rax
    dec r15d; jnz .seta_cf
    mov edi,OP_DIV; mov rsi,r12; mov rdx,rbx; call s_ast_binary_new
    jmp .setanh_done
.seta_fail: xor eax,eax
.setanh_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=x, rsi=high->low coefficient table, edx=count -> P(x*x).
s_expand_even_poly_ast:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; test rax,rax; jz .sepv_fail
    mov rdi,rax; mov rsi,r13; mov edx,r14d; call s_math_poly_horner; jmp .sepv_done
.sepv_fail: xor eax,eax
.sepv_done: pop r14; pop r13; pop r12; pop rbx; ret

# Shared scale-safe Euclidean norm fact. rdi=x, rsi=y -> sqrt(x^2+y^2).
# Scalar hypot and complex magnitude are projections of this one authority.
# max/min plus one protected denominator keep the emitted graph branchless; the
# zero case is represented as a sparse dataflow select, never control flow.
s_expand_scaled_hypot_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,48
    mov r12,rdi; mov r13,rsi
    mov edi,OP_ABS; mov rsi,r12; call s_ast_unary_new; test rax,rax; jz .sesha_fail; mov [rsp],rax
    mov edi,OP_ABS; mov rsi,r13; call s_ast_unary_new; test rax,rax; jz .sesha_fail; mov [rsp+8],rax
    mov edi,OP_MAX; mov rsi,[rsp]; mov rdx,[rsp+8]; call s_ast_scalar_binary_new; test rax,rax; jz .sesha_fail; mov r14,rax
    mov edi,OP_MIN; mov rsi,[rsp]; mov rdx,[rsp+8]; call s_ast_scalar_binary_new; test rax,rax; jz .sesha_fail; mov r15,rax
    call s_struct_zero; mov [rsp+16],rax
    mov edi,OP_EQ; mov rsi,r14; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sesha_fail; mov rbx,rax
    call s_struct_one; mov rdi,rbx; mov rsi,rax; mov rdx,r14; call s_ast_select_new; test rax,rax; jz .sesha_fail; mov [rsp+24],rax
    mov edi,OP_DIV; mov rsi,r15; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; test rax,rax; jz .sesha_fail
    mov edi,OP_SQUARE; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .sesha_fail
    mov r15,rax; call s_struct_one; mov edi,OP_ADD; mov rsi,r15; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .sesha_fail
    mov edi,OP_SQRT; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .sesha_fail
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_scalar_binary_new
    jmp .sesha_done
.sesha_fail: xor eax,eax
.sesha_done:
    add rsp,48; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Abramowitz-Stegun 7.1.26 shared complement kernel. rdi=x ->
# q≈erfc(abs(x)).  erf and erfc are merely sign projections of this one old
# approximation, so the expensive t/poly/exp structure exists only once.
s_expand_erf_tail_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov [rsp],rdi
    mov edi,OP_ABS; mov rsi,[rsp]; call s_ast_unary_new; test rax,rax; jz .seeft_fail; mov r13,rax
    mov rdi,0x3fd4f740a93d7b8c; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov r15,rax
    mov edi,OP_ADD; mov rsi,r15; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov edi,OP_DIV; mov rsi,r15; mov rdx,r14; call s_ast_binary_new; mov r13,rax # t
    mov rdi,r13; lea rsi,[rip+s_math_erf_coeff]; mov edx,5; call s_math_poly_horner; test rax,rax; jz .seeft_fail
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,[rsp]; call s_ast_unary_new; mov r15,rax
    mov edi,OP_NEG; mov rsi,r15; call s_ast_unary_new; mov rdi,rax; call s_expand_exp_ast; test rax,rax; jz .seeft_fail
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new
    jmp .seeft_done
.seeft_fail: xor eax,eax
.seeft_done: add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_expand_erf_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov [rsp],rdi
    call s_expand_erf_tail_ast; test rax,rax; jz .seef_fail; mov [rsp+8],rax # q
    call s_struct_one
    mov edi,OP_SUB; mov rsi,rax; mov rdx,[rsp+8]; call s_ast_scalar_binary_new; test rax,rax; jz .seef_fail; mov [rsp+16],rax # magnitude
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .seef_fail; mov [rsp+24],rax
    call s_struct_zero; mov edi,OP_GE; mov rsi,[rsp]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .seef_fail
    mov rdi,rax; mov rsi,[rsp+16]; mov rdx,[rsp+24]; call s_ast_select_new
    jmp .seef_done
.seef_fail: xor eax,eax
.seef_done: add rsp,32; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_expand_erfc_ast:
    # x>=0 -> q, x<0 -> 2-q.  Positive tails never pass through 1-erf(x), so
    # relative information survives without a second approximation branch.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov [rsp],rdi
    call s_expand_erf_tail_ast; test rax,rax; jz .seefc_fail; mov [rsp+8],rax
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,[rsp+8]; call s_ast_scalar_binary_new; test rax,rax; jz .seefc_fail; mov [rsp+16],rax
    call s_struct_zero; mov edi,OP_GE; mov rsi,[rsp]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .seefc_fail
    mov rdi,rax; mov rsi,[rsp+8]; mov rdx,[rsp+16]; call s_ast_select_new
    jmp .seefc_done
.seefc_fail: xor eax,eax
.seefc_done: add rsp,32; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Digamma/trigamma use a user-selectable AOT recurrence shift followed by the
# same Bernoulli asymptotics; omission selects the historical default.
# They are compile-time recipes over the existing arithmetic/log ValueFacts.
s_expand_digamma_ast:
    # rdi=x, rsi=recurrence shifts before the existing Bernoulli asymptotic.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16; mov [rsp],rsi
    mov r12,rdi; xor ebx,ebx; xor r15d,r15d
.seda_shift:
    cmp r15,[rsp]; jae .seda_asym
    mov rdi,r15; call s_math_small_u64_f64; mov r14,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    test rbx,rbx; jz .seda_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; mov rbx,rax; jmp .seda_next
.seda_first: mov rbx,r14
.seda_next: inc r15; jmp .seda_shift
.seda_asym:
    mov rdi,[rsp]; call s_math_small_u64_f64
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r13,rax
    mov rdi,r13; call s_expand_log_ast; mov r14,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r13; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r13; call s_ast_unary_new; mov r13,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov r12,rax
    mov rdi,0xbfb5555555555555; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r12; call s_ast_binary_new; mov r15,rax
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r13,rax
    mov rdi,0x3f81111111111111; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; mov r15,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r12; call s_ast_binary_new; mov r13,rax
    mov rdi,0xbf70410410410410; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; mov r15,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r12; call s_ast_binary_new; mov r13,rax
    mov rdi,0x3f71111111111111; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; mov r15,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r12; call s_ast_binary_new; mov r13,rax
    mov rdi,0xbf7f07c1f07c1f08; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; mov r15,rax
    mov edi,OP_ADD; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; mov r14,rax
    test rbx,rbx; jz .seda_no_recurrence
    mov edi,OP_SUB; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new; jmp .seda_done
.seda_no_recurrence:
    mov rax,r14
.seda_done:
    add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_expand_trigamma_ast:
    # rdi=x, rsi=recurrence shifts before the existing Bernoulli asymptotic.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16; mov [rsp],rsi
    mov r12,rdi; xor ebx,ebx; xor r15d,r15d
.seta_shift:
    cmp r15,[rsp]; jae .seta_asym
    mov rdi,r15; call s_math_small_u64_f64; mov r14,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    test rbx,rbx; jz .seta_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; mov rbx,rax; jmp .seta_next
.seta_first: mov rbx,r14
.seta_next: inc r15; jmp .seta_shift
.seta_asym:
    mov rdi,[rsp]; call s_math_small_u64_f64
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r13,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov r12,rax
    mov r14,r12
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r13,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r12; call s_ast_binary_new; mov r15,rax
    mov rdi,0x3fc5555555555555; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r15; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_MUL; mov rsi,r15; mov rdx,r13; call s_ast_binary_new; mov r15,rax
    mov rdi,0xbfa1111111111111; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r15; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_MUL; mov rsi,r15; mov rdx,r13; call s_ast_binary_new; mov r15,rax
    mov rdi,0x3f98618618618618; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r15; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    test rbx,rbx; jz .setrig_no_recurrence
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_ast_binary_new; jmp .setrig_done
.setrig_no_recurrence:
    mov rax,r14
.setrig_done:
    add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_expand_erfinv_ast:
    # rdi=x, rsi=Newton refinements after the Winitzki seed.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov r12,rdi; mov [rsp+8],rsi
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r13,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov rdi,rax; call s_expand_log_ast; mov r13,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov rdi,0x401152af46b7c65e; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3fc2d0e560418937; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,r13; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new; mov r13,rax
    mov rdi,0x0000000000000000; call s_math_const_bits
    mov edi,OP_GE; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov edi,OP_NEG; mov rsi,r13; call s_ast_unary_new; mov r15,rax
    call s_new_ast; test rax,rax; jz .seei_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],OP_SELECT
    mov [rax+SN_A],r14; mov [rax+SN_B],r13; mov [rax+SN_C],r15; mov r13,rax
    # The historical default is supplied by the Semantic Registry handler.
    # Explicit user depth reuses this exact old Newton relation.
    mov r15,[rsp+8]
    test r15,r15; jz .seei_ready
.seei_loop:
    mov rdi,r13; call s_expand_erf_ast; test rax,rax; jz .seei_fail; mov r14,rax
    mov edi,OP_SUB; mov rsi,r14; mov rdx,r12; call s_ast_binary_new; mov [rsp],rax
    mov edi,OP_SQUARE; mov rsi,r13; call s_ast_unary_new; mov r14,rax
    mov edi,OP_NEG; mov rsi,r14; call s_ast_unary_new; mov rdi,rax; call s_expand_exp_ast; mov r14,rax
    mov rdi,0x3ff20dd750429b6d; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_DIV; mov rsi,[rsp]; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov r13,rax
    dec r15; jnz .seei_loop
.seei_ready:
    mov rax,r13; jmp .seei_done
.seei_fail: xor eax,eax
.seei_done: add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Positive-real Gamma family via one classic g=7 Lanczos authority.  The core
# emits only the three mathematical facts shared by every projection:
#   rax = Lanczos rational sum, rdx = t=z+7.5, rcx = z+0.5.
# Gamma keeps the historical multiply/pow sequence bit-for-bit; log-Gamma and
# all Gamma ratios consume the same core in the log domain.  This is A∩B: one
# sparse kernel, multiple projections, no duplicated Lanczos algorithm.
s_expand_lanczos_core_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .selc_fail
    mov r13,rax                              # z=x-1
    mov rdi,[rip+s_math_lanczos_coeff]; call s_math_const_bits; mov r14,rax
    mov r15d,1
.selc_sum:
    cmp r15d,9; jae .selc_sum_done
    mov rdi,r15; call s_math_small_u64_f64
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .selc_fail; mov rbx,rax
    lea rax,[rip+s_math_lanczos_coeff]; mov rdi,[rax+r15*8]; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,rbx; call s_ast_binary_new; test rax,rax; jz .selc_fail; mov rbx,rax
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new; test rax,rax; jz .selc_fail; mov r14,rax
    inc r15d; jmp .selc_sum
.selc_sum_done:
    mov [rsp],r14                            # shared sum
    mov rdi,0x401e000000000000; call s_math_const_bits # 7.5
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .selc_fail; mov [rsp+8],rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .selc_fail; mov [rsp+16],rax
    mov rax,[rsp]; mov rdx,[rsp+8]; mov rcx,[rsp+16]
    jmp .selc_done
.selc_fail: xor eax,eax; xor edx,edx; xor ecx,ecx
.selc_done: add rsp,32; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_expand_lgamma_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    call s_expand_lanczos_core_ast; test rax,rax; jz .selga_fail
    mov r14,rax                              # sum
    mov r15,rdx                              # t
    mov r13,rcx                              # z+0.5
    mov rdi,r15; call s_expand_log_ast; test rax,rax; jz .selga_fail
    mov edi,OP_MUL; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .selga_fail; mov r13,rax
    mov edi,OP_SUB; mov rsi,r13; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .selga_fail; mov r13,rax
    mov rdi,r14; call s_expand_log_ast; test rax,rax; jz .selga_fail
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .selga_fail; mov r13,rax
    mov rdi,0x3fed67f1c864beb4; call s_math_const_bits # half_ln_2pi
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new
    jmp .selga_done
.selga_fail: xor eax,eax
.selga_done: add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_expand_gamma_ast:
    # Historical projection of the shared Lanczos core.  Keeping this operation
    # order preserves the old f64 release bits while deleting the duplicate core.
    push rbx; push r12; push r13; push r14; push r15
    call s_expand_lanczos_core_ast; test rax,rax; jz .sega_fail
    mov r14,rax                              # sum
    mov r15,rdx                              # t
    mov r13,rcx                              # exponent z+0.5
    mov rdi,r15; mov rsi,r13; call s_expand_pow_ast; test rax,rax; jz .sega_fail; mov r13,rax
    mov edi,OP_NEG; mov rsi,r15; call s_ast_unary_new; mov rdi,rax; call s_expand_exp_ast; test rax,rax; jz .sega_fail; mov r15,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r15; call s_ast_binary_new; mov r13,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r13,rax
    mov rdi,0x40040d931ff62705; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new
    jmp .sega_done
.sega_fail: xor eax,eax
.sega_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Principal Lambert-W for x>=0.  A classical Halley iteration starts from
# log1p(x); omission keeps the historical three-refinement default.
s_expand_lambertw_ast:
    # rdi=x, rsi=Halley refinements.  The seed is iteration zero.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov r12,rdi; mov r15,rsi
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov rdi,rax; call s_expand_log_ast; test rax,rax; jz .selw_fail
    mov r13,rax
    test r15,r15; jz .selw_ready
.selw_loop:
    mov rdi,r13; call s_expand_exp_ast; test rax,rax; jz .selw_fail; mov r14,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_SUB; mov rsi,rbx; mov rdx,r12; call s_ast_binary_new; mov [rsp],rax # f
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new; mov r14,rax # e^w(w+1)
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov rbx,rax # w+2
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,[rsp]; call s_ast_binary_new; mov rbx,rax
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov rdx,rax
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rdx; mov rdx,rax; call s_ast_binary_new; mov rdx,rax # 2w+2
    mov edi,OP_DIV; mov rsi,rbx; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_SUB; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new; mov r14,rax
    mov edi,OP_DIV; mov rsi,[rsp]; mov rdx,r14; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_SUB; mov rsi,r13; mov rdx,rbx; call s_ast_binary_new; mov r13,rax
    dec r15; jnz .selw_loop
.selw_ready:
    mov rax,r13; jmp .selw_done
.selw_fail: xor eax,eax
.selw_done: add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# zeta(s): direct finite Dirichlet series for positive integer s>=2.  The
# exponent is static, so every term uses exponentiation-by-squaring; no generic
# pow runtime is introduced.  The cutoff is an AOT-static source fact; omission
# keeps the historical native-probe default rather than defining semantic capacity.
s_expand_zeta_ast:
    # rdi=s, rsi=Euler-Maclaurin cutoff N.  Six Bernoulli
    # corrections make the f64 result converge to ordinary machine precision
    # across the supported range without a runtime zeta engine or long series.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi; mov [rsp+16],rsi
    cmp qword ptr [rsp+16],2; jb .seza_fail
    mov rdi,r12; call s_eval_static_u64; test edx,edx; jnz .seza_fail
    cmp rax,2; jb .seza_fail; mov r14,rax
    xor ebx,ebx; mov r15,1
.seza_sum_loop:
    cmp r15,[rsp+16]; jae .seza_tail
    mov rdi,r15; call s_math_small_u64_f64; test rax,rax; jz .seza_fail; mov r13,rax
    mov rdi,r13; mov rsi,r14; call s_expand_pow_u64; test rax,rax; jz .seza_fail; mov r13,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .seza_fail; mov r13,rax
    test rbx,rbx; jz .seza_sum_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov rbx,rax; jmp .seza_sum_next
.seza_sum_first: mov rbx,r13
.seza_sum_next: inc r15; jmp .seza_sum_loop

.seza_tail:
    # N^(1-s)/(s-1) = 1 / ((s-1)*16^(s-1))
    mov rdi,[rsp+16]; call s_math_small_u64_f64; mov r13,rax
    lea rsi,[r14-1]; mov rdi,r13; call s_expand_pow_u64; test rax,rax; jz .seza_fail; mov r13,rax
    lea rdi,[r14-1]; call s_math_small_u64_f64
    mov edi,OP_MUL; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov r13,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov r13,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov rbx,rax

    # + 1/(2*N^s)
    mov rdi,[rsp+16]; call s_math_small_u64_f64; mov r13,rax
    mov rdi,r13; mov rsi,r14; call s_expand_pow_u64; test rax,rax; jz .seza_fail; mov r13,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov r13,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov rbx,rax

    # Bernoulli correction k=1..6:
    # B_2k/(2k)! * (s)_(2k-1) / N^(s+2k-1)
    mov rdi,r14; call s_math_small_u64_f64; test rax,rax; jz .seza_fail
    mov r15,rax                          # rising AST=(s)_1
    mov dword ptr [rsp],1                # k
.seza_corr_loop:
    mov eax,dword ptr [rsp]; cmp eax,6; ja .seza_ok
    mov ecx,eax; shl ecx,1
    mov rdx,r14; add rdx,rcx; jc .seza_fail; dec rdx
    mov [rsp+24],rdx                    # denominator exponent
    mov rdi,[rsp+16]; call s_math_small_u64_f64; mov r13,rax
    mov rdi,r13; mov rsi,[rsp+24]; call s_expand_pow_u64; test rax,rax; jz .seza_fail
    mov [rsp+8],rax                     # denominator power
    mov r13,r15                         # rising is already an f64 AST
    mov eax,dword ptr [rsp]; dec eax
    lea rdx,[rip+s_math_zeta_em_coeff]
    mov rdi,[rdx+rax*8]; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r13; mov rdx,rax; call s_ast_binary_new; mov r13,rax
    mov edi,OP_DIV; mov rsi,r13; mov rdx,[rsp+8]; call s_ast_binary_new; mov r13,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov rbx,rax
    mov eax,dword ptr [rsp]; cmp eax,6; jae .seza_corr_next
    # rising *= (s+2k-1)*(s+2k), represented in the mathematical AST so
    # compiler-host integer width cannot become a zeta semantic ceiling.
    mov ecx,eax; shl ecx,1
    mov rdi,r14; add rdi,rcx; jc .seza_fail; dec rdi
    call s_math_small_u64_f64; test rax,rax; jz .seza_fail
    mov edi,OP_MUL; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .seza_fail
    mov r15,rax
    mov eax,dword ptr [rsp]; lea ecx,[eax+eax]
    mov rdi,r14; add rdi,rcx; jc .seza_fail
    call s_math_small_u64_f64; test rax,rax; jz .seza_fail
    mov edi,OP_MUL; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .seza_fail
    mov r15,rax
.seza_corr_next:
    inc dword ptr [rsp]; jmp .seza_corr_loop
.seza_ok:
    mov rax,rbx; jmp .seza_done
.seza_fail:
    mov dword ptr [rip+s_error],1; xor eax,eax
.seza_done:
    add rsp,32; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# polylog(s,z) for compile-time positive integer s: user-sized Horner series
# sum z^n/n^s.  This preserves one z chain rather than materialising each power.
s_expand_polylog_ast:
    # rdi=s, rsi=z, rdx=number of Horner series terms.
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r15,rdx
    mov rdi,r12; call s_eval_static_u64; test edx,edx; jnz .sepl_fail
    test rax,rax; jz .sepl_fail; mov r14,rax
    xor ebx,ebx
    test r15,r15; jz .sepl_zero
.sepl_loop:
    mov rdi,r15; call s_math_small_u64_f64; mov r12,rax
    mov rdi,r12; mov rsi,r14; call s_expand_pow_u64; test rax,rax; jz .sepl_fail; mov r12,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r12; call s_ast_binary_new; mov r12,rax
    test rbx,rbx; jz .sepl_seed
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r12; call s_ast_binary_new; mov rbx,rax; jmp .sepl_next
.sepl_seed: mov rbx,r12
.sepl_next: dec r15; jnz .sepl_loop
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r13; call s_ast_binary_new; jmp .sepl_done
.sepl_zero:
    xor edi,edi; call s_ast_u64_imm; jmp .sepl_done
.sepl_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.sepl_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Complete elliptic K/E through a user-sized AOT AGM refinement count.
# Omission keeps six refinements. esi=0 -> K, esi=1 -> E.
# The construction is compile-time unrolled into sqrt/add/mul ValueFacts.
s_expand_elliptic_ast:
    # rdi=m, rsi=0 K /1 E, rdx=AGM refinements.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov r12,rdi; mov [rsp],rdx; mov [rsp+8],rsi
    mov edi,1; call s_ast_u64_imm; mov [rsp+16],rax   # exact 2^n factor, n=0
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov r13,rax # a=1
    mov edi,OP_SUB; mov rsi,r13; mov rdx,r12; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new; mov r14,rax # b
    xor ebx,ebx # correction sum
    # E(m) AGM identity starts with m/2, then adds 2^n*c_{n+1}^2.
    # K mode keeps the correction absent.
    cmp qword ptr [rsp+8],0
    je .seel_corr_seed_done
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov rbx,rax
.seel_corr_seed_done:
    mov r15d,0
.seel_loop:
    cmp r15,[rsp]; jae .seel_finish
    mov edi,OP_SUB; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r12,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r12,rax # c=(a-b)/2
    # E correction += 2^n c^2
    cmp qword ptr [rsp+8],0; je .seel_no_corr
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r12,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,[rsp+16]; call s_ast_binary_new; mov r12,rax
    test rbx,rbx; jz .seel_corr_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r12; call s_ast_binary_new; mov rbx,rax; jmp .seel_no_corr
.seel_corr_first: mov rbx,r12
.seel_no_corr:
    mov edi,OP_ADD; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r12,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r12,rax # new a
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new; mov r14,rax
    cmp qword ptr [rsp+8],0; je .seel_factor_done
    mov edi,2; call s_ast_u64_imm
    mov edi,OP_MUL; mov rsi,[rsp+16]; mov rdx,rax; call s_ast_binary_new; mov [rsp+16],rax
.seel_factor_done:
    mov r13,r12; inc r15; jmp .seel_loop
.seel_finish:
    mov rdi,0x400921fb54442d18; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r13; call s_ast_binary_new; mov r12,rax # pi/a
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r12,rax # K=pi/(2a)
    cmp qword ptr [rsp+8],0; je .seel_ret_k
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    test rbx,rbx; jnz .seel_have_corr
    xor rbx,rbx; jmp .seel_ret_k
.seel_have_corr:
    mov edi,OP_SUB; mov rsi,rax; mov rdx,rbx; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rbx; call s_ast_binary_new; jmp .seel_done
.seel_ret_k: mov rax,r12
.seel_done: add rsp,32; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# edi=MB_*, rsi=a, rdx=b, rcx=c -> expanded old-AST graph.
s_expand_math_builtin:
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12,rsi; mov r13,rdx
    # Semantic Registry dispatch.  Mathematical vocabulary is data-driven:
    # adding a semantic extends the registry tables, never a parser/runtime
    # comparison tree.  Entry zero is intentionally null.
    cmp ebx,1; jb .semb_fail
    cmp ebx,MB_LAST; ja .semb_fail
    lea rax,[rip+s_math_expand_jump_table]
    mov rax,[rax+rbx*8]
    test rax,rax; jz .semb_fail
    jmp rax
.semb_sin: mov rdi,r12; call s_expand_sin_ast; jmp .semb_done
.semb_cos: mov rdi,r12; call s_expand_cos_ast; jmp .semb_done
.semb_atan: mov rdi,r12; call s_expand_atan_ast; jmp .semb_done
.semb_exp: mov rdi,r12; call s_expand_exp_ast; jmp .semb_done
.semb_log: mov rdi,r12; call s_expand_log_ast; jmp .semb_done
.semb_tanh: mov rdi,r12; call s_expand_tanh_ast; jmp .semb_done
.semb_tan:
    mov rdi,r12; call s_expand_sin_ast; mov r14,rax
    mov rdi,r12; call s_expand_cos_ast; mov r15,rax
    mov edi,OP_DIV; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; jmp .semb_done
.semb_asin:
    # asin(x)=2*atan(x/(1+sqrt(1-x*x)))
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov edi,OP_SQRT; mov rsi,r14; call s_ast_unary_new; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; mov r14,rax
    mov edi,OP_DIV; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov rdi,rax; call s_expand_atan_ast; mov r14,rax
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_acos:
    mov edi,MB_ASIN; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r14,rax
    mov rdi,0x3ff921fb54442d18; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; jmp .semb_done
.semb_exp2:
    mov rdi,0x3fe62e42fefa39ef; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov rdi,rax; call s_expand_exp_ast; jmp .semb_done
.semb_log2:
    mov rdi,r12; call s_expand_log_ast; mov r14,rax
    mov rdi,0x3ff71547652b82fe; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_log10:
    mov rdi,r12; call s_expand_log_ast; mov r14,rax
    mov rdi,0x3fdbcb7b1526e50d; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_expm1:
    mov rdi,r12; call s_expand_expm1_ast; jmp .semb_done
.semb_log1p:
    mov rdi,r12; call s_expand_log1p_ast; jmp .semb_done
.semb_sinh:
    # sinh = t/sqrt(1-t^2), t=tanh(x): one convergent structure, no duplicated exp.
    mov rdi,r12; call s_expand_tanh_ast; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new; mov r15,rax
    mov edi,OP_DIV; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; jmp .semb_done
.semb_cosh:
    # cosh = 1/sqrt(1-tanh(x)^2)
    mov rdi,r12; call s_expand_tanh_ast; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov r14,rax
    mov edi,OP_SUB; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new; mov r15,rax
    mov edi,OP_DIV; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; jmp .semb_done
.semb_asinh:
    # asinh(x)=sign(x)*log1p(a + a^2/(1+hypot(a,1))), a=abs(x).
    # Old log1p + old scaled hypot become one stable identity, no magnitude route.
    mov edi,OP_ABS; mov rsi,r12; call s_ast_unary_new; test rax,rax; jz .semb_fail; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new; test rax,rax; jz .semb_fail; mov r15,rax
    call s_struct_one; mov rdi,r14; mov rsi,rax; call s_expand_scaled_hypot_ast; test rax,rax; jz .semb_fail; mov rbx,rax
    call s_struct_one; mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_DIV; mov rsi,r15; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_log1p_ast; test rax,rax; jz .semb_fail; mov r14,rax
    mov edi,OP_NEG; mov rsi,r14; call s_ast_unary_new; mov r15,rax
    call s_struct_zero; mov edi,OP_GE; mov rsi,r12; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; mov rsi,r14; mov rdx,r15; call s_ast_select_new; jmp .semb_done
.semb_acosh:
    # acosh(x)=log1p((x-1)+sqrt((x-1)(x+1))) is stable as x approaches 1.
    call s_struct_one; mov r14,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r14; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail; mov r15,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail; mov r14,rax
    mov edi,OP_MUL; mov rsi,r15; mov rdx,r14; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_SQRT; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .semb_fail
    mov edi,OP_ADD; mov rsi,r15; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_log1p_ast; jmp .semb_done
.semb_atanh:
    # atanh(x)=0.5*log1p(2x/(1-x)): one compensated log fact, no ratio log tree.
    call s_struct_one; mov r14,rax
    mov edi,OP_SUB; mov rsi,r14; mov rdx,r12; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail; mov r15,rax
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r15; call s_ast_scalar_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_log1p_ast; test rax,rax; jz .semb_fail; mov r14,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_scalar_binary_new; jmp .semb_done
.semb_sec:
    mov rdi,r12; call s_expand_cos_ast; mov r14,rax; jmp .semb_recip_r14
.semb_csc:
    mov rdi,r12; call s_expand_sin_ast; mov r14,rax; jmp .semb_recip_r14
.semb_cot:
    mov rdi,r12; call s_expand_cos_ast; mov r14,rax
    mov rdi,r12; call s_expand_sin_ast; mov r15,rax
    mov edi,OP_DIV; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; jmp .semb_done
.semb_sech:
    # sech = sqrt(1-tanh^2), avoiding a second exponential tree.
    mov rdi,r12; call s_expand_tanh_ast; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new; jmp .semb_done
.semb_csch:
    # csch = sech/tanh.
    mov rdi,r12; call s_expand_tanh_ast; mov r14,rax
    mov edi,OP_SQUARE; mov rsi,r14; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new; mov r15,rax
    mov edi,OP_DIV; mov rsi,r15; mov rdx,r14; call s_ast_binary_new; jmp .semb_done
.semb_coth:
    mov rdi,r12; call s_expand_tanh_ast; mov r14,rax; jmp .semb_recip_r14
.semb_rsqrt:
    mov edi,OP_SQRT; mov rsi,r12; call s_ast_unary_new; mov r14,rax; jmp .semb_recip_r14
.semb_recip: mov r14,r12
.semb_recip_r14:
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; jmp .semb_done
.semb_square:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; jmp .semb_done
.semb_cube:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r14,rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,r12; call s_ast_binary_new; jmp .semb_done
.semb_hypot:
    mov rdi,r12; mov rsi,r13; call s_expand_scaled_hypot_ast; jmp .semb_done
.semb_erf:
    mov rdi,r12; call s_expand_erf_ast; jmp .semb_done
.semb_erfc:
    mov rdi,r12; call s_expand_erfc_ast; jmp .semb_done
.semb_gamma:
    mov rdi,r12; call s_expand_gamma_ast; jmp .semb_done
.semb_lgamma:
    mov rdi,r12; call s_expand_lgamma_ast; jmp .semb_done
.semb_beta:
    # beta(a,b)=exp(lgamma(a)+lgamma(b)-lgamma(a+b)); one Lanczos authority.
    mov rdi,r12; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail; mov r14,rax
    mov rdi,r13; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail; mov r15,rax
    mov edi,OP_ADD; mov rsi,r14; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .semb_fail; mov r14,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail
    mov edi,OP_SUB; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_exp_ast; jmp .semb_done
.semb_lambertw:
    mov edi,1; mov esi,MATH_DEFAULT_LAMBERTW_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_expand_lambertw_ast; jmp .semb_done
.semb_besselj0:
    mov rdi,r12; lea rsi,[rip+s_math_bessel_j0_coeff]; mov edx,13; call s_expand_even_poly_ast; jmp .semb_done
.semb_besselj1:
    mov rdi,r12; lea rsi,[rip+s_math_bessel_j1_coeff]; mov edx,13; call s_expand_even_poly_ast; test rax,rax; jz .semb_fail
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_besseli0:
    mov rdi,r12; lea rsi,[rip+s_math_bessel_i0_coeff]; mov edx,13; call s_expand_even_poly_ast; jmp .semb_done
.semb_zeta:
    mov edi,1; mov esi,MATH_DEFAULT_ZETA_TERMS; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_expand_zeta_ast; jmp .semb_done
.semb_polylog:
    mov edi,2; mov esi,MATH_DEFAULT_POLYLOG_TERMS; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rdx,rax; mov rdi,r12; mov rsi,r13; call s_expand_polylog_ast; jmp .semb_done
.semb_elliptick:
    mov edi,1; mov esi,MATH_DEFAULT_ELLIPTIC_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rdx,rax; mov rdi,r12; xor esi,esi; call s_expand_elliptic_ast; jmp .semb_done
.semb_elliptice:
    mov edi,1; mov esi,MATH_DEFAULT_ELLIPTIC_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rdx,rax; mov rdi,r12; mov esi,1; call s_expand_elliptic_ast; jmp .semb_done
.semb_sinc:
    # sinc(x)=sin(x)/x with the removable singularity represented as a sparse
    # select fact.  The denominator is protected before division; x=0 projects
    # exactly to one without introducing a runtime control branch.
    sub rsp,32
    mov [rsp],r12
    mov rdi,r12; call s_expand_sin_ast; test rax,rax; jz .semb_sinc_fail; mov [rsp+8],rax
    call s_struct_zero; mov edi,OP_EQ; mov rsi,[rsp]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_sinc_fail; mov [rsp+16],rax
    call s_struct_one; mov [rsp+24],rax
    mov rdi,[rsp+16]; mov rsi,[rsp+24]; mov rdx,[rsp]; call s_ast_select_new; test rax,rax; jz .semb_sinc_fail
    mov edi,OP_DIV; mov rsi,[rsp+8]; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_sinc_fail
    mov rdi,[rsp+16]; mov rsi,[rsp+24]; mov rdx,rax; call s_ast_select_new
    add rsp,32; jmp .semb_done
.semb_sinc_fail:
    add rsp,32; jmp .semb_fail
.semb_fma:
    mov rax,[rip+s_math_call_args]
    mov r12,[rax]; mov r13,[rax+8]; mov r14,[rax+16]
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_ADD; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; jmp .semb_done
.semb_clamp:
    mov rax,[rip+s_math_call_args]
    mov r12,[rax]; mov r13,[rax+8]; mov r14,[rax+16]
    mov edi,OP_MAX; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_MIN; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; jmp .semb_done
.semb_lerp:
    mov rax,[rip+s_math_call_args]
    mov r12,[rax]; mov r13,[rax+8]; mov r14,[rax+16]
    mov edi,OP_SUB; mov rsi,r13; mov rdx,r12; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_factorial:
    # Factorial is the exact historical Gamma projection of the shared Lanczos core.
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_gamma_ast; jmp .semb_done
.semb_binomial:
    # C(n,k)=exp(lgamma(n+1)-lgamma(k+1)-lgamma(n-k+1)).
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov r14,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov rdi,rax; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail; mov r15,rax
    mov edi,OP_ADD; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov rdi,rax; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail; mov rbx,rax
    mov edi,OP_SUB; mov rsi,r15; mov rdx,rbx; call s_ast_binary_new; test rax,rax; jz .semb_fail; mov r15,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_ADD; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; mov rdi,rax; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail
    mov edi,OP_SUB; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_exp_ast; jmp .semb_done
.semb_rising:
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; mov rdi,rax; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail; mov r14,rax
    mov rdi,r12; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail
    mov edi,OP_SUB; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_exp_ast; jmp .semb_done
.semb_falling:
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov r14,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_ast_binary_new; mov rdi,rax; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail; mov r15,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov edi,OP_ADD; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; mov rdi,rax; call s_expand_lgamma_ast; test rax,rax; jz .semb_fail
    mov edi,OP_SUB; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_expand_exp_ast; jmp .semb_done
.semb_digamma:
    mov edi,1; mov esi,MATH_DEFAULT_DIGAMMA_SHIFT; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_expand_digamma_ast; jmp .semb_done
.semb_trigamma:
    mov edi,1; mov esi,MATH_DEFAULT_TRIGAMMA_SHIFT; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_expand_trigamma_ast; jmp .semb_done
.semb_erfinv:
    mov edi,1; mov esi,MATH_DEFAULT_ERFINV_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_expand_erfinv_ast; jmp .semb_done
.semb_normalpdf:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r14,rax
    mov rdi,0xbfe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov rdi,rax; call s_expand_exp_ast; mov r14,rax
    mov rdi,0x3fd9884533d43651; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_normalcdf:
    mov rdi,0x3fe6a09e667f3bcc; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov rdi,rax; call s_expand_erf_ast; mov r14,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; mov r14,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_tetration:
    mov rdi,r13; call s_eval_static_u64; test edx,edx; jnz .semb_fail
    test rax,rax; jz .semb_fail
    mov r14,rax; mov r15,r12; dec r14; jz .semb_tetration_done
.semb_tetration_loop:
    mov rdi,r12; mov rsi,r15; call s_expand_pow_ast; test rax,rax; jz .semb_fail
    mov r15,rax; dec r14; jnz .semb_tetration_loop
.semb_tetration_done: mov rax,r15; jmp .semb_done
.semb_det2:
    mov rax,[rip+s_math_call_args]
    mov r12,[rax]; mov r13,[rax+8]; mov r14,[rax+16]; mov r15,[rax+24]
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r15; call s_ast_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,r13; mov rdx,r14; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_det3:
    mov r11,[rip+s_math_call_args]
    mov r12,[r11]; mov r13,[r11+8]; mov r14,[r11+16]
    mov rsi,[r11+32]; mov rdx,[r11+64]; mov edi,OP_MUL; call s_ast_binary_new; mov r15,rax
    mov r11,[rip+s_math_call_args]; mov rsi,[r11+40]; mov rdx,[r11+56]; mov edi,OP_MUL; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,r15; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov rbx,rax
    mov r11,[rip+s_math_call_args]; mov rsi,[r11+24]; mov rdx,[r11+64]; mov edi,OP_MUL; call s_ast_binary_new; mov r15,rax
    mov r11,[rip+s_math_call_args]; mov rsi,[r11+40]; mov rdx,[r11+48]; mov edi,OP_MUL; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,r15; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_MUL; mov rsi,r13; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; mov rbx,rax
    mov r11,[rip+s_math_call_args]; mov rsi,[r11+24]; mov rdx,[r11+56]; mov edi,OP_MUL; call s_ast_binary_new; mov r15,rax
    mov r11,[rip+s_math_call_args]; mov rsi,[r11+32]; mov rdx,[r11+48]; mov edi,OP_MUL; call s_ast_binary_new
    mov edi,OP_SUB; mov rsi,r15; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_besseli1:
    mov rdi,r12; lea rsi,[rip+s_math_bessel_i1_coeff]; mov edx,13; call s_expand_even_poly_ast; test rax,rax; jz .semb_fail
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; jmp .semb_done
.semb_complex:
    sub rsp,16; mov [rsp],r12; mov [rsp+8],r13
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build; add rsp,16; jmp .semb_done
.semb_real:
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .semb_fail
    cmp qword ptr [r12+SN_AUX],STF_COMPLEX; je .semb_real_complex
    cmp qword ptr [r12+SN_AUX],STF_ROOT; jne .semb_fail
    mov rdi,r12; mov esi,1; call s_struct_component; jmp .semb_done
.semb_real_complex:
    mov rdi,r12; xor esi,esi; call s_struct_component; jmp .semb_done
.semb_imag:
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .semb_fail
    cmp qword ptr [r12+SN_AUX],STF_COMPLEX; je .semb_imag_complex
    cmp qword ptr [r12+SN_AUX],STF_ROOT; jne .semb_fail
    mov rdi,r12; mov esi,2; call s_struct_component; jmp .semb_done
.semb_imag_complex:
    mov rdi,r12; mov esi,1; call s_struct_component; jmp .semb_done
.semb_conj:
    sub rsp,16
    mov rdi,r12; xor esi,esi; call s_struct_component; mov [rsp],rax
    mov rdi,r12; mov esi,1; call s_struct_component; mov rsi,rax; mov edi,OP_NEG; call s_ast_unary_new; mov [rsp+8],rax
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build; add rsp,16; jmp .semb_done
.semb_cabs:
    # Complex magnitude is the same scale-safe norm fact as scalar hypot.
    sub rsp,16
    mov rdi,r12; xor esi,esi; call s_struct_component; mov [rsp],rax
    mov rdi,r12; mov esi,1; call s_struct_component; mov [rsp+8],rax
    mov rdi,[rsp]; mov rsi,[rsp+8]; call s_expand_scaled_hypot_ast
    add rsp,16; jmp .semb_done
.semb_cexp:
    # exp(a+bi)=exp(a)(cos(b)+i sin(b)).  The three old scalar authorities are
    # checkpointed once so both complex components reuse ValueFacts instead of
    # serialising/regrowing the same transcendental trees inside RootRelation.
    sub rsp,32
    mov rdi,r12; xor esi,esi; call s_struct_component; mov r14,rax
    mov rdi,r12; mov esi,1; call s_struct_component; mov r15,rax
    mov rdi,r14; call s_expand_exp_ast; test rax,rax; jz .semb_cexp_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_cexp_fail; mov r14,rax
    mov rdi,r15; call s_expand_cos_ast; test rax,rax; jz .semb_cexp_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_cexp_fail; mov [rsp+16],rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; test rax,rax; jz .semb_cexp_fail; mov [rsp],rax
    mov rdi,r15; call s_expand_sin_ast; test rax,rax; jz .semb_cexp_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_cexp_fail; mov [rsp+24],rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; test rax,rax; jz .semb_cexp_fail; mov [rsp+8],rax
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build
    add rsp,32; jmp .semb_done
.semb_cexp_fail:
    add rsp,32; jmp .semb_fail
.semb_clog:
    # Principal complex log.  Argument uses an atan2-equivalent select DAG;
    # no runtime control-flow object or branch scheduler is introduced.
    sub rsp,160
    mov rdi,r12; xor esi,esi; call s_struct_component; mov [rsp],rax       # re
    mov rdi,r12; mov esi,1; call s_struct_component; mov [rsp+8],rax     # im
    mov edi,MB_CABS; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin
    mov rdi,rax; call s_expand_log_ast; mov [rsp+16],rax                  # logarithmic modulus
    call s_struct_zero; mov [rsp+24],rax
    mov edi,OP_EQ; mov rsi,[rsp]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov [rsp+32],rax
    mov edi,OP_LT; mov rsi,[rsp]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov [rsp+40],rax
    mov edi,OP_LT; mov rsi,[rsp+8]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov [rsp+48],rax
    mov edi,OP_GT; mov rsi,[rsp+8]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov [rsp+56],rax
    call s_struct_one; mov rdi,[rsp+32]; mov rsi,rax; mov rdx,[rsp]; call s_ast_select_new; mov [rsp+104],rax
    mov edi,OP_DIV; mov rsi,[rsp+8]; mov rdx,[rsp+104]; call s_ast_scalar_binary_new
    mov rdi,rax; call s_expand_atan_ast; mov [rsp+64],rax
    mov rdi,0x400921fb54442d18; call s_math_const_bits; mov [rsp+112],rax # pi
    mov rdi,0x3ff921fb54442d18; call s_math_const_bits; mov [rsp+120],rax # pi/2
    mov edi,OP_SUB; mov rsi,[rsp+64]; mov rdx,[rsp+112]; call s_ast_scalar_binary_new; mov [rsp+128],rax
    mov edi,OP_ADD; mov rsi,[rsp+64]; mov rdx,[rsp+112]; call s_ast_scalar_binary_new; mov [rsp+136],rax
    mov rdi,[rsp+48]; mov rsi,[rsp+128]; mov rdx,[rsp+136]; call s_ast_select_new; mov [rsp+72],rax
    mov rsi,[rsp+120]; mov edi,OP_NEG; call s_ast_unary_new; mov [rsp+144],rax
    mov rdi,[rsp+56]; mov rsi,[rsp+120]; mov rdx,[rsp+24]; call s_ast_select_new; mov [rsp+152],rax
    mov rdi,[rsp+48]; mov rsi,[rsp+144]; mov rdx,[rsp+152]; call s_ast_select_new; mov [rsp+80],rax
    mov rdi,[rsp+40]; mov rsi,[rsp+72]; mov rdx,[rsp+64]; call s_ast_select_new; mov [rsp+88],rax
    mov rdi,[rsp+32]; mov rsi,[rsp+80]; mov rdx,[rsp+88]; call s_ast_select_new; mov [rsp+96],rax
    mov rax,[rsp+16]; mov [rsp],rax; mov rax,[rsp+96]; mov [rsp+8],rax
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build
    add rsp,160; jmp .semb_done
.semb_root_valid:
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .semb_fail
    cmp qword ptr [r12+SN_AUX],STF_ROOT; jne .semb_fail
    mov rdi,r12; xor esi,esi; call s_struct_component; jmp .semb_done
.semb_component:
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .semb_fail
    mov rdi,r13; call s_eval_static_u64; test edx,edx; jnz .semb_fail
    mov esi,eax; mov rdi,r12; call s_struct_component; jmp .semb_done
.semb_matrix2:
    mov rdx,[rip+s_math_call_args]; mov edi,STF_MAT2; mov esi,4; call s_struct_build; jmp .semb_done
.semb_matrix3:
    mov rdx,[rip+s_math_call_args]; mov edi,STF_MAT3; mov esi,9; call s_struct_build; jmp .semb_done
.semb_matrix4:
    mov rdx,[rip+s_math_call_args]; mov edi,STF_MAT4; mov esi,16; call s_struct_build; jmp .semb_done
.semb_mget:
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .semb_fail
    mov edi,dword ptr [r12+SN_AUX]; call s_matrix_dim; test eax,eax; jz .semb_fail; mov r14d,eax
    mov rdi,r13; call s_eval_static_u64; test edx,edx; jnz .semb_mget_defer
    cmp eax,r14d; jae .semb_fail; mov r15d,eax
    mov rax,[rip+s_math_call_args]; mov rdi,[rax+16]; call s_eval_static_u64; test edx,edx; jnz .semb_mget_defer
    cmp eax,r14d; jae .semb_fail
    imul r15d,r14d; add r15d,eax; mov rdi,r12; mov esi,r15d; call s_struct_component; jmp .semb_done
.semb_mget_defer:
    # Human-shell only: contraction axes are lexical facts and become static
    # during s_clone_subst. Keep the existing MatrixFact and two index ASTs in
    # a surface-only node; no such node is serializable or reaches a backend.
    call s_new_ast; test rax,rax; jz .semb_fail
    mov dword ptr [rax+SN_KIND],NK_STATIC_MGET
    mov [rax+SN_A],r12; mov [rax+SN_B],r13
    mov rdx,[rip+s_math_call_args]; mov rdx,[rdx+16]; mov [rax+SN_C],rdx
    jmp .semb_done
.semb_mtranspose: mov rdi,r12; call s_matrix_transpose_struct; jmp .semb_done
.semb_mtrace: mov rdi,r12; call s_matrix_trace_struct; jmp .semb_done
.semb_makespd: mov rdi,r12; mov rsi,r13; call s_matrix_make_spd; jmp .semb_done
.semb_cholesky: mov rdi,r12; call s_matrix_cholesky; jmp .semb_done
.semb_orthogonalize: mov rdi,r12; call s_matrix_orthogonalize; jmp .semb_done
.semb_qrr: mov rdi,r12; call s_matrix_qr_r; jmp .semb_done
.semb_lul: mov rdi,r12; xor esi,esi; call s_matrix_lu_struct; jmp .semb_done
.semb_luu: mov rdi,r12; mov esi,1; call s_matrix_lu_struct; jmp .semb_done
.semb_ldltl: mov rdi,r12; xor esi,esi; call s_matrix_ldlt_struct; jmp .semb_done
.semb_ldltd: mov rdi,r12; mov esi,1; call s_matrix_ldlt_struct; jmp .semb_done
.semb_matrixexp:
    mov edi,1; mov esi,MATH_DEFAULT_MATRIX_EXP_TERMS; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_matrix_exp_struct; jmp .semb_done
.semb_matrixlog:
    mov edi,1; mov esi,MATH_DEFAULT_MATRIX_LOG_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_matrix_log_struct; jmp .semb_done
.semb_matrixsqrt:
    mov edi,1; mov esi,MATH_DEFAULT_MATRIX_SQRT_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_matrix_sqrt_struct; jmp .semb_done
.semb_eigvalues:
    mov edi,1; mov esi,MATH_DEFAULT_EIG_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rdx,rax; mov rdi,r12; xor esi,esi; call s_matrix_eig_struct; jmp .semb_done
.semb_eigvectors:
    mov edi,1; mov esi,MATH_DEFAULT_EIG_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rdx,rax; mov rdi,r12; mov esi,1; call s_matrix_eig_struct; jmp .semb_done
.semb_svdvalues:
    mov edi,1; mov esi,MATH_DEFAULT_EIG_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_matrix_svd_values; jmp .semb_done
.semb_svdu:
    mov edi,1; mov esi,MATH_DEFAULT_EIG_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_matrix_svd_u; jmp .semb_done
.semb_svdv:
    mov edi,1; mov esi,MATH_DEFAULT_EIG_ITER; call s_math_iteration_count; test edx,edx; jnz .semb_fail
    mov rsi,rax; mov rdi,r12; call s_matrix_svd_v; jmp .semb_done
.semb_matrixinv: mov rdi,r12; call s_matrix_inverse_struct; jmp .semb_done
.semb_hadamard:
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r13; call s_struct_componentwise_binary; jmp .semb_done
.semb_csin:
    # sin(a+bi)=sin(a)cosh(b)+i cos(a)sinh(b).  Scalar semantic results are
    # materialised once; complex/root composition therefore stays a sparse DAG.
    sub rsp,48
    mov rdi,r12; xor esi,esi; call s_struct_component; mov r14,rax
    mov rdi,r12; mov esi,1; call s_struct_component; mov r15,rax
    mov rdi,r14; call s_expand_sin_ast; test rax,rax; jz .semb_csin_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_csin_fail; mov [rsp+16],rax
    mov edi,MB_COSH; mov rsi,r15; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .semb_csin_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_csin_fail; mov [rsp+24],rax
    mov edi,OP_MUL; mov rsi,[rsp+16]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; test rax,rax; jz .semb_csin_fail; mov [rsp],rax
    mov rdi,r14; call s_expand_cos_ast; test rax,rax; jz .semb_csin_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_csin_fail; mov [rsp+32],rax
    mov edi,MB_SINH; mov rsi,r15; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .semb_csin_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_csin_fail; mov [rsp+40],rax
    mov edi,OP_MUL; mov rsi,[rsp+32]; mov rdx,[rsp+40]; call s_ast_scalar_binary_new; test rax,rax; jz .semb_csin_fail; mov [rsp+8],rax
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build
    add rsp,48; jmp .semb_done
.semb_csin_fail:
    add rsp,48; jmp .semb_fail
.semb_ccos:
    # cos(a+bi)=cos(a)cosh(b)-i sin(a)sinh(b), sharing the same sparse scalar
    # checkpoint pattern as complex sine rather than a second dense realization.
    sub rsp,48
    mov rdi,r12; xor esi,esi; call s_struct_component; mov r14,rax
    mov rdi,r12; mov esi,1; call s_struct_component; mov r15,rax
    mov rdi,r14; call s_expand_cos_ast; test rax,rax; jz .semb_ccos_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_ccos_fail; mov [rsp+16],rax
    mov edi,MB_COSH; mov rsi,r15; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .semb_ccos_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_ccos_fail; mov [rsp+24],rax
    mov edi,OP_MUL; mov rsi,[rsp+16]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; test rax,rax; jz .semb_ccos_fail; mov [rsp],rax
    mov rdi,r14; call s_expand_sin_ast; test rax,rax; jz .semb_ccos_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_ccos_fail; mov [rsp+32],rax
    mov edi,MB_SINH; mov rsi,r15; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .semb_ccos_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .semb_ccos_fail; mov [rsp+40],rax
    mov edi,OP_MUL; mov rsi,[rsp+32]; mov rdx,[rsp+40]; call s_ast_scalar_binary_new; test rax,rax; jz .semb_ccos_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .semb_ccos_fail; mov [rsp+8],rax
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build
    add rsp,48; jmp .semb_done
.semb_ccos_fail:
    add rsp,48; jmp .semb_fail
.semb_csqrt:
    # principal sqrt via exp(0.5*log(z)); structured stages checkpoint into
    # ordinary scalar ValueFacts so composition does not regrow an AST tree.
    mov edi,MB_CLOG; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_materialize_struct; test rax,rax; jz .semb_fail; mov r14,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits; mov edi,OP_MUL; mov rsi,r14; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .semb_fail
    mov rdi,rax; call s_materialize_struct; test rax,rax; jz .semb_fail
    mov edi,MB_CEXP; mov rsi,rax; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; jmp .semb_done
.semb_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.semb_done:
    # Preserve the high-level mathematical identity as compile-time metadata on
    # the existing AST root.  It is never serialized and never reaches runtime;
    # symbolic calculus may use it to apply an algebraic derivative rule before
    # descending into the lower arithmetic realization.  This prevents a compact
    # native semantic from being re-expanded merely because it is differentiated.
    test rax,rax; jz .semb_meta_done
    mov r15,rax                         # preserve expanded root across metadata lookup
    mov edi,ebx; call s_math_semantic_flags_by_id
    test eax,MSF_DIFFERENTIABLE; jz .semb_meta_restore
    mov ecx,dword ptr [r15+SN_KIND]
    cmp ecx,NK_UNARY; je .semb_meta_store
    cmp ecx,NK_BINARY; jne .semb_meta_restore
    # OP_SELECT owns SN_C as its false dataflow edge.  Differentiable semantics
    # therefore project a select through the arithmetic identity *1 before
    # attaching origin metadata.  One generic sparse fix protects every native
    # mathematical select instead of growing per-function compatibility paths.
    cmp dword ptr [r15+SN_OP],OP_SELECT; jne .semb_meta_store
    mov r14d,ebx
    mov rdi,0x3ff0000000000000; call s_math_const_bits; test rax,rax; jz .semb_meta_restore
    mov edi,OP_MUL; mov rsi,r15; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .semb_meta_restore
    mov r15,rax; mov ebx,r14d
.semb_meta_store:
    mov dword ptr [r15+SN_AUX],ebx
    mov [r15+SN_C],r12
.semb_meta_restore:
    mov rax,r15
.semb_meta_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=node -> eax=1 only for the exact compile-time u64 zero derivative fact.
s_ast_is_zero_imm:
    test rdi,rdi; jz .saizi_no
    cmp dword ptr [rdi+SN_KIND],NK_IMM_U64; jne .saizi_no
    cmp qword ptr [rdi+SN_AUX],0; sete al; movzx eax,al; ret
.saizi_no: xor eax,eax; ret

# Differentiate a Surface-native mathematical origin before descending into its
# arithmetic realization. rdi=root,rsi=name,rdx=len -> rax ordinary AST.
# The origin metadata lives only on the old AST node; no Math IR survives.
s_ast_diff_math_origin:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov rbx,rdi
    mov r13,rsi
    mov r14,rdx
    mov r12,[rbx+SN_C]                 # original argument
    mov ebx,dword ptr [rbx+SN_AUX]     # MB_ id
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_ast_diff
    test rax,rax; jz .sadmo_fail
    mov [rsp],rax                      # da
    mov rdi,rax; call s_ast_is_zero_imm; test eax,eax; jnz .sadmo_return_da

    # Differentiation uses the same Semantic Registry identity.  A semantic
    # without a registered derivative handler is rejected rather than guessed.
    cmp ebx,1; jb .sadmo_fail
    cmp ebx,MB_LAST; ja .sadmo_fail
    lea rax,[rip+s_math_diff_jump_table]
    mov rax,[rax+rbx*8]
    test rax,rax; jz .sadmo_fail
    jmp rax

# Common helper convention: build derivative factor in r15, then multiply by da.
.sadmo_sin:
    mov edi,MB_COS; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r15,rax; jmp .sadmo_times_da
.sadmo_cos:
    mov edi,MB_SIN; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .sadmo_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_tan:
    mov edi,MB_SEC; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQUARE; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_asin:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQRT; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_acos:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQRT; mov rsi,rax; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_atan:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_exp:
    mov edi,MB_EXP; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r15,rax; jmp .sadmo_times_da
.sadmo_log:
    mov r15,r12; jmp .sadmo_recip_factor
.sadmo_exp2:
    mov edi,MB_EXP2; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r15,rax
    mov rdi,0x3fe62e42fefa39ef; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_log2:
    mov rdi,0x3fe62e42fefa39ef; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_log10:
    mov rdi,0x40026bb1bbb55516; call s_math_const_bits # ln(10)
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_log1p:
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_sinh:
    mov edi,MB_COSH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r15,rax; jmp .sadmo_times_da
.sadmo_cosh:
    mov edi,MB_SINH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r15,rax; jmp .sadmo_times_da
.sadmo_tanh:
    # tanh' = 1 - tanh^2. Reuse the one native tanh structure instead of
    # constructing sech and then squaring another copy of the same CF.
    mov edi,MB_TANH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQUARE; mov rsi,rax; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_asinh:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQRT; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_acosh:
    mov rdi,0x3ff0000000000000; call s_math_const_bits; mov r15,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQRT; mov rsi,rax; call s_ast_unary_new; mov [rsp+8],rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQRT; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_MUL; mov rsi,[rsp+8]; mov rdx,rax; call s_ast_binary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_atanh:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r15,rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_SUB; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov r15,rax; jmp .sadmo_recip_factor
.sadmo_sec:
    mov edi,MB_SEC; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r15,rax; mov [rsp+8],rax
    mov edi,MB_TAN; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin
    mov edi,OP_MUL; mov rsi,[rsp+8]; mov rdx,rax; call s_ast_binary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_csc:
    mov edi,MB_CSC; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov r15,rax; mov [rsp+8],rax
    mov edi,MB_COT; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin
    mov edi,OP_MUL; mov rsi,[rsp+8]; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_cot:
    mov edi,MB_CSC; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQUARE; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_sech:
    mov edi,MB_SECH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov [rsp+8],rax
    mov edi,MB_TANH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin
    mov edi,OP_MUL; mov rsi,[rsp+8]; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_csch:
    mov edi,MB_CSCH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; mov [rsp+8],rax
    mov edi,MB_COTH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin
    mov edi,OP_MUL; mov rsi,[rsp+8]; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_coth:
    mov edi,MB_CSCH; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .sadmo_fail
    mov edi,OP_SQUARE; mov rsi,rax; call s_ast_unary_new; test rax,rax; jz .sadmo_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_rsqrt:
    mov edi,MB_RSQRT; mov rsi,r12; xor edx,edx; xor ecx,ecx; call s_expand_math_builtin; test rax,rax; jz .sadmo_fail
    mov r15,rax
    mov rdi,0xbfe0000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,r15; mov rdx,rax; call s_ast_binary_new; mov r15,rax
    mov edi,OP_DIV; mov rsi,r15; mov rdx,r12; call s_ast_binary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_recip:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r15,rax
    mov rdi,0xbff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_square:
    mov rdi,0x4000000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r12; call s_ast_binary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_cube:
    mov edi,OP_SQUARE; mov rsi,r12; call s_ast_unary_new; mov r15,rax
    mov rdi,0x4008000000000000; call s_math_const_bits
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov r15,rax; jmp .sadmo_times_da
.sadmo_recip_factor:
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r15; call s_ast_binary_new; mov r15,rax
.sadmo_times_da:
    test r15,r15; jz .sadmo_fail
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rsp]; call s_ast_binary_new; jmp .sadmo_done
.sadmo_return_da:
    mov rax,[rsp]; jmp .sadmo_done
.sadmo_fail:
    xor eax,eax
.sadmo_done:
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Componentwise structured differentiation.  The container is only a sparse
# compile-time fact: every component reuses the one scalar differentiation
# authority and the original structured tag is rebuilt.
s_ast_diff_struct:
    # rdi=struct,rsi=name ptr,rdx=len -> same-tag struct / 0.  The temporary
    # component vector follows the structure itself; differentiation has no
    # matrix-size tier or fixed structured-width branch.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    cmp dword ptr [rbx+SN_KIND],NK_STRUCT; jne .sads_fail_nostack
    mov r14d,dword ptr [rbx+SN_OP]
    test r14d,r14d; jz .sads_fail_nostack
    mov r15d,dword ptr [rbx+SN_AUX]
    mov eax,r14d; shl rax,3; add rax,15; and rax,-16
    sub rsp,rax
    xor ecx,ecx
.sads_loop:
    cmp ecx,r14d; jae .sads_build
    push rcx
    mov rdi,rbx; mov esi,ecx; call s_struct_component
    pop rcx; test rax,rax; jz .sads_fail
    push rcx
    mov rdi,rax; mov rsi,r12; mov rdx,r13; call s_ast_diff
    pop rcx; test rax,rax; jz .sads_fail
    mov [rsp+rcx*8],rax
    inc ecx; jmp .sads_loop
.sads_build:
    mov edi,r15d; mov esi,r14d; mov rdx,rsp; call s_struct_build
    jmp .sads_done
.sads_fail:
    xor eax,eax
.sads_done:
    mov edx,r14d; shl rdx,3; add rdx,15; and rdx,-16
    add rsp,rdx
    jmp .sads_epilogue
.sads_fail_nostack:
    xor eax,eax
.sads_epilogue:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Symbolic differentiation on the existing AST. rdi=node,rsi=name ptr,rdx=len.
# No derivative node survives this routine: the result is ordinary arithmetic,
# sqrt/select/abs ValueFacts and is optimized by the existing Physical Reality.
s_ast_diff:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    test rbx,rbx; jz .sad_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_UNARY; je .sad_origin_probe
    cmp eax,NK_BINARY; jne .sad_origin_skip
.sad_origin_probe:
    mov ecx,dword ptr [rbx+SN_AUX]
    test ecx,ecx; jz .sad_origin_skip
    mov edi,ecx; call s_math_semantic_flags_by_id
    test eax,MSF_DIFFERENTIABLE; jz .sad_origin_skip
    cmp qword ptr [rbx+SN_C],0; je .sad_origin_skip
    mov rdi,rbx; mov rsi,r12; mov rdx,r13; call s_ast_diff_math_origin
    test rax,rax; jnz .sad_done
    jmp .sad_fail
.sad_origin_skip:
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_VAR; je .sad_name
    cmp eax,NK_AXIS; je .sad_name
    cmp eax,NK_STATE; je .sad_name
    cmp eax,NK_UNARY; je .sad_unary
    cmp eax,NK_BINARY; je .sad_binary
    cmp eax,NK_CAST; je .sad_cast
    cmp eax,NK_STRUCT; je .sad_struct
    # Literals, loads and discrete objects are constants with respect to the
    # named scalar/coordinate. Loads can still be differentiated by writing
    # their analytical field expression before materialization.
    xor edi,edi; call s_ast_u64_imm; jmp .sad_done
.sad_struct:
    mov rdi,rbx; mov rsi,r12; mov rdx,r13; call s_ast_diff_struct
    test rax,rax; jz .sad_fail; jmp .sad_done
.sad_name:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; mov rdx,r12; mov rcx,r13; call s_span_eq
    test eax,eax; jz .sad_zero
    mov edi,1; call s_ast_u64_imm; jmp .sad_done
.sad_zero:
    xor edi,edi; call s_ast_u64_imm; jmp .sad_done
.sad_cast:
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; call s_ast_diff
    jmp .sad_done
.sad_unary:
    mov r14d,dword ptr [rbx+SN_OP]
    cmp r14d,OP_TRUNC; je .sad_zero
    cmp r14d,OP_NOT; je .sad_zero
    cmp r14d,OP_BIT_NOT; je .sad_zero
    cmp r14d,OP_SQUARE; je .sad_unary_square_chain
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; call s_ast_diff
    test rax,rax; jz .sad_fail
    mov r15,rax
    mov rdi,r15; call s_ast_is_zero_imm; test eax,eax; jnz .sad_return_r15
    cmp r14d,OP_NEG; je .sad_unary_neg
    cmp r14d,OP_SQRT; je .sad_unary_sqrt
    cmp r14d,OP_ABS; je .sad_unary_abs
    # Unknown pure unary operations are not silently guessed.
    jmp .sad_fail
.sad_unary_neg:
    mov edi,OP_NEG; mov rsi,r15; call s_ast_unary_new; jmp .sad_done
.sad_unary_square_chain:
    # Collapse a maximal square(square(...square(base))) chain before
    # differentiation.  d(base^(2^n)) = 2^n * base^(2^n-1) * d(base).
    # This is a generic algebraic rule for the existing square ValueFact and
    # keeps derivative construction logarithmic rather than duplicating every
    # recovery stage.
    mov r14,rbx
    xor r15d,r15d
.sad_sqchain_scan:
    cmp dword ptr [r14+SN_KIND],NK_UNARY; jne .sad_sqchain_base
    cmp dword ptr [r14+SN_OP],OP_SQUARE; jne .sad_sqchain_base
    inc r15d
    cmp r15d,30; ja .sad_fail
    mov r14,[r14+SN_A]
    test r14,r14; jz .sad_fail
    jmp .sad_sqchain_scan
.sad_sqchain_base:
    mov [rsp+8],r14
    mov rdi,r14; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov [rsp],rax
    mov rdi,rax; call s_ast_is_zero_imm; test eax,eax; jnz .sad_zero
    mov eax,1; mov ecx,r15d; shl eax,cl; mov r15d,eax
    mov esi,r15d; dec esi; mov rdi,[rsp+8]; call s_expand_pow_u64; test rax,rax; jz .sad_fail
    mov r14,rax
    mov edi,r15d; call s_math_small_u64_f64; test rax,rax; jz .sad_fail
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov edi,OP_MUL; mov rsi,rax; mov rdx,[rsp]; call s_ast_binary_new; jmp .sad_done

.sad_unary_sqrt:
    mov edi,OP_SQRT; mov rsi,[rbx+SN_A]; call s_ast_unary_new; test rax,rax; jz .sad_fail
    mov r14,rax
    mov edi,2; call s_ast_u64_imm; mov rdx,r14; mov rsi,rax; mov edi,OP_MUL; call s_ast_binary_new
    test rax,rax; jz .sad_fail
    mov rdx,rax; mov rsi,r15; mov edi,OP_DIV; call s_ast_binary_new; jmp .sad_done
.sad_return_r15:
    mov rax,r15; jmp .sad_done
.sad_unary_abs:
    mov edi,OP_ABS; mov rsi,[rbx+SN_A]; call s_ast_unary_new; test rax,rax; jz .sad_fail
    mov r14,rax
    mov edi,OP_DIV; mov rsi,[rbx+SN_A]; mov rdx,r14; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov rdx,r15; mov rsi,rax; mov edi,OP_MUL; call s_ast_binary_new; jmp .sad_done
.sad_binary:
    mov r14d,dword ptr [rbx+SN_OP]
    cmp r14d,OP_ADD; je .sad_bin_linear
    cmp r14d,OP_SUB; je .sad_bin_linear
    cmp r14d,OP_MUL; je .sad_bin_mul
    cmp r14d,OP_DIV; je .sad_bin_div
    cmp r14d,OP_MIN; je .sad_bin_min
    cmp r14d,OP_MAX; je .sad_bin_max
    cmp r14d,OP_SELECT; je .sad_bin_select
    # comparisons, boolean/bitwise and modulo are piecewise/discrete.
    jmp .sad_zero
.sad_bin_linear:
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov [rsp],rax
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov r15,rax
    mov rdi,[rsp]; call s_ast_is_zero_imm; test eax,eax; jz .sad_linear_left_live
    cmp r14d,OP_ADD; je .sad_return_r15
    mov rdi,r15; call s_ast_is_zero_imm; test eax,eax; jnz .sad_return_r15
    mov edi,OP_NEG; mov rsi,r15; call s_ast_unary_new; jmp .sad_done
.sad_linear_left_live:
    mov rdi,r15; call s_ast_is_zero_imm; test eax,eax; jnz .sad_return_left
    mov rdx,r15; mov rsi,[rsp]; mov edi,r14d; call s_ast_binary_new; jmp .sad_done
.sad_return_left:
    mov rax,[rsp]; jmp .sad_done
.sad_bin_mul:
    # Shared square DAG: d(a*a)=2*a*da. Differentiate the shared child once;
    # this preserves less-work and prevents derivative expansion from duplicating
    # every squaring stage used by exp/power recovery.
    mov rax,[rbx+SN_A]; cmp rax,[rbx+SN_B]; jne .sad_bin_mul_general
    mov rdi,rax; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov r15,rax; mov rdi,r15; call s_ast_is_zero_imm; test eax,eax; jnz .sad_return_r15
    mov edi,OP_MUL; mov rsi,[rbx+SN_A]; mov rdx,r15; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov r15,rax; mov edi,2; call s_ast_u64_imm
    mov rdx,r15; mov rsi,rax; mov edi,OP_MUL; call s_ast_binary_new; jmp .sad_done
.sad_bin_mul_general:
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov r15,rax
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov [rsp],rax
    mov rdi,r15; call s_ast_is_zero_imm; test eax,eax; jz .sad_mul_da_live
    mov rdi,[rsp]; call s_ast_is_zero_imm; test eax,eax; jnz .sad_return_r15
    mov edi,OP_MUL; mov rsi,[rbx+SN_A]; mov rdx,[rsp]; call s_ast_binary_new; jmp .sad_done
.sad_mul_da_live:
    mov rdi,[rsp]; call s_ast_is_zero_imm; test eax,eax; jz .sad_mul_both_live
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rbx+SN_B]; call s_ast_binary_new; jmp .sad_done
.sad_mul_both_live:
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rbx+SN_B]; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov r15,rax
    mov edi,OP_MUL; mov rsi,[rbx+SN_A]; mov rdx,[rsp]; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov rdx,rax; mov rsi,r15; mov edi,OP_ADD; call s_ast_binary_new; jmp .sad_done
.sad_bin_div:
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov r15,rax
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov [rsp],rax
    mov rdi,[rsp]; call s_ast_is_zero_imm; test eax,eax; jz .sad_div_db_live
    mov rdi,r15; call s_ast_is_zero_imm; test eax,eax; jnz .sad_return_r15
    mov edi,OP_DIV; mov rsi,r15; mov rdx,[rbx+SN_B]; call s_ast_binary_new; jmp .sad_done
.sad_div_db_live:
    mov rdi,r15; call s_ast_is_zero_imm; test eax,eax; jz .sad_div_both_live
    mov edi,OP_MUL; mov rsi,[rbx+SN_A]; mov rdx,[rsp]; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov edi,OP_NEG; mov rsi,rax; call s_ast_unary_new; mov r15,rax
    jmp .sad_div_den
.sad_div_both_live:
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rbx+SN_B]; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov r15,rax
    mov edi,OP_MUL; mov rsi,[rbx+SN_A]; mov rdx,[rsp]; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov rdx,rax; mov rsi,r15; mov edi,OP_SUB; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov r15,rax
.sad_div_den:
    mov edi,OP_MUL; mov rsi,[rbx+SN_B]; mov rdx,[rbx+SN_B]; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov rdx,rax; mov rsi,r15; mov edi,OP_DIV; call s_ast_binary_new; jmp .sad_done
.sad_bin_min:
    mov edi,OP_LE; jmp .sad_bin_piecewise
.sad_bin_max:
    mov edi,OP_GE
.sad_bin_piecewise:
    mov [rsp+8],rdi
    mov rsi,[rbx+SN_A]; mov rdx,[rbx+SN_B]; call s_ast_binary_new; test rax,rax; jz .sad_fail
    mov r15,rax
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov [rsp],rax
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov rcx,rax
    call s_new_ast; test rax,rax; jz .sad_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],OP_SELECT
    mov [rax+SN_A],r15; mov rdx,[rsp]; mov [rax+SN_B],rdx; mov [rax+SN_C],rcx
    jmp .sad_done
.sad_bin_select:
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov [rsp],rax
    mov rdi,[rbx+SN_C]; mov rsi,r12; mov rdx,r13; call s_ast_diff; test rax,rax; jz .sad_fail
    mov r15,rax
    call s_new_ast; test rax,rax; jz .sad_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],OP_SELECT
    mov rdx,[rbx+SN_A]; mov [rax+SN_A],rdx; mov rdx,[rsp]; mov [rax+SN_B],rdx; mov [rax+SN_C],r15
    jmp .sad_done
.sad_fail:
    mov dword ptr [rip+s_error],1; xor eax,eax
.sad_done:
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Structured Fact Authority (1.3.35)
# A structured fact is compile-time only.  It owns a linked list of ordinary
# scalar AST facts.  No structured object, allocator, scheduler or runtime
# survives serialization.  Complex, high precision and small dense linear
# algebra therefore reuse exactly the old scalar ValueFact/Physical-DAG path.
# -----------------------------------------------------------------------------
s_ast_scalar_binary_new:
    # edi=op,rsi=a,rdx=b -> rax; never dispatches structured semantics.
    push rbx; push r12; push r13
    mov ebx,edi; mov r12,rsi; mov r13,rdx
    call s_new_ast; test rax,rax; jz .sasbn_done
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],ebx
    mov [rax+SN_A],r12; mov [rax+SN_B],r13
.sasbn_done: pop r13; pop r12; pop rbx; ret

s_struct_from_array:
    # edi=tag, esi=count, rdx=qword[count] component ASTs -> rax struct/0
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12d,esi; mov r13,rdx
    test r12d,r12d; jz .ssfa_fail
    xor r14d,r14d; xor r15d,r15d              # head/tail
.ssfa_loop:
    cmp r14d,r12d; jae .ssfa_wrap
    call s_new_ast; test rax,rax; jz .ssfa_fail
    mov dword ptr [rax+SN_KIND],NK_STRUCT_ELEM
    mov rcx,[r13+r14*8]; mov [rax+SN_A],rcx
    mov qword ptr [rax+SN_NEXT],0
    test r15,r15; jz .ssfa_first
    mov [r15+SN_NEXT],rax; mov r15,rax; jmp .ssfa_next
.ssfa_first:
    mov r15,rax; mov [rsp],rax                 # temporary head in saved-r15 slot is unsafe; use r13? no
    # store head in SN_B scratch of first cell by self-reference until wrapper
    mov [rax+SN_B],rax
.ssfa_next:
    inc r14d; jmp .ssfa_loop
.ssfa_wrap:
    # recover head by walking count-1 predecessors from tail is unavailable;
    # build head separately using a stack local in the corrected implementation.
    # This label is replaced below.
    jmp .ssfa_fail
.ssfa_fail:
    xor eax,eax
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Correct structured constructor with explicit local head/tail slots.
s_struct_build:
    # edi=tag, esi=count, rdx=qword[count] components -> rax
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov ebx,edi; mov r12d,esi; mov r13,rdx
    mov qword ptr [rsp],0; mov qword ptr [rsp+8],0
    xor r14d,r14d
.ssb_loop:
    cmp r14d,r12d; jae .ssb_wrap
    call s_new_ast; test rax,rax; jz .ssb_fail
    mov dword ptr [rax+SN_KIND],NK_STRUCT_ELEM
    mov rcx,[r13+r14*8]; mov [rax+SN_A],rcx; mov qword ptr [rax+SN_NEXT],0
    mov r15,[rsp+8]; test r15,r15; jz .ssb_first
    mov [r15+SN_NEXT],rax; mov [rsp+8],rax; jmp .ssb_next
.ssb_first:
    mov [rsp],rax; mov [rsp+8],rax
.ssb_next:
    inc r14d; jmp .ssb_loop
.ssb_wrap:
    call s_new_ast; test rax,rax; jz .ssb_fail
    mov dword ptr [rax+SN_KIND],NK_STRUCT
    mov dword ptr [rax+SN_OP],r12d
    mov [rax+SN_AUX],rbx
    mov rcx,[rsp]; mov [rax+SN_A],rcx
    jmp .ssb_done
.ssb_fail: xor eax,eax
.ssb_done:
    add rsp,16
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_struct_component:
    # rdi=struct, esi=index -> rax scalar component / 0
    test rdi,rdi; jz .ssc_no
    cmp dword ptr [rdi+SN_KIND],NK_STRUCT; jne .ssc_no
    cmp esi,dword ptr [rdi+SN_OP]; jae .ssc_no
    mov rax,[rdi+SN_A]
.ssc_loop:
    test esi,esi; jz .ssc_yes
    test rax,rax; jz .ssc_no
    mov rax,[rax+SN_NEXT]; dec esi; jmp .ssc_loop
.ssc_yes:
    test rax,rax; jz .ssc_no
    mov rax,[rax+SN_A]; ret
.ssc_no: xor eax,eax; ret

s_struct_zero:
    mov rdi,0x0000000000000000
    jmp s_ast_f64_bits_imm

s_struct_one:
    mov rdi,0x3ff0000000000000
    jmp s_ast_f64_bits_imm

s_struct_scalar_lift:
    # rdi=scalar AST, esi=target structured tag -> rax structured
    push rbx; push r12; sub rsp,32
    mov r12,rdi; mov ebx,esi
    mov [rsp],r12
    xor edi,edi; call s_ast_u64_imm; test rax,rax; jz .sssl_fail
    mov [rsp+8],rax; mov [rsp+16],rax; mov [rsp+24],rax
    cmp ebx,STF_COMPLEX; jne .sssl_fail
    mov edi,ebx; mov esi,2; mov rdx,rsp; call s_struct_build; jmp .sssl_done
.sssl_fail: xor eax,eax
.sssl_done: add rsp,32; pop r12; pop rbx; ret

s_struct_componentwise_binary:
    # edi=op, rsi=A struct, rdx=B struct -> same-tag struct.  Component
    # workspace scales with the represented structure; no 16-element matrix
    # tier survives here.
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; mov r12,rsi; mov r13,rdx
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .sscb_fail_nostack
    cmp dword ptr [r13+SN_KIND],NK_STRUCT; jne .sscb_fail_nostack
    mov r14,[r12+SN_AUX]; cmp r14,[r13+SN_AUX]; jne .sscb_fail_nostack
    mov r15d,dword ptr [r12+SN_OP]; cmp r15d,dword ptr [r13+SN_OP]; jne .sscb_fail_nostack
    test r15d,r15d; jz .sscb_fail_nostack
    mov eax,r15d; shl rax,3; add rax,15; and rax,-16
    sub rsp,rax
    xor ecx,ecx
.sscb_loop:
    cmp ecx,r15d; jae .sscb_build
    push rcx
    mov rdi,r12; mov esi,ecx; call s_struct_component; mov r8,rax
    pop rcx; push rcx; push r8
    mov rdi,r13; mov esi,ecx; call s_struct_component; mov r9,rax
    pop r8; pop rcx
    test r8,r8; jz .sscb_fail; test r9,r9; jz .sscb_fail
    push rcx
    mov edi,ebx; mov rsi,r8; mov rdx,r9; call s_ast_scalar_binary_new
    pop rcx; test rax,rax; jz .sscb_fail
    mov [rsp+rcx*8],rax
    inc ecx; jmp .sscb_loop
.sscb_build:
    mov edi,r14d; mov esi,r15d; mov rdx,rsp; call s_struct_build; jmp .sscb_done
.sscb_fail: xor eax,eax
.sscb_done:
    mov edx,r15d; shl rdx,3; add rdx,15; and rdx,-16
    add rsp,rdx
    jmp .sscb_epilogue
.sscb_fail_nostack:
    xor eax,eax
.sscb_epilogue:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_complex_binary:
    # edi=op,rsi=A complex,rdx=B complex -> complex
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,32
    mov ebx,edi; mov r12,rsi; mov r13,rdx
    mov rdi,r12; xor esi,esi; call s_struct_component; mov r14,rax
    mov rdi,r12; mov esi,1; call s_struct_component; mov r15,rax
    mov rdi,r13; xor esi,esi; call s_struct_component; mov [rsp+16],rax
    mov rdi,r13; mov esi,1; call s_struct_component; mov [rsp+24],rax
    test r14,r14; jz .scb_fail; test r15,r15; jz .scb_fail
    cmp ebx,OP_ADD; je .scb_addsub
    cmp ebx,OP_SUB; je .scb_addsub
    cmp ebx,OP_MUL; je .scb_mul
    cmp ebx,OP_DIV; je .scb_div
    jmp .scb_fail
.scb_addsub:
    mov edi,ebx; mov rsi,r14; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; mov [rsp],rax
    mov edi,ebx; mov rsi,r15; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov [rsp+8],rax
    jmp .scb_build
.scb_mul:
    # real=ac-bd; imag=ad+bc
    mov edi,OP_MUL; mov rsi,r14; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; mov [rsp],rax
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov rbx,rax
    mov edi,OP_SUB; mov rsi,[rsp]; mov rdx,rbx; call s_ast_scalar_binary_new; mov [rsp],rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; mov rcx,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rcx; call s_ast_scalar_binary_new; mov [rsp+8],rax
    jmp .scb_build
.scb_div:
    # denom=c*c+d*d; real=(ac+bd)/denom; imag=(bc-ad)/denom
    mov edi,OP_MUL; mov rsi,[rsp+16]; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,[rsp+24]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov rcx,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rcx; call s_ast_scalar_binary_new; mov [rsp],rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov rcx,rax
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rcx; call s_ast_scalar_binary_new; mov rbx,rax
    mov edi,OP_DIV; mov rsi,rbx; mov rdx,[rsp]; call s_ast_scalar_binary_new; mov [rsp],rax
    mov edi,OP_MUL; mov rsi,r15; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; mov rbx,rax
    mov edi,OP_MUL; mov rsi,r14; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov rcx,rax
    mov edi,OP_SUB; mov rsi,rbx; mov rdx,rcx; call s_ast_scalar_binary_new; mov rbx,rax
    # denominator must be rebuilt because rsp[0] now holds real; c^2+d^2 is cheap and CSE collapses it.
    mov edi,OP_MUL; mov rsi,[rsp+16]; mov rdx,[rsp+16]; call s_ast_scalar_binary_new; mov r14,rax
    mov edi,OP_MUL; mov rsi,[rsp+24]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new; mov r15,rax
    mov edi,OP_ADD; mov rsi,r14; mov rdx,r15; call s_ast_scalar_binary_new; mov rcx,rax
    mov edi,OP_DIV; mov rsi,rbx; mov rdx,rcx; call s_ast_scalar_binary_new; mov [rsp+8],rax
.scb_build:
    mov edi,STF_COMPLEX; mov esi,2; mov rdx,rsp; call s_struct_build; jmp .scb_done
.scb_fail: xor eax,eax
.scb_done:
    add rsp,32
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_dim:
    # edi=dimension-bearing matrix tag -> eax dimension /0.  Matrix/vector
    # identity occupies a structural tag domain; dimension is no longer squeezed
    # into the historical 8-bit family window.
    mov eax,edi
    cmp eax,STF_MATRIX_BASE+2; jb .smd_bad
    cmp eax,STF_VECTOR_BASE; jae .smd_bad
    sub eax,STF_MATRIX_BASE
    ret
.smd_bad: xor eax,eax; ret

s_matrix_tag_from_n:
    # edi=n>=2 -> eax matrix tag /0.  The caller's component-cardinality
    # representation proves the practical bound; no independent dimension cap.
    cmp edi,2; jb .smtfn_bad
    mov eax,edi
    add eax,STF_MATRIX_BASE
    jc .smtfn_bad
    cmp eax,STF_VECTOR_BASE; jae .smtfn_bad
    ret
.smtfn_bad: xor eax,eax; ret

s_matrix_mul_struct:
    # rdi=A,rsi=B same square matrix tag -> matrix struct.  The result scratch
    # is n^2-derived; matrix2/3/4 are merely surface aliases of this relation.
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi
    mov r15d,dword ptr [r12+SN_AUX]
    cmp r15d,dword ptr [r13+SN_AUX]; jne .smms_fail_nostack
    mov edi,r15d; call s_matrix_dim; test eax,eax; jz .smms_fail_nostack
    mov r14d,eax
    mov eax,r14d; imul rax,rax; shl rax,3
    add rax,64+15; and rax,-16
    sub rsp,rax
    # locals occupy the final 64 bytes of the dynamic frame.
    mov dword ptr [rsp+rax-64],0                  # i
.smms_i:
    mov eax,dword ptr [rsp+rax-64]               # rax is not frame size now: recompute below
    cmp eax,r14d; jae .smms_build
    # local addresses are recomputed from n because nested calls may clobber rax.
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov dword ptr [rsp+rdx-60],0                 # j
.smms_j:
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov eax,dword ptr [rsp+rdx-60]; cmp eax,r14d; jae .smms_next_i
    mov qword ptr [rsp+rdx-48],0                 # accumulator
    mov dword ptr [rsp+rdx-56],0                 # k
.smms_k:
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov eax,dword ptr [rsp+rdx-56]; cmp eax,r14d; jae .smms_store
    mov ecx,dword ptr [rsp+rdx-64]; imul ecx,r14d; add ecx,eax
    mov rdi,r12; mov esi,ecx; call s_struct_component; mov rbx,rax
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov ecx,dword ptr [rsp+rdx-56]; imul ecx,r14d; add ecx,dword ptr [rsp+rdx-60]
    mov rdi,r13; mov esi,ecx; call s_struct_component; mov r11,rax
    test rbx,rbx; jz .smms_fail; test r11,r11; jz .smms_fail
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r11; call s_ast_scalar_binary_new; test rax,rax; jz .smms_fail
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov rbx,[rsp+rdx-48]; test rbx,rbx; jz .smms_acc_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .smms_fail
.smms_acc_first:
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov [rsp+rdx-48],rax
    inc dword ptr [rsp+rdx-56]; jmp .smms_k
.smms_store:
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov eax,dword ptr [rsp+rdx-64]; imul eax,r14d; add eax,dword ptr [rsp+rdx-60]
    mov rcx,[rsp+rdx-48]; mov [rsp+rax*8],rcx
    inc dword ptr [rsp+rdx-60]; jmp .smms_j
.smms_next_i:
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    inc dword ptr [rsp+rdx-64]; jmp .smms_i_reenter
.smms_i_reenter:
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    mov eax,dword ptr [rsp+rdx-64]; cmp eax,r14d; jb .smms_j_reset
    jmp .smms_build
.smms_j_reset:
    mov dword ptr [rsp+rdx-60],0; jmp .smms_j
.smms_build:
    mov edi,r15d
    mov esi,r14d; imul esi,r14d
    mov rdx,rsp; call s_struct_build; jmp .smms_done
.smms_fail: xor eax,eax
.smms_done:
    mov edx,r14d; imul rdx,rdx; shl rdx,3; add rdx,64+15; and rdx,-16
    add rsp,rdx
    jmp .smms_epilogue
.smms_fail_nostack:
    xor eax,eax
.smms_epilogue:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_transpose_struct:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]; mov edi,r13d; call s_matrix_dim; test eax,eax; jz .smts_fail_nostack
    mov r14d,eax; mov r15d,eax; imul r15d,eax
    mov eax,r15d; shl rax,3; add rax,15; and rax,-16; sub rsp,rax
    xor ebx,ebx
.smts_loop:
    cmp ebx,r15d; jae .smts_build
    mov eax,ebx; xor edx,edx; div r14d
    mov ecx,edx; imul ecx,r14d; add ecx,eax
    mov rdi,r12; mov esi,ecx; call s_struct_component; test rax,rax; jz .smts_fail
    mov [rsp+rbx*8],rax; inc ebx; jmp .smts_loop
.smts_build:
    mov edi,r13d; mov esi,r15d; mov rdx,rsp; call s_struct_build; jmp .smts_done
.smts_fail: xor eax,eax
.smts_done:
    mov edx,r15d; shl rdx,3; add rdx,15; and rdx,-16; add rsp,rdx
    jmp .smts_epilogue
.smts_fail_nostack: xor eax,eax
.smts_epilogue: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_trace_struct:
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]; mov edi,r13d; call s_matrix_dim; test eax,eax; jz .smtrs_fail
    mov r14d,eax; xor ebx,ebx; xor r13d,r13d
.smtrs_loop:
    cmp ebx,r14d; jae .smtrs_done_loop
    mov eax,ebx; imul eax,r14d; add eax,ebx
    mov rdi,r12; mov esi,eax; call s_struct_component; test rax,rax; jz .smtrs_fail
    test r13,r13; jz .smtrs_first
    mov edi,OP_ADD; mov rsi,r13; mov rdx,rax; call s_ast_scalar_binary_new; test rax,rax; jz .smtrs_fail
.smtrs_first:
    mov r13,rax; inc ebx; jmp .smtrs_loop
.smtrs_done_loop: mov rax,r13; jmp .smtrs_done
.smtrs_fail: xor eax,eax
.smtrs_done: pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_identity_struct:
    # edi=matrix tag -> identity structured matrix, dimension-derived scratch.
    push rbx; push r12; push r13
    mov r13d,edi; call s_matrix_dim; test eax,eax; jz .smis_fail_nostack
    mov r12d,eax; mov eax,r12d; imul eax,r12d; mov ebx,eax
    mov eax,ebx; shl rax,3; add rax,15; and rax,-16; sub rsp,rax
    xor ecx,ecx
.smis_loop:
    cmp ecx,ebx; jae .smis_build
    mov eax,ecx; xor edx,edx; div r12d
    push rcx
    cmp eax,edx; jne .smis_zero
    call s_struct_one; jmp .smis_put
.smis_zero: call s_struct_zero
.smis_put:
    pop rcx; test rax,rax; jz .smis_fail
    mov [rsp+rcx*8],rax; inc ecx; jmp .smis_loop
.smis_build:
    mov edi,r13d; mov esi,ebx; mov rdx,rsp; call s_struct_build; jmp .smis_done
.smis_fail: xor eax,eax
.smis_done:
    mov edx,ebx; shl rdx,3; add rdx,15; and rdx,-16; add rsp,rdx
    jmp .smis_epilogue
.smis_fail_nostack: xor eax,eax
.smis_epilogue: pop r13; pop r12; pop rbx; ret

s_matrix_scale_struct:
    # rdi=matrix,rsi=scalar -> matrix.  Result storage follows component count.
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r14d,dword ptr [r12+SN_AUX]; mov edi,r14d; call s_matrix_dim; test eax,eax; jz .smscs_fail_nostack
    imul eax,eax; mov ebx,eax
    mov eax,ebx; shl rax,3; add rax,15; and rax,-16; sub rsp,rax
    xor r15d,r15d
.smscs_loop:
    cmp r15d,ebx; jae .smscs_build
    mov rdi,r12; mov esi,r15d; call s_struct_component; test rax,rax; jz .smscs_fail
    mov edi,OP_MUL; mov rsi,rax; mov rdx,r13; call s_ast_scalar_binary_new; test rax,rax; jz .smscs_fail
    mov [rsp+r15*8],rax; inc r15d; jmp .smscs_loop
.smscs_build:
    mov edi,r14d; mov esi,ebx; mov rdx,rsp; call s_struct_build; jmp .smscs_done
.smscs_fail: xor eax,eax
.smscs_done:
    mov edx,ebx; shl rdx,3; add rdx,15; and rdx,-16; add rsp,rdx
    jmp .smscs_epilogue
.smscs_fail_nostack: xor eax,eax
.smscs_epilogue: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_make_spd:
    # rdi=A matrix,rsi=epsilon scalar -> A^T A + eps I
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov r14d,dword ptr [r12+SN_AUX]
    mov rdi,r12; call s_matrix_transpose_struct; test rax,rax; jz .smspd_fail
    mov rdi,rax; mov rsi,r12; call s_matrix_mul_struct; test rax,rax; jz .smspd_fail; mov rbx,rax
    mov edi,r14d; call s_matrix_identity_struct; test rax,rax; jz .smspd_fail
    mov rdi,rax; mov rsi,r13; call s_matrix_scale_struct; test rax,rax; jz .smspd_fail
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_struct_componentwise_binary; jmp .smspd_done
.smspd_fail: xor eax,eax
.smspd_done: pop r14; pop r13; pop r12; pop rbx; ret

# ---- Structured small dense linear algebra: all compile-time AST construction ----
s_matrix_cholesky:
    # rdi=A SPD matrix -> lower-triangular L.  The workset is n^2-derived;
    # decomposition capacity is no longer a sixteen-pointer surface property.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,64
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]
    mov edi,r13d; call s_matrix_dim; test eax,eax; jz .smch_fail
    mov r14d,eax
    mov edi,eax; imul rdi,rdi; shl rdi,3; call s_alloc_pointer_workset
    test rax,rax; jz .smch_fail; mov [rsp],rax
    mov dword ptr [rsp+8],0                         # i
.smch_i:
    mov eax,dword ptr [rsp+8]; cmp eax,r14d; jae .smch_build
    mov dword ptr [rsp+12],0                        # j
.smch_j:
    mov eax,dword ptr [rsp+12]; cmp eax,r14d; jae .smch_next_i
    cmp eax,dword ptr [rsp+8]; jbe .smch_compute
    call s_struct_zero
    mov ecx,dword ptr [rsp+8]; imul ecx,r14d; add ecx,dword ptr [rsp+12]
    mov rdx,[rsp]; mov [rdx+rcx*8],rax
    jmp .smch_next_j
.smch_compute:
    mov ecx,dword ptr [rsp+8]; imul ecx,r14d; add ecx,dword ptr [rsp+12]
    mov rdi,r12; mov esi,ecx; call s_struct_component
    test rax,rax; jz .smch_fail; mov [rsp+24],rax
    mov dword ptr [rsp+16],0                        # k
.smch_k:
    mov eax,dword ptr [rsp+16]; cmp eax,dword ptr [rsp+12]; jae .smch_finish
    mov rdx,[rsp]
    mov ecx,dword ptr [rsp+8]; imul ecx,r14d; add ecx,eax; mov rbx,[rdx+rcx*8]
    mov ecx,dword ptr [rsp+12]; imul ecx,r14d; add ecx,eax; mov r15,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new
    test rax,rax; jz .smch_fail
    mov edi,OP_SUB; mov rsi,[rsp+24]; mov rdx,rax; call s_ast_scalar_binary_new
    test rax,rax; jz .smch_fail; mov [rsp+24],rax
    inc dword ptr [rsp+16]; jmp .smch_k
.smch_finish:
    mov eax,dword ptr [rsp+8]; cmp eax,dword ptr [rsp+12]; jne .smch_offdiag
    mov edi,OP_SQRT; mov rsi,[rsp+24]; call s_ast_unary_new; jmp .smch_store
.smch_offdiag:
    mov ecx,dword ptr [rsp+12]; imul ecx,r14d; add ecx,dword ptr [rsp+12]
    mov rdx,[rsp]; mov rdx,[rdx+rcx*8]
    mov edi,OP_DIV; mov rsi,[rsp+24]; call s_ast_scalar_binary_new
.smch_store:
    test rax,rax; jz .smch_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .smch_fail
    mov ecx,dword ptr [rsp+8]; imul ecx,r14d; add ecx,dword ptr [rsp+12]
    mov rdx,[rsp]; mov [rdx+rcx*8],rax
.smch_next_j:
    inc dword ptr [rsp+12]; jmp .smch_j
.smch_next_i:
    inc dword ptr [rsp+8]; jmp .smch_i
.smch_build:
    mov edi,r13d; mov esi,r14d; imul esi,r14d; mov rdx,[rsp]; call s_struct_build; jmp .smch_done
.smch_fail: xor eax,eax
.smch_done: add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_orthogonalize:
    # Modified Gram-Schmidt columns, rdi=A -> Q.  Q[n^2] and v[n] are
    # structure-derived compiler worksets rather than a 4x4 local array.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,64
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]
    mov edi,r13d; call s_matrix_dim; test eax,eax; jz .smog_fail; mov r14d,eax
    mov edi,eax; imul rdi,rdi; add rdi,rax; shl rdi,3; call s_alloc_pointer_workset
    test rax,rax; jz .smog_fail; mov [rsp],rax
    mov ecx,r14d; imul rcx,rcx; lea rcx,[rax+rcx*8]; mov [rsp+8],rcx
    mov dword ptr [rsp+16],0                       # column j
.smog_col:
    mov eax,dword ptr [rsp+16]; cmp eax,r14d; jae .smog_build
    mov dword ptr [rsp+20],0                       # row i
.smog_copyv:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smog_proj_start
    mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+16]
    mov rdi,r12; mov esi,ecx; call s_struct_component; test rax,rax; jz .smog_fail
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+20]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+20]; jmp .smog_copyv
.smog_proj_start:
    mov dword ptr [rsp+24],0                       # previous col p
.smog_proj:
    mov eax,dword ptr [rsp+24]; cmp eax,dword ptr [rsp+16]; jae .smog_norm
    mov qword ptr [rsp+32],0; mov dword ptr [rsp+20],0
.smog_dot:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smog_apply
    mov rdx,[rsp]
    mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+24]; mov rbx,[rdx+rcx*8]
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+20]; mov r15,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new; test rax,rax; jz .smog_fail
    mov rbx,[rsp+32]; test rbx,rbx; jz .smog_dot_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smog_dot_first:
    mov [rsp+32],rax; inc dword ptr [rsp+20]; jmp .smog_dot
.smog_apply:
    mov dword ptr [rsp+20],0
.smog_apply_loop:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smog_next_proj
    mov rdx,[rsp]
    mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+24]; mov rbx,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,[rsp+32]; mov rdx,rbx; call s_ast_scalar_binary_new; mov r15,rax
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+20]; mov rbx,[rdx+rcx*8]
    mov edi,OP_SUB; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .smog_fail
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+20]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+20]; jmp .smog_apply_loop
.smog_next_proj:
    inc dword ptr [rsp+24]; jmp .smog_proj
.smog_norm:
    mov qword ptr [rsp+32],0; mov dword ptr [rsp+20],0
.smog_norm_loop:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smog_norm_sqrt
    mov rdx,[rsp+8]; mov rsi,[rdx+rax*8]; mov edi,OP_SQUARE; call s_ast_unary_new
    mov rbx,[rsp+32]; test rbx,rbx; jz .smog_norm_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smog_norm_first:
    mov [rsp+32],rax; inc dword ptr [rsp+20]; jmp .smog_norm_loop
.smog_norm_sqrt:
    mov edi,OP_SQRT; mov rsi,[rsp+32]; call s_ast_unary_new; mov [rsp+40],rax
    mov dword ptr [rsp+20],0
.smog_store_q:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smog_next_col
    mov rdx,[rsp+8]; mov rsi,[rdx+rax*8]; mov edi,OP_DIV; mov rdx,[rsp+40]; call s_ast_scalar_binary_new
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .smog_fail
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+20]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+20]; jmp .smog_store_q
.smog_next_col:
    inc dword ptr [rsp+16]; jmp .smog_col
.smog_build:
    mov edi,r13d; mov esi,r14d; imul esi,r14d; mov rdx,[rsp]; call s_struct_build; jmp .smog_done
.smog_fail: xor eax,eax
.smog_done: add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_qr_r:
    push rbx; push r12
    mov r12,rdi; call s_matrix_orthogonalize; test rax,rax; jz .smqr_fail; mov rbx,rax
    mov rdi,rbx; call s_matrix_transpose_struct; test rax,rax; jz .smqr_fail
    mov rdi,rax; mov rsi,r12; call s_matrix_mul_struct; jmp .smqr_done
.smqr_fail: xor eax,eax
.smqr_done: pop r12; pop rbx; ret

s_matrix_lu_struct:
    # rdi=A, esi=0 return L /1 return U. Doolittle, no pivoting.  L/U are
    # dimension-derived compiler worksets.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,64
    mov r12,rdi; mov dword ptr [rsp+40],esi
    mov r13d,dword ptr [r12+SN_AUX]; mov edi,r13d; call s_matrix_dim
    test eax,eax; jz .smlu_fail; mov r14d,eax
    mov edi,eax; imul rdi,rdi; shl rdi,4; call s_alloc_pointer_workset
    test rax,rax; jz .smlu_fail; mov [rsp],rax
    mov ecx,r14d; imul rcx,rcx; lea rcx,[rax+rcx*8]; mov [rsp+8],rcx
    call s_struct_zero; mov r15,rax; xor ebx,ebx
.smlu_zero:
    mov eax,r14d; imul eax,r14d; cmp ebx,eax; jae .smlu_i_start
    mov rdx,[rsp]; mov [rdx+rbx*8],r15; mov rdx,[rsp+8]; mov [rdx+rbx*8],r15
    inc ebx; jmp .smlu_zero
.smlu_i_start:
    mov dword ptr [rsp+16],0
.smlu_i:
    mov eax,dword ptr [rsp+16]; cmp eax,r14d; jae .smlu_build
    mov dword ptr [rsp+20],eax
.smlu_u_k:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smlu_l_start
    mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,eax
    mov rdi,r12; mov esi,ecx; call s_struct_component; mov [rsp+32],rax
    mov dword ptr [rsp+24],0
.smlu_u_j:
    mov eax,dword ptr [rsp+24]; cmp eax,dword ptr [rsp+16]; jae .smlu_u_store
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,eax; mov rbx,[rdx+rcx*8]
    mov rdx,[rsp+8]; mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov r15,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new
    mov edi,OP_SUB; mov rsi,[rsp+32]; mov rdx,rax; call s_ast_scalar_binary_new; mov [rsp+32],rax
    inc dword ptr [rsp+24]; jmp .smlu_u_j
.smlu_u_store:
    mov rdi,[rsp+32]; call s_materialize_scalar_ast; test rax,rax; jz .smlu_fail
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+20]
    mov [rdx+rcx*8],rax
    inc dword ptr [rsp+20]; jmp .smlu_u_k
.smlu_l_start:
    mov eax,dword ptr [rsp+16]; mov dword ptr [rsp+20],eax
.smlu_l_k:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smlu_next_i
    cmp eax,dword ptr [rsp+16]; jne .smlu_l_compute
    call s_struct_one
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+20]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov [rdx+rcx*8],rax
    jmp .smlu_l_next
.smlu_l_compute:
    mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov rdi,r12; mov esi,ecx; call s_struct_component; mov [rsp+32],rax
    mov dword ptr [rsp+24],0
.smlu_l_j:
    mov eax,dword ptr [rsp+24]; cmp eax,dword ptr [rsp+16]; jae .smlu_l_div
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+20]; imul ecx,r14d; add ecx,eax; mov rbx,[rdx+rcx*8]
    mov rdx,[rsp+8]; mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov r15,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new
    mov edi,OP_SUB; mov rsi,[rsp+32]; mov rdx,rax; call s_ast_scalar_binary_new; mov [rsp+32],rax
    inc dword ptr [rsp+24]; jmp .smlu_l_j
.smlu_l_div:
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov rdx,[rdx+rcx*8]
    mov edi,OP_DIV; mov rsi,[rsp+32]; call s_ast_scalar_binary_new
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .smlu_fail
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+20]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov [rdx+rcx*8],rax
.smlu_l_next:
    inc dword ptr [rsp+20]; jmp .smlu_l_k
.smlu_next_i:
    inc dword ptr [rsp+16]; jmp .smlu_i
.smlu_build:
    cmp dword ptr [rsp+40],0; jne .smlu_build_u
    mov rdx,[rsp]; jmp .smlu_build_do
.smlu_build_u:
    mov rdx,[rsp+8]
.smlu_build_do:
    mov edi,r13d; mov esi,r14d; imul esi,r14d; call s_struct_build; jmp .smlu_done
.smlu_fail: xor eax,eax
.smlu_done: add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_ldlt_struct:
    # rdi=A, esi=0 return L /1 return diagonal D matrix.  L/D storage scales
    # with the MatrixFact dimension.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,64
    mov r12,rdi; mov dword ptr [rsp+40],esi
    mov r13d,dword ptr [r12+SN_AUX]; mov edi,r13d; call s_matrix_dim
    test eax,eax; jz .smld_fail; mov r14d,eax
    mov edi,eax; imul rdi,rdi; shl rdi,4; call s_alloc_pointer_workset
    test rax,rax; jz .smld_fail; mov [rsp],rax
    mov ecx,r14d; imul rcx,rcx; lea rcx,[rax+rcx*8]; mov [rsp+8],rcx
    call s_struct_zero; mov r15,rax; xor ebx,ebx
.smld_zero:
    mov eax,r14d; imul eax,r14d; cmp ebx,eax; jae .smld_i_start
    mov rdx,[rsp]; mov [rdx+rbx*8],r15; mov rdx,[rsp+8]; mov [rdx+rbx*8],r15
    inc ebx; jmp .smld_zero
.smld_i_start:
    mov dword ptr [rsp+16],0
.smld_i:
    mov eax,dword ptr [rsp+16]; cmp eax,r14d; jae .smld_build
    call s_struct_one
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov [rdx+rcx*8],rax
    mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov rdi,r12; mov esi,ecx; call s_struct_component; mov [rsp+32],rax
    mov dword ptr [rsp+24],0
.smld_dsum:
    mov eax,dword ptr [rsp+24]; cmp eax,dword ptr [rsp+16]; jae .smld_dstore
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,eax; mov rbx,[rdx+rcx*8]
    mov edi,OP_SQUARE; mov rsi,rbx; call s_ast_unary_new; mov rbx,rax
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+24]; imul ecx,r14d; add ecx,dword ptr [rsp+24]; mov r15,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new
    mov edi,OP_SUB; mov rsi,[rsp+32]; mov rdx,rax; call s_ast_scalar_binary_new; mov [rsp+32],rax
    inc dword ptr [rsp+24]; jmp .smld_dsum
.smld_dstore:
    mov rdi,[rsp+32]; call s_materialize_scalar_ast; test rax,rax; jz .smld_fail
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov [rdx+rcx*8],rax
    mov eax,dword ptr [rsp+16]; inc eax; mov dword ptr [rsp+20],eax
.smld_j:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .smld_next_i
    mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov rdi,r12; mov esi,ecx; call s_struct_component; mov [rsp+32],rax
    mov dword ptr [rsp+24],0
.smld_lsum:
    mov eax,dword ptr [rsp+24]; cmp eax,dword ptr [rsp+16]; jae .smld_ldiv
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+20]; imul ecx,r14d; add ecx,eax; mov rbx,[rdx+rcx*8]
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,eax; mov r15,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new; mov rbx,rax
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+24]; imul ecx,r14d; add ecx,dword ptr [rsp+24]; mov r15,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r15; call s_ast_scalar_binary_new
    mov edi,OP_SUB; mov rsi,[rsp+32]; mov rdx,rax; call s_ast_scalar_binary_new; mov [rsp+32],rax
    inc dword ptr [rsp+24]; jmp .smld_lsum
.smld_ldiv:
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov rdx,[rdx+rcx*8]
    mov edi,OP_DIV; mov rsi,[rsp+32]; call s_ast_scalar_binary_new
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .smld_fail
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+20]; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+20]; jmp .smld_j
.smld_next_i:
    inc dword ptr [rsp+16]; jmp .smld_i
.smld_build:
    cmp dword ptr [rsp+40],0; je .smld_build_l
    mov rdx,[rsp+8]; jmp .smld_do
.smld_build_l:
    mov rdx,[rsp]
.smld_do:
    mov edi,r13d; mov esi,r14d; imul esi,r14d; call s_struct_build; jmp .smld_done
.smld_fail: xor eax,eax
.smld_done: add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_inverse_struct:
    # Gauss-Jordan with dataflow partial pivoting. A and accumulator are
    # dimension-derived pointer worksets; no fixed 4x4 inverse tier survives.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,80
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]; mov edi,r13d; call s_matrix_dim
    test eax,eax; jz .sminv_fail; mov r14d,eax
    mov edi,eax; imul rdi,rdi; shl rdi,4; call s_alloc_pointer_workset
    test rax,rax; jz .sminv_fail; mov [rsp],rax
    mov ecx,r14d; imul rcx,rcx; lea rcx,[rax+rcx*8]; mov [rsp+8],rcx
    xor ebx,ebx
.sminv_init:
    mov eax,r14d; imul eax,r14d; cmp ebx,eax; jae .sminv_p_start
    mov rdi,r12; mov esi,ebx; call s_struct_component; mov rdx,[rsp]; mov [rdx+rbx*8],rax
    mov eax,ebx; xor edx,edx; div r14d; cmp eax,edx; jne .sminv_z
    call s_struct_one; jmp .sminv_iput
.sminv_z:
    call s_struct_zero
.sminv_iput:
    mov rdx,[rsp+8]; mov [rdx+rbx*8],rax; inc ebx; jmp .sminv_init
.sminv_p_start:
    mov dword ptr [rsp+16],0                       # p
.sminv_p:
    mov eax,dword ptr [rsp+16]; cmp eax,r14d; jae .sminv_build
    mov eax,dword ptr [rsp+16]; inc eax; mov dword ptr [rsp+28],eax # candidate row
.sminv_pivot_row:
    mov eax,dword ptr [rsp+28]; cmp eax,r14d; jae .sminv_pivot_done
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+16]
    mov rsi,[rdx+rcx*8]; mov edi,OP_ABS; call s_ast_unary_new; test rax,rax; jz .sminv_fail; mov [rsp+40],rax
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+28]; imul ecx,r14d; add ecx,dword ptr [rsp+16]
    mov rsi,[rdx+rcx*8]; mov edi,OP_ABS; call s_ast_unary_new; test rax,rax; jz .sminv_fail
    mov edi,OP_GT; mov rsi,rax; mov rdx,[rsp+40]; call s_ast_scalar_binary_new; test rax,rax; jz .sminv_fail; mov [rsp+48],rax
    mov dword ptr [rsp+32],0                       # col
.sminv_pivot_col:
    mov eax,dword ptr [rsp+32]; cmp eax,r14d; jae .sminv_pivot_next_row
    mov rdx,[rsp]
    mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,eax; mov rbx,[rdx+rcx*8]
    mov ecx,dword ptr [rsp+28]; imul ecx,r14d; add ecx,eax; mov r15,[rdx+rcx*8]
    mov rdi,[rsp+48]; mov rsi,r15; mov rdx,rbx; call s_ast_select_new; test rax,rax; jz .sminv_fail; mov [rsp+56],rax
    mov rdi,[rsp+48]; mov rsi,rbx; mov rdx,r15; call s_ast_select_new; test rax,rax; jz .sminv_fail
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+28]; imul ecx,r14d; add ecx,dword ptr [rsp+32]; mov [rdx+rcx*8],rax
    mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+32]; mov rax,[rsp+56]; mov [rdx+rcx*8],rax
    mov rdx,[rsp+8]
    mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+32]; mov rbx,[rdx+rcx*8]
    mov ecx,dword ptr [rsp+28]; imul ecx,r14d; add ecx,dword ptr [rsp+32]; mov r15,[rdx+rcx*8]
    mov rdi,[rsp+48]; mov rsi,r15; mov rdx,rbx; call s_ast_select_new; test rax,rax; jz .sminv_fail; mov [rsp+56],rax
    mov rdi,[rsp+48]; mov rsi,rbx; mov rdx,r15; call s_ast_select_new; test rax,rax; jz .sminv_fail
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+28]; imul ecx,r14d; add ecx,dword ptr [rsp+32]; mov [rdx+rcx*8],rax
    mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+32]; mov rax,[rsp+56]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+32]; jmp .sminv_pivot_col
.sminv_pivot_next_row:
    inc dword ptr [rsp+28]; jmp .sminv_pivot_row
.sminv_pivot_done:
    mov rdx,[rsp]; mov eax,dword ptr [rsp+16]; mov ecx,eax; imul ecx,r14d; add ecx,eax
    mov r15,[rdx+rcx*8]; mov [rsp+40],r15          # pivot
    mov dword ptr [rsp+20],0                       # j
.sminv_scale:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .sminv_elim_start
    mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,eax
    mov rdx,[rsp]; mov rsi,[rdx+rcx*8]; mov edi,OP_DIV; mov rdx,[rsp+40]; call s_ast_scalar_binary_new
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov [rdx+rcx*8],rax
    mov rdx,[rsp+8]; mov rsi,[rdx+rcx*8]; mov edi,OP_DIV; mov rdx,[rsp+40]; call s_ast_scalar_binary_new
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+20]; jmp .sminv_scale
.sminv_elim_start:
    mov dword ptr [rsp+24],0                       # i
.sminv_elim_i:
    mov eax,dword ptr [rsp+24]; cmp eax,r14d; jae .sminv_next_p
    cmp eax,dword ptr [rsp+16]; je .sminv_elim_next
    mov rdx,[rsp]; mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+16]; mov r15,[rdx+rcx*8]
    mov dword ptr [rsp+20],0
.sminv_elim_j:
    mov eax,dword ptr [rsp+20]; cmp eax,r14d; jae .sminv_elim_next
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,eax; mov rbx,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,r15; mov rdx,rbx; call s_ast_scalar_binary_new; mov rbx,rax
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+24]; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov rsi,[rdx+rcx*8]
    mov edi,OP_SUB; mov rdx,rbx; call s_ast_scalar_binary_new
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+24]; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov [rdx+rcx*8],rax
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+16]; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov rbx,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,r15; mov rdx,rbx; call s_ast_scalar_binary_new; mov rbx,rax
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+24]; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov rsi,[rdx+rcx*8]
    mov edi,OP_SUB; mov rdx,rbx; call s_ast_scalar_binary_new
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+24]; imul ecx,r14d; add ecx,dword ptr [rsp+20]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+20]; jmp .sminv_elim_j
.sminv_elim_next:
    inc dword ptr [rsp+24]; jmp .sminv_elim_i
.sminv_next_p:
    inc dword ptr [rsp+16]; jmp .sminv_p
.sminv_build:
    mov edi,r13d; mov esi,r14d; imul esi,r14d; mov rdx,[rsp+8]; call s_struct_build; jmp .sminv_done
.sminv_fail: xor eax,eax
.sminv_done: add rsp,80; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_exp_struct:
    # rdi=A, rsi=Taylor nonzero-term count. Scaling-and-squaring over the existing matrix substrate.  A is scaled by
    # 1/4; the historical default is 12 terms, with each term checkpointed
    # into old scalar bindings, then the result is squared twice.  No matrix
    # runtime or solver object survives.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16; mov [rsp],rsi
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]
    mov rdi,0x3fd0000000000000; call s_math_const_bits
    mov rsi,rax; mov rdi,r12; call s_matrix_scale_struct; mov r12,rax; test r12,r12; jz .smex_fail
    mov edi,r13d; call s_matrix_identity_struct; test rax,rax; jz .smex_fail
    mov rbx,rax; mov r14,rax; mov r15,1
.smex_loop:
    cmp r15,[rsp]; ja .smex_square1
    mov rdi,r14; mov rsi,r12; call s_matrix_mul_struct; mov r14,rax; test r14,r14; jz .smex_fail
    mov rdi,r15; call s_math_small_u64_f64; mov rdx,rax
    call s_struct_one; mov rsi,rax; mov edi,OP_DIV; call s_ast_scalar_binary_new; test rax,rax; jz .smex_fail
    mov rsi,rax; mov rdi,r14; call s_matrix_scale_struct; mov r14,rax; test r14,r14; jz .smex_fail
    mov rdi,r14; call s_materialize_struct; mov r14,rax; test r14,r14; jz .smex_fail
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,r14; call s_struct_componentwise_binary; mov rbx,rax; test rbx,rbx; jz .smex_fail
    inc r15; jmp .smex_loop
.smex_square1:
    mov rdi,rbx; mov rsi,rbx; call s_matrix_mul_struct; mov rbx,rax; test rbx,rbx; jz .smex_fail
    mov rdi,rbx; call s_materialize_struct; mov rbx,rax; test rbx,rbx; jz .smex_fail
.smex_square2:
    mov rdi,rbx; mov rsi,rbx; call s_matrix_mul_struct; mov rbx,rax; test rbx,rbx; jz .smex_fail
    mov rdi,rbx; call s_materialize_struct; mov rbx,rax; test rbx,rbx; jz .smex_fail
    mov rax,rbx; jmp .smex_done
.smex_fail: xor eax,eax
.smex_done: add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_log_struct:
    # rdi=A, rsi=extra odd-series refinements after the seed Y.
    # atanh series log(A)=2*(Y+Y^3/3+Y^5/5+...), Y=(A-I)(A+I)^-1.
    # Raw powers and partial sums are checkpointed into the old scalar DAG.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov [rsp+8],rsi
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]
    mov edi,r13d; call s_matrix_identity_struct; test rax,rax; jz .smlog_fail; mov r14,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r14; call s_struct_componentwise_binary; mov rbx,rax
    mov edi,OP_ADD; mov rsi,r12; mov rdx,r14; call s_struct_componentwise_binary; mov rdi,rax; call s_matrix_inverse_struct; test rax,rax; jz .smlog_fail
    mov rdi,rbx; mov rsi,rax; call s_matrix_mul_struct; mov r14,rax; mov r15,rax
    test r14,r14; jz .smlog_fail
    mov rdi,r14; call s_materialize_struct; mov r14,rax; mov r15,rax; test r14,r14; jz .smlog_fail
    mov rdi,r14; mov rsi,r14; call s_matrix_mul_struct; mov r12,rax; test r12,r12; jz .smlog_fail
    mov rdi,r12; call s_materialize_struct; mov r12,rax; test r12,r12; jz .smlog_fail
    mov qword ptr [rsp],3
.smlog_loop:
    cmp qword ptr [rsp+8],0; je .smlog_scale
    mov rdi,r15; mov rsi,r12; call s_matrix_mul_struct; mov r15,rax; test r15,r15; jz .smlog_fail
    mov rdi,r15; call s_materialize_struct; mov r15,rax; test r15,r15; jz .smlog_fail
    mov rdi,[rsp]; call s_math_small_u64_f64; mov rdx,rax
    call s_struct_one; mov rsi,rax; mov edi,OP_DIV; call s_ast_scalar_binary_new; test rax,rax; jz .smlog_fail
    mov rsi,rax; mov rdi,r15; call s_matrix_scale_struct; mov rbx,rax; test rbx,rbx; jz .smlog_fail
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rbx; call s_struct_componentwise_binary; mov r14,rax; test r14,r14; jz .smlog_fail
    add qword ptr [rsp],2; dec qword ptr [rsp+8]; jmp .smlog_loop
.smlog_scale:
    mov rdi,0x4000000000000000; call s_math_const_bits; mov rsi,rax; mov rdi,r14; call s_matrix_scale_struct
    jmp .smlog_done
.smlog_fail: xor eax,eax
.smlog_done: add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_sqrt_struct:
    # rdi=A, rsi=Newton refinements for SPD matrices.
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi; mov rbx,r12; xor r14d,r14d
.smsqrt_loop:
    cmp r14,r13; jae .smsqrt_ok
    mov rdi,rbx; call s_matrix_inverse_struct; test rax,rax; jz .smsqrt_fail
    mov rdi,r12; mov rsi,rax; call s_matrix_mul_struct; test rax,rax; jz .smsqrt_fail
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_struct_componentwise_binary; mov rbx,rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits; mov rsi,rax; mov rdi,rbx; call s_matrix_scale_struct; mov rbx,rax
    test rbx,rbx; jz .smsqrt_fail
    mov rdi,rbx; call s_materialize_struct; mov rbx,rax; test rbx,rbx; jz .smsqrt_fail
    inc r14; jmp .smsqrt_loop
.smsqrt_ok: mov rax,rbx; jmp .smsqrt_done
.smsqrt_fail: xor eax,eax
.smsqrt_done: pop r14; pop r13; pop r12; pop rbx; ret

s_vector_tag_from_n:
    # One dimension-bearing vector family, parallel to Structured Matrix.
    # Dimension comes from the matrix structural fact that births the vector.
    cmp edi,2; jb .svtn_bad
    mov eax,edi
    add eax,STF_VECTOR_BASE
    jc .svtn_bad
    ret
.svtn_bad: xor eax,eax; ret

s_matrix_eig_struct:
    # Symmetric matrix power-deflation. rdi=A, esi=0 values /1 vectors,
    # rdx=power iterations.  All pointer worksets scale with n; no 4x4 tier.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,128
    mov r12,rdi; mov dword ptr [rsp+40],esi; mov [rsp+48],rdx
    mov r13d,dword ptr [r12+SN_AUX]; mov dword ptr [rsp+96],r13d; mov edi,r13d; call s_matrix_dim
    test eax,eax; jz .smeig_fail; mov r14d,eax
    # vectors[n^2] + evals[n] + v[n] + w[n] + deflation[n^2]
    mov edi,eax; imul rdi,rdi; add rdi,rdi
    mov ecx,eax; imul ecx,3; add rdi,rcx; shl rdi,3; call s_alloc_pointer_workset
    test rax,rax; jz .smeig_fail
    mov [rsp],rax                                           # vectors
    mov rcx,r14; imul rcx,rcx; lea rdx,[rax+rcx*8]; mov [rsp+8],rdx  # evals
    lea rdx,[rdx+r14*8]; mov [rsp+16],rdx                   # v
    lea rdx,[rdx+r14*8]; mov [rsp+24],rdx                   # w
    lea rdx,[rdx+r14*8]; mov [rsp+32],rdx                   # deflation matrix scratch
    mov r15,r12; mov dword ptr [rsp+56],0                   # eigenpair p
.smeig_pair:
    mov eax,dword ptr [rsp+56]; cmp eax,r14d; jae .smeig_build
    mov dword ptr [rsp+60],0
.smeig_seed:
    mov eax,dword ptr [rsp+60]; cmp eax,r14d; jae .smeig_iter_start
    cmp eax,dword ptr [rsp+56]; jne .smeig_seed_half
    call s_struct_one; jmp .smeig_seed_put
.smeig_seed_half:
    mov rdi,0x3fe0000000000000; call s_math_const_bits
.smeig_seed_put:
    mov rdx,[rsp+16]; mov ecx,dword ptr [rsp+60]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+60]; jmp .smeig_seed
.smeig_iter_start:
    mov qword ptr [rsp+72],0
.smeig_iter:
    mov rax,[rsp+72]; cmp rax,[rsp+48]; jae .smeig_rayleigh
    mov dword ptr [rsp+60],0
.smeig_w_i:
    mov eax,dword ptr [rsp+60]; cmp eax,r14d; jae .smeig_norm
    mov qword ptr [rsp+80],0; mov dword ptr [rsp+64],0
.smeig_w_j:
    mov eax,dword ptr [rsp+64]; cmp eax,r14d; jae .smeig_w_store
    mov ecx,dword ptr [rsp+60]; imul ecx,r14d; add ecx,eax
    mov rdi,r15; mov esi,ecx; call s_struct_component; mov rbx,rax
    mov rdx,[rsp+16]; mov ecx,dword ptr [rsp+64]; mov r12,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r12; call s_ast_scalar_binary_new
    mov rbx,[rsp+80]; test rbx,rbx; jz .smeig_w_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smeig_w_first:
    mov [rsp+80],rax; inc dword ptr [rsp+64]; jmp .smeig_w_j
.smeig_w_store:
    mov rdx,[rsp+24]; mov ecx,dword ptr [rsp+60]; mov rax,[rsp+80]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+60]; jmp .smeig_w_i
.smeig_norm:
    mov qword ptr [rsp+80],0; mov dword ptr [rsp+60],0
.smeig_norm_i:
    mov eax,dword ptr [rsp+60]; cmp eax,r14d; jae .smeig_norm_sqrt
    mov rdx,[rsp+24]; mov rsi,[rdx+rax*8]; mov edi,OP_SQUARE; call s_ast_unary_new
    mov rbx,[rsp+80]; test rbx,rbx; jz .smeig_norm_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smeig_norm_first:
    mov [rsp+80],rax; inc dword ptr [rsp+60]; jmp .smeig_norm_i
.smeig_norm_sqrt:
    mov edi,OP_SQRT; mov rsi,[rsp+80]; call s_ast_unary_new; mov [rsp+88],rax
    mov dword ptr [rsp+60],0
.smeig_update_v:
    mov eax,dword ptr [rsp+60]; cmp eax,r14d; jae .smeig_iter_next
    mov rdx,[rsp+24]; mov rsi,[rdx+rax*8]; mov edi,OP_DIV; mov rdx,[rsp+88]; call s_ast_scalar_binary_new
    mov rdx,[rsp+16]; mov ecx,dword ptr [rsp+60]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+60]; jmp .smeig_update_v
.smeig_iter_next:
    inc qword ptr [rsp+72]
    mov rax,[rsp+72]; test eax,1; jnz .smeig_iter
    mov dword ptr [rsp+68],0
.smeig_checkpoint_v:
    mov eax,dword ptr [rsp+68]; cmp eax,r14d; jae .smeig_checkpoint_v_done
    mov rdx,[rsp+16]; mov rdi,[rdx+rax*8]; call s_materialize_scalar_ast; test rax,rax; jz .smeig_fail
    mov rdx,[rsp+16]; mov ecx,dword ptr [rsp+68]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+68]; jmp .smeig_checkpoint_v
.smeig_checkpoint_v_done:
    jmp .smeig_iter
.smeig_rayleigh:
    mov qword ptr [rsp+80],0; mov dword ptr [rsp+60],0
.smeig_ray_i:
    mov eax,dword ptr [rsp+60]; cmp eax,r14d; jae .smeig_store_pair
    mov qword ptr [rsp+88],0; mov dword ptr [rsp+64],0
.smeig_ray_j:
    mov eax,dword ptr [rsp+64]; cmp eax,r14d; jae .smeig_ray_dot
    mov ecx,dword ptr [rsp+60]; imul ecx,r14d; add ecx,eax
    mov rdi,r15; mov esi,ecx; call s_struct_component; mov rbx,rax
    mov rdx,[rsp+16]; mov ecx,dword ptr [rsp+64]; mov r12,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,r12; call s_ast_scalar_binary_new
    mov rbx,[rsp+88]; test rbx,rbx; jz .smeig_ray_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smeig_ray_first:
    mov [rsp+88],rax; inc dword ptr [rsp+64]; jmp .smeig_ray_j
.smeig_ray_dot:
    mov rdx,[rsp+16]; mov ecx,dword ptr [rsp+60]; mov rbx,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,rbx; mov rdx,[rsp+88]; call s_ast_scalar_binary_new
    mov rbx,[rsp+80]; test rbx,rbx; jz .smeig_ray_acc_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smeig_ray_acc_first:
    mov [rsp+80],rax; inc dword ptr [rsp+60]; jmp .smeig_ray_i
.smeig_store_pair:
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+56]; mov rax,[rsp+80]; mov [rdx+rcx*8],rax
    mov dword ptr [rsp+60],0
.smeig_store_vec_i:
    mov eax,dword ptr [rsp+60]; cmp eax,r14d; jae .smeig_deflate
    mov rdx,[rsp]; mov ecx,eax; imul ecx,r14d; add ecx,dword ptr [rsp+56]
    mov rbx,[rsp+16]; mov rbx,[rbx+rax*8]; mov [rdx+rcx*8],rbx
    inc dword ptr [rsp+60]; jmp .smeig_store_vec_i
.smeig_deflate:
    mov dword ptr [rsp+60],0
.smeig_def_i:
    mov eax,dword ptr [rsp+60]; cmp eax,r14d; jae .smeig_def_build
    mov dword ptr [rsp+64],0
.smeig_def_j:
    mov eax,dword ptr [rsp+64]; cmp eax,r14d; jae .smeig_def_next_i
    mov ecx,dword ptr [rsp+60]; imul ecx,r14d; add ecx,eax
    mov rdi,r15; mov esi,ecx; call s_struct_component; mov rbx,rax
    mov rdx,[rsp+16]; mov ecx,dword ptr [rsp+60]; mov r12,[rdx+rcx*8]
    mov ecx,dword ptr [rsp+64]; mov r13,[rdx+rcx*8]
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r13; call s_ast_scalar_binary_new
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+56]; mov rsi,[rdx+rcx*8]
    mov edi,OP_MUL; mov rdx,rax; call s_ast_scalar_binary_new
    mov edi,OP_SUB; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
    mov rdx,[rsp+32]; mov ecx,dword ptr [rsp+60]; imul ecx,r14d; add ecx,dword ptr [rsp+64]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+64]; jmp .smeig_def_j
.smeig_def_next_i:
    inc dword ptr [rsp+60]; jmp .smeig_def_i
.smeig_def_build:
    mov edi,dword ptr [rsp+96]; mov esi,r14d; imul esi,r14d; mov rdx,[rsp+32]; call s_struct_build; mov r15,rax
    test r15,r15; jz .smeig_fail
    mov rdi,r15; call s_materialize_struct; mov r15,rax; test r15,r15; jz .smeig_fail
    inc dword ptr [rsp+56]; jmp .smeig_pair
.smeig_build:
    cmp dword ptr [rsp+40],0; jne .smeig_vectors
    mov edi,r14d; call s_vector_tag_from_n; test eax,eax; jz .smeig_fail
    mov edi,eax; mov esi,r14d; mov rdx,[rsp+8]; call s_struct_build; jmp .smeig_done
.smeig_vectors:
    mov edi,dword ptr [rsp+96]; mov esi,r14d; imul esi,r14d; mov rdx,[rsp]; call s_struct_build; jmp .smeig_done
.smeig_fail: xor eax,eax
.smeig_done: add rsp,128; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_svd_values:
    # rdi=A, rsi=spectral power iterations. Output vector workset scales with n.
    push rbx; push r12; push r13; push r14
    sub rsp,32
    mov [rsp+16],rsi
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]; mov edi,r13d; call s_matrix_dim; mov ebx,eax
    test ebx,ebx; jz .smsv_fail
    mov edi,ebx; shl rdi,3; call s_alloc_pointer_workset; test rax,rax; jz .smsv_fail; mov [rsp],rax
    mov rdi,r12; call s_matrix_transpose_struct; test rax,rax; jz .smsv_fail
    mov rdi,rax; mov rsi,r12; call s_matrix_mul_struct; test rax,rax; jz .smsv_fail
    mov rdi,rax; xor esi,esi; mov rdx,[rsp+16]; call s_matrix_eig_struct; mov r12,rax
    test r12,r12; jz .smsv_fail
    xor r14d,r14d
.smsv_loop:
    cmp r14d,ebx; jae .smsv_build
    mov rdi,r12; mov esi,r14d; call s_struct_component; mov rbx,rax
    call s_struct_zero; mov rdx,rax; mov rsi,rbx; mov edi,OP_MAX; call s_ast_scalar_binary_new
    mov rsi,rax; mov edi,OP_SQRT; call s_ast_unary_new
    mov rdx,[rsp]; mov [rdx+r14*8],rax; inc r14d; jmp .smsv_loop
.smsv_build:
    mov edi,r13d; call s_matrix_dim; mov ebx,eax
    mov edi,ebx; call s_vector_tag_from_n; mov edi,eax; mov esi,ebx; mov rdx,[rsp]; call s_struct_build
    jmp .smsv_done
.smsv_fail: xor eax,eax
.smsv_done: add rsp,32; pop r14; pop r13; pop r12; pop rbx; ret

s_matrix_svd_v:
    # rdi=A, rsi=spectral power iterations.
    push rbx; push r12
    mov r12,rdi; mov rbx,rsi
    call s_matrix_transpose_struct; mov rdi,rax; mov rsi,r12; call s_matrix_mul_struct; mov rdi,rax; mov esi,1; mov rdx,rbx; call s_matrix_eig_struct
    pop r12; pop rbx; ret

s_matrix_svd_u:
    # rdi=A, rsi=spectral power iterations. U columns are Av/||Av||; U[n^2]
    # and Av[n] are dimension-derived worksets.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,80
    mov [rsp+24],rsi
    mov r12,rdi; mov r13d,dword ptr [r12+SN_AUX]
    mov edi,r13d; call s_matrix_dim; test eax,eax; jz .smsu_fail; mov r14d,eax
    mov edi,eax; imul rdi,rdi; add rdi,rax; shl rdi,3; call s_alloc_pointer_workset
    test rax,rax; jz .smsu_fail; mov [rsp],rax
    mov rcx,r14; imul rcx,rcx; lea rcx,[rax+rcx*8]; mov [rsp+8],rcx
    mov rdi,r12; mov rsi,[rsp+24]; call s_matrix_svd_v; test rax,rax; jz .smsu_fail; mov r15,rax
    mov dword ptr [rsp+32],0                       # col j
.smsu_col:
    mov eax,dword ptr [rsp+32]; cmp eax,r14d; jae .smsu_build
    mov dword ptr [rsp+36],0                       # row i
.smsu_av_i:
    mov eax,dword ptr [rsp+36]; cmp eax,r14d; jae .smsu_norm
    mov qword ptr [rsp+48],0; mov dword ptr [rsp+40],0
.smsu_av_k:
    mov eax,dword ptr [rsp+40]; cmp eax,r14d; jae .smsu_av_store
    mov ecx,dword ptr [rsp+36]; imul ecx,r14d; add ecx,eax
    mov rdi,r12; mov esi,ecx; call s_struct_component; mov [rsp+56],rax
    mov ecx,dword ptr [rsp+40]; imul ecx,r14d; add ecx,dword ptr [rsp+32]
    mov rdi,r15; mov esi,ecx; call s_struct_component; mov [rsp+64],rax
    mov edi,OP_MUL; mov rsi,[rsp+56]; mov rdx,[rsp+64]; call s_ast_scalar_binary_new
    mov rbx,[rsp+48]; test rbx,rbx; jz .smsu_av_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smsu_av_first:
    mov [rsp+48],rax; inc dword ptr [rsp+40]; jmp .smsu_av_k
.smsu_av_store:
    mov rdx,[rsp+8]; mov ecx,dword ptr [rsp+36]; mov rax,[rsp+48]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+36]; jmp .smsu_av_i
.smsu_norm:
    mov qword ptr [rsp+48],0; mov dword ptr [rsp+36],0
.smsu_norm_i:
    mov eax,dword ptr [rsp+36]; cmp eax,r14d; jae .smsu_norm_sqrt
    mov rdx,[rsp+8]; mov rsi,[rdx+rax*8]; mov edi,OP_SQUARE; call s_ast_unary_new
    mov rbx,[rsp+48]; test rbx,rbx; jz .smsu_norm_first
    mov edi,OP_ADD; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.smsu_norm_first:
    mov [rsp+48],rax; inc dword ptr [rsp+36]; jmp .smsu_norm_i
.smsu_norm_sqrt:
    mov edi,OP_SQRT; mov rsi,[rsp+48]; call s_ast_unary_new; mov [rsp+56],rax
    mov rdi,0x0010000000000000; call s_math_const_bits; mov rdx,rax
    mov edi,OP_MAX; mov rsi,[rsp+56]; call s_ast_scalar_binary_new; mov [rsp+64],rax
    mov dword ptr [rsp+36],0
.smsu_emit_i:
    mov eax,dword ptr [rsp+36]; cmp eax,r14d; jae .smsu_next_col
    mov rdx,[rsp+8]; mov rsi,[rdx+rax*8]; mov rdx,[rsp+64]; mov edi,OP_DIV; call s_ast_scalar_binary_new
    mov rdx,[rsp]; mov ecx,dword ptr [rsp+36]; imul ecx,r14d; add ecx,dword ptr [rsp+32]; mov [rdx+rcx*8],rax
    inc dword ptr [rsp+36]; jmp .smsu_emit_i
.smsu_next_col:
    inc dword ptr [rsp+32]; jmp .smsu_col
.smsu_build:
    mov edi,r13d; mov esi,r14d; imul esi,r14d; mov rdx,[rsp]; call s_struct_build; jmp .smsu_done
.smsu_fail: xor eax,eax
.smsu_done: add rsp,80; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_struct_binary:
    # edi=op,rsi=a,rdx=b -> structured result / 0
    push rbx; push r12; push r13; push r14
    mov ebx,edi; mov r12,rsi; mov r13,rdx
    mov r14d,-1
    cmp dword ptr [r12+SN_KIND],NK_STRUCT; jne .stb_left_scalar
    mov r14d,dword ptr [r12+SN_AUX]
    jmp .stb_tag_known
.stb_left_scalar:
    cmp dword ptr [r13+SN_KIND],NK_STRUCT; jne .stb_fail
    mov r14d,dword ptr [r13+SN_AUX]
    mov rdi,r12; mov esi,r14d; call s_struct_scalar_lift; test rax,rax; jz .stb_fail
    mov r12,rax; jmp .stb_tag_known
.stb_tag_known:
    cmp dword ptr [r13+SN_KIND],NK_STRUCT; je .stb_b_struct
    mov rdi,r13; mov esi,r14d; call s_struct_scalar_lift; test rax,rax; jz .stb_fail
    mov r13,rax
.stb_b_struct:
    cmp r14d,dword ptr [r13+SN_AUX]; jne .stb_fail
    cmp r14d,STF_COMPLEX; je .stb_complex
    mov edi,r14d; call s_matrix_dim; test eax,eax; jz .stb_fail
    # Structural count must agree with the encoded dimension.
    imul eax,eax
    cmp eax,dword ptr [r12+SN_OP]; jne .stb_fail
    cmp ebx,OP_ADD; je .stb_component
    cmp ebx,OP_SUB; je .stb_component
    # matrix '*' is mathematical matrix product and is implemented by the matrix semantic helper below.
    cmp ebx,OP_MUL; je .stb_matrix_mul
    jmp .stb_fail
.stb_complex:
    mov edi,ebx; mov rsi,r12; mov rdx,r13; call s_complex_binary; jmp .stb_done
.stb_component:
    mov edi,ebx; mov rsi,r12; mov rdx,r13; call s_struct_componentwise_binary; jmp .stb_done
.stb_matrix_mul:
    mov rdi,r12; mov rsi,r13; call s_matrix_mul_struct; jmp .stb_done
.stb_fail: xor eax,eax
.stb_done: pop r14; pop r13; pop r12; pop rbx; ret

s_ast_select_new:
    # rdi=condition, rsi=true scalar, rdx=false scalar -> scalar select AST.
    # A shared old-AST primitive used by structured mathematics; no runtime branch.
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    test rbx,rbx; jz .sasn_fail; test r12,r12; jz .sasn_fail; test r13,r13; jz .sasn_fail
    call s_new_ast; test rax,rax; jz .sasn_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],OP_SELECT
    mov [rax+SN_A],rbx; mov [rax+SN_B],r12; mov [rax+SN_C],r13
    jmp .sasn_done
.sasn_fail: xor eax,eax
.sasn_done: pop r14; pop r13; pop r12; pop rbx; ret

s_ast_binary_new:
    # edi=op,rsi=a,rdx=b -> scalar or Structured Fact.
    test rsi,rsi; jz .sabn_zero
    test rdx,rdx; jz .sabn_zero
    cmp dword ptr [rsi+SN_KIND],NK_STRUCT; je .sabn_struct
    cmp dword ptr [rdx+SN_KIND],NK_STRUCT; je .sabn_struct
    jmp s_ast_scalar_binary_new
.sabn_struct:
    jmp s_struct_binary
.sabn_zero: xor eax,eax; ret

s_ast_shape_product_new:
    # Canonical physical extent owned by ShapeFact-N.  This synthetic value is
    # never a user variable and therefore cannot collide with source spelling.
    call s_new_ast; test rax,rax; jz .saspn_done
    mov dword ptr [rax+SN_KIND],NK_VAR
    lea rcx,[rip+shape_product_name]; mov [rax+SN_PTR],rcx; mov qword ptr [rax+SN_LEN],SHAPEFN_PRODUCT_NAME_LEN
.saspn_done: ret

s_shapefact_axis_matches:
    # rdi=node, esi=logical axis id -> eax bool
    push rbx
    mov rbx,rdi
    cmp dword ptr [rbx+SN_KIND],NK_AXIS; jne .sram_no
    mov eax,esi
    mov rcx,[rip+s_shape_axis_ptrs]; mov rdi,[rcx+rax*8]
    mov rcx,[rip+s_shape_axis_lens]; mov rsi,[rcx+rax*8]
    mov rdx,[rbx+SN_PTR]; mov rcx,[rbx+SN_LEN]
    call s_span_eq
    jmp .sram_done
.sram_no: xor eax,eax
.sram_done: pop rbx; ret

s_shapefact_extent_var_matches:
    # rdi=node -> eax bool for this ShapeFact-N instance's runtime extent.
    # No source identifier (historically `n`) is privileged.
    push rbx
    mov rbx,rdi
    test rbx,rbx; jz .srnvm_no
    cmp dword ptr [rbx+SN_KIND],NK_VAR; jne .srnvm_no
    mov rdx,[rip+s_shape_runtime_extent_ptr]; test rdx,rdx; jz .srnvm_no
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]
    mov rcx,[rip+s_shape_runtime_extent_len]; call s_span_eq
    jmp .srnvm_done
.srnvm_no: xor eax,eax
.srnvm_done: pop rbx; ret

s_ast_shape_q_new:
    call s_new_ast; test rax,rax; jz .sarqn_done
    mov dword ptr [rax+SN_KIND],NK_AXIS
    lea rcx,[rip+shape_q_name]; mov [rax+SN_PTR],rcx; mov qword ptr [rax+SN_LEN],SHAPEFN_Q_NAME_LEN
.sarqn_done: ret

# Canonical affine coordinate collector for one dynamic ShapeFact-N axis.
# rdi=node, esi=axis id -> eax=1 when node is an ADD/SUB affine form over
# {axis,n,literal}; rdx=signed constant, ecx=axis coefficient, r8d=n coefficient.
# No source spelling or fixed AST shape is privileged.
s_shapefact_affine_coord_collect:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12d,esi
    test rbx,rbx; jz .sracc_no

    mov rdi,rbx; mov esi,r12d; call s_shapefact_axis_matches
    test eax,eax; jz .sracc_try_n
    xor edx,edx; mov ecx,1; xor r8d,r8d; mov eax,1; jmp .sracc_done
.sracc_try_n:
    mov rdi,rbx; call s_shapefact_extent_var_matches
    test eax,eax; jz .sracc_try_literal
    xor edx,edx; xor ecx,ecx; mov r8d,1; mov eax,1; jmp .sracc_done
.sracc_try_literal:
    mov rdi,rbx; call s_eval_literal_u64_fixed
    test edx,edx; jnz .sracc_try_binary
    test rax,rax; js .sracc_no             # bounded signed compile-time offset
    mov rdx,rax; xor ecx,ecx; xor r8d,r8d; mov eax,1; jmp .sracc_done
.sracc_try_binary:
    cmp dword ptr [rbx+SN_KIND],NK_BINARY; jne .sracc_no
    mov r13d,dword ptr [rbx+SN_OP]
    cmp r13d,OP_ADD; je .sracc_binary
    cmp r13d,OP_SUB; jne .sracc_no
.sracc_binary:
    mov rdi,[rbx+SN_A]; mov esi,r12d; call s_shapefact_affine_coord_collect
    test eax,eax; jz .sracc_no
    push rdx                              # left constant
    push rcx                              # left axis coefficient
    push r8                               # left n coefficient
    mov rdi,[rbx+SN_B]; mov esi,r12d; call s_shapefact_affine_coord_collect
    test eax,eax; jz .sracc_right_fail
    mov r14,rdx                           # right constant
    mov r15d,ecx                          # right axis coefficient
    mov r11d,r8d                          # right n coefficient
    pop r10                               # left n coefficient
    pop r9                                # left axis coefficient
    pop rdx                               # left constant
    cmp r13d,OP_SUB; je .sracc_combine_sub
    add rdx,r14; jo .sracc_no
    mov ecx,r9d; add ecx,r15d
    mov r8d,r10d; add r8d,r11d
    mov eax,1; jmp .sracc_done
.sracc_combine_sub:
    sub rdx,r14; jo .sracc_no
    mov ecx,r9d; sub ecx,r15d
    mov r8d,r10d; sub r8d,r11d
    mov eax,1; jmp .sracc_done
.sracc_right_fail:
    add rsp,24
.sracc_no:
    xor eax,eax; xor edx,edx; xor ecx,ecx; xor r8d,r8d
.sracc_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret
# Canonical dynamic affine-mod physicalization.
# rdi=coordinate AST, esi=axis id -> rax=physical high-axis contribution,
# ecx=2 when the coordinate is mod(affine(axis,n,const),n), otherwise zero.
# The accepted source family is defined by algebraic closure, not one AST spelling.
s_shapefact_dynamic_affine_mod:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12d,esi
    mov rax,[rip+s_shape_extent_kind]
    cmp dword ptr [rax+r12*4],0; je .srdam_no
    test rbx,rbx; jz .srdam_no
    cmp dword ptr [rbx+SN_KIND],NK_BINARY; jne .srdam_no
    cmp dword ptr [rbx+SN_OP],OP_MOD; jne .srdam_no
    mov r13,[rbx+SN_B]; test r13,r13; jz .srdam_no
    mov rdi,r13; call s_shapefact_extent_var_matches
    test eax,eax; jz .srdam_no

    mov rdi,[rbx+SN_A]; mov esi,r12d; call s_shapefact_affine_coord_collect
    test eax,eax; jz .srdam_no
    cmp ecx,1; jne .srdam_no              # exactly one target-axis authority
    cmp r8d,0; je .srdam_coeff_ok
    cmp r8d,1; jne .srdam_no              # optional +n is modulo-neutral
.srdam_coeff_ok:
    mov r15,rdx                            # signed logical offset C

    call s_ast_shape_q_new; test rax,rax; jz .srdam_fail
    mov r14,rax                            # physical product coordinate q
    call s_ast_shape_product_new; test rax,rax; jz .srdam_fail
    mov rbx,rax                            # physical runtime extent
    mov r12,qword ptr [rip+s_shape_static_product]
    test r12,r12; jz .srdam_fail

    # Magnitude of C times static product stride. Negative offsets are realized
    # in the physical ring as q + physical_n - |C|*S.
    mov r13d,0                             # 0 nonnegative, 1 negative
    test r15,r15; jns .srdam_have_mag
    mov r13d,1
    neg r15
    jo .srdam_no
.srdam_have_mag:
    mov rax,r15; mul r12
    test rdx,rdx; jnz .srdam_fail
    mov r15,rax

    test r13d,r13d; jnz .srdam_minus
    test r15,r15; jz .srdam_lhs_ready
    mov rdi,r15; call s_ast_u64_imm; test rax,rax; jz .srdam_fail
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rax; call s_ast_binary_new
    test rax,rax; jz .srdam_fail
    mov r14,rax; jmp .srdam_lhs_ready
.srdam_minus:
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new
    test rax,rax; jz .srdam_fail
    mov r14,rax
    test r15,r15; jz .srdam_lhs_ready
    mov rdi,r15; call s_ast_u64_imm; test rax,rax; jz .srdam_fail
    mov edi,OP_SUB; mov rsi,r14; mov rdx,rax; call s_ast_binary_new
    test rax,rax; jz .srdam_fail
    mov r14,rax
.srdam_lhs_ready:
    mov edi,OP_MOD; mov rsi,r14; mov rdx,rbx; call s_ast_binary_new
    test rax,rax; jz .srdam_fail
    mov r14,rax

    # Remove the original static suffix from q; the remaining term is exactly
    # periodic(dynamic_coordinate)*S.
    cmp r12,1; jbe .srdam_success
    call s_ast_shape_q_new; test rax,rax; jz .srdam_fail
    mov r13,rax
    mov rdi,r12; call s_ast_u64_imm; test rax,rax; jz .srdam_fail
    mov edi,OP_MOD; mov rsi,r13; mov rdx,rax; call s_ast_binary_new
    test rax,rax; jz .srdam_fail
    mov edi,OP_SUB; mov rsi,r14; mov rdx,rax; call s_ast_binary_new
    test rax,rax; jz .srdam_fail
    mov r14,rax
.srdam_success:
    mov rax,r14; mov ecx,2; jmp .srdam_done
.srdam_fail:
    mov dword ptr [rip+s_error],1
.srdam_no:
    xor eax,eax; xor ecx,ecx
.srdam_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_shapefact_rewrite:
    # rdi=node -> rax rewritten node. Current reduction rank layout globals.
    # The local slot owns tuple-successor identity across every recursive rewrite
    # and AST-builder call; caller-saved GPRs must never carry structural links.
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,16
    mov rbx,rdi
    test rbx,rbx; jz .srw_done
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_AXIS; je .srw_axis
    cmp eax,NK_VAR; je .srw_var
    cmp eax,NK_UNARY; je .srw_unary
    cmp eax,NK_BINARY; je .srw_binary
    cmp eax,NK_CAST; je .srw_cast
    cmp eax,NK_LOAD; je .srw_load
    mov rax,rbx; jmp .srw_done
.srw_var:
    # A runtime extent is a ShapeFact, not a privileged source variable.
    # Canonical tensor expressions consume the synthetic physical product fact;
    # the logical runtime extent is recovered by exact division by the static
    # suffix.  This makes `n`, `batch`, `rows`, ... semantically identical.
    mov rdi,rbx; call s_shapefact_extent_var_matches
    test eax,eax; jz .srw_same
    mov r14,qword ptr [rip+s_shape_static_product]
    call s_ast_shape_product_new; test rax,rax; jz .srw_fail
    mov r12,rax
    cmp r14,1; jbe .srw_shape_product_direct
    mov rax,r14; mov rcx,rax; dec rcx; test rax,rcx; jnz .srw_var_div
    bsf rcx,rax; mov edi,ecx; call s_ast_u64_imm; mov r13,rax
    mov edi,OP_USHR; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; jmp .srw_done
.srw_var_div:
    mov rdi,r14; call s_ast_u64_imm; mov r13,rax
    mov edi,OP_DIV; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; jmp .srw_done
.srw_shape_product_direct:
    mov rax,r12; jmp .srw_done
.srw_axis:
    xor r12d,r12d
.srw_axis_scan:
    cmp r12d,dword ptr [rip+s_shape_rank]; jae .srw_same
    mov rax,[rip+s_shape_axis_ptrs]; mov rdi,[rax+r12*8]
    mov rax,[rip+s_shape_axis_lens]; mov rsi,[rax+r12*8]
    mov rdx,[rbx+SN_PTR]; mov rcx,[rbx+SN_LEN]; call s_span_eq
    test eax,eax; jnz .srw_axis_found
    inc r12d; jmp .srw_axis_scan
.srw_axis_found:
    # Rank-1 is already its own physical axis.  Keep the source spelling so
    # ordinary one-dimensional programs retain byte-for-byte canonical shape,
    # while the unified rewrite can still flatten loads from higher-rank sources.
    cmp dword ptr [rip+s_shape_rank],1; jne .srw_axis_make_q
    mov rax,rbx; jmp .srw_done
.srw_axis_make_q:
    # q axis node
    call s_new_ast; test rax,rax; jz .srw_fail
    mov dword ptr [rax+SN_KIND],NK_AXIS
    lea rcx,[rip+shape_q_name]; mov [rax+SN_PTR],rcx; mov qword ptr [rax+SN_LEN],SHAPEFN_Q_NAME_LEN
    mov r13,rax
    # Every logical coordinate is floor(q/stride) mod extent. The leading
    # dynamic axis has no modulo. Constant powers of two keep shift/mask paths.
    mov rax,[rip+s_shape_stride_static]; mov r14,[rax+r12*8]
    cmp r14,1; jbe .srw_axis_after_div
    mov rax,r14; mov rcx,rax; dec rcx; test rax,rcx; jnz .srw_axis_div
    bsf rcx,rax; mov edi,ecx; call s_ast_u64_imm; mov r15,rax
    mov edi,OP_USHR; mov rsi,r13; mov rdx,r15; call s_ast_binary_new; mov r13,rax
    jmp .srw_axis_after_div
.srw_axis_div:
    mov rdi,r14; call s_ast_u64_imm; mov r15,rax
    mov edi,OP_DIV; mov rsi,r13; mov rdx,r15; call s_ast_binary_new; mov r13,rax
.srw_axis_after_div:
    mov rax,[rip+s_shape_extent_kind]; cmp dword ptr [rax+r12*4],0; jne .srw_axis_direct
    mov rax,[rip+s_shape_extent_static]; mov r14,[rax+r12*8]
    cmp r14,1; jbe .srw_zero
    mov rdi,r14; call s_ast_u64_imm; mov r15,rax
    mov edi,OP_MOD; mov rsi,r13; mov rdx,r15; call s_ast_binary_new; jmp .srw_done
.srw_axis_direct: mov rax,r13; jmp .srw_done
.srw_zero: xor edi,edi; call s_ast_u64_imm; jmp .srw_done
.srw_unary:
    mov rdi,[rbx+SN_A]; call s_shapefact_rewrite; mov [rbx+SN_A],rax; mov rax,rbx; jmp .srw_done
.srw_binary:
    mov rdi,[rbx+SN_A]; call s_shapefact_rewrite; mov [rbx+SN_A],rax
    mov rdi,[rbx+SN_B]; call s_shapefact_rewrite; mov [rbx+SN_B],rax
    mov rdi,[rbx+SN_C]; test rdi,rdi; jz 1f; call s_shapefact_rewrite; mov [rbx+SN_C],rax
1:  mov rax,rbx; jmp .srw_done
.srw_cast:
    mov rdi,[rbx+SN_A]; call s_shapefact_rewrite; mov [rbx+SN_A],rax; mov rax,rbx; jmp .srw_done
.srw_load:
    # A flattened load is a stable source-shape fact. Shared AST/value uses may
    # revisit the same node through another parent; never flatten the same load
    # twice. SN_AUX is otherwise unused for NK_LOAD and remains compile-time only.
    cmp qword ptr [rbx+SN_AUX],1; je .srw_same
    # A load is indexed according to the SOURCE binding's persisted ShapeFact-N
    # shape, not whatever rank the current consumer happens to have. This is
    # the ShapeFact-N authority extended to selected-axis contraction/trace.
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_decl_lookup_exact
    cmp eax,-1; je .srw_load_legacy
    mov r14d,eax
    mov rcx,[rip+s_decl_shape_rank]; mov r10d,[rcx+r14*4]
    test r10d,r10d; jz .srw_load_legacy
    cmp r10d,dword ptr [rip+s_shape_rank]; jne .srw_load_source_shape
    # Preserve the historical zero-overhead path when producer and consumer
    # have exactly the same physical strides. Existing physical code shape stays.
    xor r13d,r13d
.srw_load_shape_cmp:
    cmp r13d,r10d; jae .srw_load_legacy
    mov rcx,[rip+s_decl_shape_offset]; mov eax,[rcx+r14*4]; add eax,r13d
    mov rcx,[rip+s_decl_shape_stride_pool]; mov r11,[rcx+rax*8]
    mov rcx,[rip+s_shape_stride_static]; mov r9,[rcx+r13*8]
    cmp r11,r9; jne .srw_load_source_shape
    inc r13d; jmp .srw_load_shape_cmp

.srw_load_source_shape:
    mov r12,[rbx+SN_A]
    test r12,r12; jz .srw_fail
    xor r13d,r13d
    xor r15d,r15d
.srw_load_source_loop:
    mov rcx,[rip+s_decl_shape_rank]; cmp r13d,dword ptr [rcx+r14*4]; jae .srw_load_source_end
    test r12,r12; jz .srw_fail
    mov r11,[r12+SN_NEXT]
    mov [rsp],r11
    mov qword ptr [r12+SN_NEXT],0
    mov rdi,r12; call s_shapefact_rewrite
    test rax,rax; jz .srw_fail
    mov r12,rax
    mov rcx,[rip+s_decl_shape_offset]; mov eax,[rcx+r14*4]; add eax,r13d
    mov rcx,[rip+s_decl_shape_stride_pool]; mov r10,[rcx+rax*8]
    cmp r10,1; jbe .srw_load_source_term
    mov rdi,r10; call s_ast_u64_imm; test rax,rax; jz .srw_fail
    mov r9,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r9; call s_ast_binary_new
    test rax,rax; jz .srw_fail
    mov r12,rax
.srw_load_source_term:
    test r15,r15; jnz .srw_load_source_add
    mov r15,r12; jmp .srw_load_source_next
.srw_load_source_add:
    mov edi,OP_ADD; mov rsi,r15; mov rdx,r12; call s_ast_binary_new
    test rax,rax; jz .srw_fail
    mov r15,rax
.srw_load_source_next:
    mov r12,[rsp]
    inc r13d
    jmp .srw_load_source_loop
.srw_load_source_end:
    test r12,r12; jnz .srw_fail
    test r15,r15; jz .srw_fail
    mov qword ptr [r15+SN_NEXT],0
    mov [rbx+SN_A],r15
    mov qword ptr [rbx+SN_AUX],1
    mov rax,rbx; jmp .srw_done

.srw_load_legacy:
    mov r12,[rbx+SN_A]
    test r12,r12; jz .srw_same
    cmp dword ptr [rip+s_shape_rank],1; jbe .srw_load_rank1
    # ShapeFact-N coordinate algebra.  A tuple load is not a nested runtime
    # walker: every logical coordinate expression is rewritten against the one
    # physical product axis and folded directly into one affine/periodic flat
    # address.  Identity x[i,j,...], neighborhood x[i+di,j+dj,...], periodic
    # coordinates and cross-axis affine expressions therefore share the same
    # general lowering.  Unsupported/non-vectorizable arithmetic may still be
    # rejected later by the native tensor proof; there is no scalar fallback.
    xor r13d,r13d                 # logical axis id
    xor r15d,r15d                 # flat-address AST accumulator
.srw_load_tuple_loop:
    cmp r13d,dword ptr [rip+s_shape_rank]; jae .srw_load_tuple_end
    test r12,r12; jz .srw_fail
    mov r14,[r12+SN_NEXT]         # preserve tuple chain before recursive rewrite
    mov qword ptr [r12+SN_NEXT],0
    mov rax,[rip+s_shape_extent_kind]
    cmp dword ptr [rax+r13*4],0
    je .srw_load_generic_coord
    mov rdi,r12; mov esi,r13d
    call s_shapefact_dynamic_affine_mod
    cmp ecx,2; je .srw_load_physical_term
    test ecx,ecx; jnz .srw_load_coord_ready
    cmp dword ptr [rip+s_error],0; jne .srw_fail
.srw_load_generic_coord:
    mov rdi,r12
    call s_shapefact_rewrite
    test rax,rax; jz .srw_fail
.srw_load_coord_ready:
    mov r12,rax                   # rewritten logical coordinate
    jmp .srw_load_stride_dispatch
.srw_load_physical_term:
    mov r12,rax                   # already physical high-axis contribution
    jmp .srw_load_term_ready
.srw_load_stride_dispatch:

    # Canonical product stride.  The single dynamic root occupies the high
    # product coordinate and therefore advances by the complete static suffix;
    # every static power-of-two axis advances by its proved low-bit stride.
    mov rax,[rip+s_shape_stride_static]
    mov r11,[rax+r13*8]
.srw_load_have_stride:
    cmp r11,1
    je .srw_load_term_ready
    mov rdi,r11; call s_ast_u64_imm; test rax,rax; jz .srw_fail
    mov r10,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r10; call s_ast_binary_new
    test rax,rax; jz .srw_fail
    mov r12,rax
.srw_load_term_ready:
    test r15,r15
    jnz .srw_load_accumulate
    mov r15,r12
    jmp .srw_load_next_axis
.srw_load_accumulate:
    mov edi,OP_ADD; mov rsi,r15; mov rdx,r12; call s_ast_binary_new
    test rax,rax; jz .srw_fail
    mov r15,rax
.srw_load_next_axis:
    mov r12,r14
    inc r13d
    jmp .srw_load_tuple_loop
.srw_load_tuple_end:
    test r12,r12; jnz .srw_fail
    test r15,r15; jz .srw_fail
    mov qword ptr [r15+SN_NEXT],0
    mov [rbx+SN_A],r15
    mov qword ptr [rbx+SN_AUX],1
    mov rax,rbx; jmp .srw_done
.srw_load_rank1:
    cmp qword ptr [r12+SN_NEXT],0; jne .srw_fail
    mov rdi,r12; call s_shapefact_rewrite; mov [rbx+SN_A],rax
    mov qword ptr [rbx+SN_AUX],1
    mov rax,rbx; jmp .srw_done
.srw_same: mov rax,rbx; jmp .srw_done
.srw_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.srw_done: add rsp,16; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Stream selection and item prefix
# -----------------------------------------------------------------------------
s_stream_inputs:
    lea rax,[rip+s_inputs_buf]; mov [rip+s_active_base_var],rax
    lea rax,[rip+s_inputs_end]; mov [rip+s_active_end_var],rax
    lea rax,[rip+s_inputs_cap]; mov [rip+s_active_cap_var],rax
    mov rax,[rip+s_inputs_end]; mov [rip+s_out_ptr],rax
    mov rax,[rip+s_inputs_buf]; add rax,[rip+s_inputs_cap]; mov [rip+s_out_limit],rax; ret
s_stream_bindings:
    lea rax,[rip+s_bindings_buf]; mov [rip+s_active_base_var],rax
    lea rax,[rip+s_bindings_end]; mov [rip+s_active_end_var],rax
    lea rax,[rip+s_bindings_cap]; mov [rip+s_active_cap_var],rax
    mov rax,[rip+s_bindings_end]; mov [rip+s_out_ptr],rax
    mov rax,[rip+s_bindings_buf]; add rax,[rip+s_bindings_cap]; mov [rip+s_out_limit],rax; ret
s_stream_outputs:
    lea rax,[rip+s_outputs_buf]; mov [rip+s_active_base_var],rax
    lea rax,[rip+s_outputs_end]; mov [rip+s_active_end_var],rax
    lea rax,[rip+s_outputs_cap]; mov [rip+s_active_cap_var],rax
    mov rax,[rip+s_outputs_end]; mov [rip+s_out_ptr],rax
    mov rax,[rip+s_outputs_buf]; add rax,[rip+s_outputs_cap]; mov [rip+s_out_limit],rax; ret
s_stream_tests:
    lea rax,[rip+s_tests_buf]; mov [rip+s_active_base_var],rax
    lea rax,[rip+s_tests_end]; mov [rip+s_active_end_var],rax
    lea rax,[rip+s_tests_cap]; mov [rip+s_active_cap_var],rax
    mov rax,[rip+s_tests_end]; mov [rip+s_out_ptr],rax
    mov rax,[rip+s_tests_buf]; add rax,[rip+s_tests_cap]; mov [rip+s_out_limit],rax; ret
s_commit_inputs: mov rax,[rip+s_out_ptr]; mov [rip+s_inputs_end],rax; ret
s_commit_bindings: mov rax,[rip+s_out_ptr]; mov [rip+s_bindings_end],rax; ret
s_commit_outputs: mov rax,[rip+s_out_ptr]; mov [rip+s_outputs_end],rax; ret
s_commit_tests: mov rax,[rip+s_out_ptr]; mov [rip+s_tests_end],rax; ret

s_item_prefix:
    # rdi=&count. emits comma when count>0, increments.
    mov eax,[rdi]
    test eax,eax; jz .sip_inc
    push rdi; mov dil,','; call s_out_byte; pop rdi
.sip_inc: inc dword ptr [rdi]; ret

# -----------------------------------------------------------------------------
# Type parser/serializer
# -----------------------------------------------------------------------------
# rdi=name ptr,rsi=len -> rax=parameterized floating precision, or 0.
# The only non-native spelling is fp<decimal-bits>. Native fp32/fp64 aliases
# are consumed earlier. Precision is a machine-size Physical Fact, never a bit
# field inside a semantic type ID; unsigned overflow is the sole parser frontier.
s_parse_param_fp_span:
    cmp rsi,3
    jb .sppfs_bad
    cmp byte ptr [rdi],'f'
    jne .sppfs_bad
    cmp byte ptr [rdi+1],'p'
    jne .sppfs_bad
    xor eax,eax
    mov ecx,2
.sppfs_loop:
    cmp rcx,rsi
    jae .sppfs_done
    movzx r8d,byte ptr [rdi+rcx]
    cmp r8b,'0'
    jb .sppfs_bad
    cmp r8b,'9'
    ja .sppfs_bad
    sub r8d,'0'
    mov r9,10
    mul r9
    test rdx,rdx
    jnz .sppfs_bad
    add rax,r8
    jc .sppfs_bad
    inc rcx
    jmp .sppfs_loop
.sppfs_done:
    cmp rax,64
    jbe .sppfs_bad
    ret
.sppfs_bad:
    xor eax,eax
    ret

s_parse_type_emit:
    # output JSON type representation; eax code 1 bool,2 i64,3 u64,4 f32,5 f64,6 string,7 parameterized fp>64, 0 fail
    push rbx; push r12
    call s_parse_name
    test edx,edx; jnz .spte_fail
    mov r12,rax; mov rbx,rcx
    xor r10d,r10d
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_bool]; mov ecx,4; call s_span_eq; test eax,eax; jz 1f; mov r10d,1; jmp .spte_base
1:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_i64]; mov ecx,3; call s_span_eq; test eax,eax; jz 2f; mov r10d,2; jmp .spte_base
2:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_u64]; mov ecx,3; call s_span_eq; test eax,eax; jz 3f; mov r10d,3; jmp .spte_base
3:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_f32]; mov ecx,3; call s_span_eq; test eax,eax; jnz .spte_f32
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_fp32]; mov ecx,4; call s_span_eq; test eax,eax; jnz .spte_f32
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_float32]; mov ecx,7; call s_span_eq; test eax,eax; jnz .spte_f32
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_real32]; mov ecx,6; call s_span_eq; test eax,eax; jz 4f
.spte_f32:
    lea r12,[rip+ty_f32]; mov ebx,3; mov r10d,4; jmp .spte_base
4:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jnz .spte_f64
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_fp64]; mov ecx,4; call s_span_eq; test eax,eax; jnz .spte_f64
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_float64]; mov ecx,7; call s_span_eq; test eax,eax; jnz .spte_f64
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_real64]; mov ecx,6; call s_span_eq; test eax,eax; jnz .spte_f64
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_double]; mov ecx,6; call s_span_eq; test eax,eax; jz 5f
.spte_f64:
    lea r12,[rip+ty_f64]; mov ebx,3; mov r10d,5; jmp .spte_base
5:  mov rdi,r12; mov rsi,rbx; call s_parse_param_fp_span; test rax,rax; jz 6f
    mov r10d,7; jmp .spte_base
6:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_string]; mov ecx,6; call s_span_eq; test eax,eax; jz .spte_fail; mov r10d,6
.spte_base:
    # tolerant suffix is currently accepted only for floating point.
    lea rdi,[rip+tok_tilde]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spte_simple
    cmp r10d,4; jb .spte_fail
    lea rdi,[rip+js_type_obj_base]; call s_out_cstr
    mov rdi,r12; mov rsi,rbx; call s_out_quote_span
    lea rdi,[rip+js_tol_mid_abs]; call s_out_cstr
    # parse ~(abs=num,rel=num), preserving source numerics
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spte_fail
    # field name must abs
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_abs]; mov ecx,3; call s_span_eq; test eax,eax; jz .spte_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_number_span; test edx,edx; jnz .spte_fail
    mov rdi,rax; mov rsi,rcx; call s_out_span
    lea rdi,[rip+js_tol_mid_rel]; call s_out_cstr
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spte_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_rel]; mov ecx,3; call s_span_eq; test eax,eax; jz .spte_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_number_span; test edx,edx; jnz .spte_fail
    mov rdi,rax; mov rsi,rcx; call s_out_span
    mov dil,'}'; call s_out_byte
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov eax,r10d; jmp .spte_done
.spte_simple:
    mov rdi,r12; mov rsi,rbx; call s_out_quote_span
    mov eax,r10d; jmp .spte_done
.spte_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.spte_done: pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Axis list parsers
# -----------------------------------------------------------------------------
s_axis_scope_clear:
    mov dword ptr [rip+s_axis_count],0
    ret
s_state_scope_clear:
    mov dword ptr [rip+s_state_count],0
    ret

s_axis_add:
    # rdi ptr,rsi len. eax index/ -1
    mov eax,dword ptr [rip+s_axis_count]; cmp eax,dword ptr [rip+s_fact_cap]; jae .saa_fail
    mov rdx,[rip+s_axis_ptrs]; mov [rdx+rax*8],rdi
    mov rdx,[rip+s_axis_lens]; mov [rdx+rax*8],rsi
    inc dword ptr [rip+s_axis_count]
    ret
.saa_fail: mov dword ptr [rip+s_error],1; mov eax,-1; ret

s_state_add:
    mov eax,dword ptr [rip+s_state_count]; cmp eax,dword ptr [rip+s_fact_cap]; jae .ssa_fail
    mov rdx,[rip+s_state_ptrs]; mov [rdx+rax*8],rdi
    mov rdx,[rip+s_state_lens]; mov [rdx+rax*8],rsi
    inc dword ptr [rip+s_state_count]
    ret
.ssa_fail: mov dword ptr [rip+s_error],1; mov eax,-1; ret

# Parse WH axis list [name:extent,...], emit canonical axes array and install scope.
s_parse_wh_axes_emit:
    call s_axis_scope_clear
    mov dil,'['; call s_out_byte
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor ebx,ebx
.spwa_loop:
    call s_parse_name; test edx,edx; jnz .spwa_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    test ebx,ebx; jz .spwa_nocomma
    mov dil,','; call s_out_byte
.spwa_nocomma:
    lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_extent_mid]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwa_fail
    mov rdi,rax; call s_emit_ast
    mov dil,'}'; call s_out_byte
    inc ebx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwa_loop
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    mov dil,']'; call s_out_byte
    xor eax,eax; ret
.spwa_fail: mov eax,1; ret

# WHEX axes [i in extent,j in 2,...]. Records sparse logical ShapeFact-N.
s_parse_whex_axes_record:
    call s_axis_scope_clear
    mov dword ptr [rip+s_shape_rank],0
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
.spwx_loop:
    call s_parse_name; test edx,edx; jnz .spwx_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    mov ebx,dword ptr [rip+s_shape_rank]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .spwx_fail
    mov rax,[rip+s_shape_axis_ptrs]; mov [rax+rbx*8],r12
    mov rax,[rip+s_shape_axis_lens]; mov [rax+rbx*8],r13
    mov edi,KID_IN; call s_expect_kw_id
    call s_skip
    # Extent is either a declared runtime scalar fact or a positive static cardinality.
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spwx_fail
    mov al,[r8]; cmp al,'0'; jb .spwx_extent_name; cmp al,'9'; jbe .spwx_extent_num
.spwx_extent_name:
    call s_parse_name; test edx,edx; jnz .spwx_fail
    mov rdx,[rip+s_shape_extent_ptrs]; mov [rdx+rbx*8],rax
    mov rdx,[rip+s_shape_extent_lens]; mov [rdx+rbx*8],rcx
    mov rdi,rax; mov rsi,rcx; call s_decl_lookup_exact; cmp eax,-1; je .spwx_fail
    mov rax,[rip+s_shape_extent_kind]; mov dword ptr [rax+rbx*4],1
    mov rax,[rip+s_shape_extent_static]; mov qword ptr [rax+rbx*8],0
    jmp .spwx_extent_done
.spwx_extent_num:
    call s_parse_number_span; test edx,edx; jnz .spwx_fail
    # decimal integer -> u64
    xor r14,r14; xor r15d,r15d
.spwx_numconv:
    cmp r15,rcx; jae .spwx_numok
    movzx edx,byte ptr [rax+r15]; cmp dl,'0'; jb .spwx_fail; cmp dl,'9'; ja .spwx_fail
    imul r14,r14,10; sub edx,'0'; add r14,rdx; inc r15; jmp .spwx_numconv
.spwx_numok:
    test r14,r14; jz .spwx_fail
    # Static ShapeFact-N extents are mathematical cardinalities, not bit-field widths.
    # Power-of-two extents retain the old shift/mask realization; arbitrary
    # positive extents use the same ShapeFact-N authority with exact constant div/mod.
    mov rdx,[rip+s_shape_extent_kind]; mov dword ptr [rdx+rbx*4],0
    mov rdx,[rip+s_shape_extent_ptrs]; mov qword ptr [rdx+rbx*8],0
    mov rdx,[rip+s_shape_extent_lens]; mov qword ptr [rdx+rbx*8],0
    mov rdx,[rip+s_shape_extent_static]; mov [rdx+rbx*8],r14
.spwx_extent_done:
    inc dword ptr [rip+s_shape_rank]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwx_loop
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor eax,eax; ret
.spwx_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# ShapeFact-N validation is semantic and consumer-neutral.  It owns no limit on
# the number or position of runtime extents; consumers declare the subset they
# can currently realize.  This keeps capacity/realization policy out of shape.
s_shapefact_validate:
    mov eax,dword ptr [rip+s_shape_rank]
    test eax,eax; jz .ssfv_fail
    xor ebx,ebx
.ssfv_loop:
    cmp ebx,dword ptr [rip+s_shape_rank]; jae .ssfv_ok
    mov rax,[rip+s_shape_axis_ptrs]; cmp qword ptr [rax+rbx*8],0; je .ssfv_fail
    mov rax,[rip+s_shape_axis_lens]; cmp qword ptr [rax+rbx*8],0; je .ssfv_fail
    mov rax,[rip+s_shape_extent_kind]; mov ecx,dword ptr [rax+rbx*4]
    cmp ecx,SHAPEFN_EXTENT_RUNTIME; je .ssfv_runtime
    cmp ecx,SHAPEFN_EXTENT_STATIC; jne .ssfv_fail
    mov rax,[rip+s_shape_extent_static]; cmp qword ptr [rax+rbx*8],0; je .ssfv_fail
    jmp .ssfv_next
.ssfv_runtime:
    mov rax,[rip+s_shape_extent_ptrs]; cmp qword ptr [rax+rbx*8],0; je .ssfv_fail
    mov rax,[rip+s_shape_extent_lens]; cmp qword ptr [rax+rbx*8],0; je .ssfv_fail
.ssfv_next:
    inc ebx; jmp .ssfv_loop
.ssfv_ok:
    xor eax,eax; ret
.ssfv_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1; ret

# Current Tensor realization of ShapeFact-N.  This consumer collapses one
# runtime extent plus an arbitrary static suffix onto the single physical q
# root.  The restriction belongs here, not to ShapeFact-N itself.
s_tensor_shapefact_prepare:
    call s_shapefact_validate
    test eax,eax; jnz .sprl_fail
    mov qword ptr [rip+s_shape_runtime_extent_ptr],0
    mov qword ptr [rip+s_shape_runtime_extent_len],0
    mov eax,dword ptr [rip+s_shape_rank]
    test eax,eax; jz .sprl_fail
    xor ebx,ebx; xor r12d,r12d; mov r13,1
.sprl_scan:
    cmp ebx,dword ptr [rip+s_shape_rank]; jae .sprl_scan_done
    mov rax,[rip+s_shape_extent_kind]; cmp dword ptr [rax+rbx*4],0; je .sprl_static
    inc r12d
    # Current one-root Tensor realization keeps its sole runtime extent in the
    # high product coordinate.  ShapeFact-N records the identity explicitly so
    # the spelling is unconstrained and the restriction lives only here.
    test ebx,ebx; jnz .sprl_fail
    mov rax,[rip+s_shape_extent_ptrs]; mov r14,[rax+rbx*8]; test r14,r14; jz .sprl_fail
    mov [rip+s_shape_runtime_extent_ptr],r14
    mov rax,[rip+s_shape_extent_lens]; mov r14,[rax+rbx*8]; test r14,r14; jz .sprl_fail
    mov [rip+s_shape_runtime_extent_len],r14
    jmp .sprl_next
.sprl_static:
    mov rax,[rip+s_shape_extent_static]; mov r15,[rax+rbx*8]
    test r15,r15; jz .sprl_fail
    mov rax,r13; mul r15; test rdx,rdx; jnz .sprl_fail
    mov r13,rax
.sprl_next: inc ebx; jmp .sprl_scan
.sprl_scan_done:
    cmp r12d,1; jne .sprl_fail
    mov [rip+s_shape_static_product],r13
    # Row-major physical strides are compile-time facts because the sole runtime
    # extent is the leading logical axis.  ShapeFact-N keeps them as derived
    # axis facts rather than a second independent shape authority.
    mov r14,1
    mov ebx,dword ptr [rip+s_shape_rank]
.sprl_stride:
    test ebx,ebx; jz .sprl_stride_done
    dec ebx
    mov rax,[rip+s_shape_stride_static]; mov [rax+rbx*8],r14
    mov rax,[rip+s_shape_extent_kind]; cmp dword ptr [rax+rbx*4],0; jne .sprl_stride
    mov rax,[rip+s_shape_extent_static]; mov r15,[rax+rbx*8]
    mov rax,r14; mul r15; test rdx,rdx; jnz .sprl_fail
    mov r14,rax
    jmp .sprl_stride
.sprl_stride_done:
    mov rax,r13; test rax,rax; jz .sprl_fail
    mov rcx,rax; dec rcx; test rax,rcx; jnz .sprl_nonpow2
    bsf rcx,rax; mov [rip+s_shape_static_bits],ecx; jmp .sprl_ok
.sprl_nonpow2:
    mov dword ptr [rip+s_shape_static_bits],-1
.sprl_ok:
    mov eax,dword ptr [rip+s_shape_rank]; cmp eax,1; seta al; movzx eax,al; ret
.sprl_fail: mov dword ptr [rip+s_error],1; mov eax,-1; ret

# -----------------------------------------------------------------------------
# Top-level WH declarations
# -----------------------------------------------------------------------------
s_parse_program_decl:
    call s_parse_name; test edx,edx; jnz .spd_fail
    mov [rip+s_program_ptr],rax; mov [rip+s_program_len],rcx
    call s_optional_semicolon
    xor eax,eax; ret
.spd_fail: mov eax,1; ret

s_optional_semicolon:
    lea rdi,[rip+tok_semicolon]; mov esi,1; xor edx,edx; call s_match_token; ret

s_parse_contract_decl:
    call s_parse_name; test edx,edx; jnz .spcd_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    # integer_overflow=trap/wrap and deterministic=true/false are compile-significant.
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+ck_integer_overflow]; mov ecx,16; call s_span_eq
    test eax,eax; jnz .spcd_overflow
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+ck_deterministic]; mov ecx,13; call s_span_eq
    test eax,eax; jnz .spcd_det
    # generic value consume as name/number/string, ignored by current native contract.
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spcd_fail
    mov al,[r8]; cmp al,'"'; je .spcd_skipstr; cmp al,'0'; jb .spcd_skipname; cmp al,'9'; jbe .spcd_skipnum
.spcd_skipname: call s_parse_name; jmp .spcd_done
.spcd_skipnum: call s_parse_number_span; jmp .spcd_done
.spcd_skipstr:
    inc r8
.spcd_strloop: cmp r8,[rip+s_end]; jae .spcd_fail; cmp byte ptr [r8],'"'; je .spcd_strdone; inc r8; jmp .spcd_strloop
.spcd_strdone: inc r8; mov [rip+s_cur],r8; jmp .spcd_done
.spcd_overflow:
    call s_parse_name; test edx,edx; jnz .spcd_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+cv_wrap]; mov ecx,4; call s_span_eq; test eax,eax; jz .spcd_trytrap
    mov dword ptr [rip+s_overflow_wrap],1; jmp .spcd_done
.spcd_trytrap:
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+cv_trap]; mov ecx,4; call s_span_eq; test eax,eax; jz .spcd_fail
    mov dword ptr [rip+s_overflow_wrap],0; jmp .spcd_done
.spcd_det:
    call s_parse_name; test edx,edx; jnz .spcd_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_true]; mov ecx,4; call s_span_eq; test eax,eax; jz .spcd_detfalse
    mov dword ptr [rip+s_deterministic],1; jmp .spcd_done
.spcd_detfalse:
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_false]; mov ecx,5; call s_span_eq; test eax,eax; jz .spcd_fail
    mov dword ptr [rip+s_deterministic],0
.spcd_done: call s_optional_semicolon; xor eax,eax; ret
.spcd_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_input_decl:
    call s_stream_inputs
    lea rdi,[rip+s_input_count]; call s_item_prefix
    mov dil,'{'; call s_out_byte
    lea rdi,[rip+js_name_key]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spid_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spid_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; test eax,eax; jz .spid_fail
    # Wide scalar inputs are sovereign General values.  Mark the existing
    # general lane here so an input/output-only program does not get routed to
    # the tensor frontend merely because it has no let binding.
    cmp eax,7; je .spid_general_lane
    cmp eax,8; jne .spid_type_ready
.spid_general_lane:
    mov dword ptr [rip+s_general_lane],1
.spid_type_ready:
    # optional range
    mov edi,KID_RANGE; call s_match_kw_id
    test eax,eax; jz .spid_close
    lea rdi,[rip+js_min_key]; call s_out_cstr
    call s_parse_signed_literal_emit; test eax,eax; jnz .spid_fail
    lea rdi,[rip+tok_dotdot]; mov esi,2; xor edx,edx; call s_expect_token
    lea rdi,[rip+js_max_key]; call s_out_cstr
    call s_parse_signed_literal_emit; test eax,eax; jnz .spid_fail
.spid_close:
    mov dil,'}'; call s_out_byte; call s_commit_inputs; call s_optional_semicolon; xor eax,eax; ret
.spid_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_signed_literal_emit:
    # emits JSON scalar literal (numbers/bool/string) without typed expression wrapper.
    lea rdi,[rip+tok_minus]; mov esi,1; xor edx,edx; call s_match_token
    mov r12d,eax
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spsle_fail
    mov al,[r8]; cmp al,'"'; je .spsle_str
    cmp al,'0'; jb .spsle_name
    cmp al,'9'; ja .spsle_name
    test r12d,r12d; jz .spsle_num
    mov dil,'-'; call s_out_byte
.spsle_num:
    call s_parse_number_span; test edx,edx; jnz .spsle_fail
    mov rdi,rax; mov rsi,rcx; call s_out_span; xor eax,eax; ret
.spsle_name:
    test r12d,r12d; jnz .spsle_fail
    call s_parse_name; test edx,edx; jnz .spsle_fail
    mov r10,rax; mov r11,rcx
    mov rdi,r10; mov rsi,r11; mov edx,KID_TRUE; call s_span_kw_id; test eax,eax; jnz .spsle_true
    mov rdi,r10; mov rsi,r11; mov edx,KID_FALSE; call s_span_kw_id; test eax,eax; jnz .spsle_false
    jmp .spsle_fail
.spsle_true: lea rdi,[rip+lit_true]; call s_out_cstr; xor eax,eax; ret
.spsle_false: lea rdi,[rip+lit_false]; call s_out_cstr; xor eax,eax; ret
.spsle_str:
    test r12d,r12d; jnz .spsle_fail
    # reuse primary string AST then serialize literal value only is inconvenient; copy raw JSON string span.
    mov r9,r8; inc r9
.spsle_sloop: cmp r9,[rip+s_end]; jae .spsle_fail; cmp byte ptr [r9],'"'; je .spsle_sdone; cmp byte ptr [r9],'\\'; je .spsle_esc; inc r9; jmp .spsle_sloop
.spsle_esc: add r9,2; jmp .spsle_sloop
.spsle_sdone: inc r9; mov [rip+s_cur],r9; mov rdi,r8; mov rsi,r9; sub rsi,r8; call s_out_span; xor eax,eax; ret
.spsle_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_let_decl:
    # Parse first, serialize second.  This leaves the ordinary binding stream
    # closed while Structured Facts materialize scalar carrier checkpoints into
    # the same old compute-binding authority.
    push rbx; push r12; push r13; push r14; push r15
    mov dword ptr [rip+s_general_lane],1
    call s_stream_bindings
    call s_parse_name; test edx,edx; jnz .spld_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spld_fail
    mov qword ptr [rip+s_type_capture_len],0
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spld_expr
    # Type syntax is parsed by the old authority into a tiny compile-time
    # capture buffer, then replayed after the expression has fully lowered.
    mov r14,[rip+s_out_ptr]; mov r15,[rip+s_out_limit]
    mov rax,[rip+s_type_capture_buf]; mov [rip+s_out_ptr],rax
    add rax,[rip+s_type_capture_cap]; mov [rip+s_out_limit],rax
    call s_parse_type_emit; mov ebx,eax
    mov rax,[rip+s_out_ptr]; mov rcx,[rip+s_type_capture_buf]; sub rax,rcx
    mov [rip+s_type_capture_len],rax
    mov [rip+s_out_ptr],r14; mov [rip+s_out_limit],r15
    test ebx,ebx; jz .spld_fail
    cmp dword ptr [rip+s_error],0; jne .spld_fail
.spld_expr:
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spld_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spld_fail
    mov r14,rax
    cmp dword ptr [r14+SN_KIND],NK_RECUR_APPLY; jne .spld_not_recursive_apply
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_materialize_recursive_apply
    test eax,eax; jnz .spld_fail
    call s_optional_semicolon
    xor eax,eax; jmp .spld_done
.spld_not_recursive_apply:
    # Declared precision is enforced by the existing compute-binding conversion
    # authority after expression inference.  Parameterized fp types therefore do
    # not grow a private AST wrapper or width-specific binding path.
    cmp dword ptr [r14+SN_KIND],NK_STRUCT; je .spld_struct_probe
    jmp .spld_scalar
.spld_struct_probe:
    cmp dword ptr [r14+SN_KIND],NK_STRUCT; jne .spld_scalar
    # A Structured Fact crosses a user-visible let boundary by first joining
    # the old scalar compute-binding/ValueFact authority.  The compile-time
    # wrapper survives only as a projection map over those old scalar facts.
    # This prevents chained structured algebra from growing a private AST tree
    # and makes every future Structured Fact inherit the same old DAG lifetime.
    mov rdi,r14; call s_materialize_struct; test rax,rax; jz .spld_fail; mov r14,rax
    mov rdi,r12; mov rsi,r13; mov rdx,r14; call s_struct_decl_add; test eax,eax; jnz .spld_fail
    call s_optional_semicolon
    xor eax,eax; jmp .spld_done
.spld_scalar:
    call s_stream_bindings
    lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_compute_prefix]; call s_out_cstr
    mov r15,[rip+s_type_capture_len]; test r15,r15; jz .spld_no_type
    lea rdi,[rip+js_type_key]; call s_out_cstr
    mov rdi,[rip+s_type_capture_buf]; mov rsi,r15; call s_out_span
.spld_no_type:
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    mov rdi,r14; call s_emit_ast; test eax,eax; jnz .spld_fail
    mov dil,'}'; call s_out_byte; test eax,eax; jnz .spld_fail
    call s_commit_bindings
    call s_optional_semicolon
    xor eax,eax; jmp .spld_done
.spld_fail:
    mov dword ptr [rip+s_error],1; mov eax,1
.spld_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_output_decl:
    call s_stream_outputs; lea rdi,[rip+s_output_count]; call s_item_prefix
    lea rdi,[rip+js_output_label]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spod_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_try_decl_repair
    mov r12,rax; mov r13,rcx
    cmp dword ptr [rip+s_error],0; jne .spod_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_output_expr_mid]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spod_bare
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spod_fail
    mov rdi,rax; call s_emit_ast; jmp .spod_close
.spod_bare:
    # bare output/publish name -> var reference
    call s_new_ast; test rax,rax; jz .spod_fail
    mov dword ptr [rax+SN_KIND],NK_VAR; mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    mov rdi,rax; call s_emit_ast
.spod_close:
    mov dil,'}'; call s_out_byte; call s_commit_outputs; call s_optional_semicolon; xor eax,eax; ret
.spod_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_test_decl:
    call s_stream_tests; lea rdi,[rip+s_test_count]; call s_item_prefix
    lea rdi,[rip+js_test_args]; call s_out_cstr
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    xor ebx,ebx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_args_done
.sptd_arg_loop:
    test ebx,ebx; jz .sptd_arg_nocomma
    mov dil,','; call s_out_byte
.sptd_arg_nocomma:
    call s_parse_signed_literal_emit; test eax,eax; jnz .sptd_fail
    inc ebx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_arg_loop
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
.sptd_args_done:
    lea rdi,[rip+js_expected_mid]; call s_out_cstr
    lea rdi,[rip+tok_arrowfat]; mov esi,2; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    xor ebx,ebx
.sptd_exp_loop:
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_close
    test ebx,ebx; jz .sptd_exp_nocomma
    mov dil,','; call s_out_byte
.sptd_exp_nocomma:
    call s_parse_name; test edx,edx; jnz .sptd_fail
    mov rdi,rax; mov rsi,rcx; call s_try_decl_repair
    cmp dword ptr [rip+s_error],0; jne .sptd_fail
    mov rdi,rax; mov rsi,rcx; call s_out_quote_span
    mov dil,':'; call s_out_byte
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_signed_literal_emit; test eax,eax; jnz .sptd_fail
    inc ebx
    # Expected fields accept either comma or semicolon separators, matching the
    # human WH/WHEX surface. JSON commas are emitted structurally next iteration.
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_exp_loop
    lea rdi,[rip+tok_semicolon]; mov esi,1; xor edx,edx; call s_match_token
    jmp .sptd_exp_loop
.sptd_close:
    lea rdi,[rip+js_test_close]; call s_out_cstr
    call s_commit_tests; call s_optional_semicolon; xor eax,eax; ret
.sptd_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# ---------------- 1.3.70 execution-form semantic convergence ----------------
# A pure self-recursive scalar relation may disappear into the already-existing
# iterate/Rank-N authority when the relation itself proves a finite fixed-lag
# state closure.  This layer knows no workload/algorithm names and owns no
# runtime recursion, memo table, recurrence backend or fixed order limit.

# rdi=node, esi=formal index -> eax=1 iff node is exactly that lexical formal.
s_rec_match_formal_leaf:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12d,esi
    test rbx,rbx; jz .srmfl_no
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_AXIS; je .srmfl_kind_ok
    cmp eax,NK_VAR; jne .srmfl_no
.srmfl_kind_ok:
    mov r13d,dword ptr [rip+s_rec_function_index]
    test r13d,r13d; js .srmfl_no
    mov rax,[rip+s_function_param_offset]
    mov eax,dword ptr [rax+r13*4]
    add eax,r12d
    mov rdx,[rip+s_function_param_ptr]; mov rdx,[rdx+rax*8]
    mov rcx,[rip+s_function_param_len]; mov rcx,[rcx+rax*8]
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]
    call s_span_eq
    jmp .srmfl_done
.srmfl_no:
    xor eax,eax
.srmfl_done:
    pop r13; pop r12; pop rbx; ret

# rdi=NK_RECUR_CALL -> rax=positive fixed lag, edx=0; else edx=1.
# Every non-axis argument must be the same lexical invariant formal.  This is a
# semantic relation proof, not a call-shape optimization route.
s_rec_match_call_lag:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    cmp dword ptr [rbx+SN_KIND],NK_RECUR_CALL; jne .srmcl_bad
    mov eax,dword ptr [rbx+SN_AUX]
    cmp eax,dword ptr [rip+s_rec_function_index]; jne .srmcl_bad
    mov r12,[rbx+SN_A]
    test r12,r12; jz .srmcl_bad
    cmp dword ptr [r12+SN_KIND],NK_CALL_ARG; jne .srmcl_bad
    mov r13,[r12+SN_A]
    test r13,r13; jz .srmcl_bad
    cmp dword ptr [r13+SN_KIND],NK_BINARY; jne .srmcl_bad
    cmp dword ptr [r13+SN_OP],OP_SUB; jne .srmcl_bad
    mov rdi,[r13+SN_A]; xor esi,esi; call s_rec_match_formal_leaf
    test eax,eax; jz .srmcl_bad
    mov rdi,[r13+SN_B]; call s_eval_static_u64
    test edx,edx; jnz .srmcl_bad
    test rax,rax; jz .srmcl_bad
    mov r15,rax                         # lag

    mov r14d,1
    mov r12,[r12+SN_NEXT]
.srmcl_more:
    cmp r14d,dword ptr [rip+s_rec_param_count]; jae .srmcl_end_args
    test r12,r12; jz .srmcl_bad
    cmp dword ptr [r12+SN_KIND],NK_CALL_ARG; jne .srmcl_bad
    mov rdi,[r12+SN_A]; mov esi,r14d; call s_rec_match_formal_leaf
    test eax,eax; jz .srmcl_bad
    mov r12,[r12+SN_NEXT]
    inc r14d; jmp .srmcl_more
.srmcl_end_args:
    test r12,r12; jnz .srmcl_bad
    mov rax,r15; xor edx,edx; jmp .srmcl_done
.srmcl_bad:
    xor eax,eax; mov edx,1
.srmcl_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=AST -> eax=1 iff every ordinary operation is total under the current
# wrap-u64 recurrence proof.  Self calls are admitted only through fixed lags.
# Partial operations (division/mod/shift/load/effect) are intentionally absent:
# window-state recovery may compute causally irrelevant future lanes, so totality
# is required for zero-flip semantics.
s_rec_expr_is_total:
    push rbx; push r12
    mov rbx,rdi
    test rbx,rbx; jz .sreit_no
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_RECUR_CALL; je .sreit_call
    cmp eax,NK_NUM; je .sreit_yes
    cmp eax,NK_BOOL; je .sreit_yes
    cmp eax,NK_IMM_U64; je .sreit_yes
    cmp eax,NK_VAR; je .sreit_formal_probe
    cmp eax,NK_AXIS; je .sreit_formal_probe
    cmp eax,NK_UNARY; je .sreit_unary
    cmp eax,NK_BINARY; je .sreit_binary
    jmp .sreit_no
.sreit_call:
    mov rdi,rbx; call s_rec_match_call_lag; test edx,edx; jnz .sreit_no
    jmp .sreit_yes
.sreit_formal_probe:
    # Lexical formals/globals are total immutable facts.  The step relation's
    # stronger autonomy condition (no direct recurrence-axis use) is proved by
    # s_rec_scan_lags; the base branch may legitimately depend on k (e.g. k<K).
    jmp .sreit_yes
.sreit_unary:
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_NOT; je .sreit_unary_child
    cmp eax,OP_BIT_NOT; jne .sreit_no
.sreit_unary_child:
    mov rdi,[rbx+SN_A]; call s_rec_expr_is_total; jmp .sreit_done
.sreit_binary:
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_ADD; je .sreit_binary_children
    cmp eax,OP_SUB; je .sreit_binary_children
    cmp eax,OP_MUL; je .sreit_binary_children
    cmp eax,OP_BIT_AND; je .sreit_binary_children
    cmp eax,OP_BIT_OR; je .sreit_binary_children
    cmp eax,OP_BIT_XOR; je .sreit_binary_children
    cmp eax,OP_EQ; je .sreit_binary_children
    cmp eax,OP_NE; je .sreit_binary_children
    cmp eax,OP_LT; je .sreit_binary_children
    cmp eax,OP_LE; je .sreit_binary_children
    cmp eax,OP_GT; je .sreit_binary_children
    cmp eax,OP_GE; je .sreit_binary_children
    cmp eax,OP_MIN; je .sreit_binary_children
    cmp eax,OP_MAX; je .sreit_binary_children
    cmp eax,OP_AND; je .sreit_binary_children
    cmp eax,OP_OR; jne .sreit_no
.sreit_binary_children:
    mov rdi,[rbx+SN_A]; call s_rec_expr_is_total; test eax,eax; jz .sreit_no
    mov rdi,[rbx+SN_B]; call s_rec_expr_is_total; test eax,eax; jz .sreit_no
    cmp dword ptr [rbx+SN_OP],OP_SELECT; jne .sreit_yes
    mov rdi,[rbx+SN_C]; call s_rec_expr_is_total; test eax,eax; jz .sreit_no
.sreit_yes:
    mov eax,1; jmp .sreit_done
.sreit_no:
    xor eax,eax
.sreit_done:
    pop r12; pop rbx; ret

# rdi=AST -> eax 0 success /1 fail.  Updates s_rec_max_lag from every self call.
s_rec_scan_lags:
    push rbx
    mov rbx,rdi
    test rbx,rbx; jz .srsl_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_RECUR_CALL; je .srsl_call
    cmp eax,NK_NUM; je .srsl_ok
    cmp eax,NK_BOOL; je .srsl_ok
    cmp eax,NK_IMM_U64; je .srsl_ok
    cmp eax,NK_VAR; je .srsl_atom
    cmp eax,NK_AXIS; je .srsl_atom
    cmp eax,NK_UNARY; je .srsl_one
    cmp eax,NK_BINARY; je .srsl_three
    jmp .srsl_fail
.srsl_atom:
    # Direct recurrence-axis use would make the recovered relation nonautonomous.
    mov rdi,rbx; xor esi,esi; call s_rec_match_formal_leaf
    test eax,eax; jnz .srsl_fail
    jmp .srsl_ok
.srsl_call:
    mov rdi,rbx; call s_rec_match_call_lag
    test edx,edx; jnz .srsl_fail
    cmp rax,[rip+s_rec_max_lag]; jbe .srsl_ok
    mov [rip+s_rec_max_lag],rax
    jmp .srsl_ok
.srsl_one:
    mov rdi,[rbx+SN_A]; call s_rec_scan_lags
    jmp .srsl_done
.srsl_three:
    mov rdi,[rbx+SN_A]; call s_rec_scan_lags; test eax,eax; jnz .srsl_fail
    mov rdi,[rbx+SN_B]; call s_rec_scan_lags; test eax,eax; jnz .srsl_fail
    mov rdi,[rbx+SN_C]; test rdi,rdi; jz .srsl_ok
    call s_rec_scan_lags; test eax,eax; jnz .srsl_fail
.srsl_ok:
    xor eax,eax; jmp .srsl_done
.srsl_fail:
    mov eax,1
.srsl_done:
    pop rbx; ret

# rdi=guard AST, esi=1 when true branch is base, 0 when true branch is recurrence.
# eax=1 only when the guard exactly partitions the structurally required lag span.
s_rec_guard_proves_domain:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r14d,esi
    test rbx,rbx; jz .srgpd_no
    cmp dword ptr [rbx+SN_KIND],NK_BINARY; jne .srgpd_no
    mov r12d,dword ptr [rbx+SN_OP]
    mov rdi,[rbx+SN_A]; xor esi,esi; call s_rec_match_formal_leaf
    test eax,eax; jnz .srgpd_left
    mov rdi,[rbx+SN_B]; xor esi,esi; call s_rec_match_formal_leaf
    test eax,eax; jz .srgpd_no
    # Swap operands and invert the ordered relation.
    mov rdi,[rbx+SN_A]; call s_eval_static_u64; test edx,edx; jnz .srgpd_no
    mov r13,rax
    cmp r12d,OP_LT; jne 1f; mov r12d,OP_GT; jmp .srgpd_norm
1:  cmp r12d,OP_LE; jne 2f; mov r12d,OP_GE; jmp .srgpd_norm
2:  cmp r12d,OP_GT; jne 3f; mov r12d,OP_LT; jmp .srgpd_norm
3:  cmp r12d,OP_GE; jne .srgpd_no; mov r12d,OP_LE; jmp .srgpd_norm
.srgpd_left:
    mov rdi,[rbx+SN_B]; call s_eval_static_u64; test edx,edx; jnz .srgpd_no
    mov r13,rax
.srgpd_norm:
    mov rax,[rip+s_rec_max_lag]
    test rax,rax; jz .srgpd_no
    test r14d,r14d; jz .srgpd_recur_true
    cmp r12d,OP_LT; je .srgpd_eq_k
    cmp r12d,OP_LE; je .srgpd_plus1_k
    cmp r12d,OP_EQ; jne .srgpd_no
    cmp rax,1; jne .srgpd_no
    test r13,r13; sete al; movzx eax,al; jmp .srgpd_done
.srgpd_recur_true:
    cmp r12d,OP_GE; je .srgpd_eq_k
    cmp r12d,OP_GT; je .srgpd_plus1_k
    jmp .srgpd_no
.srgpd_eq_k:
    cmp r13,rax; sete al; movzx eax,al; jmp .srgpd_done
.srgpd_plus1_k:
    mov rcx,r13; inc rcx; jz .srgpd_no
    cmp rcx,rax; sete al; movzx eax,al; jmp .srgpd_done
.srgpd_no:
    xor eax,eax
.srgpd_done:
    pop r14; pop r13; pop r12; pop rbx; ret

# rdi=u64 structural lane -> rax stable generated name, rcx=18.
s_make_recur_state_name:
    push rbx; push r12; push r13
    mov r12,rdi
    call s_alloc_struct_temp_name; test rax,rax; jz .smrsn_fail
    mov rbx,rax
    mov byte ptr [rbx],'@'; mov byte ptr [rbx+1],'r'
    xor r13d,r13d
.smrsn_hex:
    cmp r13d,16; jae .smrsn_done
    mov ecx,15; sub ecx,r13d; shl ecx,2
    mov rax,r12; shr rax,cl; and eax,15
    lea rdx,[rip+rec_hex_digits]; mov al,[rdx+rax]
    mov [rbx+r13+2],al
    inc r13d; jmp .smrsn_hex
.smrsn_done:
    mov rax,rbx; mov ecx,18; jmp .smrsn_ret
.smrsn_fail:
    xor eax,eax; xor ecx,ecx
.smrsn_ret:
    pop r13; pop r12; pop rbx; ret

# rdi=AST -> rax clone where each proved self call is replaced by the matching
# old iterate state fact.  Other lexical formals remain for the old simultaneous
# pure-substitution authority to resolve afterwards.
s_rec_replace_calls:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    test rbx,rbx; jz .srrc_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_RECUR_CALL; je .srrc_call
    cmp eax,NK_NUM; je .srrc_atom
    cmp eax,NK_BOOL; je .srrc_atom
    cmp eax,NK_IMM_U64; je .srrc_atom
    cmp eax,NK_VAR; je .srrc_atom
    cmp eax,NK_AXIS; je .srrc_atom
    cmp eax,NK_UNARY; je .srrc_one
    cmp eax,NK_BINARY; je .srrc_three
    jmp .srrc_fail
.srrc_call:
    mov rdi,rbx; call s_rec_match_call_lag; test edx,edx; jnz .srrc_fail
    mov rcx,[rip+s_rec_max_lag]; sub rcx,rax; jc .srrc_fail
    mov r12,rcx
    call s_new_ast; test rax,rax; jz .srrc_fail
    mov dword ptr [rax+SN_KIND],NK_STATE
    mov rdx,[rip+s_iter_state_name_ptr]; mov rcx,[rdx+r12*8]; mov [rax+SN_PTR],rcx
    mov rdx,[rip+s_iter_state_name_len]; mov rcx,[rdx+r12*8]; mov [rax+SN_LEN],rcx
    jmp .srrc_done
.srrc_atom:
    call s_new_ast; test rax,rax; jz .srrc_fail
    mov r12,rax
    movdqu xmm0,[rbx]; movdqu [r12],xmm0
    movdqu xmm0,[rbx+16]; movdqu [r12+16],xmm0
    movdqu xmm0,[rbx+32]; movdqu [r12+32],xmm0
    movdqu xmm0,[rbx+48]; movdqu [r12+48],xmm0
    mov rax,r12; jmp .srrc_done
.srrc_one:
    call s_new_ast; test rax,rax; jz .srrc_fail
    mov r12,rax
    movdqu xmm0,[rbx]; movdqu [r12],xmm0
    movdqu xmm0,[rbx+16]; movdqu [r12+16],xmm0
    movdqu xmm0,[rbx+32]; movdqu [r12+32],xmm0
    movdqu xmm0,[rbx+48]; movdqu [r12+48],xmm0
    mov rdi,[rbx+SN_A]; call s_rec_replace_calls; test rax,rax; jz .srrc_fail
    mov [r12+SN_A],rax; mov rax,r12; jmp .srrc_done
.srrc_three:
    call s_new_ast; test rax,rax; jz .srrc_fail
    mov r12,rax
    movdqu xmm0,[rbx]; movdqu [r12],xmm0
    movdqu xmm0,[rbx+16]; movdqu [r12+16],xmm0
    movdqu xmm0,[rbx+32]; movdqu [r12+32],xmm0
    movdqu xmm0,[rbx+48]; movdqu [r12+48],xmm0
    mov rdi,[rbx+SN_A]; call s_rec_replace_calls; test rax,rax; jz .srrc_fail
    mov [r12+SN_A],rax
    mov rdi,[rbx+SN_B]; call s_rec_replace_calls; test rax,rax; jz .srrc_fail
    mov [r12+SN_B],rax
    mov rdi,[rbx+SN_C]; test rdi,rdi; jz .srrc_three_done
    call s_rec_replace_calls; test rax,rax; jz .srrc_fail
    mov [r12+SN_C],rax
.srrc_three_done:
    mov rax,r12; jmp .srrc_done
.srrc_fail:
    xor eax,eax
.srrc_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=user binding name ptr, rsi=len, rdx=NK_RECUR_APPLY -> eax 0 success /1 reject.
# Successful recovery emits an ordinary canonical iterate binding.  The General
# backend then independently decides whether its existing Rank-N affine closure
# reaches transition power; Surface owns no ISA/performance selector.
s_materialize_recursive_apply:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,128
    mov r12,rdi; mov r13,rsi; mov r14,rdx
    cmp dword ptr [r14+SN_KIND],NK_RECUR_APPLY; jne .smra_fail
    cmp dword ptr [rip+s_overflow_wrap],1; jne .smra_fail
    mov ebx,dword ptr [r14+SN_AUX]
    mov dword ptr [rip+s_rec_function_index],ebx
    mov rax,[rip+s_function_param_count]; mov eax,dword ptr [rax+rbx*4]
    test eax,eax; jz .smra_fail
    mov dword ptr [rip+s_rec_param_count],eax
    mov rax,[rip+s_function_param_offset]; mov eax,dword ptr [rax+rbx*4]
    mov dword ptr [rip+s_rec_param_offset],eax
    mov rax,[rip+s_function_expr_ast]; mov r15,[rax+rbx*8]
    test r15,r15; jz .smra_fail
    cmp dword ptr [r15+SN_KIND],NK_RECUR_DEF; jne .smra_fail
    # Current execution-form proof is wrap-u64 total algebra.  This is a typed
    # proof class, not a workload name or state-count route.
    mov rdi,[r15+SN_PTR]; mov rsi,[r15+SN_LEN]; lea rdx,[rip+ty_u64]; mov ecx,3; call s_span_eq
    test eax,eax; jz .smra_fail
    mov rbx,[r15+SN_A]                    # function body
    test rbx,rbx; jz .smra_fail
    cmp dword ptr [rbx+SN_KIND],NK_BINARY; jne .smra_fail
    cmp dword ptr [rbx+SN_OP],OP_SELECT; jne .smra_fail
    mov rdi,[rbx+SN_A]; call s_ast_contains_recur; test eax,eax; jnz .smra_fail
    mov rdi,[rbx+SN_B]; call s_ast_contains_recur; mov dword ptr [rip+s_rec_true_has_recur],eax
    mov rdi,[rbx+SN_C]; call s_ast_contains_recur; mov dword ptr [rip+s_rec_false_has_recur],eax
    mov eax,dword ptr [rip+s_rec_true_has_recur]; add eax,dword ptr [rip+s_rec_false_has_recur]
    cmp eax,1; jne .smra_fail
    cmp dword ptr [rip+s_rec_true_has_recur],0; jne .smra_true_is_step
    mov rax,[rbx+SN_B]; mov [rip+s_rec_base_branch],rax
    mov rax,[rbx+SN_C]; mov [rip+s_rec_step_branch],rax
    mov dword ptr [rip+s_rec_base_true],1
    jmp .smra_branches_ready
.smra_true_is_step:
    mov rax,[rbx+SN_C]; mov [rip+s_rec_base_branch],rax
    mov rax,[rbx+SN_B]; mov [rip+s_rec_step_branch],rax
    mov dword ptr [rip+s_rec_base_true],0
.smra_branches_ready:
    mov qword ptr [rip+s_rec_max_lag],0
    mov rdi,[rip+s_rec_step_branch]; call s_rec_scan_lags; test eax,eax; jnz .smra_fail
    cmp qword ptr [rip+s_rec_max_lag],0; je .smra_fail
    mov rdi,[rip+s_rec_base_branch]; call s_rec_expr_is_total; test eax,eax; jz .smra_fail
    mov rdi,[rip+s_rec_step_branch]; call s_rec_expr_is_total; test eax,eax; jz .smra_fail
    mov rdi,[rbx+SN_A]; mov esi,dword ptr [rip+s_rec_base_true]; call s_rec_guard_proves_domain
    test eax,eax; jz .smra_fail

    # Validate/canonicalize invocation arguments into ordinary scalar facts.
    mov r15,[r14+SN_A]
    mov ecx,dword ptr [rip+s_rec_param_count]
    xor ebx,ebx
.smra_arg_loop:
    cmp ebx,ecx; jae .smra_args_done
    test r15,r15; jz .smra_fail
    cmp dword ptr [r15+SN_KIND],NK_CALL_ARG; jne .smra_fail
    mov rdi,[r15+SN_A]; call s_materialize_scalar_ast; test rax,rax; jz .smra_fail
    mov rdx,[rip+s_math_call_args]; mov [rdx+rbx*8],rax
    mov r15,[r15+SN_NEXT]
    inc ebx; jmp .smra_arg_loop
.smra_args_done:
    test r15,r15; jnz .smra_fail
    mov rax,[rip+s_math_call_args]; mov rax,[rax]; mov [rsp+64],rax

    # Save old explicit-iterate scratch views; recurrence dimensionality owns a
    # fresh compiler-only workset sized from the proved lag span itself.
    mov rax,[rip+s_iter_state_name_ptr]; mov [rsp+0],rax
    mov rax,[rip+s_iter_state_name_len]; mov [rsp+8],rax
    mov rax,[rip+s_iter_state_type_ptr]; mov [rsp+16],rax
    mov rax,[rip+s_iter_state_type_len]; mov [rsp+24],rax
    mov rax,[rip+s_iter_state_init_ast]; mov [rsp+32],rax
    mov rax,[rip+s_iter_update_name_ptr]; mov [rsp+40],rax
    mov rax,[rip+s_iter_update_name_len]; mov [rsp+48],rax
    mov rax,[rip+s_iter_update_ast]; mov [rsp+56],rax
    mov rax,[rip+s_rec_max_lag]; inc rax; jz .smra_fail
    mov [rsp+72],rax                       # total states = lag span + counter
    mov rcx,64; mul rcx; test rdx,rdx; jnz .smra_fail
    mov rdi,rax; call s_alloc_pointer_workset; test rax,rax; jz .smra_fail
    mov [rsp+80],rax
    mov rcx,[rsp+72]; mov rdx,rcx; shl rdx,3
    mov [rip+s_iter_state_name_ptr],rax; add rax,rdx
    mov [rip+s_iter_state_name_len],rax; add rax,rdx
    mov [rip+s_iter_state_type_ptr],rax; add rax,rdx
    mov [rip+s_iter_state_type_len],rax; add rax,rdx
    mov [rip+s_iter_state_init_ast],rax; add rax,rdx
    mov [rip+s_iter_update_name_ptr],rax; add rax,rdx
    mov [rip+s_iter_update_name_len],rax; add rax,rdx
    mov [rip+s_iter_update_ast],rax

    # Generate one state name per structural lag.  No order-specific spelling,
    # table, or finite maximum exists.
    xor ebx,ebx
    mov r15,[rip+s_rec_max_lag]
.smra_name_loop:
    cmp rbx,r15; jae .smra_counter_meta
    mov rdi,rbx; call s_make_recur_state_name; test rax,rax; jz .smra_restore_fail
    mov rdx,[rip+s_iter_state_name_ptr]; mov [rdx+rbx*8],rax
    mov rdx,[rip+s_iter_state_name_len]; mov [rdx+rbx*8],rcx
    mov rdx,[rip+s_iter_state_type_ptr]; mov rax,[rip+s_function_expr_ast]
    mov ecx,dword ptr [rip+s_rec_function_index]; mov rax,[rax+rcx*8]
    mov r8,[rax+SN_PTR]; mov [rdx+rbx*8],r8
    mov rdx,[rip+s_iter_state_type_len]; mov r8,[rax+SN_LEN]; mov [rdx+rbx*8],r8
    inc rbx; jmp .smra_name_loop
.smra_counter_meta:
    lea rax,[rip+rec_counter_name]
    mov rdx,[rip+s_iter_state_name_ptr]; mov [rdx+rbx*8],rax
    mov rdx,[rip+s_iter_state_name_len]; mov qword ptr [rdx+rbx*8],rec_counter_name_end-rec_counter_name
    lea rax,[rip+ty_u64]; mov rdx,[rip+s_iter_state_type_ptr]; mov [rdx+rbx*8],rax
    mov rdx,[rip+s_iter_state_type_len]; mov qword ptr [rdx+rbx*8],3

    # Initial window is F(0)..F(K-1).  Each value is the proven nonrecursive
    # base relation with the recurrence axis statically substituted.
    xor ebx,ebx
.smra_init_loop:
    cmp rbx,[rip+s_rec_max_lag]; jae .smra_counter_init
    mov rdi,rbx; call s_ast_u64_imm; test rax,rax; jz .smra_restore_fail
    mov rdx,[rip+s_math_call_args]; mov [rdx],rax
    mov rdi,[rip+s_rec_base_branch]
    mov esi,dword ptr [rip+s_rec_param_offset]
    mov edx,dword ptr [rip+s_rec_param_count]
    call s_clone_subst_pure_multi; test rax,rax; jz .smra_restore_fail
    mov rdx,[rip+s_iter_state_init_ast]; mov [rdx+rbx*8],rax
    inc rbx; jmp .smra_init_loop
.smra_counter_init:
    mov rdx,[rip+s_math_call_args]; mov rax,[rsp+64]; mov [rdx],rax
    xor edi,edi; call s_ast_u64_imm; test rax,rax; jz .smra_restore_fail
    mov rdx,[rip+s_iter_state_init_ast]; mov rcx,[rip+s_rec_max_lag]; mov [rdx+rcx*8],rax

    # counter < N and max_iterations=N use the exact same canonical argument fact.
    call s_new_ast; test rax,rax; jz .smra_restore_fail
    mov dword ptr [rax+SN_KIND],NK_STATE
    lea rdx,[rip+rec_counter_name]; mov [rax+SN_PTR],rdx
    mov qword ptr [rax+SN_LEN],rec_counter_name_end-rec_counter_name
    mov [rsp+88],rax
    mov rdi,[rsp+64]; xor esi,esi; xor edx,edx; xor ecx,ecx; call s_clone_subst
    test rax,rax; jz .smra_restore_fail
    mov [rip+s_iter_limit_ast],rax
    mov rdx,rax; mov rsi,[rsp+88]; mov edi,OP_LT; call s_ast_binary_new
    test rax,rax; jz .smra_restore_fail
    mov [rip+s_iter_condition_ast],rax

    # Shift the old window left.  The last lane receives the recovered recurrence
    # relation with every self-call replaced by the corresponding old state.
    xor ebx,ebx
    mov r15,[rip+s_rec_max_lag]
.smra_shift_loop:
    mov rax,r15; dec rax
    cmp rbx,rax; jae .smra_last_update
    mov rdx,[rip+s_iter_update_name_ptr]; mov rcx,[rip+s_iter_state_name_ptr]; mov r8,[rcx+rbx*8]; mov [rdx+rbx*8],r8
    mov rdx,[rip+s_iter_update_name_len]; mov rcx,[rip+s_iter_state_name_len]; mov r8,[rcx+rbx*8]; mov [rdx+rbx*8],r8
    call s_new_ast; test rax,rax; jz .smra_restore_fail
    mov dword ptr [rax+SN_KIND],NK_STATE
    mov rcx,rbx; inc rcx
    mov rdx,[rip+s_iter_state_name_ptr]; mov r8,[rdx+rcx*8]; mov [rax+SN_PTR],r8
    mov rdx,[rip+s_iter_state_name_len]; mov r8,[rdx+rcx*8]; mov [rax+SN_LEN],r8
    mov rdx,[rip+s_iter_update_ast]; mov [rdx+rbx*8],rax
    inc rbx; jmp .smra_shift_loop
.smra_last_update:
    mov rbx,r15; dec rbx
    mov rdx,[rip+s_iter_update_name_ptr]; mov rcx,[rip+s_iter_state_name_ptr]; mov r8,[rcx+rbx*8]; mov [rdx+rbx*8],r8
    mov rdx,[rip+s_iter_update_name_len]; mov rcx,[rip+s_iter_state_name_len]; mov r8,[rcx+rbx*8]; mov [rdx+rbx*8],r8
    mov rdi,[rip+s_rec_step_branch]; call s_rec_replace_calls; test rax,rax; jz .smra_restore_fail
    mov [rsp+96],rax
    # Keep the recurrence axis out of the autonomous step proof: its only legal
    # occurrences were self-call indices, already erased into states.
    mov rdi,rax; xor esi,esi; call s_rec_match_formal_leaf; test eax,eax; jnz .smra_restore_fail
    mov rdi,[rsp+96]
    mov esi,dword ptr [rip+s_rec_param_offset]
    mov edx,dword ptr [rip+s_rec_param_count]
    # first formal cannot survive; retain the caller argument merely to satisfy
    # the shared arbitrary-arity substitution vector for other invariant formals.
    call s_clone_subst_pure_multi; test rax,rax; jz .smra_restore_fail
    mov rdx,[rip+s_iter_update_ast]; mov [rdx+rbx*8],rax

    # Counter is ordinary final state and ordinary affine update.
    mov rbx,[rip+s_rec_max_lag]
    lea rax,[rip+rec_counter_name]; mov rdx,[rip+s_iter_update_name_ptr]; mov [rdx+rbx*8],rax
    mov rdx,[rip+s_iter_update_name_len]; mov qword ptr [rdx+rbx*8],rec_counter_name_end-rec_counter_name
    call s_new_ast; test rax,rax; jz .smra_restore_fail
    mov dword ptr [rax+SN_KIND],NK_STATE; lea rdx,[rip+rec_counter_name]; mov [rax+SN_PTR],rdx
    mov qword ptr [rax+SN_LEN],rec_counter_name_end-rec_counter_name
    mov r15,rax; mov edi,1; call s_ast_u64_imm; test rax,rax; jz .smra_restore_fail
    mov rdx,rax; mov rsi,r15; mov edi,OP_ADD; call s_ast_binary_new; test rax,rax; jz .smra_restore_fail
    mov rdx,[rip+s_iter_update_ast]; mov [rdx+rbx*8],rax
    mov eax,dword ptr [rip+s_rec_max_lag]; inc eax; mov dword ptr [rip+s_iter_update_count],eax

    # Publication is the first window lane after N applications.
    mov rax,[rip+s_iter_state_name_ptr]; mov rax,[rax]
    mov [rip+s_iter_result_ptr],rax
    mov rax,[rip+s_iter_state_name_len]; mov rax,[rax]
    mov [rip+s_iter_result_len],rax
    mov rdi,r12; mov rsi,r13; mov rdx,[rsp+72]
    call s_emit_collected_iterate_binding
    test eax,eax; jnz .smra_restore_fail
    mov rdi,r12; call s_diag_note_cheese_ptr
    call s_rec_restore_iter_scratch
    xor eax,eax; jmp .smra_done
.smra_restore_fail:
    call s_rec_restore_iter_scratch
.smra_fail:
    mov eax,1
.smra_done:
    add rsp,128
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Restore explicit-iterate scratch pointers saved in the active materializer frame.
# rsp here points at the helper return address, so caller locals start at +8.
s_rec_restore_iter_scratch:
    mov rax,[rsp+8+0]; mov [rip+s_iter_state_name_ptr],rax
    mov rax,[rsp+8+8]; mov [rip+s_iter_state_name_len],rax
    mov rax,[rsp+8+16]; mov [rip+s_iter_state_type_ptr],rax
    mov rax,[rsp+8+24]; mov [rip+s_iter_state_type_len],rax
    mov rax,[rsp+8+32]; mov [rip+s_iter_state_init_ast],rax
    mov rax,[rsp+8+40]; mov [rip+s_iter_update_name_ptr],rax
    mov rax,[rsp+8+48]; mov [rip+s_iter_update_name_len],rax
    mov rax,[rsp+8+56]; mov [rip+s_iter_update_ast],rax
    ret

s_parse_iterate_decl:
    mov dword ptr [rip+s_general_lane],1
    # Parse first and emit once through the shared collected-iterate authority.
    # Recursive execution-form convergence fills the same facts and therefore
    # cannot grow a second recurrence serialization path.
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spit_fail
    mov edi,KID_LIMIT; call s_expect_kw_id
    # max_iterations is emitted later, so parse AST and retain.
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    mov [rip+s_iter_limit_ast],rax
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_state_scope_clear
    xor ebx,ebx                    # state count
    mov qword ptr [rip+s_iter_condition_ast],0
    mov qword ptr [rip+s_iter_result_ptr],0
    mov dword ptr [rip+s_iter_update_count],0
    # Emit states array immediately.
.spit_member:
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spit_members_done
    mov edi,KID_STATE; call s_match_kw_id
    test eax,eax; jnz .spit_state
    mov edi,KID_WHILE; call s_match_kw_id
    test eax,eax; jnz .spit_while
    mov edi,KID_UPDATE; call s_match_kw_id
    test eax,eax; jnz .spit_update
    mov edi,KID_RESULT; call s_match_kw_id
    test eax,eax; jnz .spit_result
    jmp .spit_fail
.spit_state:
    cmp ebx,dword ptr [rip+s_fact_cap]; jae .spit_fail
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov r14,rax; mov r15,rcx
    mov rax,[rip+s_iter_state_name_ptr]; mov [rax+rbx*8],r14
    mov rax,[rip+s_iter_state_name_len]; mov [rax+rbx*8],r15
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    # Type span is constrained scalar; remember by parsing name directly.
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov r10,[rip+s_iter_state_type_ptr]; mov [r10+rbx*8],rax
    mov r10,[rip+s_iter_state_type_len]; mov [r10+rbx*8],rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    mov r10,[rip+s_iter_state_init_ast]; mov [r10+rbx*8],rax
    # State becomes visible after its initializer, matching current surface semantics.
    mov rdi,r14; mov rsi,r15; call s_state_add
    inc ebx; call s_optional_semicolon; jmp .spit_member
.spit_while:
    cmp qword ptr [rip+s_iter_condition_ast],0; jne .spit_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    mov [rip+s_iter_condition_ast],rax; call s_optional_semicolon; jmp .spit_member
.spit_update:
    mov eax,dword ptr [rip+s_iter_update_count]; cmp eax,dword ptr [rip+s_fact_cap]; jae .spit_fail
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov r14,rax; mov r15,rcx
    mov eax,dword ptr [rip+s_iter_update_count]
    mov r10,[rip+s_iter_update_name_ptr]; mov [r10+rax*8],r14
    mov r10,[rip+s_iter_update_name_len]; mov [r10+rax*8],r15
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    mov ecx,dword ptr [rip+s_iter_update_count]
    mov r10,[rip+s_iter_update_ast]; mov [r10+rcx*8],rax
    inc dword ptr [rip+s_iter_update_count]
    call s_optional_semicolon; jmp .spit_member
.spit_result:
    cmp qword ptr [rip+s_iter_result_ptr],0; jne .spit_fail
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov [rip+s_iter_result_ptr],rax; mov [rip+s_iter_result_len],rcx
    call s_optional_semicolon; jmp .spit_member
.spit_members_done:
    test ebx,ebx; jz .spit_fail
    cmp qword ptr [rip+s_iter_condition_ast],0; je .spit_fail
    cmp qword ptr [rip+s_iter_result_ptr],0; je .spit_fail
    mov rdi,r12; mov rsi,r13; mov edx,ebx
    call s_emit_collected_iterate_binding
    test eax,eax; jnz .spit_fail
    call s_state_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spit_fail:
    mov dword ptr [rip+s_error],1; mov eax,1; ret

# rdi=binding name ptr, rsi=name len, edx=state count -> eax 0/1.
# One canonical Surface -> old General iterate serializer.  Human explicit
# iterate and automatically recovered finite-state recurrence both enter here.
# It owns no recurrence proof and no runtime manager.
s_emit_collected_iterate_binding:
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov ebx,edx
    test ebx,ebx; jz .secib_fail
    cmp qword ptr [rip+s_iter_condition_ast],0; je .secib_fail
    cmp qword ptr [rip+s_iter_result_ptr],0; je .secib_fail
    cmp qword ptr [rip+s_iter_limit_ast],0; je .secib_fail
    call s_stream_bindings
    lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_iterate_mid]; call s_out_cstr
    xor r14d,r14d
.secib_emit_states:
    cmp r14d,ebx; jae .secib_states_done
    test r14d,r14d; jz .secib_state_nocomma
    mov dil,','; call s_out_byte
.secib_state_nocomma:
    lea rdi,[rip+js_state_obj_name]; call s_out_cstr
    mov rax,[rip+s_iter_state_name_ptr]; mov rdi,[rax+r14*8]
    mov rax,[rip+s_iter_state_name_len]; mov rsi,[rax+r14*8]; call s_out_quote_span
    lea rdi,[rip+js_type_key]; call s_out_cstr
    mov rax,[rip+s_iter_state_type_ptr]; mov rdi,[rax+r14*8]
    mov rax,[rip+s_iter_state_type_len]; mov rsi,[rax+r14*8]; call s_out_quote_span
    lea rdi,[rip+js_init_key]; call s_out_cstr
    mov rax,[rip+s_iter_state_init_ast]; mov rdi,[rax+r14*8]; call s_emit_ast
    test eax,eax; jnz .secib_fail
    mov dil,'}'; call s_out_byte
    inc r14d; jmp .secib_emit_states
.secib_states_done:
    lea rdi,[rip+js_condition_mid]; call s_out_cstr
    mov rdi,[rip+s_iter_condition_ast]; call s_emit_ast; test eax,eax; jnz .secib_fail
    lea rdi,[rip+js_update_mid]; call s_out_cstr
    xor r14d,r14d
.secib_emit_updates:
    cmp r14d,dword ptr [rip+s_iter_update_count]; jae .secib_updates_done
    test r14d,r14d; jz .secib_up_nocomma
    mov dil,','; call s_out_byte
.secib_up_nocomma:
    mov rax,[rip+s_iter_update_name_ptr]; mov rdi,[rax+r14*8]
    mov rax,[rip+s_iter_update_name_len]; mov rsi,[rax+r14*8]; call s_out_quote_span
    mov dil,':'; call s_out_byte
    mov rax,[rip+s_iter_update_ast]; mov rdi,[rax+r14*8]; call s_emit_ast
    test eax,eax; jnz .secib_fail
    inc r14d; jmp .secib_emit_updates
.secib_updates_done:
    lea rdi,[rip+js_result_mid]; call s_out_cstr
    mov rdi,[rip+s_iter_result_ptr]; mov rsi,[rip+s_iter_result_len]; call s_out_quote_span
    lea rdi,[rip+js_maxiter_mid]; call s_out_cstr
    mov rdi,[rip+s_iter_limit_ast]; call s_emit_ast; test eax,eax; jnz .secib_fail
    mov dil,'}'; call s_out_byte
    call s_commit_bindings
    xor eax,eax; jmp .secib_done
.secib_fail:
    mov eax,1
.secib_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_tensor_decl:
    # Legacy WH tensor/reduce surface remains in the sovereign general lane;
    # structural WH `for` is the explicit topology-recovery spelling.
    mov dword ptr [rip+s_general_lane],1
    # WH tensor map.
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .sptn_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .sptn_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr
    call s_parse_wh_axes_emit; test eax,eax; jnz .sptn_fail
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; test eax,eax; jz .sptn_fail
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sptn_fail
    mov rdi,rax; call s_emit_ast
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.sptn_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_reduce_decl:
    mov dword ptr [rip+s_general_lane],1
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .sprd_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .sprd_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_reduce_mid_axes]; call s_out_cstr
    call s_parse_wh_axes_emit; test eax,eax; jnz .sprd_fail
    lea rdi,[rip+js_acc_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; test eax,eax; jz .sprd_fail
    lea rdi,[rip+js_reduce_kind_mid]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sprd_fail
    mov r14,rax; mov r15,rcx
    # Native mathematical reduction semantics collapse into the existing Rank-N
    # sum authority.  No math runtime or second reduction backend is created.
    mov rdi,r14; mov rsi,r15; mov edx,KID_SUM; call s_span_kw_id; test eax,eax; jnz .sprd_sem_sum
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+kw_dot]; mov ecx,3; call s_span_eq; test eax,eax; jnz .sprd_sem_dot
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+kw_inner]; mov ecx,5; call s_span_eq; test eax,eax; jnz .sprd_sem_dot
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+kw_frobenius_inner]; mov ecx,15; call s_span_eq; test eax,eax; jnz .sprd_sem_dot
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+kw_squared_norm]; mov ecx,12; call s_span_eq; test eax,eax; jnz .sprd_sem_sqnorm
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+kw_norm2_squared]; mov ecx,13; call s_span_eq; test eax,eax; jnz .sprd_sem_sqnorm
    mov rdi,r14; mov rsi,r15; lea rdx,[rip+kw_squared_distance]; mov ecx,16; call s_span_eq; test eax,eax; jnz .sprd_sem_sqdist
    jmp .sprd_fail

.sprd_sem_emit_header:
    lea rdi,[rip+kw_sum]; mov esi,3; call s_out_quote_span
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    ret
.sprd_sem_sum:
    call .sprd_sem_emit_header
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprd_fail
    mov rdi,rax; call s_emit_ast
    jmp .sprd_sem_done
.sprd_sem_dot:
    call .sprd_sem_emit_header
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprd_fail; mov r12,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprd_fail; mov r13,rax
    mov edi,OP_MUL; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .sprd_fail
    mov rdi,rax; call s_emit_ast
    jmp .sprd_sem_done
.sprd_sem_sqnorm:
    call .sprd_sem_emit_header
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprd_fail; mov r12,rax
    mov rdi,r12; xor esi,esi; xor edx,edx; xor ecx,ecx; call s_clone_subst; test rax,rax; jz .sprd_fail
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .sprd_fail
    mov rdi,rax; call s_emit_ast
    jmp .sprd_sem_done
.sprd_sem_sqdist:
    call .sprd_sem_emit_header
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprd_fail; mov r12,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprd_fail; mov r13,rax
    mov edi,OP_SUB; mov rsi,r12; mov rdx,r13; call s_ast_binary_new; test rax,rax; jz .sprd_fail; mov r12,rax
    mov rdi,r12; xor esi,esi; xor edx,edx; xor ecx,ecx; call s_clone_subst; test rax,rax; jz .sprd_fail
    mov edi,OP_MUL; mov rsi,r12; mov rdx,rax; call s_ast_binary_new; test rax,rax; jz .sprd_fail
    mov rdi,rax; call s_emit_ast
    jmp .sprd_sem_done
.sprd_sem_done:
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.sprd_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# -----------------------------------------------------------------------------
# WHEX declarations (field/sum/tolerance)
# -----------------------------------------------------------------------------
s_parse_tolerance_decl:
    call s_parse_number_span; test edx,edx; jnz .sptol_fail
    mov [rip+s_tol_ptr],rax; mov [rip+s_tol_len],rcx
    mov dword ptr [rip+s_fp_tolerant],1
    call s_optional_semicolon; xor eax,eax; ret
.sptol_fail: mov eax,1; ret

s_parse_strict_decl:
    mov dword ptr [rip+s_fp_tolerant],0
    mov qword ptr [rip+s_tol_ptr],0; mov qword ptr [rip+s_tol_len],0
    call s_optional_semicolon; xor eax,eax; ret

# Precision propagation contract.  This is a compile-time semantic switch on
# the existing numeric type-meet authority, not a second mixed-precision engine.
# 0 = lower precision dominates (default), 1 = higher precision dominates.
s_parse_precision_propagation_decl:
    call s_parse_number_span; test edx,edx; jnz .sppd_fail
    cmp rcx,1; jne .sppd_fail
    cmp byte ptr [rax],'0'; je .sppd_low
    cmp byte ptr [rax],'1'; je .sppd_high
    jmp .sppd_fail
.sppd_low:
    mov dword ptr [rip+s_precision_propagation],0
    call s_optional_semicolon; xor eax,eax; ret
.sppd_high:
    mov dword ptr [rip+s_precision_propagation],1
    call s_optional_semicolon; xor eax,eax; ret
.sppd_fail:
    mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_whex_field:
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spwf_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spwf_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr
    call s_parse_whex_axes_record; test eax,eax; jnz .spwf_fail
    call s_tensor_shapefact_prepare
    cmp eax,-1; je .spwf_fail
    mov r14d,eax
    call s_store_decl_shape_meta; test eax,eax; jnz .spwf_fail
    # ShapeFact-N is materialized as one product axis. This is dimensional
    # dataization, never nested sequential loops.
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .spwf_rank1_axis
    lea rdi,[rip+shape_q_name]; mov esi,SHAPEFN_Q_NAME_LEN; call s_out_quote_span; jmp .spwf_axis_extent
.spwf_rank1_axis:
    mov rax,[rip+s_shape_axis_ptrs]; mov rdi,[rax]; mov rax,[rip+s_shape_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.spwf_axis_extent:
    lea rdi,[rip+js_extent_shape_product]; call s_out_cstr
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; cmp eax,5; jne .spwf_fail
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwf_fail
    mov dword ptr [rip+surface_debug_stage],200
    mov rdi,rax; call s_shapefact_rewrite; test rax,rax; jz .spwf_fail
    mov dword ptr [rip+surface_debug_stage],201
.spwf_emit_expr:
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .spwf_fail
    mov dword ptr [rip+surface_debug_stage],202
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    mov dword ptr [rip+s_shapefact_active],1
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spwf_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# WHEX `each i in n { name: type = expr }` is structural map spelling only.
# It lowers to the same map node as `field`; no loop object survives.
s_parse_whex_each:
    call s_axis_scope_clear
    mov dword ptr [rip+s_shape_rank],0
.spwe_axis_loop:
    call s_parse_name; test edx,edx; jnz .spwe_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    mov ebx,dword ptr [rip+s_shape_rank]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .spwe_fail
    mov rax,[rip+s_shape_axis_ptrs]; mov [rax+rbx*8],r12
    mov rax,[rip+s_shape_axis_lens]; mov [rax+rbx*8],r13
    mov edi,KID_IN; call s_expect_kw_id
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spwe_fail
    mov al,[r8]; cmp al,'0'; jb .spwe_extent_name; cmp al,'9'; jbe .spwe_extent_num
.spwe_extent_name:
    call s_parse_name; test edx,edx; jnz .spwe_fail
    mov rdx,[rip+s_shape_extent_ptrs]; mov [rdx+rbx*8],rax
    mov rdx,[rip+s_shape_extent_lens]; mov [rdx+rbx*8],rcx
    mov rdi,rax; mov rsi,rcx; call s_decl_lookup_exact; cmp eax,-1; je .spwe_fail
    mov rax,[rip+s_shape_extent_kind]; mov dword ptr [rax+rbx*4],1
    mov rax,[rip+s_shape_extent_static]; mov qword ptr [rax+rbx*8],0
    jmp .spwe_extent_done
.spwe_extent_num:
    call s_parse_number_span; test edx,edx; jnz .spwe_fail
    xor r14,r14; xor r15d,r15d
.spwe_numconv:
    cmp r15,rcx; jae .spwe_numok
    movzx edx,byte ptr [rax+r15]; cmp dl,'0'; jb .spwe_fail; cmp dl,'9'; ja .spwe_fail
    imul r14,r14,10; sub edx,'0'; add r14,rdx; inc r15; jmp .spwe_numconv
.spwe_numok:
    test r14,r14; jz .spwe_fail
    # Static extent is a cardinality.  Arbitrary positive radices share the
    # same ShapeFact-N product authority as field/sum; only realization may choose
    # shift/mask for powers of two.
    mov rdx,[rip+s_shape_extent_kind]; mov dword ptr [rdx+rbx*4],0
    mov rdx,[rip+s_shape_extent_ptrs]; mov qword ptr [rdx+rbx*8],0
    mov rdx,[rip+s_shape_extent_lens]; mov qword ptr [rdx+rbx*8],0
    mov rdx,[rip+s_shape_extent_static]; mov [rdx+rbx*8],r14
.spwe_extent_done:
    inc dword ptr [rip+s_shape_rank]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwe_axis_loop
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spwe_fail
    call s_tensor_shapefact_prepare; cmp eax,-1; je .spwe_fail
    mov r14d,eax
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spwe_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spwe_fail
    call s_store_decl_shape_meta; test eax,eax; jnz .spwe_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .spwe_rank1_axis
    lea rdi,[rip+shape_q_name]; mov esi,SHAPEFN_Q_NAME_LEN; call s_out_quote_span; jmp .spwe_axis_extent
.spwe_rank1_axis:
    mov rax,[rip+s_shape_axis_ptrs]; mov rdi,[rax]; mov rax,[rip+s_shape_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.spwe_axis_extent:
    lea rdi,[rip+js_extent_shape_product]; call s_out_cstr
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; cmp eax,5; jne .spwe_fail
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwe_fail
    mov rdi,rax; call s_shapefact_rewrite; test rax,rax; jz .spwe_fail
.spwe_emit_expr:
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .spwe_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    mov dword ptr [rip+s_shapefact_active],1
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_optional_semicolon
    call s_axis_scope_clear
    cmp dword ptr [rip+s_error],0; jne .spwe_fail
    xor eax,eax; ret
.spwe_fail:
    mov dword ptr [rip+s_error],1; mov eax,1; ret

s_emit_whex_accumulator:
    lea rdi,[rip+js_acc_tol_prefix]; call s_out_cstr
    cmp dword ptr [rip+s_fp_tolerant],0; je .sewa_zero
    mov rdi,[rip+s_tol_ptr]; mov rsi,[rip+s_tol_len]; test rdi,rdi; jz .sewa_zero
    call s_out_span; jmp .sewa_rel
.sewa_zero: lea rdi,[rip+num_zero_float]; call s_out_cstr
.sewa_rel:
    lea rdi,[rip+js_acc_tol_rel]; call s_out_cstr
    cmp dword ptr [rip+s_fp_tolerant],0; je .sewa_zero2
    mov rdi,[rip+s_tol_ptr]; mov rsi,[rip+s_tol_len]; test rdi,rdi; jz .sewa_zero2
    call s_out_span; jmp .sewa_close
.sewa_zero2: lea rdi,[rip+num_zero_float]; call s_out_cstr
.sewa_close: mov dil,'}'; call s_out_byte; ret

s_parse_whex_sum:
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spws_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spws_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_reduce_mid_axes]; call s_out_cstr
    call s_parse_whex_axes_record; test eax,eax; jnz .spws_fail
    call s_tensor_shapefact_prepare
    cmp eax,-1; je .spws_fail
    mov r14d,eax                    # 1 rank-N, 0 rank1
    # Emit physical axis list.
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .spws_rank1_axis
    lea rdi,[rip+shape_q_name]; mov esi,SHAPEFN_Q_NAME_LEN; call s_out_quote_span; jmp .spws_axis_extent
.spws_rank1_axis:
    mov rax,[rip+s_shape_axis_ptrs]; mov rdi,[rax]; mov rax,[rip+s_shape_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.spws_axis_extent:
    lea rdi,[rip+js_extent_shape_product]; call s_out_cstr
    lea rdi,[rip+js_acc_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    # WHEX native sum requires f64 source spelling.
    call s_parse_name; test edx,edx; jnz .spws_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jz .spws_fail
    call s_emit_whex_accumulator
    lea rdi,[rip+js_reduce_sum_expr]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spws_fail
    mov rdi,rax; call s_shapefact_rewrite; test rax,rax; jz .spws_fail
.spws_emit_expr:
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .spws_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    # ShapeFact-N static product is the physical extent multiplier of the reduction that
    # owns the execution domain, not a process-global property inherited from
    # an earlier higher-rank map.  A lower-rank reduction following ShapeFact-N maps
    # therefore resets the execution domain to its own natural factor (1 for
    # rank-1) while source loads keep their persisted declaration shapes.
    mov dword ptr [rip+s_shapefact_active],1
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spws_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret



# WH structural `for` lowers directly into tensor/reduction data axes. No loop
# object survives into the canonical graph.
s_parse_for_axes_record:
    call s_axis_scope_clear
    mov dword ptr [rip+s_shape_rank],0
.spfa_loop:
    call s_parse_name; test edx,edx; jnz .spfa_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    mov ebx,dword ptr [rip+s_shape_rank]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .spfa_fail
    mov rax,[rip+s_shape_axis_ptrs]; mov [rax+rbx*8],r12
    mov rax,[rip+s_shape_axis_lens]; mov [rax+rbx*8],r13
    mov edi,KID_IN; call s_expect_kw_id
    call s_skip
    # optional zero-based half-open 0..extent
    mov r8,[rip+s_cur]
    cmp r8,[rip+s_end]; jae .spfa_fail
    cmp byte ptr [r8],'0'; jne .spfa_extent
    lea r9,[r8+1]; cmp r9,[rip+s_end]; jae .spfa_extent
    cmp byte ptr [r8+1],'.'; jne .spfa_extent
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spfa_extent
    cmp byte ptr [r8+2],'.'; jne .spfa_extent
    add qword ptr [rip+s_cur],3
.spfa_extent:
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spfa_fail
    mov al,[r8]; cmp al,'0'; jb .spfa_extent_name; cmp al,'9'; jbe .spfa_extent_num
.spfa_extent_name:
    call s_parse_name; test edx,edx; jnz .spfa_fail
    mov rdx,[rip+s_shape_extent_ptrs]; mov [rdx+rbx*8],rax
    mov rdx,[rip+s_shape_extent_lens]; mov [rdx+rbx*8],rcx
    mov rdi,rax; mov rsi,rcx; call s_decl_lookup_exact; cmp eax,-1; je .spfa_fail
    mov rax,[rip+s_shape_extent_kind]; mov dword ptr [rax+rbx*4],1
    mov rax,[rip+s_shape_extent_static]; mov qword ptr [rax+rbx*8],0
    jmp .spfa_extent_done
.spfa_extent_num:
    call s_parse_number_span; test edx,edx; jnz .spfa_fail
    xor r14,r14; xor r15d,r15d
.spfa_numconv:
    cmp r15,rcx; jae .spfa_numok
    movzx edx,byte ptr [rax+r15]; cmp dl,'0'; jb .spfa_fail; cmp dl,'9'; ja .spfa_fail
    imul r14,r14,10; sub edx,'0'; add r14,rdx; inc r15; jmp .spfa_numconv
.spfa_numok:
    test r14,r14; jz .spfa_fail
    # WH `for` is the same structural axis relation as WHEX field/each.  Do not
    # turn a power-of-two realization opportunity into a source-language law.
    mov rdx,[rip+s_shape_extent_kind]; mov dword ptr [rdx+rbx*4],0
    mov rdx,[rip+s_shape_extent_ptrs]; mov qword ptr [rdx+rbx*8],0
    mov rdx,[rip+s_shape_extent_lens]; mov qword ptr [rdx+rbx*8],0
    mov rdx,[rip+s_shape_extent_static]; mov [rdx+rbx*8],r14
.spfa_extent_done:
    inc dword ptr [rip+s_shape_rank]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spfa_loop
    xor eax,eax; ret
.spfa_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# Verify [i,j,...] exactly names the declared for axes.
s_emit_shape_physical_axis:
    # r14d=productized-shape flag. Emits one physical axis, productized when rank>1.
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .sefpa_rank1
    lea rdi,[rip+shape_q_name]; mov esi,SHAPEFN_Q_NAME_LEN; call s_out_quote_span; jmp .sefpa_extent
.sefpa_rank1:
    mov rax,[rip+s_shape_axis_ptrs]; mov rdi,[rax]; mov rax,[rip+s_shape_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.sefpa_extent:
    lea rdi,[rip+js_extent_shape_product]; call s_out_cstr
    ret

s_mark_shapefact_metadata:
    mov dword ptr [rip+s_shapefact_active],1
    ret

s_parse_wh_for:
    call s_parse_for_axes_record; test eax,eax; jnz .spfor_fail
    call s_tensor_shapefact_prepare; cmp eax,-1; je .spfor_fail; mov r14d,eax
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    # optional familiar let
    mov edi,KID_LET; call s_match_kw_id
    call s_parse_name; test edx,edx; jnz .spfor_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spfor_fail
    call s_store_decl_shape_meta; test eax,eax; jnz .spfor_fail
    # Element assignment if an index tuple follows the target.
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spfor_reduce
    # opening '[' already consumed, validate tuple manually.
    xor ebx,ebx
.spfor_idx_loop:
    cmp ebx,dword ptr [rip+s_shape_rank]; jae .spfor_idx_close
    call s_parse_name; test edx,edx; jnz .spfor_fail
    mov rdx,[rip+s_shape_axis_ptrs]; mov rdi,[rdx+rbx*8]
    mov rdx,[rip+s_shape_axis_lens]; mov rsi,[rdx+rbx*8]
    mov rdx,rax; call s_span_eq; test eax,eax; jz .spfor_fail
    inc ebx
    cmp ebx,dword ptr [rip+s_shape_rank]; jae .spfor_idx_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    jmp .spfor_idx_loop
.spfor_idx_close:
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spfor_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jz .spfor_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spfor_fail
    mov rdi,rax; call s_shapefact_rewrite; test rax,rax; jz .spfor_fail
.spfor_map_ast: mov r15,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    # emit map after parsing body
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr; mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr; call s_emit_shape_physical_axis
    lea rdi,[rip+js_type_key]; call s_out_cstr; lea rdi,[rip+ty_f64]; mov esi,3; call s_out_quote_span
    lea rdi,[rip+js_expr_key]; call s_out_cstr; mov rdi,r15; call s_emit_ast
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_mark_shapefact_metadata
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spfor_reduce:
    # Optional explicit f64 accumulator.
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spfor_plus
    call s_parse_name; test edx,edx; jnz .spfor_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jz .spfor_fail
.spfor_plus:
    lea rdi,[rip+tok_plus]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spfor_fail
    mov rdi,rax; call s_shapefact_rewrite; test rax,rax; jz .spfor_fail
.spfor_red_ast: mov r15,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr; mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_reduce_mid_axes]; call s_out_cstr; call s_emit_shape_physical_axis
    lea rdi,[rip+js_acc_key]; call s_out_cstr; call s_emit_whex_accumulator
    lea rdi,[rip+js_reduce_sum_expr]; call s_out_cstr; mov rdi,r15; call s_emit_ast
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_mark_shapefact_metadata
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spfor_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_wh_region:
    call s_parse_name; test edx,edx; jnz .spwhr_fail
    mov edi,KID_EFFECT; call s_expect_kw_id
    call s_parse_name; test edx,edx; jnz .spwhr_fail
    mov rdi,rax; mov rsi,rcx; mov edx,KID_PURE; call s_span_kw_id; test eax,eax; jz .spwhr_fail
    mov edi,KID_PARALLEL; call s_expect_kw_id
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spwhr_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwhr_done
    mov edi,KID_FOR; call s_match_kw_id; test eax,eax; jnz .spwhr_for
    mov edi,KID_FIELD; call s_match_kw_id; test eax,eax; jnz .spwhr_field
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spwhr_sum
    mov edi,KID_WHILE; call s_match_kw_id; test eax,eax; jnz .spwhr_fail
    jmp .spwhr_fail
.spwhr_for: call s_parse_wh_for; test eax,eax; jnz .spwhr_fail; jmp .spwhr_loop
.spwhr_field: call s_parse_whex_field; test eax,eax; jnz .spwhr_fail; jmp .spwhr_loop
.spwhr_sum: call s_parse_whex_sum; test eax,eax; jnz .spwhr_fail; jmp .spwhr_loop
.spwhr_done: call s_optional_semicolon; xor eax,eax; ret
.spwhr_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# WHEX semantic wrappers are compile-time topology declarations. They carry no
# execution resource ownership and therefore erase before native physicalization.
s_parse_whex_axis_decl:
    call s_parse_name; test edx,edx; jnz .spwad_fail
    mov edi,KID_IN; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwad_fail
    call s_optional_semicolon
    xor eax,eax; ret
.spwad_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_whex_region:
    # region NAME effect pure parallel { field/sum ... }
    call s_parse_name; test edx,edx; jnz .spwr_fail
    mov edi,KID_EFFECT; call s_expect_kw_id
    call s_parse_name; test edx,edx; jnz .spwr_fail
    mov rdi,rax; mov rsi,rcx; mov edx,KID_PURE; call s_span_kw_id
    test eax,eax; jz .spwr_fail
    mov edi,KID_PARALLEL; call s_expect_kw_id
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spwr_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwr_done
    mov edi,KID_FIELD; call s_match_kw_id; test eax,eax; jnz .spwr_field
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spwr_sum
    jmp .spwr_fail
.spwr_field: call s_parse_whex_field; test eax,eax; jnz .spwr_fail; jmp .spwr_loop
.spwr_sum: call s_parse_whex_sum; test eax,eax; jnz .spwr_fail; jmp .spwr_loop
.spwr_done: call s_optional_semicolon; xor eax,eax; ret
.spwr_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# -----------------------------------------------------------------------------
# Compile-time semantic abstraction tables: records and pure functions.
# Nothing here survives into runtime machine code.
# -----------------------------------------------------------------------------
s_record_lookup:
    # rdi=record ptr,rsi=len,rdx=field ptr,rcx=len -> rax AST/0
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov r14,rcx; xor r15d,r15d
.srl_loop:
    cmp r15d,dword ptr [rip+s_record_field_count]; jae .srl_no
    mov rax,[rip+s_record_name_ptr]; mov rdi,[rax+r15*8]
    mov rax,[rip+s_record_name_len]; mov rsi,[rax+r15*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jz .srl_next
    mov rax,[rip+s_record_field_ptr]; mov rdi,[rax+r15*8]
    mov rax,[rip+s_record_field_len]; mov rsi,[rax+r15*8]
    mov rdx,r13; mov rcx,r14; call s_span_eq; test eax,eax; jz .srl_next
    mov rax,[rip+s_record_value_ast]; mov rax,[rax+r15*8]; jmp .srl_done
.srl_next: inc r15d; jmp .srl_loop
.srl_no: xor eax,eax
.srl_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# rdi=AST -> eax=1 iff this Surface tree contains a self-recursive relation call.
# The witness is lexical and disappears before canonical JSON emission.
s_ast_contains_recur:
    push rbx
    mov rbx,rdi
    test rbx,rbx; jz .sacr_no
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_RECUR_CALL; je .sacr_yes
    cmp eax,NK_RECUR_APPLY; je .sacr_yes
    cmp eax,NK_CALL_ARG; je .sacr_pair
    cmp eax,NK_UNARY; je .sacr_one
    cmp eax,NK_CAST; je .sacr_one
    cmp eax,NK_LOAD; je .sacr_one
    cmp eax,NK_BINARY; je .sacr_three
    cmp eax,NK_RECUR_DEF; je .sacr_one
    jmp .sacr_no
.sacr_three:
    mov rdi,[rbx+SN_A]; call s_ast_contains_recur; test eax,eax; jnz .sacr_yes
    mov rdi,[rbx+SN_B]; call s_ast_contains_recur; test eax,eax; jnz .sacr_yes
    mov rdi,[rbx+SN_C]; call s_ast_contains_recur; test eax,eax; jnz .sacr_yes
    jmp .sacr_no
.sacr_pair:
    mov rdi,[rbx+SN_A]; call s_ast_contains_recur; test eax,eax; jnz .sacr_yes
    mov rdi,[rbx+SN_NEXT]; call s_ast_contains_recur; test eax,eax; jnz .sacr_yes
    jmp .sacr_no
.sacr_one:
    mov rdi,[rbx+SN_A]; call s_ast_contains_recur; test eax,eax; jnz .sacr_yes
    mov rdi,[rbx+SN_NEXT]; call s_ast_contains_recur; test eax,eax; jnz .sacr_yes
.sacr_no:
    xor eax,eax; pop rbx; ret
.sacr_yes:
    mov eax,1; pop rbx; ret

# edi=argument count -> rax=head of NK_CALL_ARG chain.
# The source-derived Semantic Registry argument vector is only staging; the
# returned chain is ordinary Surface AST storage and has no arity ceiling.
s_build_call_arg_chain:
    push rbx; push r12; push r13
    mov ebx,edi
    xor r12,r12
    test ebx,ebx; jz .sbcac_done
.sbcac_loop:
    dec ebx
    call s_new_ast; test rax,rax; jz .sbcac_fail
    mov r13,rax
    mov dword ptr [r13+SN_KIND],NK_CALL_ARG
    mov rax,[rip+s_math_call_args]
    mov rax,[rax+rbx*8]; mov [r13+SN_A],rax
    mov [r13+SN_NEXT],r12
    mov r12,r13
    test ebx,ebx; jnz .sbcac_loop
.sbcac_done:
    mov rax,r12; pop r13; pop r12; pop rbx; ret
.sbcac_fail:
    xor eax,eax; pop r13; pop r12; pop rbx; ret

s_function_lookup:
    # rdi=name,rsi=len -> eax index or -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sfl_loop:
    cmp r13d,dword ptr [rip+s_function_count]; jae .sfl_no
    mov rax,[rip+s_function_name_ptr]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_function_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sfl_yes
    inc r13d; jmp .sfl_loop
.sfl_yes: mov eax,r13d; jmp .sfl_done
.sfl_no: mov eax,-1
.sfl_done: pop r13; pop r12; pop rbx; ret

s_clone_subst_pure_multi:
    # rdi=body AST, esi=flat parameter offset, edx=arity.  All lexical
    # parameters are substituted in one tree walk, so caller expressions cannot
    # be captured by a later parameter merely because they share its spelling.
    mov dword ptr [rip+s_subst_multi_offset],esi
    mov dword ptr [rip+s_subst_multi_count],edx
    mov dword ptr [rip+s_subst_multi_active],1
    xor esi,esi; xor edx,edx; xor ecx,ecx
    call s_clone_subst
    mov dword ptr [rip+s_subst_multi_active],0
    ret

s_clone_subst:
    # rdi=node,rsi=param ptr,rdx=param len,rcx=argument AST -> rax clone/arg
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov r14,rcx
    test rbx,rbx; jz .scs_null
    # A pure-function parameter is installed as a temporary lexical axis while
    # its body is parsed.  That gives the exact local identity precedence over
    # global one-edit typo repair without inventing a runtime variable class.
    # On expansion, both ordinary NK_VAR bodies from older sources and the
    # lexical NK_AXIS parameter form are substituted away before emission.
    mov eax,dword ptr [rbx+SN_KIND]
    # If lexical substitution closes a select predicate, choose before cloning
    # its data branches.  This is compile-time branch erasure, not a field or
    # runtime optimization: dead human-shell text never enters the scalar AST.
    cmp eax,NK_BINARY; jne .scs_kind_dispatch
    cmp dword ptr [rbx+SN_OP],OP_SELECT; jne .scs_kind_dispatch
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    test rax,rax; jz .scs_null
    mov rdi,rax; call s_eval_static_u64
    test edx,edx; jnz .scs_kind_dispatch
    test rax,rax; jz .scs_static_select_false
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    jmp .scs_done
.scs_static_select_false:
    mov rdi,[rbx+SN_C]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    jmp .scs_done
.scs_kind_dispatch:
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_STATIC_MGET; je .scs_static_mget
    cmp eax,NK_VAR; je .scs_param_candidate
    cmp eax,NK_AXIS; je .scs_param_candidate
    jmp .scs_clone
.scs_static_mget:
    # Preserve the immutable compile-time MatrixFact; only lexical index ASTs
    # are substituted. Resolve as soon as both indices become static.
    sub rsp,32
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    test rax,rax; jz .scs_static_mget_fail; mov [rsp],rax
    mov rdi,[rbx+SN_C]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    test rax,rax; jz .scs_static_mget_fail; mov [rsp+8],rax
    mov rdi,[rsp]; call s_eval_static_u64; test edx,edx; jnz .scs_static_mget_keep
    mov dword ptr [rsp+16],eax
    mov rdi,[rsp+8]; call s_eval_static_u64; test edx,edx; jnz .scs_static_mget_keep
    mov dword ptr [rsp+20],eax
    mov rdi,[rbx+SN_A]; cmp dword ptr [rdi+SN_KIND],NK_STRUCT; jne .scs_static_mget_fail
    mov edi,dword ptr [rdi+SN_AUX]; call s_matrix_dim; test eax,eax; jz .scs_static_mget_fail
    mov r15d,dword ptr [rsp+16]
    cmp r15d,eax; jae .scs_static_mget_fail
    mov r11d,dword ptr [rsp+20]
    cmp r11d,eax; jae .scs_static_mget_fail
    imul r15d,eax; add r15d,r11d
    mov rdi,[rbx+SN_A]; mov esi,r15d; call s_struct_component; test rax,rax; jz .scs_static_mget_fail
    mov rdi,rax; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    add rsp,32; jmp .scs_done
.scs_static_mget_keep:
    call s_new_ast; test rax,rax; jz .scs_static_mget_fail
    mov dword ptr [rax+SN_KIND],NK_STATIC_MGET
    mov rdx,[rbx+SN_A]; mov [rax+SN_A],rdx
    mov rdx,[rsp]; mov [rax+SN_B],rdx; mov rdx,[rsp+8]; mov [rax+SN_C],rdx
    add rsp,32; jmp .scs_done
.scs_static_mget_fail:
    add rsp,32; jmp .scs_null
.scs_param_candidate:
    cmp dword ptr [rip+s_subst_multi_active],0; je .scs_single_param_candidate
    xor r15d,r15d
.scs_multi_param_scan:
    cmp r15d,dword ptr [rip+s_subst_multi_count]; jae .scs_clone
    mov eax,dword ptr [rip+s_subst_multi_offset]; add eax,r15d
    mov rdx,[rip+s_function_param_ptr]; mov rdx,[rdx+rax*8]
    mov rcx,[rip+s_function_param_len]; mov rcx,[rcx+rax*8]
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_span_eq
    test eax,eax; jnz .scs_multi_arg
    inc r15d; jmp .scs_multi_param_scan
.scs_single_param_candidate:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; mov rdx,r12; mov rcx,r13; call s_span_eq
    test eax,eax; jnz .scs_arg
.scs_clone:
    call s_new_ast; test rax,rax; jz .scs_null
    mov r15,rax
    movdqu xmm0,[rbx]; movdqu [r15],xmm0
    movdqu xmm0,[rbx+16]; movdqu [r15+16],xmm0
    movdqu xmm0,[rbx+32]; movdqu [r15+32],xmm0
    movdqu xmm0,[rbx+48]; movdqu [r15+48],xmm0
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_A],rax
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_B],rax
    mov rdi,[rbx+SN_C]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_C],rax
    mov rdi,[rbx+SN_NEXT]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_NEXT],rax
    mov rax,r15; jmp .scs_done
.scs_multi_arg:
    # Clone a caller argument with simultaneous substitution disabled.  Its own
    # lexical names belong to the caller and must never be captured by another
    # formal parameter of the callee.
    mov rax,[rip+s_math_call_args]; mov rdi,[rax+r15*8]
    mov dword ptr [rip+s_subst_multi_active],0
    xor esi,esi; xor edx,edx; xor ecx,ecx; call s_clone_subst
    mov dword ptr [rip+s_subst_multi_active],1
    test rax,rax; jz .scs_null
    mov r15,rax
    mov rdi,[rbx+SN_NEXT]; xor esi,esi; xor edx,edx; xor ecx,ecx; call s_clone_subst
    mov [r15+SN_NEXT],rax
    mov rax,r15; jmp .scs_done

.scs_arg:
    # Substitution owns a fresh AST occurrence. Returning the same argument node
    # into multiple index chains aliases SN_NEXT and corrupts structural tuples.
    # Clone the argument, then preserve the replaced occurrence's tuple successor.
    mov rdi,r14; xor esi,esi; xor edx,edx; xor ecx,ecx; call s_clone_subst
    test rax,rax; jz .scs_null
    mov r15,rax
    mov rdi,[rbx+SN_NEXT]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst
    mov [r15+SN_NEXT],rax
    mov rax,r15; jmp .scs_done
.scs_null: xor eax,eax
.scs_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_record_decl:
    # record NAME { FIELD = compile_time_expr ... }
    call s_parse_name; test edx,edx; jnz .sprc_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.sprc_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sprc_done
    call s_parse_name; test edx,edx; jnz .sprc_fail
    mov r14,rax; mov r15,rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprc_fail
    mov ebx,dword ptr [rip+s_record_field_count]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .sprc_fail
    mov rdx,[rip+s_record_name_ptr]; mov [rdx+rbx*8],r12
    mov rdx,[rip+s_record_name_len]; mov [rdx+rbx*8],r13
    mov rdx,[rip+s_record_field_ptr]; mov [rdx+rbx*8],r14
    mov rdx,[rip+s_record_field_len]; mov [rdx+rbx*8],r15
    mov rdx,[rip+s_record_value_ast]; mov [rdx+rbx*8],rax
    inc dword ptr [rip+s_record_field_count]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sprc_loop
    call s_optional_semicolon
    jmp .sprc_loop
.sprc_done: call s_optional_semicolon; xor eax,eax; ret
.sprc_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_pure_function:
    # pure [generic] fn NAME(PARAM: TYPE, ...) -> TYPE = EXPR
    # 1.3.70 pre-registers only lexical identity so a function may name itself
    # while its body is parsed.  A self-call is a Surface relation witness, not a
    # runtime call.  If no recursive witness survives, the old compile-time pure
    # substitution path remains byte-for-byte the authority.
    mov edi,KID_GENERIC; call s_match_kw_id
    mov edi,KID_FN; call s_match_kw_id; test eax,eax; jz .sppf_fail
    call s_parse_name; test edx,edx; jnz .sppf_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov eax,dword ptr [rip+s_axis_count]
    mov dword ptr [rip+s_pure_saved_axis_count],eax
    mov eax,dword ptr [rip+s_function_param_total]
    mov dword ptr [rip+s_pure_param_start],eax
    mov dword ptr [rip+s_pure_function_index],-1
    # Empty parameter lists remain legal ordinary pure functions.
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sppf_params_done
.sppf_param_loop:
    call s_parse_name; test edx,edx; jnz .sppf_restore_fail
    mov r14,rax; mov r15,rcx
    mov ebx,dword ptr [rip+s_function_param_total]
    cmp ebx,dword ptr [rip+s_fact_cap]; jae .sppf_restore_fail
    mov rdx,[rip+s_function_param_ptr]; mov [rdx+rbx*8],r14
    mov rdx,[rip+s_function_param_len]; mov [rdx+rbx*8],r15
    inc dword ptr [rip+s_function_param_total]
    mov rdi,r14; mov rsi,r15; call s_axis_add
    cmp eax,-1; je .sppf_restore_fail
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppf_restore_fail
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sppf_param_loop
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .sppf_restore_fail
.sppf_params_done:
    lea rdi,[rip+tok_arrowthin]; mov esi,2; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppf_restore_fail
    mov [rip+s_pure_return_type_ptr],rax; mov [rip+s_pure_return_type_len],rcx

    # Install the function identity before parsing the body.  expr_ast==0 means
    # "currently proving this lexical self relation" and is never serializable.
    mov ebx,dword ptr [rip+s_function_count]
    cmp ebx,dword ptr [rip+s_fact_cap]; jae .sppf_restore_fail
    mov dword ptr [rip+s_pure_function_index],ebx
    mov rdx,[rip+s_function_name_ptr]; mov [rdx+rbx*8],r12
    mov rdx,[rip+s_function_name_len]; mov [rdx+rbx*8],r13
    mov ecx,dword ptr [rip+s_pure_param_start]
    mov rdx,[rip+s_function_param_offset]; mov [rdx+rbx*4],ecx
    mov edx,dword ptr [rip+s_function_param_total]; sub edx,ecx
    mov rcx,[rip+s_function_param_count]; mov [rcx+rbx*4],edx
    mov rdx,[rip+s_function_expr_ast]; mov qword ptr [rdx+rbx*8],0
    inc dword ptr [rip+s_function_count]

    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr
    mov r11,rax
    mov eax,dword ptr [rip+s_pure_saved_axis_count]
    mov dword ptr [rip+s_axis_count],eax
    mov rax,r11
    test rax,rax; jz .sppf_registered_fail
    mov rdi,rax; call s_ast_contains_recur
    test eax,eax; jz .sppf_store_plain

    # Recursive definition metadata lives in one ordinary AST wrapper and dies
    # before canonical emission.  No recurrence IR/table/backend is introduced.
    mov r14,r11
    call s_new_ast; test rax,rax; jz .sppf_registered_fail
    mov dword ptr [rax+SN_KIND],NK_RECUR_DEF
    mov [rax+SN_A],r14
    mov rdx,[rip+s_pure_return_type_ptr]; mov [rax+SN_PTR],rdx
    mov rdx,[rip+s_pure_return_type_len]; mov [rax+SN_LEN],rdx
    mov edx,dword ptr [rip+s_pure_function_index]; mov dword ptr [rax+SN_AUX],edx
    mov ecx,edx; mov rdx,[rip+s_function_expr_ast]; mov [rdx+rcx*8],rax
    jmp .sppf_success
.sppf_store_plain:
    mov ecx,dword ptr [rip+s_pure_function_index]
    mov rdx,[rip+s_function_expr_ast]; mov [rdx+rcx*8],r11
.sppf_success:
    mov dword ptr [rip+s_pure_function_index],-1
    call s_optional_semicolon; xor eax,eax; ret
.sppf_registered_fail:
    mov eax,dword ptr [rip+s_pure_function_index]
    test eax,eax; js .sppf_restore_fail
    mov dword ptr [rip+s_function_count],eax
    mov eax,dword ptr [rip+s_pure_param_start]
    mov dword ptr [rip+s_function_param_total],eax
    mov dword ptr [rip+s_pure_function_index],-1
.sppf_restore_fail:
    mov eax,dword ptr [rip+s_pure_saved_axis_count]
    mov dword ptr [rip+s_axis_count],eax
.sppf_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret


# -----------------------------------------------------------------------------
# Closed static abstractions: dictionary / nested / cascade.
# These structures exist only while compiling. They never become runtime
# objects, queues, schedulers, hash tables, or resource owners.
# -----------------------------------------------------------------------------
s_ast_closed:
    # rdi=node -> eax=1 iff no runtime reference occurs anywhere below it.
    push rbx
    mov rbx,rdi
    test rbx,rbx; jz .sac_no
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .sac_yes
    cmp eax,NK_STRING; je .sac_yes
    cmp eax,NK_BOOL; je .sac_yes
    cmp eax,NK_IMM_U64; je .sac_yes
    cmp eax,NK_IMM_F64_BITS; je .sac_yes
    cmp eax,NK_VAR; je .sac_no
    cmp eax,NK_AXIS; je .sac_no
    cmp eax,NK_STATE; je .sac_no
    cmp eax,NK_LOAD; je .sac_no
    cmp eax,NK_GOAL_RESULT; je .sac_no
    cmp eax,NK_CAST; je .sac_one
    cmp eax,NK_UNARY; je .sac_one
    cmp eax,NK_BINARY; jne .sac_no
    mov rdi,[rbx+SN_A]; call s_ast_closed; test eax,eax; jz .sac_no
    mov rdi,[rbx+SN_B]; call s_ast_closed; test eax,eax; jz .sac_no
    mov rdi,[rbx+SN_C]; test rdi,rdi; jz .sac_yes
    call s_ast_closed; test eax,eax; jz .sac_no
    jmp .sac_yes
.sac_one:
    mov rdi,[rbx+SN_A]; call s_ast_closed; test eax,eax; jz .sac_no
.sac_yes: mov eax,1; pop rbx; ret
.sac_no: xor eax,eax; pop rbx; ret

s_emit_compute_ast:
    # rdi=name ptr,rsi=len,rdx=AST. Emits an ordinary compute binding.
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    mov dword ptr [rip+s_general_lane],1
    mov rdi,rbx; mov rsi,r12; call s_decl_add; test eax,eax; jnz .seca_fail
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    mov rdi,rbx; mov rsi,r12; call s_out_quote_span
    lea rdi,[rip+js_compute_prefix]; call s_out_cstr
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    mov rdi,r13; call s_emit_ast; test eax,eax; jnz .seca_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    xor eax,eax; jmp .seca_done
.seca_fail: mov dword ptr [rip+s_error],1; mov eax,1
.seca_done: pop r13; pop r12; pop rbx; ret


# Convert one composite scalar AST into an ordinary old compute binding and
# return an NK_VAR reference to it.  This is the bridge that lets new
# Structured Facts collapse back into the pre-existing canonical ValueFact DAG
# instead of serializing a shared DAG as an exponentially duplicated tree.
s_materialize_scalar_ast:
    # rdi=scalar AST -> rax scalar AST (usually generated var)
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    test rbx,rbx; jz .smsa_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_STRUCT; je .smsa_fail
    cmp eax,NK_STRUCT_ELEM; je .smsa_fail
    # Existing atoms are already canonical checkpoints.
    cmp eax,NK_VAR; je .smsa_same
    cmp eax,NK_STATE; je .smsa_same
    cmp eax,NK_AXIS; je .smsa_same
    cmp eax,NK_NUM; je .smsa_same
    cmp eax,NK_IMM_U64; je .smsa_same
    cmp eax,NK_IMM_F64_BITS; je .smsa_same
    mov r15d,dword ptr [rip+s_struct_temp_count]
    call s_alloc_struct_temp_name
    test rax,rax; jz .smsa_fail
    mov r14,rax
    mov byte ptr [r14+0],'@'; mov byte ptr [r14+1],'w'
    mov byte ptr [r14+2],'h'; mov byte ptr [r14+3],'.'
    mov byte ptr [r14+4],'s'; mov byte ptr [r14+5],'f'
    # Reuse the old decimal output primitive to make a persistent unique name.
    mov r12,[rip+s_out_ptr]; mov r13,[rip+s_out_limit]
    lea rax,[r14+6]; mov [rip+s_out_ptr],rax
    lea rax,[r14+16]; mov [rip+s_out_limit],rax
    mov edi,r15d; call s_emit_u64_decimal
    mov rax,[rip+s_out_ptr]; sub rax,r14; mov r15,rax
    mov [rip+s_out_ptr],r12; mov [rip+s_out_limit],r13
    inc dword ptr [rip+s_struct_temp_count]
    # Emit through the long-standing compute-binding path.  Save/restore the
    # caller's current stream because this can happen while parsing an output.
    mov rdi,r14; mov rsi,r15; mov rdx,rbx; call s_emit_compute_ast
    test eax,eax; jnz .smsa_restore_fail
    mov [rip+s_out_ptr],r12; mov [rip+s_out_limit],r13
    call s_new_ast; test rax,rax; jz .smsa_fail
    mov dword ptr [rax+SN_KIND],NK_VAR
    mov [rax+SN_PTR],r14; mov [rax+SN_LEN],r15
    jmp .smsa_done
.smsa_restore_fail:
    mov [rip+s_out_ptr],r12; mov [rip+s_out_limit],r13
.smsa_fail:
    mov dword ptr [rip+s_error],1; xor eax,eax; jmp .smsa_done
.smsa_same: mov rax,rbx
.smsa_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Generic Structured Fact checkpointing: every scalar carrier joins the old
# compute-binding/ValueFact authority, then the compile-time container is rebuilt
# from those scalar identities.  No structured runtime representation is added.
s_materialize_struct:
    # rdi=NK_STRUCT -> rax rebuilt NK_STRUCT /0.  Checkpoint storage is derived
    # from the fact width, so a generalized matrix does not acquire a second
    # materialization path merely because it has more than sixteen scalars.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    test rbx,rbx; jz .smst_fail_nostack
    cmp dword ptr [rbx+SN_KIND],NK_STRUCT; jne .smst_fail_nostack
    mov r12d,dword ptr [rbx+SN_OP]
    test r12d,r12d; jz .smst_fail_nostack
    mov r13d,dword ptr [rbx+SN_AUX]
    mov eax,r12d; shl rax,3; add rax,15; and rax,-16
    sub rsp,rax
    xor r14d,r14d
.smst_loop:
    cmp r14d,r12d; jae .smst_build
    mov rdi,rbx; mov esi,r14d; call s_struct_component; test rax,rax; jz .smst_fail
    mov rdi,rax; call s_materialize_scalar_ast; test rax,rax; jz .smst_fail
    mov [rsp+r14*8],rax
    inc r14d; jmp .smst_loop
.smst_build:
    mov edi,r13d; mov esi,r12d; mov rdx,rsp; call s_struct_build
    jmp .smst_done
.smst_fail:
    mov dword ptr [rip+s_error],1; xor eax,eax
.smst_done:
    mov edx,r12d; shl rdx,3; add rdx,15; and rdx,-16
    add rsp,rdx
    jmp .smst_epilogue
.smst_fail_nostack:
    mov dword ptr [rip+s_error],1; xor eax,eax
.smst_epilogue:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_static_key_equal:
    # rdi=a AST,rsi=b AST -> eax bool. Only literal keys are comparable.
    push rbx; push r12
    mov rbx,rdi; mov r12,rsi
    test rbx,rbx; jz .sske_no
    test r12,r12; jz .sske_no
    mov eax,dword ptr [rbx+SN_KIND]; cmp eax,dword ptr [r12+SN_KIND]; jne .sske_no
    cmp eax,NK_BOOL; je .sske_aux
    cmp eax,NK_IMM_U64; je .sske_aux
    cmp eax,NK_IMM_F64_BITS; je .sske_aux
    cmp eax,NK_NUM; je .sske_span_aux
    cmp eax,NK_STRING; je .sske_span
    jmp .sske_no
.sske_aux:
    mov rax,[rbx+SN_AUX]; cmp rax,[r12+SN_AUX]; sete al; movzx eax,al; jmp .sske_done
.sske_span_aux:
    mov rax,[rbx+SN_AUX]; cmp rax,[r12+SN_AUX]; jne .sske_no
.sske_span:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]
    mov rdx,[r12+SN_PTR]; mov rcx,[r12+SN_LEN]; call s_span_eq; jmp .sske_done
.sske_no: xor eax,eax
.sske_done: pop r12; pop rbx; ret

s_dictionary_find:
    # rdi=name,rsi=len -> eax index or -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sdf_loop:
    cmp r13d,dword ptr [rip+s_dictionary_count]; jae .sdf_no
    mov rax,[rip+s_dictionary_name_ptr]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_dictionary_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sdf_yes
    inc r13d; jmp .sdf_loop
.sdf_yes: mov eax,r13d; jmp .sdf_done
.sdf_no: mov eax,-1
.sdf_done: pop r13; pop r12; pop rbx; ret

s_parse_dictionary_decl:
    # dictionary name: key_type -> value_type { literal = closed_expr, ... }
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .spdd_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spdd_fail
    mov ebx,dword ptr [rip+s_dictionary_count]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .spdd_fail
    mov rax,[rip+s_dictionary_name_ptr]; mov [rax+rbx*8],r12
    mov rax,[rip+s_dictionary_name_len]; mov [rax+rbx*8],r13
    inc dword ptr [rip+s_dictionary_count]
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spdd_fail        # key type
    lea rdi,[rip+tok_arrowthin]; mov esi,2; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spdd_fail        # value type
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spdd_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spdd_done
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spdd_fail
    mov r14,rax
    mov eax,dword ptr [r14+SN_KIND]
    cmp eax,NK_STRING; je .spdd_key_ok
    cmp eax,NK_NUM; je .spdd_key_ok
    cmp eax,NK_BOOL; je .spdd_key_ok
    cmp eax,NK_IMM_U64; jne .spdd_fail
.spdd_key_ok:
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spdd_fail
    mov r15,rax; mov rdi,r15; call s_ast_closed; test eax,eax; jz .spdd_fail
    mov eax,dword ptr [rip+s_dictionary_entry_count]; cmp eax,dword ptr [rip+s_fact_cap]; jae .spdd_fail
    mov rdx,[rip+s_dictionary_entry_dict]; mov [rdx+rax*4],ebx
    mov rdx,[rip+s_dictionary_entry_key]; mov [rdx+rax*8],r14
    mov rdx,[rip+s_dictionary_entry_value]; mov [rdx+rax*8],r15
    inc dword ptr [rip+s_dictionary_entry_count]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    call s_optional_semicolon
    jmp .spdd_loop
.spdd_done: call s_optional_semicolon; xor eax,eax; jmp .spdd_exit
.spdd_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spdd_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_lookup_decl:
    # lookup result = dictionary[literal] default closed_expr
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .splu_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .splu_fail
    mov rdi,rax; mov rsi,rcx; call s_dictionary_find; cmp eax,-1; je .splu_fail
    mov ebx,eax
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .splu_fail
    mov r14,rax
    mov eax,dword ptr [r14+SN_KIND]
    cmp eax,NK_STRING; je .splu_key_ok
    cmp eax,NK_NUM; je .splu_key_ok
    cmp eax,NK_BOOL; je .splu_key_ok
    cmp eax,NK_IMM_U64; jne .splu_fail
.splu_key_ok:
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    mov edi,KID_DEFAULT; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .splu_fail
    mov r15,rax; mov rdi,r15; call s_ast_closed; test eax,eax; jz .splu_fail
    xor ecx,ecx
.splu_scan:
    cmp ecx,dword ptr [rip+s_dictionary_entry_count]; jae .splu_emit_default
    mov rax,[rip+s_dictionary_entry_dict]; cmp dword ptr [rax+rcx*4],ebx; jne .splu_next
    push rcx
    mov rax,[rip+s_dictionary_entry_key]; mov rdi,[rax+rcx*8]; mov rsi,r14; call s_static_key_equal
    pop rcx
    test eax,eax; jnz .splu_chosen
.splu_next: inc ecx; jmp .splu_scan
.splu_chosen:
    mov rax,[rip+s_dictionary_entry_value]; mov r15,[rax+rcx*8]
.splu_emit_default:
    mov rdi,r12; mov rsi,r13; mov rdx,r15; call s_emit_compute_ast
    test eax,eax; jnz .splu_fail
    call s_optional_semicolon; xor eax,eax; jmp .splu_exit
.splu_fail: mov dword ptr [rip+s_error],1; mov eax,1
.splu_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_nested_find:
    # rdi=name,rsi=len -> eax index or -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.snf_loop:
    cmp r13d,dword ptr [rip+s_nested_count]; jae .snf_no
    mov rax,[rip+s_nested_name_ptr]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_nested_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .snf_yes
    inc r13d; jmp .snf_loop
.snf_yes: mov eax,r13d; jmp .snf_done
.snf_no: mov eax,-1
.snf_done: pop r13; pop r12; pop rbx; ret

s_parse_nested_decl:
    # nested name: type = [[closed,...], ...]
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .spnd_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spnd_fail
    mov ebx,dword ptr [rip+s_nested_count]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .spnd_fail
    mov rax,[rip+s_nested_name_ptr]; mov [rax+rbx*8],r12
    mov rax,[rip+s_nested_name_len]; mov [rax+rbx*8],r13
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spnd_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor r14d,r14d                         # count
    xor r15d,r15d                         # segments
    mov qword ptr [rip+s_nested_build_sum],0
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_store
.spnd_seg:
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    inc r15d
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_seg_done
.spnd_item:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spnd_fail
    mov [rip+s_nested_item_ast],rax
    mov rdi,rax; call s_ast_closed; test eax,eax; jz .spnd_fail
    mov r11,[rip+s_nested_item_ast]
    inc r14d
    mov r10,[rip+s_nested_build_sum]; test r10,r10; jz .spnd_first
    mov edi,OP_ADD; mov rsi,r10; mov rdx,r11; call s_ast_binary_new
    test rax,rax; jz .spnd_fail
    mov [rip+s_nested_build_sum],rax; jmp .spnd_after_add
.spnd_first: mov [rip+s_nested_build_sum],r11
.spnd_after_add:
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_item
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
.spnd_seg_done:
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_seg
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
.spnd_store:
    mov r10,[rip+s_nested_build_sum]; test r10,r10; jnz .spnd_have_sum
    xor edi,edi; call s_ast_u64_imm; mov r10,rax
.spnd_have_sum:
    mov rax,[rip+s_nested_sum_ast]; mov [rax+rbx*8],r10
    mov rax,[rip+s_nested_item_count]; mov [rax+rbx*8],r14
    mov rax,[rip+s_nested_segment_count]; mov [rax+rbx*8],r15
    inc dword ptr [rip+s_nested_count]
    call s_optional_semicolon; xor eax,eax; jmp .spnd_exit
.spnd_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spnd_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_nested_reduce_decl:
    # nested_reduce result[:type] = sum|count|segment_count nested_name
    push rbx; push r12; push r13; push r14
    call s_parse_name; test edx,edx; jnz .spnr_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spnr_eq
    call s_parse_name; test edx,edx; jnz .spnr_fail
.spnr_eq:
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spnr_sum
    call s_parse_name; test edx,edx; jnz .spnr_fail
    mov r14,rax; mov r11,rcx
    lea rdi,[rip+kw_count]; mov esi,5; mov rdx,r14; mov rcx,r11; xchg rdi,rdx; xchg rsi,rcx; call s_span_eq
    test eax,eax; jnz .spnr_count
    mov rdi,r14; mov rsi,r11; lea rdx,[rip+kw_segment_count]; mov ecx,13; call s_span_eq
    test eax,eax; jnz .spnr_segments
    jmp .spnr_fail
.spnr_sum:
    mov ebx,0; jmp .spnr_source
.spnr_count: mov ebx,1; jmp .spnr_source
.spnr_segments: mov ebx,2
.spnr_source:
    call s_parse_name; test edx,edx; jnz .spnr_fail
    mov rdi,rax; mov rsi,rcx; call s_nested_find; cmp eax,-1; je .spnr_fail
    mov r14d,eax
    cmp ebx,0; je .spnr_get_sum
    cmp ebx,1; je .spnr_get_count
    mov rax,[rip+s_nested_segment_count]; mov rdi,[rax+r14*8]; call s_ast_u64_imm; jmp .spnr_emit
.spnr_get_count:
    mov rax,[rip+s_nested_item_count]; mov rdi,[rax+r14*8]; call s_ast_u64_imm; jmp .spnr_emit
.spnr_get_sum:
    mov rax,[rip+s_nested_sum_ast]; mov rax,[rax+r14*8]
.spnr_emit:
    test rax,rax; jz .spnr_fail
    mov rdi,r12; mov rsi,r13; mov rdx,rax; call s_emit_compute_ast
    test eax,eax; jnz .spnr_fail
    call s_optional_semicolon; xor eax,eax; jmp .spnr_exit
.spnr_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spnr_exit: pop r14; pop r13; pop r12; pop rbx; ret

# Parse an integer literal AST into u64. eax status in edx (0 success).
s_eval_literal_u64_fixed:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi
    cmp dword ptr [rbx+SN_KIND],NK_IMM_U64; jne 1f
    mov rax,[rbx+SN_AUX]; xor edx,edx; jmp .self_done
1:  cmp dword ptr [rbx+SN_KIND],NK_BOOL; jne 2f
    mov eax,dword ptr [rbx+SN_AUX]; xor edx,edx; jmp .self_done
2:  cmp dword ptr [rbx+SN_KIND],NK_NUM; jne .self_fail
    cmp qword ptr [rbx+SN_AUX],0; jne .self_fail
    mov r12,[rbx+SN_PTR]; mov r13,[rbx+SN_LEN]; xor r14d,r14d
    xor eax,eax
.self_loop:
    cmp r14,r13; jae .self_ok
    movzx ecx,byte ptr [r12+r14]; cmp cl,'0'; jb .self_fail; cmp cl,'9'; ja .self_fail
    sub ecx,'0'
    mov r8,rax
    mov r9,10; mul r9; test rdx,rdx; jnz .self_fail
    add rax,rcx; jc .self_fail
    inc r14; jmp .self_loop
.self_ok: xor edx,edx; jmp .self_done
.self_fail: xor eax,eax; mov edx,1
.self_done: pop r14; pop r13; pop r12; pop rbx; ret

s_cascade_goal_find:
    # rdi=name,rsi=len -> eax index/-1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.scgf_loop:
    cmp r13d,dword ptr [rip+s_cascade_goal_count]; jae .scgf_no
    mov rax,[rip+s_cascade_goal_name_ptr]; mov rdi,[rax+r13*8]
    mov rax,[rip+s_cascade_goal_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .scgf_yes
    inc r13d; jmp .scgf_loop
.scgf_yes: mov eax,r13d; jmp .scgf_done
.scgf_no: mov eax,-1
.scgf_done: pop r13; pop r12; pop rbx; ret

s_eval_static_u64:
    # rdi=AST -> rax=value, edx=0 success / 1 unresolved-or-invalid.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; test rbx,rbx; jz .ses_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .ses_literal
    cmp eax,NK_IMM_U64; je .ses_literal
    cmp eax,NK_BOOL; je .ses_literal
    cmp eax,NK_AXIS; je .ses_axis
    cmp eax,NK_GOAL_RESULT; je .ses_goal
    cmp eax,NK_CAST; je .ses_one
    cmp eax,NK_UNARY; je .ses_unary
    cmp eax,NK_BINARY; jne .ses_fail
    mov rdi,[rbx+SN_A]; call s_eval_static_u64; test edx,edx; jnz .ses_fail
    mov r12,rax
    mov rdi,[rbx+SN_B]; call s_eval_static_u64; test edx,edx; jnz .ses_fail
    mov r13,rax
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_SELECT; je .ses_select
    cmp eax,OP_ADD; je .ses_add
    cmp eax,OP_SUB; je .ses_sub
    cmp eax,OP_MUL; je .ses_mul
    cmp eax,OP_DIV; je .ses_div
    cmp eax,OP_MOD; je .ses_mod
    cmp eax,OP_BIT_AND; je .ses_band
    cmp eax,OP_BIT_OR; je .ses_bor
    cmp eax,OP_BIT_XOR; je .ses_bxor
    cmp eax,OP_SHL; je .ses_shl
    cmp eax,OP_SHR; je .ses_shr
    cmp eax,OP_EQ; je .ses_eq
    cmp eax,OP_NE; je .ses_ne
    cmp eax,OP_LT; je .ses_lt
    cmp eax,OP_LE; je .ses_le
    cmp eax,OP_GT; je .ses_gt
    cmp eax,OP_GE; je .ses_ge
    cmp eax,OP_MIN; je .ses_min
    cmp eax,OP_MAX; je .ses_max
    jmp .ses_fail
.ses_literal: mov rdi,rbx; call s_eval_literal_u64_fixed; jmp .ses_done
.ses_axis:
    cmp dword ptr [rip+s_cascade_axis_enabled],0; je .ses_fail
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]
    mov rdx,[rip+s_cascade_axis_ptr]; mov rcx,[rip+s_cascade_axis_len]; call s_span_eq
    test eax,eax; jz .ses_fail
    mov rax,[rip+s_cascade_axis_value]; xor edx,edx; jmp .ses_done
.ses_goal:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_cascade_goal_find
    cmp eax,-1; je .ses_fail
    mov ecx,eax; mov rax,[rip+s_cascade_goal_done]; cmp dword ptr [rax+rcx*4],0; je .ses_fail
    mov rax,[rip+s_cascade_goal_result]; mov rax,[rax+rcx*8]; xor edx,edx; jmp .ses_done
.ses_one: mov rdi,[rbx+SN_A]; call s_eval_static_u64; jmp .ses_done
.ses_unary:
    mov rdi,[rbx+SN_A]; call s_eval_static_u64; test edx,edx; jnz .ses_fail
    mov r12,rax; mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_NOT; je .ses_not
    cmp eax,OP_BIT_NOT; je .ses_bnot
    cmp eax,OP_ABS; je .ses_abs
    cmp eax,OP_NEG; jne .ses_fail
    test r12,r12; jz .ses_zero
    cmp dword ptr [rip+s_overflow_wrap],0; je .ses_fail
    mov rax,r12; neg rax; xor edx,edx; jmp .ses_done
.ses_zero: xor eax,eax; xor edx,edx; jmp .ses_done
.ses_not: test r12,r12; sete al; movzx eax,al; xor edx,edx; jmp .ses_done
.ses_bnot: mov rax,r12; not rax; xor edx,edx; jmp .ses_done
.ses_abs: mov rax,r12; xor edx,edx; jmp .ses_done
.ses_select:
    test r12,r12; jz .ses_select_c
    mov rax,r13; xor edx,edx; jmp .ses_done
.ses_select_c:
    mov rdi,[rbx+SN_C]; call s_eval_static_u64; jmp .ses_done
.ses_add: mov rax,r12; add rax,r13; jnc .ses_ok; cmp dword ptr [rip+s_overflow_wrap],0; jne .ses_ok; jmp .ses_fail
.ses_sub: mov rax,r12; sub rax,r13; jnc .ses_ok; cmp dword ptr [rip+s_overflow_wrap],0; jne .ses_ok; jmp .ses_fail
.ses_mul: mov rax,r12; mul r13; test rdx,rdx; jz .ses_ok; cmp dword ptr [rip+s_overflow_wrap],0; jne .ses_ok; jmp .ses_fail
.ses_div: test r13,r13; jz .ses_fail; mov rax,r12; xor edx,edx; div r13; xor edx,edx; jmp .ses_done
.ses_mod: test r13,r13; jz .ses_fail; mov rax,r12; xor edx,edx; div r13; mov rax,rdx; xor edx,edx; jmp .ses_done
.ses_band: mov rax,r12; and rax,r13; jmp .ses_ok
.ses_bor: mov rax,r12; or rax,r13; jmp .ses_ok
.ses_bxor: mov rax,r12; xor rax,r13; jmp .ses_ok
.ses_shl: cmp r13,64; jae .ses_fail; mov rax,r12; mov rcx,r13; shl rax,cl; jmp .ses_ok
.ses_shr: cmp r13,64; jae .ses_fail; mov rax,r12; mov rcx,r13; shr rax,cl; jmp .ses_ok
.ses_eq: cmp r12,r13; sete al; movzx eax,al; jmp .ses_ok
.ses_ne: cmp r12,r13; setne al; movzx eax,al; jmp .ses_ok
.ses_lt: cmp r12,r13; setb al; movzx eax,al; jmp .ses_ok
.ses_le: cmp r12,r13; setbe al; movzx eax,al; jmp .ses_ok
.ses_gt: cmp r12,r13; seta al; movzx eax,al; jmp .ses_ok
.ses_ge: cmp r12,r13; setae al; movzx eax,al; jmp .ses_ok
.ses_min: mov rax,r12; cmp r13,r12; cmovb rax,r13; jmp .ses_ok
.ses_max: mov rax,r12; cmp r13,r12; cmova rax,r13
.ses_ok: xor edx,edx; jmp .ses_done
.ses_fail: xor eax,eax; mov edx,1
.ses_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_record_add_static_field:
    # rdi=record ptr,rsi=len,rdx=field ptr,rcx=len,r8=AST -> eax
    push rbx
    mov ebx,dword ptr [rip+s_record_field_count]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .sras_fail
    mov rax,[rip+s_record_name_ptr]; mov [rax+rbx*8],rdi
    mov rax,[rip+s_record_name_len]; mov [rax+rbx*8],rsi
    mov rax,[rip+s_record_field_ptr]; mov [rax+rbx*8],rdx
    mov rax,[rip+s_record_field_len]; mov [rax+rbx*8],rcx
    mov rax,[rip+s_record_value_ast]; mov [rax+rbx*8],r8
    inc dword ptr [rip+s_record_field_count]
    xor eax,eax; pop rbx; ret
.sras_fail: mov dword ptr [rip+s_error],1; mov eax,1; pop rbx; ret

s_cascade_prereqs_ready:
    # edi=target goal index -> eax=1 iff every explicit predecessor is done.
    # Relations live in one flat edge list.  Goal count therefore does not leak
    # into a machine-word bit mask or create a 32/64-goal source-language tier.
    push rbx; push r12; push r13
    mov ebx,edi; xor r12d,r12d
.scpr_loop:
    cmp r12d,dword ptr [rip+s_cascade_edge_count]; jae .scpr_yes
    mov rax,[rip+s_cascade_edge_to]; cmp dword ptr [rax+r12*4],ebx; jne .scpr_next
    mov rax,[rip+s_cascade_edge_from]; mov r13d,dword ptr [rax+r12*4]
    mov rax,[rip+s_cascade_goal_done]; cmp dword ptr [rax+r13*4],0; je .scpr_no
.scpr_next:
    inc r12d; jmp .scpr_loop
.scpr_yes:
    mov eax,1; jmp .scpr_done
.scpr_no:
    xor eax,eax
.scpr_done:
    pop r13; pop r12; pop rbx; ret

s_parse_cascade_decl:
    # Closed cascade -> compile-time record. Dynamic state/input use rejects.
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .spcas_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spcas_fail
    # Cascade syntax enters semantic axis directly; historical worker/chunk annotations are not accepted.
.spcas_axis:
    mov edi,KID_AXIS; call s_expect_kw_id
    call s_parse_name; test edx,edx; jnz .spcas_fail
    mov [rip+s_cascade_axis_ptr],rax; mov [rip+s_cascade_axis_len],rcx
    mov edi,KID_EVENTS; call s_match_kw_id; test eax,eax; jz .spcas_events_done
    mov edi,KID_TRUE; call s_match_kw_id; test eax,eax; jnz .spcas_events_done
    mov edi,KID_FALSE; call s_match_kw_id; test eax,eax; jz .spcas_fail
.spcas_events_done:
    mov dword ptr [rip+s_cascade_goal_count],0
    mov dword ptr [rip+s_cascade_edge_count],0
    # expose unit axis only while parsing the cascade body
    mov ebx,dword ptr [rip+s_axis_count]; cmp ebx,dword ptr [rip+s_fact_cap]; jae .spcas_fail
    mov rax,[rip+s_axis_ptrs]; mov rcx,[rip+s_cascade_axis_ptr]; mov [rax+rbx*8],rcx
    mov rax,[rip+s_axis_lens]; mov rcx,[rip+s_cascade_axis_len]; mov [rax+rbx*8],rcx
    inc dword ptr [rip+s_axis_count]
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spcas_body:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spcas_body_done
    mov edi,KID_GOAL; call s_match_kw_id; test eax,eax; jnz .spcas_goal
    mov edi,KID_RELATION; call s_match_kw_id; test eax,eax; jnz .spcas_relation
    jmp .spcas_fail_axis
.spcas_goal:
    call s_parse_name; test edx,edx; jnz .spcas_fail_axis
    mov r14,rax; mov r15,rcx
    mov eax,dword ptr [rip+s_cascade_goal_count]; cmp eax,dword ptr [rip+s_fact_cap]; jae .spcas_fail_axis
    mov rdx,[rip+s_cascade_goal_name_ptr]; mov [rdx+rax*8],r14
    mov rdx,[rip+s_cascade_goal_name_len]; mov [rdx+rax*8],r15
    mov edi,KID_WORK; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spcas_fail_axis
    mov ecx,dword ptr [rip+s_cascade_goal_count]; mov rdx,[rip+s_cascade_goal_work_ast]; mov [rdx+rcx*8],rax
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spcas_fail_axis
    mov ecx,dword ptr [rip+s_cascade_goal_count]; mov rdx,[rip+s_cascade_goal_expr_ast]; mov [rdx+rcx*8],rax
    mov rdx,[rip+s_cascade_goal_done]; mov dword ptr [rdx+rcx*4],0
    inc dword ptr [rip+s_cascade_goal_count]
    call s_optional_semicolon; jmp .spcas_body
.spcas_relation:
    call s_parse_name; test edx,edx; jnz .spcas_fail_axis
    mov rdi,rax; mov rsi,rcx; call s_cascade_goal_find; cmp eax,-1; je .spcas_fail_axis
    mov r14d,eax
    lea rdi,[rip+tok_arrowthin]; mov esi,2; xor edx,edx; call s_match_token
    test eax,eax; jnz .spcas_rel_target
    mov edi,KID_TO; call s_expect_kw_id
.spcas_rel_target:
    call s_parse_name; test edx,edx; jnz .spcas_fail_axis
    mov rdi,rax; mov rsi,rcx; call s_cascade_goal_find; cmp eax,-1; je .spcas_fail_axis
    mov r10d,eax
    mov ecx,dword ptr [rip+s_cascade_edge_count]
    cmp ecx,dword ptr [rip+s_fact_cap]; jae .spcas_fail_axis
    mov rdx,[rip+s_cascade_edge_from]; mov dword ptr [rdx+rcx*4],r14d
    mov rdx,[rip+s_cascade_edge_to]; mov dword ptr [rdx+rcx*4],r10d
    inc dword ptr [rip+s_cascade_edge_count]
    call s_optional_semicolon; jmp .spcas_body
.spcas_body_done:
    mov dword ptr [rip+s_axis_count],ebx
    # Fixed-point causal evaluation. A goal is eligible only after declared
    # predecessors and every goal_result it reads are available.  Completion is
    # represented by the goal facts themselves, not a machine-word-sized mask.
    xor r15d,r15d                           # done count
.spcas_eval_round:
    mov dword ptr [rip+s_cascade_eval_progressed],0
    mov dword ptr [rip+s_cascade_eval_goal_idx],0
.spcas_eval_goal:
    mov ecx,dword ptr [rip+s_cascade_eval_goal_idx]
    cmp ecx,dword ptr [rip+s_cascade_goal_count]; jae .spcas_eval_round_done
    mov rax,[rip+s_cascade_goal_done]; cmp dword ptr [rax+rcx*4],0; jne .spcas_eval_next
    mov edi,ecx; call s_cascade_prereqs_ready; test eax,eax; jz .spcas_eval_next
    mov dword ptr [rip+s_cascade_axis_enabled],0
    mov rax,[rip+s_cascade_goal_work_ast]; mov rdi,[rax+rcx*8]; call s_eval_static_u64
    test edx,edx; jnz .spcas_eval_next
    mov [rip+s_cascade_eval_work],rax
    mov qword ptr [rip+s_cascade_eval_unit],0
    mov qword ptr [rip+s_cascade_eval_total],0
.spcas_units:
    mov r9,[rip+s_cascade_eval_unit]
    cmp r9,[rip+s_cascade_eval_work]; jae .spcas_goal_value
    mov dword ptr [rip+s_cascade_axis_enabled],1
    mov [rip+s_cascade_axis_value],r9
    mov ecx,dword ptr [rip+s_cascade_eval_goal_idx]
    mov rax,[rip+s_cascade_goal_expr_ast]; mov rdi,[rax+rcx*8]; call s_eval_static_u64
    test edx,edx; jnz .spcas_eval_next
    mov r10,[rip+s_cascade_eval_total]
    add r10,rax; jnc .spcas_sum_ok
    cmp dword ptr [rip+s_overflow_wrap],0; je .spcas_eval_hardfail
.spcas_sum_ok:
    mov [rip+s_cascade_eval_total],r10
    inc qword ptr [rip+s_cascade_eval_unit]
    jmp .spcas_units
.spcas_goal_value:
    mov ecx,dword ptr [rip+s_cascade_eval_goal_idx]
    mov r10,[rip+s_cascade_eval_total]
    mov rax,[rip+s_cascade_goal_result]; mov [rax+rcx*8],r10
    mov rax,[rip+s_cascade_goal_done]; mov dword ptr [rax+rcx*4],1
    inc r15d
    mov dword ptr [rip+s_cascade_eval_progressed],1
.spcas_eval_next:
    inc dword ptr [rip+s_cascade_eval_goal_idx]
    jmp .spcas_eval_goal
.spcas_eval_round_done:
    cmp r15d,dword ptr [rip+s_cascade_goal_count]; je .spcas_record
    cmp dword ptr [rip+s_cascade_eval_progressed],0; je .spcas_fail
    jmp .spcas_eval_round
.spcas_eval_hardfail:
    jmp .spcas_fail
.spcas_record:
    # Emit no binding. Materialize a compile-time record table instead.
    xor ecx,ecx
.spcas_record_loop:
    cmp ecx,dword ptr [rip+s_cascade_goal_count]; jae .spcas_completed
    mov rax,[rip+s_cascade_goal_result]; mov rdi,[rax+rcx*8]
    push rcx; call s_ast_u64_imm; pop rcx; mov r8,rax
    mov rax,[rip+s_cascade_goal_name_ptr]; mov rdx,[rax+rcx*8]
    mov rax,[rip+s_cascade_goal_name_len]; mov r9,[rax+rcx*8]
    push rcx; mov rcx,r9; mov rdi,r12; mov rsi,r13; call s_record_add_static_field; pop rcx
    test eax,eax; jnz .spcas_fail
    inc ecx; jmp .spcas_record_loop
.spcas_completed:
    mov edi,r15d; call s_ast_u64_imm; mov r8,rax
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_completed_goals]; mov ecx,15; call s_record_add_static_field
    test eax,eax; jnz .spcas_fail
    call s_optional_semicolon; xor eax,eax; jmp .spcas_exit
.spcas_fail_axis:
    mov dword ptr [rip+s_axis_count],ebx
.spcas_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spcas_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Root parser / final canonical JSON assembly
# -----------------------------------------------------------------------------
s_parse_wh:
.spwh_loop:
    call s_skip
    mov rax,[rip+s_cur]; cmp rax,[rip+s_end]; jae .spwh_done
    mov edi,KID_PROGRAM; call s_match_kw_id; test eax,eax; jnz .spwh_program
    mov edi,KID_CONTRACT; call s_match_kw_id; test eax,eax; jnz .spwh_contract
    mov edi,KID_TOLERANCE; call s_match_kw_id; test eax,eax; jnz .spwh_tol
    mov edi,KID_STRICT; call s_match_kw_id; test eax,eax; jnz .spwh_strict
    mov edi,KID_PRECISION_PROPAGATION; call s_match_kw_id; test eax,eax; jnz .spwh_precision
    mov edi,KID_INPUT; call s_match_kw_id; test eax,eax; jnz .spwh_input
    mov edi,KID_AXIS; call s_match_kw_id; test eax,eax; jnz .spwh_axis
    mov edi,KID_RECORD; call s_match_kw_id; test eax,eax; jnz .spwh_record
    mov edi,KID_PURE; call s_match_kw_id; test eax,eax; jnz .spwh_pure
    mov edi,KID_REGION; call s_match_kw_id; test eax,eax; jnz .spwh_region
    mov edi,KID_FOR; call s_match_kw_id; test eax,eax; jnz .spwh_for
    mov edi,KID_WHILE; call s_match_kw_id; test eax,eax; jnz .spwh_fail
    mov edi,KID_LET; call s_match_kw_id; test eax,eax; jnz .spwh_let
    mov edi,KID_TENSOR; call s_match_kw_id; test eax,eax; jnz .spwh_tensor
    mov edi,KID_REDUCE; call s_match_kw_id; test eax,eax; jnz .spwh_reduce
    mov edi,KID_DICTIONARY; call s_match_kw_id; test eax,eax; jnz .spwh_dictionary
    mov edi,KID_LOOKUP; call s_match_kw_id; test eax,eax; jnz .spwh_lookup
    mov edi,KID_NESTED; call s_match_kw_id; test eax,eax; jnz .spwh_nested
    mov edi,KID_NESTED_REDUCE; call s_match_kw_id; test eax,eax; jnz .spwh_nested_reduce
    mov edi,KID_CASCADE; call s_match_kw_id; test eax,eax; jnz .spwh_cascade
    mov edi,KID_ITERATE; call s_match_kw_id; test eax,eax; jnz .spwh_iterate
    mov edi,KID_OUTPUT; call s_match_kw_id; test eax,eax; jnz .spwh_output
    mov edi,KID_PUBLISH; call s_match_kw_id; test eax,eax; jnz .spwh_output
    mov edi,KID_TEST; call s_match_kw_id; test eax,eax; jnz .spwh_test
    jmp .spwh_fail
.spwh_program: call s_parse_program_decl; jmp .spwh_check
.spwh_contract: call s_parse_contract_decl; jmp .spwh_check
.spwh_tol: call s_parse_tolerance_decl; jmp .spwh_check
.spwh_strict: call s_parse_strict_decl; jmp .spwh_check
.spwh_precision: call s_parse_precision_propagation_decl; jmp .spwh_check
.spwh_input: call s_parse_input_decl; jmp .spwh_check
.spwh_axis: call s_parse_whex_axis_decl; jmp .spwh_check
.spwh_record: call s_parse_record_decl; jmp .spwh_check
.spwh_pure: call s_parse_pure_function; jmp .spwh_check
.spwh_region: call s_parse_wh_region; jmp .spwh_check
.spwh_for: call s_parse_wh_for; jmp .spwh_check
.spwh_let: call s_parse_let_decl; jmp .spwh_check
.spwh_tensor: call s_parse_tensor_decl; jmp .spwh_check
.spwh_reduce: call s_parse_reduce_decl; jmp .spwh_check
.spwh_dictionary: call s_parse_dictionary_decl; jmp .spwh_check
.spwh_lookup: call s_parse_lookup_decl; jmp .spwh_check
.spwh_nested: call s_parse_nested_decl; jmp .spwh_check
.spwh_nested_reduce: call s_parse_nested_reduce_decl; jmp .spwh_check
.spwh_cascade: call s_parse_cascade_decl; jmp .spwh_check
.spwh_iterate: call s_parse_iterate_decl; jmp .spwh_check
.spwh_output: call s_parse_output_decl; jmp .spwh_check
.spwh_test: call s_parse_test_decl
.spwh_check:
    test eax,eax; jnz .spwh_fail
    cmp dword ptr [rip+s_error],0; jne .spwh_fail
    jmp .spwh_loop
.spwh_done: xor eax,eax; ret
.spwh_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_whex:
.spwxh_loop:
    call s_skip
    mov rax,[rip+s_cur]; cmp rax,[rip+s_end]; jae .spwxh_done
    mov edi,KID_PROGRAM; call s_match_kw_id; test eax,eax; jnz .spwxh_program
    mov edi,KID_INPUT; call s_match_kw_id; test eax,eax; jnz .spwxh_input
    mov edi,KID_TOLERANCE; call s_match_kw_id; test eax,eax; jnz .spwxh_tol
    mov edi,KID_STRICT; call s_match_kw_id; test eax,eax; jnz .spwxh_strict
    mov edi,KID_PRECISION_PROPAGATION; call s_match_kw_id; test eax,eax; jnz .spwxh_precision
    mov edi,KID_AXIS; call s_match_kw_id; test eax,eax; jnz .spwxh_axis
    mov edi,KID_RECORD; call s_match_kw_id; test eax,eax; jnz .spwxh_record
    mov edi,KID_PURE; call s_match_kw_id; test eax,eax; jnz .spwxh_pure
    mov edi,KID_REGION; call s_match_kw_id; test eax,eax; jnz .spwxh_region
    mov edi,KID_FIELD; call s_match_kw_id; test eax,eax; jnz .spwxh_field
    mov edi,KID_EACH; call s_match_kw_id; test eax,eax; jnz .spwxh_each
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spwxh_sum
    mov edi,KID_OUTPUT; call s_match_kw_id; test eax,eax; jnz .spwxh_output
    mov edi,KID_TEST; call s_match_kw_id; test eax,eax; jnz .spwxh_test
    jmp .spwxh_fail
.spwxh_program: call s_parse_program_decl; jmp .spwxh_check
.spwxh_input: call s_parse_input_decl; jmp .spwxh_check
.spwxh_tol: call s_parse_tolerance_decl; jmp .spwxh_check
.spwxh_strict: call s_parse_strict_decl; jmp .spwxh_check
.spwxh_precision: call s_parse_precision_propagation_decl; jmp .spwxh_check
.spwxh_axis: call s_parse_whex_axis_decl; jmp .spwxh_check
.spwxh_record: call s_parse_record_decl; jmp .spwxh_check
.spwxh_pure: call s_parse_pure_function; jmp .spwxh_check
.spwxh_region: call s_parse_whex_region; jmp .spwxh_check
.spwxh_field: call s_parse_whex_field; jmp .spwxh_check
.spwxh_each: call s_parse_whex_each; jmp .spwxh_check
.spwxh_sum: call s_parse_whex_sum; jmp .spwxh_check
.spwxh_output: call s_parse_output_decl; jmp .spwxh_check
.spwxh_test: call s_parse_test_decl
.spwxh_check:
    test eax,eax; jnz .spwxh_fail
    cmp dword ptr [rip+s_error],0; jne .spwxh_fail
    jmp .spwxh_loop
.spwxh_done: xor eax,eax; ret
.spwxh_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_path_is_whex:
    # rdi path -> eax bool
    xor ecx,ecx
.spiw_len: cmp byte ptr [rdi+rcx],0; je .spiw_chk; inc ecx; jmp .spiw_len
.spiw_chk: cmp ecx,5; jb .spiw_no
    lea rax,[rdi+rcx-5]
    cmp byte ptr [rax],'.'; jne .spiw_no
    cmp byte ptr [rax+1],'w'; jne .spiw_no
    cmp byte ptr [rax+2],'h'; jne .spiw_no
    cmp byte ptr [rax+3],'e'; jne .spiw_no
    cmp byte ptr [rax+4],'x'; jne .spiw_no
    mov eax,1; ret
.spiw_no: xor eax,eax; ret

s_finalize_json:
    lea rax,[rip+surface_json_buffer]; mov [rip+s_active_base_var],rax
    mov qword ptr [rip+s_active_end_var],0
    lea rax,[rip+surface_json_cap]; mov [rip+s_active_cap_var],rax
    mov rax,[rip+surface_json_buffer]; mov [rip+s_out_ptr],rax
    add rax,[rip+surface_json_cap]; mov [rip+s_out_limit],rax
    lea rdi,[rip+js_root_format]; call s_out_cstr
    # program
    mov rdi,[rip+s_program_ptr]; mov rsi,[rip+s_program_len]
    test rdi,rdi; jnz .sfj_have_program
    lea rdi,[rip+default_program]; mov esi,15
.sfj_have_program:
    call s_out_quote_span
    lea rdi,[rip+js_contract_prefix]; call s_out_cstr
    cmp dword ptr [rip+s_deterministic],0; je .sfj_det_false
    lea rdi,[rip+lit_true]; call s_out_cstr; jmp .sfj_det_done
.sfj_det_false: lea rdi,[rip+lit_false]; call s_out_cstr
.sfj_det_done:
    lea rdi,[rip+js_overflow_mid]; call s_out_cstr
    cmp dword ptr [rip+s_overflow_wrap],0; je .sfj_trap
    lea rdi,[rip+cv_wrap]; mov esi,4; call s_out_quote_span; jmp .sfj_overflow_done
.sfj_trap: lea rdi,[rip+cv_trap]; mov esi,4; call s_out_quote_span
.sfj_overflow_done:
    lea rdi,[rip+js_fp_mid]; call s_out_cstr
    cmp dword ptr [rip+s_fp_tolerant],0; je .sfj_fp_strict
    lea rdi,[rip+cv_tolerant]; mov esi,8; call s_out_quote_span; jmp .sfj_fp_done
.sfj_fp_strict: lea rdi,[rip+cv_strict]; mov esi,17; call s_out_quote_span
.sfj_fp_done:
    # Mixed-precision policy is a first-class compile-time contract for every
    # source surface. Tensor/Field may ignore it until multiple FP widths meet.
    lea rdi,[rip+js_mixed_mid]; call s_out_cstr
    cmp dword ptr [rip+s_precision_propagation],0; jne .sfj_mixed_high
    lea rdi,[rip+cv_mixed_low]; call s_out_cstr; jmp .sfj_contract_close
.sfj_mixed_high:
    lea rdi,[rip+cv_mixed_high]; call s_out_cstr
.sfj_contract_close:
    lea rdi,[rip+js_inputs_prefix]; call s_out_cstr
    mov rdi,[rip+s_inputs_buf]; mov rsi,[rip+s_inputs_end]; sub rsi,rdi; call s_out_span
    lea rdi,[rip+js_bindings_mid]; call s_out_cstr
    mov rdi,[rip+s_bindings_buf]; mov rsi,[rip+s_bindings_end]; sub rsi,rdi; call s_out_span
    lea rdi,[rip+js_outputs_mid]; call s_out_cstr
    mov rdi,[rip+s_outputs_buf]; mov rsi,[rip+s_outputs_end]; sub rsi,rdi; call s_out_span
    lea rdi,[rip+js_tests_mid]; call s_out_cstr
    mov rdi,[rip+s_tests_buf]; mov rsi,[rip+s_tests_end]; sub rsi,rdi; call s_out_span
    # Close tests exactly once. Optional metadata is appended to the root object.
    mov dil,']'; call s_out_byte
    # Optional compiler-lane and ShapeFact-N metadata.  ShapeFact-N is the only
    # logical-shape authority; no product/rank compatibility scalar survives.
    cmp dword ptr [rip+s_general_lane],0; je .sfj_shape
    lea rdi,[rip+js_general_lane]; call s_out_cstr
.sfj_shape:
    cmp dword ptr [rip+s_shapefact_active],0; je .sfj_close
    call s_emit_shapefact_json
    test eax,eax; jnz .sfj_fail
.sfj_close:
    mov dil,'}'; call s_out_byte
    mov rax,[rip+s_out_ptr]; mov rcx,[rip+surface_json_buffer]; sub rax,rcx
    mov [rip+surface_json_length],rax
    xor eax,eax; ret
.sfj_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1
    ret

# Emit the active sparse ShapeFact-N.  Extent identity stays logical; the Tensor
# physicalizer decides how to collapse it onto silicon.
s_emit_shapefact_json:
    push rbx; push r12; push r13
    lea rdi,[rip+js_shapefact_prefix]; call s_out_cstr
    xor ebx,ebx
.sesf_loop:
    cmp ebx,dword ptr [rip+s_shape_rank]; jae .sesf_done
    test ebx,ebx; jz .sesf_no_comma
    mov dil,','; call s_out_byte
.sesf_no_comma:
    lea rdi,[rip+js_shape_axis_name]; call s_out_cstr
    mov rax,[rip+s_shape_axis_ptrs]; mov rdi,[rax+rbx*8]
    mov rax,[rip+s_shape_axis_lens]; mov rsi,[rax+rbx*8]; call s_out_quote_span
    mov rax,[rip+s_shape_extent_kind]
    cmp dword ptr [rax+rbx*4],SHAPEFN_EXTENT_RUNTIME; jne .sesf_static
    lea rdi,[rip+js_shape_extent_var]; call s_out_cstr
    mov rax,[rip+s_shape_extent_ptrs]; mov rdi,[rax+rbx*8]
    mov rax,[rip+s_shape_extent_lens]; mov rsi,[rax+rbx*8]; call s_out_quote_span
    lea rdi,[rip+js_obj2_close]; call s_out_cstr
    jmp .sesf_next
.sesf_static:
    lea rdi,[rip+js_shape_extent_static]; call s_out_cstr
    mov rax,[rip+s_shape_extent_static]; mov rdi,[rax+rbx*8]; call s_emit_u64_decimal
    lea rdi,[rip+js_shape_extent_static_close]; call s_out_cstr
.sesf_next:
    inc ebx; jmp .sesf_loop
.sesf_done:
    lea rdi,[rip+js_shapefact_close]; call s_out_cstr
    xor eax,eax
    pop r13; pop r12; pop rbx; ret

s_emit_u64_decimal:
    # rdi=value to current output
    push rbx
    mov rax,rdi; lea rbx,[rip+s_num_scratch+31]; xor ecx,ecx
    test rax,rax; jnz .seud_loop
    dec rbx; mov byte ptr [rbx],'0'; mov ecx,1; jmp .seud_emit
.seud_loop:
    xor edx,edx; mov r8,10; div r8; add dl,'0'; dec rbx; mov [rbx],dl; inc ecx; test rax,rax; jnz .seud_loop
.seud_emit: mov rdi,rbx; mov rsi,rcx; call s_out_span; pop rbx; ret

surface_lower_to_json:
    # rdi=input path. Uses global source_ptr/source_length. eax 0 success.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    mov rdi,rbx; call s_diag_reset_for_path
    mov dword ptr [rip+s_error],0
    mov dword ptr [rip+s_ast_count],0
    mov dword ptr [rip+s_input_count],0; mov dword ptr [rip+s_binding_count],0
    mov dword ptr [rip+s_output_count],0; mov dword ptr [rip+s_test_count],0
    mov dword ptr [rip+s_general_lane],0; mov dword ptr [rip+s_shapefact_active],0
    mov dword ptr [rip+s_record_field_count],0; mov dword ptr [rip+s_function_count],0; mov dword ptr [rip+s_decl_count],0; mov dword ptr [rip+s_struct_decl_count],0
    mov dword ptr [rip+s_function_param_total],0; mov dword ptr [rip+s_decl_shape_stride_count],0
    mov dword ptr [rip+s_subst_multi_active],0
    mov dword ptr [rip+s_struct_temp_count],0; mov qword ptr [rip+s_type_capture_len],0
    mov dword ptr [rip+s_dictionary_count],0; mov dword ptr [rip+s_dictionary_entry_count],0; mov dword ptr [rip+s_nested_count],0
    mov dword ptr [rip+s_cascade_goal_count],0; mov dword ptr [rip+s_cascade_edge_count],0; mov dword ptr [rip+s_cascade_axis_enabled],0
    mov dword ptr [rip+s_overflow_wrap],0; mov dword ptr [rip+s_deterministic],1
    mov dword ptr [rip+s_fp_tolerant],0
    mov dword ptr [rip+s_precision_propagation],0
    mov qword ptr [rip+s_tol_ptr],0; mov qword ptr [rip+s_tol_len],0
    mov qword ptr [rip+s_program_ptr],0; mov qword ptr [rip+s_program_len],0
    mov qword ptr [rip+s_ast_cur],0; mov qword ptr [rip+s_ast_end],0; mov qword ptr [rip+s_ast_next_slab_bytes],0
    mov qword ptr [rip+s_struct_temp_cur],0; mov qword ptr [rip+s_struct_temp_end],0; mov qword ptr [rip+s_struct_temp_next_slab_bytes],0
    call s_prepare_surface_arenas; test eax,eax; jnz .sltj_fail
    mov rax,[rip+source_ptr]; mov [rip+s_src],rax; mov [rip+s_cur],rax
    add rax,[rip+source_length]; mov [rip+s_end],rax
    mov rax,[rip+s_inputs_buf]; mov [rip+s_inputs_end],rax
    mov rax,[rip+s_bindings_buf]; mov [rip+s_bindings_end],rax
    mov rax,[rip+s_outputs_buf]; mov [rip+s_outputs_end],rax
    mov rax,[rip+s_tests_buf]; mov [rip+s_tests_end],rax
    mov rdi,rbx
    call s_path_is_whex
    mov [rip+s_mode],eax
    test eax,eax; jz .sltj_wh
    call s_parse_whex; jmp .sltj_after
.sltj_wh: call s_parse_wh
.sltj_after:
    test eax,eax; jnz .sltj_fail
    cmp dword ptr [rip+s_output_count],0; je .sltj_fail
    # Tests are optional validation metadata, not a semantic prerequisite.
    # An executable program with outputs must compile identically whether or
    # not an embedded test vector is present.
    call s_finalize_json
    test eax,eax; jnz .sltj_fail
    mov rax,[rip+surface_json_buffer]; mov [rip+source_ptr],rax
    mov rax,[rip+surface_json_length]; mov [rip+source_length],rax
    xor eax,eax; jmp .sltj_done
.sltj_fail:
    call s_diag_note_error_cursor
    mov eax,1
.sltj_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
.section .rodata
rec_hex_digits:.ascii "0123456789abcdef"
rec_counter_name:.ascii "@r.counter"
rec_counter_name_end:
# punctuation
 tok_bang:.ascii "!"; tok_tilde:.ascii "~"; tok_minus:.ascii "-"; tok_plus:.ascii "+"
 tok_minus_math:.byte 0xE2,0x88,0x92; tok_sqrt_math:.byte 0xE2,0x88,0x9A
 tok_not_math:.byte 0xC2,0xAC
 tok_sup2:.byte 0xC2,0xB2; tok_sup3:.byte 0xC2,0xB3
 tok_lparen:.ascii "("; tok_rparen:.ascii ")"; tok_lbrack:.ascii "["; tok_rbrack:.ascii "]"
 tok_lbrace:.ascii "{"; tok_rbrace:.ascii "}"; tok_comma:.ascii ","; tok_colon:.ascii ":"; tok_semicolon:.ascii ";"
 tok_eq1:.ascii "="; tok_dot:.ascii "."; tok_dotdot:.ascii ".."; tok_arrowfat:.ascii "=>"; tok_arrowthin:.ascii "->"
# keywords/names
kw_program:.ascii "program"; kw_contract:.ascii "contract"; kw_input:.ascii "input"; kw_range:.ascii "range"; kw_for:.ascii "for"; kw_if:.ascii "if"; kw_else:.ascii "else"
kw_let:.ascii "let"; kw_tensor:.ascii "tensor"; kw_reduce:.ascii "reduce"; kw_iterate:.ascii "iterate"
kw_output:.ascii "output"; kw_publish:.ascii "publish"; kw_test:.ascii "test"; kw_limit:.ascii "limit"
kw_state:.ascii "state"; kw_while:.ascii "while"; kw_update:.ascii "update"; kw_result:.ascii "result"
kw_true:.ascii "true"; kw_false:.ascii "false"; kw_cast:.ascii "cast"; kw_periodic:.ascii "periodic"; kw_select:.ascii "select"
kw_min:.ascii "min"; kw_max:.ascii "max"; kw_abs:.ascii "abs"; kw_sqrt:.ascii "sqrt"; kw_trunc:.ascii "trunc"; kw_pow:.ascii "pow"; kw_rel:.ascii "rel"
kw_pi:.ascii "pi"; kw_pi_utf8:.byte 0xCF,0x80; kw_e:.ascii "e"; kw_e_script:.byte 0xE2,0x84,0xAF
kw_dot:.ascii "dot"; kw_inner:.ascii "inner"; kw_frobenius_inner:.ascii "frobenius_inner"
kw_squared_norm:.ascii "squared_norm"; kw_norm2_squared:.ascii "norm2_squared"; kw_squared_distance:.ascii "squared_distance"
kw_trace:.ascii "trace"
kw_matmul:.ascii "matmul"
kw_gram:.ascii "gram"; kw_mean:.ascii "mean"; kw_average:.ascii "average"; kw_norm:.ascii "norm"; kw_norm2:.ascii "norm2"
kw_distance:.ascii "distance"; kw_rms:.ascii "rms"; kw_variance:.ascii "variance"; kw_series:.ascii "series"
kw_derivative:.ascii "derivative"; kw_diff:.ascii "diff"; kw_gradient:.ascii "gradient"; kw_jacobian:.ascii "jacobian"
kw_second_derivative:.ascii "second_derivative"; kw_hessian:.ascii "hessian"; kw_laplacian:.ascii "laplacian"
kw_integral:.ascii "integral"; kw_quad:.ascii "quad"; kw_root:.ascii "root"; kw_newton:.ascii "newton"
kw_matrix:.ascii "matrix"
kw_xor:.ascii "xor"; kw_bit_and:.ascii "bit_and"; kw_bit_or:.ascii "bit_or"; kw_bit_xor:.ascii "bit_xor"
kw_shl:.ascii "shl"; kw_shr:.ascii "shr"
kw_in:.ascii "in"; kw_tolerance:.ascii "tolerance"; kw_strict:.ascii "strict"; kw_precision_propagation:.ascii "precision_propagation"; kw_field:.ascii "field"; kw_sum:.ascii "sum"
kw_axis:.ascii "axis"; kw_region:.ascii "region"; kw_effect:.ascii "effect"; kw_pure:.ascii "pure"; kw_parallel:.ascii "parallel"
kw_record:.ascii "record"; kw_generic:.ascii "generic"; kw_fn:.ascii "fn"
kw_dictionary:.ascii "dictionary"; kw_lookup:.ascii "lookup"; kw_default:.ascii "default"
kw_nested:.ascii "nested"; kw_nested_reduce:.ascii "nested_reduce"; kw_cascade:.ascii "cascade"
kw_events:.ascii "events"
kw_goal:.ascii "goal"; kw_work:.ascii "work"; kw_relation:.ascii "relation"; kw_to:.ascii "to"
kw_goal_result:.ascii "goal_result"; kw_count:.ascii "count"; kw_segment_count:.ascii "segment_count"
kw_completed_goals:.ascii "完成目标数"
shape_q_name:.ascii "__shape_q"; shape_product_name:.ascii "__shape_product"
ck_integer_overflow:.ascii "integer_overflow"; ck_deterministic:.ascii "deterministic"
cv_wrap:.ascii "wrap"; cv_trap:.ascii "trap"; cv_tolerant:.ascii "tolerant"; cv_strict:.ascii "strict_by_default"
ty_bool:.ascii "bool"; ty_i64:.ascii "i64"; ty_u64:.ascii "u64"; ty_f32:.ascii "f32"; ty_f64:.ascii "f64"; ty_string:.ascii "string"
ty_fp32:.ascii "fp32"; ty_fp64:.ascii "fp64"; ty_float32:.ascii "float32"; ty_float64:.ascii "float64"
ty_real32:.ascii "real32"; ty_real64:.ascii "real64"; ty_double:.ascii "double"
default_program:.ascii "surface_program"
lit_true:.asciz "true"; lit_false:.asciz "false"; num_zero_float:.asciz "0.0"
lit_f64bits_prefix:.asciz "@f64bits:"
# UTF-8 keyword aliases: compile-time only.
kwa_program_0:.ascii "program"; kwa_program_0_end:
kwa_program_1:.ascii "程序"; kwa_program_1_end:
kwa_program_2:.ascii "程式"; kwa_program_2_end:
kwa_contract_0:.ascii "contract"; kwa_contract_0_end:
kwa_contract_1:.ascii "契约"; kwa_contract_1_end:
kwa_contract_2:.ascii "契約"; kwa_contract_2_end:
kwa_input_0:.ascii "input"; kwa_input_0_end:
kwa_input_1:.ascii "输入"; kwa_input_1_end:
kwa_input_2:.ascii "輸入"; kwa_input_2_end:
kwa_range_0:.ascii "range"; kwa_range_0_end:
kwa_range_1:.ascii "范围"; kwa_range_1_end:
kwa_range_2:.ascii "範圍"; kwa_range_2_end:
kwa_let_0:.ascii "let"; kwa_let_0_end:
kwa_let_1:.ascii "定义"; kwa_let_1_end:
kwa_let_2:.ascii "定義"; kwa_let_2_end:
kwa_let_3:.ascii "令"; kwa_let_3_end:
kwa_tensor_0:.ascii "tensor"; kwa_tensor_0_end:
kwa_tensor_1:.ascii "张量"; kwa_tensor_1_end:
kwa_tensor_2:.ascii "張量"; kwa_tensor_2_end:
kwa_reduce_0:.ascii "reduce"; kwa_reduce_0_end:
kwa_reduce_1:.ascii "归约"; kwa_reduce_1_end:
kwa_reduce_2:.ascii "歸約"; kwa_reduce_2_end:
kwa_sum_0:.ascii "sum"; kwa_sum_0_end:
kwa_sum_1:.ascii "求和"; kwa_sum_1_end:
kwa_sum_2:.ascii "總和"; kwa_sum_2_end:
kwa_iterate_0:.ascii "iterate"; kwa_iterate_0_end:
kwa_iterate_1:.ascii "迭代"; kwa_iterate_1_end:
kwa_limit_0:.ascii "limit"; kwa_limit_0_end:
kwa_limit_1:.ascii "上限"; kwa_limit_1_end:
kwa_state_0:.ascii "state"; kwa_state_0_end:
kwa_state_1:.ascii "状态"; kwa_state_1_end:
kwa_state_2:.ascii "狀態"; kwa_state_2_end:
kwa_while_0:.ascii "while"; kwa_while_0_end:
kwa_while_1:.ascii "当"; kwa_while_1_end:
kwa_while_2:.ascii "當"; kwa_while_2_end:
kwa_update_0:.ascii "update"; kwa_update_0_end:
kwa_update_1:.ascii "更新"; kwa_update_1_end:
kwa_result_0:.ascii "result"; kwa_result_0_end:
kwa_result_1:.ascii "结果"; kwa_result_1_end:
kwa_result_2:.ascii "結果"; kwa_result_2_end:
kwa_record_0:.ascii "record"; kwa_record_0_end:
kwa_record_1:.ascii "记录"; kwa_record_1_end:
kwa_record_2:.ascii "記錄"; kwa_record_2_end:
kwa_axis_0:.ascii "axis"; kwa_axis_0_end:
kwa_axis_1:.ascii "轴"; kwa_axis_1_end:
kwa_axis_2:.ascii "軸"; kwa_axis_2_end:
kwa_pure_0:.ascii "pure"; kwa_pure_0_end:
kwa_pure_1:.ascii "纯"; kwa_pure_1_end:
kwa_pure_2:.ascii "純"; kwa_pure_2_end:
kwa_generic_0:.ascii "generic"; kwa_generic_0_end:
kwa_generic_1:.ascii "泛型"; kwa_generic_1_end:
kwa_fn_0:.ascii "fn"; kwa_fn_0_end:
kwa_fn_1:.ascii "函数"; kwa_fn_1_end:
kwa_fn_2:.ascii "函數"; kwa_fn_2_end:
kwa_region_0:.ascii "region"; kwa_region_0_end:
kwa_region_1:.ascii "区域"; kwa_region_1_end:
kwa_region_2:.ascii "區域"; kwa_region_2_end:
kwa_effect_0:.ascii "effect"; kwa_effect_0_end:
kwa_effect_1:.ascii "效应"; kwa_effect_1_end:
kwa_effect_2:.ascii "效應"; kwa_effect_2_end:
kwa_parallel_0:.ascii "parallel"; kwa_parallel_0_end:
kwa_parallel_1:.ascii "并行"; kwa_parallel_1_end:
kwa_parallel_2:.ascii "並行"; kwa_parallel_2_end:
kwa_for_0:.ascii "for"; kwa_for_0_end:
kwa_for_1:.ascii "循环"; kwa_for_1_end:
kwa_for_2:.ascii "循環"; kwa_for_2_end:
kwa_if_0:.ascii "if"; kwa_if_0_end:
kwa_if_1:.ascii "如果"; kwa_if_1_end:
kwa_if_2:.ascii "若"; kwa_if_2_end:
kwa_else_0:.ascii "else"; kwa_else_0_end:
kwa_else_1:.ascii "否则"; kwa_else_1_end:
kwa_else_2:.ascii "否則"; kwa_else_2_end:
kwa_tolerance_0:.ascii "tolerance"; kwa_tolerance_0_end:
kwa_tolerance_1:.ascii "容差"; kwa_tolerance_1_end:
kwa_strict_0:.ascii "strict"; kwa_strict_0_end:
kwa_strict_1:.ascii "严格"; kwa_strict_1_end:
kwa_strict_2:.ascii "嚴格"; kwa_strict_2_end:
kwa_precision_propagation_0:.ascii "precision_propagation"; kwa_precision_propagation_0_end:
kwa_precision_propagation_1:.ascii "精度传播"; kwa_precision_propagation_1_end:
kwa_precision_propagation_2:.ascii "精度傳播"; kwa_precision_propagation_2_end:
kwa_field_0:.ascii "field"; kwa_field_0_end:
kwa_field_1:.ascii "场"; kwa_field_1_end:
kwa_field_2:.ascii "場"; kwa_field_2_end:
kwa_each_0:.ascii "each"; kwa_each_0_end:
kwa_each_1:.ascii "每个"; kwa_each_1_end:
kwa_each_2:.ascii "每個"; kwa_each_2_end:
kwa_in_0:.ascii "in"; kwa_in_0_end:
kwa_in_1:.ascii "属于"; kwa_in_1_end:
kwa_in_2:.ascii "屬於"; kwa_in_2_end:
kwa_output_0:.ascii "output"; kwa_output_0_end:
kwa_output_1:.ascii "输出"; kwa_output_1_end:
kwa_output_2:.ascii "輸出"; kwa_output_2_end:
kwa_publish_0:.ascii "publish"; kwa_publish_0_end:
kwa_publish_1:.ascii "发布"; kwa_publish_1_end:
kwa_publish_2:.ascii "發佈"; kwa_publish_2_end:
kwa_test_0:.ascii "test"; kwa_test_0_end:
kwa_test_1:.ascii "测试"; kwa_test_1_end:
kwa_test_2:.ascii "測試"; kwa_test_2_end:
kwa_true_0:.ascii "true"; kwa_true_0_end:
kwa_true_1:.ascii "真"; kwa_true_1_end:
kwa_false_0:.ascii "false"; kwa_false_0_end:
kwa_false_1:.ascii "假"; kwa_false_1_end:
kwa_cast_0:.ascii "cast"; kwa_cast_0_end:
kwa_cast_1:.ascii "转换"; kwa_cast_1_end:
kwa_cast_2:.ascii "轉換"; kwa_cast_2_end:
kwa_select_0:.ascii "select"; kwa_select_0_end:
kwa_select_1:.ascii "选择"; kwa_select_1_end:
kwa_select_2:.ascii "選擇"; kwa_select_2_end:
kwa_min_0:.ascii "min"; kwa_min_0_end:
kwa_min_1:.ascii "最小"; kwa_min_1_end:
kwa_max_0:.ascii "max"; kwa_max_0_end:
kwa_max_1:.ascii "最大"; kwa_max_1_end:
kwa_abs_0:.ascii "abs"; kwa_abs_0_end:
kwa_abs_1:.ascii "绝对值"; kwa_abs_1_end:
kwa_abs_2:.ascii "絕對值"; kwa_abs_2_end:
kwa_periodic_0:.ascii "periodic"; kwa_periodic_0_end:
kwa_periodic_1:.ascii "周期"; kwa_periodic_1_end:
kwa_periodic_2:.ascii "週期"; kwa_periodic_2_end:
kwa_dictionary_0:.ascii "dictionary"; kwa_dictionary_0_end:
kwa_dictionary_1:.ascii "字典"; kwa_dictionary_1_end:
kwa_dictionary_2:.ascii "辭典"; kwa_dictionary_2_end:
kwa_lookup_0:.ascii "lookup"; kwa_lookup_0_end:
kwa_lookup_1:.ascii "查找"; kwa_lookup_1_end:
kwa_lookup_2:.ascii "查詢"; kwa_lookup_2_end:
kwa_default_0:.ascii "default"; kwa_default_0_end:
kwa_default_1:.ascii "默认"; kwa_default_1_end:
kwa_default_2:.ascii "預設"; kwa_default_2_end:
kwa_nested_0:.ascii "nested"; kwa_nested_0_end:
kwa_nested_1:.ascii "嵌套"; kwa_nested_1_end:
kwa_nested_2:.ascii "巢狀"; kwa_nested_2_end:
kwa_nested_reduce_0:.ascii "nested_reduce"; kwa_nested_reduce_0_end:
kwa_nested_reduce_1:.ascii "嵌套归约"; kwa_nested_reduce_1_end:
kwa_nested_reduce_2:.ascii "巢狀歸約"; kwa_nested_reduce_2_end:
kwa_cascade_0:.ascii "cascade"; kwa_cascade_0_end:
kwa_cascade_1:.ascii "级联"; kwa_cascade_1_end:
kwa_cascade_2:.ascii "級聯"; kwa_cascade_2_end:
kwa_events_0:.ascii "events"; kwa_events_0_end:
kwa_events_1:.ascii "事件"; kwa_events_1_end:
kwa_goal_0:.ascii "goal"; kwa_goal_0_end:
kwa_goal_1:.ascii "目标"; kwa_goal_1_end:
kwa_goal_2:.ascii "目標"; kwa_goal_2_end:
kwa_work_0:.ascii "work"; kwa_work_0_end:
kwa_work_1:.ascii "工作"; kwa_work_1_end:
kwa_relation_0:.ascii "relation"; kwa_relation_0_end:
kwa_relation_1:.ascii "关系"; kwa_relation_1_end:
kwa_relation_2:.ascii "關係"; kwa_relation_2_end:
kwa_to_0:.ascii "to"; kwa_to_0_end:
kwa_to_1:.ascii "到"; kwa_to_1_end:
kwa_goal_result_0:.ascii "goal_result"; kwa_goal_result_0_end:
kwa_goal_result_1:.ascii "目标结果"; kwa_goal_result_1_end:
kwa_goal_result_2:.ascii "目標結果"; kwa_goal_result_2_end:
.p2align 3
s_kw_alias_table:
    .quad kwa_program_0; .long kwa_program_0_end-kwa_program_0; .long KID_PROGRAM
    .quad kwa_program_1; .long kwa_program_1_end-kwa_program_1; .long KID_PROGRAM
    .quad kwa_program_2; .long kwa_program_2_end-kwa_program_2; .long KID_PROGRAM
    .quad kwa_contract_0; .long kwa_contract_0_end-kwa_contract_0; .long KID_CONTRACT
    .quad kwa_contract_1; .long kwa_contract_1_end-kwa_contract_1; .long KID_CONTRACT
    .quad kwa_contract_2; .long kwa_contract_2_end-kwa_contract_2; .long KID_CONTRACT
    .quad kwa_input_0; .long kwa_input_0_end-kwa_input_0; .long KID_INPUT
    .quad kwa_input_1; .long kwa_input_1_end-kwa_input_1; .long KID_INPUT
    .quad kwa_input_2; .long kwa_input_2_end-kwa_input_2; .long KID_INPUT
    .quad kwa_range_0; .long kwa_range_0_end-kwa_range_0; .long KID_RANGE
    .quad kwa_range_1; .long kwa_range_1_end-kwa_range_1; .long KID_RANGE
    .quad kwa_range_2; .long kwa_range_2_end-kwa_range_2; .long KID_RANGE
    .quad kwa_let_0; .long kwa_let_0_end-kwa_let_0; .long KID_LET
    .quad kwa_let_1; .long kwa_let_1_end-kwa_let_1; .long KID_LET
    .quad kwa_let_2; .long kwa_let_2_end-kwa_let_2; .long KID_LET
    .quad kwa_let_3; .long kwa_let_3_end-kwa_let_3; .long KID_LET
    .quad kwa_tensor_0; .long kwa_tensor_0_end-kwa_tensor_0; .long KID_TENSOR
    .quad kwa_tensor_1; .long kwa_tensor_1_end-kwa_tensor_1; .long KID_TENSOR
    .quad kwa_tensor_2; .long kwa_tensor_2_end-kwa_tensor_2; .long KID_TENSOR
    .quad kwa_reduce_0; .long kwa_reduce_0_end-kwa_reduce_0; .long KID_REDUCE
    .quad kwa_reduce_1; .long kwa_reduce_1_end-kwa_reduce_1; .long KID_REDUCE
    .quad kwa_reduce_2; .long kwa_reduce_2_end-kwa_reduce_2; .long KID_REDUCE
    .quad kwa_sum_0; .long kwa_sum_0_end-kwa_sum_0; .long KID_SUM
    .quad kwa_sum_1; .long kwa_sum_1_end-kwa_sum_1; .long KID_SUM
    .quad kwa_sum_2; .long kwa_sum_2_end-kwa_sum_2; .long KID_SUM
    .quad kwa_iterate_0; .long kwa_iterate_0_end-kwa_iterate_0; .long KID_ITERATE
    .quad kwa_iterate_1; .long kwa_iterate_1_end-kwa_iterate_1; .long KID_ITERATE
    .quad kwa_limit_0; .long kwa_limit_0_end-kwa_limit_0; .long KID_LIMIT
    .quad kwa_limit_1; .long kwa_limit_1_end-kwa_limit_1; .long KID_LIMIT
    .quad kwa_state_0; .long kwa_state_0_end-kwa_state_0; .long KID_STATE
    .quad kwa_state_1; .long kwa_state_1_end-kwa_state_1; .long KID_STATE
    .quad kwa_state_2; .long kwa_state_2_end-kwa_state_2; .long KID_STATE
    .quad kwa_while_0; .long kwa_while_0_end-kwa_while_0; .long KID_WHILE
    .quad kwa_while_1; .long kwa_while_1_end-kwa_while_1; .long KID_WHILE
    .quad kwa_while_2; .long kwa_while_2_end-kwa_while_2; .long KID_WHILE
    .quad kwa_update_0; .long kwa_update_0_end-kwa_update_0; .long KID_UPDATE
    .quad kwa_update_1; .long kwa_update_1_end-kwa_update_1; .long KID_UPDATE
    .quad kwa_result_0; .long kwa_result_0_end-kwa_result_0; .long KID_RESULT
    .quad kwa_result_1; .long kwa_result_1_end-kwa_result_1; .long KID_RESULT
    .quad kwa_result_2; .long kwa_result_2_end-kwa_result_2; .long KID_RESULT
    .quad kwa_record_0; .long kwa_record_0_end-kwa_record_0; .long KID_RECORD
    .quad kwa_record_1; .long kwa_record_1_end-kwa_record_1; .long KID_RECORD
    .quad kwa_record_2; .long kwa_record_2_end-kwa_record_2; .long KID_RECORD
    .quad kwa_axis_0; .long kwa_axis_0_end-kwa_axis_0; .long KID_AXIS
    .quad kwa_axis_1; .long kwa_axis_1_end-kwa_axis_1; .long KID_AXIS
    .quad kwa_axis_2; .long kwa_axis_2_end-kwa_axis_2; .long KID_AXIS
    .quad kwa_pure_0; .long kwa_pure_0_end-kwa_pure_0; .long KID_PURE
    .quad kwa_pure_1; .long kwa_pure_1_end-kwa_pure_1; .long KID_PURE
    .quad kwa_pure_2; .long kwa_pure_2_end-kwa_pure_2; .long KID_PURE
    .quad kwa_generic_0; .long kwa_generic_0_end-kwa_generic_0; .long KID_GENERIC
    .quad kwa_generic_1; .long kwa_generic_1_end-kwa_generic_1; .long KID_GENERIC
    .quad kwa_fn_0; .long kwa_fn_0_end-kwa_fn_0; .long KID_FN
    .quad kwa_fn_1; .long kwa_fn_1_end-kwa_fn_1; .long KID_FN
    .quad kwa_fn_2; .long kwa_fn_2_end-kwa_fn_2; .long KID_FN
    .quad kwa_region_0; .long kwa_region_0_end-kwa_region_0; .long KID_REGION
    .quad kwa_region_1; .long kwa_region_1_end-kwa_region_1; .long KID_REGION
    .quad kwa_region_2; .long kwa_region_2_end-kwa_region_2; .long KID_REGION
    .quad kwa_effect_0; .long kwa_effect_0_end-kwa_effect_0; .long KID_EFFECT
    .quad kwa_effect_1; .long kwa_effect_1_end-kwa_effect_1; .long KID_EFFECT
    .quad kwa_effect_2; .long kwa_effect_2_end-kwa_effect_2; .long KID_EFFECT
    .quad kwa_parallel_0; .long kwa_parallel_0_end-kwa_parallel_0; .long KID_PARALLEL
    .quad kwa_parallel_1; .long kwa_parallel_1_end-kwa_parallel_1; .long KID_PARALLEL
    .quad kwa_parallel_2; .long kwa_parallel_2_end-kwa_parallel_2; .long KID_PARALLEL
    .quad kwa_for_0; .long kwa_for_0_end-kwa_for_0; .long KID_FOR
    .quad kwa_for_1; .long kwa_for_1_end-kwa_for_1; .long KID_FOR
    .quad kwa_for_2; .long kwa_for_2_end-kwa_for_2; .long KID_FOR
    .quad kwa_if_0; .long kwa_if_0_end-kwa_if_0; .long KID_IF
    .quad kwa_if_1; .long kwa_if_1_end-kwa_if_1; .long KID_IF
    .quad kwa_if_2; .long kwa_if_2_end-kwa_if_2; .long KID_IF
    .quad kwa_else_0; .long kwa_else_0_end-kwa_else_0; .long KID_ELSE
    .quad kwa_else_1; .long kwa_else_1_end-kwa_else_1; .long KID_ELSE
    .quad kwa_else_2; .long kwa_else_2_end-kwa_else_2; .long KID_ELSE
    .quad kwa_tolerance_0; .long kwa_tolerance_0_end-kwa_tolerance_0; .long KID_TOLERANCE
    .quad kwa_tolerance_1; .long kwa_tolerance_1_end-kwa_tolerance_1; .long KID_TOLERANCE
    .quad kwa_strict_0; .long kwa_strict_0_end-kwa_strict_0; .long KID_STRICT
    .quad kwa_strict_1; .long kwa_strict_1_end-kwa_strict_1; .long KID_STRICT
    .quad kwa_strict_2; .long kwa_strict_2_end-kwa_strict_2; .long KID_STRICT
    .quad kwa_precision_propagation_0; .long kwa_precision_propagation_0_end-kwa_precision_propagation_0; .long KID_PRECISION_PROPAGATION
    .quad kwa_precision_propagation_1; .long kwa_precision_propagation_1_end-kwa_precision_propagation_1; .long KID_PRECISION_PROPAGATION
    .quad kwa_precision_propagation_2; .long kwa_precision_propagation_2_end-kwa_precision_propagation_2; .long KID_PRECISION_PROPAGATION
    .quad kwa_field_0; .long kwa_field_0_end-kwa_field_0; .long KID_FIELD
    .quad kwa_field_1; .long kwa_field_1_end-kwa_field_1; .long KID_FIELD
    .quad kwa_field_2; .long kwa_field_2_end-kwa_field_2; .long KID_FIELD
    .quad kwa_each_0; .long kwa_each_0_end-kwa_each_0; .long KID_EACH
    .quad kwa_each_1; .long kwa_each_1_end-kwa_each_1; .long KID_EACH
    .quad kwa_each_2; .long kwa_each_2_end-kwa_each_2; .long KID_EACH
    .quad kwa_in_0; .long kwa_in_0_end-kwa_in_0; .long KID_IN
    .quad kwa_in_1; .long kwa_in_1_end-kwa_in_1; .long KID_IN
    .quad kwa_in_2; .long kwa_in_2_end-kwa_in_2; .long KID_IN
    .quad kwa_output_0; .long kwa_output_0_end-kwa_output_0; .long KID_OUTPUT
    .quad kwa_output_1; .long kwa_output_1_end-kwa_output_1; .long KID_OUTPUT
    .quad kwa_output_2; .long kwa_output_2_end-kwa_output_2; .long KID_OUTPUT
    .quad kwa_publish_0; .long kwa_publish_0_end-kwa_publish_0; .long KID_PUBLISH
    .quad kwa_publish_1; .long kwa_publish_1_end-kwa_publish_1; .long KID_PUBLISH
    .quad kwa_publish_2; .long kwa_publish_2_end-kwa_publish_2; .long KID_PUBLISH
    .quad kwa_test_0; .long kwa_test_0_end-kwa_test_0; .long KID_TEST
    .quad kwa_test_1; .long kwa_test_1_end-kwa_test_1; .long KID_TEST
    .quad kwa_test_2; .long kwa_test_2_end-kwa_test_2; .long KID_TEST
    .quad kwa_true_0; .long kwa_true_0_end-kwa_true_0; .long KID_TRUE
    .quad kwa_true_1; .long kwa_true_1_end-kwa_true_1; .long KID_TRUE
    .quad kwa_false_0; .long kwa_false_0_end-kwa_false_0; .long KID_FALSE
    .quad kwa_false_1; .long kwa_false_1_end-kwa_false_1; .long KID_FALSE
    .quad kwa_cast_0; .long kwa_cast_0_end-kwa_cast_0; .long KID_CAST
    .quad kwa_cast_1; .long kwa_cast_1_end-kwa_cast_1; .long KID_CAST
    .quad kwa_cast_2; .long kwa_cast_2_end-kwa_cast_2; .long KID_CAST
    .quad kwa_select_0; .long kwa_select_0_end-kwa_select_0; .long KID_SELECT
    .quad kwa_select_1; .long kwa_select_1_end-kwa_select_1; .long KID_SELECT
    .quad kwa_select_2; .long kwa_select_2_end-kwa_select_2; .long KID_SELECT
    .quad kwa_min_0; .long kwa_min_0_end-kwa_min_0; .long KID_MIN
    .quad kwa_min_1; .long kwa_min_1_end-kwa_min_1; .long KID_MIN
    .quad kwa_max_0; .long kwa_max_0_end-kwa_max_0; .long KID_MAX
    .quad kwa_max_1; .long kwa_max_1_end-kwa_max_1; .long KID_MAX
    .quad kwa_abs_0; .long kwa_abs_0_end-kwa_abs_0; .long KID_ABS
    .quad kwa_abs_1; .long kwa_abs_1_end-kwa_abs_1; .long KID_ABS
    .quad kwa_abs_2; .long kwa_abs_2_end-kwa_abs_2; .long KID_ABS
    .quad kwa_periodic_0; .long kwa_periodic_0_end-kwa_periodic_0; .long KID_PERIODIC
    .quad kwa_periodic_1; .long kwa_periodic_1_end-kwa_periodic_1; .long KID_PERIODIC
    .quad kwa_periodic_2; .long kwa_periodic_2_end-kwa_periodic_2; .long KID_PERIODIC
    .quad kwa_dictionary_0; .long kwa_dictionary_0_end-kwa_dictionary_0; .long KID_DICTIONARY
    .quad kwa_dictionary_1; .long kwa_dictionary_1_end-kwa_dictionary_1; .long KID_DICTIONARY
    .quad kwa_dictionary_2; .long kwa_dictionary_2_end-kwa_dictionary_2; .long KID_DICTIONARY
    .quad kwa_lookup_0; .long kwa_lookup_0_end-kwa_lookup_0; .long KID_LOOKUP
    .quad kwa_lookup_1; .long kwa_lookup_1_end-kwa_lookup_1; .long KID_LOOKUP
    .quad kwa_lookup_2; .long kwa_lookup_2_end-kwa_lookup_2; .long KID_LOOKUP
    .quad kwa_default_0; .long kwa_default_0_end-kwa_default_0; .long KID_DEFAULT
    .quad kwa_default_1; .long kwa_default_1_end-kwa_default_1; .long KID_DEFAULT
    .quad kwa_default_2; .long kwa_default_2_end-kwa_default_2; .long KID_DEFAULT
    .quad kwa_nested_0; .long kwa_nested_0_end-kwa_nested_0; .long KID_NESTED
    .quad kwa_nested_1; .long kwa_nested_1_end-kwa_nested_1; .long KID_NESTED
    .quad kwa_nested_2; .long kwa_nested_2_end-kwa_nested_2; .long KID_NESTED
    .quad kwa_nested_reduce_0; .long kwa_nested_reduce_0_end-kwa_nested_reduce_0; .long KID_NESTED_REDUCE
    .quad kwa_nested_reduce_1; .long kwa_nested_reduce_1_end-kwa_nested_reduce_1; .long KID_NESTED_REDUCE
    .quad kwa_nested_reduce_2; .long kwa_nested_reduce_2_end-kwa_nested_reduce_2; .long KID_NESTED_REDUCE
    .quad kwa_cascade_0; .long kwa_cascade_0_end-kwa_cascade_0; .long KID_CASCADE
    .quad kwa_cascade_1; .long kwa_cascade_1_end-kwa_cascade_1; .long KID_CASCADE
    .quad kwa_cascade_2; .long kwa_cascade_2_end-kwa_cascade_2; .long KID_CASCADE
    .quad kwa_events_0; .long kwa_events_0_end-kwa_events_0; .long KID_EVENTS
    .quad kwa_events_1; .long kwa_events_1_end-kwa_events_1; .long KID_EVENTS
    .quad kwa_goal_0; .long kwa_goal_0_end-kwa_goal_0; .long KID_GOAL
    .quad kwa_goal_1; .long kwa_goal_1_end-kwa_goal_1; .long KID_GOAL
    .quad kwa_goal_2; .long kwa_goal_2_end-kwa_goal_2; .long KID_GOAL
    .quad kwa_work_0; .long kwa_work_0_end-kwa_work_0; .long KID_WORK
    .quad kwa_work_1; .long kwa_work_1_end-kwa_work_1; .long KID_WORK
    .quad kwa_relation_0; .long kwa_relation_0_end-kwa_relation_0; .long KID_RELATION
    .quad kwa_relation_1; .long kwa_relation_1_end-kwa_relation_1; .long KID_RELATION
    .quad kwa_relation_2; .long kwa_relation_2_end-kwa_relation_2; .long KID_RELATION
    .quad kwa_to_0; .long kwa_to_0_end-kwa_to_0; .long KID_TO
    .quad kwa_to_1; .long kwa_to_1_end-kwa_to_1; .long KID_TO
    .quad kwa_goal_result_0; .long kwa_goal_result_0_end-kwa_goal_result_0; .long KID_GOAL_RESULT
    .quad kwa_goal_result_1; .long kwa_goal_result_1_end-kwa_goal_result_1; .long KID_GOAL_RESULT
    .quad kwa_goal_result_2; .long kwa_goal_result_2_end-kwa_goal_result_2; .long KID_GOAL_RESULT
    .quad 0; .long 0; .long 0
.p2align 3
s_builtin_repair_table:
    .quad kw_xor;     .long 3; .long OP_BIT_XOR; .long 2; .long 0
    .quad kw_bit_and; .long 7; .long OP_BIT_AND; .long 2; .long 0
    .quad kw_bit_or;  .long 6; .long OP_BIT_OR;  .long 2; .long 0
    .quad kw_bit_xor; .long 7; .long OP_BIT_XOR; .long 2; .long 0
    .quad kw_shl;     .long 3; .long OP_SHL;     .long 2; .long 0
    .quad kw_shr;     .long 3; .long OP_SHR;     .long 2; .long 0
    .quad 0; .long 0; .long 0; .long 0; .long 0
# Unified structural mathematics registry.  These entries own only parsing
# shape; numerical realization remains in the existing AST/Rank-N authorities.
# {ptr,len,parse_class}; aliases are intentionally just additional rows.
.p2align 3
s_semantic_parse_table:
    .quad kwa_sum_0; .long kwa_sum_0_end-kwa_sum_0,MSC_STATIC_SUM
    .quad kwa_sum_1; .long kwa_sum_1_end-kwa_sum_1,MSC_STATIC_SUM
    .quad kwa_sum_2; .long kwa_sum_2_end-kwa_sum_2,MSC_STATIC_SUM
    .quad kwa_contract_0; .long kwa_contract_0_end-kwa_contract_0,MSC_STATIC_SUM
    .quad kwa_contract_1; .long kwa_contract_1_end-kwa_contract_1,MSC_STATIC_SUM
    .quad kwa_contract_2; .long kwa_contract_2_end-kwa_contract_2,MSC_STATIC_SUM
    .quad kw_trace; .long 5,MSC_STATIC_SUM
    .quad kw_series; .long 6,MSC_STATIC_SUM
    .quad kw_dot; .long 3,MSC_STATIC_PRODUCT_SUM
    .quad kw_inner; .long 5,MSC_STATIC_PRODUCT_SUM
    .quad kw_matmul; .long 6,MSC_STATIC_PRODUCT_SUM
    .quad kw_gram; .long 4,MSC_STATIC_PRODUCT_SUM
    .quad kw_frobenius_inner; .long 15,MSC_STATIC_PRODUCT_SUM
    .quad kw_squared_norm; .long 12,MSC_STATIC_SQNORM
    .quad kw_norm2_squared; .long 13,MSC_STATIC_SQNORM
    .quad kw_norm; .long 4,MSC_STATIC_NORM
    .quad kw_norm2; .long 5,MSC_STATIC_NORM
    .quad kw_squared_distance; .long 16,MSC_STATIC_SQDIST
    .quad kw_distance; .long 8,MSC_STATIC_DIST
    .quad kw_mean; .long 4,MSC_STATIC_MEAN
    .quad kw_average; .long 7,MSC_STATIC_MEAN
    .quad kw_rms; .long 3,MSC_STATIC_RMS
    .quad kw_variance; .long 8,MSC_STATIC_VARIANCE
    .quad kw_derivative; .long 10,MSC_DERIVATIVE
    .quad kw_diff; .long 4,MSC_DERIVATIVE
    .quad kw_gradient; .long 8,MSC_DERIVATIVE
    .quad kw_jacobian; .long 8,MSC_DERIVATIVE
    .quad kw_second_derivative; .long 17,MSC_SECOND_DERIVATIVE
    .quad kw_hessian; .long 7,MSC_HESSIAN_COMPONENT
    .quad kw_laplacian; .long 9,MSC_LAPLACIAN2
    .quad kw_integral; .long 8,MSC_INTEGRAL
    .quad kw_quad; .long 4,MSC_INTEGRAL
    .quad kw_root; .long 4,MSC_ROOT
    .quad kw_newton; .long 6,MSC_ROOT
    .quad kw_pow; .long 3,MSC_POW
    .quad kw_matrix; .long 6,MSC_MATRIX
    .quad 0; .long 0,0

# Parse-class dispatch.  Registry growth does not alter the primary parser.
.p2align 3
s_semantic_parse_jump_table:
    .quad 0
    .quad .sppp_static_sum
    .quad .sppp_static_product_sum
    .quad .sppp_static_sqnorm
    .quad .sppp_static_norm
    .quad .sppp_static_sqdistance
    .quad .sppp_static_distance
    .quad .sppp_static_mean
    .quad .sppp_static_rms
    .quad .sppp_static_variance
    .quad .sppp_derivative
    .quad .sppp_second_derivative
    .quad .sppp_hessian_component
    .quad .sppp_laplacian2
    .quad .sppp_integral
    .quad .sppp_root
    .quad .sppp_pow
    .quad .sppp_matrix_relation

# Native math surface names. Table entries are {ptr,len,id,arity,pad} and
# disappear before canonical emission.
mb_sin:.ascii "sin"; mb_cos:.ascii "cos"; mb_tan:.ascii "tan"
mb_asin:.ascii "asin"; mb_acos:.ascii "acos"; mb_atan:.ascii "atan"
mb_exp:.ascii "exp"; mb_log:.ascii "log"; mb_exp2:.ascii "exp2"; mb_log2:.ascii "log2"; mb_log10:.ascii "log10"
mb_expm1:.ascii "expm1"; mb_log1p:.ascii "log1p"
mb_sinh:.ascii "sinh"; mb_cosh:.ascii "cosh"; mb_tanh:.ascii "tanh"
mb_asinh:.ascii "asinh"; mb_acosh:.ascii "acosh"; mb_atanh:.ascii "atanh"
mb_sec:.ascii "sec"; mb_csc:.ascii "csc"; mb_cot:.ascii "cot"
mb_sech:.ascii "sech"; mb_csch:.ascii "csch"; mb_coth:.ascii "coth"
mb_rsqrt:.ascii "rsqrt"; mb_recip:.ascii "reciprocal"; mb_square:.ascii "square"; mb_cube:.ascii "cube"; mb_hypot:.ascii "hypot"
mb_erf:.ascii "erf"; mb_erfc:.ascii "erfc"; mb_gamma:.ascii "gamma"; mb_lgamma:.ascii "lgamma"; mb_beta:.ascii "beta"
mb_lambertw:.ascii "lambertw"; mb_besselj0:.ascii "besselj0"; mb_besselj1:.ascii "besselj1"; mb_besseli0:.ascii "besseli0"
mb_zeta:.ascii "zeta"; mb_polylog:.ascii "polylog"; mb_elliptick:.ascii "elliptic_k"; mb_elliptice:.ascii "elliptic_e"; mb_sinc:.ascii "sinc"
mb_fma:.ascii "fma"; mb_clamp:.ascii "clamp"; mb_lerp:.ascii "lerp"
mb_factorial:.ascii "factorial"; mb_binomial:.ascii "binomial"; mb_rising:.ascii "rising_factorial"; mb_falling:.ascii "falling_factorial"
mb_digamma:.ascii "digamma"; mb_trigamma:.ascii "trigamma"; mb_erfinv:.ascii "erfinv"
mb_normalpdf:.ascii "normal_pdf"; mb_normalcdf:.ascii "normal_cdf"; mb_tetration:.ascii "tetration"
mb_det2:.ascii "det2"; mb_det3:.ascii "det3"; mb_besseli1:.ascii "besseli1"
mb_complex:.ascii "complex"; mb_real:.ascii "real"; mb_imag:.ascii "imag"; mb_conj:.ascii "conj"; mb_cabs:.ascii "cabs"
mb_cexp:.ascii "complex_exp"; mb_clog:.ascii "complex_log"; mb_csin:.ascii "complex_sin"; mb_ccos:.ascii "complex_cos"; mb_csqrt:.ascii "complex_sqrt"
mb_component:.ascii "component"; mb_root_valid:.ascii "root_valid"
mb_matrix2:.ascii "matrix2"; mb_matrix3:.ascii "matrix3"; mb_matrix4:.ascii "matrix4"; mb_mget:.ascii "mget"; mb_mtranspose:.ascii "transpose"; mb_mtrace:.ascii "matrix_trace"; mb_makespd:.ascii "make_spd"
mb_cholesky:.ascii "cholesky"; mb_orthogonalize:.ascii "orthogonalize"; mb_qrr:.ascii "qr_r"; mb_lul:.ascii "lu_l"; mb_luu:.ascii "lu_u"; mb_ldltl:.ascii "ldlt_l"; mb_ldltd:.ascii "ldlt_d"
mb_matrixexp:.ascii "matrix_exp"; mb_matrixlog:.ascii "matrix_log"; mb_matrixsqrt:.ascii "matrix_sqrt"; mb_eigvalues:.ascii "eig_values"; mb_eigvectors:.ascii "eig_vectors"; mb_svdvalues:.ascii "svd_values"; mb_svdu:.ascii "svd_u"; mb_svdv:.ascii "svd_v"; mb_matrixinv:.ascii "matrix_inverse"; mb_hadamard:.ascii "hadamard"
.p2align 3
s_math_builtin_table:
    .quad mb_sin; .long 3,MB_SIN,1,MSF_PURE|MSF_DIFFERENTIABLE|MSF_NATIVE_VALUEFACT
    .quad mb_cos; .long 3,MB_COS,1,MSF_PURE|MSF_DIFFERENTIABLE|MSF_NATIVE_VALUEFACT
    .quad mb_tan; .long 3,MB_TAN,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_asin; .long 4,MB_ASIN,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_acos; .long 4,MB_ACOS,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_atan; .long 4,MB_ATAN,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_exp; .long 3,MB_EXP,1,MSF_PURE|MSF_DIFFERENTIABLE|MSF_NATIVE_VALUEFACT
    .quad mb_log; .long 3,MB_LOG,1,MSF_PURE|MSF_DIFFERENTIABLE|MSF_NATIVE_VALUEFACT
    .quad mb_exp2; .long 4,MB_EXP2,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_log2; .long 4,MB_LOG2,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_log10; .long 5,MB_LOG10,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_expm1; .long 5,MB_EXPM1,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_log1p; .long 5,MB_LOG1P,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_sinh; .long 4,MB_SINH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_cosh; .long 4,MB_COSH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_tanh; .long 4,MB_TANH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_asinh; .long 5,MB_ASINH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_acosh; .long 5,MB_ACOSH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_atanh; .long 5,MB_ATANH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_sec; .long 3,MB_SEC,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_csc; .long 3,MB_CSC,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_cot; .long 3,MB_COT,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_sech; .long 4,MB_SECH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_csch; .long 4,MB_CSCH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_coth; .long 4,MB_COTH,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_rsqrt; .long 5,MB_RSQRT,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_recip; .long 10,MB_RECIP,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_square; .long 6,MB_SQUARE,1,MSF_PURE|MSF_DIFFERENTIABLE|MSF_NATIVE_VALUEFACT
    .quad mb_cube; .long 4,MB_CUBE,1,MSF_PURE|MSF_DIFFERENTIABLE
    .quad mb_hypot; .long 5,MB_HYPOT,2,MSF_PURE
    .quad mb_erf; .long 3,MB_ERF,1,MSF_PURE|MSF_SPECIAL
    .quad mb_erfc; .long 4,MB_ERFC,1,MSF_PURE|MSF_SPECIAL
    .quad mb_gamma; .long 5,MB_GAMMA,1,MSF_PURE|MSF_SPECIAL
    .quad mb_lgamma; .long 6,MB_LGAMMA,1,MSF_PURE|MSF_SPECIAL
    .quad mb_beta; .long 4,MB_BETA,2,MSF_PURE|MSF_SPECIAL
    .quad mb_lambertw; .long 8,MB_LAMBERTW,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_besselj0; .long 8,MB_BESSELJ0,1,MSF_PURE|MSF_SPECIAL
    .quad mb_besselj1; .long 8,MB_BESSELJ1,1,MSF_PURE|MSF_SPECIAL
    .quad mb_besseli0; .long 8,MB_BESSELI0,1,MSF_PURE|MSF_SPECIAL
    .quad mb_zeta; .long 4,MB_ZETA,1,MSF_PURE|MSF_STATIC_ARG0|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_polylog; .long 7,MB_POLYLOG,2,MSF_PURE|MSF_STATIC_ARG0|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_elliptick; .long 10,MB_ELLIPTICK,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_elliptice; .long 10,MB_ELLIPTICE,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_sinc; .long 4,MB_SINC,1,MSF_PURE
    .quad mb_fma; .long 3,MB_FMA,3,MSF_PURE
    .quad mb_clamp; .long 5,MB_CLAMP,3,MSF_PURE
    .quad mb_lerp; .long 4,MB_LERP,3,MSF_PURE
    .quad mb_factorial; .long 9,MB_FACTORIAL,1,MSF_PURE|MSF_SPECIAL
    .quad mb_binomial; .long 8,MB_BINOMIAL,2,MSF_PURE|MSF_SPECIAL
    .quad mb_rising; .long 16,MB_RISING,2,MSF_PURE|MSF_SPECIAL
    .quad mb_falling; .long 17,MB_FALLING,2,MSF_PURE|MSF_SPECIAL
    .quad mb_digamma; .long 7,MB_DIGAMMA,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_trigamma; .long 8,MB_TRIGAMMA,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_erfinv; .long 6,MB_ERFINV,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_normalpdf; .long 10,MB_NORMALPDF,1,MSF_PURE|MSF_SPECIAL
    .quad mb_normalcdf; .long 10,MB_NORMALCDF,1,MSF_PURE|MSF_SPECIAL
    .quad mb_tetration; .long 9,MB_TETRATION,2,MSF_PURE|MSF_STATIC_ARG1
    .quad mb_det2; .long 4,MB_DET2,4,MSF_PURE
    .quad mb_det3; .long 4,MB_DET3,9,MSF_PURE
    .quad mb_besseli1; .long 8,MB_BESSELI1,1,MSF_PURE|MSF_SPECIAL
    .quad mb_complex; .long 7,MB_COMPLEX,2,MSF_PURE
    .quad mb_real; .long 4,MB_REAL,1,MSF_PURE
    .quad mb_imag; .long 4,MB_IMAG,1,MSF_PURE
    .quad mb_conj; .long 4,MB_CONJ,1,MSF_PURE
    .quad mb_cabs; .long 4,MB_CABS,1,MSF_PURE
    .quad mb_cexp; .long 11,MB_CEXP,1,MSF_PURE|MSF_SPECIAL
    .quad mb_clog; .long 11,MB_CLOG,1,MSF_PURE|MSF_SPECIAL
    .quad mb_component; .long 9,MB_COMPONENT,2,MSF_PURE|MSF_STATIC_ARG1
    .quad mb_matrix2; .long 7,MB_MATRIX2,4,MSF_PURE
    .quad mb_matrix3; .long 7,MB_MATRIX3,9,MSF_PURE
    .quad mb_matrix4; .long 7,MB_MATRIX4,16,MSF_PURE
    .quad mb_mget; .long 4,MB_MGET,3,MSF_PURE
    .quad mb_mtranspose; .long 9,MB_MTRANSPOSE,1,MSF_PURE
    .quad mb_mtrace; .long 12,MB_MTRACE,1,MSF_PURE
    .quad mb_makespd; .long 8,MB_MAKE_SPD,2,MSF_PURE
    .quad mb_cholesky; .long 8,MB_CHOLESKY,1,MSF_PURE|MSF_SPECIAL
    .quad mb_orthogonalize; .long 13,MB_ORTHOGONALIZE,1,MSF_PURE|MSF_SPECIAL
    .quad mb_qrr; .long 4,MB_QR_R,1,MSF_PURE|MSF_SPECIAL
    .quad mb_lul; .long 4,MB_LU_L,1,MSF_PURE|MSF_SPECIAL
    .quad mb_luu; .long 4,MB_LU_U,1,MSF_PURE|MSF_SPECIAL
    .quad mb_ldltl; .long 6,MB_LDLT_L,1,MSF_PURE|MSF_SPECIAL
    .quad mb_ldltd; .long 6,MB_LDLT_D,1,MSF_PURE|MSF_SPECIAL
    .quad mb_matrixexp; .long 10,MB_MATRIX_EXP,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_matrixlog; .long 10,MB_MATRIX_LOG,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_matrixsqrt; .long 11,MB_MATRIX_SQRT,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_eigvalues; .long 10,MB_EIG_VALUES,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_eigvectors; .long 11,MB_EIG_VECTORS,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_svdvalues; .long 10,MB_SVD_VALUES,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_svdu; .long 5,MB_SVD_U,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_svdv; .long 5,MB_SVD_V,1,MSF_PURE|MSF_SPECIAL|MSF_OPTIONAL_ITER
    .quad mb_matrixinv; .long 14,MB_MATRIX_INV,1,MSF_PURE|MSF_SPECIAL
    .quad mb_hadamard; .long 8,MB_HADAMARD,2,MSF_PURE
    .quad mb_csin; .long 11,MB_CSIN,1,MSF_PURE|MSF_SPECIAL
    .quad mb_ccos; .long 11,MB_CCOS,1,MSF_PURE|MSF_SPECIAL
    .quad mb_csqrt; .long 12,MB_CSQRT,1,MSF_PURE|MSF_SPECIAL
    .quad mb_root_valid; .long 10,MB_ROOT_VALID,1,MSF_PURE
    .quad 0; .long 0,0,0,0

# Semantic Registry execution tables.  Registry growth is append-only and does
# not change parser, calculus or runtime control flow.
.p2align 3
s_math_expand_jump_table:
    .quad 0
    .quad .semb_sin
    .quad .semb_cos
    .quad .semb_tan
    .quad .semb_asin
    .quad .semb_acos
    .quad .semb_atan
    .quad .semb_exp
    .quad .semb_log
    .quad .semb_exp2
    .quad .semb_log2
    .quad .semb_log10
    .quad .semb_expm1
    .quad .semb_log1p
    .quad .semb_sinh
    .quad .semb_cosh
    .quad .semb_tanh
    .quad .semb_asinh
    .quad .semb_acosh
    .quad .semb_atanh
    .quad .semb_sec
    .quad .semb_csc
    .quad .semb_cot
    .quad .semb_sech
    .quad .semb_csch
    .quad .semb_coth
    .quad .semb_rsqrt
    .quad .semb_recip
    .quad .semb_square
    .quad .semb_cube
    .quad .semb_hypot
    .quad .semb_erf
    .quad .semb_erfc
    .quad .semb_gamma
    .quad .semb_lgamma
    .quad .semb_beta
    .quad .semb_lambertw
    .quad .semb_besselj0
    .quad .semb_besselj1
    .quad .semb_besseli0
    .quad .semb_zeta
    .quad .semb_polylog
    .quad .semb_elliptick
    .quad .semb_elliptice
    .quad .semb_sinc
    .quad .semb_fma
    .quad .semb_clamp
    .quad .semb_lerp
    .quad .semb_factorial
    .quad .semb_binomial
    .quad .semb_rising
    .quad .semb_falling
    .quad .semb_digamma
    .quad .semb_trigamma
    .quad .semb_erfinv
    .quad .semb_normalpdf
    .quad .semb_normalcdf
    .quad .semb_tetration
    .quad .semb_det2
    .quad .semb_det3
    .quad .semb_besseli1
    .quad .semb_complex
    .quad .semb_real
    .quad .semb_imag
    .quad .semb_conj
    .quad .semb_cabs
    .quad .semb_cexp
    .quad .semb_clog
    .quad .semb_component
    .quad .semb_matrix2
    .quad .semb_matrix3
    .quad .semb_matrix4
    .quad .semb_mget
    .quad .semb_mtranspose
    .quad .semb_mtrace
    .quad .semb_makespd
    .quad .semb_cholesky
    .quad .semb_orthogonalize
    .quad .semb_qrr
    .quad .semb_lul
    .quad .semb_luu
    .quad .semb_ldltl
    .quad .semb_ldltd
    .quad .semb_matrixexp
    .quad .semb_matrixlog
    .quad .semb_matrixsqrt
    .quad .semb_eigvalues
    .quad .semb_eigvectors
    .quad .semb_svdvalues
    .quad .semb_svdu
    .quad .semb_svdv
    .quad .semb_matrixinv
    .quad .semb_hadamard
    .quad .semb_csin
    .quad .semb_ccos
    .quad .semb_csqrt
    .quad .semb_root_valid

.p2align 3
s_math_diff_jump_table:
    .quad 0
    .quad .sadmo_sin
    .quad .sadmo_cos
    .quad .sadmo_tan
    .quad .sadmo_asin
    .quad .sadmo_acos
    .quad .sadmo_atan
    .quad .sadmo_exp
    .quad .sadmo_log
    .quad .sadmo_exp2
    .quad .sadmo_log2
    .quad .sadmo_log10
    .quad .sadmo_exp
    .quad .sadmo_log1p
    .quad .sadmo_sinh
    .quad .sadmo_cosh
    .quad .sadmo_tanh
    .quad .sadmo_asinh
    .quad .sadmo_acosh
    .quad .sadmo_atanh
    .quad .sadmo_sec
    .quad .sadmo_csc
    .quad .sadmo_cot
    .quad .sadmo_sech
    .quad .sadmo_csch
    .quad .sadmo_coth
    .quad .sadmo_rsqrt
    .quad .sadmo_recip
    .quad .sadmo_square
    .quad .sadmo_cube
    .quad 0
    .quad 0
.quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0

.p2align 3
# Horner high->low for erf: a5..a1
s_math_zeta_em_coeff:
    .quad 0x3fb5555555555555,0xbf56c16c16c16c17,0x3f01566abc011567
    .quad 0xbeabbd779334ef0b,0x3e566a8f2bf70ebe,0xbe022805d644267f
s_math_erf_coeff:
    .quad 0x3ff0fb844255a12d,0xbff7401c57014c39,0x3ff6be1c55bae157,0xbfd23531cc3c1469,0x3fd04f20c6ec5a7e
s_math_lanczos_coeff:
    .quad 0x3feffffffffff950,0x40852429b6c30b05,0xc093ac8e8ed4171b,0x40881a9661d3b4d8
    .quad 0xc06613ae51a32f5d,0x402903c27f8b9c81,0xbfc1bcb2992b2855,0x3ee4f0514e4e324f,0x3e8435508f3faeef
s_math_bessel_j0_coeff:
    .quad 0x3ad4197a7f5154bc,0xbb669ca9cf3b7f54,0x3bf5601885e63e5d,0xbc80b313289be0b9
    .quad 0x3d0522a43f65486a,0xbd8522a43f65486a,0x3e002e85c0898b71,0xbe723456789abcdf
    .quad 0x3edc71c71c71c71c,0xbf3c71c71c71c71c,0x3f90000000000000,0xbfd0000000000000,0x3ff0000000000000
s_math_bessel_j1_coeff:
    .quad 0x3a88bce58901a35e,0xbb1e2637bef9ff1a,0x3baf17697cf1cf13,0xbc3ab81ea75fcdf4
    .quad 0x3cc2c9758daf5cd0,0xbd4522a43f65486a,0x3dc27e4fb7789f5c,0xbe3845c8a0ce5129
    .quad 0x3ea6c16c16c16c17,0xbf0c71c71c71c71c,0x3f65555555555555,0xbfb0000000000000,0x3fe0000000000000
s_math_bessel_i0_coeff:
    .quad 0x3ad4197a7f5154bc,0x3b669ca9cf3b7f54,0x3bf5601885e63e5d,0x3c80b313289be0b9
    .quad 0x3d0522a43f65486a,0x3d8522a43f65486a,0x3e002e85c0898b71,0x3e723456789abcdf
    .quad 0x3edc71c71c71c71c,0x3f3c71c71c71c71c,0x3f90000000000000,0x3fd0000000000000,0x3ff0000000000000

.p2align 3
s_math_bessel_i1_coeff:
    .quad 0x3a88bce58901a35e,0x3b1e2637bef9ff1a,0x3baf17697cf1cf13,0x3c3ab81ea75fcdf4
    .quad 0x3cc2c9758daf5cd0,0x3d4522a43f65486a,0x3dc27e4fb7789f5c,0x3e3845c8a0ce5129
    .quad 0x3ea6c16c16c16c17,0x3f0c71c71c71c71c,0x3f65555555555555,0x3fb0000000000000,0x3fe0000000000000
.p2align 3
s_math_exp_coeff:
    .quad 0x3d2ae7f3e733b81f,0x3d6ae7f3e733b81f,0x3da93974a8c07c9d,0x3de6124613a86d09
    .quad 0x3e21eed8eff8d898,0x3e5ae64567f544e4,0x3e927e4fb7789f5c,0x3ec71de3a556c734
    .quad 0x3efa01a01a01a01a,0x3f2a01a01a01a01a,0x3f56c16c16c16c17,0x3f81111111111111
    .quad 0x3fa5555555555555,0x3fc5555555555555,0x3fe0000000000000,0x3ff0000000000000,0x3ff0000000000000
s_math_exp_pade_num:
    .quad 0x39ce3d36c1c38faa,0x3a58ce36eaf26bda,0x3ad4405ad5cfea0d,0x3b45d561ee842856
    .quad 0x3bb1660a0a115024,0x3c15bf8c8c95a42e,0x3c76168abec7fabe,0x3cd2a30510f8bb90
    .quad 0x3d2a7fcb3421aab1,0x3d80028ac4d45721,0x3dd0829f1afaf9da,0x3e1d149e0f85b242
    .quad 0x3e65cf768ba445b2,0x3eabaeb40001baeb,0x3eed699f4001d69a,0x3f29bc6b58019bc7
    .quad 0x3f62187b79e12188,0x3f93b13b13b13b14,0x3fbf2df2df2df2df,0x3fe0000000000000,0x3ff0000000000000
s_math_exp_pade_den:
    .quad 0x39ce3d36c1c38faa,0xba58ce36eaf26bda,0x3ad4405ad5cfea0d,0xbb45d561ee842856
    .quad 0x3bb1660a0a115024,0xbc15bf8c8c95a42e,0x3c76168abec7fabe,0xbcd2a30510f8bb90
    .quad 0x3d2a7fcb3421aab1,0xbd80028ac4d45721,0x3dd0829f1afaf9da,0xbe1d149e0f85b242
    .quad 0x3e65cf768ba445b2,0xbeabaeb40001baeb,0x3eed699f4001d69a,0xbf29bc6b58019bc7
    .quad 0x3f62187b79e12188,0xbf93b13b13b13b14,0x3fbf2df2df2df2df,0xbfe0000000000000,0x3ff0000000000000
s_math_log_coeff:
    .quad 0x3fb3b13b13b13b14,0x3fb745d1745d1746,0x3fbc71c71c71c71c,0x3fc2492492492492
    .quad 0x3fc999999999999a,0x3fd5555555555555,0x3ff0000000000000
s_math_atan13_coeff:
    .quad 0x3fa47ae147ae147b,0xbfa642c8590b2164,0x3fa8618618618618,0xbfaaf286bca1af28
    .quad 0x3fae1e1e1e1e1e1e,0xbfb1111111111111,0x3fb3b13b13b13b14,0xbfb745d1745d1746
    .quad 0x3fbc71c71c71c71c,0xbfc2492492492492,0x3fc999999999999a,0xbfd5555555555555
    .quad 0x3ff0000000000000

.align 8
s_gl8_nodes:
    .quad 0x3fc77ac94f3c7345,0x3fe0d129583284b4,0x3fe97e4ab249f41e,0x3feebab1cb0acc67
s_gl8_weights:
    .quad 0x3fd736360b199343,0x3fd413c50a255616,0x3fcc76fb531d2b97,0x3fb9ea1d04ca0377
s_math_sin_coeff:
    .quad 0xb8e434d2e783f5bc,0x398259f98b4358ad,0xba1d1ab1c2dccea3,0x3ab3f3ccdd165fa9
    .quad 0xbb4761b41316381a,0x3bd71b8ef6dcf572,0xbc62f49b46814157,0x3ce952c77030ad4a
    .quad 0xbd6ae7f3e733b81f,0x3de6124613a86d09,0xbe5ae64567f544e4,0x3ec71de3a556c734
    .quad 0xbf2a01a01a01a01a,0x3f81111111111111,0xbfc5555555555555,0x3ff0000000000000
s_math_cos_coeff:
    .quad 0xb933932c5047d60e,0x39d0a18a2635085d,0xba688e85fc6a4e5a,0x3aff2cf01972f578
    .quad 0xbb90ce396db7f853,0x3c1e542ba4020225,0xbca6827863b97d97,0x3d2ae7f3e733b81f
    .quad 0xbda93974a8c07c9d,0x3e21eed8eff8d898,0xbe927e4fb7789f5c,0x3efa01a01a01a01a
    .quad 0xbf56c16c16c16c17,0x3fa5555555555555,0xbfe0000000000000,0x3ff0000000000000
s_math_atan_coeff:
    .quad 0x3fae1e1e1e1e1e1e,0xbfb1111111111111,0x3fb3b13b13b13b14,0xbfb745d1745d1746
    .quad 0x3fbc71c71c71c71c,0xbfc2492492492492,0x3fc999999999999a,0xbfd5555555555555,0x3ff0000000000000
# high->low coefficients 1/41,1/39,...,1 for atanh(u)/u polynomial in u^2
s_math_atanh_coeff:
    .quad 0x3f98f9c18f9c18fa,0x3f9a41a41a41a41a,0x3f9bacf914c1bad0,0x3f9d41d41d41d41d
    .quad 0x3f9f07c1f07c1f08,0x3fa0842108421084,0x3fa1a7b9611a7b96,0x3fa2f684bda12f68
    .quad 0x3fa47ae147ae147b,0x3fa642c8590b2164,0x3fa8618618618618,0x3faaf286bca1af28
    .quad 0x3fae1e1e1e1e1e1e,0x3fb1111111111111,0x3fb3b13b13b13b14,0x3fb745d1745d1746
    .quad 0x3fbc71c71c71c71c,0x3fc2492492492492,0x3fc999999999999a,0x3fd5555555555555
    .quad 0x3ff0000000000000

# op strings
op_or:.ascii "or"; op_and:.ascii "and"; op_bit_or:.ascii "bit_or"; op_bit_xor:.ascii "bit_xor"; op_bit_and:.ascii "bit_and"
op_eq:.ascii "eq"; op_ne:.ascii "ne"; op_lt:.ascii "lt"; op_le:.ascii "le"; op_gt:.ascii "gt"; op_ge:.ascii "ge"
op_shl:.ascii "shl"; op_shr:.ascii "shr"; op_add:.ascii "add"; op_sub:.ascii "sub"; op_mul:.ascii "mul"; op_div:.ascii "div"; op_mod:.ascii "mod"
op_not:.ascii "not"; op_bit_not:.ascii "bit_not"; op_neg:.ascii "neg"; op_select:.ascii "select"; op_min:.ascii "min"; op_max:.ascii "max"; op_abs:.ascii "abs"; op_sqrt:.ascii "sqrt"; op_trunc:.ascii "trunc"; op_ushr:.ascii "ushr"
op_square:.ascii "square"; op_exp:.ascii "exp"; op_log:.ascii "log"; op_sin:.ascii "sin"; op_cos:.ascii "cos"; op_square_end:
# JSON fragments
js_lit_prefix:.asciz "{\"literal\":"
js_type_mid:.asciz ",\"type\":"
js_var_prefix:.asciz "{\"var\":"
js_axis_prefix:.asciz "{\"axis\":"
js_state_prefix:.asciz "{\"state\":"
js_op_prefix:.asciz "{\"op\":"
js_args_mid:.asciz ",\"args\":["
js_arr_obj_close:.asciz "]}"
js_cast_prefix:.asciz "{\"op\":\"cast\",\"to\":"
js_cast_mid:.asciz ",\"args\":["
js_load_prefix:.asciz "{\"load\":"
js_indices_mid:.asciz ",\"indices\":["
js_type_obj_base:.asciz "{\"base\":"
js_tol_mid_abs:.asciz ",\"mode\":\"tolerant\",\"absolute_error\":"
js_tol_mid_rel:.asciz ",\"relative_error\":"
js_axis_obj_name:.asciz "{\"name\":"
js_extent_mid:.asciz ",\"extent\":"
js_extent_shape_product:.asciz ",\"extent\":{\"var\":\"__shape_product\"}}]"
js_name_key:.asciz "\"name\":"
js_type_key:.asciz ",\"type\":"
js_min_key:.asciz ",\"min\":"
js_max_key:.asciz ",\"max\":"
js_binding_name:.asciz "{\"name\":"
js_compute_prefix:.asciz ",\"op\":\"compute\""
js_compute_mid:.asciz ",\"op\":\"compute\",\"expr\":"
js_output_label:.asciz "{\"label\":"
js_output_expr_mid:.asciz ",\"expr\":"
js_test_args:.asciz "{\"args\":["
js_expected_mid:.asciz "],\"expected\":{"
js_test_close:.asciz "}}"
js_iterate_mid:.asciz ",\"op\":\"iterate\",\"states\":["
js_state_obj_name:.asciz "{\"name\":"
js_init_key:.asciz ",\"init\":"
js_condition_mid:.asciz "],\"condition\":"
js_update_mid:.asciz ",\"update\":{"
js_result_mid:.asciz "},\"result\":"
js_maxiter_mid:.asciz ",\"max_iterations\":"
js_map_mid_axes:.asciz ",\"op\":\"map\",\"axes\":"
js_expr_key:.asciz ",\"expr\":"
js_reduce_mid_axes:.asciz ",\"op\":\"reduce\",\"kind\":\"sum\",\"axes\":"
js_acc_key:.asciz ",\"accumulator\":"
js_reduce_kind_mid:.asciz ",\"kind\":"
js_reduce_sum_expr:.asciz ",\"expr\":"
js_acc_tol_prefix:.asciz "{\"base\":\"f64\",\"mode\":\"tolerant\",\"absolute_error\":"
js_acc_tol_rel:.asciz ",\"relative_error\":"
js_root_format:.asciz "{\"format\":\"wheelchair.tensor/1\",\"program\":"
js_contract_prefix:.asciz ",\"contracts\":{\"deterministic\":"
js_overflow_mid:.asciz ",\"integer_overflow\":"
js_fp_mid:.asciz ",\"floating_point\":"
js_mixed_mid:.asciz ",\"mixed_precision\":"
cv_mixed_low:.asciz "\"lower_precision_dominates\""
cv_mixed_high:.asciz "\"higher_precision_dominates\""
js_inputs_prefix:.asciz "},\"inputs\":["
js_bindings_mid:.asciz "],\"bindings\":["
js_outputs_mid:.asciz "],\"outputs\":["
js_tests_mid:.asciz "],\"tests\":["
js_general_lane:.asciz ",\"_compiler_lane\":\"wheelchair.general/1\""
js_shapefact_prefix:.asciz ",\"shape_fact_n\":{\"axes\":["
js_shape_axis_name:.asciz "{\"name\":"
js_shape_extent_var:.asciz ",\"extent\":{\"var\":"
js_obj2_close:.asciz "}}"
js_shape_extent_static:.asciz ",\"extent\":{\"literal\":"
js_shape_extent_static_close:.asciz ",\"type\":\"u64\"}}"
js_shapefact_close:.asciz "]}"

.section .bss
.p2align 6
s_src:.skip 8
s_cur:.skip 8
s_end:.skip 8
s_mode:.skip 4
s_error:.skip 4
.p2align 3
surface_diag_active:.skip 4
surface_diag_repaired:.skip 4
surface_diag_repair_line:.skip 8
surface_diag_cheesed:.skip 4
.p2align 3
surface_diag_cheese_line:.skip 8
surface_diag_error_line:.skip 8
s_peek_repair_ptr:.skip 8
s_general_lane:.skip 4
s_deterministic:.skip 4
s_overflow_wrap:.skip 4
s_fp_tolerant:.skip 4
s_precision_propagation:.skip 4
s_tol_ptr:.skip 8
s_tol_len:.skip 8
s_program_ptr:.skip 8
s_program_len:.skip 8
s_input_count:.skip 4
s_binding_count:.skip 4
s_output_count:.skip 4
s_test_count:.skip 4
s_ast_count:.skip 4
s_axis_count:.skip 4
s_state_count:.skip 4
s_shape_rank:.skip 4
s_shape_static_bits:.skip 4
s_shape_static_product:.skip 8
s_shapefact_active:.skip 4
s_shape_runtime_extent_ptr:.skip 8
s_shape_runtime_extent_len:.skip 8
s_out_ptr:.skip 8
s_out_limit:.skip 8
s_inputs_end:.skip 8
s_bindings_end:.skip 8
.global surface_debug_stage
surface_debug_stage:.skip 4
s_outputs_end:.skip 8
s_tests_end:.skip 8
surface_json_length:.skip 8
# Semantic Registry argument vector. Compile-time only: one reusable operand
# vector replaces per-function parser branches and makes arbitrary arity native.
.p2align 3
s_math_call_argc:.skip 4
.p2align 3
s_math_call_args:.skip 8
s_axis_ptrs:.skip 8
s_axis_lens:.skip 8
s_state_ptrs:.skip 8
s_state_lens:.skip 8
s_shape_axis_ptrs:.skip 8
s_shape_axis_lens:.skip 8
s_shape_extent_ptrs:.skip 8
s_shape_extent_lens:.skip 8
s_shape_extent_kind:.skip 8
s_shape_extent_static:.skip 8
s_shape_low_bit:.skip 8
s_shape_stride_static:.skip 8
s_iter_limit_ast:.skip 8
s_iter_condition_ast:.skip 8
s_iter_result_ptr:.skip 8
s_iter_result_len:.skip 8
s_iter_update_count:.skip 4
s_iter_state_name_ptr:.skip 8
s_iter_state_name_len:.skip 8
s_iter_state_type_ptr:.skip 8
s_iter_state_type_len:.skip 8
s_iter_state_init_ast:.skip 8
s_iter_update_name_ptr:.skip 8
s_iter_update_name_len:.skip 8
s_iter_update_ast:.skip 8
s_record_field_count:.skip 4
s_function_count:.skip 4
s_pure_saved_axis_count:.skip 4
s_pure_param_start:.skip 4
s_pure_function_index:.skip 4
s_pure_return_type_ptr:.skip 8
s_pure_return_type_len:.skip 8
s_rec_function_index:.skip 4
s_rec_param_count:.skip 4
s_rec_param_offset:.skip 4
s_rec_true_has_recur:.skip 4
s_rec_false_has_recur:.skip 4
s_rec_base_true:.skip 4
s_rec_max_lag:.skip 8
s_rec_base_branch:.skip 8
s_rec_step_branch:.skip 8
s_function_param_total:.skip 4
s_subst_multi_active:.skip 4
s_subst_multi_offset:.skip 4
s_subst_multi_count:.skip 4
s_record_name_ptr:.skip 8
s_record_name_len:.skip 8
s_record_field_ptr:.skip 8
s_record_field_len:.skip 8
s_record_value_ast:.skip 8
s_function_name_ptr:.skip 8
s_function_name_len:.skip 8
s_function_param_offset:.skip 8
s_function_param_count:.skip 8
s_function_param_ptr:.skip 8
s_function_param_len:.skip 8
s_function_expr_ast:.skip 8
s_decl_count:.skip 4
s_struct_decl_count:.skip 4
s_struct_temp_count:.skip 4
s_type_capture_len:.skip 8
s_struct_decl_ptrs:.skip 8
s_struct_decl_lens:.skip 8
s_struct_decl_nodes:.skip 8
s_decl_ptrs:.skip 8
s_decl_lens:.skip 8
s_last_decl_index:.skip 4
s_decl_shape_rank:.skip 8
s_decl_shape_offset:.skip 8
s_decl_shape_stride_count:.skip 4
s_decl_shape_stride_pool:.skip 8
s_repair_split_end:.skip 8
s_repair_split_len:.skip 8
s_dictionary_count:.skip 4
s_dictionary_entry_count:.skip 4
s_dictionary_name_ptr:.skip 8
s_dictionary_name_len:.skip 8
s_dictionary_entry_dict:.skip 8
s_dictionary_entry_key:.skip 8
s_dictionary_entry_value:.skip 8
s_nested_count:.skip 4
s_nested_name_ptr:.skip 8
s_nested_name_len:.skip 8
s_nested_sum_ast:.skip 8
s_nested_item_count:.skip 8
s_nested_segment_count:.skip 8
s_nested_build_sum:.skip 8
s_nested_item_ast:.skip 8
s_cascade_goal_count:.skip 4
s_cascade_axis_enabled:.skip 4
s_cascade_axis_ptr:.skip 8
s_cascade_axis_len:.skip 8
s_cascade_axis_value:.skip 8
s_cascade_goal_name_ptr:.skip 8
s_cascade_goal_name_len:.skip 8
s_cascade_goal_work_ast:.skip 8
s_cascade_goal_expr_ast:.skip 8
s_cascade_edge_count:.skip 4
s_cascade_edge_from:.skip 8
s_cascade_edge_to:.skip 8
s_cascade_goal_done:.skip 8
s_cascade_goal_result:.skip 8
s_cascade_eval_goal_idx:.skip 4
s_cascade_eval_progressed:.skip 4
s_cascade_eval_work:.skip 8
s_cascade_eval_unit:.skip 8
s_cascade_eval_total:.skip 8
s_num_scratch:.skip 32
s_type_capture_buf:.skip 8
s_type_capture_cap:.skip 8
.p2align 4
s_struct_temp_cur:.skip 8
s_struct_temp_end:.skip 8
s_struct_temp_next_slab_bytes:.skip 8
s_const_pi_ready:.skip 4
s_const_e_ready:.skip 4
s_const_pi_value:.skip 8
s_const_e_value:.skip 8
.p2align 3
s_fact_cap:.skip 4
s_fact_arena:.skip 8
s_fact_arena_bytes:.skip 8
s_ast_cur:.skip 8
s_ast_end:.skip 8
s_ast_next_slab_bytes:.skip 8
s_inputs_buf:.skip 8
s_inputs_cap:.skip 8
s_bindings_buf:.skip 8
s_bindings_cap:.skip 8
s_outputs_buf:.skip 8
s_outputs_cap:.skip 8
s_tests_buf:.skip 8
s_tests_cap:.skip 8
surface_json_buffer:.skip 8
surface_json_cap:.skip 8
s_active_base_var:.skip 8
s_active_end_var:.skip 8
s_active_cap_var:.skip 8

# 1.2.18 native materialized-field WH/WHEX surface completion.
.include "compiler/field_surface_lowerer_x86_64.inc"
