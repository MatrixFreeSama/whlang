#!/usr/bin/env python3
"""AOT compiler-image selection for Wheelchair 1.2.7.

The sovereign topology compiler's silicon audit is the hardware authority. This
module only binds two orthogonal compile-time facts:
  * generic graph-resource class: base / wide / derived
  * physical vector shape: native256 / split512x256 / native512

No workload name, source path, benchmark identity, runtime timing, or profitability
measurement participates in selection. The selected compiler emits the final static
ELF before the user program starts; there is no runtime backend selector.
"""
from __future__ import annotations
import json
import subprocess
from pathlib import Path
from typing import Any


class NativeBackendMatrixError(RuntimeError):
    pass


_SHAPE_BY_ID = {
    1: "native256",
    2: "split512x256",
    3: "native512",
}

_MATRIX = {
    "native256": {
        "base": "topologyc-native256",
        "wide": "topologyc-wide-native256",
        "derived": "topologyc-derived-native256",
    },
    "split512x256": {
        "base": "topologyc",
        "wide": "topologyc-wide",
        "derived": "topologyc-derived",
    },
    "native512": {
        "base": "topologyc",
        "wide": "topologyc-wide",
        "derived": "topologyc-derived",
    },
}


def _run_text(exe: Path, arg: str) -> str:
    p = subprocess.run(
        [str(exe), arg],
        cwd=exe.parent.parent,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if p.returncode:
        detail = (p.stderr or p.stdout).strip()
        raise NativeBackendMatrixError(f"native silicon audit failed: {detail}")
    return p.stdout


def native_silicon_state(root: Path) -> dict[str, Any]:
    """Read physical shape from the native compiler, never from workload data."""
    topologyc = root / "build" / "topologyc"
    if not topologyc.is_file():
        raise NativeBackendMatrixError("build/topologyc is missing; run build.sh first")
    try:
        audit = json.loads(_run_text(topologyc, "--silicon-audit"))
    except json.JSONDecodeError as exc:
        raise NativeBackendMatrixError(f"invalid native silicon audit JSON: {exc}") from exc
    probe = _run_text(topologyc, "--probe")

    shape = _SHAPE_BY_ID.get(int(audit.get("physical_vector_shape_id", 0)), "unknown")
    if shape == "unknown":
        # Unknown vendors are still admitted by architectural capability. This
        # fallback consumes the native compiler's probe, not a Python CPUID model.
        if "AVX-512F: usable" in probe:
            shape = "native512"
        elif "AVX2: available" in probe:
            shape = "native256"

    return {
        "shape": shape,
        "audit": audit,
        "probe": probe,
    }


def select_compiler(
    root: Path,
    resource_profile: dict[str, Any],
    *,
    isa_limit: str | None = None,
) -> tuple[Path, dict[str, Any]]:
    """Return the AOT compiler image and an auditable workload-blind decision."""
    cls = str(resource_profile.get("backend_class", "base"))
    if cls not in ("base", "wide", "derived"):
        raise NativeBackendMatrixError(f"unknown generic resource class {cls!r}")

    state = native_silicon_state(root)
    shape = state["shape"]

    # --isa-limit is a capability ceiling used for audit/testing. AVX2 narrows
    # the physicalizer to native256. Higher ceilings never manufacture AVX-512
    # on a 256-bit host and therefore preserve the audited physical shape.
    if isa_limit == "avx2":
        shape = "native256"
    elif isa_limit not in (None, "native", "avx512f", "avx512dq"):
        raise NativeBackendMatrixError(f"unsupported ISA ceiling {isa_limit!r}")

    if shape not in _MATRIX:
        raise NativeBackendMatrixError(
            "no proven vector physicalizer for this host; scalar fallback is forbidden"
        )

    compiler = root / "build" / _MATRIX[shape][cls]
    if not compiler.is_file():
        raise NativeBackendMatrixError(f"selected compiler image is missing: {compiler.name}")

    audit = state["audit"]
    decision = {
        "backend_class": cls,
        "physical_shape": shape,
        "compiler_image": compiler.name,
        "selection_authority": "native_topologyc_silicon_audit",
        "native_audit_shape_id": int(audit.get("physical_vector_shape_id", 0)),
        "native_audit_profile": audit.get("silicon_profile"),
        "isa_limit": isa_limit or "native",
        "aot_only": True,
        "workload_dispatch": 0,
        "source_path_dispatch": 0,
        "benchmark_dispatch": 0,
        "runtime_selector": 0,
        "runtime_profitability_selector": 0,
        "scalar_fallback": 0,
        "python_native_authority": False,
    }
    return compiler, decision
