.intel_syntax noprefix
# Group contraction and instruction geometry are shared by every frontend.
.include "compiler/groupfact.inc"
.text
# One register instruction encoding authority. Descriptor: opcode[7:0],
# map[9:8], pp[11:10], W[12], length[14:13], EVEX[15].
# edi=descriptor, esi=destination, edx=first source, ecx=second source.
# rax=little endian bytes, edx=length; zero length means invalid geometry.
# No semantic type, frontend, or workload identity enters this relation.
.global physical_encode_rrr
physical_encode_rrr:
    push rbx
    sub rsp,8
    mov r8d,edi
    mov r9d,esi
    mov r10d,edx
    mov r11d,ecx
    mov eax,esi; or eax,edx; or eax,ecx
    cmp eax,31; ja .per_bad
    test edi,0x8000; jnz .per_evex
    cmp eax,15; ja .per_bad
    mov byte ptr [rsp],0xc4
    mov eax,r9d; shr eax,3; xor eax,1; and eax,1; shl eax,7
    mov ecx,r11d; shr ecx,3; xor ecx,1; and ecx,1; shl ecx,5
    or eax,ecx; or eax,0x40
    mov ecx,r8d; shr ecx,8; and ecx,3; or eax,ecx
    mov [rsp+1],al
    mov eax,r10d; and eax,15; xor eax,15; shl eax,3
    mov ecx,r8d; shr ecx,10; and ecx,3; or eax,ecx
    mov ecx,r8d; shr ecx,5; and ecx,0x80; or eax,ecx
    mov ecx,r8d; shr ecx,11; and ecx,4; or eax,ecx
    mov [rsp+2],al
    mov [rsp+3],r8b
    mov ebx,4
    jmp .per_modrm
.per_evex:
    mov byte ptr [rsp],0x62
    mov eax,r9d; shr eax,3; xor eax,1; and eax,1; shl eax,7
    mov ecx,r11d; shr ecx,4; xor ecx,1; and ecx,1; shl ecx,6; or eax,ecx
    mov ecx,r11d; shr ecx,3; xor ecx,1; and ecx,1; shl ecx,5; or eax,ecx
    mov ecx,r9d; shr ecx,4; xor ecx,1; and ecx,1; shl ecx,4; or eax,ecx
    mov ecx,r8d; shr ecx,8; and ecx,3; or eax,ecx
    mov [rsp+1],al
    mov eax,r10d; and eax,15; xor eax,15; shl eax,3; or eax,4
    mov ecx,r8d; shr ecx,10; and ecx,3; or eax,ecx
    mov ecx,r8d; shr ecx,5; and ecx,0x80; or eax,ecx
    mov [rsp+2],al
    mov eax,r10d; shr eax,4; xor eax,1; and eax,1; shl eax,3
    mov ecx,r8d; shr ecx,8; and ecx,0x60; or eax,ecx
    mov [rsp+3],al
    mov [rsp+4],r8b
    mov ebx,5
.per_modrm:
    mov eax,r9d; and eax,7; shl eax,3
    mov ecx,r11d; and ecx,7; or eax,ecx; or eax,0xc0
    mov [rsp+rbx],al
    mov rax,[rsp]
    lea edx,[ebx+1]
    add rsp,8; pop rbx; ret
.per_bad:
    xor eax,eax; xor edx,edx
    add rsp,8; pop rbx; ret
# Recover an exact low-bit projection from a ConstantFact. Both scalar and
# packed carriers consume this proof, rather than owning separate modulo rules.
.global physical_u64_lowbits_mask
physical_u64_lowbits_mask:
    xor edx,edx
    test rdi,rdi; jz 1f
    lea rax,[rdi-1]
    test rax,rdi; jnz 1f
    mov edx,1
1:  ret

.global synthesize_group_fact
synthesize_group_fact:
    # Inputs are sparse facts only: logical rank and relation mask from the
    # semantic frontend, lane factor from the target physicalizer, and the
    # already-proven resource replication/carrier factors.  No fixed rank or
    # group-size candidate set exists.
    mov eax,dword ptr [rip+group_body_factor]
    test eax,eax
    jnz .sgf_body_ready
    mov eax,1
.sgf_body_ready:
    mov dword ptr [rip+group_body_factor],eax
    mov eax,dword ptr [rip+group_carrier_factor]
    test eax,eax
    jnz .sgf_carrier_ready
    mov eax,1
.sgf_carrier_ready:
    mov dword ptr [rip+group_carrier_factor],eax

    # Realization closure: a carrier witness cannot exceed the body episode that
    # physically feeds it.  Resource scheduling has already priced recurrence
    # demand against the same front-end/L1I fit, so closure only contracts stale
    # carrier demand; it never widens the body after the cost proof.
    mov edx,dword ptr [rip+group_relation_mask]
    test edx,GF_REL_REDUCTION
    jz .sgf_reduction_closed
    mov eax,dword ptr [rip+group_carrier_factor]
    mov ecx,dword ptr [rip+group_body_factor]
    cmp eax,ecx
    jbe .sgf_reduction_closed
    mov dword ptr [rip+group_carrier_factor],ecx
.sgf_reduction_closed:

    mov eax,dword ptr [rip+group_lane_factor]
    test eax,eax
    jnz .sgf_lane_ready
    mov eax,1
    mov dword ptr [rip+group_lane_factor],eax
.sgf_lane_ready:

    # Rank is derived, never stored as a capacity. ShapeFact-N retains logical
    # axis identity. Operation-affine replication and an independent reduction
    # carrier each contribute an additional nontrivial group axis.
    mov ecx,dword ptr [rip+group_logical_rank]
    test ecx,ecx
    jnz .sgf_have_logical_rank
    cmp eax,1
    jbe .sgf_have_logical_rank
    mov ecx,1
.sgf_have_logical_rank:
    cmp dword ptr [rip+group_body_factor],1
    jbe .sgf_no_body_axis
    inc ecx
.sgf_no_body_axis:
    mov edx,dword ptr [rip+group_relation_mask]
    test edx,GF_REL_REDUCTION
    jz .sgf_no_carrier_axis
    cmp dword ptr [rip+group_carrier_factor],1
    jbe .sgf_no_carrier_axis
    inc ecx
.sgf_no_carrier_axis:
    mov dword ptr [rip+group_rank],ecx

    # Scalar and Vector are not sibling optimizers. They are the rank-0/rank-1
    # degradations of the recovered group.
    mov eax,GF_FORM_SCALAR
    test ecx,ecx
    jz .sgf_form_ready
    mov eax,GF_FORM_VECTOR
    cmp ecx,1
    je .sgf_form_ready
    mov eax,GF_FORM_GROUP
.sgf_form_ready:
    mov dword ptr [rip+group_form],eax

    # Cardinality is diagnostic only. Overflow means unknown/unbounded at AOT,
    # never rejection or a hidden admission threshold.
    mov dword ptr [rip+group_cardinality_exact],1
    mov eax,dword ptr [rip+group_lane_factor]
    mov ecx,dword ptr [rip+group_body_factor]
    mul rcx
    test rdx,rdx
    jnz .sgf_card_unknown
    mov ecx,dword ptr [rip+group_carrier_factor]
    mul rcx
    test rdx,rdx
    jnz .sgf_card_unknown
    mov qword ptr [rip+group_cardinality],rax
    ret
.sgf_card_unknown:
    mov qword ptr [rip+group_cardinality],0
    mov dword ptr [rip+group_cardinality_exact],0
    ret


.section .note.GNU-stack,"",@progbits

.text
# One local math identity relation. rdi=name, rsi=bytes, edx=precision bits.
# Returns rax=ISA fragment, ecx=bytes, edx=identity ordinal, or rax=0.
# Source children retain their own precision; only this consumer is rounded.
.global physical_math_fragment
physical_math_fragment:
    cmp rsi,3; jne .pmf_bad
    mov r8d,edx
    movzx eax,word ptr [rdi]
    movzx ecx,byte ptr [rdi+2]
    shl ecx,16; or eax,ecx
    lea r9,[rip+physical_math_names]
    xor edi,edi
.pmf_next:
    cmp eax,[r9+rdi*4]; je .pmf_found
    inc edi; cmp edi,4; jb .pmf_next
.pmf_bad: xor eax,eax; xor ecx,ecx; ret
.pmf_found:
    mov esi,r8d
    jmp physical_math_fragment_by_id
# edi=canonical ordinal, esi=natural precision bits.
.global physical_math_fragment_by_id
physical_math_fragment_by_id:
    cmp edi,4; jae .pmf_bad
    cmp esi,64; je .pmfi_wide
    cmp esi,32; jne .pmf_bad
    mov edx,edi; shl edi,5; add edi,16; jmp .pmfi_entry
.pmfi_wide: mov edx,edi; shl edi,5
.pmfi_entry:
    lea r9,[rip+physical_math_table]
    mov rax,[r9+rdi]; mov ecx,[r9+rdi+8]; ret

.section .rodata
physical_math_names: .long 0x6e6973,0x736f63,0x707865,0x676f6c
.p2align 3
physical_math_table:
    .quad gc_sin_f64; .long gc_sin_f64_size,0
    .quad gc_sin_f32; .long gc_sin_f32_size,0
    .quad gc_cos_f64; .long gc_cos_f64_size,0
    .quad gc_cos_f32; .long gc_cos_f32_size,0
    .quad gc_exp_f64; .long gc_exp_f64_size,0
    .quad gc_exp_f32; .long gc_exp_f32_size,0
    .quad gc_log_f64; .long gc_log_f64_size,0
    .quad gc_log_f32; .long gc_log_f32_size,0
# Native scalar transcendental ValueFacts. x87 is used only as an ISA-level
# realization primitive; values remain ordinary f32/f64 facts and are rounded
# back to their declared format at this exact consumer edge.
.macro PHYSICAL_LOG_BODY bits,slot
    fldln2
.if \bits == 64
    fld qword ptr [rsp+\slot]
.else
    fld dword ptr [rsp+\slot]
.endif
    fyl2x
.if \bits == 64
    fstp qword ptr [rsp+\slot]
.else
    fstp dword ptr [rsp+\slot]
.endif
.endm
.macro PHYSICAL_LOG name,bits
\name:
    PHYSICAL_LOG_BODY \bits,0
\name\()_end:
.endm
PHYSICAL_LOG gc_log_f64,64
PHYSICAL_LOG gc_log_f32,32
.macro PHYSICAL_EXP_BODY bits,exp_mask,sign_mask,slot
    .if \bits == 64
        mov rax,[rsp+\slot]
    .else
        mov eax,[rsp+\slot]
    .endif
    mov rcx,\exp_mask; mov rdx,rax; and rdx,rcx
    cmp rdx,rcx; jne .Lpex_finite\@
    mov rdx,\sign_mask; or rdx,rcx
    cmp rax,rdx; jne .Lpex_done\@
    .if \bits == 64
        mov qword ptr [rsp+\slot],0
    .else
        mov dword ptr [rsp+\slot],0
    .endif
    jmp .Lpex_done\@
.Lpex_finite\@:
    .if \bits == 64
        fld qword ptr [rsp+\slot]
    .else
        fld dword ptr [rsp+\slot]
    .endif
    fldl2e; fmulp; fld st(0); frndint; fsub st(1),st(0)
    fxch; f2xm1; fld1; faddp; fscale; fstp st(1)
    .if \bits == 64
        fstp qword ptr [rsp+\slot]
    .else
        fstp dword ptr [rsp+\slot]
    .endif
.Lpex_done\@:
.endm
.macro PHYSICAL_SCALAR_MATH_BODY op,bits,slot
.if \op == 2
    .if \bits == 64
        PHYSICAL_EXP_BODY 64,0x7ff0000000000000,0x8000000000000000,\slot
    .else
        PHYSICAL_EXP_BODY 32,0x7f800000,0x80000000,\slot
    .endif
.else
    PHYSICAL_LOG_BODY \bits,\slot
.endif
.endm
# Completed lanes consume the same scalar primitive at their owned offsets.
# GPR preservation is episode-wide; no lane payload transfer or polling cache.
.macro PHYSICAL_SCALAR_MATH_PACKET name,op,bits,lanes
\name:
.if \op == 2
    push rax; push rdx; push rcx
.endif
    .set .Lmath_slot\@,0
    .rept \lanes
        .if \op == 2
            PHYSICAL_SCALAR_MATH_BODY \op,\bits,.Lmath_slot\@+24
        .else
            PHYSICAL_SCALAR_MATH_BODY \op,\bits,.Lmath_slot\@
        .endif
        .set .Lmath_slot\@,.Lmath_slot\@+\bits/8
    .endr
.if \op == 2
    pop rcx; pop rdx; pop rax
.endif
\name\()_end:
.endm
PHYSICAL_SCALAR_MATH_PACKET gc_exp_f64,2,64,1
PHYSICAL_SCALAR_MATH_PACKET gc_exp_f32,2,32,1
.irp op,2,3
    .irp lanes,4,8,16
        PHYSICAL_SCALAR_MATH_PACKET gc_scalar_math_\op\()_32_\lanes,\op,32,\lanes
    .endr
    .irp lanes,4,8
        PHYSICAL_SCALAR_MATH_PACKET gc_scalar_math_\op\()_64_\lanes,\op,64,\lanes
    .endr
.endr
.include "compiler/physical_sincos.inc"


.global gc_sin_f32,gc_sin_f32_size
.equ gc_sin_f32_size,gc_sin_f32_end-gc_sin_f32

.global gc_sin_f64,gc_sin_f64_size
.equ gc_sin_f64_size,gc_sin_f64_end-gc_sin_f64

.global gc_cos_f32,gc_cos_f32_size
.equ gc_cos_f32_size,gc_cos_f32_end-gc_cos_f32

.global gc_cos_f64,gc_cos_f64_size
.equ gc_cos_f64_size,gc_cos_f64_end-gc_cos_f64

.global gc_exp_f32,gc_exp_f32_size
.equ gc_exp_f32_size,gc_exp_f32_end-gc_exp_f32

.global gc_exp_f64,gc_exp_f64_size
.equ gc_exp_f64_size,gc_exp_f64_end-gc_exp_f64

.global gc_log_f32,gc_log_f32_size
.equ gc_log_f32_size,gc_log_f32_end-gc_log_f32

.global gc_log_f64,gc_log_f64_size
.equ gc_log_f64_size,gc_log_f64_end-gc_log_f64

.text
# One branch-free truncation relation over the already rounded IEEE payload.
# edi unused, esi=32/64 -> RAX=fragment, ECX=size. Runtime input/output RAX;
# RCX is preserved, RDX is the existing implicit scratch. No new FP rounding.
.global physical_fp_u64_fragment
physical_fp_u64_fragment:
    lea rax,[rip+gc_payload_f64_u64]; mov ecx,gc_payload_f64_u64_end-gc_payload_f64_u64
    cmp esi,64; je 1f
    lea rax,[rip+gc_payload_f32_u64]; mov ecx,gc_payload_f32_u64_end-gc_payload_f32_u64
    cmp esi,32; je 1f
    xor eax,eax; xor ecx,ecx
1:  ret
.section .rodata
.macro FP_U64_PAYLOAD name,fraction,bias,expmask,signbit
\name:
    push rcx
    push rax
    mov rdx,rax
    shr rdx,\fraction
    and edx,\expmask
    sub edx,\bias
    # One significand, one alignment. Rotation implements either direction;
    # the exponent-derived low mask removes only the wrapped fractional bits.
    # For 0<=E<64, result=rol(significand,E-fraction)&(2^(E+1)-1).
    shl rax,(64-\fraction)
    shr rax,(64-\fraction)
    bts rax,\fraction
    lea ecx,[rdx-\fraction]
    rol rax,cl
    push rdx
    mov ecx,63
    sub ecx,edx
    mov rdx,-1
    shr rdx,cl
    and rax,rdx
    pop rdx
    xor ecx,ecx
    test edx,edx
    cmovl rax,rcx
    mov rcx,0x8000000000000000
    cmp edx,64
    cmovge rax,rcx
    test edx,edx
    mov ecx,0
    mov rdx,0x8000000000000000
    cmovge rcx,rdx
    mov rdx,[rsp]
    bt rdx,\signbit
    cmovc rax,rcx
    add rsp,8
    pop rcx
\name\()_end:
.endm
FP_U64_PAYLOAD gc_payload_f64_u64,52,1023,2047,63
FP_U64_PAYLOAD gc_payload_f32_u64,23,127,255,31

.text
# Reciprocal ConstantFact with consumer precision. rdi=d, esi=quotient demand.
# Remainder needs only a quotient bounded one below exact: k=0, floor(2^64/d).
# Quotient demand normalizes k=floor(log2(d)) and rounds the same division.
# Returns RAX=m, EDX=k, ECX=addend form. Quotient runtime relation:
# q=high64(n*m); q=((n-q)>>1)+q when addend form; q>>=k.
# Both projections consume the same fact generator. No runtime selection.
.global physical_u64_division_fact
physical_u64_division_fact:
    bsr rcx,rdi
    imul ecx,esi
    mov r8d,ecx
    mov edx,1
    shl rdx,cl
    mov r11,rdx
    xor eax,eax
    div rdi
    mov r9,rax
    mov r10,rdi
    sub r10,rdx
    cmp r10,r11
    setae r10b
    and r10b,sil
    jz .pudf_direct
    # Double the normalized reciprocal and round upward. The remainder carry
    # and the ordinary comparison are the two bits of one exact integer sum.
    add r9,r9
    add rdx,rdx
    setc r10b
    cmp rdx,rdi
    setae r11b
    or r10b,r11b
    movzx r10d,r10b
    add r9,r10
    inc r9
    mov rax,r9; mov edx,r8d; mov ecx,1
    ret
.pudf_direct:
    lea rax,[r9+rsi]; mov edx,r8d; xor ecx,ecx
    ret

.text
# Canonical projection relation, independent of any frontend/workload names.
.global physical_math_projection_peer
physical_math_projection_peer:
    mov eax,-1
    cmp edi,2; jae 1f
    mov eax,edi; xor eax,1
1: ret

.global physical_math_packet_dual_fragment_by_id
physical_math_packet_dual_fragment_by_id:
    cmp edi,2; jae .pmd_bad
    cmp esi,64; jne .pmd_bad
    cmp edx,4; je .pmd_four
    cmp edx,8; jne .pmd_bad
    lea eax,[rdi*2+1]; jmp .pmd_entry
.pmd_four: lea eax,[rdi*2]
.pmd_entry:
    shl eax,4; lea r9,[rip+physical_math_packet_dual_table]
    mov ecx,[r9+rax+8]; mov r8d,[r9+rax+12]; mov rax,[r9+rax]; ret
.pmd_bad: xor eax,eax; xor ecx,ecx; ret
.section .rodata
.p2align 3
physical_math_packet_dual_table:
    .quad gc_sincos_f64_4; .long gc_sincos_f64_4_end-gc_sincos_f64_4,0xffff
    .quad gc_sincos_f64_8; .long gc_sincos_f64_8_end-gc_sincos_f64_8,0xffff
    .quad gc_cossin_f64_4; .long gc_cossin_f64_4_end-gc_cossin_f64_4,0xffff
    .quad gc_cossin_f64_8; .long gc_cossin_f64_8_end-gc_cossin_f64_8,0xffff
.text
.global physical_math_packet_fragment_by_id
physical_math_packet_fragment_by_id:
    test edx,edx; jz .pmp_bad
    lea eax,[rdx-1]; test eax,edx; jnz .pmp_bad
    cmp edi,4; jae .pmp_bad
    cmp esi,64; je .pmp_f64
    cmp esi,32; jne .pmp_bad
    bsr eax,edx; sub eax,2; cmp eax,2; ja .pmp_bad
    lea ecx,[rdi+rdi*4]; add eax,ecx; jmp .pmp_entry
.pmp_f64:
    bsr eax,edx; sub eax,2; cmp eax,1; ja .pmp_bad
    lea ecx,[rdi+rdi*4]; add eax,ecx; add eax,3
.pmp_entry:
    shl eax,4; lea r9,[rip+physical_math_packet_table]
    mov ecx,[r9+rax+8]; mov r8d,[r9+rax+12]; mov rax,[r9+rax]; ret
.pmp_bad: xor eax,eax; xor ecx,ecx; ret
.section .rodata
.p2align 3
physical_math_packet_table:
    .quad gc_sin_f32_4; .long gc_sin_f32_4_end-gc_sin_f32_4,0xffff
    .quad gc_sin_f32_8; .long gc_sin_f32_8_end-gc_sin_f32_8,0xffff
    .quad gc_sin_f32_16; .long gc_sin_f32_16_end-gc_sin_f32_16,0xffff
    .quad gc_sin_f64_4; .long gc_sin_f64_4_end-gc_sin_f64_4,0xffff
    .quad gc_sin_f64_8; .long gc_sin_f64_8_end-gc_sin_f64_8,0xffff
    .quad gc_cos_f32_4; .long gc_cos_f32_4_end-gc_cos_f32_4,0xffff
    .quad gc_cos_f32_8; .long gc_cos_f32_8_end-gc_cos_f32_8,0xffff
    .quad gc_cos_f32_16; .long gc_cos_f32_16_end-gc_cos_f32_16,0xffff
    .quad gc_cos_f64_4; .long gc_cos_f64_4_end-gc_cos_f64_4,0xffff
    .quad gc_cos_f64_8; .long gc_cos_f64_8_end-gc_cos_f64_8,0xffff
.macro PHYSICAL_SCALAR_MATH_ENTRY name
    .quad \name; .long \name\()_end-\name,0
.endm
    .irp op,2,3
        .irp lanes,4,8,16
            PHYSICAL_SCALAR_MATH_ENTRY gc_scalar_math_\op\()_32_\lanes
        .endr
        .irp lanes,4,8
            PHYSICAL_SCALAR_MATH_ENTRY gc_scalar_math_\op\()_64_\lanes
        .endr
    .endr

.text
# Natural native FMA: three completed operands, exactly one final rounding.
# esi=General natural type (4=f32,5=f64), RAX=fragment, ECX=bytes.
.global physical_fma_fragment
physical_fma_fragment:
    lea rax,[rip+gc_fma_f64]; mov ecx,gc_fma_f64_end-gc_fma_f64
    cmp esi,5; je 1f
    lea rax,[rip+gc_fma_f32]; mov ecx,gc_fma_f32_end-gc_fma_f32
    cmp esi,4; je 1f
    xor eax,eax; xor ecx,ecx
1: ret
.section .rodata
gc_fma_f64:
    vmovsd xmm0,[rsp+16]; vmovsd xmm1,[rsp+8]; vmovsd xmm2,[rsp]
    vfmadd213sd xmm0,xmm1,xmm2
    vmovsd [rsp+16],xmm0; add rsp,16
gc_fma_f64_end:
gc_fma_f32:
    vmovss xmm0,[rsp+16]; vmovss xmm1,[rsp+8]; vmovss xmm2,[rsp]
    vfmadd213ss xmm0,xmm1,xmm2
    vmovss [rsp+16],xmm0; add rsp,16
gc_fma_f32_end:

.text
.include "compiler/physical_strict_fold.inc"

.text
.include "compiler/physical_transport.inc"

.include "compiler/physical_value_identity.inc"

.include "compiler/physical_input_range.inc"

.include "compiler/physical_predicate.inc"
.text
.global physical_fp_setcc_fragment
# edi=SETcc opcode 92..97 -> rax=fragment, ecx=bytes, else zero.
physical_fp_setcc_fragment:
    sub edi,0x92
    cmp edi,5; ja .pfsc_bad
    shl edi,4; lea rax,[rip+physical_fp_setcc_table]; add rax,rdi
    mov ecx,[rax+8]; mov rax,[rax]; ret
.pfsc_bad: xor eax,eax; xor ecx,ecx; ret
.section .rodata
.macro FP_SETCC_FRAGMENT name,cc
\name: PHYSICAL_FP_SETCC \cc
\name\()_end:
.endm
FP_SETCC_FRAGMENT physical_fp_setcc_lt,0x92
FP_SETCC_FRAGMENT physical_fp_setcc_ge,0x93
FP_SETCC_FRAGMENT physical_fp_setcc_eq,0x94
FP_SETCC_FRAGMENT physical_fp_setcc_ne,0x95
FP_SETCC_FRAGMENT physical_fp_setcc_le,0x96
FP_SETCC_FRAGMENT physical_fp_setcc_gt,0x97
physical_fp_setcc_table:
.quad physical_fp_setcc_lt,physical_fp_setcc_lt_end-physical_fp_setcc_lt
.quad physical_fp_setcc_ge,physical_fp_setcc_ge_end-physical_fp_setcc_ge
.quad physical_fp_setcc_eq,physical_fp_setcc_eq_end-physical_fp_setcc_eq
.quad physical_fp_setcc_ne,physical_fp_setcc_ne_end-physical_fp_setcc_ne
.quad physical_fp_setcc_le,physical_fp_setcc_le_end-physical_fp_setcc_le
.quad physical_fp_setcc_gt,physical_fp_setcc_gt_end-physical_fp_setcc_gt

.include "compiler/physical_plan_search.inc"
