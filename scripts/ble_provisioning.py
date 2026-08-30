#!/usr/bin/env python3
"""BLE WiFi-provisioning service - replaces the WLAN hotspot/captive-portal
approach entirely (see scripts/wifi-fallback.sh for the old approach, still
present on this branch for comparison/fallback, not run alongside this).

Christoph, 2026-08-30: wanted a Bluetooth-based setup instead of a
WiFi-hotspot-based one, since the app already has a backend/login and can
carry the WiFi handoff over BLE instead of switching the phone's own WiFi
onto the Pi's temporary hotspot. Not live-tested against real hardware yet
(no BLE central/phone available to pair against while building this
overnight) - the first real pairing test needs a phone physically present.

State machine (as agreed):
  - Normal boot: NetworkManager auto-connects the saved "Customer-WiFi"
    profile on its own, this script just watches.
  - Offline for OFFLINE_TIMEOUT (120s): start BLE advertising.
  - While advertising: re-check for the known WiFi every WIFI_RECHECK (30s);
    the instant it's back, stop advertising immediately - don't make a
    customer whose router was just restarting sit through a provisioning
    flow they didn't need.
  - Central writes new credentials -> test-connect BEFORE touching the old
    profile (a typo'd password must not lock the customer out of both the
    old network and a broken new one) -> only on confirmed success replace
    the saved "Customer-WiFi" profile and stop advertising.
  - Only ever one saved customer WiFi profile at a time (same policy as the
    old hotspot approach's portal_server.py - a device like this lives in
    one place, no reason to accumulate networks).

GATT layout (custom 128-bit UUIDs, base 6c85f0XX-79e0-4a58-a9c1-b8f3d6e7c2a1):
  Service            6c85f000-...
    NETWORKS   (01)   read + notify  - JSON array of {"ssid","security"}
    CREDENTIALS(02)   write          - JSON {"ssid","passphrase"}
    STATUS     (03)   read + notify  - JSON {"state","detail"}
    DEVICE_CODE(04)   read           - plain text pairing code (see
                                        firstboot.sh / /etc/littlefarmers/device-code) -
                                        the app already knows how to hand
                                        this to the backend from the old
                                        deep-link flow, reused here instead
                                        of inventing a second pairing
                                        mechanism.

STATUS.state values the app should handle: idle, connecting, testing,
connected, failed.

Security note, not yet resolved: GATT writes here aren't currently
encrypted at the application layer - relies on BLE's own link-layer
pairing/bonding (bluezero/BlueZ default "Just Works" pairing) to stop
passive eavesdropping on the WiFi password in transit. That's roughly
the same security bar as most consumer IoT BLE provisioning, but isn't
protected against an active attacker. Flagging this rather than quietly
shipping it - worth a deliberate decision, not a default.
"""
import json
import subprocess
import threading
import time

from bluezero import adapter, peripheral

SERVICE_UUID = "6c85f000-79e0-4a58-a9c1-b8f3d6e7c2a1"
CHAR_NETWORKS_UUID = "6c85f001-79e0-4a58-a9c1-b8f3d6e7c2a1"
CHAR_CREDENTIALS_UUID = "6c85f002-79e0-4a58-a9c1-b8f3d6e7c2a1"
CHAR_STATUS_UUID = "6c85f003-79e0-4a58-a9c1-b8f3d6e7c2a1"
CHAR_DEVICE_CODE_UUID = "6c85f004-79e0-4a58-a9c1-b8f3d6e7c2a1"

DEVICE_CODE_FILE = "/etc/littlefarmers/device-code"
CUSTOMER_WIFI_CONN_NAME = "Customer-WiFi"

OFFLINE_TIMEOUT = 120  # seconds of no internet before BLE advertising starts
WIFI_RECHECK_INTERVAL = 30  # seconds between "is the known WiFi back?" checks
CONNECTIVITY_HOST = "1.1.1.1"


def log(msg: str) -> None:
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}", flush=True)


def internet_available() -> bool:
    result = subprocess.run(
        ["ping", "-c", "1", "-W", "3", CONNECTIVITY_HOST],
        capture_output=True, timeout=6,
    )
    return result.returncode == 0


def parse_nmcli_terse(output: str, fields: int) -> list[list[str]]:
    rows = []
    for line in output.splitlines():
        if not line:
            continue
        parts: list[str] = []
        current: list[str] = []
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


def scan_networks() -> list[dict]:
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


def forget_other_wifi_profiles(keep_name: str) -> None:
    try:
        result = subprocess.run(
            ["nmcli", "-t", "-f", "UUID,TYPE,NAME", "connection", "show"],
            capture_output=True, text=True, timeout=15,
        )
    except Exception:
        return
    for uuid, conn_type, name in parse_nmcli_terse(result.stdout, 3):
        if conn_type != "802-11-wireless" or name == keep_name:
            continue
        subprocess.run(["nmcli", "connection", "delete", uuid], capture_output=True, timeout=15)


class ProvisioningState:
    """Shared mutable state between the GATT callbacks (called from
    BlueZ's D-Bus thread) and the connectivity-watch loop. A plain lock is
    enough here - nothing performance-sensitive, just avoiding torn reads/
    writes of the status dict across threads."""

    def __init__(self):
        self.lock = threading.Lock()
        self.status = {"state": "idle", "detail": ""}
        # The actual localGATT.Characteristic object for STATUS, set by
        # build_peripheral() once it exists - set_status() needs this to
        # push a real notify event (via its set_value(), which internally
        # fires PropertiesChanged - confirmed by reading bluezero's
        # localGATT.py source, 2026-08-30). Before that object exists (or
        # after a cycle ends and periph is torn down), notifications are
        # simply skipped - a client can still get the current value via a
        # plain characteristic read.
        self.status_characteristic = None

    def set_status(self, state: str, detail: str = "") -> None:
        with self.lock:
            self.status = {"state": state, "detail": detail}
            char = self.status_characteristic
        log(f"Status: {state} {detail}".strip())
        if char is not None:
            char.set_value(list(json.dumps(self.status).encode("utf-8")))


state = ProvisioningState()


def test_and_apply_credentials(ssid: str, passphrase: str) -> None:
    """Runs off the D-Bus callback thread (started as a daemon thread) so
    the GATT write can return immediately - a phone waiting on a BLE write
    ack while we spend 10-45s testing a WiFi connection would be a bad
    experience and some BLE stacks time the write out anyway."""
    state.set_status("connecting", ssid)

    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if passphrase:
        cmd += ["password", passphrase]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=45)

    if result.returncode != 0:
        state.set_status("failed", result.stderr.strip()[:200])
        return

    state.set_status("testing", ssid)
    time.sleep(2)
    if not internet_available():
        state.set_status("failed", "Verbunden, aber kein Internet")
        # Leave the freshly-added profile in place for a human to debug,
        # but don't touch whatever the old "Customer-WiFi" profile was -
        # a customer must never end up locked out of both.
        return

    # Confirmed working - now safe to make it the one saved profile.
    subprocess.run(
        ["nmcli", "connection", "modify", ssid, "connection.id", CUSTOMER_WIFI_CONN_NAME],
        capture_output=True, timeout=15,
    )
    forget_other_wifi_profiles(CUSTOMER_WIFI_CONN_NAME)
    state.set_status("connected", ssid)


# --- GATT callbacks -------------------------------------------------------

def networks_read_cb():
    return list(json.dumps(scan_networks()).encode("utf-8"))


def credentials_write_cb(value, options):
    try:
        data = json.loads(bytes(value).decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        state.set_status("failed", "ungueltige Anfrage")
        return
    ssid = str(data.get("ssid", "")).strip()
    passphrase = str(data.get("passphrase", ""))
    if not ssid:
        state.set_status("failed", "ssid fehlt")
        return
    threading.Thread(target=test_and_apply_credentials, args=(ssid, passphrase), daemon=True).start()


def status_read_cb():
    with state.lock:
        return list(json.dumps(state.status).encode("utf-8"))


def device_code_read_cb():
    try:
        with open(DEVICE_CODE_FILE, encoding="utf-8") as f:
            return list(f.read().strip().encode("utf-8"))
    except FileNotFoundError:
        return list(b"")


# --- Main provisioning lifecycle ------------------------------------------

def build_peripheral(local_name: str) -> "peripheral.Peripheral":
    adapter_address = list(adapter.Adapter.available())[0].address
    periph = peripheral.Peripheral(adapter_address, local_name=local_name)

    periph.add_service(srv_id=1, uuid=SERVICE_UUID, primary=True)

    periph.add_characteristic(
        srv_id=1, chr_id=1, uuid=CHAR_NETWORKS_UUID,
        value=[], notifying=False, flags=["read"],
        read_callback=networks_read_cb,
    )
    periph.add_characteristic(
        srv_id=1, chr_id=2, uuid=CHAR_CREDENTIALS_UUID,
        value=[], notifying=False, flags=["write"],
        write_callback=credentials_write_cb,
    )
    periph.add_characteristic(
        srv_id=1, chr_id=3, uuid=CHAR_STATUS_UUID,
        value=[], notifying=True, flags=["read", "notify"],
        read_callback=status_read_cb,
        notify_callback=None,
    )
    periph.add_characteristic(
        srv_id=1, chr_id=4, uuid=CHAR_DEVICE_CODE_UUID,
        value=[], notifying=False, flags=["read"],
        read_callback=device_code_read_cb,
    )

    # add_characteristic() only appends to periph.characteristics, doesn't
    # return the object - grab the STATUS one back out by UUID so
    # set_status() can actually push notify events through it (see
    # ProvisioningState.set_status).
    for char in periph.characteristics:
        if char.props.get("org.bluez.GattCharacteristic1", {}).get("UUID") == CHAR_STATUS_UUID:
            state.status_characteristic = char
            break

    return periph


def run_provisioning() -> None:
    device_code = ""
    try:
        with open(DEVICE_CODE_FILE, encoding="utf-8") as f:
            device_code = f.read().strip()
    except FileNotFoundError:
        pass
    local_name = f"LittleFarmers-{device_code[:6] or 'Setup'}"

    log(f"Starte BLE-Advertising als '{local_name}'.")
    state.set_status("idle", "")

    periph = build_peripheral(local_name)

    # bluezero's GLib mainloop (periph.publish() calls self.mainloop.run(),
    # where self.mainloop is a bluezero.async_tools.EventLoop wrapping a
    # plain GLib.MainLoop - confirmed by reading bluezero's actual source,
    # 2026-08-30: there is no Peripheral.stop() method, an earlier draft of
    # this file called one that doesn't exist and would have crashed the
    # very first time this branch tried to end advertising) blocks this
    # thread, so the "did the old WiFi come back?" recheck runs on a
    # background thread instead - it only needs to call
    # periph.mainloop.quit(), which is safe to call from any thread
    # (GLib.MainLoop.quit() is documented thread-safe), to end publish()
    # and return control to run_provisioning's caller.
    def recheck_loop():
        while True:
            time.sleep(WIFI_RECHECK_INTERVAL)
            with state.lock:
                current_state = state.status["state"]
            if current_state == "connected" or internet_available():
                log("WLAN wieder da / Zugangsdaten bestaetigt - beende BLE-Advertising.")
                periph.mainloop.quit()
                return

    threading.Thread(target=recheck_loop, daemon=True).start()
    periph.publish()  # blocks until periph.mainloop.quit() is called (see above)
    log("BLE-Advertising beendet.")


def main() -> None:
    offline_since = 0.0
    log("LittleFarmers BLE-Fallback gestartet.")

    while True:
        if internet_available():
            offline_since = 0.0
            time.sleep(15)
            continue

        if offline_since == 0.0:
            offline_since = time.monotonic()
            log("Keine Internetverbindung erkannt.")

        if time.monotonic() - offline_since < OFFLINE_TIMEOUT:
            time.sleep(15)
            continue

        log(f"Laenger als {OFFLINE_TIMEOUT}s offline - starte BLE-Provisioning.")
        run_provisioning()
        offline_since = 0.0
        time.sleep(5)


if __name__ == "__main__":
    main()
