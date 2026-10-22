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
- [Security](#security)

## Versioning

AURGen follows [Semantic Versioning (SemVer)](https://semver.org/) principles. The current version is stored in the `VERSION` file and can be displayed using:

```bash
aurgen --version
# Output: aurgen version 1.0.0
```

### Version Bumping

The maintainer chooses `major`, `minor`, or `patch`. SemVer rules are in [doc/VERSIONING.md](VERSIONING.md). The release steps are in [doc/RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md).

## Tool Mapping System

AURGen uses a comprehensive mapping system that converts common tool names to their containing packages. The system currently maps **307 tools** across build tools, compilers, package managers, and utilities.

For detailed documentation on the tool mapping system, see [doc/MAPPING-SYSTEM.md](MAPPING-SYSTEM.md).

## Development Workflow

### Local Development

1. **Setup**: Ensure you have all development dependencies installed
2. **Testing**: Run comprehensive tests before making changes
3. **Linting**: Use the lint mode to check code quality
4. **Version Management**: Follow [doc/RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md) for a release

### Testing

AURGen includes a comprehensive testing framework:

```bash
# Dry-run the local, aur and git modes
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

- **Mapping updates**: `scripts/update-mapping`
- **Tests**: `tests/run.sh` runs `tests/test-*.sh`
- **Releases**: [doc/RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md)

Bug reports and feature requests go to the GitHub issue tracker. A pull request should include documentation updates when the behavior changes.

For more detailed contributing guidelines, see [CONTRIBUTING.md](../.github/CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](../.github/CODE_OF_CONDUCT.md).

## Security

Report a security vulnerability privately by emailing **lxldev.contact@gmail.com**. Do not open a public issue for a security problem. Security updates are published for the latest stable version.

## Automation & CI/CD

GitHub Actions covers quality checks only. Releases are cut on a local checkout; see [doc/RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md).

- **Quality checks**: `shellcheck.yml` lints shell scripts. `test.yml` skips the AURGen functional tests, which need Arch tools; the local suites (`bash tests/run.sh`, `./bin/aurgen lint`, `./bin/aurgen test`) are the gate
- **Dependency updates**: Dependabot updates GitHub Actions dependencies (`dependabot.yml`)

## GitHub CLI Integration

AURGen integrates with GitHub CLI (`gh`) to automatically upload release assets:

- **Automatic Asset Upload**: If GitHub CLI is installed, AURGen can automatically upload missing release assets to GitHub releases
- **Smart Asset Management**: When a release asset doesn't exist, AURGen uploads the tarball and signature automatically (no prompt)
- **Overwrite Protection**: If the asset already exists, AURGen asks before uploading again. The default is no. Without a terminal the default is used, so the existing asset stays
- **Graceful Fallback**: If GitHub CLI is not installed, AURGen provides clear instructions for manual upload

## Environment Variables for Automation/CI

- `NO_COLOR`: Set to any non-empty value to disable colored output on a terminal (alternative to `--no-color`). Piped or redirected output is already plain
- `GPG_KEY_ID`: Set to your GPG key ID to skip the interactive key selection menu (auto-selects first key after 10-second timeout if not set)
- `CI`: Turns color off. It does not change the mode: a source checkout runs in development mode (`RELEASE=0`) unless `RELEASE` is set. Prompts still follow the terminal: without a terminal they take their default
- `NO_WAIT`: Set to `1` to skip the post-upload wait for asset availability (alternative to `--no-wait` flag)
- `RELEASE`: Override automatic mode detection (1=release mode, 0=development mode)
- `AURGEN_LIB_DIR`: Set custom library directory path
- `AURGEN_LOG`: Set custom log file path (default: `${XDG_STATE_HOME:-~/.local/state}/aurgen/aurgen.log`)
- `AURGEN_ERROR_LOG`: Set custom error log file path (default: `${XDG_STATE_HOME:-~/.local/state}/aurgen/aurgen-error.log`)
- `MAXDEPTH`: Positive integer search depth for lint and clean (default: 5). `0` and any non-integer are refused 