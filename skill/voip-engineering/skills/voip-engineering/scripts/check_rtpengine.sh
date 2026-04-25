#!/usr/bin/env bash
# check_rtpengine.sh — Health check rápido de RTPEngine
# Uso: ./check_rtpengine.sh

set -euo pipefail

echo "=== RTPEngine Health Check ==="

# 1. Proceso vivo
if ! pgrep -x rtpengine >/dev/null; then
    echo "[FAIL] rtpengine no está corriendo"
    exit 1
fi
echo "[OK] proceso activo"

# 2. ng-protocol port
if ! ss -lun | grep -q ":2223"; then
    echo "[WARN] no escucha en udp/2223"
else
    echo "[OK] ng-protocol port abierto"
fi

# 3. rtpengine-ctl
if command -v rtpengine-ctl >/dev/null; then
    SESSIONS=$(rtpengine-ctl list numsessions 2>/dev/null || echo "ERR")
    echo "[INFO] sesiones activas: $SESSIONS"
fi

# 4. Kernel module
if [ -d /proc/rtpengine/0 ]; then
    KSESSIONS=$(wc -l < /proc/rtpengine/0/list 2>/dev/null || echo 0)
    echo "[OK] kernel module cargado ($KSESSIONS calls in-kernel)"
else
    echo "[WARN] kernel module no detectado (userspace only)"
fi

# 5. Puertos RTP en uso
RTP_USED=$(ss -lun | awk '$5 ~ /:[0-9]+$/ { split($5,a,":"); p=a[length(a)]; if (p>=30000 && p<=40000) print p }' | wc -l)
echo "[INFO] puertos RTP en uso: $RTP_USED"

# 6. Errores recientes en log
LOG=/var/log/rtpengine/rtpengine.log
if [ -r "$LOG" ]; then
    ERRS=$(tail -n 1000 "$LOG" | grep -ciE "error|fail|critical" || true)
    echo "[INFO] errores en últimas 1000 líneas: $ERRS"
fi

echo "=== fin ==="
