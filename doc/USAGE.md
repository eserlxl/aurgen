# AURGen Usage Guide

This document provides comprehensive usage information for AURGen, including all available modes, options, and workflows.

## Quick Start

```bash
# Options come before the mode
aurgen [options] <mode>

# Examples
aurgen local                    # Build and test locally
aurgen aur                      # Prepare for AUR release
aurgen aur-deploy               # Deploy to AUR
aurgen aur-push                 # Push a deployed clone to the AUR
aurgen aur-status               # Check AUR repository status
```

## Modes

### Core Packaging Modes

#### `local`
Build and install the package from a local tarball for testing.

```bash
aurgen local
```

**What it does:**
- Creates a local tarball of the tracked files as they are in the working tree, so uncommitted edits to tracked files are included and untracked files are not (non-ASCII names included; a directory prefix does not rewrite symlink targets)
- Generates PKGBUILD and .SRCINFO
- Builds the package locally using `makepkg`
- When namcap is installed, checks the built package and stops the install on namcap `E:` findings
- Installs the package for testing, unless `--build-only` is passed or `AURGEN_CHROOT_DIR` is set: with the latter it builds in that clean chroot with `makechrootpkg -c -r` and installs nothing

**Use case:** Test your package locally before releasing

To catch undeclared build dependencies, set `AURGEN_CHROOT_DIR` to an existing
clean chroot. Install `devtools` (which provides `makechrootpkg` and `mkarchroot`),
then create the chroot once:

```bash
sudo pacman -S devtools
mkdir -p "$HOME/aurgen-chroot"
sudo mkarchroot "$HOME/aurgen-chroot/root" base-devel
AURGEN_CHROOT_DIR="$HOME/aurgen-chroot" aurgen local
```

With this variable non-empty, local mode requires its `root` directory and
`makechrootpkg` on PATH, then runs `makechrootpkg -c -r "$AURGEN_CHROOT_DIR"`.
A failed chroot build fails local mode. When namcap is available, the packages
listed by `makepkg --packagelist` are checked; this honors `PKGDEST`. `E:` findings fail local mode.
This path never installs the package on the host. Dry runs skip the build.
With the variable unset or empty, local mode builds and installs on the host
as usual, unless `--build-only` is passed.

#### `aur`
Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload.

```bash
aurgen aur
```

**What it does:**
- Creates a reproducible tarball from the release tag (tracked files, including non-ASCII names)
- Signs the tarball with GPG
- Uploads tarball and signature to GitHub releases; a release aurgen creates gets GitHub-generated notes. A failed tarball or signature upload stops the run. When `gh` is not logged in to github.com, the upload stops and names `gh auth login --hostname github.com`. Keeping an existing release does not check login
- For `package.source` archive and signed-tag, stops with a `git push origin v<pkgver>` hint when the tag is not on GitHub yet. `AURGEN_PUSH_TAG=1` pushes the existing local `v<pkgver>` tag to origin without `--force` and continues; a failed push stops the run, and a missing local tag keeps the hint. `--dry-run` skips that remote check
- Reads the published version from the configured AUR clone's `.SRCINFO` (using the package name from `aur/.SRCINFO`, else the configured name). With no clone, queries the AUR RPC unless `--dry-run` is set. An unpublished package starts at `pkgrel=1`, regardless of local leftovers. If the RPC is unavailable or skipped for a dry run, falls back to local `aur/PKGBUILD` or `PKGBUILD.prev`. Logs the chosen source
- Same published `pkgver` bumps `pkgrel` by one. When the AUR clone's PKGBUILD exists and the regenerated PKGBUILD matches that file once its first `pkgrel` line is the published value, the published `pkgrel` is kept and the run logs that the PKGBUILD is unchanged. If `install=` is set, that file must also exist and byte-match the copy beside the clone's PKGBUILD. A minor release such as `1.1` becomes `2`. A comment on a local fallback's `pkgrel` line is ignored. A new `pkgver` starts at `1`. Without a clone, the same `pkgver` still bumps `pkgrel`. `AURGEN_BUMP_PKGREL=1` bumps it even for an unchanged PKGBUILD, for a rebuild after a dependency's soname change
- Updates PKGBUILD with correct checksums and URLs
- Generates .SRCINFO file

**Use case:** Prepare your package for AUR submission

#### `git`
Generate a PKGBUILD for the -git (VCS) AUR package.

```bash
aurgen git
```

**What it does:**
- Creates a PKGBUILD whose `pkgname` is `<name>-git` and whose `.SRCINFO` `pkgbase` is that name
- Uses the git source (`origin/HEAD`, or the local branch when that ref is missing) instead of a release tarball
- Keeps `build()`, `check()`, and `package()`, including when `source=` is one line
- Merges configured `provides` and `conflicts` with `<name>` instead of replacing them. `git` is added to `makedepends` unless that array already has a `git` entry (`libgit2` does not count)
- Refuses a branch, owner, or repository name that is not safe to write into the source URL
- Writes `b2sums=("SKIP")` and drops `validpgpkeys` and `sha256sums`
- Generates .SRCINFO for git packages

**Use case:** Create git-based AUR packages

`aurgen local`, `aurgen aur`, and `aurgen git` keep the previous `aur/PKGBUILD` and `aur/.SRCINFO` as `aur/PKGBUILD.prev` and `aur/.SRCINFO.prev`. `aurgen clean` removes those `.prev` files.

### AUR Integration Modes

#### `aur-init`
Initialize a new AUR repository for package deployment.

```bash
aurgen aur-init
```

**What it does:**
- Uses the package in `aur/.SRCINFO` (its `pkgbase`: `<name>-git` after `aurgen git`, `<name>` after `aurgen aur`). With no `.SRCINFO` yet it uses the configured package name
- Refuses a name that is empty, contains `/`, or starts with `.`
- Clones `https://aur.archlinux.org/<name>.git` into the configured AUR directory and sets the push URL to `ssh://aur@aur.archlinux.org/<name>.git`
- `--dry-run` prints the clone it would make and does not clone. A yes answer to reinitialize does not delete the existing clone

**Requirements:**
- Git must be installed
- An AUR SSH key is required to push. The clone uses https and does not need the key

**Use case:** First-time setup of AUR repository

#### `aur-deploy`
Deploy your package to AUR.

```bash
aurgen aur-deploy
```

**What it does:**
- Ensures PKGBUILD and .SRCINFO exist (run `aurgen aur` or `aurgen git` first)
- Regenerates .SRCINFO from the PKGBUILD before copying, so a hand-edited PKGBUILD is published with matching metadata. A dry run leaves the files in `aur/` unchanged
- Deploys the package named by `aur/.SRCINFO` `pkgbase` (else `pkgname`)
- Checks if AUR repository exists (initializes if missing)
- Copies PKGBUILD, .SRCINFO, and, when `install=` names a file in `aur/`, that install file
- Commits with the configured message (`{version}` is `pkgver-pkgrel` from `.SRCINFO`)
- When `auto_push` is true (the generated default), pushes with `git push origin HEAD:master`
- When `auto_push` is false, the commit stays in the local clone. `aurgen aur-push` performs the push
- If that commit has nothing new and an earlier commit was never pushed, pushes that commit instead
- After a successful push, prints the version the AUR website reports (`AUR web: ...`). A package the index has not listed yet says the index can lag a few minutes. A numeric `OutOfDate` appends ` (flagged out of date since YYYY-MM-DD)`; a null `Maintainer` appends ` (orphaned)`

**Requirements:**
- PKGBUILD and .SRCINFO must exist (run `aurgen aur` first)
- Git must be installed
- SSH access to AUR (if auto-push is enabled)

**Use case:** Deploy your package to AUR after preparation

#### `aur-push`
Push commits that are already in a deployed AUR clone.

```bash
aurgen aur-push
```

**What it does:**
- Loads the AUR integration configuration the same way `aur-deploy` does
- Uses the package in `aur/.SRCINFO` (`pkgbase`, else `pkgname`)
- Exits non-zero when that clone does not exist
- Counts commits ahead of the upstream (`@{u}`, or `origin/master` when no upstream is set)
- Exits 0 without pushing when nothing is ahead
- With `--dry-run`, prints how many commits it would push and pushes nothing
- Otherwise validates when `validate_before_push` is true, applies the configured SSH key, and pushes with `git push origin HEAD:master`

**Requirements:**
- Git must be installed
- A local AUR clone from `aurgen aur-init` or `aurgen aur-deploy`
- SSH access to the AUR

**Use case:** Push after `auto_push: false`, or from a machine that holds the AUR SSH key

#### `aur-status`
Check the status of your AUR repository.

```bash
aurgen aur-status
```

**What it does:**
- Uses the package in `aur/.SRCINFO` (`pkgbase`, so the `-git` package after `aurgen git`)
- Displays repository existence status
- Shows git working directory status, with modified paths indented
- Reports remote branch status
- Shows current AUR integration configuration
- Prints `Version: AUR <pkgver>-<pkgrel>, generated <pkgver>-<pkgrel> (up to date)` or `(deploy pending)` when both `.SRCINFO` files have those fields
- Prints `AUR web:` from the AUR RPC even when there is no local clone (`not published` or `unavailable`; omitted without `curl` and `jq`). A numeric `OutOfDate` appends ` (flagged out of date since YYYY-MM-DD)`; a null `Maintainer` appends ` (orphaned)`
- Exits 0 when the clone matches the generated `.SRCINFO` or when no clone exists, and exits 3 when a deploy is pending or the clone has commits ahead of its upstream (`@{u}`, or `origin/master` when no upstream is set; a first commit to an empty AUR repo counts as ahead)

**Use case:** Check the health of your AUR repository

### Utility Modes

#### `clean`
Remove all generated files and directories in the output folder.

```bash
aurgen clean
```

**What it does:**
- Removes generated `aur/PKGBUILD`, `aur/PKGBUILD.git`, `aur/.SRCINFO`, `aur/PKGBUILD.prev`, `aur/.SRCINFO.prev`, tarballs, signatures, built packages, and `aur/golden/PKGBUILD.*.golden`
- Removes the same generated files under `aur/dry-run/`, then the directory when nothing else is left in it
- Removes `aur/<pkgname>-*` build directories
- Leaves `PKGBUILD.0`, `PKGBUILD.HEADER`, `aurgen.install.yaml`, and `*.install` in place

**Use case:** Clean up after testing or before a fresh build

#### `test`
Dry-run the local, aur and git modes, then check that invalid arguments are rejected. The bash test suite is a separate command: `bash tests/run.sh`.

```bash
aurgen test
```

**What it does:**
- Dry-runs local, aur, and git, then checks that invalid arguments are rejected
- Removes generated files before each of those three runs, and keeps the first `aur/PKGBUILD.prev` across them
- Compares each generated PKGBUILD with `aur/golden/PKGBUILD.<mode>.golden` when that file exists
- When namcap is installed, namcap E: findings fail the run and W: findings are shown

**Use case:** Validate your setup and configuration

#### `lint`
Run `shellcheck` and `bash -n` on all Bash scripts for linting.

```bash
aurgen lint
```

**What it does:**
- Runs shellcheck on all bash scripts
- Validates bash syntax with `bash -n`
- Reports code quality issues and suggestions

**Use case:** Ensure code quality and catch potential issues

#### `golden`
Regenerate the golden PKGBUILD files for test comparison.

```bash
aurgen golden
```

**What it does:**
- Regenerates reference PKGBUILD files in `aur/golden`
- Ensures test accuracy

**Use case:** Update test fixtures after changes

#### `config`
Manage AURGen configuration for directory copying behavior.

```bash
aurgen config <action>
```

Actions (short forms in parentheses):
- `generate` (`gen`, `g`): write a default `aurgen.install.yaml`
- `edit` (`e`): open it in `$EDITOR`, falling back to nano, then vim, then vi; generates it first when missing
- `show` (`s`, `list`, `l`): print it; `show effective` prints the settings after defaults are applied
- `validate` (`v`): check it
- `reset` (`r`): back it up to `aurgen.install.yaml.bak` and write the default again
- `import` (`i`) `[PKGBUILD]`: derive it from an existing PKGBUILD (default `aur/PKGBUILD`)
- `help` (`h`): print the action list

`aurgen config` with no action prints an error.

**What it does:**
- Manages `aurgen.install.yaml` configuration
- Handles directory copying rules
- Configures package installation behavior

**Use case:** Customize package installation behavior

## Options

### Global Options

All options must appear before the mode.

```bash
aurgen [OPTIONS] <mode>
```

#### `-n, --no-color`
Disable colored output.

```bash
aurgen --no-color aur
```

#### `-a, --ascii-armor`
Use ASCII-armored GPG signatures (.asc).

```bash
aurgen --ascii-armor aur
```

#### `-d, --dry-run`
Dry run: write PKGBUILD, .SRCINFO, tarballs, signatures, and packages under `aur/dry-run/` and leave the published files in `aur/` unchanged. Checksums are `b2sums=('SKIP')` instead of `updpkgsums`. The install, the GitHub upload, and the AUR copy, commit, and push are skipped. `aur-init` does not clone or delete.

```bash
aurgen --dry-run aur
```

#### `--build-only`
Build and check the package in `local` mode without installing the candidate package.
Runs `makepkg -sf`, which may install missing build dependencies, then checks the
listed packages with namcap when it is available. Namcap `E:` findings fail the
run. Without namcap, only the build runs. Other modes reject this option.
`AURGEN_CHROOT_DIR` still takes priority, and `--dry-run` still skips the build.

```bash
aurgen --build-only local
```

#### `--no-wait`
Skip post-upload wait for asset availability (for CI/advanced users).

```bash
aurgen --no-wait aur
```

#### `--deploy`
After a successful `aur` or `git` run, deploys the generated PKGBUILD and `.SRCINFO` to the AUR.

```bash
aurgen --deploy git
```

#### `--maxdepth N`
Set maximum search depth for lint and clean (default: 5). The value must be a positive integer (`1`, `2`, `3`, …). `0`, a negative number, and any other text are refused before a mode runs.

```bash
aurgen --maxdepth 10 lint
```

#### `-h, --help`
Show detailed help and exit.

```bash
aurgen --help
```

#### `-v, --version`
Show version and exit.

```bash
aurgen --version
```

#### `--usage`
Show minimal usage and exit.

```bash
aurgen --usage
```

## Workflows

### Complete AUR Release Workflow

1. **Test locally first:**
   ```bash
   aurgen local
   ```

2. **Prepare for AUR release:**
   ```bash
   aurgen aur
   ```

3. **Initialize AUR repository (first time only):**
   ```bash
   aurgen aur-init
   ```

4. **Deploy to AUR:**
   ```bash
   aurgen aur-deploy
   ```

### Git Package Workflow

1. **Generate git package:**
   ```bash
   aurgen git
   ```

2. **Deploy to AUR:**
   ```bash
   aurgen aur-deploy
   ```

### Testing and Validation Workflow

1. **Run comprehensive tests:**
   ```bash
   aurgen test
   ```

2. **Check code quality:**
   ```bash
   aurgen lint
   ```

3. **Clean up after testing:**
   ```bash
   aurgen clean
   ```

## Configuration

### Directory copy rules

`aurgen.install.yaml` maps repository directories into the package. A copy section names a `source` directory, a `destination` path, and `permissions` (`executable`, `read-only`, or a three- or four-digit octal mode).

The fixed sources are `bin`, `lib`, `etc`, `share`, `include`, `local`, `var`, and `opt`. A section may also name any other repository-relative directory. Each path component uses ASCII letters, digits, `.`, `_`, or `-`. Components are separated by `/`. No component is `.` or `..`. Sources such as `data` and `scripts/hooks` are copied with the section's destination and permissions. A source that leaves the repository (`../x`) or an absolute source (`/abs`) is rejected, and loading stops.

```yaml
project_data:
  source: data
  destination: usr/share/$pkgname/data
  permissions: read-only
  exclude: []
```

### AUR Integration Configuration

Configure AUR integration in your `aurgen.install.yaml`:

```yaml
aur_integration:
  aur_repo_dir: ~/.local/share/aurgen/aur
  auto_push: true
  commit_message: "Update to version {version}"
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  # When unset, ~/.ssh/config is used.
  # ssh_key: ~/.ssh/aur
  validate_before_push: true
```

### Package keys

The `package:` mapping holds package metadata. A key the parser does not recognize stops loading. The message names that key, the config file, and the line, then lists the accepted keys: `name`, `description`, `gpg_key`, `install`, `check`, `source`, `install_messages`, `arch`, `depends`, `optdepends`, `makedepends`, `checkdepends`, `conflicts`, `provides`, `backup`, `install_vars`, `license`, and `post_package`. `install_messages` is a block mapping of `post_install`, `post_upgrade`, and `pre_remove`. The check applies inside `package:` only.

### Test Dependencies

List tools needed by `check()` under `package.checkdepends` in `aurgen.install.yaml`:

```yaml
package:
  checkdepends: [bats, python-pytest]
```

Block lists are also supported. A non-empty list becomes `checkdepends=(...)` in `PKGBUILD.0` and survives `aurgen config import`. makepkg installs these dependencies when running checks and skips them with `--nocheck`; keep build dependencies in `makedepends` and runtime dependencies in `depends`.

### Signing Key

With several secret keys, name the one this project signs with in `aurgen.install.yaml`:

```yaml
package:
  gpg_key: 0123456789ABCDEF0123456789ABCDEF01234567
```

The value is a 40-hex fingerprint or a hex suffix of one (16 characters or more), compared case-insensitively. It must match exactly one secret key that can sign and is not expired, revoked, disabled, or invalid; otherwise aurgen stops with an error instead of prompting. `GPG_KEY_ID` wins over `gpg_key`.

### Environment Variables

- `NO_COLOR`: Disable colored output on a terminal. Piped or redirected output is already plain
- `GPG_KEY_ID`: Set GPG key ID to skip interactive selection. It wins over `package.gpg_key`
- `CI`: Turn color off. It does not change the mode: a source checkout runs in development mode (`RELEASE=0`) and an installed aurgen in release mode, unless `RELEASE` is set. Prompts follow the terminal; without one they take their default
- `NO_WAIT`: Set to `1` to skip the post-upload wait for asset availability
- `AURGEN_BUMP_PKGREL`: Set to `1` to bump `pkgrel` in aur mode even when the PKGBUILD matches the AUR clone's
- `AURGEN_PUSH_TAG`: Set to `1` to push the local `v<pkgver>` tag to origin when archive or signed-tag aur mode finds it missing there. A missing local tag, or any value other than `1`, keeps the push hint and stops. A failed push stops the run
- `AURGEN_CHROOT_DIR`: An existing makechrootpkg chroot. `local` builds there with `makechrootpkg -c -r` and installs nothing; see [`local`](#local)
- `ASCII_ARMOR_DEFAULT`: Set to `1` to sign with `.asc` signatures by default, the same as `--ascii-armor`
- `DRY_RUN`: Set to `1` to enable dry-run mode (generated files go under `aur/dry-run/`)
- `RELEASE`: Override automatic mode detection
- `AURGEN_LIB_DIR`: Set custom library directory path
- `COLOR`: `1` or `0` forces color on or off, after `--no-color` and `CI` are applied. Output that is not a terminal stays plain, and `NO_COLOR` still turns color off
- `GH_USER`: GitHub owner to use instead of the one read from the `url` in `PKGBUILD.0`
- `AURGEN_LOG`: Set custom log file path
- `AURGEN_ERROR_LOG`: Set custom error log file path
- `MAXDEPTH`: Positive integer search depth for lint and clean (default 5)

## Examples

### Basic Package Development

```bash
# Test your package locally
aurgen local

# Prepare for AUR release
aurgen aur

# Deploy to AUR
aurgen aur-deploy
```

### Git-based Package

```bash
# Generate git package
aurgen git

# Deploy to AUR
aurgen aur-deploy
```

### Testing and Validation

```bash
# Dry-run the local, aur and git modes
aurgen test

# Check code quality
aurgen lint

# Clean up
aurgen clean
```

### AUR Repository Management

```bash
# Check AUR repository status
aurgen aur-status

# Initialize new AUR repository
aurgen aur-init

# Deploy package to AUR
aurgen aur-deploy
```

## Troubleshooting

### Common Issues

**Missing Dependencies**
- AURGen will provide installation hints for missing tools
- Install required packages: `sudo pacman -S <package>`

**SSH Authentication Issues**
- Ensure your SSH key is added to your AUR account
- Test SSH access: `ssh aur@aur.archlinux.org help`

**Repository Not Found**
- Verify the package name exists on AUR
- Check that you have maintainer access

**Permission Denied**
- Ensure you have write access to the AUR repository directory
- Check SSH key permissions

### Debug Mode

Enable debug logging for detailed information:

```bash
DEBUG_LEVEL=1 aurgen <mode>
```

### Getting Help

```bash
# Show help
aurgen --help

# Show usage
aurgen --usage
```

## Best Practices

1. **Always test locally first** using `aurgen local`
2. **Use meaningful commit messages** in AUR integration configuration
3. **Enable validation** to catch issues early
4. **Monitor AUR status** regularly with `aurgen aur-status`
5. **Run tests** before deploying with `aurgen test`
6. **Check code quality** with `aurgen lint`

## Security Considerations

- Store AUR SSH keys securely with appropriate permissions
- Only maintain packages you have permission to maintain
- Always review generated PKGBUILD and .SRCINFO files before deployment
- Use validation features to ensure package integrity
