# Rocket League with Easy Anti-Cheat on Apple silicon

[Türkçe](README.tr.md)

A working setup for running the **Epic Games Store version of Rocket League online, with Easy Anti-Cheat loaded**, on an Apple silicon Mac. It runs inside the SteamOS VM of the [FX Steam Launcher EAC fork](https://github.com/StonkGuy/steamac).

None of the hard parts are mine. This repo only documents how I put the existing pieces together for Rocket League and adds one small wrapper script ([`rl-wrap.sh`](rl-wrap.sh)). All credit goes to the projects under [Credits](#credits).

> [!WARNING]
> **This is unofficial and unsupported.** Epic/Psyonix do not support Rocket League on macOS, in a VM or under emulation. A ban is unlikely as long as you do not cheat or hide the environment, but it is not impossible. **Use an alt account you can afford to lose.**

[![Rocket League online on an Apple silicon Mac (video)](https://img.youtube.com/vi/zC_vq7zjUqI/maxresdefault.jpg)](https://youtu.be/zC_vq7zjUqI)

*Click to watch it running online on YouTube.*

## Result

Tested on 2026-10-21:

| | |
|---|---|
| Mac | M5 Pro, 24 GB RAM, macOS 27.2 |
| Launcher | FX Steam Launcher `1.9-eac.1` (StonkGuy fork) |
| FEX | `eac-2610.3` (StonkGuy patched FEX) |
| Proton | Proton Experimental + Proton EasyAntiCheat Runtime |
| Graphics path | **DXMT** |
| EAC | `Launcher finished with: 301` ("Easy Anti-Cheat successfully loaded in-game"), `bAntiCheatEnabled=True` |
| Online | Epic `EOS_Success`, Psyonix `Login successful`, online matches work |

## How it works

```
macOS ─ FX Steam Launcher (libkrun VM, ARM64 SteamOS)
          └─ Steam ─ FEX-Emu (patched) ─ Steam Linux Runtime ─ Proton Experimental (x86-64)
                       └─ rl-wrap.sh ─ Launcher.exe / RocketLeague.exe + EAC (Linux mode)
```

- EAC is used in its **Linux/Proton mode**. That mode works because Psyonix enabled EAC's Linux/Proton support for Rocket League.
- Valve's stock FEX in Steam's compatibility tool breaks EAC's `ptrace` and signal handling, so EAC fails. StonkGuy's patched FEX fixes this. The [paper](https://cdn.nzlinix.com/share/papers/eac-apple-silicon.pdf) and the fork's [docs](https://github.com/StonkGuy/steamac/blob/fex-eac/docs/fork.md) explain why.
- Heroic on ARM64 only offers ARM64 Wine/Proton, and EAC's x86-64 client cannot load there (code `206`). So **Heroic is only used to log in and install**. The game is started from Steam as a non-Steam game.
- Epic games need a fresh one-time login token (`-AUTH_PASSWORD=...`) on every start. `rl-wrap.sh` gets one from Heroic's bundled `legendary` and adds it to the command line. If the game is out of date, the wrapper updates it first.

## Quick install

1. Do step [1. Launcher and SteamOS](#1-launcher-and-steamos) below on the Mac, then connect over SSH as in [step 3](#3-patched-fex).
2. Inside the VM, run:
   ```sh
   curl -fsSL https://raw.githubusercontent.com/ozturkmert1212/rl-eac-macos/main/install.sh | bash
   ```
3. The script does what it can and stops with a `TODO` when it needs you: confirming Steam's install dialogs, or logging in to Epic in Heroic. Do that, then run the same command again. It skips everything that is already done. Building FEX takes 15-30 minutes, and downloading the game takes a while too.
4. In Desktop Mode it also sets the shortcut's Launch Options and Proton Experimental for you (Steam closes and opens again for a moment). In Game Mode it prints them for you to set by hand.

The manual steps below do the same thing, one by one.

## Setup

### 1. Launcher and SteamOS
1. Install the DMG from [StonkGuy/steamac releases](https://github.com/StonkGuy/steamac/releases). This setup was tested with that fork. The upstream FX release has had an experimental DXMT option since 1.9.2, but I have not tested Rocket League on it. The fork's DMG is ad-hoc signed, so the first time use right-click → Open.
2. Create a SteamOS disk. 120 GB is a good size, since the disk is sparse. Set a password for user `steamos`.
3. Log in to Steam with an account that does not matter.
4. **Settings → Advanced:** turn on **SSH**, set **Graphics path: DXMT**, then restart the launcher.

### 2. Steam tools (inside the VM)
Install these from the Steam library: **Proton Experimental**, **Proton EasyAntiCheat Runtime** and **FEX-Emu**.

### 3. Patched FEX
First connect to the VM over SSH from a terminal on the Mac:
1. In the launcher, open **FX Steam Launcher → Settings** (`Cmd + ,`) → **Advanced** and turn on **SSH**. That tab shows the **port** and a **generated password**. Note both.
2. The setting applies on the next start: shut down SteamOS (**Steam → Power → Shut Down**) or quit the launcher (`Cmd + Q`), then open it again.
3. Connect with the port from the Advanced tab (`2222` below) and enter the password when asked. The VM is only reachable from your own Mac (localhost).

Then build and install FEX inside the VM:
```sh
ssh -p 2222 steamos@127.0.0.1
git clone --depth 1 -b fex-eac https://github.com/StonkGuy/steamac.git ~/steamac-fork
cd ~/steamac-fork/fex-eac
sh build-fex.sh            # ~15-30 min
sh install-fex-tool.sh     # backs up Valve's FEX; `sh install-fex-tool.sh restore` undoes it
sh install-fex-tool.sh status
```
If Steam updates the FEX-Emu tool, the patched build is overwritten and EAC fails with `210`. In that case run `sh install-fex-tool.sh` again.

### 4. Heroic + Rocket League
```sh
mkdir -p ~/Applications && cd ~/Applications
curl -L -o Heroic.AppImage https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v2.22.4/Heroic-2.22.4-linux-arm64.AppImage
chmod +x Heroic.AppImage
```
Open Heroic in Desktop Mode, log in to Epic with your **alt account** and install Rocket League. If you already have the game files, you can copy them into the VM and use **Import Game**.

While Heroic is open, copy its bundled `legendary` to a fixed place. The AppImage mounts at a different path each time:
```sh
mkdir -p ~/bin
cp "$(find /tmp/.mount_Heroic* -type f -name legendary | head -1)" ~/bin/legendary
chmod +x ~/bin/legendary
```

### 5. Wrapper and Steam shortcut
```sh
curl -L -o ~/bin/rl-wrap.sh https://raw.githubusercontent.com/ozturkmert1212/rl-eac-macos/main/rl-wrap.sh
chmod +x ~/bin/rl-wrap.sh
steamos-add-to-steam ~/Games/Heroic/rocketleague/Binaries/Win64/Launcher.exe
```
Change the path if your install is somewhere else. Rocket League's legendary app name is `Sugar`.

In Steam, open the shortcut's **Properties**:
- **Launch Options:** `/home/steamos/bin/rl-wrap.sh %command%`
- **Compatibility:** force **Proton Experimental**

### 6. First start
- The first start is slow: the Proton prefix is created, FEX translates code for the first time, and shaders compile.
- The wrapper turns on `PROTON_LOG`, so Proton writes `~/steam-<appid>.log`. Look there for `Launcher finished with: 301`. `210` or `206` means EAC failed.
- Warm up the shader cache in Free Play or a private match before you play online. Each new effect stutters once.
- The wrapper logs to `~/rl-wrap.log`.

## Notes

- **Use DXMT.** On my M5 the Vulkan path (both KosmicKrisp and MoltenVK) hung the GPU in the main menu.
- **1080p:** the VM screen is 1280×800 by default, so the game offers nothing bigger. Change **Settings → Display → Window size** in the launcher, restart it, and then set the resolution in game.
- **Updates:** if you update the game in Heroic elsewhere, the wrapper updates the VM copy on the next Play. There is no progress bar, so wait.
- **Epic login expired:** open Heroic in the VM and log in again.

## Do not

- Do not run `realism.sh` or set `FEX_HIDEHYPERVISORBIT`. They hide the VM from anti-cheat. That turns compatibility into evasion and is the real ban risk.
- Do not install BakkesMod or put DLLs (DXVK async etc.) in the game folder.
- Do not use your main Epic account.

## Credits

- **[StonkGuy/steamac](https://github.com/StonkGuy/steamac)**: the EAC fork of FX Steam Launcher, `fex-eac/` scripts and DXMT path (Apache-2.0)
- **[StonkGuy/FEX](https://github.com/StonkGuy/FEX/tree/eac-2610)**: FEX-2610 patched for EAC (MIT)
- **[StonkGuy/eac-arm64-emulation-poc](https://github.com/StonkGuy/eac-arm64-emulation-poc)** and the paper [*EAC on Apple silicon*](https://cdn.nzlinix.com/share/papers/eac-apple-silicon.pdf): the research this is all based on
- **[fxgl/steamac](https://github.com/fxgl/steamac)**: FX Steam Launcher by FX GAMES (Apache-2.0)
- **[FEX-Emu](https://github.com/FEX-Emu/FEX)**, **[libkrun](https://github.com/containers/libkrun)**, **[DXMT](https://github.com/3Shain/dxmt)**, Valve's **Proton** and **SteamOS**
- **[Heroic Games Launcher](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher)** and **[legendary](https://github.com/derrod/legendary)** (GPL-3.0)

Not affiliated with Epic Games, Psyonix, Valve, FX GAMES or any of the projects above.

## License

[`rl-wrap.sh`](rl-wrap.sh) and these docs are MIT. The linked projects keep their own licenses. This repo does not redistribute any of them.
