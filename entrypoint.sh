#!/bin/bash
set -e

IDRIVE_BIN="/opt/IDriveForLinux/bin"
IDRIVE_IT="/opt/IDriveForLinux/idriveIt"

echo "========================================"
echo "  iDrive for Linux Container Starting"
echo "========================================"

# Ensure idriveIt directory exists (in case volume is empty on first run)
mkdir -p "$IDRIVE_IT"

# Start iDrive services if account is configured
if [ -d "$IDRIVE_IT/user_profile" ]; then
    echo "[+] Existing account detected, starting services..."
    cd "$IDRIVE_BIN"
    
    # Start dashboard and cron services
    ./idrive --start-service dashboard 2>/dev/null || true
    ./idrive --start-service cron 2>/dev/null || true
    
    echo "[+] Services started."
else
    echo "[!] No account configured yet."
    echo "[!] Run: docker exec -it idrive /opt/IDriveForLinux/bin/./idrive"
    echo "[!] Then configure your account credentials."
fi

echo "[+] Container ready. Use 'docker exec -it idrive bash' to access."
echo "[+] screen is available for persistent sessions."

# Keep container running
tail -f /dev/null
