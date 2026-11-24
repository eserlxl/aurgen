# AUR Integration

AURGen now includes comprehensive AUR (Arch User Repository) integration that automates the entire workflow from PKGBUILD generation to AUR submission.

## Overview

The AUR integration system provides:

- **Automatic AUR repository management**: Initialize and manage local AUR repositories
- **Seamless deployment**: Deploy PKGBUILD, .SRCINFO, and the `install=` file when the PKGBUILD has one
- **Configurable workflow**: Customize behavior through configuration files
- **Validation and safety**: Built-in validation before push

## Configuration

AUR integration is configured through the `aur_integration` section in your `aurgen.install.yaml` file. This section is automatically included when you generate a new configuration file using `aurgen config generate` or when AURGen creates configuration files for the first time. `aurgen config init` writes it only as a commented block, so its defaults apply (`auto_push: true`).

```yaml
aur_integration:
  # Local AUR repositories directory
  aur_repo_dir: ~/.local/share/aurgen/aur
  # Auto-push to AUR after deployment
  auto_push: true
  # Commit message template ({version}, {pkgname}, {pkgver}, {pkgrel}, {epoch})
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
| `aur_repo_dir` | `${XDG_DATA_HOME:-~/.local/share}/aurgen/aur` when the key is absent; `config generate`, first-run generation and `config import` write `~/.local/share/aurgen/aur` | Directory where local AUR repositories are stored; only `~` and `~/...` are expanded (any other leading `~`, such as `~bob/`, is a config error) and a relative path resolves against the project root |
| `auto_push` | `true` | Automatically push changes to AUR after deployment |
| `commit_message` | `"Update to version {version}"` | Template for commit messages (placeholders: `{version}`, `{pkgname}`, `{pkgver}`, `{pkgrel}`, `{epoch}`) |
| `git_user_name` | (empty, commented out) | Git user name for AUR commits. Empty uses the clone's `user.name`, then `GIT_AUTHOR_NAME`, then `GIT_COMMITTER_NAME` |
| `git_user_email` | (empty, commented out) | Git user email for AUR commits. Empty uses the clone's `user.email`, then `GIT_AUTHOR_EMAIL`, then `GIT_COMMITTER_EMAIL`, then `EMAIL` |
| `ssh_key` | (empty) | Path to an SSH key. When empty, ssh uses ~/.ssh/config. Only `~` and `~/...` are expanded; any other leading `~` is a config error |
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
- After a successful clone, probes `ssh -o BatchMode=yes -o ConnectTimeout=10 aur@aur.archlinux.org help`, adding `-i` when `ssh_key` resolves to a key file. Prints `AUR SSH: ok`, or one warning: `AUR SSH: permission denied: add your public key at https://aur.archlinux.org/account, or load the key into ssh-agent (ssh-add)`, `AUR SSH: host key verification failed: connect once with ssh aur@aur.archlinux.org to verify the key`, or `AUR SSH: unreachable:` plus the first line of ssh output. The probe does not fail initialization and does not accept an unknown host key
- `--dry-run` prints that clone and does not clone or connect. Confirming reinitialize does not delete the existing directory in a dry run; outside one, it moves the existing clone to a backup under `<aur_repo_dir>/.aur-init-backup.XXXXXX/`, clones again, restores the backup if `git clone` fails, and deletes the backup only after the fresh clone succeeds

**Requirements:**
- Git must be installed
- An AUR SSH key is required to push. The clone uses https and does not need the key. After the clone, initialization reports whether SSH authentication works

### `aurgen aur-deploy`

Deploy your package to AUR.

```bash
aurgen aur-deploy
aurgen --dry-run aur-deploy
aurgen --dry-run aur-deploy --rollback
aurgen aur-deploy --rollback
```

`aurgen --dry-run aur-deploy` prints a per-file diff, each root `*.install` file that would be removed, and the commit message. Nothing is copied, committed, or pushed.

`aurgen aur-deploy --rollback` cleans dirty/untracked files and rewinds only unpushed local commits in the local AUR clone back to its upstream tracking branch (`@{u}`), leaving pushed upstream commits intact. It refuses to rewrite commits when no valid `@{u}` tracking branch exists, and `--dry-run` previews planned resets without mutating the clone.

This command:
- Ensures PKGBUILD and .SRCINFO exist (run `aurgen aur` first if needed)
- Checks if AUR repository exists (initializes if missing)
- Fetches `origin` in an existing clone and refuses to deploy, before anything is copied, when the clone is behind the branch it tracks (`origin/master` when no upstream is set); when the clone has also diverged with unpushed commits, it fails with a diverged error naming `aurgen aur-deploy --rollback`. This happens when you deploy from two machines or with a co-maintainer: run `git -C <aur_repo_dir>/<package> pull --ff-only` (or `aurgen aur-deploy --rollback` first if diverged), then `aurgen --deploy aur` or `aurgen --deploy git` to match the refused package, so the pkgrel is read from the updated clone. When the fetch fails (offline), a warning is printed and the check uses the last fetched state
- Copies PKGBUILD, .SRCINFO, and the file named by `install=`. The file is read beside the PKGBUILD being deployed, otherwise from `aur/`, where a generated scriptlet is written. A path, a leading `.`, or a missing file stops the deploy
- Refuses to deploy when `.SRCINFO` has a `SKIP` checksum for a downloaded (`http`, `https`, or `ftp`) source; run `aurgen aur` so the checksum is pinned. `SKIP` stays valid for `git+` sources and for signature files (`.sig`, `.sign`, `.asc`), which makepkg itself leaves as `SKIP` because gpg verifies them
- Commits changes with the configured commit message (`{version}` is `[epoch:]pkgver-pkgrel` from `.SRCINFO`, with `epoch:` only when the package sets one; `{pkgname}` is the AUR package name, `{pkgver}`, `{pkgrel}` and `{epoch}` are the single `.SRCINFO` fields, `{epoch}` empty when unset; any other `{word}` stays as written)
- When `auto_push` is true, pushes with `git push origin HEAD:master` (the local branch name does not matter)
- When the files match the checkout, so the new commit is empty, and an earlier commit is still unpushed, pushes that commit instead
- After a successful push, prints the version the AUR website reports (`AUR web: ...`). A package the index has not listed yet says the index can lag a few minutes

**Requirements:**
- PKGBUILD and .SRCINFO must exist (run `aurgen aur` first)
- Git must be installed
- SSH access to AUR (if auto-push is enabled)

### `aurgen aur-push`

Push an already-committed local AUR clone to `aur.archlinux.org`.

```bash
aurgen aur-push
aurgen --dry-run aur-push
```

This command:
- Uses the package in `aur/.SRCINFO` (or the configured package name when `.SRCINFO` is absent) and requires an existing clone under `aur_repo_dir`
- Exits `0` with `Nothing to push` when `HEAD` is not ahead of its tracked upstream (`@{u}`, or `origin/master` when no upstream is set); a fresh clone with a local `HEAD` and no `origin/master` counts as ahead
- `--dry-run` still fetches `origin` to check for divergence and checks for a clean working tree and valid push URL, then prints how many commits would be pushed without running `validate_aur_repo` or pushing
- Refuses to push when tracked files in the clone have uncommitted modifications
- Validates PKGBUILD and `.SRCINFO` when `validate_before_push` is `true`, then runs `git push origin HEAD:master` (applying `ssh_key` if configured)
- After a successful push, prints the `AUR web:` status line from the AUR RPC

**Requirements:**
- Existing local AUR clone with committed changes (for example after `aurgen aur-deploy` with `auto_push: false`)
- Git and SSH access to AUR

### `aurgen aur-status`

Check the status of your AUR repository.

```bash
aurgen aur-status
aurgen --diff aur-status   # Show unified diffs against the local AUR clone
aurgen --json aur-status   # Print machine-readable JSON status on stdout
```

This command displays:
- Repository existence status
- Git working directory status
- Remote branch status (and a `Behind: <N> commit(s) behind upstream; run git -C ... pull --ff-only` line, or `Behind: <N> commit(s) behind upstream and <M> unpushed: the clone has diverged; run aurgen aur-deploy --rollback, then git -C <path> pull --ff-only` when unpushed commits exist, plus `"behind_count"` alongside `"ahead_count"` in `--json`)
- Current AUR integration configuration
- Uses the package in `aur/.SRCINFO` (its pkgbase: `<name>-git` after `aurgen git`, `<name>` after `aurgen aur`), the same one aur-deploy deploys to; with no `.SRCINFO` yet it uses the configured package name. Run `aurgen aur` or `aurgen git` first to switch between the two
- A Version line when both the generated `.SRCINFO` and the AUR checkout's `.SRCINFO` have `pkgver` and `pkgrel`: `Version: AUR <pkgver>-<pkgrel>, generated <pkgver>-<pkgrel> (up to date)` or `(deploy pending)`. When both versions match, it also compares the two `.SRCINFO` files, the `install=` scriptlet and the `PKGBUILD`, and reports `(deploy pending; only metadata differs)`, `(deploy pending; install scriptlet differs or is missing)` or `(deploy pending; PKGBUILD differs)` when one of them differs
- An `AUR web:` line from the AUR RPC (`https://aur.archlinux.org/rpc/v5/info/<pkgname>`), shown even when there is no local AUR clone. It needs `curl` and `jq`. Without them the line is omitted. When the package is not on the AUR it prints `AUR web: not published`; when the request fails it prints `AUR web: unavailable`. A package flagged out of date gets ` (flagged out of date since <YYYY-MM-DD>)` and an orphaned one ` (orphaned)`. `--json` reports the same facts as `"aur_out_of_date"` (the flag date, or `null`) and `"aur_orphaned"` (`true`, `false`, or `null` when unknown)
- A `GitHub release: <tag> (tarball: <state>, signature: <state>)` line when `package.source` is `release` (the default), `aur/.SRCINFO` has `pkgver`, and `remote.origin.url` is a GitHub repository. Takes `<tag>` from the `/releases/download/<tag>/` URL in the `.SRCINFO` source (falling back to the local `v<pkgver>` or `<pkgver>` tag when no such URL exists) and checks `<pkgname>-<pkgver>.tar.gz` and its `.sig`/`.asc` detached signature with `asset_exists` (`gh release view`, falling back to `curl -I`), reporting each as `present`, `missing`, or `unknown` (offline or failed probe) without failing `aur-status` or changing its exit codes. `--json` includes `"github_release": {"tag": "<tag>", "tarball": "<state>", "signature": "<state>"}` (or `null` when not applicable, such as `package.source` `archive` or `signed-tag`)
- A `Release: <version> is not packaged yet; run aurgen aur` line (and `"release_pending": "<version>"` in `--json`, otherwise `null`) when the project's version (its latest version tag, or `VERSION` in a project without tags) is newer than the generated `pkgver` (checked with `vercmp`; never for a `-git` package)
- An `Index lock: <path> is left over ...` line when the clone has a leftover `.git/index.lock`, and a `Push URL: <url> does not accept pushes; run: git -C <path> remote set-url --push origin ssh://aur@aur.archlinux.org/<pkgname>.git` line when its push URL is the anonymous https URL (`"index_lock"` and `"https_push_url"` in `--json`, otherwise `null`); `aur-deploy` and `aur-push` refuse both, and neither changes the exit code
- Exits `0` when up to date or when no local clone exists, and exits `3` when a deploy is pending, a newer project version is not packaged yet, or the local clone has commits ahead of its upstream (`@{u}`, or `origin/master` when no upstream is set). A clone that is only behind its upstream still exits `0`; the `Behind:` line is the signal to pull

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

Or in one run, with the same steps:

```bash
aurgen --deploy aur
```

With `--dry-run`, only the one-step `aurgen --dry-run --deploy aur` previews the freshly generated PKGBUILD; a separate `--dry-run aur-deploy` previews the files in `aur/`.

### Scheduled Release Check

`aur-status --json` exits `3` whenever something is pending, and its `release_pending` field names a
version that was tagged (or written to `VERSION`) but never packaged. A timer or CI job can use that
to release and deploy without a person in the loop:

```bash
#!/bin/bash
# Run from the project checkout. Needs a usable GPG signing key, gh logged in to github.com,
# and SSH access to the AUR (see AUR Setup Requirements below).
set -euo pipefail
status=0
json=$(aurgen --json aur-status) || status=$?
(( status == 0 )) && exit 0      # up to date, or no AUR clone yet
(( status == 3 )) || exit "$status"
if [[ "$(jq -r '.release_pending // empty' <<< "$json")" != "" ]]; then
    aurgen --non-interactive --no-wait --json aur > release.json   # tag, tarball URL, uploads
    aurgen --non-interactive aur-deploy
fi
aurgen --non-interactive aur-push   # pushes deployed commits; with nothing to push it says so
```

`aurgen --json aur` prints `package`, `version`, `release_tag`, `tarball_url`, `release` and
`uploaded` (see [USAGE.md](USAGE.md#--json)); `--json` cannot be combined with `--deploy`, so the
deploy is its own step.

## AUR Setup Requirements

Before using AUR integration, you must:

1. **Create an AUR account** at https://aur.archlinux.org/
2. **Add your SSH public key** to your AUR account
3. **Configure SSH** to use your AUR SSH key

### SSH Configuration

Add to your `~/.ssh/config`:

```
Host aur.archlinux.org
    IdentityFile ~/.ssh/aur
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
- PKGBUILD syntax (`bash -n PKGBUILD`)
- .SRCINFO syntax and required files exist
- .SRCINFO byte-matches `makepkg --printsrcinfo` from the clone's PKGBUILD before push
- .SRCINFO defines non-empty `pkgbase`/`pkgname` and pins checksums for non-VCS downloaded sources
- Any referenced `install=` script exists in the clone root and passes `bash -n`
- The clone's push URL is not the anonymous `https://aur.archlinux.org/...` URL, which cannot push (set it with `git remote set-url --push origin ssh://aur@aur.archlinux.org/<pkg>.git`)
- When `namcap` is installed, the clone's PKGBUILD has no namcap error (`E:` lines stop the push; `W:` lines are printed as warnings)

A leftover `.git/index.lock` in the clone (from an interrupted git command) stops `aur-deploy` and `aur-deploy --rollback` with a message naming the file; remove it once no git process runs there.

`aur-deploy` regenerates .SRCINFO from the PKGBUILD before copying it to the clone, and automatically rolls back copied/staged clone changes if an intermediate copy, stale `.install` removal, `git add`, or `git commit` step fails (leaving pre-existing files on an unborn repository intact).

### Dry Run Support

`aurgen --dry-run aur-deploy` prints a per-file diff, each root `*.install` file that would be removed, and the commit message. Nothing is copied, committed, or pushed.

`auto_push: false` still copies and commits in the local clone. The push is the step it skips. `aurgen aur-push` pushes that clone: validation when `validate_before_push` is enabled, the configured SSH key, and `git push origin HEAD:master`. It first fetches origin and refuses a clone that has diverged (unpushed commits on a base origin has moved past), naming `aurgen aur-deploy --rollback` and `git pull --ff-only` as the way back. Nothing ahead of the upstream (`@{u}`, or `origin/master` when no upstream is set) exits 0 without pushing. A missing clone exits non-zero. A tracked file changed in the clone but not committed also stops the push, since validation reads the files and the push sends `HEAD`: commit the change or rerun `aurgen aur-deploy`.

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
- Error: `[aur-integration] AUR clone <path> is behind origin; run git -C <path> pull --ff-only, then re-run aurgen aur --deploy` (or `aurgen git --deploy` for `-git` packages); when unpushed commits also exist, it fails with `[aur-integration] AUR clone <path> has diverged from origin ...; run aurgen aur-deploy --rollback, then git -C <path> pull --ff-only and re-run aurgen <aur|git> --deploy`
- Another machine or a co-maintainer pushed since your last pull
- Run `git -C <aur_repo_dir>/<package> pull --ff-only` (or `aurgen aur-deploy --rollback` first if diverged), then `aurgen --deploy aur` or `aurgen --deploy git` to match the refused package (aur reads the pkgrel from the updated clone)

**Failed to push to AUR**
- Error: `[aur-integration] Failed to push to AUR`
- The commit is already in the local clone, but pushing to the AUR failed (e.g., connection drops, SSH authentication issues, or remote errors)
- Retry with `aurgen aur-push` without recommitting (works for both release and `-git` packages based on `aur/.SRCINFO`)
- If you need to revert unpushed commits instead, run `aurgen aur-deploy --rollback` (preview with `aurgen --dry-run aur-deploy --rollback`). Note that `--rollback` cannot rewind when there is no upstream yet (refuses with `[aur-integration] No valid upstream tracking branch (@{u}) in <path>; refusing history rollback to protect pushed commits`)

**AUR clone has uncommitted changes**
- Error: `[aur-integration] AUR clone <path> has uncommitted changes, or git status failed there; commit or discard the changes there before deploying` (or `commit or discard the changes in <path>, then re-run aurgen aur-push`)
- The local clone has uncommitted changes or untracked files
- Either commit the changes manually (`git -C <aur_repo_dir>/<package> commit -am "..."`), or run `aurgen aur-deploy --rollback` to discard uncommitted changes and delete untracked files
- Preview with `aurgen --dry-run aur-deploy --rollback` before executing
- Then redeploy with `aurgen --deploy aur` or `aurgen --deploy git` to match the package, or run `aurgen aur-push` if you committed

**.SRCINFO is out of date**
- Error: `[aur-integration] .SRCINFO is out of date; run (cd <path> && makepkg --printsrcinfo >| .SRCINFO)`
- Occurs during pre-push validation when `.SRCINFO` does not match `makepkg --printsrcinfo`
- Running the printed hint `(cd <aur_repo_dir>/<package> && makepkg --printsrcinfo >| .SRCINFO)` regenerates the file, but leaves the clone dirty with uncommitted changes
- To proceed: commit the regenerated file (`git -C <aur_repo_dir>/<package> commit -am "Update .SRCINFO"`) and retry pushing with `aurgen aur-push`, or discard it (`git -C <aur_repo_dir>/<package> checkout -- .SRCINFO` or `aurgen aur-deploy --rollback`) and redeploy with `aurgen --deploy aur` or `aurgen --deploy git`

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
