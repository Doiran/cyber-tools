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

print_header "3. Group memberships"

printf "  - User groups: %s\n" "$(id -Gn)"

# Look for membership in high‑privilege groups (non‑standard names may vary)
declare -a high_groups=("adm" "wheel" "sudo" "root" "systemd-journal" "docker")
for grp in "${high_groups[@]}"; do
    if groups "$grp" 2>/dev/null | grep -q "$grp"; then
        print_item "  * Member of privileged group: $grp"
    fi
done


print_header "4. Potential SUID / world‑writable shell paths"

echo
print_item "Files owned by root with the set‑uid bit set:"
find / -path /proc -prune -o \
     -type f -perm -4000 -user root -exec ls -ld {} + 2>/dev/null | head -n 20

print_item "Root‑owned, world‑writable files (SHELLS):"
find / -path /proc -prune -o \
     -type f -perm +022 -user root -exec ls -ld {} + 2>/dev/null | egrep -i '\.(sh|bash|bashrc|csh|zsh|fish|ksh)$' | head -n 20

print_item "World‑writable directories that may allow compiles:"
find / -path /proc -prune -o \
     -type d -perm +022 -exec ls -ld {} + 2>/dev/null | head -n 20


print_header "5. Known privilege‑escalation helper checks"

# a) Programs that might have known exploits (update this list based on current CVEs)
declare -a risky_cmds=("vim" "emacs" "less" "top" "ps" "sh" "bash" "dash" "zsh")
print_item "Checking for programs with known SUID fixes or CVE warnings:"
for prog in "${risky_cmds[@]}"; do
    if [ -x "$(command -v $prog 2>/dev/null)" ]; then
        print_item "  * $prog found: $(command -v $prog)"
    fi
done


echo
print_item "Sudo dynamic plugins (SUDOERS.D):"
ls -l /etc/sudoers.d/ 2>/dev/null || print_item "    * No sudoers.d directory."

printf "\n   • If you see any of the above items listed in a "
printf "warning area, consider:\n"
printf "     - Removing SUID root binaries unless absolutely needed.\n"
printf "     - Tightening world‑writable directories.\n"
printf "     - Reviewing sudoers entries.\n"
printf "     - Checking SELinux/AppArmor policies.\n\n"
printf "   • For deeper analysis, run:\n"
printf "     * auditd/OSSEC logs\n"
printf "     * static analysis of kernel modules\n"
printf "     * automated tools such as 'linPEAS'.\n"

exit 0