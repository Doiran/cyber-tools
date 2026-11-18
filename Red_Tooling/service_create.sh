#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run with sudo/root privileges."
  exec sudo bash "$0" "$@"
fi

read -rp "Enter the full path to the file you want to run continuously: " FILE_PATH
FILE_PATH="$(readlink -f "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"

if [[ ! -f "$FILE_PATH" ]]; then
  echo "Error: File '$FILE_PATH' does not exist."
  exit 1
fi

if [[ ! -x "$FILE_PATH" ]]; then
  echo "File is not executable. Marking it executable now..."
  chmod +x "$FILE_PATH"
fi

read -rp "Enter a name for the new service (no spaces, e.g. 'my-app'): " SERVICE_NAME
SERVICE_NAME="${SERVICE_NAME// /-}"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ -f "$SERVICE_FILE" ]]; then
  echo "Error: A service named '${SERVICE_NAME}' already exists at $SERVICE_FILE."
  exit 1
fi

read -rp "Run the service as which user? [default: $(logname 2>/dev/null || echo root)]: " RUN_USER
RUN_USER="${RUN_USER:-$(logname 2>/dev/null || echo root)}"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=${SERVICE_NAME} service
After=network.target

[Service]
Type=simple
User=${RUN_USER}
ExecStart=${FILE_PATH}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "Created service file at $SERVICE_FILE"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl start "${SERVICE_NAME}.service"

echo
echo "Service '${SERVICE_NAME}' created and started."
echo "Check status with: systemctl status ${SERVICE_NAME}"
echo "View logs with:     journalctl -u ${SERVICE_NAME} -f"