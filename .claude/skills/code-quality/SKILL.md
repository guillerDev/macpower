---
name: code-quality
description: Swift code-quality tooling — swift-format (formatting), SwiftLint (semantic rules), and periphery (dead-code detection), wired through a Makefile and git hooks. Use when setting up or running formatting/linting/dead-code checks, fixing lint or formatting failures, keeping the two linters from fighting, configuring `.swift-format` / `.swiftlint.yml`, adding a pre-commit/pre-push hook, or before committing non-trivial Swift changes.
---

# Swift code quality: swift-format · SwiftLint · periphery

Three tools with a **clean separation of concerns** — set up so they never fight:

| Tool | Owns | Config | Install |
|---|---|---|---|
| **swift-format** (Apple) | Formatting: indentation, line length, braces, import order | `.swift-format` | bundled with the Swift toolchain (`swift format`) |
| **SwiftLint** | Semantic / style rules (complexity, naming, force-unwrap, …) | `.swiftlint.yml` | `brew install swiftlint` |
| **periphery** | Unused / dead code | `.periphery.yml` (optional) | `brew install periphery` |

## Wrap the commands in a Makefile

```make
SOURCES := Sources Tests
FORMAT  := .swift-format

format:                       ## auto-format in place
	swift format --configuration $(FORMAT) --in-place --recursive $(SOURCES)

lint:                         ## the CI gate — both --strict
	swift format lint --configuration $(FORMAT) --strict --recursive $(SOURCES)
	@command -v swiftlint >/dev/null && swiftlint lint --quiet --strict || echo "swiftlint not installed"

deadcode:                     ## audit, not a gate (needs a full build)
	periphery scan --quiet

hooks:                        ## one-time per clone
	git config core.hooksPath .githooks
```

## Git hooks (`core.hooksPath`)

- **pre-commit** (`.githooks/pre-commit`): runs `swift format lint` + SwiftLint on
  the **staged** Swift files; blocks the commit on any issue (tell the user to run
  `make format`). Skip SwiftLint gracefully if it isn't installed.
- **pre-push** (`.githooks/pre-push`): runs periphery across the whole codebase.
- `core.hooksPath` is **local** git config (not committed) — a fresh clone must run
  `make hooks` once. Bypass in emergencies: `git commit --no-verify` /
  `git push --no-verify`.

## Golden rules

1. **swift-format owns formatting; SwiftLint owns semantics.** Disable the
   *formatting-overlap* SwiftLint rules (`line_length`, `opening_brace`,
   `trailing_comma`, `colon`, …) in `.swiftlint.yml` so the two never disagree.
   Don't re-enable them.
2. **After editing Swift, run `make format` before `make lint`.** Most "lint"
   failures are just formatting and are auto-fixed by the formatter.
3. **Keep `make lint` green — it's the CI gate.** Run the same `make lint` in CI on
   every push/PR (with a defensive SwiftLint-install step).
4. **periphery is an audit, not a gate** — it needs a full build and has occasional
   false positives; run it manually and review before deleting.

## Fixing failures

- **swift-format lint fails** → `make format`, then re-run `make lint`. Done.
- **SwiftLint fails** → read the rule name in parentheses (e.g.
  `(cyclomatic_complexity)`). Prefer **fixing the code**; only if the rule is
  genuinely wrong for a pattern, adjust `.swiftlint.yml` (raise a threshold /
  disable it) **with a comment explaining why**.
- **A SwiftLint rule conflicts with swift-format** → disable it in `.swiftlint.yml`
  (swift-format wins); don't fight it.
- **periphery reports dead code** → confirm it's truly unused (grep for real usages
  vs. assign-only) before removing. "Assign-only" means a stored property is set but
  never read. Keep an intentionally-unused declaration (e.g. exercised only by
  tests, or part of a public API) with a `// periphery:ignore` comment.

## Config intent (typical)

- `.swift-format`: e.g. 4-space indentation, a fixed line length (100–120),
  ordered imports, one max blank line.
- `.swiftlint.yml`: allow short identifiers where idiomatic (`i`, `n`, `x`),
  relax body-length / complexity for view-heavy or generated code, and **disable
  the rules that overlap swift-format** (with inline comments saying why).

## Notes for the assistant

- After non-trivial Swift edits, run `make format` then `make lint` before
  declaring done — both must pass.
- Don't silence a finding by disabling a rule unless it truly conflicts with
  swift-format or is a false positive for an idiom — and say so in a comment.
  Default to fixing the code.
- After deleting code, run `make deadcode` to catch newly-orphaned symbols.
- These are dev-only tools; they never ship in the app.
