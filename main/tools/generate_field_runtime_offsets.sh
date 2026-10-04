#!/bin/sh
set -eu
BIN=$1
OUT=$2
BASE=0x400000
sym(){ nm -n "$BIN" | awk -v n="$1" '$3==n {print "0x"$1; exit}'; }
need(){ v=$(sym "$1"); [ -n "$v" ] || { echo "missing symbol: $1" >&2; exit 1; }; printf '%s' "$v"; }
to_off(){ printf '0x%x' $(( $1 - BASE )); }
va_vec=$(need field_eval_vec)
va_disp=$(need field_eval_vec_disp_patch)
va_end=$(need field_eval_vec_end)
va_admission=$(need execution_admission_patch)
va_place_required=$(need static_placement_required_patch)
va_place_bytes=$(need static_placement_mask_bytes_patch)
va_place_mask=$(need static_placement_mask_patch)
va_outward=$(need outward_materialization_ticks_patch)
va_chunk_work=$(need field_chunk_work_ticks_patch)
va_chunk_elements=$(need field_chunk_elements_patch)
va_fc=$(need field_count_patch)
va_ac=$(need access_spec_count_patch)
va_meta=$(need field_metadata_va_patch)
va_fabric_va=$(need field_fabric_datapath_va_patch)
va_fabric_bytes=$(need field_fabric_datapath_bytes_patch)
va_fabric_entry=$(need field_fabric_activation_entry_patch)
va_fabric_bridge=$(need field_fabric_activation_bridge_present_patch)
va_fabric_abi=$(need field_fabric_activation_abi_version_patch)
va_mask=$(need field_prepare_mask_f32)
va_offsets=$(need field_compute_offsets_f32)
va_store=$(need field_store_f32)
va_field_data=$(need g_field_data_ptr)
va_field_contig=$(need g_field_contig_ptr)
va_regular_run_end=$(need field_regular_run_end)
va_linear_delta=$(need g_spec_linear_delta_bytes_ptr)
va_iindex0=$(need field_iindex_0)
va_iindex1=$(need field_iindex_1)
va_iadd0=$(need field_iadd_const_0)
va_iadd1=$(need field_iadd_const_1)
va_isub0=$(need field_isub_const_0)
va_isub1=$(need field_isub_const_1)
va_imul0=$(need field_imul_const_0)
va_imul1=$(need field_imul_const_1)
va_idiv0=$(need field_idiv_const_0)
va_idiv1=$(need field_idiv_const_1)
va_imod0=$(need field_imod_const_0)
va_imod1=$(need field_imod_const_1)
va_itof0=$(need field_itof32_0)
va_itof1=$(need field_itof32_1)
va_gen=$(need generated_base)
gen_off_hex=$(objdump -h "$BIN" | awk '$2==".generated" {print "0x"$6; exit}')
gen_off=$((gen_off_hex))
phoff=$(readelf -h "$BIN" | awk -F: '/Start of program headers:/ {gsub(/^[ \t]+/,"",$2); split($2,a," "); print a[1]; exit}')
phentsize=$(readelf -h "$BIN" | awk -F: '/Size of program headers:/ {gsub(/^[ \t]+/,"",$2); split($2,a," "); print a[1]; exit}')
gen_ph=$((phoff + 2*phentsize))
cat > "$OUT" <<EOT
.equ FIELD_RUNTIME_EVAL_OFF, $(to_off "$va_vec")
.equ FIELD_RUNTIME_EVAL_DISP_OFF, $(to_off "$va_disp")
.equ FIELD_RUNTIME_EVAL_END_VA, $va_end
.equ FIELD_RUNTIME_EXECUTION_ADMISSION_OFF, $(to_off "$va_admission")
.equ FIELD_RUNTIME_STATIC_PLACEMENT_REQUIRED_OFF, $(to_off "$va_place_required")
.equ FIELD_RUNTIME_STATIC_PLACEMENT_MASK_BYTES_OFF, $(to_off "$va_place_bytes")
.equ FIELD_RUNTIME_STATIC_PLACEMENT_MASK_OFF, $(to_off "$va_place_mask")
.equ FIELD_RUNTIME_OUTWARD_MATERIALIZATION_TICKS_OFF, $(to_off "$va_outward")
.equ FIELD_RUNTIME_CHUNK_WORK_TICKS_OFF, $(to_off "$va_chunk_work")
.equ FIELD_RUNTIME_CHUNK_ELEMENTS_OFF, $(to_off "$va_chunk_elements")
.equ FIELD_RUNTIME_FIELD_COUNT_OFF, $(to_off "$va_fc")
.equ FIELD_RUNTIME_ACCESS_COUNT_OFF, $(to_off "$va_ac")
.equ FIELD_RUNTIME_METADATA_VA_OFF, $(to_off "$va_meta")
.equ FIELD_RUNTIME_FABRIC_DATAPATH_VA_OFF, $(to_off "$va_fabric_va")
.equ FIELD_RUNTIME_FABRIC_DATAPATH_BYTES_OFF, $(to_off "$va_fabric_bytes")
.equ FIELD_RUNTIME_FABRIC_ACTIVATION_ENTRY_OFF, $(to_off "$va_fabric_entry")
.equ FIELD_RUNTIME_FABRIC_BRIDGE_PRESENT_OFF, $(to_off "$va_fabric_bridge")
.equ FIELD_RUNTIME_FABRIC_ACTIVATION_ABI_OFF, $(to_off "$va_fabric_abi")
.equ FIELD_RUNTIME_MASK_VA, $va_mask
.equ FIELD_RUNTIME_OFFSETS_VA, $va_offsets
.equ FIELD_RUNTIME_STORE_VA, $va_store
.equ FIELD_RUNTIME_FIELD_DATA_PTR_VA, $va_field_data
.equ FIELD_RUNTIME_FIELD_CONTIG_PTR_VA, $va_field_contig
.equ FIELD_RUNTIME_REGULAR_RUN_END_VA, $va_regular_run_end
.equ FIELD_RUNTIME_LINEAR_DELTA_PTR_VA, $va_linear_delta
.equ FIELD_RUNTIME_IINDEX0_VA, $va_iindex0
.equ FIELD_RUNTIME_IINDEX1_VA, $va_iindex1
.equ FIELD_RUNTIME_IADD0_VA, $va_iadd0
.equ FIELD_RUNTIME_IADD1_VA, $va_iadd1
.equ FIELD_RUNTIME_ISUB0_VA, $va_isub0
.equ FIELD_RUNTIME_ISUB1_VA, $va_isub1
.equ FIELD_RUNTIME_IMUL0_VA, $va_imul0
.equ FIELD_RUNTIME_IMUL1_VA, $va_imul1
.equ FIELD_RUNTIME_IDIV0_VA, $va_idiv0
.equ FIELD_RUNTIME_IDIV1_VA, $va_idiv1
.equ FIELD_RUNTIME_IMOD0_VA, $va_imod0
.equ FIELD_RUNTIME_IMOD1_VA, $va_imod1
.equ FIELD_RUNTIME_ITOF0_VA, $va_itof0
.equ FIELD_RUNTIME_ITOF1_VA, $va_itof1
.equ FIELD_RUNTIME_GENERATED_FILE_OFF, 0x$(printf '%x' "$gen_off")
.equ FIELD_RUNTIME_GENERATED_VA, $va_gen
.equ FIELD_RUNTIME_GENERATED_FILESZ_PHDR_OFF, 0x$(printf '%x' $((gen_ph+32)))
.equ FIELD_RUNTIME_GENERATED_MEMSZ_PHDR_OFF, 0x$(printf '%x' $((gen_ph+40)))
.equ FIELD_RUNTIME_TEMPLATE_SIZE, 0x$(printf '%x' "$gen_off")
.equ FIELD_RUNTIME_ELF_SHOFF_OFF, 0x28
.equ FIELD_RUNTIME_ELF_SHENTSIZE_OFF, 0x3a
EOT
