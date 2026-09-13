# Wheelchair 1.3.10

Wheelchair is an HPC- and simulation-first general-purpose language built around matrix-free execution, Rank-N semantics, AOT compilation, direct x86-64 machine code, and causal physical execution.

Wheelchair 1.3.10 is the **Blind Surplus Reflow and Load-Balancing Extinction** release. It turns the Active-Silicon Purity doctrine introduced in 1.3.9 into production execution architecture.

## Latest release

[Download Wheelchair-1.3.10.zip](https://github.com/MatrixFreeSama/whlang/raw/refs/heads/main/dist/Wheelchair-1.3.10.zip) · [SHA-256 file](https://github.com/MatrixFreeSama/whlang/blob/main/dist/Wheelchair-1.3.10.zip.sha256)

Archive size: **4,730,734 bytes**

```text
SHA-256
3922de77ca3c0beb5ea0b46eb12a59e656f5de1add98d194b3a4e8fedceef3f1
```

The final archive was validated from a fresh extraction. Its 503-file manifest passed before and after the complete release gate, and the extracted release ended with:

```text
WHEELCHAIR_1_3_10_RELEASE=PASS
```

The supreme objective is not CPU occupancy:

```text
not: CPU utilization -> 100%

but: necessary physical work / all active physical work -> 100%
```

Idle silicon is legal when no independent causal work exists. Activated silicon doing avoidable coordination, balancing, polling, redistribution, duplicate realization, artificial synchronization, or occupancy maintenance is a design failure.

The governing rule is:

> **Activate no silicon without necessary work. Waste no activated silicon on avoidable work.**

## 1.3.10 execution architecture

### Work exists before capacity

Hardware width is only a ceiling. It does not create work.

```text
causal work -> eligibility to activate silicon
hardware     -> maximum permission ceiling
```

Affinity and the compatibility option `--executors N` therefore mean only the maximum permitted concurrent execution capacity. They do not mean "create N workers".

### Load balancing is extinct from Tensor and Field production execution

1.3.10 removes the remaining worker-equality family:

- no static `id * chunks / P` work partition;
- no proportional executor assignment by subtree size;
- no executor-ID work topology;
- no work stealing;
- no push or pull balancing;
- no peer load observation;
- no idle-worker or busy-worker discovery for redistribution;
- no global load table;
- no global ready queue;
- no post-completion work search;
- no runtime occupancy autotuning.

Execution topology comes from the canonical causal work tree. A capacity ceiling may change how many independent subtrees run at once, but it must not change which causal work exists.

### Blind Surplus Reflow

A completed causal region releases anonymous execution capacity. It never selects a recipient. A region that already owns another independent causal subtree may make one bounded blind claim for anonymous capacity. It never searches for a donor.

```text
finished causal work
        |
        v
anonymous capacity release
        |
        v
unowned execution permission
        ^
        |
blind bounded claim
        |
pre-existing independent causal work
```

The claimed object is execution permission, not another thread's work.

```text
resource release is recipient-blind
resource acquisition is donor-blind
```

Anonymous credits are distributed across four cache-line-isolated bitsets. There is no single global surplus counter. A failed claim does not spin, poll, inspect peers, or retry the same point. Execution continues through necessary local work, and a later genuine causal expansion point may perform a new bounded claim.

### Protected mechanisms

The load-balancing purge does not remove mechanisms that perform real causal or machine work:

- General causal futex waiting on a region's own indegree;
- AOT Kahn topology queues used only during compilation;
- intra-kernel SIMD carrier scheduling that removes dependency stalls inside already-active silicon;
- locality constraints that express physical permission or cost;
- compile-time physical scheduling that removes instructions or dependencies without runtime worker redistribution.

## Numerical contracts

Wheelchair keeps strict and tolerant floating-point contracts distinct.

The 1.3.8 strict reduction repair remains preserved. On the FSI diagnostic, native512 and native256 strict execution produces the same final bits across capacity ceilings q1, q2 and q4. In 1.3.10, tolerant execution also uses a capacity-independent canonical causal reduction tree.

Selected 100M FSI checksums:

```text
tolerant q1/q2/q4: 0x416522bcff4adae6
strict   q1/q2/q4: 0x416522bcff4adb3a
```

The FSI graph is a regression probe only. Production source contains no FSI, fluid, or solid specialization trigger.

## Active-Silicon audit

Host-specific 1.3.8 to 1.3.10 measurements on an Intel Xeon Platinum 8573C with 5 visible vCPUs and a sustained 4-CPU cgroup quota show the intended distinction between occupancy and useful active work.

At N=100M:

| Contract | q | 1.3.8 wall | 1.3.10 wall | 1.3.8 CPU time | 1.3.10 CPU time |
|---|---:|---:|---:|---:|---:|
| tolerant | 2 | 163.058 ms | 164.698 ms | 320.053 ms | 269.260 ms |
| tolerant | 4 | 83.526 ms | 85.106 ms | 318.845 ms | 270.973 ms |
| strict | 4 | 163.809 ms | 124.686 ms | 477.018 ms | 402.070 ms |

Tolerant q2/q4 reduces total active CPU time by about 16% and 15% while wall time stays within about 1% to 2%. Strict q4 reduces wall time by about 23.9% while also reducing total CPU active time by about 15.7%.

The generated FSI arithmetic hot payload is byte-identical between 1.3.8 and 1.3.10, so these measurements isolate execution-fabric changes rather than an FSI arithmetic rewrite.

These measurements are host- and workload-specific. They are not a transistor-level Active-Silicon Purity percentage and are not a universal performance claim.

See `PERFORMANCE_1_3_10_BLIND_SURPLUS_REFLOW.md` for the full measurement table and claim boundary.

## Core language and compiler model

Wheelchair remains:

- matrix-free by default;
- Rank-N oriented;
- AOT only;
- direct x86-64 native code;
- no C, LLVM, MLIR, or JIT production backend;
- no Python source in the release implementation path;
- WH human surface plus WHEX lower-level semantics;
- strict and tolerant numerical contracts;
- AVX2 and AVX-512 native Tensor and Field paths;
- recipient-blind resource release;
- no work stealing and no central runtime scheduler.

WH may present familiar surface forms such as `if` or `while`, but the lower execution model is dataized and physical rather than a requirement for sequential von-Neumann control.

## Build

```sh
./build.sh
```

The production build uses shell plus handwritten assembly tooling. It invokes no Python compiler generator and no C/LLVM production backend.

## Compile

General WH/WHEX:

```sh
./wheelchairc program.wh -o program
./whexc program.whex -o program
```

Tensor:

```sh
./topologyc program.whex -o program
./topologyc-wide program.whex -o program
./topologyc-native256 program.whex -o program-avx2
```

`--executors N` remains accepted for compatibility, but in 1.3.10 it means only a capacity ceiling:

```sh
./topologyc-wide program.whex -o program --executors 4
```

Field:

```sh
./fieldc kernel.whex -o kernel
./fieldc-native256 kernel.whex -o kernel-avx2
```

## Release validation

Run the complete 1.3.10 release authority:

```sh
./test_release_native_1310.sh
```

The dedicated Blind Surplus Reflow and load-balancing-extinction gate is:

```sh
./test_blind_surplus_reflow_1310.sh
```

The final release must end with:

```text
COMPLETE_1_3_7_RELEASE_AUTHORITY_PRESERVED=PASS
WHEELCHAIR_STRICT_PARALLEL_REDUCTION_1_3_8=PASS
WHEELCHAIR_BLIND_SURPLUS_REFLOW_1_3_10=PASS
WHEELCHAIR_1_3_10_RELEASE=PASS
```

## 1.3.10 authority documents

- `WHEELCHAIR_CHARTER_1_3_10.md`
- `RELEASE_NOTES_1_3_10.md`
- `RELEASE_GATES_1_3_10.txt`
- `PURE_ASSEMBLY_RELEASE_PROOF_1_3_10.md`
- `PERFORMANCE_1_3_10_BLIND_SURPLUS_REFLOW.md`
- `LOAD_BALANCING_EXTINCTION_1_3_10.md`
- `test_blind_surplus_reflow_1310.sh`
- `test_release_native_1310.sh`

Historical charter, release-note, proof, and regression files remain in the package for auditability.

## Permanent 1.3.10 red lines

```text
HARDWARE_WIDTH_IS_DEMAND_AUTHORITY=0
STATIC_EQUAL_WORK_PARTITION=0
PROPORTIONAL_EXECUTOR_SPLIT=0
EXECUTOR_ID_WORK_TOPOLOGY=0
WORK_STEALING=0
PUSH_BALANCING=0
PULL_BALANCING=0
PEER_LOAD_OBSERVATION=0
PEER_WORK_OBSERVATION=0
GLOBAL_LOAD_TABLE=0
GLOBAL_READY_QUEUE=0
GLOBAL_SURPLUS_COUNTER=0
POST_COMPLETION_WORK_SEARCH=0
FAILED_CLAIM_SPIN=0
RUNTIME_BALANCING_AUTOTUNE=0
OCCUPANCY_AS_OPTIMIZATION_TARGET=0

CAUSAL_WORK_IS_DEMAND_AUTHORITY=1
HARDWARE_WIDTH_IS_ONLY_CEILING=1
ANONYMOUS_SURPLUS_RELEASE=1
BLIND_CAPACITY_CLAIM=1
RESOURCE_RELEASE_IS_RECIPIENT_BLIND=1
RESOURCE_ACQUISITION_IS_DONOR_BLIND=1
CLAIM_REQUIRES_PREEXISTING_CAUSAL_WORK=1
ACTIVE_SILICON_PURITY_IS_PRIMARY=1
```

## Recent architecture progression

```text
1.3.7  Tensor Physical Reality Completion
       Remove repeated physical realization inside high-pressure f64 Tensor execution.

1.3.8  Strict Parallel Reduction Identity Repair
       Preserve capacity-independent strict reduction bits without collapsing to one executor.

1.3.9  Active-Silicon Purity Charter Reset
       Stop treating CPU occupancy as the objective. Necessary active work becomes the objective.

1.3.10 Blind Surplus Reflow & Load-Balancing Extinction
       Remove worker-equality execution authority and let pre-existing causal work blindly claim
       anonymous released execution capacity.
```

## Claim boundary

Wheelchair does not claim universal superiority over C, C++, Fortran, CUDA, Julia, Rust, Zig, or other mature HPC ecosystems. The measurements in this README are host- and workload-specific evidence about particular compiler and execution mechanisms.

Current strengths are concentrated in matrix-free and Rank-N numerical execution, direct AOT native realization, causal dependency exposure, elimination of redundant physical work, strict/tolerant floating-point separation, and execution structures designed to minimize avoidable active-silicon work. Mature HPC ecosystems still provide much broader libraries, tooling, platform support, GPU and distributed-memory infrastructure, debugging, profiling, and production validation.
