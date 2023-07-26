#!/usr/bin/env bash

provider_host=$(cat /usr/local/bin/zfs-enc-automount/provider_hosts.conf)
passwd_file="/run/zfs_passwords"

ssh root@$provider_host "rm -f $passwd_file"

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

  # Save the password to the remote file
  ssh root@$provider_host "echo $password >> $passwd_file"

  password_counter=$((password_counter+1))
done

echo "Passwords stored."
