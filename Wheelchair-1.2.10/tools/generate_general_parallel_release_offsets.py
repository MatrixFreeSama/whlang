#!/usr/bin/env python3
"""Derive patch offsets for the Wheelchair 1.2.9 blind-release program slot."""
from __future__ import annotations
import json, subprocess, sys
from pathlib import Path

NAMES = (
    "gr_release_base", "gr_node_count", "gr_edge_count", "gr_cpu_width",
    "gr_indegree", "gr_first_out", "gr_edge_v", "gr_next_edge",
    "gr_entry_offsets", "gr_template_end",
)

def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: generate_general_parallel_release_offsets.py ELF BIN OUT_JSON")
    elf = Path(sys.argv[1]); raw = Path(sys.argv[2]); out = Path(sys.argv[3])
    text = subprocess.check_output(["nm", "-n", str(elf)], text=True)
    symbols: dict[str, int] = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] in NAMES:
            symbols[parts[2]] = int(parts[0], 16)
    missing = [n for n in NAMES if n not in symbols]
    if missing:
        raise SystemExit("missing blind-release symbols: " + ", ".join(missing))
    if symbols["gr_release_base"] != 0:
        raise SystemExit(f"gr_release_base must link at offset zero, got {symbols['gr_release_base']:#x}")
    raw_size = raw.stat().st_size
    if raw_size != symbols["gr_template_end"]:
        raise SystemExit(f"raw template size {raw_size} != gr_template_end {symbols['gr_template_end']}")
    payload = {
        "format": "wheelchair.general_parallel_release_offsets/1",
        "template_size": raw_size,
        "program_slot_capacity": 131072,
        "max_nodes": 96,
        "max_edges": 1024,
        "max_cpu_width": 4,
        "offsets": {k: v for k, v in symbols.items()},
    }
    out.write_text(json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("GENERAL_PARALLEL_RELEASE_OFFSETS=DERIVED")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
