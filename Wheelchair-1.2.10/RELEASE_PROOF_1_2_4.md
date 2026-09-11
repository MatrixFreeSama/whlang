# Wheelchair 1.2.4 Release Proof

Wheelchair 1.2.4 is releasable only when the following evidence chain is satisfied.

## Authority source

The native-code authority for the implementation was established on branch `build-1.2.4` at commit:

```text
c47e146c7f89c2024f3f63550f64731c5ce1a692
```

GitHub Actions authority run:

```text
33879496682
```

The run completed three AVX-512-qualified jobs with no qualified failure and ended with:

```text
WHEELCHAIR_1_2_4_QUORUM=PASS
```

Each qualified job required:

```text
WHEELCHAIR_1_2_4_COMPLETE=PASS
GENERIC124_SAME_HOST_PERFORMANCE=PASS
WHEELCHAIR_1_2_4_AUTHORITY=PASS
```

## Required native gates

```text
GENERIC_NATIVE_NO_WORKLOAD_DISPATCH=PASS
GENERIC_NATIVE_OPERATOR_NAME_ERASURE=PASS
GENERIC_NATIVE_RENAMED_NATIVE_BYTE_EQUIVALENCE=PASS
GENERIC_PRODUCT_SUBTRACT_CONTRACTION=PASS
GENERIC_VECTOR_REDUCTION_RESIDENCY=PASS
GENERIC_NATIVE_GENERATED_CALL_EDGES=0
GENERIC_NATIVE_SCALAR_FALLBACK=0
NEWTON_JV_NATIVE_BYTE_IDENTITY_ON_1_2_4=PASS
RANK_N_1_2_2_TECHNICAL_PEAK_PROTECTED_ON_1_2_4=PASS
SCE_1_2_3_TECHNICAL_PEAK_PROTECTED_ON_1_2_4=PASS
GENERIC_NATIVE_OPTIMIZATION_1_2_4=PASS
WHEELCHAIR_1_2_4_COMPLETE=PASS
```

## Performance admission rule

Performance is admitted only by same-host frozen-baseline versus optimized Wheelchair comparisons. Absolute time between different CPU vendors or generations is not a release gate.

For every AVX-512-qualified authority host:

```text
median(BASE/OPT) >= 1.05
geomean(BASE/OPT) >= 1.05
```

Observed authority aggregate speedups:

```text
AMD EPYC 9V74 family 25 model 17, slot 3:
  median  1.1923x
  geomean 1.1935x

AMD EPYC 9V45 family 26 model 2, slot 6:
  median  1.0934x
  geomean 1.0930x

AMD EPYC 9V74 family 25 model 17, slot 10:
  median  1.1907x
  geomean 1.1949x
```

The matched expert-C control is retained as a calibration reference, not as a cross-vendor compiler-admission oracle.

## Final documentation-only delta rule

Release documentation may be added after the native authority commit only if the finalizer proves that every path changed after `c47e146c7f89c2024f3f63550f64731c5ce1a692` is documentation/evidence-only. Any compiler, runtime, surface, test, build, benchmark, or executable-code change invalidates the authority and requires a new full authority run.

## Package rule

The formal package may be published only after all of the following:

1. exact final source commit is recorded;
2. post-authority delta is proven documentation/evidence-only;
3. `build/`, `.git`, Python caches, temporary CI state and compiled local binaries are excluded;
4. internal `SHA256SUMS` is generated;
5. the ZIP is re-extracted into a clean directory;
6. every internal hash is verified with `sha256sum -c`;
7. the external ZIP SHA-256 is written to `Wheelchair-1.2.4.zip.sha256`;
8. both files are verified to exist in `main/dist`.

Only then may the release be called complete.
