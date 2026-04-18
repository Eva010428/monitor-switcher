import sys
import threading
import time
import urllib.request
import json
from pathlib import Path
from flask import Flask, render_template
from . import init as init_store
from .sources import bp as sources_bp, set_status
from .switch import bp as switch_bp
from .switch import init as init_switch
from .identify import bp as identify_bp
from .identify import init as init_identify
from .settings import bp as settings_bp
from .settings import init as init_settings


def _resource_base() -> Path:
    """Read-only resource base: sys._MEIPASS when bundled, project root in dev."""
    if hasattr(sys, '_MEIPASS'):
        import sys as _sys
        return Path(_sys._MEIPASS)
    return Path(__file__).parent.parent.parent


def create_app(config: dict, sources_path: Path, config_path: Path) -> Flask:
    base = _resource_base()
    tmpl_dir = base / "monitor_hub" / "templates"
    static_dir = base / "monitor_hub" / "static"
    app = Flask(__name__, template_folder=str(tmpl_dir), static_folder=str(static_dir))

    init_store(sources_path)
    init_switch(config)
    init_identify(config)
    init_settings(config, config_path)

    app.register_blueprint(sources_bp)
    app.register_blueprint(switch_bp)
    app.register_blueprint(identify_bp)
    app.register_blueprint(settings_bp)

    @app.get("/")
    def index():
        return render_template("index.html")

    # Background health-check: ping all agents every 30s
    def _ping_loop():
        from . import load_sources
        while True:
            time.sleep(30)
            try:
                data = load_sources()
                for source in data["sources"]:
                    url = f"http://{source['ip']}:{source.get('agent_port', 5001)}/health"
                    try:
                        with urllib.request.urlopen(url, timeout=3) as resp:
                            resp.read()
                        set_status(source["id"], "online")
                    except Exception:
                        set_status(source["id"], "offline")
            except Exception:
                pass

    t = threading.Thread(target=_ping_loop, daemon=True)
    t.start()

    return app
