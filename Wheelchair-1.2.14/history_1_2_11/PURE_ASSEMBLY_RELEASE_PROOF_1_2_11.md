# Wheelchair 1.2.11 Pure Assembly Release Proof

## Production closure

```text
PRODUCTION_LANGUAGE_PYTHON=0
PRODUCTION_COMPILER_PYTHON=0
PRODUCTION_RUNTIME_PYTHON=0
PRODUCTION_BUILD_PYTHON_INVOCATIONS=0
```

The release tree contains no `.py` files. The native launcher links the handwritten surface lowerer and performs resource-profile selection from the canonical graph in the same static ELF process.

## 1.2.11 resource-profile correction

The release gate proves:

```text
10 distinct structural loads -> base
11 distinct structural loads -> wide
15 distinct structural loads -> base vector recompute
Rank-N Cartesian metadata    -> derived
FSI structural pressure 12   -> wide
FSI Q1/Q2/Q4 automatic ELF   == explicit wide ELF
```

Selector policy:

```text
WORKLOAD_IDENTITY_DISPATCH=0
SOURCE_PATH_DISPATCH=0
BENCHMARK_DISPATCH=0
FAILURE_DRIVEN_FALLBACK=0
RUNTIME_PROFITABILITY_SELECTOR=0
```

The selector is AOT structural policy only.

## Fluid-solid coupling regression

The same periodic coupled operator used by the historical authority benchmark passed all 27 numerical boundary cases:

```text
N = 4, 31, 32, 33, 4096, 65535, 65536, 65537, 100000
Q = 1, 2, 4
27 / 27 PASS
maximum observed relative error = 1.87e-14
required relative error <= 1e-8
```

On the validation AMD EPYC 9V74 host, the formal 3-warmup / 11-measurement same-affinity run at N=10M and N=100M produced a six-case geometric mean `Wheelchair / Expert C = 1.168x`. The 100M/Q4 row measured `0.892x`, a Wheelchair win in that row. These are same-host benchmark observations, not a language-wide claim.

## Parallel invariants retained

```text
GLOBAL_READY_QUEUE=0
ROOT_SCHEDULER=0
WORK_STEALING=0
RUNTIME_FIXED_HOME_OWNERSHIP=0
PERSISTENT_IDLE_WORKER_SPIN=0
POST_COMPLETION_WORK_SEARCH=0
POST_COMPLETION_PEER_QUERY=0
RESOURCE_RELEASE_DESTINATION=0
RESOURCE_HANDOFF=0
BLIND_RESOURCE_RELEASE=PASS
OWNED_TO_FREE_TRANSITION=PASS
```
