from pathlib import Path

p = Path('experiments/paper_1_3_127/run_expansion_v1.py')
s = p.read_text(encoding='utf-8')
a = s.index('        # F. Deep periodic CoordinateFact composition, retained from 1.3.124.')
b = s.index('        # Binary metadata after all compilation.')
s = s[:a] + '''        # E2. The retained deep-periodic CoordinateFact sources are deliberately
        # excluded from this native256 batch because the frozen topologyc-native256
        # entry rejects them. They remain a separate whexc/ISA-matched experiment;
        # the frozen compiler is not changed to force admission for publication.\n\n''' + s[b:]
s = s.replace(
    '            "- `periodic_depth_23/40` isolate CoordinateFact composition. The natural C/Fortran controls explicitly materialize every remap stage; the ceiling controls manually compose the affine relation and are labeled ceilings, not natural baselines.",\n',
    '            "- Deep periodic CoordinateFact is not forced into this native256 batch because the frozen topologyc-native256 entry rejects the retained d23/d40 sources; it is reserved for a separate native whexc/ISA-matched table.",\n',
    1,
)
p.write_text(s, encoding='utf-8')
