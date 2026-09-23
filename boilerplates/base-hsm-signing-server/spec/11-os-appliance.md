# OS appliance — hardening, disk encryption and an immutable root

Owner: `linux-hardening-engineer` with `os-control-engineer`. Requirements:
`SZ-OS-001`…`009`, `SZ-HSM-007`…`010`, `SZ-SEC-002`, `SZ-SEC-011`.

The brief is a standard, maintainable OS hardened to NetHSM's standard.
`spec/17-nethsm-parity.md` §1 states what that cannot mean (we do not get Muen's
isolation proof). This document is what it *does* mean.

## 1. The shape: immutable root, encrypted state, nothing in between

The model is the one immutable container hosts converged on independently —
**[Lightwhale](https://lightwhale.asklandd.dk/)** live-boots a ~200 MB read-only
system into RAM with no package manager, and keeps all container data and
configuration on a separate volume that survives reboots
([DEV](https://dev.to/gramian/one-minute-lightwhale-4il6),
[XDA](https://www.xda-developers.com/lightwhale-linux-built-for-docker-containers/));
[Talos Linux](https://www.talos.dev) and Container Linux
([Wikipedia](https://en.wikipedia.org/wiki/Container_Linux)) take the same
position from the other end. It also happens to be NetHSM's shape: a signed
system image on one partition, user data encrypted on another.

We adopt the shape, on Debian 13:

```
┌─ ESP ────────────┐  UKI, signed, measured into PCR 11
├─ root A ─────────┐  read-only, dm-verity, root hash in the UKI
├─ root B ─────────┤  the other half of the A/B pair (SZ-OS-006)
├─ /var (LUKS2) ───┤  Postgres, audit log, wrapped backups, config
└─ /var/log ───────┘  (same LUKS container, separate subvolume)
```

Three properties follow, and each is a requirement rather than a preference:

1. **The root filesystem cannot be modified, including by root.** Not "should not
   be" — `dm-verity` fails the read. An attacker with code execution cannot
   persist by writing a file into the root image.
2. **The root is disposable.** It carries no state, so recovering from a
   compromised or corrupted root is "boot the other partition", not "rebuild the
   appliance".
3. **All state is in one encrypted place**, so "is this data at rest encrypted"
   has one answer rather than one per directory.

**Why not a live-from-RAM root like Lightwhale's.** We keep an on-disk A/B pair
instead, because `SZ-OS-006` requires updates to be verifiable and reversible
without physical media, and a signing appliance is a long-lived box rather than a
re-imaged one. The read-only guarantee is the same; the update path differs.

## 2. Disk encryption, and what it is actually bound to

`/var` is **LUKS2, AES-256-XTS**, with the key sealed to the TPM rather than to a
passphrase typed at every boot.

The sealing policy is where the security lives. `systemd-cryptenroll
--tpm2-device=auto --tpm2-pcrs=…` binds unsealing to PCR values, and the choice
of PCRs decides what an attacker has to defeat:

| PCR | Contents | Why we bind to it |
|-----|----------|-------------------|
| **7** | Secure Boot state and key database | Disabling Secure Boot changes it, so the disk does not unlock on a box where verification was turned off. |
| **11** | Every PE section of the UKI — kernel, initrd, cmdline, os-release — measured by `systemd-stub`, **and the boot-phase strings** `enter-initrd`, `leave-initrd`, `sysinit`, `ready`, `shutdown`, `final` measured by `systemd-pcrphase*` ([systemd `TPM2_PCR_MEASUREMENTS.md`](https://github.com/systemd/systemd/blob/main/docs/TPM2_PCR_MEASUREMENTS.md)) | A modified kernel or initrd cannot unseal. |

**The boot-phase binding is the part worth understanding**, because it is the
closest Debian gets to NetHSM's "only *S-Keyfender* can reach the key store".

PCR 11 is extended again as the boot advances. Seal against the value that exists
**before `ready` is measured**, and the secret becomes unsealable only during
early boot. By the time a login shell exists, PCR 11 has moved on — so an
attacker who obtains root on the *running* appliance cannot ask the TPM to
unseal the Device Key, even with full privileges, because the TPM will refuse a
policy that no longer matches. Compromising the running system does not yield the
secret that protects the data at rest.

This is what `SZ-HSM-010` means by "sealed against firmware measurements", and it
composes with the Locked state: the TPM releases the **Device Key**, and the
Device Key unwraps the **Domain Key** only in the unattended case. In attended
mode the operator's passphrase is still required, and the TPM alone is never
sufficient.

**`--tpm2-with-pin` is enabled by default** for the attended profile, so
possession of the hardware is not by itself possession of the data.

### The operational cost, stated

Binding to PCR 11 means **a kernel update changes the measurement and the disk
stops unsealing.** This is not a defect; it is the control working. It is also
the single most likely way to brick this appliance, so:

- Re-enrolment against the new UKI runs **as part of the update transaction**,
  before the commit step (`SZ-OS-006`), not after the reboot that would need it.
- A **recovery key** is generated at provisioning, displayed once, and never
  stored on the appliance. Without it, a firmware update at the wrong moment is
  unrecoverable.
- The DCUI shows the current PCR policy state and whether re-enrolment is
  pending, because an operator discovering this at boot has discovered it too
  late.

## 3. Hardening the userland

The TCB is large (`spec/17-nethsm-parity.md` §1). The compensating controls are
ordinary, and their value is in being complete rather than clever:

| Control | Applied as |
|---------|-----------|
| **Minimal package set** | Built from a `debootstrap` minbase manifest, not a general-purpose install with services removed. No compilers, no package manager on the running root — there is nothing for it to write to. |
| **Per-service UID + systemd sandboxing** | `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`, `NoNewPrivileges`, `RestrictAddressFamilies`, `SystemCallFilter`, `CapabilityBoundingSet=` empty except where a capability is argued for in the unit's comment. |
| **AppArmor** | Enforce, not complain. `signerd` reaches the PC/SC socket and nothing else; the web process reaches no device node (`SZ-SEC-002`). |
| **nftables** | Default-deny inbound and **default-deny egress**, with the allowed destinations named. A signing appliance that can reach the internet arbitrarily is one exfiltration bug from being a leak. |
| **auditd** | Rules covering the signer socket, the LUKS device, the DKEK paths and every `execve` by the privileged daemon. |
| **sysctl** | `kernel.kptr_restrict=2`, `kernel.dmesg_restrict=1`, `kernel.unprivileged_bpf_disabled=1`, `net.core.bpf_jit_harden=2`, `kernel.yama.ptrace_scope=2` (verify each against Debian 13 before pinning — `SZ-OS-008`). |
| **No SSH by default** | `SZ-OS-003`. Administration is the structured web surface or the DCUI. |
| **Unattended security updates** | For the *state* side only; the root is updated by the A/B path. |

## 4. What "hardened" is checked against

Prose hardening is unverifiable, so the posture is asserted by tests
(`SZ-OS-009`):

- The root is genuinely read-only: writing to `/usr` fails, and `dm-verity`
  reports the expected root hash.
- The disk does not unlock with Secure Boot disabled.
- The disk does not unlock from a rescue shell on the running system (the PCR 11
  phase binding, §2).
- `nft list ruleset` matches the committed policy exactly; egress to an
  unlisted destination fails.
- Every systemd unit has a non-empty sandbox stanza; a unit added without one
  fails the check rather than the review.
- AppArmor is in enforce for every profile, and the web process cannot open
  `/dev/bus/usb/*`.
- The CIS Debian benchmark is run and its **deviations are recorded with a
  reason**, rather than the score being reported. A benchmark score is not a
  threat model.

## 5. Where this is weaker than NetHSM, without hedging

- A Debian kernel is millions of lines and any local privilege escalation in it
  reaches the signer's memory. Muen's isolation is formally verified; ours is a
  composition of mitigations that have each been bypassed before.
- `dm-verity` protects the root, not `/var`. Integrity of the encrypted state
  rests on LUKS2's AEAD and on Postgres, not on a verified boot chain.
- Our entropy is the kernel CSPRNG plus the TPM. NetHSM adds a discrete TRNG and
  **halts** if sources fail (`SZ-SEC-011` adopts the halting behaviour, not the
  second hardware source).

An operator choosing between the two should choose NetHSM if the threat model
includes a remote attacker with kernel exploits, and this appliance if it
includes a team that must patch, audit and operate the thing for five years.
