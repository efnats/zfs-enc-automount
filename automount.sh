#!/usr/bin/env bash

provider_host=$(cat /usr/local/bin/ProxmoxAutoZFS/provider_hosts.conf)
enc_datasets=$(zfs get -r -H -o name,value keyformat | grep passphrase | awk '{print $1}' | awk '!/vm-/' | awk '!/base/' | xargs)

# Password file location
passwd_file="/run/zfs_passwords"

# Fetch the passwords from the remote server
passwords=$(ssh root@$provider_host cat $passwd_file)
password_array=($passwords)  # Convert the string to array

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
