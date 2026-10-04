from pathlib import Path

p = Path('experiments/paper_1_3_127/run_expansion_v1.py')
s = p.read_text(encoding='utf-8')
old = '''        himpls = {
            "Wheelchair_1.3.127_native256": hd / "wheelchair",
            "GCC_C_v3": hd / "c",
            "GFortran_v3": hd / "fortran",
        }
        compile_one("high_entropy/Wheelchair_1.3.127_native256",
                    ["./bin/topologyc-native256", "paper_inputs/perm_strict.whex", "-o", str(himpls["Wheelchair_1.3.127_native256"])], cwd=wroot)
        compile_one("high_entropy/GCC_C_v3", gcc_cmd(hsrc / "perm.c", himpls["GCC_C_v3"], openmp=True))
        compile_one("high_entropy/GFortran_v3", gfortran_cmd(hsrc / "perm.f90", himpls["GFortran_v3"], openmp=True))
        cases.append({
            "group": "high_entropy_permutation", "workload": "high_entropy_6perm", "baseline": "GCC_C_v3",
            "commands": {k: [str(v), str(HE_N)] for k, v in himpls.items()}, "env": omp1,
        })'''
new = '''        himpls = {
            "Wheelchair_1.3.127_whexc_v4": hd / "wheelchair",
            "GCC_C_v4": hd / "c",
            "GFortran_v4": hd / "fortran",
        }
        compile_one("high_entropy/Wheelchair_1.3.127_whexc_v4",
                    ["./bin/whexc", "paper_inputs/perm_strict.whex", "-o", str(himpls["Wheelchair_1.3.127_whexc_v4"])], cwd=wroot)
        compile_one("high_entropy/GCC_C_v4",
                    ["gcc", "-O3", "-march=x86-64-v4", "-mtune=generic", "-fopenmp", "-fno-fast-math", "-ffp-contract=off", str(hsrc / "perm.c"), "-lm", "-o", str(himpls["GCC_C_v4"])])
        compile_one("high_entropy/GFortran_v4",
                    ["gfortran", "-O3", "-march=x86-64-v4", "-mtune=generic", "-fopenmp", "-fno-fast-math", "-ffp-contract=off", "-fprotect-parens", str(hsrc / "perm.f90"), "-o", str(himpls["GFortran_v4"])])
        cases.append({
            "group": "high_entropy_permutation_v4", "workload": "high_entropy_6perm_v4", "baseline": "GCC_C_v4",
            "commands": {k: [str(v), str(HE_N)] for k, v in himpls.items()}, "env": omp1,
        })'''
if old not in s:
    raise SystemExit('high-entropy block not found')
s = s.replace(old, new, 1)
s = s.replace(
    '"Frozen compiler: `Wheelchair 1.3.127`. Physical profile: `x86-64-v3 / native256`.",',
    '"Frozen compiler: `Wheelchair 1.3.127`. High-entropy uses the existing `whexc` AVX-512 realization with x86-64-v4 C/Fortran controls; Field and periodic cases use native256 with x86-64-v3 controls. No speedup is aggregated across ISA profiles.",',
    1,
)
s = s.replace(
    '"- `high_entropy_6perm` is the retained runtime-modulo physical-work-inflation witness, rerun with 1.3.127 rather than copied from 1.3.102.",',
    '"- `high_entropy_6perm_v4` is the retained runtime-modulo physical-work-inflation witness. The frozen `whexc` product uses AVX-512, so only x86-64-v4 C/Fortran controls are compared with it; it is not mixed with the v3 tables.",',
    1,
)
p.write_text(s, encoding='utf-8')
