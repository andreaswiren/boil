# DKEK backup and restore

For custodians and administrators. Design and rationale: `spec/05-hsm-dkek.md`.

## Read this before your first ceremony

Three facts decide everything, and the first two are commonly got wrong:

1. **All declared shares are required — `n` of `n`, not `m` of `n`.** The share
   count is fixed by `--dkek-shares` at `--initialize`. Import is incremental,
   and the tool reports `DKEK import pending, N share(s) still missing` until
   every one is in. There is no threshold at the DKEK level.

2. **The `(t,n)` threshold protects a *share's password*, not the DKEK.**
   `--create-dkek-share --pwd-shares-threshold t --pwd-shares-total n` generates
   a random password for that one share and splits *the password* among
   sub-custodians.

   So "3 of 5" configured that way means: this share still must be imported, and
   3 of its 5 password-holders must be present to decrypt it. If you set
   `--dkek-shares 5` expecting 3-of-5 recovery, you have instead created **five
   mandatory shares**. That mistake is invisible until a recovery, when it is
   unfixable.

3. **The Key Check Value is the only proof two devices match.** Eight bytes,
   printed only once the last share has landed. Before that there is nothing to
   compare.

## Order that cannot be undone

`--dkek-shares` is set at `--initialize`, and initialising **destroys every key,
certificate and file on the device**. A device that generated production keys
before its DKEK was configured has two outcomes: those keys are never backed up,
or they are destroyed to fix it.

The appliance enforces this — it refuses to generate a production key on a device
without a settled DKEK Key Check Value. That refusal is protecting you.

## Creating shares

Each custodian, on their own trusted machine, **not on the appliance**:

```
sc-hsm-tool --create-dkek-share <custodian>.pbe
```

Set a strong password when prompted, or split it:

```
sc-hsm-tool --create-dkek-share <custodian>.pbe \
    --pwd-shares-threshold 3 --pwd-shares-total 5
```

The share file is a secret. It never touches the appliance's disk — present it
from removable media and remove it afterwards.

## Importing into the primary

```
sc-hsm-tool --import-dkek-share <custodian>.pbe
```

Repeat for every share. Watch the count go down. When the last one lands the tool
prints the **Key Check Value** — record it in the ceremony minutes.

## Replicating to the DR unit

Initialise the DR device with the **same share count**, import the **same
shares**, and then:

**Compare the two Key Check Values.** Equal means the devices can unwrap each
other's keys. Unequal means the DR unit is decorative, and nothing but this
comparison will tell you — not a successful wrap, not a blob on disk.

## Wrapping and restoring

```
sc-hsm-tool --wrap-key key.wrapped --label <label>      # includes cert + description
sc-hsm-tool --unwrap-key key.wrapped                    # into a matching-KCV device
```

Restore requires step-up authentication and is audited on entry and exit.

**A wrapped blob existing is not a successful backup.** Test recovery on a
schedule: import onto the designated DR token, verify the public key and
certificate fingerprint, and **sign a test vector and verify it**. An unwrap that
returns success is not evidence the key works.

## What is never written down

- A share file or its password on the appliance.
- A password in a command line (`--password` puts it in `/proc` where any local
  user can read it — prefer the prompt).
- The assembled DKEK. It exists only inside the HSM.

The audit record holds share *fingerprints* and the resulting KCV, never share
contents.

## When keys are non-exportable

Most production keys should be. A non-exportable key has no DKEK backup by
design — it cannot be recovered, only replaced, with everything it signed
re-examined. Intake decides this per signing profile and the appliance shows
which profiles are recoverable, so nobody finds out during an outage.
