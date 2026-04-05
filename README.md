# frigate-telegram-nas

This repo is created for installing and setting up Frigate NVR, enable an automation to save the frigate "review" clips (Review -> compilation of simultaneous events) in a particular folder and then send this clip to the user through Telegram Bot - Send Video service. Please note that as of Frigate 0.17, the API doesn't allow for a compiled clip for each review item but individual event clips can be called.

The setup is tested on a Debian distro installed on a Proxmox container.Hardware for this setup include a tiny PC (HP Elitedesk 800 G3 mini with Intel Core i5) and a Coral TPU

# Installation Steps

It is assumed that a MQTT Broker with valid username and password is already available.
If not, an MQTT Broker (Mosquitto, EMQX, etc.) can also be installed in the same machine

Once the distro is installed on a machine, SSH into the system and run the following command
```bash
wget -O setup.sh https://raw.githubusercontent.com/the-real-techfreak/frigate-telegram-nas/main/install.sh && chmod +x setup.sh && sudo ./setup.sh
```
# Post-Installation Steps

Once the script finishes, you need to update the following: 
- provide your specific credentials in /main/.env file
- Update the camera details in the /main/frigate/config/config.yml (a generic template is provided for reference)


# What is included in the script

The script includes the following 
- **Docker Engine & Compose:** Official repository installation.
- **Docker containers Setup:** Dozzle, Frigate NVR, Python Script container (for clip archive and telegram services)

A quick description of the containers isntalled:
- **Dozzle:** Real-time log viewer for your containers (Port 8080).
- **Frigate NVR:** Ready for USB Coral and Intel Hardware Acceleration.
- **Custom Notifier:** A Python-based Telegram bot that sends clips from Frigate "reviews" via MQTT.

Configuring your services:
- **Centralized Config:** All sensitive credentials are managed via a single `.env` file.
