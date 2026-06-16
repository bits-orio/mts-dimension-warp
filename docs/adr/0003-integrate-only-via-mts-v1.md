# MTS Dimension Warp integrates with MTS only through mts-v1

MDW reads and writes MTS state exclusively through the `mts-v1` remote interface and its custom events; it never touches MTS's `storage` directly. MTS internals change constantly (same owner), and any direct storage access would silently corrupt the surface registry on the next MTS refactor and strand players in the void. We extend `mts-v1` additively as needed (surface lifecycle, pause, team-clock events) — backward-compatible, and the hooks benefit any future MTS consumer.

This single constraint — MTS is the only writer of its own state — is what lets the two mods evolve independently without rotting each other.
