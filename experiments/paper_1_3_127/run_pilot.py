#!/usr/bin/env python3
import csv
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "experiments" / "paper_1_3_127" / "pilot_20261005"
REPS = 15
GENERAL_STEPS = 20_000_000
DOMAIN_N = 8_000_000
CPU = min(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else 0


def sh(cmd, cwd=None, check=True):
    cp = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and cp.returncode != 0:
        raise RuntimeError(
            f"command failed ({cp.returncode}): {' '.join(map(str, cmd))}\n"
            f"cwd={cwd}\nstdout:\n{cp.stdout}\nstderr:\n{cp.stderr}"
        )
    return cp


def capture(cmd):
    cp = sh(cmd, check=False)
    return f"$ {' '.join(cmd)}\n{cp.stdout}{cp.stderr}\n"


def unpack(version, work):
    archive = ROOT / "dist" / f"Wheelchair-{version}.zip"
    dest = work / f"w{version.replace('.', '_')}"
    dest.mkdir(parents=True)
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(dest)
    preferred = dest / f"Wheelchair-{version}"
    if preferred.is_dir():
        root = preferred
    else:
        dirs = [p for p in dest.iterdir() if p.is_dir()]
        root = dirs[0] if len(dirs) == 1 else dest
    compiler = root / "bin" / "wheelchairc"
    compiler.chmod(compiler.stat().st_mode | 0o111)
    return root


def rel(path, root):
    return os.path.relpath(path, root)


def gcc_cmd(src, out):
    return ["gcc", "-O3", "-march=native", "-fno-fast-math", "-ffp-contract=off", str(src), "-lm", "-o", str(out)]


def gfortran_cmd(src, out):
    return ["gfortran", "-O3", "-march=native", "-fno-fast-math", "-ffp-contract=off", "-fprotect-parens", str(src), "-o", str(out)]


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    sources_out = OUT / "sources"
    sources_out.mkdir()

    env = [
        "paper_snapshot=Wheelchair-1.3.127",
        f"repo_commit={sh(['git', 'rev-parse', 'HEAD']).stdout.strip()}",
        f"pinned_cpu={CPU}",
        f"python={sys.version}",
        f"platform={platform.platform()}",
    ]
    for cmd in (["uname", "-a"], ["lscpu"], ["gcc", "--version"], ["gfortran", "--version"], ["ld", "--version"]):
        env.append(capture(cmd))
    (OUT / "environment.txt").write_text("\n".join(env) + "\n", encoding="utf-8")

    compile_rows = []
    cases = []

    def compile_one(label, cmd, cwd=None, optional=False):
        t0 = time.perf_counter_ns()
        cp = sh(cmd, cwd=cwd, check=False)
        dt = (time.perf_counter_ns() - t0) / 1e6
        compile_rows.append([
            label, dt, cp.returncode, cp.stdout.strip(), cp.stderr.strip(),
            str(cwd or ""), " ".join(map(str, cmd)),
        ])
        if cp.returncode != 0 and not optional:
            raise RuntimeError(
                f"compile failed ({cp.returncode}): {label}\n"
                f"cwd={cwd}\ncmd={cmd!r}\nstdout={cp.stdout!r}\nstderr={cp.stderr!r}"
            )
        return cp.returncode == 0

    with tempfile.TemporaryDirectory(prefix="wheelchair-paper-") as td:
        work = Path(td)
        src127 = unpack("1.3.127", work)
        src126 = unpack("1.3.126", work)
        bins = work / "bins"
        bins.mkdir()

        # A. Deep-causal scalar negative controls.
        gdir = src127 / "devtrash" / "benchmarks" / "math_generalization_1344"
        gcopy = sources_out / "general"
        gcopy.mkdir()
        for kernel in ("mass3", "chem6", "rigid7"):
            for ext in ("wh", "c", "f90"):
                shutil.copy2(gdir / f"{kernel}.{ext}", gcopy / f"{kernel}.{ext}")
            kd = bins / f"general_{kernel}"
            kd.mkdir()
            impls = {
                "Wheelchair_1.3.127": kd / "wheelchair",
                "GCC_C": kd / "c",
                "GFortran": kd / "fortran",
            }
            compile_one(
                f"general/{kernel}/Wheelchair_1.3.127",
                ["./bin/wheelchairc", rel(gdir / f"{kernel}.wh", src127), "-o", str(impls["Wheelchair_1.3.127"])],
                cwd=src127,
            )
            compile_one(f"general/{kernel}/GCC_C", gcc_cmd(gdir / f"{kernel}.c", impls["GCC_C"]))
            compile_one(f"general/{kernel}/GFortran", gfortran_cmd(gdir / f"{kernel}.f90", impls["GFortran"]))
            cases.append({
                "group": "general_negative", "workload": kernel, "arg": GENERAL_STEPS,
                "impls": impls, "baseline": "GCC_C",
            })

        # B. Localized elastoplastic support. The 127 source is copied into the
        # 126 temporary package root so the ablation changes compiler version,
        # not source text or path semantics.
        pdir = src127 / "devtrash" / "benchmarks" / "localized_plasticity_13127"
        pcopy = sources_out / "localized_plasticity"
        pcopy.mkdir()
        for name in ("plasticity.whex", "plasticity.c", "plasticity.f90", "plasticity_ceiling.c", "plasticity_ceiling.f90", "README.md"):
            shutil.copy2(pdir / name, pcopy / name)
        p126_input = src126 / "paper_inputs"
        p126_input.mkdir(exist_ok=True)
        shutil.copy2(pdir / "plasticity.whex", p126_input / "plasticity.whex")

        pd = bins / "plasticity"
        pd.mkdir()
        pimpls = {
            "Wheelchair_1.3.127": pd / "wheelchair_127",
            "Wheelchair_1.3.126": pd / "wheelchair_126",
            "GCC_C": pd / "c",
            "GFortran": pd / "fortran",
            "C_ceiling": pd / "c_ceiling",
            "Fortran_ceiling": pd / "fortran_ceiling",
        }
        compile_one(
            "plasticity/Wheelchair_1.3.127",
            ["./bin/wheelchairc", rel(pdir / "plasticity.whex", src127), "-o", str(pimpls["Wheelchair_1.3.127"])],
            cwd=src127,
        )
        if not compile_one(
            "plasticity/Wheelchair_1.3.126",
            ["./bin/wheelchairc", "paper_inputs/plasticity.whex", "-o", str(pimpls["Wheelchair_1.3.126"])],
            cwd=src126,
            optional=True,
        ):
            pimpls.pop("Wheelchair_1.3.126")
        compile_one("plasticity/GCC_C", gcc_cmd(pdir / "plasticity.c", pimpls["GCC_C"]))
        compile_one("plasticity/GFortran", gfortran_cmd(pdir / "plasticity.f90", pimpls["GFortran"]))
        compile_one("plasticity/C_ceiling", gcc_cmd(pdir / "plasticity_ceiling.c", pimpls["C_ceiling"]))
        compile_one("plasticity/Fortran_ceiling", gfortran_cmd(pdir / "plasticity_ceiling.f90", pimpls["Fortran_ceiling"]))
        cases.append({
            "group": "support", "workload": "localized_plasticity", "arg": DOMAIN_N,
            "impls": pimpls, "baseline": "GCC_C",
        })

        # C. Disconnected Level-Set / VOF support.
        ldir = src127 / "devtrash" / "benchmarks" / "levelset_regionset_13126"
        lcopy = sources_out / "levelset_regionset"
        lcopy.mkdir()
        for name in ("levelset_two_regions.whex", "levelset.c", "levelset.f90", "levelset_ceiling.c", "levelset_ceiling.f90", "README.md"):
            if (ldir / name).exists():
                shutil.copy2(ldir / name, lcopy / name)
        ld = bins / "levelset"
        ld.mkdir()
        limpls = {
            "Wheelchair_1.3.127": ld / "wheelchair",
            "GCC_C": ld / "c",
            "GFortran": ld / "fortran",
            "C_ceiling": ld / "c_ceiling",
            "Fortran_ceiling": ld / "fortran_ceiling",
        }
        compile_one(
            "levelset/Wheelchair_1.3.127",
            ["./bin/wheelchairc", rel(ldir / "levelset_two_regions.whex", src127), "-o", str(limpls["Wheelchair_1.3.127"])],
            cwd=src127,
        )
        compile_one("levelset/GCC_C", gcc_cmd(ldir / "levelset.c", limpls["GCC_C"]))
        compile_one("levelset/GFortran", gfortran_cmd(ldir / "levelset.f90", limpls["GFortran"]))
        compile_one("levelset/C_ceiling", gcc_cmd(ldir / "levelset_ceiling.c", limpls["C_ceiling"]))
        compile_one("levelset/Fortran_ceiling", gfortran_cmd(ldir / "levelset_ceiling.f90", limpls["Fortran_ceiling"]))
        cases.append({
            "group": "support", "workload": "levelset_two_regions", "arg": DOMAIN_N,
            "impls": limpls, "baseline": "GCC_C",
        })

        with (OUT / "compile_log.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["label", "compile_ms", "returncode", "stdout", "stderr", "cwd", "command"])
            w.writerows(compile_rows)

        def run_exe(exe, arg):
            cmd = ["taskset", "-c", str(CPU), str(exe), str(arg)]
            t0 = time.perf_counter_ns()
            cp = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            dt = (time.perf_counter_ns() - t0) / 1e6
            if cp.returncode != 0:
                raise RuntimeError(
                    f"run failed ({cp.returncode}): {cmd!r}\n"
                    f"stdout={cp.stdout!r}\nstderr={cp.stderr!r}"
                )
            return dt, cp.stdout.strip(), cp.stderr.strip()

        raw = []
        for case in cases:
            names = list(case["impls"])
            for name in names:
                run_exe(case["impls"][name], case["arg"])
            for rep in range(REPS):
                shift = rep % len(names)
                order = names[shift:] + names[:shift]
                for order_index, name in enumerate(order):
                    ms, stdout, stderr = run_exe(case["impls"][name], case["arg"])
                    raw.append([
                        case["group"], case["workload"], rep, order_index, name,
                        case["arg"], CPU, ms, stdout, stderr,
                    ])

        with (OUT / "raw.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["group", "workload", "rep", "order_index", "implementation", "problem_size", "cpu", "wall_ms", "stdout", "stderr"])
            w.writerows(raw)

        summary = []
        for case in cases:
            medians = {}
            for name in case["impls"]:
                xs = [r[7] for r in raw if r[1] == case["workload"] and r[4] == name]
                medians[name] = statistics.median(xs)
            cmed = medians[case["baseline"]]
            for name in case["impls"]:
                rows = [r for r in raw if r[1] == case["workload"] and r[4] == name]
                xs = [r[7] for r in rows]
                med = statistics.median(xs)
                mad = statistics.median(abs(x - med) for x in xs)
                outputs = sorted({r[8] for r in rows})
                summary.append([
                    case["group"], case["workload"], name, case["arg"], len(xs),
                    min(xs), med, statistics.mean(xs), max(xs), statistics.pstdev(xs), mad,
                    med / cmed, cmed / med, json.dumps(outputs, ensure_ascii=False),
                ])

        with (OUT / "summary.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["group", "workload", "implementation", "problem_size", "reps", "min_ms", "median_ms", "mean_ms", "max_ms", "stdev_ms", "mad_ms", "time_over_C", "speedup_over_C", "unique_stdout"])
            w.writerows(summary)

        lines = [
            "# Wheelchair 1.3.127 paper pilot results", "",
            f"Pinned logical CPU: `{CPU}`. Measured repetitions: `{REPS}`. Whole-process wall time.", "",
            "| workload | implementation | median ms | MAD ms | time/C | speedup/C |",
            "|---|---|---:|---:|---:|---:|",
        ]
        for row in summary:
            lines.append(f"| {row[1]} | {row[2]} | {row[6]:.6f} | {row[10]:.6f} | {row[11]:.4f} | {row[12]:.4f} |")
        (OUT / "RESULTS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        print((OUT / "RESULTS.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
