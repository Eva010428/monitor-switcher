from flask import Blueprint, jsonify, request

bp = Blueprint("settings", __name__)

_config: dict = {}
_config_path = None
_EXPOSED_KEYS = {"ask_on_multiple", "default_target_id", "identify_candidates", "identify_dwell_ms", "mode"}


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
    for key in _EXPOSED_KEYS:
        if key in body:
            _config[key] = body[key]

    # Persist entire config (including non-exposed keys)
    if _config_path:
        import json as _json
        _config_path.write_text(_json.dumps(_config, indent=2))

    return jsonify(_public(_config))
