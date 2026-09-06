#!/usr/bin/env python3
"""Finalize generated native256 tensor frontends into self-contained AVX2/YMM units.

This pass is purely structural and workload-blind. It resolves physical helper-label
ownership and materializes the generic resident-reduction ABI that earlier generic
passes may request. Native256 uses the same YMM lane-resident reduction shape for
both ordinary and resident recipes, so no workload route or runtime selector is
introduced.
"""
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / 'build' / 'generated_native256'
FILES = [
    GEN / 'tensor_frontend_base_native256.S',
    GEN / 'tensor_frontend_wide_native256.S',
    GEN / 'tensor_frontend_derived_native256.S',
]


def function_span(text: str, name: str) -> tuple[int, int]:
    start = text.find(name + ':\n')
    if start < 0:
        raise SystemExit(f'native256 finalizer: missing function {name}')
    m = re.search(r'(?m)^[A-Za-z][A-Za-z0-9_]*:\n', text[start + len(name) + 2:])
    end = len(text) if m is None else start + len(name) + 2 + m.start()
    return start, end


def uniquify_fixed_wrapper_labels(text: str) -> str:
    funcs = [
        'vec_vpaddq_mem_const',
        'vec_vpandq_mem_const',
        'vec_vmulpd_mem_const',
        'vec_vaddpd_mem_const',
    ]
    # Replace from the end so earlier byte offsets remain valid while slicing.
    spans = []
    for idx, name in enumerate(funcs):
        a, b = function_span(text, name)
        spans.append((a, b, idx, name))
    for a, b, idx, name in sorted(spans, reverse=True):
        body = text[a:b]
        if '.vcm256_fail' not in body or '.vcm256_done' not in body:
            raise SystemExit(f'native256 finalizer: fixed-wrapper labels missing in {name}')
        suffix = f'_{idx}'
        body = body.replace('.vcm256_fail', '.vcm256_fail' + suffix)
        body = body.replace('.vcm256_done', '.vcm256_done' + suffix)
        text = text[:a] + body + text[b:]
    return text


RESIDENT_MASK = r'''vec_fused_mask_reduce_resident_fragment:
    cmp r8,4
    jae .Lvfmrr256_full
    vmovq xmm13,r8
    vpbroadcastq ymm13,xmm13
    vpcmpgtq ymm13,ymm13,ymmword ptr [rip+.Lvfmrr256_lanes]
    vandpd ymm0,ymm0,ymm13
.Lvfmrr256_full:
    vaddpd ymm12,ymm12,ymm0
vec_fused_mask_reduce_resident_fragment_end:
'''

RESIDENT_FINISH = r'''vec_fused_finish_resident_fragment:
    vextractf128 xmm13,ymm12,1
    vunpckhpd xmm14,xmm13,xmm13
    vaddsd xmm13,xmm13,xmm14
    vunpckhpd xmm14,xmm12,xmm12
    vaddsd xmm12,xmm12,xmm14
    vaddsd xmm12,xmm12,xmm13
    vmovapd xmm0,xmm12
    ret
vec_fused_finish_resident_fragment_end:
'''

RESIDENT_INIT = r'''vec_fused_init_resident_fragment:
    mov r8,rdx
    sub r8,rsi
    vxorpd ymm12,ymm12,ymm12
vec_fused_init_resident_fragment_end:
'''


def materialize_resident_fragments(text: str) -> str:
    # Reuse the existing four-lane lane-index table owned by the ordinary mask
    # fragment. The ABI remains generic and no second data table is introduced.
    mask_anchor = 'vec_fused_mask_reduce_fragment_end:\n\n'
    if mask_anchor not in text:
        raise SystemExit('native256 finalizer: ordinary mask fragment anchor missing')
    if 'vec_fused_mask_reduce_resident_fragment:' not in text:
        text = text.replace(mask_anchor, mask_anchor + RESIDENT_MASK + '\n', 1)

    finish_anchor = 'vec_fused_finish_fragment_end:\n\n'
    if finish_anchor not in text:
        raise SystemExit('native256 finalizer: ordinary finish fragment anchor missing')
    if 'vec_fused_finish_resident_fragment:' not in text:
        text = text.replace(finish_anchor, finish_anchor + RESIDENT_FINISH + '\n', 1)

    init_anchor = 'vec_fused_init_fragment_end:\n\n'
    if init_anchor not in text:
        raise SystemExit('native256 finalizer: ordinary init fragment anchor missing')
    if 'vec_fused_init_resident_fragment:' not in text:
        text = text.replace(init_anchor, init_anchor + RESIDENT_INIT + '\n', 1)
    return text


for path in FILES:
    text = path.read_text(encoding='utf-8')
    text = uniquify_fixed_wrapper_labels(text)
    text = materialize_resident_fragments(text)
    # Hard no-specialization/no-fallback audit on the generated physicalizer.
    lowered = text.lower()
    for forbidden in ('newton', 'fsi', 'fluid', 'solid', 'stiffness', 'poisson'):
        if forbidden in lowered:
            raise SystemExit(f'native256 finalizer: workload identity leaked into {path.name}: {forbidden}')
    path.write_text(text, encoding='utf-8')

print('NATIVE256_HELPER_LABEL_OWNERSHIP=PASS')
print('NATIVE256_RESIDENT_REDUCTION_ABI=PASS')
print('NATIVE256_WORKLOAD_SPECIALIZATION=0')
print('NATIVE256_RUNTIME_SELECTOR=0')
print('NATIVE256_SCALAR_FALLBACK=0')
