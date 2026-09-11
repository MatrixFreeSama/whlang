#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/newton121

# Frontend-erasure witness: Python WHEX surface and direct canonical JSON must
# feed the handwritten topology compiler to byte-identical native images.
python3 surface/whex_surface.py compile tests/whex/newton_jv_mature_regression.whex -o build/newton121/core.wh >/dev/null
for e in 1 2 4; do
  ./whexc tests/whex/newton_jv_mature_regression.whex -o build/newton121/whex_$e --executors $e >/dev/null
  build/topologyc build/newton121/core.wh -o build/newton121/direct_$e --executors $e >/dev/null
  cmp build/newton121/whex_$e build/newton121/direct_$e
  [ "$(build/newton121/whex_$e 10000000)" = 'checksum_bits=0x40a1414a1c4e8000' ]
  [ "$(build/newton121/whex_$e 100000000)" = 'checksum_bits=0x40d591e5093fa000' ]
done
echo 'NEWTON_JV_FRONTEND_ERASURE=PASS'
echo 'NEWTON_JV_10M_100M_EXECUTOR_EQUIVALENCE=PASS'

# The performance restoration must remain a generic compiler transformation.
# The compiler itself may not mention this benchmark or its mathematical label.
python3 - <<'PY'
from pathlib import Path
src=(Path('compiler/tensor_frontend_x86_64.S').read_text()+Path('compiler/topologyc_x86_64.S').read_text()).lower()
for bad in ('newton_jv','newton','jacobian'):
    assert bad not in src,bad
print('NEWTON_JV_NO_WORKLOAD_DISPATCH=PASS')
PY

echo 'WHEX_NEWTON_JV_REGRESSION_1_2_1=PASS'
