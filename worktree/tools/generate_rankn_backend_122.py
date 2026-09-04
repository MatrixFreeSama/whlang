#!/usr/bin/env python3
from __future__ import annotations
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
GEN = BUILD / "generated_122"
GEN.mkdir(parents=True, exist_ok=True)

BASE_FRONTEND_SHA = "e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6"
BASE_RUNTIME_SHA = "e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3"
MAX_POINTS = 2048 * 65536


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_count(text: str, needle: str, count: int = 1) -> None:
    got = text.count(needle)
    if got != count:
        raise SystemExit(f"1.2.2 protected derivation rejected: expected {count} copies of {needle!r}, found {got}")


def replace_once(text: str, old: str, new: str) -> str:
    require_count(text, old, 1)
    return text.replace(old, new, 1)


frontend_path = ROOT / "compiler/tensor_frontend_x86_64.S"
runtime_path = ROOT / "runtime/tensor_runtime_template_x86_64.S"
if digest(frontend_path) != BASE_FRONTEND_SHA:
    raise SystemExit("1.2.2 Rank-N derivation rejected: protected 1.2.1 tensor frontend bytes changed")
if digest(runtime_path) != BASE_RUNTIME_SHA:
    raise SystemExit("1.2.2 Rank-N derivation rejected: protected 1.2.1 tensor runtime bytes changed")

# ---- derived runtime ----
runtime = runtime_path.read_text(encoding="utf-8")
runtime = replace_once(
    runtime,
    "    mov [rip+g_n], rax\n    add rax, CHUNK_SIZE-1\n",
    "    # 1.2.2 Rank-N: expand the logical input extent into the proved Cartesian\n"
    "    # product domain before chunk ownership is formed. This multiplication is\n"
    "    # one launch-time operation, never an inner-axis loop.\n"
    "    mov rcx,qword ptr [rip+rank_n_product_patch]\n"
    "    test rcx,rcx\n"
    "    jz .bad_args\n"
    "    mul rcx\n"
    "    test rdx,rdx\n"
    "    jnz .bad_args\n"
    "    mov [rip+g_n], rax\n"
    "    add rax, CHUNK_SIZE-1\n"
)
runtime = replace_once(
    runtime,
    ".global n_max_patch\nn_max_patch: .quad 100000000\nchecksum_line:",
    ".global n_max_patch\nn_max_patch: .quad 100000000\n"
    ".global rank_n_product_patch\nrank_n_product_patch: .quad 1\nchecksum_line:"
)
(GEN / "tensor_rankn_runtime_template_x86_64.S").write_text(runtime, encoding="utf-8")

# ---- derived tensor frontend ----
front = frontend_path.read_text(encoding="utf-8")
front = replace_once(front, '.include "compiler/runtime_offsets.inc"', '.include "build/runtime_rankn_offsets.inc"')
front = replace_once(
    front,
    "    mov dword ptr [rip+tensor_comm_elimination],0\n",
    "    mov dword ptr [rip+tensor_comm_elimination],0\n"
    "    mov qword ptr [rip+tensor_rank_n_product],0\n"
)
front = replace_once(
    front,
    "    mov [rip+tensor_n_max],rax\n\n    # bindings[] structural extraction.\n",
    "    mov [rip+tensor_n_max],rax\n\n"
    "    # 1.2.2 Rank-N private canonical marker. The human input n remains logical;\n"
    "    # the derived runtime expands only the physical Cartesian point domain.\n"
    "    mov rdi,r12\n"
    "    lea rsi,[rip+k_rank_n_product]\n"
    "    mov edx,k_rank_n_product_end-k_rank_n_product\n"
    "    call obj_get\n"
    "    test rax,rax\n"
    "    jz .fail\n"
    "    call node_parse_u64\n"
    "    test edx,edx\n"
    "    jnz .fail\n"
    "    test rax,rax\n"
    "    jz .fail\n"
    "    mov rcx,rax\n"
    "    dec rcx\n"
    "    test rcx,rax\n"
    "    jnz .fail                    # product factor is power-of-two\n"
    "    mov [rip+tensor_rank_n_product],rax\n"
    "    mov rcx,[rip+tensor_n_max]\n"
    "    mul rcx\n"
    "    test rdx,rdx\n"
    "    jnz .fail\n"
    f"    cmp rax,{MAX_POINTS}\n"
    "    ja .fail\n\n"
    "    # bindings[] structural extraction.\n"
)
front = replace_once(
    front,
    "    test eax,eax; jz .evi_mod\n",
    "    test eax,eax; jz .evi_ushr\n"
)
front = replace_once(
    front,
    ".evi_mod:\n    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq\n",
    ".evi_ushr:\n"
    "    # Internal 1.2.2 coordinate recovery. Only a compile-time immediate shift\n"
    "    # is admitted; the AVX-512F VPSRLQ primitive already existed in 1.2.1.\n"
    "    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_ushr]; mov ecx,v_ushr_end-v_ushr; call span_eq\n"
    "    test eax,eax; jz .evi_mod\n"
    "    mov rbx,[r15+32]; test rbx,rbx; jz .evi_fail\n"
    "    cmp qword ptr [rbx+32],0; jne .evi_fail\n"
    "    mov rdi,rbx; call expr_literal_u64\n"
    "    test edx,edx; jnz .evi_fail\n"
    "    cmp rax,63; ja .evi_fail\n"
    "    mov ebx,eax\n"
    "    mov rdi,r15; mov esi,r13d; call emit_vec_int\n"
    "    test eax,eax; jnz .evi_fail\n"
    "    mov edi,r13d; mov esi,r13d; mov edx,ebx; call vec_vpsrlq_imm\n"
    "    test eax,eax; jnz .evi_fail\n"
    "    jmp .evi_ok\n"
    ".evi_mod:\n"
    "    mov rdi,[r14+8]; mov rsi,[r14+16]; lea rdx,[rip+v_mod]; mov ecx,v_mod_end-v_mod; call span_eq\n"
)
front = replace_once(
    front,
    "    mov eax,SYS_pwrite64\n    mov rdi,rbx\n    lea rsi,[rip+tensor_n_max]\n    mov edx,8\n    mov r10d,RUNTIME_NMAX_OFF\n    syscall\n    cmp rax,8\n    jne .eti_close_fail\n\n    # Append exact reachable AOT code:",
    "    mov eax,SYS_pwrite64\n    mov rdi,rbx\n    lea rsi,[rip+tensor_n_max]\n    mov edx,8\n    mov r10d,RUNTIME_NMAX_OFF\n    syscall\n    cmp rax,8\n    jne .eti_close_fail\n\n"
    "    mov eax,SYS_pwrite64\n"
    "    mov rdi,rbx\n"
    "    lea rsi,[rip+tensor_rank_n_product]\n"
    "    mov edx,8\n"
    "    mov r10d,RUNTIME_RANK_N_PRODUCT_OFF\n"
    "    syscall\n"
    "    cmp rax,8\n"
    "    jne .eti_close_fail\n\n"
    "    # Append exact reachable AOT code:"
)
front = replace_once(
    front,
    'k_format:.ascii "format"; k_format_end:\n',
    'k_format:.ascii "format"; k_format_end:\n'
    'k_rank_n_product:.ascii "rank_n_product"; k_rank_n_product_end:\n'
)
front = replace_once(
    front,
    'v_mod:.ascii "mod"; v_mod_end:\n',
    'v_ushr:.ascii "ushr"; v_ushr_end:\n'
    'v_mod:.ascii "mod"; v_mod_end:\n'
)
front = replace_once(
    front,
    "tensor_n_max:.skip 8\nimage_eval_len:",
    "tensor_n_max:.skip 8\ntensor_rank_n_product:.skip 8\nimage_eval_len:"
)
(GEN / "tensor_rankn_frontend_x86_64.S").write_text(front, encoding="utf-8")

(GEN / "runtime_rankn_blob_x86_64.S").write_text(
    '.intel_syntax noprefix\n.section .rodata\n.global runtime_template_blob\n.global runtime_template_blob_end\n'
    'runtime_template_blob:\n.incbin "build/tensor_rankn_runtime_template"\nruntime_template_blob_end:\n',
    encoding="utf-8",
)
print("RANK_N_DERIVATION_BASELINE_FRONTEND_SHA256=PASS")
print("RANK_N_DERIVATION_BASELINE_RUNTIME_SHA256=PASS")
print("RANK_N_DERIVED_BACKEND_GENERATION=PASS")
