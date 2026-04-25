# Skill — voip-engineering

This directory contains the [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)
skill that accompanies this handbook.

## What's here

```
voip-engineering/
├── SKILL.md          Entry point — Claude reads this to decide when
│                     to activate, then loads relevant references.
├── references/       Deep technical references (Kamailio, FS, RTPEngine,
│                     Asterisk, billing, diagnostics, architectures).
├── assets/configs/   Battle-tested config templates.
└── scripts/          Operational scripts (voip-doctor, sip_trace,
                      check_rtpengine, fs_health).
```

## Installing

### Personal (single user)

```bash
mkdir -p ~/.claude/skills/
cp -r voip-engineering ~/.claude/skills/
```

Verify:

```bash
claude
> /skills
# voip-engineering should appear in the list
```

### Project (committed to a repo)

```bash
mkdir -p .claude/skills/
cp -r voip-engineering .claude/skills/
git add .claude/skills/voip-engineering
git commit -m "Add voip-engineering skill for Claude Code"
```

This way, anyone who clones the project gets the same Claude behavior
when working on voice-related tasks.

## How the skill activates

Claude Code reads the `description` field in the frontmatter of
`SKILL.md` and decides whether to load the rest of the skill based on
the user's prompt. Triggers include:

- Configuring Kamailio, FreeSWITCH, RTPEngine, or Asterisk.
- Debugging SIP signaling (REGISTER, INVITE, PRACK, redirects).
- Troubleshooting RTP/media flows or NAT issues.
- Designing dialplans, IVRs, or SBC architectures.
- Modifying the operational scripts in `scripts/`.

You don't have to invoke it explicitly — just describe your task as
you normally would, and the skill loads when relevant.

## Operational scripts vs. skill content

`scripts/voip-doctor.sh` and the other scripts are *not* executed by
Claude inside the skill environment. They are operational tools meant
to run on production servers. The skill stores the canonical version;
you deploy copies to `/usr/local/sbin/` (or equivalent) on each VoIP
host.

When you ask Claude to modify a script, it edits the file here. To
deploy the change, you `git pull` on the target servers (or
`scp`/`rsync` the updated script).

See `scripts/voip-doctor.README.md` for the full deployment guide for
the diagnostic tool.

## Relationship to the handbook

The references in `references/` are condensed for use by Claude — they
focus on directives, gotchas, and decision rules, with minimal prose.

The deep-dive documents in [`../docs/02-components/`](../docs/02-components/)
are the human-readable counterparts: longer, more contextual, with
history and decision-making rationale. Read those when you want to
understand; install this skill when you want a copilot.
