#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/operator1011
./whexc tests/whex/operator_subspace_cancel.whex -o build/operator1011/cancel_1 --executors 1 >/dev/null
./whexc tests/whex/operator_subspace_cancel.whex -o build/operator1011/cancel_4 --executors 4 >/dev/null
./whexc tests/whex/operator_subspace_strict.whex -o build/operator1011/strict_1 --executors 1 >/dev/null
./whexc tests/whex/operator_subspace_control.whex -o build/operator1011/control_1 --executors 1 >/dev/null

[ "$(build/operator1011/cancel_1 1024)" = 'checksum_bits=0x4097fc0000000000' ]
[ "$(build/operator1011/cancel_4 1024)" = 'checksum_bits=0x4097fc0000000000' ]
[ "$(build/operator1011/strict_1 1024)" = 'checksum_bits=0x4097fc0000000000' ]
[ "$(build/operator1011/control_1 1024)" = 'checksum_bits=0x40adfb0000000000' ]

python3 - <<'PY'
import random, struct, subprocess
bins={
    'tol1':'build/operator1011/cancel_1',
    'tol4':'build/operator1011/cancel_4',
    'strict':'build/operator1011/strict_1',
}
# Include the exact boundary shape that exposed the compiler bug (1025),
# adjacent modulo-8 residues, powers of two, and deterministic random extents.
ns=list(range(1024,1065))+[
    1537,2047,2048,2049,4095,4096,4097,8191,8192,8193,
    65535,65536,65537,262143,262144,262145,
]
r=random.Random(1011)
ns += [r.randint(1024,500000) for _ in range(32)]
for n in ns:
    vals={}
    for k,b in bins.items():
        out=subprocess.check_output([b,str(n)],text=True).strip()
        bits=out.split('0x',1)[1]
        vals[k]=struct.unpack('>d',bytes.fromhex(bits))[0]
    rel_ts=abs(vals['tol1']-vals['strict'])/max(1.0,abs(vals['strict']))
    rel_41=abs(vals['tol4']-vals['tol1'])/max(1.0,abs(vals['tol1']))
    assert rel_ts <= 1e-10, (n,vals,rel_ts)
    assert rel_41 <= 1e-10, (n,vals,rel_41)
print(f'OPERATOR_PERIODIC_DIFFERENTIAL_CASES={len(ns)}')
print('OPERATOR_PERIODIC_CORRECTNESS_FIX=PASS')
PY

echo 'OPERATOR_SUBSPACE_1_0_11_FIX=PASS'
