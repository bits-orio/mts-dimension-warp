# Multiplayer scenario helpers for dev/run-scenarios.sh, sourced after
# harness-lib.sh and vdisplay.sh. Not one of the harness templates: the same
# file sits in multi-team-support and mts-dimension-warp (keep them equal,
# check with cmp).
#
# One headless server, its stdin on a fifo so the runner can send /commands
# from the server console, and at most one graphical client on a private X
# display joining over localhost. The client lives in .run/gui, where
# dev/gui-drive.sh looks for it, so typed commands, clicks and screenshots go
# through gui-drive.sh. A member leaving or rejoining is the client stopping
# or starting again; the server keeps running.
#
# The caller sets RUN (this session's folder) and SCEN_MODS (its mod folder),
# and calls scen_cleanup on exit. scen_server_start sets PORT to the port the
# server bound (a free one the game picks on 2.1.25 and newer).

SCEN_GUI="$REPO/.run/gui"
SCEN_NAME="tester"
SERVER_PID=""
CLIENT_PID=""
CLIENT_N=0
MARK=0

# Refuse to start next to another graphical client (one at a time on this
# machine, about 2 GB each) or with too little memory free.
scen_preflight() {
  local clients avail
  clients=$(ps -C factorio -o pid=,args= | grep -v -e "--start-server" -e "--create" -e "--benchmark" || true)
  if [ -n "$clients" ]; then echo "a Factorio client is already running:"; echo "$clients"; return 1; fi
  avail=$(free -m | awk '/^Mem:/ {print $7}')
  [ "$avail" -ge 3000 ] || { echo "only ${avail} MB of memory available, need 3000"; return 1; }
  local port; port="$(harness_port_request)" || return 1
  if [ "$port" != 0 ] && ss -lun 2>/dev/null | grep -q ":$port "; then echo "UDP port $port is in use"; return 1; fi
}

scen_server_settings() { # <file>
  cat > "$1" <<JSON
{ "name": "$MOD-scenarios", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false, "only_admins_can_pause_the_game": true,
  "autosave_interval": 0, "max_players": 0 }
JSON
}

# A fresh map (seed 1) in <save>, made with the mods in SCEN_MODS.
scen_create() { # <save>
  harness_config "$RUN/server"
  scen_server_settings "$RUN/server-settings.json"
  "$FACTORIO" --config "$RUN/server/config.ini" --create "$1" --mod-directory "$SCEN_MODS" \
    --map-gen-seed 1 > "$RUN/create.log" 2>&1 || { tail -20 "$RUN/create.log"; return 1; }
}

# Starts the server on <save>; returns once it is in game. Later starts in the
# same session append to the same server.log.
scen_server_start() { # <save>
  SERVER_LOG="$RUN/server.log"
  rm -f "$RUN/server.in"; mkfifo "$RUN/server.in"
  exec 7<> "$RUN/server.in"   # held open, so the server never reads EOF on stdin
  MARK=$( [ -f "$SERVER_LOG" ] && wc -l < "$SERVER_LOG" || echo 0)
  "$FACTORIO" --config "$RUN/server/config.ini" --mod-directory "$SCEN_MODS" --start-server "$1" \
    --port "$(harness_port_request)" --server-settings "$RUN/server-settings.json" \
    < "$RUN/server.in" >> "$SERVER_LOG" 2>&1 7>&- &
  SERVER_PID=$!
  PORT="$(harness_bound_port "$SERVER_LOG" "$MARK")" || { echo "  server never hosted"; return 1; }
  echo "  server pid=$SERVER_PID port=$PORT ($(basename "$1"))"
  scen_wait "changing state from\(CreatingGame\) to\(InGame\)" 120
}

# SIGTERM: the server saves the map into the file it was started with.
scen_server_stop() {
  [ -n "$SERVER_PID" ] || return 0
  kill -TERM "$SERVER_PID" 2>/dev/null
  timeout 60 tail --pid="$SERVER_PID" -f /dev/null || kill -9 "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
  SERVER_PID=""
  exec 7>&- 2>/dev/null
}

scen_cmd() { printf '%s\n' "$1" >&7; } # a /command on the server console

# The client's private config, player name and display, once per session.
scen_client_setup() {
  mkdir -p "$SCEN_GUI/userdata"
  rm -f "$SCEN_GUI/pid" "$SCEN_GUI"/confirmed-*
  harness_config "$SCEN_GUI" graphics
  printf '[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale=1\n' >> "$SCEN_GUI/config.ini"
  printf '{ "service-username": "%s" }\n' "$SCEN_NAME" > "$SCEN_GUI/userdata/player-data.json"
  [ -f "$SCEN_GUI/xvfb.pid" ] || vdisplay_start "$SCEN_GUI" 1280x720
}

# Launches the client and waits until the server has it in game.
scen_client_start() {
  local joins i
  joins=$(grep -c "\[JOIN\] $SCEN_NAME joined" "$SERVER_LOG")
  CLIENT_N=$((CLIENT_N + 1))
  DISPLAY="$(cat "$SCEN_GUI/display")" "$FACTORIO" --config "$SCEN_GUI/config.ini" --mod-directory "$SCEN_MODS" \
    --mp-connect "127.0.0.1:$PORT" --window-size 1280x720 --disable-audio \
    > "$RUN/client-$CLIENT_N.log" 2>&1 7>&- &
  CLIENT_PID=$!
  echo "$CLIENT_PID" > "$SCEN_GUI/pid"
  echo "  client pid=$CLIENT_PID (launch $CLIENT_N)"
  for i in $(seq 1 180); do
    [ "$(grep -c "\[JOIN\] $SCEN_NAME joined" "$SERVER_LOG")" -gt "$joins" ] && break
    kill -0 "$CLIENT_PID" 2>/dev/null || { echo "  client exited before joining"; tail -5 "$RUN/client-$CLIENT_N.log"; return 1; }
    sleep 1
  done
  [ "$(grep -c "\[JOIN\] $SCEN_NAME joined" "$SERVER_LOG")" -gt "$joins" ] || { echo "  client never joined"; return 1; }
  sleep 4   # GUIs built on join settle
}

# The member leaves: the client quits, the server sees them go.
scen_client_stop() {
  [ -n "$CLIENT_PID" ] || return 0
  local leaves
  leaves=$(grep -c -e "\[LEAVE\] $SCEN_NAME left" -e "${ABBR}_TEST STEP left" "$SERVER_LOG")
  kill "$CLIENT_PID" 2>/dev/null
  timeout 20 tail --pid="$CLIENT_PID" -f /dev/null || kill -9 "$CLIENT_PID" 2>/dev/null
  wait "$CLIENT_PID" 2>/dev/null
  CLIENT_PID=""
  rm -f "$SCEN_GUI/pid" "$SCEN_GUI"/confirmed-*
  for _ in $(seq 1 40); do   # the server's [LEAVE] line, or the test mod's on_player_left_game
    [ "$(grep -c -e "\[LEAVE\] $SCEN_NAME left" -e "${ABBR}_TEST STEP left" "$SERVER_LOG")" -gt "$leaves" ] && return 0
    sleep 0.5
  done
  echo "  server never logged the leave"
}

scen_mark() { MARK=$(wc -l < "$SERVER_LOG"); }

# Waits for a line matching <regex> in the server log after MARK.
scen_wait() { # <regex> [timeout seconds]
  local re="$1" t="${2:-30}"
  for _ in $(seq 1 $((t * 4))); do
    tail -n +$((MARK + 1)) "$SERVER_LOG" | grep -qE "$re" && return 0
    [ -n "$SERVER_PID" ] && ! kill -0 "$SERVER_PID" 2>/dev/null && { echo "  server died"; return 1; }
    sleep 0.25
  done
  echo "  timed out after ${t}s waiting for: $re"
  return 1
}

# The last line matching <regex> since MARK.
scen_line() { tail -n +$((MARK + 1)) "$SERVER_LOG" | grep -E "$1" | tail -n 1; }

# Runs a test-mod step from the server console and waits for its STEP line.
scen_step() { # <command> <step name> [timeout]
  scen_mark
  scen_cmd "$1"
  scen_wait "${ABBR}_TEST STEP $2(:|$)" "${3:-30}"
}

# Types a command into the client's console (gui-drive.sh), checked by the
# test mod's on_console_command echo; tries again up to twice.
scen_type() { # <text>
  local text="$1" name attempt
  name=$(sed -E 's|^/([^ ]+).*|\1|' <<< "$text")
  for attempt in 1 2 3; do
    scen_mark
    "$DEV/gui-drive.sh" key grave
    "$DEV/gui-drive.sh" type "$text"
    "$DEV/gui-drive.sh" key Return
    if scen_wait "${ABBR}_TEST CMD $name: .*by $SCEN_NAME" 8; then echo "  typed: $text"; sleep 0.5; return 0; fi
    echo "  typing '$text' did not arrive (attempt $attempt)"
    scen_shot "type-failed-$name-$attempt"
    sleep 1
  done
  return 1
}

scen_shot() { # <name>: an OS screenshot of the client window (chat, GUIs)
  "$DEV/gui-drive.sh" shot "$RUN/shots/$1.png" && echo "  screenshot $RUN/shots/$1.png"
}

# Console history: open the console, screenshot, close it again.
scen_console_shot() { # <name>
  "$DEV/gui-drive.sh" key grave; sleep 0.5
  scen_shot "$1"
  "$DEV/gui-drive.sh" key Escape; sleep 0.3
}

# PASS/FAIL/OBS lines and errors from this session's logs. Returns non-zero on
# any FAIL, missing DONE, engine or Lua error, desync or handler mismatch.
scen_evaluate() { # <session name>
  local name="$1" status=0 tag="${ABBR}_TEST" errors pass fail logs=("$RUN"/server.log "$RUN"/client-*.log)
  [ -f "$RUN/create.log" ] && logs+=("$RUN/create.log")
  [ -f "$RUN/bench.log" ] && logs+=("$RUN/bench.log")
  grep -h "$tag \(PASS\|FAIL\|OBS\|DONE\)" "$RUN/server.log" "$RUN"/bench.log 2>/dev/null \
    | sed -E "s/^.*$tag /$tag /" > "$RUN/results.txt"
  pass=$(grep -c "^$tag PASS" "$RUN/results.txt")
  fail=$(grep -c "^$tag FAIL" "$RUN/results.txt")
  grep "^$tag \(FAIL\|OBS\)" "$RUN/results.txt" | sed "s/^/  [$name] /"
  [ "$fail" -gt 0 ] && status=1
  grep -q "^$tag DONE" "$RUN/results.txt" || { echo "  [$name] missing $tag DONE"; status=1; }
  errors=$(harness_errors "${logs[@]}" 2>/dev/null)
  [ -n "$errors" ] && { echo "$errors" | head -20 | sed "s/^/  [$name] ERROR: /"; status=1; }
  if grep -qiE "desync|mod event handlers are not identical|non-recoverable" "${logs[@]}" 2>/dev/null; then
    grep -hiE "desync|mod event handlers are not identical|non-recoverable" "${logs[@]}" | head -5 | sed "s/^/  [$name] /"
    status=1
  fi
  echo "[$name] pass=$pass fail=$fail $([ $status -eq 0 ] && echo ok || echo FAILED)   (logs: $RUN)"
  return $status
}

# Stops what this runner started: the client, the server, the display.
scen_cleanup() {
  scen_client_stop > /dev/null 2>&1
  scen_server_stop
  "$DEV/gui-drive.sh" stop > /dev/null 2>&1
  vdisplay_stop "$SCEN_GUI" 2>/dev/null
}
