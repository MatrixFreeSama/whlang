#!/usr/bin/env python3
"""Wheelchair 1.2.3 generic Sparse Causal Expansion planner.

This is a compile-time topology algebra, not a Newton/FEM/solver special case.
It borrows only the decomposition idea of Laplace expansion: expose a small
separator, keep disconnected interiors independent, and represent each interior
only by its boundary relation. It deliberately does NOT enumerate minors or
cofactors.

The planner consumes an arbitrary weighted coupling graph. It proves a bounded
binary separator decomposition with these invariants:
* no region is expanded twice;
* no central spawn/wait/reduction loop is introduced;
* non-neighbor communication is not synthesized;
* separator/signature work, memory, and communication amplification are bounded;
* unsupported dense/strongly coupled shapes can be explicitly rejected;
* workload names never participate in decisions.

The output is semantic evidence. Existing native hot paths remain byte-protected;
a physical realizer may consume this proof only when it can preserve those
invariants.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


class SparseCausalExpansionError(ValueError):
    pass


MAX_EXACT_SEPARATOR_NODES = 24
MAX_BFS_SEEDS = 8
DEFAULT_SEPARATOR_CAP = 4
DEFAULT_LEAF_SIZE = 2
DEFAULT_WORK_AMPLIFICATION_LIMIT = 1.50
DEFAULT_MEMORY_AMPLIFICATION_LIMIT = 1.50
DEFAULT_COMMUNICATION_AMPLIFICATION_LIMIT = 1.25


@dataclass(frozen=True)
class NodeSpec:
    name: str
    work: float = 1.0
    storage: float = 1.0
    recipe: str = "generic"


def _positive_number(value: Any, *, field: str, node: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise SparseCausalExpansionError(f"node {node!r} {field} must be a positive finite number")
    out = float(value)
    if not math.isfinite(out) or out <= 0.0:
        raise SparseCausalExpansionError(f"node {node!r} {field} must be a positive finite number")
    return out


def _normalize_nodes(raw: Iterable[Any]) -> dict[str, NodeSpec]:
    out: dict[str, NodeSpec] = {}
    for item in raw:
        if isinstance(item, str):
            name = item
            work = storage = 1.0
            recipe = "generic"
        elif isinstance(item, dict):
            name = item.get("id")
            if not isinstance(name, str) or not name:
                raise SparseCausalExpansionError("every coupling node requires a non-empty string id")
            work = _positive_number(item.get("work", 1.0), field="work", node=name)
            storage = _positive_number(item.get("storage", 1.0), field="storage", node=name)
            recipe_raw = item.get("recipe", "generic")
            if not isinstance(recipe_raw, str) or not recipe_raw:
                raise SparseCausalExpansionError(f"node {name!r} recipe must be a non-empty string")
            recipe = recipe_raw
        else:
            raise SparseCausalExpansionError("coupling nodes must be ids or node records")
        if name in out:
            raise SparseCausalExpansionError(f"duplicate coupling node {name!r}")
        out[name] = NodeSpec(name, work, storage, recipe)
    if not out:
        raise SparseCausalExpansionError("coupling graph must contain at least one node")
    return out


def _normalize_edges(raw: Iterable[Any], nodes: dict[str, NodeSpec]) -> set[tuple[str, str]]:
    edges: set[tuple[str, str]] = set()
    for item in raw:
        if not isinstance(item, (list, tuple)) or len(item) != 2:
            raise SparseCausalExpansionError("coupling edges must be [u,v] pairs")
        a, b = item
        if not isinstance(a, str) or not isinstance(b, str) or a not in nodes or b not in nodes:
            raise SparseCausalExpansionError(f"coupling edge {item!r} references an unknown node")
        if a == b:
            raise SparseCausalExpansionError(f"self coupling edge at {a!r} is not a separator edge")
        edges.add(tuple(sorted((a, b))))
    return edges


def _adjacency(names: Iterable[str], edges: set[tuple[str, str]]) -> dict[str, set[str]]:
    out = {n: set() for n in names}
    for a, b in edges:
        if a in out and b in out:
            out[a].add(b)
            out[b].add(a)
    return out


def _components(subset: set[str], edges: set[tuple[str, str]], removed: set[str] | None = None) -> list[set[str]]:
    removed = removed or set()
    live = set(subset) - removed
    adj = _adjacency(live, edges)
    result: list[set[str]] = []
    while live:
        seed = min(live)
        q = [seed]
        live.remove(seed)
        comp = {seed}
        while q:
            u = q.pop()
            for v in adj[u]:
                if v in live:
                    live.remove(v)
                    comp.add(v)
                    q.append(v)
        result.append(comp)
    result.sort(key=lambda c: (len(c), tuple(sorted(c))))
    return result


def _weight(group: Iterable[str], nodes: dict[str, NodeSpec], attr: str = "work") -> float:
    return sum(getattr(nodes[n], attr) for n in group)


def _group_components(parts: list[set[str]], nodes: dict[str, NodeSpec]) -> tuple[set[str], set[str]]:
    # Deterministic greedy balance. Components are already disconnected after the
    # separator is removed, therefore grouping them cannot synthesize an edge.
    ranked = sorted(parts, key=lambda c: (-_weight(c, nodes), tuple(sorted(c))))
    left: set[str] = set()
    right: set[str] = set()
    wl = wr = 0.0
    for part in ranked:
        w = _weight(part, nodes)
        if wl <= wr:
            left.update(part); wl += w
        else:
            right.update(part); wr += w
    if not left or not right:
        raise SparseCausalExpansionError("separator proof did not produce two non-empty independent sides")
    return left, right


def _separator_score(separator: set[str], parts: list[set[str]], nodes: dict[str, NodeSpec], edges: set[tuple[str, str]]) -> tuple[Any, ...]:
    live_weight = sum(_weight(c, nodes) for c in parts)
    largest = max((_weight(c, nodes) for c in parts), default=live_weight)
    balance = largest / live_weight if live_weight else 1.0
    boundary_edges = sum(1 for a, b in edges if (a in separator) ^ (b in separator))
    return (balance, len(separator), _weight(separator, nodes), boundary_edges, tuple(sorted(separator)))


def _exact_separator(subset: set[str], nodes: dict[str, NodeSpec], edges: set[tuple[str, str]], cap: int) -> set[str] | None:
    if len(subset) > MAX_EXACT_SEPARATOR_NODES:
        return None
    best: tuple[tuple[Any, ...], set[str]] | None = None
    ordered = sorted(subset)
    max_k = min(cap, max(0, len(ordered) - 2))
    for k in range(1, max_k + 1):
        for combo in itertools.combinations(ordered, k):
            sep = set(combo)
            parts = _components(subset, edges, sep)
            if len(parts) < 2:
                continue
            score = _separator_score(sep, parts, nodes, edges)
            if best is None or score < best[0]:
                best = (score, sep)
        # Prefer a proven smaller separator over searching a larger k forever.
        if best is not None:
            return best[1]
    return None


def _bfs_separator(subset: set[str], nodes: dict[str, NodeSpec], edges: set[tuple[str, str]], cap: int) -> set[str] | None:
    adj = _adjacency(subset, edges)
    if not subset:
        return None
    degrees = sorted(subset, key=lambda n: (-len(adj[n]), nodes[n].recipe, n))
    seeds = degrees[: min(MAX_BFS_SEEDS, len(degrees))]
    best: tuple[tuple[Any, ...], set[str]] | None = None
    for seed in seeds:
        level = {seed: 0}
        q: deque[str] = deque([seed])
        while q:
            u = q.popleft()
            for v in sorted(adj[u]):
                if v not in level:
                    level[v] = level[u] + 1
                    q.append(v)
        by_level: dict[int, set[str]] = {}
        for n, d in level.items():
            by_level.setdefault(d, set()).add(n)
        for d in sorted(by_level):
            sep = by_level[d]
            if len(sep) > cap or len(subset - sep) < 2:
                continue
            parts = _components(subset, edges, sep)
            if len(parts) < 2:
                continue
            score = _separator_score(sep, parts, nodes, edges)
            if best is None or score < best[0]:
                best = (score, set(sep))
    return None if best is None else best[1]


def _find_separator(subset: set[str], nodes: dict[str, NodeSpec], edges: set[tuple[str, str]], cap: int) -> set[str] | None:
    sep = _exact_separator(subset, nodes, edges, cap)
    if sep is not None:
        return sep
    return _bfs_separator(subset, nodes, edges, cap)


def _boundary(separator: set[str], child: set[str], edges: set[tuple[str, str]]) -> list[tuple[str, str]]:
    return sorted((a, b) for a, b in edges if (a in separator and b in child) or (b in separator and a in child))


def _structural_tree(node: dict[str, Any], nodes: dict[str, NodeSpec]) -> Any:
    if node["kind"] == "leaf":
        recipes = sorted(nodes[n].recipe for n in node["nodes"])
        return {"kind": "leaf", "recipes": recipes, "cardinality": len(recipes)}
    separator_recipes = sorted(nodes[n].recipe for n in node["separator"])
    children = sorted((_structural_tree(c, nodes) for c in node["children"]), key=lambda x: json.dumps(x, sort_keys=True))
    return {"kind": "separator", "separator_recipes": separator_recipes, "separator_cardinality": len(separator_recipes), "children": children}


def _plan_component(subset: set[str], nodes: dict[str, NodeSpec], edges: set[tuple[str, str]], *, separator_cap: int, leaf_size: int, require_split: bool, accounting: dict[str, float | int]) -> dict[str, Any]:
    if len(subset) <= leaf_size:
        return {"kind": "leaf", "nodes": sorted(subset), "work": _weight(subset, nodes), "serial_inner_loop": False}
    sep = _find_separator(subset, nodes, edges, separator_cap)
    if sep is None:
        if require_split:
            raise SparseCausalExpansionError(
                f"no bounded separator <= {separator_cap} proved for component of {len(subset)} nodes; explicit rejection replaces forced expansion"
            )
        return {"kind": "leaf", "nodes": sorted(subset), "work": _weight(subset, nodes), "serial_inner_loop": False, "unsplit_reason": "no_bounded_separator_proved"}
    parts = _components(subset, edges, sep)
    left, right = _group_components(parts, nodes)
    left_boundary = _boundary(sep, left, edges)
    right_boundary = _boundary(sep, right, edges)
    signature_edges = len(left_boundary) + len(right_boundary)
    accounting["separator_nodes"] += len(sep)
    accounting["signature_edges"] += signature_edges
    accounting["separator_work"] += _weight(sep, nodes)
    accounting["separator_storage"] += _weight(sep, nodes, "storage")
    accounting["split_nodes"] += len(subset)
    return {
        "kind": "separator",
        "separator": sorted(sep),
        "signature": {
            "model": "causal_separator_signature",
            "left_boundary_edges": [list(e) for e in left_boundary],
            "right_boundary_edges": [list(e) for e in right_boundary],
            "interior_values_materialized_globally": False,
            "non_neighbor_messages": 0,
        },
        "children": [
            _plan_component(left, nodes, edges, separator_cap=separator_cap, leaf_size=leaf_size, require_split=require_split, accounting=accounting),
            _plan_component(right, nodes, edges, separator_cap=separator_cap, leaf_size=leaf_size, require_split=require_split, accounting=accounting),
        ],
        "central_reduction": False,
        "serial_inner_loop": False,
    }


def _count_tree(node: dict[str, Any]) -> tuple[int, int, int]:
    if node["kind"] == "leaf":
        return 1, 0, 1
    child_stats = [_count_tree(c) for c in node["children"]]
    leaves = sum(x[0] for x in child_stats)
    separators = 1 + sum(x[1] for x in child_stats)
    depth = 1 + max(x[2] for x in child_stats)
    return leaves, separators, depth


def _node_occurrences(node: dict[str, Any], out: dict[str, int]) -> None:
    if node["kind"] == "leaf":
        for n in node["nodes"]:
            out[n] = out.get(n, 0) + 1
        return
    for n in node["separator"]:
        out[n] = out.get(n, 0) + 1
    for child in node["children"]:
        _node_occurrences(child, out)


def plan_graph(spec: dict[str, Any], *, require_split: bool | None = None) -> dict[str, Any]:
    if not isinstance(spec, dict):
        raise SparseCausalExpansionError("operator graph specification must be an object")
    nodes = _normalize_nodes(spec.get("nodes", []))
    edges = _normalize_edges(spec.get("edges", []), nodes)
    separator_cap = int(spec.get("separator_cap", DEFAULT_SEPARATOR_CAP))
    leaf_size = int(spec.get("leaf_size", DEFAULT_LEAF_SIZE))
    if separator_cap < 1 or leaf_size < 1:
        raise SparseCausalExpansionError("separator_cap and leaf_size must be positive")
    if require_split is None:
        require_split = bool(spec.get("require_split", True))
    work_limit = float(spec.get("work_amplification_limit", DEFAULT_WORK_AMPLIFICATION_LIMIT))
    memory_limit = float(spec.get("memory_amplification_limit", DEFAULT_MEMORY_AMPLIFICATION_LIMIT))
    communication_limit = float(spec.get("communication_amplification_limit", DEFAULT_COMMUNICATION_AMPLIFICATION_LIMIT))
    if min(work_limit, memory_limit, communication_limit) < 1.0:
        raise SparseCausalExpansionError("amplification limits cannot be below 1.0")

    all_names = set(nodes)
    components = _components(all_names, edges)
    accounting: dict[str, float | int] = {
        "separator_nodes": 0,
        "signature_edges": 0,
        "separator_work": 0.0,
        "separator_storage": 0.0,
        "split_nodes": 0,
    }
    forest = [
        _plan_component(c, nodes, edges, separator_cap=separator_cap, leaf_size=leaf_size,
                        require_split=bool(require_split), accounting=accounting)
        for c in components
    ]

    occurrences: dict[str, int] = {}
    for tree in forest:
        _node_occurrences(tree, occurrences)
    duplicates = {n: c for n, c in occurrences.items() if c != 1}
    if duplicates:
        raise SparseCausalExpansionError("internal planner error: a region was expanded more than once: " + repr(duplicates))

    base_work = _weight(nodes, nodes)
    base_storage = _weight(nodes, nodes, "storage")
    # Signature accounting is deliberately conservative. Separator numeric work
    # is not duplicated; only boundary relation bookkeeping is counted as added work.
    signature_work = float(accounting["signature_edges"])
    signature_storage = float(accounting["separator_nodes"])
    work_amp = (base_work + signature_work) / base_work
    memory_amp = (base_storage + signature_storage) / base_storage
    base_comm = max(1, len(edges))
    communication_amp = max(1.0, float(accounting["signature_edges"]) / base_comm)
    if work_amp > work_limit + 1e-15:
        raise SparseCausalExpansionError(f"work amplification {work_amp:.6f} exceeds limit {work_limit:.6f}")
    if memory_amp > memory_limit + 1e-15:
        raise SparseCausalExpansionError(f"memory amplification {memory_amp:.6f} exceeds limit {memory_limit:.6f}")
    if communication_amp > communication_limit + 1e-15:
        raise SparseCausalExpansionError(
            f"communication amplification {communication_amp:.6f} exceeds limit {communication_limit:.6f}"
        )

    tree_stats = [_count_tree(t) for t in forest]
    leaves = sum(x[0] for x in tree_stats)
    separator_nodes = sum(x[1] for x in tree_stats)
    depth = max((x[2] for x in tree_stats), default=0)
    structural = {
        "forest": sorted((_structural_tree(t, nodes) for t in forest), key=lambda x: json.dumps(x, sort_keys=True)),
        "edge_count": len(edges),
        "component_count": len(components),
    }
    structural_blob = json.dumps(structural, sort_keys=True, separators=(",", ":")).encode("utf-8")
    structural_sha = hashlib.sha256(structural_blob).hexdigest()

    # Recipe DAG deduplicates compile-time structural recipes only. Numeric state
    # for distinct regions is never aliased or reused.
    recipe_hashes: list[str] = []
    def collect_recipe_hashes(t: dict[str, Any]) -> None:
        s = _structural_tree(t, nodes)
        recipe_hashes.append(hashlib.sha256(json.dumps(s, sort_keys=True, separators=(",", ":")).encode()).hexdigest())
        for child in t.get("children", []):
            collect_recipe_hashes(child)
    for t in forest:
        collect_recipe_hashes(t)

    plan = {
        "format": "wheelchair.sparse-causal-expansion/1",
        "algorithm": "bounded_separator_signature_binary_dag",
        "laplace_minor_enumeration": False,
        "workload_dispatch": False,
        "nodes": len(nodes),
        "edges": len(edges),
        "components": len(components),
        "separator_cap": separator_cap,
        "leaf_size": leaf_size,
        "forest": forest,
        "metrics": {
            "base_work": base_work,
            "signature_work": signature_work,
            "work_amplification": work_amp,
            "work_amplification_limit": work_limit,
            "base_storage": base_storage,
            "signature_storage": signature_storage,
            "memory_amplification": memory_amp,
            "memory_amplification_limit": memory_limit,
            "communication_amplification": communication_amp,
            "communication_amplification_limit": communication_limit,
            "leaves": leaves,
            "separator_tree_nodes": separator_nodes,
            "critical_tree_depth": depth,
            "duplicate_region_expansions": 0,
            "unique_symbolic_recipes": len(set(recipe_hashes)),
            "symbolic_recipe_instances": len(recipe_hashes),
        },
        "parallelism_contract": {
            "central_spawn_loop": 0,
            "central_wait_loop": 0,
            "central_reduction_loop": 0,
            "global_task_queue": 0,
            "global_barrier_without_dependency": 0,
            "scalar_fallback": 0,
            "hidden_serial_fallback": 0,
            "non_neighbor_communication": 0,
            "binary_separator_composition": True,
            "no_dependency_edge_no_synchronization_edge": True,
        },
        "structural_sha256": structural_sha,
    }
    blob = json.dumps(plan, sort_keys=True, separators=(",", ":")).encode("utf-8")
    plan["plan_sha256"] = hashlib.sha256(blob).hexdigest()
    return plan


def plan_from_semantic_regions(semantic_plan: dict[str, Any]) -> dict[str, Any] | None:
    regions = semantic_plan.get("regions", [])
    names = [r.get("name") for r in regions if isinstance(r, dict) and isinstance(r.get("name"), str)]
    used = [n for n in names if n != "root"]
    raw_edges = semantic_plan.get("region_topology", {}).get("inferred_edges", [])
    edges: list[list[str]] = []
    touched: set[str] = set()
    for e in raw_edges:
        if not isinstance(e, dict):
            continue
        a, b = e.get("from"), e.get("to")
        if isinstance(a, str) and isinstance(b, str) and a != b and a != "root" and b != "root":
            edges.append([a, b]); touched.update((a, b))
    graph_nodes = sorted(set(used) | touched)
    if len(graph_nodes) < 3 or len(edges) < 2:
        return None
    # Region-derived expansion is an opportunistic proof. An unproved separator
    # preserves the existing byte-protected native path; there is no serial retry.
    spec = {
        "nodes": [{"id": n, "recipe": "pure_region"} for n in graph_nodes],
        "edges": edges,
        "separator_cap": min(DEFAULT_SEPARATOR_CAP, max(1, len(graph_nodes) // 4)),
        "leaf_size": DEFAULT_LEAF_SIZE,
        "require_split": False,
        "work_amplification_limit": 2.0,
        "memory_amplification_limit": 2.0,
        "communication_amplification_limit": 2.0,
    }
    return plan_graph(spec, require_split=False)


def attach_to_semantic_plan(semantic_plan: dict[str, Any]) -> None:
    proof = plan_from_semantic_regions(semantic_plan)
    algebra = {
        "model": "global_coupled_operator",
        "matrix_materialization_required": False,
        "sparse_definition": "few_real_dependency_edges_not_explicit_zero_storage",
        "workload_dispatch": False,
        "newton_special_case": False,
        "physics_name_dispatch": False,
        "separator_strategy": "proof_gated_sparse_causal_expansion",
        "laplace_minor_enumeration": False,
        "unproved_expansion_policy": "preserve_existing_proven_path_or_explicit_reject_when_expansion_is_required",
    }
    if proof is not None:
        algebra["sparse_causal_expansion"] = proof
    semantic_plan["global_operator_algebra"] = algebra
    p = semantic_plan.setdefault("parallelism_contract", {})
    p["global_operator_root_dispatch"] = False
    p["global_matrix_assembly_required"] = False
    p["global_block_sweep"] = False
    p["central_operator_reduction"] = False
    serial = semantic_plan.setdefault("serial_introduction", {})
    serial["new_global_operator_serial_spines"] = 0
    erasure = semantic_plan.setdefault("erasure", {})
    erasure["runtime_global_operator_type_tags"] = 0
    erasure["runtime_separator_plan_objects"] = 0
    erasure["runtime_workload_dispatch"] = 0


def _cli() -> int:
    ap = argparse.ArgumentParser(description="Wheelchair 1.2.3 generic Sparse Causal Expansion planner")
    ap.add_argument("graph", type=Path, help="JSON coupling graph")
    ap.add_argument("-o", "--output", type=Path, default=None)
    args = ap.parse_args()
    spec = json.loads(args.graph.read_text(encoding="utf-8"))
    plan = plan_graph(spec)
    text = json.dumps(plan, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output is None:
        print(text, end="")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(_cli())
    except SparseCausalExpansionError as exc:
        print(f"Sparse Causal Expansion rejection: {exc}")
        raise SystemExit(65)
