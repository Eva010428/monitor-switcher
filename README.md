# Monitor Switcher

Cross-platform tool for switching dual monitor inputs via DDC/CI. Controls monitor input switching between DisplayPort and HDMI, designed for dual-boot (Windows + macOS) or KVM setups where monitors are shared across systems.

---

## Features

- **Cross-platform**: Windows (`monitorcontrol` library) and macOS (`m1ddc`)
- **Web UI**: Browser-based dashboard — add sources, identify VCP codes, switch inputs
- **System tray**: Optional tray mode so the app runs silently in the background
- **Identify wizard**: Probe candidate VCP codes per monitor, auto-restore after each probe
- **Per-monitor VCP codes**: Each monitor can have a different input code
- **No binary compilation required**: Pure Python DDC/CI via `monitorcontrol` (Windows) or `m1ddc` subprocess (macOS)

## Use Cases

- **Dual-boot systems**: Windows and Mac sharing the same displays
- **KVM companion**: KVM switches keyboard/mouse, this tool switches monitor inputs
- **Workstation switching**: Quick transition between work and personal computers

---

## Requirements

| Platform | Requirement |
|----------|-------------|
| Windows | Python 3.10+, `monitorcontrol` (installed via `pip`) |
| macOS (Apple Silicon) | Python 3.10+, `m1ddc` (`brew install m1ddc`) |
| macOS (Intel) | Python 3.10+, `ddcctl` (`brew install ddcctl`) |

> **Apple Silicon HDMI limitation**: M1/M2/M3/M4 HDMI ports do not support DDC/CI. Connect monitors via **Thunderbolt/USB-C**.

---

## Quick Start

### Step 1: Install Dependencies

```bash
pip install flask monitorcontrol   # Windows
pip install flask                  # macOS (uses m1ddc subprocess)

# macOS: also install m1ddc or ddcctl
brew install m1ddc     # Apple Silicon
brew install ddcctl    # Intel Mac
```

### Step 2: Configure

```bash
cp monitor_hub/config.example.json monitor_hub/config.json
# Edit host/port if needed (defaults: 0.0.0.0:5000)
```

### Step 3: Start

```bash
python -m monitor_hub            # web server mode (terminal stays open)
python -m monitor_hub --tray     # system tray mode (detached, browser opens automatically)
```

Open `http://localhost:5000` if not opened automatically.

### Step 4: Add Sources and Identify

1. Click **+ Add Source** — give this machine a name (e.g., "Windows PC")
2. Click **Identify** next to the source
3. For each monitor, click a candidate VCP code to probe it — the monitor briefly switches then auto-restores
4. Click **Save** when the probe switched to the expected input, then **Confirm**
5. Repeat for other sources (e.g., "Mac Mini")

Once VCP codes are saved, use the **switch buttons** on each source card to switch all monitors at once.

> **Tip**: You can also enter VCP codes manually in the Add/Edit Source dialog (comma-separated, one per monitor, e.g. `15, 17`). Useful if you already know the codes from the monitor's spec.

---

## Web UI

Open `http://<server-ip>:5000` in a browser.

| Button / Feature | Description |
|---|---|
| **+ Add Source** | Create a named input profile; optionally enter VCP codes manually (comma-separated, one per monitor) |
| **Identify** | Interactive VCP discovery — probes one monitor at a time, auto-restores after each probe |
| **Switch buttons** | Per-source-card buttons that immediately switch all local monitors to that source's saved VCP codes |
| **⚙ Settings** | Edit `identify_candidates` and `identify_dwell_ms` |
| **Enable Tray** | Re-launch the server as a background tray app and close the terminal process |
| **✕ Quit** | Stop the server process |

> **Localhost-only controls**: The **Enable Tray** and **Quit** buttons are only shown when the browser is on the same machine as the server (request comes from `127.0.0.1` or `::1`). Remote browsers on the LAN see neither button. This is enforced on both the UI side (via the `local_request` field in `GET /api/settings`) and the server side (HTTP 403 for non-localhost callers).

---

## Architecture

```
monitor_hub/
  ├── __main__.py          ← entry point; --tray flag for tray mode
  ├── tray.py              ← pystray system tray launcher
  ├── server/
  │   ├── app.py           ← Flask app factory
  │   ├── sources.py       ← /api/sources CRUD
  │   ├── execute_switch.py← POST /api/sources/<id>/switch
  │   ├── identify.py      ← /api/identify/* session workflow
  │   └── settings.py      ← GET|PUT /api/settings; POST /api/system/quit|enable-tray
  ├── agent/
  │   └── ddc.py           ← DDC/CI abstraction (monitorcontrol on Windows, m1ddc on macOS)
  ├── templates/index.html ← web UI
  ├── static/              ← app.js, style.css
  ├── config.example.json  ← template; copy to config.json
  └── requirements.txt

monitor_hub/config.json    ← host, port, identify_candidates, identify_dwell_ms
monitor_hub/sources.json   ← source profiles (auto-created)
```

**Sources data model:**
- `"vcp_codes": {"0": 15, "1": 17}` — per-monitor VCP codes (monitor index → value)
- `"vcp_code": 15` — optional legacy single-code field (set when all monitors share the same code)

**Identify session flow:**
1. `POST /api/identify/<source_id>/start` — reads current VCP per monitor (if supported), returns candidate list
2. `POST /api/identify/<session_id>/probe` — sets one monitor to a candidate VCP for `identify_dwell_ms`, then restores; falls back to the source's saved VCP codes as restore target when DDC readback is unsupported (always on macOS, sometimes on Windows)
3. `POST /api/identify/<session_id>/confirm` — persists confirmed VCP codes to `sources.json`

**Configuration** (`monitor_hub/config.json`):

```json
{
  "host": "0.0.0.0",
  "port": 5000,
  "identify_candidates": [15, 16, 17, 18, 19, 3, 4, 27],
  "identify_dwell_ms": 3000
}
```

> **Note on `host`**: Setting `host` to a LAN IP (e.g., `"192.168.1.50"`) does **not** restrict which interface the server binds to — it always binds `0.0.0.0`. Only `"127.0.0.1"` or `"::1"` produces a loopback-only bind.

---

## System Tray Mode

```bash
python -m monitor_hub --tray
```

- Tray icon appears in the system tray
- Browser opens automatically on first launch
- "Open Monitor Hub" reopens the browser
- "Quit" exits the process

**Auto-start on login:**

Windows — create a shortcut in `shell:startup` pointing to:
```
pythonw -m monitor_hub --tray
```
(`pythonw` suppresses the console window.)

macOS — create `~/Library/LaunchAgents/com.user.monitorhub.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.user.monitorhub</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>-m</string>
        <string>monitor_hub</string>
        <string>--tray</string>
    </array>
    <key>WorkingDirectory</key><string>/path/to/monitor-switcher</string>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
```

---

## VCP 0x60 Input Code Reference

| Input Source | Code |
|--------------|------|
| DVI 1 | 3 |
| DVI 2 | 4 |
| DisplayPort 1 | 15 |
| DisplayPort 2 | 16 |
| HDMI 1 | 17 |
| HDMI 2 | 18 |
| HDMI 3 | 19 |
| USB-C / DP | 27 |

Actual values vary by monitor manufacturer. Use the Identify feature to discover the correct code for your setup.

---

## Troubleshooting

### Windows

**Identify probe has no effect / monitor doesn't switch**
- Enable DDC/CI in monitor OSD menu
- Try running as Administrator
- Update graphics driver

**`monitorcontrol` not found**
```cmd
pip install monitorcontrol
```

### macOS

**⚠️ Apple Silicon HDMI Limitation**

Apple Silicon Macs (M1/M2/M3/M4) HDMI ports do not support DDC/CI at the hardware level. Connect monitors via **Thunderbolt/USB-C**.

**`m1ddc: command not found`**
```bash
brew install m1ddc     # Apple Silicon
brew install ddcctl    # Intel Mac
```

**Identify probe doesn't restore the monitor**
- Reduce `identify_dwell_ms` in `config.json` (e.g., `1500`) — some displays drop DDC/CI access after input switch

### General

**Port already in use**
- Change `port` in `config.json`
- Or kill the existing process: `lsof -ti:5000 | xargs kill` (macOS/Linux)

**One monitor switches, the other doesn't**
- Each monitor may need a different VCP code — re-run Identify

---

## Legacy Standalone Mode

The original C++/Shell binary-based standalone switcher is preserved in `legacy/`:

```
legacy/
  ├── switch.bat / switch.sh   ← high-level launchers
  ├── windows/                 ← C++ source (monitor_switcher.cpp)
  └── macos/                   ← Shell scripts (monitor_switcher.sh)
```

These scripts supported `MONITOR_SERVER_URL` for querying a remote Monitor Hub. They are no longer maintained. See the git history for details.

---

## Acknowledgments

- **Windows DDC/CI**: [`monitorcontrol`](https://github.com/newAM/monitorcontrol) library
- **macOS DDC**: [`m1ddc`](https://github.com/waydabber/m1ddc) / [`ddcctl`](https://github.com/kfix/ddcctl)
- **JSON library** (legacy C++): [nlohmann/json](https://github.com/nlohmann/json)

## License

MIT License
