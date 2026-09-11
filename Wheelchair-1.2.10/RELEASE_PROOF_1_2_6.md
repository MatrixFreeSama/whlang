# Wheelchair 1.2.6 Release Proof

## Release statement

Wheelchair 1.2.6 closes the general-parallel upgrade under four simultaneous requirements:

1. general bindings obey causal topology rather than source order;
2. the physical fabric contains no hidden global scheduler/queue/serial fallback;
3. mature 1.2.5 native peaks are preserved at execution-byte level;
4. native resource admission is structural and generic rather than workload-specific.

## Frozen baseline

Development byte authority:

```text
branch: build-1.2.5-multifield
commit: 392111d4d0be81e2d9107724e058571c9f4c458a
```

Protected mature sources remain hash-identical:

```text
compiler/tensor_frontend_x86_64.S
  e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6
compiler/topologyc_x86_64.S
  2e83af25b6a6188c9ce24497d636206ca5978e59a92b619e6b722909ad2d4f80
runtime/tensor_runtime_template_x86_64.S
  e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3
```

## General native proof

The final gate requires:

```text
GENERAL_PARALLEL_NATIVE_Q1_Q2_Q4_EQUIVALENCE=PASS
GENERAL_PARALLEL_NATIVE_ITERATE_RELOCATION=PASS
GENERAL_PARALLEL_NATIVE_FRAGMENTATION=PASS
GENERAL_PARALLEL_NATIVE_SOURCE_ORDER_SERIALIZATION=0
GENERAL_PARALLEL_NATIVE_GLOBAL_READY_QUEUE=0
GENERAL_PARALLEL_NATIVE_RUNTIME_SELECTOR=0
GENERAL_PARALLEL_NATIVE_SERIAL_FALLBACK=0
WHEELCHAIR_GENERAL_PARALLEL_NATIVE_1_2_6=PASS
```

Semantic/schedulerless gates additionally require:

```text
GENERAL_PARALLEL_BINDING_DAG=PASS
GENERAL_PARALLEL_SOURCE_ORDER_EDGES=0
GENERAL_PARALLEL_RECURRENCE_ENCLAVE=PASS
GENERAL_PARALLEL_SCHEDULERLESS_PHYSICALIZATION=PASS
GENERAL_PARALLEL_WORKLOAD_NAME_BLIND=PASS
SCHEDULERLESS_CAUSAL_RANDOM_DAG_300=PASS
SCHEDULERLESS_CAUSAL_MULTISOURCE=PASS
SCHEDULERLESS_CAUSAL_MPSC_INBOX=PASS
SCHEDULERLESS_CAUSAL_HANDOFF_COLLISIONS=0
SCHEDULERLESS_CAUSAL_LOCAL_FALLBACKS=0
SCHEDULERLESS_CAUSAL_GLOBAL_READY_SCAN=0
SCHEDULERLESS_CAUSAL_GLOBAL_QUEUE_OPS=0
SCHEDULERLESS_CAUSAL_ROOT_SCHEDULER_OPS=0
SCHEDULERLESS_CAUSAL_PARENT_CHAIN_UPDATES=0
SCHEDULERLESS_CAUSAL_RUNTIME_COST_SELECTOR=0
SCHEDULERLESS_CAUSAL_SERIAL_FALLBACK=0
```

## Generic native profile proof

The active AOT resource classes are exactly:

```text
base
wide
derived
```

Current structural witnesses establish:

```text
5 structural loads  -> base
6 structural loads  -> base
11 structural loads -> wide
12 structural loads -> wide
proved Rank-N       -> derived
```

The gate requires:

```text
NATIVE_RESOURCE_PROFILE_STRUCTURAL_ADMISSION=PASS
NATIVE_RESOURCE_PROFILE_WORKLOAD_DISPATCH=0
NATIVE_RESOURCE_PROFILE_RUNTIME_SELECTOR=0
WH_WHEX_WIDE_CANONICAL_BYTE_EQUIVALENCE=PASS
WH_WHEX_NATIVE_RESOURCE_PROFILE_EQUIVALENCE=PASS
NATIVE_RESOURCE_PROFILE_RUNTIME_ABI_ZMM12_15_PROTECTED=PASS
NATIVE_RESOURCE_PROFILE_SPECIAL_PURPOSE_ROUTE=0
WHEELCHAIR_NATIVE_RESOURCE_PROFILES_1_2_6=PASS
```

The coupled WH/WHEX canonical witness hash is:

```text
5e78b9c89cec2baf5eafb7a6641694cd7ae2e5a6c528497bae1fefb150718b87
```

## Technical Peak Preservation proof

Mandatory host-independent checks:

```text
BASE_PROFILE_1_2_5_COMPILER_LOADABLE_BYTE_IDENTITY=PASS
WIDE_PROFILE_1_2_5_COMPILER_LOADABLE_BYTE_IDENTITY=PASS
DERIVED_PROFILE_1_2_5_FRONTEND_LOADABLE_BYTE_IDENTITY=PASS
DERIVED_PROFILE_1_2_5_COMPILER_TEXT_BYTE_IDENTITY=PASS
DERIVED_PROFILE_1_2_5_RUNTIME_LOADABLE_BYTE_IDENTITY=PASS
MATURE_RUNTIME_1_2_5_NATIVE_BYTE_IDENTITY=PASS
WHEELCHAIR_1_2_5_TECHNICAL_PEAK_EXECUTION_BYTES_PRESERVED=PASS
```

The derived compiler is not required to preserve retired source filenames inside non-executing ELF symbol/string metadata. The generated frontend, compiler `.text`, runtime loadable image, and host-qualified emitted program image are the execution authority.

## AVX-512 qualification model

The native tensor compiler self-scans the real host ISA. `--isa-limit` only places a ceiling on semantic capabilities; it does not spoof missing AVX-512 hardware.

Therefore:

```text
host-independent authority -> mandatory on every x86-64 validation runner
AVX-512 compilation/execution -> mandatory only when host reports avx512f
non-qualified dynamic subgate -> explicit SKIP_HOST_NOT_AVX512F
```

A SKIP is not a PASS.

## Pre-seal full-green authority

Workflow run:

```text
34005715246
```

Head:

```text
8fb4a502bc7373290a5ec462b58775b456b1fe7d
```

Result:

```text
success
```

All workflow steps completed successfully, including build, 1.2.5 static authority, general Q1/Q2/Q4, generic native resource profiles, schedulerless gates, execution-byte peak protection, special-purpose route audit, hidden-serial audit, and evidence archive.

This runner did not expose AVX-512F, so AVX-512-specific compile/execution subgates were explicitly marked `SKIP_HOST_NOT_AVX512F`.

Evidence artifact:

```text
artifact id: 9980851385
SHA-256: f16096d1a66efd163c54c0aa443a9d32830a5bfe34ce22353ef489a9536ec673
```

## Qualified AVX-512 dynamic witness

Workflow run:

```text
34005158707
```

Head:

```text
4382fa12caad304057eff99d63f172773a06d180
```

This runner completed the AVX-512-dependent checks before encountering a later obsolete derived whole-ELF comparison gate. Completed dynamic evidence included:

```text
1.2.5 coupled FSI dynamic self-test = PASS
coupled checksum at N=10,000,000 = 0x4130e896f42e1dd6
general Q1/Q2/Q4 = PASS
wide old/new same-core native byte identity = PASS
WH/WHEX wide native byte equivalence = PASS
wide numeric reference = PASS
wide VDIVPD = 0
wide reachable hot CALL edges = 0
schedulerless/general semantic gates = PASS
```

The later failure was caused by comparing an entire derived compiler loadable blob that contained renamed non-executing ELF `STT_FILE`/string-table metadata from an embedded runtime template. The final gate replaced that invalid comparison with execution-section/loadable-image comparisons.

A repository compare from `4382fa12caad304057eff99d63f172773a06d180` through `8fb4a502bc7373290a5ec462b58775b456b1fe7d` reports changes only in:

```text
.github/workflows/validate-1.2.6-final-general-parallel.yml
worktree/test_native_peak_preservation_126.sh
worktree/test_native_resource_profiles_126.sh
```

No compiler, runtime, build, wrapper, parser, or generated native implementation changed between that qualified dynamic witness and the pre-seal full-green authority. The dynamic witness therefore applies to the same execution implementation.

## Special-purpose and hidden-serial elimination

Final static audit requires the active route to contain no former narrow-route files or symbols and emits:

```text
ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0
ACTIVE_LEGACY_DERIVED_FILE_ROUTE=0
ACTIVE_HIDDEN_SERIAL_SPINE=0
```

`rank_n_product` remains a valid semantic property. It is not a route identity.

## Performance admission

Schedulerless three-runner whole-matrix geometric ratio against the 1.2.5 fabric:

```text
0.942883791
```

Equivalent to approximately 5.71% faster overall across the measured matrix.

This is bounded benchmark evidence, not a universal performance claim.

## Final definition

Wheelchair 1.2.6 is releasable only when the final workflow simultaneously confirms:

```text
Correct
&& General
&& Schedulerless
&& NoHiddenSerialSpine
&& NoWorkloadDispatch
&& NoRuntimeProfitabilitySelector
&& NoScalarFallback
&& TechnicalPeakExecutionBytesPreserved
```

The final release marker is:

```text
WHEELCHAIR_1_2_6_FINAL=PASS
```
