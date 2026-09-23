---
name: linux-appliance-hardening
description: Debian 13 as an appliance — dm-verity read-only root, LUKS2 sealed to TPM PCRs, nftables default-deny egress, AppArmor, systemd sandboxing, auditd and rollback-safe management. Load for any OS or hardening work.
---

# Appliance hardening

Design: `spec/11-os-appliance.md`. Verify with
`docs/operations/hardening.md`.

## The shape

Read-only verity root in an A/B pair, one LUKS2 volume for all mutable state.
The root cannot be modified — including by root — so an attacker with code
execution cannot persist into it, and recovery is a reboot into the other
partition (`SZ-OS-008`).

## The sealing policy is the substance

LUKS2 sealed to **PCR 7 and PCR 11**. PCR 7 is Secure Boot state. PCR 11 carries
the UKI's PE sections *and* the boot-phase strings measured by
`systemd-pcrphase*` (`enter-initrd`, `leave-initrd`, `sysinit`, `ready`,
`shutdown`, `final`).

**Seal against the value before `ready`.** PCR 11 advances as boot proceeds, so a
secret sealed early cannot be unsealed once a shell exists — the TPM refuses a
policy that no longer matches. An attacker with root on the *running* appliance
therefore cannot unseal the key protecting data at rest. This is the closest
Debian gets to NetHSM's isolation, and it is the reason to prefer PCR 11 over a
convenient PCR set.

## The thing that will brick an appliance

**A kernel update changes PCR 11 and the disk stops unsealing.** That is the
control working, and it is also the most likely way to lose a box.

- Re-enrol **inside the update transaction, before commit** — never after the
  reboot that would need it.
- A recovery key is generated at provisioning, shown once, never stored on the
  appliance.
- The DCUI surfaces pending re-enrolment. An operator meeting this at boot has
  met it too late.

## Userland

The TCB is large, so the compensating controls must be complete rather than
clever:

- Minimal package set built from a `debootstrap` manifest — not a general install
  with services removed. No compiler, no package manager on the running root.
- Per-service UID, plus `ProtectSystem=strict`, `PrivateTmp`, `PrivateDevices`,
  `NoNewPrivileges`, `RestrictAddressFamilies`, `SystemCallFilter`, and an empty
  `CapabilityBoundingSet` except where the unit's comment argues for one.
- AppArmor in **enforce**, not complain. `signerd` reaches the PC/SC socket and
  nothing else; the web process reaches no device node.
- nftables default-deny inbound **and egress**, with destinations named. An
  appliance that can reach the internet arbitrarily is one bug from being a leak.
- auditd over the signer socket, the LUKS device and the DKEK paths.

## Network changes roll back

Any firewall or network change is transactional and reverts unless connectivity
is confirmed (`SZ-OS-002`). The person making the change is usually remote.

## Definition of done

- [ ] Writing to `/usr` fails; verity reports the expected hash.
- [ ] The disk does not unlock with Secure Boot disabled.
- [ ] **The disk does not unlock from a root shell on the running system.**
- [ ] `nft list ruleset` matches the committed policy; unlisted egress fails.
- [ ] Every unit has a sandbox stanza; a unit without one fails the check.
- [ ] CIS deviations recorded with reasons — a score is not a threat model.
