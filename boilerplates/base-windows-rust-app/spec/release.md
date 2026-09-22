# Release Pipeline

Owner: `B10 release-publisher`. Owned paths: `.github/workflows/release.yml`,
`ci/publish/**` (`contracts/ownership.md`).

Requirements: REQ-REL-01..10, REQ-FND-09, REQ-UPD-13, REQ-SBM-01, REQ-SBM-02.
Version fields are `B17`'s (REQ-REL-09); `B10` reads them and never writes them.

---

## 1. One tag, one pipeline

A release is started by pushing an annotated tag `vMAJOR.MINOR.PATCH`. Nothing
else starts a release — no manual dispatch that publishes, no second workflow for
the second forge (REQ-REL-01). A second process drifts, and the drift is only
visible when a client downloads an artefact that one forge has and the other
does not.

```
tag v1.4.0
  └─ .github/workflows/release.yml
       job build      x86_64-pc-windows-msvc, aarch64-pc-windows-msvc (REQ-FND-04)
       job sign       code-sign every executable artefact (REQ-REL-04)
       job sbom       CycloneDX per target (REQ-SBM-01)
       job publish    GitHub + Gitea, both or neither (REQ-REL-08)
       job manifest   signed update manifest, last (REQ-REL-10)
```

The logic lives in `ci/publish/**` as a small Rust binary, not as inline YAML.
The reason is testability: the publish order (§8) is the part that breaks a fleet,
and a shell step in a workflow file cannot be unit-tested.

## 2. Two forges, one code path

Gitea's releases API is GitHub-compatible at the level this pipeline uses it, so
the publisher differs by **endpoint and credential, not by code path**
(REQ-REL-02). One `Publisher` with `base_url`, `upload_base`, `token`. A second
implementation is how the two targets diverge.

| Step | GitHub | Gitea |
|------|--------|-------|
| Create release | `POST https://api.github.com/repos/{owner}/{repo}/releases` | `POST https://<host>/api/v1/repos/{owner}/{repo}/releases` |
| Upload asset | `POST https://uploads.github.com/repos/{owner}/{repo}/releases/{id}/assets?name=<file>`, raw body, `Content-Type` = the asset's media type | `POST https://<host>/api/v1/repos/{owner}/{repo}/releases/{id}/assets?name=<file>`, `multipart/form-data` field `attachment` (or `application/octet-stream`) |
| Credential | `GITHUB_TOKEN` scoped to this repo | `GITEA_TOKEN` (encrypted CI secret) |

Confirmed, 2026-09-22:

- Gitea route and parameters read from source:
  `// swagger:operation POST /repos/{owner}/{repo}/releases repository repoCreateRelease`
  and `POST /repos/{owner}/{repo}/releases/{id}/assets` with a `name` query
  parameter and an `attachment` form field —
  <https://raw.githubusercontent.com/go-gitea/gitea/main/routers/api/v1/repo/release.go>,
  <https://raw.githubusercontent.com/go-gitea/gitea/main/routers/api/v1/repo/release_attachment.go>.
- GitHub asset upload uses the `upload_url` from the create-release response on
  the `uploads.github.com` host, with `name` as a query parameter and the raw
  binary as the body — <https://docs.github.com/en/rest/releases/assets>.

**The one genuine asymmetry is the upload host.** GitHub uploads go to
`uploads.github.com` via the `upload_url` template returned by the create call;
Gitea uploads go to the same host as the API. The publisher therefore stores
`upload_base` separately and, for GitHub, prefers the returned `upload_url` over
a constructed one. Everything else — payload shape, tag, name, body, draft flag,
asset listing — is the same call twice.

`unconfirmed`: the Gitea version in use by the deploying operator. The routes
above are current `main`. **Check:** `B10` runs `GET /api/v1/version` against the
configured Gitea host at pipeline start and records the version in the release
log. A 404 on the assets route means the host is older than the recorded route,
and that is a release-blocking configuration error, not a code change.

## 3. The artefact set

Every release carries all of this, for both architectures where the artefact is
per-architecture (REQ-REL-03):

| Artefact | Name | Produced by | REQ |
|----------|------|-------------|-----|
| Signed executable | `app-<version>-x86_64.exe`, `app-<version>-aarch64.exe` | `B10` build+sign | REQ-FND-04, REQ-REL-04 |
| MSI | `app-<version>-x86_64.msi`, `app-<version>-aarch64.msi` | `cargo-wix` 0.3.9 (`versions/manifest.json`) | REQ-INST-03 |
| SBOM | `app-<version>-<arch>.cdx.json` | `cargo-cyclonedx` 0.5.9 | REQ-SBM-01, REQ-CRA-03 |
| Checksums | `SHA256SUMS` | `B10` | REQ-UPD-04 |
| Update manifest | `update-manifest.json` + `update-manifest.json.minisig` | `B09` format, `B10` publishes | REQ-UPD-02, REQ-REL-10 |
| Release notes | release body | `B17`'s change record | REQ-REL-07 |

The shipped executables are built with `cargo auditable build` (`cargo-auditable`
0.7.6) so the dependency list is **inside** the binary as well as beside it
(REQ-SBM-02). An artefact found on a machine six months from now is auditable
without the release page, which is what a CRA audit asks for
(`compliance/cra/obligations-matrix.md`).

`SHA256SUMS` covers every uploaded file and is itself listed in the update
manifest's signed body. A checksum file that is not covered by a signature is a
courtesy, not a control.

## 4. Code signing

Release artefacts are signed with a real code-signing certificate (REQ-REL-04).
The key is a hardware- or service-held key; the pipeline holds a credential that
authorises a signing operation, not the key material.

Rules, from `contracts/ownership.md` — "Signing keys are nobody's":

1. `B10` **consumes** the signing credential from CI secrets. It never reads it
   into a variable it prints, never writes it to a file in the workspace, never
   uploads it as an artefact, and never logs a command line that contains it.
2. No `echo`, no `set -x`, no `--verbose` on the signing step. A signing tool
   that prints its arguments is invoked with the credential supplied by
   environment or by a file outside the workspace, never as an argument.
3. The credential is an encrypted CI secret. A plaintext CI variable, a
   `.env` file, or a value in `ci/publish/**` is a release-blocking defect.
4. The private key is never in the repository, in a container image, or in a
   build cache. `B09` embeds only the **public** update key (REQ-UPD-03).
5. Signing happens in a job with no third-party action beyond those pinned by
   commit SHA. An unpinned action in the signing job can read the job's secrets.

After signing, the pipeline verifies its own output: every `.exe` and `.msi` is
checked for a valid signature and the expected subject before the publish job
starts (REQ-SEC-02, REQ-INST-08). Signing is not verified by the absence of an
error from the signing tool.

## 5. Version from the tag, compiled in

The version is derived from the tag and compiled into the binary (REQ-REL-05):

1. `ci/publish` parses the tag as semver. A tag that is not semver fails the run
   before anything is built.
2. The parsed version is compared against `VERSION` and the workspace
   `Cargo.toml` — `B17`'s files. A mismatch fails the release. It is a sign the
   tag was pushed before the version bump, and publishing it would ship a binary
   that reports a version nobody released.
3. The version resource in the PE header is written by `winres` from the same
   value, so Explorer's properties dialog, `--version` and the update manifest
   all state one thing (REQ-OBS-03).

A running instance can therefore state exactly what it is, which is the whole
point: a support conversation that starts with "which version" and gets a guess
has already cost more than this step.

## 6. Reproducibility from a tag

The release is reproducible from its tag and the procedure is tested
(REQ-REL-06, REQ-FND-09):

```bash
git checkout v1.4.0
rustup toolchain install $(cat rust-toolchain.toml | grep channel)   # pinned, REQ-FND-02
cargo auditable build --release --locked --target x86_64-pc-windows-msvc
sha256sum target/x86_64-pc-windows-msvc/release/app.exe
```

What makes it hold:

- `--locked` against a committed `Cargo.lock` (REQ-SBM-08).
- One pinned toolchain, recorded in the release log with its exact version and
  the runner image identifier (REQ-FND-02).
- `--remap-path-prefix` so the build directory does not enter the binary.
- `SOURCE_DATE_EPOCH` set from the tag's commit date for any step that embeds a
  timestamp.

**The signed artefact is not bit-identical and cannot be.** An Authenticode
signature embeds a timestamp from a timestamping authority. The reproducibility
claim is therefore over the **pre-signing** binary, and the pipeline records the
pre-signing SHA-256 of every executable in the release log so a third party can
reproduce and compare. Stating the claim over the signed file would be a claim
that fails the first time anyone checks it.

The procedure is exercised in CI on every release: the build job runs twice on
different runners and compares pre-signing hashes. A mismatch fails the release
(REQ-FND-09).

## 7. Release notes, security fixes separated

Notes are generated from `B17`'s change record, not written in the release UI
(REQ-REL-07). Fixed sections, in order:

```markdown
## Security fixes
- CVE-2026-XXXXX / advisory <id> — <component> — severity <CVSS> — fixed in <version>

## Features
## Fixes
## Dependency updates
```

The security section is the same set that sets the `security: true` flag on the
corresponding entry in the update manifest (REQ-UPD-13, REQ-CRA-07). One source,
two outputs: an operator who reads the notes and an operator who reads the
manifest see the same classification. If the two disagree, the release notes are
a description of a different release.

An empty security section is printed as `None in this release` rather than
omitted. A missing heading reads as an oversight; an explicit "none" is a
statement.

## 8. Publish order, and what fails the release

The order is not a preference. It is the control (REQ-REL-08, REQ-REL-10):

1. Create the release on **both** forges as a **draft**.
2. Upload every artefact from §3 except the update manifest, to both.
3. Verify retrievability: `GET` every asset URL on both forges and check the
   SHA-256 against `SHA256SUMS`. A successful upload response is not proof the
   asset is retrievable.
4. Publish (undraft) both releases.
5. **Last**, upload and publish the signed update manifest to both.

**A failed publish to either forge fails the release** (REQ-REL-08). Half
published means the update manifest and the artefacts disagree: clients that
resolve to the forge that has the manifest fetch an artefact URL that 404s on the
other, and an operator comparing the two forges cannot tell which one is the
release. That is worse than no release, because no release leaves every client on
a known-good version.

On any failure, the pipeline rolls back: delete the manifest asset first if it
exists, then re-draft both releases, then exit non-zero with the forge and the
step named. A release left half-published because the pipeline gave up mid-way is
a defect in this file, not an operational surprise.

**The update manifest is published atomically and last** (REQ-REL-10). It is the
only artefact every installed client polls (REQ-UPD-01), so a manifest that names
an artefact which is not yet retrievable breaks every client at once, and it
breaks them in the worst way: they retry, fail, and report an update error to
users who cannot do anything about it (REQ-UPD-11). "Atomically" here means one
upload of one complete file — never an edited-in-place manifest, never a manifest
uploaded before its signature.

## 8a. Verifying the published release as a client (REQ-REL-11)

Step 3 above checks retrievability and the SHA-256 against `SHA256SUMS`, and it
runs inside the pipeline with the pipeline's credentials, network and view of the
forge. That is not the path a user takes. After both releases are published, a
separate job with **no repository credentials** does what an installed client
does, once per forge and once per architecture:

| Step | What it proves |
|------|----------------|
| Resolve the update manifest URL over HTTPS exactly as `crates/update` resolves it (REQ-UPD-01, REQ-UPD-04) | The URL the shipped binary was built with points at the manifest that was just published — not at a staging host, not at a path that resolves only inside CI |
| Verify the manifest's minisign signature with the public key **extracted from the shipped binary**, not from the release page | The key clients actually hold verifies this manifest. A key taken from the release proves the release is self-consistent and nothing more (REQ-UPD-03) |
| Download every artefact the manifest names; check SHA-256 **and** byte count against the manifest | A truncated or wrong-asset upload. `SHA256SUMS` is our file; the manifest is what the client trusts, and those can disagree |
| Verify each artefact's minisign signature, then Authenticode on the exe and the MSI | The signed thing and the published thing are the same thing (REQ-UPD-02, REQ-SEC-02) |
| Run the shipped updater against the real published channel | The whole chain end to end, on the path every user takes |

A failure here fails the release and triggers the §8 rollback, because a release
that a client cannot verify is a release that will fail on every client at once.

The reason this exists as its own step: every check before it verifies what CI
built. None verifies what the forge serves. That gap is where a correct updater
meets an asset attached to the wrong release, a manifest whose URLs resolve only
from inside the build network, or a Gitea instance whose asset route differs by
version (§2). It is the cheapest check in `H8` and the only one that runs the
user's path.

## 9. Failure modes

| Symptom | Cause | What the pipeline does |
|---------|-------|------------------------|
| Tag is not semver | Tag typo | Fail before build (REQ-REL-05) |
| Tag version ≠ `VERSION` | Tag pushed before `B17`'s bump | Fail before build |
| Signing step logs a credential | `set -x` or a verbose flag | Fail the run, rotate the credential, treat as an incident (REQ-REL-04) |
| Signature verify fails after signing | Wrong certificate or truncated upload | Fail before publish (REQ-SEC-02) |
| Asset uploads to GitHub, fails on Gitea | Token scope or host version | Roll back both, fail (REQ-REL-08) |
| Asset retrievable on one forge only | Eventual consistency or partial upload | Step 3 catches it; roll back |
| Artefacts verify in CI, fail for a client | Wrong asset attached, truncated upload, a manifest URL that resolves only inside the build network | §8a catches it; roll back (REQ-REL-11) |
| Manifest published before an artefact | Order violated | Cannot happen by construction; if it does, the order check in `ci/publish` is broken and that is a blocking test failure (REQ-REL-10) |
| Reproducibility hashes differ | Unpinned toolchain, path leak, timestamp | Fail; do not publish an unreproducible release (REQ-FND-09) |
| Advisory gate blocks mid-release | `B11`'s pass found a critical advisory | Fail; the release is not the place to accept that risk (REQ-SBM-03) |

## 10. Definition of done for a release (gate H8)

- [ ] One tag started it; no manual step published anything (REQ-REL-01).
- [ ] §8a passed on both forges and both architectures, from a job holding no
      repository credentials (REQ-REL-11).
- [ ] Both forges carry an identical artefact set (REQ-REL-02, REQ-REL-03).
- [ ] Every executable artefact is signed and the signature verified in CI
      (REQ-REL-04, REQ-SEC-02).
- [ ] The version in the binary equals the tag (REQ-REL-05).
- [ ] Pre-signing hashes recorded and reproduced on a second runner
      (REQ-REL-06, REQ-FND-09).
- [ ] Release notes separate security fixes, and the set matches the manifest's
      `security` flags (REQ-REL-07, REQ-UPD-13).
- [ ] SBOM published per architecture, and embedded in the binary
      (REQ-SBM-01, REQ-SBM-02).
- [ ] The update manifest is the last asset on both forges, signed, and every
      artefact it names was retrieved and checksummed first (REQ-REL-10).
- [ ] No signing credential appears in any log, artefact or file (REQ-REL-04).
