#!/bin/sh
# Installs (or reinstalls) the Lev Neo customizations over SSH, from a Mac or Linux machine.
#
#   LEV_SSH=lev ./install.sh            # host alias from your ~/.ssh/config (default: lev)
#   LEV_SSH_OPTS="-F /path/ssh_config" LEV_SSH=lev ./install.sh
#   LEV_NAME="Ana" ./install.sh         # name used by the Home greeting (optional)
#   ./install.sh --no-downloads         # skip fonts and dictionaries
#
# Safe to run again: everything it overwrites on the device is first copied to
# /mnt/fat/koreader/backup_lev/<date-time>/. KOReader is restarted at the end.
# Requires on this machine: ssh, tar, curl, python3; zstd and xz for the dictionaries.
set -eu

HOST="${LEV_SSH:-lev}"
SSH_OPTS="${LEV_SSH_OPTS:-}"
KO=/mnt/fat/koreader
DOWNLOADS=1
[ "${1:-}" = "--no-downloads" ] && DOWNLOADS=0

HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/lev-neo-koreader"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
export COPYFILE_DISABLE=1   # no macOS ._ files inside the tarballs

lev() { ssh $SSH_OPTS -o ConnectTimeout=20 "$HOST" "$@"; }
# send a local tar file and unpack it into a folder on the device (BusyBox tar: no -z)
send_tar() { lev "mkdir -p '$2' && cat > /tmp/lev_install.tar && tar -xf /tmp/lev_install.tar -C '$2' && rm -f /tmp/lev_install.tar" < "$1"; }

echo "==> Checking the device ($HOST)"
lev "test -x $KO/luajit" || { echo "KOReader not found in $KO on $HOST"; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
echo "==> Backing up files that will be overwritten (backup_lev/$STAMP)"
lev "cd $KO && B=backup_lev/$STAMP && mkdir -p \$B/patches \$B/plugins \$B/icons \
  && cp -p settings.reader.lua \$B/ 2>/dev/null; \
  for f in patches/*-lev.lua; do [ -e \"\$f\" ] && cp -p \"\$f\" \$B/patches/; done; \
  [ -d plugins/spotify.koplugin ] && cp -rp plugins/spotify.koplugin \$B/plugins/; \
  for f in lev_ajustes.svg lev_engrenagem.svg sp_anterior.png sp_anterior_claro.png sp_pausar.png \
    sp_pausar_claro.png sp_proxima.png sp_proxima_claro.png sp_tocar.png sp_tocar_claro.png; do \
    [ -e icons/\$f ] && cp -p icons/\$f \$B/icons/; done; true"

echo "==> Copying patches, Spotify plugin and icons"
mkdir -p "$STAGE/ko/patches" "$STAGE/ko/plugins" "$STAGE/ko/icons"
cp "$HERE"/patches/*.lua "$STAGE/ko/patches/"
cp -R "$HERE/plugins/spotify.koplugin" "$STAGE/ko/plugins/"
cp "$HERE"/icons/*.svg "$HERE"/icons/spotify/*.png "$STAGE/ko/icons/"
cp "$HERE"/bin/lev_baixar_jornal.lua "$STAGE/ko/"
(cd "$STAGE/ko" && tar -cf "$STAGE/ko.tar" patches plugins icons lev_baixar_jornal.lua)
send_tar "$STAGE/ko.tar" "$KO"

if [ "$DOWNLOADS" = 1 ]; then
  mkdir -p "$CACHE"
  fetch() { [ -s "$CACHE/$1" ] || curl -fsSL -o "$CACHE/$1" "$2"; }

  echo "==> Fonts (Charis SIL, OFL)"
  if lev "test -e $KO/fonts/charis/CharisSIL-Regular.ttf"; then
    echo "    already installed"
  else
    mkdir -p "$STAGE/fonts/charis"
    for f in CharisSIL-Regular CharisSIL-Bold CharisSIL-Italic CharisSIL-BoldItalic; do
      fetch "$f.ttf" "https://github.com/google/fonts/raw/main/ofl/charissil/$f.ttf"
      cp "$CACHE/$f.ttf" "$STAGE/fonts/charis/"
    done
    fetch charis-OFL.txt "https://github.com/google/fonts/raw/main/ofl/charissil/OFL.txt"
    cp "$CACHE/charis-OFL.txt" "$STAGE/fonts/charis/OFL.txt"
    (cd "$STAGE/fonts" && tar -cf "$STAGE/fonts.tar" charis)
    send_tar "$STAGE/fonts.tar" "$KO/fonts"
  fi

  echo "==> Dictionaries (English-Portuguese and English)"
  mkdir -p "$STAGE/dict"
  if ! lev "test -e $KO/data/dict/en-pt/en-pt.ifo"; then
    if command -v zstd >/dev/null 2>&1; then
      fetch en-pt.tar.zst "https://github.com/xxyzz/wiktionary_stardict/releases/latest/download/en-pt.tar.zst"
      mkdir -p "$STAGE/dict/en-pt" && zstd -dc "$CACHE/en-pt.tar.zst" | tar -xf - -C "$STAGE/dict/en-pt"
    else
      echo "    zstd not found: skipping Wiktionary en-pt (brew install zstd)"
    fi
  fi
  if ! lev "test -e $KO/data/dict/eng-por/eng-por.ifo"; then
    fetch freedict-eng-por.tar.xz "https://download.freedict.org/dictionaries/eng-por/0.3/freedict-eng-por-0.3.stardict.tar.xz"
    tar -xJf "$CACHE/freedict-eng-por.tar.xz" -C "$STAGE/dict"
  fi
  if ! lev "test -e '$KO/data/dict/en-en/English-English Wiktionary dictionary.ifo'"; then
    fetch en-en.tar.gz "https://github.com/Vuizur/Wiktionary-Dictionaries/raw/master/English-English%20Wiktionary%20dictionary%20stardict.tar.gz"
    mkdir -p "$STAGE/dict/x" "$STAGE/dict/en-en"
    tar -xzf "$CACHE/en-en.tar.gz" -C "$STAGE/dict/x"
    find "$STAGE/dict/x" -type f -exec mv {} "$STAGE/dict/en-en/" \;
    rm -rf "$STAGE/dict/x"
  fi
  if [ -n "$(ls -A "$STAGE/dict")" ]; then
    (cd "$STAGE/dict" && tar -cf "$STAGE/dict.tar" .)
    send_tar "$STAGE/dict.tar" "$KO/data/dict"
  else
    echo "    already installed"
  fi
fi

echo "==> Reading defaults, dictionary order and greeting name"
lev "cat > /tmp/reading_defaults.lua" < "$HERE/tools/reading_defaults.lua"
lev "cd $KO && ./luajit /tmp/reading_defaults.lua 2>/dev/null | grep -v '^ffi'; rm -f /tmp/reading_defaults.lua"
if [ -n "${LEV_NAME:-}" ]; then
  # the name goes in a Lua long string, so quotes in it are harmless
  printf '%s\n' "require('setupkoenv')" \
    "local g = require('luasettings'):open('$KO/settings.reader.lua')" \
    "g:saveSetting('lev_nome', [==[${LEV_NAME}]==])" "g:flush()" > "$STAGE/name.lua"
  lev "cat > /tmp/lev_name.lua && cd $KO && ./luajit /tmp/lev_name.lua >/dev/null 2>&1; rm -f /tmp/lev_name.lua" < "$STAGE/name.lua"
fi

echo "==> Quick settings button (Auto night)"
lev "cat > /tmp/qs_button.lua" < "$HERE/tools/quick_settings_button.lua"
lev "cd $KO && ./luajit /tmp/qs_button.lua 2>/dev/null | grep -v '^ffi'; rm -f /tmp/qs_button.lua"

echo "==> Restarting KOReader"
# kill -9 so KOReader does not overwrite settings.reader.lua on exit; koreader.sh relaunches it
lev "kill -9 \$(pidof luajit) 2>/dev/null; true"

cat <<'EOT'
Done. KOReader is restarting on the device.
Optional, not included in this repository (trademarks): put your own spotify_lev.png,
thenews_logo.png and thenews_capa.png in /mnt/fat/koreader/icons.
Spotify needs your own app credentials: see README > Spotify.
EOT
