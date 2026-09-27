#!/bin/sh
set -eu
BIN=${1:-build/general_runtime_template}
OUT=${2:-compiler/general_runtime_offsets.inc}
BASE=0x400000
sym() { nm -n "$BIN" | awk -v n="$1" '$3==n {print "0x" $1; exit}'; }
need() { v=$(sym "$1"); [ -n "$v" ] || { echo "missing symbol: $1" >&2; exit 1; }; printf '%s' "$v"; }
va_in_count=$(need input_count_patch)
va_out_count=$(need output_count_patch)
va_dynamic_arena_bytes=$(need dynamic_arena_bytes_patch)
va_trailer_file_offset=$(need program_trailer_file_offset_patch)
va_trailer_size=$(need program_trailer_size_patch)
va_code_rel_offset=$(need program_code_rel_offset_patch)
va_input_values_base=$(need input_values_base_patch)
va_input_aux_base=$(need input_aux_base_patch)
va_rankn_input_base=$(need rankn_input_base_patch)
va_rankn_input_end=$(need rankn_input_end_patch)
va_output_pages_base=$(need output_pages_base_patch)
va_output_aux_base=$(need output_aux_base_patch)
va_rankn_from_u64=$(need rankn_fp_from_u64)
va_rankn_from_i64=$(need rankn_fp_from_i64)
va_rankn_from_f64=$(need rankn_fp_from_f64_bits)
va_rankn_convert=$(need rankn_fp_convert)
va_rankn_to_f64=$(need rankn_fp_to_f64_bits)
va_rankn_add=$(need rankn_fp_add)
va_rankn_sub=$(need rankn_fp_sub)
va_rankn_mul=$(need rankn_fp_mul)
va_rankn_div=$(need rankn_fp_div)
va_rankn_neg=$(need rankn_fp_neg)
va_rankn_abs=$(need rankn_fp_abs)
va_rankn_cmp=$(need rankn_fp_cmp)
va_rankn_sqrt=$(need rankn_fp_sqrt)
va_rankn_exp=$(need rankn_fp_exp)
va_rankn_log=$(need rankn_fp_log)
va_rankn_sin=$(need rankn_fp_sin)
va_rankn_cos=$(need rankn_fp_cos)
va_rankn_affine_power=$(need rankn_affine_power_u64)
size=$(stat -c %s "$BIN")
to_off() { printf '0x%x' $(( $1 - BASE )); }
cat > "$OUT" <<EOT
.equ GENERAL_RUNTIME_SIZE, $size
.equ GENERAL_INPUT_COUNT_OFF, $(to_off "$va_in_count")
.equ GENERAL_OUTPUT_COUNT_OFF, $(to_off "$va_out_count")
.equ GENERAL_DYNAMIC_ARENA_BYTES_OFF, $(to_off "$va_dynamic_arena_bytes")
.equ GENERAL_PROGRAM_TRAILER_FILE_OFFSET_OFF, $(to_off "$va_trailer_file_offset")
.equ GENERAL_PROGRAM_TRAILER_SIZE_OFF, $(to_off "$va_trailer_size")
.equ GENERAL_PROGRAM_CODE_REL_OFFSET_OFF, $(to_off "$va_code_rel_offset")
.equ GENERAL_INPUT_VALUES_BASE_OFF, $(to_off "$va_input_values_base")
.equ GENERAL_INPUT_AUX_BASE_OFF, $(to_off "$va_input_aux_base")
.equ GENERAL_RANKN_INPUT_BASE_OFF, $(to_off "$va_rankn_input_base")
.equ GENERAL_RANKN_INPUT_END_OFF, $(to_off "$va_rankn_input_end")
.equ GENERAL_OUTPUT_PAGES_BASE_OFF, $(to_off "$va_output_pages_base")
.equ GENERAL_OUTPUT_AUX_BASE_OFF, $(to_off "$va_output_aux_base")
.equ GENERAL_RANKN_FP_FROM_U64_VA, $va_rankn_from_u64
.equ GENERAL_RANKN_FP_FROM_I64_VA, $va_rankn_from_i64
.equ GENERAL_RANKN_FP_FROM_F64_VA, $va_rankn_from_f64
.equ GENERAL_RANKN_FP_CONVERT_VA, $va_rankn_convert
.equ GENERAL_RANKN_FP_TO_F64_VA, $va_rankn_to_f64
.equ GENERAL_RANKN_FP_ADD_VA, $va_rankn_add
.equ GENERAL_RANKN_FP_SUB_VA, $va_rankn_sub
.equ GENERAL_RANKN_FP_MUL_VA, $va_rankn_mul
.equ GENERAL_RANKN_FP_DIV_VA, $va_rankn_div
.equ GENERAL_RANKN_FP_NEG_VA, $va_rankn_neg
.equ GENERAL_RANKN_FP_ABS_VA, $va_rankn_abs
.equ GENERAL_RANKN_FP_CMP_VA, $va_rankn_cmp
.equ GENERAL_RANKN_FP_SQRT_VA, $va_rankn_sqrt
.equ GENERAL_RANKN_FP_EXP_VA, $va_rankn_exp
.equ GENERAL_RANKN_FP_LOG_VA, $va_rankn_log
.equ GENERAL_RANKN_FP_SIN_VA, $va_rankn_sin
.equ GENERAL_RANKN_FP_COS_VA, $va_rankn_cos
.equ GENERAL_RANKN_AFFINE_POWER_U64_VA, $va_rankn_affine_power
EOT
