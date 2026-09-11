# Wheelchair 1.2.10 Release Notes

Wheelchair 1.2.10 is a general native physicalization upgrade built on the 1.2.9 recipient-blind resource correction.

The 1.2.9 semantic correction remains unchanged: completion never searches for work, observes peer demand, assigns a future resource consumer, or routes released capacity. `OWNED -> FREE` remains the only completion-side resource transition.

The main 1.2.10 change is AOT causal-region contraction. A dependency edge is fused only when the producer has exactly one successor and the consumer has exactly one predecessor. This rule is graph-structural, workload-name blind, timing blind, and applied to arbitrary general DAGs. It removes execution-context boundaries that cannot expose runnable parallelism while preserving every fork and join where causal width can change.

The native linker now concatenates the already emitted handwritten machine-code fragments of each proven causal region. Intermediate linker-owned `RET` bytes are removed; the final fragment keeps the region terminal `RET`. Runtime dependency tables are patched for the contracted region graph rather than the source-fragment graph.

The general blind-release runtime also replaces 1.2.9 per-context stack `mmap`/`munmap` churn with one invocation-scoped stack arena. Recursive finite contexts use disjoint stack slices. A single-region program allocates no child-stack arena.

The upgrade does not restore home slots, MPSC worker inboxes, work stealing, busy idle workers, global ready queues, a root scheduler, or runtime profitability selection. It does not alter mature Rank-N/native512/native256 technical peaks.

A same-machine runtime microbenchmark of the physical mechanisms before repository integration showed a median ~1.97x speedup across 27 chain/tree/layered points. This number is diagnostic evidence, not a universal language-performance claim; release acceptance is based on semantic/native regression gates, not benchmark selection.

## Final production closure

The final release migrates the human WH/WHEX surface and general causal physicalizer into handwritten x86-64 assembly. Mature generated assembly physicalizations are frozen as checked source authority. Production build, compilation, linking, and runtime execution no longer require Python.

The release ZIP excludes historical Python implementation/reference files and ships static native compiler binaries plus complete assembly production sources.
