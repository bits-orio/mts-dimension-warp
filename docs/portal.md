# MTS Dimension Warp

> Every team warps its own base, on its own clock, through its own sequence of dimensions.

[![Discord](https://img.shields.io/badge/Discord-join%20the%20server-5865F2?logo=discord&logoColor=white)](https://discord.gg/tWz4FT74pH) [![GitHub](https://img.shields.io/badge/GitHub-source-181717?logo=github&logoColor=white)](https://github.com/bits-orio/mts-dimension-warp)

MTS Dimension Warp requires [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support), and turns it into a race between warping factories. Your whole base rides a platform that jumps to a new world when the warp timer runs out, so you strip each dimension for what you can carry and move on before it takes you with it. Where the original [Dimension Warp](https://mods.factorio.com/mod/dimension-warp) runs one shared warp for everybody, here every team gets its own clock, its own worlds and its own finish line.

## Status

Playable and in active development, running on public multiplayer servers. The per-team warp cycle, the deterministic worlds, the docking bay and the stabilize race are all in. Report anything odd on [Discord](https://discord.gg/tWz4FT74pH) or in the [issue tracker](https://github.com/bits-orio/mts-dimension-warp/issues).

## Quick start

1. Install [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) first — this mod does nothing without it.
2. Enable MTS Dimension Warp and start a new MTS game.
3. Join a team. Your team's home world becomes its warp #0 and the platform is built onto it.
4. Watch the warp clock. Research the warp technologies, deploy harvesters, and take what you can before the jump.

## Features

- Every team warps on its own clock, never in lockstep with anyone else.
- Worlds are seeded deterministically: two teams that reach the same planet at the same warp number face the identical world, so nobody wins or loses on the luck of the draw. A host setting restores full randomization for non-competitive play.
- A finish line — research `stabilize-dimensions` to win. Ranked and non-terminal: the first team to finish stops warping and roams free while everyone else races on.
- A docking bay parks a team whose timer expires with no member online, instead of dropping an undefended base onto a fresh hostile world. It thaws when someone comes back and chooses to resume.
- Dimensions vary wildly — resource-rich worlds, barren rock, islands, and worlds the biters already ate.
- Per-team factory, mining and power floors your team unlocks and keeps across every warp; deaths respawn you on the safe factory floor.
- Harvesters strip a world's ore while you are there, and warp gates, linked loaders and a radio station keep the platform running.
- Warp early by team vote, or ride the timer down.
- Warp events reach Discord with team labels through [Open Discord Bridge](https://mods.factorio.com/mod/open-discord-bridge); milestone results go through MTS.

## Compatibility

Requires Factorio 2.0 and [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support). Space Age is optional and auto-detected — some flavour, like the frozen docking-bay visual, is Space-Age-only. Optional support for [Krastorio 2](https://mods.factorio.com/mod/Krastorio2), [Alien Biomes](https://mods.factorio.com/mod/alien-biomes), [AAI Containers](https://mods.factorio.com/mod/aai-containers), [Factorissimo](https://mods.factorio.com/mod/factorissimo-2-notnotmelon), [Rampant Fixed](https://mods.factorio.com/mod/RampantFixed) and the biter-variant mods. The original [Dimension Warp](https://mods.factorio.com/mod/dimension-warp) mod page remains the source of truth for the detail of the warp gameplay itself, and all of it applies here.

## Works with

- [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) — required; one server, one seed, a private world for every team.
- [Brave New MTS](https://mods.factorio.com/mod/brave-new-mts) — remote-only, character-free play, also built on MTS.

## Credits

MTS Dimension Warp is a fork of [Dimension Warp](https://mods.factorio.com/mod/dimension-warp) by Guillaume ("Anakhon"), rebuilt on the MTS `mts-v1` API. Everything that makes the warp feel the way it does — the platform, the dimension techs, the harvesters, the art and the sound — is Anakhon's work. Dimension Warp is BSD 3-Clause; its licence text is retained verbatim in [LICENSE.dimension-warp](https://github.com/bits-orio/mts-dimension-warp/blob/main/LICENSE.dimension-warp) and the provenance is recorded in [NOTICE](https://github.com/bits-orio/mts-dimension-warp/blob/main/NOTICE). The fork was made with Anakhon's knowledge and encouragement — raised with them before anything shipped, and welcomed.

The chain it stands on: [Warptorio](https://mods.factorio.com/mod/warptorio) by [Nonoce](https://mods.factorio.com/user/NONOCE), then [Warptorio2](https://mods.factorio.com/mod/warptorio2) by [PyroFire](https://mods.factorio.com/user/PyroFire), then Dimension Warp.

The contributions below came with Dimension Warp and remain the work of these people:

- [Hurricane046](https://mods.factorio.com/user/Hurricane046) — radio station design.
- [hgschmie](https://mods.factorio.com/user/hgschmie) / [miniloader-redux](https://mods.factorio.com/mod/miniloader-redux) — loader graphics and part of the loader code.
- [wretlaw120](https://mods.factorio.com/user/wretlaw120) / [Beacon Rebalance](https://mods.factorio.com/mod/wret-beacon-rebalance-mod) — the factory beacon graphic.
- [Quezler](https://mods.factorio.com/user/Quezler) / [Warptorio2 warp harvester indoor drill placement](https://mods.factorio.com/mod/warptorio2-warp-harvester-indoor-drill-placement) — placing drills in undeployed harvesters.
- Russian translation: [Shadow_Man](https://mods.factorio.com/user/Shadow_Man).
- [01526 swoosh 2.wav by Robinhood76](https://freesound.org/s/92909/) — Attribution NonCommercial 4.0 (warpdrive sound).
- [Woosh Noise 1.wav by potentjello](https://freesound.org/s/194081/) — Creative Commons 0 (teleport sound).
- [Space icons created by smalllikeart, Flaticon](https://www.flaticon.com/free-icons/space) — blackhole toggle icon.
- [Supply icons created by Freepik, Flaticon](https://www.flaticon.com/free-icons/supply) — supplies icon.

## Links

- [Source on GitHub](https://github.com/bits-orio/mts-dimension-warp)
- [Community Discord](https://discord.gg/tWz4FT74pH)
- [Changelog](https://github.com/bits-orio/mts-dimension-warp/blob/main/changelog.txt)
- [Design notes and decision records](https://github.com/bits-orio/mts-dimension-warp/tree/main/docs/adr)

## Development

Developed with AI coding assistants alongside human review and in-game testing. Issues and pull requests are welcome on [GitHub](https://github.com/bits-orio/mts-dimension-warp).

License: MIT — see [LICENSE](https://github.com/bits-orio/mts-dimension-warp/blob/main/LICENSE). The upstream Dimension Warp portions remain BSD 3-Clause, retained in [LICENSE.dimension-warp](https://github.com/bits-orio/mts-dimension-warp/blob/main/LICENSE.dimension-warp) with provenance in [NOTICE](https://github.com/bits-orio/mts-dimension-warp/blob/main/NOTICE). Bundled third-party assets keep their own licenses, listed under Credits.
