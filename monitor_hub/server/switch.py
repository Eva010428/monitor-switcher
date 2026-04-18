from flask import Blueprint, jsonify, request
from . import load_sources

bp = Blueprint("switch", __name__)
_config: dict = {}


def init(server_config: dict):
    global _config
    _config = server_config


def _find_source(current: str, sources: list[dict]) -> dict | None:
    for s in sources:
        if s["ip"] == current:
            return s
    lower = current.lower()
    for s in sources:
        if s["name"].lower() == lower:
            return s
    return None


@bp.get("/api/switch")
def switch():
    current = (request.args.get("current") or "").strip()
    if not current:
        return jsonify({"error": "current param required"}), 400

    data = load_sources()
    sources = data["sources"]

    caller = _find_source(current, sources)
    if not caller:
        return jsonify({
            "error": "source not found",
            "hint": "register this machine on the server UI or check your IP/name",
        }), 404

    others = [s for s in sources if s["id"] != caller["id"]]
    if not others:
        return jsonify({"error": "no other sources configured"}), 409

    if len(others) == 1:
        target = others[0]
        if target.get("vcp_code") is None:
            return jsonify({
                "error": "target vcp_code not configured",
                "hint": "use the Identify feature on the server UI",
                "target_name": target["name"],
            }), 409
        return jsonify({"action": "switch", "target": _source_summary(target)})

    # Multiple targets
    if _config.get("ask_on_multiple", True):
        valid = [s for s in others if s.get("vcp_code") is not None]
        if not valid:
            return jsonify({"error": "no targets have vcp_code configured"}), 409
        return jsonify({"action": "choose", "options": [_source_summary(s) for s in valid]})
    else:
        default_id = _config.get("default_target_id")
        target = next((s for s in others if s["id"] == default_id), None)
        if not target:
            target = next((s for s in others if s.get("vcp_code") is not None), None)
        if not target:
            return jsonify({"error": "no valid target found"}), 409
        if target.get("vcp_code") is None:
            return jsonify({"error": "default target has no vcp_code configured"}), 409
        return jsonify({"action": "switch", "target": _source_summary(target)})


def _source_summary(s: dict) -> dict:
    d = {"id": s["id"], "name": s["name"]}
    if "vcp_codes" in s:
        d["vcp_codes"] = s["vcp_codes"]
    # Always include vcp_code for backwards compatibility with switch.bat/sh
    d["vcp_code"] = s.get("vcp_code")
    return d
