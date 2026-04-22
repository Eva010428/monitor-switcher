import socket
import sys
from flask import Flask, jsonify, request, abort
from . import ddc


def create_app(config: dict, trusted_ips: list[str] | None = None) -> Flask:
    app = Flask(__name__)
    app.config["DDC_CONFIG"] = config
    app.config["TRUSTED_IPS"] = set(trusted_ips or [])

    @app.before_request
    def check_trust():
        if not app.config["TRUSTED_IPS"]:
            return
        remote = request.remote_addr
        if remote not in app.config["TRUSTED_IPS"] and remote != "127.0.0.1":
            abort(403)

    @app.get("/health")
    def health():
        cfg = app.config["DDC_CONFIG"]
        return jsonify({
            "platform": sys.platform,
            "hostname": socket.gethostname(),
            "ddc_available": ddc.available(cfg),
            "name": cfg.get("name", socket.gethostname()),
        })

    @app.post("/ddc/detect")
    def ddc_detect():
        cfg = app.config["DDC_CONFIG"]
        try:
            monitors = ddc.detect_monitors(cfg)
            return jsonify({"monitors": monitors})
        except RuntimeError as e:
            return jsonify({"error": str(e)}), 500

    @app.post("/ddc/getvcp")
    def ddc_getvcp():
        cfg = app.config["DDC_CONFIG"]
        body = request.get_json(force=True, silent=True) or {}
        monitor_id = body.get("monitor_id", 0)
        try:
            code = ddc.get_input(cfg, monitor_id)
            return jsonify({"monitor_id": monitor_id, "vcp_code": code})
        except RuntimeError as e:
            return jsonify({"error": str(e)}), 500

    @app.post("/ddc/setvcp")
    def ddc_setvcp():
        cfg = app.config["DDC_CONFIG"]
        body = request.get_json(force=True, silent=True) or {}
        monitor_id = body.get("monitor_id", 0)
        vcp_code = body.get("vcp_code")
        if vcp_code is None:
            return jsonify({"error": "vcp_code required"}), 400
        try:
            ddc.set_input(cfg, monitor_id, int(vcp_code))
            return jsonify({"ok": True})
        except RuntimeError as e:
            return jsonify({"error": str(e)}), 500

    @app.post("/ddc/setvcp_all")
    def ddc_setvcp_all():
        cfg = app.config["DDC_CONFIG"]
        body = request.get_json(force=True, silent=True) or {}
        vcp_code = body.get("vcp_code")
        if vcp_code is None:
            return jsonify({"error": "vcp_code required"}), 400
        try:
            ddc.set_input_all(cfg, int(vcp_code))
            return jsonify({"ok": True})
        except RuntimeError as e:
            return jsonify({"error": str(e)}), 500

    return app
