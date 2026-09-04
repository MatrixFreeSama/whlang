# Wheelchair 1.0.3 decimal-f64 repair proof

## Defect

`node_parse_f64_bits` accumulated the decimal scale as unsigned u64 but converted it with signed `cvtsi2sd`. A 19-digit fractional scale (`10^19`) fits u64 but exceeds INT64_MAX, so the conversion interpreted the denominator as negative. Example: `-0.0038580246913580245` was compiled with the wrong sign/magnitude.

## Repair

- Added native unsigned-u64 -> f64 conversion for decimal mantissa/scale.
- Added unsigned overflow guards for decimal mantissa and denominator accumulation.
- Values outside the supported exact structural decimal slice are rejected instead of wrapped.
- Added `tests/topology_cases/f64_u64_scale_regression.wh`.
- Corrected the FEM aggregate regression checksum previously frozen from the wrong-code build.

## Independent oracle

For `fem_linear_aggregate_tolerant_regression.wh`, GCC strict and Taichi 1.7.4 strict independently produced approximately `-115.19097222223249`. The repaired Wheelchair tolerant build produces approximately `-115.1909722222307`, relative error below `1e-13` and well below the declared `1e-10` accumulator tolerance.

## Regression

`WHEELCHAIR_BUILD=PASS`
`WHEELCHAIR_TESTS=PASS`
`WHEELCHAIR_COMPLETE_TESTS=PASS`
