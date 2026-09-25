class SpiceVdagent < Formula
  desc "SPICE guest agent for macOS VMs (clipboard-sharing daemon + launcher)"
  homepage "https://github.com/balthisar/homebrew-spice-vdagent"
  url "https://github.com/balthisar/homebrew-spice-vdagent/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0f0946f3239c68dfbce616f3a2700d9b860bddcee5dd2ce6775e801e645e2307"
  license "GPL-3.0-only"

  depends_on macos: :big_sur
  depends_on xcode: :build
  depends_on "pkg-config" => :build
  depends_on "glib"
  depends_on "spice-protocol"

  def install
    arch = Hardware::CPU.arm? ? "arm64" : "x86_64"

    # pkg-config finds spice-protocol/glib automatically: Homebrew exposes
    # every `depends_on` formula's .pc files on PKG_CONFIG_PATH during the
    # build, same as it does for any other pkg-config-based formula.
    system "make", "ARCH=#{arch}", "PREFIX=#{prefix}", "install"

    # Per-user LaunchAgent for the clipboard process (spice-vdagent). Homebrew
    # only manages one `service` per formula (the root daemon below), so this
    # one is installed as a template for the user to load themselves - see
    # `caveats`.
    inreplace "data/com.redhat.spice.vdagent.plist.erb", "<%= PREFIX %>", HOMEBREW_PREFIX
    (pkgshare/"com.redhat.spice.vdagent.plist").write \
      File.read("data/com.redhat.spice.vdagent.plist.erb").gsub(/<%.*?%>/, "")
  end

  # spice-vdagentd must run as root (it owns the virtio-serial character
  # device and the well-known coordination socket), so this service is
  # started with `sudo brew services start spice-vdagent`.
  service do
    run [opt_bin/"spice-vdagentd", "-x",
         "-s", "/dev/tty.com.redhat.spice.0",
         "-S", "/var/run/spice-vdagent-sock"]
    require_root true
    keep_alive crashed: true
    log_path var/"log/spice-vdagentd.log"
    error_log_path var/"log/spice-vdagentd.log"
  end

  def caveats
    <<~EOS
      spice-vdagentd (the daemon) is a launchd service. Start it with:
        sudo brew services start spice-vdagent

      spice-vdagent (the per-user clipboard process) is not managed by
      `brew services` since it must run as a LaunchAgent for each logged-in
      user, not as root. Install it once per user with:
        cp #{opt_pkgshare}/com.redhat.spice.vdagent.plist ~/Library/LaunchAgents/
        launchctl load ~/Library/LaunchAgents/com.redhat.spice.vdagent.plist

      Both expect the guest's virtio-serial port to be present at
      /dev/tty.com.redhat.spice.0, i.e. the VM was started with a
      virtserialport named com.redhat.spice.0.
    EOS
  end

  test do
    assert_match "spice-vdagentd", shell_output("#{bin}/spice-vdagentd --help 2>&1", 0..1)
    assert_match "spice-vdagent", shell_output("#{bin}/spice-vdagent --help 2>&1", 0..1)
  end
end

