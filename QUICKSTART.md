# 快速開始指南

## 5 分鐘上手

### Step 1：編譯 / 安裝工具

#### Windows

開啟 **Developer Command Prompt for VS**，執行：

```cmd
cd path\to\monitor-switcher\windows
cl /EHsc /MT /O2 /std:c++17 monitor_switcher.cpp /link Dxva2.lib Gdi32.lib User32.lib /OUT:..\bin\monitor_switcher.exe
```

或使用 MinGW：

```cmd
cd windows
mingw32-make
copy monitor_switcher.exe ..\bin\
```

#### macOS

```bash
brew install m1ddc     # Apple Silicon
# 或
brew install ddcctl    # Intel Mac

chmod +x macos/monitor_switcher.sh switch.sh
```

---

### Step 2：執行設定精靈

```cmd
REM Windows
switch.bat setup

# macOS
./switch.sh setup
```

精靈會引導你完成：

1. **識別螢幕**：每個螢幕依序閃爍亮度，讓你確認「左邊」還是「右邊」
2. **偵測輸入碼**：自動查詢螢幕支援的 DDC/CI 輸入代碼
3. **命名輸入**：為每個代碼取短名（例如 `dp1`、`hdmi2`）
4. **指定 profile**：告訴精靈哪個輸入是 Windows、哪個是 Mac
5. **寫入設定**：自動產生 `config/monitors.json`

---

### Step 3：開始使用

```cmd
REM Windows
switch.bat mac       ← 切換到 Mac
switch.bat windows   ← 切換到 Windows

# macOS
./switch.sh mac
./switch.sh windows
```

---

## 常見狀況

**「Failed to get the vcp code value」**
→ 在螢幕 OSD 選單啟用 DDC/CI

**macOS：精靈閃爍時什麼都沒發生**
→ 螢幕可能透過 HDMI 連接 Apple Silicon Mac（硬體不支援 DDC/CI）
→ 必須改用 USB-C/Thunderbolt 連接

**只有一個螢幕有反應**
→ 另一個螢幕可能不支援 DDC/CI，或使用不同輸入碼
→ 重新執行 `setup` 精靈

**「ddcctl: command not found」**
→ `brew install ddcctl`（Intel）或 `brew install m1ddc`（Apple Silicon）

---

需要更多說明，請見 [README.md](README.md)。
