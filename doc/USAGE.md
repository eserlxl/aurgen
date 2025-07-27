# AURGen Usage Guide

This document provides comprehensive usage information for AURGen, including all available modes, options, and workflows.

## Quick Start

```bash
# Basic usage
aurgen <mode> [options]

# Examples
aurgen local                    # Build and test locally
aurgen aur                      # Prepare for AUR release
aurgen aur-deploy               # Deploy to AUR
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
- Creates a local tarball from your project
- Generates PKGBUILD and .SRCINFO
- Builds the package locally using `makepkg`
- Installs the package for testing

**Use case:** Test your package locally before releasing

#### `aur`
Prepare a release tarball, sign it with GPG, and update PKGBUILD for AUR upload.

```bash
aurgen aur
```

**What it does:**
- Creates a reproducible tarball from your git repository
- Signs the tarball with GPG
- Uploads tarball and signature to GitHub releases
- Updates PKGBUILD with correct checksums and URLs
- Generates .SRCINFO file

**Use case:** Prepare your package for AUR submission

#### `git`
Generate a PKGBUILD for the -git (VCS) AUR package.

```bash
aurgen git
```

**What it does:**
- Creates a PKGBUILD for git-based packages
- Uses git sources instead of release tarballs
- Generates .SRCINFO for git packages

**Use case:** Create git-based AUR packages

### AUR Integration Modes

#### `aur-init`
Initialize a new AUR repository for package deployment.

```bash
aurgen aur-init
```

**What it does:**
- Creates the AUR repository directory if it doesn't exist
- Clones the AUR repository from `ssh://aur@aur.archlinux.org/$pkgname.git`
- Sets up the local repository for future deployments

**Requirements:**
- Git must be installed
- SSH access to AUR (you must have an AUR account and SSH key configured)

**Use case:** First-time setup of AUR repository

#### `aur-deploy`
Deploy your package to AUR.

```bash
aurgen aur-deploy
```

**What it does:**
- Ensures PKGBUILD and .SRCINFO exist (run `aurgen aur` first if needed)
- Checks if AUR repository exists (initializes if missing)
- Creates backups of existing files (if configured)
- Copies PKGBUILD and .SRCINFO to AUR repository
- Commits changes with configured commit message
- Pushes to AUR (if auto-push is enabled)

**Requirements:**
- PKGBUILD and .SRCINFO must exist (run `aurgen aur` first)
- Git must be installed
- SSH access to AUR (if auto-push is enabled)

**Use case:** Deploy your package to AUR after preparation

#### `aur-status`
Check the status of your AUR repository.

```bash
aurgen aur-status
```

**What it does:**
- Displays repository existence status
- Shows git working directory status
- Reports remote branch status
- Shows current AUR integration configuration

**Use case:** Check the health of your AUR repository

### Utility Modes

#### `clean`
Remove all generated files and directories in the output folder.

```bash
aurgen clean
```

**What it does:**
- Removes all generated files in the `aur/` directory
- Cleans up build artifacts, tarballs, and temporary files
- Resets the working directory to a clean state

**Use case:** Clean up after testing or before a fresh build

#### `test`
Run all modes in dry-run mode to check for errors and report results.

```bash
aurgen test
```

**What it does:**
- Runs all packaging modes in dry-run mode
- Validates configuration and dependencies
- Reports success/failure for each mode
- Provides comprehensive testing coverage

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
- Regenerates reference PKGBUILD files
- Updates test fixtures for comparison
- Ensures test accuracy

**Use case:** Update test fixtures after changes

#### `config`
Manage AURGen configuration for directory copying behavior.

```bash
aurgen config
```

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
Dry run (no changes, for testing).

```bash
aurgen --dry-run aur
```

#### `--no-wait`
Skip post-upload wait for asset availability (for CI/advanced users).

```bash
aurgen --no-wait aur
```

#### `--maxdepth N`
Set maximum search depth for lint and clean modes (default: 5).

```bash
aurgen --maxdepth 10 lint
```

#### `-h, --help`
Show detailed help and exit.

```bash
aurgen --help
aurgen aur --help
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

### AUR Integration Configuration

Configure AUR integration in your `aurgen.install.yaml`:

```yaml
aur_integration:
  aur_repo_dir: /opt/AUR
  auto_push: true
  commit_message: "Update to version {version}"
  git_user_name: "Your Name"
  git_user_email: "your.email@example.com"
  ssh_key: ~/.ssh/aur_key
  backup_existing: true
  validate_before_push: true
```

### Environment Variables

- `NO_COLOR`: Disable colored output
- `GPG_KEY_ID`: Set GPG key ID to skip interactive selection
- `AUTO`: Skip GitHub asset upload prompt
- `CI`: Skip interactive prompts (useful for CI/CD)
- `NO_WAIT`: Skip post-upload wait for asset availability
- `RELEASE`: Override automatic mode detection
- `AURGEN_LIB_DIR`: Set custom library directory path
- `AURGEN_LOG`: Set custom log file path
- `AURGEN_ERROR_LOG`: Set custom error log file path
- `MAXDEPTH`: Set maximum search depth for lint and clean modes

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
# Run all tests
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
# Show general help
aurgen --help

# Show mode-specific help
aurgen <mode> --help

# Show usage
aurgen --usage
```

## Best Practices

1. **Always test locally first** using `aurgen local`
2. **Use meaningful commit messages** in AUR integration configuration
3. **Enable validation** to catch issues early
4. **Keep backups enabled** for safety
5. **Monitor AUR status** regularly with `aurgen aur-status`
6. **Run tests** before deploying with `aurgen test`
7. **Check code quality** with `aurgen lint`

## Security Considerations

- Store AUR SSH keys securely with appropriate permissions
- Only maintain packages you have permission to maintain
- Always review generated PKGBUILD and .SRCINFO files before deployment
- Keep backups enabled to prevent accidental data loss
- Use validation features to ensure package integrity 