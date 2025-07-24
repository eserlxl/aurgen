# aurgen

**AUR Packaging Automation Script for Arch Linux**

`aurgen` is a Bash utility for automating the creation, maintenance, and testing of Arch Linux AUR packaging files. It streamlines the process of generating tarballs, updating `PKGBUILD` and `.SRCINFO` files, and preparing packages for local testing or AUR submission. It can be used to package software from any GitHub project, not just a specific repository.

> **Note:** This tool is designed for **GNU/Linux** systems only. It requires GNU Bash (v4+), GNU getopt (from util-linux), and other GNU-specific tools.

## Features

- Automates tarball creation, PKGBUILD and .SRCINFO updates
- Supports local builds, AUR release, and -git (VCS) package generation
- Cleans up generated files and artifacts
- Lints Bash scripts with `shellcheck` and `bash -n`
- Regenerates and tests against golden PKGBUILD files for CI
- Provides colored output and detailed error/warning messages
- Prints tool installation hints for missing dependencies
- **Can be used to package software from any GitHub project**

## Installation

Copy or symlink the `bin/aurgen` script to a directory in your `$PATH`, and ensure the `lib/` directory is available at `/usr/lib/aurgen` or adjust the `LIB_INSTALL_DIR` variable accordingly.

## Usage

```sh
aurgen [OPTIONS] MODE
```

### Options

- `-n`, `--no-color`      Disable colored output
- `-a`, `--ascii-armor`   Use ASCII-armored GPG signatures (.asc)
- `-d`, `--dry-run`       Dry run (no changes, for testing)
- `--no-wait`             Skip post-upload wait for asset availability (for CI)
- `-h`, `--help`          Show detailed help and exit
- `--usage`               Show minimal usage and exit

> **All options must appear before the mode.**  
> Example: `aurgen -n --dry-run aur`

### Modes

- **local**: Build and install the package from a local tarball (for testing).
- **aur**: Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload.
- **aur-git**: Generate a PKGBUILD for the -git (VCS) AUR package.
- **clean**: Remove all generated files and directories in the output folder.
- **test**: Run all modes in dry-run mode to check for errors and report results.
- **lint**: Run `shellcheck` and `bash -n` on all Bash scripts for linting.
- **golden**: Regenerate the golden PKGBUILD files for test comparison.

### Example

```sh
aurgen --no-color --dry-run aur
aurgen local
aurgen aur-git
aurgen clean
aurgen test
aurgen lint
aurgen golden
```

## Directory Structure

- `bin/aurgen` — Main CLI entrypoint
- `lib/` — Helper libraries and mode scripts
  - `helpers.sh`, `init.sh`, `valid-modes.sh`, etc.
  - `modes/` — Mode-specific logic (`aur.sh`, `local.sh`, `aur-git.sh`, etc.)
- `doc/AUR.md` — Detailed documentation and usage notes
- `test/` — Test logs and artifacts
- `golden/` — Golden PKGBUILD files for test comparison
- `Backups/` — (Optional) Backup files

## Requirements

- GNU Bash 4+
- GNU getopt (from util-linux)
- Standard Arch packaging tools: `makepkg`, `updpkgsums`, `curl`, `gpg`, `jq`
- Optional: `shellcheck` for linting

## License

This project is licensed under the **GNU General Public License v3.0 or later**. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions, bug reports, and suggestions are welcome! Please open an issue or submit a pull request.
