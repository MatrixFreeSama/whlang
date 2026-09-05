#!/usr/bin/env python3
"""Wheelchair 1.2.6 General Parallel Fabric planning.

Every top-level executable binding becomes a causal node. Ordering is derived
only from actual references, never source position. Independent nodes remain
independent. True recurrences stay inside one causal enclave instead of
fabricating parallelism or a hidden scheduler.

This module is compile-time only. Physical execution uses the schedulerless
causal fabric or a narrower proven native specialization of the same semantics.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Iterable

import schedulerless_causal_plan as sc

FORMAT = "wheelchair.general_parallel/1"

class GeneralParallelError(ValueError):
    pass


def _walk(node: Any) -> Iterable[dict[str, Any]]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)


def _refs(node: Any, names: set[str]) -> set[str]:
    out: set[str] = set()
    for item in _walk(node):
        if set(item) == {"var"} and isinstance(item.get("var"), str) and item["var"] in names:
            out.add(item["var"])
        load = item.get("load")
        if isinstance(load, str) and load in names:
            out.add(load)
        # General records/dictionaries may carry symbolic references under
        # explicit source/value fields rather than the tensor load spelling.
        for key in ("source", "value", "target", "base"):
            value = item.get(key)
            if isinstance(value, str) and value in names:
                out.add(value)
    return out


def _literal_work(binding: dict[str, Any]) -> int:
    """Return only structural, source-declared work. Never benchmark-select."""
    op = binding.get("op")
    if op == "iterate":
        lim = binding.get("max_iterations")
        if isinstance(lim, dict) and isinstance(lim.get("literal"), int) and not isinstance(lim.get("literal"), bool):
            return max(1, min(int(lim["literal"]), 0xffffffff))
    axes = binding.get("axes")
    if isinstance(axes, list):
        product = 1
        known = bool(axes)
        for axis in axes:
            extent = axis.get("extent") if isinstance(axis, dict) else None
            if not isinstance(extent, dict) or not isinstance(extent.get("literal"), int) or isinstance(extent.get("literal"), bool):
                known = False
                break
            product *= max(1, int(extent["literal"]))
            if product >= 0xffffffff:
                return 0xffffffff
        if known:
            return max(1, product)
    return 1


def plan(data: dict[str, Any], slots: int, *, semantic: dict[str, Any] | None = None,
         physical_lane: str = "general") -> dict[str, Any]:
    if not isinstance(data, dict):
        raise GeneralParallelError("canonical program must be an object")
    bindings = [b for b in data.get("bindings", []) if isinstance(b, dict) and isinstance(b.get("name"), str)]
    names = [str(b["name"]) for b in bindings]
    if len(set(names)) != len(names):
        raise GeneralParallelError("duplicate binding names violate unique causal ownership")

    if not bindings:
        return {
            "format": FORMAT,
            "node_count": 0,
            "edge_count": 0,
            "requested_slots": slots,
            "materialized_slots": 0,
            "source_order_edges": 0,
            "synthetic_order_edges": 0,
            "global_ready_queue": 0,
            "global_ready_scan": 0,
            "root_scheduler": 0,
            "runtime_cost_selector": False,
            "serial_fallback": 0,
            "parallelism": "no_executable_binding_nodes",
            "physical_lane": physical_lane,
        }

    name_set = set(names)
    deps: dict[str, set[str]] = {}
    rows: list[dict[str, Any]] = []
    recurrence_nodes = 0
    for binding in bindings:
        name = str(binding["name"])
        references = _refs(binding, name_set)
        references.discard(name)
        deps[name] = references
        op = str(binding.get("op", "unknown"))
        recurrence = op in {"iterate", "cascade"}
        recurrence_nodes += int(recurrence)
        rows.append({
            "name": name,
            "op": op,
            "dependencies": sorted(references),
            "source_position_is_dependency": False,
            "causal_enclave": "true_recurrence" if recurrence else "none",
            "declared_work": _literal_work(binding),
        })

    index = {name: i for i, name in enumerate(names)}
    edges = sorted((index[src], index[dst]) for dst, sources in deps.items() for src in sources)
    spec = {
        "format": sc.FORMAT,
        "nodes": [{"id": name, "work": rows[i]["declared_work"]} for i, name in enumerate(names)],
        "edges": [[names[u], names[v]] for u, v in edges],
        "slots": slots,
    }
    physical = sc.plan(spec, slots)

    independent_pairs: list[list[str]] = []
    # Reachability only for evidence. n<=64 in the current native fabric.
    reach = {name: set(deps[name]) for name in names}
    changed = True
    while changed:
        changed = False
        for name in names:
            add: set[str] = set()
            for source in list(reach[name]):
                add.update(reach.get(source, ()))
            if not add.issubset(reach[name]):
                reach[name].update(add)
                changed = True
    for i, a in enumerate(names):
        for b in names[i+1:]:
            if a not in reach[b] and b not in reach[a]:
                independent_pairs.append([a, b])

    payload = {
        "bindings": rows,
        "physical_signature": physical["structural_signature_sha256"],
        "physical_lane": physical_lane,
    }
    result = {
        "format": FORMAT,
        "binding_nodes": rows,
        "node_count": len(rows),
        "edge_count": len(edges),
        "recurrence_enclaves": recurrence_nodes,
        "independent_binding_pairs": independent_pairs,
        "source_order_edges": 0,
        "synthetic_order_edges": 0,
        "global_ready_queue": 0,
        "global_ready_scan": 0,
        "root_scheduler": 0,
        "runtime_cost_selector": False,
        "serial_fallback": 0,
        "global_phase_barrier": 0,
        "work_stealing": 0,
        "readiness_rule": "declared_dependency_zero_transition",
        "ordering_rule": "true_data_causality_only",
        "recurrence_rule": "true_recurrence_is_a_causal_enclave_not_a_global_spine",
        "physical_lane": physical_lane,
        "specialization_contract": "narrower_native_peak_may_replace_fabric_only_if_semantically_equivalent_and_nonregressive",
        "cpu_specialization": "AOT_only_never_runtime_profitability_selector",
        "schedulerless_causal": physical,
        "semantic_source": semantic.get("semantic_format") if isinstance(semantic, dict) else None,
    }
    result["semantic_sha256"] = hashlib.sha256(
        json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return result
