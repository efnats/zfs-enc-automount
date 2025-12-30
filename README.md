# zfs-enc-automount

Automount encrypted ZFS datasets on Proxmox VE hosts at boot, with passwords stored securely on remote provider hosts.

## Overview

This tool is designed for **Proxmox VE** environments where encrypted ZFS datasets need to be automatically unlocked at boot without storing passwords locally. It retrieves encryption passwords via SSH from one or more provider hosts (e.g., Raspberry Pi) that keep the passwords only in RAM.

## How does it work?

The setup involves two physically separated hosts:

- **Proxmox host**: The server with encrypted ZFS datasets that reboots from time to time.
- **Provider host(s)**: One or more devices (e.g., Raspberry Pi) that store the encryption passwords in RAM only. Regular reboots are not expected.

When the Proxmox host boots, passwords are retrieved via SSH from all reachable provider hosts. The passwords are combined and deduplicated, then used to unlock the encrypted datasets before services like `pve-guests.service` start.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              LOCAL NETWORK                                   │
│                                                                              │
│  ┌───────────────┐         SSH (Key-Only)        ┌───────────────────────┐  │
│  │ Proxmox Host  │──────────────────────────────►│ Provider #1 (Pi)      │  │
│  │               │                               │ /var/run/zfs_passwords│  │
│  │ ZFS Encrypted │──────────────────────────────►│                       │  │
│  │               │         SSH (Key-Only)        ├───────────────────────┤  │
│  │               │                               │ Provider #2 (Fallback)│  │
│  └───────────────┘                               │ /var/run/zfs_passwords│  │
│                                                  └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Multiple Provider Hosts

You can configure multiple provider hosts for:
- **Redundancy**: Same passwords on multiple hosts (if one is down, the other works)
- **Distribution**: Different passwords on different hosts (all are aggregated)
- **Combination**: Some passwords shared, some exclusive to specific hosts

## Security Features

| Feature | Description |
|---------|-------------|
| SSH Key-Only | Password authentication disabled on provider hosts |
| RAM-Only Storage | Passwords stored in `/var/run/` (tmpfs), lost on reboot |
| No Local Storage | Passwords exist only in bash variables on main host |
| Secure Password Handling | Uses `printf` instead of `echo` to avoid process list exposure |
| No Shell Injection | Proper quoting prevents issues with special characters |
| Timeout Protection | Service won't hang indefinitely if providers are unreachable |

## Installation

### 1. Setup the Provider Host(s) (Raspberry Pi)

```bash
# Flash Raspberry Pi OS Lite (no desktop) onto SD card
# Enable SSH and configure:

# Disable password authentication
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Add main host's public key
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "ssh-rsa AAAA..." >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Optional: Disable HDMI output for added security
echo 'hdmi_blanking=2' | sudo tee -a /boot/config.txt

# Recommended: Set static IP via router or network config
```

### 2. Setup the Proxmox Host

```bash
# Clone to /opt/
git clone https://github.com/efnats/zfs-enc-automount.git /opt/zfs-enc-automount

# Make scripts executable
chmod +x /opt/zfs-enc-automount/*.sh

# Edit provider hosts configuration
nano /opt/zfs-enc-automount/provider_hosts.conf

# Copy and enable systemd service
cp /opt/zfs-enc-automount/zfs-enc-automount.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable zfs-enc-automount

# Verify SSH connectivity to provider(s)
ssh root@192.168.28.6 hostname

# Push encryption passwords to provider(s)
/opt/zfs-enc-automount/provide_password.sh
```

### 3. Configure Dependent Services

Edit `/etc/systemd/system/zfs-enc-automount.service` and modify the `Before=` line to include all services that depend on the encrypted datasets:

```ini
Before=pve-guests.service nfs-server.service smbd.service
```

## Usage

### Initial Password Setup

```bash
./provide_password.sh
```

Enter each encryption password when prompted. Passwords are sent to all reachable provider hosts.

### Manual Unlock (Testing)

```bash
./automount.sh
```

### After Provider Host Reboot

If a provider host reboots, its passwords are lost (RAM-only). Re-run:

```bash
./provide_password.sh
```

### Check Status

```bash
# Service status
systemctl status zfs-enc-automount

# Verify datasets are mounted
zfs list

# Check password file on provider
ssh root@192.168.28.6 cat /var/run/zfs_passwords
```

## Dataset Filtering

The script automatically identifies encrypted datasets while filtering out Proxmox-specific patterns:

| Pattern | Description |
|---------|-------------|
| `vm-*-disk-*` | Proxmox VM disks (inherit encryption from parent) |
| `subvol-*-disk-*` | Proxmox LXC container volumes |
| `base-*` | Proxmox template base images |

Standalone encryption roots like `pool/vmdisks` are correctly included.

## Tested On

- **Proxmox VE 6, 7, and 8**
- Raspberry Pi OS Lite (provider host)
- Debian 11/12 (provider host)

## Todo

- [ ] Implementation of Shamir Secret Sharing for improved security model

## License

MIT
