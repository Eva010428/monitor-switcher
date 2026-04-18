import subprocess
import re
import sys
from pathlib import Path


def _project_root() -> Path:
    """Project root: next to exe when bundled, 3 levels up from this file in dev."""
    if hasattr(sys, '_MEIPASS'):
        return Path(sys.executable).parent
    return Path(__file__).parent.parent.parent


def _exe_path(config: dict) -> Path | None:
    raw = config.get("exe_path", "bin/monitor_switcher.exe")
    p = (_project_root() / raw).resolve()
    return p if p.exists() else None


def _sh_path() -> Path | None:
    p = (_project_root() / "macos" / "monitor_switcher.sh").resolve()
    return p if p.exists() else None


def _tool(config: dict):
    if sys.platform == "win32":
        exe = _exe_path(config)
        if exe:
            return ("exe", str(exe))
    else:
        sh = _sh_path()
        if sh:
            return ("sh", str(sh))
    return (None, None)


def _run(tool_type, tool_path, *args, timeout=10):
    if tool_type == "exe":
        cmd = [tool_path] + list(args)
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                                creationflags=flags)
    else:
        cmd = [tool_path] + list(args)
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"exit code {result.returncode}")
    return result.stdout


def detect_monitors(config: dict) -> list[dict]:
    tool_type, tool_path = _tool(config)
    if not tool_type:
        raise RuntimeError("No DDC tool available on this platform")
    out = _run(tool_type, tool_path, "detect")
    monitors = []
    for line in out.splitlines():
        m = re.match(r"Display\s+(\d+):\s+(.+)", line)
        if m:
            monitors.append({"id": int(m.group(1)), "description": m.group(2).strip()})
    return monitors


def get_input(config: dict, monitor_id: int) -> int:
    tool_type, tool_path = _tool(config)
    if not tool_type:
        raise RuntimeError("No DDC tool available")
    out = _run(tool_type, tool_path, "getvcp", str(monitor_id), "60")
    m = re.search(r"\((\d+) decimal\)", out)
    if not m:
        raise RuntimeError(f"Could not parse getvcp output: {out!r}")
    return int(m.group(1))


def set_input(config: dict, monitor_id: int, vcp_value: int) -> None:
    tool_type, tool_path = _tool(config)
    if not tool_type:
        raise RuntimeError("No DDC tool available")
    _run(tool_type, tool_path, "setvcp", str(monitor_id), "60", str(vcp_value))


def set_input_all(config: dict, vcp_value: int) -> None:
    monitors = detect_monitors(config)
    errors = []
    for mon in monitors:
        try:
            set_input(config, mon["id"], vcp_value)
        except RuntimeError as e:
            errors.append(f"Monitor {mon['id']}: {e}")
    if errors:
        raise RuntimeError("; ".join(errors))


def available(config: dict) -> bool:
    tool_type, _ = _tool(config)
    return tool_type is not None
