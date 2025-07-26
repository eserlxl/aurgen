#!/bin/bash
# Exclusion words for README dependency detection
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

get_exclude_words() {
    local -a exclude_words=(
        # Common English words
        the and or with from to for in on at by of is are was were be been being
        have has had "do" does did will would could should may might can must shall

        # Package management / version control
        install require depend prerequisite build package version latest stable
        dev master main branch commit tag release download clone

        # Domains / URLs
        url https http www com org net io github gitlab bitbucket

        # Package managers
        pacman apt yum brew

        # Shell & scripting
        script shell terminal command run running executed executing example usage

        # Operating systems / distros
        linux gnu unix bsd macos windows debian ubuntu fedora arch

        # File paths / system dirs
        usr bin lib etc share include local var opt path directory file files
        subdirectories source_dir dest_dir destination

        # Docs & config terms
        configuration default optional comma separated list read only
        permissions format variable octal executable help info usage manual doc
        documentation readme example examples test temp tmp backup logs cache

        # Project meta
        ide vscode idea project pkgbuild pkgname aurgen license author maintainer
        changelog contributing contribution issue issues pull request pr merge
        workflow automation versioning semver log error output environment

        # Tools & utilities
        tools utilities cli parser args getopt getopt_long getopt_short

        # Misc
        excludes exclusions matched match case sensitive insensitive patterns
        exact omit everything content content-based note note1 note2
        github-actions ci cd ci-system pipeline action actions

        # File formats
        markdown md json yaml yml ini toml txt conf

        # Time / misc phrases
        time system systems detailed overview quick reference introduction
        comprehensive based template designed included
    )

    printf '%s\n' "${exclude_words[@]}"
}
