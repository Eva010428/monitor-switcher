import json
import logging
import socket
import sys
import webbrowser

from .logging_setup import setup_logging
from .net import bind_host
from .runtime_paths import config_path, ensure_default_config, sources_path


logger = logging.getLogger(__name__)


def _load_config() -> dict:
    path = ensure_default_config()
    return json.loads(path.read_text())


def _is_already_running(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except OSError:
        return False


def _run_hub(cfg: dict):
    from .agent import ddc

    if not ddc.available(cfg):
        logger.warning("No DDC tool found — web UI will start but switching/identify will fail")

    from .server.app import create_app

    hub_sources_path = sources_path()
    hub_config_path = config_path()
    host = cfg.get("host", "0.0.0.0")
    bind = bind_host(host)
    port = cfg.get("port", 5000)
    logger.info("Starting Monitor Hub on http://%s:%s (bind %s)", host, port, bind)
    app = create_app(cfg, hub_sources_path, hub_config_path, ddc_config=cfg)
    app.run(host=bind, port=port, threaded=True)


def main():
    setup_logging()
    cfg = _load_config()
    port = cfg.get("port", 5000)

    tray_mode = "--tray" in sys.argv

    if _is_already_running(port):
        logger.info("Server already running on port %s — opening browser", port)
        webbrowser.open(f"http://127.0.0.1:{port}")
        return

    if tray_mode:
        from .tray import run_tray
        run_tray(cfg)
        return

    _run_hub(cfg)


if __name__ == "__main__":
    main()
