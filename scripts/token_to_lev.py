"""Turn token.json (from authorize_spotify.py) into the plugin settings file.

Usage: python3 token_to_lev.py token.json > spotify.lua
Then copy spotify.lua to /mnt/fat/koreader/settings/spotify.lua on the device
(for example: ssh <your-lev-alias> 'cat > /mnt/fat/koreader/settings/spotify.lua' < spotify.lua).
The output contains your refresh token: do not commit or share it.
"""
import json, sys

t = json.load(open(sys.argv[1]))
q = lambda s: '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
print("-- ./spotify.lua\nreturn {")
print(f'    ["client_id"] = {q(t["client_id"])},')
print(f'    ["refresh_token"] = {q(t["refresh_token"])},')
print("}")
