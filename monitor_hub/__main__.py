import json
import sys
import threading
from pathlib import Path


def _data_base() -> Path:
    """Writable data dir: next to exe when bundled by PyInstaller, package dir in dev."""
    if hasattr(sys, '_MEIPASS'):
        return Path(sys.executable).parent
    return Path(__file__).parent


_BASE = _data_base()


def _load_config() -> dict:
    path = _BASE / "config.json"
    if not path.exists():
        print(f"[monitor_hub] config.json not found at {path}")
        print("[monitor_hub] Copy config.example.json to config.json and set your mode.")
        sys.exit(1)
    return json.loads(path.read_text())


def _run_server(cfg: dict):
    from .server.app import create_app
    sources_path = _BASE / "sources.json"
    config_path = _BASE / "config.json"
    host = cfg.get("host", "0.0.0.0")
    port = cfg.get("port", 5000)
    print(f"[server] Starting on http://{host}:{port}")
    app = create_app(cfg, sources_path, config_path)
    app.run(host=host, port=port, threaded=True)


def _run_agent(cfg: dict, server_url: str | None = None):
    from .agent.app import create_app as create_agent_app
    from .agent.register import register

    if server_url:
        cfg = dict(cfg)
        cfg["server_url"] = server_url
        try:
            register(cfg)
        except Exception as e:
            print(f"[agent] Registration error: {e}")

    host = cfg.get("host", "0.0.0.0")
    port = cfg.get("port", 5001)
    print(f"[agent] Starting on http://{host}:{port}")
    app = create_agent_app(cfg)
    app.run(host=host, port=port, threaded=True)


def main():
    full_config = _load_config()
    mode = full_config.get("mode", "server")

    if mode == "server":
        _run_server(full_config)

    elif mode == "agent":
        server_url = full_config.get("server_url")
        _run_agent(full_config, server_url)

    elif mode == "both":
        server_cfg = full_config.get("server", {})
        agent_cfg = full_config.get("agent", {})
        server_port = server_cfg.get("port", 5000)
        server_url = f"http://127.0.0.1:{server_port}"

        # Check DDC availability
        from .agent import ddc
        if not ddc.available(agent_cfg):
            print("[monitor_hub] WARNING: No DDC tool found. Running in server-only mode.")
            _run_server(server_cfg)
            return

        # Start server in background thread
        t = threading.Thread(
            target=_run_server,
            args=(server_cfg,),
            daemon=True,
            name="server",
        )
        t.start()

        # Give server a moment to bind
        import time
        time.sleep(1.5)

        # Run agent in main thread
        _run_agent(agent_cfg, server_url)

    else:
        print(f"[monitor_hub] Unknown mode: {mode!r}. Must be 'server', 'agent', or 'both'.")
        sys.exit(1)


if __name__ == "__main__":
    main()
