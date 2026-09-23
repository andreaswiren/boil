# Installer and first-run setup

Owner: `installer-engineer` with `setup-wizard-engineer`. Requirements:
`SZ-INS-001`…`005`, `SZ-HSM-003`, `SZ-OS-009`, `SZ-SEC-011`.

## 1. One command, and what it must not ask

Installation is a single command on a clean Debian 13 host. It is **idempotent**:
running it twice reaches the same state, and running it after a partial failure
resumes rather than compounding.

It never asks for a secret it could generate, and it never generates a secret it
cannot show exactly once. Every interactive prompt is a step someone will
automate wrongly.

## 2. Order, because two steps cannot be undone

```
1. Verify the host          Debian 13, UEFI + Secure Boot, TPM 2.0 present
2. Partition and encrypt    A/B verity roots, LUKS2 /var  (SZ-OS-008, SZ-OS-009)
3. Seal to the TPM          PCR 7 + 11; RECOVERY KEY SHOWN ONCE
4. Entropy gate             refuse to proceed without healthy sources (SZ-SEC-011)
5. Generate the Device Key  only after step 4 passes
6. Install services         signerd, osd, dcui, web, Postgres
7. Hand over to setup mode  one-shot, token-protected
```

Steps 3 and 5 are the irreversible ones:

- **The recovery key is displayed once and never stored on the appliance**
  (`SZ-OS-009`). Without it, a firmware or kernel change at the wrong moment is
  unrecoverable. The installer requires explicit confirmation that it has been
  recorded, and that confirmation is the only place in the product where a
  "yes I wrote it down" checkbox is a real control rather than theatre.
- **The Device Key is generated only after the entropy gate passes**
  (`SZ-SEC-011`). A key generated from weak entropy must be rotated and
  everything it signed re-examined, so the installer halts rather than proceeding
  with a warning.

## 3. Setup mode is one-shot and closes permanently (`SZ-INS-003`)

After installation the appliance is in setup mode, reachable over TLS with a
**token printed on the console** — not a default password, not an open form.

Setup collects: the first administrator (with a second factor enrolled
immediately — `SZ-AUTH-001`), the TLS certificate or CSR, network configuration,
the HSM(s), and the DKEK ceremony trigger.

When setup completes, **setup mode becomes permanently unavailable**. Not
disabled by a flag in the database — the code path is gone until a factory reset
(`SZ-OS-007`) or an explicit reset from the physical console
(`SZ-OS-005`).

The reason is that setup mode is, by construction, the one part of the system
that creates an administrator without an existing administrator. Anything that
can re-enter it is a privilege escalation path, so re-entering it requires
physical presence.

## 4. The DKEK gate (`SZ-HSM-003`)

Setup **refuses to let a production key be generated** on an HSM whose status
does not show a settled DKEK Key Check Value.

Hard stop, not a warning. `--dkek-shares` is fixed at `--initialize`, and
initialising destroys existing keys (`spec/05-hsm-dkek.md` §3), so a device that
generated keys before its DKEK was configured has two outcomes: those keys are
never backed up, or they are destroyed to fix it. The failure otherwise surfaces
months later, when the primary dies.

## 5. Provisioning as an API operation (`SZ-INS-005`)

Everything setup does is available as `POST /api/v1/provision`, so a fleet can be
built reproducibly rather than by a human repeating a browser flow.

It carries the same one-shot property: once provisioned, the endpoint is gone. A
reproducible provisioning path that could be re-run would be a reprovisioning
path.

## 6. What the installer refuses

- A host without a TPM, unless attended-only mode is explicitly chosen — and then
  it says that unattended boot is unavailable rather than falling back to an
  unsealed key on disk (`SZ-HSM-010`).
- A host with Secure Boot disabled.
- A non-empty target disk without explicit confirmation naming the disk.
- Any configuration that would leave setup mode reachable after completion.

Each refusal names the condition and what to change. An installer that fails with
a stack trace is an installer people work around.

## 7. Upgrades are not installs

The installer provisions a new appliance. Updating an existing one is the A/B
path (`SZ-OS-006`), and the two are separate code paths so that an update cannot
accidentally re-run provisioning.

**TPM re-enrolment happens inside the update transaction, before commit**
(`SZ-OS-009`) — a kernel change alters PCR 11, and re-enrolling after the reboot
that needs it is too late.

## 8. How this is verified

- A second run of the installer on a provisioned host changes nothing.
- An interrupted install resumes to the same end state.
- Setup mode is unreachable after completion, including by direct URL and by
  database manipulation.
- The setup token is single-use and expires.
- Production key generation is refused on an HSM without a settled DKEK KCV.
- The installer halts, rather than warning, when an entropy source is unavailable.
- Installation on a host without a TPM either refuses or produces an appliance
  that states unattended boot is unavailable.
- The recovery key appears exactly once and is absent from the filesystem
  afterwards — checked by scanning.
