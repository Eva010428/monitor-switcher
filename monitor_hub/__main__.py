import json
import logging
import subprocess
import sys
from pathlib import Path

from .logging_setup import setup_logging
from .runtime_paths import config_path, ensure_default_config, sources_path


logger = logging.getLogger(__name__)


def _relaunch_detached() -> None:
    """Spawn a detached copy of this process and exit the current terminal-attached one."""
    root = str(Path(__file__).parent.parent)
    if sys.platform == "win32":
        subprocess.Popen(
            ["pythonw", "-m", "monitor_hub"],
            cwd=root,
            stdin=subprocess.DEVNULL,
            creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NO_WINDOW,
        )
    else:
        subprocess.Popen(
            ["python3", "-m", "monitor_hub"],
            cwd=root,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    sys.exit(0)


def _load_config() -> dict:
    path = ensure_default_config()
    return json.loads(path.read_text())


def _run_server(cfg: dict):
    from .server.app import create_app
    hub_sources_path = sources_path()
    hub_config_path = config_path()
    host = cfg.get("host", "0.0.0.0")
    port = cfg.get("port", 5000)
    logger.info("[server] Starting on http://%s:%s", host, port)
    app = create_app(cfg, hub_sources_path, hub_config_path)
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
    setup_logging()
    full_config = _load_config()
    mode = full_config.get("mode", "local")

    if mode == "local":
        _run_local(full_config)
    elif mode == "tray":
        # If launched from a terminal, re-exec detached so closing the terminal
        # doesn't kill the tray app.
        if sys.stdin is not None and hasattr(sys.stdin, "isatty") and sys.stdin.isatty():
            logger.info("[tray] Terminal detected — relaunching detached")
            _relaunch_detached()
        from .tray import run_tray
        run_tray(full_config)
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
