#!/bin/sh
set -eu
[ "$#" -eq 3 ] || { echo 'usage: generate_general_parallel_release_offsets.sh ELF BIN OUT_JSON' >&2; exit 64; }
ELF=$1
BIN=$2
OUT=$3
need='gr_release_base gr_node_count gr_edge_count gr_cpu_width gr_indegree gr_first_out gr_edge_v gr_next_edge gr_entry_offsets gr_template_end'
value() {
  name=$1
  v=$(nm -n "$ELF" | awk -v n="$name" '$3==n {print $1; exit}')
  [ -n "$v" ] || { echo "missing blind-release symbol: $name" >&2; exit 1; }
  printf '%d' "$((0x$v))"
}
BASE=$(value gr_release_base)
[ "$BASE" -eq 0 ] || { echo "gr_release_base must link at offset zero, got $BASE" >&2; exit 1; }
END=$(value gr_template_end)
SIZE=$(wc -c < "$BIN" | tr -d ' ')
[ "$SIZE" -eq "$END" ] || { echo "raw template size $SIZE != gr_template_end $END" >&2; exit 1; }
NODE=$(value gr_node_count)
EDGE=$(value gr_edge_count)
CPU=$(value gr_cpu_width)
INDEG=$(value gr_indegree)
FIRST=$(value gr_first_out)
EV=$(value gr_edge_v)
NEXT=$(value gr_next_edge)
ENTRY=$(value gr_entry_offsets)
cat > "$OUT" <<EOF
{
  "format": "wheelchair.general_parallel_release_offsets/1",
  "max_cpu_width": 4,
  "max_edges": 1024,
  "max_nodes": 96,
  "offsets": {
    "gr_cpu_width": $CPU,
    "gr_edge_count": $EDGE,
    "gr_edge_v": $EV,
    "gr_entry_offsets": $ENTRY,
    "gr_first_out": $FIRST,
    "gr_indegree": $INDEG,
    "gr_next_edge": $NEXT,
    "gr_node_count": $NODE,
    "gr_release_base": 0,
    "gr_template_end": $END
  },
  "program_slot_capacity": 131072,
  "template_size": $SIZE
}
EOF
echo 'GENERAL_PARALLEL_RELEASE_OFFSETS=DERIVED_WITHOUT_PYTHON'
