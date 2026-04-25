# Security Policy

## Reporting a vulnerability

This handbook is documentation, but the operational scripts under
`skill/voip-engineering/scripts/` are real code that runs on
production systems. If you find a security issue in any of them — for
example, a way for the script to leak credentials, escalate
privileges, or be tricked into executing arbitrary commands — please
report it privately rather than opening a public issue.

To report privately:

- GitHub Security Advisories (preferred): use the **Report a vulnerability**
  button on this repository's Security tab.
- Or email the maintainer (see profile) with subject line starting
  with `[SECURITY]`.

I will acknowledge within 7 days. If the issue is confirmed, I will
work on a fix and credit you in the patch release notes (unless you
prefer to remain anonymous).

## What is in scope

- Operational scripts (`voip-doctor.sh`, `sip_trace.sh`,
  `check_rtpengine.sh`, `fs_health.sh`).
- Docker-compose stacks in `labs/` if they expose unsafe defaults.
- Configuration templates in `examples/` and `skill/voip-engineering/assets/`
  if they contain unsafe defaults.

## What is not in scope

- Vulnerabilities in upstream Kamailio, FreeSWITCH, RTPEngine, or
  Asterisk. Those should be reported to their respective projects.
- General security advice in the handbook prose. If something is
  *missing* (e.g., a security best practice that isn't covered),
  open a normal issue or PR.

## A note on the operational scripts

These scripts are intended to be run by operators on systems they own.
They do not transmit data anywhere; they write to local files only.
They don't include telemetry or "phone home" behavior, and they never
will. If you ever see a contribution that adds such behavior, please
report it as a security issue.
