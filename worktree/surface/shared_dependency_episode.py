#!/usr/bin/env python3
"""Compile-time shared-dependency episode pressure analysis.

This module is intentionally workload-name blind.  It inspects only the canonical
wheelchair.tensor/1 graph.  A terminal reduction is recursively expanded through
pure map bindings and its distinct (binding, structural-coordinate) loads are
counted.  The count is a conservative persistent-CSE pressure estimate for the
mature Rank-1 AVX-512 realizer.

No runtime metadata is emitted from this plan.  It only chooses between proved AOT
physical recipes before native compilation.
"""
from __future__ import annotations
import copy, hashlib, json
from typing import Any

LEGACY_PERSISTENT_SLOTS = 10
WIDE_PERSISTENT_SLOTS = 14


def _canon(x: Any) -> str:
    return json.dumps(x, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _subst_axes(x: Any, mapping: dict[str, Any]) -> Any:
    if isinstance(x, list):
        return [_subst_axes(v, mapping) for v in x]
    if not isinstance(x, dict):
        return x
    if set(x) == {"axis"} and x.get("axis") in mapping:
        return copy.deepcopy(mapping[x["axis"]])
    return {k: _subst_axes(v, mapping) for k, v in x.items()}


def analyze(data: dict[str, Any]) -> dict[str, Any]:
    bindings = {b.get("name"): b for b in data.get("bindings", []) if isinstance(b, dict) and b.get("name")}
    terminals = [b for b in bindings.values() if b.get("op") == "reduce"]
    distinct_loads: set[tuple[str, tuple[str, ...]]] = set()
    expanded: set[tuple[str, tuple[str, ...]]] = set()
    recursion_guard: set[tuple[str, tuple[str, ...]]] = set()
    max_depth = 0
    node_visits = 0

    def walk(node: Any, depth: int = 0) -> None:
        nonlocal max_depth, node_visits
        if depth > 64:
            return
        max_depth = max(max_depth, depth)
        if isinstance(node, list):
            for v in node:
                walk(v, depth + 1)
            return
        if not isinstance(node, dict):
            return
        node_visits += 1
        if "load" in node and isinstance(node.get("load"), str):
            name = node["load"]
            indices = node.get("indices", [])
            if not isinstance(indices, list):
                indices = []
            key = (name, tuple(_canon(i) for i in indices))
            distinct_loads.add(key)
            binding = bindings.get(name)
            if binding and binding.get("op") == "map":
                axes = binding.get("axes", [])
                if isinstance(axes, list) and len(axes) == len(indices) and key not in recursion_guard:
                    names = [a.get("name") for a in axes if isinstance(a, dict)]
                    if len(names) == len(indices) and all(isinstance(n, str) for n in names):
                        recursion_guard.add(key)
                        expanded.add(key)
                        mapping = dict(zip(names, indices))
                        walk(_subst_axes(binding.get("expr"), mapping), depth + 1)
                        recursion_guard.remove(key)
            for idx in indices:
                walk(idx, depth + 1)
            return
        for value in node.values():
            walk(value, depth + 1)

    for terminal in terminals:
        walk(terminal.get("expr"), 0)

    pressure = len(distinct_loads)
    rank_n = "rank_n_product" in data
    eligible = bool(terminals) and not rank_n and pressure > LEGACY_PERSISTENT_SLOTS
    fits_wide = pressure <= WIDE_PERSISTENT_SLOTS
    recipe = "legacy_1_2_4"
    reason = "pressure_within_legacy_capacity"
    if eligible and fits_wide:
        recipe = "shared_dependency_episode_wide_125"
        reason = "structural_persistent_pressure_exceeds_legacy_capacity"
    elif eligible:
        recipe = "legacy_vector_recompute_125"
        reason = "pressure_exceeds_wide_capacity_use_proved_vector_recompute_recipe"
    elif rank_n and pressure > LEGACY_PERSISTENT_SLOTS:
        recipe = "rank_n_proved_vector_recipe"
        reason = "rank_n_keeps_existing_proved_vector_physicalization"

    signature_payload = {
        "pressure": pressure,
        "terminal_reductions": len(terminals),
        "rank_n": rank_n,
        "recipe": recipe,
        "loads": sorted((name, list(coords)) for name, coords in distinct_loads),
    }
    signature = hashlib.sha256(_canon(signature_payload).encode("utf-8")).hexdigest()
    return {
        "format": "wheelchair.shared_dependency_episode/1",
        "workload_dispatch": False,
        "runtime_dispatch": False,
        "scalar_fallback": 0,
        "hidden_serial_fallback": 0,
        "resource_shortage_scalarization": 0,
        "legacy_persistent_slots": LEGACY_PERSISTENT_SLOTS,
        "wide_persistent_slots": WIDE_PERSISTENT_SLOTS,
        "distinct_structural_loads": pressure,
        "expanded_map_coordinates": len(expanded),
        "terminal_reductions": len(terminals),
        "node_visits": node_visits,
        "max_expansion_depth": max_depth,
        "rank_n": rank_n,
        "eligible": eligible,
        "fits_wide_recipe": fits_wide,
        "recipe": recipe,
        "reason": reason,
        "structural_signature_sha256": signature,
    }
