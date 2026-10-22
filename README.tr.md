# Apple silicon'da Easy Anti-Cheat ile Rocket League

[English](README.md)

Bu rehber, **Rocket League'in Epic Games Store sürümünü EAC yüklenmiş halde, online olarak** Apple silicon bir Mac'te çalıştıran kurulumu anlatıyor. Oyun, [FX Steam Launcher EAC fork'unun](https://github.com/StonkGuy/steamac) SteamOS VM'i içinde çalışıyor.

Zor kısımların hiçbiri benim değil. Bu repo, var olan parçaları Rocket League için nasıl birleştirdiğimi anlatıyor ve küçük bir wrapper script ekliyor ([`rl-wrap.sh`](rl-wrap.sh)). Bütün emek [Kaynaklar](#kaynaklar) bölümündeki projelere ait.

> [!WARNING]
> **Resmi değil, desteklenmiyor.** Epic/Psyonix, Rocket League'i macOS'ta, VM'de ya da emülasyon altında desteklemiyor. Hile yapmadığın ve ortamı gizlemediğin sürece ban ihtimali düşük, ama sıfır değil. **Kaybetmeyi göze alabileceğin bir yan hesap kullan.**

## Sonuç

21 Ekim 2026'da test edildi:

| | |
|---|---|
| Mac | M5 Pro, 24 GB RAM, macOS 27.2 |
| Launcher | FX Steam Launcher `1.9-eac.1` (StonkGuy fork'u) |
| FEX | `eac-2610.3` (StonkGuy'ın yamalı FEX'i) |
| Proton | Proton Experimental + Proton EasyAntiCheat Runtime |
| Grafik yolu | **DXMT** |
| EAC | `Launcher finished with: 301` ("Easy Anti-Cheat successfully loaded in-game"), `bAntiCheatEnabled=True` |
| Online | Epic `EOS_Success`, Psyonix `Login successful`, online maçlar çalışıyor |

## Nasıl çalışıyor

```
macOS ─ FX Steam Launcher (libkrun VM, ARM64 SteamOS)
          └─ Steam ─ FEX-Emu (yamalı) ─ Steam Linux Runtime ─ Proton Experimental (x86-64)
                       └─ rl-wrap.sh ─ Launcher.exe / RocketLeague.exe + EAC (Linux modu)
```

- EAC, **Linux/Proton modunda** çalışıyor. Bu mod, Psyonix Rocket League için EAC'in Linux/Proton desteğini açtığı için çalışıyor.
- Steam'in uyumluluk aracındaki Valve'ın orijinal FEX'i, EAC'in `ptrace` ve sinyal işlemlerini bozuyor, bu yüzden EAC başarısız oluyor. StonkGuy'ın yamalı FEX'i bunu düzeltiyor. Nedenini [makale](https://cdn.nzlinix.com/share/papers/eac-apple-silicon.pdf) ve fork'un [dokümanları](https://github.com/StonkGuy/steamac/blob/fex-eac/docs/fork.md) anlatıyor.
- ARM64 Heroic sadece ARM64 Wine/Proton sunuyor. EAC'in x86-64 istemcisi orada yüklenemiyor (kod `206`). Bu yüzden **Heroic sadece giriş ve kurulum için kullanılıyor**. Oyun, Steam'den "non-Steam game" olarak açılıyor.
- Epic oyunları her açılışta yeni bir tek kullanımlık giriş kodu (`-AUTH_PASSWORD=...`) istiyor. `rl-wrap.sh` bu kodu Heroic'in içindeki `legendary`'den alıp komut satırına ekliyor. Oyun eskiyse önce güncelliyor.

## Kurulum

### 1. Launcher ve SteamOS
1. DMG'yi [StonkGuy/steamac releases](https://github.com/StonkGuy/steamac/releases) sayfasından kur. Resmi FX sürümünü **kurma**, onda DXMT yolu yok. DMG ad-hoc imzalı, ilk açılışta sağ tık → Aç de.
2. SteamOS diski oluştur. Disk sparse olduğu için 120 GB iyi bir boyut. `steamos` kullanıcısına şifre koy.
3. Önemsemediğin bir Steam hesabıyla giriş yap.
4. **Settings → Advanced:** **SSH**'ı aç, **Graphics path: DXMT** seç, sonra launcher'ı yeniden başlat.

### 2. Steam araçları (VM içinde)
Steam kütüphanesinden şunları kur: **Proton Experimental**, **Proton EasyAntiCheat Runtime** ve **FEX-Emu**.

### 3. Yamalı FEX
```sh
ssh -p 2222 steamos@127.0.0.1
git clone --depth 1 -b fex-eac https://github.com/StonkGuy/steamac.git ~/steamac-fork
cd ~/steamac-fork/fex-eac
sh build-fex.sh            # ~15-30 dk
sh install-fex-tool.sh     # Valve'ın FEX'ini yedekler; `sh install-fex-tool.sh restore` geri alır
sh install-fex-tool.sh status
```
Steam FEX-Emu aracını güncellerse yamalı sürümün üzerine yazılır ve EAC `210` hatası verir. O zaman `sh install-fex-tool.sh`'ı tekrar çalıştır.

### 4. Heroic + Rocket League
```sh
mkdir -p ~/Applications && cd ~/Applications
curl -L -o Heroic.AppImage https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v2.22.4/Heroic-2.22.4-linux-arm64.AppImage
chmod +x Heroic.AppImage
```
Heroic'i Desktop Mode'da aç, Epic'e **yan hesabınla** gir ve Rocket League'i kur. Oyun dosyaların zaten varsa VM'e kopyalayıp **Import Game** diyebilirsin.

Heroic açıkken içindeki `legendary`'yi sabit bir yere kopyala. AppImage her açılışta farklı bir yola mount oluyor:
```sh
mkdir -p ~/bin
cp "$(find /tmp/.mount_Heroic* -type f -name legendary | head -1)" ~/bin/legendary
chmod +x ~/bin/legendary
```

### 5. Wrapper ve Steam kısayolu
```sh
curl -L -o ~/bin/rl-wrap.sh https://raw.githubusercontent.com/ozturkmert1212/rl-eac-macos/main/rl-wrap.sh
chmod +x ~/bin/rl-wrap.sh
steamos-add-to-steam ~/Games/Heroic/rocketleague/Binaries/Win64/Launcher.exe
```
Oyun başka bir yere kuruluysa yolu değiştir. Rocket League'in legendary'deki adı `Sugar`.

Steam'de kısayolun **Properties** bölümünü aç:
- **Launch Options:** `/home/steamos/bin/rl-wrap.sh %command%`
- **Compatibility:** **Proton Experimental**'ı zorla

### 6. İlk açılış
- İlk açılış yavaş olur: Proton prefix'i oluşur, FEX kodu ilk kez çevirir, shader'lar derlenir.
- Wrapper `PROTON_LOG`'u açıyor, Proton `~/steam-<appid>.log` dosyasına yazıyor. Orada `Launcher finished with: 301` ara. `210` ya da `206` EAC'in başarısız olduğunu gösterir.
- Online oynamadan önce Free Play veya özel maçta shader cache'i ısıt. Her yeni efekt bir kez takılır.
- Wrapper'ın logu `~/rl-wrap.log`.

## Notlar

- **DXMT kullan.** Benim M5'imde Vulkan yolu (hem KosmicKrisp hem MoltenVK) ana menüde GPU'yu kilitledi.
- **1080p:** VM ekranı varsayılan olarak 1280×800, oyun bundan büyüğünü sunmuyor. Launcher'da **Settings → Display → Window size**'ı değiştir, yeniden başlat, sonra oyunda çözünürlüğü seç.
- **Güncellemeler:** oyunu başka yerde Heroic'ten güncellersen, wrapper bir sonraki Play'de VM'deki kopyayı da günceller. İlerleme çubuğu çıkmaz, bekle.
- **Epic oturumu düştüyse:** VM'de Heroic'i açıp tekrar giriş yap.

## Yapma

- `realism.sh`'ı çalıştırma ve `FEX_HIDEHYPERVISORBIT`'i açma. Bunlar VM'i anti-cheat'ten gizliyor. Bu, uyumluluğu atlatmaya çevirir ve asıl ban riski budur.
- BakkesMod kurma, oyun klasörüne DLL koyma (DXVK async vb.).
- Ana Epic hesabını kullanma.

## Kaynaklar

- **[StonkGuy/steamac](https://github.com/StonkGuy/steamac)**: FX Steam Launcher'ın EAC fork'u, `fex-eac/` script'leri ve DXMT yolu (Apache-2.0)
- **[StonkGuy/FEX](https://github.com/StonkGuy/FEX/tree/eac-2610)**: EAC için yamalanmış FEX-2610 (MIT)
- **[StonkGuy/eac-arm64-emulation-poc](https://github.com/StonkGuy/eac-arm64-emulation-poc)** ve [*EAC on Apple silicon*](https://cdn.nzlinix.com/share/papers/eac-apple-silicon.pdf) makalesi: her şeyin dayandığı araştırma
- **[fxgl/steamac](https://github.com/fxgl/steamac)**: FX GAMES'in FX Steam Launcher'ı (Apache-2.0)
- **[FEX-Emu](https://github.com/FEX-Emu/FEX)**, **[libkrun](https://github.com/containers/libkrun)**, **[DXMT](https://github.com/3Shain/dxmt)**, Valve'ın **Proton**'u ve **SteamOS**
- **[Heroic Games Launcher](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher)** ve **[legendary](https://github.com/derrod/legendary)** (GPL-3.0)

Epic Games, Psyonix, Valve, FX GAMES ya da yukarıdaki projelerin hiçbiriyle bağlantılı değil.

## Lisans

[`rl-wrap.sh`](rl-wrap.sh) ve bu dokümanlar MIT lisanslı. Linklenen projelerin kendi lisansları geçerli. Bu repo hiçbirini yeniden dağıtmıyor.
