---
name: dcui-ratatui
description: The persistent tty1 DCUI and local maintenance unlock flow in Rust/ratatui. Load for physical console work.
---

# DCUI

Design: `spec/12-dcui.md`.

## Why it exists

There is no SSH (`SZ-OS-003`). When the network is misconfigured, the certificate
is wrong, or the appliance will not unlock, this is the way in that does not
depend on any of those working.

## Never a shell

No command entry, no advanced mode, no escape into one. The DCUI drives the same
typed `osd` operations the web surface does, so it has exactly the same
allowlist. The pressure will be "we need shell for support"; the answer is
`collect_support_bundle()`.

Test the usual escapes deliberately — a TUI library that drops to a shell on some
key combination is a remote-code-execution path with physical presence.

## Two tiers

**Unauthenticated status**: appliance state, hostname and addresses, link state,
both HSMs present, **pending TPM re-enrolment**, version. None of it is secret to
someone standing at the machine, and the re-enrolment warning is the most useful
thing this screen carries.

**Behind the maintenance credential** (`SZ-OS-005`): network repair, unlock,
service restart, recent logs, setup-mode reset, factory reset.

## The maintenance credential is separate

Not an admin password that also works here. Different threat models: a web
credential is phishable and used daily; this one is used rarely by someone
physically present and **must survive compromise of the web tier**.

Rate limit with increasing delay — an attacker at the console has unlimited
attempts and no network to be blocked on. **Auto-relock** on inactivity and on
TTY switch; the person who walked away is not coming back to lock it.

## It must work when everything else does not

- **Persistent**: respawns, and is present in `Failed` — the state where someone
  is most likely standing there.
- **Legible at 80×25**, low contrast, no colour guarantees, and identical over
  serial. Racks are reached by serial.
- **Says what to do next**: "Locked — unlock via the web UI or press U", not just
  a state name.

## Definition of done

- [ ] Present and correct in `Operational`, `Locked` and `Failed`, and after its
      process is killed.
- [ ] No key sequence reaches a shell.
- [ ] The maintenance credential is rejected by the web tier and vice versa.
- [ ] Auto-relock fires on inactivity and TTY switch.
- [ ] Legible at 80×25 and over serial.
