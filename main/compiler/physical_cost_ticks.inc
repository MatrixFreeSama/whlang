# Wheelchair compiler-wide Physical Reality cost vocabulary.
# Units are 1/12 CPU-cycle ticks. These are target resource prices, not
# workload thresholds, profile selectors or runtime scheduling controls.
.equ PRC_FP_ADD_TICKS,6
.equ PRC_FP_ADD_LATENCY_TICKS,36
.equ PRC_FP_MUL_TICKS,6
.equ PRC_FP_DIV_TICKS,168
.equ PRC_FP_CONV_TICKS,12
.equ PRC_INT_ALU_TICKS,3
.equ PRC_INT_MUL_TICKS,6
.equ PRC_INT_DIV_TICKS,120
.equ PRC_LOAD_TICKS,6
.equ PRC_AGU_TICKS,4
.equ PRC_BRANCH_TICKS,12

# 1.3.81 transport dimension.  A cache-line transfer is a physical resource
# price in the same 1/12-cycle domain, not a workload threshold.  The generic
# x86-64 profile admits one 64-byte ownership line per cycle as the conservative
# sustained L1/data-path floor.  Wider/slower target profiles may override the
# same fact in their existing profile authority; no runtime bandwidth probe is
# introduced.
.equ PRC_TRAFFIC_LINE_TICKS,12
.equ PRC_TRAFFIC_LINE_BYTES,64

# Front-end transport price for already-emitted straight-line native code.  This
# bounds both outward region work and the actual encoded scalar window. It is
# a resource estimate, not a source-size threshold or a cycle-accurate schedule.
# Dynamic/iterative regions remain unbounded for outward admission unless their
# execution count is proved by the existing work relation. 3 ticks/byte corresponds
# to the mature four-byte/cycle decode floor in the shared 1/12-cycle domain.
.equ PRC_FRONTEND_BYTE_TICKS,3
.equ PRC_CACHE_LINE_BYTES,64
.equ PRC_LOAD_AGU_TICKS,PRC_LOAD_TICKS+PRC_AGU_TICKS
.equ PRC_INT_MUL_LOAD_AGU_TICKS,PRC_INT_MUL_TICKS+PRC_LOAD_TICKS+PRC_AGU_TICKS

# Fourier work uses the same primitive/transport prices as every other DAG.
# Per-coefficient estimates sum the native forward/inverse butterfly work;
# radix is a stage factor, never a different multiplication algorithm.
.equ PRC_COMPLEX_MUL_TICKS,4*PRC_FP_MUL_TICKS+2*PRC_FP_ADD_TICKS
.equ PRC_FOURIER_RADIX2_TICKS,(2*PRC_COMPLEX_MUL_TICKS+8*PRC_FP_ADD_TICKS+12*PRC_LOAD_AGU_TICKS)/2
.equ PRC_FOURIER_RADIX3_TICKS,(8*PRC_COMPLEX_MUL_TICKS+16*PRC_FP_ADD_TICKS+18*PRC_LOAD_AGU_TICKS)/3
.equ PRC_FOURIER_RADIX5_TICKS,(16*PRC_COMPLEX_MUL_TICKS+32*PRC_FP_ADD_TICKS+30*PRC_LOAD_AGU_TICKS)/5
.equ PRC_FOURIER_COEFFICIENT_TICKS,2*PRC_FP_CONV_TICKS+4*PRC_INT_ALU_TICKS+4*PRC_LOAD_AGU_TICKS
