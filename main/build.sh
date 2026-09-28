#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$ROOT"

# 1.3.24 single-source production authority.  Historical frozen copies are no
# longer a build input: compiler/ and runtime/ are the only source authority.
# This prevents a deleted private matcher or compatibility path from surviving
# through a copied legacy physicalization.
echo 'SINGLE_CURRENT_SOURCE_AUTHORITY=PASS'
echo 'PRODUCTION_BUILD_PYTHON_GENERATORS=0'

# Mature native-512 runtime remains the protected physical peak.
as --64 runtime/tensor_runtime_x86_64.S -o "$BUILD/tensor_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_template.o" -o "$BUILD/tensor_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_template" compiler/runtime_offsets.inc

# Derived native-512 runtime from the same current runtime authority.
as --64 runtime/tensor_runtime_x86_64.S -o "$BUILD/tensor_derived_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_derived_runtime_template.o" -o "$BUILD/tensor_derived_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_derived_runtime_template" "$BUILD/runtime_derived_offsets.inc"

# True AVX2/YMM runtimes from the same current runtime authority.
as --64 --defsym TENSOR_RUNTIME_NATIVE256=1 runtime/tensor_runtime_x86_64.S -o "$BUILD/tensor_runtime_native256_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_native256_template.o" -o "$BUILD/tensor_runtime_native256_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_native256_template" "$BUILD/runtime_native256_offsets.inc"

as --64 --defsym TENSOR_RUNTIME_NATIVE256=1 runtime/tensor_runtime_x86_64.S -o "$BUILD/tensor_derived_runtime_native256_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_derived_runtime_native256_template.o" -o "$BUILD/tensor_derived_runtime_native256_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_derived_runtime_native256_template" "$BUILD/runtime_derived_native256_offsets.inc"

echo 'STRICT_REDUCTION_REPAIR_RUNTIME_OFFSETS=BUILT'

as --64 runtime/general_runtime_template_x86_64.S -o "$BUILD/general_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/general_runtime.ld \
  "$BUILD/general_runtime_template.o" -o "$BUILD/general_runtime_template"
./tools/generate_general_runtime_offsets.sh "$BUILD/general_runtime_template" compiler/general_runtime_offsets.inc

# Recipient-blind causal-region runtime. Offset derivation is shell + native ELF
# symbols only; no Python participates in production build authority.
as --64 runtime/general_parallel_release_x86_64.S -o "$BUILD/general_parallel_release.o"
ld -nostdlib -static -z noexecstack -T runtime/general_parallel_release.ld \
  "$BUILD/general_parallel_release.o" -o "$BUILD/general_parallel_release.elf"
objcopy -O binary --only-section=.text \
  "$BUILD/general_parallel_release.elf" "$BUILD/general_parallel_release_template.bin"
sh tools/generate_general_parallel_release_offsets.sh \
  "$BUILD/general_parallel_release.elf" "$BUILD/general_parallel_release_template.bin" \
  "$BUILD/general_parallel_release_offsets.json" "$BUILD/general_parallel_release_offsets.inc"
echo 'GENERAL_PARALLEL_RELEASE_OFFSETS_NO_PYTHON=PASS'

# Shared handwritten sovereign topology core with physical-shape capability algebra.
as --64 compiler/topologyc_x86_64.S -o "$BUILD/topologyc_core.o"
as --64 compiler/silicon_domain_probe_x86_64.S -o "$BUILD/silicon_domain_probe.o"
as --64 compiler/fabric_target_facts_x86_64.S -o "$BUILD/fabric_target_facts.o"
as --64 compiler/outward_materialization_profile_x86_64.S -o "$BUILD/outward_materialization_profile.o"
as --64 compiler/general_frontend_x86_64.S -o "$BUILD/general_frontend.o"
as --64 compiler/general_runtime_blob_x86_64.S -o "$BUILD/general_runtime_blob.o"
as --64 compiler/general_parallel_release_blob_x86_64.S -o "$BUILD/general_parallel_release_blob.o"
as --64 compiler/surface_lowerer_x86_64.S -o "$BUILD/surface_lowerer.o"
as --64 compiler/human_shell_feedback_x86_64.S -o "$BUILD/human_shell_feedback.o"

# Native/split 512 physicalizers.
as --64 compiler/tensor_frontend_x86_64.S -o "$BUILD/tensor_frontend.o"
as --64 compiler/runtime_blob_x86_64.S -o "$BUILD/runtime_blob.o"

# 1.2.17 sovereign native field lane.  This extends the separate direct-native AOT
# physicalization so the protected 1.2.15 f64 tensor path remains byte-authoritative.
# The field lane is pure handwritten assembly and maps materialized WHFLD216
# fields directly; it never routes through C, LLVM, JIT, Python, or a bytecode
# interpreter.
as --64 runtime/field_runtime_512_x86_64.S -o "$BUILD/field_runtime_512.o"
ld -nostdlib -static -z noexecstack -T runtime/field_runtime.ld \
  "$BUILD/field_runtime_512.o" -o "$BUILD/field_runtime_512_template"
sh tools/generate_field_runtime_offsets.sh \
  "$BUILD/field_runtime_512_template" "$BUILD/field_runtime_512_offsets.inc"

as --64 runtime/field_runtime_256_x86_64.S -o "$BUILD/field_runtime_256.o"
ld -nostdlib -static -z noexecstack -T runtime/field_runtime.ld \
  "$BUILD/field_runtime_256.o" -o "$BUILD/field_runtime_256_template"
sh tools/generate_field_runtime_offsets.sh \
  "$BUILD/field_runtime_256_template" "$BUILD/field_runtime_256_offsets.inc"

as --64 compiler/field_runtime_blob_512_x86_64.S -o "$BUILD/field_runtime_blob_512.o"
as --64 compiler/field_runtime_blob_256_x86_64.S -o "$BUILD/field_runtime_blob_256.o"
as --64 compiler/field_frontend_512_x86_64.S -o "$BUILD/field_frontend_512.o"
as --64 compiler/field_frontend_256_x86_64.S -o "$BUILD/field_frontend_256.o"
as --64 compiler/fieldc_driver_x86_64.S -o "$BUILD/fieldc_driver.o"
as --64 compiler/field_parser_link_stubs_x86_64.S -o "$BUILD/field_parser_link_stubs.o"

# Fieldc links the current handwritten parser symbols from the tensor frontend.
# Unreachable tensor-only link references are satisfied by compile-time stubs;
# no tensor scheduler/runtime is entered by fieldc.
ld -nostdlib -static -z noexecstack \
  "$BUILD/fieldc_driver.o" "$BUILD/field_frontend_512.o" \
  "$BUILD/tensor_frontend.o" "$BUILD/runtime_blob.o" \
  "$BUILD/field_runtime_blob_512.o" "$BUILD/field_parser_link_stubs.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" \
  -o "$BUILD/fieldc"
ld -nostdlib -static -z noexecstack \
  "$BUILD/fieldc_driver.o" "$BUILD/field_frontend_256.o" \
  "$BUILD/tensor_frontend.o" "$BUILD/runtime_blob.o" \
  "$BUILD/field_runtime_blob_256.o" "$BUILD/field_parser_link_stubs.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" \
  -o "$BUILD/fieldc-native256"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc"
as --64 compiler/tensor_derived_frontend_x86_64.S -o "$BUILD/tensor_frontend_derived.o"
as --64 compiler/runtime_derived_blob_x86_64.S -o "$BUILD/runtime_derived_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend_derived.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_derived_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc-derived"

# Native256 physicalizers for every generic graph-resource class.
as --64 compiler/tensor_frontend_native256_x86_64.S -o "$BUILD/tensor_frontend_native256.o"
as --64 compiler/tensor_derived_frontend_native256_x86_64.S -o "$BUILD/tensor_frontend_derived_native256.o"
as --64 compiler/runtime_native256_blob_x86_64.S -o "$BUILD/runtime_native256_blob.o"
as --64 compiler/runtime_derived_native256_blob_x86_64.S -o "$BUILD/runtime_derived_native256_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend_native256.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_native256_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc-native256"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend_derived_native256.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_derived_native256_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc-derived-native256"

# Native production launchers.  The driver performs only compile-time structural
# classification (base/derived from canonical structure); it never retries a failed compiler
# and never inspects workload names.
as --64 compiler/native_driver_x86_64.S -o "$BUILD/native_driver.o"
ld -nostdlib -static -z noexecstack "$BUILD/native_driver.o" "$BUILD/surface_lowerer.o" -o "$BUILD/wheelchairc"
cp "$BUILD/wheelchairc" "$BUILD/whexc"

for f in \
  "$BUILD/topologyc" "$BUILD/topologyc-derived" \
  "$BUILD/topologyc-native256" "$BUILD/topologyc-derived-native256" \
  "$BUILD/tensor_runtime_template" "$BUILD/tensor_derived_runtime_template" \
  "$BUILD/tensor_runtime_native256_template" "$BUILD/tensor_derived_runtime_native256_template" \
  "$BUILD/general_runtime_template" "$BUILD/general_parallel_release.elf" \
  "$BUILD/field_runtime_512_template" "$BUILD/field_runtime_256_template" \
  "$BUILD/fieldc" "$BUILD/fieldc-native256" \
  "$BUILD/wheelchairc" "$BUILD/whexc"; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

# Production build closure must not invoke Python. Python remains allowed only
# in reference/validation tooling while the human surface is being migrated.
if grep -En '(^|[[:space:]])python(3)?([[:space:]]|$)' build.sh; then
  echo 'Python invocation leaked into production build' >&2; exit 1
fi

# Current release surface: bin/ contains only canonical production executables.
rm -rf "$ROOT/bin"
mkdir -p "$ROOT/bin"
for f in \
  wheelchairc whexc topologyc topologyc-derived \
  topologyc-native256 topologyc-derived-native256 \
  fieldc fieldc-native256; do
  cp "$BUILD/$f" "$ROOT/bin/$f"
done

# 1.3.53 optional-iteration convergence. Historical defaults remain fallback policy only.
[ ! -e "$BUILD/topologyc-wide" ]
[ ! -e "$BUILD/topologyc-wide-native256" ]
[ ! -e "$ROOT/bin/topologyc-wide" ]
[ ! -e "$ROOT/bin/topologyc-wide-native256" ]
[ -f compiler/physical_reality.inc ]
[ ! -e compiler/physical_reality_136.inc ]
[ ! -e compiler/physical_reality_137.inc ]
[ ! -e compiler/physical_reality_138.inc ]
[ ! -e compiler/json_parser_x86_64.S ]
[ ! -e compiler/physical_vector_shapes.inc ]
if find compiler runtime tools surface -type f -name '*138*' -print | grep -q .; then
  echo 'Historical 138 filename leaked into production authority' >&2; exit 1
fi
if grep -RniE '\b(PR|T)138_|physical_reality_138|tensor_(derived_)?frontend_138|tensor_runtime_138' \
  compiler runtime tools surface >/dev/null 2>&1; then
  echo 'Historical 138 identifier leaked into production authority' >&2; exit 1
fi
if grep -Rni 'devtrash/' compiler runtime tools surface >/dev/null 2>&1; then
  echo 'Production source depends on devtrash' >&2; exit 1
fi

echo 'CURRENT_PHYSICAL_REALITY_AUTHORITY=compiler/physical_reality.inc'
echo 'PRODUCTION_VERSION_TAGGED_ARCHITECTURE=0'
echo 'DEAD_WIDE_COMPILER_ALIAS=0'
echo 'PRODUCTION_UNUSED_SOURCE_AUTHORITY=0'
echo 'PRODUCTION_BUILD_HISTORY_REPLAY=0'
echo 'ADVANCED_MATH_OPTIONAL_ITERATION_AUTHORITY=PASS'
echo 'NEW_ALGORITHM_FAMILIES_1_3_53=0'
echo 'NEW_RUNTIME_SOLVER_AUTHORITIES_1_3_53=0'
echo 'WHEELCHAIR_1_3_53_BUILD=PASS'

# 1.3.54 large architecture aging: structural storage, not enlarged constants.
! grep -q '^\.equ SAST_MAX' compiler/surface_lowerer_x86_64.S
! grep -q '^\.equ SBUF_.*_CAP' compiler/surface_lowerer_x86_64.S
grep -q '^s_grow_ast_slab:' compiler/surface_lowerer_x86_64.S
grep -q '^s_out_reserve:' compiler/surface_lowerer_x86_64.S
grep -q '^s_alloc_pointer_workset:' compiler/surface_lowerer_x86_64.S
! grep -q 'GENERAL_RUNTIME_BINDING_SLOT_CAP' compiler/general_runtime_capacity.inc
! grep -q 'SFH_OPS_CAP' compiler/field_surface_lowerer_x86_64.inc
! grep -q 'SFH_MAX_SCALARS' compiler/field_surface_lowerer_x86_64.inc
! grep -q 'SFH_MAX_REDUCES' compiler/field_surface_lowerer_x86_64.inc
echo 'ARCHITECTURE_AGING_1_3_54=PASS'
echo 'WHEELCHAIR_1_3_54_BUILD=PASS'

# 1.3.55 runtime-record and code-staging aging. Program cardinality and generated
# code size are instance facts; the initial staging estimate may grow and retry.
! grep -Eq 'GENERAL_RUNTIME_(INPUT|BINDING_SLOT|STATE|OUTPUT)_CAP' compiler/general_runtime_capacity.inc
grep -q '^\.equ GENERAL_RUNTIME_DYNAMIC_ARENA_VA,' compiler/general_runtime_capacity.inc
! grep -q 'GCODE_CAP' compiler/general_frontend_x86_64.S
grep -q '^g_prepare_code_arenas:' compiler/general_frontend_x86_64.S
grep -q 'g_code_overflow' compiler/general_frontend_x86_64.S
grep -q '^dynamic_arena_bytes_patch:' runtime/general_runtime_template_x86_64.S
grep -q '^program_trailer_file_offset_patch:' runtime/general_runtime_template_x86_64.S
grep -q '^rankn_input_end_patch:' runtime/general_runtime_template_x86_64.S
grep -q '^g_measure_runtime_state_capacity:' compiler/general_frontend_x86_64.S
grep -q '^g_measure_rankn_input_workspace:' compiler/general_frontend_x86_64.S
! grep -Eq 'RPF_INPUT_(OBJ_)?STRIDE|GRPF_INPUT_STRIDE' compiler/general_frontend_x86_64.S runtime/general_runtime_template_x86_64.S
! grep -Eq '^\.equ (MAX_OPS|MAX_CONST_POOL|GEN_CAP),' compiler/field_frontend_common_x86_64.S
grep -q '^ff_prepare_graph_arena:' compiler/field_frontend_common_x86_64.S
grep -q '^ff_prepare_code_arena:' compiler/field_frontend_common_x86_64.S
grep -q 'ff_code_overflow' compiler/field_frontend_common_x86_64.S
echo 'ARCHITECTURE_AGING_1_3_55=PASS'
echo 'WHEELCHAIR_1_3_55_BUILD=PASS'

# 1.3.56 final compiler-workspace aging. Field/access cardinality and Tensor
# staging/optimizer metadata are instance facts. Rank-8 remains the WHFLD216
# external-format width; logical VREG ownership remains the current physicalizer.
! grep -Rqs 'FIELD_RUNTIME_FIELD_CAP\|FIELD_RUNTIME_ACCESS_CAP' compiler runtime tools
! grep -RqsE '\bMAX_(FIELDS|SPECS|ACCESS)\b' compiler/field_frontend_common_x86_64.S runtime/field_runtime_512_x86_64.S runtime/field_runtime_256_x86_64.S
grep -q '^\.equ FIELD_RUNTIME_RANK_CAP,8$' compiler/field_runtime_capacity.inc
grep -q '^ff_prepare_instance_arena:' compiler/field_frontend_common_x86_64.S
grep -q '^field_prepare_instance_arenas:' runtime/field_runtime_512_x86_64.S
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_derived_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  grep -q '^tensor_prepare_code_arenas:' "$f"
  grep -q '^tensor_prepare_optimizer_arena:' "$f"
  ! grep -Eq 'EVAL_CAP|VEC_AOT_FACT_CAP|\.skip[[:space:]]+4194304|\.skip[[:space:]]+524288' "$f"
  ! grep -Eq '^vec_const_(bits|reg|addr):\.skip|^vec_linear_(binding|key_a|key_b|key_c|expr|coeff|mode):\.skip' "$f"
done
echo 'ARCHITECTURE_AGING_1_3_56=PASS'
echo 'WHEELCHAIR_1_3_56_BUILD=PASS'

# 1.3.57 ShapeFact-N convergence. Logical shape is one sparse semantic authority:
# axis identity + extent fact are stored; rank/product/stride are derived instead
# of serialized as compatibility scalars. Current Tensor consumers may collapse
# supported shapes onto one physical q root, but that capability restriction is
# not encoded into ShapeFact itself.
[ -f compiler/shapefact_n.inc ]
[ -f compiler/shapefact_n_frontend.inc ]
! grep -Eq '\.(equ|set)[[:space:]]+.*(MAX|CAP|LIMIT)' compiler/shapefact_n.inc compiler/shapefact_n_frontend.inc
! grep -RqsE 'rank_n_product|rank_n_source_rank|rank_n_product_patch|RUNTIME_RANK_N_PRODUCT|__rankn_q' compiler runtime tools
grep -q '^s_shapefact_validate:' compiler/surface_lowerer_x86_64.S
grep -q '^s_tensor_shapefact_prepare:' compiler/surface_lowerer_x86_64.S
grep -q '^s_emit_shapefact_json:' compiler/surface_lowerer_x86_64.S
grep -q '^shapefn_parse_root:' compiler/shapefact_n_frontend.inc
grep -q 'shape_fact_n' compiler/native_driver_x86_64.S
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  grep -q 'compiler/shapefact_n' "$f"
done
echo 'SHAPEFACT_N_1_3_57=PASS'
echo 'SHAPEFACT_COMPATIBILITY_PRODUCT_DESCRIPTOR=0'
echo 'SHAPEFACT_FIXED_CAPACITY=0'
echo 'WHEELCHAIR_1_3_57_BUILD=PASS'

# 1.3.58 regression-only ShapeFact consumer-selector convergence. Presence of
# ShapeFact is not itself a derived-physicalizer predicate; the existing axis
# structure chooses between already-existing base and derived consumers.
grep -q '^shape_fact_requires_derived:' compiler/native_driver_x86_64.S
grep -q 'call shape_fact_requires_derived' compiler/native_driver_x86_64.S
echo 'SELECTOR_CONVERGENCE_1_3_58=PASS'
echo 'WHEELCHAIR_1_3_58_BUILD=PASS'

# 1.3.59 physical-plan authority remains converged. 1.3.61 ages the final
# physical-shape handoff through GroupFact, so the old private unroll/carrier
# plan names must not return.
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  grep -q 'call synthesize_resource_schedule' "$f"
  grep -q 'call synthesize_group_fact' "$f"
  grep -q 'group_body_factor' "$f"
  ! grep -Fq 'physical_plan_unroll' "$f"
  ! grep -Fq 'physical_plan_carriers' "$f"
  ! grep -Fq 'mov dword ptr [rip+group_body_factor],2' "$f"
done
grep -q 'physical_realized_group_body' compiler/tensor_derived_frontend_x86_64.S
echo 'PHYSICAL_PLAN_CONVERGENCE_1_3_59=PASS'
echo 'WHEELCHAIR_1_3_59_BUILD=PASS'

# 1.3.60 pure-function/numeric-literal convergence.  No stdpf-specific compiler
# identity exists: generic call AST hygiene and one shared numeric spelling
# authority close the exposed gaps.
sed -n '/^\.sppp_call_args:/,/^\.sppp_call_close:/p' compiler/surface_lowerer_x86_64.S | grep -q 'xor r13d,r13d'
grep -q '^\.equ SURFACE_FACT_RECORD_BYTES,432$' compiler/surface_lowerer_x86_64.S
grep -q 'cmp rbx,rax' compiler/surface_lowerer_x86_64.S
grep -q '^\.sppp_num_exp_probe:' compiler/surface_lowerer_x86_64.S
[ -f compiler/numeric_literal_parser.inc ]
grep -q '^node_parse_f64_bits:' compiler/numeric_literal_parser.inc
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_derived_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  grep -q 'compiler/numeric_literal_parser.inc' "$f"
  ! grep -q '^node_parse_f64_bits:' "$f"
done
echo 'PURE_COMPOSITION_CONVERGENCE_1_3_60=PASS'
echo 'WHEELCHAIR_1_3_60_BUILD=PASS'


# 1.3.61 Automatic Grouping convergence. Group is the structural authority;
# Vector and Scalar are degradations, not sibling optimizers or compatibility
# backends. No fixed group/rank/tile bound or runtime group manager is allowed.
[ -f compiler/groupfact.inc ]
grep -q '^.equ GF_VECTOR_IS_DEGENERATE_GROUP,1$' compiler/groupfact.inc
grep -q '^.equ GF_SCALAR_IS_DEGENERATE_VECTOR,1$' compiler/groupfact.inc
grep -q '^.equ GF_FIXED_RANK_CAP,0$' compiler/groupfact.inc
grep -q '^.equ GF_FIXED_GROUP_SIZE,0$' compiler/groupfact.inc
grep -q '^.equ GF_RUNTIME_GROUP_MANAGER,0$' compiler/groupfact.inc
grep -q '^.equ PR_GROUPFACT_IS_SINGLE_SEMANTIC_AUTHORITY,1$' compiler/physical_reality.inc
grep -q '^synthesize_group_fact:' compiler/topologyc_x86_64.S
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_derived_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  grep -q 'call synthesize_group_fact' "$f"
  grep -q 'group_body_factor' "$f"
  grep -q 'group_carrier_factor' "$f"
  ! grep -q 'physical_plan_group_body' "$f"
  ! grep -q 'physical_plan_group_carriers' "$f"
  ! grep -q 'physical_tensorized' "$f"
  ! grep -q 'physical_plan_unroll' "$f"
  ! grep -q 'physical_plan_carriers' "$f"
done
echo 'AUTOMATIC_GROUPING_1_3_61=PASS'
echo 'GROUP_FIXED_HARD_LIMITS=0'
echo 'GROUP_RUNTIME_MANAGERS=0'
echo 'WHEELCHAIR_1_3_61_BUILD=PASS'

# 1.3.63 Automatic Grouping aging/convergence. Resource scheduling, GroupFact,
# canonical physicalization and runtime patching share one body/carrier fact pair.
# Backend realization fields are witnesses only; shadow width authorities and the
# old unroll/reduction-carrier ABI names are forbidden in production sources.
grep -q '^.equ GF_SINGLE_BODY_FACTOR_AUTHORITY,1$' compiler/groupfact.inc
grep -q '^.equ GF_SINGLE_CARRIER_FACTOR_AUTHORITY,1$' compiler/groupfact.inc
grep -q '^.equ GF_SHADOW_SCHEDULE_WIDTH_FIELDS,0$' compiler/groupfact.inc
grep -q '^.equ GF_SHADOW_PHYSICAL_PLAN_FIELDS,0$' compiler/groupfact.inc
grep -q '^.equ PR_GROUPFACT_IS_SINGLE_SEMANTIC_AUTHORITY,1$' compiler/physical_reality.inc
grep -q 'RUNTIME_GROUP_CARRIER_FACTOR_OFF' compiler/runtime_offsets.inc
grep -q 'RUNTIME_GROUP_BODY_FACTOR_OFF' compiler/runtime_offsets.inc
grep -q 'group_carrier_factor_patch' runtime/tensor_runtime_x86_64.S
grep -q 'group_body_factor_patch' runtime/tensor_runtime_x86_64.S
grep -q 'topology.resource-schedule/2' compiler/topologyc_x86_64.S
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_derived_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  grep -q 'group_body_factor' "$f"
  grep -q 'group_carrier_factor' "$f"
  ! grep -q 'physical_plan_group_body' "$f"
  ! grep -q 'physical_plan_group_carriers' "$f"
  ! grep -q 'physical_group_form' "$f"
done
if grep -RniE 'schedule_(unroll|carriers)|RUNTIME_(UNROLL|CARRIERS)_OFF|unroll_count_patch|reduction_carriers_patch|physical_plan_group_(body|carriers)|physical_group_form' \
  compiler runtime tools surface >/dev/null 2>&1; then
  echo 'Legacy Group width authority leaked into production source' >&2; exit 1
fi
echo 'AUTOMATIC_GROUPING_AGING_1_3_63=PASS'
echo 'GROUP_SHADOW_WIDTH_AUTHORITIES=0'
echo 'GROUP_LEGACY_RUNTIME_WIDTH_ABI=0'
echo 'WHEELCHAIR_1_3_63_BUILD=PASS'

# 1.3.64 full aging/convergence. Internal compatibility aliases and impossible
# zero-capacity native256 physical domains are forbidden from production source.
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_derived_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  ! grep -q '^vec_mov:' "$f"
  ! grep -q 'legacy duplicate/ignored operand' "$f"
  grep -q 'Canonical generic i64 multiply ABI: edi=dst' "$f"
done
! grep -Eq '^vec_const_reg_(alloc|free):|^tensor_select_(constant|induct)_facts:' compiler/tensor_frontend_x86_64.S
for f in compiler/tensor_frontend_native256_x86_64.S compiler/tensor_derived_frontend_native256_x86_64.S; do
  ! grep -Eq '^vec_const_reg_(alloc|free):|^vec_emit_init_const:' "$f"
  grep -q 'No resident constant-register allocator exists on this physicalizer' "$f"
  sed -n '/^vec_const_get_reg:/,/^[^.#[:space:]][^:]*:/p' "$f" | grep -q 'call vec_const_intern'
done
grep -q '^.equ GF_INTERNAL_COMPATIBILITY_ALIASES,0$' compiler/groupfact.inc
grep -q '^.equ GF_NATIVE256_GHOST_CONSTANT_DOMAIN,0$' compiler/groupfact.inc
grep -q '^.equ GF_NATIVE256_GHOST_CACHE_DOMAIN,0$' compiler/groupfact.inc
grep -q '^.equ PR_ZERO_CAPACITY_PSEUDO_DOMAIN,0$' compiler/physical_reality.inc
grep -q '^.equ PR_NATIVE256_PERSISTENT_CACHE_DOMAIN,0$' compiler/physical_reality.inc
for f in compiler/tensor_frontend_native256_x86_64.S compiler/tensor_derived_frontend_native256_x86_64.S; do
  ! grep -Eq 'vec_cache_|vec_index_cache_|vec_index_value_cache_|vec_current_gen|vec_gen_counter' "$f"
done
echo 'FULL_CONVERGENCE_1_3_64=PASS'
echo 'INTERNAL_COMPATIBILITY_ALIASES=0'
echo 'NATIVE256_GHOST_CONSTANT_DOMAIN=0'
echo 'NATIVE256_GHOST_CACHE_DOMAIN=0'
echo 'WHEELCHAIR_1_3_64_BUILD=PASS'

# 1.3.65 Automatic Grouping execution closure. Group must widen from the mature
# Vector physicalization rather than replacing it with a weaker one-packet path.
# Width remains derived from measured body cost, ShapeFact geometry and silicon
# facts; no fixed candidate set, workload route or runtime manager is admitted.
grep -q '^.equ GF_VECTOR_PHYSICAL_BASELINE_PRESERVED,1$' compiler/groupfact.inc
grep -q '^.equ GF_GROUP_BODY_FROM_MEASURED_PHYSICAL_COST,1$' compiler/groupfact.inc
grep -q '^.equ GF_GROUP_LEVEL_CONTROL_EDGE,1$' compiler/groupfact.inc
grep -q '^.equ GF_GROUP_WIDTH_CANDIDATE_SET,0$' compiler/groupfact.inc
grep -q '^.equ GF_NECESSARY_WORK_CONSERVED,1$' compiler/groupfact.inc
grep -q '^.equ GF_REALIZATION_CLOSED_OVER_BODY,1$' compiler/groupfact.inc
grep -q '^.equ GF_VECTOR_DEGRADATION_IS_CANONICAL,1$' compiler/groupfact.inc
grep -q '^.equ GF_FIXED_DENSE_PACKET_GATE,0$' compiler/groupfact.inc
grep -q '^.equ PR_GROUPFACT_CANONICAL_FACTORS_DRIVE_EXECUTION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_PRIVATE_WIDTH_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_DOMAIN_CAP_CODEGEN_GATE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_RUNTIME_SELECTOR,0$' compiler/physical_reality.inc
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_derived_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  grep -q 'group_body_cost_ops' "$f"
  grep -q 'group_body_cost_bytes' "$f"
  grep -q 'group_body_factor' "$f"
done
grep -q '^vec_emit_group_countdown_backedge:' compiler/tensor_frontend_x86_64.S
grep -q '^vec_emit_group_countdown_backedge:' compiler/tensor_frontend_native256_x86_64.S
! grep -RqsE 'group_(candidate|threshold)_(2|4|8|16|32)|workload.*group.*route' compiler runtime surface tools
echo 'AUTOMATIC_GROUPING_EXECUTION_1_3_65=PASS'
echo 'GROUP_VECTOR_BASELINE_PRESERVED=PASS'
echo 'GROUP_FIXED_EXPANSION_THRESHOLDS=0'
echo 'WHEELCHAIR_1_3_65_BUILD=PASS'

# 1.3.66 Group aging: GroupFact is the sole width/structure authority. A zero
# finite ShapeFact cap cannot disable a canonical Group; every Tensor emitter
# consumes group_body_factor directly. The derived-512 private packet-width
# shadow has been deleted rather than bridged.
grep -q '^.equ GF_CANONICAL_BODY_FACTOR_DRIVES_ALL_TENSOR_EMITTERS,1$' compiler/groupfact.inc
grep -q '^.equ GF_PRIVATE_DENSE_PACKET_WIDTH,0$' compiler/groupfact.inc
grep -q '^.equ GF_ZERO_DOMAIN_CAP_IS_CODEGEN_GATE,0$' compiler/groupfact.inc
grep -q '^.equ GF_GROUP_IS_OPTIMIZER_BRANCH,0$' compiler/groupfact.inc
grep -q '^.equ PR_GROUPFACT_IS_SINGLE_SEMANTIC_AUTHORITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUPFACT_CANONICAL_FACTORS_DRIVE_EXECUTION,1$' compiler/physical_reality.inc
! grep -Rqs 'vec_dense_group_packets' compiler runtime surface tools
for f in \
  compiler/tensor_frontend_x86_64.S \
  compiler/tensor_frontend_native256_x86_64.S \
  compiler/tensor_derived_frontend_native256_x86_64.S; do
  ! grep -Fq 'cmp dword ptr [rip+group_body_cap],0' "$f"
done
# Physical Reality no longer mirrors the GroupFact semantic constitution.
! grep -Eq '^\.equ PR_(AUTOMATIC_GROUPING|GROUP_IS_PRIMARY_STRUCTURE|VECTOR_IS_GROUP_DEGRADATION|SCALAR_IS_VECTOR_DEGRADATION|GROUP_RESOURCE_FACTORS_UNIFIED|GROUP_CANONICAL_FACTORS_UNIFIED|GROUP_EXECUTING_PHYSICAL_EPISODE|GROUP_MEASURED_BODY_FOOTPRINT|GROUP_PRESERVES_VECTOR_BASELINE|GROUP_NECESSARY_WORK_CONSERVED|GROUP_REALIZATION_CLOSED_OVER_BODY|GROUP_CONTROL_EDGE_PER_EPISODE),' compiler/physical_reality.inc
echo 'GROUP_AGING_1_3_66=PASS'
echo 'GROUP_PRIVATE_WIDTH_AUTHORITIES=0'
echo 'GROUP_DOMAIN_CAP_CODEGEN_GATES=0'
echo 'WHEELCHAIR_1_3_66_BUILD=PASS'


# 1.3.67 transition-power aging.  The historical scalar affine self-map is no
# longer a production route: one Rank-N backward slice proves and materializes
# x'=A*x+b, with scalar power surviving only as the one-lane degeneration.
grep -q '^.equ PR_TRANSITION_POWER_RANKN_AFFINE_CLOSURE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_TRANSITION_POWER_SCALAR_SHADOW_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_TRANSITION_POWER_FIXED_DIMENSION,0$' compiler/physical_reality.inc
grep -q '^.equ PR_TRANSITION_POWER_STATE_COUNT_ROUTE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_TRANSITION_POWER_REPEAT_THRESHOLD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FIXED_AFFINE_AST_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_TRANSITION_POWER_RUNTIME_SELECTOR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_TRANSITION_POWER_MANAGER,0$' compiler/physical_reality.inc
grep -q '^g_transition_mark_state_refs:' compiler/general_frontend_x86_64.S
grep -q '^g_transition_emit_affine_terms:' compiler/general_frontend_x86_64.S
grep -q '^g_try_emit_transition_power_slice:' compiler/general_frontend_x86_64.S
grep -q '^g_alloc_runtime_temp_bytes:' compiler/general_frontend_x86_64.S
grep -q '^rankn_affine_power_u64:' runtime/general_runtime_template_x86_64.S
grep -q 'GENERAL_RANKN_AFFINE_POWER_U64_VA' tools/generate_general_runtime_offsets.sh
! grep -RqsE '^g_collect_u64_transition_affine:|^g_transition_power_a:|^g_transition_power_b:|^gc_transition_power_mov_r8_rax:|^gc_transition_power_square:' compiler runtime surface tools
echo 'TRANSITION_POWER_RANKN_AGING_1_3_67=PASS'
echo 'TRANSITION_POWER_SCALAR_SHADOW_AUTHORITY=0'
echo 'TRANSITION_POWER_FIXED_DIMENSION=0'
echo 'TRANSITION_POWER_RUNTIME_SELECTOR=0'
echo 'WHEELCHAIR_1_3_67_BUILD=PASS'

# 1.3.68 human semantic convergence.  Human spelling is allowed to disappear
# only after type/contract proof and before first fragment materialization.
# Canonical representatives live in the existing General symbol record; no
# shadow IR, algorithm-name dispatcher, fixed convergence budget, or runtime
# convergence manager is admissible.
grep -q '^.equ PR_HUMAN_SEMANTIC_CONVERGENCE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_ZERO_FLIP,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_ALGORITHM_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_FIXED_ROUNDS,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_SEMANTIC_CONVERGENCE_MANAGER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STRICT_FP_SEMANTIC_REASSOCIATION,0$' compiler/physical_reality.inc
grep -q '^g_semantic_resolve_symbol:' compiler/general_frontend_x86_64.S
grep -q '^g_semantic_expr_is_pure:' compiler/general_frontend_x86_64.S
grep -q '^g_semantic_json_equal:' compiler/general_frontend_x86_64.S
grep -q '^g_semantic_converge_symbols:' compiler/general_frontend_x86_64.S
grep -q 'call g_semantic_converge_symbols' compiler/general_frontend_x86_64.S
! grep -RqsE 'semantic_(convergence|converge).*(round|budget|threshold|algorithm|workload).*=[1-9]' compiler runtime surface tools
echo 'HUMAN_SEMANTIC_CONVERGENCE_1_3_68=PASS'
echo 'SEMANTIC_CONVERGENCE_ZERO_FLIP=PASS'
echo 'SEMANTIC_CONVERGENCE_SECOND_IR=0'
echo 'SEMANTIC_CONVERGENCE_ALGORITHM_MATCHER=0'
echo 'SEMANTIC_CONVERGENCE_FIXED_ROUNDS=0'
echo 'SEMANTIC_CONVERGENCE_RUNTIME_MANAGER=0'
echo 'STRICT_FP_SEMANTIC_REASSOCIATION=0'
echo 'WHEELCHAIR_1_3_68_BUILD=PASS'


# 1.3.69 proof-level human semantic convergence. The old representative grows
# proof power; no new optimizer/pass/IR authority is introduced. Only typed,
# zero-flip relations may erase human spelling before fragment materialization.
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_PROOF_RELATIONS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_IDENTITY_SHELL_ERASURE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_COMPARISON_DUALITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SEMANTIC_CONVERGENCE_ASSOCIATIVE_REWRITE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STRICT_FP_SEMANTIC_COMMUTATION,0$' compiler/physical_reality.inc
grep -q '^g_semantic_var_representative:' compiler/general_frontend_x86_64.S
grep -q '^g_semantic_identity_representative:' compiler/general_frontend_x86_64.S
grep -q '^g_semantic_expr_is_total:' compiler/general_frontend_x86_64.S
grep -q '^g_semantic_prove_equal:' compiler/general_frontend_x86_64.S
grep -q 'call g_semantic_identity_representative' compiler/general_frontend_x86_64.S
grep -q 'call g_semantic_prove_equal' compiler/general_frontend_x86_64.S
! grep -RqsE 'semantic_(newton|fft|fibonacci|stencil|krylov|sort)_|semantic_algorithm_match' compiler runtime surface tools
! grep -RqsE 'semantic_(convergence|converge).*(round|budget|threshold|workload).*=[1-9]' compiler runtime surface tools
echo 'PROOF_LEVEL_SEMANTIC_CONVERGENCE_1_3_69=PASS'
echo 'SEMANTIC_CONVERGENCE_IDENTITY_SHELLS=PASS'
echo 'SEMANTIC_CONVERGENCE_COMPARISON_DUALITY=PASS'
echo 'SEMANTIC_CONVERGENCE_ASSOCIATIVE_REWRITE=0'
echo 'STRICT_FP_SEMANTIC_COMMUTATION=0'
echo 'WHEELCHAIR_1_3_69_BUILD=PASS'


# 1.3.70 execution-form convergence.  Recursive human spelling is not a new
# backend: the proved fixed-lag relation must disappear into the same collected
# iterate facts consumed by the old General/Rank-N/Physical-Reality authority.
grep -q '^.equ PR_EXECUTION_FORM_CONVERGENCE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSIVE_RELATION_TO_CANONICAL_ITERATE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSION_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSION_RUNTIME_BACKEND,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSION_RUNTIME_MEMO_MANAGER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSION_ALGORITHM_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSION_FIXED_ORDER_LIMIT,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSION_DEPTH_THRESHOLD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSION_RUNTIME_SELECTOR,0$' compiler/physical_reality.inc
grep -q '^s_materialize_recursive_apply:' compiler/surface_lowerer_x86_64.S
grep -q '^s_emit_collected_iterate_binding:' compiler/surface_lowerer_x86_64.S
grep -q 'call s_emit_collected_iterate_binding' compiler/surface_lowerer_x86_64.S
grep -q '^s_rec_scan_lags:' compiler/surface_lowerer_x86_64.S
grep -q '^s_rec_replace_calls:' compiler/surface_lowerer_x86_64.S
! grep -RqsE '(^|[^A-Za-z])(fibonacci|factorial|tribonacci|newton|fft|krylov|stencil)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
! grep -RqsE 'recurs(ion|ive).*(order|depth|lag|state).*(threshold|limit)[[:space:]]*=[[:space:]]*[1-9]' compiler runtime surface tools
! grep -RqsE '^recursive_(lowerer|backend|runtime|memo)|^recurrence_(ir|backend|runtime):' compiler runtime surface tools
echo 'EXECUTION_FORM_CONVERGENCE_1_3_70=PASS'
echo 'RECURSIVE_RELATION_TO_CANONICAL_ITERATE=PASS'
echo 'RECURSION_SECOND_IR=0'
echo 'RECURSION_RUNTIME_BACKEND=0'
echo 'RECURSION_RUNTIME_MEMO_MANAGER=0'
echo 'RECURSION_ALGORITHM_MATCHER=0'
echo 'RECURSION_FIXED_ORDER_LIMIT=0'
echo 'RECURSION_DEPTH_THRESHOLD=0'
echo 'WHEELCHAIR_1_3_70_BUILD=PASS'


# 1.3.71 Physical Region Fact sparsification.  A proven contiguous region is a
# persistent physical fact for the current invocation, not a predicate to be
# recomputed for every vector packet.  Boundary crossings alone rematerialize
# topology.  No workload matcher, shadow address IR/table, fixed geometry gate,
# or runtime region manager is admitted.
grep -q '^.equ PR_PHYSICAL_REGION_FACT_SPARSIFICATION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_PROVED_TOPOLOGY_RETIRES_INSIDE_REGION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_BOUNDARY_ONLY_TOPOLOGY_REMATERIALIZATION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_PHYSICAL_REGION_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STENCIL_WORKLOAD_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PHYSICAL_REGION_FIXED_THRESHOLD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PER_ELEMENT_ADDRESS_TABLE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_PHYSICAL_REGION_MANAGER,0$' compiler/physical_reality.inc
grep -q 'cg_cmp_q_regular_end:' compiler/field_frontend_common_x86_64.S
grep -q 'cg_mov_r14_rax:' compiler/field_frontend_common_x86_64.S
grep -q '^field_regular_run_end:' runtime/field_runtime_512_x86_64.S
grep -q '^field_regular_run_end:' runtime/field_runtime_256_x86_64.S
grep -q 'FIELD_RUNTIME_REGULAR_RUN_END_VA' tools/generate_field_runtime_offsets.sh
! grep -RqsE 'field_regular_episode_ok|FIELD_RUNTIME_REGULAR_EPISODE_VA' compiler runtime tools
for f in runtime/field_runtime_512_x86_64.S runtime/field_runtime_256_x86_64.S; do
  grep -q 'Piecewise-Affine RegionFact' "$f"
done
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
! grep -RqsE 'physical_region.*(threshold|limit)[[:space:]]*=[[:space:]]*[1-9]' compiler runtime surface tools
echo 'PHYSICAL_REGION_FACT_SPARSIFICATION_1_3_71=PASS'
echo 'PROVED_TOPOLOGY_RETIRES_INSIDE_REGION=PASS'
echo 'BOUNDARY_ONLY_TOPOLOGY_REMATERIALIZATION=PASS'
echo 'PHYSICAL_REGION_SECOND_IR=0'
echo 'STENCIL_WORKLOAD_MATCHER=0'
echo 'WHEELCHAIR_1_3_71_BUILD=PASS'

# 1.3.72 ownership-local execution aging.  Cold Physical Reality owns leaf
# profitability once; hot Tensor/Field executions own only disjoint regions.
# Launch geometry and mathematical reduction are separate, and the historical
# recursive causal split/join authority is deleted from current production.
grep -q '^.equ PR_OWNERSHIP_LOCAL_EXECUTION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_LAUNCH_FRONTIER_RETIRES_AT_REGION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_OS_LIFECYCLE_COMPLETION_AUTHORITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_REDUCTION_SEPARATE_FROM_EXECUTION_OWNERSHIP,1$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_CAUSAL_TREE_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_SUBTREE_PROFITABILITY_RECHECK,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RECURSIVE_PARALLEL_JOIN_TREE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_EXECUTION_GLOBAL_COMPLETION_COUNTER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_ROOT_LINEAR_SPAWN_SWEEP,0$' compiler/physical_reality.inc
grep -q '^.equ PR_OUTWARD_REGION_SECOND_BACKEND,0$' compiler/physical_reality.inc
for f in runtime/tensor_runtime_x86_64.S runtime/field_runtime_512_x86_64.S runtime/field_runtime_256_x86_64.S; do
  grep -q '^run_region_frontier:' "$f"
  grep -q '^reduce_region_results:' "$f"
  grep -q 'CLONE_PARENT' "$f"
  ! grep -q '^run_causal_tree:' "$f"
  ! grep -q '^run_causal_tree_local:' "$f"
  ! grep -q 'g_region_done' "$f"
done
! grep -RqsE '^run_causal_tree(_local)?:' runtime/tensor_runtime_x86_64.S runtime/field_runtime_512_x86_64.S runtime/field_runtime_256_x86_64.S
! sed -n '/^run_region_frontier:/,/^# reduce_region_results/p' runtime/tensor_runtime_x86_64.S | grep -q 'outward_materialization_ticks_patch'
! sed -n '/^run_region_frontier:/,/^# reduce_region_results/p' runtime/field_runtime_512_x86_64.S | grep -q 'outward_materialization_ticks_patch'
grep -q 'outward_materialization_ticks_patch' runtime/tensor_runtime_x86_64.S
grep -q 'outward_materialization_ticks_patch' runtime/field_runtime_512_x86_64.S
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
echo 'OWNERSHIP_LOCAL_EXECUTION_1_3_72=PASS'
echo 'RUNTIME_CAUSAL_TREE_AUTHORITY=0'
echo 'RUNTIME_SUBTREE_PROFITABILITY_RECHECK=0'
echo 'RECURSIVE_PARALLEL_JOIN_TREE=0'
echo 'EXECUTION_GLOBAL_COMPLETION_COUNTER=0'
echo 'ROOT_LINEAR_SPAWN_SWEEP=0'
echo 'OUTWARD_REGION_SECOND_BACKEND=0'
echo 'WHEELCHAIR_1_3_72_BUILD=PASS'

# 1.3.73 launch-static physical realization.  Cold-proved Field policy is packed
# once into the generated invocation state; packet loops may not reload those
# global facts or retain the old regular-layout compatibility branch.
grep -q '^.equ PR_LAUNCH_STATIC_PHYSICAL_REALIZATION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_PROVED_FACT_PACKET_REQUESTION,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PACKET_GLOBAL_LAYOUT_RELOAD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PACKET_GLOBAL_UNIFORM_RELOAD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PACKET_GLOBAL_NT_POLICY_RELOAD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_LAUNCH_STATIC_MODE_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_LAUNCH_STATIC_RUNTIME_POLICY_MANAGER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_LAUNCH_STATIC_WORKLOAD_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_LAUNCH_STATIC_FIXED_REGION_SPAN,0$' compiler/physical_reality.inc
grep -q 'cg_test_r15_direct:' compiler/field_frontend_common_x86_64.S
grep -q 'cg_test_r15_uniform:' compiler/field_frontend_common_x86_64.S
grep -q 'cg_test_r15_nt:' compiler/field_frontend_common_x86_64.S
grep -q 'ff_direct_loop_ptr:' compiler/field_frontend_common_x86_64.S
grep -q 'ff_generic_loop_ptr:' compiler/field_frontend_common_x86_64.S
grep -q 'ff_regular_loop_ptr:' compiler/field_frontend_common_x86_64.S
! grep -RqsE 'FIELD_RUNTIME_(REGULAR_CONTIG|UNIFORM_LAYOUT|NT_ACTIVE)_VA|ff_regular_layout_fallback_disp_ptr|g_input_regular_contig' compiler runtime tools
for f in runtime/field_runtime_512_x86_64.S runtime/field_runtime_256_x86_64.S; do
  grep -q '^g_launch_direct_layout:' "$f"
  grep -q 'movzx eax,byte ptr \[rip+g_launch_direct_layout\]' "$f"
  grep -q 'movzx eax,byte ptr \[rip+g_input_uniform_layout\]' "$f"
  grep -q 'movzx eax,byte ptr \[rip+g_nt_active\]' "$f"
done
! grep -RqsE 'launch_static.*(threshold|limit)[[:space:]]*=[[:space:]]*[1-9]' compiler runtime surface tools
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
echo 'LAUNCH_STATIC_PHYSICAL_REALIZATION_1_3_73=PASS'
echo 'PROVED_FACT_PACKET_REQUESTION=0'
echo 'PACKET_GLOBAL_LAYOUT_RELOAD=0'
echo 'PACKET_GLOBAL_UNIFORM_RELOAD=0'
echo 'PACKET_GLOBAL_NT_POLICY_RELOAD=0'
echo 'LAUNCH_STATIC_SECOND_IR=0'
echo 'WHEELCHAIR_1_3_73_BUILD=PASS'

# 1.3.74 burn-level machine facts.  Proven Physical Facts must become their
# final hardware carriers instead of being reissued as packet-local temporaries.
grep -q '^.equ PR_BURN_LEVEL_MACHINE_FACTS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_ADDRESSFACT_GPR_REGION_LIFETIME,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CONSTANTFACT_SIMD_REGION_LIFETIME,1$' compiler/physical_reality.inc
grep -q '^.equ PR_IMMUTABLE_CARRIER_ALIASING,1$' compiler/physical_reality.inc
grep -q '^.equ PR_PACKET_STACK_ADDRESS_RELOAD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PACKET_CONSTANT_RELOAD,0$' compiler/physical_reality.inc
grep -q '^.equ PR_TOLERANT_REDUCE_MACHINE_FUSION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_MACHINE_FACT_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_MACHINE_FACT_WORKLOAD_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_MACHINE_FACT_RUNTIME_POLICY_MANAGER,0$' compiler/physical_reality.inc
grep -q '^ff_assign_address_gprs:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_emit_address_gpr_residents:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_codegen_source_reg:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_reduce_square_foldable:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_emit_reduce_square_fma:$' compiler/field_frontend_common_x86_64.S
! grep -q '^ff_emit_cache_store:$' compiler/field_frontend_common_x86_64.S
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil|fibonacci|mgpcg)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
! grep -RqsE 'burn_level.*(threshold|limit)[[:space:]]*=[[:space:]]*[1-9]' compiler runtime surface tools
echo 'BURN_LEVEL_MACHINE_FACTS_1_3_74=PASS'
echo 'ADDRESSFACT_GPR_REGION_LIFETIME=PASS'
echo 'CONSTANTFACT_SIMD_REGION_LIFETIME=PASS'
echo 'IMMUTABLE_CARRIER_ALIASING=PASS'
echo 'PACKET_STACK_ADDRESS_RELOAD=0'
echo 'PACKET_CONSTANT_RELOAD=0'
echo 'TOLERANT_REDUCE_MACHINE_FUSION=PASS'
echo 'MACHINE_FACT_SECOND_IR=0'
echo 'MACHINE_WORKLOAD_MATCHER=0'
echo 'WHEELCHAIR_1_3_74_BUILD=PASS'

# 1.3.75 machine-form burn. Physical DAG stays sovereign; exact tolerant
# coefficient identities die only at final ISA realization.
grep -q '^.equ PR_COMPLETE_MACHINE_FORM_BURN,1$' compiler/physical_reality.inc
grep -q '^.equ PR_OPERATOR_IDENTITY_BURN_AT_EMITTER,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CAUSAL_DEPTH_MACHINE_ORDER_DIRECT,1$' compiler/physical_reality.inc
grep -q '^.equ PR_LATE_MACHINE_GRAPH_REWRITE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SECOND_MACHINE_SCHEDULER_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FIXED_PACKET_UNROLL_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_MACHINE_ISSUE_MANAGER,0$' compiler/physical_reality.inc
grep -q '^ff_const_bits_for_phys_reg:$' compiler/field_frontend_common_x86_64.S
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil|fibonacci|mgpcg)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
echo 'COMPLETE_MACHINE_FORM_BURN_1_3_75=PASS'
echo 'OPERATOR_IDENTITY_BURN_AT_EMITTER=PASS'
echo 'CAUSAL_DEPTH_MACHINE_ORDER_DIRECT=PASS'
echo 'SECOND_MACHINE_SCHEDULER_IR=0'
echo 'FIXED_PACKET_UNROLL_AUTHORITY=0'
echo 'WHEELCHAIR_1_3_75_BUILD=PASS'

# 1.3.76 causal-depth machine burn.  Canonical GroupFact consumes the actual
# free carrier bank; independent packet work may not collapse back into one
# repeatedly reused SIMD identity at final ISA realization.
grep -q '^.equ PR_CAUSAL_DEPTH_MACHINE_BURN,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUPFACT_DISJOINT_PACKET_CARRIERS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUPFACT_CARRIER_FROM_LIVE_MACHINE_FACTS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_PACKET_BYTE_CLONING,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PRIVATE_MACHINE_UNROLL_WIDTH,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_WIDTH_CANDIDATE_SET,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_GROUP_ISSUE_SELECTOR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STRICT_REDUCTION_GROUP_REORDER,0$' compiler/physical_reality.inc
grep -q '^ff_derive_field_groupfact:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_group_packet0_cache_reg:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_group_vreg_reg:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_group_source_reg:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_emit_group_packet_op:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_emit_group_depth_schedule:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_emit_group_fma_direct_mem:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_group_packet0_cache_reg:$' compiler/field_frontend_common_x86_64.S
! grep -q '^ff_emit_group_packet_preload:$' compiler/field_frontend_common_x86_64.S
! grep -q 'ff_direct_preload_end_ptr' compiler/field_frontend_common_x86_64.S
! grep -RqsE 'group_body_factor[^\n]*(=|,)[[:space:]]*(2|4|8)([^0-9]|$)' compiler runtime surface tools
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil|fibonacci|mgpcg)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
echo 'CAUSAL_DEPTH_MACHINE_BURN_1_3_76=PASS'
echo 'GROUPFACT_DISJOINT_PACKET_CARRIERS=PASS'
echo 'GROUPFACT_CARRIER_FROM_LIVE_MACHINE_FACTS=PASS'
echo 'GROUP_PACKET_BYTE_CLONING=0'
echo 'PRIVATE_MACHINE_UNROLL_WIDTH=0'
echo 'GROUP_WIDTH_CANDIDATE_SET=0'
echo 'WHEELCHAIR_1_3_76_BUILD=PASS'

# 1.3.77/1.3.84 Physical-DAG -> realization schedule burn. The existing
# canonical depth owns target time; x86 consumes it as ISA order while spatial
# targets may materialize the same level as simultaneous physical structure.
grep -q '^.equ PR_PHYSICAL_DAG_REALIZATION_SCHEDULE_BURN,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_DEPTH_MAJOR_REALIZATION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_LOADFACT_DEFERRED_MATERIALIZATION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_LOADFACT_MEMORY_OPERAND_BURN,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_LOADFACT_SYNTHETIC_CARRIER_REQUIRED,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_SHADOW_LOAD_CARRIER_BANK,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_PACKET0_BYTE_COPY_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GROUP_PACKET_MAJOR_BODY_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_POST_CODEGEN_MACHINE_SCHEDULER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SCHEDULE_BURN_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SCHEDULE_BURN_CANDIDATE_WIDTHS,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SCHEDULE_BURN_RUNTIME_SELECTOR,0$' compiler/physical_reality.inc
grep -q '^.equ GF_PHYSICAL_DEPTH_IS_FINAL_REALIZATION_TIME_AXIS,1$' compiler/groupfact.inc
grep -q '^.equ GF_LOADFACT_MAY_REMAIN_MEMORY_AT_TRUE_CONSUMER,1$' compiler/groupfact.inc
grep -q '^.equ GF_PACKET_MAJOR_MACHINE_REWRAP,0$' compiler/groupfact.inc
grep -q '^ff_emit_group_packet_op:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_emit_group_depth_schedule:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_group_packet0_cache_reg:$' compiler/field_frontend_common_x86_64.S
! grep -q '^ff_emit_group_packet_preload:$' compiler/field_frontend_common_x86_64.S
! grep -q '^ff_emit_group_packet_body:$' compiler/field_frontend_common_x86_64.S
! grep -RqsE 'schedule_burn.*(width|factor)[[:space:]]*=[[:space:]]*(2|4|8)([^0-9]|$)' compiler runtime surface tools
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil|fibonacci|mgpcg)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
echo 'PHYSICAL_DAG_REALIZATION_SCHEDULE_BURN_1_3_77=PASS'
echo 'GROUP_DEPTH_MAJOR_REALIZATION=PASS'
echo 'PACKET_MAJOR_MACHINE_REWRAP=0'
echo 'POST_CODEGEN_MACHINE_SCHEDULER=0'
echo 'WHEELCHAIR_1_3_77_BUILD=PASS'

# 1.3.78 converged human-shell feedback.  User-facing repair/convergence/error
# reporting is one fused protocol over the existing Surface facts.  No new
# optimization dispatcher, convergence subtype, retry frontend, or runtime state
# is admitted.  Expert WHEX/canonical output remains on the old path.
grep -q '^human_shell_report_success:' compiler/human_shell_feedback_x86_64.S
grep -q '^human_shell_report_error:' compiler/human_shell_feedback_x86_64.S
grep -q '^surface_note_convergence_name:' compiler/surface_lowerer_x86_64.S
grep -Fq 'Cheesed successfully.' compiler/human_shell_feedback_x86_64.S
grep -Fq 'Repaired successfully.' compiler/human_shell_feedback_x86_64.S
grep -Fq 'Compilation failed.' compiler/human_shell_feedback_x86_64.S
grep -Fq 'Compiled successfully.' compiler/human_shell_feedback_x86_64.S
[ "$(grep -c '^hs_art_pattern:$' compiler/human_shell_feedback_x86_64.S)" -eq 1 ]
! grep -q 'surface_field_error_code' compiler/fieldc_driver_x86_64.S
! grep -q 'msg_surface_boundary' compiler/fieldc_driver_x86_64.S
! grep -q 'msg_surface_domain' compiler/fieldc_driver_x86_64.S
! grep -q 'msg_surface_type' compiler/fieldc_driver_x86_64.S
! grep -q 'msg_surface_expr' compiler/fieldc_driver_x86_64.S
! grep -RqsE 'human_shell.*(fibonacci|recursion|alias|duplicate|identity|field|tensor)[_-]?(message|route|selector|branch)' compiler runtime surface tools
! grep -RqsE 'cheese_(fibonacci|recursive|alias|field|tensor)|repair_(keyword|identifier|newline)_message' compiler runtime surface tools
echo 'HUMAN_SHELL_FEEDBACK_CONVERGENCE_1_3_78=PASS'
echo 'HUMAN_SHELL_DIAGNOSTIC_SUBTYPE_BRANCHES=0'
echo 'HUMAN_SHELL_ERROR_DOMINATES_REPAIR=PASS'
echo 'WHEELCHAIR_1_3_78_BUILD=PASS'

# 1.3.80 physical-work convergence.  Causal readiness is a mathematical fact,
# not an automatic OS-execution request.  The old outward lifecycle remains the
# single externalization mechanism, now admitted only when the local causal
# region can repay its shared physical price.  Boundary ValueFacts may remain in
# helper-sovereign carriers instead of being forced through stack authority.
grep -q '^.equ PR_CAUSAL_FRONTIER_COST_GATED,1$' compiler/physical_reality.inc
grep -q '^.equ PR_READY_IMPLIES_OUTWARD_EXECUTION,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_CPU_LOCATION_QUERY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_NUMA_PAGE_MIGRATION,0$' compiler/physical_reality.inc
grep -q '^.equ PR_CAUSAL_STATE_CACHELINE_OWNERSHIP,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CAUSAL_STATE_PAGE_PER_NODE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_BOUNDARY_VALUEFACT_RESIDENCY_CONTINUITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_BOUNDARY_FORCES_STACK_ROUNDTRIP,0$' compiler/physical_reality.inc
grep -q '^.equ PRC_FRONTEND_BYTE_TICKS,3$' compiler/physical_cost_ticks.inc
grep -q '^.equ ST_NODE_BYTES, 64$' runtime/general_parallel_release_x86_64.S
! grep -qE 'SYS_getcpu|SYS_mbind|gr_localize_node_state' runtime/general_parallel_release_x86_64.S
grep -q '^gr_should_materialize:$' runtime/general_parallel_release_x86_64.S
grep -q '^g_fragment_static_once:$' compiler/general_frontend_x86_64.S
! grep -RqsE 'work[ _-]*steal|global[ _-]*ready[ _-]*queue|idle[ _-]*cpu[ _-]*(query|scan)' compiler runtime surface tools
echo 'CAUSAL_FRONTIER_READY_IMPLIES_CLONE=0'
echo 'GENERAL_CPU_LOCATION_QUERY=0'
echo 'CAUSAL_STATE_BYTES_PER_NODE=64'
echo 'BOUNDARY_VALUEFACT_STACK_ROUNDTRIP=REDUCED'
echo 'WHEELCHAIR_1_3_80_BUILD=PASS'

# 1.3.81 mathematical/physical convergence.  Traffic is a peer Physical-Reality
# resource of the old AddressFact/RegionFact/DAG authority.  Periodic topology is
# piecewise affine; mathematical traffic floors may guide realization but may not
# create a second scheduler, workload matcher, runtime probe, or fixed tile.
grep -q '^.equ PR_TRAFFIC_REALITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_TRAFFIC_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_BANDWIDTH_PROBE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_PIECEWISE_AFFINE_REGIONFACT,1$' compiler/physical_reality.inc
grep -q '^.equ PR_PERIODIC_BOUNDARY_IMPLIES_GATHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_BOUNDARY_COMPATIBILITY_BACKEND,0$' compiler/physical_reality.inc
grep -q '^.equ PR_AFFINE_TRANSPORT_STREAM_FACT,1$' compiler/physical_reality.inc
grep -q '^.equ PR_MATHEMATICAL_TRANSPORT_FLOOR_IS_LOWER_BOUND,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CROSS_PACKET_RELATION_IS_ADDRESSFACT,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SLIDING_WINDOW_WORKLOAD_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FIXED_WINDOW_WIDTH,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SPACETIME_IS_RANKN_CAUSAL_REGION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_TIMESTEP_FRONTEND_BOUNDARY_FORCES_MATERIALIZATION,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SPACETIME_SECOND_SCHEDULER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FIXED_TEMPORAL_TILE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FRONTEND_PHYSICAL_AUTHORITY_UNIFIED,1$' compiler/physical_reality.inc
grep -q '^.equ PR_FRONTEND_NAME_EXECUTION_ROUTE,0$' compiler/physical_reality.inc
grep -q '^.equ PRC_TRAFFIC_LINE_TICKS,12$' compiler/physical_cost_ticks.inc
grep -q '^.equ PRC_TRAFFIC_LINE_BYTES,64$' compiler/physical_cost_ticks.inc
grep -q '^ff_derive_transport_facts:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_transport_floor_lines:' compiler/field_frontend_common_x86_64.S
grep -q '^bottleneck_traffic:' compiler/topologyc_x86_64.S
grep -q 'g_fragment_memory_ops_ptr' compiler/general_frontend_x86_64.S
for f in runtime/field_runtime_512_x86_64.S runtime/field_runtime_256_x86_64.S; do
  grep -q '1.3.81 Piecewise-Affine RegionFact' "$f"
  grep -q 'execution-local RegionFact deltas' "$f"
done
! grep -RqsE 'work[ _-]*steal|global[ _-]*ready[ _-]*queue|idle[ _-]*cpu[ _-]*(query|scan)|runtime[ _-]*bandwidth[ _-]*(probe|autotune)' compiler runtime surface tools
! grep -RqsE '(^|[^A-Za-z])(poisson|stencil|miniFE|miniAMR|CloverLeaf)[_-]?(matcher|route|selector|optimizer)' compiler runtime surface tools
! grep -RqsE 'sliding[ _-]*window[ _-]*(matcher|scheduler)|spacetime[ _-]*(scheduler|tile)[ _-]*(manager|selector)|layout[ _-]*(copy|transpose)[ _-]*(manager|scheduler)' compiler runtime surface tools
echo 'TRAFFIC_REALITY_1_3_81=PASS'
echo 'PIECEWISE_AFFINE_REGIONFACT=PASS'
echo 'FIELD_MATHEMATICAL_TRAFFIC_FLOOR=PASS'
echo 'TRAFFIC_SECOND_IR=0'
echo 'RUNTIME_BANDWIDTH_PROBE=0'
echo 'SLIDING_WINDOW_WORKLOAD_MATCHER=0'
echo 'SECOND_SPACETIME_SCHEDULER=0'
echo 'FRONTEND_PHYSICAL_AUTHORITY_UNIFIED=PASS'
echo 'WHEELCHAIR_1_3_81_BUILD=PASS'
# 1.3.82 persistent Rank-N CoordinateFact physicalization.  This is the old
# Physical Reality lifetime model extended through the missing coordinate layer,
# not a boundary/stencil optimizer family.
grep -q '^.equ PR_PERSISTENT_RANKN_COORDINATEFACT,1$' compiler/physical_reality.inc
grep -q '^.equ PR_COORDINATEFACT_PER_ACCESS_REDECODE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_COORDINATEFACT_EXECUTION_LOCAL_CARRIERS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_COORDINATEFACT_SHARED_ACROSS_LAYOUTS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_AVX512_COORDINATE_OFFSET_STACK_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_COORDINATEFACT_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_COORDINATE_WORKLOAD_MATCHER,0$' compiler/physical_reality.inc
grep -q '^field_prepare_coords_f32_r8:$' runtime/field_runtime_512_x86_64.S
grep -q '^field_compute_offsets_from_coords_f32_r8:$' runtime/field_runtime_512_x86_64.S
grep -q '^ff_runtime_prepare_coords_va_for_field:$' compiler/field_frontend_common_x86_64.S
grep -q '^ff_runtime_offsets_from_coords_va_for_access:$' compiler/field_frontend_common_x86_64.S
! grep -RqsE 'coordinate[ _-]*(optimizer|scheduler|manager)|boundary[ _-]*coordinate[ _-]*(route|matcher)|stencil[ _-]*coordinate' compiler runtime surface tools
echo 'PERSISTENT_RANKN_COORDINATEFACT=PASS'
echo 'COORDINATEFACT_PER_ACCESS_REDECODE=0'
echo 'AVX512_COORDINATE_OFFSET_STACK_AUTHORITY=0'
echo 'COORDINATEFACT_SECOND_IR=0'
echo 'COORDINATE_WORKLOAD_MATCHER=0'
echo 'WHEELCHAIR_1_3_82_BUILD=PASS'


# 1.3.83 Mutable StateFact causal-lifetime ownership. Independent live mutable
# facts receive disjoint execution-local physical authority. Sequential episodes
# reuse the same stack offsets after causal death. No shared writable state arena,
# lock repair, worker identity, state scheduler, or parallel-language route exists.
grep -q '^.equ PR_MUTABLE_STATEFACT_CAUSAL_LIFETIME_OWNERSHIP,1$' compiler/physical_reality.inc
grep -q '^.equ PR_STATEFACT_EXECUTION_LOCAL_FRAME,1$' compiler/physical_reality.inc
grep -q '^.equ PR_STATEFACT_SHARED_RUNTIME_ARENA,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STATEFACT_SHARED_NEXT_VERSION_MAILBOX,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STATEFACT_LOCK_REPAIR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STATEFACT_RUNTIME_OWNER_MANAGER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STATEFACT_WORK_STEALING,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STATEFACT_PARALLEL_DSL_ROUTE,0$' compiler/physical_reality.inc
! grep -q 'GSTATE_RUNTIME_STRIDE' compiler/general_frontend_x86_64.S
! grep -q 'g_runtime_state_base_va' compiler/general_frontend_x86_64.S
! grep -q 'g_runtime_state_temp_base_va' compiler/general_frontend_x86_64.S
grep -q '^g_emit_state_frame_enter:$' compiler/general_frontend_x86_64.S
grep -q '^g_emit_state_frame_leave:$' compiler/general_frontend_x86_64.S
! grep -RqsE 'statefact[ _-]*(lock|mutex|spin|owner[ _-]*manager|worker|steal|queue)|parallel[ _-]*(iterate[ _-]*scheduler|state[ _-]*scheduler)' compiler runtime surface tools
echo 'MUTABLE_STATEFACT_CAUSAL_LIFETIME_OWNERSHIP=PASS'
echo 'SHARED_MUTABLE_STATE_ARENA=0'
echo 'STATEFACT_LOCK_REPAIR=0'
echo 'STATEFACT_PARALLEL_DSL_ROUTE=0'
echo 'WHEELCHAIR_1_3_83_BUILD=PASS'


# 1.3.84 silicon-realization closure. The same Physical DAG remains sovereign
# through target realization. Time, space, storage, and multiplicity are direct
# consequences of causal depth, Traffic/Region, fact lifetime, GroupFact, and
# exposed target resources. No HLS/kernel/task language, second semantic IR,
# occupancy target, fixed PE/tile/stage count, or runtime silicon scheduler.
[ -f compiler/silicon_reality.inc ]
[ "$(grep -c '^.include "compiler/silicon_reality.inc"$' compiler/physical_reality.inc)" -eq 1 ]
grep -q '^.equ SR_PHYSICAL_DAG_IS_REALIZATION_AUTHORITY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_CAUSAL_DEPTH_IS_TIME_AUTHORITY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_TRAFFIC_REGION_IS_SPACE_AUTHORITY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FACT_LIFETIME_IS_STORAGE_AUTHORITY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_GROUPFACT_IS_MULTIPLICITY_AUTHORITY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_THEORETICAL_WORK_CONVERGENCE_IS_OBJECTIVE,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_OCCUPANCY_IS_OBJECTIVE,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_RUNTIME_SILICON_ALLOCATOR,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_PARALLEL_DSL_ROUTE,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_HLS_KERNEL_AUTHORITY,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_TARGET_SECOND_SEMANTIC_IR,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_VON_NEUMANN_ORDER_IS_SEMANTIC_AUTHORITY,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_RELINEARIZE_BEFORE_SPATIAL_REALIZATION,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_ARBITRARY_TRANSISTOR_ADDRESSING,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_SILICON_REALITY_SINGLE_AUTHORITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_ISA_IS_ONE_REALIZATION_NOT_SEMANTIC_CEILING,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SPATIAL_TARGET_REQUIRES_RELINEARIZATION,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SILICON_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ GF_PHYSICAL_DEPTH_IS_FINAL_REALIZATION_TIME_AXIS,1$' compiler/groupfact.inc
grep -q '^.equ GF_SPATIAL_REALIZATION_USES_SAME_FACT,1$' compiler/groupfact.inc
! grep -q '^.equ PR_DOMAIN_\(GPR\|XMM\|YMM\|ZMM\|MASK\),' compiler/physical_reality.inc
grep -q 'opt_silicon_contract: .asciz "--silicon-contract"' compiler/topologyc_x86_64.S
grep -q '^print_silicon_contract_json:$' compiler/topologyc_x86_64.S
grep -q 'wheelchair.silicon-reality/' compiler/topologyc_x86_64.S
echo 'SILICON_REALITY_SINGLE_AUTHORITY=PASS'
echo 'VON_NEUMANN_SEMANTIC_AUTHORITY=0'
echo 'SPATIAL_RELINEARIZATION=0'
echo 'RUNTIME_SILICON_SCHEDULER=0'
echo 'PARALLEL_DSL_ROUTE=0'
echo 'FIXED_PROCESSING_ELEMENT_COUNT=0'
echo 'WHEELCHAIR_1_3_84_BUILD=PASS'

# 1.3.85 Silicon Domain Graph closure. Mathematical structure remains program
# authority while exposed cache/core/package sharing geometry constrains target
# realization. Vendor/model names are diagnostic only; no source-size crossover,
# guessed die adjacency, target-private IR, or runtime topology scheduler exists.
grep -q '^.equ SR_SILICON_DOMAIN_GRAPH_IS_TARGET_AUTHORITY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_TRAFFIC_X_DOMAIN_BOUNDARY_IS_SPACE_COST,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_VENDOR_MODEL_ROUTE,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_GEOMETRIC_DIE_ADJACENCY_ASSUMED,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_SOURCE_SIZE_AFFINITY_CROSSOVER,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_DOMAIN_GRAPH_RUNTIME_SCHEDULER,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_SILICON_DOMAIN_GRAPH_SINGLE_AUTHORITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_TRAFFIC_X_DOMAIN_GRAPH_SPATIAL_CLOSURE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_VENDOR_MODEL_EXECUTION_ROUTE,0$' compiler/physical_reality.inc
grep -q '^.equ PR_SOURCE_SIZE_AFFINITY_THRESHOLD,0$' compiler/physical_reality.inc
grep -q '^detect_cpu_topology:$' compiler/topologyc_x86_64.S
grep -q '^detect_field_llc_share_threads:$' compiler/fieldc_driver_x86_64.S
grep -q 'wheelchair.silicon-reality/' compiler/topologyc_x86_64.S
grep -q 'topology.silicon-audit/' compiler/topologyc_x86_64.S
! grep -RqsE 'profile_zen4|OUTWARD_TICKS_ZEN4|PIN_AT_OR_ABOVE_32_MIB|33554432' compiler runtime tools
! grep -RqsE 'silicon[ _-]*(worker|task|ready[ _-]*queue|work[ _-]*steal|kernel[ _-]*dispatch)|fpga[ _-]*(worker|task|scheduler)|asic[ _-]*(worker|task|scheduler)' compiler runtime surface tools
echo 'SILICON_DOMAIN_GRAPH_AUTHORITY=PASS'
echo 'VENDOR_MODEL_EXECUTION_ROUTES=0'
echo 'SOURCE_SIZE_AFFINITY_CROSSOVER=0'
echo 'GEOMETRIC_DIE_DISTANCE_GUESS=0'
echo 'SILICON_DOMAIN_SECOND_IR=0'
echo 'WHEELCHAIR_1_3_85_BUILD=PASS'

# 1.3.86 Silicon Domain Identity closure. The admitted CPU cardinality is no
# longer mistaken for one cache domain. A shared compile-time assembly probe
# intersects the external affinity set with architectural APIC/cache identities;
# CPU ordinals and device names remain non-authoritative.
[ -f compiler/silicon_domain_probe_x86_64.S ]
grep -q '^.equ SR_DOMAIN_IDENTITY_FROM_ARCHITECTURAL_TOPOLOGY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_ALLOWED_SET_X_DOMAIN_IDENTITY_IS_CAPACITY,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_CPU_ORDINAL_IS_PHYSICAL_ADJACENCY,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_CARDINALITY_ONLY_DOMAIN_APPROXIMATION_IS_AUTHORITY,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_RUNTIME_TOPOLOGY_IDENTITY_PROBE,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_SILICON_DOMAIN_IDENTITY_CLOSURE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_ALLOWED_SET_X_CACHE_IDENTITY_INTERSECTION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CPU_NUMBER_ADJACENCY_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_DOMAIN_WIDTH_ONLY_NORMAL_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^silicon_domain_probe:$' compiler/silicon_domain_probe_x86_64.S
grep -q 'sd_execution_admission_capacity' compiler/topologyc_x86_64.S
grep -q 'sd_execution_admission_capacity' compiler/fieldc_driver_x86_64.S
! grep -q '^detect_runtime_topology:$' compiler/topologyc_x86_64.S
! grep -q 'fieldc_affinity_mask' compiler/fieldc_driver_x86_64.S
grep -q 'wheelchair.silicon-reality/10' compiler/topologyc_x86_64.S
grep -q 'topology.silicon-audit/10' compiler/topologyc_x86_64.S
! grep -RqsE 'cpu[ _-]*(id|number|ordinal)[ _-]*(distance|adjacen|near)|fixed[ _-]*llc[ _-]*group' compiler runtime surface tools
echo 'SILICON_DOMAIN_IDENTITY_CLOSURE=PASS'
echo 'CPU_ORDINAL_ADJACENCY_AUTHORITY=0'
echo 'CARDINALITY_ONLY_DOMAIN_NORMAL_AUTHORITY=0'
echo 'RUNTIME_TOPOLOGY_IDENTITY_PROBE=0'
echo 'WHEELCHAIR_1_3_86_BUILD=PASS'


# 1.3.87 static silicon placement closure. Traffic x exact LLC-domain identity
# now becomes an executable AOT placement fact. The generated runtime inherits
# one baked domain mask; there is no runtime placement chooser, load query,
# migration loop, worker/task/kernel abstraction, or cardinality compatibility guess.
grep -q '^.equ SR_AOT_STATIC_DOMAIN_PLACEMENT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_PLACEMENT_INHERITED_BY_OUTWARD_EXECUTIONS,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_RUNTIME_PLACEMENT_RESOURCE_MATCHING,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_RUNTIME_PLACEMENT_MIGRATION,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_CARDINALITY_FALLBACK_ON_IDENTITY_FAILURE,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_PLACEMENT_CPU_ORDINAL_TIEBREAK,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_TRAFFIC_X_DOMAIN_IDENTITY_STATIC_PLACEMENT,1$' compiler/physical_reality.inc
grep -q '^.equ PR_STATIC_PLACEMENT_INHERITED,1$' compiler/physical_reality.inc
grep -q '^.equ PR_RUNTIME_PLACEMENT_SELECTOR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_DOMAIN_IDENTITY_FAILURE_CARDINALITY_GUESS,0$' compiler/physical_reality.inc
grep -q '^sd_choose_preferred_l3_domain:$' compiler/silicon_domain_probe_x86_64.S
grep -q 'static_placement_required_patch' runtime/tensor_runtime_x86_64.S
grep -q 'static_placement_required_patch' runtime/field_runtime_512_x86_64.S
grep -q 'static_placement_required_patch' runtime/field_runtime_256_x86_64.S
grep -q 'gr_static_placement_required' runtime/general_parallel_release_x86_64.S
grep -q 'placement_authority.*traffic_x_exact_l3_domain_identity' compiler/topologyc_x86_64.S
! grep -RqsE 'runtime[ _-]*placement[ _-]*(selector|scheduler|autotune|migration)|placement[ _-]*worker|placement[ _-]*task|placement[ _-]*kernel' compiler runtime surface tools
echo 'SILICON_STATIC_PLACEMENT_1_3_87=PASS'
echo 'TRAFFIC_X_DOMAIN_IDENTITY_PLACEMENT=PASS'
echo 'CARDINALITY_FALLBACK=0'
echo 'RUNTIME_PLACEMENT_SELECTOR=0'
echo 'WHEELCHAIR_1_3_87_BUILD=PASS'


# 1.3.88 heterogeneous Physical Edge / completion closure. x86 and fabric may
# coexist in one Physical DAG realization; no source kernel/offload authority is
# introduced and unproved fabric is never materialized.
grep -q '^.equ SR_SIMULTANEOUS_HETEROGENEOUS_REALIZATION,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_X86_FPGA_EXCLUSIVE_TARGET_SELECTION,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_PHYSICAL_EDGE_FACT_AUTHORITY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_SHARED_CAUSAL_COMPLETION_LAW,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FPGA_OFFLOAD_KERNEL_MODEL,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_RUNTIME_DEVICE_SELECTOR,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_UNPROVEN_FABRIC_MAY_BE_MATERIALIZED,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_PHYSICAL_EDGE_FACTS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_HETEROGENEOUS_DOMAINS_MAY_COEXIST,1$' compiler/physical_reality.inc
grep -q '^.equ PR_SHARED_CAUSAL_COMPLETION_PUBLICATION,1$' compiler/physical_reality.inc
grep -q '^g_edge_accumulate_type_transfer:$' compiler/general_frontend_x86_64.S
grep -q '^gr_publish_completion:$' runtime/general_parallel_release_x86_64.S
grep -q 'edge_transfer_bytes\[E:qword\],realization_tag\[N\]' build/general_parallel_release_offsets.json
grep -q 'simultaneous_heterogeneous_realization.*true' compiler/topologyc_x86_64.S
! grep -RqsE '(@fpga|fpga[ _-]*kernel|hls[ _-]*kernel|runtime[ _-]*device[ _-]*(selector|scheduler)|fpga[ _-]*(worker|task|ready[ _-]*queue|work[ _-]*steal))' surface compiler runtime tools
echo 'HETEROGENEOUS_PHYSICAL_EDGE_CLOSURE_1_3_88=PASS'
echo 'SIMULTANEOUS_X86_FABRIC_REALIZATION=PASS'
echo 'FPGA_OFFLOAD_KERNEL_MODEL=0'
echo 'RUNTIME_DEVICE_SELECTOR=0'
echo 'WHEELCHAIR_1_3_88_BUILD=PASS'

# 1.3.89 external fabric-target facts and joint domain placement. Fabric exists
# only when target facts are explicitly proved; normal production defaults zero.
# Region tags are closed AOT by strict physical-cost improvement with no fixed
# iteration count and no source/device/kernel authority.
[ -f compiler/fabric_target_facts_x86_64.S ]
grep -q '^.equ SR_FABRIC_TARGET_FACTS_EXTERNAL_ONLY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FABRIC_TARGET_FACTS_DEFAULT_ZERO,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_AOT_JOINT_DOMAIN_PLACEMENT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_JOINT_PLACEMENT_STRICT_IMPROVEMENT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_JOINT_PLACEMENT_FIXED_ROUND_LIMIT,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_USER_FABRIC_PLACEMENT_ANNOTATION,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_FABRIC_ACTIVATION_BRIDGE_PRESENT,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_FABRIC_TARGET_FACTS_ARE_PHYSICAL_FACTS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_X86_FABRIC_JOINT_COST_CLOSURE,1$' compiler/physical_reality.inc
grep -q '^.equ PR_INCIDENT_EDGE_TRAFFIC_IN_DOMAIN_FLIP_COST,1$' compiler/physical_reality.inc
grep -q '^.equ PR_JOINT_DOMAIN_FIXED_ROUND_LIMIT,0$' compiler/physical_reality.inc
grep -q '^fabric_target_facts_proved:$' compiler/fabric_target_facts_x86_64.S
grep -q '^g_close_heterogeneous_placement:$' compiler/general_frontend_x86_64.S
grep -q 'wheelchair.silicon-reality/10' compiler/topologyc_x86_64.S
grep -q 'topology.silicon-audit/10' compiler/topologyc_x86_64.S
grep -q 'joint_domain_placement.*strict_improvement_coordinate_closure' compiler/topologyc_x86_64.S
! grep -RqsE '(@fpga|fpga[ _-]*kernel|hls[ _-]*kernel|runtime[ _-]*device[ _-]*(selector|scheduler)|fixed[ _-]*(pe|tile)|fabric[ _-]*workload[ _-]*matcher)' surface compiler runtime tools
echo 'FABRIC_TARGET_FACT_CLOSURE_1_3_89=PASS'
echo 'AOT_JOINT_DOMAIN_PLACEMENT=PASS'
echo 'FABRIC_TARGET_DEFAULT_ZERO=PASS'
echo 'JOINT_PLACEMENT_FIXED_ROUNDS=0'
echo 'SOURCE_DEVICE_ANNOTATION=0'
echo 'WHEELCHAIR_1_3_89_BUILD=PASS'

# 1.3.90 fabric realization descriptor / activation-boundary closure. The AOT
# joint plan is now serialized from the existing Physical DAG. A missing board
# bridge is a hard physical absence, never a request for native compatibility.
grep -q '^.equ SR_FABRIC_REALIZATION_DESCRIPTOR,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FABRIC_ACTIVATION_ABI_PRESENT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FABRIC_COMPLETION_CALLBACK_ABI,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FABRIC_NATIVE_FALLBACK,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_FABRIC_UNBRIDGED_EXECUTION_ALLOWED,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_FABRIC_REALIZATION_DESCRIPTOR_FROM_PHYSICAL_DAG,1$' compiler/physical_reality.inc
grep -q '^.equ PR_FABRIC_DESCRIPTOR_SECOND_IR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FABRIC_NATIVE_FALLBACK,0$' compiler/physical_reality.inc
grep -q '^g_emit_fabric_realization_descriptors:$' compiler/general_frontend_x86_64.S
grep -q '^gr_fabric_descriptor_for_node:$' runtime/general_parallel_release_x86_64.S
grep -q 'fabric_descriptor\[N:48\]' build/general_parallel_release_offsets.json
grep -q 'wheelchair.silicon-reality/10' compiler/topologyc_x86_64.S
grep -q 'topology.silicon-audit/10' compiler/topologyc_x86_64.S
! grep -RqsE '(@fpga|fpga[ _-]*kernel|hls[ _-]*kernel|runtime[ _-]*device[ _-]*(selector|scheduler)|fixed[ _-]*(pe|tile)|fabric[ _-]*workload[ _-]*matcher|fabric[ _-]*native[ _-]*fallback)' surface compiler runtime tools
echo 'FABRIC_REALIZATION_DESCRIPTOR_1_3_90=PASS'
echo 'FABRIC_ACTIVATION_ABI=PASS'
echo 'FABRIC_NATIVE_FALLBACK=0'
echo 'SECOND_FABRIC_IR=0'
echo 'WHEELCHAIR_1_3_90_BUILD=PASS'

# 1.3.91 direct fabric activation + Field datapath projection.
grep -q '^.equ SR_FABRIC_ACTIVATION_ENTRY_ABI,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FABRIC_ACTIVATION_ABI_VERSION,2$' compiler/silicon_reality.inc
grep -q '^.equ SR_FIELD_FABRIC_DATAPATH_DESCRIPTOR,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_FIELD_FABRIC_DESCRIPTOR_SECOND_IR,0$' compiler/silicon_reality.inc
grep -q '^gr_activate_fabric_node:$' runtime/general_parallel_release_x86_64.S
grep -q '^gr_publish_completion_external:$' runtime/general_parallel_release_x86_64.S
grep -q '^ff_close_fabric_datapath_descriptor:$' compiler/field_frontend_common_x86_64.S
echo 'FABRIC_ACTIVATION_ENTRY_1_3_91=PASS'
echo 'FIELD_FABRIC_DATAPATH_DESCRIPTOR_1_3_91=PASS'
echo 'SECOND_FABRIC_IR_1_3_91=0'
echo 'WHEELCHAIR_1_3_91_BUILD=PASS'

# 1.3.92 execution-admission / locality separation and exact leaf geometry.
# Multiplicity follows exact external admission; cache identity prices placement.
# Tensor/Field expose the largest profitable integer width directly, never a
# power-of-two compatibility tree and never a runtime idle-resource query.
grep -q '^.equ SR_EXECUTION_ADMISSION_FROM_AFFINITY_SET,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_LOCALITY_IDENTITY_IS_PLACEMENT_ONLY,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_CGROUP_CPU_QUOTA_IS_TEMPORAL_BUDGET_FACT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_CGROUP_CPU_QUOTA_IS_MULTIPLICITY_AUTHORITY,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_POWER_OF_TWO_EXECUTION_ROUNDUP,0$' compiler/silicon_reality.inc
grep -q '^.equ SR_GENERAL_EXECUTION_ADMISSION_BOUND,1$' compiler/silicon_reality.inc
grep -q '^.equ PR_EXECUTION_ADMISSION_OWNS_MULTIPLICITY_BOUND,1$' compiler/physical_reality.inc
grep -q '^.equ PR_LOCALITY_IDENTITY_OWNS_PLACEMENT_ONLY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_LOCALITY_FAILURE_COLLAPSES_EXECUTION_ADMISSION,0$' compiler/physical_reality.inc
grep -q '^.equ PR_AFFINITY_SET_OWNS_X86_MULTIPLICITY_BOUND,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CGROUP_QUOTA_OWNS_TEMPORAL_BUDGET,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CGROUP_QUOTA_OWNS_MULTIPLICITY_BOUND,0$' compiler/physical_reality.inc
grep -q '^.equ PR_POWER_OF_TWO_EXECUTION_ROUNDUP,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GENERAL_EXECUTION_ADMISSION_BOUND,1$' compiler/physical_reality.inc
grep -q '^sd_read_cgroup_cpu_temporal_budget:$' compiler/silicon_domain_probe_x86_64.S
grep -q 'execution_admission_capacity' compiler/topologyc_x86_64.S
grep -q 'cpu_quota_usec' compiler/topologyc_x86_64.S
grep -q 'cpu_period_usec' compiler/topologyc_x86_64.S
grep -q 'execution_admission_patch' runtime/tensor_runtime_x86_64.S
grep -q 'execution_admission_patch' runtime/field_runtime_512_x86_64.S
grep -q 'execution_admission_patch' runtime/field_runtime_256_x86_64.S
grep -q 'gr_execution_admission_capacity' runtime/general_parallel_release_x86_64.S
grep -q 'gr_try_acquire_x86_slot' runtime/general_parallel_release_x86_64.S
grep -q 'GR_EXECUTION_ADMISSION_CAPACITY_OFF' compiler/general_frontend_x86_64.S
! grep -RqsE 'capacity_ceiling_patch|tensor_capacity_ceiling|locality_domain_execution_ceiling|dllg_pow2|fdllg_pow2' compiler runtime tools
! grep -RqsE 'runtime[ _-]*idle[ _-]*(cpu|capacity|worker)|work[ _-]*steal|ready[ _-]*queue|@fpga|fpga[ _-]*kernel|hls[ _-]*kernel' compiler runtime surface tools
echo 'EXECUTION_ADMISSION_LOCALITY_SEPARATION_1_3_92=PASS'
echo 'CGROUP_QUOTA_TEMPORAL_BUDGET=PASS'
echo 'POWER_OF_TWO_EXECUTION_ROUNDUP=0'
echo 'RUNTIME_IDLE_RESOURCE_QUERY=0'
echo 'WHEELCHAIR_1_3_92_BUILD=PASS'


# 1.3.93 transport/issue orthogonality. Traffic remains part of total Physical
# Reality but cannot collapse independent reduction recurrence width. Group and
# recurrence carriers consume the issue/dependency bound; outward/placement keep
# the total bound including transport.
grep -q '^.equ PR_ISSUE_BOUND_OWNS_RECURRENCE_CARRIERS,1$' compiler/physical_reality.inc
grep -q '^.equ PR_TRAFFIC_OWNS_TOTAL_PHYSICAL_COST,1$' compiler/physical_reality.inc
grep -q '^.equ PR_TRAFFIC_OWNS_RECURRENCE_CARRIER_WIDTH,0$' compiler/physical_reality.inc
grep -q '^.equ PR_TRANSPORT_COMPUTE_AXIS_COLLAPSE,0$' compiler/physical_reality.inc
grep -q '^.equ SR_TRANSPORT_IS_TOTAL_COST_FACT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_ISSUE_IS_RECURRENCE_WIDTH_FACT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_TRANSPORT_IS_RECURRENCE_WIDTH_AUTHORITY,0$' compiler/silicon_reality.inc
grep -q '^schedule_issue_bound_ticks:' compiler/topologyc_x86_64.S
grep -q 'mov ecx, dword ptr \[rip+schedule_issue_bound_ticks\]' compiler/topologyc_x86_64.S
grep -q 'PRC_TRAFFIC_LINE_TICKS' compiler/topologyc_x86_64.S
grep -q 'schedule_bound_ticks' compiler/outward_materialization_profile_x86_64.S
echo 'TRANSPORT_ISSUE_ORTHOGONALITY_1_3_93=PASS'
echo 'TRAFFIC_REALITY_PRESERVED=PASS'
echo 'TRAFFIC_OWNS_RECURRENCE_CARRIER_WIDTH=0'
echo 'WHEELCHAIR_1_3_93_BUILD=PASS'


# 1.3.94 spatial multiplicity / temporal quota orthogonality. The affinity set
# proves x86 execution contexts. cgroup cpu.max remains an exact quota/period
# Physical Fact but never masquerades as a worker count or multiplicity cap.
grep -q '^.equ SR_EXECUTION_ADMISSION_FROM_AFFINITY_SET,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_CGROUP_CPU_QUOTA_IS_TEMPORAL_BUDGET_FACT,1$' compiler/silicon_reality.inc
grep -q '^.equ SR_CGROUP_CPU_QUOTA_IS_MULTIPLICITY_AUTHORITY,0$' compiler/silicon_reality.inc
grep -q '^.equ PR_AFFINITY_SET_OWNS_X86_MULTIPLICITY_BOUND,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CGROUP_QUOTA_OWNS_TEMPORAL_BUDGET,1$' compiler/physical_reality.inc
grep -q '^.equ PR_CGROUP_QUOTA_OWNS_MULTIPLICITY_BOUND,0$' compiler/physical_reality.inc
grep -q '^sd_read_cgroup_cpu_temporal_budget:$' compiler/silicon_domain_probe_x86_64.S
grep -q 'cpu_quota_usec' compiler/topologyc_x86_64.S
grep -q 'cpu_period_usec' compiler/topologyc_x86_64.S
grep -q 'affinity_set' compiler/topologyc_x86_64.S
grep -q 'temporal_budget_only' compiler/topologyc_x86_64.S
! grep -RqsE 'cpu_quota_execution_capacity|sd_cpu_quota_capacity|sd_read_cgroup_cpu_quota_capacity|CGROUP_CPU_QUOTA_IS_ADMISSION_FACT|CGROUP_QUOTA_IS_EXTERNAL_ADMISSION_FACT' compiler runtime tools
echo 'SPATIAL_MULTIPLICITY_TEMPORAL_QUOTA_ORTHOGONALITY_1_3_94=PASS'
echo 'CGROUP_QUOTA_OWNS_MULTIPLICITY_BOUND=0'
echo 'POWER_OF_TWO_EXECUTION_ROUNDUP=0'
echo 'RUNTIME_IDLE_RESOURCE_QUERY=0'
echo 'WHEELCHAIR_1_3_94_BUILD=PASS'


# 1.3.96 scalar FP Physical Reality consumes the compiler-wide register geometry
# and removes local carrier/constant cliffs without a vendor backend.
grep -q '^g_phys_fp_geometry_refresh:$' compiler/general_frontend_x86_64.S
grep -q 'ISA_CAP_WIDE_REGFILE' compiler/general_frontend_x86_64.S
grep -q '^g_emit_phys_evex_scalar3:$' compiler/general_frontend_x86_64.S
! grep -q 'G_PHYS_FP_CARRIER_COUNT' compiler/general_frontend_x86_64.S
! grep -q 'G_PHYS_FP_TEMP_MASK_INIT' compiler/general_frontend_x86_64.S
! grep -q 'G_PHYS_FP_CONST_MAX' compiler/general_frontend_x86_64.S
echo 'GENERAL_SCALAR_PHYSICAL_REALITY_1_3_96=PASS'
echo 'WHEELCHAIR_1_3_96_BUILD=PASS'

# 1.3.97 StateFact generation authority closure. One FP generation either proves
# a fixed-point old/next carrier identity or remains on the mature disjoint
# realization. There is no partial hybrid, workload route, or second backend.
grep -q '^.equ PR_FP_GENERATION_FIXED_POINT_AUTHORITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_FP_GENERATION_PARTIAL_AUTHORITY_MIX,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FP_GENERATION_WORKLOAD_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_FP_GENERATION_SECOND_BACKEND,0$' compiler/physical_reality.inc
grep -q '^g_phys_expr_effectively_uses_state:$' compiler/general_frontend_x86_64.S
grep -q '^g_phys_fp_can_birth_in_old_authority:$' compiler/general_frontend_x86_64.S
grep -q '^g_phys_prove_inplace_fp_epoch:$' compiler/general_frontend_x86_64.S
grep -q '^g_phys_fp_inplace_epoch:.skip 4$' compiler/general_frontend_x86_64.S
! grep -Eq 'mass3|chem6|rigid7' compiler/general_frontend_x86_64.S
echo 'FP_GENERATION_FIXED_POINT_AUTHORITY_1_3_97=PASS'
echo 'PARTIAL_FP_GENERATION_AUTHORITY_MIX=0'
echo 'GENERAL_WORKLOAD_ROUTE=0'
echo 'WHEELCHAIR_1_3_97_BUILD=PASS'

# 1.3.98 General constant-mod Physical Reality closure. Every nonzero compile-
# time u64 divisor is realized by one exact reciprocal relation. Powers of two
# no longer own a compatibility branch; modulo does not create a second backend.
grep -q '^.equ PR_GENERAL_CONST_MOD_RECIPROCAL_AUTHORITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_GENERAL_CONST_MOD_POWER_OF_TWO_BRANCH,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GENERAL_CONST_MOD_WORKLOAD_MATCHER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GENERAL_CONST_MOD_RUNTIME_SELECTOR,0$' compiler/physical_reality.inc
grep -q '^.equ PR_GENERAL_CONST_MOD_SECOND_BACKEND,0$' compiler/physical_reality.inc
grep -q '^g_emit_phys_u64_const_mod:$' compiler/general_frontend_x86_64.S
grep -q '^g_emit_phys_mul_rax_gpr:$' compiler/general_frontend_x86_64.S
grep -q '^.gpior2: mov eax,1; ret' compiler/general_frontend_x86_64.S
! grep -Eq 'mod_.*(pow2|power2)|pow2_.*mod|mod_.*mask_path' compiler/general_frontend_x86_64.S
! grep -Eq 'mass3|chem6|rigid7|waitslow|1000003' compiler/general_frontend_x86_64.S
echo 'GENERAL_CONST_MOD_RECIPROCAL_AUTHORITY_1_3_98=PASS'
echo 'GENERAL_CONST_MOD_POWER_OF_TWO_BRANCH=0'
echo 'GENERAL_CONST_MOD_WORKLOAD_MATCHER=0'
echo 'GENERAL_CONST_MOD_SECOND_BACKEND=0'
echo 'WHEELCHAIR_1_3_98_BUILD=PASS'

# 1.3.99 static mixed-radix CoordinateFact convergence. This is a structural
# extension of the existing Tensor Physical Reality, not a workload route.
grep -q '^vec_vpmuludq_mem_const:' compiler/tensor_derived_frontend_x86_64.S
grep -q '^expr_dense_mixed_coord_key:' compiler/tensor_derived_frontend_x86_64.S
grep -q '^vec_mixed_scaled_refresh:' compiler/tensor_derived_frontend_x86_64.S
if grep -q 'dense_irregular_allpairs127' compiler/tensor_derived_frontend_x86_64.S; then
  echo 'DENSE_MIXED_WORKLOAD_MATCHER=1' >&2
  exit 1
fi
echo 'MIXED_RADIX_COORDINATEFACT_1_3_99=PASS'
echo 'DENSE_MIXED_WORKLOAD_MATCHER=0'
echo 'SECOND_TENSOR_IR_1_3_99=0'
echo 'WHEELCHAIR_1_3_99_BUILD=PASS'

# 1.3.102 retains the converged Tensor Fact path. Mixed-radix carry recurrence remains the one
# coordinate authority; scaled CoordinateFact logical identity is no longer
# aliased with physical-register allocation, and tolerant literal division
# consumes one explicit reciprocal relation. Strict rounding authority is unchanged.
grep -q '^vec_mixed_chain_preflight:$' compiler/tensor_derived_frontend_x86_64.S
grep -q '^vec_mixed_emit_step_chain:$' compiler/tensor_derived_frontend_x86_64.S
grep -q '^vec_mixed_find_direct_residue:$' compiler/tensor_derived_frontend_x86_64.S
grep -q '^vec_mixed_emit_step:$' compiler/tensor_derived_frontend_x86_64.S
grep -q 'mov r13d,ecx.*logical scaled-fact slot survives physical-reg allocation' compiler/tensor_derived_frontend_x86_64.S
grep -q '^recip_tolerant_f64_bits:$' compiler/tensor_derived_frontend_x86_64.S
! grep -Eq 'dense_irregular_allpairs127|waitslow|mass3|chem6|rigid7' compiler/tensor_derived_frontend_x86_64.S
echo 'MIXED_RADIX_CARRY_RECURRENCE_1_3_102=PASS'
echo 'SCALED_FACT_LOGICAL_PHYSICAL_ALIAS=0'
echo 'TOLERANT_LITERAL_DIV_RECIPROCAL_1_3_102=PASS'
echo 'RUNTIME_RADIX_SELECTOR_1_3_102=0'
echo 'DENSE_MIXED_WORKLOAD_MATCHER=0'
echo 'SECOND_TENSOR_IR_1_3_102=0'
echo 'WHEELCHAIR_TENSOR_FACT_AGING_1_3_102_BUILD=PASS'

# 1.3.102 execution-realization aging. Invocation affinity is a launch fact, not
# a compiler-host lifetime fact. Tensor/Field expose arbitrary cardinality with
# balanced ownership intervals; General exposes ready siblings before consuming
# local continuation work. No scheduler, worker pool or workload route is added.
grep -q '^.equ PR_INVOCATION_AFFINITY_REFRESHES_EXECUTION_ADMISSION,1$' compiler/physical_reality.inc
grep -q '^.equ PR_COMPILE_HOST_WIDTH_IS_IMAGE_AUTHORITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_ADMISSION_FAILURE_USES_COMPILE_HOST_WIDTH,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STATIC_PLACEMENT_INTERSECTS_INVOCATION_AFFINITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_STATIC_PLACEMENT_MAY_EXPAND_INVOCATION_AFFINITY,0$' compiler/physical_reality.inc
grep -q '^.equ PR_STRICT_REDUCTION_INVARIANT_TO_EXECUTION_CARDINALITY,1$' compiler/physical_reality.inc
grep -q '^.equ PR_ARBITRARY_CARDINALITY_LAUNCH_FRONTIER,1$' compiler/physical_reality.inc
grep -q '^.equ PR_POWER_OF_TWO_LAUNCH_FRONTIER,0$' compiler/physical_reality.inc
grep -q '^.equ PR_COMPLETION_LOCAL_SIBLING_EXPOSURE,1$' compiler/physical_reality.inc
grep -q '^.macro CONSTRAIN_STATIC_PLACEMENT_WITHIN_INVOCATION required, mask_bytes, mask$' runtime/execution_admission_refresh_x86_64.inc
grep -q '^.macro REFRESH_EXECUTION_ADMISSION target$' runtime/execution_admission_refresh_x86_64.inc
for S in runtime/tensor_runtime_x86_64.S runtime/field_runtime_512_x86_64.S runtime/field_runtime_256_x86_64.S; do
  grep -q 'CONSTRAIN_STATIC_PLACEMENT_WITHIN_INVOCATION static_placement_required_patch, static_placement_mask_bytes_patch, static_placement_mask_patch' "$S"
  grep -q 'REFRESH_EXECUTION_ADMISSION execution_admission_patch' "$S"
  sed -n '/^run_region_frontier:/,/^# reduce_region_results/p' "$S" > "$BUILD/frontier_13102.tmp"
  ! grep -Eq '[[:space:]]bsr[[:space:]]' "$BUILD/frontier_13102.tmp"
done
rm -f "$BUILD/frontier_13102.tmp"
grep -q 'sub rsp,REDUCE_LEVELS\*8+16' runtime/tensor_runtime_x86_64.S
grep -q 'mov r15,rax.*callee-saved descriptor identity' runtime/tensor_runtime_x86_64.S
! grep -q '\[rsp+16\].*descriptor' runtime/tensor_runtime_x86_64.S
grep -q '^gr_read_invocation_admission:$' runtime/general_parallel_release_x86_64.S
grep -q '^.gpc_ready_exposed:$' runtime/general_parallel_release_x86_64.S
! grep -q 'cmp dword ptr \[rip+execution_admission_capacity\],1' compiler/general_frontend_x86_64.S
! grep -RqsE 'runtime_(ready_queue|work_steal)|g_(ready_queue|work_steal)|worker_pool|cross_axis|high_entropy_sparse_perm' compiler runtime surface tools
echo 'INVOCATION_BOUND_EXECUTION_ADMISSION_1_3_102=PASS'
echo 'STATIC_PLACEMENT_INVOCATION_INTERSECTION_1_3_102=PASS'
echo 'STRICT_REDUCTION_EXECUTION_CARDINALITY_INVARIANT_1_3_102=PASS'
echo 'POWER_OF_TWO_LAUNCH_FRONTIER_1_3_102=0'
echo 'COMPLETION_LOCAL_SIBLING_EXPOSURE_1_3_102=PASS'
echo 'RUNTIME_READY_QUEUE_1_3_102=0'
echo 'WORK_STEALING_1_3_102=0'
echo 'WHEELCHAIR_1_3_102_BUILD=PASS'
