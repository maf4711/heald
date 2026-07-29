class Heald < Formula
  desc "Self-healing macOS system daemon — Apple Intelligence + auto-update"
  homepage "https://github.com/maf4711/heald"
  url "https://github.com/maf4711/heald/releases/download/v3.1.0/heald"
  sha256 "fc18939f9cbc429d3c78caaae22e2e1c82b56904ca8166d8e7ba305f5deb23ab"
  version "3.1.0"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  def install
    bin.install "heald"
    system "curl", "-sL", "-o", "com.heald.daemon.plist",
      "https://raw.githubusercontent.com/maf4711/heald/v3.1.0/launchd/com.heald.daemon.plist"
    system "curl", "-sL", "-o", "install.sh",
      "https://raw.githubusercontent.com/maf4711/heald/v3.1.0/install.sh"
    system "curl", "-sL", "-o", "uninstall.sh",
      "https://raw.githubusercontent.com/maf4711/heald/v3.1.0/uninstall.sh"
    prefix.install "com.heald.daemon.plist"
    prefix.install "install.sh"
    prefix.install "uninstall.sh"
    chmod 0755, bin/"heald"
  end

  def post_install
    (var/"log/heald").mkpath
  end

  def caveats
    <<~EOS
      Auto-update: managed install at ~/Library/heald/heald checks
      https://heald.sh/api/update every 6h (HEALD_AUTO_UPDATE=0 to disable).

        #{prefix}/install.sh

      CLI:
        heald doctor
        heald update
        heald update --check

      Dashboard: https://heald.sh
    EOS
  end

  test do
    assert_match "3.1.0", shell_output("#{bin}/heald --version 2>&1", 0)
  end
end
