# macOS Setup Instructions

---

## Part 1 — monitor_switcher.sh (DDC/CI shell script)

### Install DDC Tools

#### Apple Silicon (M1/M2/M3/M4)

```bash
brew install m1ddc
```

#### Intel Mac

```bash
brew install ddcctl
```

> **⚠️ Apple Silicon HDMI Limitation**: Apple Silicon Macs have HDMI ports that do not support DDC/CI at the hardware level. Monitors must be connected via **Thunderbolt/USB-C** for auto-switching to work. Monitors connected via HDMI require manual OSD button switching.

---

### Make Scripts Executable

```bash
chmod +x macos/monitor_switcher.sh switch.sh
```

---

### Verify Installation

```bash
./switch.sh detect
```

Should display DDC/CI support status for each display.

---

### Optional Dependencies

#### jq (JSON parsing, optional)

```bash
brew install jq
```

If jq is not installed, `load_config()` will fall back to `grep`/`sed` for parsing config files with identical functionality.

---

### Quick Launch Options

#### Automator App

1. Open Automator → New "Application"
2. Add "Run Shell Script"
3. Enter: `/path/to/monitor-switcher/switch.sh mac`
4. Save as "Switch to Mac.app" and drag to Dock

#### Hotkeys (BetterTouchTool / Karabiner-Elements)

Bind hotkey to execute shell script: `/path/to/switch.sh mac`

---

### Troubleshooting

**"ddcctl: command not found"**
```bash
brew reinstall ddcctl
```

**DDC communication failure**
- Most common cause: monitor connected via HDMI to Apple Silicon Mac
- Run `m1ddc display list detailed` to verify connection type
- Switch to USB-C/Thunderbolt connection

**Monitor not responding**
- Verify DDC/CI is enabled in monitor OSD menu
- Ensure cable supports DDC/CI (cheap cables may not)
- Re-run `./switch.sh setup` to auto-detect correct input codes

**Terminal permission issues**
- System Preferences → Privacy → Accessibility → Allow Terminal

---

## Part 2 — monitor_hub (Python Flask hub, optional)

`monitor_hub` is the optional network hub service. Build it into a standalone binary with PyInstaller so Python is not required on the target machine.

### Requirements

- Python 3.11+
- pip

```bash
pip install flask pyinstaller
```

### Build

From the project root:

```bash
pyinstaller monitor_hub.spec
```

Output: `dist/monitor_hub`

The binary is self-contained — it bundles Flask, Jinja2, the web UI templates, and static files.

### Run

```bash
# Copy config and edit mode/ports
cp monitor_hub/config.example.json monitor_hub/config.json
nano monitor_hub/config.json

# Start hub (reads config.json from same directory as binary when bundled)
./dist/monitor_hub
```

Or copy `monitor_hub` next to `config.json` anywhere and run it directly.

### Verify

```bash
curl http://localhost:5000/
```

Should return the web UI HTML.

### Auto-start via LaunchAgent

Create `~/Library/LaunchAgents/com.user.monitorhub.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.user.monitorhub</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/monitor_hub</string>
    </array>
    <key>WorkingDirectory</key><string>/path/to/monitor-switcher</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.user.monitorhub.plist
```
