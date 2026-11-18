#!/usr/bin/env bash

set -euo pipefail


print_header() {
    local title="$1"
    printf "\n%s\n%s\n\n" \
        "=== $title ===" \
        "$(printf '=%.0s' $(seq 1 ${#title}+8))"
}

print_item() {
    local indent="  "
    printf "%s- %s\n" "$indent" "$1"
}


print_header "1. Current UID & User"

if [ "$(id -u)" -eq 0 ]; then
    print_item "Running as root – full privileges."
else
    print_item "Running as user '$(whoami)' (UID $(id -u))."
    print_item "Check if this account is in the sudoers file."
fi


print_header "2. Sudo configuration"

if command -v sudo >/dev/null 2>&1; then
    echo
    print_item "Listing allowed sudoers entries for $(whoami):"
    sudo -l -U "$(whoami)" 2>/dev/null | grep -v 'visual' || print_item "    * No explicit sudo permissions."
else
    print_item "sudo command not found – skipping."
fi


exit 0