#!/usr/bin/env python3
"""Generic compile-time native resource-profile analysis.

The analyzer is intentionally blind to workload names, source paths and benchmark
families. It inspects only the canonical tensor graph and returns physical resource
requirements. The result may select a build-time native capability class, never a
runtime implementation, workload recipe, or profitability fallback.
"""
from __future__ import annotations
import copy, hashlib, json
from typing import Any

BASE_PERSISTENT_SLOTS = 10
EXPANDED_PERSISTENT_SLOTS = 14


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
                        walk(_subst_axes(binding.get("expr"), dict(zip(names, indices))), depth + 1)
                        recursion_guard.remove(key)
            for idx in indices:
                walk(idx, depth + 1)
            return
        for value in node.values():
            walk(value, depth + 1)

    for terminal in terminals:
        walk(terminal.get("expr"), 0)

    pressure = len(distinct_loads)
    derived_cartesian = "rank_n_product" in data
    expanded_registers = bool(terminals) and not derived_cartesian and (
        BASE_PERSISTENT_SLOTS < pressure <= EXPANDED_PERSISTENT_SLOTS
    )
    recompute = bool(terminals) and not derived_cartesian and pressure > EXPANDED_PERSISTENT_SLOTS

    if derived_cartesian:
        backend_class = "derived"
        lowering_policy = "proved_cartesian_native"
    elif expanded_registers:
        backend_class = "wide"
        lowering_policy = "expanded_persistent_registers"
    elif recompute:
        backend_class = "base"
        lowering_policy = "proved_vector_recompute"
    else:
        backend_class = "base"
        lowering_policy = "base_persistent_registers"

    signature_payload = {
        "pressure": pressure,
        "terminal_reductions": len(terminals),
        "derived_cartesian": derived_cartesian,
        "backend_class": backend_class,
        "lowering_policy": lowering_policy,
        "loads": sorted((name, list(coords)) for name, coords in distinct_loads),
    }
    return {
        "format": "wheelchair.native_resource_profile/1",
        "workload_dispatch": False,
        "source_path_dispatch": False,
        "benchmark_dispatch": False,
        "runtime_dispatch": False,
        "runtime_cost_selector": False,
        "scalar_fallback": 0,
        "hidden_serial_fallback": 0,
        "resource_shortage_scalarization": 0,
        "persistent_slots_base": BASE_PERSISTENT_SLOTS,
        "persistent_slots_expanded": EXPANDED_PERSISTENT_SLOTS,
        "distinct_structural_loads": pressure,
        "expanded_map_coordinates": len(expanded),
        "terminal_reductions": len(terminals),
        "node_visits": node_visits,
        "max_expansion_depth": max_depth,
        "derived_cartesian": derived_cartesian,
        "expanded_registers": expanded_registers,
        "vector_recompute": recompute,
        "backend_class": backend_class,
        "lowering_policy": lowering_policy,
        "structural_signature_sha256": hashlib.sha256(_canon(signature_payload).encode("utf-8")).hexdigest(),
    }
