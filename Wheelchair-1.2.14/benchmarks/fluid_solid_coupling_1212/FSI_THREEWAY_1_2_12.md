# Wheelchair 1.2.12 / Expert C / Expert Fortran FSI Diagnostic

This is a same-host diagnostic retained to ensure that the execution-lifetime change does not alter the numerical problem.

Protocol:

- same periodic fluid-solid operator;
- N = 10,000,000 and 100,000,000;
- q = 1, 2, 4;
- 3 warmups + 11 measured runs per contender;
- same CPU affinity;
- medians per case;
- 27-case correctness matrix before authority timing.

Correctness:

```text
27 / 27 PASS
max Wheelchair relative error vs C = 1.8660438476835228e-14
contract = 1e-8
```

This particular cloud pass produced geometric means approximately:

```text
Fortran / C      = 1.0645x
Wheelchair / C   = 1.4225x
Wheelchair / F   = 1.3363x
```

Wheelchair won the 10M/q4 row against Fortran in this pass, but the aggregate remained behind C and Fortran. Cloud timing has shown substantial pass-to-pass variation, so these numbers are diagnostic only.

The important 1.2.12 result is structural: execution-lifetime fragmentation is reduced without changing the operator, numerical gate, resource-profile selection, or blind-release semantics.
