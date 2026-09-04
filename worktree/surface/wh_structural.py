#!/usr/bin/env python3
"""Wheelchair .wh structural-recovery surface for the unified semantic core.

This module is intentionally *not* imported by WHEX.  WHEX 1.1.0 is a frozen
byte-level reference.  The WH surface may present familiar imperative-looking
syntax, but every accepted construct in this lane is translated into the same
canonical ``wheelchair.tensor/1`` graph and the same semantic topology that the
corresponding WHEX source would produce.

Accepted source sugar is zero-cost by construction:

* ``for ... { a[i]: f64 = expr }`` -> structural map axis
* ``for ... { total += expr }`` -> structural sum reduction
* ``if cond { a } else { b }`` -> dataflow ``select``
* ``pure [generic] fn`` -> compile-time expression specialization
* compile-time ``record`` -> field substitution
* ``region ... effect pure parallel`` -> proof metadata only
* Rank-N reduction axes are erased only when independence is proved, exactly as
  in WHEX.  Non-erasable Rank-N remains structured and the current native
  realizer rejects it rather than flattening it into a serial nest.

A dynamic ``while`` request is recognized as control intent but is deliberately
rejected until a recurrence/fixed-point topology can be proved.  It never falls
through to a sequential backedge in this lane.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys
import unicodedata
from typing import Any

import wh_surface as wh
import whex_surface as wx
import whex_semantics as ws

SOURCE_EXTENSION = ".wh"

SOFT_ALIASES: dict[str, tuple[str, ...]] = {
    "for": ("for", "循环", "循環"),
    "if": ("if", "如果", "若"),
    "else": ("else", "否则", "否則"),
    "while": ("while", "当", "當"),
}
SOFT_TO_CANONICAL = {
    unicodedata.normalize("NFC", alias): key
    for key, aliases in SOFT_ALIASES.items() for alias in aliases
}


def looks_structural(text: str) -> bool:
    """Conservative source classifier used before parsing, never as fallback.

    Existing WH programs stay in the historical general surface.  New structural
    WH is selected only when it contains vocabulary that the old top-level
    grammar does not admit as a declaration.
    """
    toks = wh.lex(text, auto_repair=False)
    # Use the first significant token on each source line.  This keeps a legacy
    # variable named `field` or `strict` inside an expression from changing the
    # compiler lane, while every WHEX declaration remains valid when the file is
    # simply written with the .wh suffix.
    first_by_line: dict[int, str] = {}
    for t in toks:
        if t.kind not in {"IDENT", "KW"}:
            continue
        first_by_line.setdefault(t.line, unicodedata.normalize("NFC", str(t.value)))
    markers={"axis", "pure", "region", "for", "field", "each", "strict", "tolerance"}
    # Lane identity is a semantic boundary. Exact structural vocabulary is
    # decisive. Fuzzy spelling repair is only allowed as *corroborating* lane
    # evidence: two or more independent line-leading structural-keyword repairs
    # are required. This lets deliberately misspelled structural source reach
    # the structural parser while preventing an accidental legacy fragment such
    # as line-wrapped `temperature` -> `ture` from becoming `pure` and silently
    # switching execution models. Once selected, the parser performs the normal
    # conservative one-character repair.
    exact=set()
    fuzzy_hits=set()
    for line,v in first_by_line.items():
        c=SOFT_TO_CANONICAL.get(v, wx.ALIAS_TO_CANONICAL.get(v, v))
        if c in markers:
            exact.add(c)
            continue
        if wh._english_repairable(v):
            candidate,_=wh._unique_distance_one(v, markers)
            if candidate is not None:
                fuzzy_hits.add((line,candidate))
    return bool(exact) or len(fuzzy_hits) >= 2


class WHStructuralParser(wx.WHEXParser):
    """Inference-heavy WH surface targeting the unchanged WHEX structural core."""

    def __init__(self, text: str, source: Path | None = None, *, auto_repair: bool = True):
        super().__init__(text, source, auto_repair=auto_repair)
        self.surface_for_loops = 0
        self.surface_if_nodes = 0
        self.surface_while_requests = 0

    def _soft_keyword(self, value: str) -> bool:
        tok = self.peek()
        if tok.kind not in {"IDENT", "KW"}:
            return False
        raw = unicodedata.normalize("NFC", str(tok.value))
        canonical = SOFT_TO_CANONICAL.get(raw, raw)
        if canonical == value:
            self.pos += 1
            return True
        return False

    def _expect_soft(self, value: str) -> None:
        if not self._soft_keyword(value):
            raise self.error(f"expected WH surface keyword {value!r}")

    def parse_primary(self) -> dict[str, Any]:
        # Familiar WH conditional is a semantic predicate, not a branch request.
        if self._soft_keyword("if"):
            cond = self.parse_expr()
            self.expect_op("{")
            yes = self.parse_expr()
            self.optional_semicolon()
            self.expect_op("}")
            self._expect_soft("else")
            self.expect_op("{")
            no = self.parse_expr()
            self.optional_semicolon()
            self.expect_op("}")
            self.surface_if_nodes += 1
            return {"op": "select", "args": [cond, yes, no]}
        return super().parse_primary()

    def _parse_for_axes(self) -> tuple[list[dict[str, Any]], set[str]]:
        axes: list[dict[str, Any]] = []
        names: set[str] = set()
        while True:
            name = self.parse_name(allow_numeric=True)
            if name in names:
                raise self.error(f"duplicate WH for-axis {name!r}")
            self._expect_soft("in") if False else None
            # `in` is already a WHEX keyword and may have been lexed as IDENT by
            # the shared WH lexer.  WHEX _consume_keyword handles both cases.
            self.expect_kw("in")
            first = self.parse_expr()
            if self.match_op(".."):
                # Familiar half-open range.  The current structural axis starts
                # at zero; nonzero origins are preserved as structure only when
                # a future axis-offset proof exists, so reject now.
                if first != {"literal": 0, "type": "u64"}:
                    raise self.error("WH structural for currently requires a zero-based range 0..extent")
                extent = self.parse_expr()
            else:
                extent = first
            axes.append({"name": name, "extent": extent})
            names.add(name)
            if self.match_op(","):
                continue
            return axes, names

    def _parse_index_list(self) -> list[str]:
        self.expect_op("[")
        names: list[str] = []
        if self.match_op("]"):
            return names
        while True:
            names.append(self.parse_ref_name(allow_numeric=True))
            if self.match_op(","):
                continue
            self.expect_op("]")
            return names

    def parse_for(self) -> None:
        self.surface_for_loops += 1
        axes, names = self._parse_for_axes()
        self.expect_op("{")
        self.axes.append(names)
        try:
            # Optional familiar `let` on an element assignment.
            self.match_kw("let")
            target = self.parse_name(allow_numeric=True)
            if self.peek().kind == "OP" and self.peek().value == "[":
                indices = self._parse_index_list()
                if indices != [a["name"] for a in axes]:
                    raise self.error("WH structural element assignment indices must match the declared for-axes in order")
                self.expect_op(":")
                typ = self.parse_scalar_type()
                if typ != "f64":
                    raise self.error("current unified native topology requires structural WH map elements to be f64")
                self.expect_op("=")
                expr = self.parse_expr()
                self.optional_semicolon()
                self.expect_op("}")
                self.data["bindings"].append({
                    "name": target, "op": "map", "type": typ,
                    "axes": axes, "expr": expr,
                })
                self.binding_regions.setdefault(target, self.current_region)
                self.optional_semicolon()
                return

            # Familiar accumulation form.  It is accepted only as an explicit
            # associative sum reduction, never as mutable scalar state.
            typ: Any = "f64"
            if self.match_op(":"):
                typ = self.parse_scalar_type()
            if not self.match_op("+") or not self.match_op("="):
                raise self.error("WH structural for body must be element assignment or associative '+=' reduction")
            if typ != "f64":
                raise self.error("current unified native topology requires structural WH sum accumulator to be f64")
            expr = self.parse_expr()
            self.optional_semicolon()
            self.expect_op("}")
            axes2, expr2 = self._erase_irrelevant_reduction_axes(target, axes, expr)
            self.data["bindings"].append({
                "name": target, "op": "reduce", "kind": "sum",
                "accumulator": self._accumulator(typ), "axes": axes2, "expr": expr2,
            })
            self.binding_regions.setdefault(target, self.current_region)
            self.optional_semicolon()
        finally:
            self.axes.pop()

    def _reject_while(self) -> None:
        self.surface_while_requests += 1
        raise self.error(
            "WH 'while' is control intent, not permission to emit a serial backedge; "
            "the current unified structural core cannot yet prove this recurrence/fixed-point topology, "
            "so compilation is rejected instead of falling back to sequential execution"
        )

    def _parse_region_member(self) -> None:
        before = len(self.data["bindings"])
        if self._soft_keyword("for"):
            self.parse_for()
        elif self._soft_keyword("while"):
            self._reject_while()
        elif self.match_kw("field"):
            self.parse_field()
        elif self.match_kw("each"):
            self.parse_each()
        elif self.match_kw("sum"):
            self.parse_reduction("sum")
        else:
            raise self.error("WH structural region accepts for/field/each/sum; dynamic while rejects until topology proof exists")
        for item in self.data["bindings"][before:]:
            self.binding_regions[item["name"]] = self.current_region

    def parse(self) -> dict[str, Any]:
        while self.peek().kind != "EOF":
            if self.match_kw("program"):
                if self.data["program"] is not None:
                    raise self.error("program declared more than once")
                self.parse_program()
            elif self.match_kw("input"):
                self.parse_hpc_input()
            elif self.match_kw("axis"):
                self.parse_axis_declaration()
            elif self.match_kw("pure"):
                self.parse_structural_function()
            elif self.match_kw("record"):
                self.parse_compiletime_record()
            elif self.match_kw("region"):
                self.parse_region()
            elif self.match_kw("tolerance"):
                self.parse_tolerance()
            elif self.match_kw("strict"):
                self.parse_strict()
            elif self._soft_keyword("for"):
                self.parse_for()
            elif self._soft_keyword("while"):
                self._reject_while()
            elif self.match_kw("field"):
                self.parse_field()
            elif self.match_kw("each"):
                self.parse_each()
            elif self.match_kw("sum"):
                self.parse_reduction("sum")
            elif self.match_kw("output"):
                self.parse_output(False)
            elif self.match_kw("test"):
                self.parse_test()
            else:
                raise self.error("expected WH structural declaration")

        if self.data["program"] is None:
            stem = self.source.stem if self.source else "structural_program"
            self.human_program_name = wh.normalize_name(stem, "program name")
            self.core_program_name = wh.core_program_name(self.human_program_name)
            self.data["program"] = self.core_program_name
        if len(self.data["inputs"]) != 1:
            raise wh.SurfaceError("current unified WH/WHEX topology requires exactly one n:u64 extent input")
        reductions = [b for b in self.data["bindings"] if b.get("op") == "reduce"]
        if len(reductions) != 1:
            raise wh.SurfaceError("current unified WH/WHEX topology requires exactly one sum reduction")
        if len(self.data["outputs"]) != 1:
            raise wh.SurfaceError("current unified WH/WHEX topology requires exactly one scalar output")
        out_expr = self.data["outputs"][0].get("expr", {})
        if out_expr != {"var": reductions[0]["name"]}:
            raise wh.SurfaceError("WH structural output must publish the single structural sum reduction")
        if not self.data["tests"]:
            raise wh.SurfaceError("WH structural program must declare at least one test")

        plan = ws.build_plan(
            self.data, functions=self.functions, records=self.records,
            axis_declarations=self.axis_declarations,
            binding_regions=self.binding_regions, regions=self.regions,
            rank_n_erasures=self.rank_n_erasures,
        )
        plan["surface"] = {
            "kind": "wheelchair.wh.inference_surface/1",
            "for_loops": self.surface_for_loops,
            "if_nodes": self.surface_if_nodes,
            "while_requests": self.surface_while_requests,
            "runtime_loop_objects": 0,
            "runtime_if_dispatchers": 0,
            "runtime_surface_objects": 0,
            "imperative_syntax_implies_serial_execution": False,
            "structural_recovery_required": True,
        }
        plan["surface_equivalence_contract"] = {
            "target": "wheelchair.whex.semantic/1",
            "canonical_equivalence_required": True,
            "native_equivalence_required_when_proof_complete": True,
            "failure_policy": "explicit_reject_not_general_or_scalar_fallback",
        }
        self.semantic_plan = plan
        return self.data


def compile_surface(text: str, source: Path | None = None, *, auto_repair: bool = True):
    p = WHStructuralParser(text, source, auto_repair=auto_repair)
    return p.parse(), p


def load_surface(path: Path, *, auto_repair: bool = True):
    if path.suffix.lower() != SOURCE_EXTENSION:
        raise wh.SurfaceError(f"Wheelchair source must use {SOURCE_EXTENSION!r}")
    text = path.read_text(encoding="utf-8", errors="strict")
    data, parser = compile_surface(text, path, auto_repair=auto_repair)
    return data, parser, text


def canonical_core_bytes(data: dict[str, Any]) -> bytes:
    return wh.canonical_core_bytes(data)


def core_hash(data: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_core_bytes(data)).hexdigest()


def semantic_plan(parser: WHStructuralParser) -> dict[str, Any]:
    return parser.semantic_plan
