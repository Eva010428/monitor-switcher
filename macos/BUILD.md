# macOS 設定說明

## 安裝 DDC 工具

### Apple Silicon（M1/M2/M3/M4）

```bash
brew install m1ddc
```

### Intel Mac

```bash
brew install ddcctl
```

> **⚠️ Apple Silicon HDMI 限制**：Apple Silicon Mac 的內建 HDMI 孔硬體上不支援 DDC/CI。螢幕必須透過 **Thunderbolt/USB-C** 連接才能使用自動切換。透過 HDMI 連接的螢幕需手動按 OSD 按鈕切換。

---

## 讓腳本可執行

```bash
chmod +x macos/monitor_switcher.sh switch.sh
```

---

## 確認安裝

```bash
./switch.sh detect
```

應顯示每個 display 的 DDC/CI 支援狀態。

---

## 可選依賴

### jq（JSON 解析，非必要）

```bash
brew install jq
```

若未安裝 jq，`load_config()` 會改用 `grep`/`sed` 解析設定檔，功能相同。

---

## 快速啟動方式

### Automator App

1. 開啟 Automator → 新增「應用程式」
2. 加入「執行 Shell 指令碼」
3. 填入：`/path/to/monitor-switcher/switch.sh mac`
4. 儲存為 "Switch to Mac.app" 並拖曳到 Dock

### 快速鍵（BetterTouchTool / Karabiner-Elements）

綁定快速鍵執行 shell script：`/path/to/switch.sh mac`

---

## 疑難排解

**「ddcctl: command not found」**
```bash
brew reinstall ddcctl
```

**DDC communication failure**
- 最常見原因：螢幕透過 HDMI 連接 Apple Silicon Mac
- 執行 `m1ddc display list detailed` 確認連接方式
- 改用 USB-C/Thunderbolt 連接

**螢幕沒有反應**
- 在螢幕 OSD 選單確認 DDC/CI 已啟用
- 確認使用的線材支援 DDC/CI（劣質線材可能不支援）
- 重新執行 `./switch.sh setup` 自動偵測正確輸入碼

**Terminal 權限問題**
- 系統偏好設定 → 隱私權 → 輔助使用 → 允許 Terminal
