# Wheelchair 1.3.178

Native x86-64 AOT compiler. Build with `sh build.sh` using GNU binutils. Seven canonical tools are provided in `bin/`; production compilation and generated programs require no Python, GCC, LLVM or libc. `wheelchairc` is the production launcher.

Exact ordered expression identity is independent of physical residency admission. Dynamic checked integer division/remainder, casts and shifts can participate in the existing scalar fact planner. No commutation or floating-point reassociation is introduced.

Checked facts become available at their first unconditional demand, using the existing generation/scope table. They are not eagerly evaluated in a preheader. Conditional arms and lazy Boolean tails cannot initialize an unconditional fact. Generation refresh invalidates the appropriate frontier; deferred facts retain their old-state dependencies until production. Zero-trip and dormant errors remain lazy.

Immutable scalar payloads share the existing XMM bit-carrier bank. Integer arithmetic keeps its ordinary caller-owned GPR destination; retention moves its exact bits into the common bank, and consumers recover those bits without a floating-point conversion. The separate persistent integer GPR allocator has been removed. Measured anonymous pressure and target prices still govern admission.

One checked register division relation produces quotient and remainder, with unsigned, signed trap and signed wrap policies. Stack consumers project their existing ABI around this same relation. The native register path no longer pushes operands into a stack helper and pops them back. Zero and INT64_MIN/-1 contracts remain explicit.

Iteration work projects the actual emitted steady-state loop span. Initialization and result publication are priced once rather than multiplied by the iteration bound. The existing outward materialization profile is unchanged. This remains an approximate target resource price, not elapsed cycles or a guarantee that every short parallel invocation is profitable.

Rank-N / Axis / Operator / Region / Effect / Capability / Physical Reality / Physical DAG remain common authorities. Existing guard completion, strict rounding, simultaneous state updates, lazy errors and overflow contracts are preserved. No workload selector, compatibility recurrence backend, user scheduling annotation, new runtime cache, worker pool, polling or work stealing is added.

This release removes proved compiler redundancy; it does not disable silicon branch prediction or replace hardware out-of-order execution. Branch-local sharing, cross-state SIMD and complete Tensor/Field lifetime unification remain limited. No global compiler optimum or hardware peak-throughput percentage is claimed. See RELEASE_NOTES_1_3_178.md and the accompanying measured report.

## Validation and measured boundaries

The release archive SHA-256 is `d223eae8f9bf285f2f922f0f1769811dd308dd3870e54ca82edbc734b9908460`. The 120-file production tree was cleanly rebuilt with GNU binutils; all seven packaged tools and all production files matched byte for byte. The accompanying report records the original regression and four-way measurements, including remaining C/Fortran gaps and short-call overhead. This publication does not claim a new full benchmark run.
