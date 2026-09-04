#!/bin/sh
set -eu
BIN=${1:-build/tensor_runtime_template}
OUT=${2:-compiler/runtime_offsets.inc}
BASE=0x400000
sym() { nm -n "$BIN" | awk -v n="$1" '$3==n {print "0x" $1; exit}'; }
need() { v=$(sym "$1"); [ -n "$v" ] || { echo "missing symbol: $1" >&2; exit 1; }; printf '%s' "$v"; }
to_off() { printf '0x%x' $(( $1 - BASE )); }

va_eval=$(need eval_slot)
va_eval_disp=$(need eval_slot_disp_patch)
va_vec=$(need eval_vec4)
va_vec_disp=$(need eval_vec4_disp_patch)
va_init=$(need eval_vec_init)
va_init_disp=$(need eval_vec_init_disp_patch)
va_exec=$(need executor_count_patch)
va_width=$(need vector_width_patch)
va_carriers=$(need reduction_carriers_patch)
va_unroll=$(need unroll_count_patch)
va_comm=$(need communication_elimination_patch)
va_nmin=$(need n_min_patch)
va_nmax=$(need n_max_patch)
va_gen=$(need generated_base)

gen_off_hex=$(objdump -h "$BIN" | awk '$2==".generated" {print "0x"$6; exit}')
[ -n "$gen_off_hex" ] || { echo "missing .generated section" >&2; exit 1; }
gen_off=$((gen_off_hex))

# ELF64 PHDR table is fixed by the linker script: generated is PHDR index 2.
phoff=$(readelf -h "$BIN" | awk -F: '/Start of program headers:/ {gsub(/^[ \t]+/,"",$2); split($2,a," "); print a[1]; exit}')
phentsize=$(readelf -h "$BIN" | awk -F: '/Size of program headers:/ {gsub(/^[ \t]+/,"",$2); split($2,a," "); print a[1]; exit}')
[ -n "$phoff" ] && [ -n "$phentsize" ] || { echo "cannot read ELF PHDR geometry" >&2; exit 1; }
gen_ph=$((phoff + 2*phentsize))
gen_filesz_off=$((gen_ph + 32))
gen_memsz_off=$((gen_ph + 40))

cat > "$OUT" <<EOT
.equ RUNTIME_EVAL_OFF, $(to_off "$va_eval")
.equ RUNTIME_EVAL_DISP_OFF, $(to_off "$va_eval_disp")
.equ RUNTIME_VEC_OFF, $(to_off "$va_vec")
.equ RUNTIME_VEC_DISP_OFF, $(to_off "$va_vec_disp")
.equ RUNTIME_VEC_INIT_OFF, $(to_off "$va_init")
.equ RUNTIME_VEC_INIT_DISP_OFF, $(to_off "$va_init_disp")
.equ RUNTIME_EXECUTOR_OFF, $(to_off "$va_exec")
.equ RUNTIME_VECTOR_WIDTH_OFF, $(to_off "$va_width")
.equ RUNTIME_CARRIERS_OFF, $(to_off "$va_carriers")
.equ RUNTIME_UNROLL_OFF, $(to_off "$va_unroll")
.equ RUNTIME_COMM_ELIM_OFF, $(to_off "$va_comm")
.equ RUNTIME_NMIN_OFF, $(to_off "$va_nmin")
.equ RUNTIME_NMAX_OFF, $(to_off "$va_nmax")
.equ RUNTIME_GENERATED_FILE_OFF, 0x$(printf '%x' "$gen_off")
.equ RUNTIME_GENERATED_VA, $va_gen
.equ RUNTIME_GENERATED_FILESZ_PHDR_OFF, 0x$(printf '%x' "$gen_filesz_off")
.equ RUNTIME_GENERATED_MEMSZ_PHDR_OFF, 0x$(printf '%x' "$gen_memsz_off")
.equ RUNTIME_TEMPLATE_SIZE, 0x$(printf '%x' "$gen_off")
.equ RUNTIME_ELF_SHOFF_OFF, 0x28
.equ RUNTIME_ELF_SHENTSIZE_OFF, 0x3a
EOT
