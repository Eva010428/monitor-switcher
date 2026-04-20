# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Monitor Switcher switches dual monitor inputs between DisplayPort and HDMI using DDC/CI. Designed for dual-boot (Windows + macOS) or KVM setups where monitors are shared across systems.

Optionally, `monitor_hub` provides a network hub (Flask server + agent) so VCP codes are managed centrally and machines query the server before switching.

## Build Commands

### Windows (C++)

```cmd
# Visual Studio
cd windows
cl /EHsc /MT /O2 /std:c++17 monitor_switcher.cpp /link Dxva2.lib Gdi32.lib User32.lib /OUT:../bin/monitor_switcher.exe

# MinGW
cd windows
mingw32-make
```

Output: `bin/monitor_switcher.exe`

### macOS

No compilation needed. Shell scripts are the implementation.

```bash
chmod +x macos/monitor_switcher.sh switch.sh
```

### monitor_hub (Python, optional)

```bash
pip install flask pyinstaller
pyinstaller monitor_hub.spec
# output: dist/monitor_hub(.exe)
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

# monitor_hub
python -m monitor_hub                        # run from source
dist/monitor_hub.exe                         # run bundled (Windows)
dist/monitor_hub                             # run bundled (macOS)
```

## Architecture

```
switch.bat / switch.sh          ← thin launchers, forward args to core
    │
    ├── [MONITOR_SERVER_URL set]
    │       GET /api/switch?current=<my_ip>  →  monitor_hub server
    │       Returns { action: "switch", target: { vcp_code } }
    │          or  { action: "choose", options: [...] }
    │       Falls back to local config on network error
    │
    └── [local fallback]
            windows/monitor_switcher.cpp  ← C++, Windows Monitor APIs + DDC/CI
            macos/monitor_switcher.sh     ← Bash, wraps ddcctl / m1ddc

monitor_hub/                    ← Python Flask network hub (optional)
    ├── __main__.py             ← entry point; reads config.json, dispatches mode
    ├── server/
    │   ├── app.py              ← Flask app factory; background agent health-ping loop
    │   ├── sources.py          ← /api/sources CRUD (sources.json persistence)
    │   ├── switch.py           ← GET /api/switch?current=<ip|name>
    │   ├── identify.py         ← /api/identify/* — cycles VCP codes on remote agent
    │   └── settings.py         ← GET|PUT /api/settings
    ├── agent/
    │   ├── app.py              ← Flask app; /health, /ddc/detect, /ddc/getvcp,
    │   │                          /ddc/setvcp, /ddc/setvcp_all
    │   ├── ddc.py              ← wraps monitor_switcher.exe / monitor_switcher.sh
    │   └── register.py         ← POST /api/sources on startup to self-register
    ├── templates/index.html    ← web UI (sources grid, identify modal, settings modal)
    ├── static/                 ← app.js, style.css
    ├── config.example.json     ← template; copy to config.json
    └── requirements.txt        ← flask>=3.0

config/monitors.json            ← VCP values and profiles (standalone mode)
monitor_hub/config.json         ← monitor_hub mode, ports, server URL (not committed)
monitor_hub/sources.json        ← registered machines (auto-created at runtime)
```

**Configuration** (`config/monitors.json`):
- `vcp_code`: DDC/CI feature code for input source (always `0x60`)
- `inputs`: mapping of human names (`dp1`, `hdmi2`) to integer VCP values
- `profiles`: mapping of profile names (`windows`, `mac`) to input names

**monitor_hub modes**:
- `server` (port 5000): web UI + REST API, manages sources.json, no DDC access
- `agent` (port 5001): wraps monitor_switcher binary, exposes /ddc/* HTTP endpoints
- `both`: server + agent on same machine (server in daemon thread, agent in main thread)

**Retry logic**: 3 attempts with 500 ms delay, present in both C++ and shell implementations.

**Setup wizard** (`setup` / `autodetect` command): blinks brightness (VCP 0x10) to identify monitors, parses capabilities string (Windows) or probes standard code list (macOS) to discover valid VCP 0x60 values, interactively names inputs and assigns profiles, writes `config/monitors.json`. Both `loadConfig()` (Windows) and `load_config()` (macOS) now read from the file; fallback to hardcoded defaults only if file is absent.

**Identify feature** (monitor_hub): server sends setvcp_all commands to a remote agent, cycling through candidate VCP codes (default: 15,16,17,18,19,3,4,27) at a configurable dwell interval. User clicks "This is it!" in the web UI to confirm and persist the vcp_code.

**Apple Silicon limitation**: HDMI ports on M1/M2/M3/M4 Macs do not support DDC/CI. Must connect monitors via Thunderbolt/USB-C.

## Git Commit Convention

All commits must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope]: <description>
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`

Examples:
- `feat(windows): add skip option in setup wizard`
- `fix(macos): restore input after probe timeout`
- `chore: update .gitignore`
