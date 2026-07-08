# Releasing

Releases are automated by `.github/workflows/release.yml`, which builds the app,
publishes a GitHub Release with a zipped `MacPower.app`, and (optionally) bumps
the Homebrew cask.

## One-time setup

1. **Create a tap repo** named `homebrew-tap` under your account/org (it can be
   empty).
2. *(Optional, for auto-bump)* Create a Personal Access Token with write access
   to `homebrew-tap` and add it to this repo's secrets as **`TAP_GITHUB_TOKEN`**.
   If you skip this, the workflow still cuts the release; you just update the
   cask's `version`/`sha256` by hand from the release notes.

You do **not** need to create or maintain the cask file yourself: when the token
is set, **every release regenerates** `homebrew-tap/Casks/macpower.rb` from
`packaging/homebrew/macpower.rb` (filling in your owner, version, and sha256).

The template is the **single source of truth** — customise the cask in
`packaging/homebrew/macpower.rb` in *this* repo, not in the tap, and your changes
propagate on the next release. (Manual edits in the tap will be overwritten.)

## Cutting a release

```sh
git tag v1.0.0
git push --tags
```

The workflow then:
1. builds the icon + `dist/MacPower.app` (`Scripts/make_icon.sh`, `Scripts/bundle.sh`),
2. zips it as `MacPower-v1.0.0.zip` and computes its `sha256`,
3. creates the GitHub Release with that asset and install instructions,
4. bumps `version` + `sha256` in `homebrew-tap/Casks/macpower.rb` (if the token
   is set).

You can also trigger it manually from the Actions tab (**workflow_dispatch**)
with a tag input.

## Install (end users)

```sh
brew install --cask <owner>/tap/macpower
```

## Notes

- The app is **ad-hoc signed, not notarized**, so downloaded copies are
  quarantined by Gatekeeper. The cask `caveats` tell users how to clear it. For a
  frictionless install, sign with a Developer ID and notarize (see the signing
  step you'd add before `ditto` in the workflow).
- The runner is `macos-26` so the released app links against the macOS 26 SDK and
  matches local Tahoe builds. Pin to `macos-15` if the preview image is unstable.
