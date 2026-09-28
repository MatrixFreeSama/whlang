.intel_syntax noprefix
.include "runtime/execution_admission_refresh_x86_64.inc"
.include "compiler/field_runtime_capacity.inc"
.include "compiler/native256_physical_profile.inc"

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
.equ MAX_RANK,FIELD_RUNTIME_RANK_CAP
# Reduction frontier follows the qword chunk-index domain.
.equ REDUCE_LEVELS,64
.equ FIELD_HEADER_SIZE,256
.equ FIELD_MAGIC,0x363132444c464857  # "WHFLD216" little endian
.equ FIELD_VERSION,1
.equ FIELD_TYPE_F32,1
.equ FIELD_MODE_INPUT,0
.equ FIELD_MODE_OUTPUT,1
.equ FIELD_MODE_INOUT,2

# Header layout
.equ FH_MAGIC,0
.equ FH_VERSION,8
.equ FH_TYPE,12
.equ FH_RANK,16
.equ FH_FLAGS,20
.equ FH_DATA_OFF,24
.equ FH_EXTENTS,32
.equ FH_STRIDES,96
.equ FH_TOTAL,160

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
# properties of the compiled graph.  Rank remains the WHFLD216 file-format width.
field_prepare_instance_arenas:
    push rbx
    push r12
    push r13
    push r14
    mov ebx,dword ptr [rip+field_count_patch]
    mov r12d,dword ptr [rip+access_spec_count_patch]
    test ebx,ebx
    jz .fpia_fail
    test r12d,r12d
    jz .fpia_fail
    mov rax,qword ptr [rip+field_metadata_va_patch]
    test rax,rax
    jz .fpia_fail
    mov qword ptr [rip+field_mode_ptr],rax
    lea rcx,[rax+rbx]
    mov qword ptr [rip+field_rank_ptr],rcx
    lea rcx,[rcx+rbx]
    mov qword ptr [rip+access_delta_ptr],rcx

    mov r13,rbx
    imul r13,r13,113               # six qword + two rank-dword arrays + contig
    jo .fpia_fail
    mov rax,r12
    imul rax,rax,40                # normalized rank deltas + linear byte delta
    jo .fpia_fail
    add r13,rax
    jc .fpia_fail
    add r13,63
    jc .fpia_fail
    and r13,-64
    mov rsi,r13
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ|PROT_WRITE
    mov r10d,MAP_PRIVATE_ANON
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .fpia_fail
    mov qword ptr [rip+g_field_arena],rax
    mov qword ptr [rip+g_field_arena_size],r13
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
    mov qword ptr [rip+g_field_extents_ptr],r14
    mov rax,rbx; shl rax,5; add r14,rax
    mov qword ptr [rip+g_field_strides_ptr],r14
    add r14,rax
    mov qword ptr [rip+g_field_contig_ptr],r14
    add r14,rbx
    add r14,7; and r14,-8
    mov qword ptr [rip+g_spec_delta_norm_ptr],r14
    mov rax,r12; shl rax,5; add r14,rax
    mov qword ptr [rip+g_spec_linear_delta_bytes_ptr],r14
    xor eax,eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fpia_fail:
    mov eax,1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# map_one_field(rdi=path, edx=mode, ebx=index) -> eax=0/1
map_one_field:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,160
    mov r12d,ebx
    mov r13d,edx
    mov r14,rdi

    mov eax,SYS_openat
    mov edi,AT_FDCWD
    mov rsi,r14
    xor r10d,r10d
    cmp r13d,FIELD_MODE_INPUT
    je .mof_rd
    mov edx,O_RDWR
    jmp .mof_open
.mof_rd:
    mov edx,O_RDONLY
.mof_open:
    syscall
    test rax,rax
    js .mof_fail
    mov r15,rax

    mov eax,SYS_fstat
    mov rdi,r15
    mov rsi,rsp
    syscall
    test rax,rax
    js .mof_close_fail
    mov rax,[rsp+48]               # struct stat st_size on Linux x86-64
    cmp rax,FIELD_HEADER_SIZE
    jb .mof_close_fail
    mov rcx,[rip+g_field_size_ptr]
    mov [rcx+r12*8],rax

    # Native field alias contract: distinct field declarations are noalias.
    # Intentional read/write aliasing is represented by one MODE_INOUT field,
    # never by mapping the same underlying file through two declarations.
    # Compare (st_dev, st_ino) so hard links cannot bypass the contract.
    mov r8,[rsp+0]
    mov r9,[rsp+8]
    xor ecx,ecx
.mof_alias_scan:
    cmp ecx,r12d
    jae .mof_alias_store
    mov rax,[rip+g_field_dev_ptr]
    cmp [rax+rcx*8],r8
    jne .mof_alias_next
    mov rax,[rip+g_field_ino_ptr]
    cmp [rax+rcx*8],r9
    je .mof_close_fail
.mof_alias_next:
    inc ecx
    jmp .mof_alias_scan
.mof_alias_store:
    mov rax,[rip+g_field_dev_ptr]
    mov [rax+r12*8],r8
    mov rax,[rip+g_field_ino_ptr]
    mov [rax+r12*8],r9

    mov eax,SYS_mmap
    xor edi,edi
    mov rcx,[rip+g_field_size_ptr]
    mov rsi,[rcx+r12*8]
    mov edx,PROT_READ
    mov r10d,MAP_PRIVATE
    cmp r13d,FIELD_MODE_INPUT
    je .mof_map
    mov edx,PROT_READ|PROT_WRITE
    mov r10d,MAP_SHARED
.mof_map:
    mov r8,r15
    xor r9d,r9d
    syscall
    test rax,rax
    js .mof_close_fail
    mov rcx,[rip+g_field_map_ptr]
    mov [rcx+r12*8],rax
    mov r14,rax

    mov eax,SYS_close
    mov rdi,r15
    syscall

    mov rax,FIELD_MAGIC
    cmp qword ptr [r14+FH_MAGIC],rax
    jne .mof_unmap_fail
    cmp dword ptr [r14+FH_VERSION],FIELD_VERSION
    jne .mof_unmap_fail
    cmp dword ptr [r14+FH_TYPE],FIELD_TYPE_F32
    jne .mof_unmap_fail
    mov rax,[rip+field_rank_ptr]
    movzx ecx,byte ptr [rax+r12]
    cmp dword ptr [r14+FH_RANK],ecx
    jne .mof_unmap_fail
    test ecx,ecx
    jz .mof_unmap_fail
    cmp ecx,MAX_RANK
    ja .mof_unmap_fail
    mov rax,[r14+FH_DATA_OFF]
    cmp rax,FIELD_HEADER_SIZE
    jb .mof_unmap_fail
    mov rdx,[rip+g_field_size_ptr]
    cmp rax,[rdx+r12*8]
    jae .mof_unmap_fail
    lea rdx,[r14+rax]
    mov rax,[rip+g_field_data_ptr]
    mov [rax+r12*8],rdx

    # Validate logical product and physical span. Every extent must fit signed
    # dword coordinate arithmetic; every byte offset must stay below 2^31.
    mov r8,1                       # logical total
    xor r9d,r9d                    # axis
    xor r10,r10                    # max byte offset
.mof_axis:
    cmp r9d,ecx
    jae .mof_axes_done
    mov rax,[r14+FH_EXTENTS+r9*8]
    test rax,rax
    jz .mof_unmap_fail
    cmp rax,0x7fffffff
    ja .mof_unmap_fail
    mov rdx,r8
    imul rdx,rax
    jo .mof_unmap_fail
    cmp rdx,0x7fffffff
    ja .mof_unmap_fail
    mov r8,rdx
    mov r11,[r14+FH_STRIDES+r9*8]
    test r11,r11
    jz .mof_unmap_fail
    cmp r11,0x7fffffff
    ja .mof_unmap_fail
    dec rax
    imul rax,r11
    jo .mof_unmap_fail
    add r10,rax
    jo .mof_unmap_fail
    cmp r10,0x7ffffffb
    ja .mof_unmap_fail
    inc r9d
    jmp .mof_axis
.mof_axes_done:
    cmp qword ptr [r14+FH_TOTAL],r8
    jne .mof_unmap_fail
    mov rax,[r14+FH_DATA_OFF]
    add rax,r10
    add rax,4
    mov rdx,[rip+g_field_size_ptr]
    cmp rax,[rdx+r12*8]
    ja .mof_unmap_fail

    # Copy extents and strides into hot compact tables. First field establishes
    # the logical domain; every subsequent field must share logical extents but
    # may have an arbitrary valid physical stride layout.
    xor r9d,r9d
.mof_copy_axis:
    cmp r9d,ecx
    jae .mof_copy_done
    mov rax,[r14+FH_EXTENTS+r9*8]
    mov edx,eax
    mov rax,[rip+g_field_extents_ptr]
    mov r11,r12
    shl r11,5
    lea r11,[r11+r9*4]
    mov [rax+r11],edx
    mov rax,[r14+FH_STRIDES+r9*8]
    mov edx,eax
    mov rax,[rip+g_field_strides_ptr]
    mov r11,r12
    shl r11,5
    lea r11,[r11+r9*4]
    mov [rax+r11],edx
    inc r9d
    jmp .mof_copy_axis
.mof_copy_done:
    mov rax,[rip+g_field_total_ptr]
    mov [rax+r12*8],r8

    # 1.3.2 Physical Memory Causality: every mutable affine field must prove
    # logical-coordinate -> physical-byte injectivity before any executor may
    # run. Read-only fields may intentionally self-alias (broadcast/views).
    # The proof sorts non-trivial axes by positive byte stride and requires
    # each next axis stride to start at or beyond the complete lower-axis span.
    # This admits contiguous, transposed, and padded layouts without enumerating
    # elements; an exotic mutable layout that cannot be proven is rejected.
    cmp r13d,FIELD_MODE_INPUT
    je .mof_injective_done
    mov edi,r12d
    mov esi,ecx
    call validate_mutable_injective
    test eax,eax
    jnz .mof_unmap_fail
.mof_injective_done:

    # Contiguous row-major classification is launch-time metadata only.
    mov rax,[rip+g_field_contig_ptr]
    mov byte ptr [rax+r12],1
    mov r11d,4
    mov r9d,ecx
.mof_contig_loop:
    test r9d,r9d
    jz .mof_ok
    dec r9d
    mov rax,[rip+g_field_strides_ptr]
    mov rdx,r12
    shl rdx,5
    lea rdx,[rdx+r9*4]
    mov eax,[rax+rdx]
    cmp eax,r11d
    jne .mof_not_contig
    mov rax,[rip+g_field_extents_ptr]
    mov rdx,r12
    shl rdx,5
    lea rdx,[rdx+r9*4]
    mov eax,[rax+rdx]
    imul r11d,eax
    jo .mof_not_contig
    jmp .mof_contig_loop
.mof_not_contig:
    mov rax,[rip+g_field_contig_ptr]
    mov byte ptr [rax+r12],0
.mof_ok:
    xor eax,eax
    jmp .mof_done
.mof_unmap_fail:
    mov rax,[rip+g_field_map_ptr]
    mov rdi,[rax+r12*8]
    mov rax,[rip+g_field_size_ptr]
    mov rsi,[rax+r12*8]
    mov eax,SYS_munmap
    syscall
    mov rax,[rip+g_field_map_ptr]
    mov qword ptr [rax+r12*8],0
    mov eax,1
    jmp .mof_done
.mof_close_fail:
    mov eax,SYS_close
    mov rdi,r15
    syscall
.mof_fail:
    mov eax,1
.mof_done:
    add rsp,160
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# validate_mutable_injective(edi=field index, esi=rank) -> eax 0/1
# Cold launch-time sufficient proof for positive affine f32 layouts.
# A selected-axis mask lives entirely in registers; no global ownership table
# or runtime memory coordinator is introduced.
validate_mutable_injective:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d,edi                    # field
    mov r13d,esi                    # rank
    xor r14d,r14d                   # selected/trivial axis mask
    mov r15,4                       # occupied byte span of lower axes
.vmi_mark_trivial:
    xor ebx,ebx
.vmi_mark_loop:
    cmp ebx,r13d
    jae .vmi_select
    mov r8,[rip+g_field_extents_ptr]
    mov rax,r12
    shl rax,5
    lea rax,[rax+rbx*4]
    cmp dword ptr [r8+rax],1
    jne .vmi_mark_next
    bts r14d,ebx
.vmi_mark_next:
    inc ebx
    jmp .vmi_mark_loop

.vmi_select:
    mov r10d,-1                    # best axis
    mov r11d,0x7fffffff            # best stride
    xor ebx,ebx
.vmi_find:
    cmp ebx,r13d
    jae .vmi_found
    bt r14d,ebx
    jc .vmi_find_next
    mov r8,[rip+g_field_strides_ptr]
    mov rax,r12
    shl rax,5
    lea rax,[rax+rbx*4]
    mov eax,dword ptr [r8+rax]
    cmp eax,r11d
    jae .vmi_find_next
    mov r11d,eax
    mov r10d,ebx
.vmi_find_next:
    inc ebx
    jmp .vmi_find

.vmi_found:
    cmp r10d,-1
    je .vmi_ok                      # all non-trivial axes proven
    mov eax,r11d
    cmp rax,r15
    jb .vmi_fail                    # next writable axis overlaps lower span
    # span += (extent-1)*stride. Existing descriptor span validation proves
    # this remains in the signed 31-bit physical-offset domain.
    mov r8,[rip+g_field_extents_ptr]
    mov rdx,r12
    shl rdx,5
    lea rdx,[rdx+r10*4]
    mov edx,dword ptr [r8+rdx]
    dec edx
    imul rdx,rax
    add r15,rdx
    bts r14d,r10d
    jmp .vmi_select

.vmi_ok:
    xor eax,eax
    jmp .vmi_done
.vmi_fail:
    mov eax,1
.vmi_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Establish shared logical extents and row-major logical strides.
finalize_shape:
    push rbx
    push r12
    mov rax,[rip+field_rank_ptr]
    movzx ecx,byte ptr [rax]
    mov [rip+g_rank],ecx
    mov rax,[rip+g_field_total_ptr]
    mov rax,[rax]
    test rax,rax
    jz .fs_fail
    mov [rip+g_total],rax
    # extents of all fields must match first field for the 1.2.16 native field
    # domain. Physical strides/layout are intentionally independent.
    mov ebx,1
.fs_field_loop:
    cmp ebx,dword ptr [rip+field_count_patch]
    jae .fs_strides
    mov rdx,[rip+field_rank_ptr]
    cmp byte ptr [rdx+rbx],cl
    jne .fs_fail
    mov rdx,[rip+g_field_total_ptr]
    cmp [rdx+rbx*8],rax
    jne .fs_fail
    xor edx,edx
.fs_cmp_axis:
    cmp edx,ecx
    jae .fs_next_field
    mov r9,[rip+g_field_extents_ptr]
    mov r8d,[r9+rdx*4]
    mov r9,[rip+g_field_extents_ptr]
    mov r10,rbx
    shl r10,5
    lea r10,[r10+rdx*4]
    cmp r8d,[r9+r10]
    jne .fs_fail
    inc edx
    jmp .fs_cmp_axis
.fs_next_field:
    inc ebx
    jmp .fs_field_loop

.fs_strides:
    # logical stride[last]=1, moving left multiplies extents. dword domain proven.
    mov eax,1
    mov edx,ecx
.fs_stride_loop:
    test edx,edx
    jz .fs_chunks
    dec edx
    lea r8,[rip+g_logical_strides]
    mov [r8+rdx*4],eax
    mov r8,[rip+g_field_extents_ptr]
    imul eax,[r8+rdx*4]
    jo .fs_fail
    jmp .fs_stride_loop
.fs_chunks:
    # 1.2.17 caretaker proof: dynamic logical shape may change every launch,
    # but if every extent (and therefore every logical stride) is a power of
    # two, Rank-N coordinate recovery needs no vector division.  Prove once at
    # launch and retain per-axis masks/shifts for the hot locality path.
    mov byte ptr [rip+g_shape_pow2],1
    xor edx,edx
.fs_pow2_axis:
    cmp edx,ecx
    jae .fs_pow2_done
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+rdx*4]
    test eax,eax
    jz .fs_pow2_no
    mov r9d,eax
    dec r9d
    test eax,r9d
    jnz .fs_pow2_no
    lea r8,[rip+g_extent_masks]
    mov [r8+rdx*4],r9d
    lea r8,[rip+g_logical_strides]
    mov eax,[r8+rdx*4]
    test eax,eax
    jz .fs_pow2_no
    mov r9d,eax
    dec r9d
    test eax,r9d
    jnz .fs_pow2_no
    bsf eax,eax
    lea r8,[rip+g_stride_shifts]
    mov [r8+rdx*4],eax
    inc edx
    jmp .fs_pow2_axis
.fs_pow2_no:
    mov byte ptr [rip+g_shape_pow2],0
.fs_pow2_done:
    # Input-field layout equivalence proof for coordinate CSE.  Logical shape is
    # already common; here we prove byte strides only. Mutable/output fields do
    # not participate in immutable load residency.
    mov byte ptr [rip+g_input_uniform_layout],0
    mov dword ptr [rip+g_input_layout_ref],-1
    xor ebx,ebx
.fs_uniform_find:
    cmp ebx,dword ptr [rip+field_count_patch]
    jae .fs_uniform_done
    mov r8,[rip+field_mode_ptr]
    cmp byte ptr [r8+rbx],FIELD_MODE_INPUT
    jne .fs_uniform_find_next
    cmp dword ptr [rip+g_input_layout_ref],-1
    jne .fs_uniform_compare
    mov [rip+g_input_layout_ref],ebx
    mov byte ptr [rip+g_input_uniform_layout],1
    jmp .fs_uniform_find_next
.fs_uniform_compare:
    mov r10d,dword ptr [rip+g_input_layout_ref]
    xor edx,edx
.fs_uniform_axis:
    cmp edx,ecx
    jae .fs_uniform_find_next
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r10; shl r9,5; lea r9,[r9+rdx*4]
    mov eax,[r8+r9]
    mov r9,rbx; shl r9,5; lea r9,[r9+rdx*4]
    cmp eax,[r8+r9]
    jne .fs_uniform_no
    inc edx
    jmp .fs_uniform_axis
.fs_uniform_no:
    mov byte ptr [rip+g_input_uniform_layout],0
    jmp .fs_uniform_done
.fs_uniform_find_next:
    inc ebx
    jmp .fs_uniform_find
.fs_uniform_done:
    # 1.3.4 regular-neighborhood eligibility. Every immutable input must be
    # proven contiguous row-major. If not, only the existing general path is
    # available; no layout conversion or temporary transpose is introduced.
    mov byte ptr [rip+g_launch_direct_layout],0
    cmp dword ptr [rip+g_input_layout_ref],-1
    je .fs_regular_done
    mov byte ptr [rip+g_launch_direct_layout],1
    xor ebx,ebx
.fs_regular_scan:
    cmp ebx,dword ptr [rip+field_count_patch]
    jae .fs_regular_done
    mov r8,[rip+field_mode_ptr]
    cmp byte ptr [r8+rbx],FIELD_MODE_INPUT
    jne .fs_regular_next
    mov r8,[rip+g_field_contig_ptr]
    cmp byte ptr [r8+rbx],1
    je .fs_regular_next
    mov byte ptr [rip+g_launch_direct_layout],0
    jmp .fs_regular_done
.fs_regular_next:
    inc ebx
    jmp .fs_regular_scan
.fs_regular_done:
    call field_derive_launch_leaf_geometry
    test eax,eax
    jnz .fs_fail
    mov rax,[rip+g_total]
    mov rcx,qword ptr [rip+field_chunk_elements_patch]
    test rcx,rcx
    jz .fs_fail
    xor edx,edx
    div rcx
    test rdx,rdx
    jz .fs_chunks_exact
    inc rax
.fs_chunks_exact:
    test rax,rax
    jz .fs_fail
    mov [rip+g_chunks],rax
    xor eax,eax
    jmp .fs_done
.fs_fail:
    mov eax,1
.fs_done:
    pop r12
    pop rbx
    ret


# Cold launch-time Physical Reality leaf derivation for materialized fields.
# AOT publishes one cache-line ownership quantum and its necessary work price.
# Runtime logical extent N is now known. Expose the largest profitable integer
# width bounded by exact external execution admission and real structural work.
# No binary executor geometry, fixed chunk threshold, workload name, or runtime
# free-worker state exists.
field_derive_launch_leaf_geometry:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,qword ptr [rip+field_chunk_elements_patch]
    mov r13,qword ptr [rip+field_chunk_work_ticks_patch]
    test r12,r12
    jz .fdllg_fail
    test r13,r13
    jz .fdllg_fail

    # total_quanta = ceil(total logical elements / structural quantum)
    mov rax,qword ptr [rip+g_total]
    xor edx,edx
    div r12
    mov r14,rax
    test rdx,rdx
    jz .fdllg_total_ready
    inc r14
.fdllg_total_ready:
    test r14,r14
    jz .fdllg_fail

    # Exact external admission, never rounded to a binary executor count.
    mov r15d,dword ptr [rip+execution_admission_patch]
    test r15d,r15d
    jnz .fdllg_have_admission
    mov r15d,1
.fdllg_have_admission:
    cmp r15,r14
    jbe .fdllg_profit_bound
    mov r15,r14

.fdllg_profit_bound:
    cmp r15,1
    jbe .fdllg_leaf_quanta
    mov rax,qword ptr [rip+outward_materialization_ticks_patch]
    xor edx,edx
    div r13
    inc rax
    mov rcx,rax
    cmp rcx,1
    jbe .fdllg_leaf_quanta
    cmp r14,rcx
    jae .fdllg_max_profitable
    mov r15,1
    jmp .fdllg_leaf_quanta

.fdllg_max_profitable:
    mov rax,r14
    dec rax
    mov rbx,rcx
    dec rbx
    xor edx,edx
    div rbx
    test rax,rax
    jnz .fdllg_cap_profit
    mov rax,1
.fdllg_cap_profit:
    cmp r15,rax
    jbe .fdllg_leaf_quanta
    mov r15,rax

.fdllg_leaf_quanta:
    mov rax,r14
    xor edx,edx
    div r15
    mov rbx,rax
    test rdx,rdx
    jz .fdllg_accept
    inc rbx

.fdllg_accept:
    mov rax,rbx
    mul r12
    test rdx,rdx
    jnz .fdllg_fail
    test rax,rax
    jz .fdllg_fail
    mov qword ptr [rip+field_chunk_elements_patch],rax
    mov rax,rbx
    mul r13
    test rdx,rdx
    jz .fdllg_store_work
    mov rax,0x7fffffffffffffff
.fdllg_store_work:
    mov qword ptr [rip+field_chunk_work_ticks_patch],rax
    xor eax,eax
    jmp .fdllg_done
.fdllg_fail:
    mov eax,1
.fdllg_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Writable-cache-line ownership proof for any Field invocation whose capacity
# ceiling permits more than one causal region to become active. Hardware width does
# not demand parallelism; when activation occurs, every mutable field must prove that
# the AOT leaf grain is also a physical 64-byte ownership boundary. Read-only
# strided/broadcast inputs do not participate. Unprovable writable geometry is
# rejected rather than silently serialized or allowed to false-share.
validate_parallel_mutable_geometry:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword ptr [rip+g_chunks],1
    jbe .vpmg_ok
    mov rax,qword ptr [rip+field_chunk_elements_patch]
    test rax,15                    # 16 f32 = one 64-byte ownership quantum
    jnz .vpmg_fail
    xor ebx,ebx
.vpmg_field:
    cmp ebx,dword ptr [rip+field_count_patch]
    jae .vpmg_ok
    mov r8,[rip+field_mode_ptr]
    cmp byte ptr [r8+rbx],FIELD_MODE_INPUT
    je .vpmg_next
    # Physical data base itself must be cache-line aligned.
    mov r8,[rip+g_field_data_ptr]
    mov rax,[r8+rbx*8]
    test rax,63
    jnz .vpmg_fail
    movzx r12d,byte ptr [rip+g_rank]
    test r12d,r12d
    jz .vpmg_fail
    mov r13d,r12d
    dec r13d                        # logical innermost axis
    mov r14,rbx
    shl r14,5
    # The innermost logical axis must be the physical f32 stream so a logical
    # The AOT leaf grain is proven in whole 64-byte f32 ownership quanta.
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r14
    lea r9,[r9+r13*4]
    mov eax,dword ptr [r8+r9]
    cmp eax,4
    jne .vpmg_fail
    mov r8,[rip+g_field_extents_ptr]
    mov r9,r14
    lea r9,[r9+r13*4]
    mov eax,dword ptr [r8+r9]
    test eax,15
    jnz .vpmg_fail
    imul rax,rax,4
    mov r15,rax                     # physical span of inner logical block
    test r13d,r13d
    jz .vpmg_next
.vpmg_axis:
    dec r13d
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r14
    lea r9,[r9+r13*4]
    mov eax,dword ptr [r8+r9]
    test eax,63
    jnz .vpmg_fail
    cmp rax,r15
    jb .vpmg_fail
    mov r8,[rip+g_field_extents_ptr]
    mov r9,r14
    lea r9,[r9+r13*4]
    mov edx,dword ptr [r8+r9]
    dec edx
    imul rdx,rax
    add r15,rdx
    test r13d,r13d
    jnz .vpmg_axis
.vpmg_next:
    inc ebx
    jmp .vpmg_field
.vpmg_ok:
    xor eax,eax
    jmp .vpmg_done
.vpmg_fail:
    mov eax,1
.vpmg_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Normalize compile-time signed neighborhood deltas into each runtime axis ring.
# 1.3.4 also derives a shortest signed periodic delta, one contiguous-row-major
# byte displacement per access, and the global neighborhood interior envelope.
# These are launch-time facts only; no runtime lookup table or benchmark dispatch
# participates in the generated arithmetic.
normalize_specs:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rdi,[rip+g_regular_min_delta]
    xor eax,eax
    mov ecx,MAX_RANK
    rep stosd
    lea rdi,[rip+g_regular_max_delta]
    xor eax,eax
    mov ecx,MAX_RANK
    rep stosd
    mov rdi,[rip+g_spec_linear_delta_bytes_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+access_spec_count_patch]
    shl ecx,1
    rep stosd
    xor ebx,ebx
.ns_spec:
    cmp ebx,dword ptr [rip+access_spec_count_patch]
    jae .ns_ok
    movzx r12d,byte ptr [rip+g_rank]
    xor r13d,r13d
    xor r15d,r15d                  # signed logical-element displacement
.ns_axis:
    cmp r13d,r12d
    jae .ns_next
    mov rdx,[rip+access_delta_ptr]
    mov rcx,rbx
    shl rcx,5
    lea rcx,[rcx+r13*4]
    movsxd rax,dword ptr [rdx+rcx]
    mov rdx,[rip+g_field_extents_ptr]
    mov ecx,[rdx+r13*4]
    test ecx,ecx
    jz .ns_fail
    # Signed remainder first.  Canonicalize to the shortest periodic
    # representative so e.g. +63 on extent 64 becomes -1.  This maximizes the
    # provable interior without changing periodic semantics.
    cqo
    idiv rcx
    mov r14,rdx
    mov rax,rcx
    shr rax,1
    cmp r14,rax
    jle .ns_check_negative_short
    sub r14,rcx
.ns_check_negative_short:
    mov rax,rcx
    shr rax,1
    neg rax
    cmp r14,rax
    jge .ns_short_ready
    add r14,rcx
.ns_short_ready:
    # Positive normalized ring delta remains the authority used by the fully
    # general gather path.
    mov rax,r14
    test rax,rax
    jns .ns_norm_ready
    add rax,rcx
.ns_norm_ready:
    mov rdx,[rip+g_spec_delta_norm_ptr]
    mov rcx,rbx
    shl rcx,5
    lea rcx,[rcx+r13*4]
    mov [rdx+rcx],eax

    # Global minimum/maximum signed delta per axis defines one kernel-wide
    # interior domain.  It is intentionally conservative and workload-name blind.
    lea rdx,[rip+g_regular_min_delta]
    mov eax,[rdx+r13*4]
    cmp r14d,eax
    jge .ns_min_done
    mov [rdx+r13*4],r14d
.ns_min_done:
    lea rdx,[rip+g_regular_max_delta]
    mov eax,[rdx+r13*4]
    cmp r14d,eax
    jle .ns_max_done
    mov [rdx+r13*4],r14d
.ns_max_done:

    # Contiguous row-major physical displacement in elements.  This is used
    # only after a launch-time contiguous-layout proof and an episode interior
    # proof; the general gather authority remains available otherwise.
    lea rdx,[rip+g_logical_strides]
    movsxd rax,dword ptr [rdx+r13*4]
    imul rax,r14
    add r15,rax
    inc r13d
    jmp .ns_axis
.ns_next:
    mov rax,r15
    shl rax,2                       # f32 byte displacement
    mov rdx,[rip+g_spec_linear_delta_bytes_ptr]
    mov [rdx+rbx*8],rax
    inc ebx
    jmp .ns_spec
.ns_ok:
    xor eax,eax
    jmp .ns_done
.ns_fail:
    mov eax,1
.ns_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# field_regular_run_end(rdi=execution-local delta arena, rdx=q, rcx=end) -> rax exclusive direct-region end, or 0.
# 1.3.81 Piecewise-Affine RegionFact.  Periodicity is not random access.  For
# each access and axis, the cold region transition proves one constant wrap class
# (negative-wrap / interior / positive-wrap), folds that wrap into the ordinary
# signed physical displacement, and publishes the resulting per-access linear
# delta through the already-existing AddressFact arena.  The returned run is the
# maximal conservative interval in the current innermost row for which every
# active vector lane preserves those affine classes.  Only an episode that truly
# straddles one of the affine boundaries returns 0 and uses generic gather.
# There is no pow2 compatibility path, stencil matcher, fixed extent threshold,
# per-element table, or runtime policy manager.
.global field_regular_run_end
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
    movzx ebx,byte ptr [rip+g_rank]
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
    lea r8,[rip+g_extent_masks]
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
    movzx ecx,byte ptr [rip+g_rank]
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
    lea rax,[rip+g_stride_shifts]
    mov ecx,[rax+rbx*4]
    mov rax,r12
    shr rax,cl
    lea rdx,[rip+g_extent_masks]
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
    lea rax,[rip+g_regular_min_delta]
    mov edx,[rax+rcx*4]
    mov eax,esi
    add eax,edx
    js .fre81_fast_boundary
    lea rax,[rip+g_regular_max_delta]
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
    movzx ecx,byte ptr [rip+g_rank]
    dec ecx
    lea rax,[rip+g_regular_max_delta]
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
    movzx eax,byte ptr [rip+g_rank]
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
    lea r8,[rip+g_logical_strides]
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
    movzx eax,byte ptr [rip+g_rank]
    dec eax
    cmp r10d,eax
    jne .fre81_coord_ready
    add edi,7
.fre81_coord_ready:

    # Recover the canonical shortest signed periodic delta from the already-old
    # positive ring delta authority.
    mov r8,[rip+g_spec_delta_norm_ptr]
    mov rax,rbx
    shl rax,5
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
    movzx ecx,byte ptr [rip+g_rank]
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
    movzx ecx,byte ptr [rip+g_rank]
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
    lea r8,[rip+g_logical_strides]
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
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,8388608                 # conservative fallback: 8 MiB
    xor r13d,r13d
    xor eax,eax
    cpuid
    mov r15d,eax
    cmp r15d,4
    jb .fimp_cache_done
.fimp_cache_loop:
    mov eax,4
    mov ecx,r13d
    cpuid
    mov edx,eax
    and edx,31
    jz .fimp_cache_done
    mov r8d,ebx
    and r8d,0x0fff
    inc r8d                         # line bytes
    mov r9d,ebx
    shr r9d,12
    and r9d,0x03ff
    inc r9d                         # partitions
    mov r10d,ebx
    shr r10d,22
    and r10d,0x03ff
    inc r10d                        # ways
    mov r11d,ecx
    inc r11d                        # sets
    mov eax,r8d
    imul rax,r9
    imul rax,r10
    imul rax,r11
    cmp rax,r12
    cmova r12,rax
    inc r13d
    cmp r13d,32
    jb .fimp_cache_loop
.fimp_cache_done:
    mov [rip+g_llc_bytes],r12
    mov r14,r12
    shl r14,1                       # base threshold = 2x largest cache
    cmp r14,8388608
    jae .fimp_scan_inputs
    mov r14,8388608
.fimp_scan_inputs:
    mov byte ptr [rip+g_random_read_pressure],0
    xor ecx,ecx
.fimp_input_loop:
    cmp ecx,dword ptr [rip+field_count_patch]
    jae .fimp_threshold_ready
    mov rax,[rip+field_mode_ptr]
    cmp byte ptr [rax+rcx],FIELD_MODE_INPUT
    jne .fimp_input_next
    mov rax,[rip+g_field_contig_ptr]
    cmp byte ptr [rax+rcx],1
    je .fimp_input_next
    mov byte ptr [rip+g_random_read_pressure],1
    shl r14,1                       # random gather pressure => 4x cache
    jmp .fimp_threshold_ready
.fimp_input_next:
    inc ecx
    jmp .fimp_input_loop
.fimp_threshold_ready:
    mov [rip+g_nt_threshold_bytes],r14
    mov byte ptr [rip+g_nt_active],0
    mov rax,[rip+g_total]
    shl rax,2                       # f32 physical output bytes
    cmp rax,r14
    jb .fimp_done
    xor ecx,ecx
.fimp_output_loop:
    cmp ecx,dword ptr [rip+field_count_patch]
    jae .fimp_done
    mov rax,[rip+field_mode_ptr]
    cmp byte ptr [rax+rcx],FIELD_MODE_OUTPUT
    jne .fimp_output_next
    mov rax,[rip+g_field_contig_ptr]
    cmp byte ptr [rax+rcx],1
    jne .fimp_output_next
    mov byte ptr [rip+g_nt_active],1
    jmp .fimp_done
.fimp_output_next:
    inc ecx
    jmp .fimp_output_loop
.fimp_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# -----------------------------------------------------------------------------
# Wheelchair 1.3.72 Ownership-Local Execution Aging
# -----------------------------------------------------------------------------
# Cold Physical Reality has already derived the profitable leaf geometry before
# this entry.  Runtime therefore does not re-own the causal tree or repeat a
# subtree profitability decision.  The launch frontier only exposes disjoint
# ownership regions.  Once an execution reaches one region, launch structure is
# dead: the hot path sees only [chunk_lo,chunk_hi), worker_range and its result
# slot.  Descendants use CLONE_PARENT so every outward execution is directly
# reapable by the invocation root; no recursive join tree survives.
#
# run_region_frontier(rsi=chunk_lo,rdx=chunk_hi,edi=root_flag) -> xmm0 f32
# Root entry is [0,g_chunks), root_flag=1.  Non-root executions never return.
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
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,REDUCE_LEVELS*4+16
    mov r13,rsi
    mov r14,rdx
    xor r15d,r15d
.w_chunk:
    cmp r13,r14
    jae .w_finish
    mov rdi,r13
    call eval_chunk
    xor ecx,ecx
.w_carry:
    bt r15,rcx
    jnc .w_store
    movss xmm1,dword ptr [rsp+rcx*4]
    addss xmm1,xmm0
    vmovaps xmm0,xmm1
    btr r15,rcx
    inc ecx
    cmp ecx,REDUCE_LEVELS
    jb .w_carry
    jmp .bad_args
.w_store:
    movss dword ptr [rsp+rcx*4],xmm0
    bts r15,rcx
    inc r13
    jmp .w_chunk
.w_finish:
    xor ecx,ecx
    xor edx,edx
    vxorps xmm0,xmm0,xmm0
.w_fin_loop:
    cmp ecx,REDUCE_LEVELS
    jae .w_done
    bt r15,rcx
    jnc .w_fin_next
    test edx,edx
    jnz .w_merge
    movss xmm0,dword ptr [rsp+rcx*4]
    mov edx,1
    jmp .w_fin_next
.w_merge:
    movss xmm1,dword ptr [rsp+rcx*4]
    addss xmm1,xmm0
    vmovaps xmm0,xmm1
.w_fin_next:
    inc ecx
    jmp .w_fin_loop
.w_done:
    cmp byte ptr [rip+g_nt_active],0
    je 1f
    sfence
1:  vzeroupper
    add rsp,REDUCE_LEVELS*4+16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# eval_chunk(rdi=chunk token) -> xmm0 f32. Generated kernel owns vector loop.
eval_chunk:
    push r12
    push r13
    mov rax,rdi
    mul qword ptr [rip+field_chunk_elements_patch]
    test rdx,rdx
    jnz .bad_args
    mov r12,rax
    mov r13,qword ptr [rip+field_chunk_elements_patch]
    add r13,r12
    jc .bad_args
    cmp r13,[rip+g_total]
    cmova r13,[rip+g_total]
    mov rdi,r12
    mov rsi,r13
    xor edx,edx
    movzx eax,byte ptr [rip+g_launch_direct_layout]
    or edx,eax
    movzx eax,byte ptr [rip+g_input_uniform_layout]
    shl eax,1
    or edx,eax
    movzx eax,byte ptr [rip+g_nt_active]
    shl eax,2
    or edx,eax
    call field_eval_vec
    pop r13
    pop r12
    ret

# Direct AOT jump stub.
.p2align 4
.global field_eval_vec
field_eval_vec:
    .byte 0xE9
.global field_eval_vec_disp_patch
field_eval_vec_disp_patch: .long 0
.global field_eval_vec_end
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

# 1.3.82 common CoordinateFact symbol authority. Native256 has only sixteen
# architectural vector registers, so the persistent Rank-N carrier realization
# is not profitable/representable without stealing live ValueFacts. These entry
# points retain the existing exact helper semantics and are not selected by the
# Native256 compiler path.
.macro DEFINE_COORD256_ALIAS rank
.global field_prepare_coords_f32_r\rank
field_prepare_coords_f32_r\rank:
    jmp field_prepare_mask_f32
.global field_compute_offsets_from_coords_f32_r\rank
field_compute_offsets_from_coords_f32_r\rank:
    jmp field_compute_offsets_f32_r\rank
.endm
DEFINE_COORD256_ALIAS 1
DEFINE_COORD256_ALIAS 2
DEFINE_COORD256_ALIAS 3
DEFINE_COORD256_ALIAS 4
DEFINE_COORD256_ALIAS 5
DEFINE_COORD256_ALIAS 6
DEFINE_COORD256_ALIAS 7
DEFINE_COORD256_ALIAS 8

# 1.3.82 common coordinate-induction symbol authority; Native256 does not
# select these because its vector carrier bank has no eight-register coordinate
# domain independent of live ValueFacts.
.macro DEFINE_ADV_COORD256_ALIAS rank
.global field_advance_coords_f32_r\rank
field_advance_coords_f32_r\rank:
    jmp field_prepare_mask_f32
.endm
DEFINE_ADV_COORD256_ALIAS 1
DEFINE_ADV_COORD256_ALIAS 2
DEFINE_ADV_COORD256_ALIAS 3
DEFINE_ADV_COORD256_ALIAS 4
DEFINE_ADV_COORD256_ALIAS 5
DEFINE_ADV_COORD256_ALIAS 6
DEFINE_ADV_COORD256_ALIAS 7
DEFINE_ADV_COORD256_ALIAS 8

# 1.3.1 fixed-Rank AVX2 address episodes.  Rank is selected by AOT fieldc;
# there is no runtime axis loop in any r1..r8 entry point.
.macro FCO8_RESTORE_Q
    mov eax,r15d
    vmovd xmm6,eax
    vpbroadcastd ymm6,xmm6
    vpaddd ymm6,ymm6,ymmword ptr [rip+lane8_dword]
.endm
.macro FCO8_GEN_AXIS idx
    FCO8_RESTORE_Q
    lea r8,[rip+g_logical_strides]
    mov eax,[r8+(\idx)*4]
    call vec_divmod_u31_8
    vmovdqa ymm6,ymm8
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+(\idx)*4]
    call vec_divmod_u31_8
    vmovdqa ymm11,ymm9
    mov r8,[rip+g_spec_delta_norm_ptr]
    mov r9,r13
    shl r9,5
    add r9,(\idx)*4
    mov eax,[r8+r9]
    test eax,eax
    jz .Lfco8_coord_\@
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpaddd ymm11,ymm11,ymm15
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+(\idx)*4]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpcmpgtd ymm10,ymm15,ymm11
    vpcmpeqd ymm9,ymm9,ymm9
    vpxor ymm10,ymm10,ymm9
    vpand ymm10,ymm10,ymm15
    vpsubd ymm11,ymm11,ymm10
.Lfco8_coord_\@:
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r12
    shl r9,5
    add r9,(\idx)*4
    mov eax,[r8+r9]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpmulld ymm11,ymm11,ymm15
    vpaddd ymm7,ymm7,ymm11
.endm
.macro FCO8_POW2_AXIS idx
    FCO8_RESTORE_Q
    lea r8,[rip+g_stride_shifts]
    mov eax,[r8+(\idx)*4]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpsrlvd ymm11,ymm6,ymm15
    lea r8,[rip+g_extent_masks]
    mov eax,[r8+(\idx)*4]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpand ymm11,ymm11,ymm15
    mov r8,[rip+g_spec_delta_norm_ptr]
    mov r9,r13
    shl r9,5
    add r9,(\idx)*4
    mov eax,[r8+r9]
    test eax,eax
    jz .Lfco8_powstride_\@
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpaddd ymm11,ymm11,ymm15
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+(\idx)*4]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpcmpgtd ymm10,ymm15,ymm11
    vpcmpeqd ymm9,ymm9,ymm9
    vpxor ymm10,ymm10,ymm9
    vpand ymm10,ymm10,ymm15
    vpsubd ymm11,ymm11,ymm10
.Lfco8_powstride_\@:
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r12
    shl r9,5
    add r9,(\idx)*4
    mov eax,[r8+r9]
    vmovd xmm15,eax
    vpbroadcastd ymm15,xmm15
    vpmulld ymm11,ymm11,ymm15
    vpaddd ymm7,ymm7,ymm11
.endm
.macro DEFINE_FCO8_RANK rank
.global field_compute_offsets_f32_r\rank
field_compute_offsets_f32_r\rank:
    push rbx
    push r12
    push r13
    push r15
    mov r12d,edi
    mov r13d,esi
    mov r15d,edx
    call field_prepare_q8
    vpxor ymm7,ymm7,ymm7
    cmp byte ptr [rip+g_shape_pow2],1
    je .Lfco8_r\rank\()_pow
    .set .Lfco8_ax,0
    .rept \rank
      FCO8_GEN_AXIS .Lfco8_ax
      .set .Lfco8_ax,.Lfco8_ax+1
    .endr
    jmp .Lfco8_r\rank\()_done
.Lfco8_r\rank\()_pow:
    .set .Lfco8_axp,0
    .rept \rank
      FCO8_POW2_AXIS .Lfco8_axp
      .set .Lfco8_axp,.Lfco8_axp+1
    .endr
.Lfco8_r\rank\()_done:
    mov edx,r15d
    pop r15
    pop r13
    pop r12
    pop rbx
    ret
.endm
DEFINE_FCO8_RANK 1
DEFINE_FCO8_RANK 2
DEFINE_FCO8_RANK 3
DEFINE_FCO8_RANK 4
DEFINE_FCO8_RANK 5
DEFINE_FCO8_RANK 6
DEFINE_FCO8_RANK 7
DEFINE_FCO8_RANK 8

.macro LOAD8_DELTA_ZERO idx, badlabel
    mov rax,[rip+g_spec_delta_norm_ptr]
    mov r10,rsi
    shl r10,5
    add r10,(\idx)*4
    cmp dword ptr [rax+r10],0
    jne \badlabel
.endm
.macro DEFINE_LOAD8_RANK rank
.global field_load_f32_r\rank
field_load_f32_r\rank:
    push r12
    mov r12d,edi
    mov rax,[rip+g_field_contig_ptr]
    cmp byte ptr [rax+r12],1
    jne .Lfl8_r\rank\()_gather
    .set .Lfl8_ax,0
    .rept \rank
      LOAD8_DELTA_ZERO .Lfl8_ax,.Lfl8_r\rank\()_gather
      .set .Lfl8_ax,.Lfl8_ax+1
    .endr
    call field_prepare_q8
    mov rax,[rip+g_field_data_ptr]
    mov rax,[rax+r12*8]
    lea rax,[rax+rdx*4]
    vmaskmovps ymm0,ymm4,ymmword ptr [rax]
    pop r12
    ret
.Lfl8_r\rank\()_gather:
    call field_compute_offsets_f32_r\rank
    mov rax,[rip+g_field_data_ptr]
    mov rax,[rax+r12*8]
    vxorps ymm0,ymm0,ymm0
    vmovaps ymm15,ymm4
    vgatherdps ymm0,dword ptr [rax+ymm7],ymm15
    pop r12
    ret
.endm
DEFINE_LOAD8_RANK 1
DEFINE_LOAD8_RANK 2
DEFINE_LOAD8_RANK 3
DEFINE_LOAD8_RANK 4
DEFINE_LOAD8_RANK 5
DEFINE_LOAD8_RANK 6
DEFINE_LOAD8_RANK 7
DEFINE_LOAD8_RANK 8

# Rank-specialized store symbols share the AVX2 contiguous-only physicalizer.
# The generic body contains no axis loop: non-contiguous output is explicitly
# rejected because AVX2 has no architectural scatter.
.global field_store_f32_r1
field_store_f32_r1: jmp .field_store_contiguous_f32
.global field_store_f32_r2
field_store_f32_r2: jmp .field_store_contiguous_f32
.global field_store_f32_r3
field_store_f32_r3: jmp .field_store_contiguous_f32
.global field_store_f32_r4
field_store_f32_r4: jmp .field_store_contiguous_f32
.global field_store_f32_r5
field_store_f32_r5: jmp .field_store_contiguous_f32
.global field_store_f32_r6
field_store_f32_r6: jmp .field_store_contiguous_f32
.global field_store_f32_r7
field_store_f32_r7: jmp .field_store_contiguous_f32
.global field_store_f32_r8
field_store_f32_r8: jmp .field_store_contiguous_f32

.field_store_contiguous_f32:
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
    # AVX2 has no architectural scatter. A non-contiguous output is an explicit
    # unsupported physicalization, never a scalar lane-store fallback.
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
field_rank_ptr: .skip 8
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
g_logical_strides: .skip MAX_RANK*4
# Launch-time caretaker proof for division-free dynamic Rank-N coordinates.
g_stride_shifts: .skip MAX_RANK*4
g_extent_masks: .skip MAX_RANK*4
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
g_regular_min_delta: .skip MAX_RANK*4
g_regular_max_delta: .skip MAX_RANK*4
.p2align 3
.global g_spec_linear_delta_bytes_ptr
g_spec_linear_delta_bytes_ptr: .skip 8
g_rank: .skip 1
.p2align 3
g_total: .skip 8
# 1.3.3 immutable launch-time memory profitability facts.
g_llc_bytes: .skip 8
g_nt_threshold_bytes: .skip 8
g_nt_active: .skip 1
g_random_read_pressure: .skip 1
.p2align 3
g_chunks: .skip 8
.p2align 3
g_region_arena: .skip 8
g_region_arena_size: .skip 8
