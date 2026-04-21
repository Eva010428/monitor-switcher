import json
import urllib.error
import urllib.request

from flask import Blueprint, jsonify, request

from . import load_sources
from .sources import get_status

bp = Blueprint("execute_switch", __name__)


def _agent_post(base_url, path, body, timeout=10):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{base_url}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


@bp.post("/api/sources/<source_id>/switch")
def execute_switch(source_id):
    body = request.get_json(force=True, silent=True) or {}
    target_id = (body.get("target_source_id") or "").strip()
    if not target_id:
        return jsonify({"error": "target_source_id required"}), 400

    all_sources = load_sources()["sources"]
    source = next((s for s in all_sources if s["id"] == source_id), None)
    target = next((s for s in all_sources if s["id"] == target_id), None)

    if not source:
        return jsonify({"error": "source not found"}), 404
    if not target:
        return jsonify({"error": "target source not found"}), 404
    if source_id == target_id:
        return jsonify({"error": "source and target must differ"}), 400
    if get_status(source_id) != "online":
        return jsonify({"error": f"'{source['name']}' is not online"}), 409

    vcp_codes = target.get("vcp_codes")
    vcp_code = target.get("vcp_code")
    if not vcp_codes and vcp_code is None:
        return jsonify({
            "error": f"'{target['name']}' has no VCP code set",
            "hint": "use Identify on that source card first",
        }), 409

    base = f"http://{source['ip']}:{source.get('agent_port', 5001)}"
    try:
        if vcp_codes:
            detected = _agent_post(base, "/ddc/detect", {})
            source_monitors = sorted(
                detected.get("monitors", []),
                key=lambda mon: int(mon["id"]),
            )
            target_codes = [
                code for _, code in sorted(
                    vcp_codes.items(),
                    key=lambda item: int(item[0]),
                )
            ]
            if not source_monitors:
                return jsonify({"error": f"'{source['name']}' has no detected monitors"}), 409
            if len(target_codes) > len(source_monitors):
                return jsonify({
                    "error": (
                        f"'{target['name']}' has {len(target_codes)} VCP codes, "
                        f"but '{source['name']}' has only {len(source_monitors)} monitors"
                    ),
                }), 409

            for index, code in enumerate(target_codes):
                mon_id = source_monitors[index]["id"]
                _agent_post(
                    base,
                    "/ddc/setvcp",
                    {"monitor_id": int(mon_id), "vcp_code": int(code)},
                )
        else:
            _agent_post(base, "/ddc/setvcp_all", {"vcp_code": int(vcp_code)})
    except urllib.error.URLError as e:
        return jsonify({"error": f"agent unreachable: {e.reason}"}), 502
    except Exception as e:
        return jsonify({"error": str(e)}), 502

    return jsonify({"ok": True})
