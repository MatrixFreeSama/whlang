#!/usr/bin/env python3
"""Compiler-only native256 lowering failure telemetry.

Messages are emitted only by the compiler process on rejected native lowering.
They are never copied into user ELFs and never influence backend selection.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
GEN=ROOT/'build'/'generated_native256'
FILES=[GEN/'tensor_frontend_base_native256.S',GEN/'tensor_frontend_wide_native256.S',GEN/'tensor_frontend_derived_native256.S']

NEEDLE='''    mov rdi,[r15+40]\n    xor esi,esi\n    call emit_vec_float\n    test eax,eax\n    jnz .fail\n'''
INTERIOR='''    mov rdi,[r15+40]\n    xor esi,esi\n    call emit_vec_float\n    test eax,eax\n    jz .nv128_interior_ok\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_interior]\n    mov edx,nv128_diag_interior_end-nv128_diag_interior\n    syscall\n    jmp .fail\n.nv128_interior_ok:\n'''
BOUNDARY='''    mov rdi,[r15+40]\n    xor esi,esi\n    call emit_vec_float\n    test eax,eax\n    jz .nv128_boundary_ok\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_boundary]\n    mov edx,nv128_diag_boundary_end-nv128_diag_boundary\n    syscall\n    jmp .fail\n.nv128_boundary_ok:\n'''

# CACHE_ALLOC is intentionally not instrumented: native256 has no persistent
# high-register cache pool, so those misses are normal rematerialization events.
FAIL_SITES={
'.evi_fail:\n    mov eax,1\n':('.evi_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_int]\n    mov edx,nv128_diag_int_end-nv128_diag_int\n    syscall\n    mov eax,1\n'),
'.evfa_fail:\n    mov eax,1\n':('.evfa_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_accum]\n    mov edx,nv128_diag_accum_end-nv128_diag_accum\n    syscall\n    mov eax,1\n'),
'.evf_fail:\n    mov eax,1\n':('.evf_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_float]\n    mov edx,nv128_diag_float_end-nv128_diag_float\n    syscall\n    mov eax,1\n'),
'.va_fail:\n    mov eax,-1\n    ret\n':('.va_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_alloc]\n    mov edx,nv128_diag_alloc_end-nv128_diag_alloc\n    syscall\n    mov eax,-1\n    ret\n'),
'.vci_fail:\n    mov eax,-1\n':('.vci_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_const_pool]\n    mov edx,nv128_diag_const_pool_end-nv128_diag_const_pool\n    syscall\n    mov eax,-1\n'),
'.vca_fail:\n    mov eax,1\n':('.vca_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_cache_table]\n    mov edx,nv128_diag_cache_table_end-nv128_diag_cache_table\n    syscall\n    mov eax,1\n'),
'.vica_fail:\n    mov eax,1\n':('.vica_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_cache_table]\n    mov edx,nv128_diag_cache_table_end-nv128_diag_cache_table\n    syscall\n    mov eax,1\n'),
'.vivca_fail:\n    mov eax,1; ret\n':('.vivca_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_cache_table]\n    mov edx,nv128_diag_cache_table_end-nv128_diag_cache_table\n    syscall\n    mov eax,1; ret\n'),
'.vlat_fail:\n    mov eax,1\n':('.vlat_fail:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_linear_table]\n    mov edx,nv128_diag_linear_table_end-nv128_diag_linear_table\n    syscall\n    mov eax,1\n'),
}

FIXUP_FAIL_LABELS=(
    '.vecli_fail:', '.vecli256_fail:', '.vpaqmc_fail:', '.vpaqm_fail:',
    '.vpmqmc_native_fail:', '.vmpdmc_fail:', '.vfmcm_fail:', '.vapdmc_fail:'
)
FIXUP_PROBE='''\n    cmp dword ptr [rip+vec_fixup_count],512\n    jb .Lnv128_fixup_not_full_@N@\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_diag_fixup]\n    mov edx,nv128_diag_fixup_end-nv128_diag_fixup\n    syscall\n.Lnv128_fixup_not_full_@N@:\n'''

LOW_LEVEL={
    '.veac_fail:':'AFFINE', '.vepk_fail:':'PERIODIC_KEY',
    '.vcq2pds_fail:':'I64_F64_SYNTH', '.vtnps_fail:':'F64_U64_SYNTH',
    '.vml_generic_fail:':'I64_MUL', '.vpmqmc_dispatch_fail:':'I64_MUL_CONST',
    '.vbc_fail:':'CONST_BROADCAST', '.vecli_fail:':'CONST_LOAD',
    '.vecli256_fail:':'CONST_LOAD_256', '.vfmac256_fail:':'FMA_CONST_256',
    '.vmpdmc_fail:':'FP_MUL_MEM', '.vfmcm_fail:':'FMA_MEM',
    '.vpaqmc_fail:':'I64_ADD_MEM', '.vpaqm_fail:':'I64_AND_MEM',
    '.vapdmc_fail:':'FP_ADD_MEM', '.vce_mask_fail:':'CMP_MASK',
    '.vfc_fail:':'CONST_FINALIZE', '.veu_fail:':'CODE_BUFFER',
    '.vie_fail:':'INIT_BUFFER', '.vlebt_fail:':'LINEAR_BASE_TERM',
}

def emit_diag(idx:int)->str:
    return f'''\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+nv128_low_{idx}]\n    mov edx,nv128_low_{idx}_end-nv128_low_{idx}\n    syscall\n'''

BASE_RO=['\n.section .rodata\n',
'nv128_diag_interior:.ascii "NATIVE256_FAIL_STAGE=INTERIOR_EXPR\\n"\nnv128_diag_interior_end:\n',
'nv128_diag_boundary:.ascii "NATIVE256_FAIL_STAGE=BOUNDARY_EXPR\\n"\nnv128_diag_boundary_end:\n',
'nv128_diag_int:.ascii "NATIVE256_FAIL_EMITTER=INT\\n"\nnv128_diag_int_end:\n',
'nv128_diag_float:.ascii "NATIVE256_FAIL_EMITTER=FLOAT\\n"\nnv128_diag_float_end:\n',
'nv128_diag_accum:.ascii "NATIVE256_FAIL_EMITTER=TOL_ACCUM\\n"\nnv128_diag_accum_end:\n',
'nv128_diag_alloc:.ascii "NATIVE256_FAIL_RESOURCE=VEC_ALLOC\\n"\nnv128_diag_alloc_end:\n',
'nv128_diag_const_pool:.ascii "NATIVE256_FAIL_RESOURCE=CONST_POOL\\n"\nnv128_diag_const_pool_end:\n',
'nv128_diag_fixup:.ascii "NATIVE256_FAIL_RESOURCE=FIXUP_CAP\\n"\nnv128_diag_fixup_end:\n',
'nv128_diag_cache_table:.ascii "NATIVE256_FAIL_RESOURCE=CACHE_TABLE_CAP\\n"\nnv128_diag_cache_table_end:\n',
'nv128_diag_linear_table:.ascii "NATIVE256_FAIL_RESOURCE=LINEAR_TABLE_CAP\\n"\nnv128_diag_linear_table_end:\n']
for i,name in enumerate(LOW_LEVEL.values()):
    BASE_RO.append(f'nv128_low_{i}:.ascii "NATIVE256_FAIL_RECIPE={name}\\n"\nnv128_low_{i}_end:\n')


def number_edges(text:str, start_label:str, done_label:str, target:str, prefix:str, map_prefix:str, msg_prefix:str, ro:list[str], file_index:int):
    f0=text.find(start_label+'\n')
    done=text.find(done_label+'\n',f0)
    ret=text.find('\n    ret\n',done)
    if f0<0 or done<0 or ret<0:
        raise SystemExit(f'cannot bound {start_label}')
    f1=ret+len('\n    ret\n')
    body=text[f0:f1]
    pat=re.compile(r'\b(j(?:mp|[a-z]{1,3})\s+)'+re.escape(target)+r'\b')
    contexts=[]
    def repl(m):
        i=len(contexts)
        ls=body.rfind('\n',0,m.start())+1
        le=body.find('\n',m.end())
        if le<0: le=len(body)
        contexts.append(body[ls:le].strip())
        return f'{m.group(1)}.{prefix}_{i}'
    body=pat.sub(repl,body)
    tramps=[]
    for i,line in enumerate(contexts):
        if file_index==0:
            print(f'{map_prefix}={i}:{line}')
        value_prefix=map_prefix.replace('_MAP','')
        tramps.append(f'''.{prefix}_{i}:\n    mov eax,SYS_write\n    mov edi,2\n    lea rsi,[rip+{msg_prefix}_{i}]\n    mov edx,{msg_prefix}_{i}_end-{msg_prefix}_{i}\n    syscall\n    jmp {target}\n''')
        ro.append(f'{msg_prefix}_{i}:.ascii "{value_prefix}={i}\\n"\n{msg_prefix}_{i}_end:\n')
    text=text[:f0]+body+text[f1:]+'\n.section .text\n'+''.join(tramps)
    return text

for file_index,path in enumerate(FILES):
    text=path.read_text()
    pos=text.find(NEEDLE)
    if pos<0: raise SystemExit(f'missing interior lowering anchor: {path.name}')
    text=text[:pos]+INTERIOR+text[pos+len(NEEDLE):]
    pos=text.find(NEEDLE,pos+len(INTERIOR))
    if pos<0: raise SystemExit(f'missing boundary lowering anchor: {path.name}')
    text=text[:pos]+BOUNDARY+text[pos+len(NEEDLE):]

    ro=list(BASE_RO)
    text=number_edges(text,'emit_vec_float_accum:','.evfa_done:','.evfa_fail','nv128_evfa_edge','NATIVE256_EVFA_EDGE_MAP','nv128_evfa_edge_msg',ro,file_index)
    text=number_edges(text,'emit_vec_float:','.evf_done:','.evf_fail','nv128_evf_edge','NATIVE256_EVF_EDGE_MAP','nv128_evf_edge_msg',ro,file_index)

    for old,new in FAIL_SITES.items():
        if old not in text:
            raise SystemExit(f'missing telemetry anchor in {path.name}: {old.splitlines()[0]}')
        text=text.replace(old,new,1)
    for i,label in enumerate(FIXUP_FAIL_LABELS):
        if label in text:
            text=text.replace(label,label+FIXUP_PROBE.replace('@N@',str(i)),1)
    for i,label in enumerate(LOW_LEVEL):
        if label in text:
            text=text.replace(label,label+emit_diag(i),1)
    text += ''.join(ro)
    path.write_text(text)

print('NATIVE256_COMPILER_FAIL_TELEMETRY=PASS')
print('NATIVE256_COMPILER_FAIL_TELEMETRY_USER_ELF=0')
