#!/bin/bash
# One-command setup inside the SteamOS guest of the FX Steam Launcher EAC fork.
#   curl -fsSL https://raw.githubusercontent.com/ozturkmert1212/rl-eac-macos/main/install.sh | bash
# Safe to re-run: every step checks what is already there. Run it again after each step it asks you to do.
set -euo pipefail

SCRIPT_VERSION=2026-10-24.5
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
      *"Download size: "*)
        total=${line##*Download size: }; total=${total%% (*}
        case $total in *MiB) total=$(awk -v m="${total% MiB}" 'BEGIN{printf "%.2f GiB", m/1024}') ;; esac ;;
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
  echo "    logged in as $account, installing Rocket League to ~/Games/Heroic"
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
desktop() { pgrep -u "$USER" -x plasmashell >/dev/null; }
steam_up() { pgrep -u "$USER" -x steam >/dev/null; }
# Steam rewrites its files when it exits, and in Game Mode the session can start it again at once,
# so the shortcut and its settings are only done in Desktop Mode.
if ! desktop; then
  todo "switch to Desktop Mode: Steam > Power > Switch to Desktop"
  echo "    waiting for the desktop, Ctrl+C is safe"
  until desktop && steam_up; do sleep 3; done
  sleep 10
  ok "Desktop Mode"
fi
if grep -qaF "$exe" "$STEAM"/userdata/*/config/shortcuts.vdf 2>/dev/null; then
  ok "Steam shortcut already exists"
else
  until steam_up; do sleep 3; done
  steamos-add-to-steam "$exe" >/dev/null 2>&1 || die "could not add the Steam shortcut"
  sleep 5
  ok "Steam shortcut added"
fi

say "Steam shortcut settings"
echo "    install.sh $SCRIPT_VERSION"
# Edits shortcuts.vdf (binary: launch options, name) and config.vdf (text: compat tool) for the shortcut
# whose Exe is $1. "check" only reports; "apply" writes. Steam must not be running for "apply".
shortcut_cfg() {
  python3 - "$@" <<'PY'
import glob, os, re, struct, sys
mode, exe, opts = sys.argv[1], sys.argv[2], sys.argv[3]
steam = os.path.expanduser("~/.local/share/Steam")

def rd_bin(b, i):
    d = {}
    while True:
        t = b[i]; i += 1
        if t == 8: return d, i
        j = b.index(0, i); k = b[i:j].decode("utf-8", "surrogateescape"); i = j + 1
        if t == 0: d[k], i = rd_bin(b, i)
        elif t == 1: j = b.index(0, i); d[k] = b[i:j].decode("utf-8", "surrogateescape"); i = j + 1
        elif t == 2: d[k] = ("i32", struct.unpack_from("<i", b, i)[0]); i += 4
        elif t == 7: d[k] = ("i64", struct.unpack_from("<q", b, i)[0]); i += 8
        else: raise ValueError("unknown shortcuts.vdf type %d" % t)

def wr_bin(d):
    o = bytearray()
    for k, v in d.items():
        kb = k.encode("utf-8", "surrogateescape") + b"\0"
        if isinstance(v, dict): o += b"\0" + kb + wr_bin(v)
        elif isinstance(v, str): o += b"\1" + kb + v.encode("utf-8", "surrogateescape") + b"\0"
        elif v[0] == "i32": o += b"\2" + kb + struct.pack("<i", v[1])
        else: o += b"\7" + kb + struct.pack("<q", v[1])
    return bytes(o + b"\x08")

def sub(d, key):
    # config.vdf key case varies ("Valve"/"valve"), so reuse whatever is there.
    k = next((k for k in d if k.lower() == key.lower() and isinstance(d[k], dict)), key)
    return d.setdefault(k, {})

# Tokens are kept exactly as written (escapes included), so everything not touched is written back unchanged.
def rd_txt(s):
    toks = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', s)
    def node(i):
        d = {}
        while i < len(toks):
            k, br = toks[i]
            if br == "}": return d, i + 1
            if k in d: raise ValueError("duplicate key in config.vdf: " + k)
            q2, br2 = toks[i + 1]
            if br2 == "{": d[k], i = node(i + 2)
            else: d[k] = q2; i += 2
        return d, i
    return node(0)[0]

def wr_txt(d, ind=0):
    o, t = [], "\t" * ind
    for k, v in d.items():
        if isinstance(v, dict): o += [f'{t}"{k}"', t + "{"] + wr_txt(v, ind + 1) + [t + "}"]
        else: o.append(f'{t}"{k}"\t\t"{v}"')
    return o

todo, found = 0, 0
for sf in glob.glob(steam + "/userdata/*/config/shortcuts.vdf"):
    b = open(sf, "rb").read()
    if not b or b[0] != 0: continue
    root, _ = rd_bin(b, b.index(0, 1) + 1)
    name = b[1:b.index(0, 1)].decode()
    for sc in root.values():
        e = next((v for k, v in sc.items() if k.lower() == "exe"), "")
        if not isinstance(e, str) or e.strip('"') != exe: continue
        found = 1
        appid = sc.get("appid", ("i32", 0))[1] & 0xffffffff
        cfgf = steam + "/config/config.vdf"
        cfg = rd_txt(open(cfgf, encoding="utf-8").read())
        m = cfg
        for key in ("InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"):
            m = sub(m, key)
        an = next((k for k in sc if k.lower() == "appname"), "AppName")
        ok = (sc.get("LaunchOptions") == opts and m.get(str(appid), {}).get("name") == "proton_experimental"
              and sc.get(an) not in ("", "Launcher.exe", "Launcher"))
        if mode == "check": todo += not ok; continue
        if ok: continue
        sc["LaunchOptions"] = opts
        if sc.get(an) in ("", "Launcher.exe", "Launcher"): sc[an] = "Rocket League"
        m[str(appid)] = {"name": "proton_experimental", "config": "", "priority": "250"}
        for f, data in ((sf, b"\0" + name.encode() + b"\0" + wr_bin(root) + b"\x08"),
                        (cfgf, ("\n".join(wr_txt(cfg)) + "\n").encode())):
            open(f + ".rl-bak", "wb").write(open(f, "rb").read())
            open(f + ".tmp", "wb").write(data); os.replace(f + ".tmp", f)
if not found: print("    the Steam shortcut for " + exe + " is not in shortcuts.vdf yet", file=sys.stderr); sys.exit(2)
sys.exit(1 if todo else 0)
PY
}
opts="$HOME/bin/rl-wrap.sh %command%"
if shortcut_cfg check "$exe" "$opts"; then
  ok "launch options and Proton Experimental already set"
else
  restart=0
  if pgrep -u "$USER" -x steam >/dev/null; then
    echo "    closing Steam for a moment (it rewrites these files when it exits)"
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 60); do pgrep -u "$USER" -x steam >/dev/null || break; sleep 1; done
    pgrep -u "$USER" -x steam >/dev/null && die "Steam did not exit, close it and run this script again"
    sleep 2; restart=1
  fi
  shortcut_cfg apply "$exe" "$opts" || die "could not write the Steam settings (backups: *.rl-bak next to them)"
  shortcut_cfg check "$exe" "$opts" || die "the Steam settings did not stick"
  ok "launch options set, Proton Experimental forced, shortcut renamed to Rocket League"
  if [ $restart = 1 ]; then
    # Start Steam inside the desktop session, with plasmashell's display and bus.
    pid=$(pgrep -u "$USER" -x plasmashell | head -1)
    (
      while IFS= read -r -d '' kv; do
        case $kv in DISPLAY=*|WAYLAND_DISPLAY=*|XDG_RUNTIME_DIR=*|DBUS_SESSION_BUS_ADDRESS=*|XAUTHORITY=*) export "${kv?}" ;; esac
      done <"/proc/$pid/environ"
      setsid steam </dev/null >/dev/null 2>&1 &
    )
    sleep 15
    if pgrep -u "$USER" -x steam >/dev/null; then ok "Steam started again"; else todo "start Steam again from the desktop"; fi
  fi
fi

say "Done"
printf '    \033[1mGo back to Game Mode before you play\033[0m (desktop icon "Return to Gaming Mode").\n'
echo "    In Desktop Mode the game stays on a white screen."
echo "    Then play Rocket League from the Steam library. The first start is slow."
echo "    Check FX Steam Launcher > Settings > Advanced > Graphics path: DXMT."
