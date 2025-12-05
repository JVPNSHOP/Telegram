#!/usr/bin/env bash
set -e

# setup.sh — interactive setup for the Telegram bot
# Usage: chmod +x setup.sh ; ./setup.sh

REPO_DIR="$(pwd)"
VENV_DIR="${REPO_DIR}/.venv"
ENV_FILE="/etc/default/telegram-bot"
SERVICE_FILE="/etc/systemd/system/telegram-bot.service"

echo "=== Telegram Bot Interactive Setup ==="
echo
read -p "Create/activate Python venv and install deps here? (y/n) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  python3 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  python3 -m pip install --upgrade pip
  pip install python-telegram-bot==20.5
  echo "Virtualenv created at $VENV_DIR and dependencies installed."
else
  echo "Skipping venv setup. Make sure dependencies are installed manually."
fi

echo
echo "Now we will store BOT credentials. You can skip and set them later."
read -p "Set BOT_TOKEN now? (y/n) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  read -p "Enter BOT_TOKEN (e.g. 123:ABC...): " BOT_TOKEN
else
  BOT_TOKEN=""
fi

read -p "Set ADMIN_ID now? (y/n) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  read -p "Enter ADMIN_ID (numeric): " ADMIN_ID
else
  ADMIN_ID=""
fi

read -p "Set ADMIN_PIN now? (y/n) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  read -p "Enter ADMIN_PIN: " ADMIN_PIN
else
  ADMIN_PIN=""
fi

read -p "Set ADMIN_USERNAME now? (y/n) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  read -p "Enter ADMIN_USERNAME (e.g. @Juevpn): " ADMIN_USERNAME
else
  ADMIN_USERNAME=""
fi

echo
read -p "Write environment to $ENV_FILE (requires sudo)? (y/n) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ] || [ -z "$ADMIN_PIN" ] || [ -z "$ADMIN_USERNAME" ]; then
    echo "Warning: one or more values are empty. You can edit $ENV_FILE later."
  fi
  sudo tee "$ENV_FILE" > /dev/null <<EOF
BOT_TOKEN="${BOT_TOKEN}"
ADMIN_ID="${ADMIN_ID}"
ADMIN_PIN="${ADMIN_PIN}"
ADMIN_USERNAME="${ADMIN_USERNAME}"
DELAY_BETWEEN="0.05"
EOF
  sudo chmod 600 "$ENV_FILE"
  echo "Wrote env to $ENV_FILE"
else
  echo "Skipping env file write. You can export variables manually in your shell later."
fi

echo
read -p "Create systemd service (recommended) to run bot automatically? (y/n) " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  read -p "Enter the Linux username to run service as (e.g. youruser): " RUN_USER
  # default paths (change if needed)
  echo "Creating service file at $SERVICE_FILE"
  sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Bot
After=network.target

[Service]
User=${RUN_USER}
WorkingDirectory=${REPO_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/python ${REPO_DIR}/bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable telegram-bot
  sudo systemctl start telegram-bot
  echo "Service created and started. Check with: sudo systemctl status telegram-bot"
else
  echo "Skipping service creation. You can run bot manually with 'source .venv/bin/activate && python3 bot.py'"
fi

echo
echo "=== Setup finished ==="
echo "If you skipped writing env file, you can set variables manually with:"
echo "export BOT_TOKEN=\"...\""
echo "export ADMIN_ID=\"...\""
echo "export ADMIN_PIN=\"...\""
echo "export ADMIN_USERNAME=\"...\""
echo
echo "Run the bot with:"
echo "source ${VENV_DIR}/bin/activate"
echo "python3 ${REPO_DIR}/bot.py"
