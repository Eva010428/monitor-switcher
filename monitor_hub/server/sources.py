import uuid
import ipaddress
from flask import Blueprint, jsonify, request
from . import load_sources, save_sources

bp = Blueprint("sources", __name__)

# In-memory status overlay (not persisted)
_status: dict[str, str] = {}


def set_status(source_id: str, status: str):
    _status[source_id] = status


def get_status(source_id: str) -> str:
    return _status.get(source_id, "unknown")


def _validate_ip(ip: str):
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        return False
    return True


@bp.get("/api/sources")
def list_sources():
    data = load_sources()
    for s in data["sources"]:
        s["status"] = get_status(s["id"])
    return jsonify(data)


@bp.post("/api/sources")
def add_source():
    body = request.get_json(force=True, silent=True) or {}
    name = (body.get("name") or "").strip()
    ip = (body.get("ip") or "").strip()

    if not name:
        return jsonify({"error": "name required"}), 400
    if not ip:
        return jsonify({"error": "ip required"}), 400
    if not _validate_ip(ip):
        return jsonify({"error": f"invalid ip: {ip}"}), 400
    if len(name) > 64:
        return jsonify({"error": "name too long (max 64 chars)"}), 400

    data = load_sources()
    for s in data["sources"]:
        if s["ip"] == ip:
            return jsonify({"error": f"duplicate ip: {ip}", "existing_id": s["id"]}), 409

    source = {
        "id": str(uuid.uuid4()),
        "name": name,
        "ip": ip,
        "vcp_code": body.get("vcp_code"),
        "vcp_code_confirmed": False,
        "agent_port": body.get("agent_port", 5001),
    }
    data["sources"].append(source)
    save_sources(data)

    result = dict(source)
    result["status"] = get_status(source["id"])
    return jsonify(result), 201


@bp.put("/api/sources/<source_id>")
def update_source(source_id: str):
    body = request.get_json(force=True, silent=True) or {}
    data = load_sources()
    source = next((s for s in data["sources"] if s["id"] == source_id), None)
    if not source:
        return jsonify({"error": "not found"}), 404

    if "name" in body:
        name = (body["name"] or "").strip()
        if not name:
            return jsonify({"error": "name cannot be empty"}), 400
        if len(name) > 64:
            return jsonify({"error": "name too long"}), 400
        source["name"] = name

    if "ip" in body:
        ip = (body["ip"] or "").strip()
        if not _validate_ip(ip):
            return jsonify({"error": f"invalid ip: {ip}"}), 400
        for s in data["sources"]:
            if s["ip"] == ip and s["id"] != source_id:
                return jsonify({"error": f"duplicate ip: {ip}"}), 409
        source["ip"] = ip

    if "vcp_code" in body:
        source["vcp_code"] = body["vcp_code"]
        source["vcp_code_confirmed"] = body["vcp_code"] is not None

    if "agent_port" in body:
        source["agent_port"] = body["agent_port"]

    save_sources(data)
    result = dict(source)
    result["status"] = get_status(source["id"])
    return jsonify(result)


@bp.delete("/api/sources/<source_id>")
def delete_source(source_id: str):
    data = load_sources()
    before = len(data["sources"])
    data["sources"] = [s for s in data["sources"] if s["id"] != source_id]
    if len(data["sources"]) == before:
        return jsonify({"error": "not found"}), 404
    save_sources(data)
    _status.pop(source_id, None)
    return "", 204
