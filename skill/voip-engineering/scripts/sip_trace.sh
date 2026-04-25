#!/usr/bin/env bash
# sip_trace.sh — Captura SIP rápida con sngrep
# Uso: ./sip_trace.sh [interface] [filter]
#
# Ejemplos:
#   ./sip_trace.sh                    # any interface, todo SIP
#   ./sip_trace.sh eth0               # solo eth0
#   ./sip_trace.sh eth0 "host 1.2.3.4"  # con filtro BPF

set -euo pipefail

IFACE="${1:-any}"
FILTER="${2:-port 5060 or port 5061}"
OUT="/tmp/sip-$(date +%Y%m%d-%H%M%S).pcap"

command -v sngrep >/dev/null 2>&1 || { echo "sngrep no instalado"; exit 1; }

echo "Capturando en $IFACE — filtro: $FILTER"
echo "Output: $OUT"
echo "Ctrl-C para detener"

sngrep -d "$IFACE" -O "$OUT" "$FILTER"

echo "Captura guardada en $OUT"
echo "Reproducir con: sngrep -I $OUT"
