#!/usr/bin/env python3
import array
import csv
import json
import math
import os
import platform
import re
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "experiments" / "paper_1_3_127" / "expansion_v1_20261005"
REPS = 15
CPU = min(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else 0
HE_N = 50_000_000
FIELD_N = 256
PERIODIC_N = 16_000_000


def sh(cmd, cwd=None, env=None, check=True):
    cp = subprocess.run(cmd, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and cp.returncode != 0:
        raise RuntimeError(
            f"command failed ({cp.returncode}): {' '.join(map(str, cmd))}\n"
            f"cwd={cwd}\nstdout:\n{cp.stdout}\nstderr:\n{cp.stderr}"
        )
    return cp


def capture(cmd):
    cp = sh(cmd, check=False)
    return f"$ {' '.join(map(str, cmd))}\n{cp.stdout}{cp.stderr}\n"


def unpack_127(work):
    archive = ROOT / "dist" / "Wheelchair-1.3.127.zip"
    dest = work / "w127"
    dest.mkdir(parents=True)
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(dest)
    root = dest / "Wheelchair-1.3.127"
    if not root.is_dir():
        dirs = [p for p in dest.iterdir() if p.is_dir()]
        root = dirs[0] if len(dirs) == 1 else dest
    for name in ("topologyc-native256", "fieldc-native256", "whexc", "fieldc"):
        p = root / "bin" / name
        if p.exists():
            p.chmod(p.stat().st_mode | 0o111)
    return root


def rel(path, root):
    return os.path.relpath(path, root)


def gcc_cmd(src, out, openmp=False):
    cmd = ["gcc", "-O3", "-march=x86-64-v3", "-mtune=generic",
           "-fno-fast-math", "-ffp-contract=off"]
    if openmp:
        cmd.append("-fopenmp")
    cmd += [str(src), "-lm", "-o", str(out)]
    return cmd


def gfortran_cmd(src, out, openmp=False):
    cmd = ["gfortran", "-O3", "-march=x86-64-v3", "-mtune=generic",
           "-fno-fast-math", "-ffp-contract=off", "-fprotect-parens"]
    if openmp:
        cmd.append("-fopenmp")
    cmd += [str(src), "-o", str(out)]
    return cmd


def write_whfld217(path, n):
    total = n * n * n
    header = bytearray(256)
    header[0:8] = b"WHFLD217"
    struct.pack_into("<I", header, 8, 2)      # version
    struct.pack_into("<I", header, 12, 1)     # f32
    struct.pack_into("<Q", header, 16, 3)     # rank
    struct.pack_into("<Q", header, 24, 256)   # data offset
    struct.pack_into("<Q", header, 32, total)
    struct.pack_into("<Q", header, 40, 0)
    extents = (n, n, n)
    strides = (n * n * 4, n * 4, 4)
    for i, x in enumerate(extents):
        struct.pack_into("<Q", header, 64 + 8 * i, x)
    for i, x in enumerate(strides):
        struct.pack_into("<Q", header, 64 + 8 * 3 + 8 * i, x)

    vals = array.array("f", (((i * 37 + 11) & 4095) / 4096.0 for i in range(4096)))
    if sys.byteorder != "little":
        vals.byteswap()
    block = vals.tobytes()
    q, r = divmod(total, 4096)
    with path.open("wb") as f:
        f.write(header)
        for _ in range(q):
            f.write(block)
        if r:
            f.write(block[:r * 4])


def parse_checksum(text):
    m32 = re.search(r"checksum_f32_bits=0x([0-9a-fA-F]{8})", text)
    if m32:
        bits = int(m32.group(1), 16)
        return "f32", bits, struct.unpack("<f", bits.to_bytes(4, "little"))[0]
    m64 = re.search(r"checksum_bits=0x([0-9a-fA-F]{16})", text)
    if m64:
        bits = int(m64.group(1), 16)
        return "f64", bits, struct.unpack("<d", bits.to_bytes(8, "little"))[0]
    return None, None, None


def rx_payload_size(path):
    cp = sh(["readelf", "-lW", str(path)], check=False)
    n = 0
    for line in cp.stdout.splitlines():
        parts = line.split()
        if parts and parts[0] == "LOAD" and "R" in parts and "E" in parts:
            n += 1
            if n == 2 and len(parts) >= 5:
                try:
                    return int(parts[4], 16)
                except ValueError:
                    return None
    return None


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    source_out = OUT / "sources"
    source_out.mkdir()

    env_lines = [
        "paper_snapshot=Wheelchair-1.3.127",
        "experiment=cross-mechanism expansion v1",
        "isa_profile=x86-64-v3 / Wheelchair native256",
        f"repo_commit={sh(['git', 'rev-parse', 'HEAD']).stdout.strip()}",
        f"pinned_cpu={CPU}",
        f"python={sys.version}",
        f"platform={platform.platform()}",
        f"high_entropy_n={HE_N}",
        f"field_n={FIELD_N}",
        f"periodic_n={PERIODIC_N}",
        f"repetitions={REPS}",
    ]
    for cmd in (["uname", "-a"], ["lscpu"], ["gcc", "--version"], ["gfortran", "--version"], ["ld", "--version"]):
        env_lines.append(capture(cmd))
    (OUT / "environment.txt").write_text("\n".join(env_lines) + "\n", encoding="utf-8")

    compile_rows = []
    binary_rows = []
    cases = []

    def compile_one(label, cmd, cwd=None):
        t0 = time.perf_counter_ns()
        cp = sh(cmd, cwd=cwd, check=False)
        dt = (time.perf_counter_ns() - t0) / 1e6
        compile_rows.append([label, dt, cp.returncode, cp.stdout.strip(), cp.stderr.strip(), str(cwd or ""), " ".join(map(str, cmd))])
        if cp.returncode != 0:
            raise RuntimeError(f"compile failed: {label}\n{cp.stdout}\n{cp.stderr}")

    with tempfile.TemporaryDirectory(prefix="wheelchair-paper-expand-") as td:
        work = Path(td)
        wroot = unpack_127(work)
        bins = work / "bins"
        bins.mkdir()

        omp1 = os.environ.copy()
        omp1.update({
            "OMP_NUM_THREADS": "1",
            "OMP_PROC_BIND": "true",
            "OMP_PLACES": "cores",
            "OMP_WAIT_POLICY": "PASSIVE",
        })

        # D. High-entropy runtime-modulo permutation, retained from 1.3.102.
        hsrc = ROOT / "benchmarks" / "high_entropy_sparse_permutation_13102"
        hout = source_out / "high_entropy_sparse_permutation"
        shutil.copytree(hsrc, hout)
        hp = wroot / "paper_inputs"
        hp.mkdir(exist_ok=True)
        shutil.copy2(hsrc / "perm_strict.whex", hp / "perm_strict.whex")
        hd = bins / "high_entropy"
        hd.mkdir()
        himpls = {
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
        })

        # E. Established public simulation kernels: miniAMR-27 and miniFE heat21.
        fsrc = wroot / "devtrash" / "benchmarks" / "real_sparse_1326"
        fout = source_out / "real_sparse_1326"
        fout.mkdir()
        for name in ("README.md", "miniamr27.json", "miniamr27.c", "miniamr27.f90", "minife_heat21.json", "minife_heat21.c", "minife_heat21.f90"):
            shutil.copy2(fsrc / name, fout / name)
        field_file = work / f"paper_field_{FIELD_N}.whfld"
        write_whfld217(field_file, FIELD_N)
        (OUT / "field_input_sha256.txt").write_text(
            sh(["sha256sum", str(field_file)]).stdout.replace(str(field_file), field_file.name), encoding="utf-8"
        )

        for stem, label in (("miniamr27", "miniAMR_27point"), ("minife_heat21", "miniFE_heat21")):
            fd = bins / stem
            fd.mkdir()
            fimpls = {
                "Wheelchair_1.3.127_field_native256": fd / "wheelchair",
                "GCC_C_v3": fd / "c",
                "GFortran_v3": fd / "fortran",
            }
            compile_one(f"{stem}/Wheelchair_1.3.127_field_native256",
                        ["./bin/fieldc-native256", rel(fsrc / f"{stem}.json", wroot), "-o", str(fimpls["Wheelchair_1.3.127_field_native256"])], cwd=wroot)
            compile_one(f"{stem}/GCC_C_v3", gcc_cmd(fsrc / f"{stem}.c", fimpls["GCC_C_v3"], openmp=True))
            compile_one(f"{stem}/GFortran_v3", gfortran_cmd(fsrc / f"{stem}.f90", fimpls["GFortran_v3"], openmp=True))
            cases.append({
                "group": "field_real_miniapp", "workload": label, "baseline": "GCC_C_v3", "env": omp1,
                "commands": {
                    "Wheelchair_1.3.127_field_native256": [str(fimpls["Wheelchair_1.3.127_field_native256"]), str(field_file)],
                    "GCC_C_v3": [str(fimpls["GCC_C_v3"]), str(field_file), str(FIELD_N)],
                    "GFortran_v3": [str(fimpls["GFortran_v3"]), str(field_file), str(FIELD_N)],
                },
            })

        # F. Deep periodic CoordinateFact composition, retained from 1.3.124.
        psrc = wroot / "devtrash" / "benchmarks" / "periodic_affine_aging_13124"
        pout = source_out / "periodic_affine_aging_13124"
        pout.mkdir()
        for name in ("README.md", "d23.whex", "d40.whex", "affine_natural.c", "affine_natural_generic.f90", "affine_ceiling.c", "affine_ceiling_generic.f90"):
            shutil.copy2(psrc / name, pout / name)
        pd = bins / "periodic"
        pd.mkdir()
        pcommon = {
            "GCC_C_v3": pd / "c_natural",
            "GFortran_v3": pd / "fortran_natural",
            "C_ceiling_v3": pd / "c_ceiling",
            "Fortran_ceiling_v3": pd / "fortran_ceiling",
        }
        compile_one("periodic/GCC_C_v3", gcc_cmd(psrc / "affine_natural.c", pcommon["GCC_C_v3"]))
        compile_one("periodic/GFortran_v3", gfortran_cmd(psrc / "affine_natural_generic.f90", pcommon["GFortran_v3"]))
        compile_one("periodic/C_ceiling_v3", gcc_cmd(psrc / "affine_ceiling.c", pcommon["C_ceiling_v3"]))
        compile_one("periodic/Fortran_ceiling_v3", gfortran_cmd(psrc / "affine_ceiling_generic.f90", pcommon["Fortran_ceiling_v3"]))

        for depth in (23, 40):
            wexe = pd / f"wheelchair_d{depth}"
            compile_one(f"periodic/d{depth}/Wheelchair_1.3.127_native256",
                        ["./bin/topologyc-native256", rel(psrc / f"d{depth}.whex", wroot), "-o", str(wexe)], cwd=wroot)
            commands = {
                "Wheelchair_1.3.127_native256": [str(wexe), str(PERIODIC_N)],
                "GCC_C_v3": [str(pcommon["GCC_C_v3"]), str(PERIODIC_N), str(depth)],
                "GFortran_v3": [str(pcommon["GFortran_v3"]), str(PERIODIC_N), str(depth)],
                "C_ceiling_v3": [str(pcommon["C_ceiling_v3"]), str(PERIODIC_N), str(depth)],
                "Fortran_ceiling_v3": [str(pcommon["Fortran_ceiling_v3"]), str(PERIODIC_N), str(depth)],
            }
            cases.append({
                "group": "coordinatefact_periodic", "workload": f"periodic_depth_{depth}",
                "baseline": "GCC_C_v3", "commands": commands, "env": os.environ.copy(),
            })

        # Binary metadata after all compilation.
        seen = set()
        for case in cases:
            for name, cmd in case["commands"].items():
                p = Path(cmd[0])
                key = (name, str(p))
                if key in seen:
                    continue
                seen.add(key)
                binary_rows.append([name, str(p.name), p.stat().st_size, rx_payload_size(p)])
        with (OUT / "binary_metadata.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f); w.writerow(["implementation", "binary", "elf_bytes", "generated_rx_bytes"]); w.writerows(binary_rows)
        with (OUT / "compile_log.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f); w.writerow(["label", "compile_ms", "returncode", "stdout", "stderr", "cwd", "command"]); w.writerows(compile_rows)

        def run_cmd(cmd, env):
            full = ["taskset", "-c", str(CPU)] + cmd
            t0 = time.perf_counter_ns()
            cp = subprocess.run(full, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            ms = (time.perf_counter_ns() - t0) / 1e6
            if cp.returncode != 0:
                raise RuntimeError(f"run failed ({cp.returncode}): {full!r}\nstdout={cp.stdout}\nstderr={cp.stderr}")
            return ms, cp.stdout.strip(), cp.stderr.strip()

        raw = []
        for case in cases:
            names = list(case["commands"])
            for name in names:
                run_cmd(case["commands"][name], case["env"])
            for rep in range(REPS):
                shift = rep % len(names)
                order = names[shift:] + names[:shift]
                for order_index, name in enumerate(order):
                    ms, stdout, stderr = run_cmd(case["commands"][name], case["env"])
                    kind, bits, value = parse_checksum(stdout)
                    raw.append([
                        case["group"], case["workload"], rep, order_index, name, CPU, ms,
                        stdout, stderr, kind or "", f"0x{bits:x}" if bits is not None else "", value if value is not None else "",
                    ])

        with (OUT / "raw.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["group", "workload", "rep", "order_index", "implementation", "cpu", "wall_ms", "stdout", "stderr", "checksum_kind", "checksum_bits", "checksum_value"])
            w.writerows(raw)

        summary = []
        for case in cases:
            base_rows = [r for r in raw if r[1] == case["workload"] and r[4] == case["baseline"]]
            base_times = [r[6] for r in base_rows]
            base_med = statistics.median(base_times)
            base_vals = [r[11] for r in base_rows if isinstance(r[11], float)]
            base_val = statistics.median(base_vals) if base_vals else None
            for name in case["commands"]:
                rows = [r for r in raw if r[1] == case["workload"] and r[4] == name]
                xs = [r[6] for r in rows]
                med = statistics.median(xs)
                mad = statistics.median(abs(x - med) for x in xs)
                outputs = sorted({r[7] for r in rows})
                vals = [r[11] for r in rows if isinstance(r[11], float)]
                val = statistics.median(vals) if vals else None
                relerr = ""
                if val is not None and base_val is not None and math.isfinite(val) and math.isfinite(base_val):
                    relerr = abs(val - base_val) / max(abs(base_val), 1e-300)
                summary.append([
                    case["group"], case["workload"], name, len(xs), min(xs), med,
                    statistics.mean(xs), max(xs), statistics.pstdev(xs), mad,
                    med / base_med, base_med / med, len(outputs), relerr,
                    json.dumps(outputs, ensure_ascii=False),
                ])

        with (OUT / "summary.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["group", "workload", "implementation", "reps", "min_ms", "median_ms", "mean_ms", "max_ms", "stdev_ms", "mad_ms", "time_over_C", "speedup_over_C", "unique_output_count", "relative_checksum_error_vs_C", "unique_stdout"])
            w.writerows(summary)

        lines = [
            "# Wheelchair 1.3.127 cross-mechanism paper pilot", "",
            "Frozen compiler: `Wheelchair 1.3.127`. High-entropy uses the existing `whexc` AVX-512 realization with x86-64-v4 C/Fortran controls; Field and periodic cases use native256 with x86-64-v3 controls. No speedup is aggregated across ISA profiles.",
            f"All timed processes are pinned to logical CPU `{CPU}`; C/Fortran OpenMP controls use one thread. Each implementation receives one warm-up and `{REPS}` interleaved measured repetitions.",
            "", "This table deliberately mixes wins and losses only across workloads run on this same hosted runner. It is pilot evidence, not the final fixed-machine submission table.", "",
            "| mechanism/workload | implementation | median ms | MAD ms | time/C | speedup/C | checksum rel. error vs C |",
            "|---|---|---:|---:|---:|---:|---:|",
        ]
        for r in summary:
            err = "-" if r[13] == "" else f"{r[13]:.3e}"
            lines.append(f"| {r[1]} | {r[2]} | {r[5]:.6f} | {r[9]:.6f} | {r[10]:.4f} | {r[11]:.4f} | {err} |")
        lines += [
            "", "## Interpretation guardrails", "",
            "- `high_entropy_6perm_v4` is the retained runtime-modulo physical-work-inflation witness. The frozen `whexc` product uses AVX-512, so only x86-64-v4 C/Fortran controls are compared with it; it is not mixed with the v3 tables.",
            "- `miniAMR_27point` and `miniFE_heat21` are established public simulation kernels; the same generated WHFLD217 bytes are consumed by Wheelchair, C, and Fortran.",
            "- `periodic_depth_23/40` isolate CoordinateFact composition. The natural C/Fortran controls explicitly materialize every remap stage; the ceiling controls manually compose the affine relation and are labeled ceilings, not natural baselines.",
            "- No compiler source is modified by this experiment. No workload-specific branch is added.",
        ]
        (OUT / "RESULTS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
