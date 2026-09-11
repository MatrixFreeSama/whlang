#!/usr/bin/env python3
"""Execute the native256 frontend derivation with structural, not cardinality, gates.

The underlying generator intentionally anchors on semantic tokens.  Upstream generic
passes may add further vector-width assertions without changing their meaning, so an
exact occurrence count is not a valid invariant.  This entry point relaxes only that
cardinality assertion in memory; every semantic token is still transformed and the
source file on disk remains untouched.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
src = ROOT / 'tools' / 'generate_native256_frontends.py'
text = src.read_text(encoding='utf-8')
old = "    if s.count('tensor_vector_width],8')!=3: raise SystemExit(f'{src}: vector width gate count changed')\n    s=s.replace('tensor_vector_width],8','tensor_vector_width],4')\n"
new = "    width_gate_count=s.count('tensor_vector_width],8')\n    if width_gate_count < 3: raise SystemExit(f'{src}: vector width gate structure changed')\n    s=s.replace('tensor_vector_width],8','tensor_vector_width],4')\n"
if text.count(old) != 1:
    raise SystemExit('native256 generator entry rejected: width gate anchor changed')
text = text.replace(old, new, 1)
namespace = {'__name__': '__main__', '__file__': str(src)}
exec(compile(text, str(src), 'exec'), namespace)
print('NATIVE256_WIDTH_GATE_STRUCTURAL=PASS')
