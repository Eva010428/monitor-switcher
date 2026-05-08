import uuid
from flask import Blueprint, jsonify, request
from . import load_sources, save_sources

bp = Blueprint("sources", __name__)


def get_status(source_id: str) -> str:
    return "online"


def _same_name(a: str, b: str) -> bool:
    return a.strip().casefold() == b.strip().casefold()


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

    if not name:
        return jsonify({"error": "name required"}), 400
    if len(name) > 64:
        return jsonify({"error": "name too long (max 64 chars)"}), 400

    data = load_sources()
    for s in data["sources"]:
        if _same_name(s["name"], name):
            return jsonify({"error": f"duplicate name: {name}", "existing_id": s["id"]}), 409

    source = {
        "id": str(uuid.uuid4()),
        "name": name,
        "vcp_code": body.get("vcp_code"),
        "vcp_code_confirmed": False,
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
        for s in data["sources"]:
            if _same_name(s["name"], name) and s["id"] != source_id:
                return jsonify({"error": f"duplicate name: {name}"}), 409
        source["name"] = name

    if "vcp_code" in body:
        source["vcp_code"] = body["vcp_code"]
        source["vcp_code_confirmed"] = body["vcp_code"] is not None

    if "vcp_codes" in body:
        source["vcp_codes"] = body["vcp_codes"]

    if "vcp_code_confirmed" in body:
        source["vcp_code_confirmed"] = body["vcp_code_confirmed"]

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
    return "", 204
