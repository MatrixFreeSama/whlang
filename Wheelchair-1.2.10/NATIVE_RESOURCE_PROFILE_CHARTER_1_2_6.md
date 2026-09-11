# Wheelchair 1.2.6 Native Resource Profile Charter

Wheelchair native physicalization is selected from graph structure and machine-resource demand only.

## Public capability classes

- `base`: the mature default direct-native topology compiler.
- `wide`: the same semantics with the expanded persistent-register ownership profile.
- `derived`: a mathematically proved structural physicalization whose source rank or domain is erased/encoded before native realization.

These are capabilities, not workload implementations. A source path, benchmark name, physics domain, program name, historical performance case, or runtime timing measurement must never select a capability class.

## Hard prohibitions

Current compilation and execution must contain no workload-name dispatch, benchmark dispatch, source-path dispatch, runtime profitability selector, hidden scalar fallback, global runnable queue, root scheduler, work stealing, or synthetic source-order dependency.

Resource shortage is not permission to serialize. The compiler must use a proved generic physicalization or explicitly reject the program.

## Technical peak preservation

Genericization must not erase mature machine-code peaks. The 1.2.6 release gate therefore compares the public `base`, `wide`, and `derived` compiler images against their clean 1.2.5 byte authorities. Naming and routing may generalize; retained native code must remain byte-identical unless a separately measured non-regressive replacement is introduced.

The expanded register profile keeps runtime-owned ZMM12..15 protected, uses the proven persistent CSE register expansion, preserves compile-time reciprocal lowering, and introduces no runtime division or foreign backend.

## General parallel interaction

The native resource profile answers only how a fragment is physically realized. The general parallel fabric answers when a fragment becomes causally ready and where its AOT home executor is. Neither layer may smuggle policy into the other.

For ordinary general WH, the handwritten assembly frontend remains the machine-code lowerer. Q2/Q4 compilation cuts the already-emitted native program into binding/output fragments and links them behind the schedulerless causal slot engine. The AOT linker does not reinterpret numeric expressions.

This separation is mandatory: semantic causality, native resource realization, and machine-code generation are independent contracts rather than named workload lanes.
