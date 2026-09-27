#!/bin/sh
set -eu
[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || { echo 'usage: generate_general_parallel_release_offsets.sh ELF BIN OUT_JSON [OUT_INC]' >&2; exit 64; }
ELF=$1
BIN=$2
OUT=$3
INC=${4:-}
need='gr_release_base gr_publish_completion gr_publish_completion_external gr_node_count gr_edge_count gr_fabric_region_count gr_fabric_activation_bridge_present gr_fabric_activation_abi_version gr_fabric_activation_entry gr_fabric_descriptor_bytes gr_fabric_descriptor_for_node gr_meta_fabric_descriptor_ptr gr_outward_materialization_ticks gr_execution_admission_capacity gr_static_placement_required gr_static_placement_mask_bytes gr_static_placement_mask gr_template_end'
value() {
  name=$1
  v=$(nm -n "$ELF" | awk -v n="$name" '$3==n {print $1; exit}')
  [ -n "$v" ] || { echo "missing blind-release symbol: $name" >&2; exit 1; }
  printf '%d' "$((0x$v))"
}
BASE=$(value gr_release_base)
[ "$BASE" -eq 0 ] || { echo "gr_release_base must link at offset zero, got $BASE" >&2; exit 1; }
END=$(value gr_template_end)
PUBLISH=$(value gr_publish_completion)
PUBLISH_EXTERNAL=$(value gr_publish_completion_external)
SIZE=$(wc -c < "$BIN" | tr -d ' ')
[ "$SIZE" -eq "$END" ] || { echo "raw template size $SIZE != gr_template_end $END" >&2; exit 1; }
NODE=$(value gr_node_count)
EDGE=$(value gr_edge_count)
FABRIC_COUNT=$(value gr_fabric_region_count)
FABRIC_BRIDGE=$(value gr_fabric_activation_bridge_present)
FABRIC_ABI=$(value gr_fabric_activation_abi_version)
FABRIC_ENTRY=$(value gr_fabric_activation_entry)
FABRIC_DESC_BYTES=$(value gr_fabric_descriptor_bytes)
FABRIC_DESC_FOR_NODE=$(value gr_fabric_descriptor_for_node)
FABRIC_DESC_PTR=$(value gr_meta_fabric_descriptor_ptr)
OUTWARD=$(value gr_outward_materialization_ticks)
ADMISSION=$(value gr_execution_admission_capacity)
PLACE_REQUIRED=$(value gr_static_placement_required)
PLACE_BYTES=$(value gr_static_placement_mask_bytes)
PLACE_MASK=$(value gr_static_placement_mask)
cat > "$OUT" <<EOF
{
  "format": "wheelchair.general_parallel_release_offsets/1",
  "graph_capacity": "structural",
  "offsets": {
    "gr_edge_count": $EDGE,
    "gr_node_count": $NODE,
    "gr_fabric_region_count": $FABRIC_COUNT,
    "gr_fabric_activation_bridge_present": $FABRIC_BRIDGE,
    "gr_fabric_activation_abi_version": $FABRIC_ABI,
    "gr_fabric_activation_entry": $FABRIC_ENTRY,
    "gr_fabric_descriptor_bytes": $FABRIC_DESC_BYTES,
    "gr_fabric_descriptor_for_node": $FABRIC_DESC_FOR_NODE,
    "gr_meta_fabric_descriptor_ptr": $FABRIC_DESC_PTR,
    "gr_publish_completion": $PUBLISH,
    "gr_publish_completion_external": $PUBLISH_EXTERNAL,
    "gr_outward_materialization_ticks": $OUTWARD,
    "gr_execution_admission_capacity": $ADMISSION,
    "gr_static_placement_required": $PLACE_REQUIRED,
    "gr_static_placement_mask_bytes": $PLACE_BYTES,
    "gr_static_placement_mask": $PLACE_MASK,
    "gr_release_base": 0,
    "gr_template_end": $END
  },
  "metadata_layout": "indegree[N],first_out[N],entry_offsets[N],work_ticks[N],edge_v[E],next_edge[E],edge_transfer_bytes[E:qword],realization_tag[N],fabric_descriptor[N:48]",
  "template_size": $SIZE
}
EOF

if [ -n "$INC" ]; then
cat > "$INC" <<EOF
.equ GR_NODE_COUNT_OFF, $NODE
.equ GR_EDGE_COUNT_OFF, $EDGE
.equ GR_FABRIC_REGION_COUNT_OFF, $FABRIC_COUNT
.equ GR_FABRIC_ACTIVATION_BRIDGE_PRESENT_OFF, $FABRIC_BRIDGE
.equ GR_FABRIC_ACTIVATION_ABI_VERSION_OFF, $FABRIC_ABI
.equ GR_FABRIC_ACTIVATION_ENTRY_OFF, $FABRIC_ENTRY
.equ GR_FABRIC_DESCRIPTOR_BYTES_OFF, $FABRIC_DESC_BYTES
.equ GR_FABRIC_DESCRIPTOR_FOR_NODE_OFF, $FABRIC_DESC_FOR_NODE
.equ GR_META_FABRIC_DESCRIPTOR_PTR_OFF, $FABRIC_DESC_PTR
.equ GR_PUBLISH_COMPLETION_OFF, $PUBLISH
.equ GR_PUBLISH_COMPLETION_EXTERNAL_OFF, $PUBLISH_EXTERNAL
.equ GR_OUTWARD_MATERIALIZATION_TICKS_OFF, $OUTWARD
.equ GR_EXECUTION_ADMISSION_CAPACITY_OFF, $ADMISSION
.equ GR_STATIC_PLACEMENT_REQUIRED_OFF, $PLACE_REQUIRED
.equ GR_STATIC_PLACEMENT_MASK_BYTES_OFF, $PLACE_BYTES
.equ GR_STATIC_PLACEMENT_MASK_OFF, $PLACE_MASK
.equ GR_STATIC_PLACEMENT_MASK_SIZE, 128
.equ GR_TEMPLATE_SIZE, $SIZE
EOF
fi
echo 'GENERAL_PARALLEL_RELEASE_OFFSETS=DERIVED_WITHOUT_PYTHON'
