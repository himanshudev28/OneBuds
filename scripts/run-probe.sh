#!/bin/bash
# Runs the read-only Phase B probe through LaunchServices (so the Bluetooth permission belongs to
# "OneBuds Probe", not to your terminal) and prints its report. Extra arguments go to the probe,
# e.g. scripts/run-probe.sh --read-standard. Reports are written to Diagnostics/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/OneBuds Probe.app"
out="$root/Diagnostics"

[[ -d "$app" ]] || "$root/scripts/build-probe.sh"
mkdir -p "$out"
log="$out/last-run.log"
progress="$out/last-run.progress.log"
# `open --stdout` fails with LaunchServices error -10810 if the file already exists.
rm -f "$log" "$progress"

echo "Running OneBuds Probe (read-only). If macOS asks for Bluetooth access, click Allow."
open -W -n "$app" --stdout "$log" --stderr "$progress" --args --out-dir "$out" "$@"
cat "$progress" "$log"
