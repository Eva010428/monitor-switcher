# Windows 編譯說明

## 環境需求

### 方案 A：Visual Studio（推薦）

- Visual Studio 2019 或 2022（Community 版免費）
- 安裝時選擇「**使用 C++ 的桌面開發**」工作負載（包含 Windows SDK）

### 方案 B：MinGW-w64

```cmd
choco install mingw
```

或前往 https://www.mingw-w64.org/downloads/ 下載。

---

## 編譯

### Visual Studio（命令列）

開啟 **Developer Command Prompt for VS**：

```cmd
cd path\to\monitor-switcher\windows
cl /EHsc /MT /O2 /std:c++17 monitor_switcher.cpp /link Dxva2.lib Gdi32.lib User32.lib /OUT:..\bin\monitor_switcher.exe
```

### MinGW

```cmd
cd windows
mingw32-make
copy monitor_switcher.exe ..\bin\
```

或手動：

```cmd
g++ -std=c++17 -O2 -static -o monitor_switcher.exe monitor_switcher.cpp -ldxva2 -lgdi32
```

> **注意**：`json.hpp` 已包含在 `windows/` 目錄中，編譯時必須存在。

---

## 確認編譯結果

```cmd
bin\monitor_switcher.exe help
bin\monitor_switcher.exe detect
```

---

## 疑難排解

**找不到 `PhysicalMonitorEnumerationAPI.h`**
- 確認已安裝「使用 C++ 的桌面開發」工作負載（含 Windows SDK）
- 在 Visual Studio Installer 中重新修復安裝

**找不到 `Dxva2.lib`**
- 同上，需要 Windows SDK
- Visual Studio：專案屬性 → 連結器 → 輸入 → 額外相依性，加入 `Dxva2.lib`

**找不到 `cl.exe`**
- 必須在 Developer Command Prompt 中執行，不是一般 cmd
- 開始選單搜尋「Developer Command Prompt for VS」

**編譯成功但執行時找不到 DLL**
- 使用了動態連結：重新編譯加上 `/MT`（MSVC）或 `-static`（MinGW）
- 或安裝 [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe)

**DDC/CI 相關執行期錯誤**
- 在螢幕 OSD 選單啟用 DDC/CI
- 以系統管理員身分執行
- 更新顯示卡驅動程式
