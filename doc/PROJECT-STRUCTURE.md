# Project Structure

This document describes the complete directory structure of the AURGen project.

## Overview

AURGen follows a modular design with clear separation of concerns:

- **CLI Interface**: Main entry point and user interaction
- **Core Libraries**: Reusable utility functions and core logic
- **Mode Implementations**: Individual packaging mode handlers
- **Documentation**: Comprehensive guides and reference materials
- **Generated Artifacts**: Output files and package repositories

## Directory Structure

### Core Files

- `bin/aurgen` — Main CLI entrypoint
- `VERSION` — Current semantic version number

### Scripts (`scripts/`)

- `update-mapping` — Tool mapping update CLI
- `bump-version.sh` — Updates only the `VERSION` file. See [RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md)

### Tests (`tests/`)

- `run.sh` — Runs `tests/test-*.sh`

### Library Files (`lib/`)

Helper libraries and mode scripts that provide the core functionality:

- `helpers.sh` — Core utility functions, error handling, and prompts
- `init.sh` — Initialization and setup functions
- `valid-modes.sh` — Mode validation and usage information
- `aur-integration.sh` — AUR integration functionality and repository management
- `colors.sh` — Color output and formatting
- `detect-deps.sh` — Automatic dependency detection for build systems
- `tool-mapping.sh` — Tool to package mapping for Arch Linux
- `expand-mapping.sh` — Tool mapping expansion and update system
- `gen-pkgbuild0.sh` — PKGBUILD generation with install function creation
- `check-pkgbuild0.sh` — PKGBUILD validation and checking
- `config.sh` — Loading and validating `aur/aurgen.install.yaml`
- `config-import.sh` — Importing a hand-written PKGBUILD into `aurgen.install.yaml`
- `exclude-words.sh` — Words ignored by README dependency detection

### Mode Implementations (`lib/modes/`)

Individual mode implementations that handle specific packaging workflows:

- `aur.sh` — AUR release package mode
- `git.sh` — AUR VCS package mode
- `aur-init.sh` — AUR repository initialization mode
- `aur-deploy.sh` — AUR package deployment and `aur-push` modes
- `aur-status.sh` — AUR repository status checking mode
- `local.sh` — Local build and test mode
- `clean.sh` — Cleanup mode
- `test.sh` — Testing framework mode
- `lint.sh` — Code linting mode
- `golden.sh` — Golden file generation mode
- `config.sh` — Configuration mode (generate, import, show, edit, validate, reset)

### Documentation (`doc/`)

Comprehensive documentation covering all aspects of the project:

- `AUR.md` — Comprehensive AUR documentation
- `AUR-INTEGRATION.md` — AUR integration system documentation
- `AUR-QUICK-REFERENCE.md` — Quick reference card for AUR integration
- `USAGE.md` — Comprehensive usage guide and command reference
- `PKGBUILD-GENERATION.md` — PKGBUILD generation and configuration system documentation
- `DEVELOPER_GUIDE.md` — Contributor workflow, testing, CI/CD, and automation reference
- `MAPPING-SYSTEM.md` — Tool mapping system documentation
- `MAPPING-EXPANSION.md` — Tool mapping expansion documentation
- `VERSIONING.md` — Semantic versioning rules
- `RELEASE_WORKFLOW.md` — How a release updates `VERSION`, then commits, tags, and pushes
- `PROJECT-STRUCTURE.md` — This file, describing the project structure

### Generated Artifacts (`aur/`)

Package configuration and generated AUR artifacts:

- `.gitignore` — Ignores generated artifacts while keeping `aurgen.install.yaml` tracked
- `aurgen.install.yaml` — Active per-project install, package metadata, and AUR integration configuration
- `aurgen.install.yaml.example` — Generated example configuration reference
- `PKGBUILD.0` — Template file for PKGBUILD generation (tracked via `.PKGBUILD.0.stamp`)
- `PKGBUILD.HEADER` — Header template with copyright, license, and maintainer metadata
- `PKGBUILD` — Generated package build file (with `PKGBUILD.prev` backup of previous output)
- `.SRCINFO` — Generated package source metadata (with `.SRCINFO.prev` backup)
- `<pkgname>.install` — Optional hand-written or generated pacman install scriptlet
- `dry-run/` — Isolated output directory for `--dry-run` and `aurgen test` child runs
- `golden/` — Reference `PKGBUILD.<mode>.golden` snapshots managed by `aurgen golden`
- `test/` — Per-subtest log files written by `aurgen test`
- `lint/` — Per-script lint output mirror written by `aurgen lint`

The AUR git clones are not kept here. `aur-init` and `aur-deploy` clone into `${XDG_DATA_HOME:-~/.local/share}/aurgen/aur/<package>` (set `aur_integration.aur_repo_dir` to change it).

### GitHub Integration (`.github/`)

GitHub-specific files for automation, documentation, and project governance:

- `workflows/` — GitHub Actions automation
  - `shellcheck.yml` — Shell script linting and code quality checks
  - `test.yml` — Runs `bash tests/run.sh` functional tests on Ubuntu on `push` and `pull_request`; `./bin/aurgen lint` and `./bin/aurgen test` (requiring Arch tools) remain local checks in the release gate
- `dependabot.yml` — Automated dependency updates for GitHub Actions
- `SECURITY.md` — Security policy and vulnerability reporting guidelines
- `CONTRIBUTING.md` — Contribution guidelines and development setup
- `CODE_OF_CONDUCT.md` — Community code of conduct
- `pull_request_template.md` — Pull request template for standardized submissions
- `ISSUE_TEMPLATE/` — Issue templates for bug reports and feature requests
  - `bug_report.md` — Standardized bug report template
  - `feature_request.md` — Standardized feature request template

### Project Files

- `.gitattributes` — Export-ignore rules keeping non-shipped files out of git archives
- `.gitignore` — Repository ignore rules for local build and tool state
- `LICENSE` — GNU General Public License v3.0 or later
- `README.md` — Main project documentation and quick start guide

## Design Principles

The project structure follows these key principles:

1. **Modularity**: Each mode and library has a single responsibility
2. **Separation of Concerns**: Core logic, user interface, and documentation are clearly separated
3. **Extensibility**: New modes can be easily added to the `lib/modes/` directory
4. **Maintainability**: Clear file organization makes the codebase easy to navigate and maintain
5. **Documentation**: Comprehensive documentation for all major components

## Development Workflow

When developing new features or modes:

1. **Core Logic**: Add utility functions to appropriate files in `lib/`
2. **New Modes**: Create new mode files in `lib/modes/`
3. **Documentation**: Update relevant documentation in `doc/`
4. **Testing**: Use the test mode to validate changes
5. **Linting**: Run lint mode to ensure code quality 