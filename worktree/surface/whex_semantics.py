#!/usr/bin/env python3
"""Compile-time semantic planning for Wheelchair Expert.

This module is deliberately non-executable at runtime.  It derives Region,
Effect, Dependency, Control-Topology, Erasure, and Parallelism contracts from
an already-erased WHEX canonical graph plus surface-only metadata.
"""
from __future__ import annotations
from dataclasses import dataclass
import hashlib
import json
from typing import Any, Iterable

PURE_EFFECT = "pure"
EFFECTS = {"pure", "local_state", "region_write", "shared_state", "atomic", "io", "device", "external"}

class SemanticError(Exception):
    pass


def _walk_expr(node: Any) -> Iterable[dict[str, Any]]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk_expr(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk_expr(value)


def expr_dependencies(expr: Any, binding_names: set[str], input_names: set[str]) -> tuple[set[str], set[str]]:
    bindings: set[str] = set()
    inputs: set[str] = set()
    for node in _walk_expr(expr):
        if "load" in node and isinstance(node.get("load"), str):
            name = node["load"]
            if name in binding_names:
                bindings.add(name)
            elif name in input_names:
                inputs.add(name)
        if set(node) == {"var"} and isinstance(node.get("var"), str):
            name = node["var"]
            if name in binding_names:
                bindings.add(name)
            elif name in input_names:
                inputs.add(name)
    return bindings, inputs


def _extent_text(expr: Any) -> str:
    if isinstance(expr, dict):
        if set(expr) == {"var"}: return str(expr["var"])
        if "literal" in expr: return str(expr["literal"])
    return json.dumps(expr, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def _domain_width_text(axes: list[dict[str, Any]]) -> str:
    parts=[_extent_text(a.get("extent")) for a in axes]
    if not parts: return "1"
    return "*".join(parts)


def _toposort(names: list[str], deps: dict[str, set[str]]) -> list[str]:
    indegree = {name: 0 for name in names}
    outgoing = {name: [] for name in names}
    for dst, sources in deps.items():
        for src in sources:
            if src not in indegree:
                continue
            indegree[dst] += 1
            outgoing[src].append(dst)
    ready = [n for n in names if indegree[n] == 0]
    order: list[str] = []
    while ready:
        n = ready.pop(0)
        order.append(n)
        for dst in outgoing[n]:
            indegree[dst] -= 1
            if indegree[dst] == 0:
                ready.append(dst)
    if len(order) != len(names):
        cycle = [n for n in names if indegree[n] != 0]
        raise SemanticError("WHEX dependency topology contains a cycle: " + ", ".join(cycle))
    return order


def _longest_dependency_depth(order: list[str], deps: dict[str, set[str]]) -> int:
    depth: dict[str, int] = {}
    for name in order:
        sources = deps.get(name, set())
        depth[name] = 1 + max((depth[s] for s in sources if s in depth), default=0)
    return max(depth.values(), default=0)


def build_plan(data: dict[str, Any], *, functions: dict[str, Any] | None = None,
               records: dict[str, Any] | None = None,
               axis_declarations: dict[str, Any] | None = None,
               binding_regions: dict[str, str] | None = None,
               regions: dict[str, Any] | None = None,
               rank_n_erasures: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    functions = functions or {}
    records = records or {}
    axis_declarations = axis_declarations or {}
    binding_regions = binding_regions or {}
    regions = regions or {}
    rank_n_erasures = rank_n_erasures or []

    bindings = list(data.get("bindings", []))
    names = [b.get("name") for b in bindings if isinstance(b.get("name"), str)]
    binding_names = set(names)
    if len(binding_names) != len(names):
        raise SemanticError("duplicate WHEX binding names would violate unique ownership")
    input_names = {x.get("name") for x in data.get("inputs", []) if isinstance(x.get("name"), str)}
    deps: dict[str, set[str]] = {n: set() for n in names}
    input_reads: dict[str, set[str]] = {n: set() for n in names}
    control_selects: dict[str, int] = {n: 0 for n in names}

    binding_rows: list[dict[str, Any]] = []
    max_rank = 0
    reduction_count = 0
    for b in bindings:
        name = b.get("name")
        if name not in deps:
            continue
        op = b.get("op")
        if op not in {"map", "reduce"}:
            raise SemanticError(f"WHEX true-parallel lane rejects runtime op {op!r}; no serial/general fallback is permitted")
        axes = b.get("axes", [])
        rank = len(axes)
        max_rank = max(max_rank, rank)
        if op == "reduce":
            reduction_count += 1
        bd, ins = expr_dependencies(b.get("expr"), binding_names, input_names)
        bd.discard(name)
        deps[name] = bd
        input_reads[name] = ins
        control_selects[name] = sum(1 for node in _walk_expr(b.get("expr")) if node.get("op") == "select")
        region = binding_regions.get(name, "root")
        region_info = regions.get(region, {"effect": PURE_EFFECT, "parallel": True})
        effect = region_info.get("effect", PURE_EFFECT)
        if effect not in EFFECTS:
            raise SemanticError(f"unknown effect {effect!r} in region {region!r}")
        if effect != PURE_EFFECT:
            raise SemanticError(
                f"WHEX native true-parallel lane currently accepts only effect pure; region {region!r} declares {effect!r}. "
                "Explicit rejection is required rather than hidden serialization."
            )
        if region_info.get("parallel", True) is not True:
            raise SemanticError(f"WHEX region {region!r} disables the parallel contract")
        binding_rows.append({
            "name": name,
            "op": op,
            "rank": rank,
            "axes": [{"name": a.get("name"), "extent": _extent_text(a.get("extent"))} for a in axes],
            "region": region,
            "effect": effect,
            "dependencies": sorted(bd),
            "input_reads": sorted(ins),
            "control_selects": control_selects[name],
            "parallel_required": True,
            "independent_domain_width": _domain_width_text(axes),
            "closure": "fan_in_two_tree" if op == "reduce" else "none",
        })

    order = _toposort(names, deps)
    depth = _longest_dependency_depth(order, deps)
    independent_pairs: list[list[str]] = []
    reach: dict[str, set[str]] = {n: set() for n in names}
    for n in order:
        for s in deps[n]:
            reach[n].add(s)
            reach[n].update(reach.get(s, ()))
    for i, a in enumerate(names):
        for b in names[i+1:]:
            if a not in reach[b] and b not in reach[a]:
                independent_pairs.append([a, b])

    region_names=list(regions) or ["root"]
    if "root" not in region_names: region_names.insert(0,"root")
    region_edges:set[tuple[str,str]]=set()
    name_region={row["name"]:row["region"] for row in binding_rows}
    for dst,sources in deps.items():
        dr=name_region.get(dst,"root")
        for src in sources:
            sr=name_region.get(src,"root")
            if sr != dr: region_edges.add((sr,dr))
    region_reach={r:set() for r in region_names}
    for a,b in region_edges: region_reach.setdefault(b,set()).add(a)
    changed=True
    while changed:
        changed=False
        for r in list(region_reach):
            add=set()
            for x in region_reach[r]: add.update(region_reach.get(x,()))
            if not add.issubset(region_reach[r]): region_reach[r].update(add); changed=True
    independent_regions=[]
    for i,a in enumerate(region_names):
        for b in region_names[i+1:]:
            if a not in region_reach.get(b,set()) and b not in region_reach.get(a,set()):
                independent_regions.append([a,b])

    # These counters are intentionally explicit.  A future lowering that adds
    # any non-semantic ordering must change the plan and fail the release gate.
    serial_report = {
        "new_serial_backedges": 0,
        "new_global_barriers": 0,
        "new_central_loops": 0,
        "new_scalar_regions": 0,
        "new_scalar_tails": 0,
        "new_scalar_fallbacks": 0,
        "new_global_queues": 0,
        "new_ordered_dependencies": 0,
    }
    erasure = {
        "surface_functions": len(functions),
        "runtime_function_objects": 0,
        "runtime_call_boundaries_from_surface_functions": 0,
        "surface_records": len(records),
        "runtime_record_objects": 0,
        "surface_regions": len(regions),
        "runtime_region_objects": 0,
        "runtime_effect_dispatch": 0,
        "runtime_axis_metadata_objects": 0,
    }
    plan = {
        "semantic_format": "wheelchair.whex.semantic/1",
        "program": data.get("program"),
        "axis_algebra": {
            "declared": [
                {"name": name, "extent": _extent_text(extent)}
                for name, extent in axis_declarations.items()
            ],
            "maximum_native_binding_rank": max_rank,
            "maximum_source_rank": max([max_rank]+[int(x.get("source_rank",0)) for x in rank_n_erasures]),
            "native_rank_limit": 1,
            "rank_n_eliminations": rank_n_erasures,
            "rank_n_policy": "prove_and_erase_irrelevant_axes_before_native_realization; otherwise preserve structure and reject",
        },
        "regions": [
            {"name": name, "effect": info.get("effect", PURE_EFFECT), "parallel": bool(info.get("parallel", True))}
            for name, info in regions.items()
        ] or [{"name": "root", "effect": PURE_EFFECT, "parallel": True}],
        "bindings": binding_rows,
        "dependency_topology": {
            "topological_order": order,
            "critical_binding_depth": depth,
            "independent_binding_pairs": independent_pairs,
            "inferred_edges": sum(len(v) for v in deps.values()),
            "synthetic_order_edges": 0,
        },
        "region_topology": {
            "inferred_edges": [{"from":a,"to":b} for a,b in sorted(region_edges)],
            "synthetic_order_edges": 0,
            "independent_region_pairs": independent_regions,
            "implicit_global_lock": False,
            "implicit_global_allocator_lock": False,
        },
        "ownership": {
            "model": "compile_time_unique_output_ownership",
            "binding_write_sets": {row["name"]:[row["name"]] for row in binding_rows},
            "binding_read_sets": {row["name"]:sorted(set(row["dependencies"]+row["input_reads"])) for row in binding_rows},
            "shared_mutable_writes": 0,
            "runtime_borrow_table": False,
            "implicit_locking": False,
            "alias_uncertainty_policy": "explicit_reject_not_serialization",
            "index_safety_policy": "native proof or compile rejection",
            "data_race_free_by_current_pure_lane": True,
        },
        "control_topology": {
            "select_nodes": sum(control_selects.values()),
            "source_loop_implies_serial_loop": False,
            "predicate_regions_are_dataflow": True,
        },
        "parallelism_contract": {
            "independent_means_no_serialization": True,
            "scalar_fallback_allowed": False,
            "central_scheduler_allowed": False,
            "global_queue_allowed": False,
            "global_barrier_allowed_without_dependency": False,
            "reductions": reduction_count,
            "reduction_closure": "fan_in_two_tree",
            "width_rule": "preserve independent domain width unless work is mathematically erased",
            "rank_n_erasure_is_math_elimination": bool(rank_n_erasures),
        },
        "serial_introduction": serial_report,
        "erasure": erasure,
    }
    blob = json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    plan["semantic_sha256"] = hashlib.sha256(blob).hexdigest()
    return plan
