# Homebrew Cask template for MacPower.
#
# Copy this to your tap repo at:  <owner>/homebrew-tap/Casks/macpower.rb
# Replace OWNER with your GitHub username/org. The Release workflow then keeps
# `version` and `sha256` up to date automatically on each tagged release.
cask "macpower" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/OWNER/macpower/releases/download/v#{version}/MacPower-v#{version}.zip"
  name "MacPower"
  desc "Live macOS power-consumption visualiser (no root required)"
  homepage "https://github.com/OWNER/macpower"

  depends_on macos: :tahoe   # macOS 26 (Tahoe) or newer

  app "MacPower.app"

  zap trash: [
    "~/Library/Preferences/com.macpower.app.plist",
  ]

  caveats <<~EOS
    MacPower is ad-hoc signed (not notarized). If macOS blocks it on first
    launch, clear the download quarantine:

      xattr -dr com.apple.quarantine "#{appdir}/MacPower.app"

    The optional "Exact energy" mode installs a passwordless-sudo rule at
    /etc/sudoers.d/macpower-powermetrics via an admin prompt (older versions
    used /etc/sudoers.d/macpower). To remove it:

      sudo rm -f /etc/sudoers.d/macpower-powermetrics /etc/sudoers.d/macpower
  EOS
end
