#!/bin/bash
set -e

# Improved root check
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Fallback for the username if SUDO_USER is blank
USER_NAME=${SUDO_USER:-$USER}

echo "--- Phase 1: Installing Frigate & Docker Core ---"

# 1. Install Docker & Dependencies
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 2. Create Frigate Directories
mkdir -p /main/frigate/{config,data}

# 3. Create .env
cat <<EOF > /main/.env
MQTT_HOST=127.0.0.1
MQTT_PORT=1883
MQTT_USER=admin
MQTT_PASS=password
FRIGATE_RTSP_PASSWORD=password
EOF

# 4. Create Frigate config.yml
# Note: we use \${VAR} so Frigate reads them at runtime from the env
cat <<EOF > /main/frigate/config/config.yml
mqtt:
  host: \${MQTT_HOST}
  port: \${MQTT_PORT}
  user: \${MQTT_USER}
  password: \${MQTT_PASS}

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

objects:
  track:
    - person

go2rtc:
  streams:
    outdoorcamhd:
      - rtsp://admin:PASSWORD@IP:554/cam/realmonitor?channel=1&subtype=0

cameras:
  outdoorcamhd:
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/outdoorcamhd
          input_args: preset-rtsp-restream
          roles:
            - detect
            - record
EOF

# 5. Create compose.yml
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
    shm_size: "512mb"
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
      - "1984:1984"
    env_file:
      - .env
EOF

chown -R "$USER_NAME":"$USER_NAME" /main
usermod -aG docker "$USER_NAME"
echo "--- Success! Edit /main/.env and then run 'docker compose up -d' in /main ---"
