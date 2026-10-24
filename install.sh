#!/bin/bash
# One-command setup inside the SteamOS guest of the FX Steam Launcher EAC fork.
#   curl -fsSL https://raw.githubusercontent.com/ozturkmert1212/rl-eac-macos/main/install.sh | bash
# Safe to re-run: every step checks what is already there. Run it again after each step it asks you to do.
set -euo pipefail

REPO_RAW=https://raw.githubusercontent.com/ozturkmert1212/rl-eac-macos/main
FORK=https://github.com/StonkGuy/steamac.git
FEX_TAG=eac-2610.3
HEROIC_URL=https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v2.22.4/Heroic-2.22.4-linux-arm64.AppImage
STEAM=$HOME/.local/share/Steam
APPS=$STEAM/steamapps
export LEGENDARY_CONFIG_PATH=$HOME/.config/heroic/legendaryConfig/legendary

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m %s\n' "$*"; }
todo() { printf '    \033[33mTODO\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

say "Checking the guest"
[ "$(uname -m)" = aarch64 ] || die "run this inside the SteamOS VM (over SSH), not on the Mac"
[ -d "$APPS" ] || die "Steam library not found at $APPS: start SteamOS and log in to Steam first"
ok "ARM64 SteamOS, Steam library found"

say "Steam tools"
TOOLS=("1493710:Proton - Experimental" "1826330:Proton EasyAntiCheat Runtime" "3127680:FEX-Emu")
# The manifest appears as soon as a download starts; StateFlags has bit 4 (installed) without bit 2 (update needed) once it is done.
installed() {
  local f=$APPS/appmanifest_$1.acf flags
  [ -f "$f" ] || return 1
  flags=$(sed -n 's/^[[:space:]]*"StateFlags"[[:space:]]*"\([0-9]*\)".*/\1/p' "$f")
  [ -n "$flags" ] && (( (flags & 4) && !(flags & 2) ))
}
missing=0
for t in "${TOOLS[@]}"; do
  id=${t%%:*} name=${t#*:}
  if installed "$id"; then
    ok "$name"
  else
    missing=1
    if [ -f "$APPS/appmanifest_$id.acf" ]; then todo "$name is still downloading"; else todo "$name is not installed"; fi
  fi
done
if [ $missing = 1 ]; then
  # Steam shows one install dialog at a time, so ask for the next tool only once the previous download has started.
  echo "    confirm each install dialog in Steam (VM window); waiting for the downloads, Ctrl+C is safe"
  asked='' asked_at=0 now=0
  while :; do
    left=() next='' next_name=''
    for t in "${TOOLS[@]}"; do
      id=${t%%:*}
      installed "$id" && continue
      left+=("${t#*:}")
      [ -z "$next" ] && [ ! -f "$APPS/appmanifest_$id.acf" ] && next=$id next_name=${t#*:}
    done
    [ ${#left[@]} = 0 ] && break
    if [ -n "$next" ] && { [ "$next" != "$asked" ] || [ $((now - asked_at)) -ge 90 ]; }; then
      if [ "$next" = "$asked" ]; then
        printf '\n'; todo "no download started for $next_name; if no dialog showed up, install it from the Steam library by hand"
      fi
      steam "steam://install/$next" >/dev/null 2>&1 &
      asked=$next asked_at=$now
    fi
    printf '\r\033[K    waiting for: %s' "$(IFS=,; echo "${left[*]}")"
    sleep 10; now=$((now + 10))
  done
  printf '\n'; ok "all Steam tools installed"
fi

say "Patched FEX ($FEX_TAG)"
if [ -d "$HOME/steamac-fork/.git" ]; then
  git -C "$HOME/steamac-fork" pull -q --ff-only || todo "could not update ~/steamac-fork, using the copy there"
else
  git clone -q --depth 1 -b fex-eac "$FORK" "$HOME/steamac-fork"
fi
cd "$HOME/steamac-fork/fex-eac"
# Same test as install-fex-tool.sh: the patched build is in place when Steam's FEX tool has the staged binaries.
# (Its version string is fixed at configure time, so it does not say eac-2610.3.)
fex_same() {
  local b
  for b in FEX FEXBash FEXGetConfig FEXOfflineCompiler FEXServer FEXServerManager FEXpidof; do
    cmp -s "$HOME/fex-eac-work/stage/usr/bin/$b" "$APPS/common/FEX-Emu/usr/bin/$b" || return 1
  done
}
if fex_same; then
  ok "already installed"
else
  if [ -x "$HOME/fex-eac-work/stage/usr/bin/FEX" ]; then
    echo "    Steam's FEX tool has Valve's build again (Steam updated it?), putting the patched build back"
  else
    echo "    building FEX in the VM, this takes about 15-30 minutes (log: ~/fex-build.log)"
  fi
  sh build-fex.sh >"$HOME/fex-build.log" 2>&1 || die "FEX build failed, see ~/fex-build.log"
  sh install-fex-tool.sh >/dev/null || die "FEX install failed (if a game is running, quit it and run this script again)"
  ok "installed (Valve's build is backed up; 'sh ~/steamac-fork/fex-eac/install-fex-tool.sh restore' undoes it)"
fi
cd "$HOME"

say "Heroic and legendary"
mkdir -p "$HOME/Applications" "$HOME/bin" "$HOME/Desktop"
if [ ! -x "$HOME/Applications/Heroic.AppImage" ]; then
  curl -fL# -o "$HOME/Applications/Heroic.AppImage" "$HEROIC_URL"
  chmod +x "$HOME/Applications/Heroic.AppImage"
fi
ln -sf "$HOME/Applications/Heroic.AppImage" "$HOME/Desktop/Heroic.AppImage"
ok "Heroic: ~/Applications/Heroic.AppImage (also on the Desktop)"
if [ ! -x "$HOME/bin/legendary" ]; then
  # The AppImage mounts at a new path every start, so keep a copy of its bundled legendary.
  # Its path inside the AppImage differs between builds, so unpack the whole image and search it.
  tmp=$(mktemp -d)
  (cd "$tmp" && "$HOME/Applications/Heroic.AppImage" --appimage-extract >/dev/null) || { rm -rf "$tmp"; die "could not unpack Heroic.AppImage"; }
  lg=$(find "$tmp/squashfs-root" -type f -name legendary -perm -u+x | head -1)
  [ -n "$lg" ] || { rm -rf "$tmp"; die "legendary not found inside Heroic.AppImage"; }
  cp "$lg" "$HOME/bin/legendary" && chmod +x "$HOME/bin/legendary"
  rm -rf "$tmp"
fi
ok "legendary: ~/bin/legendary ($("$HOME/bin/legendary" --version 2>/dev/null | tail -1))"

say "Launch wrapper"
curl -fsSL -o "$HOME/bin/rl-wrap.sh.new" "$REPO_RAW/rl-wrap.sh"
chmod +x "$HOME/bin/rl-wrap.sh.new" && mv -f "$HOME/bin/rl-wrap.sh.new" "$HOME/bin/rl-wrap.sh"
ok "~/bin/rl-wrap.sh"

say "Rocket League"
rl_path() {
  "$HOME/bin/legendary" list-installed --json 2>/dev/null |
    python3 -c 'import json,sys; print(next((g["install_path"] for g in json.load(sys.stdin) if g["app_name"]=="Sugar"), ""))' 2>/dev/null || true
}
epic_account() {
  "$HOME/bin/legendary" status --offline --json 2>/dev/null |
    python3 -c 'import json,sys; a=json.load(sys.stdin).get("account") or ""; print("" if a.startswith("<") else a)' 2>/dev/null || true
}
# Turns legendary's five-line status blocks into one updating line.
progress_bar() {
  local line total='?' pct=0 done_mib=0 eta='--:--:--' dl=0 disk=0 n bar
  while IFS= read -r line; do
    case $line in
      *"Download size: "*) total=${line##*Download size: }; total=${total%% (*} ;;
      *"= Progress: "*)
        pct=${line##*Progress: }; pct=${pct%%%*}
        eta=${line##*ETA: } ;;
      *" - Downloaded: "*) done_mib=${line##*Downloaded: }; done_mib=${done_mib%% MiB*} ;;
      *" + Download"*) dl=${line##*- }; dl=${dl%% MiB/s*} ;;
      *" + Disk"*)
        disk=${line##*- }; disk=${disk%% MiB/s*}
        n=$(( ${pct%.*} * 30 / 100 ))
        bar=$(printf '%*s' "$n" '' | tr ' ' '#')$(printf '%*s' $((30 - n)) '' | tr ' ' '-')
        printf '\r\033[K    [%s] %5s%%  %s / %s  down %s MiB/s  disk %s MiB/s  ETA %s' \
          "$bar" "$pct" "$(awk -v m="$done_mib" 'BEGIN{printf "%.2f GiB", m/1024}')" "$total" "$dl" "$disk" "$eta" ;;
      *ERROR*|*CRITICAL*) printf '\r\033[K    %s\n' "$line" ;;
    esac
  done
}
path=$(rl_path)
if [ -z "$path" ]; then
  account=$(epic_account)
  if [ -z "$account" ]; then
    todo "log in to Epic in Heroic:"
    echo "      1. Steam > Power > Switch to Desktop, open Heroic.AppImage on the Desktop"
    echo "      2. Log in to Epic with an ALT account (you do not need to install the game there)"
    echo "    waiting for the login, Ctrl+C is safe"
    while [ -z "$account" ]; do
      sleep 5
      account=$(epic_account)
    done
    ok "logged in"
  fi
  # Same config and install folder as Heroic, so Heroic sees the game afterwards.
  echo "    logged in as $account, installing Rocket League (about 25 GB) to ~/Games/Heroic"
  echo "    full log: ~/rl-install.log"
  "$HOME/bin/legendary" install Sugar -y --base-path "$HOME/Games/Heroic" 2>&1 | tee "$HOME/rl-install.log" | progress_bar ||
    { printf '\n'; tail -15 "$HOME/rl-install.log" >&2; die "legendary could not install Rocket League (run this script again to resume)"; }
  printf '\n'
  path=$(rl_path)
  [ -n "$path" ] || die "Rocket League still does not show as installed"
fi
exe="$path/Binaries/Win64/Launcher.exe"
[ -f "$exe" ] || die "Launcher.exe not found at $exe"
ok "installed at $path"
if grep -qaF "$exe" "$STEAM"/userdata/*/config/shortcuts.vdf 2>/dev/null; then
  ok "Steam shortcut already exists"
else
  steamos-add-to-steam "$exe" >/dev/null 2>&1 || die "could not add the Steam shortcut"
  ok "Steam shortcut added (it shows up as Launcher.exe, rename it if you like)"
fi

say "Two settings left for you, in Steam: Launcher.exe / Rocket League > Properties"
echo "    Launch Options:  $HOME/bin/rl-wrap.sh %command%"
echo "    Compatibility:   force Proton Experimental"
echo
echo "    Also check FX Steam Launcher > Settings > Advanced > Graphics path: DXMT."
echo "    Then press Play. The first start is slow. EAC is fine when ~/steam-*.log says 'Launcher finished with: 301'."
