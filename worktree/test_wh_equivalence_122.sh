#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_wh_equivalence_122_derived.$$"
trap 'rm -f "$TMP"' EXIT INT TERM

# Derive the mature 1.2.1 WH/WHEX gate while superseding only its whole-file
# freeze of whex_surface.py. 1.2.2 must edit that routing surface to admit
# proved native Rank-N. Unchanged semantic foundations stay byte-frozen, while
# the old curated canonical/native corpus remains the stronger compatibility
# authority for the changed surface.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_wh_equivalence_121.sh').read_text(encoding='utf-8')
start=src.index('# 0. WHEX human surfaces and canonical semantics remain byte-frozen to 1.2.0.')
end=src.index('# Curated canonical hashes remain frozen', start)
replacement=r'''# 0. 1.2.2 Rank-N intentionally extends the structural routing surface. The
# untouched human/general surface and semantic foundation remain byte-frozen;
# compatibility of the changed structural surface is proven below by the old
# curated canonical hashes and WH/WHEX native byte-equivalence corpus.
python3 - <<'PYFREEZE'
from pathlib import Path
import hashlib
want={
 'surface/wh_surface.py':'c2a2ce61b169de39d8bd4ff7de3e615ea71c86d25dbb64236b2c7ba5f2a59c09',
 'surface/whex_semantics.py':'32518611fad6079c91b68d67e11f09e902f8f86d62136532dac993e5929f2551',
}
for f,h in want.items():
    got=hashlib.sha256(Path(f).read_bytes()).hexdigest(); assert got==h,(f,got,h)
ws=Path('surface/whex_surface.py').read_text(encoding='utf-8')
hs=Path('surface/wh_structural.py').read_text(encoding='utf-8')
assert 'rank_n_product' in ws and 'rank_n_product' in hs
print('WHEX_1_2_0_UNCHANGED_SEMANTIC_FOUNDATION_FREEZE=PASS')
print('WHEX_1_2_2_RANK_N_SURFACE_EXTENSION_PRESENT=PASS')
PYFREEZE

'''
out=src[:start]+replacement+src[end:]
out=out.replace("echo 'WH_WHEX_SURFACE_EQUIVALENCE_1_2_1=PASS'",
                "echo 'WH_WHEX_LEGACY_SURFACE_EQUIVALENCE_ON_1_2_2=PASS'")
Path(sys.argv[1]).write_text(out,encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"

# New positive Rank-N peer proof: familiar WH and explicit WHEX must converge
# to the same native image for a genuinely non-erasable Rank-2 topology.
mkdir -p build/wh122
./wheelchairc tests/wh_equivalence/rank2_native_122.wh -o build/wh122/rank2.wh.elf --executors 4 >/dev/null
./whexc tests/whex/rank2_native_122.whex -o build/wh122/rank2.whex.elf --executors 4 >/dev/null
cmp build/wh122/rank2.wh.elf build/wh122/rank2.whex.elf
[ "$(build/wh122/rank2.wh.elf 4)" = 'checksum_bits=0x405e000000000000' ]
echo 'WH_WHEX_RANK2_NATIVE_BYTE_EQUIVALENCE_1_2_2=PASS'
echo 'WH_WHEX_SURFACE_EQUIVALENCE_1_2_2=PASS'
