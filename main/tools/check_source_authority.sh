#!/bin/sh
set -eu
# The build already assembles/links every dependency. These checks constrain
# ownership, language surface and authority rather than historical comments.
if grep -Rqs --exclude=check_source_authority.sh 'devtrash/' compiler runtime surface tools; then
  echo 'Production dependency refers to discarded sources' >&2; exit 1
fi
if grep -RqsE '^[[:space:]]*[A-Za-z_]*(benchmark|workload)[A-Za-z_]*(matcher|route)[A-Za-z_]*:' compiler runtime; then
  echo 'Workload-specific source selector is forbidden' >&2; exit 1
fi
[ "$(grep -Rhl '^physical_decimal_bits:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^physical_encode_rrr:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^node_parse_f64_bits:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^node_parse_f32_bits:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro PHYSICAL_SINCOS ' compiler | wc -l)" -eq 1 ]
if grep -qs '\.sesa_expand_recipe\|\.smcos_expand_recipe' compiler/surface_lowerer_x86_64.S; then
  echo 'Private frontend sin/cos recipe is forbidden' >&2; exit 1
fi
# Width is a property of the common carrier, not a new surface construct.
! grep -q '^synthesize_group_fact:' compiler/field_parser_link_stubs_x86_64.S

[ "$(grep -Rhl '^physical_encode_simd_rsp:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^physical_value_expr_equal:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro TMC_functions' compiler | wc -l)" -eq 1 ]

[ "$(grep -Rhl '^physical_input_range_parse:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro INPUT_RANGE_RELATION' runtime | wc -l)" -eq 1 ]

[ "$(grep -Rhl '^.macro TCC_functions' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro TFC_completed_code_stage' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro TFP_vec_emit_const_load_index' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro TFP_01_vec_emit_init_const' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^physical_math_projection_peer:' compiler | wc -l)" -eq 1 ]

[ "$(grep -Rhl '^physical_plan_resolve:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^physical_u64_division_fact:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^g_emit_phys_u64_const_divmod:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^g_emit_phys_gpr_literal:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^g_emit_phys_gpr_cmov:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro FP_U64_PAYLOAD ' compiler | wc -l)" -eq 1 ]
! grep -q '^\.gpcsef_pick:\|^\.gpcf_slot:\|^\.t_select_persistent_pick:\|^\.farl_pick_unified:' compiler/general_frontend_x86_64.S compiler/tensor_frontend_x86_64.S compiler/field_frontend_common_x86_64.S

[ "$(grep -Rhl '^.macro FLOAT_TYPE_PRECISION ' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro FRC_run_region_frontier_and_reduce' runtime | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro FRC_print_checksum' runtime | wc -l)" -eq 1 ]
! grep -q 'OP_ITOF32\|"itof32"' compiler/field_frontend_common_x86_64.S
! grep -q 'cmp .*RPF_PREC.*rpfac_bad\|cmp .*RPF_PREC.*rpfm_bad\|cmp .*RPF_PREC.*rpfd2_bad\|rpfcmp_bad:' runtime/rankn_precision_physical_x86_64.inc

[ "$(grep -Rhl '^.macro TFC_emit_tensor_image$' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro TFC_tensor_prepare_binding_arena$' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^.macro TFC_vec_vcvtuqq2pd_synth$' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^physical_input_range_sign:' compiler | wc -l)" -eq 1 ]
[ "$(grep -Rhl '^tensor_support_analyze_root:' compiler | wc -l)" -eq 1 ]
! grep -Rq '^.macro TFP_.*_vec_vcvtqq2pd_synth$\|^vec_vcvtqq2pd:' compiler
