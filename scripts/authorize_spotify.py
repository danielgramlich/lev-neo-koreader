"""One-time Spotify authorization (OAuth 2.0 Authorization Code + PKCE) for the Lev remote.

Usage:
    SPOTIFY_CLIENT_ID=<your app client id> python3 authorize_spotify.py
    # or: python3 authorize_spotify.py <client id>

Opens a local server on 127.0.0.1:8888, receives the code from Spotify and writes
token.json (mode 600) next to this script. No client secret is used.
Create your app at https://developer.spotify.com/dashboard with the redirect URI
http://127.0.0.1:8888/callback. Never commit token.json.
"""
import base64, hashlib, http.server, json, os, secrets, sys, urllib.parse, urllib.request

CLIENT_ID = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("SPOTIFY_CLIENT_ID", "")).strip()
if not CLIENT_ID:
    sys.exit("Set SPOTIFY_CLIENT_ID or pass the client id as the first argument.")
REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = ("user-read-playback-state user-modify-playback-state user-read-currently-playing "
          "playlist-read-private playlist-read-collaborative user-library-read")
FOLDER = os.path.dirname(os.path.abspath(__file__))

verifier = secrets.token_urlsafe(64)[:96]
challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
state = secrets.token_urlsafe(16)
url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
    "client_id": CLIENT_ID, "response_type": "code", "redirect_uri": REDIRECT,
    "code_challenge_method": "S256", "code_challenge": challenge, "scope": SCOPES, "state": state,
})
print("Open this URL in your browser:\n", url, flush=True)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if q.get("state", [""])[0] != state or "code" not in q:
            self.send_response(400); self.end_headers()
            self.wfile.write(b"Authorization refused or invalid."); return
        data = urllib.parse.urlencode({
            "grant_type": "authorization_code", "code": q["code"][0], "redirect_uri": REDIRECT,
            "client_id": CLIENT_ID, "code_verifier": verifier,
        }).encode()
        req = urllib.request.Request("https://accounts.spotify.com/api/token", data=data,
                                     headers={"Content-Type": "application/x-www-form-urlencoded"})
        tok = json.load(urllib.request.urlopen(req, timeout=30))
        path = os.path.join(FOLDER, "token.json")
        with open(path, "w") as f:
            json.dump({"client_id": CLIENT_ID, "refresh_token": tok["refresh_token"],
                       "scope": tok.get("scope", "")}, f)
        os.chmod(path, 0o600)
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8"); self.end_headers()
        self.wfile.write("<h2>Done. The Lev can now control your Spotify.</h2>You can close this page.".encode())
        print("TOKEN-OK, scopes:", tok.get("scope", ""), "->", path, flush=True)
        raise SystemExit


srv = http.server.HTTPServer(("127.0.0.1", 8888), Handler)
try:
    srv.serve_forever()
except SystemExit:
    pass
