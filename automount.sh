#!/usr/bin/env bash

# Read hosts from the configuration file
readarray -t provider_hosts < /usr/local/bin/zfs-enc-automount/provider_hosts.conf

# Get encrypted datasets
enc_datasets=$(zfs get -r -H -o name,value keyformat | grep passphrase | awk '{print $1}' | awk '!/vm-/' | awk '!/base/')

# Password file location
passwd_file="/run/zfs_passwords"

# Iterate over provider hosts until passwords are successfully fetched
for provider_host in "${provider_hosts[@]}"; do
  echo "Attempting to fetch passwords from $provider_host..."
  passwords=$(ssh root@$provider_host cat $passwd_file 2>/dev/null)
  if [[ -n "$passwords" ]]; then
    echo "Passwords fetched from $provider_host"
    break
  else
    echo "Unable to fetch passwords from $provider_host"
  fi
done

# Exit if no passwords fetched
if [[ -z "$passwords" ]]; then
  echo "Could not fetch passwords from any provider host. Exiting."
  exit 1
fi

# Convert the passwords string to an array
password_array=($passwords)

for ds in $enc_datasets; do
  # Check if the dataset is already mounted
  is_mounted=$(zfs list -H -o mounted $ds)
  if [ "$is_mounted" = "yes" ]; then
    echo "Dataset $ds already mounted. Skipping..."
    continue
  fi

  passwd_index=0
  for passwd in "${password_array[@]}"; do
    echo "Trying password #$(($passwd_index+1)) for dataset $ds"
    echo $passwd | zfs load-key $ds 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "Password #$(($passwd_index+1)) successfully loaded key for dataset $ds"
      break
    fi
    passwd_index=$((passwd_index+1))
  done
done

zfs mount -a && echo "All datasets mounted successfully"
exit $?
