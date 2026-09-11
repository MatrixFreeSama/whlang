# Wheelchair Current Release Proof

Current release: **1.2.9**.

The authoritative proof is `RELEASE_PROOF_1_2_9.md`.

The 1.2.9 proof establishes the source-level removal of the former general resource-routing implementation, the new recipient-blind dependency-only runtime state, finite causal node contexts, futex causal waiting, OS-controlled CPU selection inside the requested affinity envelope, and preservation boundaries for mature tensor/Rank-N physicalizations.

Development validation includes successful GNU x86-64 assembly/link of the replacement engine and 100-run native DAG stress at CPU widths 2 and 4. The full source-tree regression is intentionally not misreported as completed in the editing environment; `./test_129.sh` is the release-host gate and is also invoked by `./test_complete.sh`.

Historical versioned proof files remain evidence for the releases named in their filenames. They do not override `WHEELCHAIR_CHARTER_1_2_9.md`.
