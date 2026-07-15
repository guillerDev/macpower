---
name: code-quality
description: Explains and runs code-quality tooling — swift-format (formatting), SwiftLint (semantic rules), periphery (dead-code detection), and the git pre-commit hook — via the Makefile. Use when the user asks how to format or lint the code, fix lint/formatting failures, find or remove dead/unused code, set up or bypass the pre-commit/git hook, understand the .swift-format or .swiftlint.yml config, or when about to commit non-trivial Swift changes.
---

# MacPower code quality

Three tools with a **clean separation of concerns** — they must not fight:

| Tool | Owns | Config | Install |
|---|---|---|---|
| **swift-format** (Apple) | Formatting: indentation, line length, braces, imports | `.swift-format` | bundled with the toolchain |
| **SwiftLint** | Semantic/style rules (complexity, naming, force-unwrap, …) | `.swiftlint.yml` | `brew install swiftlint` |
| **periphery** | Unused/dead code | — | `brew install periphery` |

## Commands (Makefile)

```sh
make hooks      # install the git pre-commit hook (one-time, sets core.hooksPath)
make format     # auto-format all sources in place (swift-format)
make lint       # swift-format lint (--strict) + SwiftLint (--strict); the CI gate
make deadcode   # periphery dead-code scan (manual; not a CI gate)
```

**Pre-commit hook** (`.githooks/pre-commit`, enabled by `make hooks`): on commit,
it runs swift-format lint + SwiftLint on the *staged* Swift files and blocks the
commit on any issue (telling you to run `make format`). It's the same gate as CI,
run locally. SwiftLint is skipped gracefully if not installed. To bypass in an
emergency: `git commit --no-verify`.

Underlying invocations:
- `swift format --configuration .swift-format --in-place --recursive Sources Tests`
- `swift format lint --configuration .swift-format --strict --recursive Sources Tests`
- `swiftlint lint --quiet --strict`
- `periphery scan --quiet`

## Golden rules

1. **swift-format owns formatting; SwiftLint owns semantics.** Rules that overlap
   formatting are DISABLED in `.swiftlint.yml` (`line_length`, `opening_brace`,
   `trailing_comma`) so the two tools never disagree. Don't re-enable them.
2. **After editing Swift, run `make format`** before `make lint` — most "lint"
   failures are just formatting and are auto-fixed by the formatter.
3. **`make lint` must stay green** — it's the CI gate (`.github/workflows/ci.yml`
   runs it on every push/PR, with a defensive SwiftLint install step).
4. **periphery is an audit, not a gate** — it needs a full build and can have
   false positives; run it manually and review before deleting.

## Fixing failures

- **swift-format lint fails** → run `make format`, re-run `make lint`. Done.
- **SwiftLint fails** → read the rule name in parentheses (e.g.
  `(cyclomatic_complexity)`). Fix the code, or — if the rule is genuinely wrong
  for a pattern here — adjust `.swiftlint.yml` (raise a threshold or disable the
  rule) with a comment explaining why. Prefer fixing code over disabling rules.
- **A SwiftLint rule conflicts with swift-format** → disable it in
  `.swiftlint.yml` (swift-format wins), don't fight it.
- **periphery reports dead code** → confirm it's truly unused
  (`grep` for real usages vs. assign-only), then remove the property/function.
  Assign-only warnings mean a stored property is set but never read.

## Config intent

`.swift-format`: 4-space indentation, 110-column line length, ordered imports,
one max blank line. `.swiftlint.yml`: short-identifier names allowed
(`i`, `n`, `w`), 3-field tuples allowed, relaxed body-length/complexity for the
SwiftUI views and the IOReport decoder, plus the formatting-overlap and
false-positive rules disabled (with inline comments).

## Notes for the assistant

- When you make non-trivial Swift edits, run `make format` then `make lint`
  before declaring done; both must pass.
- Do NOT silence a lint finding by disabling a rule unless it truly conflicts
  with swift-format or is a false positive for a SwiftUI/interop idiom — and say
  so in a comment. Default to fixing the code.
- After removing code, consider `make deadcode` to catch newly-orphaned symbols.
- The pre-commit hook enforces the same gate locally, but only on **staged**
  files — it's not a substitute for running `make lint` over the whole tree
  after big edits. A fresh clone must run `make hooks` once to enable it
  (`core.hooksPath` is local git config, not committed). Bypass with
  `git commit --no-verify` only in emergencies.
- These are dev-only tools; they never ship in the app.
