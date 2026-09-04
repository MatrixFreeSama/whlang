#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/general108

# Mixed numeric promotion must convert representations, not reinterpret bits.
./wheelchairc tests/general_108/mixed.wh -o build/general108/mixed > build/general108/mixed.json
[ "$(build/general108/mixed 0)" = 'out00_bits=0x3ff8000000000000' ]
[ "$(build/general108/mixed 1)" = 'out00_bits=0x4004000000000000' ]
[ "$(build/general108/mixed 10)" = 'out00_bits=0x4027000000000000' ]
[ "$(build/general108/mixed 18446744073709551615)" = 'out00_bits=0x43f0000000000000' ]
echo 'GENERAL_MIXED_NUMERIC=PASS'

# Mixed select branches must share the inferred representation.
./wheelchairc tests/general_108/selectmix.wh -o build/general108/selectmix > build/general108/selectmix.json
[ "$(build/general108/selectmix 1)" = 'out00_bits=0x3ff0000000000000' ]
[ "$(build/general108/selectmix 0)" = 'out00_bits=0x4004000000000000' ]
echo 'GENERAL_MIXED_SELECT=PASS'

# f64 rhs must not be accidentally reloaded from lhs (the pre-1.0.8 bug).
./wheelchairc tests/general_108/f64_ops.wh -o build/general108/f64_ops > build/general108/f64_ops.json
python3 - <<'PY'
import subprocess
lines=subprocess.check_output(['build/general108/f64_ops'],text=True).strip().splitlines()
want=[
'out00_bits=0x4004000000000000', # 2.5
'out01_bits=0x4008000000000000', # 3
'out02_bits=0x4018000000000000', # 6
'out03_bits=0x4008000000000000', # 3
'out04_bits=0x4000000000000000', # 2
'out05_bits=0x4008000000000000', # 3
'out06_bits=0x0000000000000001',
'out07_bits=0x0000000000000000']
assert lines==want,(lines,want)
PY
echo 'GENERAL_F64_BINARY_RHS=PASS'

# Deterministic runtime differential: compare generated f64 arithmetic against
# the same IEEE-754 operations applied to the exact values parsed by the WH
# executable (so decimal-parser rounding cannot masquerade as an ALU failure).
./wheelchairc tests/general_108/f64_input_differential.wh -o build/general108/f64_diff > build/general108/f64_diff.json
python3 - <<'PY2'
import subprocess,struct,re,random
random.seed(108)
def val(b): return struct.unpack('<d',struct.pack('<Q',b))[0]
def bits(x): return struct.unpack('<Q',struct.pack('<d',float(x)))[0]
for _ in range(16):
    x=random.uniform(-1e6,1e6); y=random.uniform(-1e6,1e6)
    if abs(y)<1e-12: y=1.0
    lines=subprocess.check_output(['build/general108/f64_diff',repr(x),repr(y)],text=True).splitlines()
    got=[int(re.search(r'0x([0-9a-f]+)',z).group(1),16) for z in lines]
    xx,yy=val(got[0]),val(got[1])
    want=[got[0],got[1],bits(xx+yy),bits(xx-yy),bits(xx*yy),bits(xx/yy),1 if xx<yy else 0,bits(max(xx,yy))]
    assert got==want,(xx,yy,got,want)
PY2
echo 'GENERAL_F64_DIFFERENTIAL=PASS'
echo 'GENERAL_F64_DIFFERENTIAL_CASES=16'

# Surface/core cast contract is unified on `to`, while core still admits the
# legacy schema during the compatibility window.
./wheelchairc tests/general_108/cast_surface_mismatch.wh -o build/general108/cast > build/general108/cast.json
[ "$(build/general108/cast 1)" = 'out00_bits=0x3ff0000000000000' ]
python3 - <<'PY'
import sys
sys.path.insert(0,'surface'); import wh_surface
from pathlib import Path
d,_,_=wh_surface.load_surface(Path('tests/general_108/cast_surface_mismatch.wh'))
cast=d['bindings'][0]['expr']
assert cast['op']=='cast' and cast['to']=='f64' and 'type' not in cast
PY
echo 'GENERAL_CAST_SCHEMA=PASS'

# Signed overflow/division traps must be controlled exit 65, never wrong bits or SIGFPE.
for f in negmin absmin; do
  ./wheelchairc tests/general_108/$f.wh -o build/general108/$f > build/general108/$f.json
  set +e; build/general108/$f -9223372036854775808 >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 65 ]
done
for f in idiv imod; do
  ./wheelchairc tests/general_108/$f.wh -o build/general108/$f > build/general108/$f.json
  set +e; build/general108/$f -9223372036854775808 -1 >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 65 ]
done
[ "$(build/general108/idiv -7 2)" = 'out00_bits=0xfffffffffffffffd' ]
[ "$(build/general108/imod -7 2)" = 'out00_bits=0xffffffffffffffff' ]
echo 'GENERAL_SIGNED_TRAPS=PASS'

# The `abs` tolerance keyword must parse as a tolerance key, not collide with
# the abs() expression keyword.
./wheelchairc tests/general_108/tolerance_abs_parser.wh -o build/general108/tolerance > build/general108/tolerance.json
python3 - <<'PY'
import json
r=json.load(open('build/general108/tolerance.json'))
assert r['general_topology_recovery']['active'] is True
assert r['general_topology_recovery']['floating_point_contract']=='tolerant'
PY
echo 'GENERAL_TOLERANCE_PARSER=PASS'

# Fast-path classification is a hint, never a semantic cliff.  This strict f64
# map+sum is not admitted by the topology slice but must retry direct general.
./wheelchairc tests/general_108/fastsum.wh -o build/general108/fastsum > build/general108/fastsum.json
[ "$(build/general108/fastsum 4)" = 'out00_bits=0x4010000000000000' ]
echo 'GENERAL_FASTPATH_FALLBACK=PASS'

# Direct-general multi-executor requests must reject explicitly rather than
# silently producing a byte-identical one-executor ELF.
set +e
./wheelchairc tests/general_108/fastsum.wh -o build/general108/fastsum4 --executors 4 >build/general108/fastsum4.out 2>build/general108/fastsum4.err
rc=$?
set -e
[ "$rc" -eq 65 ]
grep -q 'requested executor width cannot be honored by an unrecovered general region' build/general108/fastsum4.err
echo 'GENERAL_EXECUTOR_NOT_SILENT=PASS'

# General Topology Recovery: dead scalar code cannot poison a provable numeric
# region.  The recovered .wh and equivalent .whex must reach exactly the same
# native image through the shared topology backend.
./wheelchairc tests/general_108/gtr_equiv.wh -o build/general108/gtr_wh --executors 4 > build/general108/gtr_wh.json
./whexc tests/general_108/gtr_equiv.whex -o build/general108/gtr_whex --executors 4 > build/general108/gtr_whex.json
cmp -s build/general108/gtr_wh build/general108/gtr_whex
python3 - <<'PY'
import json
r=json.load(open('build/general108/gtr_wh.json'))
g=r['general_topology_recovery']
assert g['active'] and g['semantic_lane']=='topology'
assert g['dropped_dead_bindings']==['dummy']
assert r['requested_executors']==4 and r['effective_executors']==4
PY
[ "$(build/general108/gtr_wh 8)" = 'checksum_bits=0x4036000000000000' ]
echo 'GENERAL_TOPOLOGY_RECOVERY=PASS'
echo 'GENERAL_TOPOLOGY_MACHINE_CODE_EQUIVALENT=PASS'

# Complex FEM recovery proof: the general-language spelling of the canonical
# computation/communication-elimination case must also erase to the exact same
# 4-executor native image as WHEX, including the existing 48->36 computation
# elimination and partition-local communication plan.
./wheelchairc tests/general_108/fem_gtr_equiv.wh -o build/general108/fem_gtr_wh --executors 4 > build/general108/fem_gtr_wh.json
./whexc tests/whex/fem_parallel_elimination.whex -o build/general108/fem_gtr_whex --executors 4 > build/general108/fem_gtr_whex.json
cmp -s build/general108/fem_gtr_wh build/general108/fem_gtr_whex
python3 - <<'PYFEM'
import json
r=json.load(open('build/general108/fem_gtr_wh.json'))
g=r['general_topology_recovery']
assert g['active'] and g['semantic_lane']=='topology'
assert g['dropped_dead_bindings']==['dead_general_scalar']
assert 'checksum' in g['recovered_bindings'] and len(g['recovered_bindings'])==7
PYFEM
[ "$(build/general108/fem_gtr_wh 262144)" = "$(build/general108/fem_gtr_whex 262144)" ]
echo 'GENERAL_FEM_TOPOLOGY_MACHINE_CODE_EQUIVALENT=PASS'

# The shipped feature showcase must be an executable example.  Closed literal
# dictionary lookup and closed cascade goals are eliminated before native
# general lowering; dynamic variants remain conservative/rejected.
./wheelchairc surface/examples/feature_showcase.wh -o build/general108/feature > build/general108/feature.json
python3 - <<'PY'
import json,subprocess
r=json.load(open('build/general108/feature.json'))
s=r['static_general_lowering']
assert s['dictionary_lookups_folded']==['weight']
assert s['cascades_folded']==['级联结果']
lines=subprocess.check_output(['build/general108/feature'],text=True).strip().splitlines()
want=[
'out00_bits=0x000000000000000c','out01_bits=0x0000000000000096',
'out02_bits=0x0000000000000015','out03_bits=0x4018000000000000',
'out04_bits=0x000000000000000f','out05_bits=0x000000000000000a',
'out06_bits=0x0000000000000015','out07_bits=0x0000000000000004']
assert lines==want,(lines,want)
PY
echo 'GENERAL_FEATURE_SHOWCASE=PASS'

# Unproven dynamic dictionary/cascade constructs must reject cleanly.  A crash,
# SIGFPE, fabricated value, or silent static reinterpretation is a release failure.
for f in dynamic_dictionary dynamic_cascade; do
  set +e
  ./wheelchairc tests/general_108/$f.wh -o build/general108/$f >build/general108/$f.out 2>build/general108/$f.err
  rc=$?
  set -e
  [ "$rc" -eq 65 ]
done
echo 'GENERAL_DYNAMIC_COMPLEX_CONSERVATIVE=PASS'

echo 'GENERAL_1_0_8_GATES=PASS'
