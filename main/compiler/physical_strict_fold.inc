# One strict ordered fold: same parenthesization and lane order as the scalar
# relation. The completed payload's actual carrier selects memory or register
# operands. Lane projections preserve every bit; the accumulator crosses the
# integer/FP boundary once per carrier. Neither form reassociates the fold.
.macro PHYSICAL_STRICT_FOLD name,bits,lanes,register
\name:
    .if \bits == 64
      .if \register
        .if \lanes == 8
            vextractf64x4 ymm1,zmm0,1
            vextractf128 xmm2,ymm0,1
        .else
            vextractf128 xmm1,ymm0,1
        .endif
        vmovq xmm3,r11
        vaddsd xmm3,xmm3,xmm0
        vshufpd xmm0,xmm0,xmm0,1
        vaddsd xmm3,xmm3,xmm0
        .if \lanes == 8
            vaddsd xmm3,xmm3,xmm2
            vshufpd xmm2,xmm2,xmm2,1
            vaddsd xmm3,xmm3,xmm2
            vextractf128 xmm2,ymm1,1
        .endif
        vaddsd xmm3,xmm3,xmm1
        vshufpd xmm1,xmm1,xmm1,1
        vaddsd xmm3,xmm3,xmm1
        .if \lanes == 8
            vaddsd xmm3,xmm3,xmm2
            vshufpd xmm2,xmm2,xmm2,1
            vaddsd xmm3,xmm3,xmm2
        .endif
        vmovq r11,xmm3
      .else
        vmovq xmm3,r11
        .set pf_i\@,0
        .rept \lanes
            vaddsd xmm3,xmm3,[rsp+pf_i\@*8]
            .set pf_i\@,pf_i\@+1
        .endr
        vmovq r11,xmm3
      .endif
    .else
      .if \register
        .if \lanes == 8
            vextractf128 xmm1,ymm0,1
        .endif
        vmovd xmm3,r11d
        .set pf_i\@,0
        .rept 4
            vaddss xmm3,xmm3,xmm0
            .if pf_i\@ < 3
                vshufps xmm0,xmm0,xmm0,0x39
            .endif
            .set pf_i\@,pf_i\@+1
        .endr
        .if \lanes == 8
            .set pf_i\@,0
            .rept 4
                vaddss xmm3,xmm3,xmm1
                .if pf_i\@ < 3
                    vshufps xmm1,xmm1,xmm1,0x39
                .endif
                .set pf_i\@,pf_i\@+1
            .endr
        .endif
        vmovd r11d,xmm3
      .else
        vmovd xmm3,r11d
        .set pf_i\@,0
        .rept \lanes
            vaddss xmm3,xmm3,[rsp+pf_i\@*4]
            .set pf_i\@,pf_i\@+1
        .endr
        vmovd r11d,xmm3
      .endif
    .endif
\name\()_end:
.endm
.pushsection .rodata
PHYSICAL_STRICT_FOLD physical_fold_f64_4,64,4,0
PHYSICAL_STRICT_FOLD physical_fold_f64_8,64,8,0
PHYSICAL_STRICT_FOLD physical_fold_f32_4,32,4,0
PHYSICAL_STRICT_FOLD physical_fold_f32_8,32,8,0
PHYSICAL_STRICT_FOLD physical_fold_f64_4_register,64,4,1
PHYSICAL_STRICT_FOLD physical_fold_f64_8_register,64,8,1
PHYSICAL_STRICT_FOLD physical_fold_f32_4_register,32,4,1
PHYSICAL_STRICT_FOLD physical_fold_f32_8_register,32,8,1
physical_strict_fold_table:
    .quad physical_fold_f64_4; .long physical_fold_f64_4_end-physical_fold_f64_4,0
    .quad physical_fold_f64_8; .long physical_fold_f64_8_end-physical_fold_f64_8,0
    .quad physical_fold_f32_4; .long physical_fold_f32_4_end-physical_fold_f32_4,0
    .quad physical_fold_f32_8; .long physical_fold_f32_8_end-physical_fold_f32_8,0
    .quad physical_fold_f64_4_register; .long physical_fold_f64_4_register_end-physical_fold_f64_4_register,0
    .quad physical_fold_f64_8_register; .long physical_fold_f64_8_register_end-physical_fold_f64_8_register,0
    .quad physical_fold_f32_4_register; .long physical_fold_f32_4_register_end-physical_fold_f32_4_register,0
    .quad physical_fold_f32_8_register; .long physical_fold_f32_8_register_end-physical_fold_f32_8_register,0
.popsection
.global physical_strict_fold_fragment
physical_strict_fold_fragment:
    cmp edx,1; ja 3f
    xor eax,eax; cmp edi,64; je 1f
    cmp edi,32; jne 3f
    mov eax,2
1:  bsr ecx,esi; sub ecx,2; cmp ecx,1; ja 3f
    add eax,ecx; shl edx,2; add eax,edx; shl eax,4
    lea rdx,[rip+physical_strict_fold_table]
    mov ecx,[rdx+rax+8]; mov rax,[rdx+rax]; ret
3:  xor eax,eax; xor ecx,ecx; ret
