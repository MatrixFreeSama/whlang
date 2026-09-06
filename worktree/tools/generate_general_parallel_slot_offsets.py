#!/usr/bin/env python3
"""Derive patch offsets for the generic direct-general causal program_slot.

Build-time only. User programs never invoke nm/objcopy/ld; wheelchairc reads the
resulting raw template and this JSON map.
"""
from __future__ import annotations
import json, subprocess, sys
from pathlib import Path

NAMES=(
    'gp_slot_base','gp_node_count','gp_edge_count','gp_slot_count',
    'gp_home_slots','gp_indegree','gp_first_out','gp_edge_v','gp_next_edge',
    'gp_entry_offsets','gp_home_initial','gp_template_end',
)

def main() -> int:
    if len(sys.argv)!=4:
        raise SystemExit('usage: generate_general_parallel_slot_offsets.py SLOT_ELF SLOT_BIN OUT_JSON')
    elf=Path(sys.argv[1]); raw=Path(sys.argv[2]); out=Path(sys.argv[3])
    text=subprocess.check_output(['nm','-n',str(elf)],text=True)
    symbols={}
    for line in text.splitlines():
        parts=line.split()
        if len(parts)>=3 and parts[2] in NAMES:
            symbols[parts[2]]=int(parts[0],16)
    missing=[n for n in NAMES if n not in symbols]
    if missing:
        raise SystemExit('missing general-parallel slot symbols: '+', '.join(missing))
    if symbols['gp_slot_base']!=0:
        raise SystemExit(f'gp_slot_base must link at offset zero, got {symbols["gp_slot_base"]:#x}')
    raw_size=raw.stat().st_size
    if raw_size!=symbols['gp_template_end']:
        raise SystemExit(f'raw template size {raw_size} != gp_template_end {symbols["gp_template_end"]}')
    payload={
        'format':'wheelchair.general_parallel_slot_offsets/1',
        'template_size':raw_size,
        'program_slot_capacity':131072,
        'max_nodes':96,
        'max_edges':1024,
        'max_slots':4,
        'offsets':{k:v for k,v in symbols.items()},
    }
    out.write_text(json.dumps(payload,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    print('GENERAL_PARALLEL_SLOT_OFFSETS=DERIVED')
    return 0
if __name__=='__main__':
    raise SystemExit(main())
