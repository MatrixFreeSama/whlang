# Real sparse simulation kernels used for the 1.3.26 pressure test

These are regression/benchmark artifacts only. They have zero production authority.

The physical/discretization kernels are taken from established public miniapps rather than invented benchmark equations:

- Mantevo miniFE: 3-D Hex8 steady heat-conduction finite-element operator. The uniform interior assembly produces the 21 numerically nonzero neighbors used by `minife_heat21.json`.
  Upstream: https://github.com/Mantevo/miniFE
- Mantevo miniAMR: official 7-point and 27-point stencil modes used by `miniamr7.json` and `miniamr27.json`.
  Upstream: https://github.com/Mantevo/miniAMR
- CloverLeaf: x-velocity acceleration pressure/viscosity-gradient kernel used by `clover_xacc.json`.
  Upstream C serial kernel: https://github.com/UK-MAC/CloverLeaf_Serial/blob/master/accelerate_kernel_c.c

The Wheelchair JSON files describe the same local arithmetic over WHFLD materialized f32 fields. C and Fortran files implement the same measured kernels. Input field bytes are intentionally not duplicated in the release archive; the measurements recorded in PERFORMANCE_1_3_26_FIELD_VALUEFACT_LIFETIME.md used 256^3 materialized fields on the validation host.
