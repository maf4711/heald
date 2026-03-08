class Heald < Formula
  desc "Self-healing macOS system daemon — monitors, repairs, and reports"
  homepage "https://github.com/maf4711/heald"
  url "https://github.com/maf4711/heald.git", tag: "v1.1.0"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["16.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/heald"

    # Install LaunchAgent plist template
    prefix.install "launchd/com.heald.daemon.plist"
  end

  def post_install
    (var/"log/heald").mkpath
    (Dir.home + "/.heald/data").mkpath rescue nil
  end

  def caveats
    <<~EOS
      To start heald as a LaunchAgent:

        # Copy and configure plist
        cp #{prefix}/com.heald.daemon.plist ~/Library/LaunchAgents/
        sed -i '' "s|USERNAME|$(whoami)|g" ~/Library/LaunchAgents/com.heald.daemon.plist
        # Set your API key in the plist
        # Then load:
        launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.heald.daemon.plist

      Or use the install script:
        ./install.sh

      Optionally install Ollama for AI-powered decisions:
        brew install ollama
        ollama pull qwen3-coder:30b

      Logs:
        log stream --predicate 'subsystem=="com.heald.daemon"' --level info
    EOS
  end

  test do
    assert_match "heald", shell_output("#{bin}/heald --version")
  end
end
