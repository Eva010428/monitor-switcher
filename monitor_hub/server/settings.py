import os
import subprocess
import sys
import threading
import time
import logging
from pathlib import Path
from flask import Blueprint, abort, jsonify, request

bp = Blueprint("settings", __name__)
logger = logging.getLogger(__name__)

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


def _tray_command() -> list[str]:
    if getattr(sys, "frozen", False):
        return [sys.executable, "--tray"]
    return [sys.executable, "-m", "monitor_hub", "--tray"]


def _spawn_tray() -> None:
    time.sleep(1.0)
    root = str(_project_root())
    kwargs = {
        "cwd": root,
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
    }
    if sys.platform == "win32":
        kwargs["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NO_WINDOW
    else:
        kwargs["start_new_session"] = True
    try:
        subprocess.Popen(_tray_command(), **kwargs)
    except Exception:
        logger.exception("Failed to spawn tray process")
        return
    os._exit(0)


def _is_local_request() -> bool:
    return request.remote_addr in {"127.0.0.1", "::1", "localhost"}


def _require_local_request() -> None:
    if not _is_local_request():
        abort(403)


@bp.get("/api/settings")
def get_settings():
    result = _public(_config)
    result["tray_active"] = "--tray" in sys.argv
    result["local_request"] = _is_local_request()
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
    _require_local_request()
    threading.Thread(target=_spawn_tray, daemon=True).start()
    return jsonify({"ok": True})


@bp.post("/api/system/quit")
def quit_server():
    _require_local_request()

    def _exit():
        time.sleep(0.5)
        os._exit(0)
    threading.Thread(target=_exit, daemon=True).start()
    return jsonify({"ok": True})
