# macOS Setup Instructions

## Install DDC Tools

### Apple Silicon (M1/M2/M3/M4)

```bash
brew install m1ddc
```

### Intel Mac

```bash
brew install ddcctl
```

> **⚠️ Apple Silicon HDMI Limitation**: Apple Silicon Macs have HDMI ports that do not support DDC/CI at the hardware level. Monitors must be connected via **Thunderbolt/USB-C** for auto-switching to work. Monitors connected via HDMI require manual OSD button switching.

---

## Make Scripts Executable

```bash
chmod +x macos/monitor_switcher.sh switch.sh
```

---

## Verify Installation

```bash
./switch.sh detect
```

Should display DDC/CI support status for each display.

---

## Optional Dependencies

### jq (JSON parsing, optional)

```bash
brew install jq
```

If jq is not installed, `load_config()` will fall back to `grep`/`sed` for parsing config files with identical functionality.

---

## Quick Launch Options

### Automator App

1. Open Automator → New "Application"
2. Add "Run Shell Script"
3. Enter: `/path/to/monitor-switcher/switch.sh mac`
4. Save as "Switch to Mac.app" and drag to Dock

### Hotkeys (BetterTouchTool / Karabiner-Elements)

Bind hotkey to execute shell script: `/path/to/switch.sh mac`

---

## Troubleshooting

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
