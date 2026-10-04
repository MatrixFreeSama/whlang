from pathlib import Path

p = Path('experiments/paper_1_3_127/run_expansion_v1.py')
s = p.read_text(encoding='utf-8')
old = '''    for name in ("topologyc-native256", "fieldc-native256", "whexc", "fieldc"):
        p = root / "bin" / name
        if p.exists():
            p.chmod(p.stat().st_mode | 0o111)'''
new = '''    for p in (root / "bin").iterdir():
        if p.is_file():
            p.chmod(p.stat().st_mode | 0o111)'''
if old not in s:
    raise SystemExit('permission block not found')
p.write_text(s.replace(old, new, 1), encoding='utf-8')
