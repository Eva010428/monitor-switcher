import json
import os
import platform
from pathlib import Path


APP_DIR_NAME = "MonitorSwitcher"

DEFAULT_CONFIG = {
    "mode": "local",
    "host": "0.0.0.0",
    "port": 5000,
    "exe_path": "bin/monitor_switcher.exe",
    "identify_candidates": [15, 16, 17, 18, 19, 3, 4, 27],
    "identify_dwell_ms": 3000,
}


def user_data_dir() -> Path:
    system = platform.system()
    if system == "Windows":
        base = os.environ.get("APPDATA")
        if base:
            return Path(base) / APP_DIR_NAME
        return Path.home() / "AppData" / "Roaming" / APP_DIR_NAME
    if system == "Darwin":
        return Path.home() / "Library" / "Application Support" / APP_DIR_NAME
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / APP_DIR_NAME


def ensure_user_data_dir() -> Path:
    path = user_data_dir()
    path.mkdir(parents=True, exist_ok=True)
    return path


def config_path() -> Path:
    return ensure_user_data_dir() / "config.json"


def sources_path() -> Path:
    return ensure_user_data_dir() / "sources.json"


def logs_dir() -> Path:
    path = ensure_user_data_dir() / "logs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def ensure_default_config() -> Path:
    path = config_path()
    if not path.exists():
        path.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n")
    return path
