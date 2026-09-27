.intel_syntax noprefix
# Link-only support for the shared handwritten JSON parser currently housed in
# tensor_frontend_x86_64.S. fieldc never dispatches compile_tensor_source; these
# symbols satisfy unreachable tensor-only references without importing the
# topology driver or any runtime scheduler.
.section .bss
.global isa_cap_bits
isa_cap_bits: .skip 4
.global profile_id
profile_id: .skip 4
.global schedule_counts
schedule_counts: .skip 40
.global schedule_bound_ticks
schedule_bound_ticks: .skip 4
.global group_body_cap
group_body_cap: .skip 4
.global group_body_cost_ops
group_body_cost_ops: .skip 4
.global group_body_cost_bytes
group_body_cost_bytes: .skip 4
.global group_carrier_cap
group_carrier_cap: .skip 4

.global group_logical_rank
group_logical_rank: .skip 4
.global group_relation_mask
group_relation_mask: .skip 4
.global group_lane_factor
group_lane_factor: .skip 4
.global group_rank
group_rank: .skip 4
.global group_form
group_form: .skip 4
.global group_body_factor
group_body_factor: .skip 4
.global group_carrier_factor
group_carrier_factor: .skip 4
.global group_cardinality_exact
group_cardinality_exact: .skip 4
.global group_cardinality
group_cardinality: .skip 8
.section .text
.global synthesize_resource_schedule
synthesize_resource_schedule:
    ret
.global synthesize_group_fact
synthesize_group_fact:
    ret
