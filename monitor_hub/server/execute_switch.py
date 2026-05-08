from flask import Blueprint, jsonify
from . import load_sources
from ..agent import ddc

bp = Blueprint("execute_switch", __name__)

_ddc_config: dict = {}


def init(ddc_config: dict = None):
    global _ddc_config
    _ddc_config = ddc_config or {}


@bp.post("/api/sources/<source_id>/switch")
def execute_switch(source_id):
    all_sources = load_sources()["sources"]
    source = next((s for s in all_sources if s["id"] == source_id), None)
    if not source:
        return jsonify({"error": "source not found"}), 404

    vcp_codes = source.get("vcp_codes")
    vcp_code = source.get("vcp_code")
    if not vcp_codes and vcp_code is None:
        return jsonify({
            "error": f"'{source['name']}' has no VCP code set",
            "hint": "use Identify on this source card first, or set VCP codes manually",
        }), 409

    try:
        if vcp_codes:
            monitors = ddc.detect_monitors(_ddc_config)
            monitors = sorted(monitors, key=lambda m: int(m["id"]))
            codes = [code for _, code in sorted(vcp_codes.items(), key=lambda item: int(item[0]))]
            if not monitors:
                return jsonify({"error": "no monitors detected locally"}), 409
            if len(codes) > len(monitors):
                return jsonify({
                    "error": f"'{source['name']}' has {len(codes)} VCP codes but only {len(monitors)} monitors detected"
                }), 409
            for index, code in enumerate(codes):
                ddc.set_input(_ddc_config, monitors[index]["id"], int(code))
        else:
            monitors = ddc.detect_monitors(_ddc_config)
            for mon in monitors:
                ddc.set_input(_ddc_config, mon["id"], int(vcp_code))
    except Exception as e:
        return jsonify({"error": str(e)}), 502

    return jsonify({"ok": True})
