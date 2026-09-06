# WH Surface

`wh_surface.py` is the optional human-facing shell. The old WH Core remains the
authority and remains byte-for-byte untouched.

```bash
# Human syntax -> canonical Core JSON
python3 surface/wh_surface.py compile my_program.wh -o my_program.core.wh

# Desugar and ask the unchanged WH Core validator
python3 surface/wh_surface.py validate my_program.wh

# English is the default source spelling
python3 surface/wh_surface.py format my_program.wh

# Other spelling skins
python3 surface/wh_surface.py format my_program.wh --language zh-hans
python3 surface/wh_surface.py format my_program.wh --language zh-hant
python3 surface/wh_surface.py format my_program.wh --language preserve

# Prove several spelling variants erase to one Core graph
python3 surface/wh_surface.py equivalent a.wh b.wh c.wh
```

See `SURFACE_SPEC.md` and `examples/`.

## Conservative auto-repair

Compilation now performs a deterministic Surface-only repair pass by default:

- English keyword: exactly one inserted, deleted, or substituted ASCII character.
- Declared bare English identifier: same edit-distance-1 rule, only when exactly one
  already-declared candidate exists in the relevant scope.
- Built-in English callable spelling: same unique one-edit rule.
- Newline split inside a known English keyword or an already-declared English name:
  joined only when the concatenation is exact.
- Newline split inside a two-character operator such as `>=`, `->`, or `=>`:
  merged only when the resulting operator already exists in the grammar.

Chinese keyword/identifier spelling, emoji names, and mixed-Unicode identifiers are
never spell-guessed. Ambiguous English candidates are rejected rather than chosen.
Transposition is not treated as one edit. Repair changes only token interpretation;
the source file is never rewritten by `compile` or `validate`.

Every applied repair appears in the JSON command report as `surface_repairs`.
The Python API can disable repair with `compile_surface(..., auto_repair=False)`.

See `examples/auto_repair_clean.wh`, `examples/auto_repair_typos.wh`, and
`tests/run_auto_repair_tests.py`.

## WHEX 1.1.0 structural semantics

The expert `.whex` lane now has a separate semantic planner:

```bash
python3 surface/whex_surface.py plan program.whex
./whexc program.whex -o program --semantic-plan program.semantic.json
```

The plan exposes Axis, Region, Effect, Ownership, Dependency, Control,
Parallelism-Preservation, Serial-Introduction, and Erasure facts. Pure structural
functions and compile-time records erase before canonical IR. Pure parallel regions
create no runtime region/effect dispatcher. Rank-N reductions may eliminate proven
irrelevant static axes before native realization; non-erasable Rank-N structure rejects
rather than silently flattening into a sequential loop.

See `WHEX_SPEC.md` and `../GENERAL_TRUE_PARALLEL_CHARTER_1_1_0.md`.
