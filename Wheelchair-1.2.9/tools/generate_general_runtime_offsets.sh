#!/bin/sh
set -eu
BIN=${1:-build/general_runtime_template}
OUT=${2:-compiler/general_runtime_offsets.inc}
BASE=0x400000
sym() { nm -n "$BIN" | awk -v n="$1" '$3==n {print "0x" $1; exit}'; }
need() { v=$(sym "$1"); [ -n "$v" ] || { echo "missing symbol: $1" >&2; exit 1; }; printf '%s' "$v"; }
va_program=$(need program_slot)
va_in_count=$(need input_count_patch)
va_out_count=$(need output_count_patch)
va_in_type=$(need input_type_patch)
va_out_type=$(need output_type_patch)
va_in_values=$(need input_values)
va_in_aux=$(need input_aux)
va_bind=$(need binding_values)
va_state=$(need state_values)
va_state_temp=$(need state_temp)
va_out_values=$(need output_values)
size=$(stat -c %s "$BIN")
to_off() { printf '0x%x' $(( $1 - BASE )); }
cat > "$OUT" <<EOT
.equ GENERAL_RUNTIME_SIZE, $size
.equ GENERAL_PROGRAM_OFF, $(to_off "$va_program")
.equ GENERAL_INPUT_COUNT_OFF, $(to_off "$va_in_count")
.equ GENERAL_OUTPUT_COUNT_OFF, $(to_off "$va_out_count")
.equ GENERAL_INPUT_TYPE_OFF, $(to_off "$va_in_type")
.equ GENERAL_OUTPUT_TYPE_OFF, $(to_off "$va_out_type")
.equ GENERAL_INPUT_VALUES_VA, $va_in_values
.equ GENERAL_INPUT_AUX_VA, $va_in_aux
.equ GENERAL_BINDING_VALUES_VA, $va_bind
.equ GENERAL_STATE_VALUES_VA, $va_state
.equ GENERAL_STATE_TEMP_VA, $va_state_temp
.equ GENERAL_OUTPUT_VALUES_VA, $va_out_values
EOT
