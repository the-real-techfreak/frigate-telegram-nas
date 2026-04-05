#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script is run as root/sudo
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root or using sudo"
  exit
fi

echo "--- Starting Full Frigate Stack Installation (GitHub-Safe) ---"

# 1. Update and install initial dependencies
echo "Updating package index and installing prerequisites..."
apt-get update
apt-get install -y ca-certificates curl gnupg

# 2. Add Docker's official GPG key
echo "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 3. Set up the repository
echo "Setting up the Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Docker Engine and Docker Compose
echo "Installing Docker Engine and Compose..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Create directory structure
echo "Creating directory structure in /main..."
mkdir -p /main/clips
mkdir -p /main/frigate/config
mkdir -p /main/frigate/data
mkdir -p /main/notifier

# 6. Create Global .env file with BLANK values
echo "Creating global .env template..."
cat <<EOF > /main/.env
# Replace these with your actual values before running 'docker compose up -d'
FRIGATE_URL=http://frigate:5000
MQTT_HOST=
MQTT_PORT=1883
MQTT_USER=
MQTT_PASS=
TELEGRAM_TOKEN=
TELEGRAM_CHAT_ID=
FRIGATE_RTSP_PASSWORD=
EOF

# 7. Create Frigate config.yml
cat <<EOF > /main/frigate/config/config.yml
mqtt:
  host: {MQTT_HOST}
  port: {MQTT_PORT}
  user: {MQTT_USER}
  password: {MQTT_PASS}

detectors:
  coral:
    type: edgetpu
    device: usb

ffmpeg:
  hwaccel_args: preset-vaapi

detect:
  width: 2688
  height: 1664
  fps: 4
  enabled: true

objects:
  track:
    - person

review:
  alerts:
    enabled: true
    labels:
      - person

snapshots:
  enabled: true
  retain:
    default: 1
    objects:
      person: 5

record:
  enabled: true
  alerts:
    retain:
      days: 1
      mode: motion
  continuous:
    days: 1

go2rtc:
  streams:
    outdoorcamhd:
      - rtsp://admin:PASSWORD@CAMERA_IP:554/cam/realmonitor?channel=1&subtype=0

cameras:
  outdoorcamhd:
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/outdoorcamhd
          input_args: preset-rtsp-restream
          roles:
            - detect
            - record

version: 0.17-0
EOF

# 8. Create notifier/requirements.txt
cat <<EOF > /main/notifier/requirements.txt
paho-mqtt
requests
python-telegram-bot
EOF

# 9. Create notifier/frigate_notifier.py
cat <<'EOF' > /main/notifier/frigate_notifier.py
import time, json, os, requests, asyncio
import paho.mqtt.client as mqtt
from telegram import Bot

FRIGATE_URL = os.getenv("FRIGATE_URL")
MQTT_HOST = os.getenv("MQTT_HOST")
MQTT_PORT = int(os.getenv("MQTT_PORT", 1883))
MQTT_USER = os.getenv("MQTT_USER")
MQTT_PASS = os.getenv("MQTT_PASS")
TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
SAVE_FOLDER = "/app/frigate_clips"

bot = Bot(token=TELEGRAM_TOKEN)

async def handle_review_clip(camera, start, end, review_id, severity):
    url = f"{FRIGATE_URL}/api/{camera}/start/{start}/end/{end}/clip.mp4"
    path = os.path.join(SAVE_FOLDER, f"{review_id}.mp4")
    try:
        res = requests.get(url, stream=True, timeout=60)
        if res.status_code == 200:
            with open(path, 'wb') as f:
                for chunk in res.iter_content(1024): f.write(chunk)
            caption = f"🎬 **NEW {severity.upper()}**\n📷 Camera: {camera}"
            with open(path, 'rb') as v:
                await bot.send_video(chat_id=TELEGRAM_CHAT_ID, video=v, caption=caption, parse_mode='Markdown')
    except Exception as e:
        print(f"Error: {e}")

def on_message(client, userdata, msg):
    from datetime import datetime
    data = json.loads(msg.payload.decode())
    if data.get("type") == "end":
        val = data["after"]
        asyncio.run_coroutine_threadsafe(
            handle_review_clip(val["camera"], val["start_time"]-5, val["end_time"]+5, 
                               datetime.now().strftime('%Y%m%d-%H%M%S'), val["severity"]), loop
        )

if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    client = mqtt.Client()
    if MQTT_USER: client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.on_message = on_message
    client.connect(MQTT_HOST, MQTT_PORT, 60)
    client.subscribe("frigate/reviews")
    client.loop_start()
    loop.run_forever()
EOF

# 10. Create compose.yml
echo "Creating compose.yml..."
cat <<EOF > /main/compose.yml
services:
  dozzle:
    container_name: dozzle
    restart: unless-stopped
    image: amir20/dozzle:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - 8080:8080

  frigate:
    container_name: frigate
    privileged: true
    restart: unless-stopped
    image: ghcr.io/blakeblackshear/frigate:stable
    shm_size: "256mb"
    devices:
      - /dev/bus/usb:/dev/bus/usb
      - /dev/dri/renderD128:/dev/dri/renderD128
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /main/frigate/config:/config
      - /main/frigate/data:/media/frigate
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1000000000
    ports:
      - "5000:5000"
      - "8971:8971"
      - "8554:8554"
      - "8555:8555/tcp"
      - "8555:8555/udp"
      - "1984:1984"
    environment:
      FRIGATE_RTSP_PASSWORD: \${FRIGATE_RTSP_PASSWORD}
      MQTT_HOST: \${MQTT_HOST}
      MQTT_PORT: \${MQTT_PORT}
      MQTT_USER: \${MQTT_USER}
      MQTT_PASS: \${MQTT_PASS}

  frigate-notifier:
    image: python:3.11-slim
    container_name: frigate-notifier
    restart: always
    depends_on:
      - frigate
    volumes:
      - /main/notifier:/app
      - /main/clips:/app/frigate_clips
    working_dir: /app
    environment:
      - FRIGATE_URL=\${FRIGATE_URL}
      - MQTT_HOST=\${MQTT_HOST}
      - MQTT_PORT=\${MQTT_PORT}
      - MQTT_USER=\${MQTT_USER}
      - MQTT_PASS=\${MQTT_PASS}
      - TELEGRAM_TOKEN=\${TELEGRAM_TOKEN}
      - TELEGRAM_CHAT_ID=\${TELEGRAM_CHAT_ID}
    command: >
      sh -c "pip install --no-cache-dir -r requirements.txt && python frigate_notifier.py"
EOF

# 11. Finalize permissions
echo "Adjusting permissions..."
chown -R $SUDO_USER:$SUDO_USER /main
usermod -aG docker $SUDO_USER

echo "--- Setup Complete ---"
echo "STEP 1: Open /main/.env and fill in your credentials."
echo "STEP 2: Open /main/frigate/config/config.yml and set your camera URL."
echo "STEP 3: Run 'cd /main && docker compose up -d'"




# Use the command wget -O setup.sh https://raw.githubusercontent.com/your-username/your-repo/main/install.sh && chmod +x setup.sh && sudo ./setup.sh
