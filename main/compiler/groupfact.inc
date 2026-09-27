# Wheelchair 1.3.61 Automatic Grouping semantic authority.
#
# Group is the complete structural form. Vector and Scalar are degradations:
#   Group -> Vector -> Scalar
# The compiler never packs scalars merely because a fixed width exists. It
# recovers an operation-affine group from existing ValueFact / Axis /
# ShapeFact-N / Operator / Physical-DAG facts, then Physical Reality degrades
# that group only as far as the target requires.
#
# GroupFact owns no fixed rank, extent count, lane count, tile size, chunk size,
# workload selector, or runtime manager. Logical axes remain owned by ShapeFact-N;
# GroupFact stores only derived relation/realization facts.
.equ GF_FORM_SCALAR,0
.equ GF_FORM_VECTOR,1
.equ GF_FORM_GROUP,2

# Relation/affinity facts. These describe structure, not algorithm families.
.equ GF_REL_INDEPENDENT,(1 << 0)
.equ GF_REL_AFFINE,(1 << 1)
.equ GF_REL_NEIGHBORHOOD,(1 << 2)
.equ GF_REL_REDUCTION,(1 << 3)
.equ GF_REL_CAUSAL,(1 << 4)
.equ GF_REL_OPERATOR,(1 << 5)

# Hard architecture laws.
.equ GF_VECTOR_IS_DEGENERATE_GROUP,1
.equ GF_SCALAR_IS_DEGENERATE_VECTOR,1
.equ GF_FIXED_RANK_CAP,0
.equ GF_FIXED_EXTENT_CAP,0
.equ GF_FIXED_GROUP_SIZE,0
.equ GF_FIXED_TILE_SIZE,0
.equ GF_RUNTIME_GROUP_MANAGER,0
.equ GF_RUNTIME_GROUP_SELECTOR,0
.equ GF_WORKLOAD_NAME_ROUTE,0
.equ GF_COMPATIBILITY_VECTORIZER,0
.equ GF_GROUP_BEFORE_PHYSICAL_DEGRADATION,1
# 1.3.63 aging/convergence: resource scheduling and canonical physicalization
# share these exact factors. There is no shadow schedule width, shadow physical
# plan width, or legacy runtime unroll/carrier ABI.
.equ GF_SINGLE_BODY_FACTOR_AUTHORITY,1
.equ GF_SINGLE_CARRIER_FACTOR_AUTHORITY,1
.equ GF_SHADOW_SCHEDULE_WIDTH_FIELDS,0
.equ GF_SHADOW_PHYSICAL_PLAN_FIELDS,0
.equ GF_LEGACY_RUNTIME_WIDTH_ABI,0


# 1.3.64 convergence: internal compatibility aliases are not architecture.
# Current tensor physicalizers call the canonical emitters/allocators directly;
# native256 does not model a resident constant-register domain that cannot exist.
.equ GF_INTERNAL_COMPATIBILITY_ALIASES,0
.equ GF_NATIVE256_GHOST_CONSTANT_DOMAIN,0
.equ GF_CANONICAL_EMITTER_ABI,1
.equ GF_NATIVE256_GHOST_CACHE_DOMAIN,0

# Executing Group realization. A Group body axis may widen the mature Vector
# episode only from common Physical Reality facts. When no higher-order relation
# remains, the already-proven Vector episode is the floor rather than being
# destroyed and rebuilt as one packet. Group execution owns one control edge for
# the complete episode; interior packets consume the same relation with stronger
# boundary facts. No fixed candidate width or workload route exists.
.equ GF_VECTOR_PHYSICAL_BASELINE_PRESERVED,1
.equ GF_GROUP_BODY_FROM_MEASURED_PHYSICAL_COST,1
.equ GF_GROUP_LEVEL_CONTROL_EDGE,1
.equ GF_INTERIOR_RELATION_STRENGTHENING,1
.equ GF_GROUP_WIDTH_CANDIDATE_SET,0
.equ GF_GROUP_PROFITABILITY_WORKLOAD_ROUTE,0
.equ GF_NECESSARY_WORK_CONSERVED,1
.equ GF_REALIZATION_CLOSED_OVER_BODY,1
.equ GF_VECTOR_DEGRADATION_IS_CANONICAL,1
.equ GF_FIXED_DENSE_PACKET_GATE,0
# 1.3.66 aging closure. These are not new optimization families: they state that
# every Tensor physicalizer consumes the same GroupFact body/carrier facts, and
# dense packet count is not copied into a private codegen width. ShapeFact may
# bound a finite domain; a zero bound never disables an already-proved Group.
.equ GF_CANONICAL_BODY_FACTOR_DRIVES_ALL_TENSOR_EMITTERS,1
.equ GF_PRIVATE_DENSE_PACKET_WIDTH,0
.equ GF_ZERO_DOMAIN_CAP_IS_CODEGEN_GATE,0
.equ GF_GROUP_IS_OPTIMIZER_BRANCH,0


# 1.3.77/1.3.84 aging: the canonical GroupFact body factor is also the final
# realization concurrency fact. The existing depth-sorted Physical order remains
# the time authority on ISA targets and becomes simultaneous physical structure
# on spatial targets; Group is never rewrapped into a target-private scheduler.
.equ GF_PHYSICAL_DEPTH_IS_FINAL_REALIZATION_TIME_AXIS,1
.equ GF_LOADFACT_LIFETIME_STARTS_AT_TRUE_CONSUMER,1
.equ GF_LOADFACT_MAY_REMAIN_MEMORY_AT_TRUE_CONSUMER,1
.equ GF_PACKET_SHADOW_LOAD_BANK,0
.equ GF_PACKET_MAJOR_MACHINE_REWRAP,0
.equ GF_PACKET_ZERO_BYTE_BODY_AUTHORITY,0


# 1.3.84: target geometry may degrade Group but never create a private width
# authority. Spatial hardware and ISA carriers consume the same body/carrier
# factors; device family is not a semantic branch.
.equ GF_TARGET_GEOMETRY_DEGRADES_ONLY,1
.equ GF_SPATIAL_REALIZATION_USES_SAME_FACT,1
.equ GF_TARGET_PRIVATE_GROUP_WIDTH,0
.equ GF_HARDWARE_KERNEL_GROUP_ROUTE,0
