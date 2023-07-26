## Simple tool to automount encrypted zfs datasets on boot while storing the password on a remote host.

### How does it work?
The setup involves two physical separated hosts:
- The 'main host', which needs to mount encrypted zfs datasets on boot and is expected to reboot from time to time.
- The 'provider host', which is solely used to save the password in memory. Regular reboots are not expected. A cheap single board computer like the raspberry pi is suitable for being the provider host.

When the main host boots, the password is retrieved via ssh from the provider host which stores the password in memory. The remote host can be a raspberry pi in your local network for example. In the rare case the provider host loses its memory because of a reboot, the password must be provided manually once. This can be done by executing `./provide_password.sh` on the main host.

### How to set this up with proxmox + raspberry pi
#### 1. Setup the raspberry pi
- Flash a fresh raspbian onto a sd card. I recommend using raspbian lite (without desktop) to limit the attack surface.
- Enable ssh on the rpi, disable password authentication and add your main host's public key to /root/.ssh/authorized_hosts
- for added security disable the monitor output: by adding the line 'hdmi_blanking=2' to /boot/config.txt
- I recommend giving the rpi a static ip address either via network configuration or by binding the mac address on your routers config

#### 2. Setup the main host
- Clone this project to /usr/local/bin/ 
- Copy the autozfs.service to /etc/system/systemd/
- Edit the provider_hosts.conf to match your rpi's ip address
- Enable the automount service by executing `systemctl daemon-reload && systemctl enable autozfs`.
- Manually execute `./provide_password.sh` and type in your encryption passwords. It will be pushed to the memory of the rpi via ssh.'

Currently the autozfs.service is only tested on proxmox pve version 6,7 and 8. To make it work on other operating systems, slight modifications might be necessary.
Make sure to modify the 'Before=' field to include all services which must wait for the encrypted datasets to be mounted before they start.
