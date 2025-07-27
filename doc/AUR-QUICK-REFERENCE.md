# AUR Integration Quick Reference

## Commands

| Command | Description | Use Case |
|---------|-------------|----------|
| `aurgen aur-init` | Initialize AUR repository | First-time setup |
| `aurgen aur-deploy` | Deploy package to AUR | After `aurgen aur` |
| `aurgen aur-status` | Check AUR repository status | Monitor health |

## Configuration

Add to `aurgen.install.yaml`:

```yaml
aur_integration:
  aur_repo_dir: /opt/AUR
  auto_push: true
  commit_message: "Update to version {version}"
  backup_existing: true
  validate_before_push: true
```

## Workflow

### Complete AUR Release
```bash
aurgen local          # Test locally
aurgen aur            # Prepare release
aurgen aur-init       # Setup AUR repo (first time)
aurgen aur-deploy     # Deploy to AUR
```

### Git Package
```bash
aurgen git            # Generate git package
aurgen aur-deploy     # Deploy to AUR
```

## Requirements

- **Git**: `sudo pacman -S git`
- **AUR Account**: Create at https://aur.archlinux.org/
- **SSH Key**: Add to AUR account and configure SSH

## SSH Setup

Add to `~/.ssh/config`:
```
Host aur.archlinux.org
    IdentityFile ~/.ssh/aur_key
    User aur
```

Test: `ssh aur@aur.archlinux.org help`

## Safety Features

- ✅ **Automatic Backups**: Timestamped backups before overwriting
- ✅ **Validation**: PKGBUILD and .SRCINFO syntax checking
- ✅ **Error Handling**: Comprehensive error checking
- ✅ **Dry Run**: Test without pushing (`--dry-run`)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| SSH Auth Failed | Check SSH key in AUR account |
| Repository Not Found | Verify package name and access |
| Permission Denied | Check SSH key permissions |

## Debug Mode

```bash
DEBUG_LEVEL=1 aurgen aur-status
```

## Documentation

- **Complete Guide**: [doc/AUR-INTEGRATION.md](doc/AUR-INTEGRATION.md)
- **Usage Guide**: [doc/USAGE.md](doc/USAGE.md)
- **Configuration**: `aurgen.install.yaml.example` 