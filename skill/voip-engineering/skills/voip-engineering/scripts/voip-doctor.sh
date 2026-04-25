#!/usr/bin/env bash
# voip-doctor.sh — Diagnóstico end-to-end Kamailio + FreeSWITCH + RTPEngine
#
# Modos:
#   triage   — snapshot rápido (60s) por stdout + reporte mínimo
#   capture  — captura completa con pcap, logs y HTML SVG flow
#   monitor  — loop continuo con alertas a syslog/stderr
#
# Targets soportados:
#   Apolo SBC (Debian 12)        — kamailio + freeswitch + rtpengine bare metal
#   Apolo IVR 119 (RHEL 8)       — mismo stack, distinto distro
#   Auto-detecta /etc/os-release y rutas de logs/binaries
#
# Uso:
#   ./voip-doctor.sh triage
#   ./voip-doctor.sh capture --duration 300 --iface eth0
#   ./voip-doctor.sh monitor --interval 30 --threshold-cps 50
#
# Autor: Apolo Next — para Jesús Bazán
# Licencia: uso interno

set -uo pipefail

# ============================================================
# CONFIG
# ============================================================
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="voip-doctor"

# Defaults (override por flags o env)
MODE="${MODE:-triage}"
DURATION="${DURATION:-60}"
IFACE="${IFACE:-any}"
INTERVAL="${INTERVAL:-30}"
OUT_BASE="${OUT_BASE:-/var/tmp/voip-doctor}"
SIP_PORTS="${SIP_PORTS:-5060,5061,5080}"
RTP_PORT_MIN="${RTP_PORT_MIN:-30000}"
RTP_PORT_MAX="${RTP_PORT_MAX:-40000}"
THRESHOLD_CPS="${THRESHOLD_CPS:-50}"
THRESHOLD_RTP_LOSS_PCT="${THRESHOLD_RTP_LOSS_PCT:-2}"
THRESHOLD_REGS_DROP_PCT="${THRESHOLD_REGS_DROP_PCT:-10}"
KAMCMD="${KAMCMD:-kamcmd}"
FS_CLI="${FS_CLI:-fs_cli}"
RTPENGINE_CTL="${RTPENGINE_CTL:-rtpengine-ctl}"
SNGREP="${SNGREP:-sngrep}"

# Componentes presentes (poblados por detect_stack)
HAS_KAMAILIO=0
HAS_FREESWITCH=0
HAS_RTPENGINE=0
DISTRO=""
DISTRO_FAMILY=""
KAM_LOG=""
FS_LOG=""
RTP_LOG=""

# Run state
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
OUT_DIR=""
REPORT_TXT=""
REPORT_HTML=""
PCAP_FILE=""
EVENTS_FILE=""

# Métricas (poblados por collect_*)
declare -A METRICS=()

# Colores (deshabilitados si no tty)
if [[ -t 1 ]]; then
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'
    C_BLU=$'\e[34m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
    C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_DIM=""; C_RST=""
fi

# ============================================================
# UTIL
# ============================================================
log() {
    local lvl="$1"; shift
    local color="$C_RST"
    case "$lvl" in
        ERR)  color="$C_RED" ;;
        WARN) color="$C_YLW" ;;
        OK)   color="$C_GRN" ;;
        INFO) color="$C_BLU" ;;
    esac
    printf '%s[%s]%s %s\n' "$color" "$lvl" "$C_RST" "$*"
}

die() { log ERR "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Ejecuta cmd con timeout, captura stdout+stderr, no falla el script
safe_run() {
    local timeout_sec="$1"; shift
    timeout --foreground "${timeout_sec}s" "$@" 2>&1 || true
}

usage() {
    cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION — diagnóstico end-to-end VoIP

USO:
    $0 <modo> [opciones]

MODOS:
    triage              Snapshot rápido (~60s), salida por stdout + reporte texto
    capture             Captura completa: pcap + logs + reporte HTML con SVG
    monitor             Loop continuo con alertas (Ctrl-C para salir)

OPCIONES:
    --duration SEC      Duración captura/monitor (default: $DURATION)
    --iface IFACE       Interfaz de red (default: $IFACE)
    --interval SEC      Intervalo en modo monitor (default: $INTERVAL)
    --out-base DIR      Directorio base para outputs (default: $OUT_BASE)
    --sip-ports LIST    Puertos SIP coma-sep (default: $SIP_PORTS)
    --rtp-min PORT      RTP min port (default: $RTP_PORT_MIN)
    --rtp-max PORT      RTP max port (default: $RTP_PORT_MAX)
    --threshold-cps N   Alerta si CPS supera N (default: $THRESHOLD_CPS)
    -h, --help          Esta ayuda

EJEMPLOS:
    $0 triage
    $0 capture --duration 300 --iface eth0
    $0 monitor --interval 15

ENV VARS (override de comandos):
    KAMCMD, FS_CLI, RTPENGINE_CTL, SNGREP

EOF
}

parse_args() {
    [[ $# -lt 1 ]] && { usage; exit 1; }

    case "$1" in
        triage|capture|monitor) MODE="$1"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Modo inválido: $1 (usa: triage|capture|monitor)" ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --duration)        DURATION="$2"; shift 2 ;;
            --iface)           IFACE="$2"; shift 2 ;;
            --interval)        INTERVAL="$2"; shift 2 ;;
            --out-base)        OUT_BASE="$2"; shift 2 ;;
            --sip-ports)       SIP_PORTS="$2"; shift 2 ;;
            --rtp-min)         RTP_PORT_MIN="$2"; shift 2 ;;
            --rtp-max)         RTP_PORT_MAX="$2"; shift 2 ;;
            --threshold-cps)   THRESHOLD_CPS="$2"; shift 2 ;;
            -h|--help)         usage; exit 0 ;;
            *) die "Opción desconocida: $1" ;;
        esac
    done
}

# ============================================================
# DETECCIÓN DE STACK
# ============================================================
detect_stack() {
    # Distro
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="${PRETTY_NAME:-unknown}"
        case "${ID_LIKE:-$ID}" in
            *rhel*|*fedora*|*centos*) DISTRO_FAMILY="rhel" ;;
            *debian*|*ubuntu*)        DISTRO_FAMILY="debian" ;;
            *)                        DISTRO_FAMILY="unknown" ;;
        esac
    fi

    # Kamailio
    if pgrep -x kamailio >/dev/null 2>&1 || have "$KAMCMD"; then
        HAS_KAMAILIO=1
        for p in /var/log/kamailio/kamailio.log /var/log/kamailio.log /var/log/syslog; do
            [[ -r "$p" ]] && { KAM_LOG="$p"; break; }
        done
    fi

    # FreeSWITCH
    if pgrep -x freeswitch >/dev/null 2>&1 || have "$FS_CLI"; then
        HAS_FREESWITCH=1
        for p in /var/log/freeswitch/freeswitch.log /usr/local/freeswitch/log/freeswitch.log; do
            [[ -r "$p" ]] && { FS_LOG="$p"; break; }
        done
    fi

    # RTPEngine
    if pgrep -x rtpengine >/dev/null 2>&1 || have "$RTPENGINE_CTL"; then
        HAS_RTPENGINE=1
        for p in /var/log/rtpengine/rtpengine.log /var/log/ngcp/rtpengine.log; do
            [[ -r "$p" ]] && { RTP_LOG="$p"; break; }
        done
    fi
}

print_stack_summary() {
    log INFO "Distro: $DISTRO (familia: $DISTRO_FAMILY)"
    log INFO "Componentes detectados:"
    [[ $HAS_KAMAILIO   -eq 1 ]] && log OK   "  Kamailio    ✓ (log: ${KAM_LOG:-no encontrado})" || log WARN "  Kamailio    ✗"
    [[ $HAS_FREESWITCH -eq 1 ]] && log OK   "  FreeSWITCH  ✓ (log: ${FS_LOG:-no encontrado})" || log WARN "  FreeSWITCH  ✗"
    [[ $HAS_RTPENGINE  -eq 1 ]] && log OK   "  RTPEngine   ✓ (log: ${RTP_LOG:-no encontrado})" || log WARN "  RTPEngine   ✗"
}

# ============================================================
# COLECTORES
# ============================================================
collect_kamailio() {
    [[ $HAS_KAMAILIO -ne 1 ]] && return 0
    local section="$1"  # archivo destino

    {
        echo "=== Kamailio ==="
        echo "## core.uptime"
        safe_run 5 "$KAMCMD" core.uptime
        echo
        echo "## tm.stats"
        safe_run 5 "$KAMCMD" tm.stats
        echo
        echo "## sl.stats"
        safe_run 5 "$KAMCMD" sl.stats
        echo
        echo "## dispatcher.list"
        safe_run 5 "$KAMCMD" dispatcher.list
        echo
        echo "## ul.dump (registrations summary)"
        safe_run 10 "$KAMCMD" ul.dump | head -200
        echo
        echo "## htable list (call counters)"
        safe_run 5 "$KAMCMD" htable.listTables
        echo
        echo "## permissions.addressDump"
        safe_run 5 "$KAMCMD" permissions.addressDump | head -50
        echo
    } >> "$section"

    # Métricas extraíbles
    local stats
    stats=$(safe_run 5 "$KAMCMD" tm.stats)
    local current_tm
    current_tm=$(echo "$stats" | awk -F: '/current/ {gsub(/ /,""); print $2; exit}')
    METRICS[kam_current_tm]="${current_tm:-0}"

    local uptime_s
    uptime_s=$(safe_run 5 "$KAMCMD" core.uptime | awk -F: '/uptime/ {gsub(/ /,""); print $2; exit}')
    METRICS[kam_uptime]="${uptime_s:-0}"
}

collect_freeswitch() {
    [[ $HAS_FREESWITCH -ne 1 ]] && return 0
    local section="$1"

    {
        echo "=== FreeSWITCH ==="
        echo "## status"
        safe_run 5 "$FS_CLI" -x "status"
        echo
        echo "## show channels count"
        safe_run 5 "$FS_CLI" -x "show channels count"
        echo
        echo "## sofia status"
        safe_run 5 "$FS_CLI" -x "sofia status"
        echo
        echo "## show registrations count"
        safe_run 5 "$FS_CLI" -x "show registrations count"
        echo
        echo "## show calls count"
        safe_run 5 "$FS_CLI" -x "show calls count"
        echo
        echo "## global_getvar hostname"
        safe_run 3 "$FS_CLI" -x "global_getvar hostname"
        echo
    } >> "$section"

    # Métricas
    local channels
    channels=$(safe_run 5 "$FS_CLI" -x "show channels count" | grep -oE '^[0-9]+' | head -1)
    METRICS[fs_channels]="${channels:-0}"

    local registrations
    registrations=$(safe_run 5 "$FS_CLI" -x "show registrations count" | grep -oE '^[0-9]+' | head -1)
    METRICS[fs_registrations]="${registrations:-0}"

    local calls
    calls=$(safe_run 5 "$FS_CLI" -x "show calls count" | grep -oE '^[0-9]+' | head -1)
    METRICS[fs_calls]="${calls:-0}"
}

collect_rtpengine() {
    [[ $HAS_RTPENGINE -ne 1 ]] && return 0
    local section="$1"

    {
        echo "=== RTPEngine ==="
        echo "## list numsessions"
        safe_run 5 "$RTPENGINE_CTL" list numsessions
        echo
        echo "## list totals"
        safe_run 5 "$RTPENGINE_CTL" list totals
        echo
        echo "## list sessions (top 20)"
        safe_run 5 "$RTPENGINE_CTL" list sessions | head -50
        echo
        echo "## list maxopenfiles"
        safe_run 5 "$RTPENGINE_CTL" list maxopenfiles
        echo
        echo "## list timeout"
        safe_run 3 "$RTPENGINE_CTL" list timeout
        echo

        if [[ -d /proc/rtpengine/0 ]]; then
            echo "## /proc/rtpengine/0 (kernel module)"
            echo "in-kernel sessions: $(wc -l < /proc/rtpengine/0/list 2>/dev/null || echo N/A)"
            [[ -r /proc/rtpengine/0/control ]] && echo "control interface: presente"
            echo
        else
            echo "## kernel module: NO cargado (userspace only)"
            echo
        fi

        echo "## puertos RTP en uso (rango $RTP_PORT_MIN-$RTP_PORT_MAX)"
        ss -lun 2>/dev/null | awk -v min="$RTP_PORT_MIN" -v max="$RTP_PORT_MAX" '
            { n=split($5,a,":"); p=a[n]+0; if (p>=min && p<=max) c++ }
            END { print c+0 " puertos en uso" }'
        echo
    } >> "$section"

    # Métricas
    local sessions
    sessions=$(safe_run 5 "$RTPENGINE_CTL" list numsessions | grep -oE 'Currently active sessions[^0-9]*[0-9]+' | grep -oE '[0-9]+$')
    METRICS[rtp_sessions]="${sessions:-0}"

    local rtp_used
    rtp_used=$(ss -lun 2>/dev/null | awk -v min="$RTP_PORT_MIN" -v max="$RTP_PORT_MAX" \
               '{ n=split($5,a,":"); p=a[n]+0; if (p>=min && p<=max) c++ } END { print c+0 }')
    METRICS[rtp_ports_used]="${rtp_used:-0}"
}

collect_system() {
    local section="$1"

    {
        echo "=== Sistema ==="
        echo "## uname"
        uname -a
        echo
        echo "## uptime"
        uptime
        echo
        echo "## load + memoria"
        free -h
        echo
        echo "## conexiones SIP/RTP en stack TCP/UDP"
        ss -ltun 2>/dev/null | grep -E ':5060|:5061|:5080|:8021|:2223' || echo "(ningún puerto VoIP escuchando)"
        echo
        echo "## firewall (resumen)"
        if have firewall-cmd; then
            safe_run 3 firewall-cmd --list-ports
        elif have ufw; then
            safe_run 3 ufw status
        elif have iptables; then
            safe_run 3 iptables -L -n | head -20
        fi
        echo
        echo "## errores recientes en journalctl (últimos 50, kamailio/freeswitch/rtpengine)"
        if have journalctl; then
            safe_run 5 journalctl -u kamailio -u freeswitch -u rtpengine \
                --since "10 min ago" -p err --no-pager 2>/dev/null | tail -50
        fi
        echo
    } >> "$section"

    METRICS[load_1m]=$(awk '{print $1}' /proc/loadavg)
    METRICS[mem_avail_kb]=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
}

collect_logs_tail() {
    local section="$1"
    local lines="${2:-100}"

    {
        echo "=== Tail de logs (últimas $lines líneas con errores) ==="
        for log in "$KAM_LOG" "$FS_LOG" "$RTP_LOG"; do
            [[ -z "$log" || ! -r "$log" ]] && continue
            echo "## $log"
            tail -n 2000 "$log" 2>/dev/null \
                | grep -iE 'error|critical|fail|warning' \
                | tail -n "$lines"
            echo
        done
    } >> "$section"
}

# ============================================================
# CAPTURA SIP CON TSHARK/TCPDUMP
# ============================================================
capture_pcap() {
    local pcap_file="$1"
    local duration="$2"
    local iface="$3"

    local sip_filter
    # Construir filtro BPF para SIP_PORTS
    IFS=',' read -ra ports <<< "$SIP_PORTS"
    local sip_parts=()
    for p in "${ports[@]}"; do sip_parts+=("port $p"); done
    local sip_expr
    sip_expr=$(IFS=' or '; echo "${sip_parts[*]}")

    local bpf="($sip_expr) or (udp portrange ${RTP_PORT_MIN}-${RTP_PORT_MAX})"

    log INFO "Captura pcap: iface=$iface, duración=${duration}s, filtro: $bpf"

    if have tcpdump; then
        timeout "${duration}s" tcpdump -i "$iface" -s 0 -w "$pcap_file" "$bpf" 2>/dev/null &
        local pid=$!
        wait "$pid" 2>/dev/null || true
    elif have tshark; then
        timeout "${duration}s" tshark -i "$iface" -w "$pcap_file" -f "$bpf" >/dev/null 2>&1 &
        wait $! 2>/dev/null || true
    else
        log WARN "ni tcpdump ni tshark instalados — sin pcap"
        return 1
    fi

    if [[ -s "$pcap_file" ]]; then
        local size
        size=$(du -h "$pcap_file" | awk '{print $1}')
        log OK "pcap guardado: $pcap_file ($size)"
        METRICS[pcap_size]="$size"
        METRICS[pcap_file]="$pcap_file"
        return 0
    else
        log WARN "pcap vacío o no generado"
        return 1
    fi
}

# Extrae mensajes SIP del pcap usando tshark, formato simplificado
extract_sip_flow() {
    local pcap="$1"
    local out="$2"

    [[ ! -s "$pcap" ]] && return 1
    have tshark || { log WARN "tshark no disponible, no se extrae flow"; return 1; }

    log INFO "Extrayendo flow SIP de $pcap..."

    tshark -r "$pcap" -Y "sip" \
        -T fields \
        -e frame.time_epoch \
        -e ip.src -e ip.dst \
        -e udp.srcport -e udp.dstport \
        -e sip.Method -e sip.Status-Code -e sip.CSeq.method \
        -e sip.Call-ID -e sip.from.user -e sip.to.user \
        -E separator='|' 2>/dev/null > "$out" || true

    local nlines
    nlines=$(wc -l < "$out" 2>/dev/null || echo 0)
    log INFO "$nlines mensajes SIP extraídos"
    METRICS[sip_messages]="$nlines"
}

# ============================================================
# VERIFICACIÓN DE PUERTOS / CONECTIVIDAD
# ============================================================
check_ports() {
    local section="$1"
    {
        echo "=== Verificación de puertos ==="
        IFS=',' read -ra ports <<< "$SIP_PORTS"
        for p in "${ports[@]}"; do
            if ss -lun 2>/dev/null | grep -q ":$p\b" || ss -lt 2>/dev/null | grep -q ":$p\b"; then
                echo "[OK]   puerto $p escuchando"
            else
                echo "[WARN] puerto $p NO escuchando"
            fi
        done
        if ss -lun 2>/dev/null | grep -q ":2223\b"; then
            echo "[OK]   ng-protocol RTPEngine udp/2223"
        else
            [[ $HAS_RTPENGINE -eq 1 ]] && echo "[WARN] ng-protocol udp/2223 NO escuchando (RTPEngine activo)"
        fi
        if ss -lt 2>/dev/null | grep -q ":8021\b"; then
            echo "[OK]   ESL FreeSWITCH tcp/8021"
        else
            [[ $HAS_FREESWITCH -eq 1 ]] && echo "[WARN] ESL tcp/8021 NO escuchando (FS activo)"
        fi
        echo
    } >> "$section"
}

# ============================================================
# REPORTE TXT
# ============================================================
build_txt_report() {
    local report="$1"
    local mode="$2"

    {
        echo "================================================================"
        echo "  $SCRIPT_NAME v$SCRIPT_VERSION — modo: $mode"
        echo "  Run ID: $RUN_ID"
        echo "  Host:   $(hostname)"
        echo "  Fecha:  $(date -Is)"
        echo "  Distro: $DISTRO"
        echo "================================================================"
        echo
    } > "$report"

    check_ports "$report"
    collect_system "$report"
    collect_kamailio "$report"
    collect_freeswitch "$report"
    collect_rtpengine "$report"
    collect_logs_tail "$report" 50

    {
        echo "=== Resumen métricas ==="
        for k in "${!METRICS[@]}"; do
            printf "  %-25s %s\n" "$k:" "${METRICS[$k]}"
        done | sort
        echo
        echo "=== Veredicto ==="
        evaluate_health
        echo
    } >> "$report"
}

# Devuelve diagnóstico simple según métricas
evaluate_health() {
    local issues=()

    if [[ $HAS_KAMAILIO -eq 1 && "${METRICS[kam_uptime]:-0}" -lt 60 ]]; then
        issues+=("Kamailio uptime <60s — posible reinicio reciente")
    fi
    if [[ $HAS_FREESWITCH -eq 1 && "${METRICS[fs_calls]:-0}" -gt $THRESHOLD_CPS ]]; then
        issues+=("FreeSWITCH calls=${METRICS[fs_calls]} supera umbral $THRESHOLD_CPS")
    fi
    if [[ $HAS_RTPENGINE -eq 1 && "${METRICS[rtp_ports_used]:-0}" -gt $((RTP_PORT_MAX - RTP_PORT_MIN - 100)) ]]; then
        issues+=("Pool de puertos RTP casi agotado: ${METRICS[rtp_ports_used]} en uso")
    fi
    if (( $(awk -v l="${METRICS[load_1m]:-0}" 'BEGIN{print (l>4.0)}') )); then
        issues+=("Load 1m=${METRICS[load_1m]} elevado")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "  [OK] Sin alertas detectadas en thresholds básicos"
    else
        for i in "${issues[@]}"; do echo "  [WARN] $i"; done
    fi
}

# ============================================================
# REPORTE HTML CON SVG FLOW
# ============================================================
build_html_report() {
    local html="$1"
    local txt="$2"
    local sip_flow_file="${3:-}"

    local svg_flow=""
    [[ -n "$sip_flow_file" && -s "$sip_flow_file" ]] && svg_flow=$(generate_svg_flow "$sip_flow_file")

    local svg_metrics
    svg_metrics=$(generate_svg_metrics)

    local txt_escaped
    txt_escaped=$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$txt")

    cat > "$html" <<HTML
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>VoIP Doctor — $RUN_ID</title>
<style>
  :root {
    --bg: #0d1117; --panel: #161b22; --border: #30363d;
    --fg: #c9d1d9; --muted: #8b949e;
    --ok: #3fb950; --warn: #d29922; --err: #f85149;
    --accent: #58a6ff;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 24px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    background: var(--bg); color: var(--fg); line-height: 1.5;
  }
  h1 { color: var(--accent); border-bottom: 2px solid var(--accent); padding-bottom: 8px; }
  h2 { color: var(--accent); margin-top: 32px; }
  .meta { background: var(--panel); border: 1px solid var(--border);
          padding: 12px 16px; border-radius: 6px; margin: 16px 0; }
  .meta dt { color: var(--muted); display: inline-block; min-width: 100px; }
  .meta dd { display: inline; margin: 0; }
  .meta div { margin: 4px 0; }
  .panel { background: var(--panel); border: 1px solid var(--border);
           border-radius: 6px; padding: 16px; margin: 12px 0; overflow-x: auto; }
  pre { margin: 0; white-space: pre-wrap; word-break: break-word; font-size: 13px; }
  .ok   { color: var(--ok); font-weight: 600; }
  .warn { color: var(--warn); font-weight: 600; }
  .err  { color: var(--err); font-weight: 600; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px,1fr));
          gap: 12px; margin: 12px 0; }
  .metric { background: var(--panel); border: 1px solid var(--border);
            padding: 12px; border-radius: 6px; }
  .metric .lbl { color: var(--muted); font-size: 11px; text-transform: uppercase; }
  .metric .val { color: var(--accent); font-size: 22px; font-weight: 700; margin-top: 4px; }
  svg { background: var(--panel); border: 1px solid var(--border);
        border-radius: 6px; max-width: 100%; height: auto; }
  details { margin: 12px 0; }
  summary { cursor: pointer; color: var(--accent); padding: 8px;
            background: var(--panel); border: 1px solid var(--border); border-radius: 6px; }
  summary:hover { border-color: var(--accent); }
  .footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid var(--border);
            color: var(--muted); font-size: 12px; }
</style>
</head>
<body>

<h1>🩺 VoIP Doctor — Diagnóstico End-to-End</h1>

<div class="meta">
  <div><dt>Run ID:</dt><dd>$RUN_ID</dd></div>
  <div><dt>Host:</dt><dd>$(hostname)</dd></div>
  <div><dt>Fecha:</dt><dd>$(date -Is)</dd></div>
  <div><dt>Distro:</dt><dd>$DISTRO</dd></div>
  <div><dt>Modo:</dt><dd>$MODE</dd></div>
  <div><dt>Duración:</dt><dd>${DURATION}s</dd></div>
</div>

<h2>📊 Métricas clave</h2>
<div class="grid">
HTML

    # Métricas como cards
    for k in fs_channels fs_calls fs_registrations rtp_sessions rtp_ports_used kam_current_tm load_1m sip_messages; do
        local v="${METRICS[$k]:-N/A}"
        cat >> "$html" <<HTML
  <div class="metric">
    <div class="lbl">$k</div>
    <div class="val">$v</div>
  </div>
HTML
    done

    cat >> "$html" <<HTML
</div>

<h2>🔧 Stack detectado</h2>
<div class="panel">
<pre>
HTML
    [[ $HAS_KAMAILIO   -eq 1 ]] && echo "<span class='ok'>✓</span> Kamailio    — log: ${KAM_LOG:-(no encontrado)}" >> "$html" \
                                || echo "<span class='warn'>✗</span> Kamailio    — no detectado" >> "$html"
    [[ $HAS_FREESWITCH -eq 1 ]] && echo "<span class='ok'>✓</span> FreeSWITCH  — log: ${FS_LOG:-(no encontrado)}" >> "$html" \
                                || echo "<span class='warn'>✗</span> FreeSWITCH  — no detectado" >> "$html"
    [[ $HAS_RTPENGINE  -eq 1 ]] && echo "<span class='ok'>✓</span> RTPEngine   — log: ${RTP_LOG:-(no encontrado)}" >> "$html" \
                                || echo "<span class='warn'>✗</span> RTPEngine   — no detectado" >> "$html"

    cat >> "$html" <<HTML
</pre>
</div>

<h2>📈 Visualización de carga</h2>
$svg_metrics
HTML

    if [[ -n "$svg_flow" ]]; then
        cat >> "$html" <<HTML

<h2>📞 Flow SIP capturado</h2>
<p style="color: var(--muted)">Primeros mensajes SIP del pcap. Click en flecha para ver detalles.</p>
$svg_flow
HTML
    fi

    cat >> "$html" <<HTML

<h2>📋 Reporte completo</h2>
<details open>
<summary>Ver reporte de texto completo</summary>
<div class="panel">
<pre>$txt_escaped</pre>
</div>
</details>

<div class="footer">
  Generado por $SCRIPT_NAME v$SCRIPT_VERSION — Apolo Next S.A.C.<br>
  Archivos en: $OUT_DIR
</div>

</body>
</html>
HTML

    log OK "HTML report: $html"
}

# Genera SVG con barras de métricas principales
generate_svg_metrics() {
    local fs_calls="${METRICS[fs_calls]:-0}"
    local fs_chans="${METRICS[fs_channels]:-0}"
    local rtp_sess="${METRICS[rtp_sessions]:-0}"
    local rtp_pool=$((RTP_PORT_MAX - RTP_PORT_MIN))
    local rtp_used="${METRICS[rtp_ports_used]:-0}"
    local rtp_pct=$((rtp_pool > 0 ? rtp_used * 100 / rtp_pool : 0))

    cat <<SVG
<svg viewBox="0 0 700 280" xmlns="http://www.w3.org/2000/svg">
  <style>
    .lbl { fill: #8b949e; font: 12px ui-monospace, monospace; }
    .val { fill: #58a6ff; font: bold 16px ui-monospace, monospace; }
    .bar-bg { fill: #30363d; }
    .bar-ok { fill: #3fb950; }
    .bar-warn { fill: #d29922; }
    .bar-err { fill: #f85149; }
    .axis { stroke: #30363d; stroke-width: 1; }
    .title { fill: #c9d1d9; font: bold 14px ui-monospace, monospace; }
  </style>

  <text x="20" y="25" class="title">Distribución de carga actual</text>

  <!-- FS Calls -->
  <text x="20" y="65" class="lbl">FS calls</text>
  <rect x="120" y="50" width="500" height="20" class="bar-bg" rx="3"/>
  <rect x="120" y="50" width="$(( fs_calls > 500 ? 500 : fs_calls ))" height="20"
        class="$( (( fs_calls > THRESHOLD_CPS )) && echo bar-warn || echo bar-ok )" rx="3"/>
  <text x="630" y="65" class="val">$fs_calls</text>

  <!-- FS Channels -->
  <text x="20" y="105" class="lbl">FS channels</text>
  <rect x="120" y="90" width="500" height="20" class="bar-bg" rx="3"/>
  <rect x="120" y="90" width="$(( fs_chans > 500 ? 500 : fs_chans ))" height="20" class="bar-ok" rx="3"/>
  <text x="630" y="105" class="val">$fs_chans</text>

  <!-- RTP Sessions -->
  <text x="20" y="145" class="lbl">RTP sessions</text>
  <rect x="120" y="130" width="500" height="20" class="bar-bg" rx="3"/>
  <rect x="120" y="130" width="$(( rtp_sess > 500 ? 500 : rtp_sess ))" height="20" class="bar-ok" rx="3"/>
  <text x="630" y="145" class="val">$rtp_sess</text>

  <!-- RTP Port pool % -->
  <text x="20" y="185" class="lbl">RTP pool %</text>
  <rect x="120" y="170" width="500" height="20" class="bar-bg" rx="3"/>
  <rect x="120" y="170" width="$(( rtp_pct * 5 ))" height="20"
        class="$( (( rtp_pct > 80 )) && echo bar-err || (( rtp_pct > 50 )) && echo bar-warn || echo bar-ok )" rx="3"/>
  <text x="630" y="185" class="val">${rtp_pct}%</text>

  <!-- Load -->
  <text x="20" y="225" class="lbl">Load 1m</text>
  <text x="120" y="225" class="val">${METRICS[load_1m]:-N/A}</text>

  <!-- Mem -->
  <text x="320" y="225" class="lbl">Mem avail</text>
  <text x="430" y="225" class="val">$(awk -v k="${METRICS[mem_avail_kb]:-0}" 'BEGIN{printf "%.1f GB", k/1024/1024}')</text>

  <line x1="20" y1="250" x2="680" y2="250" class="axis"/>
  <text x="20" y="270" class="lbl">Generado: $(date +%H:%M:%S) — host: $(hostname)</text>
</svg>
SVG
}

# Genera SVG de ladder diagram con primeros N mensajes SIP
generate_svg_flow() {
    local flow_file="$1"
    local max_msgs=20

    [[ ! -s "$flow_file" ]] && { echo ""; return; }

    # Extraer hosts únicos para columnas
    local hosts
    hosts=$(awk -F'|' '{print $2"\n"$3}' "$flow_file" | sort -u | grep -v '^$' | head -6)

    [[ -z "$hosts" ]] && { echo "<p style='color:var(--muted)'>(sin datos SIP)</p>"; return; }

    local nhosts
    nhosts=$(echo "$hosts" | wc -l)
    local col_w=$(( 700 / (nhosts + 1) ))

    # Iniciar SVG
    local svg='<svg viewBox="0 0 800 700" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet">'
    svg+='<style>
      .host-box { fill: #161b22; stroke: #58a6ff; stroke-width: 2; }
      .host-text { fill: #c9d1d9; font: bold 12px ui-monospace, monospace; text-anchor: middle; }
      .lifeline { stroke: #30363d; stroke-width: 1; stroke-dasharray: 4,4; }
      .arrow { stroke: #58a6ff; stroke-width: 1.5; fill: none; marker-end: url(#ah); }
      .arrow-resp { stroke: #3fb950; stroke-width: 1.5; fill: none; marker-end: url(#ah); }
      .arrow-err { stroke: #f85149; stroke-width: 1.5; fill: none; marker-end: url(#ah); }
      .msg-text { fill: #c9d1d9; font: 11px ui-monospace, monospace; }
      .ts-text { fill: #8b949e; font: 9px ui-monospace, monospace; }
    </style>'
    svg+='<defs><marker id="ah" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">'
    svg+='<polygon points="0,0 10,3 0,6" fill="#58a6ff"/></marker></defs>'

    # Dibujar columnas (hosts)
    local idx=1
    declare -A host_x
    while IFS= read -r h; do
        local x=$(( idx * col_w ))
        host_x["$h"]="$x"
        svg+="<rect x='$((x - 60))' y='10' width='120' height='30' class='host-box' rx='4'/>"
        svg+="<text x='$x' y='30' class='host-text'>$(echo "$h" | head -c 18)</text>"
        svg+="<line x1='$x' y1='40' x2='$x' y2='680' class='lifeline'/>"
        idx=$((idx + 1))
    done <<< "$hosts"

    # Dibujar flechas
    local y=70
    local count=0
    local first_ts=""
    while IFS='|' read -r ts src dst sport dport method status cseq callid fuser tuser; do
        [[ $count -ge $max_msgs ]] && break
        [[ -z "$src" || -z "$dst" ]] && continue

        local sx="${host_x[$src]:-}"
        local dx="${host_x[$dst]:-}"
        [[ -z "$sx" || -z "$dx" ]] && continue

        # Timestamp relativo
        [[ -z "$first_ts" ]] && first_ts="$ts"
        local dt
        dt=$(awk -v t="$ts" -v t0="$first_ts" 'BEGIN{printf "+%.3fs", t-t0}')

        # Etiqueta
        local label
        if [[ -n "$method" ]]; then
            label="$method ($cseq)"
            local cls="arrow"
        elif [[ -n "$status" ]]; then
            label="$status $cseq"
            local cls="arrow-resp"
            [[ "$status" =~ ^[45] ]] && cls="arrow-err"
        else
            continue
        fi

        # Línea con label
        svg+="<line x1='$sx' y1='$y' x2='$dx' y2='$y' class='$cls'/>"
        local mid_x=$(( (sx + dx) / 2 ))
        svg+="<text x='$mid_x' y='$((y - 4))' class='msg-text' text-anchor='middle'>$label</text>"
        svg+="<text x='10' y='$((y + 3))' class='ts-text'>$dt</text>"

        y=$((y + 30))
        count=$((count + 1))
    done < "$flow_file"

    svg+='</svg>'
    echo "$svg"
}

# ============================================================
# MODOS
# ============================================================
mode_triage() {
    log INFO "=== Modo: TRIAGE (snapshot rápido) ==="
    OUT_DIR="$OUT_BASE/triage-$RUN_ID"
    mkdir -p "$OUT_DIR" || die "no puedo crear $OUT_DIR"
    REPORT_TXT="$OUT_DIR/report.txt"

    print_stack_summary
    build_txt_report "$REPORT_TXT" "triage"

    log OK "Reporte: $REPORT_TXT"
    echo
    echo "================================================================"
    cat "$REPORT_TXT" | tail -60
    echo "================================================================"
    log INFO "Reporte completo en: $REPORT_TXT"
}

mode_capture() {
    log INFO "=== Modo: CAPTURE (pcap + HTML) ==="
    OUT_DIR="$OUT_BASE/capture-$RUN_ID"
    mkdir -p "$OUT_DIR" || die "no puedo crear $OUT_DIR"
    REPORT_TXT="$OUT_DIR/report.txt"
    REPORT_HTML="$OUT_DIR/report.html"
    PCAP_FILE="$OUT_DIR/capture.pcap"
    EVENTS_FILE="$OUT_DIR/sip_flow.txt"

    print_stack_summary

    # Disparar pcap en background
    log INFO "Iniciando captura de ${DURATION}s en background..."
    capture_pcap "$PCAP_FILE" "$DURATION" "$IFACE" &
    local pcap_pid=$!

    # Mientras corre el pcap, recolectar el resto
    log INFO "Recolectando datos en paralelo..."
    sleep 2
    build_txt_report "$REPORT_TXT" "capture"

    log INFO "Esperando fin de captura..."
    wait "$pcap_pid" 2>/dev/null || true

    # Procesar pcap
    if [[ -s "$PCAP_FILE" ]]; then
        extract_sip_flow "$PCAP_FILE" "$EVENTS_FILE"
    fi

    # Snapshot final post-captura para refrescar métricas
    declare -A METRICS_PRE=()
    for k in "${!METRICS[@]}"; do METRICS_PRE[$k]="${METRICS[$k]}"; done

    log INFO "Generando HTML report..."
    build_html_report "$REPORT_HTML" "$REPORT_TXT" "$EVENTS_FILE"

    # Copiar logs relevantes
    log INFO "Copiando snippets de logs..."
    [[ -r "$KAM_LOG" ]] && tail -1000 "$KAM_LOG" > "$OUT_DIR/kamailio.log.tail" 2>/dev/null
    [[ -r "$FS_LOG"  ]] && tail -1000 "$FS_LOG"  > "$OUT_DIR/freeswitch.log.tail" 2>/dev/null
    [[ -r "$RTP_LOG" ]] && tail -1000 "$RTP_LOG" > "$OUT_DIR/rtpengine.log.tail" 2>/dev/null

    # Tarball para fácil transporte
    local tgz="$OUT_BASE/capture-$RUN_ID.tar.gz"
    tar -czf "$tgz" -C "$OUT_BASE" "capture-$RUN_ID" 2>/dev/null

    echo
    log OK "=== Captura completada ==="
    log OK "Directorio: $OUT_DIR"
    log OK "  - report.txt    ($(du -h "$REPORT_TXT" | awk '{print $1}'))"
    log OK "  - report.html   ($(du -h "$REPORT_HTML" | awk '{print $1}'))"
    [[ -s "$PCAP_FILE" ]] && log OK "  - capture.pcap  ($(du -h "$PCAP_FILE" | awk '{print $1}'))"
    log OK "Tarball: $tgz"
    echo
    log INFO "Abrir HTML: file://$REPORT_HTML"
    log INFO "Analizar pcap: sngrep -I $PCAP_FILE"
}

mode_monitor() {
    log INFO "=== Modo: MONITOR (loop, Ctrl-C para salir) ==="
    OUT_DIR="$OUT_BASE/monitor-$RUN_ID"
    mkdir -p "$OUT_DIR"
    local mlog="$OUT_DIR/monitor.log"

    print_stack_summary
    log INFO "Intervalo: ${INTERVAL}s, log: $mlog"

    # Trap para salida limpia
    trap 'log INFO "Monitor detenido"; exit 0' INT TERM

    local last_calls=0
    local last_regs=0
    local iteration=0

    while true; do
        iteration=$((iteration + 1))
        METRICS=()
        local tmp; tmp=$(mktemp)

        collect_freeswitch "$tmp" >/dev/null 2>&1 || true
        collect_rtpengine "$tmp" >/dev/null 2>&1 || true
        rm -f "$tmp"

        local fs_calls="${METRICS[fs_calls]:-0}"
        local fs_regs="${METRICS[fs_registrations]:-0}"
        local rtp_sess="${METRICS[rtp_sessions]:-0}"
        local rtp_pool=$((RTP_PORT_MAX - RTP_PORT_MIN))
        local rtp_used="${METRICS[rtp_ports_used]:-0}"
        local rtp_pct=$((rtp_pool > 0 ? rtp_used * 100 / rtp_pool : 0))

        local cps_delta=$(( fs_calls - last_calls ))
        local regs_delta=$(( fs_regs - last_regs ))

        local ts; ts=$(date +%H:%M:%S)
        local line
        printf -v line '[%s] iter=%d  fs_calls=%d (Δ%+d)  fs_regs=%d (Δ%+d)  rtp_sess=%d  rtp_pool=%d%%' \
            "$ts" "$iteration" "$fs_calls" "$cps_delta" "$fs_regs" "$regs_delta" "$rtp_sess" "$rtp_pct"

        # Alertas
        local alerts=()
        (( fs_calls > THRESHOLD_CPS )) && alerts+=("CALLS>$THRESHOLD_CPS")
        (( rtp_pct > 80 )) && alerts+=("RTP_POOL>80%")
        if (( iteration > 1 && last_regs > 0 )); then
            local drop_pct=$(( regs_delta < 0 ? -regs_delta * 100 / last_regs : 0 ))
            (( drop_pct > THRESHOLD_REGS_DROP_PCT )) && alerts+=("REGS_DROP=${drop_pct}%")
        fi

        if [[ ${#alerts[@]} -gt 0 ]]; then
            line="$line  ${C_RED}ALERTS: ${alerts[*]}${C_RST}"
            command -v logger >/dev/null && logger -t "$SCRIPT_NAME" -p local1.warn "ALERTS=${alerts[*]} fs_calls=$fs_calls"
        fi

        echo "$line" | tee -a "$mlog"

        last_calls="$fs_calls"
        last_regs="$fs_regs"

        sleep "$INTERVAL"
    done
}

# ============================================================
# MAIN
# ============================================================
main() {
    parse_args "$@"

    # Pre-flight checks
    [[ $EUID -ne 0 ]] && log WARN "no estás corriendo como root — captura pcap y algunos comandos pueden fallar"

    detect_stack
    [[ $HAS_KAMAILIO -eq 0 && $HAS_FREESWITCH -eq 0 && $HAS_RTPENGINE -eq 0 ]] && \
        log WARN "ningún componente VoIP detectado — el reporte tendrá solo datos de sistema"

    case "$MODE" in
        triage)  mode_triage ;;
        capture) mode_capture ;;
        monitor) mode_monitor ;;
    esac
}

main "$@"
