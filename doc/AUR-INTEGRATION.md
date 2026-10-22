# AUR Integration

AURGen now includes comprehensive AUR (Arch User Repository) integration that automates the entire workflow from PKGBUILD generation to AUR submission.

## Overview

The AUR integration system provides:

- **Automatic AUR repository management**: Initialize and manage local AUR repositories
- **Seamless deployment**: Deploy PKGBUILD, .SRCINFO, and the `install=` file when the PKGBUILD has one
- **Configurable workflow**: Customize behavior through configuration files
- **Validation and safety**: Built-in validation before push

## Configuration

AUR integration is configured through the `aur_integration` section in your `aurgen.install.yaml` file. This section is automatically included when you generate a new configuration file using `aurgen config generate` or when AURGen creates configuration files for the first time.

```yaml
aur_integration:
  # Local AUR repositories directory
  aur_repo_dir: ~/.local/share/aurgen/aur
  # Auto-push to AUR after deployment
  auto_push: true
  # Commit message template (use {version} for version placeholder)
  commit_message: "Update to version {version}"
  # Git user for AUR commits. Leave commented so the clone uses the existing git identity.
  # git_user_name: "Your Name"
  # git_user_email: "your.email@example.com"
  # SSH key for AUR authentication. When unset, ~/.ssh/config is used.
  # ssh_key: ~/.ssh/aur
  # Validate AUR repository before pushing
  validate_before_push: true
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `aur_repo_dir` | `${XDG_DATA_HOME:-~/.local/share}/aurgen/aur` | Directory where local AUR repositories are stored; a leading `~` is expanded |
| `auto_push` | `true` | Automatically push changes to AUR after deployment |
| `commit_message` | `"Update to version {version}"` | Template for commit messages (use `{version}` placeholder) |
| `git_user_name` | (empty, commented out) | Git user name for AUR commits. Empty uses the clone's `user.name`, then `GIT_AUTHOR_NAME`, then `GIT_COMMITTER_NAME` |
| `git_user_email` | (empty, commented out) | Git user email for AUR commits. Empty uses the clone's `user.email`, then `GIT_AUTHOR_EMAIL`, then `GIT_COMMITTER_EMAIL`, then `EMAIL` |
| `ssh_key` | (empty) | Path to an SSH key. When empty, ssh uses ~/.ssh/config |
| `validate_before_push` | `true` | Validate repository before pushing to AUR |

Deploy stops before copying if the name or email is still empty.

## Commands

### `aurgen aur-init`

Initialize a new AUR repository for your package.

```bash
aurgen aur-init
```

This command:
- Uses the package in `aur/.SRCINFO` (its pkgbase: `<name>-git` after `aurgen git`, `<name>` after `aurgen aur`), the same one aur-deploy deploys to; with no `.SRCINFO` yet it uses the configured package name. Run `aurgen aur` or `aurgen git` first to switch between the two
- Refuses a name that is empty, contains `/`, or starts with `.` (the name is one directory under `aur_repo_dir`)
- Creates the AUR repository directory if it doesn't exist
- Clones the AUR repository from `https://aur.archlinux.org/<name>.git` and sets the push URL to `ssh://aur@aur.archlinux.org/<name>.git`
- After a successful clone, probes `ssh -o BatchMode=yes -o ConnectTimeout=10 aur@aur.archlinux.org help`, adding `-i` when `ssh_key` resolves to a key file. Prints `AUR SSH: ok`, or one warning: `AUR SSH: permission denied: add your public key at https://aur.archlinux.org/account`, `AUR SSH: host key verification failed: connect once with ssh aur@aur.archlinux.org to verify the key`, or `AUR SSH: unreachable:` plus the first line of ssh output. The probe does not fail initialization and does not accept an unknown host key
- `--dry-run` prints that clone and does not clone or connect. Confirming reinitialize does not delete the existing directory

**Requirements:**
- Git must be installed
- An AUR SSH key is required to push. The clone uses https and does not need the key. After the clone, initialization reports whether SSH authentication works

### `aurgen aur-deploy`

Deploy your package to AUR.

```bash
aurgen aur-deploy
aurgen --dry-run aur-deploy
```

`aurgen --dry-run aur-deploy` prints a per-file diff, each root `*.install` file that would be removed, and the commit message. Nothing is copied, committed, or pushed.

This command:
- Ensures PKGBUILD and .SRCINFO exist (run `aurgen aur` first if needed)
- Checks if AUR repository exists (initializes if missing)
- Fetches `origin` in an existing clone and refuses to deploy, before anything is copied, when the clone is behind the branch it tracks (`origin/master` when no upstream is set). This happens when you deploy from two machines or with a co-maintainer: run `git -C <aur_repo_dir>/<package> pull --ff-only`, then `aurgen aur --deploy`, so the pkgrel is read from the updated clone. When the fetch fails (offline), a warning is printed and the check uses the last fetched state
- Copies PKGBUILD, .SRCINFO, and the file named by `install=`. The file is read beside the PKGBUILD being deployed, otherwise from `aur/`, where a generated scriptlet is written. A path, a leading `.`, or a missing file stops the deploy
- Refuses to deploy when `.SRCINFO` has a `SKIP` checksum for a downloaded (`http`, `https`, or `ftp`) source; run `aurgen aur` so the checksum is pinned. `SKIP` stays valid for `git+` sources and for signature files (`.sig`, `.sign`, `.asc`), which makepkg itself leaves as `SKIP` because gpg verifies them
- Commits changes with the configured commit message (`{version}` is `pkgver-pkgrel` from `.SRCINFO`)
- When `auto_push` is true, pushes with `git push origin HEAD:master` (the local branch name does not matter)
- When the files match the checkout, so the new commit is empty, and an earlier commit is still unpushed, pushes that commit instead
- After a successful push, prints the version the AUR website reports (`AUR web: ...`). A package the index has not listed yet says the index can lag a few minutes

**Requirements:**
- PKGBUILD and .SRCINFO must exist (run `aurgen aur` first)
- Git must be installed
- SSH access to AUR (if auto-push is enabled)

### `aurgen aur-status`

Check the status of your AUR repository.

```bash
aurgen aur-status
```

This command displays:
- Repository existence status
- Git working directory status
- Remote branch status
- Current AUR integration configuration
- Uses the package in `aur/.SRCINFO` (its pkgbase: `<name>-git` after `aurgen git`, `<name>` after `aurgen aur`), the same one aur-deploy deploys to; with no `.SRCINFO` yet it uses the configured package name. Run `aurgen aur` or `aurgen git` first to switch between the two
- A Version line when both the generated `.SRCINFO` and the AUR checkout's `.SRCINFO` have `pkgver` and `pkgrel`: `Version: AUR <pkgver>-<pkgrel>, generated <pkgver>-<pkgrel> (up to date)` or `(deploy pending)`
- An `AUR web:` line from the AUR RPC (`https://aur.archlinux.org/rpc/v5/info/<pkgname>`), shown even when there is no local AUR clone. It needs `curl` and `jq`. Without them the line is omitted. When the package is not on the AUR it prints `AUR web: not published`; when the request fails it prints `AUR web: unavailable`.

## Workflow

### Complete AUR Deployment Workflow

1. **Prepare your package**:
   ```bash
   aurgen aur
   ```
   This generates PKGBUILD and .SRCINFO files.

2. **Initialize AUR repository** (first time only):
   ```bash
   aurgen aur-init
   ```
   This sets up your local AUR repository.

3. **Deploy to AUR**:
   ```bash
   aurgen aur-deploy
   ```
   This deploys your package to AUR.

### Alternative: One-Step Deployment

You can also run the complete workflow in sequence:

```bash
aurgen aur
aurgen aur-deploy
```

Or in one run, with the same steps and the same `--dry-run` preview:

```bash
aurgen --deploy aur
```

## AUR Setup Requirements

Before using AUR integration, you must:

1. **Create an AUR account** at https://aur.archlinux.org/
2. **Add your SSH public key** to your AUR account
3. **Configure SSH** to use your AUR SSH key

### SSH Configuration

Add to your `~/.ssh/config`:

```
Host aur.archlinux.org
    IdentityFile ~/.ssh/aur_key
    User aur
```

### Testing SSH Access

Test your SSH access:

```bash
ssh aur@aur.archlinux.org help
```

You should see AUR help information if your SSH key is properly configured.

`aur-init` runs that command non-interactively after a successful clone (`BatchMode=yes`, `ConnectTimeout=10`, and `-i` when `ssh_key` is set). A working key prints `AUR SSH: ok`. A failure prints a warning and initialization still succeeds. An unknown host key is reported, not accepted. `--dry-run` does not connect.

## Safety Features

### Validation

When `validate_before_push` is enabled, AURGen validates:
- PKGBUILD syntax
- .SRCINFO syntax
- Required files exist
- .SRCINFO byte-matches `makepkg --printsrcinfo` from the clone's PKGBUILD before push

`aur-deploy` regenerates .SRCINFO from the PKGBUILD before copying it to the clone.

### Dry Run Support

`aurgen --dry-run aur-deploy` prints a per-file diff, each root `*.install` file that would be removed, and the commit message. Nothing is copied, committed, or pushed.

`auto_push: false` still copies and commits in the local clone. The push is the step it skips. `aurgen aur-push` pushes that clone: validation when `validate_before_push` is enabled, the configured SSH key, and `git push origin HEAD:master`. Nothing ahead of the upstream (`@{u}`, or `origin/master` when no upstream is set) exits 0 without pushing. A missing clone exits non-zero. A tracked file changed in the clone but not committed also stops the push, since validation reads the files and the push sends `HEAD`: commit the change or rerun `aurgen aur-deploy`.

## Troubleshooting

### Common Issues

**SSH Authentication Failed**
- Ensure your SSH key is added to your AUR account
- Check SSH configuration in `~/.ssh/config`
- Test SSH access manually

**Repository Not Found**
- A package that is not on the AUR yet still clones as an empty repository
- Maintainer access is required before a push
- The package name comes from the PKGBUILD

**AUR clone is behind origin**
- Another machine or a co-maintainer pushed since your last pull
- Run `git -C <aur_repo_dir>/<package> pull --ff-only`, then `aurgen aur --deploy` (aur reads the pkgrel from the updated clone)

**Permission Denied**
- Ensure you have write access to the AUR repository directory
- Check that your SSH key has the correct permissions

### Debug Mode

Enable debug logging to see detailed information:

```bash
DEBUG_LEVEL=1 aurgen aur-deploy
```

## Integration with Existing Workflow

The AUR integration seamlessly integrates with AURGen's existing workflow:

1. **`aurgen aur`** - Generates PKGBUILD and .SRCINFO, uploads to GitHub
2. **`aurgen aur-deploy`** - Deploys the generated files to AUR

The integration is designed to be non-intrusive - existing workflows continue to work unchanged, with AUR deployment as an optional additional step.

## Best Practices

1. **Always test locally first**: Use `aurgen local` to test your package before AUR deployment
2. **Use meaningful commit messages**: Customize the commit message template to include relevant information
3. **Enable validation**: Keep `validate_before_push` enabled to catch issues early
4. **Monitor AUR status**: Use `aurgen aur-status` to check repository health

## Security Considerations

- **SSH keys**: Store your AUR SSH key securely and use appropriate permissions
- **Repository access**: Only maintain packages you have permission to maintain
- **Validation**: Always review generated PKGBUILD and .SRCINFO files before deployment

## AUR Integration

AURGen includes comprehensive AUR (Arch User Repository) integration that automates the entire workflow from PKGBUILD generation to AUR submission:

### AUR Workflow

1. **Generate Package Files**: `aurgen aur` creates PKGBUILD and .SRCINFO
2. **Initialize AUR Repository**: `aurgen aur-init` sets up your local AUR repository
3. **Deploy to AUR**: `aurgen aur-deploy` automatically deploys your package to AUR

### Key Features

- **Automatic Repository Management**: Initialize and manage local AUR repositories
- **Seamless Deployment**: Deploy PKGBUILD, .SRCINFO, and the `install=` file when the PKGBUILD has one
- **Configurable Workflow**: Customize behavior through `aurgen.install.yaml`
- **Safety Features**: Validation and error handling
- **SSH Integration**: Secure AUR authentication with SSH key management

### Configuration

AUR integration is automatically configured when you generate your `aurgen.install.yaml` file. The configuration includes:

```yaml
aur_integration:
  aur_repo_dir: ~/.local/share/aurgen/aur
  auto_push: true
  commit_message: "Update to version {version}"
  validate_before_push: true
```

For complete AUR integration documentation, see [doc/AUR-INTEGRATION.md](AUR-INTEGRATION.md) and [doc/AUR-QUICK-REFERENCE.md](AUR-QUICK-REFERENCE.md).
