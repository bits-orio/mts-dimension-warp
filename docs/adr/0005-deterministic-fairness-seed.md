# Warp worlds are fair by deterministic seed, keyed by planet and warp number

A warp world's seed is derived as a pure function of `(map_seed, planet, warp_number)` with no team identity, so any two teams that reach the same planet at the same warp number face the byte-identical world. This replaces stock DW's per-warp randomization (`math.random + game.tick`), which is unacceptable for MTS's competitive races, while preserving DW's open progression: teams still choose their own destinations. Fairness is therefore a property of the rule, not of enforced lockstep.

Consequence accepted: the same planet at *different* warp numbers yields different (but equally fair) worlds — the price of open progression, and a deliberate "deeper warps are stranger worlds" flavour. A host setting restores full randomization for non-competitive play.

`math.random` or `game.tick` anywhere in the warp-world generation path is a bug — it breaks both fairness and save reproducibility.
