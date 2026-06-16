# MTS Dimension Warp

A per-team fork of Dimension Warp built on Multi-Team Support: each MTS team warps its own base, on its own clock, through its own deterministic sequence of dimensions, racing to stabilize them. Requires MTS; integrates only through the `mts-v1` remote interface.

## Language

### Teams & surfaces

**Team**:
An MTS force named `team-N`. The unit everything in this mod is instanced by — one independent warp cycle per team.
_Avoid_: force (the engine term, for when precision demands it), player (a team can hold many)

**Warp surface**:
The surface a team currently occupies in its warp cycle. At any moment it *is* that team's MTS home surface. MTS creates and retires it on this mod's request; this mod never owns a surface directly.
_Avoid_: dimension surface, level

**Warp number**:
A team's running count of completed warps. With the destination planet, it is what a world's seed is keyed to.

**Adopt**:
Taking the MTS-provided home surface as the team's warp #0 at team birth. This mod creates no surface at team birth — only MTS does; it only bootstraps the platform onto the one MTS made.

### The warp

**Depart**:
The first half of a warp — the platform leaves the current surface.

**Arrive**:
The second half — the platform reaches the next surface. With a member online, Depart and Arrive happen together.

**Docking bay**:
A safe holding surface a team Departs to, but does not Arrive from, when its warp timer expires with every member offline. The team is frozen there until a member returns and chooses to resume.
_Avoid_: limbo, adrift (earlier names for it), space station

**Thaw**:
Resuming a docked team after a member chooses to: power returns gradually, then a warp becomes imminent. Its frozen-and-warming visual exists only under Space Age.

**Fairness seed**:
A team-independent world seed derived from the map seed, the destination planet, and the warp number — so any two teams reaching the same planet at the same warp number face the identical world. A host setting can replace it with full randomization.

**Stabilize**:
A team's win: completing the `stabilize-dimensions` research. Per-team and non-terminal — that team stops warping and roams freely while the others race on; MTS announces the finish.
