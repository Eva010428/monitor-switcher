import json
import logging
import sys
from pathlib import Path

from .runtime_paths import config_path, ensure_default_config, sources_path


def _data_base() -> Path:
    """Writable data dir: next to exe when bundled by PyInstaller, package dir in dev."""
    if hasattr(sys, '_MEIPASS'):
        return Path(sys.executable).parent
    return Path(__file__).parent


_BASE = _data_base()
logger = logging.getLogger(__name__)


def _load_config() -> dict:
    path = ensure_default_config()
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


def _run_local(cfg: dict):
    from .agent import ddc

    if not ddc.available(cfg):
        logger.warning("No DDC tool found — web UI will start but switching/identify will fail")

    from .server.app import create_app

    hub_sources_path = sources_path()
    hub_config_path = config_path()
    host = cfg.get("host", "0.0.0.0")
    port = cfg.get("port", 5000)
    logger.info("[local] Starting on http://%s:%s", host, port)
    app = create_app(cfg, hub_sources_path, hub_config_path, ddc_config=cfg)
    app.run(host=host, port=port, threaded=True)


def main():
    full_config = _load_config()
    mode = full_config.get("mode", "local")

    if mode == "local":
        _run_local(full_config)
    elif mode == "server":
        _run_server(full_config)
    elif mode in {"both", "agent"}:
        logger.warning("mode both/agent is deprecated, running as local mode")
        _run_local(full_config.get("agent", full_config))
    else:
        logger.error("Unknown mode: %r", mode)
        sys.exit(1)


if __name__ == "__main__":
    main()
