# Monitor Switcher

一鍵切換雙螢幕輸入源的跨平台工具。透過 DDC/CI 協定控制螢幕在 DisplayPort 與 HDMI 之間切換，適用於雙系統（Windows + Mac）共用螢幕的場景。

---

## 功能特色

- **雙平台支援**：Windows（C++）與 macOS（Shell + m1ddc/ddcctl）
- **一鍵切換**：同時切換多個螢幕的輸入源
- **自動設定精靈**：自動偵測可用輸入碼、閃爍亮度確認螢幕身份、互動寫入設定檔
- **JSON 設定檔**：設定完成後可直接編輯微調
- **無需安裝**：編譯後僅需執行檔，不污染系統環境

## 使用情境

- 雙系統共用螢幕：Windows 與 Mac 共用顯示器，切換時自動切換輸入源
- KVM 補充：KVM 切換鍵鼠，本工具切換螢幕輸入源
- 工作站切換：在工作電腦與個人電腦之間快速切換

---

## 快速開始

### Step 1：編譯（Windows）/ 安裝依賴（macOS）

#### Windows

```cmd
cd windows
cl /EHsc /MT /O2 /std:c++17 monitor_switcher.cpp /link Dxva2.lib Gdi32.lib User32.lib /OUT:..\bin\monitor_switcher.exe
```

詳細編譯說明見 [windows/BUILD.md](windows/BUILD.md)。

#### macOS

```bash
# Apple Silicon
brew install m1ddc

# Intel Mac
brew install ddcctl

chmod +x macos/monitor_switcher.sh switch.sh
```

詳細說明見 [macos/BUILD.md](macos/BUILD.md)。

### Step 2：執行設定精靈

```cmd
REM Windows
switch.bat setup

# macOS
./switch.sh setup
```

精靈會自動：
1. 閃爍每個螢幕的亮度，讓你確認哪個是哪個
2. 查詢 DDC/CI 能力字串（Windows）或探測標準輸入碼（macOS），找出可用輸入源
3. 互動命名每個輸入（例如 `dp1`、`hdmi2`）
4. 詢問哪個輸入對應 Windows，哪個對應 Mac
5. 寫入 `config/monitors.json`

### Step 3：使用

```cmd
REM Windows
switch.bat windows
switch.bat mac

# macOS
./switch.sh windows
./switch.sh mac
```

---

## 低階命令

直接操作 DDC/CI，用於排查問題或手動調整：

```cmd
REM Windows
bin\monitor_switcher.exe detect
bin\monitor_switcher.exe getvcp 0 60
bin\monitor_switcher.exe setvcp 0 60 15
bin\monitor_switcher.exe capabilities 0
```

```bash
# macOS（根據工具）
m1ddc display 1 get input
m1ddc display 1 set input 15
ddcctl -d 1
ddcctl -d 1 -i 15
```

---

## VCP 0x60 輸入碼參考

| 輸入源 | 代碼 |
|--------|------|
| DVI 1 | 3 |
| DVI 2 | 4 |
| DisplayPort 1 | 15 |
| DisplayPort 2 | 16 |
| HDMI 1 | 17 |
| HDMI 2 | 18 |
| HDMI 3 | 19 |
| USB-C / DP | 27 |

實際值依螢幕廠商而異，請以 `setup` 精靈偵測到的值為準。

---

## 進階使用

### 建立桌面捷徑（Windows）

1. 右鍵桌面 → 新增 → 捷徑
2. 位置：`C:\path\to\monitor-switcher\switch.bat mac`
3. 可設定快速鍵（捷徑內容 → 快速鍵欄位）

### 建立 Automator App（macOS）

1. 開啟 Automator → 新增應用程式
2. 加入「執行 Shell 指令碼」
3. 填入：`/path/to/switch.sh mac`
4. 儲存為 "Switch to Mac.app" 並拖曳到 Dock

### 開機自動執行（Windows）

```cmd
schtasks /create /tn "SwitchToWindows" /tr "C:\path\to\switch.bat windows" /sc onlogon
```

### 開機自動執行（macOS LaunchAgent）

建立 `~/Library/LaunchAgents/com.user.monitorswitcher.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.user.monitorswitcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/switch.sh</string>
        <string>mac</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
```

---

## 疑難排解

### Windows

**「Failed to get the vcp code value」**
- 在螢幕 OSD 選單中啟用 DDC/CI
- 以系統管理員身分執行
- 更新顯示卡驅動程式

**偵測不到螢幕**
- 確認螢幕已開啟並連接
- 重新插拔線材
- 更新顯示卡驅動程式

**編譯錯誤**
- 確認已安裝 Windows SDK（含 `PhysicalMonitorEnumerationAPI.h`）
- 確認連結了 `Dxva2.lib`
- 詳見 [windows/BUILD.md](windows/BUILD.md)

### macOS

**⚠️ Apple Silicon HDMI 限制**

Apple Silicon Mac（M1/M2/M3/M4）的**內建 HDMI 孔硬體上不支援 DDC/CI**。必須透過 **Thunderbolt/USB-C** 連接螢幕才能使用自動切換。

若螢幕只能透過 HDMI 連接：只在 Windows 端使用自動切換，macOS 端手動按螢幕 OSD 按鈕切換。

**「ddcctl: command not found」**
```bash
brew install ddcctl    # Intel Mac
brew install m1ddc     # Apple Silicon
```

**DDC communication failure**
- 最常見原因：螢幕透過 HDMI 連接 Apple Silicon Mac
- 解決方案：改用 USB-C/Thunderbolt 連接

### 通用

**某個螢幕可切換，另一個不行**
- 兩個螢幕可能使用不同的 VCP 值
- 重新執行 `setup` 精靈

**切換後螢幕黑屏數秒**
- 正常現象，螢幕需要時間切換輸入源

---

## 致謝

- **Windows 實作**：基於 [DDC/CI Windows API](https://blog.csdn.net/sinat_26143945/article/details/135137436) 範例
- **macOS 實作**：使用 [ddcctl](https://github.com/kfix/ddcctl)
- **JSON 函式庫**：[nlohmann/json](https://github.com/nlohmann/json)

## 授權

- 本專案整合程式碼：MIT License
- macOS ddcctl 工具：GPL v3 License
