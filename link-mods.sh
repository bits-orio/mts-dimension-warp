#!/usr/bin/env bash
#
# link-mods.sh — symlink the Multi-Team Support + MTS Dimension Warp source
# trees into your Factorio mods directory for live testing, so you edit the
# source and just restart Factorio (no copying). Re-runnable and reversible.
#
#   ./link-mods.sh           link the dev mods (parks any installed .zip aside)
#   ./link-mods.sh --unlink  remove the links and restore the parked .zip files
#
# Override paths with env vars if your layout differs:
#   FACTORIO_MODS=~/.factorio/mods SRC_MTS=~/src/multi-team-support \
#   SRC_MDW=~/src/mts-dimension-warp ./link-mods.sh

set -euo pipefail

MODS_DIR="${FACTORIO_MODS:-$HOME/.factorio/mods}"
SRC_MTS="${SRC_MTS:-$HOME/src/multi-team-support}"
SRC_MDW="${SRC_MDW:-$HOME/src/mts-dimension-warp}"

# mod name (must match info.json "name") -> source tree
declare -A MODS=(
  [multi-team-support]="$SRC_MTS"
  [mts-dimension-warp]="$SRC_MDW"
)

link_one() {
  local name="$1" src="$2"
  local dest="$MODS_DIR/$name"
  if [ ! -f "$src/info.json" ]; then
    echo "  ✗ $name: no info.json at $src — skipping"; return 0
  fi
  # A real (non-symlink) folder is probably an installed copy or your own data —
  # never delete it; bail so nothing is lost.
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "  ✗ $name: $dest exists and is NOT a symlink — move it aside yourself first"; return 0
  fi
  rm -f "$dest"                                    # drop any stale symlink
  for z in "$MODS_DIR/${name}_"*.zip; do           # park installed zips: Factorio must see ONE version
    [ -e "$z" ] && mv -v "$z" "$z.bak"
  done
  ln -s "$src" "$dest"
  echo "  ✓ linked $name -> $src"
}

unlink_one() {
  local name="$1"
  local dest="$MODS_DIR/$name"
  [ -L "$dest" ] && rm -v "$dest"
  for b in "$MODS_DIR/${name}_"*.zip.bak; do        # restore parked zips
    [ -e "$b" ] && mv -v "$b" "${b%.bak}"
  done
}

mkdir -p "$MODS_DIR"
if [ "${1:-}" = "--unlink" ]; then
  echo "Unlinking dev mods from $MODS_DIR:"
  for name in "${!MODS[@]}"; do unlink_one "$name"; done
  echo "Done — restored any parked .zip versions."
else
  echo "Linking dev mods into $MODS_DIR:"
  for name in "${!MODS[@]}"; do link_one "$name" "${MODS[$name]}"; done
  cat <<'NOTE'

Next:
  • FULLY RESTART Factorio (data-stage changes need a full restart, not a save reload).
  • Factorio auto-enables new folder mods. For a clean test enable:
      base + space-age + multi-team-support + mts-dimension-warp  (+ any optional companions)
    and DISABLE anything MDW marks incompatible (e.g. lane-filtered-loaders, loaders-make-full-stacks).
  • Edited the source? Just restart Factorio — the links are live, nothing to copy.
  • ./link-mods.sh --unlink restores your installed .zip versions.
NOTE
fi
