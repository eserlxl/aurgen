# AUR Integration

AURGen now includes comprehensive AUR (Arch User Repository) integration that automates the entire workflow from PKGBUILD generation to AUR submission.

## Overview

The AUR integration system provides:

- **Automatic AUR repository management**: Initialize and manage local AUR repositories
- **Seamless deployment**: Deploy PKGBUILD and .SRCINFO files to AUR with a single command
- **Configurable workflow**: Customize behavior through configuration files
- **Validation and safety**: Built-in validation and backup features

## Configuration

AUR integration is configured through the `aur_integration` section in your `aurgen.install.yaml` file:

```yaml
aur_integration:
  # Local AUR repositories directory
  aur_repo_dir: /opt/AUR
  # Auto-push to AUR after deployment
  auto_push: true
  # Commit message template (use {version} for version placeholder)
  commit_message: "Update to version {version}"
  # Git user configuration for AUR commits
  git_user_name: "Your Name"
  git_user_email: "your.email@example.com"
  # SSH key for AUR authentication (optional)
  ssh_key: ~/.ssh/aur_key
  # Backup existing files before overwriting
  backup_existing: true
  # Validate AUR repository before pushing
  validate_before_push: true
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `aur_repo_dir` | `/opt/AUR` | Directory where local AUR repositories are stored |
| `auto_push` | `true` | Automatically push changes to AUR after deployment |
| `commit_message` | `"Update to version {version}"` | Template for commit messages (use `{version}` placeholder) |
| `git_user_name` | (empty) | Git user name for AUR commits |
| `git_user_email` | (empty) | Git user email for AUR commits |
| `ssh_key` | (empty) | Path to SSH key for AUR authentication |
| `backup_existing` | `true` | Create backups before overwriting existing files |
| `validate_before_push` | `true` | Validate repository before pushing to AUR |

## Commands

### `aurgen aur-init`

Initialize a new AUR repository for your package.

```bash
aurgen aur-init
```

This command:
- Creates the AUR repository directory if it doesn't exist
- Clones the AUR repository from `ssh://aur@aur.archlinux.org/$pkgname.git`
- Sets up the local repository for future deployments

**Requirements:**
- Git must be installed
- SSH access to AUR (you must have an AUR account and SSH key configured)

### `aurgen aur-deploy`

Deploy your package to AUR.

```bash
aurgen aur-deploy
```

This command:
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
aurgen aur && aurgen aur-deploy
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

## Safety Features

### Automatic Backups

When `backup_existing` is enabled, AURGen creates timestamped backups before overwriting files:

```
/opt/AUR/your-package/backup-20250115-143022/
├── PKGBUILD
└── .SRCINFO
```

### Validation

When `validate_before_push` is enabled, AURGen validates:
- PKGBUILD syntax
- .SRCINFO syntax
- Required files exist

### Dry Run Support

You can test the deployment process without actually pushing:

```bash
# Set auto_push to false in configuration
aurgen aur-deploy
```

## Troubleshooting

### Common Issues

**SSH Authentication Failed**
- Ensure your SSH key is added to your AUR account
- Check SSH configuration in `~/.ssh/config`
- Test SSH access manually

**Repository Not Found**
- Ensure the package name exists on AUR
- Check that you have maintainer access to the package
- Verify the package name in your PKGBUILD

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
4. **Use backups**: Keep `backup_existing` enabled for safety
5. **Monitor AUR status**: Use `aurgen aur-status` to check repository health

## Security Considerations

- **SSH keys**: Store your AUR SSH key securely and use appropriate permissions
- **Repository access**: Only maintain packages you have permission to maintain
- **Validation**: Always review generated PKGBUILD and .SRCINFO files before deployment
- **Backups**: Keep backups enabled to prevent accidental data loss 