# DCUI — the local console

Owner: `dcui-engineer`. Requirements: `SZ-OS-004`, `SZ-OS-005`, `SZ-OS-003`.

## 1. Why a console exists at all

The appliance has no SSH (`SZ-OS-003`). So when the network is misconfigured, the
certificate is wrong, or the appliance will not unlock, there has to be a way in
that does not depend on any of those things working.

That is the DCUI: a persistent fullscreen interface on **tty1**, in the style of
an ESXi console. It exists for the states where the web surface is unreachable,
and it is deliberately unable to do most of what the web surface can.

## 2. What it does

| Shown without authentication | Why it is safe to show |
|------------------------------|------------------------|
| Appliance state — `Operational`, `Locked`, `Failed` | Someone standing at the machine can see whether it is running |
| Hostname, IP addresses, link state | Diagnosing "why can I not reach it" is the reason to be there |
| Whether both HSMs are present | A missing DR unit is visible at a glance |
| **Pending TPM re-enrolment** (`SZ-OS-009`) | The single most useful warning this screen carries |
| Software version and update state | |

Nothing here is a secret, and all of it is visible to anyone with physical access
by other means anyway.

| Behind the maintenance credential | Why it is gated |
|-----------------------------------|-----------------|
| Network and firewall repair | Can lock out or open up |
| Unlock the appliance | It is the unlock |
| Restart services, view recent logs | Operational impact |
| Reset setup mode | The one path back from a completed initialization (`SZ-INS-003`) |
| Factory reset | Destroys the Device Key (`SZ-OS-007`) |

## 3. The maintenance credential (`SZ-OS-005`)

**Separate from every web identity.** Not an admin password that also works here.

The reasoning is that these are different threat models. A web credential is
phishable and is used daily. The console credential is used rarely, by someone
physically present, and it must survive the compromise of the web tier — if it
were the same secret, a stolen admin session would also be console access.

- Rate limited, with an increasing delay, because an attacker at the console has
  unlimited attempts and no network to be blocked on.
- **Auto-relock** after inactivity, and on any TTY switch. An unlocked console in
  a rack is an unlocked appliance, and the person who walked away is not coming
  back to lock it.
- Every authentication and every action is audited (`SZ-AUD-001`), with the
  channel recorded as the console.

## 4. What it must never be

- **Not a shell.** No command entry, no "advanced" mode, no escape into one. The
  DCUI drives the same typed `osd` operations the web surface does
  (`spec/01-architecture.md` §2), so it has exactly the same allowlist.
- **Not reachable over the network.** tty1 and the physical serial console only.
  No screen-sharing, no remote KVM integration in software.
- **Not a bypass.** Actions requiring step-up still require it; actions requiring
  approval cannot be performed here at all. The console is for the appliance, not
  for signing.

The pressure on this specification will be "we need shell access for support".
The answer is a support bundle (`collect_support_bundle()`), which is a typed
operation producing a redacted archive — not a shell.

## 5. Operational details that decide whether it works

- **Persistent.** It respawns if it dies and survives the boot it is most needed
  in. A console that is absent in the `Failed` state is absent exactly when
  someone is standing there.
- **Legible on a bad screen** — a rack KVM at 80×25, low contrast, no colour
  guarantees. Status is conveyed by text and position, never by colour alone.
- **Works at the serial console** with the same layout, because appliances live
  in racks reached by serial.
- **Says what to do next.** "Locked — unlock via the web UI or press U" rather
  than only reporting a state. The person at the console is usually there because
  something is wrong and they do not know the procedure.

## 6. How this is verified

- The DCUI is present and correct in `Operational`, `Locked` and `Failed`, and
  after killing its process.
- No key sequence reaches a shell — asserted by attempting the usual escapes.
- The maintenance credential is not accepted by the web tier, and an admin
  password is not accepted by the console.
- Auto-relock fires on the configured inactivity and on TTY switch.
- Pending TPM re-enrolment appears on the status screen.
- Every console action appears in the audit log with the console as channel.
- The layout is legible at 80×25 and over serial.
