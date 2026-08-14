import socket

LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


def bind_host(config_host: str | None) -> str:
    host = config_host or "0.0.0.0"
    if host in LOCAL_HOSTS:
        return host
    return "0.0.0.0"


def detect_lan_ip() -> str:
    """Best-effort local-network IP for this machine (e.g. 192.168.1.50).

    Uses the "UDP connect" trick: connecting a UDP socket triggers no
    actual packet send, but makes the OS pick the outbound interface, whose
    address we can then read back — no external calls, works offline.
    """
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def advertised_host(config_host: str | None) -> str:
    """Host to show the user for LAN access. Auto-detects the LAN IP when
    config doesn't pin a specific address (default "0.0.0.0"); an explicit
    loopback host is shown as-is since the server isn't LAN-reachable then."""
    host = config_host or "0.0.0.0"
    if host == "0.0.0.0":
        return detect_lan_ip()
    return host
