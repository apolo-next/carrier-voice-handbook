# Contributing to Carrier Voice Handbook

Thank you for considering a contribution. This handbook gets better with
every engineer who shares what they learned in the trenches.

## What's most welcome

In rough order of value to readers:

1. **War stories** (`docs/04-operations/common-failures.md`) — a real
   production incident, anonymized, with symptoms, root cause, and
   resolution. Even short ones (200-300 words) are extremely valuable.
   No vendor blame, no employer-identifying details, no real customer
   data.

2. **Regional context** — carrier interconnect quirks in your country,
   regulatory specifics (number portability, lawful intercept, emergency
   services), local operator behavior. The internet has tons of US/EU
   content; LATAM, Africa, Southeast Asia and the Middle East are
   underrepresented.

3. **Lab improvements** — cleaner docker-compose, additional exercises,
   alternative scenarios, fixes for breakage caused by upstream changes.

4. **Component deep dives** — if you have production experience with a
   component covered lightly (CGRateS, dSIPRouter, OpenSIPS as
   alternative to Kamailio), a deep-dive PR is welcome.

5. **Translations** — Spanish, Portuguese, French, and other languages
   commonly spoken by working voice engineers. Translate to where you
   are fluent; do not run docs through an LLM and submit the output.

6. **Skill improvements** — new references, refined config templates,
   additional scripts, fixes for the operational scripts.

## What's not welcome

- **AI-generated filler.** Bullet-point summaries of upstream docs,
  generic "what is SIP" content, regurgitated tutorials. The bar is:
  *would this save a real engineer real time on a real problem?*
- **Vendor pitches.** Commercial products may be mentioned in context
  (e.g., "if you're migrating from Ribbon SBC..."), but content
  promoting a product is not the goal of this repo.
- **Employer-confidential information.** If you work at a carrier or
  vendor, sanitize aggressively. When in doubt, ask your employer
  first.
- **Real credentials, real IPs, real hostnames.** Use placeholders
  (`CHANGEME`, `ACME_CARRIER_IP`, `sbc.example.com`).

## How to submit

### For small fixes (typos, broken links, config corrections)

Just open a PR. No issue needed.

### For new content (new doc, new lab, new example)

1. Open an issue first describing what you want to add and why.
2. Wait for a thumbs-up from a maintainer (usually within a week) to
   avoid duplicating work.
3. Submit the PR with the agreed scope.

### Pull request checklist

- [ ] Spelling and grammar checked.
- [ ] All code blocks tested (or marked as untested with a note).
- [ ] No real credentials, IPs, or hostnames.
- [ ] No employer-confidential information.
- [ ] Cross-links to related docs/labs/examples added where helpful.
- [ ] If adding a new file, it appears in the repo's main `README.md`
      under the relevant section.

## Style guide

### Tone

Direct, technical, opinionated. A senior engineer talking to a smart
junior. Not corporate-wiki neutral, not breathless evangelism. If you
have an opinion, state it and explain why.

Bad:

> Kamailio is a powerful, flexible, high-performance SIP server that
> can be used in many scenarios depending on the requirements.

Better:

> Kamailio is a stateful proxy. It does not process media. If your
> design has Kamailio "doing the IVR", that's the wrong tool — you
> need FreeSWITCH or Asterisk.

### Formatting

- Markdown, no HTML. Tables are fine.
- Code blocks must specify language (` ```bash `, ` ```cfg `, etc.).
- Filenames in `backticks`. Commands in `backticks`.
- Headings use Title Case for `#` and `##`, sentence case for `###` and
  below.
- Line length: aim for 80 columns in prose. Code can extend further.

### Code samples

- Every config snippet must indicate which file it goes in.
- Every command must indicate where it runs (host, container, which
  component).
- Use placeholders, never real values.
- Add a "verify with" line where it makes sense.

### War stories

Suggested template:

```markdown
### [Symptom] — [one-line cause]

**Stack:** Kamailio 5.7 + FreeSWITCH 1.10 + RTPEngine mr11 on RHEL 8

**Symptom:**
- What did the user / monitor see?
- What did the logs say?

**False leads:**
- What looked like the cause but wasn't?

**Root cause:**
- The actual mechanism.

**Fix:**
- Concrete steps. Config diff if relevant.

**Lesson:**
- One sentence — what would have prevented this.
```

Stories that follow this template land merged faster.

## Review process

- All PRs are reviewed before merging.
- Expect feedback within a week. If a PR sits longer, ping in the
  thread — sometimes notifications get lost.
- Reviewers may push commits to your branch with small fixes (fixing
  typos, adjusting format) rather than asking you to revise. If you
  prefer to keep the branch read-only, mention it in the PR.
- Substantive changes always come back as comments for you to address.

## Code of conduct

Be kind. Be technical. Share what you know.

This repo is meant to be the place where the engineer at 2 AM finds
help. Treat that engineer — and every contributor — with the respect
they deserve.

If you see behavior that breaks this, email me directly (see profile)
or open a private security advisory on GitHub.

## Recognition

Every contributor whose work is merged is added to a `CONTRIBUTORS.md`
file. If you'd rather remain pseudonymous or anonymous, say so in your
PR; that's fine.

If you contribute substantial regional content (e.g., an entire chapter
on portability in your country), you'll be listed as a section author.

## License of contributions

By submitting a contribution, you agree that it will be licensed under
the Apache License 2.0, the same as the rest of this repository.
