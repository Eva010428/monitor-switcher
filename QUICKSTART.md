# Quick Start Guide

## 5-Minute Setup

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
5. **Write config**: Auto-generate config/monitors.json

---

### Step 3: Start Using

```cmd
REM Windows
switch.bat mac       <- Switch to Mac
switch.bat windows   <- Switch to Windows

# macOS
./switch.sh mac
./switch.sh windows
```

---

## Common Issues

**"Failed to get the vcp code value"**
-> Enable DDC/CI in monitor OSD menu

**macOS: Nothing happens during wizard blinking**
-> Monitor may be connected via HDMI to Apple Silicon Mac (hardware doesn't support DDC/CI)
-> Must use USB-C/Thunderbolt connection

**Only one monitor responds**
-> Other monitor may not support DDC/CI or uses different input codes
-> Re-run setup wizard

**"ddcctl: command not found"**
-> brew install ddcctl (Intel) or brew install m1ddc (Apple Silicon)

---

For more details, see [README.md](README.md).
