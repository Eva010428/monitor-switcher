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
    │       Falls back to local config on network error (5s timeout)
    │
    └── [local fallback]
            windows/monitor_switcher.cpp  ← C++, Windows Monitor APIs + DDC/CI
            macos/monitor_switcher.sh     ← Bash, wraps ddcctl / m1ddc

monitor_hub/                    ← Python Flask network hub (optional)
    ├── __main__.py             ← entry point; reads config.json, dispatches mode
    ├── server/
    │   ├── app.py              ← Flask app factory; background agent health-ping loop
    │   ├── sources.py          ← /api/sources CRUD (sources.json persistence)
    │   ├── execute_switch.py   ← web UI source-card switch endpoint
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
- `profiles`: per-monitor input mapping — `{ "windows": { "0": "dp1", "1": "hdmi2" } }`

**Config file resolution by mode**:
- Standalone: `config/monitors.json` relative to the launcher (`switch.bat` / `switch.sh`)
- monitor_hub agent: `bin/monitor_switcher.exe` is resolved relative to project root; when bundled via PyInstaller `sys._MEIPASS` is used as root
- `monitor_hub/sources.json` is auto-created at first agent registration

**monitor_hub modes**:
- `server` (port 5000): web UI + REST API, manages sources.json, no DDC access
- `agent` (port 5001): wraps monitor_switcher binary, exposes /ddc/* HTTP endpoints
- `both`: server starts in daemon thread (port 5000) first with 1.5 s head-start, agent runs in main thread (port 5001); if DDC unavailable silently downgrades to server-only

**Per-monitor VCP codes** (sources data model):
- Legacy: `"vcp_code": 15` — single code applied to all monitors
- New: `"vcp_codes": {"0": 15, "1": 17}` — per-monitor mapping (index → VCP value)
- `/api/switch` response always includes both fields for backward compatibility

**Server-aware switch API response format**:
```json
{ "action": "switch", "target": { "id": "…", "name": "…", "vcp_code": 15, "vcp_codes": {"0": 15} } }
{ "action": "choose", "options": [ {…}, {…} ] }
```
`switch.bat` / `switch.sh` parse this with inline Python (no `jq` dependency); fall back to local config on any network error.

**Identify feature** (monitor_hub): interactive VCP discovery workflow:
1. Server starts session (`POST /api/identify/<agent_id>/start`), saves current VCP values
2. Client probes candidate codes one by one (`POST /api/identify/<session_id>/probe`) — each probe sets the code for `identify_dwell_ms` then restores the original
3. User saves only successful probes in the web UI, then confirms (`POST /api/identify/<session_id>/confirm`) → persists to `sources.json`
4. Session state machine: `idle → probing → idle` (also `error` / `confirmed` / `cancelled`); `probe_lock` prevents concurrent probes

**Web UI quick switch**: `POST /api/sources/<source_id>/switch` asks the source agent to switch its local monitors to the target source's saved VCP codes. Per-monitor codes are applied by detected monitor order so Windows `0,1` and macOS `1,2,...` IDs do not have to match.

**Agent registration**: on startup agent POSTs to `/api/sources`; detects own IP via socket connection to server URL (`_local_ip()`). Duplicate IPs and duplicate names are handled gracefully; names are unique so `both` mode does not add a duplicate localhost source when a named source already exists.

**Health pings**: server background thread pings all agents every 30 s (3 s timeout); status is in-memory only, not persisted to `sources.json`.

**Retry logic**: identify restore retries 5 times with 400 ms delay. Agent registration retries 5 times with 3 s delays. DDC subprocess timeout is 10 s.

**Setup wizard** (`setup` / `autodetect` command): blinks brightness (VCP 0x10) to identify monitors, parses capabilities string (Windows) or probes standard code list (macOS) to discover valid VCP 0x60 values, interactively names inputs and assigns profiles, writes `config/monitors.json`. Both `loadConfig()` (Windows) and `load_config()` (macOS) read from the file; fallback to hardcoded defaults only if file is absent.

**macOS DDC tool chain**: tries `m1ddc` (Apple Silicon, `brew install m1ddc`) → falls back to `ddcctl` (Intel, `brew install ddcctl`) → exits with error. JSON parsing tries `jq` if available, else grep/sed fallback.

**Apple Silicon limitation**: HDMI ports on M1/M2/M3/M4 Macs do not support DDC/CI. Must connect monitors via Thunderbolt/USB-C.

## Git Commit Convention

All commits must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`

Use `!` after the type/scope or a `BREAKING CHANGE:` footer for breaking changes.

Examples:
- `feat(windows): add skip option in setup wizard`
- `fix(macos): restore input after probe timeout`
- `chore: update .gitignore`
