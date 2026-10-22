#!/bin/bash
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

set -uo pipefail

ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
tmp="$(mktemp -d /tmp/aurgen-license-detect.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        echo "--- $2 ---"
        cat "$2"
    fi
    exit 1
}

export LIB_INSTALL_DIR="$ROOT/lib"
export AURGEN_ERROR_LOG="$tmp/err.log"
export AURGEN_MODE=test
export color_enabled=0
touch "$AURGEN_ERROR_LOG"
# shellcheck source=../lib/gen-pkgbuild0.sh
source "$ROOT/lib/gen-pkgbuild0.sh"

expect_id() {
    local file="$1"
    local want="$2"
    local got
    got=$(detect_license_spdx "$file") || fail "detect_license_spdx failed for $file"
    [[ "$got" == "$want" ]] || fail "detect_license_spdx $file: got [$got] want [$want]"
}

write_sample() {
    local name="$1"
    shift
    printf '%s\n' "$@" > "$tmp/$name"
    printf '%s\n' "$tmp/$name"
}

mit_title="$(write_sample mit-title.txt 'MIT License' 'Copyright (c) 2026 Example')"
expect_id "$mit_title" MIT

mit_grant="$(write_sample mit-grant.txt 'Permission is hereby granted, free of charge, to any person obtaining a copy')"
expect_id "$mit_grant" MIT

apache="$(write_sample apache.txt 'Apache License' 'Version 2.0, January 2004')"
expect_id "$apache" Apache-2.0

lgpl3="$(write_sample lgpl3.txt 'GNU LESSER GENERAL PUBLIC LICENSE' 'Version 3, 29 June 2007')"
expect_id "$lgpl3" LGPL-3.0-or-later

lgpl21="$(write_sample lgpl21.txt 'GNU LESSER GENERAL PUBLIC LICENSE' 'Version 2.1, February 1999')"
expect_id "$lgpl21" LGPL-2.1-or-later

gpl3="$(write_sample gpl3.txt 'GNU GENERAL PUBLIC LICENSE' 'Version 3, 29 June 2007')"
expect_id "$gpl3" GPL-3.0-or-later

gpl2="$(write_sample gpl2.txt 'GNU GENERAL PUBLIC LICENSE' 'Version 2, June 1991')"
expect_id "$gpl2" GPL-2.0-or-later

agpl="$(write_sample agpl.txt 'GNU AFFERO GENERAL PUBLIC LICENSE' 'Version 3, 19 November 2007')"
expect_id "$agpl" AGPL-3.0-or-later

bsd3="$(write_sample bsd3.txt \
    'Redistribution and use in source and binary forms, with or without' \
    'modification, are permitted provided that the following conditions' \
    'are met:' \
    'Neither the name of the copyright holder nor the names of its')"
expect_id "$bsd3" BSD-3-Clause

bsd2="$(write_sample bsd2.txt \
    'Redistribution and use in source and binary forms, with or without' \
    'modification, are permitted provided that the following conditions' \
    'are met:')"
expect_id "$bsd2" BSD-2-Clause

spdx_wins="$(write_sample spdx-wins.txt 'SPDX-License-Identifier: Apache-2.0' 'MIT License')"
expect_id "$spdx_wins" Apache-2.0

unknown="$(write_sample unknown.txt 'This project is free to use.')"
expect_id "$unknown" custom

spdx_gpl="/usr/share/licenses/spdx/GPL-3.0-or-later.txt"
if [[ -f "$spdx_gpl" ]]; then
    expect_id "$spdx_gpl" GPL-3.0-or-later
fi

stub="$tmp/bin"
mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/gh"
chmod +x "$stub/gh"

new_repo() {
    local name="$1"
    local repo="$tmp/$name"
    mkdir -p "$repo/aur"
    git -C "$repo" init -q
    git -C "$repo" config user.email "t@example.com"
    git -C "$repo" config user.name "t"
    git -C "$repo" remote add origin "https://example.com/testuser/testpkg.git"
    printf 'all:\n\t@true\n' > "$repo/Makefile"
    printf 'hello\n' > "$repo/README.md"
    printf '%s\n' 'MIT License' 'Permission is hereby granted, free of charge, to any person obtaining a copy' > "$repo/LICENSE"
    git -C "$repo" add Makefile README.md LICENSE
    git -C "$repo" commit -q -m init
    printf '%s\n' "$repo"
}

run_gen() {
    local repo="$1"
    local label="$2"
    (
        export PATH="$stub:$PATH"
        export LIB_INSTALL_DIR="$ROOT/lib"
        export PROJECT_ROOT="$repo"
        export AUR_DIR="$repo/aur"
        export PKGNAME=testpkg
        export AURGEN_ERROR_LOG="$tmp/${label}.errlog"
        export AURGEN_MODE=test
        export GPG_KEY_ID=TEST_KEY_FOR_DRY_RUN
        export color_enabled=0
        # shellcheck source=../lib/gen-pkgbuild0.sh
        source "$ROOT/lib/gen-pkgbuild0.sh"
        load_aurgen_config
        gen_pkgbuild0
    ) >"$tmp/${label}.out" 2>"$tmp/${label}.err"
}

detected_repo="$(new_repo detected)"
if ! run_gen "$detected_repo" detected; then
    fail "gen_pkgbuild0 failed for detected MIT" "$tmp/detected.err"
fi
grep -F -x -q "license=('MIT')" "$detected_repo/aur/PKGBUILD.0" || fail "detected license should be MIT" "$detected_repo/aur/PKGBUILD.0"

# GitHub projects often ship only LICENSE.md: it is detected and installed.
md_repo="$(new_repo markdown)"
git -C "$md_repo" mv LICENSE LICENSE.md
git -C "$md_repo" commit -q -m md
if ! run_gen "$md_repo" markdown; then
    fail "gen_pkgbuild0 failed for LICENSE.md" "$tmp/markdown.err"
fi
grep -F -x -q "license=('MIT')" "$md_repo/aur/PKGBUILD.0" || fail "LICENSE.md should be detected as MIT" "$md_repo/aur/PKGBUILD.0"
grep -E -q '^    for name in .*LICENSE\.md' "$md_repo/aur/PKGBUILD.0" || fail "package() should install LICENSE.md" "$md_repo/aur/PKGBUILD.0"

override_repo="$(new_repo override)"
cat > "$override_repo/aur/aurgen.install.yaml" <<'EOF'
package:
  license:
    - Apache-2.0
EOF
if ! run_gen "$override_repo" override; then
    fail "gen_pkgbuild0 failed for license override" "$tmp/override.err"
fi
grep -F -x -q "license=('Apache-2.0')" "$override_repo/aur/PKGBUILD.0" || fail "package.license should override detection" "$override_repo/aur/PKGBUILD.0"
