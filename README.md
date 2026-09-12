# Wheelchair 1.2.18

Wheelchair 1.2.18 is the **WH/WHEX Native Materialized-Field Surface Completion** release.

1.2.16 made real dynamic Rank-N `f32` fields executable. 1.2.17 removed the dominant repeated field/address work. 1.2.18 closes the remaining human-source gap: users can now express the supported materialized-field semantics directly in WH/WHEX instead of hand-writing the expanded `wheelchair.field/1` canonical graph.

The field ABI, locality optimizer, SIMD backends and parallel runtime are unchanged.

## Official release archive

[Download Wheelchair-1.2.18.zip](https://github.com/MatrixFreeSama/whlang/raw/refs/heads/main/dist/Wheelchair-1.2.18.zip) · [Archive SHA-256](https://github.com/MatrixFreeSama/whlang/blob/main/dist/Wheelchair-1.2.18.zip.sha256)

Archive size: **3,945,930 bytes**

Archive SHA-256:

```text
29fe6a352dc1d6fdec9cd29a072434e13cee812884943cec6ef7ef81abc42735
```

The release archive contains the complete 1.2.18 source, native compiler/runtime images, historical regression authority, release proofs, and the self-checking `SHA256SUMS` manifest. The supported release gate is `./test_release_native_1218.sh`.

## Human field source

A periodic Rank-N field kernel can now be written directly as:

```text
program shift_z
strict

input nx: u64
input ny: u64
input nz: u64

input field a[
    x in nx periodic,
    y in ny periodic,
    z in nz periodic
]: f32

output field out[x in nx, y in ny, z in nz]: f32 =
    a[x,y,z+1]
```

The WH shell may use structural `for` syntax for the same data-domain semantics, while WHEX may use `region ... effect pure parallel`. Equivalent forms are required by the release suite to generate byte-identical native executables.

Supported surface features in 1.2.18 include:

- `input field`, `output field`, `inout field`;
- multiple independent dynamic extents;
- Rank-N logical axes;
- per-axis `periodic` boundaries and explicit `periodic(expr, extent)`;
- WH fake-for field assignment;
- WHEX pure-parallel regions;
- materialized-field `sum` reduction;
- UTF-8 identifiers;
- compile-time `pure fn` expressions;
- normal `whexc` routing into the sovereign field backend.

## Pure functions are zero-cost abstractions

```text
pure fn twice(v: f32) -> f32 = v * 2.0
output field out[x in nx, y in ny, z in nz]: f32 = twice(a[x,y,z])
```

The function call disappears at compile time. The release tests require the one-character parameter form above, a long-name parameter form, the direct expression `a[x,y,z] * 2.0`, and the equivalent canonical JSON to generate byte-for-byte identical ELF images.

1.2.18 also fixes lexical precedence so an exact pure-function parameter identity outranks optional one-edit human-shell typo repair.

## Strict boundary semantics

A field axis is strict unless a real boundary contract is declared. Therefore:

```text
a[x+1,y,z]
```

rejects when `x` has no proved boundary rule. With:

```text
x in nx periodic
```

or an explicit `periodic(x+1,nx)`, the access is legal and lowers to the existing Rank-N coordinate algebra.

The compiler does not silently invent periodicity.

## Runtime shape truth

Materialized-field shape truth comes from `WHFLD216` descriptors. Human source names the logical extent symbols:

```text
input nc: u64
input field p[x in nx, y in ny, z in nz, c in nc]: f32
```

1.2.18 deliberately does **not** pretend that `c in 3` is a runtime-checked static component contract, because the current ABI does not encode such a source constraint. That spelling remains rejected until a real semantic/ABI contract exists.

## Zero-cost surface bridge

The production path is:

```text
WH / WHEX
   -> compile-time human Field lowering
   -> wheelchair.field/1
   -> 1.2.17 load/coordinate locality compression
   -> direct AVX2 / AVX-512 AOT machine code
```

`wheelchair.field/1` remains accepted for compatibility, testing and compiler work, but it is no longer the required human authoring surface for the supported Field subset.

There is no FieldLang, wrapper runtime, bytecode layer, C/LLVM/MLIR backend or JIT.

## 1.2.17 locality engine remains intact

The full strict-f32 integration authority still contains 6,921 canonical operations and 2,304 logical field loads. The 1.2.17 backend reduces these to:

```text
logical field loads                2304
unique field+coordinate values       97
unique neighborhood coordinates      27
fast-path direct gathers              97
```

Launch-time layout proof, dynamic power-of-two address strength reduction, reuse-weighted residency, general-layout fallback and strict accumulation order are preserved.

The historical same-host 1.2.16 -> 1.2.17 regression probe remains:

| Physicalization | 1.2.16 | 1.2.17 | Speedup |
|---|---:|---:|---:|
| AVX-512 | 2033.430 ms | 30.146 ms | 67.45x |
| AVX2 | 4241.540 ms | 47.666 ms | 88.98x |

1.2.18 does not alter that backend.

## Native field ABI

The storage ABI remains **`WHFLD216`**. A field descriptor carries rank, logical extents, physical byte strides, logical element count and data offset. Intentional read/write aliasing uses one `inout` field; distinct declarations remain under the noalias contract.

See `FIELD_ABI_1_2_16.md`.

## Compile

Human WHEX/WH field source can be compiled through the ordinary launcher:

```sh
./whexc kernel.whex -o kernel
```

or through an explicit field physicalization:

```sh
./fieldc kernel.whex -o kernel
./fieldc-native256 kernel.whex -o kernel-avx2
```

Canonical `wheelchair.field/1` input remains compatible with the same commands.

## Parallel contract

1.2.18 adds no scheduler. The existing recipient-blind release model remains unchanged:

- no work stealing;
- no global ready queue;
- no central scheduler;
- no post-completion peer query;
- no destination-aware resource handoff;
- no hidden scalar field fallback.

Unsupported physical behavior rejects. AVX2 non-contiguous output remains an explicit rejection rather than hidden scalar lane stores.

## Production closure

The production compiler/runtime chain remains handwritten assembly and static native ELF. `build.sh` invokes no Python, and the release contains no Python source.

Run the complete release suite with:

```sh
./test_release_native_1218.sh
```

Key terminal markers include:

```text
WH_WHEX_CANONICAL_ELF_IDENTITY=PASS
WH_FAKE_FOR_FIELD_LOWERING=PASS
WHEX_REGION_FIELD_LOWERING=PASS
FIELD_INPUT_OUTPUT_INOUT_SURFACE=PASS
RANK4_COMPONENT_AXIS_SURFACE=PASS
PURE_FN_SHORT_PARAMETER_SCOPE=PASS
PURE_FN_ZERO_RUNTIME_ABSTRACTION=PASS
UTF8_FIELD_IDENTIFIERS=PASS
STRICT_BOUNDARY_REJECTION=PASS
NO_FAKE_STATIC_COMPONENT_CONTRACT=PASS
WHEELCHAIR_HUMAN_FIELD_SURFACE_1_2_18=PASS
WHEELCHAIR_1_2_18_RELEASE=PASS
```

See `RELEASE_NOTES_1_2_18.md`, `RELEASE_GATES_1_2_18.txt`, `WHEELCHAIR_CHARTER_1_2_18.md` and `PURE_ASSEMBLY_RELEASE_PROOF_1_2_18.md` for the exact release boundary.

## 简体中文概览

Wheelchair（轮椅）是一门以 **HPC 与科学仿真为首要目标的国产自研通用语言**：坚持矩阵自由、Rank-N 数据化语义、AOT 专一化编译、直接生成原生机器码，并以 WH 人类友好壳层与 WHEX 显式结构语义共同驱动同一套底层。它强调真并行而不是“并行外壳里藏串行”，不采用工作窃取、全局就绪队列和中央调度器，资源完成后立即盲释放；同时拒绝 C/LLVM/MLIR/JIT 套壳和隐藏标量回退，尽量把重复地址、重复访存和无效机器工作在编译期压掉。1.2.18 已把真实 Rank-N `f32` 物化场正式接回 WH/WHEX 顶层，支持动态多维形状、周期邻域、输入/输出/原地场、纯函数零开销展开、UTF-8 标识符以及 AVX2/AVX-512 原生物理化。项目追求的不是“看起来像传统语言”，而是让用户尽量只写数学关系，把并行、SIMD、邻域访问、寄存器驻留和结构压缩这些脏活交给编译器自己完成。
