#!/usr/bin/env bash

passwd_file="/run/zfs_passwords"

readarray -t provider_hosts < /usr/local/bin/zfs-enc-automount.dev/provider_hosts.conf

for provider_host in "${provider_hosts[@]}"; do
    echo -n "Checking connection to $provider_host... "
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 root@$provider_host true 2>/dev/null; then
        echo -e "\e[31mError: Can't connect or login to $provider_host\e[0m"
        exit 1
    else
        echo -e "\e[32mOK\e[0m"
    fi
    ssh root@$provider_host "rm -f $passwd_file"
done

echo "Please provide the list of passwords. When finished, enter an empty line."

password_counter=1

while true; do
  password=""
  echo -n "Password #$password_counter ([enter] to finish): "

  # Read characters one by one and print '*' for each character
  while IFS= read -r -s -n1 char; do
    if [[ -z $char ]]; then
      # If 'Enter' is pressed, exit the loop
      echo
      break
    else
      # Append the input to the variable
      password+=$char
      echo -n '*'
    fi
  done

  # If no password was entered (i.e., 'Enter' was pressed immediately), exit the loop
  if [[ -z $password ]]; then
    break
  fi

  # Save the password to the remote file on each host
  for provider_host in "${provider_hosts[@]}"; do
      ssh root@$provider_host "echo $password >> $passwd_file"
  done

  password_counter=$((password_counter+1))
done

echo "Passwords stored."
