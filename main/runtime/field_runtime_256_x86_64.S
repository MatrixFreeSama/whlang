.intel_syntax noprefix
.include "runtime/execution_admission_refresh_x86_64.inc"
.include "compiler/native256_physical_profile.inc"
.include "runtime/field_runtime_common_blocks.inc"

# Keep literal YMM encodings tied to the single native256 physical profile.
.if FF256_V3_REG != 12
.error "native256 field v3 literal register no longer matches physical profile"
.endif
.if FF256_TAIL_MASK_REG != 4
.error "native256 field tail-mask literal register no longer matches physical profile"
.endif
.if FF256_REDUCE_REG != 5
.error "native256 field reduction literal register no longer matches physical profile"
.endif
.if FF256_I0_REG != 13
.error "native256 field i0 literal register no longer matches physical profile"
.endif
.if FF256_I1_REG != 14
.error "native256 field i1 literal register no longer matches physical profile"
.endif
.if FF256_PHASE_SCRATCH_REG != 15
.error "native256 field phase-scratch literal register no longer matches physical profile"
.endif
# Wheelchair 1.2.16 native materialized-field runtime, AVX2/YMM physicalization.
# External field ABI is a compact mmap-able binary descriptor.  The hot path
# never walks descriptor objects: launch-time validation collapses them into
# base/extent/stride tables consumed by vector helpers.

.equ SYS_read,0
.equ SYS_write,1
.equ SYS_openat,257
.equ SYS_close,3
.equ SYS_fstat,5
.equ SYS_mmap,9
.equ SYS_munmap,11
.equ SYS_exit,60
.equ SYS_exit_group,231
.equ SYS_clone,56
.equ SYS_wait4,61
.equ SYS_sched_setaffinity,203
.equ AT_FDCWD,-100
.equ O_RDONLY,0
.equ O_RDWR,2
.equ PROT_READ,1
.equ PROT_WRITE,2
.equ MAP_SHARED,1
.equ MAP_PRIVATE,2
.equ MAP_PRIVATE_ANON,0x22
.equ MAP_PRIVATE_ANON_STACK,0x20022
.equ CLONE_VM_FILES_FS_SIGCHLD,0x711
.equ CLONE_PARENT,0x8000
.equ REGION_STACK_SIZE,16384
# Reduction frontier follows the qword chunk-index domain.
.equ REDUCE_LEVELS,64
.equ FIELD_HEADER_SIZE,64
.equ FIELD_MAGIC,0x373132444c464857  # "WHFLD217" little endian
.equ FIELD_VERSION,2
.equ FIELD_TYPE_F32,1
.equ FIELD_MODE_INPUT,0
.equ FIELD_MODE_OUTPUT,1
.equ FIELD_MODE_INOUT,2

# Header layout
.equ FH_MAGIC,0
.equ FH_VERSION,8
.equ FH_TYPE,12
.equ FH_RANK,16          # u64 RankFact
.equ FH_DATA_OFF,24
.equ FH_TOTAL,32
.equ FH_FLAGS,40
# Axis descriptors follow the fixed header:
#   extent[rank] u64 at FIELD_HEADER_SIZE
#   stride[rank] u64 immediately after extents

.section .text
.global _start
_start:
    # 1.3.91 Field fabric descriptor admission. A proved fabric projection may
    # never silently execute through the native x86 body when no bridge exists.
    cmp qword ptr [rip+field_fabric_datapath_bytes_patch],0
    je .fabric_admission_done
    cmp dword ptr [rip+field_fabric_activation_bridge_present_patch],1
    jne .bad_args
    cmp qword ptr [rip+field_fabric_activation_entry_patch],0
    je .bad_args
.fabric_admission_done:
    # 1.3.87 one-shot AOT silicon placement. Outward executions inherit this
    # exact admitted LLC-domain mask; no runtime work/resource matching exists.
    # AOT locality may narrow, but never expand, the external invocation domain.
    CONSTRAIN_STATIC_PLACEMENT_WITHIN_INVOCATION static_placement_required_patch, static_placement_mask_bytes_patch, static_placement_mask_patch
    REFRESH_EXECUTION_ADMISSION execution_admission_patch
    mov r15,rsp
    mov rax,[r15]
    mov ecx,dword ptr [rip+field_count_patch]
    inc ecx
    cmp eax,ecx
    jne .bad_args
    test ecx,ecx
    jz .bad_args
    call field_prepare_instance_arenas
    test eax,eax
    jnz .bad_args

    # Map and validate every declared field in source order.
    xor ebx,ebx
.map_fields:
    cmp ebx,dword ptr [rip+field_count_patch]
    jae .mapped
    mov rdi,[r15+16+rbx*8]
    mov rax,[rip+field_mode_ptr]
    movzx edx,byte ptr [rax+rbx]
    call map_one_field
    test eax,eax
    jnz .bad_args
    inc ebx
    jmp .map_fields

.mapped:
    call finalize_shape
    test eax,eax
    jnz .bad_args
    call normalize_specs
    test eax,eax
    jnz .bad_args
    call validate_parallel_mutable_geometry
    test eax,eax
    jnz .bad_args
    # 1.3.3 launch-time Physical Memory Access Profitability. This is a cold,
    # owner-blind target/topology query; the hot path receives only one immutable
    # policy bit and never consults a global mutable coordinator.
    call field_init_memory_profitability

    # One virtual stack/result slice per non-root ownership region. Region-start
    # identity is mathematical and invocation-local; it is not a worker slot.
    mov qword ptr [rip+g_region_arena],0
    mov qword ptr [rip+g_region_arena_size],0
    mov rax,[rip+g_chunks]
    cmp rax,1
    jbe .region_arena_ready
    dec rax
    shl rax,14
    mov [rip+g_region_arena_size],rax
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ|PROT_WRITE
    mov r10d,MAP_PRIVATE_ANON_STACK
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .bad_args
    mov [rip+g_region_arena],rax
.region_arena_ready:

    xor esi,esi
    mov rdx,[rip+g_chunks]
    mov edi,1
    call run_region_frontier
    vmovd r12d,xmm0

    mov rdi,[rip+g_region_arena]
    test rdi,rdi
    jz .no_region_arena_unmap
    mov eax,SYS_munmap
    mov rsi,[rip+g_region_arena_size]
    syscall
.no_region_arena_unmap:
    movd xmm0,r12d
    movd eax,xmm0
    call print_checksum_f32

    # Unmap field mappings exactly once after all ownership executions are reaped.
    xor ebx,ebx
.unmap_loop:
    cmp ebx,dword ptr [rip+field_count_patch]
    jae .exit_ok
    mov rax,[rip+g_field_map_ptr]
    mov rdi,[rax+rbx*8]
    test rdi,rdi
    jz .unmap_next
    mov rax,[rip+g_field_size_ptr]
    mov rsi,[rax+rbx*8]
    mov eax,SYS_munmap
    syscall
.unmap_next:
    inc ebx
    jmp .unmap_loop
.exit_ok:
    xor edi,edi
    mov eax,SYS_exit_group
    syscall
    ud2

.bad_args:
    mov edi,2
    mov eax,SYS_exit_group
    syscall
    ud2


# 1.3.56 instance-sized Field runtime storage.  Field and access cardinality are
# properties of the compiled graph.  RankFact is invocation data; no fixed rank width survives.
field_prepare_instance_arenas:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,dword ptr [rip+field_count_patch]
    mov r12d,dword ptr [rip+access_spec_count_patch]
    test ebx,ebx; jz .fpia_fail
    test r12d,r12d; jz .fpia_fail
    mov rax,qword ptr [rip+field_metadata_va_patch]
    test rax,rax; jz .fpia_fail

    # One invocation-wide RankFact precedes fixed field modes and Rank-N deltas.
    mov r13,[rax]
    test r13,r13; jz .fpia_fail
    mov [rip+g_rank],r13
    mov r14,r13
    shl r14,2
    jc .fpia_fail
    mov [rip+g_axis_bytes],r14
    mov [rip+g_access_delta_stride],r14
    lea rcx,[rax+8]
    mov qword ptr [rip+field_mode_ptr],rcx
    add rcx,rbx
    mov qword ptr [rip+access_delta_ptr],rcx

    # Fixed field facts + RankFact-derived field/access/axis facts.
    mov r15,rbx
    imul r15,r15,49                 # six qwords + contig byte
    jo .fpia_fail
    mov rax,rbx
    imul rax,r14                    # one axis table per field
    jo .fpia_fail
    add r15,rax; jc .fpia_fail      # extents
    add r15,rax; jc .fpia_fail      # strides
    mov rax,r12
    imul rax,r14
    jo .fpia_fail
    add r15,rax; jc .fpia_fail      # normalized access deltas
    mov rax,r12
    shl rax,3
    jc .fpia_fail
    add r15,rax; jc .fpia_fail      # linear byte deltas
    mov rax,r14
    imul rax,5
    jo .fpia_fail
    add r15,rax; jc .fpia_fail      # logical stride/shift/mask/min/max
    add r15,127; jc .fpia_fail
    and r15,-64

    mov rsi,r15
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ|PROT_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax; js .fpia_fail
    mov qword ptr [rip+g_field_arena],rax
    mov qword ptr [rip+g_field_arena_size],r15
    mov r14,rax
    mov qword ptr [rip+g_field_map_ptr],r14
    lea r14,[r14+rbx*8]
    mov qword ptr [rip+g_field_size_ptr],r14
    lea r14,[r14+rbx*8]
    mov qword ptr [rip+g_field_dev_ptr],r14
    lea r14,[r14+rbx*8]
    mov qword ptr [rip+g_field_ino_ptr],r14
    lea r14,[r14+rbx*8]
    mov qword ptr [rip+g_field_data_ptr],r14
    lea r14,[r14+rbx*8]
    mov qword ptr [rip+g_field_total_ptr],r14
    lea r14,[r14+rbx*8]
    mov qword ptr [rip+g_field_contig_ptr],r14
    add r14,rbx
    add r14,7; and r14,-8

    mov qword ptr [rip+g_field_extents_ptr],r14
    mov rax,rbx; imul rax,qword ptr [rip+g_axis_bytes]; add r14,rax
    mov qword ptr [rip+g_field_strides_ptr],r14
    add r14,rax
    mov qword ptr [rip+g_spec_delta_norm_ptr],r14
    mov rax,r12; imul rax,qword ptr [rip+g_axis_bytes]; add r14,rax
    mov qword ptr [rip+g_spec_linear_delta_bytes_ptr],r14
    lea r14,[r14+r12*8]
    mov qword ptr [rip+g_logical_strides_ptr],r14
    add r14,qword ptr [rip+g_axis_bytes]
    mov qword ptr [rip+g_stride_shifts_ptr],r14
    add r14,qword ptr [rip+g_axis_bytes]
    mov qword ptr [rip+g_extent_masks_ptr],r14
    add r14,qword ptr [rip+g_axis_bytes]
    mov qword ptr [rip+g_regular_min_delta_ptr],r14
    add r14,qword ptr [rip+g_axis_bytes]
    mov qword ptr [rip+g_regular_max_delta_ptr],r14
    xor eax,eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fpia_fail:
    mov eax,1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# map_one_field(rdi=path, edx=mode, ebx=index) -> eax=0/1
map_one_field:
FRC_map_one_field
validate_mutable_injective:
FRC_validate_mutable_injective
finalize_shape:
FRC_finalize_shape
field_derive_launch_leaf_geometry:
FRC_field_derive_launch_leaf_geometry
validate_parallel_mutable_geometry:
FRC_validate_parallel_mutable_geometry
normalize_specs:
FRC_normalize_specs
field_regular_run_end:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbp,rdi                         # execution-local RegionFact deltas
    mov r12,rdx                         # q, first lane
    mov r13,rcx                         # end
    mov rax,r13
    sub rax,r12
    cmp rax,8
    jb .fre81_fail                      # partial tail keeps truthful mask
    mov ebx,dword ptr [rip+g_rank]
    test ebx,ebx
    jz .fre81_fail

    # A direct packet may not cross the innermost row itself.  This is a true
    # affine boundary; the one straddling episode remains generic.
    mov ecx,ebx
    dec ecx
    mov r8,[rip+g_field_extents_ptr]
    mov r9d,[r8+rcx*4]                  # innermost extent
    test r9d,r9d
    jz .fre81_fail
    cmp byte ptr [rip+g_shape_pow2],1
    jne .fre81_row_exact
    mov r8,[rip+g_extent_masks_ptr]
    mov eax,r12d
    and eax,[r8+rcx*4]
    mov r15d,eax                        # bit-exact innermost coordinate fact
    xor r10d,r10d                       # unused by pow2 coordinate realization
    jmp .fre81_row_ready
.fre81_row_exact:
    mov rax,r12
    xor edx,edx
    div r9                              # rdx = first-lane inner coordinate
    mov r15,rdx                         # c_inner
    mov r10,rax                         # quotient shared by all outer axes
.fre81_row_ready:
    lea rax,[r15+7]
    cmp rax,r9
    jae .fre81_fail

    # Initial bound includes the last complete packet in this row and never
    # crosses the invocation end.  q is compared with this exclusive first-lane
    # bound by the generated direct loop.
    mov r14,r12
    sub r14,r15                         # row base
    add r14,r9                          # row end
    sub r14,7                   # first unsafe q after final full packet
    mov rax,r13
    sub rax,7
    cmp r14,rax
    cmova r14,rax

    # Cheapest proof first: one coordinate decode per axis proves the whole
    # neighborhood interior from its canonical min/max envelope. Only a real
    # periodic boundary descends into per-access piecewise-affine refinement.
    mov ecx,dword ptr [rip+g_rank]
    dec ecx
    mov r11d,ecx
    mov r8,[rip+g_field_extents_ptr]
.fre81_fast_axis:
    mov r9d,[r8+rcx*4]
    test r9d,r9d
    jz .fre81_fail
    cmp byte ptr [rip+g_shape_pow2],1
    jne .fre81_fast_exact_coord
    # Coordinate identity is a proved bit relation for power-of-two extents.
    # This is one RegionFact realization, not a second execution backend.
    mov ebx,ecx
    mov rax,[rip+g_stride_shifts_ptr]
    mov ecx,[rax+rbx*4]
    mov rax,r12
    shr rax,cl
    mov rdx,[rip+g_extent_masks_ptr]
    and eax,[rdx+rbx*4]
    mov esi,eax
    mov edi,eax
    cmp ebx,r11d
    jne .fre81_fast_pow2_ready
    add edi,7
.fre81_fast_pow2_ready:
    mov ecx,ebx
    jmp .fre81_fast_have_coord
.fre81_fast_exact_coord:
    cmp ecx,r11d
    jne .fre81_fast_outer_coord
    mov esi,r15d
    lea edi,[r15+7]
    jmp .fre81_fast_have_coord
.fre81_fast_outer_coord:
    mov rax,r10
    xor edx,edx
    div r9
    mov r10,rax
    mov esi,edx
    mov edi,edx
.fre81_fast_have_coord:
    mov rax,[rip+g_regular_min_delta_ptr]
    mov edx,[rax+rcx*4]
    mov eax,esi
    add eax,edx
    js .fre81_fast_boundary
    mov rax,[rip+g_regular_max_delta_ptr]
    mov edx,[rax+rcx*4]
    mov eax,edi
    add eax,edx
    cmp eax,r9d
    jae .fre81_fast_boundary
    test ecx,ecx
    jz .fre81_fast_interior
    dec ecx
    jmp .fre81_fast_axis

.fre81_fast_boundary:
    # An innermost wrap occupies only a local row fragment; the generic vector
    # episode already owns truthful mask/gather machinery, so no second Region
    # is materialized merely to replace that local boundary.  Outer-axis wraps
    # persist across the row and may repay piecewise-affine physicalization.
    cmp ecx,r11d
    je .fre81_fail
    jmp .fre81_piecewise

.fre81_fast_interior:
.fre81_fast_bound:
    mov ecx,dword ptr [rip+g_rank]
    dec ecx
    mov rax,[rip+g_regular_max_delta_ptr]
    movsxd rax,dword ptr [rax+rcx*4]
    mov r8,r12
    sub r8,r15
    mov rdx,[rip+g_field_extents_ptr]
    mov r9d,[rdx+rcx*4]
    add r8,r9
    sub r8,rax
    sub r8,7
    cmp r14,r8
    cmova r14,r8
    xor edx,edx                         # canonical interior class
    jmp .fre81_success

.fre81_piecewise:
    xor ebx,ebx                         # access id
.fre81_access:
    cmp ebx,dword ptr [rip+access_spec_count_patch]
    jae .fre81_piecewise_success
    xor r11d,r11d                       # signed physical delta in elements
    xor r10d,r10d                       # axis
.fre81_axis:
    mov eax,dword ptr [rip+g_rank]
    cmp r10d,eax
    jae .fre81_store_delta

    # extent
    mov r8,[rip+g_field_extents_ptr]
    mov r9d,[r8+r10*4]
    test r9d,r9d
    jz .fre81_fail

    # c0 = (q / logical_stride[axis]) mod extent.  Region transition is cold,
    # so exact integer division is preferable to retaining two old pow2/generic
    # proof families.
    mov r8,[rip+g_logical_strides_ptr]
    mov ecx,[r8+r10*4]
    test ecx,ecx
    jz .fre81_fail
    mov rax,r12
    xor edx,edx
    div rcx
    xor edx,edx
    div r9
    mov esi,edx                         # c0
    mov edi,esi                         # c1
    mov eax,dword ptr [rip+g_rank]
    dec eax
    cmp r10d,eax
    jne .fre81_coord_ready
    add edi,7
.fre81_coord_ready:

    # Recover the canonical shortest signed periodic delta from the already-old
    # positive ring delta authority.
    mov r8,[rip+g_spec_delta_norm_ptr]
    mov rax,rbx
    imul rax,qword ptr [rip+g_access_delta_stride]
    lea rax,[rax+r10*4]
    mov eax,[r8+rax]
    mov edx,r9d
    shr edx,1
    cmp eax,edx
    jle .fre81_delta_signed
    sub eax,r9d                         # eax = signed shortest d
.fre81_delta_signed:
    mov edx,eax                         # edx = d, preserved for inner bound
    add esi,eax                         # s0
    add edi,eax                         # s1

    # Every active lane must share one wrap class.  If the packet itself
    # straddles a periodic boundary, no constant affine displacement exists.
    test esi,esi
    js .fre81_negative
    cmp esi,r9d
    jae .fre81_positive
    cmp edi,r9d
    jae .fre81_fail                     # interior -> positive straddle
    mov eax,edx                         # interior effective d

    # On the innermost axis, stop before the first q whose final lane would
    # enter positive wrap for this access.
    mov ecx,dword ptr [rip+g_rank]
    dec ecx
    cmp r10d,ecx
    jne .fre81_accumulate
    mov ecx,r9d
    sub ecx,edx
    sub ecx,7                   # first unsafe inner coordinate
    mov r8,r12
    sub r8,r15                          # row base
    movsxd rcx,ecx
    add r8,rcx
    cmp r14,r8
    cmova r14,r8
    jmp .fre81_accumulate

.fre81_negative:
    test edi,edi
    jns .fre81_fail                     # negative -> interior straddle
    mov eax,edx
    add eax,r9d                         # wrap from low side: d + extent
    mov ecx,dword ptr [rip+g_rank]
    dec ecx
    cmp r10d,ecx
    jne .fre81_accumulate
    # First q whose final lane reaches coordinate zero after adding d.
    mov ecx,edx
    neg ecx
    sub ecx,7
    mov r8,r12
    sub r8,r15
    movsxd rcx,ecx
    add r8,rcx
    cmp r14,r8
    cmova r14,r8
    jmp .fre81_accumulate

.fre81_positive:
    cmp edi,r9d
    jb .fre81_fail                     # cannot share positive-wrap class
    mov eax,edx
    sub eax,r9d                        # high-side wrap: d - extent

.fre81_accumulate:
    # Convert axis displacement to flat logical elements using the canonical
    # common-shape stride.  Overflow cannot be silently turned into a direct
    # region; generic topology remains authoritative on failure.
    mov r8,[rip+g_logical_strides_ptr]
    movsxd rcx,dword ptr [r8+r10*4]
    movsxd rax,eax
    imul rax,rcx
    jo .fre81_fail
    add r11,rax
    jo .fre81_fail
    inc r10d
    jmp .fre81_axis

.fre81_store_delta:
    mov rax,r11
    shl rax,2                           # f32 byte displacement
    jo .fre81_fail
    mov [rbp+rbx*8],rax                # private to this execution/frame
    inc ebx
    jmp .fre81_access

.fre81_piecewise_success:
    mov edx,1                           # exact wrap-folded deltas are local
    jmp .fre81_success

.fre81_success:
    cmp r14,r12
    jbe .fre81_fail
    mov rax,r14
    jmp .fre81_done
.fre81_fail:
    xor eax,eax
.fre81_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# causal executor tree -> scalar f32 in xmm0
# 1.3.3 target-aware memory-access profitability.
# Largest deterministic cache size is read from architectural CPUID leaf 4.
# Pure streaming output is selected only when its byte working set is at least
# 2x the largest visible cache; irregular input/gather pressure raises that to
# 4x. This removes the old element-count heuristic and the small-output NT
# regression without runtime autotuning or recipient-aware scheduling.
field_init_memory_profitability:
FRC_field_init_memory_profitability
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

.frf_descend:
    mov rax,r14
    sub rax,r13
    cmp rax,1
    jbe .frf_leaf

    # Profitability was already collapsed into field_chunk_elements_patch.
    # Expose actual cardinality directly: no inherited binary reduction geometry.
    mov r8,rax
    inc r8
    shr r8,1
    lea rbx,[r13+r8]              # right ownership region begins here

    # The right-subtree start is unique and becomes the permanent result/stack
    # slot identity for the outward execution that owns its leftmost leaf.
    mov rax,rbx
    dec rax
    shl rax,14
    mov r15,qword ptr [rip+g_region_arena]
    test r15,r15
    jz .bad_args
    add r15,rax
    mov dword ptr [r15],0

    lea rsi,[r15+REGION_STACK_SIZE-16]
    mov eax,SYS_clone
    mov edi,CLONE_VM_FILES_FS_SIGCHLD
    test r12d,r12d
    jnz .frf_clone_flags_ready
    or edi,CLONE_PARENT
.frf_clone_flags_ready:
    xor edx,edx
    xor r10d,r10d
    xor r8d,r8d
    syscall
    test rax,rax
    js .frf_refused_right
    jz .frf_child

    # Current execution owns only the left side after exposing the right side.
    # No parent/child reduction relation is retained.
    mov r14,rbx
    jmp .frf_descend

.frf_child:
    # A non-root outward execution follows the left spine of its own disjoint
    # ownership range.  Any descendants it exposes use CLONE_PARENT and are
    # direct children of the invocation root rather than a runtime join tree.
    xor r12d,r12d
    mov r13,rbx
    jmp .frf_descend

.frf_refused_right:
    # Linux refusal does not create a compatibility backend.  The current
    # execution evaluates the refused ownership range with the same worker_range
    # primitive and publishes each canonical leaf result into its normal slot.
    mov r15,rbx
.frf_refused_loop:
    cmp r15,r14
    jae .frf_refused_done
    mov rsi,r15
    lea rdx,[r15+1]
    call worker_range
    mov rax,r15
    dec rax
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    movss dword ptr [rax],xmm0
    inc r15
    jmp .frf_refused_loop
.frf_refused_done:
    mov r14,rbx
    jmp .frf_descend

.frf_leaf:
    mov rsi,r13
    mov rdx,r14
    call worker_range
    test r12d,r12d
    jnz .frf_root_leaf

    # Leaf execution publishes only its own local reduction and immediately
    # returns its silicon context to the OS.  It knows no sibling or join tree.
    mov rax,r13
    dec rax
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    movss dword ptr [rax],xmm0
    xor edi,edi
    mov eax,SYS_exit
    syscall
    ud2

.frf_root_leaf:
    movss dword ptr [rsp],xmm0

    # All non-root outward executions are direct children of the invocation root.
    # wait4(-1) is the OS lifecycle truth; no Wheelchair completion counter,
    # scheduler state or join tree survives.
.frf_reap:
    mov dword ptr [rsp+8],0
    mov eax,SYS_wait4
    mov rdi,-1
    lea rsi,[rsp+8]
    xor edx,edx
    xor r10d,r10d
    syscall
    cmp rax,-10                    # -ECHILD
    je .frf_reduce
    cmp rax,-4                     # -EINTR
    je .frf_reap
    test rax,rax
    js .bad_args
    cmp dword ptr [rsp+8],0
    jne .bad_args
    jmp .frf_reap

.frf_reduce:
    movss xmm0,dword ptr [rsp]
    call reduce_region_results

    add rsp,64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# reduce_region_results(xmm0=root-region result) -> xmm0 f32
# Results are consumed in chunk order with the same left-to-right binary carry
# frontier used by worker_range.  Parallel ownership topology is absent here.
reduce_region_results:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,REDUCE_LEVELS*4+16
    movss dword ptr [rsp+REDUCE_LEVELS*4],xmm0
    xor r15d,r15d                  # occupied reduction levels
    xor r13d,r13d                  # region index

.rrr_next:
    cmp r13,qword ptr [rip+g_chunks]
    jae .rrr_finish
    test r13,r13
    jnz .rrr_load_slot
    movss xmm0,dword ptr [rsp+REDUCE_LEVELS*4]
    jmp .rrr_carry_start
.rrr_load_slot:
    mov rax,r13
    dec rax
    shl rax,14
    add rax,qword ptr [rip+g_region_arena]
    movss xmm0,dword ptr [rax]
.rrr_carry_start:
    xor ecx,ecx
.rrr_carry:
    bt r15,rcx
    jnc .rrr_store
    movss xmm1,dword ptr [rsp+rcx*4]
    addss xmm1,xmm0
    vmovaps xmm0,xmm1
    btr r15,rcx
    inc ecx
    cmp ecx,REDUCE_LEVELS
    jb .rrr_carry
    jmp .bad_args
.rrr_store:
    movss dword ptr [rsp+rcx*4],xmm0
    bts r15,rcx
    inc r13
    jmp .rrr_next

.rrr_finish:
    xor ecx,ecx
    xor edx,edx
    vxorps xmm0,xmm0,xmm0
.rrr_finish_loop:
    cmp ecx,REDUCE_LEVELS
    jae .rrr_done
    bt r15,rcx
    jnc .rrr_finish_next
    test edx,edx
    jnz .rrr_merge
    movss xmm0,dword ptr [rsp+rcx*4]
    mov edx,1
    jmp .rrr_finish_next
.rrr_merge:
    movss xmm1,dword ptr [rsp+rcx*4]
    addss xmm1,xmm0
    vmovaps xmm0,xmm1
.rrr_finish_next:
    inc ecx
    jmp .rrr_finish_loop
.rrr_done:
    add rsp,REDUCE_LEVELS*4+16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# worker_range(rsi=begin_chunk,rdx=end_chunk) -> xmm0 f32
worker_range:
FRC_worker_range
eval_chunk:
FRC_eval_chunk
field_eval_vec:
FRC_field_eval_vec
field_eval_vec_end:

# -----------------------------------------------------------------------------
# Vector helpers: AVX2/YMM, eight f32 lanes. Generated expression ValueFacts use
# the profile mapping YMM1/YMM2/YMM3/YMM12; YMM4 is the tail mask and YMM5 the
# hidden reduction accumulator. YMM6..11 are helper temporaries/reloadable
# residents, YMM13..14 are procedural-index state, and YMM15 is phase-local high
# scratch/gather-mask authority. No scalar lane fallback is permitted.

.global field_prepare_mask_f32
field_prepare_mask_f32:
field_prepare_q8:
    mov r8,rcx
    sub r8,rdx
    cmp r8,8
    jbe .fp8_rem_ok
    mov r8d,8
.fp8_rem_ok:
    lea r9,[rip+mask8_table]
    mov r10,r8
    shl r10,5
    vmovdqa ymm4,ymmword ptr [r9+r10]
    mov eax,edx
    vmovd xmm6,eax
    vpbroadcastd ymm6,xmm6
    vpaddd ymm6,ymm6,ymmword ptr [rip+lane8_dword]
    ret

# divmod eight non-negative dword lanes by positive scalar eax.
# input ymm6, quotient ymm8, remainder ymm9. scratch ymm10..12.
vec_divmod_u31_8:
    test eax,eax
    jz .bad_args
    mov r8d,eax
    vcvtsi2sd xmm10,xmm10,r8d
    vbroadcastsd ymm10,xmm10
    # low four lanes
    vcvtdq2pd ymm8,xmm6
    vdivpd ymm8,ymm8,ymm10
    vroundpd ymm8,ymm8,3
    vcvttpd2dq xmm8,ymm8
    # high four lanes
    vextracti128 xmm11,ymm6,1
    vcvtdq2pd ymm11,xmm11
    vdivpd ymm11,ymm11,ymm10
    vroundpd ymm11,ymm11,3
    vcvttpd2dq xmm11,ymm11
    vinserti128 ymm8,ymm8,xmm11,1
    # remainder = q - quotient*d
    mov eax,r8d
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    # The FP64 quotient is an estimate only. Perform an exact unsigned
    # one-step correction in integer SIMD so / and % remain exact across the
    # whole u31 carrier domain. AVX2 lacks unsigned dword compare, so xor the
    # sign bit and reuse signed vpcmpgtd.
    vpmulld ymm9,ymm8,ymm15            # product = quotient*d
    mov eax,0x80000000
    vmovd xmm10,eax
    vpbroadcastd ymm10,xmm10           # unsigned-compare bias
    vpxor ymm11,ymm9,ymm10
    vpxor ymm0,ymm6,ymm10
    vpcmpgtd ymm11,ymm11,ymm0          # mask: product > input unsigned
    mov eax,1
    vmovd xmm10,eax
    vpbroadcastd ymm10,xmm10           # vector one
    vpand ymm0,ymm11,ymm10
    vpsubd ymm8,ymm8,ymm0
    vpand ymm0,ymm11,ymm15
    vpsubd ymm9,ymm9,ymm0
    vpsubd ymm9,ymm6,ymm9              # remainder
    # mask: remainder >= divisor <=> remainder > divisor-1, unsigned
    vpsubd ymm11,ymm15,ymm10           # divisor - 1
    mov eax,0x80000000
    vmovd xmm0,eax
    vpbroadcastd ymm0,xmm0
    vpxor ymm11,ymm11,ymm0
    vpxor ymm10,ymm9,ymm0
    vpcmpgtd ymm11,ymm10,ymm11
    mov eax,1
    vmovd xmm10,eax
    vpbroadcastd ymm10,xmm10
    vpand ymm0,ymm11,ymm10
    vpaddd ymm8,ymm8,ymm0
    vpand ymm0,ymm11,ymm15
    vpsubd ymm9,ymm9,ymm0
    ret

# Two 8-lane u31 procedural-index carriers. YMM13/YMM14 are persistent only
# when the Physical DAG contains the corresponding integer authority; resident
# selection reserves them in that case.
.global field_iindex_0
field_iindex_0:
    call field_prepare_q8
    vmovdqa ymm13,ymm6
    ret
.global field_iindex_1
field_iindex_1:
    call field_prepare_q8
    vmovdqa ymm14,ymm6
    ret
.global field_iadd_const_0
field_iadd_const_0:
    vmovd xmm0,edi
    vpbroadcastd ymm0,xmm0
    vpaddd ymm13,ymm13,ymm0
    ret
.global field_iadd_const_1
field_iadd_const_1:
    vmovd xmm0,edi
    vpbroadcastd ymm0,xmm0
    vpaddd ymm14,ymm14,ymm0
    ret
.global field_isub_const_0
field_isub_const_0:
    vmovd xmm0,edi
    vpbroadcastd ymm0,xmm0
    vpsubd ymm13,ymm13,ymm0
    ret
.global field_isub_const_1
field_isub_const_1:
    vmovd xmm0,edi
    vpbroadcastd ymm0,xmm0
    vpsubd ymm14,ymm14,ymm0
    ret
.global field_imul_const_0
field_imul_const_0:
    vmovd xmm0,edi
    vpbroadcastd ymm0,xmm0
    vpmulld ymm13,ymm13,ymm0
    ret
.global field_imul_const_1
field_imul_const_1:
    vmovd xmm0,edi
    vpbroadcastd ymm0,xmm0
    vpmulld ymm14,ymm14,ymm0
    ret
.global field_idiv_const_0
field_idiv_const_0:
    test edi,edi
    jz .bad_args
    vmovdqa ymm6,ymm13
    mov eax,edi
    call vec_divmod_u31_8
    vmovdqa ymm13,ymm8
    ret
.global field_idiv_const_1
field_idiv_const_1:
    test edi,edi
    jz .bad_args
    vmovdqa ymm6,ymm14
    mov eax,edi
    call vec_divmod_u31_8
    vmovdqa ymm14,ymm8
    ret
.global field_imod_const_0
field_imod_const_0:
    test edi,edi
    jz .bad_args
    vmovdqa ymm6,ymm13
    mov eax,edi
    call vec_divmod_u31_8
    vmovdqa ymm13,ymm9
    ret
.global field_imod_const_1
field_imod_const_1:
    test edi,edi
    jz .bad_args
    vmovdqa ymm6,ymm14
    mov eax,edi
    call vec_divmod_u31_8
    vmovdqa ymm14,ymm9
    ret
.global field_itof32_0
field_itof32_0:
    vcvtdq2ps ymm0,ymm13
    ret
.global field_itof32_1
field_itof32_1:
    vcvtdq2ps ymm0,ymm14
    ret

# One runtime-rank AVX2 address relation. RankFact changes loop geometry, not ABI.
.global field_compute_offsets_f32
field_compute_offsets_f32:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d,edi
    mov r13d,esi
    mov r14,rdx
    call field_prepare_q8
    vpxor ymm7,ymm7,ymm7
    xor r15d,r15d
    cmp byte ptr [rip+g_shape_pow2],1
    je .Lfco8_dynamic_pow
.Lfco8_dynamic_gen:
    cmp r15d,dword ptr [rip+g_rank]
    jae .Lfco8_dynamic_done
    mov eax,r14d
    vmovd xmm6,eax
    vpbroadcastd ymm6,xmm6
    vpaddd ymm6,ymm6,ymmword ptr [rip+lane8_dword]
    mov r8,[rip+g_logical_strides_ptr]
    mov eax,[r8+r15*4]
    call vec_divmod_u31_8
    vmovdqa ymm6,ymm8
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+r15*4]
    call vec_divmod_u31_8
    vmovdqa ymm11,ymm9
    jmp .Lfco8_dynamic_realize
.Lfco8_dynamic_pow:
    cmp r15d,dword ptr [rip+g_rank]
    jae .Lfco8_dynamic_done
    mov eax,r14d
    vmovd xmm6,eax
    vpbroadcastd ymm6,xmm6
    vpaddd ymm6,ymm6,ymmword ptr [rip+lane8_dword]
    mov r8,[rip+g_stride_shifts_ptr]
    mov eax,[r8+r15*4]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpsrlvd ymm11,ymm6,ymm15
    mov r8,[rip+g_extent_masks_ptr]
    mov eax,[r8+r15*4]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpand ymm11,ymm11,ymm15
.Lfco8_dynamic_realize:
    mov r8,[rip+g_spec_delta_norm_ptr]
    mov r9,r13
    imul r9,qword ptr [rip+g_access_delta_stride]
    lea r9,[r9+r15*4]
    mov eax,[r8+r9]
    test eax,eax
    jz .Lfco8_dynamic_stride
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpaddd ymm11,ymm11,ymm15
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+r15*4]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpcmpgtd ymm10,ymm15,ymm11
    vpcmpeqd ymm9,ymm9,ymm9
    vpxor ymm10,ymm10,ymm9
    vpand ymm10,ymm10,ymm15
    vpsubd ymm11,ymm11,ymm10
.Lfco8_dynamic_stride:
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r12
    imul r9,qword ptr [rip+g_axis_bytes]
    lea r9,[r9+r15*4]
    mov eax,[r8+r9]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpmulld ymm11,ymm11,ymm15
    vpaddd ymm7,ymm7,ymm11
    inc r15d
    cmp byte ptr [rip+g_shape_pow2],1
    je .Lfco8_dynamic_pow
    jmp .Lfco8_dynamic_gen
.Lfco8_dynamic_done:
    mov rdx,r14
    call field_prepare_q8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.global field_load_f32
field_load_f32:
    push r12
    mov r12d,edi
    mov rax,[rip+g_field_contig_ptr]
    cmp byte ptr [rax+r12],1
    jne .Lfl8_dynamic_gather
    mov rax,[rip+g_spec_linear_delta_bytes_ptr]
    cmp qword ptr [rax+rsi*8],0
    jne .Lfl8_dynamic_gather
    call field_prepare_q8
    mov rax,[rip+g_field_data_ptr]
    mov rax,[rax+r12*8]
    lea rax,[rax+rdx*4]
    vmaskmovps ymm0,ymm4,ymmword ptr [rax]
    pop r12
    ret
.Lfl8_dynamic_gather:
    call field_compute_offsets_f32
    mov rax,[rip+g_field_data_ptr]
    mov rax,[rax+r12*8]
    vxorps ymm0,ymm0,ymm0
    vmovaps ymm15,ymm4
    vgatherdps ymm0,dword ptr [rax+ymm7],ymm15
    pop r12
    ret

.global field_store_f32
field_store_f32:
    push r12
    mov r12d,edi
    mov rax,[rip+g_field_contig_ptr]
    cmp byte ptr [rax+r12],1
    jne .fs8_reject
    call field_prepare_q8
    mov rax,[rip+g_field_data_ptr]
    mov rax,[rax+r12*8]
    lea rax,[rax+rdx*4]
    mov r11,[rip+field_mode_ptr]
    cmp byte ptr [r11+r12],FIELD_MODE_OUTPUT
    jne 1f
    cmp byte ptr [rip+g_nt_active],1
    jne 1f
    cmp r8,8
    jne 1f
    vmovntps ymmword ptr [rax],ymm0
    pop r12
    ret
1:
    vmaskmovps ymmword ptr [rax],ymm4,ymm0
    pop r12
    ret
.fs8_reject:
    jmp .bad_args

print_checksum_f32:
    # eax=f32 bits
    lea rdi,[rip+checksum_line+20]
    mov ecx,8
.pcf_hex:
    mov edx,eax
    shr edx,28
    and edx,15
    cmp edx,9
    jbe .pcf_digit
    add edx,'a'-10
    jmp .pcf_store
.pcf_digit:
    add edx,'0'
.pcf_store:
    mov byte ptr [rdi],dl
    inc rdi
    shl eax,4
    dec ecx
    jnz .pcf_hex
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+checksum_line]
    mov edx,29
    syscall
    ret

.section .rodata
.p2align 5
lane8_dword: .long 0,1,2,3,4,5,6,7
# Eight 32-bit sign masks for active lane counts 0..8.
mask8_table:
.long 0,0,0,0,0,0,0,0
.long -1,0,0,0,0,0,0,0
.long -1,-1,0,0,0,0,0,0
.long -1,-1,-1,0,0,0,0,0
.long -1,-1,-1,-1,0,0,0,0
.long -1,-1,-1,-1,-1,0,0,0
.long -1,-1,-1,-1,-1,-1,0,0
.long -1,-1,-1,-1,-1,-1,-1,0
.long -1,-1,-1,-1,-1,-1,-1,-1
checksum_line: .ascii "checksum_f32_bits=0x00000000\n"

.section .data
.p2align 6
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
.global field_chunk_work_ticks_patch
field_chunk_work_ticks_patch: .quad 1
.global field_chunk_elements_patch
field_chunk_elements_patch: .quad 16
.global field_count_patch
field_count_patch: .long 0
.global access_spec_count_patch
access_spec_count_patch: .long 1
.global field_metadata_va_patch
field_metadata_va_patch: .quad 0
.global field_fabric_datapath_va_patch
field_fabric_datapath_va_patch: .quad 0
.global field_fabric_datapath_bytes_patch
field_fabric_datapath_bytes_patch: .quad 0
.global field_fabric_activation_entry_patch
field_fabric_activation_entry_patch: .quad 0
.global field_fabric_activation_bridge_present_patch
field_fabric_activation_bridge_present_patch: .long 0
.global field_fabric_activation_abi_version_patch
field_fabric_activation_abi_version_patch: .long 1

.section .bss
.p2align 6
g_field_arena: .skip 8
g_field_arena_size: .skip 8
field_mode_ptr: .skip 8
access_delta_ptr: .skip 8
g_field_map_ptr: .skip 8
g_field_size_ptr: .skip 8
g_field_dev_ptr: .skip 8
g_field_ino_ptr: .skip 8
.global g_field_data_ptr
g_field_data_ptr: .skip 8
g_field_total_ptr: .skip 8
g_field_extents_ptr: .skip 8
g_field_strides_ptr: .skip 8
.global g_field_contig_ptr
g_field_contig_ptr: .skip 8
g_logical_strides_ptr: .skip 8
# Launch-time caretaker proof for division-free dynamic Rank-N coordinates.
g_stride_shifts_ptr: .skip 8
g_extent_masks_ptr: .skip 8
.global g_input_uniform_layout
g_shape_pow2: .skip 1
g_input_uniform_layout: .skip 1
.p2align 2
g_input_layout_ref: .skip 4
g_spec_delta_norm_ptr: .skip 8
# 1.3.4 Physical Regularity Collapse launch-time facts.
.global g_launch_direct_layout
g_launch_direct_layout: .skip 1
.p2align 2
g_regular_min_delta_ptr: .skip 8
g_regular_max_delta_ptr: .skip 8
.p2align 3
.global g_spec_linear_delta_bytes_ptr
g_spec_linear_delta_bytes_ptr: .skip 8
g_rank: .skip 8
g_axis_bytes: .skip 8
g_access_delta_stride: .skip 8
.p2align 3
g_total: .skip 8
# 1.3.3 immutable launch-time memory profitability facts.
g_llc_bytes: .skip 8
g_nt_threshold_bytes: .skip 8
g_nt_active: .skip 1
.p2align 3
g_chunks: .skip 8
.p2align 3
g_region_arena: .skip 8
g_region_arena_size: .skip 8
