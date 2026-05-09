import uuid
import threading
import time
from flask import Blueprint, jsonify, request
from ..agent import ddc
from . import load_sources, save_sources

bp = Blueprint("identify", __name__)

_sessions: dict[str, dict] = {}
_session_lock = threading.Lock()
_config: dict = {}
_ddc_config: dict = {}


def init(server_config: dict, ddc_config: dict = None):
    global _config, _ddc_config
    _config = server_config
    _ddc_config = ddc_config or {}


@bp.post("/api/identify/<source_id>/start")
def start_identify(source_id: str):
    data = load_sources()
    source = next((s for s in data["sources"] if s["id"] == source_id), None)
    if not source:
        return jsonify({"error": "source not found"}), 404

    try:
        monitors = ddc.detect_monitors(_ddc_config)
    except Exception as e:
        return jsonify({"error": f"DDC detect failed: {e}"}), 502

    if not monitors:
        return jsonify({"error": "No monitors detected on agent"}), 502

    # Save prior VCP per monitor so we can restore each one after probing
    prior_vcps: dict[int, int | None] = {}
    for mon in monitors:
        try:
            prior_vcps[mon["id"]] = ddc.get_input(_ddc_config, mon["id"])
        except Exception:
            prior_vcps[mon["id"]] = None

    candidates = _config.get("identify_candidates", [15, 16, 17, 18, 19, 3, 4, 27])
    session_id = str(uuid.uuid4())

    session = {
        "session_id": session_id,
        "source_id": source_id,
        "source": source,
        "state": "idle",
        "candidates": candidates,
        "monitors": monitors,
        "prior_vcps": prior_vcps,
        # {monitor_id: vcp_code} — tracks last successfully probed code per monitor
        "probed": {},
        "probe_lock": threading.Lock(),
        "error": None,
    }

    with _session_lock:
        _sessions[session_id] = session

    return jsonify({
        "session_id": session_id,
        "candidates": candidates,
        "monitors": monitors,
        "prior_vcps": prior_vcps,
        "saved_vcp_codes": source.get("vcp_codes") or {},
        "saved_vcp_code": source.get("vcp_code"),
        "state": "idle",
    })


@bp.post("/api/identify/<session_id>/probe")
def probe_identify(session_id: str):
    """
    Switch ONE monitor to the given VCP code for 1 second, then restore.
    Only that monitor goes dark; others are unaffected.
    """
    session = _sessions.get(session_id)
    if not session:
        return jsonify({"error": "session not found"}), 404
    if session["state"] not in ("idle", "probing"):
        return jsonify({"error": f"session is {session['state']}"}), 409

    body = request.get_json(force=True, silent=True) or {}
    monitor_id = body.get("monitor_id")
    vcp_code = body.get("vcp_code")
    if monitor_id is None or vcp_code is None:
        return jsonify({"error": "monitor_id and vcp_code required"}), 400

    if not session["probe_lock"].acquire(blocking=False):
        return jsonify({"error": "probe already in progress"}), 409

    try:
        prior = session["prior_vcps"].get(int(monitor_id))
        if prior is None:
            # Fall back to the source's saved VCP code for this monitor
            saved_vcps = session["source"].get("vcp_codes") or {}
            fallback = saved_vcps.get(str(int(monitor_id))) or saved_vcps.get(int(monitor_id))
            if fallback is None:
                fallback = session["source"].get("vcp_code")
            if fallback is not None:
                prior = int(fallback)

        dwell_ms = int(_config.get("identify_dwell_ms", 3000))
        dwell_s = max(0.5, min(dwell_ms / 1000.0, 10.0))

        session["state"] = "probing"
        ddc.set_input(_ddc_config, int(monitor_id), int(vcp_code))

        if prior is not None:
            time.sleep(dwell_s)
            last_err = None
            for attempt in range(5):
                try:
                    ddc.set_input(_ddc_config, int(monitor_id), prior)
                    break
                except Exception as e:
                    last_err = e
                    if attempt < 4:
                        time.sleep(0.4)
            else:
                raise RuntimeError(f"restore to VCP {prior} failed after 5 attempts: {last_err}")

        session["state"] = "idle"
        return jsonify({
            "ok": True,
            "monitor_id": int(monitor_id),
            "vcp_code": int(vcp_code),
            "restored_vcp_code": prior,
            "dwell_ms": dwell_ms if prior is not None else 0,
        })
    except Exception as e:
        session["state"] = "error"
        session["error"] = str(e)
        return jsonify({"error": str(e)}), 502
    finally:
        session["probe_lock"].release()


@bp.post("/api/identify/<session_id>/confirm")
def confirm_identify(session_id: str):
    """
    Save the confirmed VCP codes to sources.json.
    Body: {vcp_codes: {monitor_id: vcp_code, ...}}
    If all monitors share the same code, vcp_code is also set at the top level.
    """
    session = _sessions.get(session_id)
    if not session:
        return jsonify({"error": "session not found"}), 404
    if session["state"] != "idle":
        return jsonify({"error": f"session is {session['state']}, cannot confirm now"}), 409

    body = request.get_json(force=True, silent=True) or {}
    # Accept either explicit vcp_codes map or fall back to probed dict
    vcp_codes: dict[int, int] = {int(k): int(v)
                                  for k, v in (body.get("vcp_codes") or session["probed"]).items()}
    if not vcp_codes:
        return jsonify({"error": "no vcp_codes to confirm — probe at least one monitor first"}), 400

    unique_codes = set(vcp_codes.values())
    shared_code = next(iter(unique_codes)) if len(unique_codes) == 1 else None

    data = load_sources()
    for s in data["sources"]:
        if s["id"] == session["source_id"]:
            s["vcp_codes"] = {str(k): v for k, v in vcp_codes.items()}
            s["vcp_code_confirmed"] = True
            # Keep legacy single vcp_code if all monitors agree
            if shared_code is not None:
                s["vcp_code"] = shared_code
            else:
                s.pop("vcp_code", None)
            break
    save_sources(data)
    session["state"] = "confirmed"

    return jsonify({
        "vcp_codes": vcp_codes,
        "vcp_code": shared_code,
        "source_id": session["source_id"],
    })


@bp.post("/api/identify/<session_id>/cancel")
def cancel_identify(session_id: str):
    session = _sessions.get(session_id)
    if not session:
        return jsonify({"error": "session not found"}), 404
    session["state"] = "cancelled"
    return jsonify({"state": "cancelled"})


@bp.get("/api/identify/<session_id>/status")
def status_identify(session_id: str):
    session = _sessions.get(session_id)
    if not session:
        return jsonify({"error": "session not found"}), 404
    return jsonify({
        "session_id": session_id,
        "source_id": session["source_id"],
        "state": session["state"],
        "candidates": session["candidates"],
        "monitors": session["monitors"],
        "probed": session["probed"],
        "error": session.get("error"),
    })
