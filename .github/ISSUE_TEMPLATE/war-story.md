---
name: War story submission
about: Share a real production failure you've debugged. These teach more than tutorials.
title: '[War story] Brief symptom — '
labels: ['war-story', 'docs']
---

## Symptom

What did the user / monitor / business see? Be concrete.

## Stack

- Kamailio version:
- FreeSWITCH version:
- RTPEngine version:
- OS:
- Other relevant components:

## False leads

What did you initially think the cause was? What did you change that
didn't fix it? This part is often the most useful for readers.

## Root cause

The actual mechanism. The smaller and more specific you can make this,
the better.

## Fix

Concrete steps. Config diff if relevant. Verification command.

## Lesson

One sentence. What would have prevented this?

## OK to publish

- [ ] No employer-confidential information remains.
- [ ] No real IPs, hostnames, or customer identifiers.
- [ ] No vendor blame (the goal is to teach, not to litigate).
- [ ] I'm OK with this being merged into `docs/04-operations/common-failures.md`
      under my GitHub handle (or a pseudonym I've specified below).

**Attribution preference:** _your handle / pseudonym / anonymous_
