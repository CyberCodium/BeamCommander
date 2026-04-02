# BeamCommander 🔭

> **Advanced management script for Ubiquiti PowerBeam M5 400 UX running OpenWRT.**

[![License: Private](https://img.shields.io/badge/license-Private%20Use-red.svg)](#license)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://kernel.org/)

---

## Features

- 🔍 **Auto-discovery** – automatically scans the local subnet and identifies SSH-accessible devices
- 📡 **Wireless management** – scan nearby APs, show/change channel, TX power, and SSID
- 🌐 **Network management** – change the LAN IP address on the fly
- 🖥️ **System information** – kernel, OpenWRT release, uptime, and memory at a glance
- 🔄 **Remote reboot** – safely reboot the device from the menu
- 💻 **SSH terminal passthrough** – drop into a full interactive shell when needed
- 🎨 **Coloured output** – easy-to-read status messages with severity levels

---

## Requirements

| Requirement | Notes |
|---|---|
| Bash ≥ 4.0 | Ships with most Linux distros |
| `ssh` / `scp` | OpenSSH client |
| `ping` | Standard system utility |
| `ip` | Part of `iproute2` |
| PowerBeam M5 400 UX | Firmware: OpenWRT (SSH enabled) |

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/CyberCodium/BeamCommander.git
cd BeamCommander

# 2. Make the script executable
chmod +x powerbeam-manager.sh

# 3. Run (defaults to 192.168.1.20)
./powerbeam-manager.sh

# 3b. Override IP or SSH key via environment variables
POWERBEAM_IP=192.168.1.50 SSH_KEY=~/.ssh/id_rsa ./powerbeam-manager.sh
```

---

## Configuration

All options can be overridden via environment variables before running the script:

| Variable | Default | Description |
|---|---|---|
| `POWERBEAM_IP` | `192.168.1.20` | Primary IP of the PowerBeam |
| `ALT_IP` | `192.168.1.1` | Alternative / fallback IP |
| `SSH_USER` | `root` | SSH login user |
| `SSH_KEY` | *(empty)* | Path to SSH private key (leave empty for password auth) |
| `TIMEOUT` | `5` | SSH connection timeout (seconds) |
| `BACKUP_DIR` | `~/powerbeam-backups` | Directory where backups are stored |
| `LOG_FILE` | `/tmp/powerbeam-manager.log` | Path to the log file |
| `INTERFACE` | *(auto-detected)* | Local network interface to use |

---

## Menu

```
╔══════════════════════════════════════════════════╗
║   PowerBeam M5 400 UX Manager v2.0 (FIXED)      ║
╚══════════════════════════════════════════════════╝

 1. System Information
 2. Quick Test (ping + SSH)
 3. Wireless Scan
 4. Show Wireless Config
 5. Set Channel
 6. Set TX Power
 7. Set SSID
 8. Change LAN IP
 9. Reboot Device
10. SSH Terminal
 0. Exit
```

---

## Logging

All actions are appended to the log file (default: `/tmp/powerbeam-manager.log`).  
Override the path with the `LOG_FILE` environment variable.

---

## License

This project is released under a **Private Use License**.  
It is permitted for **personal and testing use only**.  
Commercial use, redistribution, or sublicensing is **not** permitted.  
See the [LICENSE](LICENSE) file for full terms.
