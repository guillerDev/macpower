---
name: release
description: Explains and drives MacPower's release flow and versioning — how the git tag is the single source of truth, and how pushing a tag builds the app, publishes a GitHub Release, and updates the Homebrew cask. Use when the user asks how releasing or versioning works, how to choose/bump the version (SemVer), wants to cut/publish a new release, or troubleshoot the release/CI workflows or the Homebrew tap.
---

# MacPower release flow

MacPower is distributed as a notarizable (currently ad-hoc-signed) `.app` via a
personal **Homebrew tap**. Releases are fully automated from a **git tag** — you
never hand-edit a version or a cask.

## The pipeline (what happens on `git tag vX.Y.Z && git push --tags`)

```
git tag vX.Y.Z ──> .github/workflows/release.yml (runs on macos-26)
                     1. make_icon.sh        -> Icon/AppIcon.icns
                     2. bundle.sh release   -> dist/MacPower.app  (version = the tag)
                     3. ditto -> MacPower-vX.Y.Z.zip  + sha256
                     4. gh release create   -> GitHub Release with the zip
                     5. regenerate homebrew-tap/Casks/macpower.rb from
                        packaging/homebrew/macpower.rb (owner/version/sha filled in)
```

End users then: `brew install --cask <owner>/tap/macpower`.

## Files that define the flow

| File | Role |
|---|---|
| `.github/workflows/release.yml` | The release job (tag-triggered). |
| `.github/workflows/ci.yml` | On every push/PR: `make test` + build + bundle + verify. |
| `Scripts/bundle.sh` | Builds and assembles `dist/MacPower.app`; derives the version. |
| `Scripts/make_icon.sh` / `make_icon.swift` | Generates `Icon/AppIcon.icns` (git-ignored). |
| `Makefile` | `build` / `test` / `bundle` / `icon` / `run` / `clean`. |
| `packaging/homebrew/macpower.rb` | Cask **template** — the single source of truth for the tap cask. |
| `docs/RELEASING.md` | Human setup + usage doc. |

## How versioning works (single source of truth = the git tag)

**The git tag is the version.** Nothing else is authoritative — no plist, no
constant, no manifest field is edited by hand. To change the version, you create
a new tag; everything downstream derives from it.

### Tag format — SemVer with a leading `v`

Tags are `vMAJOR.MINOR.PATCH` (e.g. `v1.2.0`), following [SemVer](https://semver.org):
- **MAJOR** — incompatible/breaking change (e.g. dropping a supported macOS,
  removing a section, changing the sudoers/helper contract).
- **MINOR** — new functionality, backward compatible (a new section, a new
  metric source, the menu-bar app).
- **PATCH** — backward-compatible bug fixes only (the menu-closing fix, a cask
  deprecation fix).

The leading `v` is part of the **tag** and the **release asset / cask url**
(`MacPower-v1.2.0.zip`, `download/v1.2.0/…`), but the **app/cask version string**
drops it (`1.2.0`). The workflow computes both: `TAG=v1.2.0`,
`steps.ver.outputs.value = ${TAG#v} = 1.2.0`.

### Choosing the next version

```sh
git describe --tags --abbrev=0     # current latest tag, e.g. v1.0.5
```
Decide major/minor/patch from the change since that tag, then tag the next one.
Tags must be **monotonically increasing** and **never reused/moved** (a tag is an
immutable release; Homebrew pins the asset by sha256).

### How the number flows to the artifacts

`Scripts/bundle.sh` resolves the version in priority order:
1. `MACPOWER_VERSION` env — the release workflow passes the tag minus `v`;
2. latest git tag via `git describe --tags` (so local `make bundle` matches);
3. `0.0.0` fallback (fresh clone with no tags).

It stamps that into:
- the `.app`'s `Contents/Info.plist` (`CFBundleShortVersionString` +
  `CFBundleVersion`) — this is what a released app reports;
- the embedded `Sources/MacPower/Info.plist` during the build, then **restores**
  it via a `trap` so the working tree stays clean.

The Homebrew cask's `version "X.Y.Z"` is set from the same value, and its `url`
derives from `version` (so bumping version alone repoints the download).

### Where the version surfaces

- App UI: `AppInfo.version` (reads `CFBundleShortVersionString`) → sidebar footer
  (`vX.Y.Z`) and the Help window header.
- Finder “Get Info”, the release title, the zip name, and the cask.

### Dev vs release

The **committed** `Sources/MacPower/Info.plist` version is only a **dev
placeholder** seen by bare `swift run` / Xcode debug runs. Every real build
(`make bundle`, CI) overwrites it from the tag, so only release artifacts carry a
meaningful version. `CFBundleVersion` (build number) is set equal to the
marketing version here — bump it separately only if you ever ship two builds of
the same version.

## The Homebrew cask is regenerated every release

The tap's `Casks/macpower.rb` is **rebuilt from `packaging/homebrew/macpower.rb`
on each release** (only owner/version/sha256 are substituted). So:
- the template in THIS repo is authoritative — edit the cask there, never in the tap;
- template fixes (e.g. DSL deprecations) propagate on the next release;
- manual edits made directly in the tap are overwritten.

## How to cut a release

1. Ensure `main` is green (CI passing) and the change is committed.
2. Tag and push:
   ```sh
   git tag vX.Y.Z
   git push --tags
   ```
3. Watch the **Release** workflow in the Actions tab. It publishes the GitHub
   Release and (if `TAP_GITHUB_TOKEN` is set) updates the tap cask.
4. Verify: `brew update && brew upgrade --cask <owner>/macpower` (or a fresh
   `brew install --cask <owner>/tap/macpower`).

You can also trigger it manually: Actions → Release → **Run workflow** (workflow_dispatch) with a tag input.

## One-time setup (per the docs)

- A `homebrew-tap` repo under the owner's account (may be empty).
- Repo secret **`TAP_GITHUB_TOKEN`** = a PAT with write access to `homebrew-tap`
  (optional; without it the release still publishes, you bump the cask by hand).

## Troubleshooting

- **`sed: Casks/macpower.rb: No such file or directory`** — old failure mode;
  the workflow now regenerates the cask from the template, so this shouldn't
  recur. Ensure the `homebrew-tap` repo exists (the clone needs it).
- **`depends_on macos` deprecation warning** — fix it in the *template*
  (`packaging/homebrew/macpower.rb`); it propagates on the next release. Current
  correct form: `depends_on macos: :sonoma`.
- **App version doesn't match the tag** — check the release workflow passed
  `MACPOWER_VERSION`; a released `.app` reads `Contents/Info.plist`, which
  `bundle.sh` writes from the tag.
- **Gatekeeper blocks the downloaded app** — it's ad-hoc signed, not notarized.
  Users clear quarantine: `xattr -dr com.apple.quarantine MacPower.app`. For a
  frictionless install, add a Developer-ID sign + notarize step before `ditto`
  in `release.yml`.
- **CI can't build** — `macos-latest` must have Xcode 16+/Swift 6 for the
  tools-version 6.0 manifest; pin to `macos-15` if a future image regresses.

## Notes for the assistant

- To bump the version, do NOT edit plists — create a tag. If asked to prepare a
  release, confirm the desired `vX.Y.Z`, remind about `TAP_GITHUB_TOKEN`, then
  give the tag commands (do not push tags without explicit confirmation).
- The cask must be edited in `packaging/homebrew/macpower.rb`, not in the tap.
