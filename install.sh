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
missing=0
for t in "1493710:Proton - Experimental" "1826330:Proton EasyAntiCheat Runtime" "3127680:FEX-Emu"; do
  id=${t%%:*} name=${t#*:}
  if [ -f "$APPS/appmanifest_$id.acf" ]; then
    ok "$name"
  else
    missing=1; todo "$name is not installed, asking Steam to install it"
    steam "steam://install/$id" >/dev/null 2>&1 &
  fi
done
[ $missing = 0 ] || die "confirm the install dialogs in Steam, wait for the downloads, then run this script again"

say "Patched FEX ($FEX_TAG)"
if [ -d "$HOME/steamac-fork/.git" ]; then
  git -C "$HOME/steamac-fork" pull -q --ff-only || todo "could not update ~/steamac-fork, using the copy there"
else
  git clone -q --depth 1 -b fex-eac "$FORK" "$HOME/steamac-fork"
fi
cd "$HOME/steamac-fork/fex-eac"
if sh install-fex-tool.sh status 2>/dev/null | grep -q "^installed: $FEX_TAG"; then
  ok "already installed"
else
  echo "    building FEX in the VM, this takes about 15-30 minutes (log: ~/fex-build.log)"
  sh build-fex.sh >"$HOME/fex-build.log" 2>&1 || die "FEX build failed, see ~/fex-build.log"
  sh install-fex-tool.sh || die "FEX install failed (if a game is running, quit it and run this script again)"
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
  tmp=$(mktemp -d)
  (cd "$tmp" && "$HOME/Applications/Heroic.AppImage" --appimage-extract '*/linux/legendary' >/dev/null)
  lg=$(find "$tmp" -type f -name legendary | head -1)
  [ -n "$lg" ] || die "legendary not found inside Heroic.AppImage"
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
path=$(rl_path)
if [ -z "$path" ]; then
  account=$("$HOME/bin/legendary" status --json 2>/dev/null |
    python3 -c 'import json,sys; a=json.load(sys.stdin).get("account") or ""; print("" if a.startswith("<") else a)' 2>/dev/null || true)
  if [ -z "$account" ]; then
    todo "log in to Epic in Heroic first:"
    echo "      1. Steam > Power > Switch to Desktop, open Heroic.AppImage on the Desktop"
    echo "      2. Log in to Epic with an ALT account (you do not need to install the game there)"
    echo "      3. Close Heroic and run this script again"
    exit 0
  fi
  # Same config and install folder as Heroic, so Heroic sees the game afterwards.
  echo "    logged in as $account, installing Rocket League (about 25 GB) to ~/Games/Heroic"
  "$HOME/bin/legendary" install Sugar -y --base-path "$HOME/Games/Heroic" ||
    die "legendary could not install Rocket League (run this script again to resume)"
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
