#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/elimination

# Retained 1.0.6 computation-elimination proof, now audited in the exact-size
# sectionless AOT RX segment emitted by Wheelchair 1.0.9.
./whexc tests/whex/fem_parallel_elimination.whex -o build/elimination/fem --executors 1 >/dev/null
[ "$(build/elimination/fem 262144)" = 'checksum_bits=0xc05ccc38e38e39d8' ]

RAW_P_OCCURRENCES=$(grep -oE 'p[012]\[' tests/whex/fem_parallel_elimination.whex | wc -l | tr -d ' ')
[ "$RAW_P_OCCURRENCES" -eq 51 ]

./whexc tests/whex/elimination_cancel.whex -o build/elimination/cancel --executors 1 >/dev/null
[ "$(build/elimination/cancel 8)" = 'checksum_bits=0x0000000000000000' ]

python3 - <<'PYCODE'
from pathlib import Path
import re, struct, subprocess, tempfile

INC=Path('compiler/runtime_offsets.inc').read_text()
def equ(name):
    m=re.search(rf'^\.equ\s+{re.escape(name)},\s*(0x[0-9a-fA-F]+|\d+)',INC,re.M)
    assert m,name
    return int(m.group(1),0)

def stub_target(blob,off):
    disp=struct.unpack_from('<i',blob,off+1)[0]
    return 0x400000+off+5+disp

def vector_regions(path):
    blob=Path(path).read_bytes()
    vec=stub_target(blob,equ('RUNTIME_VEC_OFF'))
    ini=stub_target(blob,equ('RUNTIME_VEC_INIT_OFF'))
    gen_off=equ('RUNTIME_GENERATED_FILE_OFF')
    gen_va=equ('RUNTIME_GENERATED_VA')
    with tempfile.NamedTemporaryFile() as f:
        f.write(blob[gen_off:]); f.flush()
        raw=subprocess.check_output(
            ['objdump','-D','-b','binary','-m','i386:x86-64','-M','intel',
             f'--adjust-vma=0x{gen_va:x}',f'--start-address=0x{vec:x}',
             f'--stop-address=0x{ini:x}',f.name],text=True)
    rows=[]
    for line in raw.splitlines():
        m=re.match(r'^\s*([0-9a-fA-F]+):\s+(.*)$',line)
        if m: rows.append((int(m.group(1),16),line,m.group(2)))
    # 1.0.15 region partition: both Jcc edges point at the exact boundary body.
    safe=None; fast_start=None
    for i,(addr,line,ins) in enumerate(rows):
        m=re.search(r'\bje\s+0x([0-9a-fA-F]+)',ins)
        if not m: continue
        safe=int(m.group(1),16)
        for j in range(i+1,min(i+8,len(rows))):
            m2=re.search(r'\bjae\s+0x([0-9a-fA-F]+)',rows[j][2])
            if m2 and int(m2.group(1),16)==safe:
                fast_start=rows[j+1][0]
                break
        if fast_start is not None: break
    assert safe is not None and fast_start is not None,(path,safe,fast_start)
    common=None
    for addr,line,ins in rows:
        if not (fast_start <= addr < safe): continue
        m=re.search(r'\bjmp\s+0x([0-9a-fA-F]+)',ins)
        if m and int(m.group(1),16)>safe:
            common=int(m.group(1),16)
    assert common is not None,(path,safe,fast_start)
    return {
        'interior':'\n'.join(line for addr,line,ins in rows if fast_start <= addr < safe)+'\n',
        'boundary':'\n'.join(line for addr,line,ins in rows if safe <= addr < common)+'\n',
    }

fem_regions=vector_regions('build/elimination/fem')
for name,fem in fem_regions.items():
    Path(f'build/elimination/fem_{name}.asm').write_text(fem)
    counts=[]
    for r in range(4):
        c=len(re.findall(rf'vfmadd231pd\s+zmm{r},zmm4,',fem))
        assert c==9,(name,r,c)
        counts.append(c)
    assert sum(counts)==36,(name,counts)
    assert len(re.findall(r'\bvaddpd\b',fem))==3,(name,len(re.findall(r'\bvaddpd\b',fem)))
    assert not re.search(r'\b(?:lock|mfence|sfence|lfence|xchg)\b',fem),name

cancel_regions=vector_regions('build/elimination/cancel')
for name,cancel in cancel_regions.items():
    Path(f'build/elimination/cancel_{name}.asm').write_text(cancel)
    assert not re.search(r'\b(?:vfmadd231pd|vmulpd|vdivpd|vpmullq|vpandq)\b',cancel),name
    assert len(re.findall(r'\bvpaddq\b',cancel))==0,(name,cancel)
PYCODE
echo 'COMPUTATION_ELIMINATION=PASS'
echo 'ELIMINATION_WORK_STRICTLY_DECREASES=PASS'
echo 'ELIMINATION_ZERO_FILL=PASS'
echo 'ELIMINATION_PARALLEL_WIDTH_PRESERVED=PASS'
echo 'ELIMINATION_NO_NEW_SYNC=PASS'
echo 'ELIMINATION_EXACT_CANCELLATION=PASS'
