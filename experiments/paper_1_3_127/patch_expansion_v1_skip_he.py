from pathlib import Path

p = Path('experiments/paper_1_3_127/run_expansion_v1.py')
s = p.read_text(encoding='utf-8')
a = s.index('        # D. High-entropy runtime-modulo permutation, retained from 1.3.102.')
b = s.index('        # E. Established public simulation kernels: miniAMR-27 and miniFE heat21.')
s = s[:a] + '''        # D. High-entropy runtime-modulo permutation is deliberately excluded from
        # this expansion batch. The frozen whexc launcher admits the retained source
        # from the repository root but the sovereign topology path rejects the same
        # source after relocation under a temporary package root. That launcher/path
        # coverage issue is kept as a separate reproducibility observation instead of
        # changing the frozen compiler or inventing a publication-only route.\n\n''' + s[b:]
s = s.replace(
    '"Frozen compiler: `Wheelchair 1.3.127`. High-entropy uses the existing `whexc` AVX-512 realization with x86-64-v4 C/Fortran controls; Field and periodic cases use native256 with x86-64-v3 controls. No speedup is aggregated across ISA profiles.",',
    '"Frozen compiler: `Wheelchair 1.3.127`. This expansion batch uses native256 with x86-64-v3 C/Fortran controls throughout. The retained high-entropy case is excluded here because its frozen whexc launcher has path-dependent admission under relocation; the compiler is not modified to make the paper harness accept it.",',
    1,
)
s = s.replace(
    '            "- `high_entropy_6perm_v4` is the retained runtime-modulo physical-work-inflation witness. The frozen `whexc` product uses AVX-512, so only x86-64-v4 C/Fortran controls are compared with it; it is not mixed with the v3 tables.",\n',
    '            "- The retained high-entropy 1.3.102 witness is not included in this fresh batch because relocated frozen-package admission differs from repository-root admission. That coverage issue is recorded rather than repaired for publication.",\n',
    1,
)
p.write_text(s, encoding='utf-8')
