#!/bin/bash
# Rocket League (Epic, imported in Heroic) through Steam: FEX -> Steam Linux Runtime -> Proton -> EAC.
# Steam launch options:  /home/steamos/bin/rl-wrap.sh %command%
# Fetches a fresh Epic login for the Heroic account and appends it to the game's command line.
# If the game is out of date (e.g. updated in Heroic on the Mac), updates this VM's copy first.
set -u
LOG=$HOME/rl-wrap.log
export LEGENDARY_CONFIG_PATH=$HOME/.config/heroic/legendaryConfig/legendary
export PROTON_EAC_RUNTIME="$HOME/.local/share/Steam/steamapps/common/Proton EasyAntiCheat Runtime"
[ -n "${STEAM_COMPAT_DATA_PATH:-}" ] &&
  export EAC_LAUNCHERDIR="$STEAM_COMPAT_DATA_PATH/pfx/drive_c/users/steamuser/AppData/Roaming/EasyAntiCheat"
export WINEDEBUG=-all PROTON_USE_XALIA=0 PROTON_LOG=1

ERR=$(mktemp)
get_args() {
  "$HOME/bin/legendary" launch Sugar --json 2>"$ERR" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
print(shlex.join(d["game_parameters"] + d["egl_parameters"] + d["user_parameters"]))' 2>/dev/null
  cat "$ERR" >>"$LOG"
}
ARGS=$(get_args)
if [ -z "$ARGS" ] && grep -q "out of date" "$ERR"; then
  echo "$(date) game out of date, updating this VM's copy..." >>"$LOG"
  "$HOME/bin/legendary" update Sugar -y >>"$LOG" 2>&1
  ARGS=$(get_args)
fi
rm -f "$ERR"
if [ -z "$ARGS" ]; then
  echo "$(date) legendary returned no launch parameters (update failed or Epic login expired? see above)" >>"$LOG"
  exit 1
fi
echo "$(date) launching: compat data=${STEAM_COMPAT_DATA_PATH:-unset}, $# args from Steam" >>"$LOG"
eval "set -- \"\$@\" $ARGS"
exec "$@"
