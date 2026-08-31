# MIT for the fork, superseding GPLv3

Supersedes [0001](0001-gplv3-over-bsd-origin.md).

This fork is now MIT. The rest of the family moved to MIT and this mod followed, so the
whole set is permissive and consistent.

0001 argued for copyleft to stop a downstream fork closing the source. That argument is
weaker than it looked for this specific artifact: Factorio mods ship as readable Lua
inside a zip the portal serves to anyone, so the practical source-visibility guarantee
does not depend on the licence. What GPLv3 added was a legal obligation on derivatives,
and the owner's stated goal is the opposite — the widest possible reuse, unpaid, as a
public good for Factorio players. MIT serves that goal directly.

What does NOT change: the upstream Dimension Warp portions remain BSD-3-Clause. We do
not relicense Guillaume's ("Anakhon") code. `LICENSE.dimension-warp` retains the original
licence text verbatim and `NOTICE` records the provenance, as BSD-3 requires. Only this
fork's own additions are MIT.

Also recorded in NOTICE: the fork was made with the original author's knowledge and
encouragement. That is a courtesy record, not a licence waiver — the BSD terms govern the
upstream portions regardless.
