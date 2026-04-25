# Examples

Sanitized real-world configurations. Production-derived starting points
with credentials, IPs, and internal hostnames redacted.

## What's planned

| Example | Status | Description |
|---|---|---|
| `sbc-edge-debian/` | Planned | Edge SBC on Debian 12: Kamailio 5.7 + RTPEngine, dual-interface, TLS termination, dispatcher to two backends. |
| `ivr-rhel/` | Planned | IVR stack on RHEL 8 air-gapped: Kamailio + FreeSWITCH + RTPEngine, containerized with Podman. |
| `billing-cgrates/` | Planned | FreeSWITCH integrated with CGRateS for real-time prepaid billing. |

## Difference between `examples/` and `labs/`

- **Labs** are designed for learning. They are minimal, well-commented,
  and meant to be spun up, broken, and rebuilt. They prioritize
  pedagogical clarity over production fidelity.

- **Examples** are designed for borrowing. They reflect choices you'd
  actually make in production — TLS, ACL hardening, sensible logging,
  resource limits, monitoring hooks. They prioritize production
  fidelity over pedagogical clarity.

If you're learning, start with the labs. If you're building something
real and want a starting point, examples are likely closer to what you
need.

## Sanitization rules

Every example has been processed to remove:

- Real IPs (replaced with RFC 5737 documentation ranges or
  placeholders).
- Real hostnames (replaced with `example.com` / `*.local`).
- Credentials (replaced with `CHANGEME`).
- Carrier-specific routing rules that would identify a real operator.
- Internal comments that reference internal teams, projects, or
  ticket numbers.

If you see something that should be sanitized but isn't, please open
an issue or PR.
