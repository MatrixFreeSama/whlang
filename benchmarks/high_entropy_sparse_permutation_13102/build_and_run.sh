#!/usr/bin/env bash
set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
WHEELCHAIR_ROOT=${WHEELCHAIR_ROOT:-"$ROOT/main"}
N=${N:-50000000}
cd "$HERE"

"$WHEELCHAIR_ROOT/bin/whexc" perm_strict.whex -o wh_strict
"$WHEELCHAIR_ROOT/bin/whexc" perm_fast.whex -o wh_fast
cc -O3 -march=native -fopenmp -fno-fast-math -ffp-contract=off perm.c -o c_strict
cc -O3 -march=native -fopenmp -ffast-math perm.c -o c_fast
gfortran -O3 -march=native -fopenmp -fno-fast-math -ffp-contract=off -fwrapv perm.f90 -o f_strict
gfortran -O3 -march=native -fopenmp -ffast-math -fwrapv perm.f90 -o f_fast

for x in wh_strict c_strict f_strict wh_fast c_fast f_fast; do
  echo "== $x =="
  OMP_NUM_THREADS=4 OMP_PROC_BIND=true OMP_PLACES=cores OMP_WAIT_POLICY=PASSIVE \
    taskset -c 0-3 ./$x "$N"
done
