# FRIGATE -- TELEGRAM -- NAS

This repo is created for the following requirements 
- One-click installation of Frigate NVR
- Enable automatic saving of review clips to local folder (optionally to NAS)
- Notify the saved review clip through Telegram Bot service

(Note: Review -> compilation of simultaneous events; as of Frigate 0.17, the API doesn't allow for a compiled clip for each review item but individual event clips can be called)

# Pre-requisites for Installation

Following are the prerequisites for this installation
- Working Linux distro on a machine with network connectivity
- Accessible MQTT Broker with valid username and password. (In case there is no external MQTT broker setup, applications like Eclipse, EMQX, etc. can be installed on the same machine)

If the setup is being deployed in a Proxmox container along with an edge device like Coral TPU, USB-Pass through is essential which can be enabled by the following commands

Enter the following command in Proxmox Node Shell
```bash
cd /etc/pve/lxc 
```
Locate the .conf file related to the container (e.g: 100.conf) and run the following command
```bash
nano 100.conf
```
Add the following lines at the end of the file to allow USB-Pass through
```bash
lxc.mount.entry: /dev/bus/usb/001/ dev/bus/usb/001/ none bind,optional,create=dir 0,0
lxc.mount.entry: /dev/bus/usb/002/ dev/bus/usb/002/ none bind,optional,create=dir 0,0
lxc.mount.entry: /dev/bus/usb/003/ dev/bus/usb/003/ none bind,optional,create=dir 0,0 
```

# Frigate NVR Installation

SSH into the machine and run the following command
```bash
wget -O frigate.sh https://raw.githubusercontent.com/the-real-techfreak/frigate-telegram-nas/blob/main/install_frigate.sh && sudo chmod +x frigate.sh && sudo ./frigate.sh
```
The above script completes the following actions
- Install Docker, Docker-Compose and corresponding dependencies
- Create **directories** for frigate container (/main/frigate/{config,data}
- Create a sample **configuration** for frigate (/main/frigate/config/config.yml)
- Create a **.env** file for user input related to MQTT (/main/.env)
- Create a **compose.yml** (/main/compose.yml) for docker-compose to run the following containers -> dozzle (monitoring logs), frigate


If the requirement is only Frigate installation, please proceed to below steps after the script finishes, to complete the setup:
- provide MQTT details in the .env file using the following command
  
```bash
sudo nano /main/.env
```
- Update the frigate config file with your camera details using the following command
  
```bash
sudo nano /main/frigate/config/config.yml
```

If you need to save the review clips and forward them using Telegram Bot, please proceed to the next step 


# Notifier Installation

The below script needs to be executed after installing Frigate NVR from the above step.

SSH into the machine and run the following command

```bash
wget -O notifier.sh https://raw.githubusercontent.com/the-real-techfreak/frigate-telegram-nas/blob/main/install_notifier.sh && sudo chmod +x notifier.sh && sudo ./notifier.sh
```
The above script completes the following actions
- Create directories for notifier and review clips collection (/main/{notifier, clips})
- Add python script for clip download and notify it using telegram bot, along with dependancies
- Update the .env file with Telegram variables for user input
- Update the docker compose file with Python script container

To complete the setup, please update as below:
- Update the MQTT and Telegram Bot details in .env file using the following command

```bash
sudo nano /main/.env
```
- Update the frigate config file with your camera details using the following command
  
```bash
sudo nano /main/frigate/config/config.yml
```

# Optional - NAS Archiving from Proxmox LXC

Mounting a SMB share in an LXC container is slightly different from mounting the same on a stand-alone Linux Machine or VM as we will have problems with FSTAB in mounting on boot

The steps are as below:
- Store the SMB credentials in a file (e.g: /main/.smbcred) using nano
```bash
sudo nano /main/.smbcred
```

```bash
username=smbuser
password=smbpass
```

- Mount the network drive to a folder using FSTAB
```bash
sudo nano /etc/fstab
```

```bash
//smb-ip-address/share /frigate-archive cifs credentials=/main/.smbcred,iocharset=utf8,uid=0,gid=0,vers=3.0,_netdev,nofail 0 0
```

- Create a file named "rc.local" in /etc and add the below script
```bash
sudo nano /etc/rc.local
```

```bash
#!/bin/sh -e
sleep 10
mount -a
exit 0
```
- Give privileges to the newly created file
```bash
sudo chmod +x /etc/rc.local
```

Once it is confirmed that Network drive is mounted perfectly, a cronjob can be implemented to continuously move the frigate clips to Network Drive periodically by using the following commands
```bash
crontab -e
```

```bash
*/5 * * * * mkdir -p /frigate-archive/$(date '+\%Y')/$(date '+\%Y-\%m-\%d') && mv /main/clips/* /frigate-archive/$(date '+\%Y')/$(date '+\%Y-\%m-\%d')

```
