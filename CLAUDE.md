# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Monitor Switcher switches dual monitor inputs between DisplayPort and HDMI using DDC/CI. Designed for dual-boot (Windows + macOS) or KVM setups where monitors are shared across systems.

## Build Commands

### Windows (C++)

```cmd
# Visual Studio
cd windows
cl /EHsc /MT /O2 /std:c++17 monitor_switcher.cpp /link Dxva2.lib Gdi32.lib User32.lib /OUT:../bin/monitor_switcher.exe

# MinGW
cd windows && mingw32-make
```

Output lands in `bin/monitor_switcher.exe`.

### macOS

No compilation needed. Shell scripts are the implementation.

```bash
chmod +x macos/monitor_switcher.sh switch.sh
```

## Running

```bash
# Windows
switch.bat setup           # run interactive setup wizard (first-time)
switch.bat detect          # enumerate connected monitors
switch.bat mac             # switch all monitors to Mac profile
switch.bat windows         # switch all monitors to Windows profile

# macOS
./switch.sh setup
./switch.sh detect
./switch.sh mac
./switch.sh windows

# Low-level debug (Windows)
bin\monitor_switcher.exe getvcp 0 60        # read VCP 0x60 on monitor 0
bin\monitor_switcher.exe setvcp 0 60 18     # set monitor 0 to input 18
bin\monitor_switcher.exe capabilities 0     # query monitor's full capability string
```

## Architecture

```
switch.bat / switch.sh          ← thin launchers, forward args to core
    │
    ├── windows/monitor_switcher.cpp  ← C++, Windows Monitor APIs + DDC/CI
    │       PhysicalMonitorEnumerationAPI → EnumDisplayMonitors
    │       LowLevelMonitorConfigurationAPI → GetVCPFeatureAndVCPFeatureReply / SetVCPFeature
    │       Dxva2.lib for DDC/CI transport
    │
    └── macos/monitor_switcher.sh     ← Bash, wraps ddcctl / m1ddc
            Auto-detects tool (ddcctl for Intel, m1ddc for Apple Silicon)

config/monitors.json            ← all VCP values and profiles live here
```

**Configuration** (`config/monitors.json`):
- `vcp_code`: DDC/CI feature code for input source (always `0x60`)
- `inputs`: mapping of human names (`dp1`, `hdmi2`) to integer VCP values
- `profiles`: mapping of profile names (`windows`, `mac`) to input names

**Retry logic**: 3 attempts with 500 ms delay, present in both implementations.

**Setup wizard** (`setup` / `autodetect` command): blinks brightness (VCP 0x10) to identify monitors, parses capabilities string (Windows) or probes standard code list (macOS) to discover valid VCP 0x60 values, interactively names inputs and assigns profiles, writes `config/monitors.json`. Both `loadConfig()` (Windows) and `load_config()` (macOS) now read from the file; fallback to hardcoded defaults only if file is absent.

**Apple Silicon limitation**: HDMI ports on M1/M2/M3/M4 Macs do not support DDC/CI. Must connect monitors via Thunderbolt/USB-C.
