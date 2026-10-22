# AURGen

**AUR Packaging Automation Script for Arch Linux**

[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)](LICENSE)
[![AUR](https://img.shields.io/aur/version/aurgen)](https://aur.archlinux.org/packages/aurgen)
[![Release](https://img.shields.io/github/v/release/eserlxl/aurgen)](https://github.com/eserlxl/aurgen/releases/latest)

AURGen is a Bash utility that builds Arch Linux AUR packaging files for any GitHub project: a tarball, `PKGBUILD`, and `.SRCINFO`, for a local test install, an AUR release, or a `-git` package. It runs only on GNU/Linux, and it needs GNU Bash 4.4 or newer and GNU getopt from `util-linux`.

## Contents

- [Quick start](#quick-start)
- [Install](#install)
- [Workflow](#workflow)
- [Safety](#safety)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

## Quick start

```sh
aurgen config generate
aurgen test
aurgen aur
aurgen aur-deploy
```

`config generate` writes `aur/aurgen.install.yaml`. `test` dry-runs local, aur, and git. `aur` prepares the release tarball, signature, and PKGBUILD. `aur-deploy` copies that PKGBUILD, `.SRCINFO`, and the file named by `install=` when the PKGBUILD has one.

A project that already has `aur/PKGBUILD` and no `aur/aurgen.install.yaml` is imported on the first run of a mode such as `local` or `aur`; that run then regenerates `aur/PKGBUILD` and keeps the previous file as `aur/PKGBUILD.prev`. `aurgen config import` writes the same config and leaves `aur/PKGBUILD` untouched. Such a project should start with `aurgen config import`, not `config generate`: generate writes a default config, after which the PKGBUILD is never imported.

## Install

On Arch Linux, install the [`aurgen`](https://aur.archlinux.org/packages/aurgen) AUR package (`yay -S aurgen` or `paru -S aurgen`). It pulls in the required tools; `github-cli`, `shellcheck`, `namcap`, and `bubblewrap` are optional dependencies.

From a source checkout:

1. Copy or symlink `bin/aurgen` onto a directory in `$PATH`.
2. Put `lib/` at `/usr/lib/aurgen`, or set `AURGEN_LIB_DIR`. A source checkout uses its own `lib/` unless `RELEASE` is set.
3. Install `bash` (4.4+), `git`, GNU `getopt` (`util-linux`), `makepkg`, `updpkgsums`, `curl`, and `jq`. `gpg` is required for `aur`. `gh`, `shellcheck`, and `namcap` are optional.

A missing required tool prints an install hint.

## Workflow

```sh
aurgen local
aurgen aur
aurgen aur-init
aurgen aur-deploy
```

`aur-init` is only the first time. `aurgen git` then `aurgen aur-deploy` publishes the `-git` package. `aurgen --deploy aur` and `aurgen --deploy git` run that deploy after a successful aur or git run.

## Safety

A generated config sets `auto_push: true`. `aurgen aur-deploy` then pushes to the AUR with `git push origin HEAD:master`. The local branch name does not matter.

`aur-init` deletes an existing local clone after a yes answer. `--dry-run` does not delete or clone.

`local`, `aur`, and `git` delete generated files at startup. An `origin` that is not a GitHub URL is refused before that deletion. `--dry-run` writes those files under `aur/dry-run/` and leaves published `aur/PKGBUILD`, `aur/.SRCINFO`, tarballs, and packages unchanged.

`aurgen clean` deletes generated packages, `aur/PKGBUILD.prev`, `aur/.SRCINFO.prev`, and the golden PKGBUILD files. It leaves `PKGBUILD.0`, `PKGBUILD.HEADER`, and `aurgen.install.yaml`.

## Documentation

### User guides

| Guide | Contents |
| --- | --- |
| [Usage](doc/USAGE.md) | Modes, options, and workflows |
| [PKGBUILD Generation](doc/PKGBUILD-GENERATION.md) | Templates, install configuration, and dependency detection |
| [AUR Integration](doc/AUR-INTEGRATION.md) | Repository setup, deployment, and safety checks |
| [AUR Quick Reference](doc/AUR-QUICK-REFERENCE.md) | Command cheat sheet |
| [AUR](doc/AUR.md) | Packaging files for GitHub projects |

### Maintainer docs

| Guide | Contents |
| --- | --- |
| [Developer Guide](doc/DEVELOPER_GUIDE.md) | Contributing and development workflows |
| [Project Structure](doc/PROJECT-STRUCTURE.md) | Directory layout and design |
| [Release Workflow](doc/RELEASE_WORKFLOW.md) | Version bump, tag, and push |
| [Versioning](doc/VERSIONING.md) | Semantic versioning rules |
| [Mapping System](doc/MAPPING-SYSTEM.md) | Tool name to Arch package mappings |
| [Mapping Expansion](doc/MAPPING-EXPANSION.md) | How new tool mappings are discovered |

## Development

The release gate is the only check before a release. The commands run from the repository root:

```sh
bash tests/run.sh
./bin/aurgen lint
./bin/aurgen test
```

`bash tests/run.sh` runs every `tests/test-*.sh`. `./bin/aurgen lint` runs ShellCheck and `bash -n`. `./bin/aurgen test` dry-runs local, aur, and git.

## License

This project is licensed under the GNU General Public License version 3 or later (GPL-3.0-or-later). See the [LICENSE](LICENSE) file.
