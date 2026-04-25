# Labs

Reproducible Docker-based environments to practice with the
open-source carrier-class voice stack without breaking anything in
production.

## What's planned

| Lab | Status | What you'll learn |
|---|---|---|
| `01-hello-sip/` | Planned | Send your first SIP REGISTER and INVITE. Watch them with sngrep. Understand what each header does. |
| `02-kamailio-dispatcher/` | Planned | Configure Kamailio to load-balance across two FreeSWITCH backends. See failover in action. |
| `03-freeswitch-ivr/` | Planned | Build a multi-level IVR. Add 100rel/PRACK interworking. Capture and analyze the flow. |
| `04-full-sbc-stack/` | Planned | Kamailio + FreeSWITCH + RTPEngine end-to-end: edge SBC fronting an internal softswitch with NAT. |

## Lab structure

Each lab will contain:

```
NN-name/
├── README.md           Objectives, prerequisites, exercises.
├── docker-compose.yml  The stack.
├── configs/            Pre-baked configs you can read and modify.
├── scripts/            Helper scripts (start, test, verify).
└── EXERCISES.md        Hands-on tasks, increasing in difficulty.
```

## Prerequisites for all labs

- Linux or macOS host (Windows via WSL2 should work but is untested).
- Docker and docker-compose (or Podman with compose support).
- 4 GB RAM available to containers, more for the full stack lab.
- Basic comfort with the terminal.

## Note on networking

Voice containers need `network_mode: host` (or equivalent) because
SIP carries IP addresses inside its payload and standard Docker NAT
breaks RTP. Each lab's README will explain the network model in
detail.

This means the labs interact with your host network. If you have a
SIP-related service running on your host already (anything listening
on 5060), the labs will conflict with it.

## Contributing labs

If you have an idea for an additional lab — multi-tenant scenarios,
specific carrier interworking, billing integration, security
hardening — see [CONTRIBUTING.md](../CONTRIBUTING.md). Labs are
particularly welcome contributions because they let readers learn by
doing.
