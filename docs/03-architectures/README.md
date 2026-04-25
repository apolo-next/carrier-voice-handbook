# 03 — Architectures

Patterns for putting the components together into production designs.

## Files in this section

| File | Status | Description |
|---|---|---|
| `edge-sbc-pattern.md` | Planned | Carrier-facing SBC topology with Kamailio + RTPEngine. |
| `ivr-pattern.md` | Planned | Hosted IVR with FreeSWITCH behind Kamailio, PRACK interworking. |
| `billing-integration.md` | Planned | Pre-call auth, post-call CDR, CGRateS vs custom. |
| `ha-and-scaling.md` | Planned | HA models, dispatcher cross-pointing, what scales linearly. |

Each document includes:

- An ASCII or Mermaid diagram of the topology.
- The trade-offs vs. alternatives.
- Required components and config snippets (full configs in `examples/`).
- Operational considerations: monitoring, common failure modes,
  capacity planning.
