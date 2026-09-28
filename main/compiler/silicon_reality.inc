# Wheelchair current Silicon Reality authority.
#
# This is not an FPGA/HLS language, a kernel model, or a second scheduling IR.
# It is the target-physical closure of the existing Physical Reality facts.
# Mathematical structure stays authoritative until the target realization:
#
#   causal depth -> time
#   Traffic/Region facts -> spatial coupling
#   Value/State lifetime -> storage residency
#   GroupFact -> multiplicity admitted by real carriers
#   Effect/Capability -> external physical boundary
#
# x86-64, reconfigurable fabric, and future fixed silicon are realizations of
# these same facts. Target choice may change physical realization, never program
# meaning or introduce a frontend-named execution route.

# Universal physical domain classes. These classify target resources, not
# source-language constructs and not device families.
.equ SR_DOMAIN_EXECUTION,1
.equ SR_DOMAIN_STORAGE,2
.equ SR_DOMAIN_TRANSPORT,3
.equ SR_DOMAIN_EFFECT,4

# One-way structural burn laws.
.equ SR_PHYSICAL_DAG_IS_REALIZATION_AUTHORITY,1
.equ SR_CAUSAL_DEPTH_IS_TIME_AUTHORITY,1
.equ SR_TRAFFIC_REGION_IS_SPACE_AUTHORITY,1
.equ SR_FACT_LIFETIME_IS_STORAGE_AUTHORITY,1
.equ SR_GROUPFACT_IS_MULTIPLICITY_AUTHORITY,1
.equ SR_CAPABILITY_IS_EFFECT_BOUNDARY_AUTHORITY,1
.equ SR_TARGET_FACTS_MAY_DEGRADE_REALIZATION,1
.equ SR_TARGET_FACTS_MAY_CHANGE_SEMANTICS,0

# Resource multiplicity and placement are consequences of the real target.
# No source/program fixed width or occupancy target is allowed to become an
# architecture law.
.equ SR_FIXED_PROCESSING_ELEMENT_COUNT,0
.equ SR_FIXED_TILE_SIZE,0
.equ SR_FIXED_PIPELINE_STAGE_COUNT,0
.equ SR_FIXED_SIMD_WIDTH_AUTHORITY,0
.equ SR_FIXED_CORE_COUNT_AUTHORITY,0
.equ SR_OCCUPANCY_IS_OBJECTIVE,0
.equ SR_THEORETICAL_WORK_CONVERGENCE_IS_OBJECTIVE,1

# There is no runtime silicon allocator. The compiled realization never asks
# which CPU/device region is idle, steals work, chooses recipients, or repairs
# structure with a task scheduler.
.equ SR_RUNTIME_SILICON_ALLOCATOR,0
.equ SR_RUNTIME_IDLE_RESOURCE_QUERY,0
.equ SR_RUNTIME_RECIPIENT_SELECTION,0
.equ SR_RUNTIME_WORK_STEALING,0
.equ SR_RUNTIME_READY_QUEUE,0
.equ SR_RUNTIME_TOPOLOGY_AUTOTUNER,0

# Anti-DSL firewall. Surface forms cannot become hardware kernels/tasks and a
# target cannot own a second semantic graph.
.equ SR_PARALLEL_DSL_ROUTE,0
.equ SR_HLS_KERNEL_AUTHORITY,0
.equ SR_SOURCE_KERNEL_EXTRACTION,0
.equ SR_TARGET_SECOND_SEMANTIC_IR,0
.equ SR_TARGET_ALGORITHM_SELECTOR,0
.equ SR_WORKLOAD_NAME_ROUTE,0

# The old instruction machine is one realization, not the conceptual ceiling.
# On an ISA target, the existing machine emitter consumes these facts. On a
# spatial target, the same facts may become simultaneously live physical units,
# storage and routes without first re-serializing them into an instruction list.
.equ SR_VON_NEUMANN_ORDER_IS_SEMANTIC_AUTHORITY,0
.equ SR_RELINEARIZE_BEFORE_SPATIAL_REALIZATION,0
.equ SR_SPATIAL_REALIZATION_ALLOWED,1
.equ SR_DIRECT_FACT_TO_PHYSICAL_RESOURCE_ALLOWED,1

# Public hardware boundary: commodity CPU/GPU software cannot address arbitrary
# individual transistors. A future fabric/ASIC realization may control placement
# and routing only through the target's exposed physical primitives.
.equ SR_ARBITRARY_TRANSISTOR_ADDRESSING,0
.equ SR_TARGET_EXPOSED_PRIMITIVES_ARE_BOUNDARY,1

# 1.3.85 spatial closure.  The target contributes a domain graph, not a device
# name.  Traffic is priced against exposed sharing boundaries; unknown die
# geometry remains unknown rather than becoming guessed adjacency.
.equ SR_SILICON_DOMAIN_GRAPH_IS_TARGET_AUTHORITY,1
.equ SR_TRAFFIC_X_DOMAIN_BOUNDARY_IS_SPACE_COST,1
.equ SR_VENDOR_MODEL_ROUTE,0
.equ SR_GEOMETRIC_DIE_ADJACENCY_ASSUMED,0
.equ SR_SOURCE_SIZE_AFFINITY_CROSSOVER,0
.equ SR_DOMAIN_GRAPH_RUNTIME_SCHEDULER,0
.equ SR_DOMAIN_GRAPH_MAY_CHANGE_SEMANTICS,0
.equ SR_DOMAIN_GRAPH_MAY_CONSTRAIN_REALIZATION,1

# Domain identity, execution multiplicity, and temporal CPU budget are distinct
# Physical Facts. APIC/cache identity prices placement. The affinity set proves
# which execution contexts spatially exist. cgroup cpu.max is a quota/period time
# budget and therefore cannot erase an affinity-proved context or become a worker
# count. Linux CPU ordinals are never die coordinates. Temporary probe affinity
# is compile-time observation only and is restored before compilation; it is not
# program work placement, idle-resource discovery, or a runtime scheduler.
.equ SR_DOMAIN_IDENTITY_FROM_ARCHITECTURAL_TOPOLOGY,1
.equ SR_ALLOWED_SET_X_DOMAIN_IDENTITY_IS_CAPACITY,0
.equ SR_EXECUTION_ADMISSION_FROM_AFFINITY_SET,1
.equ SR_LOCALITY_IDENTITY_IS_PLACEMENT_ONLY,1
.equ SR_CGROUP_CPU_QUOTA_IS_TEMPORAL_BUDGET_FACT,1
.equ SR_CGROUP_CPU_QUOTA_IS_MULTIPLICITY_AUTHORITY,0
.equ SR_POWER_OF_TWO_EXECUTION_ROUNDUP,0
.equ SR_GENERAL_EXECUTION_ADMISSION_BOUND,1
.equ SR_INVOCATION_AFFINITY_REFRESHES_EXECUTION_ADMISSION,1
.equ SR_COMPILE_HOST_WIDTH_IS_IMAGE_AUTHORITY,0
.equ SR_ADMISSION_FAILURE_USES_COMPILE_HOST_WIDTH,0
.equ SR_STATIC_PLACEMENT_INTERSECTS_INVOCATION_AFFINITY,1
.equ SR_STATIC_PLACEMENT_MAY_EXPAND_INVOCATION_AFFINITY,0
.equ SR_STRICT_REDUCTION_INVARIANT_TO_EXECUTION_CARDINALITY,1
.equ SR_ARBITRARY_CARDINALITY_LAUNCH_FRONTIER,1
.equ SR_POWER_OF_TWO_LAUNCH_FRONTIER,0
.equ SR_COMPLETION_LOCAL_SIBLING_EXPOSURE,1
.equ SR_RUNTIME_READY_QUEUE,0
.equ SR_CPU_ORDINAL_IS_PHYSICAL_ADJACENCY,0
.equ SR_CARDINALITY_ONLY_DOMAIN_APPROXIMATION_IS_AUTHORITY,0
.equ SR_COMPILETIME_TOPOLOGY_IDENTITY_PROBE,1
.equ SR_RUNTIME_TOPOLOGY_IDENTITY_PROBE,0
.equ SR_PROBE_AFFINITY_IS_PROGRAM_PLACEMENT,0
.equ SR_DOMAIN_IDENTITY_PROBE_FAILURE_CHANGES_SEMANTICS,0

# 1.3.87 static silicon-placement closure. Exact admitted domain identity now
# materializes one AOT affinity domain when the external set spans LLC domains.
# The choice is made once from target facts; generated outward executions inherit
# it. No runtime load/idle observation, recipient matching, migration policy,
# kernel/task surface, or cardinality-only compatibility approximation exists.
.equ SR_AOT_STATIC_DOMAIN_PLACEMENT,1
.equ SR_PLACEMENT_INHERITED_BY_OUTWARD_EXECUTIONS,1
.equ SR_RUNTIME_PLACEMENT_RESOURCE_MATCHING,0
.equ SR_RUNTIME_PLACEMENT_MIGRATION,0
.equ SR_CARDINALITY_FALLBACK_ON_IDENTITY_FAILURE,0
.equ SR_PLACEMENT_CPU_ORDINAL_TIEBREAK,0
.equ SR_PLACEMENT_FAILURE_CHANGES_SEMANTICS,0


# 1.3.88 heterogeneous fabric closure. x86 and reconfigurable fabric are not
# mutually exclusive targets: both may realize disjoint Regions of one Physical
# DAG at the same time. Region boundaries carry Physical Edge Facts so transport
# cost remains part of the same closure. Completion is one causal law regardless
# of whether the Region returned from an ISA body or completed asynchronously in
# exposed fabric. No kernel/offload language, target-owned task graph, runtime
# device chooser, or fabricated hardware availability is admitted.
.equ SR_SIMULTANEOUS_HETEROGENEOUS_REALIZATION,1
.equ SR_X86_FPGA_EXCLUSIVE_TARGET_SELECTION,0
.equ SR_PHYSICAL_EDGE_FACT_AUTHORITY,1
.equ SR_EDGE_TRAFFIC_IS_CROSS_DOMAIN_COST,1
.equ SR_SHARED_CAUSAL_COMPLETION_LAW,1
.equ SR_FPGA_OFFLOAD_KERNEL_MODEL,0
.equ SR_RUNTIME_DEVICE_SELECTOR,0
.equ SR_UNPROVEN_FABRIC_MAY_BE_MATERIALIZED,0
.equ SR_FPGA_BITSTREAM_EMITTER_PRESENT,0

# Physical realization tags are target facts only. They are deliberately absent
# from source syntax and never select a semantic algorithm.
.equ SR_REALIZATION_X86_ISA,1
.equ SR_REALIZATION_RECONFIGURABLE_FABRIC,2

# 1.3.89 exposed-fabric target-fact and joint-placement closure. Reconfigurable
# fabric enters the same Silicon Domain Graph only through externally proved
# physical facts. Production defaults are zero, so missing hardware cannot be
# fabricated. Region placement is deterministic AOT strict-improvement closure
# over Region work and Physical Edge crossing cost; it has no fixed round count,
# runtime device chooser, source annotation, kernel extraction or device-name
# algorithm route. Logic/register/DSP/storage/routing/clock facts describe the
# target; they are not new source semantics.
.equ SR_FABRIC_TARGET_FACTS_EXTERNAL_ONLY,1
.equ SR_FABRIC_TARGET_FACTS_DEFAULT_ZERO,1
.equ SR_FABRIC_LOGIC_FACT,1
.equ SR_FABRIC_REGISTER_FACT,1
.equ SR_FABRIC_DSP_FACT,1
.equ SR_FABRIC_LOCAL_STORAGE_FACT,1
.equ SR_FABRIC_ROUTING_DOMAIN_FACT,1
.equ SR_FABRIC_CLOCK_REGION_FACT,1
.equ SR_AOT_JOINT_DOMAIN_PLACEMENT,1
.equ SR_JOINT_PLACEMENT_STRICT_IMPROVEMENT,1
.equ SR_JOINT_PLACEMENT_FIXED_ROUND_LIMIT,0
.equ SR_USER_FABRIC_PLACEMENT_ANNOTATION,0
.equ SR_FABRIC_DEVICE_NAME_ROUTE,0
.equ SR_FABRIC_ACTIVATION_BRIDGE_PRESENT,0

# 1.3.90 fabric-realization descriptor closure.  The joint AOT plan is now
# serialized as physical target metadata consumable by a future board bridge.
# The descriptor is a projection of the existing Physical DAG, not a second IR.
# A fabric-tagged image is never silently executed through its x86 body when no
# activation bridge exists; production target facts remain zero by default.
.equ SR_FABRIC_REALIZATION_DESCRIPTOR,1
.equ SR_FABRIC_REALIZATION_DESCRIPTOR_VERSION,2
.equ SR_FABRIC_ACTIVATION_ABI_PRESENT,1
.equ SR_FABRIC_COMPLETION_CALLBACK_ABI,1
.equ SR_FABRIC_NATIVE_FALLBACK,0
.equ SR_FABRIC_UNBRIDGED_EXECUTION_ALLOWED,0

# 1.3.91 direct fabric activation closure. The runtime materializes an already-
# placed fabric Region through one target entry pointer and publishes completion
# through an explicit-state callback. Field projects its existing op-level
# Physical DAG into a target descriptor without creating a kernel language or IR.
.equ SR_FABRIC_ACTIVATION_ENTRY_ABI,1
.equ SR_FABRIC_ACTIVATION_ABI_VERSION,2
.equ SR_FABRIC_EXTERNAL_COMPLETION_EXPLICIT_STATE,1
.equ SR_FIELD_FABRIC_DATAPATH_DESCRIPTOR,1
.equ SR_FIELD_FABRIC_DESCRIPTOR_SECOND_IR,0
.equ SR_FIELD_FABRIC_X86_FALLBACK,0

# 1.3.93 keeps silicon transport and compute issue as separate target facts.
# Their costs meet only in total realization cost; transport is not a proxy for
# arithmetic recurrence width or independent carrier availability.
.equ SR_TRANSPORT_IS_TOTAL_COST_FACT,1
.equ SR_ISSUE_IS_RECURRENCE_WIDTH_FACT,1
.equ SR_TRANSPORT_IS_RECURRENCE_WIDTH_AUTHORITY,0
