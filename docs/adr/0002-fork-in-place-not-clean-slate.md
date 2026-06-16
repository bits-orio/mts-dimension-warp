# Fork Dimension Warp in place; do not clean-slate

We forked DW's repository — keeping its 360-commit history and an `upstream` remote for cherry-picking Guillaume's ongoing fixes — rather than starting a new project. DW's value is its large data stage (68 prototype files plus graphics and locale) which we keep verbatim, while the per-team work is almost entirely the ~4.8k-line control stage. Clean-slate would mean re-creating the data stage by hand (still a BSD derivative, so no license benefit) and losing the ability to A/B the per-team rewrite against a known-good baseline.

The mod's internal name is changed to `mts-dimension-warp` so it cannot collide with the real Dimension Warp in a user's mod folder. It is a distinct mod for the MTS audience, deliberately divorced from the original — not a competitor to it.
