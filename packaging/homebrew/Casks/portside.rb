cask "portside" do
  version "1.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_PORTSIDE_ZIP"

  url "https://github.com/springmusk026/Portside/releases/download/v#{version}/Portside.zip"
  name "Portside"
  desc "Menu bar app that shows what's listening on your ports and stops it"
  homepage "https://github.com/springmusk026/Portside"

  depends_on macos: ">= :sonoma"

  app "Portside.app"
  binary "#{appdir}/Portside.app/Contents/MacOS/Portside", target: "portside"

  # Remove once releases are notarized (see CONTRIBUTING.md, Releasing)
  caveats <<~EOS
    Portside isn't notarized yet, so macOS blocks its first launch. To allow it:
      xattr -dr com.apple.quarantine #{appdir}/Portside.app
  EOS

  zap trash: "~/Library/Preferences/io.github.springmusk026.Portside.plist"
end
