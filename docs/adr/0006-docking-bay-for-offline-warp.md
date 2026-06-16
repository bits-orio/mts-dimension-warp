# Offline teams keep running; a warp while fully offline parks the base in a docking bay

An offline team's base keeps simulating — defending it is the team's responsibility — and its warp timer keeps ticking; offline does not pause a team. But a warp that fires with *no* member online must not drop the base onto a fresh hostile world undefended. Instead the platform Departs to a safe **docking bay** and waits there, frozen, until a member returns and *chooses* to resume; resuming thaws power over ~30s and a warp becomes imminent at ~60s.

The docking bay must be a separate safe surface, not a freeze-in-place, because the freeze cuts power — including turrets — so a paused base left on its own world would be defenseless. Freezing itself is delegated to MTS's pause feature (see MTS ADR-0001). The dock is an airlock, not a campsite: capping powered time at ~30s before the forced warp prevents a parked team from accruing advantage.
