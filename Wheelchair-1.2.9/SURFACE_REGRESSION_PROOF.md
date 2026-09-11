# Inherited Wheelchair 1.0.2 Surface Regression Proof

The UTF-8 human surface shell was restored above the existing 1.0.2 native Core.
This repair is additive at compile time and is not a backend replacement.

## Bottom-layer immutability

`BOTTOM_LAYER_SHA256` is the pre-regression manifest for every source file under:

- `compiler/`
- `runtime/`
- `tools/`

After the surface restoration, full rebuild, general tests, topology tests and
surface tests, the independently recomputed manifest is byte-identical.

Manifest SHA-256:

```text
2d42ffa47b42232c89e4eb851a40cde3884c9604b7ea5c82c411ec3a248a0aa8
```

## Original 1.0.2 vs restored-surface build products

The original pre-surface-regression 1.0.2 tar and the restored tree were extracted
and built independently on the same host. These native products were byte-identical:

```text
build/topologyc                  54d3039de4b91b37d4b672d559982616da701e2292f0a1bf800c0415eba45ebc
build/tensor_runtime_template    39b0f37a20a0d37b731c58185d891aba8c4b00014a17754e960f32eba8fbc0fe
build/general_runtime_template   9c294cc4e6e711a26ea755d98eba4cf9df0616ff7f36249948464c8be27261a2
build/topology-fabric            6e9aa62119ded1f438a59d4558aaf420f9d568443a5c2bd6c0d75e2c0d54f38d
build/topology-fabric-run        700df0885fe9a809f1b3766d1bb0c08f500bc030f1f56e2675574044cdc16bfd
```

Representative user-program outputs were also byte-identical across the two trees:

```text
general_compute  6fbc8664448cb23bb25f8aaced799bdd47a5edc652f7cf84f69855fd8a1f901c
general_add      432b7237ad633b1e3034a6dcdc67eb5faf024439a5061b6c97309506f4293c21
heat_1           ca5307ee3d22ca9716e46c0fa1f864d2b4cefb07fdde0d9ef4b9a656d906773b
heat_2           42701aeac778ea078086bd637c22b6c449eb1b6b15d68f22e5e27d5309468bf3
heat_4           4a928bb8664292367181255d7673b611fb948d296b37d98abb89faf060c4e63e
wave_1           99a79ccb58ce010449e4fa4709b1415b9623d089ffc5b18870c1700cd4666535
wave_2           a8015c532e0b63fc82e944005570481cab1170088d0b51ec5064732fe3734b00
wave_4           4c9f676aa1304b0ae672af210ec1269f8e7fc66456c89e48239e8ca5a6287fa4
sparse_1         abf465596e9009d2a0fe072cf21fcd92c25e415cf9648f80bb6dcc05d73bafd3
sparse_2         6e73e936cb770a33efbec7d63a3a555d42a16924249c5dbe590122043fba3c92
sparse_4         7abc78c4c3e18fa5f71162fafa2c3e88edf8f8603c04f9007b52caf2efbe8d2c
```

## Surface grammar preservation

The historical `wh_surface.py` and the restored version are byte-identical from
the beginning of the file through the parser/desugaring implementation up to the
old Core-validation integration function. This covers 1050 lines of lexer, UTF-8
identifier handling, multilingual keyword aliases, parser grammar, expression
parsing and canonical Core generation.

Grammar-prefix SHA-256:

```text
7dd4e1e586937fd7d8cad177269ca576c0cedd4956a7b3c6708e5cee11542215
```

Only the historical endpoint that called the former Python Core validator was
adapted to call the current `build/topologyc`, and a `native` command was added.

## Erasure gates

The release test requires:

1. English, Simplified Chinese, Traditional Chinese and mixed-keyword surface
   sources to emit byte-identical canonical Core JSON.
2. Those four Core graphs to emit byte-identical native ELF images.
3. `./wheelchairc` and direct `build/topologyc` compilation of the same canonical
   Core to emit byte-identical native ELF images.
4. The minimal human program `surface/examples/simple_add.wh` to execute correctly.
5. All original general/HPC and causal-fabric tests to continue passing.

The surface layer therefore adds source convenience, not runtime behavior.

`architecture_complete = false`
