!/usr/bin/env bash

set -euo pipefail

TARGET_FILE="/etc/bash.bashrc"

if [ ! -e "$TARGET_FILE" ]; then
    echo "✖  $TARGET_FILE does not exist – this script is intended for a system that uses /etc/bash.bashrc (Debian/Ubuntu style)." >&2
    exit 1
fi


WRAPPER_BLOCK=$(cat <<'EOF'

ls()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
cd()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
rm()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
cat() { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
cp()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
mv()  { echo "ദ്ദി ᗜˬᗜ✧ Good try! ദ്ദി ᗜˬᗜ✧"; }
EOF
)

if grep -Fq "$(printf '%s' "$WRAPPER_BLOCK" | head -n1)" "$TARGET_FILE"; then
    exit 0
fi

# ------------------------------------------------------------
printf '%s\n' "$WRAPPER_BLOCK" | sudo tee -a "$TARGET_FILE" > /dev/null