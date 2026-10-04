#!/usr/bin/env python3
import csv
import json
import math
import os
import platform
import re
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
OUT.mkdir(parents=True, exist_ok=True)
BUILD = OUT / "_build"
if BUILD.exists():
    shutil.rmtree(BUILD)
BUILD.mkdir(parents=True)

REPS = 15
GENERAL_STEPS = 20_000_000
DOMAIN_N = 8_000_000
CPU = min(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else 0


def sh(cmd, cwd=None, check=True):
    cp = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and cp.returncode != 0:
        raise RuntimeError(f"command failed ({cp.returncode}): {' '.join(map(str, cmd))}\nstdout:\n{cp.stdout}\nstderr:\n{cp.stderr}")
    return cp


def capture(cmd):
    cp = sh(cmd, check=False)
    return f"$ {' '.join(cmd)}\n{cp.stdout}{cp.stderr}\n"


def extract(version):
    archive = ROOT / "dist" / f"Wheelchair-{version}.zip"
    if not archive.exists():
        raise FileNotFoundError(archive)
    dest = BUILD / f"w{version.replace('.', '_')}"
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(dest)
    preferred = dest / f"Wheelchair-{version}"
    if preferred.is_dir():
        src = preferred
    else:
        dirs = [p for p in dest.iterdir() if p.is_dir()]
        src = dirs[0] if len(dirs) == 1 else dest
    compiler = src / "bin" / "wheelchairc"
    compiler.chmod(compiler.stat().st_mode | 0o111)
    return src, compiler


SRC127, WH127 = extract("1.3.127")
SRC126, WH126 = extract("1.3.126")


def compiler_version(cmd, cwd):
    for arg in ("--version", "-V", "-v"):
        cp = sh([str(cmd), arg], cwd=cwd, check=False)
        text = (cp.stdout + cp.stderr).strip()
        if text:
            return text[:2000]
    return "version flag produced no text"


env_text = []
env_text.append(f"paper_snapshot=Wheelchair-1.3.127\n")
env_text.append(f"repo_commit={sh(['git','rev-parse','HEAD']).stdout.strip()}\n")
env_text.append(f"cpu_affinity={CPU}\n")
env_text.append(f"python={sys.version}\n")
env_text.append(f"platform={platform.platform()}\n")
for cmd in (["uname", "-a"], ["lscpu"], ["gcc", "--version"], ["gfortran", "--version"], ["ld", "--version"]):
    env_text.append(capture(cmd))
env_text.append("Wheelchair 1.3.127 compiler:\n" + compiler_version(WH127, SRC127) + "\n")
env_text.append("Wheelchair 1.3.126 compiler:\n" + compiler_version(WH126, SRC126) + "\n")
(OUT / "environment.txt").write_text("\n".join(env_text), encoding="utf-8")

compile_rows = []


def compile_one(label, cmd, optional=False, cwd=None):
    t0 = time.perf_counter_ns()
    cp = sh(cmd, cwd=cwd, check=False)
    ms = (time.perf_counter_ns() - t0) / 1e6
    compile_rows.append([label, ms, cp.returncode, cp.stdout.strip(), cp.stderr.strip(), str(cwd or ""), " ".join(map(str, cmd))])
    if cp.returncode != 0 and not optional:
        raise RuntimeError(f"compile failed ({cp.returncode}): {label}\n{cp.stdout}\n{cp.stderr}")
    return cp.returncode == 0


def gcc_cmd(src, out):
    return ["gcc", "-O3", "-march=native", "-fno-fast-math", "-ffp-contract=off", str(src), "-lm", "-o", str(out)]


def gfortran_cmd(src, out):
    return ["gfortran", "-O3", "-march=native", "-fno-fast-math", "-ffp-contract=off", "-fprotect-parens", str(src), "-o", str(out)]


cases = []
sources_out = OUT / "sources"
sources_out.mkdir(exist_ok=True)

# A. Scalar/deep-causal negative controls.
gdir = SRC127 / "devtrash" / "benchmarks" / "math_generalization_1344"
for kernel in ("mass3", "chem6", "rigid7"):
    kd = BUILD / f"general_{kernel}"
    kd.mkdir()
    copied = sources_out / "general"
    copied.mkdir(exist_ok=True)
    for ext in ("wh", "c", "f90"):
        shutil.copy2(gdir / f"{kernel}.{ext}", copied / f"{kernel}.{ext}")
    wh = kd / "wheelchair"
    cc = kd / "c"
    ff = kd / "fortran"
    compile_one(f"general/{kernel}/Wheelchair_1.3.127", [str(WH127), str(gdir / f"{kernel}.wh"), "-o", str(wh)], cwd=SRC127)
    compile_one(f"general/{kernel}/GCC_C", gcc_cmd(gdir / f"{kernel}.c", cc))
    compile_one(f"general/{kernel}/GFortran", gfortran_cmd(gdir / f"{kernel}.f90", ff))
    cases.append({"group":"general_negative", "workload":kernel, "arg":GENERAL_STEPS,
                  "impls":{"Wheelchair_1.3.127":wh, "GCC_C":cc, "GFortran":ff}, "baseline":"GCC_C"})

# B. Localized plasticity, including 1.3.126 mechanism ablation and manual ceilings.
pdir = SRC127 / "devtrash" / "benchmarks" / "localized_plasticity_13127"
pso = sources_out / "localized_plasticity"
pso.mkdir(exist_ok=True)
for name in ("plasticity.whex", "plasticity.c", "plasticity.f90", "plasticity_ceiling.c", "plasticity_ceiling.f90", "README.md"):
    shutil.copy2(pdir / name, pso / name)
pb = BUILD / "plasticity"
pb.mkdir()
impls = {}
impls["Wheelchair_1.3.127"] = pb / "wheelchair_127"
compile_one("plasticity/Wheelchair_1.3.127", [str(WH127), str(pdir / "plasticity.whex"), "-o", str(impls["Wheelchair_1.3.127"])], cwd=SRC127)
impls["Wheelchair_1.3.126"] = pb / "wheelchair_126"
if not compile_one("plasticity/Wheelchair_1.3.126", [str(WH126), str(pdir / "plasticity.whex"), "-o", str(impls["Wheelchair_1.3.126"])], optional=True, cwd=SRC126):
    impls.pop("Wheelchair_1.3.126")
impls["GCC_C"] = pb / "c"
impls["GFortran"] = pb / "fortran"
impls["C_ceiling"] = pb / "c_ceiling"
impls["Fortran_ceiling"] = pb / "fortran_ceiling"
compile_one("plasticity/GCC_C", gcc_cmd(pdir / "plasticity.c", impls["GCC_C"]))
compile_one("plasticity/GFortran", gfortran_cmd(pdir / "plasticity.f90", impls["GFortran"]))
compile_one("plasticity/C_ceiling", gcc_cmd(pdir / "plasticity_ceiling.c", impls["C_ceiling"]))
compile_one("plasticity/Fortran_ceiling", gfortran_cmd(pdir / "plasticity_ceiling.f90", impls["Fortran_ceiling"]))
cases.append({"group":"support", "workload":"localized_plasticity", "arg":DOMAIN_N, "impls":impls, "baseline":"GCC_C"})

# C. Disconnected Level-Set / VOF support.
ldir = SRC127 / "devtrash" / "benchmarks" / "levelset_regionset_13126"
lso = sources_out / "levelset_regionset"
lso.mkdir(exist_ok=True)
for name in ("levelset_two_regions.whex", "levelset.c", "levelset.f90", "levelset_ceiling.c", "levelset_ceiling.f90"):
    shutil.copy2(ldir / name, lso / name)
lb = BUILD / "levelset"
lb.mkdir()
limpls = {
    "Wheelchair_1.3.127": lb / "wheelchair",
    "GCC_C": lb / "c",
    "GFortran": lb / "fortran",
    "C_ceiling": lb / "c_ceiling",
    "Fortran_ceiling": lb / "fortran_ceiling",
}
compile_one("levelset/Wheelchair_1.3.127", [str(WH127), str(ldir / "levelset_two_regions.whex"), "-o", str(limpls["Wheelchair_1.3.127"])], cwd=SRC127)
compile_one("levelset/GCC_C", gcc_cmd(ldir / "levelset.c", limpls["GCC_C"]))
compile_one("levelset/GFortran", gfortran_cmd(ldir / "levelset.f90", limpls["GFortran"]))
compile_one("levelset/C_ceiling", gcc_cmd(ldir / "levelset_ceiling.c", limpls["C_ceiling"]))
compile_one("levelset/Fortran_ceiling", gfortran_cmd(ldir / "levelset_ceiling.f90", limpls["Fortran_ceiling"]))
cases.append({"group":"support", "workload":"levelset_two_regions", "arg":DOMAIN_N, "impls":limpls, "baseline":"GCC_C"})

with (OUT / "compile_log.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["label", "compile_ms", "returncode", "stdout", "stderr", "cwd", "command"])
    w.writerows(compile_rows)


def run_exe(exe, arg):
    t0 = time.perf_counter_ns()
    cp = subprocess.run(["taskset", "-c", str(CPU), str(exe), str(arg)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    dt = (time.perf_counter_ns() - t0) / 1e6
    if cp.returncode != 0:
        raise RuntimeError(f"run failed: {exe} {arg}\nstdout={cp.stdout}\nstderr={cp.stderr}")
    return dt, cp.stdout.strip(), cp.stderr.strip()


raw = []
for case in cases:
    names = list(case["impls"].keys())
    # Warm each implementation exactly once.
    for name in names:
        run_exe(case["impls"][name], case["arg"])
    for rep in range(REPS):
        shift = rep % len(names)
        order = names[shift:] + names[:shift]
        for order_index, name in enumerate(order):
            ms, stdout, stderr = run_exe(case["impls"][name], case["arg"])
            raw.append([case["group"], case["workload"], rep, order_index, name, case["arg"], CPU, ms, stdout, stderr])

with (OUT / "raw.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["group", "workload", "rep", "order_index", "implementation", "problem_size", "cpu", "wall_ms", "stdout", "stderr"])
    w.writerows(raw)

summary = []
for case in cases:
    base_name = case["baseline"]
    medians = {}
    for name in case["impls"]:
        xs = [r[7] for r in raw if r[1] == case["workload"] and r[4] == name]
        medians[name] = statistics.median(xs)
    base = medians[base_name]
    for name in case["impls"]:
        rows = [r for r in raw if r[1] == case["workload"] and r[4] == name]
        xs = [r[7] for r in rows]
        med = statistics.median(xs)
        mad = statistics.median([abs(x - med) for x in xs])
        outputs = sorted({r[8] for r in rows})
        summary.append([
            case["group"], case["workload"], name, case["arg"], len(xs),
            min(xs), med, statistics.mean(xs), max(xs), statistics.pstdev(xs), mad,
            med / base, base / med, json.dumps(outputs, ensure_ascii=False),
        ])

with (OUT / "summary.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["group", "workload", "implementation", "problem_size", "reps", "min_ms", "median_ms", "mean_ms", "max_ms", "stdev_ms", "mad_ms", "time_over_C", "speedup_over_C", "unique_stdout"])
    w.writerows(summary)

# Markdown table for immediate inspection.
lines = ["# Pilot results", "", f"Pinned CPU: `{CPU}`. Repetitions: `{REPS}`.", "",
         "| workload | implementation | median ms | MAD ms | time/C | speedup/C |",
         "|---|---|---:|---:|---:|---:|"]
for row in summary:
    lines.append(f"| {row[1]} | {row[2]} | {row[6]:.6f} | {row[10]:.6f} | {row[11]:.4f} | {row[12]:.4f} |")
(OUT / "RESULTS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

# Do not keep generated binaries or extracted compilers in the committed experiment directory.
shutil.rmtree(BUILD)
print((OUT / "RESULTS.md").read_text(encoding="utf-8"))
