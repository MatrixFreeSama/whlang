.intel_syntax noprefix
.include "runtime/execution_admission_refresh_x86_64.inc"

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
.equ MAP_PRIVATE_ANON, 0x22
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
    # AOT locality may narrow, but never expand, the external invocation domain.
    CONSTRAIN_STATIC_PLACEMENT_WITHIN_INVOCATION static_placement_required_patch, static_placement_mask_bytes_patch, static_placement_mask_patch
    REFRESH_EXECUTION_ADMISSION execution_admission_patch
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
    cmp qword ptr [rip+g_chunks],0
    je .bad_args
    call discover_support
    test eax,eax
    jnz .bad_args
    call reprice_support_ownership
    test eax,eax
    jnz .bad_args
    # An empty proven support is the reduction identity itself. Do not allocate
    # execution ownership for a Physical DAG with no value-producing leaf.
    cmp qword ptr [rip+g_support_active_chunks],0
    jne .support_nonempty
    pxor xmm0,xmm0
    movq rax,xmm0
    call print_checksum
    xor edi,edi
    mov eax,SYS_exit_group
    syscall
    hlt
.support_nonempty:

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

    # One virtual descriptor/stack/result slice per ownership region.  The
    # invocation root owns region zero; outward regions use the same slices as
    # execution stacks.  Mathematical chunk identity and execution identity are
    # deliberately separate facts.
    mov qword ptr [rip+g_region_arena],0
    mov qword ptr [rip+g_region_arena_size],0
    mov rax,[rip+g_chunks]
    shl rax,14                    # regions * 16 KiB
    test rax,rax
    jz .bad_args
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

    call build_region_descriptors
    test eax,eax
    jnz .bad_args

    # The launch frontier exposes independent ownership regions. Linux/CPU decide
    # where they run; once a leaf owns a region, launch geometry is dead.  Strict
    # arithmetic subtree geometry lives only in the descriptors and final
    # mathematical reduction, never in this launch frontier.
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
    mov r12,qword ptr [rip+chunk_elements_patch]   # canonical structural quantum
    mov r13,qword ptr [rip+chunk_work_ticks_patch]
    test r12,r12
    jz .dllg_fail
    test r13,r13
    jz .dllg_fail

    # Canonical mathematical leaf count is derived only from N and the AOT
    # structural quantum.  Execution admission may never rewrite this fact.
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
    mov qword ptr [rip+g_canonical_chunks],r14

    # K is an ownership multiplicity, clipped by real canonical work and by the
    # same Physical Reality lifecycle payback.  It does not manufacture leaves.
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
    jbe .dllg_accept_k

    # Minimum canonical quanta whose work strictly repays one outward lifetime.
    mov rax,qword ptr [rip+outward_materialization_ticks_patch]
    xor edx,edx
    div r13
    inc rax
    mov rcx,rax
    cmp rcx,1
    jbe .dllg_accept_k
    cmp r14,rcx
    jae .dllg_max_profitable
    mov r15,1
    jmp .dllg_accept_k

.dllg_max_profitable:
    # Same no-threshold algebra as before: enough canonical work must remain per
    # exposed ownership region to repay materialization.
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
    jbe .dllg_accept_k
    mov r15,rax

.dllg_accept_k:
    test r15,r15
    jz .dllg_fail
    cmp dword ptr [rip+reduction_tolerant_patch],0
    je .dllg_strict_k

    # Tolerance explicitly permits cross-region condensation. Preserve the old
    # useful property without letting it leak into Strict: choose one condensed
    # canonical leaf per profitable ownership region, independent of any binary
    # launch geometry. This removes q=1 wrapper traffic only where the numerical
    # contract already permits reassociation.
    mov rax,r14
    xor edx,edx
    div r15
    mov rbx,rax
    test rdx,rdx
    jz .dllg_tol_leaf_ready
    inc rbx
.dllg_tol_leaf_ready:
    test rbx,rbx
    jz .dllg_fail

    mov rax,r12
    mul rbx
    test rdx,rdx
    jnz .dllg_fail
    mov qword ptr [rip+chunk_elements_patch],rax

    mov rax,r13
    mul rbx
    test rdx,rdx
    jz .dllg_tol_work_ready
    mov rax,0x7fffffffffffffff
.dllg_tol_work_ready:
    mov qword ptr [rip+chunk_work_ticks_patch],rax

    # Q_tol = ceil(Q_structural / leaf_quanta), never greater than admission K.
    mov rax,r14
    xor edx,edx
    div rbx
    mov r15,rax
    test rdx,rdx
    jz .dllg_tol_q_ready
    inc r15
.dllg_tol_q_ready:
    test r15,r15
    jz .dllg_fail
    mov qword ptr [rip+g_canonical_chunks],r15
    mov qword ptr [rip+g_chunks],r15
    xor eax,eax
    jmp .dllg_done

.dllg_strict_k:
    mov qword ptr [rip+g_chunks],r15               # ownership-region count only
    xor eax,eax
    jmp .dllg_done
.dllg_fail:
    mov qword ptr [rip+g_chunks],0
    mov qword ptr [rip+g_canonical_chunks],0
    mov eax,1
.dllg_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# discover_support_term(edi=RegionSet leaf index) -> rax=chunk_lo, rdx=chunk_hi,
# ecx=0 exact interval/empty, ecx=1 witness unordered => full-domain support,
# ecx=2 physical failure. Every eval_slot call reasserts R10D because the leaf
# evaluator may consume R10 as an ordinary transient register.
discover_support_term:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,16
    mov r14d,edi
    mov r15,qword ptr [rip+g_domain_size]
    test r15,r15
    jz .dst_fail
    xor r12d,r12d                         # lo=0
    mov r13,r15
    dec r13                               # hi=n-1
.dst_min_loop:
    cmp r12,r13
    jae .dst_min_found
    mov rbx,r13
    sub rbx,r12
    shr rbx,1
    add rbx,r12                           # mid
    mov r8,rbx
    mov r9,r15
    mov r10d,r14d
    call eval_slot
    movsd qword ptr [rsp],xmm0
    lea r8,[rbx+1]
    mov r9,r15
    mov r10d,r14d
    call eval_slot
    movsd xmm1,qword ptr [rsp]
    ucomisd xmm1,xmm0
    jp .dst_full
    jbe .dst_min_left
    lea r12,[rbx+1]
    jmp .dst_min_loop
.dst_min_left:
    mov r13,rbx
    jmp .dst_min_loop
.dst_min_found:
    mov r8,r12
    mov r9,r15
    mov r10d,r14d
    call eval_slot
    test eax,eax
    jz .dst_empty
    mov qword ptr [rsp+8],r12             # exact true seed

    # lower_bound(true) over [0,seed]
    xor r12d,r12d
    mov r13,qword ptr [rsp+8]
.dst_left_loop:
    cmp r12,r13
    jae .dst_left_done
    mov rbx,r13
    sub rbx,r12
    shr rbx,1
    add rbx,r12
    mov r8,rbx
    mov r9,r15
    mov r10d,r14d
    call eval_slot
    test eax,eax
    jnz .dst_left_true
    lea r12,[rbx+1]
    jmp .dst_left_loop
.dst_left_true:
    mov r13,rbx
    jmp .dst_left_loop
.dst_left_done:
    mov qword ptr [rsp],r12               # first true element

    # lower_bound(false) over [seed,n), n is a false sentinel
    mov r12,qword ptr [rsp+8]
    mov r13,r15
.dst_right_loop:
    cmp r12,r13
    jae .dst_right_done
    mov rbx,r13
    sub rbx,r12
    shr rbx,1
    add rbx,r12
    cmp rbx,r15
    jae .dst_right_false
    mov r8,rbx
    mov r9,r15
    mov r10d,r14d
    call eval_slot
    test eax,eax
    jz .dst_right_false
    lea r12,[rbx+1]
    jmp .dst_right_loop
.dst_right_false:
    mov r13,rbx
    jmp .dst_right_loop
.dst_right_done:
    # Convert exact element support to conservative canonical-leaf support.
    mov rax,qword ptr [rsp]
    xor edx,edx
    div qword ptr [rip+chunk_elements_patch]
    mov rbx,rax                            # chunk_lo
    mov rax,r12
    xor edx,edx
    div qword ptr [rip+chunk_elements_patch]
    test rdx,rdx
    jz .dst_hi_ready
    inc rax
.dst_hi_ready:
    cmp rax,qword ptr [rip+g_canonical_chunks]
    jbe .dst_hi_ok
    mov rax,qword ptr [rip+g_canonical_chunks]
.dst_hi_ok:
    mov rdx,rax                            # chunk_hi
    mov rax,rbx                            # chunk_lo
    xor ecx,ecx
    jmp .dst_done
.dst_empty:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
    jmp .dst_done
.dst_full:
    xor eax,eax
    xor edx,edx
    mov ecx,1
    jmp .dst_done
.dst_fail:
    xor eax,eax
    xor edx,edx
    mov ecx,2
.dst_done:
    add rsp,16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# discover_support() -> eax 0/1.
# RegionSet is source-cardinality data: every AOT-proven basin contributes one
# exact cold interval; runtime sorts and canonicalizes arbitrary overlap or
# adjacency. No region-count class, density threshold, or workload geometry is
# encoded in the runtime.
discover_support:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,16
    xor eax,eax
    mov qword ptr [rip+g_support_regions],0
    mov qword ptr [rip+g_support_region_count],0
    mov qword ptr [rip+g_support_active_chunks],0
    mov rdx,qword ptr [rip+g_canonical_chunks]
    mov ecx,dword ptr [rip+support_mode_patch]
    test ecx,ecx
    jz .ds_regions_full_mode
    cmp ecx,2
    je .ds_regions_empty
    cmp ecx,1
    jne .ds_regions_fail
    mov r12d,dword ptr [rip+support_term_count_patch]
    test r12d,r12d
    jz .ds_regions_fail

    # One 16-byte [lo,hi) descriptor per proven leaf. The allocation size is a
    # source fact; there is no fixed RegionSet capacity.
    mov rsi,r12
    shl rsi,4
    jc .ds_regions_fail
    mov qword ptr [rsp],rsi
    xor edi,edi
    mov edx,PROT_RW
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    mov eax,SYS_mmap
    syscall
    test rax,rax
    js .ds_regions_fail
    mov qword ptr [rip+g_support_regions],rax
    mov r13,rax                            # descriptor base
    xor ebx,ebx                            # term index
    xor r14d,r14d                          # stored intervals
.ds_regions_term_loop:
    cmp ebx,r12d
    jae .ds_regions_terms_done
    mov edi,ebx
    call discover_support_term
    cmp ecx,1
    je .ds_regions_full
    cmp ecx,2
    je .ds_regions_fail
    cmp rax,rdx
    jae .ds_regions_term_next
    mov rcx,r14
    shl rcx,4
    mov qword ptr [r13+rcx],rax
    mov qword ptr [r13+rcx+8],rdx
    inc r14d
.ds_regions_term_next:
    inc ebx
    jmp .ds_regions_term_loop
.ds_regions_terms_done:
    test r14d,r14d
    jz .ds_regions_empty

    # Insertion sort by lo. Region count is source-derived and cold; keeping the
    # representation canonical is more valuable than maintaining another tree.
    mov ebx,1
.ds_sort_outer:
    cmp ebx,r14d
    jae .ds_sort_done
    mov rax,rbx
    shl rax,4
    mov r8,qword ptr [r13+rax]             # key lo
    mov r9,qword ptr [r13+rax+8]           # key hi
    mov r15d,ebx
.ds_sort_inner:
    test r15d,r15d
    jz .ds_sort_place
    mov rax,r15
    dec rax
    shl rax,4
    mov rcx,qword ptr [r13+rax]            # prev lo
    cmp rcx,r8
    jbe .ds_sort_place
    mov rdx,qword ptr [r13+rax+8]
    add rax,16
    mov qword ptr [r13+rax],rcx
    mov qword ptr [r13+rax+8],rdx
    dec r15d
    jmp .ds_sort_inner
.ds_sort_place:
    mov rax,r15
    shl rax,4
    mov qword ptr [r13+rax],r8
    mov qword ptr [r13+rax+8],r9
    inc ebx
    jmp .ds_sort_outer
.ds_sort_done:

    # Merge overlap and adjacency in-place into one disjoint canonical RegionSet.
    mov r15d,1                              # write count, first region retained
    mov ebx,1                               # read index
.ds_merge_loop:
    cmp ebx,r14d
    jae .ds_merge_done
    mov rax,rbx
    shl rax,4
    mov r8,qword ptr [r13+rax]             # next lo
    mov r9,qword ptr [r13+rax+8]           # next hi
    mov rax,r15
    dec rax
    shl rax,4
    mov rcx,qword ptr [r13+rax+8]          # current hi
    cmp r8,rcx
    ja .ds_merge_new
    cmp r9,rcx
    jbe .ds_merge_next
    mov qword ptr [r13+rax+8],r9
    jmp .ds_merge_next
.ds_merge_new:
    mov rax,r15
    shl rax,4
    mov qword ptr [r13+rax],r8
    mov qword ptr [r13+rax+8],r9
    inc r15d
.ds_merge_next:
    inc ebx
    jmp .ds_merge_loop
.ds_merge_done:
    mov qword ptr [rip+g_support_region_count],r15

    # Active work is the sum of disjoint surviving canonical quanta.
    xor r12d,r12d
    xor ebx,ebx
.ds_active_loop:
    cmp rbx,r15
    jae .ds_active_done
    mov rax,rbx
    shl rax,4
    mov rcx,qword ptr [r13+rax+8]
    sub rcx,qword ptr [r13+rax]
    jc .ds_regions_fail
    add r12,rcx
    jc .ds_regions_fail
    inc rbx
    jmp .ds_active_loop
.ds_active_done:
    mov qword ptr [rip+g_support_active_chunks],r12
    xor eax,eax
    jmp .ds_regions_done

.ds_regions_full:
    # An unordered witness makes one leaf conservatively full-domain. The union
    # is therefore the full ShapeFact domain, represented canonically as one region.
    mov rax,qword ptr [rip+g_canonical_chunks]
    mov qword ptr [r13],0
    mov qword ptr [r13+8],rax
    mov qword ptr [rip+g_support_region_count],1
    mov qword ptr [rip+g_support_active_chunks],rax
    xor eax,eax
    jmp .ds_regions_done
.ds_regions_full_mode:
    mov rax,qword ptr [rip+g_canonical_chunks]
    mov qword ptr [rip+g_support_active_chunks],rax
    xor eax,eax
    jmp .ds_regions_done
.ds_regions_empty:
    mov qword ptr [rip+g_support_region_count],0
    mov qword ptr [rip+g_support_active_chunks],0
    xor eax,eax
    jmp .ds_regions_done
.ds_regions_fail:
    mov eax,1
.ds_regions_done:
    add rsp,16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# support_range_class(rdi=begin_chunk,rsi=end_chunk) -> eax 0=no support,
# 1=entire range inside one canonical support region, 2=partial intersection.
support_range_class:
    cmp dword ptr [rip+support_mode_patch],0
    je .src_dense
    mov rcx,qword ptr [rip+g_support_region_count]
    test rcx,rcx
    jz .src_zero
    mov r8,qword ptr [rip+g_support_regions]
    xor edx,edx
.src_loop:
    cmp rdx,rcx
    jae .src_zero
    mov rax,rdx
    shl rax,4
    mov r9,qword ptr [r8+rax]              # lo
    mov r10,qword ptr [r8+rax+8]           # hi
    cmp r10,rdi
    jbe .src_next
    cmp r9,rsi
    jae .src_zero
    cmp rdi,r9
    jb .src_partial
    cmp rsi,r10
    jbe .src_dense
.src_partial:
    mov eax,2
    ret
.src_next:
    inc rdx
    jmp .src_loop
.src_zero:
    xor eax,eax
    ret
.src_dense:
    mov eax,1
    ret

# reprice_support_ownership() -> eax 0/1.
# Ownership is priced from the sum of surviving disjoint RegionSet quanta.
reprice_support_ownership:
    mov r10,qword ptr [rip+g_support_active_chunks]
    test r10,r10
    jz .rso_regions_ok
    mov r8,qword ptr [rip+g_chunks]
    cmp r8,1
    jbe .rso_regions_ok
    mov r9,qword ptr [rip+chunk_work_ticks_patch]
    test r9,r9
    jz .rso_regions_fail
    mov rax,qword ptr [rip+outward_materialization_ticks_patch]
    xor edx,edx
    div r9
    inc rax
    cmp rax,1
    jbe .rso_regions_ok
    cmp r10,rax
    jae .rso_regions_bound
    mov qword ptr [rip+g_chunks],1
    jmp .rso_regions_ok
.rso_regions_bound:
    dec r10
    dec rax
    xor edx,edx
    div rax
    test rax,rax
    jnz .rso_regions_clip
    mov rax,1
.rso_regions_clip:
    cmp r8,rax
    jbe .rso_regions_ok
    mov qword ptr [rip+g_chunks],rax
.rso_regions_ok:
    xor eax,eax
    ret
.rso_regions_fail:
    mov eax,1
    ret

# strict_split_k(rdi=canonical subtree leaves, esi=ownership regions)
# -> rax=canonical left leaves, edx=left ownership regions.
# The split is mathematics: q=1 pairwise reduction splits a power-of-two tree in
# half and every other tree at its greatest lower power of two.  K is distributed
# proportionally but can only cut at true subtree boundaries.
strict_split_k:
    push rbx
    push r12
    mov r12,rdi
    mov ebx,esi
    cmp r12,2
    jb .ssk_fail
    cmp ebx,2
    jb .ssk_fail
    mov rax,r12
    bsr rcx,rax
    mov r8,1
    shl r8,cl
    cmp r8,r12
    jne .ssk_have_left
    shr r8,1
.ssk_have_left:
    test r8,r8
    jz .ssk_fail
    mov r9,r12
    sub r9,r8                       # right leaves

    # rounded proportional ownership share: round(K * left / N)
    mov rax,rbx
    mul r8
    mov rcx,r12
    shr rcx,1
    add rax,rcx
    adc rdx,0
    div r12
    mov rcx,rax                     # proposed k_left

    # lower bound max(1, K-right_leaves)
    mov r10,1
    mov rax,rbx
    cmp rax,r9
    jbe .ssk_lower_ready
    sub rax,r9
    cmp rax,r10
    cmova r10,rax
.ssk_lower_ready:
    # upper bound min(K-1, left_leaves)
    mov r11,rbx
    dec r11
    cmp r11,r8
    cmova r11,r8
    cmp rcx,r10
    cmovb rcx,r10
    cmp rcx,r11
    cmova rcx,r11
    test rcx,rcx
    jz .ssk_fail
    cmp rcx,rbx
    jae .ssk_fail
    mov rax,r8
    mov rdx,rcx
    pop r12
    pop rbx
    ret
.ssk_fail:
    xor eax,eax
    xor edx,edx
    pop r12
    pop rbx
    ret

# build_strict_descriptors(rsi=chunk_lo, rdx=leaf_count, ecx=K, r8=region_base)
# Each ownership leaf is one true node of the canonical q=1 reduction tree.
build_strict_descriptors:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,16
    mov r12,rsi                     # lo
    mov r13,rdx                     # len
    mov r14d,ecx                    # K
    mov r15,r8                      # base region
    cmp r14d,1
    jne .bsd_split
    mov rax,r15
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    mov qword ptr [rax+8],r12
    lea rdx,[r12+r13]
    mov qword ptr [rax+16],rdx
    xor eax,eax
    jmp .bsd_done
.bsd_split:
    mov rdi,r13
    mov esi,r14d
    call strict_split_k
    test rax,rax
    jz .bsd_fail
    test edx,edx
    jz .bsd_fail
    mov qword ptr [rsp],rax          # left len
    mov dword ptr [rsp+8],edx        # left K

    mov rsi,r12
    mov rdx,rax
    mov ecx,dword ptr [rsp+8]
    mov r8,r15
    call build_strict_descriptors
    test eax,eax
    jnz .bsd_fail

    mov rax,qword ptr [rsp]
    lea rsi,[r12+rax]
    mov rdx,r13
    sub rdx,rax
    mov ecx,r14d
    sub ecx,dword ptr [rsp+8]
    mov r8,r15
    mov eax,dword ptr [rsp+8]
    add r8,rax
    call build_strict_descriptors
    jmp .bsd_done
.bsd_fail:
    mov eax,1
.bsd_done:
    add rsp,16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# build_region_descriptors() -> eax 0/1.  Tolerant ownership is balanced directly
# over the canonical leaf line; Strict ownership is cut only at true q=1 subtree
# boundaries.  Launch exposure itself remains arbitrary-cardinality in both cases.
build_region_descriptors:
    cmp dword ptr [rip+reduction_tolerant_patch],0
    jne .brd_tolerant
    xor esi,esi
    mov rdx,qword ptr [rip+g_canonical_chunks]
    mov ecx,dword ptr [rip+g_chunks]
    xor r8d,r8d
    call build_strict_descriptors
    ret
.brd_tolerant:
    # Balanced integer partition of canonical leaf indices into K ownership
    # intervals.  No fixed chunk size or power-of-two executor geometry exists.
    xor r8d,r8d                      # region index
.brd_tol_loop:
    cmp r8,qword ptr [rip+g_chunks]
    jae .brd_ok
    mov rax,qword ptr [rip+g_canonical_chunks]
    mul r8
    div qword ptr [rip+g_chunks]
    mov r10,rax                      # lo=floor(Q*r/K)
    mov r9,r8
    inc r9
    mov rax,qword ptr [rip+g_canonical_chunks]
    mul r9
    div qword ptr [rip+g_chunks]
    mov r11,rax                      # hi=floor(Q*(r+1)/K)
    cmp r11,r10
    jbe .brd_fail
    mov rax,r8
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    mov qword ptr [rax+8],r10
    mov qword ptr [rax+16],r11
    inc r8
    jmp .brd_tol_loop
.brd_ok:
    xor eax,eax
    ret
.brd_fail:
    mov eax,1
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

    # Launch exposure is purely ownership cardinality: exact balanced split of
    # region identities.  Strict binary-tree geometry is not an executor rule.
    mov r8,rax
    inc r8
    shr r8,1
    lea rbx,[r13+r8]

    mov rax,rbx
    shl rax,14
    mov r15,qword ptr [rip+g_region_arena]
    test r15,r15
    jz .bad_args
    add r15,rax

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
    mov rax,r15
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    mov rsi,qword ptr [rax+8]
    mov rdx,qword ptr [rax+16]
    push rax
    call worker_range
    pop rax
    movsd qword ptr [rax],xmm0
    inc r15
    jmp .rrf_refused_loop
.rrf_refused_done:
    mov r14,rbx
    jmp .rrf_descend

.rrf_leaf:
    mov rax,r13
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    mov r15,rax                     # callee-saved descriptor identity
    mov rsi,qword ptr [r15+8]
    mov rdx,qword ptr [r15+16]
    # Raw clone installs the child stack at the slice top; the child does not
    # inherit this function's pre-clone frame. Keep leaf metadata in r15 rather
    # than addressing above the fresh child RSP. worker_range preserves r15.
    call worker_range
    movsd qword ptr [r15],xmm0
    test r12d,r12d
    jnz .rrf_root_leaf
    xor edi,edi
    mov eax,SYS_exit
    syscall
    hlt

.rrf_root_leaf:
    # Every non-root execution is a direct child of the invocation root.
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
    call reduce_region_results

    add rsp,64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# reduce_strict_region_tree(rdx=canonical leaves, ecx=K, r8=region base) -> xmm0
# Cold final arithmetic only.  It reconstructs the q=1 parent additions from K
# already-computed true subtree values; no execution ancestry survives here.
reduce_strict_region_tree:
    push rbx
    push r12
    push r13
    push r14
    sub rsp,16
    mov r12,rdx
    mov r13d,ecx
    mov r14,r8
    cmp r13d,1
    jne .rsrt_split
    mov rax,r14
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    movsd xmm0,qword ptr [rax]
    jmp .rsrt_done
.rsrt_split:
    mov rdi,r12
    mov esi,r13d
    call strict_split_k
    test rax,rax
    jz .bad_args
    test edx,edx
    jz .bad_args
    mov qword ptr [rsp],rax
    mov dword ptr [rsp+8],edx

    mov rdx,rax
    mov ecx,dword ptr [rsp+8]
    mov r8,r14
    call reduce_strict_region_tree
    movsd qword ptr [rsp],xmm0       # left exact subtree scalar

    # Recompute the cold split after preserving the left scalar; this avoids a
    # second metadata tree. Region base advances by k_left, never by leaf count.
    mov rdi,r12
    mov esi,r13d
    call strict_split_k
    mov rbx,rax
    mov r9,rdx                       # k_left
    mov rdx,r12
    sub rdx,rbx
    mov ecx,r13d
    sub ecx,r9d
    mov r8,r14
    add r8,r9
    call reduce_strict_region_tree
    movsd xmm1,qword ptr [rsp]
    addsd xmm1,xmm0
    movapd xmm0,xmm1
.rsrt_done:
    add rsp,16
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# reduce_region_results() -> xmm0 f64. Strict reconstructs the immutable q=1
# tree; tolerant mode uses the same left-to-right region frontier reduction that
# its explicit numerical contract already permits.
reduce_region_results:
    cmp dword ptr [rip+reduction_tolerant_patch],0
    jne .rrr_tolerant
    mov rdx,qword ptr [rip+g_canonical_chunks]
    mov ecx,dword ptr [rip+g_chunks]
    xor r8d,r8d
    call reduce_strict_region_tree
    ret

.rrr_tolerant:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,REDUCE_LEVELS*8+16
    xor r15d,r15d
    xor r13d,r13d
.rrr_next:
    cmp r13,qword ptr [rip+g_chunks]
    jae .rrr_finish
    mov rax,r13
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
# Support-aware realization of one canonical subtree. Strict mode recursively
# folds proven-zero subtrees to +0 while reproducing the immutable q=1 addition
# tree exactly. Tolerant mode may directly clip to the support intersection.
worker_range:
    push rbx
    push r12
    push r13
    push r14
    mov r12,rsi
    mov r13,rdx
    mov rdi,r12
    mov rsi,r13
    call support_range_class
    test eax,eax
    jz .wr_regions_zero
    cmp eax,1
    je .wr_regions_dense
    # Partial RegionSet intersection. Split only along the canonical reduction
    # tree, so Strict addition order is unchanged while zero subtrees disappear.
    mov r14,r13
    sub r14,r12
    cmp r14,1
    jbe .wr_regions_dense
    mov rax,r14
    bsr rcx,rax
    mov rbx,1
    shl rbx,cl
    cmp rbx,r14
    jne .wr_regions_have_left
    shr rbx,1
.wr_regions_have_left:
    test rbx,rbx
    jz .bad_args
    add rbx,r12
    sub rsp,16
    mov rsi,r12
    mov rdx,rbx
    call worker_range
    movsd qword ptr [rsp],xmm0
    mov rsi,rbx
    mov rdx,r13
    call worker_range
    movsd xmm1,qword ptr [rsp]
    addsd xmm1,xmm0
    movapd xmm0,xmm1
    add rsp,16
    jmp .wr_regions_done
.wr_regions_dense:
    mov rsi,r12
    mov rdx,r13
    call worker_range_dense
    jmp .wr_regions_done
.wr_regions_zero:
    pxor xmm0,xmm0
.wr_regions_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Dense canonical subtree evaluator. Every supplied range is a true canonical
# reduction subtree when Strict; SupportFact only chooses whether this authority
# needs to exist physically.
worker_range_dense:
    push rbx
    push r12
    push r13
    push r14
    push r15
    # The frontier has REDUCE_LEVELS f64 carriers. The old 96-byte frame only
    # happened to survive while execution-derived ranges never reached level 12.
    # 1.3.102 decouples execution cardinality from canonical subtree size, so the
    # physical frame must follow the mathematical frontier authority itself.
    sub rsp,REDUCE_LEVELS*8+16
    mov r13,rsi
    mov r14,rdx
    mov r12,qword ptr [rip+g_domain_size]

    # Invocation-domain exact-mod constants are worker invariants, not leaf
    # work.  The old eval_chunk wrapper rebuilt u64->f64(N) and 1/N for every
    # canonical leaf. Strict cardinality-invariant trees make those leaves
    # visible, so keeping the duplicate divide would turn semantics into cost.
    vxorpd xmm14,xmm14,xmm14
    vcvtsi2sd xmm14,xmm14,r12
    movsd qword ptr [rsp+REDUCE_LEVELS*8],xmm14
    mov rax,0x3ff0000000000000
    vmovq xmm15,rax
    vdivsd xmm15,xmm15,xmm14
    movsd qword ptr [rsp+REDUCE_LEVELS*8+8],xmm15

    cmp dword ptr [rip+vector_width_patch],TENSOR_RUNTIME_VECTOR_WIDTH
    jne .w_range_no_vec_init
    call eval_vec_init
.w_range_no_vec_init:

.w_range_ready:
    xor r15d,r15d                   # occupied reduction levels

.w_chunk_loop:
    cmp r13,r14
    jae .w_reduce_finish
    # Burn the former eval_chunk wrapper into the range loop.  Start/end are
    # still exactly one canonical structural leaf; only duplicate wrapper work
    # disappears.
    mov rax,r13
    mul qword ptr [rip+chunk_elements_patch]
    test rdx,rdx
    jnz .bad_args
    mov rsi,rax
    mov rdx,qword ptr [rip+chunk_elements_patch]
    add rdx,rsi
    jc .bad_args
    cmp rdx,r12
    cmova rdx,r12
.ifdef TENSOR_RUNTIME_NATIVE256
    vbroadcastsd ymm14,qword ptr [rsp+REDUCE_LEVELS*8]
    vbroadcastsd ymm15,qword ptr [rsp+REDUCE_LEVELS*8+8]
.else
    vbroadcastsd zmm14,qword ptr [rsp+REDUCE_LEVELS*8]
    vbroadcastsd zmm15,qword ptr [rsp+REDUCE_LEVELS*8+8]
.endif
    mov rdi,r12
    call eval_vec4                  # xmm0 = exact canonical rightmost leaf

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
    add rsp,REDUCE_LEVELS*8+16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Canonical leaf evaluation is fused directly into worker_range.  There is no
# second runtime leaf wrapper or per-leaf dynamic-mod invariant reconstruction.

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
.global reduction_tolerant_patch
reduction_tolerant_patch: .long 0
.global support_mode_patch
support_mode_patch: .long 0
.global support_term_count_patch
support_term_count_patch: .long 0
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
g_canonical_chunks: .skip 8
g_support_regions: .skip 8
g_support_region_count: .skip 8
g_support_active_chunks: .skip 8
.p2align 3
g_region_arena: .skip 8
g_region_arena_size: .skip 8
