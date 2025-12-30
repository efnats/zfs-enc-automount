#!/usr/bin/env bash
#
# zfs-enc-automount - automount.sh
# Fetch passwords from provider hosts and unlock encrypted ZFS datasets
#

set -euo pipefail

# Configuration
CONFIG_DIR="/opt/zfs-enc-automount"
PASSWD_FILE="/var/run/zfs_passwords"

# Read provider hosts from configuration file
if [[ ! -f "${CONFIG_DIR}/provider_hosts.conf" ]]; then
    echo "ERROR: Configuration file not found: ${CONFIG_DIR}/provider_hosts.conf"
    exit 1
fi

readarray -t provider_hosts < "${CONFIG_DIR}/provider_hosts.conf"

# Get encrypted datasets (excluding VM disks, LXC volumes, and base images)
get_encrypted_datasets() {
    zfs get -r -H -o name,value keyformat | \
        awk '$2 == "passphrase" && !/(vm|subvol)-[0-9]+-disk-/ && !/\/base-[0-9]+/ {print $1}'
}

# Fetch passwords from all reachable provider hosts
fetch_all_passwords() {
    local all_passwords=()
    
    for provider_host in "${provider_hosts[@]}"; do
        # Skip empty lines and comments
        [[ -z "$provider_host" || "$provider_host" =~ ^# ]] && continue
        
        echo "Attempting to fetch passwords from ${provider_host}..." >&2
        
        if passwords=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "root@${provider_host}" "cat ${PASSWD_FILE}" 2>/dev/null); then
            if [[ -n "$passwords" ]]; then
                echo "Passwords fetched from ${provider_host}" >&2
                while IFS= read -r pw; do
                    [[ -n "$pw" ]] && all_passwords+=("$pw")
                done <<< "$passwords"
            else
                echo "No passwords stored on ${provider_host}" >&2
            fi
        else
            echo "Unable to reach ${provider_host}" >&2
        fi
    done
    
    # Deduplicate passwords while preserving order
    if [[ ${#all_passwords[@]} -gt 0 ]]; then
        printf '%s\n' "${all_passwords[@]}" | awk '!seen[$0]++'
    fi
}

# Main execution
echo "=== ZFS Encrypted Dataset Automount ==="
echo ""

# Fetch and deduplicate passwords from all providers
mapfile -t unique_passwords < <(fetch_all_passwords)

if [[ ${#unique_passwords[@]} -eq 0 ]]; then
    echo "ERROR: Could not fetch passwords from any provider host."
    exit 1
fi

echo ""
echo "Collected ${#unique_passwords[@]} unique password(s) from provider hosts"
echo ""

# Get encrypted datasets
enc_datasets=$(get_encrypted_datasets)

if [[ -z "$enc_datasets" ]]; then
    echo "No encrypted datasets found that need unlocking."
    exit 0
fi

# Process each dataset
while IFS= read -r ds; do
    [[ -z "$ds" ]] && continue
    
    # Check if already mounted
    is_mounted=$(zfs get -H -o value mounted "$ds" 2>/dev/null || echo "unknown")
    if [[ "$is_mounted" == "yes" ]]; then
        echo "Dataset ${ds} already mounted. Skipping..."
        continue
    fi
    
    # Check if key is already loaded
    keystatus=$(zfs get -H -o value keystatus "$ds" 2>/dev/null || echo "unknown")
    if [[ "$keystatus" == "available" ]]; then
        echo "Key for ${ds} already loaded. Skipping..."
        continue
    fi
    
    echo "Unlocking dataset: ${ds}"
    
    passwd_index=0
    key_loaded=false
    
    for passwd in "${unique_passwords[@]}"; do
        ((passwd_index++)) || true
        
        # Use printf to avoid password in process list
        if printf '%s' "$passwd" | zfs load-key "$ds" 2>/dev/null; then
            echo "  ✓ Key loaded successfully (password #${passwd_index})"
            key_loaded=true
            break
        fi
    done
    
    if [[ "$key_loaded" == "false" ]]; then
        echo "  ✗ Failed to load key for ${ds} (tried ${passwd_index} passwords)"
    fi
    
done <<< "$enc_datasets"

echo ""
echo "Mounting all datasets..."

if zfs mount -a; then
    echo "=== All datasets mounted successfully ==="
    exit 0
else
    echo "=== Warning: Some datasets may have failed to mount ==="
    exit 1
fi
