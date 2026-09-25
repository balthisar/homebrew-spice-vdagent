# spice-vdagent for macOS

A SPICE guest agent for **macOS virtual machines**, providing clipboard
sharing between the host and a macOS guest. This is a macOS-focused fork of
[utmapp/vd_agent](https://github.com/utmapp/vd_agent), trimmed down to just
the daemon and launcher needed on macOS, packaged for a normal
`brew install` instead of a signed `.pkg` installer, enabling installation
from the command line or via automation tools such as Ansible.

It ships two binaries:

- **`spice-vdagentd`** — the root daemon. Owns the virtio-serial device and
  the coordination socket other components talk to.
- **`spice-vdagent`** — a per-user process that watches `NSPasteboard` and
  relays clipboard contents over the daemon's socket.

## Compatibility

This works in **any macOS guest whose hypervisor is QEMU underneath and
exposes the standard SPICE virtio-serial clipboard channel** — it does not
depend on any particular front-end, just on QEMU wiring up a
`virtserialport` device named `com.redhat.spice.0`.

| Hypervisor | Clipboard support |
|---|---|
| [UTM](https://mac.getutm.app/)                                     | ✓ Yes |
| Proxmox VE (with SPICE display or clipboard enabled)               | ✓ Yes |
| virt-manager / libvirt (QEMU)                                      | ✓ Yes |
| Raw QEMU with `-device virtserialport,...,name=com.redhat.spice.0` | ✓ Yes |
| VMware Fusion      | ✘ No — VMware uses its own tools, not SPICE |
| VirtualBox         | ✘ No — uses VirtualBox Guest Additions instead |
| Parallels, Hyper-V | ✘ No |

If your hypervisor isn't QEMU-based, this project can't help — you'll need
that hypervisor's own guest tools (VMware Tools, VirtualBox Guest
Additions, etc.) instead.

## Requirements

- macOS 11 (Big Sur) or later, Apple Silicon or Intel
- The guest VM must be configured with a virtio-serial channel named
  `com.redhat.spice.0` (this is what carries clipboard data — check your
  hypervisor's SPICE/clipboard settings if copy/paste doesn't work)
- Xcode Command Line Tools (`xcode-select --install`) — needed to build,
  either via Homebrew or manually

## Install via Homebrew (recommended)

```
brew tap balthisar/spice-vdagent
brew install spice-vdagent
```

This builds from source against Homebrew's `glib` and `spice-protocol`.

### Start it

The daemon (`spice-vdagentd`) needs to run as root, since it owns the
virtio-serial device:

```
sudo brew services start spice-vdagent
```

The per-user clipboard process (`spice-vdagent`) runs as your own user, not
root, so it's installed as a template rather than auto-started. Set it up
once per user account:

```
cp $(brew --prefix)/opt/spice-vdagent/share/spice-vdagent/com.redhat.spice.vdagent.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.redhat.spice.vdagent.plist
```

### Stop / uninstall

```
sudo brew services stop spice-vdagent
launchctl unload ~/Library/LaunchAgents/com.redhat.spice.vdagent.plist
brew uninstall spice-vdagent
```

## Install by building it yourself

If you'd rather not use Homebrew at all, you can build and install
directly, as long as `glib`, `spice-protocol`, and `pkg-config` are
available on your machine (installed however you like — Homebrew,
MacPorts, or built from source — anything `pkg-config` can see works):

```
git clone https://github.com/balthisar/homebrew-spice-vdagent.git
cd homebrew-spice_vdagent
pkg-config --exists glib-2.0 gio-2.0 gio-unix-2.0 spice-protocol && echo "dependencies OK"

make                    # builds both binaries for your Mac's architecture
sudo make install       # installs to /usr/local/bin (override with PREFIX=)
```

To also install and start both launchd services in one step:

```
sudo make install-launchd
```

This installs `spice-vdagentd` as a `LaunchDaemon` (root, starts at boot)
and `spice-vdagent` as a `LaunchAgent` for your user account, and loads
both immediately.

To remove them:

```
sudo make uninstall-launchd
```

## Troubleshooting

- **No clipboard sharing at all**: confirm the guest has a device at
  `/dev/tty.com.redhat.spice.0` (`ls /dev/tty.com.redhat.spice.0`). If it's
  missing, the hypervisor didn't set up the virtio-serial channel — check
  its SPICE/clipboard configuration, not this project.
- **Daemon won't start**: check `/var/log/spice-vdagentd.log`.
- **Works after a fresh login but not before**: make sure the LaunchAgent
  plist is loaded for your specific user account — it's per-user, not
  system-wide.

## License

GPLv3, same as upstream [utmapp/vd_agent](https://github.com/utmapp/vd_agent).
See `COPYING`.

## AI Disclaimer

Although I'm a perfectly capable C programmer, I am not a Homebrew package
maintainer, and so I used an LLM to help me package this for distribution via
Homebrew.

