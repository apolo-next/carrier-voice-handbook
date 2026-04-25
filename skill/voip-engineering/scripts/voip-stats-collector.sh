#!/usr/bin/env bash
# ============================================================
# voip-stats-collector — JSON metrics for Kamailio + RTPEngine + FreeSWITCH
#
# Originally by Jesús Bazán / Apolo Next — released under Apache 2.0.
# Part of: github.com/apolo-next/carrier-voice-handbook
#
# Outputs a single JSON document with running and historical metrics
# from the open-source carrier-class voice stack. Designed to be
# scrape-friendly: pipe it to a file, ingest it into Loki/promtail,
# or wrap it for a Prometheus textfile collector.
#
# Usage:
#     voip-stats-collector.sh                  # JSON to stdout
#     voip-stats-collector.sh > stats.json     # capture to file
#
# Requirements:
#     - kamctl (or kamcmd; this version uses kamctl stats)
#     - rtpengine-ctl
#     - fs_cli
#
# Tested against:
#     - Kamailio 5.7
#     - RTPEngine mr11.x  (running/totals output format)
#     - FreeSWITCH 1.10.x (sofia status profile output)
#
# Version: 1.3
# ============================================================

set -uo pipefail

TS=$(date '+%Y-%m-%d %H:%M:%S %Z')
HOST=$(hostname)

# ── Kamailio ────────────────────────────────────────────────
KAM_RAW=$(kamctl stats 2>/dev/null)
kget() { echo "$KAM_RAW" | grep "\"$1 =" | grep -oP '= \K[0-9]+' | head -1; }

KAM_ACTIVE=$(kget "dialog:active_dialogs")
KAM_EARLY=$(kget "dialog:early_dialogs")
KAM_FAILED=$(kget "dialog:failed_dialogs")
KAM_PROCESSED=$(kget "dialog:processed_dialogs")
KAM_EXPIRED=$(kget "dialog:expired_dialogs")
KAM_TX=$(kget "tmx:active_transactions")
KAM_TCP=$(kget "tcp:current_opened_connections")
KAM_SHM_USED=$(kget "shmem:used_size")
KAM_SHM_FREE=$(kget "shmem:free_size")

# ── RTPEngine — numsessions (active sessions) ───────────────
# Correct command for in-flight sessions on rtpengine v11
RTP_NUM=$(rtpengine-ctl list numsessions 2>/dev/null)
rnum() { echo "$RTP_NUM" | grep -i "$1" | grep -oP ':\s*\K[0-9]+' | head -1; }

RTP_OWN=$(rnum "sessions own")
RTP_FOREIGN=$(rnum "sessions foreign")
RTP_TOTAL_SESS=$(rnum "sessions total")
RTP_TRANSCODE=$(rnum "transcoded media")
RTP_IPV4=$(rnum "ipv4 only media")
RTP_IPV6=$(rnum "ipv6 only media")
RTP_MIXED_IP=$(rnum "ip mixed  media")

# ── RTPEngine — list totals (historical + running streams) ───
# In rtpengine v11, "list sessions" and "list totals" share output.
# Active streams (Userspace-only) appear in list totals "running" section.
RTP_TOT=$(rtpengine-ctl list totals 2>/dev/null)

# Section: "Statistics over currently running sessions"
RTP_RUNNING=$(echo "$RTP_TOT" | awk '/Statistics over currently running sessions/{found=1} found && /^Total statistics/{exit} found{print}')
# Section: "Total statistics"
RTP_HIST=$(echo "$RTP_TOT" | awk '/^Total statistics/{found=1} found && /^MOS statistics/{exit} found{print}')
# Section: MOS
RTP_MOS_SEC=$(echo "$RTP_TOT" | awk '/^MOS statistics/{found=1} found && /^VoIP metrics:/{exit} found{print}')
# Section: VoIP global (before "for interface")
RTP_VOIP_G=$(echo "$RTP_TOT" | awk '/^VoIP metrics:/{found=1} found && /^VoIP metrics for interface/{exit} found{print}')
# Section: VoIP internal interface
RTP_VOIP_I=$(echo "$RTP_TOT" | awk '/VoIP metrics for interface internal/{found=1} found && /VoIP metrics for interface external/{exit} found{print}')
# Section: VoIP external interface
RTP_VOIP_E=$(echo "$RTP_TOT" | awk '/VoIP metrics for interface external/{found=1} found{print}')

run()  { echo "$RTP_RUNNING" | grep -i "$1" | grep -oP ':\s*\K[0-9.]+' | head -1; }
hist() { echo "$RTP_HIST"    | grep -i "$1" | grep -oP ':\s*\K[0-9]+'   | head -1; }
histf(){ echo "$RTP_HIST"    | grep -i "$1" | grep -oP ':\s*\K[0-9.]+' | head -1; }
mosv() { echo "$RTP_MOS_SEC" | grep -i "$1" | grep -oP ':\s*\K[0-9.]+' | head -1; }
vg()   { echo "$RTP_VOIP_G"  | grep -i "$1" | grep -oP ':\s*\K[0-9.]+' | head -1; }
vi()   { echo "$RTP_VOIP_I"  | grep -i "$1" | grep -oP ':\s*\K[0-9.]+' | head -1; }
ve()   { echo "$RTP_VOIP_E"  | grep -i "$1" | grep -oP ':\s*\K[0-9.]+' | head -1; }

# Running
RTP_STREAMS_US=$(run "Userspace-only media streams")
RTP_STREAMS_KN=$(run "Kernel-only media streams")
RTP_STREAMS_MIX=$(run "Mixed kernel")
RTP_PPS_US=$(run "Packets per second .userspace.")
RTP_BPS_US=$(run "Bytes per second .userspace.")
RTP_PPS_KN=$(run "Packets per second .kernel.")
RTP_BPS_KN=$(run "Bytes per second .kernel.")
RTP_PPS_TOT=$(run "Packets per second .total.")
RTP_BPS_TOT=$(run "Bytes per second .total.")

# Historical
RTP_UPTIME=$(hist "Uptime of rtpengine")
RTP_MANAGED=$(hist "Total managed sessions")
RTP_REJECTED=$(hist "Total rejected sessions")
RTP_TIMEOUT=$(hist "timed-out sessions via TIMEOUT\"")
RTP_SILENT_TO=$(hist "timed-out sessions via SILENT_TIMEOUT")
RTP_FINAL_TO=$(hist "timed-out sessions via FINAL_TIMEOUT")
RTP_OFFER_TO=$(hist "timed-out sessions via OFFER_TIMEOUT")
RTP_OK=$(hist "Total regular terminated sessions")
RTP_FORCED=$(hist "Total forced terminated sessions")
RTP_PKT_US=$(hist "Total relayed packets .userspace.")
RTP_PKT_ERR_US=$(hist "Total relayed packet errors .userspace.")
RTP_BYTES_US=$(hist "Total relayed bytes .userspace.")
RTP_PKT_KN=$(hist "Total relayed packets .kernel.")
RTP_BYTES_KN=$(hist "Total relayed bytes .kernel.")
RTP_NO_RELAY=$(hist "streams with no relayed packets")
RTP_1WAY=$(hist "1-way streams")
RTP_DURATION=$(histf "Average call duration")
RTP_DURATION_TOT=$(histf "Total calls duration$")
RTP_DURATION_STD=$(histf "Total calls duration standard deviation")
RTP_DUP=$(hist "Duplicate RTP packets")
RTP_OOO=$(hist "Out-of-order RTP packets")
RTP_SEQ_SKIP=$(hist "RTP sequence skips")
RTP_SEQ_RESET=$(hist "RTP sequence resets")
RTP_PKT_LOST=$(hist "Packets lost")

# MOS
RTP_MOS_AVG=$(mosv "Average MOS")
RTP_MOS_STD=$(mosv "MOS standard deviation")
RTP_MOS_N=$(echo "$RTP_MOS_SEC" | grep "Total number of MOS samples" | grep -oP ':\s*\K[0-9]+' | head -1)
RTP_MOS_SUM=$(mosv "Sum of all MOS values sampled$")

# VoIP global
RTP_JITTER_SUM=$(vg "Sum of all jitter .reported. values sampled$")
RTP_JITTER_N=$(echo "$RTP_VOIP_G" | grep "Total number of jitter .reported. samples" | grep -oP ':\s*\K[0-9]+' | head -1)
RTP_JITTER_AVG=$(vg "Average jitter .reported.")
RTP_JITTER_STD=$(vg "jitter .reported. standard deviation")
RTP_RTT_E2E=$(vg "Average end-to-end round-trip")
RTP_RTT_DISC=$(vg "Average discrete round-trip")
RTP_LOSS_SUM=$(vg "Sum of all packet loss values sampled")
RTP_LOSS_N=$(echo "$RTP_VOIP_G" | grep "Total number of packet loss samples" | grep -oP ':\s*\K[0-9]+' | head -1)
RTP_LOSS_AVG=$(vg "Average packet loss")
RTP_LOSS_STD=$(vg "packet loss standard deviation")

# VoIP per interface
RTP_INT_JITTER=$(vi "Average jitter .reported.")
RTP_INT_LOSS_STD=$(vi "packet loss standard deviation")
RTP_INT_LOSS_N=$(echo "$RTP_VOIP_I" | grep "Total number of packet loss samples" | grep -oP ':\s*\K[0-9]+' | head -1)
RTP_EXT_JITTER=$(ve "Average jitter .reported.")
RTP_EXT_LOSS_STD=$(ve "packet loss standard deviation")

# ── RTPEngine — ng control stats ────────────────────────────
RTP_STAT_LINE=$(rtpengine-ctl list stats 2>/dev/null | grep "127.0.0.1")
RTP_PINGS=$(echo "$RTP_STAT_LINE"   | awk -F'|' '{gsub(/ /,"",$2); print $2}')
RTP_OFFERS=$(echo "$RTP_STAT_LINE"  | awk -F'|' '{gsub(/ /,"",$3); print $3}')
RTP_ANSWERS=$(echo "$RTP_STAT_LINE" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
RTP_DELETES=$(echo "$RTP_STAT_LINE" | awk -F'|' '{gsub(/ /,"",$5); print $5}')

# ── FreeSWITCH ───────────────────────────────────────────────
FS_EXT=$(fs_cli -x "sofia status profile external" 2>/dev/null)
FS_INT=$(fs_cli -x "sofia status profile internal" 2>/dev/null)
FS_CALLS=$(fs_cli -x "show calls count" 2>/dev/null | grep -oP '^\d+')
FS_CHANNELS=$(fs_cli -x "show channels count" 2>/dev/null | grep -oP '^\d+')

FS_CALLS_IN=$(echo "$FS_EXT"       | awk '/^CALLS-IN/{print $2;exit}')
FS_FAILED_IN=$(echo "$FS_EXT"      | awk '/^FAILED-CALLS-IN/{print $2;exit}')
FS_CALLS_OUT_EXT=$(echo "$FS_EXT"  | awk '/^CALLS-OUT/{print $2;exit}')
FS_FAILED_OUT_EXT=$(echo "$FS_EXT" | awk '/^FAILED-CALLS-OUT/{print $2;exit}')
FS_INT_CALLS_OUT=$(echo "$FS_INT"  | awk '/^CALLS-OUT/{print $2;exit}')
FS_INT_FAILED_OUT=$(echo "$FS_INT" | awk '/^FAILED-CALLS-OUT/{print $2;exit}')

FS_GLOBAL_CODEC=$(fs_cli -x "global_getvar global_codec_prefs" 2>/dev/null | tr -d '\n' | xargs)
FS_CODEC_IN=$(echo "$FS_EXT" | awk '/^CODECS IN/{$1=$2=""; print $0}' | xargs)
FS_CODEC_OUT=$(echo "$FS_EXT" | awk '/^CODECS OUT/{$1=$2=""; print $0}' | xargs)
[[ -z "$FS_CODEC_IN" ]]  && FS_CODEC_IN="not configured"
[[ -z "$FS_CODEC_OUT" ]] && FS_CODEC_OUT="not configured"

# ── System ──────────────────────────────────────────────────
CPU=$(top -bn1 | grep "Cpu(s)" | grep -oP '\d+[.,]\d+' | head -1 | tr ',' '.')
MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_PCT=$(free | awk 'NR==2{printf "%.1f", $3/$2*100}')
UPTIME_SYS=$(uptime -p 2>/dev/null | sed 's/up //')
LOAD=$(uptime | grep -oP 'load average: \K[0-9.,\s]+' | tr ',' '.' | xargs)

# ── JSON output ──────────────────────────────────────────────
cat <<EOF
{
  "meta": {
    "timestamp": "$TS",
    "host": "$HOST",
    "collector": "voip-stats-collector v1.3"
  },
  "system": {
    "cpu_pct": "${CPU:-0}",
    "mem_used_mb": ${MEM_USED:-0},
    "mem_total_mb": ${MEM_TOTAL:-0},
    "mem_pct": "${MEM_PCT:-0}",
    "uptime": "$UPTIME_SYS",
    "load_avg": "$LOAD"
  },
  "kamailio": {
    "active_dialogs": ${KAM_ACTIVE:-0},
    "early_dialogs": ${KAM_EARLY:-0},
    "failed_dialogs": ${KAM_FAILED:-0},
    "processed_dialogs": ${KAM_PROCESSED:-0},
    "expired_dialogs": ${KAM_EXPIRED:-0},
    "active_transactions": ${KAM_TX:-0},
    "tcp_connections": ${KAM_TCP:-0},
    "shm_used_bytes": ${KAM_SHM_USED:-0},
    "shm_free_bytes": ${KAM_SHM_FREE:-0}
  },
  "rtpengine": {
    "running": {
      "sessions_own": ${RTP_OWN:-0},
      "sessions_foreign": ${RTP_FOREIGN:-0},
      "sessions_total": ${RTP_TOTAL_SESS:-0},
      "transcoded": ${RTP_TRANSCODE:-0},
      "streams_userspace": ${RTP_STREAMS_US:-0},
      "streams_kernel": ${RTP_STREAMS_KN:-0},
      "streams_mixed": ${RTP_STREAMS_MIX:-0},
      "sessions_ipv4": ${RTP_IPV4:-0},
      "sessions_ipv6": ${RTP_IPV6:-0},
      "sessions_mixed_ip": ${RTP_MIXED_IP:-0},
      "pps_userspace": ${RTP_PPS_US:-0},
      "bps_userspace": ${RTP_BPS_US:-0},
      "pps_kernel": ${RTP_PPS_KN:-0},
      "bps_kernel": ${RTP_BPS_KN:-0},
      "pps_total": ${RTP_PPS_TOT:-0},
      "bps_total": ${RTP_BPS_TOT:-0}
    },
    "totals": {
      "uptime_sec": ${RTP_UPTIME:-0},
      "managed": ${RTP_MANAGED:-0},
      "rejected": ${RTP_REJECTED:-0},
      "timeout": ${RTP_TIMEOUT:-0},
      "silent_timeout": ${RTP_SILENT_TO:-0},
      "final_timeout": ${RTP_FINAL_TO:-0},
      "offer_timeout": ${RTP_OFFER_TO:-0},
      "terminated_ok": ${RTP_OK:-0},
      "terminated_forced": ${RTP_FORCED:-0},
      "packets_userspace": ${RTP_PKT_US:-0},
      "packet_errors_userspace": ${RTP_PKT_ERR_US:-0},
      "bytes_userspace": ${RTP_BYTES_US:-0},
      "packets_kernel": ${RTP_PKT_KN:-0},
      "bytes_kernel": ${RTP_BYTES_KN:-0},
      "streams_no_relay": ${RTP_NO_RELAY:-0},
      "streams_1way": ${RTP_1WAY:-0},
      "avg_duration_sec": ${RTP_DURATION:-0},
      "total_duration_sec": ${RTP_DURATION_TOT:-0},
      "duration_std_sec": ${RTP_DURATION_STD:-0},
      "duplicate_packets": ${RTP_DUP:-0},
      "ooo_packets": ${RTP_OOO:-0},
      "seq_skips": ${RTP_SEQ_SKIP:-0},
      "seq_resets": ${RTP_SEQ_RESET:-0},
      "packets_lost": ${RTP_PKT_LOST:-0}
    },
    "mos": {
      "avg": ${RTP_MOS_AVG:-0},
      "std": ${RTP_MOS_STD:-0},
      "samples": ${RTP_MOS_N:-0},
      "sum": ${RTP_MOS_SUM:-0}
    },
    "voip_global": {
      "jitter_sum": ${RTP_JITTER_SUM:-0},
      "jitter_samples": ${RTP_JITTER_N:-0},
      "jitter_avg_ms": ${RTP_JITTER_AVG:-0},
      "jitter_std_ms": ${RTP_JITTER_STD:-0},
      "rtt_e2e_avg_ms": ${RTP_RTT_E2E:-0},
      "rtt_disc_avg_ms": ${RTP_RTT_DISC:-0},
      "loss_sum": ${RTP_LOSS_SUM:-0},
      "loss_samples": ${RTP_LOSS_N:-0},
      "loss_avg": ${RTP_LOSS_AVG:-0},
      "loss_std": ${RTP_LOSS_STD:-0}
    },
    "voip_internal": {
      "jitter_avg_ms": ${RTP_INT_JITTER:-0},
      "loss_std": ${RTP_INT_LOSS_STD:-0},
      "loss_samples": ${RTP_INT_LOSS_N:-0}
    },
    "voip_external": {
      "jitter_avg_ms": ${RTP_EXT_JITTER:-0},
      "loss_std": ${RTP_EXT_LOSS_STD:-0}
    },
    "ng_control": {
      "pings": ${RTP_PINGS:-0},
      "offers": ${RTP_OFFERS:-0},
      "answers": ${RTP_ANSWERS:-0},
      "deletes": ${RTP_DELETES:-0}
    }
  },
  "freeswitch": {
    "active_calls": ${FS_CALLS:-0},
    "active_channels": ${FS_CHANNELS:-0},
    "ext_calls_in": ${FS_CALLS_IN:-0},
    "ext_failed_in": ${FS_FAILED_IN:-0},
    "ext_calls_out": ${FS_CALLS_OUT_EXT:-0},
    "ext_failed_out": ${FS_FAILED_OUT_EXT:-0},
    "int_calls_out": ${FS_INT_CALLS_OUT:-0},
    "int_failed_out": ${FS_INT_FAILED_OUT:-0},
    "codec_in": "$FS_CODEC_IN",
    "codec_out": "$FS_CODEC_OUT",
    "global_codec_prefs": "$FS_GLOBAL_CODEC"
  }
}
EOF
