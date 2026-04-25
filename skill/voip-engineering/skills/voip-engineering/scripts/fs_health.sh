#!/usr/bin/env bash
# fs_health.sh — Snapshot de salud FreeSWITCH
# Uso: ./fs_health.sh

set -euo pipefail

FS_CLI="${FS_CLI:-fs_cli}"
command -v "$FS_CLI" >/dev/null || { echo "fs_cli no encontrado"; exit 1; }

run() {
    echo "--- $1 ---"
    $FS_CLI -x "$1" || echo "(error)"
    echo
}

echo "=== FreeSWITCH Health Snapshot — $(date) ==="
echo

run "status"
run "show channels count"
run "sofia status"
run "sofia status profile internal"
run "sofia status profile external"
run "show registrations"
run "show calls count"

echo "=== fin ==="
