# Quick Start Guide

---

## Step 1: Install Dependencies

**Windows:**
```cmd
pip install flask monitorcontrol pystray Pillow
```

**macOS:**
```bash
pip install flask pystray Pillow
brew install m1ddc     # Apple Silicon
# or: brew install ddcctl    # Intel Mac
```

---

## Step 2: Configure

```bash
cp monitor_hub/config.example.json monitor_hub/config.json
```

Default config (edit if needed):
```json
{
  "host": "0.0.0.0",
  "port": 5000,
  "identify_candidates": [15, 16, 17, 18, 19, 3, 4, 27],
  "identify_dwell_ms": 3000
}
```

---

## Step 3: Start Monitor Hub

```bash
python -m monitor_hub            # keeps terminal open
python -m monitor_hub --tray     # system tray, browser opens automatically
```

Open `http://localhost:5000` in a browser.

---

## Step 4: Add a Source and Identify VCP Codes

1. Click **+ Add Source** — enter a name for this machine (e.g. "Windows PC")
2. Click **Identify** on the source card
3. For each monitor listed:
   - Click a candidate VCP code button to probe it
   - The monitor will briefly switch inputs and then auto-restore
   - Click **Save** when the probe switched to the expected input
4. Click **Confirm** to save the codes

---

## Step 5: Switch Inputs

On the source card, click the switch button for the target source. All monitors switch simultaneously.

---

## Common Issues

**Monitor doesn't react to probe**
→ Enable DDC/CI in the monitor's OSD menu
→ macOS Apple Silicon: must use USB-C/Thunderbolt — HDMI does not support DDC/CI

**Monitor switches but doesn't restore**
→ Reduce `identify_dwell_ms` to `1500` in `config.json`

**`monitorcontrol` not found (Windows)**
→ `pip install monitorcontrol`

**`m1ddc: command not found` (macOS)**
→ `brew install m1ddc`

---

For full documentation, see [README.md](README.md).
