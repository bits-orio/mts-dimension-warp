# Victory is per-team and non-terminal

The win — completing the `stabilize-dimensions` research — is kept from DW (which already attributes it to the researching force) but made fully per-team and non-terminal. A winning team simply stops warping and roams freely; the finish is announced through MTS as a ranked race result. The global side-effects are removed: `storage.victory` becomes per-team `ctx.victory`, and DW's `game.set_game_state{game_finished=true}` is dropped so the first finisher does not end every other team's game mid-race.

This fits MTS's "same start, different finish": every team runs its own race to its own finish. There is deliberately no host toggle for a terminal single-winner mode.
