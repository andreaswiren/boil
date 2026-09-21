# Contract: `i18n-namespaces`

**Published by:** A14 (the registry and the rules). **Declared by:** every
domain, for its own namespace only. **Assembled by:** A02.
**Requirements:** REQ-I18N-01, REQ-I18N-02, REQ-I18N-03, REQ-I18N-05, REQ-I18N-06, REQ-I18N-07.

The registry exists so two agents building at the same moment cannot collide on a
key (REQ-I18N-05). It is the same mechanism as the permission catalogue: a domain
owns a namespace, declares keys inside it, and never writes into another's.

## 1. Namespace ownership

A namespace is a single segment. One owner, assigned at the freeze.

| Namespace | Owner | Covers |
|-----------|-------|--------|
| `auth` | A03 | Login, MFA enrolment, recovery codes, OIDC, step-up |
| `rbac` | A04 | Roles, permissions, tenant admin, impersonation banner |
| `nav` | A05 | Navigation labels, shell chrome, command palette |
| `grid` | A07 | Toolbar, filter operators, pagination, the `all` refusal |
| `pwa` | A09 | Install prompt, notification permission, update prompt |
| `canonical` | A10 | Canonical model and field labels, enum value labels |
| `api` | A11 | API key management, the in-app docs chrome |
| `mail` | A12 | Email subjects and bodies |
| `notify` | A12 | Notification titles, bodies, category names |
| `audit` | A13 | Event names, reason templates, console labels |
| `collector` | A15 | Agent enrolment and status |
| `help` | A16 | Help topic titles and navigation |
| `errors` | A02 | One entry per error code in `types/errors.md` |
| `common` | A02 | Yes/no, save/cancel, date labels — only genuinely cross-domain terms |

`common` is the namespace that rots. A key belongs there only if three or more
domains use it with identical meaning; otherwise it belongs to a domain. "It felt
generic" is how `common.name` ends up meaning four different things.

## 2. Key shape

```
key := <namespace> "." <segment> ("." <segment>)*
segment := [a-z][a-zA-Z0-9]*        // camelCase inside a segment
```

Keys are stable identifiers, not English. `auth.mfa.enrolPrompt` is a key;
`auth.mfa.pleaseEnrolYourSecondFactor` is a sentence pretending to be one, and it
becomes wrong the moment the copy changes.

## 3. Declaration

A domain declares its namespace and its keys in its own
`contract.declaration.ts`. A02 fails assembly on a duplicate key or a key
declared outside the declaring agent's namespace, naming both claimants
(`contracts/README.md` §3).

```ts
i18nNamespace: "auth",
i18nKeys: {
  "auth.login.title": { en: "Sign in", sv: "Logga in" },
  "auth.mfa.recoveryCodesRemaining": {
    en: "{count, plural, =0 {No codes left} one {# code left} other {# codes left}}",
    sv: "{count, plural, =0 {Inga koder kvar} one {# kod kvar} other {# koder kvar}}",
  },
},
```

## 4. ICU, because plurals are not string concatenation

Messages are ICU format (REQ-I18N-03). Swedish and English differ in plural
categories, and a `count === 1 ? "code" : "codes"` ternary in a component is both
a hardcoded literal (REQ-I18N-02) and wrong in some locale.

Interpolation is named, never positional. A positional placeholder cannot survive
a translator reordering a sentence, which is the main thing translators do.

## 5. Coverage beyond the UI

REQ-I18N-01 covers the whole application, and these are the four places it is
routinely missed:

| Surface | Locale resolved from |
|---------|----------------------|
| Emails | The recipient's profile, not the sender's request |
| Error responses | The request's `Accept-Language`, since the caller may be a script |
| Audit reason templates | The **reader's** locale at render time; the stored record holds the key and its parameters, not a rendered sentence |
| Help topics | The viewer's profile (REQ-DOC-04) |

Storing a rendered sentence in an audit record makes the trail monolingual
forever and is the one of these four that cannot be fixed later.

## 6. Resolution and fallback

Resolution: user preference → tenant default → `Accept-Language` → system default
(REQ-I18N-04).

Fallback for a missing key: visible in development (rendered as
`⟦auth.mfa.enrolPrompt⟧` so it cannot be mistaken for copy), silent to the base
locale in production, and reported by the coverage check either way
(REQ-I18N-07). A missing key must never render as an empty string — an empty
label looks like a design choice and survives review.

## 7. Adding a locale is data

`en` and `sv` ship (REQ-I18N-06). A new locale is a catalogue, a row in the
supported-locale table, and nothing else — no code change, no new import, no
component edit. If adding a locale requires touching a `.tsx` file, something has
been hardcoded and REQ-I18N-02's check has a hole.

## 8. Additive vs breaking

**Additive** — a new key; a new locale; a new namespace with a new owner; adding
a translation for an existing key.

**Breaking** — renaming a key (every catalogue and call site desynchronises at
once); removing a key; changing a message's parameters, since a caller passing
the old set silently renders a broken string rather than failing; reassigning a
namespace to a different owner. Changing the *wording* of a message is not
breaking — that is the point of having keys.
