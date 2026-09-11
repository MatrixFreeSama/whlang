# Wheelchair 1.2.12 Execution Granularity Validation

## Structural result

The 1.2.12 upgrade removes recursive tensor child-stack mapping and adds an explicit causal-mesh proof gate for general DAG materialization.

### Tensor stack lifetime

1.2.11 recursively maps child stacks at internal executor-tree nodes.

1.2.12:

```text
q1: no arena
q2: one 16 KiB arena mapping
q4: one 48 KiB arena mapping
```

The arena is partitioned into non-overlapping 16 KiB slices. The root releases it once.

A parent-lineage ptrace diagnostic on q4 observed the visible runtime stack-mapping calls drop from 2 to 1 while clone/wait structure remained unchanged. Descendant processes were not followed by that diagnostic, so this number is recorded only as supporting evidence; the source-level release gate is authoritative and proves recursive mapping sites are zero.

### Causal mesh

The release DAG probe:

```text
root
├─ left1 -> left2
└─ right1 -> right2
       \   /
        join -> tail -> output
```

materializes as four regions and four cross-region edges. The two branch-local chains coarsen; the fork and join remain physical frontiers.

A 32-node pure chain materializes as one region.

## Tensor chunk-size experiment

Candidate numerical leaf sizes from 64 KiB to 4 MiB were tested during development. Results changed with N and q and did not establish a monotonic or universal optimum.

Therefore 1.2.12 keeps the protected 65,536-element leaf. This is intentional: adaptive execution granularity must come from structure, not from baking one runner's timing optimum into the language.

## Performance interpretation

The stack-arena change removes lifecycle syscalls; it is expected to matter most when kernels are light enough for launch/lifetime overhead to be visible. Heavy FSI remains dominated by arithmetic/vector/memory behavior. No language-wide speedup is claimed from this release alone.
