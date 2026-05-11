#!/bin/bash
# Create macOS Applications for Monitor Switcher

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HOME/Applications"

echo "正在创建 Monitor Switcher 应用程序..."

# 创建应用目录
mkdir -p "$APP_DIR"

# 编译 AppleScript 为应用程序
echo "创建 'Switch to Windows.app'..."
osacompile -o "$APP_DIR/Switch to Windows.app" "$SCRIPT_DIR/SwitchToWindows.applescript"

echo ""
echo "✅ 应用程序创建完成！"
echo ""
echo "应用程序位置: $APP_DIR"
echo "  - Switch to Windows.app"
echo ""
echo "📌 下一步操作："
echo "1. 添加到 Dock："
echo "   拖拽应用到 Dock 栏即可"
echo ""
echo "2. 设置快捷键："
echo "   - 打开 系统设置 → 键盘 → 键盘快捷键"
echo "   - 点击 App 快捷键 → 点击 [+]"
echo "   - 选择应用程序，设置快捷键（如 ⌘⌥W）"
echo ""
echo "3. 使用 Spotlight 快速启动："
echo "   按 ⌘+空格，输入 'Switch to' 即可找到应用"
echo ""
