# MTS Dimension Warp

Per-team Dimension Warp for Multi-Team Support. Every team builds on a platform that warps between dimensions on its own clock, racing to stabilize them — same start, different finish.

> **Status:** early development. The per-team foundation is being built on top of Dimension Warp's mechanics.

## Built on Dimension Warp — by Anakhon

MTS Dimension Warp is a fork of **[Dimension Warp](https://mods.factorio.com/mod/dimension-warp), created by Anakhon (Guillaume).**

Everything that makes the warp *feel* the way it does — the platform that carries your whole base between worlds, the dimension techs, the harvesters, the art and sound, the relentless pace of Gleba — is Anakhon's work, written from scratch. This fork does exactly one thing on top of that: it makes the experience **per-team**, so it can be played as a fair race on [Multi-Team Support](https://github.com/bits-orio/multi-team-support).

The game underneath this belongs to Anakhon. If you enjoy it, go play the **[original Dimension Warp](https://mods.factorio.com/mod/dimension-warp)** — its mod page is the source of truth for the full detail of the warp gameplay (compatibilities, Rampant tuning, the dimension techs, planet behaviour), and all of it applies here.

## What this fork changes

Where Dimension Warp runs one shared warp for everyone, MTS Dimension Warp gives **each team its own**:

- **Its own warp world, on its own clock** — teams warp independently, never in lockstep.
- **Fair by determinism** — two teams that reach the same planet at the same warp number get the *identical* world, so no team wins or loses on the luck of the draw. A host setting restores full randomization.
- **A finish line** — research `stabilize-dimensions` to win. It's a ranked, **non-terminal** race: the first team to finish doesn't end anyone else's game.
- **Offline safety** — a team whose timer runs out while everyone's offline is parked safely in a docking bay, not dropped into a hostile new world undefended.

It **requires** Multi-Team Support and integrates with it only through the public `mts-v1` API.

## Requirements

- **[Multi-Team Support](https://github.com/bits-orio/multi-team-support)** — required.
- Works **with or without** Space Age (some flavour, like the frozen docking-bay visual, is Space-Age-only).

## Lineage

This mod stands on a chain of work, with gratitude to every link:

1. **[Warptorio](https://mods.factorio.com/mod/warptorio)** by [Nonoce](https://mods.factorio.com/user/NONOCE) — the original warping-platform idea.
2. **[Warptorio2](https://mods.factorio.com/mod/warptorio2)** by [PyroFire](https://mods.factorio.com/user/PyroFire) — which expanded and refined it.
3. **[Dimension Warp](https://mods.factorio.com/mod/dimension-warp)** by Anakhon — a from-scratch take for Factorio 2.0 / Space Age, and the direct basis for this fork.
4. **MTS Dimension Warp** — this per-team adaptation for Multi-Team Support.

## License

MTS Dimension Warp is licensed under the **GPLv3** — see [LICENSE](LICENSE).

It is a derivative work of Dimension Warp, which is **BSD 3-Clause** © 2025 Guillaume ("Anakhon"). The original BSD license is retained verbatim in [LICENSE.dimension-warp](LICENSE.dimension-warp), and the provenance is recorded in [NOTICE](NOTICE). Per the BSD license's third clause, the names "Dimension Warp", "Guillaume", and "Anakhon" are not used to endorse or promote this fork.

## Credits & thanks

The contributions below come from Dimension Warp and remain the work of these people — their art, code, and sounds live on in this fork.

### People and mods
* [Hurricane046](https://mods.factorio.com/user/Hurricane046) — Radio Station design.
* [hgschmie](https://mods.factorio.com/user/hgschmie) / [miniloader-redux](https://mods.factorio.com/mod/miniloader-redux) — loader graphics and part of the loader code.
* [wretlaw120](https://mods.factorio.com/user/wretlaw120) / [Beacon Rebalance](https://mods.factorio.com/mod/wret-beacon-rebalance-mod) — a beacon graphic used for the factory beacon.
* [Quezler](https://mods.factorio.com/user/Quezler) / [Warptorio2 — warp harvester indoor drill placement](https://mods.factorio.com/mod/warptorio2-warp-harvester-indoor-drill-placement) — the solution for placing drills in harvesters when not deployed.
* [Nonoce](https://mods.factorio.com/user/NONOCE) / [Warptorio](https://mods.factorio.com/mod/warptorio) — the original mod.
* [PyroFire](https://mods.factorio.com/user/PyroFire) / [Warptorio2](https://mods.factorio.com/mod/warptorio2) — expanding and improving that first version.

### Translations
* Russian: [Shadow_Man](https://mods.factorio.com/user/Shadow_Man)

### Assets
* [01526 swoosh 2.wav by Robinhood76](https://freesound.org/s/92909/) — License: Attribution NonCommercial 4.0 (warpdrive sound).
* [Woosh Noise 1.wav by potentjello](https://freesound.org/s/194081/) — License: Creative Commons 0 (teleport sound).
* [Space icons created by smalllikeart — Flaticon](https://www.flaticon.com/free-icons/space) — blackhole icon toggle.
* [Supply icons created by Freepik — Flaticon](https://www.flaticon.com/free-icons/supply) — supplies icon.
