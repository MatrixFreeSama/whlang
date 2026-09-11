#!/usr/bin/env python3
"""Wheelchair Expert (.whex) structural semantic front-end.

WHEX 1.1.0 admits compile-time Axis/Region/Effect/Ownership abstractions,
pure structural functions, records, and proof-gated Rank-N axis erasure.
All erasable abstractions disappear before the existing wheelchair.tensor/1
canonical graph reaches topologyc. Unsupported semantics reject explicitly;
there is no scalar or general-lane fallback.
"""
from __future__ import annotations
import argparse, hashlib, json, sys, tempfile, unicodedata, subprocess
from pathlib import Path
from typing import Any

import wh_surface as wh
import whex_semantics as ws
import rank_n_product as rnp

SOURCE_EXTENSION = ".whex"
FORMAT = wh.FORMAT

ALIASES: dict[str, tuple[str, ...]] = {
    "program": ("program", "程序", "程式"),
    "input": ("input", "输入", "輸入"),
    "range": ("range", "范围", "範圍"),
    "tolerance": ("tolerance", "容差", "容差"),
    "strict": ("strict", "严格", "嚴格"),
    "field": ("field", "场", "場"),
    "each": ("each", "每个", "每個"),
    "in": ("in", "属于", "屬於"),
    "sum": ("sum", "求和", "總和"),
    "periodic": ("periodic", "周期", "週期"),
    "output": ("output", "输出", "輸出"),
    "test": ("test", "测试", "測試"),
    "true": ("true", "真", "真"),
    "false": ("false", "假", "假"),
    "cast": ("cast", "转换", "轉換"),
    "min": ("min", "最小", "最小"),
    "max": ("max", "最大", "最大"),
    "abs": ("abs", "绝对值", "絕對值"),
    "axis": ("axis", "轴", "軸"),
    "pure": ("pure", "纯", "純"),
    "generic": ("generic", "泛型", "泛型"),
    "fn": ("fn", "函数", "函數"),
    "record": ("record", "记录", "記錄"),
    "region": ("region", "区域", "區域"),
    "effect": ("effect", "效应", "效應"),
    "parallel": ("parallel", "并行", "並行"),
    "local_state": ("local_state", "局部状态", "局部狀態"),
    "region_write": ("region_write", "区域写", "區域寫"),
    "shared_state": ("shared_state", "共享状态", "共享狀態"),
    "atomic": ("atomic", "原子", "原子"),
    "io": ("io", "输入输出", "輸入輸出"),
    "device": ("device", "设备", "裝置"),
    "external": ("external", "外部", "外部"),
}
ALIAS_TO_CANONICAL = {
    unicodedata.normalize("NFC", alias): canonical
    for canonical, aliases in ALIASES.items() for alias in aliases
}
ENGLISH_KEYWORDS = frozenset(ALIASES)
PREFERRED = {
    "en": {k: v[0] for k, v in ALIASES.items()},
    "zh-hans": {k: (v[1] if len(v)>1 else v[0]) for k, v in ALIASES.items()},
    "zh-hant": {k: (v[2] if len(v)>2 else v[-1]) for k, v in ALIASES.items()},
}

class WHEXParser(wh.Parser):
    def __init__(self, text: str, source: Path | None = None, *, auto_repair: bool = True):
        super().__init__(text, source, auto_repair=auto_repair)
        self.default_tolerance: float | None = None
        # Surface-only semantic objects.  They are proven and erased before the
        # existing wheelchair.tensor/1 graph reaches topologyc.
        self.functions: dict[str, dict[str, Any]] = {}
        self.records: dict[str, dict[str, Any]] = {}
        self.axis_declarations: dict[str, Any] = {}
        self.regions: dict[str, dict[str, Any]] = {}
        self.binding_regions: dict[str, str] = {}
        self.local_scopes: list[set[str]] = []
        self.current_region = "root"
        self.regions["root"] = {"effect": "pure", "parallel": True}
        self._function_expansion_stack: list[str] = []
        self.rank_n_erasures: list[dict[str, Any]] = []
        self.data = {
            "format": FORMAT,
            "program": None,
            "contracts": {
                "deterministic": True,
                "integer_overflow": "trap",
                "floating_point": "strict_by_default",
                "mixed_precision": "lower_precision_dominates",
            },
            "inputs": [], "bindings": [], "outputs": [], "tests": [],
        }

    def _known_reference_names(self) -> set[str]:
        names = super()._known_reference_names()
        names.update(self.records)
        names.update(self.functions)
        names.update(self.axis_declarations)
        for scope in self.local_scopes:
            names.update(scope)
        return names

    def _resolve_name_expr(self, name: str) -> dict[str, Any]:
        if any(name in scope for scope in reversed(self.local_scopes)):
            return {"var": name}
        if name in self.records:
            return {"record_ref": name}
        return super()._resolve_name_expr(name)

    @staticmethod
    def _subst_expr(node: Any, mapping: dict[str, Any]) -> Any:
        if isinstance(node, list):
            return [WHEXParser._subst_expr(x, mapping) for x in node]
        if not isinstance(node, dict):
            return node
        if set(node) == {"var"} and node.get("var") in mapping:
            import copy
            return copy.deepcopy(mapping[node["var"]])
        return {k: WHEXParser._subst_expr(v, mapping) for k, v in node.items()}

    def _expand_function(self, name: str, args: list[dict[str, Any]]) -> dict[str, Any]:
        fn = self.functions[name]
        params = fn["params"]
        if len(args) != len(params):
            raise self.error(f"function {name!r} requires {len(params)} arguments")
        if name in self._function_expansion_stack:
            raise self.error(f"recursive WHEX structural function {name!r} cannot be erased without a runtime call")
        self._function_expansion_stack.append(name)
        try:
            return self._subst_expr(fn["body"], dict(zip(params, args)))
        finally:
            self._function_expansion_stack.pop()

    def parse_postfix(self) -> dict[str, Any]:
        expr = self.parse_primary()
        while True:
            if self.match_op("["):
                indices: list[dict[str, Any]] = []
                if not self.match_op("]"):
                    while True:
                        indices.append(self.parse_expr())
                        if self.match_op(","):
                            continue
                        self.expect_op("]")
                        break
                if set(expr) != {"var"}:
                    raise self.error("tensor indexing requires a tensor name")
                expr = {"load": expr["var"], "indices": indices}
                continue
            if self.match_op("."):
                if set(expr) == {"record_ref"}:
                    record_name = expr["record_ref"]
                    fields = set(self.records[record_name])
                    field = self.parse_ref_name(allow_numeric=True, candidates=fields)
                    import copy
                    expr = copy.deepcopy(self.records[record_name][field])
                    continue
                raise self.error("field access requires a compile-time WHEX record")
            break
        return expr

    def _keyword_candidate(self, token: wh.Token):
        if token.kind != "IDENT" or token.raw.startswith("`"):
            return None, []
        return wh._unique_distance_one(str(token.value), ENGLISH_KEYWORDS)

    def _consume_keyword(self, value: str) -> bool:
        tok = self.peek()
        raw = unicodedata.normalize("NFC", str(tok.value)) if tok.kind in {"KW", "IDENT"} else ""
        # shared WH lexer may already canonicalize program/input/output/test/etc.
        if tok.kind == "KW" and tok.value == value:
            self.pos += 1; return True
        if tok.kind == "IDENT" and ALIAS_TO_CANONICAL.get(raw) == value:
            self.pos += 1; return True
        if not self.auto_repair:
            return False
        joined = self._newline_join()
        if joined is not None and joined[0] == value and wh._english_repairable(value):
            _, a, b = joined; self.pos += 2
            self._record_repair("newline_keyword", a, value,
                                "English WHEX keyword was split by a newline",
                                original=self.text[a.start:b.end])
            return True
        candidate, matches = self._keyword_candidate(tok)
        if candidate == value:
            self.pos += 1
            self._record_repair("english_keyword", tok, value,
                                "unique English WHEX keyword at edit distance 1")
            return True
        if len(matches) > 1 and value in matches:
            raise self.error(f"ambiguous English WHEX keyword typo {tok.raw!r}; candidates: {', '.join(matches)}", tok)
        return False

    def parse_primary(self) -> dict[str, Any]:
        # Human-only periodic(index, extent) sugar -> existing mod node.
        save = self.pos
        if self.match_kw("periodic"):
            self.expect_op("("); idx = self.parse_expr(); self.expect_op(",")
            extent = self.parse_expr(); self.expect_op(")")
            return {"op": "mod", "args": [idx, extent]}
        self.pos = save
        tok = self.peek()
        # Structural functions are compile-time expression transformers.  The
        # call syntax vanishes before canonical IR and cannot create CALL/RET.
        if tok.kind == "IDENT" and str(tok.value) in self.functions and self.peek(1).kind == "OP" and self.peek(1).value == "(":
            self.pos += 1
            name = str(tok.value)
            self.expect_op("(")
            args: list[dict[str, Any]] = []
            if not self.match_op(")"):
                while True:
                    args.append(self.parse_expr())
                    if self.match_op(","): continue
                    self.expect_op(")"); break
            return self._expand_function(name, args)
        return super().parse_primary()

    @staticmethod
    def _expr_axis_refs(node: Any) -> set[str]:
        out: set[str] = set()
        def walk(x: Any) -> None:
            if isinstance(x, dict):
                if set(x) == {"axis"} and isinstance(x.get("axis"), str): out.add(x["axis"])
                for v in x.values(): walk(v)
            elif isinstance(x, list):
                for v in x: walk(v)
        walk(node)
        return out

    @staticmethod
    def _literal_positive_u64(expr: Any) -> int | None:
        if not isinstance(expr, dict) or "literal" not in expr: return None
        v=expr.get("literal")
        if isinstance(v, bool) or not isinstance(v, int) or v <= 0: return None
        return v

    def _erase_irrelevant_reduction_axes(self, name: str, axes: list[dict[str, Any]], expr: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
        if len(axes) <= 1: return axes, expr
        used=self._expr_axis_refs(expr)
        n_axes=[a for a in axes if a.get("extent") == {"var":"n"}]
        if len(n_axes) != 1: return axes, expr
        survivor=n_axes[0]
        multiplicity=1
        erased=[]
        for a in axes:
            if a is survivor: continue
            if a.get("name") in used: return axes, expr
            extent=self._literal_positive_u64(a.get("extent"))
            if extent is None: return axes, expr
            multiplicity *= extent
            if multiplicity >= (1<<53): return axes, expr
            erased.append({"name":a.get("name"),"extent":extent})
        if multiplicity != 1:
            expr={"op":"mul","args":[{"literal":float(multiplicity),"type":"f64"},expr]}
        self.rank_n_erasures.append({
            "binding":name,"source_rank":len(axes),"native_rank":1,
            "survivor":survivor.get("name"),"erased_axes":erased,
            "multiplicity":multiplicity,"proof":"expression_independent_of_erased_axes",
        })
        return [survivor],expr

    def parse_axis_declaration(self) -> None:
        name = self.parse_name(allow_numeric=True)
        if name in self.axis_declarations:
            raise self.error(f"duplicate axis declaration {name!r}")
        if self.match_kw("in"):
            extent = self.parse_expr()
        else:
            self.expect_op("=")
            extent = self.parse_expr()
        self.axis_declarations[name] = extent
        self.optional_semicolon()

    def parse_structural_function(self) -> None:
        # `pure [generic] fn name(x[:T], y[:T]) [-> T] = expr`
        self.match_kw("generic")
        self.expect_kw("fn")
        name = self.parse_name(allow_numeric=False)
        if name in self.functions:
            raise self.error(f"duplicate structural function {name!r}")
        self.expect_op("(")
        params: list[str] = []
        if not self.match_op(")"):
            while True:
                param = self.parse_name(allow_numeric=False)
                if param in params: raise self.error(f"duplicate function parameter {param!r}")
                if self.match_op(":"):
                    self.parse_scalar_type()  # type is a proof annotation; specialization erases it
                params.append(param)
                if self.match_op(","): continue
                self.expect_op(")"); break
        if self.match_op("->"):
            self.parse_scalar_type()
        self.expect_op("=")
        self.local_scopes.append(set(params))
        try:
            body = self.parse_expr()
        finally:
            self.local_scopes.pop()
        self.functions[name] = {"params": params, "body": body, "effect": "pure", "generic": True}
        self.optional_semicolon()

    def parse_compiletime_record(self) -> None:
        name = self.parse_name(allow_numeric=True)
        if name in self.records:
            raise self.error(f"duplicate compile-time record {name!r}")
        self.expect_op("{")
        fields: dict[str, Any] = {}
        while not self.match_op("}"):
            field = self.parse_name(allow_numeric=True)
            if field in fields: raise self.error(f"duplicate record field {field!r}")
            self.expect_op("=")
            fields[field] = self.parse_expr()
            self.match_op(","); self.optional_semicolon()
        self.records[name] = fields
        self.optional_semicolon()

    def _parse_region_member(self) -> None:
        before = len(self.data["bindings"])
        if self.match_kw("field"): self.parse_field()
        elif self.match_kw("each"): self.parse_each()
        elif self.match_kw("sum"): self.parse_reduction("sum")
        else: raise self.error("WHEX region accepts field/each/sum declarations in the current native lane")
        for item in self.data["bindings"][before:]:
            self.binding_regions[item["name"]] = self.current_region

    def parse_region(self) -> None:
        name = self.parse_name(allow_numeric=True)
        if name in self.regions: raise self.error(f"duplicate region {name!r}")
        effect = "pure"
        parallel = False
        if self.match_kw("effect"):
            effect_kw = self.match_one_kw(("pure","local_state","region_write","shared_state","atomic","io","device","external"))
            if effect_kw is None:
                raise self.error("effect expects pure/local_state/region_write/shared_state/atomic/io/device/external")
            effect = effect_kw
        if self.match_kw("parallel"):
            parallel = True
        if not parallel:
            raise self.error("WHEX regions must explicitly declare parallel; hidden sequential regions are forbidden")
        self.regions[name] = {"effect": effect, "parallel": True}
        self.expect_op("{")
        old = self.current_region
        self.current_region = name
        try:
            while not self.match_op("}"):
                self._parse_region_member()
        finally:
            self.current_region = old
        self.optional_semicolon()

    def parse_hpc_input(self) -> None:
        if self.data["inputs"]:
            raise self.error("current dedicated topologyc currently accepts exactly one external extent input")
        name = self.parse_name(allow_numeric=False)
        if name != "n":
            raise self.error("current dedicated topologyc requires the external extent input to be named 'n'")
        self.expect_op(":")
        typ = self.parse_scalar_type()
        if typ != "u64":
            raise self.error("current dedicated topologyc requires n: u64")
        if not self.match_kw("range"):
            raise self.error("WHEX n input requires an explicit range")
        lo = self.parse_literal_value(); self.expect_op(".."); hi = self.parse_literal_value()
        self.data["inputs"].append({"name":"n","type":"u64","min":lo,"max":hi})
        self.optional_semicolon()

    def parse_tolerance(self) -> None:
        tok = self.take()
        if tok.kind != "NUMBER":
            raise self.error("tolerance requires one non-negative numeric budget", tok)
        val = float(wh.parse_number(tok.raw))
        if val < 0:
            raise self.error("tolerance must be non-negative", tok)
        self.default_tolerance = val
        self.data["contracts"]["floating_point"] = "strict_by_default" if val == 0 else "tolerant"
        self.optional_semicolon()

    def parse_strict(self) -> None:
        self.default_tolerance = 0.0
        self.data["contracts"]["floating_point"] = "strict_by_default"
        self.optional_semicolon()

    def _parse_whex_axes(self) -> tuple[list[dict[str, Any]], set[str]]:
        self.expect_op("[")
        axes: list[dict[str, Any]] = []; names: set[str] = set()
        if self.match_op("]"):
            raise self.error("WHEX field/reduction requires at least one topology axis")
        while True:
            name = self.parse_name(allow_numeric=True)
            if name in names:
                raise self.error(f"duplicate topology axis {name!r}")
            self.expect_kw("in")
            extent = self.parse_expr()
            axes.append({"name": name, "extent": extent}); names.add(name)
            if self.match_op(","): continue
            self.expect_op("]"); break
        return axes, names

    def parse_field(self) -> None:
        name = self.parse_name(allow_numeric=True)
        axes, names = self._parse_whex_axes()
        self.expect_op(":"); typ = self.parse_scalar_type()
        if typ != "f64": raise self.error("current dedicated topologyc WHEX fields are currently f64")
        if len(axes)==1 and axes[0].get("extent") != {"var":"n"}: raise self.error("current native topologyc WHEX rank-1 field extent must be n")
        self.expect_op("=")
        self.axes.append(names)
        try: expr = self.parse_expr()
        finally: self.axes.pop()
        self.data["bindings"].append({"name": name, "op": "map", "type": typ, "axes": axes, "expr": expr})
        self.binding_regions.setdefault(name, self.current_region)
        self.optional_semicolon()

    def parse_each(self) -> None:
        # Familiar block form of a structural Rank-N map. No axis is serialized.
        axes: list[dict[str, Any]] = []; names: set[str] = set()
        while True:
            axis = self.parse_name(allow_numeric=True)
            if axis in names: raise self.error(f"duplicate topology axis {axis!r}")
            self.expect_kw("in"); extent = self.parse_expr()
            axes.append({"name": axis, "extent": extent}); names.add(axis)
            if self.match_op(","): continue
            break
        self.expect_op("{")
        name = self.parse_name(allow_numeric=True)
        self.expect_op(":"); typ = self.parse_scalar_type()
        if typ != "f64": raise self.error("current dedicated topologyc WHEX fields are currently f64")
        if len(axes)==1 and axes[0].get("extent") != {"var":"n"}: raise self.error("current native topologyc WHEX rank-1 each extent must be n")
        self.expect_op("=")
        self.axes.append(names)
        try: expr = self.parse_expr()
        finally: self.axes.pop()
        self.optional_semicolon(); self.expect_op("}"); self.optional_semicolon()
        self.data["bindings"].append({"name": name, "op": "map", "type": typ, "axes": axes, "expr": expr})
        self.binding_regions.setdefault(name, self.current_region)

    def _accumulator(self, typ: Any) -> Any:
        if isinstance(typ, dict): return typ
        if typ not in {"f32", "f64"}:
            raise self.error("current dedicated topologyc reduction accumulator is currently floating-point only")
        budget = 0.0 if self.default_tolerance in {None, 0.0} else float(self.default_tolerance)
        return {"base": typ, "mode": "tolerant",
                "absolute_error": budget, "relative_error": budget}

    def parse_reduction(self, kind: str) -> None:
        name = self.parse_name(allow_numeric=True)
        axes, names = self._parse_whex_axes()
        self.expect_op(":"); typ = self.parse_scalar_type()
        if typ != "f64": raise self.error("current dedicated topologyc WHEX sum accumulator is currently f64")
        if len(axes)==1 and axes[0].get("extent") != {"var":"n"}: raise self.error("current native topologyc WHEX rank-1 sum extent must be n")
        self.expect_op("=")
        self.axes.append(names)
        try: expr = self.parse_expr()
        finally: self.axes.pop()
        axes,expr=self._erase_irrelevant_reduction_axes(name,axes,expr)
        self.data["bindings"].append({"name": name, "op": "reduce", "kind": kind,
                                      "accumulator": self._accumulator(typ), "axes": axes, "expr": expr})
        self.binding_regions.setdefault(name, self.current_region)
        self.optional_semicolon()

    def parse(self) -> dict[str, Any]:
        while self.peek().kind != "EOF":
            if self.match_kw("program"):
                if self.data["program"] is not None: raise self.error("program declared more than once")
                self.parse_program()
            elif self.match_kw("input"): self.parse_hpc_input()
            elif self.match_kw("axis"): self.parse_axis_declaration()
            elif self.match_kw("pure"): self.parse_structural_function()
            elif self.match_kw("record"): self.parse_compiletime_record()
            elif self.match_kw("region"): self.parse_region()
            elif self.match_kw("tolerance"): self.parse_tolerance()
            elif self.match_kw("strict"): self.parse_strict()
            elif self.match_kw("field"): self.parse_field()
            elif self.match_kw("each"): self.parse_each()
            elif self.match_kw("sum"): self.parse_reduction("sum")
            elif self.match_kw("output"): self.parse_output(False)
            elif self.match_kw("test"): self.parse_test()
            else:
                raise self.error("expected WHEX declaration: program/input/axis/pure fn/record/region/tolerance/strict/field/each/sum/output/test")
        if self.data["program"] is None:
            stem = self.source.stem if self.source else "expert_program"
            self.human_program_name = wh.normalize_name(stem, "program name")
            self.core_program_name = wh.core_program_name(self.human_program_name)
            self.data["program"] = self.core_program_name
        if len(self.data["inputs"]) != 1: raise wh.SurfaceError("WHEX requires exactly one n:u64 extent input")
        reductions=[b for b in self.data["bindings"] if b.get("op")=="reduce"]
        if len(reductions) != 1: raise wh.SurfaceError("current dedicated topologyc currently requires exactly one sum reduction")
        if len(self.data["outputs"]) != 1: raise wh.SurfaceError("current dedicated topologyc WHEX currently requires exactly one scalar output")
        out_expr=self.data["outputs"][0].get("expr",{})
        if out_expr != {"var":reductions[0]["name"]}: raise wh.SurfaceError("WHEX output must publish the single sum reduction")
        if not self.data["tests"]: raise wh.SurfaceError("WHEX program must declare at least one test")
        # Build the semantic plan now so dependency cycles/effects/parallel contracts
        # reject before native lowering.  The plan is side metadata and never enters
        # canonical bytes, preserving zero-cost erasure.
        plan = ws.build_plan(
            self.data, functions=self.functions, records=self.records,
            axis_declarations=self.axis_declarations,
            binding_regions=self.binding_regions, regions=self.regions,
            rank_n_erasures=self.rank_n_erasures,
        )
        try:
            physical, evidence = rnp.physicalize(self.data)
        except rnp.RankNPhysicalizationError as exc:
            raise wh.SurfaceError(str(exc)) from exc
        if evidence:
            self.data = physical
            rnp.attach_semantic_plan(plan, evidence, int(physical["rank_n_product"]))
        self.semantic_plan = plan
        return self.data

def compile_surface(text: str, source: Path | None = None, *, auto_repair: bool = True):
    p = WHEXParser(text, source, auto_repair=auto_repair)
    return p.parse(), p

def canonical_core_bytes(data: dict[str, Any]) -> bytes:
    return wh.canonical_core_bytes(data)

def core_hash(data: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_core_bytes(data)).hexdigest()

def semantic_plan(parser: WHEXParser) -> dict[str, Any]:
    return parser.semantic_plan

def load_surface(path: Path, *, auto_repair: bool = True):
    if path.suffix.lower() != SOURCE_EXTENSION:
        raise wh.SurfaceError(f"Wheelchair Expert source must use {SOURCE_EXTENSION!r}")
    text = path.read_text(encoding="utf-8", errors="strict")
    data, parser = compile_surface(text, path, auto_repair=auto_repair)
    return data, parser, text

def format_keywords(text: str, language: str) -> str:
    if language == "preserve": return text
    replacements=[]
    for tok in wh.lex(text):
        if tok.raw.startswith("`"): continue
        raw=unicodedata.normalize("NFC", str(tok.value)) if tok.kind in {"KW","IDENT"} else ""
        canonical = tok.value if tok.kind=="KW" and tok.value in ALIASES else ALIAS_TO_CANONICAL.get(raw)
        if canonical in PREFERRED:
            replacements.append((tok.start,tok.end,PREFERRED[language][canonical]))
    out=[];cur=0
    for a,b,r in replacements: out += [text[cur:a],r]; cur=b
    out.append(text[cur:]); return "".join(out)

def _compile_native(root: Path, data: dict[str, Any], output: Path, executors: int, isa_limit: str | None = None) -> None:
    with tempfile.TemporaryDirectory(prefix="whex_core_") as td:
        core=Path(td)/"program.core.wh"; core.write_bytes(canonical_core_bytes(data))
        native_compiler = root/"build/topologyc-rankn" if "rank_n_product" in data else root/"build/topologyc"
        cmd=[str(native_compiler),str(core),"-o",str(output.resolve())]
        if executors != 1: cmd += ["--executors",str(executors)]
        if isa_limit is not None: cmd += ["--isa-limit",isa_limit]
        p=subprocess.run(cmd,cwd=root,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if p.returncode: raise wh.SurfaceError("current dedicated topologyc rejected WHEX graph:\n"+(p.stderr or p.stdout).strip())

def main() -> int:
    ap=argparse.ArgumentParser(description="Wheelchair Expert .whex structural semantics -> topology core")
    sub=ap.add_subparsers(dest="command",required=True)
    c=sub.add_parser("compile"); c.add_argument("source",type=Path); c.add_argument("-o","--output",type=Path)
    v=sub.add_parser("validate"); v.add_argument("source",type=Path)
    pl=sub.add_parser("plan"); pl.add_argument("source",type=Path)
    e=sub.add_parser("equivalent"); e.add_argument("sources",nargs="+",type=Path)
    f=sub.add_parser("format"); f.add_argument("source",type=Path); f.add_argument("--language",choices=["en","zh-hans","zh-hant","preserve"],default="en"); f.add_argument("--in-place",action="store_true")
    n=sub.add_parser("native"); n.add_argument("source",type=Path); n.add_argument("-o","--output",type=Path,required=True); n.add_argument("--executors",type=int,choices=[1,2,4],default=1)
    a=ap.parse_args()
    if a.command=="format":
        text=a.source.read_text(encoding="utf-8",errors="strict"); out=format_keywords(text,a.language)
        if a.in_place:a.source.write_text(out,encoding="utf-8")
        else:sys.stdout.write(out)
        return 0
    if a.command=="equivalent":
        rows=[]; blobs=[]
        for p in a.sources:
            d,parser,_=load_surface(p); b=canonical_core_bytes(d); blobs.append(b)
            rows.append({"source":str(p),"core_sha256":hashlib.sha256(b).hexdigest(),"repair_count":len(parser.repairs)})
        ok=all(b==blobs[0] for b in blobs[1:]); print(json.dumps({"equivalent":ok,"sources":rows},ensure_ascii=False,indent=2)); return 0 if ok else 1
    d,parser,_=load_surface(a.source); root=Path(__file__).resolve().parents[1]
    if a.command=="plan":
        print(json.dumps(semantic_plan(parser),ensure_ascii=False,indent=2)); return 0
    if a.command=="compile":
        out=a.output or a.source.with_name(a.source.stem+".core.wh"); out.write_bytes(canonical_core_bytes(d))
        print(json.dumps({"surface":"whex","core_output":str(out),"core_sha256":core_hash(d),"repair_count":len(parser.repairs),"repairs":[r.as_dict() for r in parser.repairs],"bottom_layer_modified":True,"compiler_release":"1.1.0"},ensure_ascii=False,indent=2)); return 0
    if a.command=="validate":
        with tempfile.TemporaryDirectory(prefix="whex_validate_") as td:
            _compile_native(root,d,Path(td)/"probe",1)
        print(json.dumps({"surface":"valid","core_sha256":core_hash(d),"repair_count":len(parser.repairs),"bottom_layer_modified":True,"compiler_release":"1.1.0"},ensure_ascii=False,indent=2)); return 0
    _compile_native(root,d,a.output,a.executors)
    print(json.dumps({"source":str(a.source),"output":str(a.output),"core_sha256":core_hash(d),"repair_count":len(parser.repairs),"repairs":[r.as_dict() for r in parser.repairs],"bottom_layer_modified":True,"compiler_release":"1.1.0"},ensure_ascii=False,indent=2)); return 0

if __name__=="__main__":
    try: raise SystemExit(main())
    except (wh.SurfaceError,UnicodeError,OSError) as exc:
        print(f"WHEX surface rejection: {exc}",file=sys.stderr); raise SystemExit(1)
