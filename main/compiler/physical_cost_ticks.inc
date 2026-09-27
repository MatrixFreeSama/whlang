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
# is consumed only as a lower-bound physical work price when deciding whether a
# causally-ready region can repay an outward Linux execution lifecycle.  It is
# not a source-size threshold: dynamic/iterative regions remain unbounded and
# therefore cannot be admitted by this price alone.  3 ticks/byte corresponds
# to the mature four-byte/cycle decode floor in the shared 1/12-cycle domain.
.equ PRC_FRONTEND_BYTE_TICKS,3
.equ PRC_CACHE_LINE_BYTES,64
.equ PRC_LOAD_AGU_TICKS,PRC_LOAD_TICKS+PRC_AGU_TICKS
.equ PRC_INT_MUL_LOAD_AGU_TICKS,PRC_INT_MUL_TICKS+PRC_LOAD_TICKS+PRC_AGU_TICKS
