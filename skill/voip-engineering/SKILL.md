---
name: voip-engineering
description: Use this skill for any task involving VoIP infrastructure with Kamailio, FreeSWITCH, RTPEngine, Asterisk, or related SIP/RTP components. Triggers include configuring SBCs, debugging SIP signaling (REGISTER, INVITE, 100rel/PRACK, 302 redirects), troubleshooting RTP/media flows, designing dialplans, building IVRs, integrating CGRateS or custom billing engines, analyzing SIP traces (pcap, sngrep, sipgrep), tuning timers (fr_timer, fr_inv_timer), bypass_media configurations, dual-interface RTPEngine setups, FreeSWITCH B2BUA interworking, Asterisk-to-FreeSWITCH migrations, dSIPRouter, concurrent call limiting, air-gapped/containerized VoIP deployments on RHEL/Debian, and modifying or extending the operational diagnostic scripts in scripts/ (notably voip-doctor.sh for end-to-end Kamailio+FS+RTPEngine diagnostics on Apolo SBC and Apolo IVR 119). Do NOT use for general networking questions unrelated to SIP/RTP, or for non-telecom audio processing.
---

# VoIP Engineering Skill

Specialized knowledge for Kamailio, FreeSWITCH, RTPEngine, Asterisk, and SBC architectures.

## When you receive a VoIP task, follow this routing

### 1. Identify the component(s) involved

| Symptom / Request | Primary component | Reference |
|---|---|---|
| SIP routing, REGISTER, load balancing, SBC edge | Kamailio | `references/kamailio.md` |
| Media handling, IVR, B2BUA, dialplan, ESL | FreeSWITCH | `references/freeswitch.md` |
| RTP relay, NAT traversal, transcoding, recording | RTPEngine | `references/rtpengine.md` |
| Legacy PBX, AGI, queues, chan_pjsip | Asterisk | `references/asterisk.md` |
| Multi-component flow (SBC → softswitch → media) | Architecture | `references/architectures.md` |
| Billing, rating, CDR, prepaid auth | Billing integration | `references/billing.md` |
| Troubleshooting (sngrep, pcap, logs) | Diagnostics | `references/diagnostics.md` |

### 2. Always ask before assuming

Before generating configs, confirm:

- **Topology**: Is the component an edge SBC, a core registrar, or a media server?
- **Transport**: UDP / TCP / TLS / WSS — and on which port?
- **NAT context**: Is RTPEngine behind NAT? Single or dual interface?
- **Codec policy**: Pass-through, transcoding, or DTMF (RFC 2833 / SIP INFO / inband)?
- **Environment**: RHEL 8 air-gapped, Debian 12, container (Docker/Podman)?
- **Scale**: Concurrent calls expected — this drives `children`, `tcp_children`, RTP port range.

### 3. Critical rules — never violate

- **Never put credentials in configs you generate.** Use placeholders like `${DB_PASSWORD}` and document where to inject them.
- **Never recommend `bypass_media` without checking** if DTMF, recording, or transcoding is required downstream — it removes FreeSWITCH from the RTP path entirely.
- **Always specify RTPEngine interface explicitly** (`interface=internal/10.0.0.1!external/200.x.x.x`) when behind NAT. Default `interface=auto` breaks dual-homed setups.
- **For 100rel/PRACK interworking**, FreeSWITCH B2BUA is the standard pattern — Kamailio alone cannot transform PRACK semantics.
- **Kamailio `fr_inv_timer` defaults to 120s** — too long for IVR redirects. Tune to 30-60s for 302 flows.

### 4. Output format

When delivering configs:

1. State the assumed topology in 1-2 lines.
2. Provide the config block(s) with inline comments on non-obvious directives.
3. List the verification commands (`kamcmd`, `fs_cli`, `rtpengine-ctl`, `sngrep`).
4. Note any companion changes required in other components.

## Operational scripts (`scripts/`)

**Important distinction:** these scripts are NOT executed by Claude inside this skill environment. They are operational tooling intended to run on real VoIP servers (Apolo SBC on Debian 12, Apolo IVR 119 on RHEL 8). The skill stores the canonical version; the user deploys copies to `/usr/local/sbin/` on each target host (typically via `git pull` from the apolo-knowledge repo, or symlink).

When the user asks to modify, extend, or debug any of these scripts:

1. **Edit the file in-place** under `scripts/` — do NOT create a new file or a copy elsewhere.
2. **Preserve the existing structure** (flags, env-var overrides, output paths) unless the user explicitly asks to change it. These scripts are deployed in production; breaking changes in CLI surface require explicit approval.
3. **Run `bash -n` on the result** to validate syntax before delivering. The user cannot easily test on the SBC mid-conversation.
4. **Document the change** at the top of the file in a brief CHANGELOG comment when the modification is non-trivial.
5. **Remind the user** at the end of the response that they need to redeploy (`git pull` on the servers, or `scp` to the target).

Available scripts:

- `scripts/voip-doctor.sh` — **end-to-end diagnostic tool with three modes**: `triage` (60s snapshot), `capture` (pcap + HTML report with embedded SVG ladder diagram), `monitor` (continuous loop with syslog alerts). Auto-detects RHEL 8 vs Debian 12. Bash-only, no external runtime deps beyond `tcpdump`/`tshark` for pcap. Designed for cron, on-call triage, and post-mortem evidence collection. See `scripts/voip-doctor.README.md` for the full deployment guide.
- `scripts/sip_trace.sh` — quick sngrep capture wrapper with sensible defaults.
- `scripts/check_rtpengine.sh` — RTPEngine ng-protocol + kernel module health check.
- `scripts/fs_health.sh` — FreeSWITCH snapshot via fs_cli (status, channels, registrations, sofia profiles).

When the user reports an issue in production ("the SBC is dropping calls", "RTPEngine pool is exhausted"), suggest running `voip-doctor.sh capture` first to gather evidence before recommending config changes. Diagnose from data, not from guesses.

## Templates

The `assets/configs/` directory contains battle-tested base configs:

- `kamailio_sbc_edge.cfg` — minimal SBC with TLS termination + RTPEngine binding
- `freeswitch_ivr_dialplan.xml` — IVR dialplan pattern with PRACK support
- `rtpengine_dual_iface.conf` — dual-interface NAT configuration
- `dsiprouter_call_limit.sql` — concurrent call limiting via dsip_call_settings

Read the relevant reference file in full before producing output. The reference files contain the production-tested patterns and the gotchas that don't fit in this top-level guide.
