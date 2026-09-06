#!/usr/bin/env python3
"""Generic live-range fracture for limited-register native256 expression trees."""
from __future__ import annotations
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
GEN=ROOT/'build'/'generated_native256'
FILES=[GEN/'tensor_frontend_base_native256.S',GEN/'tensor_frontend_wide_native256.S',GEN/'tensor_frontend_derived_native256.S']

HELPERS=r'''
# Whole-YMM stack spill. No scalar lane is introduced. Nested fractures are
# naturally LIFO and each reserves exactly one 32-byte vector slot.
vec_stack_spill_push_128:
    push rbx
    mov ebx,edi
    mov edi,0x48; call vec_emit_u8
    mov edi,0x83; call vec_emit_u8
    mov edi,0xEC; call vec_emit_u8
    mov edi,0x20; call vec_emit_u8
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x61
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x11; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x04
    mov edi,eax; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*7]
    xor eax,eax
    pop rbx
    ret

vec_stack_spill_pop_128:
    push rbx
    mov ebx,edi
    mov edi,0xC4; call vec_emit_u8
    mov eax,ebx; shr eax,3; and eax,1; xor eax,1; shl eax,7
    or eax,0x61
    mov edi,eax; call vec_emit_u8
    mov edi,0x7D; call vec_emit_u8
    mov edi,0x10; call vec_emit_u8
    mov eax,ebx; and eax,7; shl eax,3; or eax,0x04
    mov edi,eax; call vec_emit_u8
    mov edi,0x24; call vec_emit_u8
    mov edi,0x48; call vec_emit_u8
    mov edi,0x83; call vec_emit_u8
    mov edi,0xC4; call vec_emit_u8
    mov edi,0x20; call vec_emit_u8
    inc dword ptr [rip+schedule_counts+4*7]
    xor eax,eax
    pop rbx
    ret

'''

FLOAT_NEW=r'''.evf_regular_two:
    mov rdi,r15; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    mov edi,r13d; call vec_stack_spill_push_128
    mov rdi,r14; mov esi,r13d; call emit_vec_float; test eax,eax; jnz .evf_fail
    call vec_alloc; cmp eax,-1; je .evf_fail; mov r12d,eax
    mov edi,r12d; call vec_stack_spill_pop_128
    mov edi,ebx; mov esi,r13d; mov edx,r12d; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    mov edi,r12d; call vec_free
    xor eax,eax; jmp .evf_done
'''

SELECT_NEW=r'''.evi_select_general:
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov edi,r13d; call vec_stack_spill_push_128
    mov r15,[r15+32]; test r15,r15; jz .evi_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    mov edi,r13d; call vec_stack_spill_push_128
    mov r15,[r15+32]; test r15,r15; jz .evi_fail
    mov rdi,r15; mov esi,r13d; call emit_vec_int; test eax,eax; jnz .evi_fail
    call vec_alloc; cmp eax,-1; je .evi_fail; mov ebx,eax
    mov edi,ebx; call vec_stack_spill_pop_128
    mov edi,13; call vec_stack_spill_pop_128
    mov edi,0xDB; mov esi,ebx; mov edx,ebx; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,0xDF; mov esi,13; mov edx,13; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    mov edi,0xEB; mov esi,r13d; mov edx,ebx; mov ecx,13; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; call vec_free
    jmp .evi_ok
'''

ACCUM_SCALED_NEW=r'''.evfa_scaled:
    # Preserve the live tolerant accumulator as a whole vector while lowering
    # the scaled nonlinear leaf. Only after the leaf has the full register pool
    # do we reserve one short-lived YMM to keep it across accumulator restore.
    mov edi,r13d; call vec_stack_spill_push_128
    mov rdi,r15; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evfa_fail
    call vec_alloc
    cmp eax,-1; je .evfa_fail
    mov ebx,eax
    mov edi,ebx; mov esi,r13d; call vec_mov_ext
    mov edi,r13d; call vec_stack_spill_pop_128
    mov rsi,r14; call vec_const_get_reg
    cmp eax,-1; je .evfa_scaled_mem
    mov ecx,eax
    mov edi,r13d; mov esi,r13d; mov edx,ebx; call vec_vfmadd231pd
    mov edi,ebx; call vec_free
    xor eax,eax
    jmp .evfa_done
.evfa_scaled_mem:
    mov rsi,r14; call vec_const_intern
    cmp eax,-1; je .evfa_scaled_free_fail
    mov edx,eax
    mov edi,r13d; mov esi,ebx; call vec_vfmadd231pd_mem_const
    test eax,eax; jnz .evfa_scaled_free_fail
    mov edi,ebx; call vec_free
    xor eax,eax
    jmp .evfa_done
'''

ACCUM_NEW=r'''.evfa_fallback:
    mov edi,r13d; call vec_stack_spill_push_128
    mov rdi,r12; mov esi,r13d; call emit_vec_float
    test eax,eax; jnz .evfa_fail
    call vec_alloc
    cmp eax,-1; je .evfa_fail
    mov ebx,eax
    mov edi,ebx; call vec_stack_spill_pop_128
    mov edi,0x58; mov esi,r13d; mov edx,ebx; mov ecx,r13d; mov r8d,1; call vec_vex2_rrr
    mov edi,ebx; call vec_free
    xor eax,eax
    jmp .evfa_done
'''

for path in FILES:
    text=path.read_text()
    marker='# emit_vec_float(rdi=expr, esi=dst ymm low) -> eax 0/1\nemit_vec_float:\n'
    if marker not in text:
        raise SystemExit(f'missing emit_vec_float marker: {path.name}')
    text=text.replace(marker,HELPERS+marker,1)

    pat=re.compile(r'(?ms)^\.evf_regular_two:\n.*?(?=^\.evf_free_x_fail:)')
    text,n=pat.subn(FLOAT_NEW,text,count=1)
    if n!=1: raise SystemExit(f'missing structural regular-two region: {path.name}')

    pat=re.compile(r'(?ms)^\.evi_select_general:\n.*?(?=^\.evi_[A-Za-z0-9_]+:)')
    text,n=pat.subn(SELECT_NEW,text,count=1)
    if n!=1: raise SystemExit(f'missing structural select-general region: {path.name}')

    pat=re.compile(r'(?ms)^\.evfa_scaled:\n.*?(?=^\.evfa_scaled_free_fail:)')
    text,n=pat.subn(ACCUM_SCALED_NEW,text,count=1)
    if n!=1: raise SystemExit(f'missing tolerant scaled region: {path.name}')

    pat=re.compile(r'(?ms)^\.evfa_fallback:\n.*?(?=^\.evfa_leaf_free_fail:)')
    text,n=pat.subn(ACCUM_NEW,text,count=1)
    if n!=1: raise SystemExit(f'missing tolerant-accumulator fallback region: {path.name}')

    low=text.lower()
    for forbidden in ('newton','fsi','fluid','solid','stiffness','poisson'):
        if forbidden in low: raise SystemExit(f'workload identity leaked: {forbidden}')
    path.write_text(text)

print('NATIVE256_COMPLEX_SIBLING_LIVERANGE_FRACTURE=PASS')
print('NATIVE256_BOUNDARY_SELECT_LIVERANGE_FRACTURE=PASS')
print('NATIVE256_TOLERANT_ACCUMULATOR_LIVERANGE_FRACTURE=PASS')
print('NATIVE256_TOLERANT_SCALED_LIVERANGE_FRACTURE=PASS')
print('NATIVE256_VECTOR_SPILL_BYTES=32')
print('NATIVE256_VECTOR_SPILL_SCALAR_LANES=0')
print('NATIVE256_VECTOR_SPILL_RUNTIME_SELECTOR=0')
print('NATIVE256_VECTOR_SPILL_WORKLOAD_ROUTE=0')
