import json
import threading
from pathlib import Path

_lock = threading.Lock()
_SOURCES_PATH: Path | None = None


def init(sources_path: Path):
    global _SOURCES_PATH
    _SOURCES_PATH = sources_path
    if not _SOURCES_PATH.exists():
        _SOURCES_PATH.write_text(json.dumps({"sources": []}, indent=2))


def load_sources() -> dict:
    with _lock:
        return json.loads(_SOURCES_PATH.read_text())


def save_sources(data: dict):
    with _lock:
        _SOURCES_PATH.write_text(json.dumps(data, indent=2))
