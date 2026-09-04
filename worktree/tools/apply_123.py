#!/usr/bin/env python3
"""Deterministically integrate Wheelchair 1.2.3 Sparse Causal Expansion.

The 1.2.2 native compiler/runtime sources are intentionally untouched. This
patch changes only compile-time WHEX semantic planning so WH and WHEX inherit the
same generic Global Coupled Operator proof layer.
"""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "surface" / "whex_semantics.py"
BASE_SHA256 = "32518611fad6079c91b68d67e11f09e902f8f86d62136532dac993e5929f2551"
MARKER = "sce.attach_to_semantic_plan(plan)"

text = TARGET.read_text(encoding="utf-8")
if MARKER in text:
    print("WHEELCHAIR_1_2_3_SOURCE_PATCH=PASS")
    raise SystemExit(0)

got = hashlib.sha256(TARGET.read_bytes()).hexdigest()
if got != BASE_SHA256:
    raise SystemExit(f"1.2.3 semantic baseline hash mismatch: {got}")

old_import = "from typing import Any, Iterable\n"
new_import = old_import + "\nimport sparse_causal_expansion as sce\n"
if text.count(old_import) != 1:
    raise SystemExit("1.2.3 import anchor changed")
text = text.replace(old_import, new_import, 1)

old_hash = "    blob = json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(\",\", \":\")).encode(\"utf-8\")\n"
new_hash = "    sce.attach_to_semantic_plan(plan)\n" + old_hash
if text.count(old_hash) != 1:
    raise SystemExit("1.2.3 semantic-hash anchor changed")
text = text.replace(old_hash, new_hash, 1)
TARGET.write_text(text, encoding="utf-8")
print("WHEELCHAIR_1_2_3_SOURCE_PATCH=PASS")
