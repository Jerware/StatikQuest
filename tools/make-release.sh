#!/usr/bin/env bash
# Make a clean PC-only local staging archive. No APK, upload or release clearance.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:?usage: tools/make-release.sh <version>}
shift
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$root/tools/make-release.ps1")" -Version "$version" "$@"
