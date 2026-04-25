# Carrier Voice Handbook

> Open-source carrier-grade voice infrastructure — what 20 years in
> telecom networks taught me, distilled into something you can read,
> run, and learn from.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Skill](https://img.shields.io/badge/Claude-Skill-purple.svg)](skill/voip-engineering/)
[![Stack](https://img.shields.io/badge/stack-Kamailio%20%7C%20FreeSWITCH%20%7C%20RTPEngine-green.svg)](#)

---

## Why this exists

I started in a NOC, watching alarms and restarting cards on shifts that
ended at 6 AM. Twenty years later I architect voice networks for a Tier-1
LATAM operator and run my own VoIP company. The path between those two
points was paved with mistakes nobody had documented — every gotcha I
publish here is one fewer 3 AM call for the engineer that comes after me.

This is not another Kamailio tutorial. The internet has those, and many
are excellent. **This is the mental model, the decision framework, and
the production scars I wish someone had handed me when I was looking up
SIP RFCs at 2 AM with a P1 ticket open.**

It is also, deliberately, written from the LATAM trenches. The realities
of Telcordia OAP billing, OSIPTEL portability, regional carriers that
don't speak English, and air-gapped RHEL boxes in datacenters where the
nearest senior engineer is six time zones away — these things rarely
appear in upstream docs. They appear here.

---

## Who this is for

- **NOC engineers** moving from L2/L3 into voice and signaling.
- **Junior VoIP engineers** facing their first production SBC.
- **Senior engineers from proprietary stacks** (Cisco, Genband, Sonus, Ribbon)
  evaluating the open-source path.
- **Solution architects** weighing open-source vs. commercial Class 4/5
  softswitches.
- **Anyone in LATAM** dealing with carrier interconnect, regulatory
  realities, and operators where the documentation is in a language
  the upstream community doesn't speak.

This is *not* for: SIP application developers building on top of Twilio,
WebRTC frontend developers, or anyone looking for a how-to on building a
home Asterisk PBX. There are better resources for those.

---

## What's inside

### `docs/` — the handbook

A progressive learning path from foundations to operations.

```
docs/
├── 01-foundations/      Why open source carrier, SIP mental model,
│                        the path from NOC to voice specialist
├── 02-components/       Kamailio, FreeSWITCH, RTPEngine, Asterisk —
│                        what each does, when to use each, how they fit
├── 03-architectures/    Edge SBC, IVR, billing integration, HA & scaling
├── 04-operations/       Diagnostics playbook, common failures (war
│                        stories), on-call runbook
└── 05-learning-path/    Roadmaps for beginner / intermediate / advanced,
                         curated reading and RFC list
```

Each document is meant to be readable on its own, but they cross-link.
Start wherever you like; the suggested entry point depends on where you
are (see *How to use this* below).

### `skill/voip-engineering/` — the Claude Code skill

A production skill for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview).
Drop it into `~/.claude/skills/` and Claude becomes a copilot that knows
the gotchas in this handbook. The skill includes:

- Reference docs covering Kamailio routing blocks, FreeSWITCH B2BUA
  patterns, RTPEngine NAT topology, billing integration patterns, etc.
- Battle-tested config templates (Kamailio SBC edge, FreeSWITCH IVR
  dialplan, RTPEngine dual-interface, dSIPRouter call limiting).
- Operational scripts:
  - `voip-doctor.sh` — end-to-end diagnostic with three modes (triage,
    capture with HTML+SVG flow diagram, monitor).
  - `sip_trace.sh`, `check_rtpengine.sh`, `fs_health.sh` — atomic helpers.

See [`skill/voip-engineering/SKILL.md`](skill/voip-engineering/SKILL.md)
for full skill documentation.

### `labs/` — reproducible learning environments

Docker-compose stacks you can spin up on a laptop to practice without
breaking production.

```
labs/
├── 01-hello-sip/             Minimal SIP REGISTER and INVITE
├── 02-kamailio-dispatcher/   Load balancing across two FS backends
├── 03-freeswitch-ivr/        IVR with PRACK interworking
└── 04-full-sbc-stack/        Kamailio + FS + RTPEngine, end-to-end
```

Each lab has a `README.md` with objectives, the `docker-compose.yml`,
expected behavior, and exercises.

### `examples/` — sanitized real-world configs

Production-derived configurations with credentials and internal hostnames
redacted. Useful as starting points or as comparison material.

```
examples/
├── sbc-edge-debian/      Edge SBC on Debian 12
├── ivr-rhel/             IVR stack on RHEL 8 air-gapped
└── billing-cgrates/      Billing integration with CGRateS
```

---

## How to use this

**If you're learning from scratch:**

1. Read `docs/01-foundations/` in order.
2. Run lab `01-hello-sip` and `02-kamailio-dispatcher`.
3. Read `docs/02-components/` for the deep dives.
4. Run the remaining labs.
5. Read `docs/04-operations/common-failures.md` — even before you have
   failures of your own. Pattern-recognition matters.

**If you already operate voice and want to learn the open-source side:**

1. Skim `docs/01-foundations/why-open-source-carrier.md` to align mental
   models.
2. Jump straight to `docs/02-components/` and `docs/03-architectures/`.
3. Install the skill into Claude Code so you have a copilot while you
   build your first stack.

**If you're operating already and have a problem right now:**

1. `docs/04-operations/diagnostics-playbook.md` is your starting point.
2. Run `skill/voip-engineering/scripts/voip-doctor.sh capture` to gather
   evidence before changing anything.
3. Search `docs/04-operations/common-failures.md` for symptoms matching
   yours — odds are someone (probably me) has been there already.

---

## Installing the skill

```bash
# Personal installation (your machine)
cd ~/.claude/skills/
git clone https://github.com/jesus-bazan-entel/carrier-voice-handbook.git temp
mv temp/skill/voip-engineering ./
rm -rf temp

# Or copy from a clone you already have
cp -r ~/repos/carrier-voice-handbook/skill/voip-engineering ~/.claude/skills/

# Verify
claude
> /skills
# Should list voip-engineering
```

For team installation in a project, place it under `.claude/skills/` of
your project repo and commit it.

---

## Stack covered

This handbook focuses on the open-source carrier-class voice stack:

| Component | Role | Coverage |
|---|---|---|
| **[Kamailio](https://www.kamailio.org/)** | SIP proxy / SBC / registrar | Deep |
| **[FreeSWITCH](https://signalwire.com/freeswitch)** | Softswitch / B2BUA / IVR / media | Deep |
| **[RTPEngine](https://github.com/sipwise/rtpengine)** | RTP relay, NAT traversal | Deep |
| **[Asterisk](https://www.asterisk.org/)** | Legacy PBX, when migration is in scope | Moderate |
| **[CGRateS](https://cgrates.org/)** | Real-time billing engine | Moderate |
| **[dSIPRouter](https://dsiprouter.org/)** | Kamailio GUI/management | Light |

Things explicitly out of scope: Asterisk-only PBX deployments,
proprietary SBCs (Oracle/Acme, Ribbon, Sonus), WebRTC gateways used
purely for browser-to-browser, legacy SS7/TDM (briefly mentioned for
context, not for implementation).

---

## On the shoulders of giants

This handbook would not exist without:

- The **Kamailio** team and the open mailing list, which has been the
  single best source of voice signaling knowledge on the internet for
  over a decade.
- The **FreeSWITCH / SignalWire** community, particularly the older
  ConfNumbers archive that taught a generation of engineers how a real
  softswitch behaves.
- The **OpenSIPS** community — even though this handbook focuses on
  Kamailio, OpenSIPS docs and forums saved me more than once.
- The **RTPEngine / Sipwise** team for building and open-sourcing one
  of the few production-grade RTP relays available outside vendor
  contracts.
- The colleagues, mentors, and shift partners across two decades of NOC
  rooms, core network teams, and engineering offices who taught me what
  the docs don't say. You know who you are.

If a chapter, a config, or a script in this repo saves you a midnight,
the credit ultimately belongs to them.

---

## Contributing

Contributions are warmly welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md).

Particularly welcome:

- **War stories**: a real production failure, anonymized, with root
  cause and resolution. These teach more than any tutorial.
- **Regional context**: carrier interconnect quirks in your country,
  regulatory specifics (portability, lawful intercept), local language
  notes.
- **Lab improvements**: cleaner docker-compose, additional exercises,
  alternative scenarios.
- **Translations**: especially Spanish and Portuguese for LATAM
  engineers.

Code of conduct: be kind, be technical, share what you know.

---

## License

[Apache License 2.0](LICENSE) — use it, fork it, build with it,
commercialize it, teach with it. If it saved you a midnight, that's
payment enough.

---

## A note on intent

I publish this in recognition of two decades in network engineering —
from a NOC chair to architecting voice networks for a national
operator — and as a way to leave the path easier than I found it.

The knowledge in here was gathered slowly, often painfully. Sharing it
freely is the part of the work that gives the rest of it meaning.

If you build something good with this, that is enough.

— Jesús Bazán
