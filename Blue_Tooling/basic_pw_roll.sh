#!/usr/bin/env bash

# Must be run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

NEW_PASSWORD="YourNewPasswordHere"

# Get list of regular users (UID >= 1000, excluding nologin/system accounts)
# Adjust the UID threshold if your system uses a different convention
USERS=$(awk -F: '($3>=1000)&&($1!="nobody"){print $1}' /etc/passwd)

for user in $USERS; do
    echo "${user}:${NEW_PASSWORD}" | chpasswd
    if [[ $? -eq 0 ]]; then
        echo "Password changed for $user"
    else
        echo "Failed to change password for $user"
    fi
done

#after running, remove script itself with: shred -u basic_pw_roll.sh