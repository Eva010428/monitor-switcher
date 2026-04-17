# 計畫：為 monitor-switcher 新增硬體裝置同步切換功能

## Context

使用者目前的 monitor-switcher 可快速切換螢幕輸入源（Windows ↔ Mac），但鍵盤/滑鼠等 USB 裝置仍需手動切換。使用者目前沒有任何 USB 硬體切換設備，希望讓硬體裝置能隨螢幕一起切換。

目標：在螢幕切換完成後，自動觸發鍵盤/滑鼠的切換動作。

---

## 建議方案概覽

### 硬體路線（推薦）
購買 USB 切換器（如 UGREEN USB 3.0 Sharing Switch，約 NT$500-800），這類裝置支援透過鍵盤快捷鍵觸發（通常是連按兩次 Scroll Lock）。  
→ 整合方式：螢幕切換後，用腳本模擬快捷鍵來觸發 USB 切換。

### 軟體路線（不需購買硬體）
安裝 **InputLeap**（免費開源，Barrier 的社群 fork），透過網路共享鍵盤/滑鼠，在切換螢幕時強制切換輸入焦點到目標機器。  
→ 整合方式：在 InputLeap server config 設定 `switchToScreen()` hotkey，螢幕切換後由 hook 腳本模擬該按鍵觸發。

> **注意**：InputLeap 沒有原生 CLI 強制切換指令，必須透過 server config 定義 hotkey 再用腳本模擬按鍵的方式達成。

---

## 技術實作：新增 Post-Switch Hook 系統

這是核心工程改動——在現有 monitor-switcher 中加入一個通用的 hook 機制，讓使用者自由配置「切換成功後要執行的命令」。無論是 USB 切換器快捷鍵、InputLeap 命令、或任何其他腳本，都可以透過設定檔掛入。

### 1. `config/monitors.json` — 新增 hooks 欄位

```json
{
  "inputs": { "dp1": 15, "hdmi2": 18 },
  "profiles": { "windows": "dp1", "mac": "hdmi2" },
  "hooks": {
    "post_switch": {
      "windows": "C:\\scripts\\switch_usb_to_windows.bat",
      "mac": "C:\\scripts\\switch_usb_to_mac.bat"
    }
  }
}
```

macOS 端的 hooks 範例：
```json
"hooks": {
  "post_switch": {
    "windows": "/usr/local/bin/inputleap --switch windows",
    "mac": "/usr/local/bin/inputleap --switch mac"
  }
}
```

---

### 2. `windows/monitor_switcher.cpp` 修改

**Config struct 新增欄位（約 line 60-80）：**
```cpp
struct Config {
    // 現有欄位...
    std::map<std::string, std::string> postSwitchHooks; // 新增
};
```

**loadConfig() 新增解析（約 line 225-230）：**
```cpp
if (j.contains("hooks") && j["hooks"].contains("post_switch")) {
    for (auto& [key, val] : j["hooks"]["post_switch"].items())
        if (val.is_string()) config.postSwitchHooks[key] = val.get<std::string>();
}
```

**switchProfile() 在成功後執行 hook（約 line 291，在 `return 0` 之前）：**
```cpp
if (anySuccess && !anyFailure) {
    std::cout << "All monitors switched successfully!" << std::endl;
    // 執行 post-switch hook
    if (config.postSwitchHooks.count(profileName)) {
        std::cout << "Running post-switch hook..." << std::endl;
        system(config.postSwitchHooks[profileName].c_str());
    }
    return 0;
}
```

---

### 3. `macos/monitor_switcher.sh` 修改

**load_config() 新增解析（約 line 90-103）：**
```bash
# 讀取 post-switch hook
if command -v jq &>/dev/null; then
    POST_HOOK=$(jq -r ".hooks.post_switch[\"$profile\"] // empty" "$CONFIG_FILE" 2>/dev/null)
else
    POST_HOOK=$(grep -A5 "\"post_switch\"" "$CONFIG_FILE" | grep "\"$profile\"" | sed 's/.*: "\(.*\)".*/\1/')
fi
```

**switch_profile() 在成功後執行 hook（約 line 186，在 `exit 0` 之前）：**
```bash
if [ "${success:-0}" -gt 0 ] && [ "${failure:-0}" -eq 0 ]; then
    echo -e "${GREEN}Monitors switched successfully!${NC}"
    # 執行 post-switch hook
    if [ -n "${POST_HOOK:-}" ]; then
        echo "Running post-switch hook..."
        eval "$POST_HOOK"
    fi
    exit 0
fi
```

---

### 4. `config/monitors.json.example` 更新

新增 hooks 欄位範例與說明註解。

---

## 使用者需要的額外設定（依路線而定）

### 硬體路線
建立 `switch_usb_to_windows.bat` / `switch_usb_to_mac.bat`：
```batch
REM 使用 AutoHotkey 模擬 Scroll Lock 兩次（觸發 UGREEN 切換器）
powershell -command "(New-Object -ComObject WScript.Shell).SendKeys('{SCROLLLOCK}{SCROLLLOCK}')"
```

### 軟體路線（InputLeap）

#### 前置設定
1. 安裝 InputLeap 於 Windows 和 Mac
2. **Windows 當 Server**（鍵盤/滑鼠實體接在 Windows），Mac 當 Client
3. 在 InputLeap server config 加入 hotkey 定義：

```
keystroke(Control+Shift+F11) = switchToScreen(mac-machine-name)
keystroke(Control+Shift+F12) = switchToScreen(windows-machine-name)
```

#### Hook 腳本

**Windows 端** (`switch_to_mac.bat`)：
```batch
REM 模擬 Ctrl+Shift+F11，觸發 InputLeap 切換到 Mac
powershell -command "(New-Object -ComObject WScript.Shell).SendKeys('^+{F11}')"
```

**Mac 端** (`switch_to_windows.sh`)：
```bash
# InputLeap server 在 Windows，需 SSH 遠端觸發
ssh windows-machine "powershell -command \"(New-Object -ComObject WScript.Shell).SendKeys('^+{F12}')\""
```

#### 非對稱性說明

| 方向 | 觸發機制 | 可行性 |
|------|---------|--------|
| Windows → Mac（`switch.bat mac`） | Windows hook 直接模擬按鍵 | ✅ 直接可行 |
| Mac → Windows（`switch.sh windows`） | Mac hook 需 SSH 到 Windows 遠端模擬 | ⚠️ 需設定 SSH |

Mac 端 hook 模擬按鍵無法直接觸發 InputLeap（因為 server 在 Windows），所以需要 SSH。替代方案是用 `osascript` 把游標移到螢幕邊緣觸發 InputLeap 的 edge detection，但較不乾淨。

---

## 關鍵檔案

| 檔案 | 修改內容 |
|------|----------|
| `windows/monitor_switcher.cpp` | Config struct + loadConfig + switchProfile |
| `macos/monitor_switcher.sh` | load_config + switch_profile |
| `config/monitors.json` | 新增 hooks 欄位 |
| `config/monitors.json.example` | 更新範例與說明 |

---

## 驗證方式

1. 執行 `switch.bat windows` → 確認螢幕切換後 hook 命令有被執行（console 顯示 "Running post-switch hook..."）
2. 確認 hook 指令執行後鍵盤/滑鼠成功切換到目標機器
3. 測試 hook 路徑不存在時不會 crash（靜默跳過）
4. 測試 `config/monitors.json` 沒有 hooks 欄位時仍正常運作（向下相容）
