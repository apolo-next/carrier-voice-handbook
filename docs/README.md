# Documentation Index

The handbook itself. Five sections, designed to be read in order if you
are learning, or jumped into directly if you have a problem.

## 01-foundations — *the why and the mental model*

Where this stack came from, how to think about SIP, and how a network
engineer ends up specializing in voice.

- `why-open-source-carrier.md` — When to choose open source over
  Cisco/Ribbon/Sonus, when not to, and what "carrier-class" actually
  means in practice.
- `sip-mental-model.md` — The mental model that makes everything else
  make sense. Methods, dialogs, transactions, in-dialog vs out-of-dialog.
- `from-noc-to-voice.md` — A career path written as it actually
  happened: the skills that compound, the ones that don't, the
  inflection points.

## 02-components — *deep dives into each piece*

What each component is, what it isn't, when to reach for it, and the
production gotchas that the upstream docs don't mention.

- `kamailio-deep-dive.md` — Stateful proxy, routing blocks, modules
  that matter, timer tuning, what Kamailio cannot do.
- `freeswitch-deep-dive.md` — Softswitch / B2BUA, dialplan, ESL, when
  bypass_media is right and when it breaks you.
- `rtpengine-deep-dive.md` — Media relay, NAT topology, kernel module
  vs userspace, transcoding cost.
- `asterisk-when-and-why.md` — Where Asterisk still wins (PBX, queues,
  voicemail), where FreeSWITCH wins (IVR at scale, conferences,
  transcoding), how to migrate.

## 03-architectures — *putting it together*

How the pieces fit into production designs, with diagrams and the
trade-offs of each pattern.

- `edge-sbc-pattern.md` — Carrier-facing SBC: Kamailio + RTPEngine
  topology, ACL, rate limiting, dispatcher, TLS termination.
- `ivr-pattern.md` — Hosted IVR with FreeSWITCH behind Kamailio,
  PRACK interworking, recovering from carrier quirks.
- `billing-integration.md` — Pre-call auth via HTTP async from
  Kamailio, post-call CDR via ESL from FreeSWITCH, when CGRateS
  earns its keep, when a custom Rust engine is the right call.
- `ha-and-scaling.md` — Active-active vs active-passive, dispatcher
  cross-pointing, RTPEngine HA limits, what scales linearly and what
  doesn't.

## 04-operations — *living with this stack in production*

Diagnosis, common failures, and how to be on call without losing your
sanity.

- `diagnostics-playbook.md` — The structured way to troubleshoot a
  voice incident, from "is the SIP arriving" down to MOS analysis.
- `common-failures.md` — A growing collection of war stories: real
  symptom, false leads, root cause, fix, lesson. The single most
  valuable file in this handbook for working engineers.
- `on-call-runbook.md` — A template runbook for voice on-call: alert
  triage, escalation criteria, evidence gathering, postmortem
  template.

## 05-learning-path — *roadmaps and resources*

For engineers building toward this skill set deliberately.

- `beginner-roadmap.md` — Six months from "I know networking, what is
  SIP" to "I can configure a Kamailio dispatcher with backends".
- `intermediate-roadmap.md` — One year from there to "I can design and
  operate an SBC stack" — the harder skills, the production exposure
  needed, the projects to take on.
- `recommended-resources.md` — Books, RFCs, mailing lists, blogs,
  YouTube channels, conferences. Curated, not exhaustive — quality
  over quantity.

---

## Reading order recommendations

**If you're starting from scratch** (network engineer, no voice
background): `01-foundations` in order, then `02-components/` in order,
then run the labs, then `03-architectures` and `04-operations`.

**If you're a senior engineer from a proprietary stack**: skim
`01-foundations/why-open-source-carrier.md`, then jump to
`02-components` and `03-architectures`. Use `04-operations/common-failures.md`
as a "things you don't get for free without a vendor support contract"
reference.

**If you're operating already and have a problem**:
`04-operations/diagnostics-playbook.md` first.
`04-operations/common-failures.md` for symptom matching.
The skill installed in Claude Code as a copilot.
