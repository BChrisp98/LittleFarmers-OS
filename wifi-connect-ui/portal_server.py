#!/usr/bin/env python3
"""Captive-portal HTTP server for the LittleFarmers setup hotspot.

Replaces balena-os/wifi-connect entirely. Real-hardware testing on
2026-08-23 proved wifi-connect has a reliable internal race - it creates
the NetworkManager access point and then, essentially in the same
instant, tries to bind its own HTTP server to it, and loses that race
consistently on this Pi (confirmed even under normal, non-throttled
conditions in later tests - not just an undervoltage artifact). The same
day, a manual test proved plain `nmcli` (`... 802-11-wireless.mode ap`,
`ipv4.method shared`, `connection up`) brings the AP up fast and
reliably, with NetworkManager's own built-in DHCP/DNS (no separate
dnsmasq process, which was itself failing with "unknown interface
wlan0" every time wifi-connect's own bind failed). This server assumes
the caller (wifi-fallback.sh) has already brought the AP up that way -
it only serves the setup page and turns page actions into `nmcli` calls,
no network-interface management of its own.

Stdlib only, no pip install needed on a fresh Pi.
"""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def parse_nmcli_terse(output: str, fields: int) -> list[list[str]]:
    """Split nmcli -t output into rows of `fields` columns, honouring
    nmcli's backslash-escaping of the ':' field separator inside values
    (e.g. SSIDs that themselves contain a colon)."""
    rows = []
    for line in output.splitlines():
        if not line:
            continue
        parts: list[str] = []
        current = []
        i = 0
        while i < len(line):
            ch = line[i]
            if ch == "\\" and i + 1 < len(line):
                current.append(line[i + 1])
                i += 2
                continue
            if ch == ":" and len(parts) < fields - 1:
                parts.append("".join(current))
                current = []
                i += 1
                continue
            current.append(ch)
            i += 1
        parts.append("".join(current))
        if len(parts) == fields:
            rows.append(parts)
    return rows


def list_networks() -> list[dict]:
    try:
        result = subprocess.run(
            ["nmcli", "-t", "-f", "SSID,SECURITY", "device", "wifi", "list", "--rescan", "yes"],
            capture_output=True, text=True, timeout=15,
        )
    except Exception:
        return []
    seen = set()
    networks = []
    for ssid, security in parse_nmcli_terse(result.stdout, 2):
        if not ssid or ssid in seen:
            continue
        seen.add(ssid)
        networks.append({"ssid": ssid, "security": security or "Open"})
    return networks


def connect_to_network(ssid: str, passphrase: str) -> None:
    # Runs after the HTTP response is already sent - this call moves
    # wlan0 out of AP mode, which is exactly what's supposed to happen
    # next (customer's phone naturally drops off the setup hotspot once
    # wlan0 joins their real network), so it must not block the response.
    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if passphrase:
        cmd += ["password", passphrase]
    subprocess.run(cmd, capture_output=True, text=True, timeout=45)


class Handler(BaseHTTPRequestHandler):
    ui_dir: Path = Path(".")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, status: int, payload) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_static(self, path: str) -> None:
        rel = path.lstrip("/") or "index.html"
        candidate = (self.ui_dir / rel).resolve()
        try:
            candidate.relative_to(self.ui_dir.resolve())
        except ValueError:
            candidate = self.ui_dir / "index.html"
        if not candidate.is_file():
            candidate = self.ui_dir / "index.html"

        content_type = "text/html; charset=utf-8"
        if candidate.suffix == ".css":
            content_type = "text/css"
        elif candidate.suffix == ".js":
            content_type = "application/javascript"
        elif candidate.suffix == ".txt":
            content_type = "text/plain"

        data = candidate.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/networks":
            self._send_json(200, list_networks())
            return
        self._serve_static(self.path)

    def do_POST(self):
        if self.path != "/connect":
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid json"})
            return

        ssid = str(data.get("ssid", "")).strip()
        passphrase = str(data.get("passphrase", ""))
        if not ssid:
            self._send_json(400, {"error": "ssid required"})
            return

        self._send_json(202, {"status": "connecting"})
        threading.Thread(target=connect_to_network, args=(ssid, passphrase), daemon=True).start()


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=80)
    parser.add_argument("--ui-dir", required=True)
    args = parser.parse_args()

    Handler.ui_dir = Path(args.ui_dir)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
