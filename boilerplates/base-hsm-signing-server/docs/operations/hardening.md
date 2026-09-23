# Hardening

The posture is specified in `spec/11-os-appliance.md`. This page is how to
**verify** it on a running appliance, because a hardening document nobody checks
against the machine describes an intention.

Everything here is a read-only check. None of it changes the appliance.

## What you are verifying

| Property | Why it matters |
|----------|----------------|
| Root filesystem is read-only and integrity-verified | An attacker cannot persist into the root |
| State volume is encrypted and TPM-sealed | A stolen disk is ciphertext |
| The seal is bound to boot state | Root on the *running* system cannot unseal it |
| Egress is default-deny | A compromised web tier cannot exfiltrate freely |
| Services are sandboxed and confined | A compromise stays where it landed |

## The checks

**Read-only root.** Writing must fail:
```
touch /usr/test        # must fail: Read-only file system
veritysetup status <root-device>   # must report verity active and the expected hash
```
If a write succeeds, the appliance is not running the verity root — stop and
investigate before using it for production signing.

**Disk encryption and its sealing policy.**
```
cryptsetup luksDump <state-device>     # expect LUKS2, a tpm2 token, and the PCR list
systemd-cryptenroll --tpm2-device=auto <state-device>   # lists enrolled slots
```
Expect PCRs **7 and 11**. PCR 7 covers Secure Boot state; PCR 11 covers the UKI
and the boot phases.

**That the seal is actually bound to boot phase.** This is the check people skip
and it is the most interesting one: from a root shell on the *running* appliance,
attempt to unseal. **It must fail.** PCR 11 has advanced past the sealing policy
by the time a shell exists, so the TPM refuses. If it succeeds, the sealing
policy is wrong and root compromise equals disk compromise.

**Secure Boot.**
```
mokutil --sb-state        # expect: SecureBoot enabled
```
Then confirm the appliance does **not** unlock with it disabled — a test to run
on a spare unit, not in production.

**Firewall, including egress.**
```
nft list ruleset          # must match the committed policy, byte for byte
```
Then confirm a destination that is not on the allowlist is unreachable from the
appliance. Default-deny egress is the control that turns an exfiltration bug into
a failed connection.

**Service confinement.**
```
aa-status                                  # every profile in enforce, none in complain
systemd-analyze security signerd.service   # and osd, web, dcui
```
A profile in complain mode is a profile that is not enforcing. Any unit without a
sandbox stanza is a finding, not a note.

**The web tier has no device access.** From the web service's context, opening
`/dev/bus/usb/*` must fail. That boundary is what keeps a Next.js compromise from
becoming HSM access.

## CIS benchmark

Run it, and record **deviations with reasons** rather than reporting a score. A
benchmark score is not a threat model, and several CIS items conflict with an
appliance design — those are documented decisions, not failures to remediate.

## When a check fails

A failing check is a finding against the owning agent, not something to fix
locally and move on. Fixing it on one appliance leaves every other appliance and
the next build wrong.
