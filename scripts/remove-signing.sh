#!/bin/bash
# Undoes scripts/setup-signing.sh: removes the OneBuds keychain from the user search list and
# deletes it together with its password file. Other keychains are left untouched.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/signing-common.sh"

remaining=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"; line="${line%\"}"
  [[ -n "$line" && "$line" != "$ONEBUDS_KEYCHAIN" ]] && remaining+=("$line")
done < <(security list-keychains -d user)
if [[ ${#remaining[@]} -eq 0 ]]; then
  echo "ERROR: refusing to set an empty keychain search list." >&2
  exit 1
fi
security list-keychains -d user -s "${remaining[@]}"
[[ -f "$ONEBUDS_KEYCHAIN" ]] && security delete-keychain "$ONEBUDS_KEYCHAIN"
rm -f "$ONEBUDS_KEYCHAIN_PASSWORD_FILE"
echo "Removed. Current user keychain search list:"
security list-keychains -d user
