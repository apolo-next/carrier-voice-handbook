# voip-stats-collector

A single-shot JSON collector for the open-source carrier-class voice
stack: Kamailio + RTPEngine + FreeSWITCH. Designed for ingestion into
monitoring systems — not for human reading.

If you want a human-readable diagnostic, use `voip-doctor.sh` instead.
This script is for cron, log aggregators, and time-series databases.

## What it collects

A single JSON document with five top-level sections:

| Section | What's in it |
|---|---|
| `meta` | timestamp, hostname, collector version |
| `system` | CPU %, memory used/total, uptime, load average |
| `kamailio` | active/early/failed dialogs, transactions, TCP connections, shmem |
| `rtpengine.running` | sessions own/foreign/total, streams (kernel/userspace/mixed), pps/bps |
| `rtpengine.totals` | managed/rejected sessions, timeouts, packets relayed, errors |
| `rtpengine.mos` | average MOS, standard deviation, sample count |
| `rtpengine.voip_global` | jitter, RTT, packet loss across all interfaces |
| `rtpengine.voip_internal` / `.voip_external` | same metrics, per interface |
| `rtpengine.ng_control` | offers, answers, deletes, pings on the ng-protocol socket |
| `freeswitch` | active calls/channels, calls in/out per profile, codecs |

Every numeric field defaults to `0` when its source is unavailable —
the JSON is always valid even if Kamailio or RTPEngine is down.

## Quick start

```bash
# Print to stdout
voip-stats-collector.sh

# Capture to file
voip-stats-collector.sh > /var/lib/voip-stats/stats.json

# Pretty-print for inspection
voip-stats-collector.sh | jq .

# Extract a single metric
voip-stats-collector.sh | jq -r '.rtpengine.mos.avg'
```

## Requirements

The collector runs the following commands and parses their output:

- `kamctl stats` — statistics command from Kamailio.
- `rtpengine-ctl list numsessions`, `rtpengine-ctl list totals`, `rtpengine-ctl list stats` — ng-protocol control via the rtpengine-ctl helper.
- `fs_cli -x "..."` — FreeSWITCH external CLI.
- Standard Unix tools: `awk`, `grep`, `sed`, `top`, `free`, `uptime`.

If any of these are missing, the corresponding fields appear as `0` in
the output. The script does not fail.

### Tested versions

- Kamailio 5.7+
- RTPEngine mr11.x — earlier versions had different `list totals` output
- FreeSWITCH 1.10.x

If you run older versions, validate the output manually with `jq` and
adjust the section parsers (the `awk` blocks that extract `RTP_RUNNING`,
`RTP_HIST`, `RTP_MOS_SEC`, `RTP_VOIP_G`, `RTP_VOIP_I`, `RTP_VOIP_E`).

## Deployment patterns

### Pattern 1 — cron + log file

The simplest pattern. Run every minute, append to a JSON-lines file,
let your log aggregator pick it up.

```bash
# /etc/cron.d/voip-stats
* * * * * voip /usr/local/sbin/voip-stats-collector.sh \
    | tr -d '\n' >> /var/log/voip-stats/metrics.jsonl 2>/dev/null \
    && echo >> /var/log/voip-stats/metrics.jsonl
```

The `tr -d '\n'` collapses the JSON into a single line, then `echo`
adds the line terminator. The result is JSONL (one JSON document per
line), which is the standard format for log aggregators.

Rotate with `logrotate`:

```
# /etc/logrotate.d/voip-stats
/var/log/voip-stats/metrics.jsonl {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 644 voip voip
}
```

### Pattern 2 — Loki + promtail

If you already run Loki for log aggregation, ingest the JSONL directly
without a Prometheus exporter.

```yaml
# /etc/promtail/promtail.yaml
scrape_configs:
  - job_name: voip-stats
    static_configs:
      - targets: [localhost]
        labels:
          job: voip-stats
          host: ${HOSTNAME}
          __path__: /var/log/voip-stats/metrics.jsonl
    pipeline_stages:
      - json:
          expressions:
            ts: meta.timestamp
            host: meta.host
            mos_avg: rtpengine.mos.avg
            jitter_ms: rtpengine.voip_global.jitter_avg_ms
            loss_avg: rtpengine.voip_global.loss_avg
            active_dialogs: kamailio.active_dialogs
            fs_calls: freeswitch.active_calls
      - timestamp:
          source: ts
          format: '2006-01-02 15:04:05 -0700'
      - labels:
          host:
```

Then in Grafana you get LogQL queries like:

```logql
{job="voip-stats"} | json | mos_avg < 4.0
{job="voip-stats"} | json | unwrap jitter_ms | rate(5m)
```

### Pattern 3 — Prometheus textfile collector

If you live in a Prometheus shop, convert the JSON to the textfile
exporter format. There's no built-in JSON-to-Prometheus converter, but
a small `jq` wrapper does the job:

```bash
#!/usr/bin/env bash
# /usr/local/sbin/voip-stats-prometheus.sh
# Run from cron, output to a path the textfile collector watches.

OUT=/var/lib/node_exporter/textfile_collector/voip.prom
TMP=$(mktemp)

voip-stats-collector.sh | jq -r '
"# HELP voip_kamailio_active_dialogs Currently active Kamailio dialogs",
"# TYPE voip_kamailio_active_dialogs gauge",
"voip_kamailio_active_dialogs " + (.kamailio.active_dialogs | tostring),
"# HELP voip_rtpengine_sessions_own RTPEngine own active sessions",
"# TYPE voip_rtpengine_sessions_own gauge",
"voip_rtpengine_sessions_own " + (.rtpengine.running.sessions_own | tostring),
"# HELP voip_rtpengine_mos_avg Average MOS score",
"# TYPE voip_rtpengine_mos_avg gauge",
"voip_rtpengine_mos_avg " + (.rtpengine.mos.avg | tostring),
"# HELP voip_rtpengine_jitter_avg_ms Average jitter (ms)",
"# TYPE voip_rtpengine_jitter_avg_ms gauge",
"voip_rtpengine_jitter_avg_ms " + (.rtpengine.voip_global.jitter_avg_ms | tostring),
"# HELP voip_freeswitch_active_calls FreeSWITCH active calls",
"# TYPE voip_freeswitch_active_calls gauge",
"voip_freeswitch_active_calls " + (.freeswitch.active_calls | tostring)
' > "$TMP"

mv "$TMP" "$OUT"
```

Then in node_exporter:

```bash
# In your node_exporter unit file or args
--collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

Add metrics you need by extending the `jq` template. The pattern is
the same: `# HELP`, `# TYPE`, `metric_name value`.

### Pattern 4 — Telegraf JSON input

If Telegraf is your collector:

```toml
# /etc/telegraf/telegraf.d/voip-stats.conf
[[inputs.exec]]
  commands = ["/usr/local/sbin/voip-stats-collector.sh"]
  timeout = "10s"
  data_format = "json_v2"
  name_override = "voip_stats"

  [[inputs.exec.json_v2]]
    [[inputs.exec.json_v2.object]]
      path = "kamailio"
      [[inputs.exec.json_v2.object]]
        path = "rtpengine.running"
      [[inputs.exec.json_v2.object]]
        path = "rtpengine.mos"
```

Telegraf flattens the JSON tree into measurements automatically.

## Choosing thresholds

The collector reports raw values. Setting alert thresholds is up to you,
but reasonable starting points for carrier-class voice:

| Metric | Healthy | Warn | Critical |
|---|---|---|---|
| `mos.avg` | > 4.0 | 3.5 - 4.0 | < 3.5 |
| `voip_global.jitter_avg_ms` | < 30 | 30 - 60 | > 60 |
| `voip_global.loss_avg` | < 0.01 | 0.01 - 0.03 | > 0.03 |
| `voip_global.rtt_e2e_avg_ms` | < 150 | 150 - 300 | > 300 |
| `kamailio.shm_free_bytes` | > 30% of total | 10% - 30% | < 10% |
| `running.sessions_total / port pool` | < 60% | 60% - 80% | > 80% |

These match ITU-T G.107 / G.114 guidelines for "good" vs "acceptable"
quality on toll-grade voice circuits. They're not a substitute for
your own SLA targets — calibrate from your real production data over
a week or two before setting hard alerts.

## Output security note

The JSON contains no credentials, no SIP message bodies, no caller
IDs — only counters and aggregate metrics. It's safe to ship to a
log aggregator or expose to a Prometheus scraper that runs on the
same host.

That said: the JSON does reveal call volume, codec preferences, and
operational health. If you ship it off-host, do it over TLS and to a
trusted aggregator. Don't push it to a SaaS log service without a
review of what your contract says about retention and access.

## Versioning

The collector tags its output with `meta.collector` so downstream
parsers can detect schema changes. Current version is `voip-stats-collector v1.3`.

If you write parsers against this output, key off `meta.collector`
and refuse to parse versions you don't recognize. Schema changes
will bump the minor version (1.3 → 1.4); breaking changes bump major.

## Compared to voip-doctor.sh

| Concern | `voip-doctor.sh` | `voip-stats-collector.sh` |
|---|---|---|
| Output format | Text + HTML + pcap | JSON, one document per run |
| Audience | Engineer, on-call, postmortem | Time-series DB, log aggregator |
| Frequency | Manual or one-shot | Every minute via cron |
| RTPEngine depth | Basic | Deep (MOS, jitter, RTT, ng control) |
| Side effects | Writes a directory of files | Writes one JSON to stdout |
| When to reach for it | "Something broke, what's wrong?" | "How healthy is the stack right now?" |

Use both. They're complementary.
