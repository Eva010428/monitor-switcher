#!/bin/bash
# Test script to find correct input source codes for ASUS monitor
# 測試腳本：找出 ASUS 螢幕的正確輸入源代碼

echo "======================================"
echo "ASUS 螢幕輸入源代碼測試工具"
echo "======================================"
echo ""
echo "這個腳本會測試常見的輸入源代碼"
echo "請觀察螢幕 2 (VG27AQ3A) 是否有反應"
echo ""
echo "測試的代碼包括："
echo "  15 - DisplayPort 1 (標準)"
echo "  16 - DisplayPort 2 (標準)"
echo "  17 - HDMI 1 (標準)"
echo "  18 - HDMI 2 (標準)"
echo "  27 - USB-C (標準)"
echo ""
echo "ASUS 特殊代碼："
echo "  208 - DisplayPort 1 (LG/ASUS 替代)"
echo "  209 - DisplayPort 2 (LG/ASUS 替代)"
echo "  144 - HDMI 1 (LG/ASUS 替代)"
echo "  145 - HDMI 2 (LG/ASUS 替代)"
echo "  210 - USB-C/DP 3 (LG/ASUS 替代)"
echo ""
read -p "按 Enter 開始測試..."
echo ""

# 標準代碼
echo "========== 測試標準代碼 =========="
for code in 15 16 17 18 27; do
    echo ""
    echo "► 測試代碼 $code..."
    m1ddc display 2 set input $code 2>&1
    echo "   已發送命令，等待 3 秒..."
    echo "   【請觀察螢幕是否切換】"
    sleep 3
    read -p "   螢幕有反應嗎？(y/n/skip): " response
    if [ "$response" = "y" ]; then
        echo "   ✅ 代碼 $code 有效！"
        echo "$code" >> /tmp/working_codes.txt
    elif [ "$response" = "skip" ]; then
        echo "   ⏭️  跳過剩餘測試"
        break
    else
        echo "   ❌ 代碼 $code 無反應"
    fi
done

echo ""
read -p "是否繼續測試 ASUS 特殊代碼？(y/n): " continue
if [ "$continue" != "y" ]; then
    echo "測試結束"
    exit 0
fi

# ASUS/LG 特殊代碼
echo ""
echo "========== 測試 ASUS 特殊代碼 =========="
for code in 208 209 144 145 210; do
    echo ""
    echo "► 測試代碼 $code..."
    m1ddc display 2 set input $code 2>&1
    echo "   已發送命令，等待 3 秒..."
    echo "   【請觀察螢幕是否切換】"
    sleep 3
    read -p "   螢幕有反應嗎？(y/n/skip): " response
    if [ "$response" = "y" ]; then
        echo "   ✅ 代碼 $code 有效！"
        echo "$code" >> /tmp/working_codes.txt
    elif [ "$response" = "skip" ]; then
        echo "   ⏭️  跳過剩餘測試"
        break
    else
        echo "   ❌ 代碼 $code 無反應"
    fi
done

echo ""
echo "======================================"
echo "測試完成！"
echo "======================================"
if [ -f /tmp/working_codes.txt ]; then
    echo ""
    echo "✅ 有效的代碼："
    cat /tmp/working_codes.txt | sort -u
    echo ""
    echo "請記下這些代碼，並更新到 config/monitors.json"
    rm /tmp/working_codes.txt
else
    echo ""
    echo "❌ 沒有找到有效的輸入源代碼"
    echo ""
    echo "可能的原因："
    echo "1. 螢幕當前在該輸入源上，所以看不出切換"
    echo "2. 螢幕使用非標準代碼"
    echo "3. 需要在螢幕 OSD 設定中啟用 DDC/CI"
fi
echo ""
