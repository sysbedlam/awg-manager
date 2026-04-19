#!/bin/sh
# awg-manager installer
# https://github.com/sysbedlam/awg-manager

INSTALL_PATH="/usr/bin/awg-manager"
SCRIPT_URL="https://raw.githubusercontent.com/sysbedlam/awg-manager/main/awg-manager.sh"

echo ""
echo "Устанавливаю awg-manager..."

# Download
if ! wget -O "$INSTALL_PATH" "$SCRIPT_URL" 2>/dev/null; then
    echo "[✗] Ошибка загрузки скрипта"
    exit 1
fi

# Make executable
chmod +x "$INSTALL_PATH"

echo "[✓] awg-manager установлен!"
echo ""
echo "Запускай командой: awg-manager"
echo ""
