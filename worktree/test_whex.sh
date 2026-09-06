#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/whex

# 1) English, Simplified Chinese, Traditional Chinese, mixed spelling, and
# conservative English typo repair must erase to byte-identical canonical IR.
./surface/whex_surface.py equivalent \
  surface/whex_examples/heat_en.whex \
  surface/whex_examples/heat_zh_hans.whex \
  surface/whex_examples/heat_zh_hant.whex \
  surface/whex_examples/heat_mixed.whex \
  surface/whex_examples/heat_typos.whex > build/whex/equivalent.json
python3 - <<'PY'
import json
x=json.load(open('build/whex/equivalent.json'))
assert x['equivalent'] is True
assert [r['repair_count'] for r in x['sources'][:4]] == [0,0,0,0]
assert x['sources'][4]['repair_count'] >= 10
PY

# 2) Clean human WHEX must erase exactly to the frozen direct tensor IR.
./surface/whex_surface.py compile surface/whex_examples/heat_en.whex -o build/whex/from_whex.wh > build/whex/from_whex.json
cmp build/whex/from_whex.wh tests/whex/heat_direct_core.wh

# 3) Because topologyc receives byte-identical IR, the final native ELF must
# also be byte-identical.  This is the physical shell-erasure gate.
build/topologyc tests/whex/heat_direct_core.wh -o build/whex/direct_1 >/dev/null
./whexc surface/whex_examples/heat_en.whex -o build/whex/whex_1 >/dev/null
cmp build/whex/direct_1 build/whex/whex_1
[ "$(build/whex/whex_1 4)" = 'checksum_bits=0x3ff1c80000000000' ]

# 4) 4-executor path and typo-repaired source retain the same semantics.
./whexc surface/whex_examples/heat_en.whex -o build/whex/whex_4 --executors 4 >/dev/null
./whexc surface/whex_examples/heat_typos.whex -o build/whex/typo_4 --executors 4 > build/whex/typo_4.json
[ "$(build/whex/whex_4 100000)" = 'checksum_bits=0x40f24c3640000000' ]
[ "$(build/whex/typo_4 100000)" = 'checksum_bits=0x40f24c3640000000' ]

# 5) Strict WHEX path remains valid and does not require tolerant FP.
./whexc tests/whex/topology_showcase.whex -o build/whex/strict >/dev/null
[ "$(build/whex/strict 4)" = 'checksum_bits=0xc000000000000000' ]

# 6) Extensions are semantic gates, not aliases.  .wh and .whex are mutually
# incompatible at the human-shell entry points.
if ./whexc surface/examples/auto_repair_clean.wh -o build/whex/should_not_exist >/dev/null 2>&1; then
  echo '.wh was incorrectly accepted by WHEX' >&2; exit 1
fi
if ./wheelchairc surface/whex_examples/heat_en.whex -o build/whex/should_not_exist2 >/dev/null 2>&1; then
  echo '.whex was incorrectly accepted by WH' >&2; exit 1
fi

# 7) Formatter changes keyword spelling only; semantics remain identical.
./surface/whex_surface.py format surface/whex_examples/heat_zh_hant.whex --language en > build/whex/formatted_en.whex
./surface/whex_surface.py equivalent surface/whex_examples/heat_en.whex build/whex/formatted_en.whex >/dev/null

# 8) WHEX-generated executable remains sovereign static native ELF.
readelf -d build/whex/whex_4 2>&1 | grep -q 'There is no dynamic section'

echo 'WHEX_SURFACE_ERASURE=PASS'
echo 'WHEX_CANONICAL_IR_IDENTICAL=PASS'
echo 'WHEX_MACHINE_CODE_IDENTICAL=PASS'
echo 'WHEX_MULTILINGUAL=PASS'
echo 'WHEX_AUTO_REPAIR=PASS'
echo 'WHEX_EXTENSION_ISOLATION=PASS'
