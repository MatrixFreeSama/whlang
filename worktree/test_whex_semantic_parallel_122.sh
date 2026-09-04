#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/semantic122

# Derive the 1.2.2 semantic-invariant harness from the mature 1.2.1 harness.
# Only the historical physical limit is superseded: in 1.1.0/1.2.1 a genuinely
# used second axis had to reject because the realizer was Rank-1. 1.2.2 now
# proves and executes that topology natively. Every other semantic/parallel gate
# is retained byte-for-byte from the mature harness.
python3 - <<'PY'
from pathlib import Path
src=Path('test_whex_semantic_parallel_121.sh').read_text(encoding='utf-8')
start=src.index('# A genuinely used second axis must remain Rank-N')
end=src.index('# 5. Effectful regions', start)
replacement='''# 1.2.2 supersession: a genuinely used second axis remains Rank-N but is now\n# physically realized through the proof-gated Cartesian product domain. It must\n# still introduce no serial backedge and no scalar fallback.\npython3 surface/whex_surface.py plan tests/whex/rankn_axis_nonerasable.whex > build/semantic110/rankn_nonerasable.plan\npython3 surface/whex_surface.py native tests/whex/rankn_axis_nonerasable.whex -o build/semantic110/rankn_native --executors 4 >/dev/null\n[ "$(build/semantic110/rankn_native 4)" = 'checksum_bits=0x4048000000000000' ]\npython3 - <<'PYRANK2'\nimport json\np=json.load(open('build/semantic110/rankn_nonerasable.plan'))\nassert p['axis_algebra']['maximum_source_rank']==2\nassert p['axis_algebra']['rank_n_eliminations']==[]\nassert p['parallelism_contract']['rank_n_serial_inner_loop'] is False\nassert p['parallelism_contract']['rank_n_scalar_fallback'] is False\nassert p['serial_introduction_report']['new_serial_axis_loops']==0\nprint('WHEX_RANK_N_NATIVE_NO_FAKE_FLATTEN=PASS')\nPYRANK2\n\n'''
out=src[:start]+replacement+src[end:]
path=Path('build/semantic122/semantic_122.sh')
path.write_text(out,encoding='utf-8')
path.chmod(0o755)
PY
sh build/semantic122/semantic_122.sh

echo 'WHEX_GENERAL_TRUE_PARALLEL_SEMANTICS_1_2_2=PASS'
