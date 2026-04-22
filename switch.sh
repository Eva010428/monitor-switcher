#!/bin/bash
# Monitor Switcher - macOS Launcher
# If MONITOR_SERVER_URL is set, queries the hub server for the target VCP code.
# Falls back to local config/monitors.json if server is unreachable.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/macos/monitor_switcher.sh" ]; then
    echo "Error: monitor_switcher.sh not found in macos directory"
    exit 1
fi
chmod +x "$SCRIPT_DIR/macos/monitor_switcher.sh"

# ── Server-aware mode ─────────────────────────────────────────────────────
if [ -n "$MONITOR_SERVER_URL" ]; then
    echo "Querying monitor hub: $MONITOR_SERVER_URL"

    # Detect local IP (prefer non-loopback IPv4)
    MY_IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127\.0\.0\.1' | awk '{print $2}' | head -1)
    if [ -z "$MY_IP" ]; then
        echo "Could not detect local IP, falling back to local config."
        goto_local=1
    fi

    if [ -z "$goto_local" ]; then
        RESPONSE=$(curl -sf --max-time 5 "${MONITOR_SERVER_URL}/api/switch?current=${MY_IP}" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
            echo "Server unreachable, falling back to local config."
            goto_local=1
        fi
    fi

    if [ -z "$goto_local" ]; then
        ACTION=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['action'])" <<< "$RESPONSE" 2>/dev/null)

        if [ "$ACTION" = "switch" ]; then
            TARGET_NAME=$(python3 -c "import sys,json; print(json.loads(sys.argv[1])['target']['name'])" "$RESPONSE")
            echo "Switching to: $TARGET_NAME"
            python3 - "$RESPONSE" "$SCRIPT_DIR" <<'PYEOF'
import re, sys, json, subprocess
target = json.loads(sys.argv[1])['target']
switcher = f"{sys.argv[2]}/macos/monitor_switcher.sh"
def monitor_ids():
    out = subprocess.check_output([switcher, 'detect'], text=True, stderr=subprocess.DEVNULL)
    return [m.group(1) for m in re.finditer(r'Display\s+(\d+):', out)]
if target.get('vcp_codes'):
    ids = monitor_ids()
    codes = [v for _, v in sorted(target['vcp_codes'].items(), key=lambda item: int(item[0]))]
    for mon_id, vcp in zip(ids, codes):
        subprocess.run([switcher, 'setvcp', mon_id, '60', str(vcp)])
else:
    for mon_id in monitor_ids():
        subprocess.run([switcher, 'setvcp', mon_id, '60', str(target['vcp_code'])])
PYEOF
            exit 0
        fi

        if [ "$ACTION" = "choose" ]; then
            echo "Multiple targets available. Choose one:"
            python3 - "$RESPONSE" <<'PYEOF'
import sys, json
opts = json.loads(sys.argv[1])['options']
for i, o in enumerate(opts):
    if o.get('vcp_codes'):
        vcp_str = ', '.join(f"{k}→{v}" for k, v in o['vcp_codes'].items())
    else:
        vcp_str = str(o.get('vcp_code', '?'))
    print(f"  [{i+1}] {o['name']} (VCP {vcp_str})")
PYEOF
            read -r -p "Enter number: " CHOICE
            TARGET_NAME=$(python3 -c "import sys,json; opts=json.loads(sys.argv[1])['options']; print(opts[int(sys.argv[2])-1]['name'])" "$RESPONSE" "$CHOICE")
            echo "Switching to: $TARGET_NAME"
            python3 - "$RESPONSE" "$CHOICE" "$SCRIPT_DIR" <<'PYEOF'
import re, sys, json, subprocess
opts = json.loads(sys.argv[1])['options']
target = opts[int(sys.argv[2]) - 1]
switcher = f"{sys.argv[3]}/macos/monitor_switcher.sh"
def monitor_ids():
    out = subprocess.check_output([switcher, 'detect'], text=True, stderr=subprocess.DEVNULL)
    return [m.group(1) for m in re.finditer(r'Display\s+(\d+):', out)]
if target.get('vcp_codes'):
    ids = monitor_ids()
    codes = [v for _, v in sorted(target['vcp_codes'].items(), key=lambda item: int(item[0]))]
    for mon_id, vcp in zip(ids, codes):
        subprocess.run([switcher, 'setvcp', mon_id, '60', str(vcp)])
else:
    for mon_id in monitor_ids():
        subprocess.run([switcher, 'setvcp', mon_id, '60', str(target['vcp_code'])])
PYEOF
            exit 0
        fi

        echo "Unexpected server response, falling back to local config."
    fi
fi

# ── Local config fallback ─────────────────────────────────────────────────
if [ -z "$1" ]; then
    "$SCRIPT_DIR/macos/monitor_switcher.sh" switch windows
else
    "$SCRIPT_DIR/macos/monitor_switcher.sh" "$@"
fi
