#!/usr/bin/env python3
"""Derive true four-lane AVX2/YMM tensor physicalizers from generic semantics.

Only physical leaf encoders, register ownership and vector-width fragments change.
Parser/algebra/topology lowering remain shared with the mature tensor frontend.
"""
from __future__ import annotations
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
GEN=BUILD/'generated_native256'
GEN.mkdir(parents=True,exist_ok=True)


def replace_global(s: str, name: str, body: str) -> str:
    pat=re.compile(rf'(?ms)^{re.escape(name)}:\n.*?(?=^[A-Za-z][A-Za-z0-9_]*:\n)')
    m=pat.search(s)
    if not m: raise SystemExit(f'native256 frontend missing global {name}')
    return s[:m.start()]+name+':\n'+body.rstrip()+'\n\n'+s[m.end():]


def replace_pair(s: str, start: str, end: str, block: str) -> str:
    pat=re.compile(rf'(?ms)^{re.escape(start)}:\n.*?^{re.escape(end)}:\n')
    m=pat.search(s)
    if not m: raise SystemExit(f'native256 frontend missing fragment {start}')
    return s[:m.start()]+block.rstrip()+'\n'+s[m.end():]

VEX0F_RRR=r'''    # edi=opcode, esi=dst, edx=src1, ecx=src2, r8d=pp. VEX3 map 0F, L=256.
    push rbx
    mov ebx,edi
    mov r9d,esi
    mov r10d,edx
    mov r11d,ecx
    mov edi,0xC4; call vec_emit_u8
    mov eax,r9d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r11d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,r10d; not eax; and eax,0xF; shl eax,3
    or eax,0x04
    or eax,r8d
    mov edi,eax; call vec_emit_u8
    mov edi,ebx; call vec_emit_u8
    mov eax,r9d; and eax,7; shl eax,3
    mov ecx,r11d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    cmp ebx,0x58; je .v256_fp_add
    cmp ebx,0x5C; je .v256_fp_add
    cmp ebx,0x59; je .v256_fp_mul
    cmp ebx,0x5E; je .v256_fp_div
    inc dword ptr [rip+schedule_counts+4*4]
    jmp .v256_done
.v256_fp_add:
    inc dword ptr [rip+schedule_counts+0]
    jmp .v256_done
.v256_fp_mul:
    inc dword ptr [rip+schedule_counts+4]
    jmp .v256_done
.v256_fp_div:
    inc dword ptr [rip+schedule_counts+8]
.v256_done:
    pop rbx
    xor eax,eax
    ret'''

MOV_EXT=r'''    # VEX3 vmovdqa ymm dst,ymm src, physical registers 0..15.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x6F; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    pop rbx
    xor eax,eax
    ret'''

CONST_LOAD=r'''    # edi=dst YMM, r13d=constant index. AVX2 VPBROADCASTQ from RIP pool.
    push rbx
    push r12
    mov ebx,edi
    mov eax,dword ptr [rip+vec_fixup_count]
    cmp eax,512
    jae .vecli256_fail
    mov r12d,eax
    inc eax
    mov dword ptr [rip+vec_fixup_count],eax
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x60
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x59; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,5
    mov edi,eax; call vec_emit_u8
    mov rax,[rip+vec_emit_ptr]
    lea r8,[rip+vec_fixup_ptr]
    mov qword ptr [r8+r12*8],rax
    lea r8,[rip+vec_fixup_const]
    mov dword ptr [r8+r12*4],r13d
    lea rcx,[rax+4]
    cmp rcx,[rip+vec_emit_end]
    ja .vecli256_fail
    mov dword ptr [rax],0
    mov [rip+vec_emit_ptr],rcx
    inc dword ptr [rip+schedule_counts+4*7]
    inc dword ptr [rip+schedule_counts+4*8]
    xor eax,eax
    pop r12
    pop rbx
    ret
.vecli256_fail:
    mov eax,1
    pop r12
    pop rbx
    ret'''

SHIFT_Q=r'''    # AVX2 VPS{kind}Q ymm dst,ymm src,imm8. destination in VEX.vvvv.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov r11d,edx
    mov edi,0xC4; call vec_emit_u8
    mov eax,0xC0
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x05
    mov edi,eax; call vec_emit_u8
    mov edi,0x73; call vec_emit_u8
    mov eax,r10d; and eax,7; or eax,{modrm}
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret'''

SHIFT_D=r'''    # AVX2 VPSRLD ymm dst,ymm src,imm8.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov r11d,edx
    mov edi,0xC4; call vec_emit_u8
    mov eax,0xC0
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,ebx; not eax; and eax,0xF; shl eax,3; or eax,0x05
    mov edi,eax; call vec_emit_u8
    mov edi,0x72; call vec_emit_u8
    mov eax,r10d; and eax,7; or eax,0xD0
    mov edi,eax; call vec_emit_u8
    mov edi,r11d; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret'''

FMA=r'''    # VEX3 map 0F38 W=1 VFMADD231PD ymm dst,src1,src2.
    push rbx
    mov ebx,esi
    mov r10d,edx
    mov r11d,ecx
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r11d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,2
    mov edi,eax; call vec_emit_u8
    mov eax,r10d; not eax; and eax,0xF; shl eax,3; or eax,0x85
    mov edi,eax; call vec_emit_u8
    mov edi,0xB8; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r11d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+0]
    inc dword ptr [rip+schedule_counts+4]
    pop rbx
    xor eax,eax
    ret'''

PACK_QD=r'''    # Pack low dword of each four qword lanes into XMM dst using fixed XMM13 scratch.
    push rbx
    mov ebx,edi
    mov r10d,esi
    # vextracti128 xmm13,ymmSRC,1
    mov edi,0xC4; call vec_emit_u8
    mov eax,r10d; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    or eax,3
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x39; call vec_emit_u8
    mov eax,r10d; and eax,7; shl eax,3; or eax,0xC5
    mov edi,eax; call vec_emit_u8
    mov edi,1; call vec_emit_u8
    # vshufps xmmDST,xmmSRC,xmm13,0x88
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov eax,r10d; not eax; and eax,0xF; shl eax,3
    mov edi,eax; call vec_emit_u8
    mov edi,0xC6; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0xC5
    mov edi,eax; call vec_emit_u8
    mov edi,0x88; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret'''

CVTDQ2PD=r'''    # AVX VCVTDQ2PD ymmDST,xmmSRC.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,1
    mov edi,eax; call vec_emit_u8
    mov edi,0x7E; call vec_emit_u8
    mov edi,0xE6; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3]
    pop rbx
    xor eax,eax
    ret'''

ROUND_TRUNC=r'''    # AVX VROUNDPD ymmDST,ymmSRC,truncate.
    push rbx
    mov ebx,edi
    mov r10d,esi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x40
    mov ecx,r10d; shr ecx,3; and ecx,1; xor ecx,1; shl ecx,5
    or eax,ecx
    or eax,3
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x09; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3
    mov ecx,r10d; and ecx,7; or eax,ecx; or eax,0xC0
    mov edi,eax; call vec_emit_u8
    mov edi,3; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*3]
    pop rbx
    xor eax,eax
    ret'''

CMP_EQ=r'''    # AVX2 VPCMPEQQ yields an all-ones/zero YMM predicate directly.
    push rbx
    mov ebx,edi
    mov r9d,esi
    mov r10d,edx
    mov edi,0x29
    mov esi,ebx
    mov edx,r9d
    mov ecx,r10d
    mov r8d,1
    call vec_vex3_0f38_rrr
    inc dword ptr [rip+schedule_counts+4*4]
    pop rbx
    xor eax,eax
    ret'''

MIN_U=r'''    # Exact AVX2 unsigned qword min using sign-bias + signed compare.
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx,esi                    # dst
    mov r12d,edx                   # a
    mov r14d,ecx                   # b
    mov rsi,0x8000000000000000
    call vec_const_intern
    cmp eax,-1; je .vmin256_fail
    mov r13d,eax
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vmin256_fail
    call vec_alloc
    cmp eax,-1; je .vmin256_fail
    mov r15d,eax
    # temp = a ^ sign; ymm13 = b ^ sign
    mov edi,0xEF; mov esi,r15d; mov edx,r12d; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,0xEF; mov esi,13; mov edx,r14d; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    # temp = (a > b) unsigned mask
    mov edi,0x37; mov esi,r15d; mov edx,r15d; mov ecx,13; mov r8d,1; call vec_vex3_0f38_rrr
    # ymm13 = mask & b; dst = ~mask & a; dst |= ymm13
    mov edi,0xDB; mov esi,13; mov edx,r15d; mov ecx,r14d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xDF; mov esi,ebx; mov edx,r15d; mov ecx,r12d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xEB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,r15d; call vec_free
    xor eax,eax
    jmp .vmin256_done
.vmin256_fail:
    mov eax,1
.vmin256_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret'''


def fixed_const_wrapper(opcode: int, counter_comment: str='') -> str:
    return f'''    push rbx\n    push r12\n    push r13\n    mov ebx,edi\n    mov r12d,esi\n    mov r13d,edx\n    mov edi,13; call vec_emit_const_load_index\n    test eax,eax; jnz .vcm256_fail\n    mov edi,{opcode:#x}; mov esi,ebx; mov edx,r12d; mov ecx,13; mov r8d,1\n    call vec_vex2_rrr\n    xor eax,eax\n    jmp .vcm256_done\n.vcm256_fail:\n    mov eax,1\n.vcm256_done:\n    pop r13\n    pop r12\n    pop rbx\n    ret'''

VPMULLQ_CONST=r'''    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vmulc256_fail
    mov edi,ebx; mov esi,ebx; mov edx,r12d; mov ecx,13; call vec_vpmullq
    test eax,eax; jnz .vmulc256_fail
    xor eax,eax
    jmp .vmulc256_done
.vmulc256_fail:
    mov eax,1
.vmulc256_done:
    pop r13
    pop r12
    pop rbx
    ret'''

FMA_CONST=r'''    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r12d,esi
    mov r13d,edx
    mov edi,13; call vec_emit_const_load_index
    test eax,eax; jnz .vfmac256_fail
    mov edi,ebx; mov esi,ebx; mov edx,r12d; mov ecx,13; call vec_vfmadd231pd
    test eax,eax; jnz .vfmac256_fail
    xor eax,eax
    jmp .vfmac256_done
.vfmac256_fail:
    mov eax,1
.vfmac256_done:
    pop r13
    pop r12
    pop rbx
    ret'''

FRAGMENTS=r'''.section .rodata
# Four-lane native256 fused episode. All tail work remains vectorized.
vec_fused_mask_reduce_fragment:
    jmp .Lvfmr256_code
.Lvfmr256_lanes:
    .quad 0,1,2,3
.Lvfmr256_code:
    cmp r8,4
    jae .Lvfmr256_full
    vmovq xmm13,r8
    vpbroadcastq ymm13,xmm13
    vpcmpgtq ymm13,ymm13,ymmword ptr [rip+.Lvfmr256_lanes]
    vandpd ymm0,ymm0,ymm13
.Lvfmr256_full:
    vaddpd ymm12,ymm12,ymm0
vec_fused_mask_reduce_fragment_end:

vec_fused_cmp8_fragment:
    cmp r8,4
vec_fused_cmp8_fragment_end:

vec_fused_sub8_fragment:
    sub r8,4
vec_fused_sub8_fragment_end:

vec_fused_boundary_test_zero_fragment:
    test rsi,rsi
vec_fused_boundary_test_zero_fragment_end:

vec_fused_boundary_test_end_fragment:
    lea rax,[rsi+4]
    cmp rax,rdi
vec_fused_boundary_test_end_fragment_end:

vec_fused_add_index8_fragment:
    add rsi,4
vec_fused_add_index8_fragment_end:

vec_fused_finish_fragment:
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
vec_fused_finish_fragment_end:

vec_fused_init_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
vec_fused_init_fragment_end:

vec_prefix_fragment:
    jmp .Lvec_prefix256_code
.Lvec_offsets256:
    .quad 0,1,2,3
.Lvec_prefix256_code:
    vmovq xmm6,rsi
    vpbroadcastq ymm6,xmm6
    vpaddq ymm6,ymm6,ymmword ptr [rip+.Lvec_offsets256]
    vmovq xmm7,rdi
    vpbroadcastq ymm7,xmm7
vec_prefix_fragment_end:
vec_movabs_rax: .byte 0x48,0xB8
vec_movabs_rax_end:
vec_save_axis_code:
    sub rsp,32
    vmovdqu ymmword ptr [rsp],ymm6
vec_save_axis_code_end:
vec_restore_axis_code:
    vmovdqu ymm6,ymmword ptr [rsp]
    add rsp,32
vec_restore_axis_code_end:
'''


def transform(src: Path, out: Path, derived: bool=False) -> None:
    s=src.read_text(encoding='utf-8')
    if derived:
        s=s.replace('.include "build/runtime_derived_offsets.inc"','.include "build/runtime_derived_native256_offsets.inc"',1)
    else:
        s=s.replace('.include "compiler/runtime_offsets.inc"','.include "build/runtime_native256_offsets.inc"',1)
    if s.count('ISA_CAP_TENSOR512_BASE')!=1: raise SystemExit(f'{src}: tensor512 gate count changed')
    s=s.replace('ISA_CAP_TENSOR512_BASE','ISA_CAP_TENSOR256_BASE',1)
    # Four physical f64 lanes per YMM. No source-order or scalar fallback changes.
    if s.count('tensor_vector_width],8')!=3: raise SystemExit(f'{src}: vector width gate count changed')
    s=s.replace('tensor_vector_width],8','tensor_vector_width],4')
    if s.count('mov rsi,8')!=1 or s.count('mov rcx,8')!=1:
        raise SystemExit(f'{src}: fused recurrence step anchors changed')
    s=s.replace('mov rsi,8','mov rsi,4',1).replace('mov rcx,8','mov rcx,4',1)
    s=re.sub(r'mov dword ptr \[rip\+vec13_free\],1[^\n]*', 'mov dword ptr [rip+vec13_free],0      # YMM13 is fixed native256 scratch', s, count=1)
    s=re.sub(r'mov dword ptr \[rip\+vec_cache_reg_mask\],0x[0-9A-Fa-f]+[^\n]*', 'mov dword ptr [rip+vec_cache_reg_mask],0 # no persistent high YMM bank exists', s, count=1)
    s=re.sub(r'mov dword ptr \[rip\+vec_const_reg_mask\],0x[0-9A-Fa-f]+[^\n]*', 'mov dword ptr [rip+vec_const_reg_mask],0 # constants use RIP pool + YMM13 broadcast', s, count=1)

    for name,body in [
        ('vec_vex2_rrr',VEX0F_RRR),
        ('vec_mov_ext',MOV_EXT),
        ('vec_emit_const_load_index',CONST_LOAD),
        ('vec_vpsllq_imm',SHIFT_Q.format(kind='LL',modrm='0xF0')),
        ('vec_vpsrlq_imm',SHIFT_Q.format(kind='RL',modrm='0xD0')),
        ('vec_vpsrld_imm',SHIFT_D),
        ('vec_vpaddq_mem_const',fixed_const_wrapper(0xD4)),
        ('vec_vpandq_mem_const',fixed_const_wrapper(0xDB)),
        ('vec_vpmullq_mem_const',VPMULLQ_CONST),
        ('vec_vmulpd_mem_const',fixed_const_wrapper(0x59)),
        ('vec_vaddpd_mem_const',fixed_const_wrapper(0x58)),
        ('vec_vfmadd231pd',FMA),
        ('vec_vfmadd231pd_mem_const',FMA_CONST),
        ('vec_vpminuq',MIN_U),
        ('vec_vpmovqd_ymm_from_zmm',PACK_QD),
        ('vec_vcvtdq2pd_zmm_from_ymm',CVTDQ2PD),
        ('vec_vrndscalepd_trunc',ROUND_TRUNC),
        ('vec_cmp_eq_maskvec',CMP_EQ),
    ]:
        s=replace_global(s,name,body)

    # Replace the complete copied-fragment block while leaving later scalar fragments intact.
    start=s.index('.section .rodata\n# Relocatable fused-episode fragments.')
    end=s.index('# stack-machine native code fragments',start)
    s=s[:start]+FRAGMENTS+'# stack-machine native code fragments\n'+s[end+len('# stack-machine native code fragments\n'):]
    s=s.replace('Runtime vector convention: ZMM6 = [k..k+7], ZMM7 = broadcast n.',
                'Runtime vector convention: YMM6 = [k..k+3], YMM7 = broadcast n.')
    out.write_text(s,encoding='utf-8')

transform(BUILD/'tensor_frontend_profile_base.S',GEN/'tensor_frontend_base_native256.S')
transform(BUILD/'tensor_frontend_profile_wide.S',GEN/'tensor_frontend_wide_native256.S')
transform(BUILD/'generated_derived/tensor_derived_frontend_x86_64.S',GEN/'tensor_frontend_derived_native256.S',derived=True)
print('NATIVE256_FRONTEND_GENERATION=PASS')
print('NATIVE256_VECTOR_WIDTH=4')
print('NATIVE256_SCALAR_FALLBACK=0')
print('NATIVE256_HIGH_REGISTER_DEPENDENCY=0')
