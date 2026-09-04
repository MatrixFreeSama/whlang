#!/usr/bin/env python3
"""Conservative Surface Auto-Repair regression gates.

This file tests only the erasable human shell. It never patches WH Core.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SURFACE = ROOT / "surface"
sys.path.insert(0, str(SURFACE))

from wh_surface import SurfaceError, canonical_core_bytes, compile_surface  # noqa: E402

EX = SURFACE / "examples"


def require(cond: bool, msg: str) -> None:
    if not cond:
        raise RuntimeError(msg)


def parse_text(text: str, *, repair: bool = True):
    return compile_surface(text, auto_repair=repair)


def main() -> int:
    result: dict[str, object] = {}

    clean_path = EX / "auto_repair_clean.wh"
    typo_path = EX / "auto_repair_typos.wh"
    clean_text = clean_path.read_text(encoding="utf-8")
    typo_text = typo_path.read_text(encoding="utf-8")
    typo_before = hashlib.sha256(typo_path.read_bytes()).hexdigest()

    clean, clean_parser = compile_surface(clean_text, clean_path)
    typo, typo_parser = compile_surface(typo_text, typo_path)
    require(canonical_core_bytes(clean) == canonical_core_bytes(typo),
            "repaired source did not erase to the clean WH Core bytes")
    require(not clean_parser.repairs, "clean source unexpectedly needed repair")
    require(len(typo_parser.repairs) >= 10, "typo showcase did not exercise enough repairs")
    result["clean_vs_repaired_core_byte_identity"] = {
        "passed": True,
        "core_sha256": hashlib.sha256(canonical_core_bytes(clean)).hexdigest(),
        "repair_count": len(typo_parser.repairs),
        "repairs": [r.as_dict() for r in typo_parser.repairs],
    }

    typo_after = hashlib.sha256(typo_path.read_bytes()).hexdigest()
    require(typo_before == typo_after, "auto-repair wrote back into source text")
    result["source_not_rewritten"] = True

    # Explicitly cover the three allowed English typo classes for declared names.
    base = """program id_case\nlet temperature: u64 = 7\npublish {name}\ntest () => {{ temperature = 7 }}\n"""
    id_cases = {
        "missing_one": "temperatur",
        "extra_one": "temperaturee",
        "wrong_one": "temperaturs",
    }
    id_repairs: dict[str, str] = {}
    for kind, wrong in id_cases.items():
        data, parser = parse_text(base.format(name=wrong))
        require(data["outputs"][0]["label"] == "temperature", f"{kind} identifier was not repaired")
        require(any(r.kind == "english_identifier" and r.original == wrong and r.replacement == "temperature"
                    for r in parser.repairs), f"{kind} identifier repair was not reported")
        id_repairs[kind] = wrong
    result["english_identifier_edit_distance_one"] = id_repairs

    # Same three edit classes for English grammar keywords.
    keyword_cases = {
        "missing_one": "publis",
        "extra_one": "publishh",
        "wrong_one": "publisb",
    }
    for kind, wrong in keyword_cases.items():
        src = f"program kw_{kind}\nlet value: u64 = 7\n{wrong} value\ntest () => {{ value = 7 }}\n"
        data, parser = parse_text(src)
        require(data["outputs"][0]["label"] == "value", f"{kind} keyword typo was not repaired")
        require(any(r.kind == "english_keyword" and r.original == wrong and r.replacement == "publish"
                    for r in parser.repairs), f"{kind} keyword repair was not reported")
    result["english_keyword_edit_distance_one"] = keyword_cases

    # Transposition is deliberately outside the policy: it is not one insertion,
    # deletion, or substitution.
    transposed = "program swap\nlet value: u64 = 7\npublsih value\ntest () => { value = 7 }\n"
    try:
        parse_text(transposed)
    except SurfaceError:
        result["transposition_not_silently_repaired"] = True
    else:
        raise RuntimeError("transposed English keyword was silently repaired")

    # Chinese keyword spelling is exact-only. No Chinese edit-distance guessing.
    bad_zh_keyword = "program zh_kw\nlet 温度: u64 = 7\n发佈 温度\ntest () => { 温度 = 7 }\n"
    try:
        parse_text(bad_zh_keyword)
    except SurfaceError:
        result["chinese_keyword_no_spell_repair"] = True
    else:
        raise RuntimeError("Chinese keyword typo was silently repaired")

    # Chinese/mixed/emoji identifiers are not spelling-corrected. They remain the
    # literal requested symbol and are left for normal semantic validation.
    bad_zh_id = "program zh_id\nlet 温度: u64 = 7\npublish 温庋\ntest () => { 温庋 = 7 }\n"
    data, parser = parse_text(bad_zh_id)
    require(not parser.repairs, "Chinese identifier typo received spell repair")
    require(data["outputs"][0]["label"] == "温庋", "Chinese identifier was changed")
    result["chinese_identifier_no_spell_repair"] = True

    mixed = "program mixed_id\nlet temp温度: u64 = 7\npublish temp温庋\ntest () => { temp温庋 = 7 }\n"
    data, parser = parse_text(mixed)
    require(not parser.repairs, "mixed Unicode identifier received spell repair")
    result["mixed_unicode_identifier_no_spell_repair"] = True

    # Ambiguous candidates must reject instead of guessing.
    ambiguous = """program ambiguous
let value: u64 = 1
let valve: u64 = 2
publish valee
test () => { value = 1 }
"""
    try:
        parse_text(ambiguous)
    except SurfaceError as exc:
        require("ambiguous English identifier typo" in str(exc), "ambiguous typo rejected for wrong reason")
        result["ambiguous_identifier_rejected"] = str(exc)
    else:
        raise RuntimeError("ambiguous identifier typo was guessed")

    # Newline splits: ordinary newlines are whitespace; these are the two cases that
    # actually need repair because the newline divides one lexical unit/operator.
    newline_keyword = "program nl_kw\nlet value: u64 = 7\npub\nlish value\ntest () => { value = 7 }\n"
    data, parser = parse_text(newline_keyword)
    require(any(r.kind == "newline_keyword" for r in parser.repairs), "split keyword not repaired")

    newline_identifier = "program nl_id\nlet temperature: u64 = 7\npublish tempera\nture\ntest () => { temperature = 7 }\n"
    data, parser = parse_text(newline_identifier)
    require(any(r.kind == "newline_identifier" for r in parser.repairs), "split identifier not repaired")

    newline_operator = "program nl_op\nlet x: u64 = 7\nlet ok: bool = x >\n= 7\npublish ok\ntest () => { ok = true }\n"
    data, parser = parse_text(newline_operator)
    require(any(r.kind == "newline_operator" and r.replacement == ">=" for r in parser.repairs),
            "split operator not repaired")
    result["newline_repair"] = ["keyword", "declared English identifier", "multi-character operator"]

    # Built-in English callable spellings follow the same one-edit rule.
    builtin = "program builtin\nlet x: u64 = 7\nlet y: u64 = 3\nlet z: u64 = bit_an(x,y)\npublish z\ntest () => { z = 3 }\n"
    data, parser = parse_text(builtin)
    require(any(r.kind == "english_builtin" and r.replacement == "bit_and" for r in parser.repairs),
            "built-in function typo not repaired")
    result["english_builtin_repair"] = True

    # Strict API mode proves repair is a shell policy and can be disabled without
    # changing WH Core. The typo source must then fail at the surface boundary.
    try:
        compile_surface(typo_text, typo_path, auto_repair=False)
    except SurfaceError:
        result["strict_surface_mode_rejects_typos"] = True
    else:
        raise RuntimeError("auto_repair=False still repaired typo source")

    print(json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
