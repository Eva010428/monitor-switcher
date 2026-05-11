# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] - 2026-05-12

**Breaking change**: Monitor Hub is now the primary interface. The standalone C++/Shell binary workflow is moved to `legacy/`.

### Added
- Native Python DDC/CI: `monitorcontrol` library on Windows; `m1ddc` subprocess on macOS — no binary compilation required
- System tray mode (`python -m monitor_hub --tray`) via `pystray` + `Pillow`
- Per-monitor VCP codes (`vcp_codes` map) — each monitor can have a different input code
- Source card quick-switch buttons for direct source-to-source switching
- Identify flow saves confirmed per-monitor VCP codes after explicit Save action
- `runtime_paths.py` — centralised path resolution for config and sources files
- `logging_setup.py` — unified logging configuration
- `net.py` — host binding helper
- Unit tests: `tests/test_config_and_settings.py`, `tests/test_ddc_windows.py`, `tests/test_sources_and_switch.py`

### Changed
- Monitor Hub runs as a single local process — `server`/`agent`/`both` mode split removed
- `__main__.py` simplified: default starts web server; `--tray` flag starts tray mode
- `ddc.py` rewritten: platform-dispatch at module level, no subprocess to external binaries
- Settings UI exposes only `identify_candidates` and `identify_dwell_ms`
- Add/Edit Source no longer accepts manual VCP code entry; VCP codes are managed via Identify
- Sources are local profiles; IP address field removed
- `config.example.json` trimmed to four keys: `host`, `port`, `identify_candidates`, `identify_dwell_ms`
- Identify probe falls back to source's saved VCP codes when DDC readback is unsupported
- Process-control endpoints (`/api/system/quit`, `/api/system/enable-tray`) restricted to localhost

### Removed
- `monitor_hub/agent/app.py` — agent HTTP layer replaced by direct DDC calls
- `monitor_hub/agent/register.py` — self-registration removed with agent layer
- `monitor_hub.spec` — PyInstaller spec removed
- `run.py` — replaced by `python -m monitor_hub`
- `switch.bat`, `switch.sh`, `windows/`, `macos/` — moved to `legacy/`

---

## [1.1.0] - 2026-04-17

### Added
- **Setup wizard**: Interactive auto-configuration
  - Blinks brightness (VCP 0x10) to identify each physical monitor
  - Windows: Parses DDC/CI capabilities string, auto-extracts VCP 0x60 values
  - macOS: Probes standard input code list
  - Interactive input naming and profile assignment
  - Auto-writes `config/monitors.json`
- `autodetect` command as alias for `setup`
- Windows: `loadConfig()` reads `config/monitors.json` via `json.hpp`
- macOS: `load_config()` removed hardcoded fallback, clear error when config absent
- macOS: `switch_profile()` dynamically detects displays 1–4

### Changed
- Windows `loadConfig()`: uses `GetModuleFileNameA()` to locate config independent of working directory
- macOS `load_config()`: grep/sed fallback when `jq` unavailable

---

## [1.0.0] - 2026-03-01

### Added
- Initial release
- Windows C++ implementation (DDC/CI via Windows Monitor API)
- macOS Shell wrapper (`ddcctl` / `m1ddc`)
- JSON configuration file system
- High-level commands: `switch windows`, `switch mac`
- Low-level commands: `detect`, `getvcp`, `setvcp`, `capabilities`
- Retry mechanism (up to 3 attempts, 500 ms interval)
- Cross-platform launch scripts (`switch.bat` / `switch.sh`)

---

| Version | Date | Main Changes |
|---------|------|--------------|
| 2.0.0 | 2026-05-12 | Local-mode Monitor Hub, native Python DDC, tray mode |
| 1.1.0 | 2026-04-17 | Setup wizard, JSON config reading |
| 1.0.0 | 2026-03-01 | Initial release |
