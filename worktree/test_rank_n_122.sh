#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
# Wheelchair 1.2.2 final Rank-N validation entrypoint.

# Hard peak-protection law: the complete 1.2.1 Rank-1 native source triplet is
# byte-frozen. Rank-N is a separate derived lane and cannot consume these peaks.
echo 'e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6  compiler/tensor_frontend_x86_64.S' | sha256sum -c -
echo '2e83af25b6a6188c9ce24497d636206ca5978e59a92b619e6b722909ad2d4f80  compiler/topologyc_x86_64.S' | sha256sum -c -
echo 'e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3  runtime/tensor_runtime_template_x86_64.S' | sha256sum -c -
echo 'WHEELCHAIR_1_2_1_NATIVE_SOURCE_PEAK_BYTES=PASS'

python3 surface/whex_surface.py plan tests/whex/rank2_native_122.whex > "$TMP/r2.plan.json"
python3 surface/whex_surface.py plan tests/whex/rank3_native_122.whex > "$TMP/r3.plan.json"
python3 - "$TMP/r2.plan.json" "$TMP/r3.plan.json" <<'PY'
import json,sys
for expected_rank,path in ((2,sys.argv[1]),(3,sys.argv[2])):
    p=json.load(open(path,encoding='utf-8'))
    a=p['axis_algebra']
    rows=a['rank_n_product_realizations']
    term=[r for r in rows if r['terminal_physical_domain']]
    assert len(term)==1 and term[0]['source_rank']==expected_rank
    assert term[0]['mapping']=='bijective_cartesian_product_token'
    assert term[0]['serial_axis_loops']==0
    assert term[0]['scalar_fallback'] is False
    q=p['parallelism_contract']
    assert q['rank_n_product_parallel_cardinality_preserved'] is True
    assert q['rank_n_serial_inner_loop'] is False
    assert q['rank_n_scalar_fallback'] is False
    s=p['serial_introduction_report']
    assert s['new_serial_axis_loops']==0
    e=p['abstraction_erasure']
    assert e['rank_n_runtime_shape_objects']==0
    assert e['rank_n_runtime_axis_metadata_objects']==0
print('RANK_N_SEMANTIC_PRODUCT_PROOF=PASS')
PY

# WH and WHEX must converge on the same physical canonical graph.
PYTHONPATH="$ROOT/surface" python3 - <<'PY'
from pathlib import Path
import wh_structural as hs, whex_surface as xs
wd,wp,_=hs.load_surface(Path('tests/wh_equivalence/rank2_native_122.wh'))
xd,xp,_=xs.load_surface(Path('tests/whex/rank2_native_122.whex'))
assert hs.canonical_core_bytes(wd)==xs.canonical_core_bytes(xd)
assert wd['rank_n_product']==4 and wd['rank_n_source_rank']==2
print('WH_WHEX_RANK_N_CANONICAL_EQUIVALENCE=PASS')
PY

# The transformed core must contain one physical product axis and no source
# nested-axis execution object. q is a point token, not an inner-loop variable.
python3 surface/whex_surface.py compile tests/whex/rank2_native_122.whex -o "$TMP/r2.core.wh" >/dev/null
python3 - "$TMP/r2.core.wh" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert x['rank_n_product']==4 and x['rank_n_source_rank']==2
for b in x['bindings']:
    assert len(b['axes'])==1
    assert b['axes'][0]['name'].startswith('__rankn_q_')
assert '"ushr"' in open(sys.argv[1],encoding='utf-8').read()
print('RANK_N_CANONICAL_SINGLE_TOKEN_NO_SERIAL_NEST=PASS')
PY

# Unsupported shapes reject rather than flatten.
cat > "$TMP/nonpow2.whex" <<'EOF'
program nonpow2
tolerance 1e-12
input n: u64 range 4..1024
sum checksum[i in n, j in 3]: f64 = cast(f64, i + j)
output checksum
test (4) => { checksum = 0.0 }
EOF
if python3 surface/whex_surface.py plan "$TMP/nonpow2.whex" >/dev/null 2>&1; then
  echo 'non-power-of-two Rank-N was incorrectly admitted' >&2; exit 1
fi
cat > "$TMP/periodic_rankn.whex" <<'EOF'
program periodic_rankn
tolerance 1e-12
input n: u64 range 4..1024
sum checksum[i in n, j in 4]: f64 = cast(f64, periodic(i + 1, n) + j)
output checksum
test (4) => { checksum = 0.0 }
EOF
if python3 surface/whex_surface.py plan "$TMP/periodic_rankn.whex" >/dev/null 2>&1; then
  echo 'dynamic periodic Rank-N was incorrectly admitted' >&2; exit 1
fi
echo 'RANK_N_UNPROVEN_LAYOUT_EXPLICIT_REJECTION=PASS'

# Native execution is staged so a backend failure cannot hide whether product
# coordinate recovery itself works before fused map/load composition is tested.
if python3 surface/whex_surface.py native tests/whex/rank2_reduce_native_122.whex -o "$TMP/r2direct" --executors 1 >/dev/null; then
  echo 'RANK2_DIRECT_REDUCTION_NATIVE_COMPILE=PASS'
else
  echo 'RANK2_DIRECT_REDUCTION_NATIVE_COMPILE=FAIL' >&2
  exit 1
fi
r2direct=$($TMP/r2direct 4)
[ "$r2direct" = 'checksum_bits=0x405e000000000000' ]
echo 'RANK2_DIRECT_REDUCTION_NATIVE_REFERENCE=PASS'

if python3 surface/whex_surface.py native tests/whex/rank2_native_122.whex -o "$TMP/r2" --executors 1 >/dev/null; then
  echo 'RANK2_MAP_LOAD_NATIVE_COMPILE=PASS'
else
  echo 'RANK2_MAP_LOAD_NATIVE_COMPILE=FAIL' >&2
  exit 1
fi
python3 surface/whex_surface.py native tests/whex/rank3_native_122.whex -o "$TMP/r3" --executors 1 >/dev/null
python3 wheelchairc.py tests/wh_equivalence/rank2_native_122.wh -o "$TMP/r2wh" --executors 1 --semantic-plan "$TMP/r2wh.plan.json" >/dev/null
r2=$($TMP/r2 4)
r3=$($TMP/r3 4)
r2wh=$($TMP/r2wh 4)
[ "$r2" = 'checksum_bits=0x405e000000000000' ]
[ "$r3" = 'checksum_bits=0x407f000000000000' ]
[ "$r2wh" = "$r2" ]
echo 'RANK2_NATIVE_CARTESIAN_REFERENCE=PASS'
echo 'RANK3_NATIVE_CARTESIAN_REFERENCE=PASS'
echo 'WH_WHEX_RANK2_NATIVE_EQUIVALENCE=PASS'

# The Rank-N evaluator must contain the already-existing AVX-512F logical right
# shift and must not contain scalar eval-slot calls.
objdump -d "$TMP/r2" > "$TMP/r2.asm"
grep -Eiq 'vpsrlq' "$TMP/r2.asm"
if grep -Eq 'call.*<eval_slot>' "$TMP/r2.asm"; then
  echo 'Rank-N scalar eval-slot fallback detected' >&2; exit 1
fi
echo 'RANK_N_AVX512_COORDINATE_RECOVERY=PASS'
echo 'RANK_N_SCALAR_FALLBACK=0'

# Existing mathematical Rank-N erasure must still bypass the new lane and retain
# byte identity through the historical gate.
./test_whex_semantic_parallel_110.sh > "$TMP/semantic110.log"
grep -q 'WHEX_RANK_N_AXIS_ERASURE=PASS' "$TMP/semantic110.log"
grep -q 'WHEX_RANK_N_MACHINE_CODE_ERASURE=PASS' "$TMP/semantic110.log"
echo 'RANK_N_ERASURE_PRECEDENCE_NONREGRESSION=PASS'

# Exact 1.2.1 Newton/Jv restoration gate remains authoritative for the protected
# technical spike. This is intentionally run unchanged, not reimplemented here.
./test_newton_jv_121.sh > "$TMP/newton121.log"
grep -q 'WHEX_INTERIOR_PERIODIC_COMPOSITION_1_2_1=PASS' "$TMP/newton121.log"
echo 'NEWTON_JV_1_2_1_TECHNICAL_PEAK_PROTECTED=PASS'

echo 'WHEELCHAIR_RANK_N_1_2_2=PASS'
