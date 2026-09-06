# Wheelchair 1.0.9 Release Proof

## Scope

Version 1.0.9 preserves the 1.0.8 general-language correctness and General Topology Recovery contracts while maturing the native topology path through Runtime Erasure and Serial-Spine Erasure.

## Compiler identity

The clean-built `topologyc` used for the release candidate is byte-reproducible across consecutive clean builds:

```text
topologyc-1.0.9 SHA-256:
3e1d830731ef3a1b56ffd1f169a846a35fd5f4e80f79ba232c0879942ec5845a
CLEAN_BUILD_HASH_IDENTICAL=PASS
```

`readelf` reports no dynamic section or interpreter for `topologyc`. The native build gate finds no C, Clang, LLVM, Rust, Cargo, or Python compiler backend invocation in `build.sh`; the native topology compiler is assembled from Wheelchair's own assembly sources.

## B. Runtime Erasure proof

Required 1.0.9 markers:

```text
RUNTIME_ERASURE=PASS
FIXED_EVALUATOR_CAPACITY=0
FIXED_CHILD_STACK_BSS=0
GLOBAL_PARTIAL_ARRAY=0
GLOBAL_WORKER_SUMMARY_ARRAY=0
GENERATED_RX_SEGMENT_EXACT_SIZE=PASS
REDUCTION_FRONTIER_EXACT_96B=PASS
DIRECT_REL32_AOT=PASS
```

The frozen tensor runtime template contains 2056 bytes `.text`, 69 bytes `.data`, and 20 bytes `.bss`. A representative heat topology image contains a third RX `PT_LOAD` whose file/memory size equals exactly the generated evaluator byte count; the final file ends at that segment rather than carrying a fixed evaluator reserve.

## C. Serial-Spine Erasure proof

Required markers:

```text
SERIAL_SPINE_ERASURE=PASS
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
DISTRIBUTED_CAUSAL_RETURN_TREE=PASS
GLOBAL_TASK_QUEUE=0
```

The runtime source contains the causal `run_tree` executor fabric and contains none of the former root spawn/wait/reduction loop labels or global publication arrays. Every internal node creates one independent right subtree, computes its left subtree, joins only that direct child, performs one fan-in-two result combination, then releases the child stack.

## Communication/reduction proof

At `N=33,554,432`, chunk size 65,536, four executors:

```text
chunks=512
chunks_per_executor=128
1.0.7 executor summary slots=4
1.0.9 cross-executor causal return edges=3
legacy/new reduction adds=511/511
legacy/new critical reduction span=9/9
```

A deliberately uneven `N=20,000,000` one-vs-four-executor regression remains inside the `1e-10` numeric contract; the frozen run used for the gate was bit-identical.

## Native authority proof

Required markers:

```text
ASSEMBLY_ONLY_NATIVE_BUILD=PASS
NO_FOREIGN_HIGH_LEVEL_BACKEND=PASS
NO_DYNAMIC_RUNTIME_OR_INTERPRETER=PASS
```

These markers apply to the authoritative topology backend after canonical Wheelchair semantics. The multilingual/repairing `.whex` human shell remains an optional compile-time surface tool; the WHEX physical-erasure regression requires byte-identical canonical core and byte-identical final ELF against the direct topology path.

## Retained release gates

The complete 1.0.9 suite retains:

- direct-general correctness and controlled signed traps;
- deterministic f64 differential checks;
- General Topology Recovery and `.wh`/`.whex` byte-identical topology images;
- WHEX multilingual/repair physical erasure;
- AVX-512 resource-model, topology-index CSE, and strength-reduction regressions;
- computation elimination with exact-cancellation machine-code checks;
- communication elimination with no global synchronization frontier.

## Performance boundary

Runtime/serial-spine erasure is a structural release claim, not a blanket speed claim. A current-host 51-round interleaved A/B control at `N=16,777,216` measured 1.0.9 and 1.0.8 near parity in whole-process time (about +0.66% at one executor and -0.44% at four executors for 1.0.9 in that noisy run). A separate tight `/proc` RSS sampler at `N=100,000,000` observed 1.0.9 at 28 KiB peak RSS vs 104 KiB for 1.0.8 at one executor, and 40 KiB vs 116 KiB at four executors.

The release therefore claims the verified removal of fixed/global runtime state and the central fork/join/reduction spine. It does not convert measurement noise into a speedup claim.

## Release-harness isolation

The heavy native proof gates in `test_complete.sh` run sequentially in the release harness so they cannot compete for a constrained CI CPU quota. This is test orchestration only: it does not alter generated executor topology, runtime scheduling, or benchmark semantics.

## Frozen-tree verification

The final source tree completed `test_complete.sh` with exit status 0 and emitted `WHEELCHAIR_1_0_9_COMPLETE=PASS`. Two clean rebuilds after that complete suite produced byte-identical `topologyc` images with SHA-256 `3e1d830731ef3a1b56ffd1f169a846a35fd5f4e80f79ba232c0879942ec5845a`.

## Fresh-package verification

The clean source package is verified by extraction into an empty directory. The extracted tree contains no `build`, `build109tmp`, `__pycache__`, or `.pyc` artifacts; `SOURCE_SHA256_1_0_9.txt` verifies successfully; `test_complete.sh` exits 0 and emits `WHEELCHAIR_1_0_9_COMPLETE=PASS`; and the compiler rebuilt from that extracted package has SHA-256 `3e1d830731ef3a1b56ffd1f169a846a35fd5f4e80f79ba232c0879942ec5845a`, identical to the frozen compiler.

## Freeze rule

A release package is final only when:

1. every component of `test_complete.sh` passes on the frozen tree;
2. two consecutive clean builds produce the recorded compiler hash;
3. a clean source tar is created without build/cache artifacts;
4. the tar is freshly extracted and the same release-gate components pass;
5. the compiler rebuilt from the extracted tar matches the recorded hash.
