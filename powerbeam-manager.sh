#!/bin/bash
# PowerBeam Advanced Management Script v2.0 - FIXED
# For Ubiquiti PowerBeam M5 400 UX with OpenWRT

set -euo pipefail  # CRÍTICO: sale en errores

# ─── CONFIGURATION ────────────────────────────────────────────────────────────
INTERFACE="${INTERFACE:-}"
POWERBEAM_IP="${POWERBEAM_IP:-192.168.1.20}"
ALT_IP="${ALT_IP:-192.168.1.1}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
TIMEOUT="${TIMEOUT:-5}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/powerbeam-backups}"
LOG_FILE="${LOG_FILE:-/tmp/powerbeam-manager.log}"

# PowerBeam specs
PB_MAX_TX=25
PB_VALID_CHANNELS_20="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 149 153 157 161 165"

# ─── COLORS ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# ─── LOGGING ──────────────────────────────────────────────────────────────────
log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[ERROR] $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

warning() {
    local msg="[WARNING] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

header() {
    echo -e "\n${CYAN}═══ $1 ═══${NC}\n"
}

# ─── VALIDATION ───────────────────────────────────────────────────────────────
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then return 1; fi
        done
        return 0
    fi
    return 1
}

validate_int() {
    local val="$1" min="$2" max="$3"
    if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= min && val <= max )); then
        return 0
    fi
    return 1
}

validate_port() {
    validate_int "$1" 1 65535
}

# ─── CONNECTIVITY ─────────────────────────────────────────────────────────────

# Mejor detección de interfaz
detect_interface() {
    # Buscar interfaces ethernet activas (no loopback, no wireless)
    for iface in $(ls /sys/class/net/ 2>/dev/null | grep -E '^eth|en'); do
        # Verificar que esté up
        if ip link show "$iface" 2>/dev/null | grep -q 'state UP'; then
            echo "$iface"
            return 0
        fi
    done

    # Fallback: primera interfaz ethernet que exista
    for iface in $(ls /sys/class/net/ 2>/dev/null | grep -E '^eth|en'); do
        echo "$iface"
        return 0
    done

    echo "eth0"
    return 1
}

get_local_subnet() {
    local iface="$1"
    ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[0-9./]+' | head -1 || echo ""
}

identify_powerbeam() {
    local ip="$1"
    local ssh_opts="-o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes"

    echo "Verificando $ip..."

    if ssh $ssh_opts "$SSH_USER@$ip" "echo OK" 2>/dev/null; then
        echo "OpenWRT device (SSH responds)"
        return 0
    fi

    return 1
}

auto_discover() {
    header "Auto-Discovery"
    log "Scanning network for PowerBeam devices..."

    local iface
    iface=$(detect_interface)
    INTERFACE="$iface"
    info "Using interface: $iface"

    local subnet
    subnet=$(get_local_subnet "$iface")

    if [[ -z "$subnet" ]]; then
        error "No IP address on interface $iface"
        return 1
    fi

    info "Your subnet: $subnet"

    local base_ip
    base_ip=$(echo "$subnet" | cut -d/ -f1 | sed 's/\.[0-9]*$//')

    echo -e "${CYAN}Scanning ${base_ip}.0/24 ...${NC}"
    echo ""

    info "Scanning hosts (parallel)..."
    local found_ips=()
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # Parallel ping sweep: fire all pings in the background
    for i in $(seq 1 254); do
        local ip="${base_ip}.${i}"
        (
            if ping -c 1 -W 1 "$ip" &>/dev/null; then
                echo "$ip" > "$tmp_dir/$i"
            fi
        ) &
    done
    wait  # wait for all background pings to finish

    # Collect live hosts in order, then check SSH
    for i in $(seq 1 254); do
        if [[ -f "$tmp_dir/$i" ]]; then
            local ip
            ip=$(cat "$tmp_dir/$i")
            echo "  Live: $ip"
            if identify_powerbeam "$ip" &>/dev/null; then
                found_ips+=("$ip")
                echo -e "   ${GREEN}✓ SSH device found${NC}"
            fi
        fi
    done

    rm -rf "$tmp_dir"

    echo ""

    if [[ ${#found_ips[@]} -eq 0 ]]; then
        error "No SSH devices found"
        return 1
    elif [[ ${#found_ips[@]} -eq 1 ]]; then
        POWERBEAM_IP="${found_ips[0]}"
        success "Found: $POWERBEAM_IP"
        return 0
    else
        echo -e "${WHITE}Multiple devices found:${NC}"
        for i in "${!found_ips[@]}"; do
            echo "  $((i+1)). ${found_ips[$i]}"
        done
        echo ""
        read -p "Select device [1-${#found_ips[@]}]: " dev_choice
        if validate_int "$dev_choice" 1 ${#found_ips[@]}; then
            POWERBEAM_IP="${found_ips[$((dev_choice-1))]}"
            success "Selected: $POWERBEAM_IP"
            return 0
        fi
    fi
}

# Captura errores SSH con salida informativa
ssh_cmd() {
    local cmd="$1"
    local timeout="${2:-$TIMEOUT}"
    local ssh_opts="-o ConnectTimeout=$timeout -o StrictHostKeyChecking=no -o BatchMode=yes"

    local output
    local exit_code

    if [[ -n "$SSH_KEY" ]]; then
        output=$(ssh $ssh_opts -i "$SSH_KEY" "$SSH_USER@$POWERBEAM_IP" "$cmd" 2>&1)
        exit_code=$?
    else
        output=$(ssh $ssh_opts "$SSH_USER@$POWERBEAM_IP" "$cmd" 2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
        echo "SSH ERROR (exit $exit_code): $output" >&2
        return $exit_code
    fi

    echo "$output"
    return 0
}

# Wrapper para scp
scp_from() {
    local remote="$1" local_path="$2"
    local ssh_opts="-o ConnectTimeout=$TIMEOUT -o StrictHostKeyChecking=no -o BatchMode=yes"

    if [[ -n "$SSH_KEY" ]]; then
        scp $ssh_opts -i "$SSH_KEY" "$SSH_USER@$POWERBEAM_IP:$remote" "$local_path" 2>&1
    else
        scp $ssh_opts "$SSH_USER@$POWERBEAM_IP:$remote" "$local_path" 2>&1
    fi
}

scp_to() {
    local local_path="$1" remote="$2"
    local ssh_opts="-o ConnectTimeout=$TIMEOUT -o StrictHostKeyChecking=no -o BatchMode=yes"

    if [[ -n "$SSH_KEY" ]]; then
        scp $ssh_opts -i "$SSH_KEY" "$local_path" "$SSH_USER@$POWERBEAM_IP:$remote" 2>&1
    else
        scp $ssh_opts "$local_path" "$SSH_USER@$POWERBEAM_IP:$remote" 2>&1
    fi
}

# ─── CHECK CONNECTION ─────────────────────────────────────────────────────────
check_connection() {
    log "Checking PowerBeam at $POWERBEAM_IP..."

    if ping -c 1 -W 2 "$POWERBEAM_IP" &>/dev/null; then
        log "Host reachable via ping"
    else
        warning "Host not responding to ping"
    fi

    if ssh_cmd "echo OK" &>/dev/null; then
        success "SSH connection OK"
        return 0
    else
        error "SSH connection failed"
        return 1
    fi
}

# ─── MAIN MENU ────────────────────────────────────────────────────────────────
show_menu() {
    clear
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${WHITE}   PowerBeam M5 400 UX Manager v2.0 (FIXED)   ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e " Target: ${CYAN}$POWERBEAM_IP${NC}"
    echo ""
    echo " 1. System Information"
    echo " 2. Quick Test (ping + SSH)"
    echo " 3. Wireless Scan"
    echo " 4. Show Wireless Config"
    echo " 5. Set Channel"
    echo " 6. Set TX Power"
    echo " 7. Set SSID"
    echo " 8. Change LAN IP"
    echo " 9. Reboot Device"
    echo "10. SSH Terminal"
    echo " 0. Exit"
    echo ""
}

# ─── SIMPLE FUNCTIONS ─────────────────────────────────────────────────────────
get_system_info() {
    header "System Information"
    ssh_cmd "uname -a"
    echo ""
    ssh_cmd "cat /etc/openwrt_release 2>/dev/null || cat /etc/banner 2>/dev/null"
    echo ""
    ssh_cmd "uptime"
    echo ""
    ssh_cmd "free -m"
}

wireless_scan() {
    header "Wireless Scan"
    ssh_cmd "iwinfo wlan0 scan 2>/dev/null | head -50"
}

show_wireless_config() {
    header "Wireless Configuration"
    ssh_cmd "uci show wireless 2>/dev/null"
}

set_channel() {
    echo "Valid 5GHz channels: $PB_VALID_CHANNELS_20"
    read -p "Enter 5GHz channel: " channel
    local valid=0
    for ch in $PB_VALID_CHANNELS_20; do
        if [[ "$channel" == "$ch" ]]; then
            valid=1
            break
        fi
    done
    if [[ $valid -eq 1 ]]; then
        ssh_cmd "uci set wireless.@wifi-device[0].channel=$channel; uci commit wireless; wifi reload"
        success "Channel set to $channel"
    else
        error "Invalid channel. Valid channels: $PB_VALID_CHANNELS_20"
    fi
}

set_tx_power() {
    read -p "TX power in dBm (0-${PB_MAX_TX}): " power
    if [[ "$power" =~ ^[0-9]+$ ]] && (( power >= 0 && power <= PB_MAX_TX )); then
        ssh_cmd "uci set wireless.@wifi-device[0].txpower=$power; uci commit wireless; wifi reload"
        success "TX power set to ${power}dBm"
    else
        error "Invalid power (0-${PB_MAX_TX})"
    fi
}

set_ssid() {
    read -p "New SSID: " ssid
    if [[ ${#ssid} -le 32 ]]; then
        ssh_cmd "uci set wireless.@wifi-iface[0].ssid='$ssid'; uci commit wireless; wifi reload"
        success "SSID set to: $ssid"
    else
        error "SSID too long (max 32 chars)"
    fi
}

change_lan_ip() {
    read -p "New LAN IP (e.g. 192.168.1.20): " new_ip
    if validate_ip "$new_ip"; then
        warning "This will disconnect you temporarily!"
        read -p "Continue? (y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            ssh_cmd "uci set network.lan.ipaddr='$new_ip'; uci commit network; /etc/init.d/network restart"
            POWERBEAM_IP="$new_ip"
            success "IP changed to $new_ip - reconnecting..."
            sleep 5
            check_connection
        fi
    else
        error "Invalid IP"
    fi
}

reboot_device() {
    read -p "Reboot PowerBeam? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        ssh_cmd "reboot"
        success "Reboot command sent"
    fi
}

ssh_terminal() {
    echo "Opening SSH terminal to $POWERBEAM_IP..."
    echo "Use 'exit' to return to menu"
    echo ""
    local ssh_opts="-o StrictHostKeyChecking=no"
    [[ -n "$SSH_KEY" ]] && ssh_opts="$ssh_opts -i $SSH_KEY"
    ssh $ssh_opts "$SSH_USER@$POWERBEAM_IP"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
main() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${WHITE}    PowerBeam Manager v2.0 - FIXED EDITION      ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"

    # Auto-detect interface
    local detected_iface
    detected_iface=$(detect_interface)
    if [[ -n "$detected_iface" ]]; then
        INTERFACE="$detected_iface"
        info "Interface: $INTERFACE"
    fi

    # Auto-discover if needed
    if ! ping -c 1 -W 2 "$POWERBEAM_IP" &>/dev/null; then
        warning "$POWERBEAM_IP not responding, starting discovery..."
        if ! auto_discover; then
            error "Could not find PowerBeam"
            echo ""
            echo "Manual configuration:"
            read -p "Enter PowerBeam IP: " manual_ip
            if validate_ip "$manual_ip"; then
                POWERBEAM_IP="$manual_ip"
            else
                error "Invalid IP. Exiting."
                exit 1
            fi
        fi
    fi

    # Test connection
    if ! check_connection; then
        warning "SSH connection failed. Make sure:"
        echo "  1. PowerBeam is powered on"
        echo "  2. Ethernet cable is connected"
        echo "  3. SSH is enabled in OpenWRT"
        echo "  4. Root password is set (default: no password)"
        echo ""
        read -p "Try with password authentication? (y/N): " try_pass
        if [[ $try_pass =~ ^[Yy]$ ]]; then
            unset SSH_KEY  # Force password
            if check_connection; then
                success "Connected with password!"
            else
                error "Still cannot connect. Exiting."
                exit 1
            fi
        else
            exit 1
        fi
    fi

    success "Connected to $POWERBEAM_IP"

    # Main loop
    while true; do
        show_menu
        read -p "Select option [0-10]: " choice

        case $choice in
            1) get_system_info ;;
            2) check_connection ;;
            3) wireless_scan ;;
            4) show_wireless_config ;;
            5) set_channel ;;
            6) set_tx_power ;;
            7) set_ssid ;;
            8) change_lan_ip ;;
            9) reboot_device ;;
            10) ssh_terminal ;;
            0)
                log "Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid option"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

main "$@"
