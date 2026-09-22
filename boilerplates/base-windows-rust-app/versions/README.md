# Versions

`manifest.json` is the only place a version comes from. Agents read it; they
never write a version from memory (REQ-VER-02).

Owned by **B16 version-validator**. Regenerated and re-validated at gate **H2**,
before anything is added to a `Cargo.toml`. A manifest older than
`policy.staleAfterDays` fails the gate.

## Entry shape

```json
"windows": {
  "latestStable": "0.62.2",
  "pin": "^0.62.2",
  "source": "https://crates.io/api/v1/crates/windows",
  "checkedAt": "2026-09-22T00:00:00Z"
}
```

`source` and `checkedAt` are the point. A version without them is a version
someone remembered, and remembered versions are wrong (REQ-VER-03).

## Re-validating

```bash
# crates.io REJECTS a request with no User-Agent, and the rejection reads like
# a missing crate. If a lookup "fails", check this header before believing it.
UA='User-Agent: boil-version-guard (you@example.com)'
curl -sS -H "$UA" -H 'Accept: application/json' \
  https://crates.io/api/v1/crates/windows \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['crate']['max_stable_version'])"

# The Rust release channel
curl -sS https://static.rust-lang.org/dist/channel-rust-stable.toml \
  | grep -A1 '^\[pkg.rust\]'
```

Reject prereleases, release candidates and git dependencies in a release build
(REQ-VER-01).

## Traps currently recorded

| Item | Trap |
|------|------|
| `windows` / `windows-sys` | Pair the versions deliberately. A mismatched pair compiles and then disagrees about type layout, which surfaces as a memory bug rather than a compile error. |
| `windows` majors | It moves fast, and a major bump can rename types across every FFI call site. That is a reviewed decision with a migration note (REQ-VER-04), and it is confined to `crates/ffi` precisely so the blast radius is one crate. |
| `eframe` / `egui` | The minor versions must match exactly. A mismatch surfaces as a confusing trait-resolution error, not a clear one. |
| `cargo-deny` | Deliberately recorded as unresolved in the manifest. B16 resolves it at H2 rather than inheriting a guess. |
| MSRV | A dependency bump can raise the MSRV above the pinned toolchain. CI tests the MSRV so this fails at the bump rather than on a contributor's machine (REQ-VER-06). |
| `self_update` | Its defaults do not satisfy REQ-UPD-02. Signature verification is ours to add, not its to provide. |

## When a major jumps

1. Do not bump automatically (REQ-VER-04).
2. Write `build/versions-review.md`: what moved, the breaking changes, and what
   in this stack touches them.
3. Confirm the rest of the stack supports it, from the dependency's own release
   notes rather than by assumption.
4. Bump, or pin the previous line with the reason recorded. Either outcome is
   acceptable; an unrecorded one is not.
