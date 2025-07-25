#!/bin/bash
# Tool mapping expansion script for aurgen
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

# Source tool mapping functions
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"

# Configuration
TEMP_DIR="/tmp/aurgen-mapping"
MAPPING_OUTPUT="$TEMP_DIR/expanded-mapping.txt"
ANALYSIS_LOG="$TEMP_DIR/analysis.log"

# Create temp directory
mkdir -p "$TEMP_DIR"

# Log function
log_analysis() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ANALYSIS_LOG"
}

# Analyze Arch Linux packages for common tools
analyze_arch_packages() {
    log_analysis "Analyzing Arch Linux packages..."
    
    # Common development tools and their packages
    local common_tools=(
        # Build systems
        "cmake:cmake"
        "make:make"
        "ninja:ninja"
        "autoconf:autoconf"
        "automake:automake"
        "libtool:libtool"
        "meson:meson"
        
        # Compilers
        "gcc:gcc"
        "clang:clang"
        "g++:gcc"
        "clang++:clang"
        
        # Package managers
        "npm:npm"
        "cargo:rust"
        "maven:maven"
        "gradle:gradle"
        "pip:python-pip"
        "poetry:python-poetry"
        "yarn:yarn"
        
        # Development tools
        "python:python"
        "python3:python"
        "node:nodejs"
        "nodejs:nodejs"
        "rust:rust"
        "go:go"
        "java:jdk-openjdk"
        "javac:jdk-openjdk"
        "ruby:ruby"
        "php:php"
        "perl:perl"
        "lua:lua"
        "haskell:ghc"
        "ghc:ghc"
        "ocaml:ocaml"
        "nim:nim"
        "zig:zig"
        "crystal:crystal"
        "dart:dart"
        "kotlin:kotlin"
        "scala:scala"
        "groovy:groovy"
        "clojure:clojure"
        "erlang:erlang"
        "elixir:elixir"
        
        # Utilities
        "curl:curl"
        "wget:wget"
        "jq:jq"
        "gpg:gnupg"
        "gh:github-cli"
        "shellcheck:shellcheck"
        "bash:bash"
        "git:git"
        "ssh:openssh"
        "rsync:rsync"
        "tar:tar"
        "gzip:gzip"
        "bzip2:bzip2"
        "xz:xz"
        "zstd:zstd"
        "unzip:unzip"
        "zip:zip"
        "7z:p7zip"
        "fakeroot:fakeroot"
        "sudo:sudo"
        
        # Documentation
        "asciidoc:asciidoc"
        "asciidoctor:ruby-asciidoctor"
        "sassc:sassc"
        "pandoc:pandoc"
        "doxygen:doxygen"
        
        # Libraries and frameworks
        "pkg-config:pkgconf"
        "pkgconf:pkgconf"
        "gettext:gettext"
        "intltool:intltool"
        "itstool:itstool"
        "desktop-file-validate:desktop-file-utils"
        "update-desktop-database:desktop-file-utils"
        "gtk-update-icon-cache:gtk-update-icon-cache"
        "glib-compile-schemas:glib2"
        "glib-compile-resources:glib2"
        "gobject-introspection:gobject-introspection"
        "g-ir-compiler:gobject-introspection"
        "g-ir-scanner:gobject-introspection"
        
        # Qt tools
        "qmake:qt6-base"
        "moc:qt6-base"
        "uic:qt6-base"
        "rcc:qt6-base"
        "lrelease:qt6-tools"
        "lupdate:qt6-tools"
        "linguist:qt6-tools"
        
        # GTK tools
        "gtk-builder-tool:gtk4"
        "gtk-encode-symbolic-svg:gtk4"
        "gtk-launch:gtk4"
        "gtk-query-settings:gtk4"
        "gtk-update-icon-cache:gtk-update-icon-cache"
        
        # Image processing
        "convert:imagemagick"
        "identify:imagemagick"
        "mogrify:imagemagick"
        "optipng:optipng"
        "jpegoptim:jpegoptim"
        "pngquant:pngquant"
        "svgo:svgo"
        "inkscape:inkscape"
        "gimp:gimp"
        
        # Audio/Video
        "ffmpeg:ffmpeg"
        "ffprobe:ffmpeg"
        "ffplay:ffmpeg"
        "sox:sox"
        "lame:lame"
        "oggenc:vorbis-tools"
        "oggdec:vorbis-tools"
        "flac:flac"
        "mp3gain:mp3gain"
        
        # Database tools
        "sqlite3:sqlite"
        "psql:postgresql"
        "mysql:mysql"
        "mongosh:mongodb"
        "redis-cli:redis"
        
        # Web development
        "nginx:nginx"
        "apachectl:apache"
        "lighttpd:lighttpd"
        "caddy:caddy"
        "certbot:certbot"
        "letsencrypt:certbot"
        
        # Container tools
        "docker:docker"
        "podman:podman"
        "kubectl:kubectl"
        "helm:helm"
        "terraform:terraform"
        "ansible:ansible"
        
        # Security tools
        "openssl:openssl"
        "gpg-agent:gnupg"
        "gpgconf:gnupg"
        "gpgme-config:gpgme"
        "libreoffice:libreoffice-still"
        "firefox:firefox"
        "chromium:chromium"
        
        # System tools
        "systemctl:systemd"
        "journalctl:systemd"
        "loginctl:systemd"
        "timedatectl:systemd"
        "hostnamectl:systemd"
        "localectl:systemd"
        "busctl:systemd"
        "coredumpctl:systemd"
        "systemd-analyze:systemd"
        "systemd-delta:systemd"
        "systemd-detect-virt:systemd"
        "systemd-inhibit:systemd"
        "systemd-machine-id-setup:systemd"
        "systemd-notify:systemd"
        "systemd-path:systemd"
        "systemd-run:systemd"
        "systemd-socket-activate:systemd"
        "systemd-stdio-bridge:systemd"
        "systemd-sysusers:systemd"
        "systemd-tmpfiles:systemd"
        "systemd-tty-ask-password-agent:systemd"
        "systemd-umount:systemd"
        "systemd-user-sessions:systemd"
        "systemd-verify:systemd"
        "udevadm:systemd"
        "bootctl:systemd-boot"
        "kernel-install:systemd-boot"
        "ukify:systemd-boot"
        "dbus-daemon:dbus"
        "dbus-launch:dbus"
        "dbus-monitor:dbus"
        "dbus-send:dbus"
        "dbus-uuidgen:dbus"
        "dbus-cleanup-sockets:dbus"
        "dbus-run-session:dbus"
        "dbus-update-activation-environment:dbus"
        "dbus-binding-tool:dbus-glib"
        "dbus-glib-tool:dbus-glib"
        "dbus-gmain:dbus-glib"
        "dbus-viewer:dbus-viewer"
        "dbus-x11:dbus-x11"
        "dbus-send:dbus"
        "dbus-monitor:dbus"
        "dbus-launch:dbus"
        "dbus-daemon:dbus"
        "dbus-uuidgen:dbus"
        "dbus-cleanup-sockets:dbus"
        "dbus-run-session:dbus"
        "dbus-update-activation-environment:dbus"
        "dbus-binding-tool:dbus-glib"
        "dbus-glib-tool:dbus-glib"
        "dbus-gmain:dbus-glib"
        "dbus-viewer:dbus-viewer"
        "dbus-x11:dbus-x11"
    )
    
    # Write to output file
    for tool_mapping in "${common_tools[@]}"; do
        echo "$tool_mapping" >> "$MAPPING_OUTPUT"
    done
    
    log_analysis "Added ${#common_tools[@]} common tool mappings"
}

# Analyze AUR packages for dependencies
analyze_aur_packages() {
    log_analysis "Analyzing AUR packages for common dependencies..."
    
    # Get popular AUR packages
    local popular_packages
    popular_packages=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=search&arg=popular" | jq -r '.results[] | .Name' | head -50 2>/dev/null || true)
    
    if [[ -n "$popular_packages" ]]; then
        log_analysis "Found $(echo "$popular_packages" | wc -l) popular AUR packages"
        
        # Analyze each package for dependencies
        while IFS= read -r pkg; do
            if [[ -n "$pkg" ]]; then
                # Get package info
                local pkg_info
                pkg_info=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg=$pkg" 2>/dev/null || true)
                
                if [[ -n "$pkg_info" ]]; then
                    # Extract dependencies
                    local deps
                    deps=$(echo "$pkg_info" | jq -r '.results[0].Depends[]?' 2>/dev/null || true)
                    local makedeps
                    makedeps=$(echo "$pkg_info" | jq -r '.results[0].MakeDepends[]?' 2>/dev/null || true)
                    
                    # Process dependencies
                    for dep in $deps $makedeps; do
                        if [[ -n "$dep" && "$dep" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                            echo "$dep:$dep" >> "$MAPPING_OUTPUT"
                        fi
                    done
                fi
            fi
        done <<< "$popular_packages"
    fi
}

# Analyze system packages for provides
analyze_system_provides() {
    log_analysis "Analyzing system packages for provides..."
    
    # Get packages that provide common tools
    local provides_mappings=()
    
    # Check for packages that provide common tools
    local tools_to_check=(
        "getopt" "updpkgsums" "makepkg" "cmake" "make" "gcc" "clang"
        "python" "node" "rust" "go" "java" "npm" "cargo" "maven" "gradle"
        "curl" "jq" "gpg" "gh" "shellcheck" "bash" "git" "ssh" "rsync"
        "tar" "gzip" "bzip2" "xz" "zstd" "unzip" "zip" "7z" "fakeroot"
        "asciidoc" "sassc" "pkg-config" "gettext" "qmake" "moc" "uic"
        "ffmpeg" "sqlite3" "nginx" "docker" "kubectl" "openssl"
    )
    
    for tool in "${tools_to_check[@]}"; do
        local package
        package=$(pacman -Qo "/usr/bin/$tool" 2>/dev/null | awk '{print $5}' | sed 's/^.*\///' || true)
        if [[ -n "$package" ]]; then
            provides_mappings+=("$tool:$package")
        fi
    done
    
    # Write to output file
    for mapping in "${provides_mappings[@]}"; do
        echo "$mapping" >> "$MAPPING_OUTPUT"
    done
    
    log_analysis "Added ${#provides_mappings[@]} system provides mappings"
}

# Generate expanded mapping
generate_expanded_mapping() {
    log_analysis "Generating expanded mapping..."
    
    # Clear output file
    > "$MAPPING_OUTPUT"
    
    # Run all analyses
    analyze_arch_packages
    analyze_aur_packages
    analyze_system_provides
    
    # Sort and deduplicate
    sort -u "$MAPPING_OUTPUT" -o "$MAPPING_OUTPUT"
    
    # Count results
    local count
    count=$(wc -l < "$MAPPING_OUTPUT")
    log_analysis "Generated $count unique tool mappings"
    
    echo "Expanded mapping saved to: $MAPPING_OUTPUT"
    echo "Analysis log saved to: $ANALYSIS_LOG"
}

# Main function
expand_tool_mapping() {
    echo "Starting tool mapping expansion..."
    generate_expanded_mapping
    echo "Done! Check $MAPPING_OUTPUT for the expanded mapping."
} 