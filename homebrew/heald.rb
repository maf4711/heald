class Heald < Formula
  desc "Self-healing macOS system daemon — Apple Intelligence on-device"
  homepage "https://github.com/maf4711/heald"
  url "https://github.com/maf4711/heald/releases/download/v2.0.0/heald"
  sha256 "bc1f269ca62362976e64f930db198d9834556d61ee2f4fc24865004f4dcbba9a"
  version "2.0.0"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  def install
    bin.install "heald"

    system "curl", "-sL", "-o", "com.heald.daemon.plist",
      "https://raw.githubusercontent.com/maf4711/heald/v2.0.0/launchd/com.heald.daemon.plist"
    system "curl", "-sL", "-o", "install.sh",
      "https://raw.githubusercontent.com/maf4711/heald/v2.0.0/install.sh"
    system "curl", "-sL", "-o", "uninstall.sh",
      "https://raw.githubusercontent.com/maf4711/heald/v2.0.0/uninstall.sh"
    system "curl", "-sL", "-o", "heald-top",
      "https://raw.githubusercontent.com/maf4711/heald/main/heald-top"
    system "curl", "-sL", "-o", "heald-top-render.py",
      "https://raw.githubusercontent.com/maf4711/heald/main/heald-top-render.py"

    prefix.install "com.heald.daemon.plist"
    prefix.install "install.sh"
    prefix.install "uninstall.sh"
    bin.install "heald-top"
    bin.install "heald-top-render.py"

    chmod 0755, bin/"heald"
    chmod 0755, bin/"heald-top"
    chmod 0755, bin/"heald-top-render.py"
  end

  def post_install
    (var/"log/heald").mkpath
  end

  def caveats
    <<~EOS
      Requires macOS 26+ with Apple Intelligence enabled (on-device AI).
      No Ollama — same model stack as meisterSiri.

      To start heald:

        #{prefix}/install.sh

      Or manually:

        cp #{prefix}/com.heald.daemon.plist ~/Library/LaunchAgents/
        # set HEALD_API_KEY in the plist EnvironmentVariables
        launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.heald.daemon.plist

      Check:
        heald doctor

      Terminal dashboard:
        heald-top

      Web dashboard: https://heald.merados.com
    EOS
  end

  test do
    assert_match "2.0.0", shell_output("#{bin}/heald --version 2>&1", 0)
  end
end
