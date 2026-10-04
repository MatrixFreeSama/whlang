.intel_syntax noprefix
.include "runtime/execution_admission_refresh_x86_64.inc"
.include "runtime/field_runtime_common_blocks.inc"
# Wheelchair 1.2.16 native materialized-field runtime, AVX-512 physicalization.
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
    cmp rax,16
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
    lea rax,[r15+15]
    cmp rax,r9
    jae .fre81_fail

    # Initial bound includes the last complete packet in this row and never
    # crosses the invocation end.  q is compared with this exclusive first-lane
    # bound by the generated direct loop.
    mov r14,r12
    sub r14,r15                         # row base
    add r14,r9                          # row end
    sub r14,15                   # first unsafe q after final full packet
    mov rax,r13
    sub rax,15
    cmp r14,rax
    cmova r14,rax

    # Cheapest proof first: one coordinate decode per axis proves the whole
    # neighborhood interior from its already-canonical min/max envelope.  This
    # is not an old compatibility backend; it is the shallowest proof in the
    # same RegionFact lattice.  Only a real periodic boundary descends into the
    # per-access piecewise-affine refinement below.
    mov ecx,dword ptr [rip+g_rank]
    dec ecx                              # start at innermost axis
    mov r11d,ecx                         # innermost axis identity
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
    add edi,15
.fre81_fast_pow2_ready:
    mov ecx,ebx
    jmp .fre81_fast_have_coord
.fre81_fast_exact_coord:
    cmp ecx,r11d
    jne .fre81_fast_outer_coord
    mov esi,r15d                         # c0
    lea edi,[r15+15]                     # c1 for vector lanes
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
    # Future packets in the row remain interior only until the largest positive
    # innermost displacement would make their final lane leave the extent.
    mov ecx,dword ptr [rip+g_rank]
    dec ecx
    mov rax,[rip+g_regular_max_delta_ptr]
    movsxd rax,dword ptr [rax+rcx*4]
    mov r8,r12
    sub r8,r15                           # row base
    mov rdx,[rip+g_field_extents_ptr]
    mov r9d,[rdx+rcx*4]
    add r8,r9                            # innermost extent
    sub r8,rax
    sub r8,15
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
    add edi,15
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
    sub ecx,15                   # first unsafe inner coordinate
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
    sub ecx,15
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
# Vector helpers used by generated code. Helpers preserve r12-r15 and use only
# ZMM16..31 as scratch, leaving generated expression registers ZMM0..15 sovereign.
# -----------------------------------------------------------------------------

# Build k1 active-lane mask for q in rdx, end in rcx; zmm16=q+[0..15].
.global field_prepare_mask_f32
field_prepare_mask_f32:
field_prepare_q16:
    mov r8,rcx
    sub r8,rdx
    cmp r8,16
    jbe .fpq_rem_ok
    mov r8d,16
.fpq_rem_ok:
    lea r9,[rip+mask16_table]
    movzx r10d,word ptr [r9+r8*2]
    kmovw k1,r10d
    mov eax,edx
    vpbroadcastd zmm16,eax
    vpaddd zmm16,zmm16,zmmword ptr [rip+lane16_dword]
    ret

# vec_divmod_u31(zmm input in zmm16, scalar positive divisor eax)
# -> quotient zmm18, remainder zmm19. Clobbers zmm20,zmm21 and r8/r9.
vec_divmod_u31:
    test eax,eax
    jz .bad_args
    mov r8d,eax
    vcvtsi2sd xmm20,xmm20,r8d
    vbroadcastsd zmm20,xmm20
    # low 8 dwords
    vcvtdq2pd zmm18,ymm16
    vdivpd zmm18,zmm18,zmm20
    vcvttpd2dq ymm18,zmm18
    # high 8 dwords
    vextracti64x4 ymm21,zmm16,1
    vcvtdq2pd zmm21,ymm21
    vdivpd zmm21,zmm21,zmm20
    vcvttpd2dq ymm21,zmm21
    vinserti64x4 zmm18,zmm18,ymm21,1
    vpbroadcastd zmm20,r8d
    # The FP64 division above is only a quotient estimate. Correct it with
    # exact unsigned integer arithmetic so division/modulo is exact for the
    # complete u31 carrier domain, including divisors close to 2^31 where a
    # rounded double quotient can otherwise land one integer too high/low.
    vpmulld zmm19,zmm18,zmm20          # product = q*d (mod 2^32; true domain <2^31)
    mov r9d,1
    vpbroadcastd zmm21,r9d
    vpcmpud k3,zmm19,zmm16,6          # product > input, unsigned
    vpsubd zmm18{k3},zmm18,zmm21
    vpsubd zmm19{k3},zmm19,zmm20
    vpsubd zmm19,zmm16,zmm19          # exact nonnegative remainder candidate
    vpcmpud k3,zmm19,zmm20,5          # remainder >= divisor, unsigned
    vpaddd zmm18{k3},zmm18,zmm21
    vpsubd zmm19{k3},zmm19,zmm20
    ret

# -----------------------------------------------------------------------------
# Rank-N coordinates are local facts inside field_compute_offsets_f32.  No
# persistent register bank owns a semantic axis count.
# -----------------------------------------------------------------------------
.global field_iindex_0
field_iindex_0:
    call field_prepare_q16
    vmovdqa32 zmm13,zmm16
    ret
.global field_iindex_1
field_iindex_1:
    call field_prepare_q16
    vmovdqa32 zmm14,zmm16
    ret
.global field_iadd_const_0
field_iadd_const_0:
    vpbroadcastd zmm15,edi
    vpaddd zmm13,zmm13,zmm15
    ret
.global field_iadd_const_1
field_iadd_const_1:
    vpbroadcastd zmm15,edi
    vpaddd zmm14,zmm14,zmm15
    ret
.global field_isub_const_0
field_isub_const_0:
    vpbroadcastd zmm15,edi
    vpsubd zmm13,zmm13,zmm15
    ret
.global field_isub_const_1
field_isub_const_1:
    vpbroadcastd zmm15,edi
    vpsubd zmm14,zmm14,zmm15
    ret
.global field_imul_const_0
field_imul_const_0:
    vpbroadcastd zmm15,edi
    vpmulld zmm13,zmm13,zmm15
    ret
.global field_imul_const_1
field_imul_const_1:
    vpbroadcastd zmm15,edi
    vpmulld zmm14,zmm14,zmm15
    ret
.global field_idiv_const_0
field_idiv_const_0:
    test edi,edi
    jz .bad_args
    vmovdqa32 zmm16,zmm13
    mov eax,edi
    call vec_divmod_u31
    vmovdqa32 zmm13,zmm18
    ret
.global field_idiv_const_1
field_idiv_const_1:
    test edi,edi
    jz .bad_args
    vmovdqa32 zmm16,zmm14
    mov eax,edi
    call vec_divmod_u31
    vmovdqa32 zmm14,zmm18
    ret
.global field_imod_const_0
field_imod_const_0:
    test edi,edi
    jz .bad_args
    vmovdqa32 zmm16,zmm13
    mov eax,edi
    call vec_divmod_u31
    vmovdqa32 zmm13,zmm19
    ret
.global field_imod_const_1
field_imod_const_1:
    test edi,edi
    jz .bad_args
    vmovdqa32 zmm16,zmm14
    mov eax,edi
    call vec_divmod_u31
    vmovdqa32 zmm14,zmm19
    ret
.global field_itof32_0
field_itof32_0:
    vcvtdq2ps zmm0,zmm13
    ret
.global field_itof32_1
field_itof32_1:
    vcvtdq2ps zmm0,zmm14
    ret

# -----------------------------------------------------------------------------
# One runtime-rank address relation. RankFact controls loop geometry; no r1..r8
# family, persistent-axis register contract, or rank selector survives.
# -----------------------------------------------------------------------------
.global field_compute_offsets_f32
field_compute_offsets_f32:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d,edi                         # field
    mov r13d,esi                         # access
    mov r14,rdx                          # q
    call field_prepare_q16
    vpxord zmm17,zmm17,zmm17
    xor r15d,r15d
    cmp byte ptr [rip+g_shape_pow2],1
    je .Lfco16_dynamic_pow
.Lfco16_dynamic_gen:
    cmp r15d,dword ptr [rip+g_rank]
    jae .Lfco16_dynamic_done
    # Restore q+[lane] for this axis.
    mov eax,r14d
    vpbroadcastd zmm16,eax
    vpaddd zmm16,zmm16,zmmword ptr [rip+lane16_dword]
    mov r8,[rip+g_logical_strides_ptr]
    mov eax,[r8+r15*4]
    call vec_divmod_u31
    vmovdqa32 zmm16,zmm18
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+r15*4]
    call vec_divmod_u31
    vmovdqa32 zmm22,zmm19
    jmp .Lfco16_dynamic_realize
.Lfco16_dynamic_pow:
    cmp r15d,dword ptr [rip+g_rank]
    jae .Lfco16_dynamic_done
    mov eax,r14d
    vpbroadcastd zmm16,eax
    vpaddd zmm16,zmm16,zmmword ptr [rip+lane16_dword]
    mov r8,[rip+g_stride_shifts_ptr]
    mov eax,[r8+r15*4]
    vpbroadcastd zmm23,eax
    vpsrlvd zmm22,zmm16,zmm23
    mov r8,[rip+g_extent_masks_ptr]
    mov eax,[r8+r15*4]
    vpbroadcastd zmm23,eax
    vpandd zmm22,zmm22,zmm23
.Lfco16_dynamic_realize:
    mov r8,[rip+g_spec_delta_norm_ptr]
    mov r9,r13
    imul r9,qword ptr [rip+g_access_delta_stride]
    lea r9,[r9+r15*4]
    mov eax,[r8+r9]
    test eax,eax
    jz .Lfco16_dynamic_stride
    vpbroadcastd zmm23,eax
    vpaddd zmm22,zmm22,zmm23
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+r15*4]
    vpbroadcastd zmm23,eax
    vpcmpd k2,zmm22,zmm23,5
    vpsubd zmm22{k2},zmm22,zmm23
.Lfco16_dynamic_stride:
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r12
    imul r9,qword ptr [rip+g_axis_bytes]
    lea r9,[r9+r15*4]
    mov eax,[r8+r9]
    vpbroadcastd zmm23,eax
    vpmulld zmm22,zmm22,zmm23
    vpaddd zmm17,zmm17,zmm22
    inc r15d
    cmp byte ptr [rip+g_shape_pow2],1
    je .Lfco16_dynamic_pow
    jmp .Lfco16_dynamic_gen
.Lfco16_dynamic_done:
    mov rdx,r14
    call field_prepare_q16                 # restore k1 and canonical q vector
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.global field_store_f32
field_store_f32:
    push r12
    mov r12d,edi
    mov rax,[rip+g_field_contig_ptr]
    cmp byte ptr [rax+r12],1
    jne .Lfs16_dynamic_scatter
    call field_prepare_q16
    mov rax,[rip+g_field_data_ptr]
    mov rax,[rax+r12*8]
    lea rax,[rax+rdx*4]
    mov r11,[rip+field_mode_ptr]
    cmp byte ptr [r11+r12],FIELD_MODE_OUTPUT
    jne 1f
    cmp byte ptr [rip+g_nt_active],1
    jne 1f
    cmp r8,16
    jne 1f
    vmovntps zmmword ptr [rax],zmm0
    pop r12
    ret
1:
    vmovups zmmword ptr [rax]{k1},zmm0
    pop r12
    ret
.Lfs16_dynamic_scatter:
    xor esi,esi
    call field_compute_offsets_f32
    mov rax,[rip+g_field_data_ptr]
    mov rax,[rax+r12*8]
    vscatterdps dword ptr [rax+zmm17]{k1},zmm0
    call field_prepare_q16
    pop r12
    ret

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
.p2align 6
lane16_dword:
    .long 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
mask16_table:
    .word 0x0000,0x0001,0x0003,0x0007,0x000f,0x001f,0x003f,0x007f
    .word 0x00ff,0x01ff,0x03ff,0x07ff,0x0fff,0x1fff,0x3fff,0x7fff,0xffff
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
