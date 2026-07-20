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

**Generated code** (UniFFI, protobuf/gRPC, SwiftGen, Sourcery, …) is overwritten on
the next regen, so formatting or linting it is wasted churn — exclude it from all
three tools. SwiftLint and periphery exclude by path in their config; **swift-format
has no exclude mechanism**, so if generated files live *inside* the source tree
(e.g. `Generated/`), replace `--recursive $(SOURCES)` with an explicit filtered list:

```make
SWIFT := $(shell find $(SOURCES) -name '*.swift' -not -path '*/Generated/*')
# then: swift format ... $(SWIFT)   (drop --recursive)
```

## Git hooks (`core.hooksPath`)

- **pre-commit** (`.githooks/pre-commit`): run `swift format lint` + SwiftLint on the
  **staged** `*.swift` files (excluding generated paths); block the commit on any
  issue and point the user at `make format`. Skip SwiftLint gracefully if it isn't
  installed, so a fresh clone can still commit.
- **pre-push** (`.githooks/pre-push`): run periphery across the codebase (it needs a
  full build, so keep it out of pre-commit and let it be skipped routinely).
- `core.hooksPath` is **local** git config (not committed), and a repo has exactly
  **one** hooks directory. A fresh clone must run `make hooks` once. In a **polyglot
  repo**, don't point it at a Swift-only `.githooks`: the last writer wins and a
  dependency-install step (e.g. `npm install`'s `prepare`) may reset it — instead make
  the Swift format+lint a **stage inside the repo's shared hook**, alongside the other
  languages' checks. Bypass in emergencies: `git commit --no-verify` /
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
  never read. Keep an intentionally-unused declaration (exercised only by tests, or
  part of a public API) with a `// periphery:ignore` comment.

## Config intent (typical)

- `.swift-format`: e.g. 4-space indentation, a fixed line length (100–120), ordered
  imports, one max blank line. The point is consistency, not the specific numbers.
- `.swiftlint.yml`: allow short identifiers where idiomatic (`i`, `n`, `x`, `vm`),
  relax body/type/file-length limits for view-heavy code without letting them
  balloon, and **disable the rules that overlap swift-format** (with inline comments
  saying why).
- `.periphery.yml`: scan the app's scheme, excluding generated paths.

**Ratchet length thresholds down, never up.** When a file or type sits just under a
limit, that limit is a ceiling to lower as the code shrinks — not a number to raise
for the next offender. Record *why* a threshold is where it is (e.g. "type X is ~N
lines because it owns the whole session state; decompose it, then lower this") so the
debt is visible and directional.

## Notes for the assistant

- After non-trivial Swift edits, run `make format` then `make lint` before declaring
  done — both must pass.
- Don't silence a finding by disabling a rule unless it truly conflicts with
  swift-format or is a false positive for an idiom — and say so in a comment. Default
  to fixing the code.
- After deleting code, run `make deadcode` to catch newly-orphaned symbols. In a
  polyglot repo, prefer the repo-wide dead-code pass for cross-language edges (FFI,
  exported symbols) a Swift-only scan can't see.
- A pre-commit hook enforces the same gate locally, but only on **staged** files —
  not a substitute for running `make lint` over the whole tree after big edits.
- These are dev-only tools; they never ship in the app.
