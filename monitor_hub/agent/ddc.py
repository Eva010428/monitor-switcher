import sys

if sys.platform == "win32":
    from monitorcontrol import get_monitors as _get_monitors

    def detect_monitors(config: dict) -> list[dict]:
        result = []
        for i, mon in enumerate(_get_monitors()):
            with mon:
                try:
                    caps = mon.get_vcp_capabilities()
                    desc = caps.get("model", f"Monitor {i}")
                except Exception:
                    desc = f"Monitor {i}"
            result.append({"id": i, "description": desc})
        return result

    def get_input(config: dict, monitor_id: int) -> int:
        with list(_get_monitors())[monitor_id] as mon:
            return mon.get_vcp_feature(0x60).value

    def set_input(config: dict, monitor_id: int, vcp_value: int) -> None:
        with list(_get_monitors())[monitor_id] as mon:
            mon.set_vcp_feature(0x60, vcp_value)

    def available(config: dict) -> bool:
        try:
            return len(list(_get_monitors())) > 0
        except Exception:
            return False

else:
    import re
    import shutil
    import subprocess

    def _m1ddc(*args):
        result = subprocess.run(
            ["m1ddc"] + list(args),
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or f"exit {result.returncode}")
        return result.stdout

    def detect_monitors(config: dict) -> list[dict]:
        monitors = []
        for i in range(4):
            try:
                _m1ddc("display", str(i + 1), "get", "10")
                monitors.append({"id": i, "description": f"Display {i + 1}"})
            except Exception:
                break
        return monitors

    def get_input(config: dict, monitor_id: int) -> int:
        out = _m1ddc("display", str(monitor_id + 1), "get", "60")
        m = re.search(r"(\d+)", out)
        if not m:
            raise RuntimeError(f"Cannot parse m1ddc output: {out!r}")
        return int(m.group(1))

    def set_input(config: dict, monitor_id: int, vcp_value: int) -> None:
        _m1ddc("display", str(monitor_id + 1), "set", "60", str(vcp_value))

    def available(config: dict) -> bool:
        return shutil.which("m1ddc") is not None
