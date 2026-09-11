# Wheelchair 1.2.12 Pure Assembly Release Proof

## Production closure

The production compiler/runtime remains handwritten/native x86-64 assembly.

```text
PRODUCTION_LANGUAGE_PYTHON=0
PRODUCTION_COMPILER_PYTHON=0
PRODUCTION_RUNTIME_PYTHON=0
PRODUCTION_BUILD_PYTHON_INVOCATIONS=0
```

The release tree contains no `.py` files.

The complete release gate was executed with a restricted PATH containing assembler/linker/ELF and basic Unix tools but no `python` or `python3`.

## Adaptive Execution Granularity proof

### Tensor

All four tensor runtime authorities contain:

- exactly one root-level `mmap` instruction site;
- exactly one root-level `munmap` instruction site;
- zero `mmap`/`munmap` sites inside recursive `run_tree`;
- explicit `g_stack_arena` and `g_stack_arena_size` state.

Representative q1/q2/q4 results remain bit-identical across the 1.2.12 runtime change for base, wide, derived, native512, and native256 validation cases.

### General DAG

`g_verify_causal_mesh` executes after region construction and before native materialization.

The release probes require:

```text
pure chain32: regions=1, edges=0
fork / left-chain / right-chain / join-tail: regions=4, edges=4
```

This demonstrates aggressive coarsening where no parallel width exists and preserved frontiers where independent branches exist.

## Recipient-blind release proof

Unchanged release constraints:

```text
GENERAL_PARALLEL_GLOBAL_READY_QUEUE=0
GENERAL_PARALLEL_ROOT_SCHEDULER=0
GENERAL_PARALLEL_RUNTIME_COST_SELECTOR=0
GENERAL_PARALLEL_SERIAL_FALLBACK=0
GENERAL_PARALLEL_RUNTIME_FIXED_HOME_OWNERSHIP=0
GENERAL_PARALLEL_PERSISTENT_IDLE_WORKER_SPIN=0
GENERAL_PARALLEL_POST_COMPLETION_WORK_SEARCH=0
GENERAL_PARALLEL_POST_COMPLETION_PEER_QUERY=0
GENERAL_PARALLEL_RESOURCE_RELEASE_DESTINATION=0
GENERAL_PARALLEL_RESOURCE_HANDOFF=0
GENERAL_PARALLEL_BLIND_RESOURCE_RELEASE=PASS
```

## Final gate

```text
ADAPTIVE_EXECUTION_GRANULARITY_1_2_12=PASS
LANGUAGE_PURE_ASSEMBLY=PASS
WHEELCHAIR_1_2_12_RELEASE=PASS
```
