# Wheelchair 1.2.0 Release Proof

Release identity: `1.2.0`.

The release adds WH structural recovery and does not modify the WHEX 1.1.0 expert surface, WHEX semantic planner, native compiler, ISA capability layer, or native runtimes. The WHEX implementation freeze is checked by `tests/WHEX_FROZEN_1_1_0_SHA256.txt`.

Primary new release gate: `test_wh_equivalence_120.sh`.

Required results:

```text
WHEX_1_1_0_SOURCE_FREEZE=PASS
WHEX_1_1_0_CANONICAL_FREEZE=PASS
WHEX_1_1_0_NATIVE_FREEZE=PASS
WH_ACCEPTS_WHEX_CANONICAL_CASES=26
WH_MATCHES_WHEX_EXPLICIT_REJECTIONS=1
WH_WHEX_CANONICAL_EQUIVALENCE=PASS
WH_STRUCTURAL_MULTILINGUAL_CANONICAL=PASS
WH_WHEX_NATIVE_BYTE_EQUIVALENCE=PASS
WH_FAKE_FOR_RUNTIME_LOOP_OBJECTS=0
WH_FAKE_IF_RUNTIME_DISPATCHERS=0
WH_SERIAL_INTRODUCTION_REPORT_ZERO=PASS
WH_PARALLELISM_PRESERVATION_CONTRACT=PASS
WH_RANK_N_PROVE_AND_ERASE=PASS
WH_DYNAMIC_WHILE_NO_SERIAL_FALLBACK=PASS
WH_STRUCTURAL_NO_GENERAL_FALLBACK=PASS
WH_WHEX_SURFACE_EQUIVALENCE_1_2_0=PASS
```

Existing native invariants were also rerun as component gates through 1.0.15 and 1.1.0, including Runtime Erasure, Serial-Spine Erasure, computation/communication elimination, operator algebra, true-parallel fused episodes, ISA capability generalization, vector boundary/interior partitioning, and WHEX high-level semantic erasure.

The release directory is source-only and contains no build directory, object files, executable artifacts, PDB files, or Python bytecode caches.
