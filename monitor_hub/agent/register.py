import socket
import urllib.request
import urllib.error
import json
import time


def _local_ip(server_url: str) -> str:
    host = server_url.split("//")[-1].split(":")[0].split("/")[0]
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect((host, 80))
            return s.getsockname()[0]
    except Exception:
        return socket.gethostbyname(socket.gethostname())


def register(config: dict, retries: int = 5, delay: float = 3.0) -> bool:
    server_url = config["server_url"].rstrip("/")
    ip = _local_ip(server_url)
    port = config.get("port", 5001)
    name = config.get("name", socket.gethostname())

    payload = json.dumps({
        "name": name,
        "ip": ip,
        "agent_port": port,
    }).encode()

    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                f"{server_url}/api/sources",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
                print(f"[agent] Registered as '{name}' ({ip}) → source id {data.get('id')}")
                return True
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            try:
                msg = json.loads(body).get("error", body)
            except Exception:
                msg = body
            if "duplicate" in msg.lower() or "already" in msg.lower():
                print(f"[agent] Already registered ({ip}), skipping.")
                return True
            print(f"[agent] Registration failed (HTTP {e.code}): {msg}")
            return False
        except Exception as e:
            print(f"[agent] Registration attempt {attempt + 1}/{retries} failed: {e}")
            if attempt < retries - 1:
                time.sleep(delay)

    print("[agent] Could not register with server. Will run without registration.")
    return False
