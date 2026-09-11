# Wheelchair Current Release Notes

Current release: **1.2.9**.

The authoritative release notes are `RELEASE_NOTES_1_2_9.md`.

Wheelchair 1.2.9 removes the former general causal-resource-routing/home-slot interpretation and replaces it with recipient-blind completion semantics:

```text
Compute locally.
Finish locally.
Release blindly.
```

True dependency communication remains directed. Resource release is not directed. The legal completion-side ownership transition is `OWNED -> FREE`.

The active general runtime no longer contains fixed home ownership, per-worker work inboxes, resource-token routing, post-completion work search, peer-load/resource-demand queries, or persistent idle spin.

Mature Rank-N, Native256, split512x256, Native512, fused tensor and matrix-free technical peaks remain protected rather than being flattened into the general runtime.

See `WHEELCHAIR_CHARTER_1_2_9.md`, `RELEASE_PROOF_1_2_9.md`, and `RELEASE_GATES_1_2_9.txt` for the authoritative doctrine and validation boundary.
