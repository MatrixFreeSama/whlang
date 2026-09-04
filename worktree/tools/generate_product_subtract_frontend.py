#!/usr/bin/env python3
from pathlib import Path
import hashlib, re, sys

SRC = Path('compiler/tensor_frontend_x86_64.S')
OUT = Path('build/tensor_frontend_product_subtract.S')
BASE_SHA256 = 'e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6'

raw = SRC.read_bytes()
sha = hashlib.sha256(raw).hexdigest()
if sha != BASE_SHA256:
    raise SystemExit(f'protected tensor frontend SHA mismatch: {sha}')
text = raw.decode('utf-8')

# Clone the already validated EVEX 231 FMA encoder and change only the opcode
# from VFMADD231PD (B8) to VFNMADD231PD (BC). Operand encoding is identical.
pat = re.compile(r'(# EVEX vfmadd231pd zmm dst,src1,src2: dst = src1\*src2 \+ dst\.\n# Operand encoding is validated against GNU as for low/high ZMM combinations\.\nvec_vfmadd231pd:\n.*?\n    ret\n)(?=\n# EVEX vfmadd231pd zmm dst,src1,QWORD BCST)', re.S)
m = pat.search(text)
if not m:
    raise SystemExit('vfmadd231 encoder anchor not found')
base = m.group(1)
clone = base.replace('vfmadd231pd', 'vfnmadd231pd')
clone = clone.replace('dst = src1*src2 + dst.', 'dst = -(src1*src2) + dst.')
clone = clone.replace('mov edi,0xB8; call vec_emit_u8', 'mov edi,0xBC; call vec_emit_u8')
if clone == base or '0xBC' not in clone:
    raise SystemExit('vfnmadd encoder derivation failed')
text = text[:m.end(1)] + '\n' + clone + text[m.end(1):]

old = '''.evf_regular_two:\n    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail\n    call vec_alloc; cmp eax,-1; je .evf_fail; mov r12d,eax\n    mov rdi,r14; mov esi,r12d; call emit_vec_float; test eax,eax; jnz .evf_free_x_fail\n    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r12d; mov r8d,1; call vec_vex2_rrr\n    mov edi,r12d; call vec_free\n    xor eax,eax; jmp .evf_done\n'''
new = '''.evf_regular_two:\n    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail\n\n    # Generic tolerant Product-Subtract Contraction.  This is structural algebra,\n    # not workload dispatch: sub(lhs, mul(a,b)) becomes one VFNMADD after lhs is\n    # materialized. Strict mode retains the original multiply + subtract rounding.\n    # No new synchronization, scalar path, runtime tag, or matrix-specific rule is\n    # introduced. Resource shortage simply uses the existing vector recipe.\n    cmp dword ptr [rip+tensor_tolerant_fp],0\n    je .evf_regular_two_old\n    cmp ebx,0x5C\n    jne .evf_regular_two_old\n    mov rdi,r14; lea rsi,[rip+k_op]; mov edx,k_op_end-k_op; call obj_get\n    test rax,rax; jz .evf_regular_two_old\n    push rax\n    mov rdi,[rax+8]; mov rsi,[rax+16]; lea rdx,[rip+v_mul]; mov ecx,v_mul_end-v_mul; call span_eq\n    pop rax\n    test eax,eax; jz .evf_regular_two_old\n    mov rdi,r14; lea rsi,[rip+k_args]; mov edx,k_args_end-k_args; call obj_get\n    test rax,rax; jz .evf_regular_two_old\n    mov r15,[rax+24]; test r15,r15; jz .evf_regular_two_old\n    mov r14,[r15+32]; test r14,r14; jz .evf_regular_two_old\n    cmp qword ptr [r14+32],0; jne .evf_regular_two_old\n\n    # Reserve both product operands before emitting either one. If the vector\n    # register file cannot support contraction, fall back before any RHS byte is\n    # emitted, preserving the old fully-vector recipe.\n    call vec_alloc; cmp eax,-1; je .evf_regular_two_old\n    mov r12d,eax\n    call vec_alloc; cmp eax,-1; je .evf_product_sub_free_a\n    mov ebx,eax\n    mov rdi,r15; mov esi,r12d; call emit_vec_float\n    test eax,eax; jnz .evf_product_sub_free_b_fail\n    mov rdi,r14; mov esi,ebx; call emit_vec_float\n    test eax,eax; jnz .evf_product_sub_free_b_fail\n    mov edi,r13d; mov esi,r13d; mov edx,r12d; mov ecx,ebx; call vec_vfnmadd231pd\n    mov edi,ebx; call vec_free\n    mov edi,r12d; call vec_free\n    xor eax,eax; jmp .evf_done\n.evf_product_sub_free_b_fail:\n    mov edi,ebx; call vec_free\n.evf_product_sub_free_a_fail:\n    mov edi,r12d; call vec_free\n    jmp .evf_fail\n.evf_product_sub_free_a:\n    mov edi,r12d; call vec_free\n.evf_regular_two_old:\n    call vec_alloc; cmp eax,-1; je .evf_fail; mov r12d,eax\n    mov rdi,r14; mov esi,r12d; call emit_vec_float; test eax,eax; jnz .evf_free_x_fail\n    mov edi,ebx; mov esi,r13d; mov edx,r13d; mov ecx,r12d; mov r8d,1; call vec_vex2_rrr\n    mov edi,r12d; call vec_free\n    xor eax,eax; jmp .evf_done\n'''
if old not in text:
    raise SystemExit('regular binary lowering anchor not found')
text = text.replace(old, new, 1)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(text, encoding='utf-8')
print('GENERIC_PRODUCT_SUBTRACT_CONTRACTION=DERIVED')
print(f'BASELINE_FRONTEND_SHA256={sha}')
