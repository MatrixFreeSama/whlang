s_expand_bessel_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,512
    mov [rsp],rdi; mov [rsp+8],esi
    mov edi,OP_ABS; mov rsi,[rsp+0]; call s_ast_unary_new
    test rax,rax; jz .sbj_fail; mov [rsp+16],rax
    mov edi,OP_SQUARE; mov rsi,[rsp+0]; call s_ast_unary_new
    test rax,rax; jz .sbj_fail; mov [rsp+24],rax
    mov eax,[rsp+8]; imul eax,24; lea rsi,[rip+s_bj_small_desc]; add rsi,rax
    mov rdi,[rsp+24]; call s_bessel_quotient_ast
    test rax,rax; jz .sbj_fail; mov [rsp+32],rax
    mov rdi,0x3ff0000000000000; call s_math_const_bits
    test rax,rax; jz .sbj_fail; mov [rsp+56],rax
    mov rdi,0x3fd0000000000000; call s_math_const_bits
    test rax,rax; jz .sbj_fail; mov [rsp+72],rax
    mov edi,OP_MUL; mov rsi,[rsp+72]; mov rdx,[rsp+24]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+64],rax
    mov edi,OP_SUB; mov rsi,[rsp+56]; mov rdx,[rsp+64]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+48],rax
    mov edi,OP_SQUARE; mov rsi,[rsp+24]; call s_ast_unary_new
    test rax,rax; jz .sbj_fail; mov [rsp+88],rax
    mov edi,OP_MUL; mov rsi,[rsp+88]; mov rdx,[rsp+32]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+80],rax
    mov edi,OP_ADD; mov rsi,[rsp+48]; mov rdx,[rsp+80]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+40],rax
    mov rdi,0x3fe0000000000000; call s_math_const_bits
    test rax,rax; jz .sbj_fail; mov [rsp+112],rax
    mov edi,OP_MUL; mov rsi,[rsp+24]; mov rdx,[rsp+32]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+120],rax
    mov edi,OP_ADD; mov rsi,[rsp+112]; mov rdx,[rsp+120]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+104],rax
    mov edi,OP_MUL; mov rsi,[rsp+0]; mov rdx,[rsp+104]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+96],rax
    mov rdi,[rsp+16]; mov esi,[rsp+8]; shl esi,1; add esi,0; call s_bessel_correction_ast
    test rax,rax; jz .sbj_fail; mov [rsp+128],rax
    mov rdi,[rsp+16]; mov esi,[rsp+8]; shl esi,1; add esi,1; call s_bessel_correction_ast
    test rax,rax; jz .sbj_fail; mov [rsp+136],rax
    mov rdi,0x3fe20dd750429b6d; call s_math_const_bits
    test rax,rax; jz .sbj_fail; mov [rsp+160],rax
    mov edi,OP_SQRT; mov rsi,[rsp+16]; call s_ast_unary_new
    test rax,rax; jz .sbj_fail; mov [rsp+168],rax
    mov edi,OP_DIV; mov rsi,[rsp+160]; mov rdx,[rsp+168]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+152],rax
    mov edi,OP_SIN; mov rsi,[rsp+16]; call s_ast_unary_new
    test rax,rax; jz .sbj_fail; mov [rsp+200],rax
    mov edi,OP_COS; mov rsi,[rsp+16]; call s_ast_unary_new
    test rax,rax; jz .sbj_fail; mov [rsp+208],rax
    mov edi,OP_ADD; mov rsi,[rsp+200]; mov rdx,[rsp+208]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+192],rax
    mov edi,OP_MUL; mov rsi,[rsp+128]; mov rdx,[rsp+192]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+184],rax
    mov edi,OP_SUB; mov rsi,[rsp+200]; mov rdx,[rsp+208]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+224],rax
    mov edi,OP_MUL; mov rsi,[rsp+136]; mov rdx,[rsp+224]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+216],rax
    mov edi,OP_SUB; mov rsi,[rsp+184]; mov rdx,[rsp+216]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+176],rax
    mov edi,OP_MUL; mov rsi,[rsp+152]; mov rdx,[rsp+176]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+144],rax
    mov rdi,0x0000000000000000; call s_math_const_bits
    test rax,rax; jz .sbj_fail; mov [rsp+248],rax
    mov edi,OP_LT; mov rsi,[rsp+0]; mov rdx,[rsp+248]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+240],rax
    mov edi,OP_MUL; mov rsi,[rsp+128]; mov rdx,[rsp+224]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+280],rax
    mov edi,OP_MUL; mov rsi,[rsp+136]; mov rdx,[rsp+192]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+288],rax
    mov edi,OP_ADD; mov rsi,[rsp+280]; mov rdx,[rsp+288]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+272],rax
    mov edi,OP_MUL; mov rsi,[rsp+152]; mov rdx,[rsp+272]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+264],rax
    mov edi,OP_NEG; mov rsi,[rsp+264]; call s_ast_unary_new
    test rax,rax; jz .sbj_fail; mov [rsp+256],rax
    mov rdi,[rsp+240]; mov rsi,[rsp+256]; mov rdx,[rsp+264]; call s_ast_select_new
    test rax,rax; jz .sbj_fail; mov [rsp+232],rax
    mov rax,[rsp+40]; mov rdx,[rsp+144]
    cmp dword ptr [rsp+8],0; je .sbj_order_done
    mov rax,[rsp+96]; mov rdx,[rsp+232]
.sbj_order_done:
    mov [rsp+296],rax; mov [rsp+304],rdx
    mov rdi,0x4000000000000000; call s_math_const_bits
    test rax,rax; jz .sbj_fail; mov [rsp+328],rax
    mov edi,OP_LT; mov rsi,[rsp+16]; mov rdx,[rsp+328]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+320],rax
    mov rdi,[rsp+320]; mov rsi,[rsp+296]; mov rdx,[rsp+304]; call s_ast_select_new
    test rax,rax; jz .sbj_fail; mov [rsp+312],rax
    mov rdi,0x7ff0000000000000; call s_math_const_bits
    mov [rsp+336],rax
    mov edi,OP_EQ; mov rsi,[rsp+16]; mov rdx,[rsp+336]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+352],rax
    mov edi,OP_DIV; mov rsi,[rsp+56]; mov rdx,[rsp+16]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+360],rax
    mov edi,OP_EQ; mov rsi,[rsp+0]; mov rdx,[rsp+248]; call s_ast_scalar_binary_new
    test rax,rax; jz .sbj_fail; mov [rsp+376],rax
    mov rdi,[rsp+376]; mov rsi,[rsp+296]; mov rdx,[rsp+312]; call s_ast_select_new
    test rax,rax; jz .sbj_fail; mov [rsp+368],rax
    mov rdi,[rsp+352]; mov rsi,[rsp+360]; mov rdx,[rsp+368]; call s_ast_select_new
    test rax,rax; jz .sbj_fail; mov [rsp+344],rax
    mov rax,[rsp+344]; jmp .sbj_done
.sbj_fail: xor eax,eax
.sbj_done: add rsp,512; pop r15; pop r14; pop r13; pop r12; pop rbx; ret
# rdi=z, rsi=coefficient descriptor -> one ordinary rational AST.
s_bessel_quotient_ast:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13,rsi
    mov rsi,[r13]; mov edx,[r13+16]; call s_math_poly_horner; mov rbx,rax
    test rbx,rbx; jz .sbq_done
    mov rdi,r12; mov rsi,[r13+8]; mov edx,[r13+20]; call s_math_poly_horner
    mov edi,OP_DIV; mov rsi,rbx; mov rdx,rax; call s_ast_scalar_binary_new
.sbq_done: pop r13; pop r12; pop rbx; ret

# rdi=abs(x), esi=2*order+P/Q. One interval/quotient authority for both orders.
s_bessel_correction_ast:
    push rbx; push r12; push r13; push r14; push r15
    sub rsp,48
    mov r12,rdi; mov [rsp+32],esi
    imul esi,96; lea r13,[rip+s_bj_desc]; add r13,rsi
    call s_struct_one; mov r14,rax
    mov edi,OP_DIV; mov rsi,r14; mov rdx,r12; call s_ast_scalar_binary_new
    mov edi,OP_SQUARE; mov rsi,rax; call s_ast_unary_new; mov r15,rax
    mov rdi,r15; lea rsi,[r13+72]; call s_bessel_quotient_ast; mov rbx,rax
    mov dword ptr [rsp+40],2
.sbc_interval:
    mov eax,[rsp+40]; imul eax,24; lea rsi,[r13+rax]; mov rdi,r15
    call s_bessel_quotient_ast; mov [rsp],rax
    mov eax,[rsp+40]; lea rcx,[rip+s_bj_bounds]; mov rdi,[rcx+rax*8]; call s_math_const_bits
    mov edi,OP_GE; mov rsi,r12; mov rdx,rax; call s_ast_scalar_binary_new
    mov rdi,rax; mov rsi,[rsp]; mov rdx,rbx; call s_ast_select_new; mov rbx,rax
    sub dword ptr [rsp+40],1; jns .sbc_interval
    test dword ptr [rsp+32],1; jnz .sbc_q
    mov edi,OP_ADD; mov rsi,r14; mov rdx,rbx; call s_ast_scalar_binary_new; jmp .sbc_done
.sbc_q:
    mov rdi,0xbfc0000000000000
    cmp dword ptr [rsp+32],1; je 1f
    mov rdi,0x3fd8000000000000
1:  call s_math_const_bits
    mov edi,OP_ADD; mov rsi,rax; mov rdx,rbx; call s_ast_scalar_binary_new
    mov edi,OP_DIV; mov rsi,rax; mov rdx,r12; call s_ast_scalar_binary_new
.sbc_done: add rsp,48; pop r15; pop r14; pop r13; pop r12; pop rbx; ret

.section .rodata
# Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
# Developed at SunSoft, a Sun Microsystems, Inc. business.
# Permission to use, copy, modify, and distribute this software is freely
# granted, provided that this notice is preserved.
# fdlibm e_j0.c/e_j1.c rational coefficients, same mathematical intervals.
s_bj_0pr8:
    .quad 0xc0b4850b36cc643d
    .quad 0xc0a36a6ecd4dcafc
    .quad 0xc07011027b19e863
    .quad 0xc02029d0b44fa779
    .quad 0xbfb1fffffffffd32
    .quad 0x0000000000000000
s_bj_0ps8:
    .quad 0x40e741774f2c49dc
    .quad 0x40fc810f8f9fa9bd
    .quad 0x40e3d2bb6eb6b05f
    .quad 0x40adf37d50596938
    .quad 0x405d223307a96751
    .quad 0x3ff0000000000000
s_bj_0pr5:
    .quad 0xc075a6ef28a38bd7
    .quad 0xc074b3b36742cc63
    .quad 0xc050eb2f5a7d1783
    .quad 0xc010a370f90c6bbf
    .quad 0xbfb1ffffe69afbc6
    .quad 0xbda918b147e495cc
s_bj_0ps5:
    .quad 0x40a2cc1dc70be864
    .quad 0x40c2ccb8fa76fa38
    .quad 0x40b75af88fbe1d60
    .quad 0x40906d025c7e2864
    .quad 0x404e60810c98c5de
    .quad 0x3ff0000000000000
s_bj_0pr3:
    .quad 0xc03f72aca892d80f
    .quad 0xc04d0a22420a1a45
    .quad 0xc035f74a4cb94e14
    .quad 0xc00345b2aea48074
    .quad 0xbfb1fff6f7c0e24b
    .quad 0xbe25e1036fe1aa86
s_bj_0ps3:
    .quad 0x4065b296fc379081
    .quad 0x40919ffcb8c39b7e
    .quad 0x4092a66e6d1061d6
    .quad 0x40769839464a7c0e
    .quad 0x4041ed9284077dd3
    .quad 0x3ff0000000000000
s_bj_0pr2:
    .quad 0xc009de81af8fe70f
    .quad 0xc02662e6c5246303
    .quad 0xc01e8af3edafa7f3
    .quad 0xbff736398a24a843
    .quad 0xbfb1ff62495e1e42
    .quad 0xbe77d316e927026d
s_bj_0ps2:
    .quad 0x402d50b344391809
    .quad 0x40633c033ab6faff
    .quad 0x4070e78642ea079b
    .quad 0x4061069e0ee8878f
    .quad 0x40363865908b5959
    .quad 0x3ff0000000000000
s_bj_0qr8:
    .quad 0x40e212d40e901566
    .quad 0x40c14d993e18f46d
    .quad 0x40816d6315301825
    .quad 0x402789525bb334d6
    .quad 0x3fb2bffffffffe2c
    .quad 0x0000000000000000
s_bj_0qs8:
    .quad 0xc114fd6d2c9530c5
    .quad 0x4129a66b28de0b3d
    .quad 0x412883da83a52b43
    .quad 0x4101665254d38c3f
    .quad 0x40bfa2584e6b0563
    .quad 0x406478d5365b39bc
    .quad 0x3ff0000000000000
s_bj_0qr5:
    .quad 0x409f17e953c6e3a6
    .quad 0x40900cf99dc8c481
    .quad 0x4060e3920a8788e9
    .quad 0x401757b0b9953dd3
    .quad 0x3fb2bfffd172b04c
    .quad 0x3db43d8f29cc8cd9
s_bj_0qs5:
    .quad 0xc0b4ea57bedbc609
    .quad 0x40e191181f7a54a0
    .quad 0x40ebb5e397e02372
    .quad 0x40d267d27b591e6d
    .quad 0x40a03ba0da21c0ce
    .quad 0x4054b1b3fb5e1543
    .quad 0x3ff0000000000000
s_bj_0qr3:
    .quad 0x4064d77c81fa21e0
    .quad 0x406559dbe25efd1f
    .quad 0x40454f98962daedd
    .quad 0x400ac0fc61149cf5
    .quad 0x3fb2bfee0e8d0842
    .quad 0x3e32cd036adecb82
s_bj_0qs3:
    .quad 0xc062a7eb201cf40f
    .quad 0x40a3a8aad94fb1c0
    .quad 0x40b93c6cd7c76a28
    .quad 0x40acf04be44dfc63
    .quad 0x40862d8386544eb3
    .quad 0x40486122bfe343a6
    .quad 0x3ff0000000000000
s_bj_0qr2:
    .quad 0x403040b171814bb4
    .quad 0x403faa8e29fbdc4a
    .quad 0x402cfdbfaaf96fe5
    .quad 0x3ffff897e727779c
    .quad 0x3fb2bec53e883e34
    .quad 0x3e84313b54f76bdb
s_bj_0qs2:
    .quad 0xc0153e6af8b32931
    .quad 0x406a95530e001365
    .quad 0x408b977c9c5cc214
    .quad 0x408a664522b3bf22
    .quad 0x4070d591e4d14b40
    .quad 0x403e5d96f7c07aed
    .quad 0x3ff0000000000000
s_bj_1pr8:
    .quad 0x40beea7ac32782dd
    .quad 0x40ae457da3a532cc
    .quad 0x4079c0d4652ea590
    .quad 0x402a7a9d357f7fce
    .quad 0x3fbdfffffffffcce
    .quad 0x0000000000000000
s_bj_1ps8:
    .quad 0x40de1511697a0b2d
    .quad 0x40f7d42cb28f17bb
    .quad 0x40e20b8697c5bb7f
    .quad 0x40ac85dc964d274f
    .quad 0x405c8d458e656cac
    .quad 0x3ff0000000000000
s_bj_1pr5:
    .quad 0x408085b8bb7e0cb7
    .quad 0x40802d16d052d649
    .quad 0x405b13b9452602ed
    .quad 0x401b36046e6315e3
    .quad 0x3fbdffffe2c10043
    .quad 0x3dad0667dae1ca7d
s_bj_1ps5:
    .quad 0x40978030036f5e51
    .quad 0x40bea4b0b8a5bb15
    .quad 0x40b4e9445706b6fb
    .quad 0x408efb361b066701
    .quad 0x404da3eaa8af633d
    .quad 0x3ff0000000000000
s_bj_1pr3:
    .quad 0x4048478f8ea83ee5
    .quad 0x4056c3854d2c1837
    .quad 0x40418f489da6d129
    .quad 0x400f76bce85ead8a
    .quad 0x3fbdfff55b21d17b
    .quad 0x3e29fc21a7ad9edd
s_bj_1ps3:
    .quad 0x4059f26d7c2eed53
    .quad 0x408bd67da32e31e9
    .quad 0x40905b7c5037d523
    .quad 0x40750c3307f1a75f
    .quad 0x40416549a134069c
    .quad 0x3ff0000000000000
s_bj_1pr2:
    .quad 0x40144b49a574c1fe
    .quad 0x4031b1a8177f8ee2
    .quad 0x40287c377f71a964
    .quad 0x4002f2b7f98faec0
    .quad 0x3fbdff42be760d83
    .quad 0x3e7ce9d4f65544f4
s_bj_1ps2:
    .quad 0x4020bab1f44e5192
    .quad 0x405d6b7ada1884a9
    .quad 0x406d08d8d5a2dbd9
    .quad 0x405f529314f92cd5
    .quad 0x40356fbd8ad5ecdc
    .quad 0x3ff0000000000000
s_bj_1qr8:
    .quad 0xc0e7a6d065d09c6a
    .quad 0xc0c724e740f87415
    .quad 0xc087bcd053e4b576
    .quad 0xc0304591a26779f7
    .quad 0xbfba3ffffffffdf3
    .quad 0x0000000000000000
s_bj_1qs8:
    .quad 0xc111f9690ea5aa18
    .quad 0x412457d27719ad5c
    .quad 0x4125f65372869c19
    .quad 0x4100579ab0b75e98
    .quad 0x40be9162d0d88419
    .quad 0x40642ca6de5bcde5
    .quad 0x3ff0000000000000
s_bj_1qr5:
    .quad 0xc0a468e388fda79d
    .quad 0xc09574c66931734f
    .quad 0xc066f56d6ca7b9b0
    .quad 0xc0201ce6ca03ad4b
    .quad 0xbfba3fffcb597fef
    .quad 0xbdb6fa431aa1a098
s_bj_1qs5:
    .quad 0xc0b26f2efcffa004
    .quad 0x40db4b04cf7c364b
    .quad 0x40e8576daabad197
    .quad 0x40d10f1f0d64ce29
    .quad 0x409f1f31e77bf839
    .quad 0x405451b2ff5a11b2
    .quad 0x3ff0000000000000
s_bj_1qr3:
    .quad 0xc06b66b95f5c1bf6
    .quad 0xc06c87d34718d55f
    .quad 0xc04cec71c25d16da
    .quad 0xc01270c23302d9ff
    .quad 0xbfba3feb51aeed54
    .quad 0xbe35cfa9d38fc84f
s_bj_1qs3:
    .quad 0xc060e670290a311f
    .quad 0x409dbc7a0dd4df4b
    .quad 0x40b5abbaa61d54a6
    .quad 0x40aa684e448e7c9a
    .quad 0x40850eebc031ee3e
    .quad 0x4047d523ccd367e4
    .quad 0x3ff0000000000000
s_bj_1qr2:
    .quad 0xc0355f3639cf6e52
    .quad 0xc04529a3de104aaa
    .quad 0xc033a9e2c168907f
    .quad 0xc006048469bb4eda
    .quad 0xbfba3e8e9148b010
    .quad 0xbe87f12644c626d2
s_bj_1qs2:
    .quad 0xc013d686e71be86b
    .quad 0x40637e5e3c3ed8d4
    .quad 0x40871b2548d4c029
    .quad 0x4087ac05ce49a0f7
    .quad 0x406f9f68db821cba
    .quad 0x403d888a78ae64ff
    .quad 0x3ff0000000000000
s_bj_small_r0:
    .quad 0xbe33d5e773d63fce
    .quad 0x3ebeb1d10c503919
    .quad 0xbf28e6a5b61ac6e9
    .quad 0x3f8ffffffffffffd
s_bj_small_s0:
    .quad 0x3e1408bcf4745d8f
    .quad 0x3ea13b54ce84d5a9
    .quad 0x3f1ea6d2dd57dbf4
    .quad 0x3f8ffce882c8c2a4
    .quad 0x3ff0000000000000
s_bj_small_r1:
    .quad 0x3e6aaafa46ca0bd8
    .quad 0xbef0c5c6ba169668
    .quad 0x3f570d9f98472c61
    .quad 0xbfb0000000000000
s_bj_small_s1:
    .quad 0x3dab2acfcfb97ed8
    .quad 0x3e35ac88c97dff2b
    .quad 0x3eb3bff8333f8498
    .quad 0x3f285f56b9cdf664
    .quad 0x3f939d0b12637e53
    .quad 0x3ff0000000000000
s_bj_small_desc:
    .quad s_bj_small_r0,s_bj_small_s0
    .long 4,5
    .quad s_bj_small_r1,s_bj_small_s1
    .long 4,6
s_bj_desc:
    .quad s_bj_0pr8,s_bj_0ps8
    .long 6,6
    .quad s_bj_0pr5,s_bj_0ps5
    .long 6,6
    .quad s_bj_0pr3,s_bj_0ps3
    .long 6,6
    .quad s_bj_0pr2,s_bj_0ps2
    .long 6,6
    .quad s_bj_0qr8,s_bj_0qs8
    .long 6,7
    .quad s_bj_0qr5,s_bj_0qs5
    .long 6,7
    .quad s_bj_0qr3,s_bj_0qs3
    .long 6,7
    .quad s_bj_0qr2,s_bj_0qs2
    .long 6,7
    .quad s_bj_1pr8,s_bj_1ps8
    .long 6,6
    .quad s_bj_1pr5,s_bj_1ps5
    .long 6,6
    .quad s_bj_1pr3,s_bj_1ps3
    .long 6,6
    .quad s_bj_1pr2,s_bj_1ps2
    .long 6,6
    .quad s_bj_1qr8,s_bj_1qs8
    .long 6,7
    .quad s_bj_1qr5,s_bj_1qs5
    .long 6,7
    .quad s_bj_1qr3,s_bj_1qs3
    .long 6,7
    .quad s_bj_1qr2,s_bj_1qs2
    .long 6,7
s_bj_bounds: .quad 0x4020000000000000,0x40122e8b00000000,0x4006db6d00000000
.text
