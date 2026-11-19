#!/usr/bin/env bash
# MDW docking scenarios in the real engine, with a real client. A headless
# server runs a fresh map with this mod, MTS (committed master, from DEPS in
# dev/harness.conf) and dev/mods/mdw-scenario-test; one graphical client
# (private X display, dev/vdisplay.sh) joins, claims a team through MTS's
# landing pen and types /mdw-resume, /mdw-offlinewarp, /mts-pause and
# /mts-resume into its console through dev/gui-drive.sh. A member leaving or
# rejoining is that client stopping or starting. While nobody is online the
# test mod fast-forwards the game so the team's real warp timer runs out and it
# docks.
#
# Sessions:
#   main  [base]       7  last member leaves -> dock, rejoin, /mdw-resume -> arrives live
#                      8  docked: /mts-pause, /mdw-resume holds the dock (held message
#                         once, screenshot), /mts-resume -> arrives live; and /mts-pause
#                         during the 20 s countdown holds it
#                      9  docked, server saved, MTS updated (staged copy of master with
#                         its version bumped): still paused, MDW never re-freezes;
#                         then rejoin, /mdw-resume -> arrives live
#   sa    [space-age]  7  with the pole wires cut on the dock and reconnected
#   hold  [base]       8's first half alone (admin pause, then MDW's resume)
#
#   usage: dev/run-scenarios.sh [main sa hold]   (default: main sa)
#   HARNESS_PORT=<port>   server port (default: a free port the game picks)
#   MDW_REV=<git rev>     stage this mod from a committed revision instead of the
#                         working tree, e.g. MDW_REV=HEAD as a negative control
#                         for an uncommitted fix (expect it to fail)
#
# Exit status is non-zero on any MDW_TEST FAIL, a missing MDW_TEST DONE, a Lua
# or engine error, a desync or a failed step. Everything it started (client,
# server, display) is stopped on exit, also on failure. Logs and screenshots:
# .run/scen/<session>/.
set -uo pipefail
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-lib.sh
. "$DEV/harness-lib.sh"
# shellcheck source=vdisplay.sh
. "$DEV/vdisplay.sh"
# shellcheck source=scenario-lib.sh
. "$DEV/scenario-lib.sh"
PORT=""   # set by scen_server_start
TEST_MOD_DIR="$DEV/mods/mdw-scenario-test"
MTS_REPO="$HOME/src/multi-team-support"
PEN_BUTTON=(185 139)        # MTS landing pen "Start a new team" at 1280x720, UI scale 1
WELCOME_CLOSE=(846 53)      # MTS welcome window's close button
TEAM=""
trap scen_cleanup EXIT
trap 'exit 130' INT TERM

session() { # <name> <set>
  RUN="$REPO/.run/scen/$1"; SET="$2"; SCEN_MODS="$RUN/mods"; CLIENT_N=0
  rm -rf "$RUN"; mkdir -p "$RUN/server" "$RUN/shots"
  echo "== $1 ($2)"
}

claim_team() {
  local attempt line
  "$DEV/gui-drive.sh" click "${WELCOME_CLOSE[@]}"; sleep 0.5
  for attempt in 1 2 3; do
    scen_mark
    "$DEV/gui-drive.sh" click "${PEN_BUTTON[@]}"
    if scen_wait "${ABBR}_TEST STEP fixtures: " 30; then
      line=$(scen_line "${ABBR}_TEST STEP fixtures: ")
      TEAM=$(sed -nE 's/.*team=(team-[0-9]+).*/\1/p' <<< "$line")
      echo "  claimed $TEAM through the pen (${line##*fixtures: })"
      [ -n "$TEAM" ] && return 0
    fi
    scen_shot "claim-attempt-$attempt"
  done
  return 1
}

start_session() {
  harness_stage "$RUN" "$SET" "$TEST_MOD_DIR" || return 1
  if [ -n "${MDW_REV:-}" ]; then
    rm -rf "${SCEN_MODS:?}/$MOD"; mkdir -p "$SCEN_MODS/$MOD"
    git -C "$REPO" archive "$MDW_REV" | tar -x -C "$SCEN_MODS/$MOD" || return 1
  fi
  echo "  staged multi-team-support from master ($(git -C "$MTS_REPO" rev-parse --short master)), $MOD from ${MDW_REV:-the working tree}"
  scen_create "$RUN/world.zip" || return 1
  scen_server_start "$RUN/world.zip" || return 1
  scen_client_setup; scen_client_start || return 1
  claim_team
}

# The last member leaves; the test mod fast-forwards until the warp timer
# docks the team, then the member comes back.
leave_until_docked() {
  scen_step "/mdwt ff-on-leave" ff-armed || return 1
  scen_client_stop
  scen_mark; scen_wait "${ABBR}_TEST STEP docked" 600 || return 1
  echo "  $(scen_line "${ABBR}_TEST INFO docked-after" | sed -E "s/^.*${ABBR}_TEST //")"
  scen_client_start || return 1
}

wait_arrival() { scen_mark; scen_wait "${ABBR}_TEST STEP arrived" 120; }

# 7: dock, rejoin, resume, the base arrives live.
scenario_7() {
  leave_until_docked || return 1
  scen_step "/mdwt mark" mark || return 1
  scen_type "/mdw-resume" || return 1
  sleep 4
  scen_step "/mdwt check-thawed-on-dock" check-thawed-on-dock || return 1
  scen_step "/mdwt watch-arrival s7-arrived" watch-arrival || return 1
  wait_arrival
}

# 8a: docked; an admin pause, then MDW's resume holds the dock; the admin's
# resume lets the countdown run and the base arrives live.
scenario_8a() {
  leave_until_docked || return 1
  scen_step "/mdwt mark" mark || return 1
  scen_type "/mts-pause $TEAM" || return 1
  scen_type "/mdw-resume" || return 1
  sleep 27   # past the 20 s countdown
  scen_console_shot s8a-held-console
  scen_step "/mdwt check-held s8a-held" check-held || return 1
  scen_step "/mdwt watch-arrival s8a-arrived" watch-arrival || return 1
  scen_type "/mts-resume $TEAM" || return 1
  wait_arrival
  scen_console_shot s8a-after-arrival-console
}

run_main() {
  session main base
  start_session || return 1
  scenario_7 || return 1
  scenario_8a || return 1
  # 8b: an admin pause during the countdown holds it
  scen_type "/mdw-offlinewarp" || return 1
  scen_step "/mdwt check-docked" check-docked || return 1
  scen_type "/mdw-resume" || return 1
  sleep 8    # the countdown is running
  scen_step "/mdwt check-thawed-on-dock" check-thawed-on-dock || return 1
  scen_type "/mts-pause $TEAM" || return 1
  sleep 27
  scen_console_shot s8b-held-console
  scen_step "/mdwt check-held s8b-held" check-held || return 1
  scen_step "/mdwt watch-arrival s8b-arrived" watch-arrival || return 1
  scen_type "/mts-resume $TEAM" || return 1
  wait_arrival
  # 9: a mod update while docked
  scen_type "/mdw-offlinewarp" || return 1
  scen_step "/mdwt check-docked" check-docked || return 1
  scen_step "/mdwt pre-update" pre-update || return 1
  scen_client_stop
  scen_server_stop
  grep -q "Saving map as $RUN/world.zip" "$RUN/server.log" || { echo "  the server did not save on SIGTERM"; return 1; }
  local v; v=$(git -C "$MTS_REPO" show master:info.json | python3 -c 'import json,sys; v=json.load(sys.stdin)["version"].split("."); v[-1]=str(int(v[-1])+1); print(".".join(v))')
  rm -rf "${SCEN_MODS:?}/multi-team-support"; mkdir -p "$SCEN_MODS/multi-team-support"
  git -C "$MTS_REPO" archive master | tar -x -C "$SCEN_MODS/multi-team-support" || return 1
  sed -i -E "s/(\"version\": *\")[^\"]+\"/\1$v\"/" "$SCEN_MODS/multi-team-support/info.json"
  echo "  mod update: multi-team-support master staged as $v"
  scen_server_start "$RUN/world.zip" || return 1
  scen_wait "${ABBR}_TEST STEP s9-checked" 60 || return 1
  # after the update the dock still resumes and the base arrives live
  scen_client_start || return 1
  scen_type "/mdw-resume" || return 1
  scen_step "/mdwt watch-arrival s9-arrived-after-update" watch-arrival || return 1
  wait_arrival
  scen_mark; scen_cmd "/mdwt done"; scen_wait "${ABBR}_TEST DONE" 10
  scen_client_stop; scen_server_stop
}

run_hold() {
  session hold base
  start_session || return 1
  scenario_8a
  scen_mark; scen_cmd "/mdwt done"; scen_wait "${ABBR}_TEST DONE" 10
  scen_client_stop; scen_server_stop
}

run_sa() {
  session sa space-age
  start_session || return 1
  scenario_7 || return 1
  scen_mark; scen_cmd "/mdwt done"; scen_wait "${ABBR}_TEST DONE" 10
  scen_client_stop; scen_server_stop
}

WANT=("$@"); [ ${#WANT[@]} -eq 0 ] && WANT=(main sa)
scen_preflight || exit 1
echo "Factorio $ENGINE_VERSION: $FACTORIO"
overall=0
for s in "${WANT[@]}"; do
  case "$s" in
    main|sa|hold) ;;
    *) echo "unknown session: $s"; overall=1; continue ;;
  esac
  "run_$s" || { echo "  [$s] a step failed"; overall=1; }
  scen_cleanup
  scen_evaluate "$s" || overall=1
done
if [ $overall -eq 0 ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $overall
