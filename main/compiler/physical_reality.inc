# Wheelchair 1.3.14 unified compiler-wide Physical Reality vocabulary.
# This file is compile-time authority only. It deliberately emits no runtime
# manager, queue, scheduler, ownership table, autotuner, or recipient selector.
# General scalar causal state, Tensor Rank-N and Field locality all describe
# their facts through the same physical vocabulary before target realization.
.include "compiler/physical_cost_ticks.inc"
.include "compiler/groupfact.inc"
.include "compiler/silicon_reality.inc"

.equ PR_FACT_INVALID,-1

# Axis relation classes. "Causal" is not a new backend: it is a Rank-N axis
# whose next version has a mathematically necessary dependence on the previous
# version. Independent axes remain free to physicalize in parallel.
.equ PR_AXIS_INDEPENDENT,0
.equ PR_AXIS_AFFINE,1
.equ PR_AXIS_NEIGHBORHOOD,2
.equ PR_AXIS_CAUSAL,3

# ValueFact lifetime/realization classes. These are AOT proof vocabulary only.
.equ PR_VALUE_EPHEMERAL,0
.equ PR_VALUE_VERSIONED_STATE,1
.equ PR_VALUE_CONSTANT,2
.equ PR_VALUE_ADDRESS,3
.equ PR_VALUE_REDUCTION,4

# Unified hard prohibitions.
.equ PR_RUNTIME_FACT_MANAGER,0
.equ PR_RUNTIME_RESIDENCY_MANAGER,0
.equ PR_RUNTIME_REGISTER_ALLOCATOR,0
.equ PR_RUNTIME_AUTOTUNE,0
.equ PR_GLOBAL_READY_QUEUE,0
.equ PR_WORK_STEALING,0
.equ PR_RESOURCE_RECIPIENT_SELECTION,0
.equ PR_GLOBAL_FLUSH_ON_STORE,0
.equ PR_WORKLOAD_NAME_DISPATCH,0

# A fact is releasable exactly after its final proved consumer. Release carries
# no destination identity: the current consumer never decides who uses the
# silicon next.
.equ PR_RELEASE_AT_LAST_CONSUMER,1
.equ PR_RELEASE_RECIPIENT_BLIND,1

# 1.3.15 strengthens the same vocabulary; it does not create a new causal
# backend. State count affects only compile-time pressure/profitability.
.equ PR_CAUSAL_PARTIAL_RESIDENCY,1
.equ PR_INDUCTION_IS_AXIS_AUTHORITY,1
.equ PR_STATE_COUNT_ADMISSION_THRESHOLD,0
.equ PR_PRIVATE_PAGE_CACHE_COLORING,1
.equ PR_SPILL_IS_PHYSICAL_PRESSURE_ONLY,1

# 1.3.16 strengthens the same whole-episode Physical Reality. Exact old-version
# subgraphs share one AOT ValueFact identity across simultaneous next-state
# expressions; state, shared facts, constants and anonymous temporaries compete
# under one compile-time XMM pressure authority. Pressure may reduce residency,
# but it never selects a stack/generic backend.
.equ PR_WHOLE_EPISODE_VALUEFACT_CSE,1
.equ PR_EXACT_STRICT_ORDER_CSE,1
.equ PR_AOT_TEMP_PRESSURE_PROOF,1
.equ PR_CONSTANT_COUNT_ADMISSION_THRESHOLD,0
.equ PR_PRESSURE_BACKEND_CLIFF,0
.equ PR_RUNTIME_CSE_MANAGER,0
.equ PR_RUNTIME_VALUEFACT_CACHE,0

# 1.3.20 strengthens the same Physical Reality by deleting historical private
# transition-shape emitters. A simultaneous next-version bank is only one
# physical realization candidate. If that candidate blocks already-proved
# reusable FP ValueFacts through carrier exhaustion, the same DAG is re-mapped
# with transient next-version realization through the existing version handoff.
.equ PR_PRIVATE_TRANSITION_SHAPE_EMITTERS,0
.equ PR_STATE_COUNT_ISA_ROUTE,0
.equ PR_SHARED_PRESSURE_REMAP,1
.equ PR_NEXT_VERSION_PRIVATE_BANK_MANDATORY,0
.equ PR_MACHINE_SEQUENCE_CANONICALIZATION,1
.equ PR_WORKLOAD_SPECIFIC_PRESSURE_ROUTE,0

# 1.3.21 strengthens the same lifetime authority by sparsifying physical value
# transport. A semantic timestep boundary does not force movement. A resident
# old-state carrier may become the next-version authority immediately after its
# final effective consumer. Selected episode-CSE subtrees count as consumed in
# the pre-update phase. Fixed FP-state residency thresholds are not admissible.
.equ PR_VALUEFACT_TRANSPORT_SPARSIFICATION,1
.equ PR_TIMESTEP_BOUNDARY_FORCES_TRANSPORT,0
.equ PR_OLD_AUTHORITY_REUSE_AT_LAST_CONSUMER,1
.equ PR_FP_STATE_RESIDENCY_MAGIC_THRESHOLD,0
.equ PR_TRANSPORT_WORKLOAD_ROUTE,0
# 1.3.22 strengthens ordinary ValueFact lifetime for boolean predicates. A
# materialized immutable predicate remains authoritative until one of its input
# versions changes; repeated syntax does not imply repeated physical compare.
# Reuse is recorded as a real fragment dependency. No predicate runtime/cache,
# repetition threshold, fixed AST boundary-select matcher, or fixed-state affine
# iterate lowering is admissible.
.equ PR_PREDICATE_VALUEFACT_PERSISTENCE,1
.equ PR_PREDICATE_REEVALUATE_WITHOUT_VERSION_CHANGE,0
.equ PR_PREDICATE_REPEAT_THRESHOLD,0
.equ PR_RUNTIME_PREDICATE_MANAGER,0
.equ PR_FIXED_BOUNDARY_SELECT_MATCHER,0
.equ PR_FIXED_STATE_AFFINE_ITERATE_ROUTE,0


# 1.3.67 ages transition-power algebra into the counted recurrence Physical
# Reality as one Rank-N affine closure.  The published result grows its semantic
# backward slice to a dense state vector x; if the simultaneous wrap-u64 update
# proves x' = A*x+b, repeated causal application is represented as F^N and
# realized by one dimension-generic native composition kernel.  Scalar affine
# power is the N=1 case, not a retained compatibility backend.  State count,
# workload identity, fixed dimensions, repetition thresholds and shadow AST
# matchers are not admission authorities.
.equ PR_TRANSITION_POWER_CLOSED_FAMILY,1
.equ PR_TRANSITION_POWER_BACKWARD_SLICE,1
.equ PR_TRANSITION_POWER_RANKN_AFFINE_CLOSURE,1
.equ PR_TRANSITION_POWER_STATE_COUNT_ROUTE,0
.equ PR_TRANSITION_POWER_FIXED_DIMENSION,0
.equ PR_TRANSITION_POWER_REPEAT_THRESHOLD,0
.equ PR_TRANSITION_POWER_SCALAR_SHADOW_AUTHORITY,0
.equ PR_FIXED_AFFINE_AST_MATCHER,0
.equ PR_TRANSITION_POWER_RUNTIME_SELECTOR,0
.equ PR_RUNTIME_TRANSITION_POWER_MANAGER,0

# Human-form convergence is an upstream semantic law, not a new optimizer
# family.  1.3.69 expands the same representative authority from exact identity
# to proof relations that preserve every observable contract: neutral shells,
# total commutative operand order and comparison duality.  The old symbol record
# still owns the representative.  There is no second IR, algorithm-name matcher,
# convergence round budget, runtime manager, associative regrouping authority or
# strict-FP arithmetic reordering.  Unproved differences remain distinct.
.equ PR_HUMAN_SEMANTIC_CONVERGENCE,1
.equ PR_SEMANTIC_CONVERGENCE_ZERO_FLIP,1
.equ PR_SEMANTIC_CONVERGENCE_PROOF_RELATIONS,1
.equ PR_SEMANTIC_CONVERGENCE_IDENTITY_SHELL_ERASURE,1
.equ PR_SEMANTIC_CONVERGENCE_COMPARISON_DUALITY,1
.equ PR_SEMANTIC_CONVERGENCE_SECOND_IR,0
.equ PR_SEMANTIC_CONVERGENCE_ALGORITHM_MATCHER,0
.equ PR_SEMANTIC_CONVERGENCE_FIXED_ROUNDS,0
.equ PR_RUNTIME_SEMANTIC_CONVERGENCE_MANAGER,0
.equ PR_SEMANTIC_CONVERGENCE_ASSOCIATIVE_REWRITE,0
.equ PR_STRICT_FP_SEMANTIC_REASSOCIATION,0
.equ PR_STRICT_FP_SEMANTIC_COMMUTATION,0

# Automatic Grouping semantic law lives only in groupfact.inc, which is included
# above. Physical Reality must not mirror Group/Vector/Scalar hierarchy, fixed-
# width prohibitions, or body/carrier ownership under a second PR_* vocabulary.
# This file owns only target facts/costs consumed while realizing GroupFact.
.equ PR_GROUPFACT_IS_SINGLE_SEMANTIC_AUTHORITY,1

# 1.3.64 convergence removes internal compatibility-only emitter and allocator
# surfaces. A physical domain that has zero realizable carriers is absent, not a
# zero-capacity pseudo-domain that every lowering site must probe.
.equ PR_INTERNAL_COMPATIBILITY_EMITTER_ABI,0
.equ PR_ZERO_CAPACITY_PSEUDO_DOMAIN,0
.equ PR_NATIVE256_RESIDENT_CONSTANT_DOMAIN,0
.equ PR_DIRECT_CANONICAL_INTERNAL_CALLS,1
.equ PR_NATIVE256_PERSISTENT_CACHE_DOMAIN,0

# Group execution is not a second semantic authority. The target cost model
# measures one body and writes the canonical GroupFact body/carrier factors; all
# physicalizers consume those factors directly. Finite ShapeFact geometry may
# cap a group, but zero means "unbounded domain", never "disable Group".
.equ PR_GROUPFACT_CANONICAL_FACTORS_DRIVE_EXECUTION,1
.equ PR_GROUP_PRIVATE_WIDTH_AUTHORITY,0
.equ PR_GROUP_DOMAIN_CAP_CODEGEN_GATE,0
.equ PR_GROUP_RUNTIME_SELECTOR,0



# 1.3.70 ages human-form convergence across execution spelling.  A proved pure
# self-recursive fixed-lag relation is projected directly into the already-old
# canonical iterate facts, so recursion, explicit state update and the General
# causal/Rank-N path share one semantic authority before physical materialization.
# Structural lag span is data, not an admission threshold.  There is no recursive
# runtime, memo service, workload-name matcher, recurrence-specific IR/backend,
# fixed order/depth gate, or runtime selector.  Relations outside the proof class
# remain unmaterialized rather than being approximately rewritten.
.equ PR_EXECUTION_FORM_CONVERGENCE,1
.equ PR_RECURSIVE_RELATION_TO_CANONICAL_ITERATE,1
.equ PR_RECURSION_SECOND_IR,0
.equ PR_RECURSION_RUNTIME_BACKEND,0
.equ PR_RECURSION_RUNTIME_MEMO_MANAGER,0
.equ PR_RECURSION_ALGORITHM_MATCHER,0
.equ PR_RECURSION_FIXED_ORDER_LIMIT,0
.equ PR_RECURSION_DEPTH_THRESHOLD,0
.equ PR_RECURSION_RUNTIME_SELECTOR,0


# 1.3.71 sparse physical-region aging.  Once Axis/Region/topology facts prove a
# contiguous direct-address region, their physical consequence persists as one
# invocation-local run end and the higher-level facts retire from the hot path.
# Only a genuine region boundary re-enters topology realization.  This is the
# same Physical Reality authority: no stencil/Poisson matcher, second address IR,
# fixed extent/rank threshold, precomputed per-element table, or runtime manager.
.equ PR_PHYSICAL_REGION_FACT_SPARSIFICATION,1
.equ PR_PROVED_TOPOLOGY_RETIRES_INSIDE_REGION,1
.equ PR_BOUNDARY_ONLY_TOPOLOGY_REMATERIALIZATION,1
.equ PR_PHYSICAL_REGION_SECOND_IR,0
.equ PR_STENCIL_WORKLOAD_MATCHER,0
.equ PR_PHYSICAL_REGION_FIXED_THRESHOLD,0
.equ PR_PER_ELEMENT_ADDRESS_TABLE,0
.equ PR_RUNTIME_PHYSICAL_REGION_MANAGER,0

# 1.3.72 ages independent Tensor/Field execution ownership out of the runtime
# causal tree.  Cold Physical Reality already selects the profitable leaf grain;
# the runtime launch frontier only exposes disjoint ownership regions.  Once a
# leaf owns a region, launch geometry is dead.  Every non-root execution is made
# a direct lifecycle child of the invocation root via CLONE_PARENT, so Linux
# wait4(-1) is sufficient lifecycle truth.  Mathematical reduction is a separate
# left-to-right frontier over region results.  There is no recursive join tree,
# runtime subtree-profitability recheck, completion counter, worker pool, ready
# queue, work stealing, second ownership backend, or root O(P) spawn sweep.
.equ PR_OWNERSHIP_LOCAL_EXECUTION,1
.equ PR_LAUNCH_FRONTIER_RETIRES_AT_REGION,1
.equ PR_OS_LIFECYCLE_COMPLETION_AUTHORITY,1
.equ PR_REDUCTION_SEPARATE_FROM_EXECUTION_OWNERSHIP,1
.equ PR_RUNTIME_CAUSAL_TREE_AUTHORITY,0
.equ PR_RUNTIME_SUBTREE_PROFITABILITY_RECHECK,0
.equ PR_RECURSIVE_PARALLEL_JOIN_TREE,0
.equ PR_EXECUTION_GLOBAL_COMPLETION_COUNTER,0
.equ PR_ROOT_LINEAR_SPAWN_SWEEP,0
.equ PR_OUTWARD_REGION_SECOND_BACKEND,0
.equ PR_RUNTIME_READY_QUEUE,0
.equ PR_RUNTIME_WORK_STEALING,0

# 1.3.73 launch-static physical realization.  Facts that become immutable after
# cold input/target validation are packed once into the generated-kernel call
# state and may not reappear as packet-level global questions.  The direct Field
# kernel loops only on its Region bound; generic/boundary realization is entered
# only when the proved direct Region expires or launch proof rejects it.  External
# input geometry remains truthful runtime data: this rule freezes proved facts,
# it does not pretend runtime files are AOT constants.  No second kernel IR,
# workload matcher, compatibility branch, JIT, runtime policy manager or fixed
# region span is introduced.
.equ PR_LAUNCH_STATIC_PHYSICAL_REALIZATION,1
.equ PR_PROVED_FACT_PACKET_REQUESTION,0
.equ PR_PACKET_GLOBAL_LAYOUT_RELOAD,0
.equ PR_PACKET_GLOBAL_UNIFORM_RELOAD,0
.equ PR_PACKET_GLOBAL_NT_POLICY_RELOAD,0
.equ PR_LAUNCH_STATIC_MODE_SECOND_IR,0
.equ PR_LAUNCH_STATIC_RUNTIME_POLICY_MANAGER,0
.equ PR_LAUNCH_STATIC_WORKLOAD_MATCHER,0
.equ PR_LAUNCH_STATIC_FIXED_REGION_SPAN,0


# 1.3.74 burn-level machine facts.  Once Physical Reality proves an immutable
# carrier and its lifetime, code generation may not demote that fact back into a
# packet-local temporary.  AddressFacts occupy the available GPR bank for the
# stable Region lifetime, immutable constants occupy SIMD carriers for that same
# lifetime, and logical value identities alias those physical carriers directly.
# Tolerant def/use proofs may fuse machine operations without naming a workload.
# Architectural carrier exhaustion uses the truthful existing stack authority;
# there is no second machine IR, workload matcher, compatibility backend, or
# runtime carrier-policy manager.
.equ PR_BURN_LEVEL_MACHINE_FACTS,1
.equ PR_ADDRESSFACT_GPR_REGION_LIFETIME,1
.equ PR_CONSTANTFACT_SIMD_REGION_LIFETIME,1
.equ PR_IMMUTABLE_CARRIER_ALIASING,1
.equ PR_PACKET_STACK_ADDRESS_RELOAD,0
.equ PR_PACKET_CONSTANT_RELOAD,0
.equ PR_TOLERANT_REDUCE_MACHINE_FUSION,1
.equ PR_MACHINE_FACT_SECOND_IR,0
.equ PR_MACHINE_FACT_WORKLOAD_MATCHER,0
.equ PR_MACHINE_FACT_RUNTIME_POLICY_MANAGER,0

# 1.3.75 complete machine-form burn aging.  The existing Physical DAG remains
# the sole scheduling authority all the way to ISA. Exact immutable coefficient
# identities are consumed directly by the machine emitter: tolerant +1/-1/0
# cease to exist as multiplies and become ADD/SUB/no work. The existing depth-
# ordered physical plan is emitted directly; no late graph rewrite, second
# scheduler IR, workload matcher, fixed packet count, or runtime issue manager is
# admitted. Strict FP keeps its original operator sequence.
.equ PR_COMPLETE_MACHINE_FORM_BURN,1
.equ PR_OPERATOR_IDENTITY_BURN_AT_EMITTER,1
.equ PR_CAUSAL_DEPTH_MACHINE_ORDER_DIRECT,1
.equ PR_LATE_MACHINE_GRAPH_REWRITE,0
.equ PR_SECOND_MACHINE_SCHEDULER_IR,0
.equ PR_FIXED_PACKET_UNROLL_AUTHORITY,0
.equ PR_RUNTIME_MACHINE_ISSUE_MANAGER,0
.equ PR_STRICT_FP_OPERATOR_IDENTITY_REWRITE,0

# 1.3.76 causal-depth machine burn.  GroupFact now survives to the final ISA
# carrier schedule instead of collapsing back into one packet reused serially.
# Packet zero keeps the mature Vector allocation; every additional packet exists
# only when the *actual* free SIMD carrier bank can hold its live logical-vreg
# MachineFacts.  The later 1.3.77 aging step removes the temporary shadow-load
# carrier assumption entirely, so this authority now speaks only about disjoint
# packet identities and real architectural carrier capacity.  Width is a consequence
# of causal depth and live architectural carriers, never a 2/4/8 candidate,
# source/workload threshold, runtime selector, byte-cloned body, or second IR.
# Strict reduction recurrence remains Vector when regrouping would change its
# exact IEEE reduction realization.
.equ PR_CAUSAL_DEPTH_MACHINE_BURN,1
.equ PR_GROUPFACT_DISJOINT_PACKET_CARRIERS,1
.equ PR_GROUPFACT_CARRIER_FROM_LIVE_MACHINE_FACTS,1
.equ PR_GROUP_PACKET_BYTE_CLONING,0
.equ PR_PRIVATE_MACHINE_UNROLL_WIDTH,0
.equ PR_GROUP_WIDTH_CANDIDATE_SET,0
.equ PR_RUNTIME_GROUP_ISSUE_SELECTOR,0
.equ PR_STRICT_REDUCTION_GROUP_REORDER,0

# 1.3.77/1.3.84 Physical-DAG -> realization schedule burn. The single already-existing
# dependency-depth order is now the final machine time axis for a Group episode:
# each ordered Physical operation is issued across all simultaneously live
# independent packet MachineFacts before the next operation position is visited.
# Immutable LoadFacts stay as AddressFacts until their true consumer; when the
# tolerant operator can encode that address directly, the LoadFact becomes the
# x86 memory operand and never receives a synthetic SIMD carrier at all.  Packet
# zero no longer survives as a byte-copied body authority.  Group width remains
# the old GroupFact result of real causal depth and live architectural carrier
# capacity.  There is no post-codegen scheduler, second machine IR,
# candidate unroll table, runtime issue manager, workload matcher, or packet-
# major compatibility path.  Strict reduction keeps its exact recurrence and
# therefore naturally remains Vector when regrouping is not contract-legal.
.equ PR_PHYSICAL_DAG_REALIZATION_SCHEDULE_BURN,1
.equ PR_GROUP_DEPTH_MAJOR_REALIZATION,1
.equ PR_GROUP_LOADFACT_DEFERRED_MATERIALIZATION,1
.equ PR_LOADFACT_MEMORY_OPERAND_BURN,1
.equ PR_GROUP_LOADFACT_SYNTHETIC_CARRIER_REQUIRED,0
.equ PR_GROUP_SHADOW_LOAD_CARRIER_BANK,0
.equ PR_GROUP_PACKET0_BYTE_COPY_AUTHORITY,0
.equ PR_GROUP_PACKET_MAJOR_BODY_AUTHORITY,0
.equ PR_POST_CODEGEN_MACHINE_SCHEDULER,0
.equ PR_SCHEDULE_BURN_SECOND_IR,0
.equ PR_SCHEDULE_BURN_CANDIDATE_WIDTHS,0
.equ PR_SCHEDULE_BURN_RUNTIME_SELECTOR,0

# 1.3.80 physical-work convergence. Causal readiness is semantic truth, not an
# order to manufacture an OS execution.  Straight-line regions may continue in
# the already-live execution when their proved native work cannot repay the same
# outward lifecycle price already used by Tensor/Field.  Dynamic regions remain
# outward candidates; no runtime queue, idle-CPU query, recipient search, worker
# pool or work stealing is introduced.
.equ PR_CAUSAL_FRONTIER_COST_GATED,1
.equ PR_READY_IMPLIES_OUTWARD_EXECUTION,0
.equ PR_GENERAL_OUTWARD_USES_SHARED_PHYSICAL_PRICE,1
.equ PR_RUNTIME_CPU_LOCATION_QUERY,0
.equ PR_RUNTIME_NUMA_PAGE_MIGRATION,0

# Causal arrival state is one cache-line ownership fact. A semantic node no
# longer reserves/touches a whole OS page merely to hold one arrival counter and
# one completion byte. Cache-line isolation preserves the old false-sharing
# boundary without a page-sized physical footprint.
.equ PR_CAUSAL_STATE_CACHELINE_OWNERSHIP,1
.equ PR_CAUSAL_STATE_PAGE_PER_NODE,0

# Helper-boundary ValueFacts keep an already-safe resident carrier alive.  A
# fallback helper result reaches stack authority only when the chosen carrier is
# actually in the helper clobber domain or a later proved consumer requires a
# reload authority.  Boundary syntax does not itself force a stack round-trip.
.equ PR_BOUNDARY_VALUEFACT_RESIDENCY_CONTINUITY,1
.equ PR_BOUNDARY_FORCES_STACK_ROUNDTRIP,0


# 1.3.81 transport/region aging.  Traffic is not a second scheduler or memory
# optimizer: it is another physical resource dimension of the same AddressFact /
# RegionFact realization.  A periodic neighborhood is represented as maximal
# piecewise-affine address regions; only a vector episode that actually straddles
# an affine boundary falls back to the generic gather authority.  Region changes
# refresh the existing AddressFact carriers rather than introducing a boundary
# backend.
.equ PR_TRAFFIC_REALITY,1
.equ PR_TRAFFIC_SECOND_IR,0
.equ PR_RUNTIME_BANDWIDTH_PROBE,0
.equ PR_PIECEWISE_AFFINE_REGIONFACT,1
.equ PR_PERIODIC_BOUNDARY_IMPLIES_GATHER,0
.equ PR_REGION_ADDRESSFACT_REFRESH,1
.equ PR_BOUNDARY_COMPATIBILITY_BACKEND,0

# Repetition along the innermost axis is one transport stream when field identity
# and every outer affine coordinate are identical.  The compiler records both the
# actual emitted traffic price and this mathematical stream floor in the same
# Physical Reality vocabulary; there is no stencil-name matcher or fixed window
# width.  Later machine realization may consume the relation without changing the
# semantic graph.
.equ PR_AFFINE_TRANSPORT_STREAM_FACT,1
.equ PR_MATHEMATICAL_TRANSPORT_FLOOR_IS_LOWER_BOUND,1
.equ PR_CROSS_PACKET_RELATION_IS_ADDRESSFACT,1
.equ PR_SLIDING_WINDOW_WORKLOAD_MATCHER,0
.equ PR_FIXED_WINDOW_WIDTH,0

# Time is already a causal Rank-N axis in General.  1.3.81 makes that fact the
# canonical authority for future Field/Tensor temporal fusion as well: a semantic
# timestep never forces materialization merely because a frontend boundary was
# crossed.  No second spacetime scheduler or fixed temporal tile is admitted.
.equ PR_SPACETIME_IS_RANKN_CAUSAL_REGION,1
.equ PR_TIMESTEP_FRONTEND_BOUNDARY_FORCES_MATERIALIZATION,0
.equ PR_SPACETIME_SECOND_SCHEDULER,0
.equ PR_FIXED_TEMPORAL_TILE,0

# Frontends remain syntax authorities, not execution authorities.  Their physical
# facts terminate in the same compiler-wide Physical Reality / Physical DAG
# vocabulary.  No compatibility execution lane may be selected merely from the
# surface that produced the fact.
.equ PR_FRONTEND_PHYSICAL_AUTHORITY_UNIFIED,1
.equ PR_FRONTEND_NAME_EXECUTION_ROUTE,0
# 1.3.82 CoordinateFact aging.  A Rank-N packet coordinate is a mathematical
# parent fact, not syntax owned by each field access. Native512 materializes the
# canonical coordinate once into execution-local high SIMD carriers and lets
# every AddressFact consume only its affine delta/stride realization.  Uniform
# and nonuniform field layouts share the same logical CoordinateFact.  Offset
# vectors are consumed directly; no AVX-512 coordinate stack authority, second
# coordinate IR, boundary optimizer, or workload matcher is admitted.
.equ PR_PERSISTENT_RANKN_COORDINATEFACT,1
.equ PR_COORDINATEFACT_PER_ACCESS_REDECODE,0
.equ PR_COORDINATEFACT_EXECUTION_LOCAL_CARRIERS,1
.equ PR_COORDINATEFACT_SHARED_ACROSS_LAYOUTS,1
.equ PR_AVX512_COORDINATE_OFFSET_STACK_AUTHORITY,0
.equ PR_COORDINATEFACT_SECOND_IR,0
.equ PR_COORDINATE_WORKLOAD_MATCHER,0


# 1.3.83 Mutable StateFact causal-lifetime ownership.  A mutable iterate state
# exists only for the causal execution that owns that recurrence episode.
# current and next-version values therefore live in the already-existing
# execution-local stack frame and die when that episode returns.  Simultaneous
# executions are physically disjoint by construction; sequential causal
# episodes reuse the same offsets after death.  No shared state arena, lock,
# owner table, worker identity, work stealing, or parallel-language route is
# introduced.
.equ PR_MUTABLE_STATEFACT_CAUSAL_LIFETIME_OWNERSHIP,1
.equ PR_STATEFACT_EXECUTION_LOCAL_FRAME,1
.equ PR_STATEFACT_SHARED_RUNTIME_ARENA,0
.equ PR_STATEFACT_SHARED_NEXT_VERSION_MAILBOX,0
.equ PR_STATEFACT_LOCK_REPAIR,0
.equ PR_STATEFACT_RUNTIME_OWNER_MANAGER,0
.equ PR_STATEFACT_WORK_STEALING,0
.equ PR_STATEFACT_PARALLEL_DSL_ROUTE,0


# 1.3.84 silicon-realization closure. Physical Reality no longer terminates
# conceptually at an instruction stream. The same already-proved facts own time,
# space, storage and multiplicity until the target's exposed physical boundary.
# x86 remains a direct realization; a spatial target may materialize the same
# DAG as simultaneously live compute/storage/routes. No new source construct,
# kernel language, worker/task model, target semantic IR, occupancy objective,
# fixed PE/tile/stage count, or runtime silicon allocator is admitted.
.equ PR_SILICON_REALITY_SINGLE_AUTHORITY,1
.equ PR_CAUSAL_DEPTH_OWNS_REALIZATION_TIME,1
.equ PR_TRAFFIC_REGION_OWNS_REALIZATION_SPACE,1
.equ PR_FACT_LIFETIME_OWNS_REALIZATION_STORAGE,1
.equ PR_GROUPFACT_OWNS_REALIZATION_MULTIPLICITY,1
.equ PR_ISA_IS_ONE_REALIZATION_NOT_SEMANTIC_CEILING,1
.equ PR_SPATIAL_TARGET_REQUIRES_RELINEARIZATION,0
.equ PR_SILICON_SECOND_IR,0
.equ PR_HARDWARE_KERNEL_LANGUAGE,0
.equ PR_FIXED_PROCESSING_ELEMENT_COUNT,0
.equ PR_RUNTIME_SILICON_SCHEDULER,0
.equ PR_SILICON_PARALLEL_DSL_ROUTE,0

# 1.3.85 joins mathematical structure with exposed silicon space.  The Physical
# DAG remains program authority; the silicon-domain graph contributes only
# realization cost/capacity.  Device names, guessed die adjacency and source-size
# crossover thresholds cannot select execution routes.
.equ PR_SILICON_DOMAIN_GRAPH_SINGLE_AUTHORITY,1
.equ PR_TRAFFIC_X_DOMAIN_GRAPH_SPATIAL_CLOSURE,1
.equ PR_VENDOR_MODEL_EXECUTION_ROUTE,0
.equ PR_GEOMETRIC_DIE_DISTANCE_GUESS,0
.equ PR_SOURCE_SIZE_AFFINITY_THRESHOLD,0
.equ PR_LOCALITY_DOMAIN_CAPS_EXECUTION_MULTIPLICITY,0
.equ PR_EXECUTION_ADMISSION_OWNS_MULTIPLICITY_BOUND,1
.equ PR_LOCALITY_IDENTITY_OWNS_PLACEMENT_ONLY,1
.equ PR_DOMAIN_GRAPH_SECOND_IR,0

# Domain identity, spatial execution multiplicity, and temporal quota are not
# interchangeable. Affinity proves the x86 execution-context set; cache/NUMA
# identity prices placement and transport; cgroup cpu.max contributes its exact
# quota/period time budget without pretending to be a context count. Unknown
# locality or finite temporal budget therefore never erases an affinity-proved
# execution context.
.equ PR_SILICON_DOMAIN_IDENTITY_CLOSURE,1
.equ PR_ALLOWED_SET_X_CACHE_IDENTITY_INTERSECTION,1
.equ PR_CPU_NUMBER_ADJACENCY_AUTHORITY,0
.equ PR_DOMAIN_WIDTH_ONLY_NORMAL_AUTHORITY,0
.equ PR_COMPILETIME_APIC_DOMAIN_PROBE,1
.equ PR_RUNTIME_APIC_DOMAIN_PROBE,0
.equ PR_DOMAIN_PROBE_WORK_SCHEDULER,0
.equ PR_DOMAIN_PROBE_IDLE_CAPACITY_QUERY,0

# 1.3.87 closes Traffic x Silicon Domain identity into an executable AOT spatial
# placement fact. The chosen exact LLC-domain mask is target realization only;
# it does not alter the program DAG or create a runtime scheduler.
.equ PR_TRAFFIC_X_DOMAIN_IDENTITY_STATIC_PLACEMENT,1
.equ PR_STATIC_PLACEMENT_INHERITED,1
.equ PR_RUNTIME_PLACEMENT_SELECTOR,0
.equ PR_RUNTIME_PLACEMENT_MIGRATION,0
.equ PR_DOMAIN_IDENTITY_FAILURE_CARDINALITY_GUESS,0
.equ PR_LOCALITY_FAILURE_COLLAPSES_EXECUTION_ADMISSION,0
.equ PR_AFFINITY_SET_OWNS_X86_MULTIPLICITY_BOUND,1
.equ PR_CGROUP_QUOTA_OWNS_TEMPORAL_BUDGET,1
.equ PR_CGROUP_QUOTA_OWNS_MULTIPLICITY_BOUND,0
.equ PR_POWER_OF_TWO_EXECUTION_ROUNDUP,0
.equ PR_GENERAL_EXECUTION_ADMISSION_BOUND,1
.equ PR_STATIC_PLACEMENT_SECOND_IR,0


# 1.3.88 heterogeneous edge closure. A cross-Region dependency is a Physical
# Edge Fact, not merely graph connectivity. Its represented payload contributes
# a lower-bound transport price, and every realized domain publishes completion
# through the same causal successor law. x86 and fabric may coexist in one
# realization; neither is a source-visible kernel/offload authority.
.equ PR_PHYSICAL_EDGE_FACTS,1
.equ PR_EDGE_TRANSFER_LOWER_BOUND,1
.equ PR_HETEROGENEOUS_DOMAINS_MAY_COEXIST,1
.equ PR_SHARED_CAUSAL_COMPLETION_PUBLICATION,1
.equ PR_X86_FPGA_EXCLUSIVE_TARGET,0
.equ PR_FPGA_KERNEL_OFFLOAD_MODEL,0
.equ PR_RUNTIME_DEVICE_SELECTOR,0
.equ PR_UNPROVEN_FABRIC_REALIZATION,0

# 1.3.89 heterogeneous target facts are folded into the same Physical Reality.
# A Region has no user-selected device identity. AOT placement may move a Region
# between proved x86 and fabric domains only when the common physical cost
# strictly decreases after including every incident Physical Edge transfer.
# Repeated passes terminate on structural convergence, not on a round budget.
.equ PR_FABRIC_TARGET_FACTS_ARE_PHYSICAL_FACTS,1
.equ PR_X86_FABRIC_JOINT_COST_CLOSURE,1
.equ PR_INCIDENT_EDGE_TRAFFIC_IN_DOMAIN_FLIP_COST,1
.equ PR_JOINT_DOMAIN_STRICT_IMPROVEMENT,1
.equ PR_JOINT_DOMAIN_FIXED_ROUND_LIMIT,0
.equ PR_FABRIC_TARGET_DEFAULT_NONZERO_GUESS,0
.equ PR_SOURCE_DEVICE_ANNOTATION,0
.equ PR_FABRIC_WORKLOAD_MATCHER,0
.equ PR_RUNTIME_HETEROGENEOUS_REBALANCER,0

# 1.3.90 exposes the already-closed heterogeneous realization without inventing
# a target-owned program graph.  Each Region receives one compact physical
# descriptor derived from its existing work/edge facts and the shared completion
# authority.  Missing fabric activation is a hard physical absence, never an x86
# compatibility fallback.
.equ PR_FABRIC_REALIZATION_DESCRIPTOR_FROM_PHYSICAL_DAG,1
.equ PR_FABRIC_DESCRIPTOR_SECOND_IR,0
.equ PR_FABRIC_SHARED_COMPLETION_ENTRY,1
.equ PR_FABRIC_NATIVE_FALLBACK,0
.equ PR_UNBRIDGED_FABRIC_EXECUTION,0

# 1.3.91 fabric execution aging. A fabric placement is materialized only through
# one Physical-Region activation entry. Field fabric descriptors serialize the
# already-proved op records/depth/order; they do not own semantics or scheduling.
.equ PR_FABRIC_ACTIVATION_ENTRY_FROM_REALIZATION,1
.equ PR_FABRIC_COMPLETION_EXPLICIT_STATE,1
.equ PR_FIELD_DATAPATH_FROM_EXISTING_PHYSICAL_DAG,1
.equ PR_FIELD_SECOND_FABRIC_IR,0
.equ PR_FIELD_UNBRIDGED_FABRIC_EXECUTION,0

# 1.3.93 transport/issue orthogonality.  Transport remains part of total
# Physical Reality and may dominate placement/outward cost, but it cannot erase
# arithmetic dependency width.  Recurrence carriers are owned by issue and
# dependency facts, never by a cache-line transport price.
.equ PR_ISSUE_BOUND_OWNS_RECURRENCE_CARRIERS,1
.equ PR_TRAFFIC_OWNS_TOTAL_PHYSICAL_COST,1
.equ PR_TRAFFIC_OWNS_RECURRENCE_CARRIER_WIDTH,0
.equ PR_TRANSPORT_COMPUTE_AXIS_COLLAPSE,0

# 1.3.97 scalar StateFact generation authority closure.  A resident FP
# generation may collapse old/next carrier identity only when the complete FP
# state set proves one fixed-point authority under exact post-CSE liveness and
# strict emitter order. Partial mixed-generation coalescing is not an execution
# mode; failed proof retains the mature disjoint generation realization.
.equ PR_FP_GENERATION_FIXED_POINT_AUTHORITY,1
.equ PR_FP_GENERATION_PARTIAL_AUTHORITY_MIX,0
.equ PR_FP_GENERATION_WORKLOAD_MATCHER,0
.equ PR_FP_GENERATION_SECOND_BACKEND,0

# 1.3.98 General integer Physical Reality closes compile-time u64 modulo into
# one exact reciprocal relation. Every nonzero ConstantFact, including powers
# of two, follows the same realization; no compatibility mask path, workload
# route, runtime selector, or second backend owns modulo semantics.
.equ PR_GENERAL_CONST_MOD_RECIPROCAL_AUTHORITY,1
.equ PR_GENERAL_CONST_MOD_POWER_OF_TWO_BRANCH,0
.equ PR_GENERAL_CONST_MOD_WORKLOAD_MATCHER,0
.equ PR_GENERAL_CONST_MOD_RUNTIME_SELECTOR,0
.equ PR_GENERAL_CONST_MOD_SECOND_BACKEND,0
