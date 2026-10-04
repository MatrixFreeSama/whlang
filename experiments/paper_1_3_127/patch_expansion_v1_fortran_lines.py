from pathlib import Path

p = Path('experiments/paper_1_3_127/run_expansion_v1.py')
s = p.read_text(encoding='utf-8')
old = '''    cmd = ["gfortran", "-O3", "-march=x86-64-v3", "-mtune=generic",
           "-fno-fast-math", "-ffp-contract=off", "-fprotect-parens"]'''
new = '''    cmd = ["gfortran", "-O3", "-march=x86-64-v3", "-mtune=generic",
           "-fno-fast-math", "-ffp-contract=off", "-fprotect-parens",
           "-ffree-line-length-none"]'''
if old not in s:
    raise SystemExit('gfortran command block not found')
p.write_text(s.replace(old, new, 1), encoding='utf-8')
