# AURGen Developer Guide

This guide is intended for developers contributing to AURGen or using it for advanced development workflows.

## Table of Contents

- [Versioning](#versioning)
  - [Version Bumping](#version-bumping)
- [Tool Mapping System](#tool-mapping-system)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Automation & CI/CD](#automation--cicd)
- [GitHub CLI Integration](#github-cli-integration)
- [Environment Variables for Automation/CI](#environment-variables-for-automationci)
- [Contributing](#contributing)

## Versioning

AURGen follows [Semantic Versioning (SemVer)](https://semver.org/) principles. The current version is stored in the `VERSION` file and can be displayed using:

```bash
aurgen --version
# Output: aurgen version 1.0.0
```

### Version Bumping

Use the included version bumping script for consistent version management:

```bash
# Bump patch version (bug fixes)
./dev-bin/bump-version patch

# Bump minor version (new features) and create commit
./dev-bin/bump-version minor --commit

# Bump major version (breaking changes), commit, and tag
./dev-bin/bump-version major --commit --tag
```

For detailed versioning documentation, see [doc/VERSIONING.md](VERSIONING.md).

## Tool Mapping System

AURGen uses a comprehensive mapping system that converts common tool names to their containing packages. The system currently maps **307 tools** across build tools, compilers, package managers, and utilities.

For detailed documentation on the tool mapping system, see [doc/MAPPING-SYSTEM.md](MAPPING-SYSTEM.md).

## Development Workflow

### Local Development

1. **Setup**: Ensure you have all development dependencies installed
2. **Testing**: Run comprehensive tests before making changes
3. **Linting**: Use the lint mode to check code quality
4. **Version Management**: Use the version bumping tools for releases

### Testing

AURGen includes a comprehensive testing framework:

```bash
# Run all tests in dry-run mode
aurgen test

# Run linting checks
aurgen lint

# Clean up test artifacts
aurgen clean
```

### Code Quality

- **ShellCheck**: All Bash scripts are linted with ShellCheck
- **Bash Syntax**: All scripts are validated with `bash -n`
- **Documentation**: Keep documentation updated with code changes

## Contributing

### Code Style

- Follow existing Bash conventions
- Use consistent indentation (2 spaces)
- Include proper error handling
- Add comments for complex logic

### Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request with clear description

### Development Tools

- **Version Management**: `./dev-bin/bump-version`
- **Tag Management**: `./dev-bin/tag-manager`
- **Semantic Analysis**: `./dev-bin/semantic-version-analyzer`
- **Cursor Integration**: `./dev-bin/cursor-version-bump`

For more detailed contributing guidelines, see [CONTRIBUTING.md](../.github/CONTRIBUTING.md).

## Automation & CI/CD

AURGen includes comprehensive GitHub Actions automation for security, quality, and maintenance:

- **🔄 Auto Version Bump**: Automatically bumps semantic versions and creates releases based on conventional commit messages
- **🔒 Security Scanning**: CodeQL vulnerability detection for supported languages (JavaScript, Python) and ShellCheck for shell scripts
- **📦 Dependency Updates**: Dependabot automatically updates GitHub Actions and other dependencies
- **✅ Quality Checks**: ShellCheck linting and functional testing on every change
- **🚀 Release Automation**: Automated release creation with changelog generation

All automation runs on pushes to main and pull requests, ensuring code quality and security.

## GitHub CLI Integration

AURGen integrates with GitHub CLI (`gh`) to automatically upload release assets:

- **Automatic Asset Upload**: If GitHub CLI is installed, AURGen can automatically upload missing release assets to GitHub releases
- **Smart Asset Management**: When a release asset doesn't exist, AURGen uploads the tarball and signature automatically (no prompt)
- **Overwrite Protection**: If the asset already exists, you'll be prompted to confirm overwriting before upload
- **CI/Automation**: Set the `AUTO` environment variable to skip the upload prompt (always overwrite)
- **Graceful Fallback**: If GitHub CLI is not installed, AURGen provides clear instructions for manual upload

## Environment Variables for Automation/CI

- `NO_COLOR`: Set to any value to disable colored output (alternative to `--no-color`)
- `GPG_KEY_ID`: Set to your GPG key ID to skip the interactive key selection menu (auto-selects first key after 10-second timeout if not set)
- `AUTO`: Skip the GitHub asset upload prompt in `aur` mode (requires GitHub CLI `gh` to be installed)
- `CI`: Skip interactive prompts in `aur` mode (useful for CI/CD pipelines). **If set, AURGen automatically runs in development mode (RELEASE=0) unless RELEASE is explicitly set.**
- `NO_WAIT`: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)
- `RELEASE`: Override automatic mode detection (1=release mode, 0=development mode)
- `AURGEN_LIB_DIR`: Set custom library directory path
- `AURGEN_LOG`: Set custom log file path (default: `/tmp/aurgen/aurgen.log`)
- `AURGEN_ERROR_LOG`: Set custom error log file path (default: `/tmp/aurgen/aurgen-error.log`)
- `MAXDEPTH`: Set maximum search depth for lint and clean modes (default: 5) 