# Monitor Switcher

Cross-platform tool for switching dual monitor inputs via DDC/CI. Controls monitor input switching between DisplayPort and HDMI, designed for dual-boot (Windows + macOS) or KVM setups where monitors are shared across systems.

---

## Features

- **Cross-platform**: Windows (C++) and macOS (Shell + m1ddc/ddcctl)
- **One-click switching**: Switch all monitors simultaneously
- **Auto-setup wizard**: Auto-detect input codes, blink brightness to identify monitors, interactive configuration generation
- **JSON configuration**: Easily editable config file after setup
- **Portable**: No installation required, single executable approach

## Use Cases

- **Dual-boot systems**: Windows and Mac sharing the same displays, auto-switch inputs when booting
- **KVM companion**: KVM switches keyboard/mouse, this tool switches monitor inputs
- **Workstation switching**: Quick transition between work and personal computers

---

## Quick Start

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

Actual values vary by monitor manufacturer. Use values detected by the `setup` wizard.

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
