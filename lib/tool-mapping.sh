#!/bin/bash
# Tool to package mapping for Arch Linux
# Copyright (C) 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Map tool names to their containing packages
# Usage: map_tool_to_package <tool_name>
# Returns: package name that contains the tool
map_tool_to_package() {
    local tool="$1"
    
    # Tool to package mapping for Arch Linux
    case "$tool" in
        7z) echo "7zip" ;;
        apachectl) echo "apache" ;;
        asciidoctor) echo "ruby-asciidoctor" ;;
        bootctl) echo "systemd-boot" ;;
        busctl) echo "systemd" ;;
        cargo) echo "rust" ;;
        convert) echo "imagemagick" ;;
        coredumpctl) echo "systemd" ;;
        dbus-binding-tool) echo "dbus-glib" ;;
        dbus-cleanup-sockets) echo "dbus" ;;
        dbus-daemon) echo "dbus" ;;
        dbus-glib-tool) echo "dbus-glib" ;;
        dbus-gmain) echo "dbus-glib" ;;
        dbus-launch) echo "dbus" ;;
        dbus-monitor) echo "dbus" ;;
        dbus-run-session) echo "dbus" ;;
        dbus-send) echo "dbus" ;;
        dbus-update-activation-environment) echo "dbus" ;;
        dbus-uuidgen) echo "dbus" ;;
        desktop-file-validate) echo "desktop-file-utils" ;;
        ffplay) echo "ffmpeg" ;;
        ffprobe) echo "ffmpeg" ;;
        g-ir-compiler) echo "gobject-introspection" ;;
        g-ir-scanner) echo "gobject-introspection" ;;
        getopt) echo "util-linux" ;;
        gh) echo "github-cli" ;;
        glib-compile-resources) echo "glib2" ;;
        glib-compile-schemas) echo "glib2" ;;
        glib) echo "glib2" ;;
        gpg-agent) echo "gnupg" ;;
        gpg) echo "gnupg" ;;
        gpgconf) echo "gnupg" ;;
        gpgme-config) echo "gpgme" ;;
        gtk-builder-tool) echo "gtk4" ;;
        gtk-encode-symbolic-svg) echo "gtk4" ;;
        gtk-launch) echo "gtk4" ;;
        gtk-query-settings) echo "gtk4" ;;
        gtk) echo "gtk3" ;;
        haskell) echo "ghc" ;;
        hostnamectl) echo "systemd" ;;
        identify) echo "imagemagick" ;;
        java) echo "jdk-openjdk" ;;
        javac) echo "jdk-openjdk" ;;
        journalctl) echo "systemd" ;;
        kernel-install) echo "systemd-boot" ;;
        letsencrypt) echo "certbot" ;;
        libreoffice) echo "libreoffice-still" ;;
        linguist) echo "qt6-tools" ;;
        localectl) echo "systemd" ;;
        loginctl) echo "systemd" ;;
        lrelease) echo "qt6-tools" ;;
        lupdate) echo "qt6-tools" ;;
        makepkg) echo "pacman" ;;
        moc) echo "qt5-base" ;;
        mogrify) echo "imagemagick" ;;
        mongosh) echo "mongodb" ;;
        node) echo "nodejs" ;;
        oggdec) echo "vorbis-tools" ;;
        oggenc) echo "vorbis-tools" ;;
        pip) echo "python-pip" ;;
        pkg-config) echo "pkgconf" ;;
        poetry) echo "python-poetry" ;;
        psql) echo "postgresql" ;;
        python3) echo "python" ;;
        qmake) echo "qt5-base" ;;
        qt) echo "qt6-base" ;;
        rcc) echo "qt6-base" ;;
        redis-cli) echo "redis" ;;
        sqlite3) echo "sqlite" ;;
        ssh) echo "openssh" ;;
        systemctl) echo "systemd" ;;
        systemd-analyze) echo "systemd" ;;
        systemd-delta) echo "systemd" ;;
        systemd-detect-virt) echo "systemd" ;;
        systemd-inhibit) echo "systemd" ;;
        systemd-machine-id-setup) echo "systemd" ;;
        systemd-notify) echo "systemd" ;;
        systemd-path) echo "systemd" ;;
        systemd-run) echo "systemd" ;;
        systemd-socket-activate) echo "systemd" ;;
        systemd-stdio-bridge) echo "systemd" ;;
        systemd-sysusers) echo "systemd" ;;
        systemd-tmpfiles) echo "systemd" ;;
        systemd-tty-ask-password-agent) echo "systemd" ;;
        systemd-umount) echo "systemd" ;;
        systemd-user-sessions) echo "systemd" ;;
        systemd-verify) echo "systemd" ;;
        timedatectl) echo "systemd" ;;
        udevadm) echo "systemd" ;;
        uic) echo "qt5-base" ;;
        ukify) echo "systemd-boot" ;;
        update-desktop-database) echo "desktop-file-utils" ;;
        updpkgsums) echo "pacman-contrib" ;;
        
        # Default: return the tool name as-is if no mapping exists
        *) echo "$tool" ;;
    esac
}
