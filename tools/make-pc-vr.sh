#!/usr/bin/env bash
# Stage the Windows emulator in pc-vr, preserving personal settings and saves.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$root/tools/make-pc-vr.ps1")" "$@"
