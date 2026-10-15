# Both projections consume one completed phase and the same polynomial values.
# mode bit zero orders the two output payloads; bit one admits the second demand.
.macro PHYSICAL_SINCOS_DUAL v0,v1,v2,v3,v4,width,mode
    vandpd \v4,\v0,\v2
    vandnpd \v1,\v0,\v3
    vorpd \v4,\v4,\v1
    vandpd \v3,\v3,\v0
    vandnpd \v0,\v0,\v2
    vorpd \v0,\v0,\v3
    vmovupd \v2,[rsp+2*\width]
    vmovupd \v1,[rsp+\width]
    vpsllq \v1,\v1,63
    vmovupd \v3,[rdi]
    vpsrlq \v3,\v3,63
    vpsllq \v3,\v3,63
    vxorpd \v1,\v1,\v3
    vxorpd \v1,\v1,\v2
    .if (\mode & 1) == 0
        vxorpd \v0,\v0,\v2
        vxorpd \v4,\v4,\v1
        vmovupd [rdi],\v0
        vmovupd [rdi+\width],\v4
    .else
        vxorpd \v4,\v4,\v2
        vxorpd \v0,\v0,\v1
        vmovupd [rdi],\v4
        vmovupd [rdi+\width],\v0
    .endif
.endm
# One native sin/cos relation over natural IEEE values. Quarter-turn reduction
# uses a windowed exact-payload fixed-point product at every normal exponent.
# Precision, projection and carrier cardinality are compile-time parameters.
.macro PHYSICAL_SINCOS name,bits,lanes,mode,v0,v1,v2,v3,kind
\name:
    push rax; push rcx; push rdx; push rbx; push rsi; push rdi
    push r8; push r9; push r10; push r11
    .set sc_width\@,(\bits/8)*\lanes
    .set sc_frame\@,((3*sc_width\@+64+63)/64)*64
    sub rsp,sc_frame\@
    .if \lanes == 1
        movdqu [rsp+3*sc_width\@],xmm0
        movdqu [rsp+3*sc_width\@+16],xmm1
        movdqu [rsp+3*sc_width\@+32],xmm2
        movdqu [rsp+3*sc_width\@+48],xmm3
    .endif
    lea rdi,[rsp+sc_frame\@+80]
    .if \lanes == 1
    xor ebx,ebx
.Lsc_lane\@:
    .if \bits == 64
        .if \lanes == 1
            movsd xmm0,[rdi+rbx*8]
        .else
            vmovsd xmm0,[rdi+rbx*8]
        .endif
    .else
        .if \lanes == 1
            movss xmm0,[rdi+rbx*4]; cvtss2sd xmm0,xmm0
        .else
            vmovss xmm0,[rdi+rbx*4]; vcvtss2sd xmm0,xmm0,xmm0
        .endif
    .endif
    call .Lsc_reduce\@
    .if \bits == 32
        .if \lanes == 1
            cvtsd2ss xmm0,xmm0; movss [rsp+rbx*4],xmm0
        .else
            vcvtsd2ss xmm0,xmm0,xmm0; vmovss [rsp+rbx*4],xmm0
        .endif
    .else
        .if \lanes == 1
            movsd [rsp+rbx*8],xmm0
        .else
            vmovsd [rsp+rbx*8],xmm0
        .endif
    .endif
    mov eax,ecx; and eax,1; neg rax
    .if \bits == 64
        mov [rsp+sc_width\@+rbx*8],rax
    .else
        mov [rsp+sc_width\@+rbx*4],eax
    .endif
    .if (\mode & 1) == 0
        mov eax,ecx; shr eax,1; shr r11,63; xor eax,r11d
    .else
        lea eax,[rcx+1]; shr eax,1
    .endif
    and eax,1; shl rax,(\bits-1)
    .if \bits == 64
        mov [rsp+2*sc_width\@+rbx*8],rax
    .else
        mov [rsp+2*sc_width\@+rbx*4],eax
    .endif
    inc ebx; cmp ebx,\lanes; jb .Lsc_lane\@
    .else
        .set sc_chunk\@,0
        .rept (\lanes/4)
            .if \bits == 64
                vmovupd ymm0,[rdi+sc_chunk\@*32]
            .else
                vcvtps2pd ymm0,[rdi+sc_chunk\@*16]
            .endif
            call .Lsc_reduce4\@
            .if \bits == 64
                vmovupd [rsp+sc_chunk\@*32],ymm0
                vmovdqu [rsp+sc_width\@+sc_chunk\@*32],ymm1
                vmovdqu [rsp+2*sc_width\@+sc_chunk\@*32],ymm2
            .else
                vcvtpd2ps xmm0,ymm0
                vmovups [rsp+sc_chunk\@*16],xmm0
                vpshufd ymm1,ymm1,0x88
                vextracti128 xmm3,ymm1,1
                vpunpcklqdq xmm1,xmm1,xmm3
                vmovdqu [rsp+sc_width\@+sc_chunk\@*16],xmm1
                vpsrlq ymm2,ymm2,32
                vpshufd ymm2,ymm2,0x88
                vextracti128 xmm3,ymm2,1
                vpunpcklqdq xmm2,xmm2,xmm3
                vmovdqu [rsp+2*sc_width\@+sc_chunk\@*16],xmm2
            .endif
            .set sc_chunk\@,sc_chunk\@+1
        .endr
    .endif
    .if \lanes == 1
        .if \bits == 64
            movsd xmm0,[rsp]; mulsd xmm0,xmm0; movsd xmm1,xmm0
            movsd xmm2,[rip+.Lsc_s\@]; movsd xmm3,[rip+.Lsc_c\@]
            .set sc_i\@,1
            .rept 9
                mulsd xmm2,xmm1; addsd xmm2,[rip+.Lsc_s\@+sc_i\@*8]
                mulsd xmm3,xmm1; addsd xmm3,[rip+.Lsc_c\@+sc_i\@*8]
                .set sc_i\@,sc_i\@+1
            .endr
            mulsd xmm2,[rsp]
        .else
            movss xmm0,[rsp]; mulss xmm0,xmm0; movss xmm1,xmm0
            movss xmm2,[rip+.Lsc_s\@]; movss xmm3,[rip+.Lsc_c\@]
            .set sc_i\@,1
            .rept 9
                mulss xmm2,xmm1; addss xmm2,[rip+.Lsc_s\@+sc_i\@*4]
                mulss xmm3,xmm1; addss xmm3,[rip+.Lsc_c\@+sc_i\@*4]
                .set sc_i\@,sc_i\@+1
            .endr
            mulss xmm2,[rsp]
        .endif
        movq xmm0,[rsp+sc_width\@]
        .if (\mode & 1) == 0
            andpd xmm3,xmm0; andnpd xmm0,xmm2; orpd xmm0,xmm3
        .else
            andpd xmm2,xmm0; andnpd xmm0,xmm3; orpd xmm0,xmm2
        .endif
        movq xmm1,[rsp+2*sc_width\@]; xorpd xmm0,xmm1
        .if \bits == 64
            movsd [rdi],xmm0
        .else
            movss [rdi],xmm0
        .endif
        movdqu xmm0,[rsp+3*sc_width\@]
        movdqu xmm1,[rsp+3*sc_width\@+16]
        movdqu xmm2,[rsp+3*sc_width\@+32]
        movdqu xmm3,[rsp+3*sc_width\@+48]
    .else
        vmovu\kind \v0,[rsp]; vmul\kind \v1,\v0,\v0
        vmovu\kind \v2,[rip+.Lsc_s\@]; vmovu\kind \v3,[rip+.Lsc_c\@]
        .set sc_i\@,1
        .rept 9
            vmul\kind \v2,\v2,\v1
            vadd\kind \v2,\v2,[rip+.Lsc_s\@+sc_i\@*sc_width\@]
            vmul\kind \v3,\v3,\v1
            vadd\kind \v3,\v3,[rip+.Lsc_c\@+sc_i\@*sc_width\@]
            .set sc_i\@,sc_i\@+1
        .endr
        vmul\kind \v2,\v2,\v0; vmovu\kind \v0,[rsp+sc_width\@]
        .if \mode >= 2
            .if \bits != 64 || (\lanes != 4 && \lanes != 8)
                .error "dual projection requires declared natural f64 packet geometry"
            .endif
            .if \lanes == 8
                PHYSICAL_SINCOS_DUAL \v0,\v1,\v2,\v3,zmm4,sc_width\@,\mode
            .else
                PHYSICAL_SINCOS_DUAL \v0,\v1,\v2,\v3,ymm4,sc_width\@,\mode
            .endif
        .else
        .if (\mode & 1) == 0
            vand\kind \v3,\v3,\v0; vandn\kind \v0,\v0,\v2; vor\kind \v0,\v0,\v3
        .else
            vand\kind \v2,\v2,\v0; vandn\kind \v0,\v0,\v3; vor\kind \v0,\v0,\v2
        .endif
        vxor\kind \v0,\v0,[rsp+2*sc_width\@]; vmovu\kind [rdi],\v0
        .endif
    .endif
    add rsp,sc_frame\@
    pop r11; pop r10; pop r9; pop r8
    pop rdi; pop rsi; pop rbx; pop rdx; pop rcx; pop rax
    jmp .Lsc_end\@
# XMM0 argument -> reduced XMM0, ECX quadrant, R11 source sign payload.
.Lsc_reduce\@:
    .if \lanes == 1
        movq rax,xmm0
    .else
        vmovq rax,xmm0
    .endif
    mov r11,rax; mov r8,rax; btr r8,63
    mov rax,0x3fe921fb54442d18; cmp r8,rax; jbe .Lsc_central\@
    mov rax,0x7ff0000000000000; cmp r8,rax; jae .Lsc_nonfinite\@
    mov rcx,r8; shr rcx,52; sub ecx,1023
    mov eax,2111; sub eax,ecx; mov ecx,eax; and ecx,63; shr eax,6
    lea r9,[rip+.Lsc_two_pi\@]; lea r9,[r9+rax*8]
    mov rax,0x000fffffffffffff; and r8,rax; bts r8,52
    mov rax,[r9]; mov rdx,[r9+8]; shrd rax,rdx,cl
    mov r10,[r9+8]; mov rdx,[r9+16]; shrd r10,rdx,cl
    sub rsp,8
    mul r8; mov [rsp],rax; mov r9,rdx
    mov rax,r10; mul r8; add rax,r9; adc rdx,0
    mov r8,[rsp]; shrd r8,rax,53
    shrd rax,rdx,53
    mov rdx,r8; shr rdx,63; add rax,rdx; and eax,3; mov ecx,eax
    .if \lanes == 1
        pxor xmm0,xmm0; cvtsi2sd xmm0,r8; mulsd xmm0,[rip+.Lsc_scale\@]
    .else
        vxorpd xmm0,xmm0,xmm0; vcvtsi2sd xmm0,xmm0,r8; vmulsd xmm0,xmm0,[rip+.Lsc_scale\@]
    .endif
    add rsp,8; ret
.Lsc_central\@:
    .if \lanes == 1
        movq xmm0,r8
    .else
        vmovq xmm0,r8
    .endif
    xor ecx,ecx; ret
.Lsc_nonfinite\@:
    .if \lanes == 1
        subsd xmm0,xmm0
    .else
        vsubsd xmm0,xmm0,xmm0
    .endif
    xor ecx,ecx; ret
.if \lanes > 1
.Lsc_reduce4\@:
    sub rsp,192
    vmovupd [rsp],ymm0
    vpand ymm3,ymm0,[rip+.Lsc_abs4\@]
    vpsrlq ymm4,ymm3,52
    vpsubq ymm4,ymm4,[rip+.Lsc_bias4\@]
    vpcmpgtq ymm5,ymm4,[rip+.Lsc_minus1_4\@]
    vmovdqu ymm6,[rip+.Lsc_minus1_4\@]
    vblendvpd ymm4,ymm6,ymm4,ymm5
    vmovdqu ymm13,[rip+.Lsc_window4\@]
    vpsubq ymm13,ymm13,ymm4
    vpsrlq ymm14,ymm13,6
    vpand ymm13,ymm13,[rip+.Lsc_63_4\@]
    vpand ymm4,ymm3,[rip+.Lsc_sig4\@]
    vpor ymm4,ymm4,[rip+.Lsc_hidden4\@]
    vmovdqu ymm15,[rip+.Lsc_32mask4\@]
    lea r9,[rip+.Lsc_two_pi\@]
    # A 53-bit significand needs a 119-bit table window for 64 fractional
    # product bits. Discarded lower table bits contribute strictly less than
    # one 2^-64 phase unit; the eleven guard bits exceed the f64 significand.
    .set sc_p\@,0
    .rept 3
        vpcmpeqd ymm8,ymm8,ymm8
        vpgatherqq ymm5,[r9+ymm14*8+sc_p\@*8],ymm8
        vmovdqu [rsp+32+sc_p\@*32],ymm5
        .set sc_p\@,sc_p\@+1
    .endr
    vmovdqu ymm9,[rip+.Lsc_64_4\@]
    vpsubq ymm9,ymm9,ymm13
    vmovdqu ymm5,[rsp+32]; vmovdqu ymm6,[rsp+64]
    vpsrlvq ymm5,ymm5,ymm13
    vpsllvq ymm8,ymm6,ymm9
    vpor ymm5,ymm5,ymm8
    vpsrlvq ymm6,ymm6,ymm13
    vmovdqu ymm8,[rsp+96]
    vpsllvq ymm8,ymm8,ymm9
    vpor ymm6,ymm6,ymm8
    vmovdqu [rsp+128],ymm6
    call .Lsc_mul4\@
    vmovdqu [rsp+32],ymm6
    vmovdqa ymm12,ymm7
    vmovdqu ymm5,[rsp+128]
    call .Lsc_mul4\@
    vmovdqa ymm8,ymm6
    vpaddq ymm6,ymm6,ymm12
    vpand ymm9,ymm8,ymm12
    vpor ymm10,ymm8,ymm12
    vpandn ymm10,ymm6,ymm10
    vpor ymm9,ymm9,ymm10
    vpsrlq ymm9,ymm9,63
    vpaddq ymm7,ymm7,ymm9
    vmovdqu ymm8,[rsp+32]
    vpsrlq ymm8,ymm8,53
    vpsllq ymm9,ymm6,11
    vpor ymm8,ymm8,ymm9
    vpsrlq ymm6,ymm6,53
    vpsllq ymm7,ymm7,11
    vpor ymm7,ymm7,ymm6
    vmovdqa ymm6,ymm8
    vpsrlq ymm8,ymm6,63
    vpaddq ymm7,ymm7,ymm8
    vpand ymm7,ymm7,[rip+.Lsc_3_4\@]
    # Signed i64 -> f64 through two exact i32 pieces (AVX2 has no QQ conversion).
    vpsrlq ymm1,ymm6,32
    vpshufd ymm1,ymm1,0x88
    vextracti128 xmm2,ymm1,1
    vpunpcklqdq xmm1,xmm1,xmm2
    vcvtdq2pd ymm1,xmm1
    vpxor ymm2,ymm6,[rip+.Lsc_lo_sign4\@]
    vpshufd ymm2,ymm2,0x88
    vextracti128 xmm0,ymm2,1
    vpunpcklqdq xmm2,xmm2,xmm0
    vcvtdq2pd ymm2,xmm2
    vmulpd ymm1,ymm1,[rip+.Lsc_pow32_4\@]
    vaddpd ymm2,ymm2,[rip+.Lsc_pow31_4\@]
    vaddpd ymm0,ymm1,ymm2
    vmulpd ymm0,ymm0,[rip+.Lsc_scale4\@]
    vmovupd ymm2,[rsp]
    vpand ymm3,ymm2,[rip+.Lsc_abs4\@]
    vpcmpgtq ymm1,ymm3,[rip+.Lsc_pi4_4\@]
    vblendvpd ymm0,ymm3,ymm0,ymm1
    vpand ymm7,ymm7,ymm1
    vpcmpgtq ymm1,ymm3,[rip+.Lsc_finite4\@]
    vsubpd ymm2,ymm2,ymm2
    vblendvpd ymm0,ymm0,ymm2,ymm1
    vpand ymm1,ymm7,[rip+.Lsc_one4\@]
    vpxor ymm2,ymm2,ymm2
    vpsubq ymm1,ymm2,ymm1
    .if (\mode & 1) == 0
        vpsrlq ymm2,ymm7,1
        vmovdqu ymm3,[rsp]
        vpsrlq ymm3,ymm3,63
        vpxor ymm2,ymm2,ymm3
    .else
        vpaddq ymm2,ymm7,[rip+.Lsc_one4\@]
        vpsrlq ymm2,ymm2,1
    .endif
    vpand ymm2,ymm2,[rip+.Lsc_one4\@]
    vpsllq ymm2,ymm2,63
    add rsp,192; ret
# a=YMM4, b=YMM5 -> low=YMM6, high=YMM7. All four products are
# independently represented; middle sums fit in 34 bits before carry removal.
.Lsc_mul4\@:
    vpmuludq ymm6,ymm4,ymm5
    vpsrlq ymm8,ymm4,32; vpsrlq ymm9,ymm5,32
    vpmuludq ymm10,ymm8,ymm5
    vpmuludq ymm11,ymm4,ymm9
    vpmuludq ymm7,ymm8,ymm9
    vpsrlq ymm8,ymm6,32
    vpand ymm9,ymm10,ymm15
    vpaddq ymm8,ymm8,ymm9
    vpand ymm9,ymm11,ymm15
    vpaddq ymm8,ymm8,ymm9
    vpsrlq ymm10,ymm10,32
    vpsrlq ymm11,ymm11,32
    vpaddq ymm7,ymm7,ymm10
    vpaddq ymm7,ymm7,ymm11
    vpsrlq ymm9,ymm8,32
    vpaddq ymm7,ymm7,ymm9
    vpand ymm6,ymm6,ymm15
    vpsllq ymm8,ymm8,32
    vpor ymm6,ymm6,ymm8
    ret
.p2align 5
.Lsc_abs4\@: .rept 4; .quad 0x7fffffffffffffff; .endr
.Lsc_bias4\@: .rept 4; .quad 1023; .endr
.Lsc_minus1_4\@: .rept 4; .quad -1; .endr
.Lsc_window4\@: .rept 4; .quad 2111; .endr
.Lsc_63_4\@: .rept 4; .quad 63; .endr
.Lsc_64_4\@: .rept 4; .quad 64; .endr
.Lsc_sig4\@: .rept 4; .quad 0x000fffffffffffff; .endr
.Lsc_hidden4\@: .rept 4; .quad 0x0010000000000000; .endr
.Lsc_32mask4\@: .rept 4; .quad 0xffffffff; .endr
.Lsc_3_4\@: .rept 4; .quad 3; .endr
.Lsc_one4\@: .rept 4; .quad 1; .endr
.Lsc_pi4_4\@: .rept 4; .quad 0x3fe921fb54442d18; .endr
.Lsc_finite4\@: .rept 4; .quad 0x7fefffffffffffff; .endr
.Lsc_lo_sign4\@: .rept 4; .quad 0x80000000; .endr
.Lsc_pow32_4\@: .rept 4; .double 4294967296.0; .endr
.Lsc_pow31_4\@: .rept 4; .double 2147483648.0; .endr
.Lsc_scale4\@: .rept 4; .quad 0x3bf921fb54442d18; .endr
.endif
.Lsc_scale\@: .quad 0x3bf921fb54442d18
.p2align 3
.Lsc_two_pi\@:
    .quad 0xfa6ed5772d30433b
    .quad 0x87f121907c7c246a
    .quad 0x9f3a1f35caf27f1d
    .quad 0xc33d26ef6b1e5ef8
    .quad 0x32c2de4f98327dbb
    .quad 0xa5ff07053f7e33e8
    .quad 0xddaf44d15719053e
    .quad 0x8359c4768b961ca6
    .quad 0x19c367cddce8092a
    .quad 0x60e27bc08c6b47c4
    .quad 0x06061556ca73a8c9
    .quad 0x8dffd8804d732731
    .quad 0x6599855f14a06840
    .quad 0xa9e391615ee61b08
    .quad 0xf0cfbc209af4361d
    .quad 0x56033046fc7b6bab
    .quad 0x6bfb5fb11f8d5d08
    .quad 0x3d0739f78a5292ea
    .quad 0x7527bac7ebe5f17b
    .quad 0x4f463f669e5fea2d
    .quad 0x6d367ecf27cb09b7
    .quad 0xef2f118b5a0a6d1f
    .quad 0x1ff897ffde05980f
    .quad 0x9c845f8bbdf9283b
    .quad 0x3991d639835339f4
    .quad 0xe99c7026b45f7e41
    .quad 0xe88235f52ebb4484
    .quad 0xfe1deb1cb129a73e
    .quad 0x06492eea09d1921c
    .quad 0xb7246e3a424dd2e0
    .quad 0xfe5163abdebbc561
    .quad 0xdb6295993c439041
    .quad 0xfc2757d1f534ddc0
    .quad 0xa2f9836e4e441529
    .quad 0x0000000000000000
    .quad 0x0000000000000000

.Lsc_s\@:
    .rept \lanes
        .if \bits == 64
            .double -8.220635246624329496e-18
        .else
            .float -8.220635246624329496e-18
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 2.811457254345520598e-15
        .else
            .float 2.811457254345520598e-15
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -7.647163731819816406e-13
        .else
            .float -7.647163731819816406e-13
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 1.605904383682161334e-10
        .else
            .float 1.605904383682161334e-10
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -2.505210838544172022e-08
        .else
            .float -2.505210838544172022e-08
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 2.755731922398589251e-06
        .else
            .float 2.755731922398589251e-06
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -1.984126984126984125e-04
        .else
            .float -1.984126984126984125e-04
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 8.333333333333333218e-03
        .else
            .float 8.333333333333333218e-03
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -1.666666666666666574e-01
        .else
            .float -1.666666666666666574e-01
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 1.000000000000000000e+00
        .else
            .float 1.000000000000000000e+00
        .endif
    .endr

.Lsc_c\@:
    .rept \lanes
        .if \bits == 64
            .double -1.561920696858622527e-16
        .else
            .float -1.561920696858622527e-16
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 4.779477332387385253e-14
        .else
            .float 4.779477332387385253e-14
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -1.147074559772972451e-11
        .else
            .float -1.147074559772972451e-11
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 2.087675698786810019e-09
        .else
            .float 2.087675698786810019e-09
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -2.755731922398588828e-07
        .else
            .float -2.755731922398588828e-07
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 2.480158730158730157e-05
        .else
            .float 2.480158730158730157e-05
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -1.388888888888888942e-03
        .else
            .float -1.388888888888888942e-03
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 4.166666666666666435e-02
        .else
            .float 4.166666666666666435e-02
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double -5.000000000000000000e-01
        .else
            .float -5.000000000000000000e-01
        .endif
    .endr
    .rept \lanes
        .if \bits == 64
            .double 1.000000000000000000e+00
        .else
            .float 1.000000000000000000e+00
        .endif
    .endr

.Lsc_end\@:
\name\()_end:
.endm
PHYSICAL_SINCOS gc_sin_f64,64,1,0,xmm0,xmm1,xmm2,xmm3,pd
PHYSICAL_SINCOS gc_sin_f32,32,1,0,xmm0,xmm1,xmm2,xmm3,ps
PHYSICAL_SINCOS gc_sin_f64_4,64,4,0,ymm0,ymm1,ymm2,ymm3,pd
PHYSICAL_SINCOS gc_sin_f64_8,64,8,0,zmm0,zmm1,zmm2,zmm3,pd
PHYSICAL_SINCOS gc_sin_f32_4,32,4,0,xmm0,xmm1,xmm2,xmm3,ps
PHYSICAL_SINCOS gc_sin_f32_8,32,8,0,ymm0,ymm1,ymm2,ymm3,ps
PHYSICAL_SINCOS gc_sin_f32_16,32,16,0,zmm0,zmm1,zmm2,zmm3,ps
PHYSICAL_SINCOS gc_cos_f64,64,1,1,xmm0,xmm1,xmm2,xmm3,pd
PHYSICAL_SINCOS gc_cos_f32,32,1,1,xmm0,xmm1,xmm2,xmm3,ps
PHYSICAL_SINCOS gc_cos_f64_4,64,4,1,ymm0,ymm1,ymm2,ymm3,pd
PHYSICAL_SINCOS gc_cos_f64_8,64,8,1,zmm0,zmm1,zmm2,zmm3,pd
PHYSICAL_SINCOS gc_cos_f32_4,32,4,1,xmm0,xmm1,xmm2,xmm3,ps
PHYSICAL_SINCOS gc_cos_f32_8,32,8,1,ymm0,ymm1,ymm2,ymm3,ps
PHYSICAL_SINCOS gc_cos_f32_16,32,16,1,zmm0,zmm1,zmm2,zmm3,ps

PHYSICAL_SINCOS gc_sincos_f64_4,64,4,2,ymm0,ymm1,ymm2,ymm3,pd
PHYSICAL_SINCOS gc_sincos_f64_8,64,8,2,zmm0,zmm1,zmm2,zmm3,pd
PHYSICAL_SINCOS gc_cossin_f64_4,64,4,3,ymm0,ymm1,ymm2,ymm3,pd
PHYSICAL_SINCOS gc_cossin_f64_8,64,8,3,zmm0,zmm1,zmm2,zmm3,pd
