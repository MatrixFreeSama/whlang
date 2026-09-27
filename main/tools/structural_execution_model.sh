#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
usage() {
  cat >&2 <<'USAGE'
usage:
  structural_execution_model.sh raw W S H P
  structural_execution_model.sh tensor ELF N P
  structural_execution_model.sh field512 ELF N P
  structural_execution_model.sh field256 ELF N P

The model is Wheelchair Structural Execution/1:
  speedup = W / (max(W/P, S) + H)
  ideal   = min(P, W/S)
W and S use the target Physical Reality tick domain. H is the weighted
critical-path realization overhead, not a resource-availability term.
USAGE
  exit 64
}
num() { case ${1:-} in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
ratio_milli() {
  n=$1; d=$2
  [ "$d" -gt 0 ] || { echo 0; return; }
  q=$((n/d)); r=$((n%d))
  echo $((q*1000 + (r*1000)/d))
}
ceil_div() { echo $(( ($1 + $2 - 1) / $2 )); }
qword_at() {
  f=$1; off=$2
  od -An -tu8 -j "$off" -N8 "$f" | tr -d '[:space:]'
}
inc_value() {
  f=$1; name=$2
  v=$(awk -v n="$name" '$1==".equ" && $2==n"," {print $3; exit}' "$f")
  [ -n "$v" ] || return 1
  echo $((v))
}
tree_depth() {
  n=$1
  d=0
  while [ "$n" -gt 1 ]; do
    n=$(( (n+1)/2 ))
    d=$((d+1))
  done
  echo "$d"
}
# Exact 1.3.18/1.3.19 profitability tree: if a node stays local, its whole
# subtree stays local. If outward is profitable, both children may independently
# expose further outward work. Return max outward lifecycle depth on one causal path.
outward_depth() {
  n=$1; work=$2; out=$3
  [ "$n" -gt 1 ] || { echo 0; return; }
  pow=1
  while [ $((pow*2)) -le "$n" ]; do pow=$((pow*2)); done
  [ "$pow" -ne "$n" ] || pow=$((pow/2))
  right=$((n-pow))
  right_work=$((right*work))
  [ "$right_work" -gt "$out" ] || { echo 0; return; }
  dl=$(outward_depth "$pow" "$work" "$out")
  dr=$(outward_depth "$right" "$work" "$out")
  [ "$dl" -ge "$dr" ] || dl=$dr
  echo $((dl+1))
}
print_model() {
  W=$1; S=$2; H=$3; P=$4; extra=${5:-}
  num "$W" && num "$S" && num "$H" && num "$P" || usage
  [ "$W" -gt 0 ] && [ "$S" -gt 0 ] && [ "$P" -gt 0 ] || usage
  wp=$(ceil_div "$W" "$P")
  core=$wp; [ "$S" -le "$core" ] || core=$S
  T=$((core+H))
  intrinsic=$(ratio_milli "$W" "$S")
  model_sp=$(ratio_milli "$W" "$T")
  ideal_sp=$intrinsic
  p_milli=$((P*1000)); [ "$ideal_sp" -le "$p_milli" ] || ideal_sp=$p_milli
  printf '{"format":"wheelchair.structural-execution/1","formula":"W/(max(W/P,S)+H)","W":%s,"S":%s,"H":%s,"P":%s,"intrinsic_parallelism_milli":%s,"ideal_speedup_milli":%s,"model_speedup_milli":%s%s}\n' \
    "$W" "$S" "$H" "$P" "$intrinsic" "$ideal_sp" "$model_sp" "$extra"
}
[ $# -ge 1 ] || usage
mode=$1; shift
case "$mode" in
  raw)
    [ $# -eq 4 ] || usage
    print_model "$1" "$2" "$3" "$4"
    ;;
  tensor|field512|field256)
    [ $# -eq 3 ] || usage
    elf=$1; N=$2; P=$3
    [ -f "$elf" ] || { echo "structural model: ELF not found: $elf" >&2; exit 66; }
    num "$N" && num "$P" || usage
    [ "$N" -gt 0 ] && [ "$P" -gt 0 ] || usage
    reduce_tick=6
    case "$mode" in
      tensor)
        inc="$ROOT/compiler/runtime_offsets.inc"
        out_off=$(inc_value "$inc" RUNTIME_OUTWARD_MATERIALIZATION_TICKS_OFF)
        work_off=$(inc_value "$inc" RUNTIME_CHUNK_WORK_TICKS_OFF)
        chunk_off=$(inc_value "$inc" RUNTIME_CHUNK_ELEMENTS_OFF)
        ;;
      field512)
        inc="$ROOT/build/field_runtime_512_offsets.inc"
        out_off=$(inc_value "$inc" FIELD_RUNTIME_OUTWARD_MATERIALIZATION_TICKS_OFF)
        work_off=$(inc_value "$inc" FIELD_RUNTIME_CHUNK_WORK_TICKS_OFF)
        chunk_off=$(inc_value "$inc" FIELD_RUNTIME_CHUNK_ELEMENTS_OFF)
        ;;
      field256)
        inc="$ROOT/build/field_runtime_256_offsets.inc"
        out_off=$(inc_value "$inc" FIELD_RUNTIME_OUTWARD_MATERIALIZATION_TICKS_OFF)
        work_off=$(inc_value "$inc" FIELD_RUNTIME_CHUNK_WORK_TICKS_OFF)
        chunk_off=$(inc_value "$inc" FIELD_RUNTIME_CHUNK_ELEMENTS_OFF)
        ;;
    esac
    [ -f "$inc" ] || { echo "structural model: build offsets missing; run ./build.sh" >&2; exit 69; }
    out=$(qword_at "$elf" "$out_off")
    work=$(qword_at "$elf" "$work_off")
    chunk=$(qword_at "$elf" "$chunk_off")
    num "$out" && num "$work" && num "$chunk" || { echo 'structural model: invalid AOT physical facts' >&2; exit 65; }
    [ "$work" -gt 0 ] && [ "$out" -gt 0 ] && [ "$chunk" -gt 0 ] || { echo 'structural model: zero physical fact' >&2; exit 65; }
    chunks=$(( (N + chunk - 1) / chunk ))
    depth=$(tree_depth "$chunks")
    # Necessary work: every leaf episode plus the canonical reduction edges.
    W=$((chunks*work + (chunks-1)*reduce_tick))
    # Causal span: one leaf episode plus one reduction edge per causal level.
    S=$((work + depth*reduce_tick))
    od=$(outward_depth "$chunks" "$work" "$out")
    H=$((od*out))
    extra=$(printf ',"mode":"%s","N":%s,"chunks":%s,"leaf_elements":%s,"chunk_work_ticks":%s,"reduction_edge_ticks":%s,"outward_materialization_ticks":%s,"causal_levels":%s,"outward_levels":%s' \
      "$mode" "$N" "$chunks" "$chunk" "$work" "$reduce_tick" "$out" "$depth" "$od")
    print_model "$W" "$S" "$H" "$P" "$extra"
    ;;
  *) usage;;
esac
