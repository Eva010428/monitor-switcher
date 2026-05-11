import threading
import webbrowser

import pystray
from PIL import Image, ImageDraw


def _make_icon() -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([4, 8, 60, 48], outline="white", width=4)
    d.rectangle([28, 48, 36, 58], fill="white")
    d.rectangle([20, 56, 44, 60], fill="white")
    return img


def _start_server(cfg: dict) -> None:
    import logging
    from .agent import ddc
    from .logging_setup import setup_logging
    from .net import bind_host
    from .runtime_paths import config_path, sources_path
    from .server.app import create_app

    setup_logging()
    if not ddc.available(cfg):
        logging.getLogger(__name__).warning(
            "No DDC tool found — switching/identify will fail"
        )

    app = create_app(cfg, sources_path(), config_path(), ddc_config=cfg)
    host = cfg.get("host", "0.0.0.0")
    bind = bind_host(host)
    port = cfg.get("port", 5000)
    app.run(host=bind, port=port, threaded=True, use_reloader=False)


def run_tray(cfg: dict) -> None:
    port = cfg.get("port", 5000)
    url = f"http://127.0.0.1:{port}"

    t = threading.Thread(target=_start_server, args=(cfg,), daemon=True)
    t.start()

    def open_ui(icon, item):
        webbrowser.open(url)

    def quit_app(icon, item):
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem("Open Monitor Hub", open_ui, default=True),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit", quit_app),
    )
    icon = pystray.Icon("monitor_hub", _make_icon(), "Monitor Hub", menu)
    webbrowser.open(url)
    icon.run()
