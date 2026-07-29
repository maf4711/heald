class Heald < Formula
  desc "Self-healing macOS system daemon — Apple Intelligence + auto-update"
  homepage "https://github.com/maf4711/heald"
  url "https://github.com/maf4711/heald/releases/download/v3.1.1/heald"
  sha256 "23d02ced4b1df0173c58f9afb36520dfdd4ec1dca838650a525ac90d4c12ee38"
  version "3.1.1"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  def install
    bin.install "heald"
  end

  def caveats
    <<~EOS
      Install as managed LaunchAgent (enables auto-update):

        curl -sL https://raw.githubusercontent.com/maf4711/heald/main/install.sh | bash

      Dashboard: https://heald.sh
      Update API: https://heald.sh/api/update
    EOS
  end

  test do
    assert_match "3.1.1", shell_output("#{bin}/heald --version 2>&1", 0)
  end
end
