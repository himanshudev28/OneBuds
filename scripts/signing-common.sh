#!/bin/bash
# Shared signing helpers for OneBuds build scripts. Source this file; do not run it.
#
# macOS remembers a Bluetooth permission grant by the app's code-signing "designated requirement".
# Ad-hoc signatures change on every build (so macOS asks again each time); a fixed certificate
# keeps the requirement stable. scripts/setup-signing.sh creates that certificate.

ONEBUDS_IDENTITY="OneBuds Local Signing"
ONEBUDS_KEYCHAIN="$HOME/Library/Keychains/onebuds-signing.keychain-db"
ONEBUDS_KEYCHAIN_PASSWORD_FILE="$HOME/.config/onebuds/signing-keychain-password"

# Prints the SHA-1 of the OneBuds signing identity, or nothing if it is not set up.
onebuds_identity_hash() {
  [[ -f "$ONEBUDS_KEYCHAIN" && -f "$ONEBUDS_KEYCHAIN_PASSWORD_FILE" ]] || return 0
  security unlock-keychain -p "$(cat "$ONEBUDS_KEYCHAIN_PASSWORD_FILE")" "$ONEBUDS_KEYCHAIN" >/dev/null 2>&1 || return 0
  security find-identity -p codesigning "$ONEBUDS_KEYCHAIN" 2>/dev/null \
    | awk -v name="\"$ONEBUDS_IDENTITY\"" 'index($0, name) && $2 ~ /^[0-9A-F]{40}$/ { print $2; exit }'
}

# onebuds_sign <bundle-or-binary> <identifier>
onebuds_sign() {
  local target="$1" identifier="$2" hash
  hash="$(onebuds_identity_hash)"
  if [[ -n "$hash" ]]; then
    codesign --force --sign "$hash" --identifier "$identifier" --timestamp=none "$target"
    echo "Signed with \"$ONEBUDS_IDENTITY\" ($hash)."
  else
    echo "WARNING: \"$ONEBUDS_IDENTITY\" is not set up; signing ad-hoc." >&2
    echo "         macOS will ask for Bluetooth permission again after every rebuild." >&2
    echo "         Run scripts/setup-signing.sh once to fix this." >&2
    codesign --force --sign - --identifier "$identifier" "$target"
  fi
  codesign --verify --strict "$target"
  echo "Designated requirement: $(codesign -d -r - "$target" 2>&1 | sed -n 's/^designated => //p')"
}
