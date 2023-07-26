#!/usr/bin/env bash

# Read hosts from the configuration file
readarray -t provider_hosts < /usr/local/bin/zfs-enc-automount.dev/provider_hosts.conf

passwd_file="/run/zfs_passwords"
available_hosts=()

# Colors for output
green=$(tput setaf 2)
red=$(tput setaf 1)
reset=$(tput sgr0)

echo
# Check each host for ssh availability
for provider_host in "${provider_hosts[@]}"; do
  echo -n "Checking $provider_host ... "
  if ssh -q root@$provider_host exit; then
    echo "${green}OK${reset}"
    available_hosts+=("$provider_host")
  else
    echo "${red}unreachable${reset}"
  fi
done

# If no hosts are available, exit the script
if [ ${#available_hosts[@]} -eq 0 ]; then
  echo "No hosts are reachable. Exiting."
  exit 1
fi
echo
echo "Please provide the list of passwords. When finished, enter an empty line."

password_counter=1
successful_hosts=()

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
  for available_host in "${available_hosts[@]}"; do
    if ssh root@$available_host "echo $password >> $passwd_file"; then
      # Add the host to the successful_hosts array only if it's not already in it
      if [[ ! " ${successful_hosts[@]} " =~ " ${available_host} " ]]; then
        successful_hosts+=("$available_host")
      fi
    fi
  done

  password_counter=$((password_counter+1))
done

echo "Passwords stored on: ${successful_hosts[*]}"
