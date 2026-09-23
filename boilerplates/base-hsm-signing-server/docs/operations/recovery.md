# Recovery

You are probably reading this because something is broken. Failure cases first;
the ordinary procedures are at the end.

**Two things to know before you start.**

1. **Full disaster recovery is two procedures**, not one. Restoring a backup
   recovers users, policies, key *metadata* and audit history. It does **not**
   recover private key material — that is the DKEK restore, against the DR HSM,
   with different secrets and different people. Doing only the first leaves an
   appliance that knows about keys it cannot use.
2. **Do not factory-reset to fix something.** It destroys the Device Key, which
   is what makes the disk readable at all. It is the last step, never the first.

---

## The disk will not unlock after an update

**What you see.** At boot, the appliance stops before the services start. The
console reports that the TPM could not unseal the volume key, or prompts for a
passphrase where it never used to.

**What happened.** The update changed the kernel or initrd. PCR 11 measures the
UKI's sections, so its value changed, and the TPM is correctly refusing to
release a key sealed against the old value. This is the control working.

**Fix.**

1. At the prompt, supply the **recovery key** recorded at provisioning.
2. Once booted, re-enrol against the current measurements:
   ```
   systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7+11 --wipe-slot=tpm2 <device>
   ```
   *(Verify the device path and flags against the installed `systemd-cryptenroll`
   before running — `unconfirmed` against Debian 13's exact version.)*
3. Reboot and confirm it unlocks unattended.
4. Record in the audit log why re-enrolment happened.

**Why it happened at all.** Re-enrolment is supposed to run *inside* the update
transaction, before commit. If you met this at boot, that step failed or the
update did not go through the appliance's own update path — worth a finding.

**If you do not have the recovery key**, the data on that volume is not
recoverable. That is the design. Rebuild the appliance and restore from backup,
then do the DKEK restore.

---

## The appliance boots but stays Locked

**What you see.** State reads `Locked`. `GET /health/state` answers; everything
else returns `412`.

This is normal for attended boot. Supply the **unlock passphrase** through the
web UI or `POST /unlock`.

If unattended boot was configured and it is still asking, the TPM did not release
the Device Key — see the previous section. The fallback to attended is
deliberate: it never fails open.

---

## The primary HSM is dead

**Do not initialise the DR unit.** `--initialize` destroys everything on it,
including the DKEK you need.

1. Confirm the DR unit's DKEK **Key Check Value** matches what the ceremony
   minutes record. If it does not, the DR unit was never a replica and the keys
   on the dead primary are gone.
2. Point the appliance at the DR serial. It is addressed by serial, not slot, so
   there is no enumeration order to get right.
3. Sign a test vector with each production key on the DR unit and verify it
   against that key's certificate. An HSM that responds is not an HSM that signs
   correctly.
4. Order a replacement and treat it as a new secondary: initialise it with the
   same share count, import the same shares, and compare KCVs again.

---

## Locked out of the network

The web surface is unreachable and SSH does not exist.

Go to the physical console (tty1 or serial). The DCUI shows current addresses and
link state without authentication. Network repair is behind the **maintenance
credential** — which is not your admin password.

Firewall and network changes are transactional: if connectivity is not confirmed
after the change, they roll back automatically. If you have locked yourself out,
waiting for the rollback window is usually faster than anything else.

---

## Restoring from a backup

**Read this before starting.** A restore into a running appliance is a **partial
restore**: users, keys and namespaces that exist here and are absent from the
backup are **removed**. It makes the state match the backup; it does not merge.

You need **two** secrets: the Backup Passphrase, and the unlock passphrase that
was current **when the backup was taken**. The manifest records which epoch that
was. If they are the same passphrase, you are fine; if it was rotated, check.

1. Upload. Nothing is written yet.
2. Read the diff. It names what will be added and what will be removed. Read the
   removals.
3. Step-up authenticate against that diff.
4. The restore runs in one transaction and is fully audited.
5. **Then do the DKEK restore** if key material needs recovering.

---

## Routine: verifying you could actually recover

Do this quarterly. A backup nobody has restored is a hypothesis.

- Restore the latest backup onto a spare appliance and confirm the diff is empty
  against a known state.
- Compare the DR HSM's KCV against the ceremony record.
- Confirm the recovery key is where your procedure says it is, and readable.
- Confirm audit forwarding is arriving at the SIEM — silence and health look
  identical from here.
