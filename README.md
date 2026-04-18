# Monitor Switcher

Cross-platform tool for switching dual monitor inputs via DDC/CI. Controls monitor input switching between DisplayPort and HDMI, designed for dual-boot (Windows + macOS) or KVM setups where monitors are shared across systems.

---

## Features

- **Cross-platform**: Windows (C++) and macOS (Shell + m1ddc/ddcctl)
- **One-click switching**: Switch all monitors simultaneously
- **Auto-setup wizard**: Auto-detect input codes, blink brightness to identify monitors, interactive configuration generation
- **JSON configuration**: Easily editable config file after setup
- **Portable**: No installation required, single executable approach
- **Network Hub** *(optional)*: `monitor_hub` — Python Flask service that coordinates switching across machines on the same LAN via a web UI and REST API

## Use Cases

- **Dual-boot systems**: Windows and Mac sharing the same displays, auto-switch inputs when booting
- **KVM companion**: KVM switches keyboard/mouse, this tool switches monitor inputs
- **Workstation switching**: Quick transition between work and personal computers
- **Multi-machine hub**: One central server manages VCP codes; all machines query it before switching

---

## Quick Start (Standalone Mode)

### Step 1: Build (Windows) / Install Dependencies (macOS)

#### Windows

```cmd
cd windows
mingw32-make
copy monitor_switcher.exe ..\bin\
```

See [windows/BUILD.md](windows/BUILD.md) for detailed build instructions.

#### macOS

```bash
# Apple Silicon
brew install m1ddc

# Intel Mac
brew install ddcctl

chmod +x macos/monitor_switcher.sh switch.sh
```

See [macos/BUILD.md](macos/BUILD.md) for details.

### Step 2: Run Setup Wizard

```cmd
REM Windows
switch.bat setup

# macOS
./switch.sh setup
```

The wizard will automatically:
1. Blink each monitor's brightness to help you identify which is which
2. Query DDC/CI capability string (Windows) or probe standard input codes (macOS) to discover available inputs
3. Interactively name each input (e.g., `dp1`, `hdmi2`)
4. Ask which input corresponds to Windows and which to Mac
5. Write configuration to `config/monitors.json`

### Step 3: Usage

```cmd
REM Windows
switch.bat windows
switch.bat mac

# macOS
./switch.sh windows
./switch.sh mac
```

---

## Monitor Hub (Network Mode)

`monitor_hub` is an optional Python service that turns one machine into a central switching server. Other machines (agents) query it before switching, so VCP codes are managed in one place.

### Architecture

```
switch.bat / switch.sh
  │
  ├── [MONITOR_SERVER_URL set]  →  GET /api/switch?current=<my_ip>
  │     monitor_hub server returns { action: "switch", target: { vcp_code } }
  │     or { action: "choose", options: [...] } when multiple targets available
  │     Falls back to local config/monitors.json if server is unreachable
  │
  └── [no server URL]  →  local config/monitors.json  →  DDC/CI

monitor_hub (Flask, port 5000 server / 5001 agent)
  ├── server mode   — web UI + /api/switch, /api/sources, /api/identify, /api/settings
  ├── agent mode    — wraps monitor_switcher.exe/.sh; exposes /ddc/* HTTP endpoints
  └── both mode     — server + agent on the same machine

config/monitors.json        ← VCP values and profiles (standalone mode)
monitor_hub/config.json     ← monitor_hub mode and settings
monitor_hub/sources.json    ← registered machines (auto-created by server)
```

### Setup

**1. Copy and edit config:**

```bash
cp monitor_hub/config.example.json monitor_hub/config.json
# Edit config.json — choose mode: "server", "agent", or "both"
```

**2. Install Python dependencies:**

```bash
pip install flask
```

**3. Run:**

```bash
python -m monitor_hub
# or via PyInstaller bundle:
./monitor_hub        # macOS/Linux
monitor_hub.exe      # Windows
```

### Modes

#### `"both"` — Single machine (server + agent)

Best for a setup where one Windows PC has the monitors and also acts as the hub.

```json
{
  "mode": "both",
  "server": { "host": "0.0.0.0", "port": 5000 },
  "agent":  { "port": 5001, "name": "My Windows PC" }
}
```

#### `"server"` — Headless/Docker hub

A dedicated server (or NAS/Pi) with no monitors, only managing state.

```json
{
  "mode": "server",
  "host": "0.0.0.0",
  "port": 5000
}
```

#### `"agent"` — Machine with monitors, remote server

```json
{
  "mode": "agent",
  "port": 5001,
  "server_url": "http://192.168.1.50:5000",
  "name": "My Mac"
}
```

### Connecting switch.bat / switch.sh to the hub

Set the `MONITOR_SERVER_URL` environment variable before running the launcher:

```cmd
REM Windows — set permanently
setx MONITOR_SERVER_URL http://192.168.1.50:5000

REM or per-session
set MONITOR_SERVER_URL=http://192.168.1.50:5000
switch.bat
```

```bash
# macOS — add to ~/.zshrc or ~/.bash_profile
export MONITOR_SERVER_URL=http://192.168.1.50:5000
./switch.sh
```

When the variable is set, the launcher:
1. Detects its own LAN IP
2. Calls `GET /api/switch?current=<my_ip>`
3. Applies the returned VCP code to all local monitors
4. Falls back silently to local `config/monitors.json` if server is unreachable

### Web UI

Open `http://<server-ip>:5000` in a browser:

- **Add Source**: register a machine by name and IP
- **Identify**: cycle through candidate VCP codes on the remote agent until you confirm which input is correct — no manual VCP lookup needed
- **Settings**: configure `ask_on_multiple`, `default_target_id`, `identify_candidates`, `identify_dwell_ms`

### Build Standalone Executable (PyInstaller)

```bash
pip install pyinstaller flask
pyinstaller monitor_hub.spec
# output: dist/monitor_hub.exe (Windows) or dist/monitor_hub (macOS)
```

---

## Low-Level Commands

Direct DDC/CI operations for troubleshooting or manual adjustments:

```cmd
REM Windows
bin\monitor_switcher.exe detect
bin\monitor_switcher.exe getvcp 0 60
bin\monitor_switcher.exe setvcp 0 60 15
bin\monitor_switcher.exe capabilities 0
```

```bash
# macOS (depending on tool)
m1ddc display 1 get input
m1ddc display 1 set input 15
ddcctl -d 1
ddcctl -d 1 -i 15
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

Actual values vary by monitor manufacturer. Use values detected by the `setup` wizard or the Identify feature in Monitor Hub.

---

## Advanced Usage

### Create Desktop Shortcuts (Windows)

1. Right-click Desktop → New → Shortcut
2. Location: `C:\path\to\monitor-switcher\switch.bat mac`
3. Can set hotkey (Shortcut properties → Shortcut key field)

### Create Automator App (macOS)

1. Open Automator → New Application
2. Add "Run Shell Script"
3. Enter: `/path/to/switch.sh mac`
4. Save as "Switch to Mac.app" and drag to Dock

### Auto-run on Startup (Windows)

```cmd
schtasks /create /tn "SwitchToWindows" /tr "C:\path\to\switch.bat windows" /sc onlogon
```

### Auto-run on Startup (macOS LaunchAgent)

Create `~/Library/LaunchAgents/com.user.monitorswitcher.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.user.monitorswitcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/switch.sh</string>
        <string>mac</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
```

### Auto-start Monitor Hub (Windows Service / macOS LaunchAgent)

**Windows** — run at login via Task Scheduler:

```cmd
schtasks /create /tn "MonitorHub" /tr "C:\path\to\monitor_hub.exe" /sc onlogon /ru SYSTEM
```

**macOS** — run at login via LaunchAgent (same pattern as above, point to `monitor_hub` binary).

---

## Troubleshooting

### Windows

**"Failed to get the vcp code value"**
- Enable DDC/CI in monitor OSD menu
- Run as Administrator
- Update graphics driver

**Monitor not detected**
- Ensure monitor is powered on and connected
- Reseat cables
- Update graphics driver

**Compilation errors**
- Ensure Windows SDK is installed (includes `PhysicalMonitorEnumerationAPI.h`)
- Verify `Dxva2.lib` is linked
- See [windows/BUILD.md](windows/BUILD.md)

### macOS

**⚠️ Apple Silicon HDMI Limitation**

Apple Silicon Macs (M1/M2/M3/M4) **HDMI ports do not support DDC/CI at the hardware level**. Must connect monitors via **Thunderbolt/USB-C** for auto-switching to work.

If your monitor only has HDMI: use auto-switching on Windows side only, manually press monitor OSD buttons when on macOS.

**"ddcctl: command not found"**
```bash
brew install ddcctl    # Intel Mac
brew install m1ddc     # Apple Silicon
```

**DDC communication failure**
- Most common cause: monitor connected via HDMI to Apple Silicon Mac
- Solution: switch to USB-C/Thunderbolt connection

### Monitor Hub

**Agent can't reach server**
- Check `server_url` in `monitor_hub/config.json`
- Verify firewall allows port 5000/5001
- Check server is running: `curl http://<server-ip>:5000/`

**switch.bat / switch.sh ignores server**
- Confirm `MONITOR_SERVER_URL` env var is set in the same shell session
- The launcher falls back silently to local config if the server returns an error

**Identify wizard doesn't change monitor input**
- Agent must be running on the machine with the monitors
- Confirm agent `exe_path` points to a valid `monitor_switcher.exe`
- macOS: confirm `macos/monitor_switcher.sh` is executable

### General

**One monitor switches, the other doesn't**
- The two monitors may use different VCP values
- Re-run the `setup` wizard

**Monitor goes black for a few seconds after switching**
- Normal behavior, monitors need time to switch inputs

---

## Acknowledgments

- **Windows implementation**: Based on [DDC/CI Windows API](https://blog.csdn.net/sinat_26143945/article/details/135137436) example
- **macOS implementation**: Uses [ddcctl](https://github.com/kfix/ddcctl)
- **JSON library**: [nlohmann/json](https://github.com/nlohmann/json)

## License

- This project integration code: MIT License
- macOS ddcctl tool: GPL v3 License
