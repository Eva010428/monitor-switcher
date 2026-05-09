import json
from pathlib import Path


DEFAULT_CONFIG = {
    "host": "0.0.0.0",
    "port": 5000,
    "identify_candidates": [15, 16, 17, 18, 19, 3, 4, 27],
    "identify_dwell_ms": 3000,
}

# All runtime data lives inside the monitor_hub package directory
_DATA_DIR = Path(__file__).parent


def config_path() -> Path:
    return _DATA_DIR / "config.json"


def sources_path() -> Path:
    return _DATA_DIR / "sources.json"


def logs_dir() -> Path:
    path = _DATA_DIR / "logs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def ensure_default_config() -> Path:
    path = config_path()
    if not path.exists():
        path.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n")
    return path
