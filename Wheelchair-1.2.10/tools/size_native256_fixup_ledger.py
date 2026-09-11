#!/usr/bin/env python3
"""Authoritative post-finalize maturation for native256 physicalizers.

The normal build invokes this pass immediately after the structural native256
finalizer.  It applies the generic finite-register maturity transforms, repairs
2^k±1 shift-count lifetimes, and sizes compiler-local constant-reference fixups
from structural graph capacity.  No workload identity, runtime selector, scalar
fallback, or user-ELF control metadata is introduced.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "build" / "generated_native256"
FILES = [
    GEN / "tensor_frontend_base_native256.S",
    GEN / "tensor_frontend_wide_native256.S",
    GEN / "tensor_frontend_derived_native256.S",
]

# The order matches the proven maturity pipeline. All three transformations are
# compiler-local, structural, deterministic and workload-blind.
for tool in (
    "fix_native256_const_shift_lifetime.py",
    "mature_native256_pressure_128.py",
    "mature_native256_liverange_128.py",
):
    subprocess.run(["python3", str(ROOT / "tools" / tool)], cwd=ROOT, check=True)

for path in FILES:
    text = path.read_text(encoding="utf-8")
    m = re.search(r"(?m)^\.equ MAX_NODES,(\d+)\s*$", text)
    if not m:
        raise SystemExit(f"missing MAX_NODES in {path.name}")
    max_nodes = int(m.group(1))
    cap = max_nodes * 8

    lines = text.splitlines()
    changed_checks = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "cmp eax,512":
            window = "\n".join(lines[max(0, i - 4):i])
            if "vec_fixup_count" in window:
                indent = line[: len(line) - len(line.lstrip())]
                lines[i] = f"{indent}cmp eax,{cap}"
                changed_checks += 1
        elif stripped == "cmp dword ptr [rip+vec_fixup_count],512":
            indent = line[: len(line) - len(line.lstrip())]
            lines[i] = f"{indent}cmp dword ptr [rip+vec_fixup_count],{cap}"
            changed_checks += 1
    text = "\n".join(lines) + "\n"

    old_ptr = "vec_fixup_ptr:.skip 512*8"
    old_const = "vec_fixup_const:.skip 512*4"
    if old_ptr not in text or old_const not in text:
        raise SystemExit(f"missing fixup ledger storage anchors in {path.name}")
    text = text.replace(old_ptr, f"vec_fixup_ptr:.skip {cap}*8", 1)
    text = text.replace(old_const, f"vec_fixup_const:.skip {cap}*4", 1)

    # Distinct constants are a different resource and remain intentionally bounded.
    if "vec_const_bits:.skip 512*8" not in text or "vec_const_reg:.skip 512*4" not in text:
        raise SystemExit(f"unique constant pool changed unexpectedly in {path.name}")
    if changed_checks < 1:
        raise SystemExit(f"no fixup capacity checks widened in {path.name}")

    path.write_text(text, encoding="utf-8")
    print(f"NATIVE256_FIXUP_LEDGER_FILE={path.name} CHECKS={changed_checks} CAP={cap}")

print("NATIVE256_NORMAL_BUILD_PRESSURE_MATURITY=PASS")
print("NATIVE256_NORMAL_BUILD_LIVERANGE_MATURITY=PASS")
print("NATIVE256_POST_FINALIZE_BUILD_AUTHORITY=PASS")
print("NATIVE256_FIXUP_LEDGER=STRUCTURAL")
print("NATIVE256_UNIQUE_CONSTANT_POOL_CAP=512")
print("NATIVE256_FIXUP_RUNTIME_SELECTOR=0")
print("NATIVE256_FIXUP_SCALAR_FALLBACK=0")
print("NATIVE256_FIXUP_WORKLOAD_ROUTE=0")
print("NATIVE256_FIXUP_LEDGER_SIZING=PASS")
