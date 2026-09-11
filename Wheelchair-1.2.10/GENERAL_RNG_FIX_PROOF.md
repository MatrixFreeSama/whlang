# General RNG / iterate repair proof

This repair is confined to the sovereign general lane. The HPC topology compiler
source and topology runtime are not modified.

## Fixed general defects

1. Decimal `u64` argument parsing no longer carries `input_count` in caller-saved
   `RCX` across decimal parser calls. Multi-digit inputs now remain one input.
2. General `iterate` state initialization reacquires state metadata after recursive
   expression emission instead of dereferencing caller-saved `R11`.
3. Near-branch patch helpers preserve the displacement-field address across the
   zero-placeholder emitter.
4. General multi-state `iterate` preserves its compiler-side state index across
   JSON lookup and machine-code emit helpers that legitimately use `RCX` as scratch.

## Correctness gates

- `simple_add 12345` -> `0x3040`.
- LCG64 `(seed=42, steps=10)` -> `0x06593f7b1358c594`
  (`457466634992928148`).
- LCG64 maximum `u64` seed is accepted; `2^64` is rejected by the runtime parser.
- The human surface LCG source and direct Core both compile to sovereign static ELF.

## HPC non-regression gate

Against the pre-repair 1.0.2 tree:

- `topologyc_x86_64.S`, `tensor_frontend_x86_64.S`, tensor runtime source/linker
  script, causal-return fabric sources, and tensor-offset generator are byte-identical.
- Heat, Wave, and Sparse generated ELF images are byte-identical at 1, 2, and 4
  execution slots.

The general compiler/runtime changed intentionally; the HPC compiler/runtime did not.

`architecture_complete = false`
