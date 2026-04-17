# 版本更新記錄

格式基於 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.0.0/)，版本命名遵循 [Semantic Versioning](https://semver.org/lang/zh-TW/)。

---

## [Unreleased]

### 計劃功能
- [ ] GUI 系統托盤程式（tray icon）
- [ ] 熱鍵支援
- [ ] 支援 Linux（ddcutil）
- [ ] 支援更多 VCP 功能（亮度、對比度批量調整）

---

## [1.1.0] - 2026-04-17

### 新增功能
- **`setup` 設定精靈**：互動式自動設定，取代手動偵測 VCP 碼流程
  - 閃爍亮度（VCP 0x10）識別每個實體螢幕
  - Windows：解析 DDC/CI capabilities 字串，自動提取 VCP 0x60 支援值
  - macOS：探測標準輸入碼清單，記錄螢幕接受的代碼
  - 互動命名輸入（`dp1`、`hdmi2` 等），指定 Windows/Mac profile
  - 自動寫入 `config/monitors.json`
- `autodetect` 為 `setup` 的別名
- Windows：`loadConfig()` 現在真正讀取 `config/monitors.json`（json.hpp 已啟用）
- macOS：`load_config()` 移除硬編碼 fallback，設定檔不存在時給明確提示
- macOS：`switch_profile()` 改為動態偵測 display 1–4，不再固定兩台

### 變更
- Windows `loadConfig()`：以 `GetModuleFileNameA()` 定位設定檔路徑，不受工作目錄影響
- macOS `load_config()`：無 jq 時改用 grep/sed 解析（格式固定，可靠）

---

## [1.0.0] - 2026-03-01

### 新增功能
- 初始版本發布
- Windows C++ 實作（DDC/CI，Windows Monitor API）
- macOS Shell 包裝（ddcctl / m1ddc）
- JSON 設定檔系統
- 高階命令：`switch windows`、`switch mac`
- 低階命令：`detect`、`getvcp`、`setvcp`、`capabilities`
- 重試機制（最多 3 次，間隔 500ms）
- 跨平台啟動腳本（switch.bat / switch.sh）

---

| 版本 | 日期 | 主要變更 |
|------|------|----------|
| 1.1.0 | 2026-04-17 | setup 精靈、啟用 JSON 讀取 |
| 1.0.0 | 2026-03-01 | 初始發布，雙平台支援 |
