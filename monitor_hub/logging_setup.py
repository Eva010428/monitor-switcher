import logging
import logging.handlers
from .runtime_paths import logs_dir


def setup_logging(level: int = logging.INFO) -> None:
    fmt = logging.Formatter("%(asctime)s %(levelname)-8s %(name)s: %(message)s")

    console = logging.StreamHandler()
    console.setFormatter(fmt)

    log_file = logs_dir() / "monitor_hub.log"
    rotating = logging.handlers.RotatingFileHandler(
        log_file, maxBytes=2 * 1024 * 1024, backupCount=3, encoding="utf-8"
    )
    rotating.setFormatter(fmt)

    root = logging.getLogger()
    root.setLevel(level)
    root.addHandler(console)
    root.addHandler(rotating)
