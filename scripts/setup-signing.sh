#!/bin/bash
# One-time setup: creates a local, self-signed code-signing identity "OneBuds Local Signing" in its
# own keychain (~/Library/Keychains/onebuds-signing.keychain-db) and appends that keychain to your
# user keychain search list so codesign can find it. Your login keychain is not modified and no
# certificate is marked as trusted. Undo with scripts/remove-signing.sh.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/signing-common.sh"

add_to_search_list() {
  local current=() line k
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#\"}"; line="${line%\"}"
    [[ -n "$line" ]] && current+=("$line")
  done < <(security list-keychains -d user)
  for k in ${current[@]+"${current[@]}"}; do
    [[ "$k" == "$ONEBUDS_KEYCHAIN" ]] && { echo "Keychain already on the search list."; return 0; }
  done
  security list-keychains -d user -s ${current[@]+"${current[@]}"} "$ONEBUDS_KEYCHAIN"
  echo "Added the OneBuds keychain to the user search list (existing entries kept):"
  security list-keychains -d user
}

if [[ -n "$(onebuds_identity_hash)" ]]; then
  echo "\"$ONEBUDS_IDENTITY\" already exists in $ONEBUDS_KEYCHAIN."
  add_to_search_list
  exit 0
fi
if [[ -e "$ONEBUDS_KEYCHAIN" ]]; then
  echo "ERROR: $ONEBUDS_KEYCHAIN exists but the identity could not be read. Run scripts/remove-signing.sh first." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$(dirname "$ONEBUDS_KEYCHAIN_PASSWORD_FILE")"
chmod 700 "$(dirname "$ONEBUDS_KEYCHAIN_PASSWORD_FILE")"
keychain_password="$(openssl rand -hex 24)"
( umask 077; printf '%s' "$keychain_password" > "$ONEBUDS_KEYCHAIN_PASSWORD_FILE" )
p12_password="$(openssl rand -hex 16)"

cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $ONEBUDS_IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
legacy=()
openssl version | grep -q '^OpenSSL 3' && legacy=(-legacy)
openssl pkcs12 -export ${legacy[@]+"${legacy[@]}"} -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/identity.p12" -passout "pass:$p12_password"

security create-keychain -p "$keychain_password" "$ONEBUDS_KEYCHAIN"
security set-keychain-settings "$ONEBUDS_KEYCHAIN"   # no auto-lock timeout
security unlock-keychain -p "$keychain_password" "$ONEBUDS_KEYCHAIN"
security import "$work/identity.p12" -k "$ONEBUDS_KEYCHAIN" -P "$p12_password" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$ONEBUDS_KEYCHAIN" >/dev/null
add_to_search_list

echo "Created \"$ONEBUDS_IDENTITY\": $(onebuds_identity_hash)"
echo "It is self-signed and untrusted, which is expected: it only gives local builds a stable identity."
