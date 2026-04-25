# SIP — A Mental Model That Holds Up

> **Status:** stub. This will be the second document we write together
> after the structure of the repo is in place.

This document will cover:

- SIP as a transactional protocol, not a request/response one. Why
  this distinction matters.
- The four-layer model: messages, transactions, dialogs, sessions.
- Methods: REGISTER, INVITE, ACK, BYE, CANCEL, OPTIONS, INFO,
  NOTIFY, REFER. What each one really does, with examples.
- In-dialog vs. out-of-dialog: why mid-call BYE works differently
  from initial INVITE, and why this trips people up.
- Provisional vs. final responses, 100rel/PRACK and why they exist.
- Record-Route and Route, loose routing, why this is the source of
  half of all SIP confusion.
- SDP as a separate but coupled negotiation: codec, port, direction.
- What SIP is not: not a media protocol, not a registration database,
  not a billing system. The temptation to make it do those things and
  why it fails.

If you want to contribute, see [CONTRIBUTING.md](../../CONTRIBUTING.md).
