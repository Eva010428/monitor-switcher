# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Monitor Hub web UI source-card quick switch endpoint for direct source-to-source switching.
- Monitor Hub Identify flow now saves confirmed per-monitor VCP codes only after an explicit Save action.

### Changed
- Monitor Hub Settings now only exposes Identify candidates and dwell time.
- Add/Edit Source no longer accepts manual VCP code entry; VCP codes are managed through Identify.
- Monitor Hub now runs as one local web process without server/agent/both modes.
- macOS multi-monitor switching continues through later displays when one DDC set fails.

### Planned Features
- [ ] GUI system tray application
- [ ] Hotkey support
- [ ] Linux support (ddcutil)
- [ ] Support for more VCP features (bulk brightness/contrast adjustment)

---

## [1.1.0] - 2026-04-17

### Added
- **setup wizard**: Interactive auto-configuration, replacing manual VCP code detection workflow
  - Blinks brightness (VCP 0x10) to identify each physical monitor
  - Windows: Parses DDC/CI capabilities string, auto-extracts supported VCP 0x60 values
  - macOS: Probes standard input code list, records accepted codes
  - Interactive naming of inputs (dp1, hdmi2, etc.), assigns Windows/Mac profiles
  - Auto-writes config/monitors.json
- autodetect command as alias for setup
- Windows: loadConfig() now actually reads config/monitors.json (json.hpp enabled)
- macOS: load_config() removed hardcoded fallback, gives clear message when config file absent
- macOS: switch_profile() dynamically detects displays 1-4, no longer hardcoded to two

### Changed
- Windows loadConfig(): Uses GetModuleFileNameA() to locate config file, independent of working directory
- macOS load_config(): Falls back to grep/sed parsing when jq unavailable (fixed format, reliable)

---

## [1.0.0] - 2026-03-01

### Added
- Initial release
- Windows C++ implementation (DDC/CI, Windows Monitor API)
- macOS Shell wrapper (ddcctl / m1ddc)
- JSON configuration file system
- High-level commands: switch windows, switch mac
- Low-level commands: detect, getvcp, setvcp, capabilities
- Retry mechanism (up to 3 attempts, 500ms interval)
- Cross-platform launch scripts (switch.bat / switch.sh)

---

| Version | Date | Main Changes |
|---------|------|--------------|
| 1.1.0 | 2026-04-17 | Setup wizard, enabled JSON reading |
| 1.0.0 | 2026-03-01 | Initial release, dual-platform support |
