# Quick Start Guide

---

## Mode A — Standalone (no server needed)

### Step 1: Build / Install Tools

#### Windows

Open **Developer Command Prompt for VS** and run:

```cmd
cd path\to\monitor-switcher\windows
cl /EHsc /MT /O2 /std:c++17 monitor_switcher.cpp /link Dxva2.lib Gdi32.lib User32.lib /OUT:..\bin\monitor_switcher.exe
```

Or using MinGW:

```cmd
cd windows
mingw32-make
copy monitor_switcher.exe ..\bin\
```

#### macOS

```bash
brew install m1ddc     # Apple Silicon
# or
brew install ddcctl    # Intel Mac

chmod +x macos/monitor_switcher.sh switch.sh
```

---

### Step 2: Run Setup Wizard

```cmd
REM Windows
switch.bat setup

# macOS
./switch.sh setup
```

The wizard will guide you through:

1. **Identify monitors**: Each monitor blinks brightness in sequence to help you identify "left" or "right"
2. **Detect input codes**: Auto-query monitor's DDC/CI input codes
3. **Name inputs**: Give each code a short name (e.g., dp1, hdmi2)
4. **Assign profiles**: Tell the wizard which input is Windows and which is Mac
5. **Write config**: Auto-generate `config/monitors.json`

---

### Step 3: Start Using

```cmd
REM Windows
switch.bat mac       <- Switch monitors to Mac input
switch.bat windows   <- Switch monitors to Windows input

# macOS
./switch.sh mac
./switch.sh windows
```

---

## Mode B — Network Hub (monitor_hub)

Use this when you want a central server to manage VCP codes across multiple machines.

### Step 1: Configure

```bash
cp monitor_hub/config.example.json monitor_hub/config.json
```

Edit `config.json`:

```json
{
  "host": "0.0.0.0",
  "port": 5000,
  "identify_candidates": [15, 16, 17, 18, 19, 3, 4, 27],
  "identify_dwell_ms": 3000
}
```

### Step 2: Start Monitor Hub

```bash
pip install flask
python -m monitor_hub
```

Or run the pre-built executable:

```cmd
monitor_hub.exe          # Windows
./monitor_hub            # macOS
```

### Step 3: Open Web UI

Go to `http://localhost:5000` and:

1. Click **+ Add Source** for each machine
2. Click **Identify** next to a source
3. For each monitor, click a candidate VCP code to test it; the monitor will briefly switch and then restore
4. Click **Save VCP** only when the test stayed on the expected source, then click **Confirm**
5. Repeat for each machine

### Step 4: Connect Launchers to the Hub

**Windows** — set environment variable:
```cmd
setx MONITOR_SERVER_URL http://192.168.1.50:5000
```

**macOS** — add to `~/.zshrc`:
```bash
export MONITOR_SERVER_URL=http://192.168.1.50:5000
```

Now `switch.bat` / `switch.sh` will automatically query the hub. If the server is unreachable, they fall back to local `config/monitors.json`.

---

## Common Issues

**"Failed to get the vcp code value"**
→ Enable DDC/CI in monitor OSD menu

**macOS: Nothing happens during wizard blinking**
→ Monitor may be connected via HDMI to Apple Silicon Mac (hardware doesn't support DDC/CI)
→ Must use USB-C/Thunderbolt connection

**Only one monitor responds**
→ Other monitor may not support DDC/CI or uses different input codes
→ Re-run setup wizard

**"ddcctl: command not found"**
→ `brew install ddcctl` (Intel) or `brew install m1ddc` (Apple Silicon)

**Monitor Hub: switch.bat ignores server**
→ Check that `MONITOR_SERVER_URL` is set (`echo %MONITOR_SERVER_URL%` on Windows)
→ The launcher silently falls back to local config if the server returns an error

---

For full documentation, see [README.md](README.md).
