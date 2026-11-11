# Lev Neo · KOReader customizations

A bricked **Saraiva Lev Neo** e-reader (Bookeen CYBME2F-SA, Allwinner A13, 8 GB eMMC,
758×1024 E Ink at ~212 ppi) brought back to life and turned into a custom reading system:
[KOReader](https://github.com/koreader/koreader) with the ZenOS theme, plus a layer of
Lua user patches, a Spotify plugin, an English-learning screen and a home-grown touch driver.

> Português mais abaixo.

## The recovery, in short

- The device stopped booting after an update with another model's firmware.
- **FEL mode** (the A13's USB boot ROM) was used to load a purpose-built **U-Boot 2024.01**
  exposing the eMMC as **read-only USB mass storage**, so a full backup was taken before
  writing anything.
- Root cause: the installed firmware shipped the board configuration (`script.bin`) of a
  NAND-based model (`storage_type=0`). The Lev's original `script.bin` (eMMC on `mmc2`) was
  **carved from the unallocated space of the boot partition** in the backup and restored.
- The touchscreen turned out to be an **ELAN** controller (found by an I2C bus scan), whose
  driver was missing from the rootfs. A new kernel module was written and cross-compiled
  for the stock 3.0.8 kernel: see [`driver/elan_touch`](driver/elan_touch).
- Also fixed: frontlight PWM freezing after suspend, Wi-Fi/DNS, key-only SSH (dropbear),
  time zone. KOReader was installed with its official Bookeen port.

## What's here

| Path | What it does |
| --- | --- |
| `patches/1-fuso-lev.lua` | Time zone from `/etc/TZ` (KOReader starts without `TZ`). |
| `patches/2-abrindo-lev.lua` | One standard loading modal (centered pill) for every slow action; replaces ZenOS's "Opening" strip and the engine's top-left progress bar. Exposes `_G.__LEV_MODAL`. |
| `patches/2-saudacao-lev.lua` | Optional Home header row (`lev_saudacao`): today's date as a title. Currently turned off in `settings/ZenOS/home.lua` (`rows.enabled.lev_saudacao = false`). |
| `patches/2-agora-lev.lua` | Home row with two cards: Spotify now playing, and Expression of the day with its meaning. |
| `patches/2-palavra-lev.lua` | Expression of the day: 133 curated English expressions for fluency (conversation, opinions, work, phrasal verbs, reactions, polite requests, idioms, common mistakes for Portuguese speakers), each with a plain-English meaning, the Portuguese equivalent, two examples and a usage tip; fully offline. Quiz alternates "what does it mean?" and "how do you say it in English?". |
| `patches/2-faixa-livros-lev.lua` | Home book strip without filters, left-aligned, tighter covers, 5 books per page plus a "+" tile in the cover format that opens the Library. Re-applied on every paint, because the strip caches and rebuilds its pages internally (cover hydration, swipes) without going through `build`. |
| `patches/2-biblioteca-lev.lua` | Clean Library: hides system folders at the storage root (`koreader`, `system`, `Digital Editions`, `Fonts`, `Imagens`, `Pictures`); nothing is deleted. |
| `patches/2-wifi-lev.lua` | Wi-Fi connection with a single modal: while connecting, no system notice is shown ("Turning on Wi-Fi…", "Scanning…", "Authenticating…", the wpa_supplicant steps and raw CTRL-EVENT codes, "Connected to network …", ZenOS toasts), only one "Connecting to Wi-Fi…" pill until connected; a short "Couldn't connect to Wi-Fi" on failure. Questions and the network list still appear. |
| `patches/2-energia-lev.lua` | Battery without hurting the e-ink: the Bookeen launcher pins the CPU at 1 GHz (~260 mA idle). On the A13 the e-ink refresh depends on CPU speed, so a plain `interactive` governor (down to 60 MHz) made the screen look worse and slower. This uses the `userspace` governor: 1 GHz on any input or redraw request (before drawing), 60 MHz after 8 s idle (~190 mA idle). It always suspends and resumes at full speed (`performance`): suspending at 60 MHz made the device reboot instead of waking. Pair it with `auto_suspend_timeout_seconds = 300`. |
| `patches/2-inicio-topo-lev.lua` | Moves the whole Home 18 px down (the device has a dead pixel line near the top). Wraps ZenOS `StandalonePage.mount_body` for the Home only, so rows, gaps and touch areas keep their relative positions. |
| `patches/2-menu-lev.lua` | Quick-settings menu without the top tab bar (quick settings / apps / gear / home icons); always opens on quick settings; the time / Wi-Fi / battery row sits 2 px higher; thin 1 px gray border. Home, Library and Settings stay in the bottom bar. |
| `patches/2-stats-lev.lua` | Home reading stats as one discreet line ("13 pages · 14 min read today · 3-day streak") instead of three big numbers. Row order in `settings/ZenOS/home.lua`: stats above the Spotify / Expression row. |
| `patches/2-noite-lev.lua` | Automatic night mode from 21:00 to 06:00 (acts only at the switch, so manual changes are respected). An "Auto night" button in the ZenOS quick settings turns the automation on/off (`tools/quick_settings_button.lua`, run by `install.sh`). Hours in `lev_noite_inicio` / `lev_noite_fim`. |
| `patches/2-botoes-lev.lua` | Context-aware physical buttons: Home short press = menu, long press = Home; side buttons turn pages in lists, change brightness in the menu, skip tracks in Spotify. |
| `patches/2-brilho-ui-lev.lua` | Brightness control redesigned for an imprecise touchscreen: 8 steps, round −/+ buttons, half-row tap zones. |
| `patches/2-luz-lev.lua` | Frontlight fixes: gamma curve and a "kick" that unfreezes the PWM after the light was off or the device slept. |
| `patches/2-barra-leitor-lev.lua` | Keeps the ZenOS bottom bar visible while reading the newsletter, without covering text. |
| `patches/2-jornal-lev.lua` | Newsletter (RSS via KOReader's News Downloader): every tap on the news tab, and hourly from 06:10, looks for the latest edition in the background; only the latest is kept. If a new edition arrives while you read the old one, it offers to open it. |
| `bin/lev_baixar_jornal.lua` | Lightweight headless downloader used by the patch (installed to the KOReader folder). Runs the News Downloader backend as a fresh process (~90 MB peak) instead of forking KOReader, which ran out of memory on large editions. Use `limit = 1` in `feed_config.lua`. |
| `patches/2-ajustes-lev.lua` | Bottom-bar tabs for the newsletter and Settings. |
| `patches/2-capas-lev.lua` | Applies custom covers dropped in `koreader/capas_lev/` and makes the lock screen fill the panel (Kindle-style crop, no stretching). |
| `patches/2-metadados-lev.lua` | Title/author from the file name (`Title - Author`) and optional clean descriptions. |
| `patches/2-renomear-lev.lua` | One-shot renames to the `Title - Author` pattern (fill in your own list). |
| `patches/2-rodape-lev.lua` | Kindle-like footer ("12 min left in chapter"). |
| `patches/2-icones-lev.lua`, `2-pasta-lev.lua` | Icon tweaks and a fix for a false "folder unreadable" warning. |
| `patches/disabled/` | Earlier experiments kept for reference (not installed). |
| `plugins/spotify.koplugin` | Spotify remote on the Web API with OAuth 2.0 PKCE (no client secret): now playing, library (liked songs, playlists, albums), volume, automatic device choice. |
| `icons/` | Line icons drawn for the UI. |
| `tools/` | Screen capture, simulated key presses and taps, reading defaults. |
| `scripts/` | Spotify authorization helpers. |

Reading defaults applied by the installer: font weight +0.5, darker gamma, best kerning,
line height 1.2, wider margins. Dictionaries: Wiktionary English→Portuguese first, then
FreeDict English–Portuguese, then Wiktionary English–English.

## Requirements

- A Lev Neo (or another Bookeen A13 device) running the **KOReader Bookeen build**.
- The **ZenOS** KOReader plugin, installed separately from its own project
  (not included here). Most Home patches hook into it.
- SSH access to the device (KOReader's SSH server with your public key), with a host
  alias in your `~/.ssh/config`, e.g. `Host lev`.
- On your computer: `ssh`, `tar`, `curl`, `python3`; `zstd` and `xz` for dictionaries.

## Install

```sh
LEV_SSH=lev LEV_NAME="Your name" ./install.sh
```

It backs up everything it overwrites to `/mnt/fat/koreader/backup_lev/<date-time>/`,
copies patches, plugin and icons, downloads fonts and dictionaries (only if missing),
applies the reading defaults and restarts KOReader. Run it again any time to restore
the setup. Use `--no-downloads` to skip fonts and dictionaries.

The greeting name lives in `settings.reader.lua` as `["lev_nome"]` (default: "reader").

### Spotify

1. Create an app at <https://developer.spotify.com/dashboard> with redirect URI
   `http://127.0.0.1:8888/callback` and the Web API enabled.
2. `SPOTIFY_CLIENT_ID=<your id> python3 scripts/authorize_spotify.py` and open the URL.
3. `python3 scripts/token_to_lev.py scripts/token.json > spotify.lua`, copy it to
   `/mnt/fat/koreader/settings/spotify.lua` and delete the local copies.

See `templates/settings/spotify.example.lua`. The plugin rotates the refresh token itself;
don't reuse the same token on another machine.

Optional images not shipped here (trademarks): `spotify_lev.png`, `thenews_logo.png`
and `thenews_capa.png` in `/mnt/fat/koreader/icons`.

## Uninstall

Delete the `*-lev.lua` files from `/mnt/fat/koreader/patches/` and the folder
`/mnt/fat/koreader/plugins/spotify.koplugin`, then restart KOReader. The previous
`settings.reader.lua` is in the latest `backup_lev/` folder.

## Licenses and credits

- This repository: MIT (see `LICENSE`); `driver/` is GPL-2.0-or-later.
- [KOReader](https://github.com/koreader/koreader): AGPL-3.0. ZenOS: see its own project.
- Wiktionary dictionaries (xxyzz/wiktionary_stardict, Vuizur/Wiktionary-Dictionaries):
  CC BY-SA, GFDL/GPL as stated by each project. FreeDict eng-por: GPL.
- Charis SIL: SIL Open Font License 1.1.
- Free Dictionary API: <https://dictionaryapi.dev>.
- Built with Claude Code as an engineering pair.

---

## Português

Um Saraiva Lev Neo que tinha parado de ligar, recuperado e transformado num sistema de
leitura sob medida: KOReader com o tema ZenOS, patches em Lua, plugin de Spotify, tela de
estudo de inglês e um driver de touch próprio.

**Recuperação:** modo FEL do Allwinner A13 com um U-Boot próprio expondo a eMMC como
armazenamento USB somente leitura (backup completo antes de qualquer gravação). A causa
era o `script.bin` de um modelo com NAND vindo no firmware errado; o original foi
recuperado do espaço livre da partição de boot. O touch é um ELAN (achado por varredura
I2C) e ganhou um driver de kernel escrito do zero.

**Instalar:** `LEV_SSH=lev LEV_NAME="Seu nome" ./install.sh` (faz backup do que substitui
em `backup_lev/`, baixa fontes e dicionários se faltarem e reinicia o KOReader).

**Spotify:** crie seu app no painel do Spotify, rode `scripts/authorize_spotify.py` com o seu
Client ID e copie o `spotify.lua` gerado para `/mnt/fat/koreader/settings/`. Nenhuma chave
fica neste repositório.

**Desinstalar:** apague os `*-lev.lua` de `koreader/patches` e a pasta
`plugins/spotify.koplugin`.
