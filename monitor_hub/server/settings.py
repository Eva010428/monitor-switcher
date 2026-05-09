import os
import subprocess
import sys
import threading
import time
from pathlib import Path
from flask import Blueprint, jsonify, request

bp = Blueprint("settings", __name__)

_config: dict = {}
_config_path = None
_EXPOSED_KEYS = {"ask_on_multiple", "default_target_id", "identify_candidates", "identify_dwell_ms"}


def init(server_config: dict, config_path):
    global _config, _config_path
    _config = server_config
    _config_path = config_path


def _public(cfg: dict) -> dict:
    return {k: cfg[k] for k in _EXPOSED_KEYS if k in cfg}


def _project_root() -> Path:
    return Path(__file__).parent.parent.parent


def _spawn_tray() -> None:
    time.sleep(1.0)
    root = str(_project_root())
    if sys.platform == "win32":
        subprocess.Popen(
            ["pythonw", "-m", "monitor_hub", "--tray"],
            cwd=root,
            stdin=subprocess.DEVNULL,
            creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NO_WINDOW,
        )
    else:
        subprocess.Popen(
            ["python3", "-m", "monitor_hub", "--tray"],
            cwd=root,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    os._exit(0)


@bp.get("/api/settings")
def get_settings():
    result = _public(_config)
    result["tray_active"] = "--tray" in sys.argv
    return jsonify(result)


@bp.put("/api/settings")
def update_settings():
    import json
    body = request.get_json(force=True, silent=True) or {}
    for key in _EXPOSED_KEYS:
        if key in body:
            _config[key] = body[key]

    if _config_path:
        _config_path.write_text(json.dumps(_config, indent=2))

    return jsonify(_public(_config))


@bp.post("/api/system/enable-tray")
def enable_tray():
    threading.Thread(target=_spawn_tray, daemon=True).start()
    return jsonify({"ok": True})


@bp.post("/api/system/quit")
def quit_server():
    def _exit():
        time.sleep(0.5)
        os._exit(0)
    threading.Thread(target=_exit, daemon=True).start()
    return jsonify({"ok": True})
