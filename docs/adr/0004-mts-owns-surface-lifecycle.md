# MTS owns surface birth and death; MDW orchestrates the warp

MTS is the sole authority over surfaces. At team birth MDW *adopts* MTS's home surface as warp #0 (bootstrapping the platform onto it, deferring starter items to MTS). On every later warp MDW asks MTS to create the next surface and to retire the old one via new `mts-v1` functions; MDW supplies the `map_gen_settings` (keeping DW's per-planet generation knowledge) while MTS performs creation, ownership registration, planet association, visibility, and deletion.

This keeps a single registry writer (ADR-0003), inherits MTS's ownership and visibility handling for free, and mirrors how Diggy lets MTS own its per-team surfaces.

Considered: MDW creating and deleting surfaces itself and notifying MTS afterward. Rejected — it splits surface authority and races MTS's own spawn flow at team birth.
