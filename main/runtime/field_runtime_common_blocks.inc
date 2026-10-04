# Wheelchair materialized-field runtime bodies shared by native256/native512.
# Only proof-neutral bodies live here; frontier/reduction/startup authorities stay explicit.

.macro FRC_map_one_field
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
    mov rax,[rsp+48]
    cmp rax,FIELD_HEADER_SIZE
    jb .mof_close_fail
    mov rcx,[rip+g_field_size_ptr]
    mov [rcx+r12*8],rax

    # Distinct declarations are noalias; one inout declaration expresses aliasing.
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
    mov rcx,[rip+g_rank]
    cmp qword ptr [r14+FH_RANK],rcx
    jne .mof_unmap_fail
    test rcx,rcx
    jz .mof_unmap_fail
    mov rax,rcx
    shr rax,32                         # loop-index representation frontier
    jnz .mof_unmap_fail

    # WHFLD217: fixed 64-byte header, then rank extents and rank strides.
    mov rax,rcx
    shl rax,4                          # 16 bytes of descriptor facts per axis
    jc .mof_unmap_fail
    add rax,FIELD_HEADER_SIZE
    jc .mof_unmap_fail
    mov rdx,[r14+FH_DATA_OFF]
    cmp rdx,rax
    jb .mof_unmap_fail
    mov rax,[rip+g_field_size_ptr]
    cmp rdx,[rax+r12*8]
    jae .mof_unmap_fail
    lea rax,[r14+rdx]
    mov rdx,[rip+g_field_data_ptr]
    mov [rdx+r12*8],rax

    lea r15,[r14+FIELD_HEADER_SIZE]     # extent[rank]
    mov rbx,rcx
    shl rbx,3
    add rbx,r15                        # stride[rank]

    # Validate logical product and physical span. Coordinate-width aging is a
    # separate representation frontier; rank cardinality itself is unrestricted.
    mov r8,1
    xor r9d,r9d
    xor r10,r10
.mof_axis:
    cmp r9,rcx
    jae .mof_axes_done
    mov rax,[r15+r9*8]
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
    mov r11,[rbx+r9*8]
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
    inc r9
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

    # Collapse descriptor spans into one hot RankFact-derived arena.
    xor r9d,r9d
    mov r11,r12
    imul r11,qword ptr [rip+g_axis_bytes]
.mof_copy_axis:
    cmp r9,rcx
    jae .mof_copy_done
    mov rax,[r15+r9*8]
    mov edx,eax
    mov rax,[rip+g_field_extents_ptr]
    lea rsi,[r11+r9*4]
    mov [rax+rsi],edx
    mov rax,[rbx+r9*8]
    mov edx,eax
    mov rax,[rip+g_field_strides_ptr]
    lea rsi,[r11+r9*4]
    mov [rax+rsi],edx
    inc r9
    jmp .mof_copy_axis
.mof_copy_done:
    mov rax,[rip+g_field_total_ptr]
    mov [rax+r12*8],r8

    cmp r13d,FIELD_MODE_INPUT
    je .mof_injective_done
    mov edi,r12d
    mov esi,ecx
    call validate_mutable_injective
    test eax,eax
    jnz .mof_unmap_fail
.mof_injective_done:

    mov rax,[rip+g_field_contig_ptr]
    mov byte ptr [rax+r12],1
    mov r11d,4
    mov r9,[rip+g_rank]
    mov rdx,r12
    imul rdx,qword ptr [rip+g_axis_bytes]
.mof_contig_loop:
    test r9d,r9d
    jz .mof_ok
    dec r9d
    mov rax,[rip+g_field_strides_ptr]
    lea rsi,[rdx+r9*4]
    mov eax,[rax+rsi]
    cmp eax,r11d
    jne .mof_not_contig
    mov rax,[rip+g_field_extents_ptr]
    lea rsi,[rdx+r9*4]
    mov eax,[rax+rsi]
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
.endm

.macro FRC_validate_mutable_injective
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d,edi                    # field
    mov r13d,esi                    # rank (source-cardinality representation)
    mov r14,[rip+g_regular_min_delta_ptr] # cold proof scratch: one dword/axis
    mov rcx,r13
    mov rdi,r14
    xor eax,eax
    rep stosd                        # selected[axis]=0, exact RankFact span
    mov r15,4                        # occupied byte span of lower axes
.vmi_mark_trivial:
    xor ebx,ebx
.vmi_mark_loop:
    cmp ebx,r13d
    jae .vmi_select
    mov r8,[rip+g_field_extents_ptr]
    mov rax,r12
    imul rax,qword ptr [rip+g_axis_bytes]
    lea rax,[rax+rbx*4]
    cmp dword ptr [r8+rax],1
    jne .vmi_mark_next
    mov dword ptr [r14+rbx*4],1
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
    cmp dword ptr [r14+rbx*4],0
    jne .vmi_find_next
    mov r8,[rip+g_field_strides_ptr]
    mov rax,r12
    imul rax,qword ptr [rip+g_axis_bytes]
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
    # span += (extent-1)*stride. Descriptor span validation already proves
    # this remains in the signed 31-bit physical-offset domain.
    mov r8,[rip+g_field_extents_ptr]
    mov rdx,r12
    imul rdx,qword ptr [rip+g_axis_bytes]
    lea rdx,[rdx+r10*4]
    mov edx,dword ptr [r8+rdx]
    dec edx
    imul rdx,rax
    add r15,rdx
    mov dword ptr [r14+r10*4],1
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
.endm

.macro FRC_finalize_shape
    push rbx
    push r12
    mov rcx,[rip+g_rank]
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
    imul r10,qword ptr [rip+g_axis_bytes]
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
    mov r8,[rip+g_logical_strides_ptr]
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
    mov r8,[rip+g_extent_masks_ptr]
    mov [r8+rdx*4],r9d
    mov r8,[rip+g_logical_strides_ptr]
    mov eax,[r8+rdx*4]
    test eax,eax
    jz .fs_pow2_no
    mov r9d,eax
    dec r9d
    test eax,r9d
    jnz .fs_pow2_no
    bsf eax,eax
    mov r8,[rip+g_stride_shifts_ptr]
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
    mov r9,r10; imul r9,qword ptr [rip+g_axis_bytes]; lea r9,[r9+rdx*4]
    mov eax,[r8+r9]
    mov r9,rbx; imul r9,qword ptr [rip+g_axis_bytes]; lea r9,[r9+rdx*4]
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
.endm

.macro FRC_field_derive_launch_leaf_geometry
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
.endm

.macro FRC_validate_parallel_mutable_geometry
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
    mov r12d,dword ptr [rip+g_rank]
    test r12d,r12d
    jz .vpmg_fail
    mov r13d,r12d
    dec r13d                        # logical innermost axis
    mov r14,rbx
    imul r14,qword ptr [rip+g_axis_bytes]
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
.endm

.macro FRC_normalize_specs
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi,[rip+g_regular_min_delta_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+g_rank]
    rep stosd
    mov rdi,[rip+g_regular_max_delta_ptr]
    xor eax,eax
    mov ecx,dword ptr [rip+g_rank]
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
    mov r12d,dword ptr [rip+g_rank]
    xor r13d,r13d
    xor r15d,r15d                  # signed logical-element displacement
.ns_axis:
    cmp r13d,r12d
    jae .ns_next
    mov rdx,[rip+access_delta_ptr]
    mov rcx,rbx
    imul rcx,qword ptr [rip+g_access_delta_stride]
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
    imul rcx,qword ptr [rip+g_access_delta_stride]
    lea rcx,[rcx+r13*4]
    mov [rdx+rcx],eax

    # Global minimum/maximum signed delta per axis defines one kernel-wide
    # interior domain.  It is intentionally conservative and workload-name blind.
    mov rdx,[rip+g_regular_min_delta_ptr]
    mov eax,[rdx+r13*4]
    cmp r14d,eax
    jge .ns_min_done
    mov [rdx+r13*4],r14d
.ns_min_done:
    mov rdx,[rip+g_regular_max_delta_ptr]
    mov eax,[rdx+r13*4]
    cmp r14d,eax
    jle .ns_max_done
    mov [rdx+r13*4],r14d
.ns_max_done:

    # Contiguous row-major physical displacement in elements.  This is used
    # only after a launch-time contiguous-layout proof and an episode interior
    # proof; the general gather authority remains available otherwise.
    mov rdx,[rip+g_logical_strides_ptr]
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
.endm

.macro FRC_field_init_memory_profitability
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12d,r12d                  # largest architectural cache discovered
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
    jmp .fimp_cache_loop
.fimp_cache_done:
    mov [rip+g_llc_bytes],r12
    # NT admission is a direct physical-capacity relation: once the streaming
    # output itself exceeds the largest visible cache, write-allocate traffic
    # cannot remain resident.  No MiB floor and no random-read multiplier form
    # a second workload heuristic.  If cache geometry is unavailable, retain
    # cached stores by making the threshold unreachable.
    mov r14,r12
    test r14,r14
    jnz .fimp_threshold_ready
    mov r14,-1
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
.endm

.macro FRC_worker_range
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
.endm

.macro FRC_eval_chunk
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
.endm

.macro FRC_field_eval_vec
    .byte 0xE9
.global field_eval_vec_disp_patch
field_eval_vec_disp_patch: .long 0
.global field_eval_vec_end
.endm

