#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
PRE='''program p\ntolerance 1e-8\ninput n: u64 range 4..100000000\nfield f[i in n]: f64 = -0.375 + cast(f64, (i * 31 + 11) % 2048) / 2048.0\nfield s[i in n]: f64 = 0.25 + cast(f64, (i * 23 + 5) % 1024) / 1536.0\nfield r[i in n]: f64 = 1.0 + cast(f64, (i * 13 + 9) % 256) / 2048.0\nfield m[i in n]: f64 = 0.75 + cast(f64, (i * 7 + 3) % 128) / 1024.0\nfield e[i in n]: f64 = 1.25 + cast(f64, (i * 19 + 1) % 256) / 1024.0\nfield g[i in n]: f64 = 0.125 + cast(f64, (i * 5 + 7) % 64) / 4096.0\n'''
FD='field fo[i in n]: f64 = r[i] * (2.0 * f[i] - f[periodic(i + n - 1, n)] - f[periodic(i + 1, n)]) + m[i] * (f[periodic(i + 1, n)] - f[periodic(i + n - 1, n)])\n'
FC='field fo[i in n]: f64 = r[i] * (2.0 * f[i] - f[periodic(i + n - 1, n)] - f[periodic(i + 1, n)]) + m[i] * (f[periodic(i + 1, n)] - f[periodic(i + n - 1, n)]) + g[i] * (f[i] - s[i])\n'
SD='field so[i in n]: f64 = e[i] * (2.0 * s[i] - s[periodic(i + n - 1, n)] - s[periodic(i + 1, n)]) + 0.0625 * (s[periodic(i + 1, n)] - s[periodic(i + n - 1, n)])\n'
SC='field so[i in n]: f64 = e[i] * (2.0 * s[i] - s[periodic(i + n - 1, n)] - s[periodic(i + 1, n)]) + 0.0625 * (s[periodic(i + 1, n)] - s[periodic(i + n - 1, n)]) + g[i] * (s[i] - f[i])\n'
END='sum checksum[i in n]: f64 = fo[i] * fo[i] + so[i] * so[i]\noutput checksum\ntest (4) => { checksum = 0.0 }\n'
CASES={'fluid_coupled_only':PRE+FC+'sum checksum[i in n]: f64 = fo[i] * fo[i]\noutput checksum\ntest (4) => { checksum = 0.0 }\n',
       'solid_coupled_only':PRE+SC+'sum checksum[i in n]: f64 = so[i] * so[i]\noutput checksum\ntest (4) => { checksum = 0.0 }\n',
       'fluid_coupled_solid_decoupled':PRE+FC+SD+END,
       'fluid_decoupled_solid_coupled':PRE+FD+SC+END,
       'both_coupled':PRE+FC+SC+END}
with tempfile.TemporaryDirectory(prefix='wh128-cpl-') as td:
  td=Path(td)
  for name,src in CASES.items():
    p=td/(name+'.whex'); p.write_text(src)
    cp=subprocess.run(['python3','whexc.py',str(p),'-o',str(td/(name+'.elf')),'--executors','1','--isa-limit','avx2'],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    print(f'NATIVE256_COUPLING_CASE={name} RESULT={"PASS" if cp.returncode==0 else "REJECT"}')
