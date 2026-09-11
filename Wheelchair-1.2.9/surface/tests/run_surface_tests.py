#!/usr/bin/env python3
"""Regression gates for the erasable WH human-syntax shell only."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SURFACE = ROOT / "surface"
sys.path.insert(0, str(SURFACE))

from wh_surface import (  # noqa: E402
    SurfaceError,
    canonical_core_bytes,
    compile_surface,
    core_hash,
    format_keywords,
)

EX = SURFACE / "examples"
EQUIV = [
    EX / "equivalent_en.wh",
    EX / "equivalent_zh_hans.wh",
    EX / "equivalent_zh_hant.wh",
    EX / "equivalent_mixed.wh",
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def parse(path: Path):
    return compile_surface(path.read_text(encoding="utf-8"), path)[0]


def main() -> int:
    results: dict[str, object] = {}

    blobs = [canonical_core_bytes(parse(path)) for path in EQUIV]
    require(len(set(blobs)) == 1, "EN/Hans/Hant/mixed did not erase to identical WH Core bytes")
    results["multilingual_core_byte_identity"] = {
        "passed": True,
        "sources": [path.name for path in EQUIV],
        "sha256": hashlib.sha256(blobs[0]).hexdigest(),
    }

    mixed_text = (EX / "equivalent_mixed.wh").read_text(encoding="utf-8")
    for language in ("en", "zh-hans", "zh-hant", "preserve"):
        formatted = format_keywords(mixed_text, language)
        formatted_data, _ = compile_surface(formatted, EX / f"formatted_{language}.wh")
        require(canonical_core_bytes(formatted_data) == blobs[0],
                f"formatter language {language} changed WH Core")
    results["formatter_is_semantics_free"] = True

    showcase = parse(EX / "feature_showcase.wh")
    require(showcase["program"].startswith("surface_"), "Unicode program name was not shell-mapped")
    require(any(item["name"] == "123" for item in showcase["bindings"]),
            "numeric-only declared identifier missing")
    require(any(item["name"] == "🐭" for item in showcase["bindings"]),
            "emoji identifier missing")
    results["utf8_identifier_surface"] = {
        "numeric_only": True,
        "emoji": True,
        "digit_leading": True,
        "unicode_program_shell_mapping": showcase["program"],
    }

    zwj_source = """\
program zwj_identifier
let 👩‍🔬: u64 = 9
publish 👩‍🔬
test () => { 👩‍🔬 = 9 }
"""
    zwj, _ = compile_surface(zwj_source)
    require(zwj["bindings"][0]["name"] == "👩‍🔬", "emoji ZWJ grapheme was not preserved")
    results["emoji_zwj_preserved"] = True

    digit_leading_source = """\
program digit_leading
let 123abc: u64 = 4
let 7号轴: u64 = 5
publish 🚀 = 123abc + 7号轴
test () => { 🚀 = 9 }
"""
    digit_data, _ = compile_surface(digit_leading_source)
    require([b["name"] for b in digit_data["bindings"]] == ["123abc", "7号轴"],
            "digit-leading identifiers were altered")
    results["digit_leading_identifiers"] = True

    numeric_source = """\
program numeric_identifier
let 123: u64 = 7
publish value = `123` + 1
test () => { value = 8 }
"""
    numeric_data, _ = compile_surface(numeric_source)
    expr = numeric_data["outputs"][0]["expr"]
    require(expr == {"op": "add", "args": [{"var": "123"}, {"literal": 1, "type": "u64"}]},
            "backtick numeric reference did not resolve as an identifier")
    results["numeric_only_identifier_reference"] = True

    nfc_a = """\
program nfc_test
let é: u64 = 3
publish é
test () => { é = 3 }
"""
    nfc_b = """\
program nfc_test
let e\u0301: u64 = 3
publish e\u0301
test () => { e\u0301 = 3 }
"""
    a, _ = compile_surface(nfc_a)
    b, _ = compile_surface(nfc_b)
    require(canonical_core_bytes(a) == canonical_core_bytes(b), "NFC did not canonicalize surface names")
    results["nfc_identifier_identity"] = True

    bad = """\
program hidden_bidi
let bad\u202Ename: u64 = 1
publish x = 1
test () => { x = 1 }
"""
    try:
        compile_surface(bad)
    except SurfaceError:
        results["hidden_bidi_rejected"] = True
    else:
        raise RuntimeError("hidden bidirectional format character was accepted")

    # Ask the old compiler to validate a surface-generated graph.  Bytecode writes are
    # disabled so this test cannot dirty compiler/__pycache__.
    with tempfile.TemporaryDirectory(prefix="wh_surface_core_") as td:
        core = Path(td) / "showcase.core.wh"
        core.write_bytes(canonical_core_bytes(showcase))
        env = dict(os.environ)
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        proc = subprocess.run(
            [sys.executable, str(ROOT / "compiler" / "wheelchairc.py"), str(core), "--validate-only"],
            cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        require(proc.returncode == 0, "unchanged WH Core rejected showcase: " + proc.stderr)
        validation = json.loads(proc.stdout)
        require(validation["tests"][0]["reference"]["🐭"] == 12, "showcase reference mismatch")
    results["unchanged_core_accepts_surface_output"] = True

    print(json.dumps(results, indent=2, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
