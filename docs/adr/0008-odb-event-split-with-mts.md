# MDW owns a dimension-warp.* ODB catalog; milestone traffic stays MTS-owned

Open Discord Bridge is an optional dependency. MDW registers its own `dimension-warp.*` event catalog and emits DW-specific *flavour* events — dimension warps, docking and return, a base lost while offline — directly, each tagged with MTS team labels. Milestone-shaped achievements (the stabilize win, warp-count markers) are never emitted to ODB directly; they go through `mts-v1 report_milestone` and MTS's existing ODB mirroring owns that traffic, which is what prevents double-posting.

This mirrors Diggy's ODB split (Diggy ADR-0003). Because MTS is a *required* dependency of MDW, Diggy's MTS-absent fallback is dropped entirely — MDW always has MTS labels and always defers milestone traffic to MTS.
