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
_EXPOSED_KEYS = {"ask_on_multiple", "default_target_id", "identify_candidates", "identify_dwell_ms", "mode"}


def _project_root() -> Path:
    return Path(__file__).parent.parent.parent


def _relaunch_deferred() -> None:
    time.sleep(1.5)
    root = str(_project_root())
    if sys.platform == "win32":
        subprocess.Popen(
            ["pythonw", "-m", "monitor_hub"],
            cwd=root,
            creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NO_WINDOW,
        )
    else:
        subprocess.Popen(
            ["python3", "-m", "monitor_hub"],
            cwd=root,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    os._exit(0)


def init(server_config: dict, config_path):
    global _config, _config_path
    _config = server_config
    _config_path = config_path


def _public(cfg: dict) -> dict:
    return {k: cfg[k] for k in _EXPOSED_KEYS if k in cfg}


@bp.get("/api/settings")
def get_settings():
    return jsonify(_public(_config))


@bp.put("/api/settings")
def update_settings():
    import json
    body = request.get_json(force=True, silent=True) or {}
    old_mode = _config.get("mode", "local")
    for key in _EXPOSED_KEYS:
        if key in body:
            _config[key] = body[key]
    new_mode = _config.get("mode", "local")

    if _config_path:
        _config_path.write_text(json.dumps(_config, indent=2))

    relaunch = new_mode != old_mode
    if relaunch:
        threading.Thread(target=_relaunch_deferred, daemon=True).start()

    result = _public(_config)
    result["relaunch"] = relaunch
    return jsonify(result)
