# Makefile for spice-vdagentd / spice-vdagent on macOS (x86_64 or arm64).
#
# Replaces vd_agent.xcodeproj for this fork. Links dynamically against
# Homebrew's glib and spice-protocol instead of Xcode's lipo'd
# static-universal build. Single-arch per build (matches how Homebrew
# builds a separate bottle per architecture) rather than a universal
# binary - override with ARCH= if the auto-detected host arch is wrong
# (e.g. cross-building).
#
# Requires: clang, swiftc (Xcode Command Line Tools), pkg-config,
#           the "glib" and "spice-protocol" formulae.

PREFIX      ?= /usr/local
CC          ?= clang
SWIFTC      ?= swiftc
PKG_CONFIG  ?= pkg-config

ARCH        ?= $(shell uname -m)
ifeq ($(ARCH),arm64)
  DEPLOY_TARGET := 11.0
else
  DEPLOY_TARGET := 10.13
endif

# spice-protocol's own .pc file already bakes in "-I${includedir}/spice-1"
# as its Cflags, so just adding it to this list is enough - no manual path
# guessing, no dependency on Homebrew specifically. Works the same whether
# glib/spice-protocol came from Homebrew, MacPorts, or a manual install, as
# long as pkg-config can see their .pc files (PKG_CONFIG_PATH).
PKGS        := glib-2.0 gio-2.0 gio-unix-2.0 spice-protocol
PKG_CFLAGS  := $(shell $(PKG_CONFIG) --cflags $(PKGS))
PKG_LIBS    := $(shell $(PKG_CONFIG) --libs $(PKGS))

CFLAGS  += -O2 -Wall -arch $(ARCH) -mmacosx-version-min=$(DEPLOY_TARGET) \
           -Isrc -Isrc/darwin $(PKG_CFLAGS)
LDFLAGS += -arch $(ARCH) -mmacosx-version-min=$(DEPLOY_TARGET)

VDAGENTD_BIN := spice-vdagentd
VDAGENT_BIN  := spice-vdagent

VDAGENTD_SRCS := src/udscs.c \
                 src/vdagent-connection.c \
                 src/vdagentd/virtio-port.c \
                 src/vdagentd/vdagentd.c \
                 src/vdagentd/dummy-session-info.c

VDAGENT_C_SRCS := src/udscs.c \
                  src/vdagent-connection.c \
                  src/darwin/vdagent.c

VDAGENT_OBJS := $(VDAGENT_C_SRCS:.c=.o)

.PHONY: all clean install install-launchd uninstall-launchd

all: $(VDAGENTD_BIN) $(VDAGENT_BIN)

$(VDAGENTD_BIN): $(VDAGENTD_SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(VDAGENTD_SRCS) $(PKG_LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(VDAGENT_BIN): $(VDAGENT_OBJS) src/darwin/Vdagent.swift
	$(SWIFTC) -O -target $(ARCH)-apple-macosx$(DEPLOY_TARGET) \
		-import-objc-header src/darwin/vdagent.h \
		-Xcc -Isrc -Xcc -Isrc/darwin \
		$(shell $(PKG_CONFIG) --cflags-only-I $(PKGS) | sed 's/-I/-Xcc -I/g') \
		src/darwin/Vdagent.swift $(VDAGENT_OBJS) \
		-o $@ \
		-framework AppKit -framework Foundation \
		-Xlinker -L$(shell $(PKG_CONFIG) --variable=libdir glib-2.0) \
		$(PKG_LIBS)

install: all
	install -d $(PREFIX)/bin
	install -m 755 $(VDAGENTD_BIN) $(PREFIX)/bin/$(VDAGENTD_BIN)
	install -m 755 $(VDAGENT_BIN) $(PREFIX)/bin/$(VDAGENT_BIN)

# Manual/testing path outside brew services - see the formula's `service`
# block and `caveats` for how this normally happens via `brew services`.
REAL_USER := $(if $(SUDO_USER),$(SUDO_USER),$(USER))
REAL_HOME := $(shell dscl . -read /Users/$(REAL_USER) NFSHomeDirectory 2>/dev/null | awk '{print $$2}')

install-launchd: all
	@test "$$(id -u)" = "0" || { echo "install-launchd must be run with sudo"; exit 1; }
	install -d $(PREFIX)/bin
	install -m 755 $(VDAGENTD_BIN) $(PREFIX)/bin/$(VDAGENTD_BIN)
	install -m 755 $(VDAGENT_BIN) $(PREFIX)/bin/$(VDAGENT_BIN)
	sed 's#<%= PREFIX %>#$(PREFIX)#' data/com.redhat.spice.vdagentd.plist.erb \
		> /Library/LaunchDaemons/com.redhat.spice.vdagentd.plist
	chown root:wheel /Library/LaunchDaemons/com.redhat.spice.vdagentd.plist
	chmod 644 /Library/LaunchDaemons/com.redhat.spice.vdagentd.plist
	launchctl load -w /Library/LaunchDaemons/com.redhat.spice.vdagentd.plist
	install -d -o $(REAL_USER) $(REAL_HOME)/Library/LaunchAgents
	sed 's#<%= PREFIX %>#$(PREFIX)#' data/com.redhat.spice.vdagent.plist.erb \
		> $(REAL_HOME)/Library/LaunchAgents/com.redhat.spice.vdagent.plist
	chown $(REAL_USER) $(REAL_HOME)/Library/LaunchAgents/com.redhat.spice.vdagent.plist
	sudo -u $(REAL_USER) launchctl load -w $(REAL_HOME)/Library/LaunchAgents/com.redhat.spice.vdagent.plist

uninstall-launchd:
	-launchctl unload -w /Library/LaunchDaemons/com.redhat.spice.vdagentd.plist 2>/dev/null
	-rm -f /Library/LaunchDaemons/com.redhat.spice.vdagentd.plist
	-sudo -u $(REAL_USER) launchctl unload -w $(REAL_HOME)/Library/LaunchAgents/com.redhat.spice.vdagent.plist 2>/dev/null
	-rm -f $(REAL_HOME)/Library/LaunchAgents/com.redhat.spice.vdagent.plist

clean:
	rm -f $(VDAGENTD_BIN) $(VDAGENT_BIN) $(VDAGENT_OBJS)
