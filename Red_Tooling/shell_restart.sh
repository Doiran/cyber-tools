#!/usr/bin/env bash

set -euo pipefail

interactive_shells=("bash" zsh" "fish")

CURRENT_USER="$(whoami)"

pids=()
for shell in "${interactive_shells[@]}"; do
    while IFS= read -r pid; do
        if [[ "$pid" -ne $$ ]]; then
            pids+=("$pid")
        fi
    done < <(pgrep -u "$CURRENT_USER" -x "$shell")
done

if [[ "${#pids[@]}" -eq 0 ]]; then
    exit 0
fi

for pid in "${pids[@]}"; do
    cmd_line=$(ps -p "$pid" -o args=)
    user="$(ps -p "$pid" -o user=)"
    shell_name="$(basename "$(ps -p "$pid" -o comm=)")"

    kill -TERM "$pid"
    
    esac
done

echo
wall -n "🍺ᗜˬᗜ Heres a drink for your hard work 🍺ᗜˬᗜ"