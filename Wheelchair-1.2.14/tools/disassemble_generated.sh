#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo "usage: $0 ELF" >&2
  exit 2
fi
ELF=$1
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INC="$ROOT/compiler/runtime_offsets.inc"
get_equ() {
  awk -v n="$1" '$1==".equ" && $2==n"," {print $3; exit}' "$INC"
}
OFF=$(get_equ RUNTIME_GENERATED_FILE_OFF)
VA=$(get_equ RUNTIME_GENERATED_VA)
[ -n "$OFF" ] && [ -n "$VA" ] || { echo "generated-segment offsets unavailable" >&2; exit 1; }
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT HUP INT TERM
dd if="$ELF" of="$TMP" bs=1 skip=$((OFF)) status=none
objdump -D -b binary -m i386:x86-64 -M intel --adjust-vma="$VA" "$TMP"
