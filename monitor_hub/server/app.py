import sys
from pathlib import Path
from flask import Flask, render_template
from . import init as init_store
from .sources import bp as sources_bp
from .switch import bp as switch_bp
from .switch import init as init_switch
from .identify import bp as identify_bp
from .identify import init as init_identify
from .settings import bp as settings_bp
from .settings import init as init_settings
from .execute_switch import bp as execute_switch_bp


def _resource_base() -> Path:
    """Read-only resource base: sys._MEIPASS when bundled, project root in dev."""
    if hasattr(sys, '_MEIPASS'):
        import sys as _sys
        return Path(_sys._MEIPASS)
    return Path(__file__).parent.parent.parent


def create_app(
    config: dict,
    sources_path: Path,
    config_path: Path,
    *,
    ddc_config: dict = None,
) -> Flask:
    from .execute_switch import init as init_execute_switch

    if ddc_config is None:
        ddc_config = {}

    base = _resource_base()
    tmpl_dir = base / "monitor_hub" / "templates"
    static_dir = base / "monitor_hub" / "static"
    app = Flask(__name__, template_folder=str(tmpl_dir), static_folder=str(static_dir))

    init_store(sources_path)
    init_switch(config)
    init_identify(config, ddc_config)
    init_settings(config, config_path)
    init_execute_switch(ddc_config)

    app.register_blueprint(sources_bp)
    app.register_blueprint(switch_bp)
    app.register_blueprint(identify_bp)
    app.register_blueprint(settings_bp)
    app.register_blueprint(execute_switch_bp)

    @app.get("/")
    def index():
        return render_template("index.html")

    return app
