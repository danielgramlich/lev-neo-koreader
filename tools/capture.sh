#!/bin/sh
# Screenshot of the Lev over SSH: ./capture.sh out.png
# Uses the SSH host alias in $LEV_SSH (default "lev", from your ~/.ssh/config).
# The framebuffer is 8 bpp 1024x758 landscape; it is rotated to portrait here (needs python3 + Pillow).
set -e
HOST="${LEV_SSH:-lev}"; OUT="${1:-lev.png}"; TMP="$(mktemp)"
ssh "$HOST" 'dd if=/dev/fb0 bs=1024 count=758 2>/dev/null' > "$TMP"
python3 -c "import sys; from PIL import Image; Image.frombytes('L',(1024,758),open(sys.argv[1],'rb').read()).rotate(-90,expand=True).save(sys.argv[2])" "$TMP" "$OUT"
rm -f "$TMP"; echo "$OUT"
