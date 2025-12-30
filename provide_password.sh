#!/usr/bin/env bash
#
# zfs-enc-automount - provide_password.sh
# Securely push encryption passwords to provider hosts
#

set -euo pipefail

# Configuration
CONFIG_DIR="/opt/zfs-enc-automount"
PASSWD_FILE="/var/run/zfs_passwords"

# Colors for output
if [[ -t 1 ]]; then
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    RESET=$(tput sgr0)
else
    GREEN=""
    RED=""
    YELLOW=""
    RESET=""
fi

# Help text
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Securely push ZFS encryption passwords to remote provider hosts.
Passwords are stored in RAM only (/var/run/zfs_passwords) on the provider hosts.

Options:
    -h, --help      Show this help message and exit
    -r, --reset     Clear all existing passwords on all hosts before adding new ones

Examples:
    $(basename "$0")              Add passwords to existing ones on provider hosts
    $(basename "$0") --reset      Clear all passwords first, then add new ones
    $(basename "$0") -r           Same as --reset

Configuration:
    Provider hosts are read from: ${CONFIG_DIR}/provider_hosts.conf

Notes:
    - Passwords are entered interactively (masked input)
    - Press Enter on an empty line to finish entering passwords
    - All reachable hosts receive the same set of passwords
    - If a provider host reboots, passwords are lost and must be re-entered

EOF
    exit 0
}

# Parse arguments
DO_RESET=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -r|--reset)
            DO_RESET=true
            shift
            ;;
        *)
            echo "${RED}ERROR: Unknown option: $1${RESET}" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Read provider hosts from configuration file
if [[ ! -f "${CONFIG_DIR}/provider_hosts.conf" ]]; then
    echo "${RED}ERROR: Configuration file not found: ${CONFIG_DIR}/provider_hosts.conf${RESET}"
    exit 1
fi

readarray -t provider_hosts < "${CONFIG_DIR}/provider_hosts.conf"

echo ""
echo "=== ZFS Encryption Password Provider ==="
echo ""

# Check each host for SSH availability
available_hosts=()

for provider_host in "${provider_hosts[@]}"; do
    # Skip empty lines and comments
    [[ -z "$provider_host" || "$provider_host" =~ ^# ]] && continue
    
    printf "Checking %s ... " "$provider_host"
    
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${provider_host}" "true" 2>/dev/null; then
        echo "${GREEN}OK${RESET}"
        available_hosts+=("$provider_host")
    else
        echo "${RED}unreachable${RESET}"
    fi
done

# Exit if no hosts are available
if [[ ${#available_hosts[@]} -eq 0 ]]; then
    echo ""
    echo "${RED}No hosts are reachable. Exiting.${RESET}"
    exit 1
fi

# Clear all passwords if --reset flag is set
if [[ "$DO_RESET" == "true" ]]; then
    echo ""
    echo "${YELLOW}Clearing all passwords on all hosts...${RESET}"
    for host in "${available_hosts[@]}"; do
        if ssh -o BatchMode=yes "root@${host}" "rm -f ${PASSWD_FILE}" 2>/dev/null; then
            echo "  Cleared passwords on ${host}"
        else
            echo "  ${RED}Failed to clear passwords on ${host}${RESET}"
        fi
    done
fi

echo ""
echo "Available hosts: ${available_hosts[*]}"
echo ""
echo "Please provide the encryption passwords."
echo "Press [Enter] on an empty line when finished."
echo ""

password_counter=0
successful_hosts=()

while true; do
    ((password_counter++)) || true
    password=""
    
    printf "Password #%d ([Enter] to finish): " "$password_counter"
    
    # Read password character by character, masking with asterisks
    while IFS= read -r -s -n1 char; do
        if [[ -z "$char" ]]; then
            # Enter pressed
            echo ""
            break
        elif [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
            # Backspace handling
            if [[ -n "$password" ]]; then
                password="${password%?}"
                printf '\b \b'
            fi
        else
            password+="$char"
            printf '*'
        fi
    done
    
    # Empty password means we're done
    if [[ -z "$password" ]]; then
        ((password_counter--)) || true
        break
    fi
    
    # Send password to all available hosts
    for host in "${available_hosts[@]}"; do
        # Use printf to avoid password in process list, append to file
        if ssh -o BatchMode=yes "root@${host}" "printf '%s\n' \"\$(cat)\" >> ${PASSWD_FILE}" <<< "$password" 2>/dev/null; then
            # Track successful hosts (avoid duplicates)
            if [[ ! " ${successful_hosts[*]:-} " =~ " ${host} " ]]; then
                successful_hosts+=("$host")
            fi
        else
            echo "${YELLOW}Warning: Failed to store password on ${host}${RESET}"
        fi
    done
done

echo ""

if [[ $password_counter -eq 0 ]]; then
    if [[ "$DO_RESET" == "true" ]]; then
        echo "${GREEN}All passwords cleared. No new passwords added.${RESET}"
    else
        echo "No passwords entered."
    fi
elif [[ ${#successful_hosts[@]} -gt 0 ]]; then
    echo "${GREEN}Successfully stored ${password_counter} password(s) on: ${successful_hosts[*]}${RESET}"
else
    echo "${RED}Failed to store passwords on any host.${RESET}"
    exit 1
fi

# Clear password variable
password=""

echo ""
echo "You can verify with: ssh root@<host> cat ${PASSWD_FILE}"
echo ""
