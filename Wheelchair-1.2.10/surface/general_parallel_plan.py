#!/usr/bin/env python3
"""Wheelchair 1.2.9 general true-parallel causality plan.

The planner derives only mathematical/data causality. It never assigns a future
resource owner. Runtime resource release is recipient-blind: completion publishes
true dependency transitions and ends the current ownership episode. CPU placement
of runnable node contexts is left to the OS inside the requested AOT affinity
envelope; in-core silicon allocation remains hardware authority.
"""
from __future__ import annotations

import hashlib
import json
from collections import deque
from typing import Any, Iterable

FORMAT = "wheelchair.general_parallel/2"
MAX_NODES = 96
MAX_EDGES = 1024
VALID_WIDTHS = (1, 2, 4)

class GeneralParallelError(ValueError):
    pass


def _canon(x: Any) -> str:
    return json.dumps(x, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


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
        for key in ("source", "value", "target", "base"):
            value = item.get(key)
            if isinstance(value, str) and value in names:
                out.add(value)
    return out


def _literal_work(binding: dict[str, Any]) -> int:
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


def causal_geometry(node_ids: list[str], edges: list[tuple[int, int]], width: int,
                    *, work: list[int] | None = None) -> dict[str, Any]:
    n = len(node_ids)
    if n == 0:
        raise GeneralParallelError("causal geometry requires at least one node")
    if n > MAX_NODES:
        raise GeneralParallelError(f"node count exceeds native blind-release cap {MAX_NODES}")
    if len(edges) > MAX_EDGES:
        raise GeneralParallelError(f"edge count exceeds native blind-release cap {MAX_EDGES}")
    if width not in VALID_WIDTHS:
        raise GeneralParallelError(f"requested CPU width must be one of {VALID_WIDTHS}")

    pred = [[] for _ in range(n)]
    succ = [[] for _ in range(n)]
    indeg = [0] * n
    seen: set[tuple[int, int]] = set()
    for u, v in edges:
        if not (0 <= u < n and 0 <= v < n):
            raise GeneralParallelError("causal edge references an unknown node")
        if u == v:
            raise GeneralParallelError("self dependency is a cycle")
        if (u, v) in seen:
            raise GeneralParallelError("duplicate causal edge")
        seen.add((u, v)); pred[v].append(u); succ[u].append(v); indeg[v] += 1

    q = deque(i for i, d in enumerate(indeg) if d == 0)
    rem = indeg[:]
    level = [0] * n
    order: list[int] = []
    while q:
        u = q.popleft(); order.append(u)
        for v in succ[u]:
            level[v] = max(level[v], level[u] + 1); rem[v] -= 1
            if rem[v] == 0: q.append(v)
    if len(order) != n:
        raise GeneralParallelError("causal relation contains a cycle")

    widths: dict[int, int] = {}
    for lev in level: widths[lev] = widths.get(lev, 0) + 1
    sources = [i for i, d in enumerate(indeg) if d == 0]
    payload = {"nodes": node_ids, "edges": [[u, v] for u, v in edges], "work": list(work or [1] * n), "width": width}
    return {
        "format": "wheelchair.blind_release_causal/1",
        "requested_cpu_width": width,
        "materialized_node_contexts": n,
        "node_count": n,
        "edge_count": len(edges),
        "source_count": len(sources),
        "sources": [node_ids[i] for i in sources],
        "topological_depth": 1 + max(level, default=0),
        "max_ready_width": max(widths.values(), default=0),
        "readiness_rule": "declared_dependency_zero_transition",
        "communication_rule": "true_dependency_neighbors_only",
        "release_rule": "owned_to_free_no_recipient",
        "cpu_dispatch_authority": "os_scheduler_within_inherited_affinity_envelope",
        "silicon_dispatch_authority": "cpu_microarchitecture",
        "resource_consumer_visibility": "none",
        "dependency_destination_visibility": "true_causal_neighbor_only",
        "global_ready_queue": 0,
        "global_ready_scan": 0,
        "root_scheduler": 0,
        "runtime_cost_selector": False,
        "serial_fallback": 0,
        "work_stealing": 0,
        "runtime_fixed_home_ownership": 0,
        "persistent_idle_worker_spin": 0,
        "post_completion_work_search": 0,
        "post_completion_peer_query": 0,
        "resource_release_destination": 0,
        "resource_handoff": 0,
        "peer_load_query": 0,
        "structural_signature_sha256": hashlib.sha256(_canon(payload).encode()).hexdigest(),
    }


def plan(data: dict[str, Any], slots: int, *, semantic: dict[str, Any] | None = None,
         physical_lane: str = "general") -> dict[str, Any]:
    if not isinstance(data, dict): raise GeneralParallelError("canonical program must be an object")
    if slots not in VALID_WIDTHS: raise GeneralParallelError(f"requested CPU width must be one of {VALID_WIDTHS}")
    bindings = [b for b in data.get("bindings", []) if isinstance(b, dict) and isinstance(b.get("name"), str)]
    names = [str(b["name"]) for b in bindings]
    if len(set(names)) != len(names): raise GeneralParallelError("duplicate binding names violate unique causal identity")
    if not bindings:
        return {"format":FORMAT,"node_count":0,"edge_count":0,"requested_cpu_width":slots,"materialized_node_contexts":0,
                "source_order_edges":0,"synthetic_order_edges":0,"global_ready_queue":0,"global_ready_scan":0,"root_scheduler":0,
                "runtime_cost_selector":False,"serial_fallback":0,"resource_release_destination":0,"runtime_fixed_home_ownership":0,
                "parallelism":"no_executable_binding_nodes","physical_lane":physical_lane}

    name_set = set(names); deps: dict[str, set[str]] = {}; rows: list[dict[str, Any]] = []; recurrence_nodes = 0
    for binding in bindings:
        name = str(binding["name"]); references = _refs(binding, name_set); references.discard(name); deps[name] = references
        op = str(binding.get("op", "unknown")); recurrence = op in {"iterate", "cascade"}; recurrence_nodes += int(recurrence)
        rows.append({"name":name,"op":op,"dependencies":sorted(references),"source_position_is_dependency":False,
                     "causal_enclave":"true_recurrence" if recurrence else "none","declared_work":_literal_work(binding)})

    index = {name:i for i,name in enumerate(names)}
    edges = sorted((index[src],index[dst]) for dst,sources in deps.items() for src in sources)
    physical = causal_geometry(names,edges,slots,work=[r["declared_work"] for r in rows])
    independent_pairs: list[list[str]] = []
    reach = {name:set(deps[name]) for name in names}; changed = True
    while changed:
        changed = False
        for name in names:
            add: set[str] = set()
            for source in list(reach[name]): add.update(reach.get(source, ()))
            if not add.issubset(reach[name]): reach[name].update(add); changed = True
    for i,a in enumerate(names):
        for b in names[i+1:]:
            if a not in reach[b] and b not in reach[a]: independent_pairs.append([a,b])

    payload = {"bindings":rows,"physical_signature":physical["structural_signature_sha256"],"physical_lane":physical_lane}
    result = {
        "format":FORMAT,"binding_nodes":rows,"node_count":len(rows),"edge_count":len(edges),"recurrence_enclaves":recurrence_nodes,
        "independent_binding_pairs":independent_pairs,"source_order_edges":0,"synthetic_order_edges":0,"global_ready_queue":0,
        "global_ready_scan":0,"root_scheduler":0,"runtime_cost_selector":False,"serial_fallback":0,"global_phase_barrier":0,
        "work_stealing":0,"runtime_fixed_home_ownership":0,"persistent_idle_worker_spin":0,"post_completion_work_search":0,
        "post_completion_peer_query":0,"resource_release_destination":0,"resource_handoff":0,
        "readiness_rule":"declared_dependency_zero_transition","ordering_rule":"true_data_causality_only",
        "release_rule":"owned_to_free_no_recipient","recurrence_rule":"true_recurrence_is_a_causal_enclave_not_a_global_spine",
        "physical_lane":physical_lane,
        "specialization_contract":"mature_native_peak_may_replace_general_fabric_only_if_semantically_equivalent_and_nonregressive",
        "cpu_specialization":"AOT_only_never_runtime_profitability_selector","blind_release_causal":physical,
        "semantic_source":semantic.get("semantic_format") if isinstance(semantic,dict) else None,
    }
    result["semantic_sha256"] = hashlib.sha256(_canon(payload).encode("utf-8")).hexdigest()
    return result
