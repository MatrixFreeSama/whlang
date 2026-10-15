# One Rank-N CoordinateFact relation, parameterized only by ISA carriers.
# R8 points to invocation-local storage: q followed by one vector per axis.
# The q identity belongs to this generated invocation, never a runtime search.
.macro FIELD_COORD_OFFSETS lanes, vector, shift, input, accum, quotient, remainder, coord, scratch
    push rbp; push rbx; push r12; push r13; push r14; push r15
    mov rbp,r8
    test rbp,rbp; jz .bad_args
    mov r12d,edi; mov r13d,esi; mov r14,rdx
    cmp qword ptr [rbp],r14
    je .Lfco_coords_ready
    xor r15d,r15d
.Lfco_coordinates:
    cmp r15d,dword ptr [rip+g_rank]; jae .Lfco_coord_done
    mov eax,r14d
.if \lanes == 16
    vpbroadcastd \input,eax
.else
    vmovd xmm6,eax
    vpbroadcastd \input,xmm6
.endif
    vpaddd \input,\input,\vector\()word ptr [rip+lane\lanes\()_dword]
    cmp byte ptr [rip+g_shape_pow2],1; je .Lfco_coord_pow
    mov r8,[rip+g_logical_strides_ptr]
    mov eax,[r8+r15*4]
.if \lanes == 16
    call vec_divmod_u31
    vmovdqa32 \input,\quotient
.else
    call vec_divmod_u31_8
    vmovdqa \input,\quotient
.endif
    mov r8,[rip+g_field_extents_ptr]
    mov eax,[r8+r15*4]
.if \lanes == 16
    call vec_divmod_u31
    vmovdqa32 \coord,\remainder
.else
    call vec_divmod_u31_8
    vmovdqa \coord,\remainder
.endif
    jmp .Lfco_coord_store
.Lfco_coord_pow:
    mov r8,[rip+g_stride_shifts_ptr]; mov eax,[r8+r15*4]
.if \lanes == 16
    vpbroadcastd \scratch,eax
.else
    vmovd xmm15,eax; vpbroadcastd \scratch,xmm15
.endif
    vpsrlvd \coord,\input,\scratch
    mov r8,[rip+g_extent_masks_ptr]; mov eax,[r8+r15*4]
.if \lanes == 16
    vpbroadcastd \scratch,eax
    vpandd \coord,\coord,\scratch
.else
    vmovd xmm15,eax; vpbroadcastd \scratch,xmm15
    vpand \coord,\coord,\scratch
.endif
.Lfco_coord_store:
    mov r9,r15; shl r9,\shift
.if \lanes == 16
    vmovdqu32 \vector\()word ptr [rbp+r9+8],\coord
.else
    vmovdqu \vector\()word ptr [rbp+r9+8],\coord
.endif
    inc r15d; jmp .Lfco_coordinates
.Lfco_coord_done:
    mov qword ptr [rbp],r14
.Lfco_coords_ready:
.if \lanes == 16
    vpxord \accum,\accum,\accum
.else
    vpxor \accum,\accum,\accum
.endif
    xor r15d,r15d
.Lfco_realize:
    cmp r15d,dword ptr [rip+g_rank]; jae .Lfco_done
    mov r9,r15; shl r9,\shift
.if \lanes == 16
    vmovdqu32 \coord,\vector\()word ptr [rbp+r9+8]
.else
    vmovdqu \coord,\vector\()word ptr [rbp+r9+8]
.endif
    mov r8,[rip+g_spec_delta_norm_ptr]
    mov r9,r13; imul r9,qword ptr [rip+g_access_delta_stride]
    lea r9,[r9+r15*4]; mov eax,[r8+r9]
    test eax,eax; jz .Lfco_stride
.if \lanes == 16
    vpbroadcastd \scratch,eax
.else
    vmovd xmm15,eax; vpbroadcastd \scratch,xmm15
.endif
    vpaddd \coord,\coord,\scratch
    mov r8,[rip+g_field_extents_ptr]; mov eax,[r8+r15*4]
.if \lanes == 16
    vpbroadcastd \scratch,eax
    vpcmpd k2,\coord,\scratch,5
    vpsubd \coord{k2},\coord,\scratch
.else
    vmovd xmm15,eax; vpbroadcastd \scratch,xmm15
    vpcmpgtd ymm10,\scratch,\coord
    vpcmpeqd ymm9,ymm9,ymm9
    vpxor ymm10,ymm10,ymm9
    vpand ymm10,ymm10,\scratch
    vpsubd \coord,\coord,ymm10
.endif
.Lfco_stride:
    mov r8,[rip+g_field_strides_ptr]
    mov r9,r12; imul r9,qword ptr [rip+g_axis_bytes]
    lea r9,[r9+r15*4]; mov eax,[r8+r9]
.if \lanes == 16
    vpbroadcastd \scratch,eax
.else
    vmovd xmm15,eax; vpbroadcastd \scratch,xmm15
.endif
    vpmulld \coord,\coord,\scratch
    vpaddd \accum,\accum,\coord
    inc r15d; jmp .Lfco_realize
.Lfco_done:
.if \lanes == 16
    # Helpers do not alter k1; restore the q carrier and lane count used by
    # surrounding gather/store code, without rebuilding the validity mask.
    mov rdx,r14
    mov r8,rcx; sub r8,rdx
    mov eax,FIELD_PACKET_LANES; cmp r8,rax; cmova r8,rax
.endif
    pop r15; pop r14; pop r13; pop r12; pop rbx; pop rbp
    ret
.endm
