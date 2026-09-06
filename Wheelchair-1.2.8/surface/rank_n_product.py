#!/usr/bin/env python3
"""Wheelchair 1.2.2 proof-gated Rank-N Cartesian product physicalization.

Source Rank-N survives semantic planning. Only after the Axis/Region/Dependency
proofs have completed is a non-erasable product domain assigned one physical token
q. The mapping is a bijection, not a serial loop nest. Executors partition q and
the native SIMD episode consumes q points directly.

Mature 1.2.2 native admission is deliberately conservative:
* one external dynamic extent, named n;
* a terminal Rank-N sum reduction is required for native Rank-N execution;
* exactly one dynamic n axis per Rank-N binding;
* additional extents are positive compile-time powers of two;
* the terminal n*static_product fits the existing 2048*65536 physical-point cap;
* dynamic periodic/mod-n inside a Rank-N realized expression rejects for now.

The old Rank-1 path is not modified or routed through this module after it proves
that no non-erasable Rank-N terminal domain exists.
"""
from __future__ import annotations

import copy
import hashlib
import json
from dataclasses import dataclass
from typing import Any

MAX_PHYSICAL_POINTS = 2048 * 65536


class RankNPhysicalizationError(ValueError):
    pass


def _u64(v: int) -> dict[str, Any]:
    return {"literal": int(v), "type": "u64"}


def _is_n_extent(node: Any) -> bool:
    return node == {"var": "n"}


def _literal_extent(node: Any) -> int | None:
    if not isinstance(node, dict) or set(node) - {"literal", "type"}:
        return None
    value = node.get("literal")
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    if node.get("type", "u64") != "u64":
        return None
    return value


def _pow2(v: int) -> bool:
    return v > 0 and (v & (v - 1)) == 0


def _mul(a: dict[str, Any], b: dict[str, Any]) -> dict[str, Any]:
    if a == _u64(0) or b == _u64(0): return _u64(0)
    if a == _u64(1): return b
    if b == _u64(1): return a
    return {"op": "mul", "args": [a, b]}


def _add(a: dict[str, Any], b: dict[str, Any]) -> dict[str, Any]:
    if a == _u64(0): return b
    if b == _u64(0): return a
    return {"op": "add", "args": [a, b]}


def _ushr(a: dict[str, Any], shift: int) -> dict[str, Any]:
    if shift == 0: return a
    return {"op": "ushr", "args": [a, _u64(shift)]}


def _mod_pow2(a: dict[str, Any], extent: int) -> dict[str, Any]:
    if extent == 1: return _u64(0)
    return {"op": "mod", "args": [a, _u64(extent)]}


@dataclass(frozen=True)
class AxisSpec:
    name: str
    position: int
    dynamic: bool
    extent: int | None
    bits: int
    low_bit: int


@dataclass(frozen=True)
class Layout:
    binding: str
    source_rank: int
    physical_axis: str
    axes: tuple[AxisSpec, ...]
    static_factor: int
    static_bits: int
    physicalized: bool

    def coordinate(self, axis_name: str) -> dict[str, Any]:
        q = {"axis": self.physical_axis}
        for spec in self.axes:
            if spec.name != axis_name:
                continue
            if spec.dynamic:
                return _ushr(q, self.static_bits)
            assert spec.extent is not None
            return _mod_pow2(_ushr(q, spec.low_bit), spec.extent)
        raise RankNPhysicalizationError(
            f"axis {axis_name!r} is not local to binding {self.binding!r}"
        )

    def linearize(self, indices: list[dict[str, Any]]) -> dict[str, Any]:
        if len(indices) != self.source_rank:
            raise RankNPhysicalizationError(
                f"load of {self.binding!r} supplies {len(indices)} indices for rank {self.source_rank}"
            )
        if self.source_rank == 1:
            return indices[0]
        dynamic_term: dict[str, Any] | None = None
        static_term = _u64(0)
        static_specs = [a for a in self.axes if not a.dynamic]
        stride_by_name: dict[str, int] = {}
        stride = 1
        for spec in reversed(static_specs):
            stride_by_name[spec.name] = stride
            assert spec.extent is not None
            stride *= spec.extent
        for spec, idx in zip(self.axes, indices):
            if spec.dynamic:
                dynamic_term = _mul(idx, _u64(self.static_factor))
            else:
                static_term = _add(static_term, _mul(idx, _u64(stride_by_name[spec.name])))
        if dynamic_term is None:
            raise RankNPhysicalizationError(f"binding {self.binding!r} lost its dynamic n axis")
        return _add(dynamic_term, static_term)


def _layout_for(binding: dict[str, Any], ordinal: int) -> Layout:
    axes = binding.get("axes")
    if not isinstance(axes, list) or not axes:
        raise RankNPhysicalizationError(f"binding {binding.get('name')!r} has no structural axes")
    name = str(binding.get("name"))
    if len(axes) == 1:
        axis = axes[0]
        if not isinstance(axis, dict) or not _is_n_extent(axis.get("extent")):
            raise RankNPhysicalizationError(f"rank-1 binding {name!r} must keep dynamic extent n")
        axis_name = str(axis.get("name"))
        return Layout(name, 1, axis_name,
                      (AxisSpec(axis_name, 0, True, None, 0, 0),),
                      1, 0, False)

    dynamic_positions: list[int] = []
    raw_static: list[tuple[int, str, int]] = []
    for pos, axis in enumerate(axes):
        if not isinstance(axis, dict):
            raise RankNPhysicalizationError(f"malformed axis in binding {name!r}")
        axis_name = str(axis.get("name"))
        extent = axis.get("extent")
        if _is_n_extent(extent):
            dynamic_positions.append(pos)
            continue
        value = _literal_extent(extent)
        if value is None or not _pow2(value):
            raise RankNPhysicalizationError(
                f"Wheelchair 1.2.2 native Rank-N requires static extra extents to be positive powers of two; "
                f"binding {name!r}, axis {axis_name!r} is unsupported"
            )
        raw_static.append((pos, axis_name, value))
    if len(dynamic_positions) != 1:
        raise RankNPhysicalizationError(
            f"Wheelchair 1.2.2 native Rank-N requires exactly one dynamic n axis per Rank-N binding; "
            f"{name!r} has {len(dynamic_positions)}"
        )

    factor = 1
    total_bits = 0
    for _, _, extent in raw_static:
        factor *= extent
        total_bits += extent.bit_length() - 1
        if factor > MAX_PHYSICAL_POINTS:
            raise RankNPhysicalizationError(f"static product factor for {name!r} exceeds native capacity")

    low_by_name: dict[str, int] = {}
    low = 0
    for _, axis_name, extent in reversed(raw_static):
        low_by_name[axis_name] = low
        low += extent.bit_length() - 1

    specs: list[AxisSpec] = []
    for pos, axis in enumerate(axes):
        axis_name = str(axis.get("name"))
        if pos == dynamic_positions[0]:
            specs.append(AxisSpec(axis_name, pos, True, None, total_bits, total_bits))
        else:
            extent = _literal_extent(axis.get("extent"))
            assert extent is not None
            specs.append(AxisSpec(axis_name, pos, False, extent,
                                  extent.bit_length() - 1, low_by_name[axis_name]))
    return Layout(name, len(axes), f"__rankn_q_{ordinal}", tuple(specs), factor, total_bits, True)


def _dynamic_mod_present(node: Any) -> bool:
    if isinstance(node, dict):
        if node.get("op") == "mod":
            args = node.get("args")
            if isinstance(args, list) and len(args) == 2 and args[1] == {"var": "n"}:
                return True
        return any(_dynamic_mod_present(v) for v in node.values())
    if isinstance(node, list):
        return any(_dynamic_mod_present(v) for v in node)
    return False


def _rewrite_expr(node: Any, current: Layout, layouts: dict[str, Layout], logical_n_shift: int) -> Any:
    if isinstance(node, list):
        return [_rewrite_expr(v, current, layouts, logical_n_shift) for v in node]
    if not isinstance(node, dict):
        return node
    # In the Rank-N runtime ABI, the native backend's n register is the physical
    # Cartesian extent. Source-level n remains logical and is recovered exactly.
    if node == {"var": "n"}:
        return _ushr({"var": "n"}, logical_n_shift)
    if set(node) == {"axis"}:
        axis_name = str(node["axis"])
        if any(s.name == axis_name for s in current.axes):
            return current.coordinate(axis_name)
        return copy.deepcopy(node)
    if "load" in node and "indices" in node:
        target_name = str(node["load"])
        target = layouts.get(target_name)
        if target is None:
            raise RankNPhysicalizationError(f"load refers to unknown structural binding {target_name!r}")
        raw = node.get("indices")
        if not isinstance(raw, list):
            raise RankNPhysicalizationError(f"load indices for {target_name!r} are malformed")
        indices = [_rewrite_expr(v, current, layouts, logical_n_shift) for v in raw]
        out = {k: _rewrite_expr(v, current, layouts, logical_n_shift)
               for k, v in node.items() if k != "indices"}
        out["indices"] = [target.linearize(indices)]
        return out
    return {k: _rewrite_expr(v, current, layouts, logical_n_shift) for k, v in node.items()}


def physicalize(data: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    bindings = data.get("bindings")
    if not isinstance(bindings, list):
        raise RankNPhysicalizationError("canonical structural core has no binding list")
    layouts_list = [_layout_for(b, i) for i, b in enumerate(bindings)]
    reductions = [b for b in bindings if b.get("op") == "reduce"]
    if len(reductions) != 1:
        raise RankNPhysicalizationError("Rank-N product realization requires exactly one terminal reduction")
    terminal = next(x for x in layouts_list if x.binding == str(reductions[0].get("name")))

    # Erasable or ordinary rank-1 programs stay byte-for-byte on the old route.
    if not terminal.physicalized:
        return data, []

    if _dynamic_mod_present(reductions[0].get("expr")):
        raise RankNPhysicalizationError(
            "Wheelchair 1.2.2 keeps dynamic periodic/mod-n Rank-N reductions explicit; "
            "the protected 1.2.1 periodic optimizer is never weakened or repurposed"
        )

    inputs = data.get("inputs")
    if not isinstance(inputs, list) or len(inputs) != 1:
        raise RankNPhysicalizationError("Rank-N product realization requires exactly one n input")
    n_max = inputs[0].get("max")
    if isinstance(n_max, bool) or not isinstance(n_max, int) or n_max <= 0:
        raise RankNPhysicalizationError("Rank-N product realization requires a positive finite n maximum")
    if n_max > MAX_PHYSICAL_POINTS // terminal.static_factor:
        raise RankNPhysicalizationError(
            f"terminal Cartesian domain n*{terminal.static_factor} exceeds {MAX_PHYSICAL_POINTS} "
            f"at declared n max {n_max}"
        )

    # Any Rank-N definition that can reach the terminal expression is still fused
    # rather than materialized. Its tuple addressing is nevertheless preserved
    # bijectively. Dynamic mod-n remains rejected in those definitions as well.
    for binding, layout in zip(bindings, layouts_list):
        if layout.physicalized and _dynamic_mod_present(binding.get("expr")):
            raise RankNPhysicalizationError(
                f"binding {layout.binding!r} uses dynamic periodic/mod-n in Rank-N; unsupported in 1.2.2"
            )

    out = copy.deepcopy(data)
    layouts = {x.binding: x for x in layouts_list}
    for original, target, layout in zip(bindings, out["bindings"], layouts_list):
        target["expr"] = _rewrite_expr(original.get("expr"), layout, layouts, terminal.static_bits)
        if layout.physicalized:
            target["axes"] = [{"name": layout.physical_axis, "extent": {"var": "n"}}]

    out["rank_n_product"] = terminal.static_factor
    out["rank_n_source_rank"] = terminal.source_rank

    evidence: list[dict[str, Any]] = []
    for layout in layouts_list:
        if not layout.physicalized:
            continue
        evidence.append({
            "binding": layout.binding,
            "terminal_physical_domain": layout.binding == terminal.binding,
            "source_rank": layout.source_rank,
            "physical_axis": layout.physical_axis,
            "static_factor": layout.static_factor,
            "static_bits": layout.static_bits,
            "mapping": "bijective_cartesian_product_token",
            "serial_axis_loops": 0,
            "scalar_fallback": False,
            "runtime_shape_object": False,
            "coordinates": [
                {"name": s.name, "dynamic_n": s.dynamic,
                 "extent": "n" if s.dynamic else s.extent,
                 "low_bit": s.low_bit, "bits": s.bits}
                for s in layout.axes
            ],
        })
    return out, evidence


def attach_semantic_plan(plan: dict[str, Any], evidence: list[dict[str, Any]], product: int) -> None:
    if not evidence:
        return
    axis = plan.setdefault("axis_algebra", {})
    axis["rank_n_product_realizations"] = evidence
    axis["source_rank_native_policy_1_2_2"] = (
        "prove-erasure-first; otherwise bijective Cartesian product physicalization; never nested serial flatten"
    )
    axis["terminal_physical_product_factor"] = int(product)
    p = plan.setdefault("parallelism_contract", {})
    p["rank_n_product_parallel_cardinality_preserved"] = True
    p["rank_n_serial_inner_loop"] = False
    p["rank_n_scalar_fallback"] = False
    serial = plan.setdefault("serial_introduction_report", {})
    serial["new_serial_axis_loops"] = 0
    erasure = plan.setdefault("abstraction_erasure", {})
    erasure["rank_n_runtime_shape_objects"] = 0
    erasure["rank_n_runtime_axis_metadata_objects"] = 0
    unhashed = {k: v for k, v in plan.items() if k != "semantic_sha256"}
    plan["semantic_sha256"] = hashlib.sha256(
        (json.dumps(unhashed, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    ).hexdigest()
