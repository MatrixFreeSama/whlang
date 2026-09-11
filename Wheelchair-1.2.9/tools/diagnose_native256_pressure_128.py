#!/usr/bin/env python3
"""Compile-and-run structural pressure bisection for native256 maturation.

Diagnostic only. Cases are generated from semantic building blocks and are never
visible to backend routing. The compiler remains workload-blind.
"""
from pathlib import Path
import subprocess, tempfile

ROOT=Path(__file__).resolve().parents[1]
CASES={
'fluid_affine_cast': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = cast(f64, i * 31 + 11)\nsum checksum[i in n]: f64 = a[i]\noutput checksum\n''',
'fluid_mod_cast': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = cast(f64, (i * 31 + 11) % 2048)\nsum checksum[i in n]: f64 = a[i]\noutput checksum\n''',
'fluid_scaled': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = cast(f64, (i * 31 + 11) % 2048) / 2048.0\nsum checksum[i in n]: f64 = a[i]\noutput checksum\n''',
'fluid_shifted': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nsum checksum[i in n]: f64 = a[i]\noutput checksum\n''',
'solid_affine_cast': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = cast(f64, i * 23 + 5)\nsum checksum[i in n]: f64 = a[i]\noutput checksum\n''',
'solid_mod_cast': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = cast(f64, (i * 23 + 5) % 1024)\nsum checksum[i in n]: f64 = a[i]\noutput checksum\n''',
'base_field': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nsum checksum[i in n]: f64 = a[i] * a[i]\noutput checksum\n''',
'periodic_one_field': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nfield op[i in n]: f64 = 2.0 * a[i] - a[periodic(i + n - 1, n)] - a[periodic(i + 1, n)]\nsum checksum[i in n]: f64 = op[i] * op[i]\noutput checksum\n''',
'periodic_weighted': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nfield r[i in n]: f64 = 1.0 + cast(f64, (i * 13 + 9) % 256) / 2048.0\nfield op[i in n]: f64 = r[i] * (2.0 * a[i] - a[periodic(i + n - 1, n)] - a[periodic(i + 1, n)])\nsum checksum[i in n]: f64 = op[i] * op[i]\noutput checksum\n''',
'fluid_operator': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nfield r[i in n]: f64 = 1.0 + cast(f64, (i * 13 + 9) % 256) / 2048.0\nfield m[i in n]: f64 = 0.75 + cast(f64, (i * 7 + 3) % 128) / 1024.0\nfield op[i in n]: f64 = r[i] * (2.0 * a[i] - a[periodic(i + n - 1, n)] - a[periodic(i + 1, n)]) + m[i] * (a[periodic(i + 1, n)] - a[periodic(i + n - 1, n)])\nsum checksum[i in n]: f64 = op[i] * op[i]\noutput checksum\n''',
'solid_operator': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield a[i in n]: f64 = 0.25 + cast(f64, (i * 23 + 5) % 1024) / 1536.0\nfield e[i in n]: f64 = 1.25 + cast(f64, (i * 19 + 1) % 256) / 1024.0\nfield op[i in n]: f64 = e[i] * (2.0 * a[i] - a[periodic(i + n - 1, n)] - a[periodic(i + 1, n)]) + 0.0625 * (a[periodic(i + 1, n)] - a[periodic(i + n - 1, n)])\nsum checksum[i in n]: f64 = op[i] * op[i]\noutput checksum\n''',
'decoupled_two_ops': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield f[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nfield s[i in n]: f64 = 0.25 + cast(f64, (i * 23 + 5) % 1024) / 1536.0\nfield r[i in n]: f64 = 1.0 + cast(f64, (i * 13 + 9) % 256) / 2048.0\nfield m[i in n]: f64 = 0.75 + cast(f64, (i * 7 + 3) % 128) / 1024.0\nfield e[i in n]: f64 = 1.25 + cast(f64, (i * 19 + 1) % 256) / 1024.0\nfield fo[i in n]: f64 = r[i] * (2.0 * f[i] - f[periodic(i + n - 1, n)] - f[periodic(i + 1, n)]) + m[i] * (f[periodic(i + 1, n)] - f[periodic(i + n - 1, n)])\nfield so[i in n]: f64 = e[i] * (2.0 * s[i] - s[periodic(i + n - 1, n)] - s[periodic(i + 1, n)]) + 0.0625 * (s[periodic(i + 1, n)] - s[periodic(i + n - 1, n)])\nsum checksum[i in n]: f64 = fo[i] * fo[i] + so[i] * so[i]\noutput checksum\n''',
'coupling_delta': '''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield f[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nfield s[i in n]: f64 = 0.25 + cast(f64, (i * 23 + 5) % 1024) / 1536.0\nfield g[i in n]: f64 = 0.125 + cast(f64, (i * 5 + 7) % 64) / 4096.0\nfield d[i in n]: f64 = g[i] * (f[i] - s[i])\nsum checksum[i in n]: f64 = d[i] * d[i]\noutput checksum\n''',
'decoupled_full': (ROOT.parent/'benchmarks/fluid_solid_coupling_124/fsi_decoupled.whex').read_text(),
'coupled_full': (ROOT.parent/'benchmarks/fluid_solid_coupling_124/fsi_coupled.whex').read_text(),
}

with tempfile.TemporaryDirectory(prefix='wh128-pressure-') as td:
    td=Path(td)
    for name,src in CASES.items():
        if '\ntest (' not in src:
            src += 'test (4) => { checksum = 0.0 }\n'
        p=td/f'{name}.whex'; p.write_text(src)
        out=td/f'{name}.elf'
        plan=td/f'{name}.json'
        cp=subprocess.run(['python3','whexc.py',str(p),'-o',str(out),'--executors','1','--isa-limit','avx2','--semantic-plan',str(plan)],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        print(f'NATIVE256_PRESSURE_CASE={name} RESULT={"PASS" if cp.returncode==0 else "REJECT"}')
        if cp.returncode:
            tail=' | '.join(cp.stdout.strip().splitlines()[-3:])
            print(f'NATIVE256_PRESSURE_DETAIL={name} {tail}')
            continue
        rp=subprocess.run([str(out),'4'],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        print(f'NATIVE256_PRESSURE_VALUE={name} RC={rp.returncode} OUT={rp.stdout.strip()}')
