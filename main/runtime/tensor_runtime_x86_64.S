.intel_syntax noprefix

# 1.3.14 one tensor runtime source, profile-selected entirely at assembly time.
.ifdef TENSOR_RUNTIME_NATIVE256
.equ TENSOR_RUNTIME_VECTOR_WIDTH,4
.else
.equ TENSOR_RUNTIME_VECTOR_WIDTH,8
.endif
# Wheelchair native topology runtime.
# 1.3.72 ownership-local execution: cold Physical Reality derives region grain;
# launch exposure forms a logarithmic frontier, while hot executions retain no
# causal-tree ownership.  No fixed evaluator arena, worker pool, ready queue or
# root O(P) spawn sweep exists.

.equ SYS_write, 1
.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ SYS_exit, 60
.equ SYS_exit_group, 231
.equ SYS_clone, 56
.equ SYS_wait4, 61
.equ SYS_sched_setaffinity, 203
.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ CLONE_PARENT, 0x8000
.equ PROT_RW, 3
.equ MAP_PRIVATE_ANON_STACK, 0x20022
.equ REGION_STACK_SIZE, 16384
# Reduction frontier is bounded by the qword chunk-index domain, not a fixed leaf geometry.
.equ REDUCE_LEVELS, 64

.section .text
.global _start
_start:
    # 1.3.87 AOT silicon placement. The compiler may bake one exact admitted
    # LLC-domain mask. This is a single inherited physical constraint, never an
    # idle-resource query, recipient choice, or runtime scheduler. Failure only
    # degrades locality; program semantics are unchanged.
    cmp dword ptr [rip+static_placement_required_patch],0
    je .static_placement_done
    mov esi,dword ptr [rip+static_placement_mask_bytes_patch]
    test esi,esi
    jz .static_placement_done
    mov eax,SYS_sched_setaffinity
    xor edi,edi
    lea rdx,[rip+static_placement_mask_patch]
    syscall
.static_placement_done:
    mov r15, rsp
    mov rax, [r15]
    cmp rax, 2
    jne .bad_args
    mov rdi, [r15+16]
    call parse_u64
    test edx, edx
    jnz .bad_args
    cmp rax, qword ptr [rip+shape_extent_min_patch]
    jb .bad_args
    cmp rax, qword ptr [rip+shape_extent_max_patch]
    ja .bad_args
    # ShapeFact-N static product is always one launch-time physical-domain fact.
    # Rank-1 is the exact degenerate case shape_static_product=1, so no separate
    # base/derived runtime family exists at the semantic level.
    mov rcx,qword ptr [rip+shape_static_product_patch]
    test rcx,rcx
    jz .bad_args
    mul rcx
    test rdx,rdx
    jnz .bad_args
    mov [rip+g_domain_size], rax
    call derive_launch_leaf_geometry
    test eax,eax
    jnz .bad_args
    mov rax,qword ptr [rip+g_domain_size]
    mov rcx,qword ptr [rip+chunk_elements_patch]
    test rcx,rcx
    jz .bad_args
    xor edx,edx
    div rcx
    test rdx,rdx
    jz .chunks_exact
    inc rax
.chunks_exact:
    test rax,rax
    jz .bad_args
    mov [rip+g_chunks], rax

    # 1.3.17 external-silicon execution: Wheelchair owns work, never silicon.
    # expansion never queries or accounts free CPU capacity.

    # 1.3.63 GroupFact execution closure. Generic tensor images realize a physical
    # group body and independent reduction carriers. These are the same GroupFact
    # factors consumed by code generation; runtime only validates them against
    # the emitted realization witness. No legacy unroll/carrier plan survives.
    mov ecx,dword ptr [rip+group_carrier_factor_patch]
    cmp ecx,1
    jb .bad_args
    cmp ecx,2
    ja .bad_args
    cmp ecx,dword ptr [rip+realized_group_carriers_patch]
    jne .bad_args
    mov edx,dword ptr [rip+group_body_factor_patch]
    cmp edx,1
    jb .bad_args
    cmp edx,dword ptr [rip+realized_group_body_patch]
    jne .bad_args

    # One virtual stack/result slice per non-root ownership region. Region-start
    # identity is mathematical, never a resource slot. Mapping is virtual; pages
    # become physical only when an outward execution actually exists.
    mov qword ptr [rip+g_region_arena],0
    mov qword ptr [rip+g_region_arena_size],0
    mov rax,[rip+g_chunks]
    cmp rax,1
    jbe .region_arena_ready
    dec rax
    shl rax,14                    # (chunks-1) * 16 KiB
    mov [rip+g_region_arena_size],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_RW
    mov r10d,MAP_PRIVATE_ANON_STACK
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .bad_args
    mov [rip+g_region_arena],rax
.region_arena_ready:

    # The launch frontier exposes independent ownership regions. Linux/CPU decide
    # where they run; once a leaf owns a region, launch geometry is dead.
    xor esi,esi                     # chunk lo
    mov rdx,[rip+g_chunks]          # chunk hi
    mov edi,1                       # invocation root owns lifecycle cleanup
    call run_region_frontier
.region_frontier_done:
    movq r12,xmm0
    mov rdi,[rip+g_region_arena]
    test rdi,rdi
    jz .region_arena_released
    mov eax,SYS_munmap
    mov rsi,[rip+g_region_arena_size]
    syscall
.region_arena_released:
    movq xmm0,r12
    movq rax,xmm0
    call print_checksum
    xor edi,edi
    mov eax,SYS_exit_group
    syscall
    hlt

# Cold launch-time Physical Reality leaf derivation.
# AOT patches describe one indivisible structural quantum: elements + work ticks.
# The launch knows N. External execution admission is an exact upper bound, while
# outward lifecycle cost decides whether exposing each additional region repays
# its own physical materialization. No power-of-two executor geometry survives:
# K is the largest profitable integer width not exceeding admitted capacity or
# available structural quanta.
derive_launch_leaf_geometry:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,qword ptr [rip+chunk_elements_patch]
    mov r13,qword ptr [rip+chunk_work_ticks_patch]
    test r12,r12
    jz .dllg_fail
    test r13,r13
    jz .dllg_fail

    # total_quanta = ceil(N / quantum_elements)
    mov rax,qword ptr [rip+g_domain_size]
    xor edx,edx
    div r12
    mov r14,rax
    test rdx,rdx
    jz .dllg_total_ready
    inc r14
.dllg_total_ready:
    test r14,r14
    jz .dllg_fail

    # K starts at exact external execution admission, clipped only by real work.
    mov r15d,dword ptr [rip+execution_admission_patch]
    test r15d,r15d
    jnz .dllg_have_admission
    mov r15d,1
.dllg_have_admission:
    cmp r15,r14
    jbe .dllg_profit_bound
    mov r15,r14

.dllg_profit_bound:
    cmp r15,1
    jbe .dllg_leaf_quanta

    # Minimum quanta per outward region required for strict payback:
    #   leaf_quanta * work_ticks > outward_lifecycle_ticks
    # min_leaf = floor(H/work)+1.
    mov rax,qword ptr [rip+outward_materialization_ticks_patch]
    xor edx,edx
    div r13
    inc rax
    mov rcx,rax
    cmp rcx,1
    jbe .dllg_leaf_quanta
    cmp r14,rcx
    jae .dllg_max_profitable
    mov r15,1
    jmp .dllg_leaf_quanta

.dllg_max_profitable:
    # ceil(Q/K) >= min_leaf  <=>  K <= floor((Q-1)/(min_leaf-1)).
    mov rax,r14
    dec rax
    mov rbx,rcx
    dec rbx
    xor edx,edx
    div rbx
    test rax,rax
    jnz .dllg_cap_profit
    mov rax,1
.dllg_cap_profit:
    cmp r15,rax
    jbe .dllg_leaf_quanta
    mov r15,rax

.dllg_leaf_quanta:
    # leaf_quanta = ceil(total_quanta / K)
    mov rax,r14
    xor edx,edx
    div r15
    mov rbx,rax
    test rdx,rdx
    jz .dllg_accept
    inc rbx

.dllg_accept:
    mov rax,rbx
    mul r12
    test rdx,rdx
    jnz .dllg_fail
    test rax,rax
    jz .dllg_fail
    mov qword ptr [rip+chunk_elements_patch],rax
    mov rax,rbx
    mul r13
    test rdx,rdx
    jz .dllg_store_work
    mov rax,0x7fffffffffffffff
.dllg_store_work:
    mov qword ptr [rip+chunk_work_ticks_patch],rax
    xor eax,eax
    jmp .dllg_done
.dllg_fail:
    mov eax,1
.dllg_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.bad_args:
    mov edi,2
    mov eax,SYS_exit_group
    syscall
    hlt

# -----------------------------------------------------------------------------
# Wheelchair 1.3.72 Ownership-Local Execution Aging
# -----------------------------------------------------------------------------
# Cold Physical Reality already collapsed target width and outward lifecycle
# price into chunk_elements_patch.  Runtime therefore exposes ownership regions
# once and never carries a causal split/join tree through the hot computation.
# Descendants use CLONE_PARENT so all outward executions are lifecycle children
# of the invocation root; leaves know only their own region and result slot.
#
# run_region_frontier(rsi=chunk_lo,rdx=chunk_hi,edi=root_flag) -> xmm0 f64
run_region_frontier:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,64
    mov r13,rsi
    mov r14,rdx
    mov r12d,edi

.rrf_descend:
    mov rax,r14
    sub rax,r13
    cmp rax,1
    jbe .rrf_leaf

    mov r15,rax
    bsr rcx,r15
    mov r8,1
    shl r8,cl
    cmp r8,r15
    jne .rrf_split_ready
    shr r8,1
.rrf_split_ready:
    test r8,r8
    jz .bad_args
    lea rbx,[r13+r8]

    mov rax,rbx
    dec rax
    shl rax,14
    mov r15,qword ptr [rip+g_region_arena]
    test r15,r15
    jz .bad_args
    add r15,rax
    mov qword ptr [r15],0

    lea rsi,[r15+REGION_STACK_SIZE-16]
    mov eax,SYS_clone
    mov edi,CLONE_VM_FILES_FS_SIGCHLD
    test r12d,r12d
    jnz .rrf_clone_flags_ready
    or edi,CLONE_PARENT
.rrf_clone_flags_ready:
    xor edx,edx
    xor r10d,r10d
    xor r8d,r8d
    syscall
    test rax,rax
    js .rrf_refused_right
    jz .rrf_child

    mov r14,rbx
    jmp .rrf_descend

.rrf_child:
    xor r12d,r12d
    mov r13,rbx
    jmp .rrf_descend

.rrf_refused_right:
    mov r15,rbx
.rrf_refused_loop:
    cmp r15,r14
    jae .rrf_refused_done
    mov rsi,r15
    lea rdx,[r15+1]
    call worker_range
    mov rax,r15
    dec rax
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    movsd qword ptr [rax],xmm0
    inc r15
    jmp .rrf_refused_loop
.rrf_refused_done:
    mov r14,rbx
    jmp .rrf_descend

.rrf_leaf:
    mov rsi,r13
    mov rdx,r14
    call worker_range
    test r12d,r12d
    jnz .rrf_root_leaf

    mov rax,r13
    dec rax
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    movsd qword ptr [rax],xmm0
    xor edi,edi
    mov eax,SYS_exit
    syscall
    hlt

.rrf_root_leaf:
    movsd qword ptr [rsp],xmm0
    # Every non-root execution is a direct child of the invocation root.
    # Reap until Linux reports that no outward context remains.
.rrf_reap:
    mov dword ptr [rsp+8],0
    mov eax,SYS_wait4
    mov rdi,-1
    lea rsi,[rsp+8]
    xor edx,edx
    xor r10d,r10d
    syscall
    cmp rax,-10
    je .rrf_reduce
    cmp rax,-4
    je .rrf_reap
    test rax,rax
    js .bad_args
    cmp dword ptr [rsp+8],0
    jne .bad_args
    jmp .rrf_reap

.rrf_reduce:
    movsd xmm0,qword ptr [rsp]
    call reduce_region_results

    add rsp,64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# reduce_region_results(xmm0=root-region result) -> xmm0 f64
reduce_region_results:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,REDUCE_LEVELS*8+16
    movsd qword ptr [rsp+REDUCE_LEVELS*8],xmm0
    xor r15d,r15d
    xor r13d,r13d
.rrr_next:
    cmp r13,qword ptr [rip+g_chunks]
    jae .rrr_finish
    test r13,r13
    jnz .rrr_load_slot
    movsd xmm0,qword ptr [rsp+REDUCE_LEVELS*8]
    jmp .rrr_carry_start
.rrr_load_slot:
    mov rax,r13
    dec rax
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    movsd xmm0,qword ptr [rax]
.rrr_carry_start:
    xor ecx,ecx
.rrr_carry:
    bt r15,rcx
    jnc .rrr_store
    movsd xmm1,qword ptr [rsp+rcx*8]
    addsd xmm1,xmm0
    movapd xmm0,xmm1
    btr r15,rcx
    inc ecx
    cmp ecx,REDUCE_LEVELS
    jb .rrr_carry
    jmp .bad_args
.rrr_store:
    movsd qword ptr [rsp+rcx*8],xmm0
    bts r15,rcx
    inc r13
    jmp .rrr_next
.rrr_finish:
    xor ecx,ecx
    xor edx,edx
    pxor xmm0,xmm0
.rrr_finish_loop:
    cmp ecx,REDUCE_LEVELS
    jae .rrr_done
    bt r15,rcx
    jnc .rrr_finish_next
    test edx,edx
    jnz .rrr_merge
    movsd xmm0,qword ptr [rsp+rcx*8]
    mov edx,1
    jmp .rrr_finish_next
.rrr_merge:
    movsd xmm1,qword ptr [rsp+rcx*8]
    addsd xmm1,xmm0
    movapd xmm0,xmm1
.rrr_finish_next:
    inc ecx
    jmp .rrr_finish_loop
.rrr_done:
    add rsp,REDUCE_LEVELS*8+16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# worker_range(rsi=begin_chunk, rdx=end_chunk) -> xmm0
# Used by the 1.3.10 causal-work topology. Every supplied range is a true
# canonical reduction subtree; no executor-derived partition exists.
worker_range:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,96
    mov r13,rsi
    mov r14,rdx

    cmp dword ptr [rip+vector_width_patch],TENSOR_RUNTIME_VECTOR_WIDTH
    jne .w_range_no_vec_init
    call eval_vec_init
.w_range_no_vec_init:

.w_range_ready:
    xor r15d,r15d                   # occupied reduction levels

.w_chunk_loop:
    cmp r13,r14
    jae .w_reduce_finish
    mov rdi,[rip+g_domain_size]
    mov rsi,r13
    call eval_chunk                 # xmm0 = new rightmost leaf

    xor ecx,ecx
.w_carry:
    bt r15,rcx
    jnc .w_carry_store
    movsd xmm1,qword ptr [rsp+rcx*8]
    addsd xmm1,xmm0                 # older left block + newer right block
    movapd xmm0,xmm1
    btr r15,rcx
    inc ecx
    cmp ecx,REDUCE_LEVELS
    jb .w_carry
    jmp .bad_args
.w_carry_store:
    movsd qword ptr [rsp+rcx*8],xmm0
    bts r15,rcx
    inc r13
    jmp .w_chunk_loop

.w_reduce_finish:
    # Remaining frontier blocks are ordered from latest/smallest at low levels
    # to earliest/largest at high levels.  Fold low->high as left+right, exactly
    # reproducing the left-to-right pairwise reduction tree for any leaf count.
    xor ecx,ecx
    xor edx,edx                     # have accumulator
    pxor xmm0,xmm0
.w_finish_levels:
    cmp ecx,REDUCE_LEVELS
    jae .w_finish_done
    bt r15,rcx
    jnc .w_finish_next
    test edx,edx
    jnz .w_finish_merge
    movsd xmm0,qword ptr [rsp+rcx*8]
    mov edx,1
    jmp .w_finish_next
.w_finish_merge:
    movsd xmm1,qword ptr [rsp+rcx*8]
    addsd xmm1,xmm0
    movapd xmm0,xmm1
.w_finish_next:
    inc ecx
    jmp .w_finish_levels

.w_finish_done:
    cmp dword ptr [rip+vector_width_patch],TENSOR_RUNTIME_VECTOR_WIDTH
    jne .w_no_vec_exit
    vzeroupper
.w_no_vec_exit:
    add rsp,96
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# eval_chunk(rdi=physical_domain_size, rsi=token) -> xmm0
#
# True-parallel fused episode ABI: runtime enters the generated AVX-512 kernel
# exactly once per chunk.  The generated kernel owns every eight-lane step, the
# masked tail, cross-vector axis recurrence and the local four-carrier reduction.
# No per-vector call boundary and no scalar boundary/tail path exist.
eval_chunk:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,64
    mov r12,rdi                    # physical domain size
    mov rax,rsi                    # canonical leaf token
    mul qword ptr [rip+chunk_elements_patch]
    test rdx,rdx
    jnz .bad_args
    mov r13,rax                    # start
    mov r14,qword ptr [rip+chunk_elements_patch]
    add r14,r13
    jc .bad_args
    cmp r14,r12
    cmova r14,r12                  # end
    cmp dword ptr [rip+vector_width_patch],TENSOR_RUNTIME_VECTOR_WIDTH
    je .ec_fused

    # Independent tensor semantics may not be serialized by the backend.
    mov eax,SYS_exit
    mov edi,125
    syscall
    ud2

.ec_fused:
    # Dynamic exact-mod invariants are episode constants.  Build them once here
    # and keep ZMM14/ZMM15 resident for the complete generated chunk loop.
    vxorpd xmm14,xmm14,xmm14
    vcvtsi2sd xmm14,xmm14,r12
    mov rax,0x3ff0000000000000
    vmovq xmm15,rax
    vdivsd xmm15,xmm15,xmm14
.ifdef TENSOR_RUNTIME_NATIVE256
    vbroadcastsd ymm14,xmm14
    vbroadcastsd ymm15,xmm15
.else
    vbroadcastsd zmm14,xmm14
    vbroadcastsd zmm15,xmm15
.endif

    mov rdi,r12
    mov rsi,r13
    mov rdx,r14
    call eval_vec4                 # one call for the entire chunk episode

    add rsp,64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Direct AOT jump stubs. topologyc patches each rel32 displacement to the exact
# code appended in the generated RX segment.  No pointer lookup or interpreter.
.p2align 4
.global eval_slot
eval_slot:
    .byte 0xE9
.global eval_slot_disp_patch
eval_slot_disp_patch: .long 0
.global eval_slot_end
eval_slot_end:

.p2align 4
.global eval_vec4
eval_vec4:
    .byte 0xE9
.global eval_vec4_disp_patch
eval_vec4_disp_patch: .long 0
.global eval_vec4_end
eval_vec4_end:

.p2align 4
.global eval_vec_init
eval_vec_init:
    .byte 0xE9
.global eval_vec_init_disp_patch
eval_vec_init_disp_patch: .long 0
.global eval_vec_init_end
eval_vec_init_end:

parse_u64:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
.pu_loop:
    movzx r8d,byte ptr [rdi]
    test r8b,r8b
    jz .pu_done
    cmp r8b,'0'
    jb .pu_bad
    cmp r8b,'9'
    ja .pu_bad
    sub r8d,'0'
    imul rax,rax,10
    add rax,r8
    inc rdi
    inc ecx
    jmp .pu_loop
.pu_done:
    test ecx,ecx
    jz .pu_bad
    xor edx,edx
    ret
.pu_bad:
    mov edx,1
    ret

# rax=bits, writes checksum line
print_checksum:
    lea rdi,[rip+checksum_line+16]
    mov ecx,16
.hex_loop:
    mov rdx,rax
    shr rdx,60
    and edx,15
    cmp edx,9
    jbe .digit
    add edx,'a'-10
    jmp .store
.digit:
    add edx,'0'
.store:
    mov byte ptr [rdi],dl
    inc rdi
    shl rax,4
    dec ecx
    jnz .hex_loop
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+checksum_line]
    mov edx,33
    syscall
    ret

.section .data
.p2align 3
.global execution_admission_patch
execution_admission_patch: .long 1
.global static_placement_required_patch
static_placement_required_patch: .long 0
.global static_placement_mask_bytes_patch
static_placement_mask_bytes_patch: .long 0
.p2align 6
.global static_placement_mask_patch
static_placement_mask_patch: .zero 128
.global outward_materialization_ticks_patch
outward_materialization_ticks_patch: .quad 0x7fffffffffffffff
.global chunk_work_ticks_patch
chunk_work_ticks_patch: .quad 1
.global chunk_elements_patch
chunk_elements_patch: .quad 1
.global vector_width_patch
vector_width_patch: .long 1
.global group_carrier_factor_patch
group_carrier_factor_patch: .long 1
.global group_body_factor_patch
group_body_factor_patch: .long 1
.global realized_group_carriers_patch
realized_group_carriers_patch: .long 1
.global realized_group_body_patch
realized_group_body_patch: .long 1
.global shape_extent_min_patch
shape_extent_min_patch: .quad 4
.global shape_extent_max_patch
shape_extent_max_patch: .quad 100000000
.global shape_static_product_patch
shape_static_product_patch: .quad 1
checksum_line: .ascii "checksum_bits=0x0000000000000000\n"

.section .bss
.p2align 3
g_domain_size: .skip 8
g_chunks: .skip 8
.p2align 3
g_region_arena: .skip 8
g_region_arena_size: .skip 8
