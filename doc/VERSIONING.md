# Versioning Strategy

This document describes the versioning strategy used by AURGen.

## Semantic Versioning

AURGen follows [Semantic Versioning](https://semver.org/) (SemVer) with the format `MAJOR.MINOR.PATCH`:

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

### Version Format Examples

- `1.0.0` → `1.0.1` (bug fix)
- `1.0.1` → `1.1.0` (new feature)
- `1.1.0` → `2.0.0` (breaking change)

## Version Storage and Display

The current version is stored in the `VERSION` file at the project root:

```
1.0.0
```

The version is automatically displayed when using the `--version` or `-v` flag:

```bash
aurgen --version
# Output: AURGen version 1.0.0
```

## Semantic Version Bumping

The project uses a semantic versioning system that analyzes actual code changes and supports both manual and automatic releases based on the significance of changes.

### Automatic Release Detection

The system automatically detects and releases for significant changes:

- **MAJOR releases**: Any breaking changes detected
- **MINOR releases**: New features with large diffs (>50 lines)
- **PATCH releases**: Bug fixes with significant diffs (>20 lines)
- **No release**: Small changes that don't meet thresholds

### Semantic Version Analyzer

A dedicated script (`dev-bin/semantic-version-analyzer`) analyzes changes and suggests appropriate version bumps:

```bash
# Analyze changes since last tag
./dev-bin/semantic-version-analyzer

# Analyze changes since specific tag
./dev-bin/semantic-version-analyzer --since v1.1.0

# Show detailed analysis
./dev-bin/semantic-version-analyzer --verbose

# Analyze changes since specific date
./dev-bin/semantic-version-analyzer --since-date 2025-01-01
```

### What the Analyzer Checks

The semantic version analyzer examines:

1. **File Changes**:
   - Added files (especially shell scripts and libraries)
   - Modified files (function signatures, API changes)
   - Deleted files (removed functionality)

2. **Code Analysis**:
   - Breaking changes in shell scripts and libraries
   - New features in main scripts and modes
   - Bug fixes and error handling
   - Configuration changes

3. **Commit Messages**:
   - Keywords indicating breaking changes
   - New feature indicators
   - Bug fix references

4. **Change Magnitude**:
   - Diff size analysis for threshold-based decisions
   - Automatic release triggers for significant changes

### Manual Version Bumping

You can manually trigger version bumps through the GitHub Actions interface:
1. Go to the "Actions" tab in your repository
2. Select "Auto Version Bump with Semantic Release Notes"
3. Click "Run workflow"
4. Choose the bump type (auto, major, minor, patch)
5. Optionally add custom release notes
6. Mark as prerelease if needed

### Automatic vs Manual Releases

- **Automatic**: Triggered on pushes to main for significant changes
- **Manual**: Full control when you want to release regardless of change size
- **Auto Detection**: Manual trigger with automatic analysis and suggestion

### Commit Message Guidelines

While the semantic version analyzer examines actual code changes, good commit messages help with analysis and documentation:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Recommended Commit Types

- **feat**: New features or functionality
- **fix**: Bug fixes and error corrections
- **docs**: Documentation changes
- **style**: Code style changes (formatting, etc.)
- **refactor**: Code refactoring
- **perf**: Performance improvements
- **test**: Test additions or changes
- **chore**: Maintenance tasks

### Version Bump Guidelines

The semantic analyzer suggests version bumps based on:

- **MAJOR**: Breaking changes, incompatible API changes
- **MINOR**: New features, backward-compatible additions
- **PATCH**: Bug fixes, minor improvements, documentation

### Examples

```bash
# New feature (will be detected by semantic analyzer)
git commit -m "feat: add support for custom PKGBUILD templates"

# Bug fix (will be detected by semantic analyzer)
git commit -m "fix: handle empty mapping files correctly"

# Documentation update
git commit -m "docs: update installation instructions"

# Breaking change (will be detected by semantic analyzer)
git commit -m "feat: change CLI interface - breaking change"
```

## Manual Version Bumping

To manually bump the version, use the `dev-bin/bump-version` script:

### Usage

```bash
./dev-bin/bump-version [major|minor|patch] [--commit] [--tag] [--dry-run]
```

### Arguments

- **major**: Increment major version (breaking changes)
- **minor**: Increment minor version (new features)
- **patch**: Increment patch version (bug fixes)

### Options

- **--commit**: Create a git commit with the version bump
- **--tag**: Create a git tag for the new version
- **--dry-run**: Show what would be done without making changes

### Examples

```bash
# Bump patch version (1.0.0 -> 1.0.1)
./dev-bin/bump-version patch

# Bump minor version (1.0.0 -> 1.1.0)
./dev-bin/bump-version minor

# Bump major version (1.0.0 -> 2.0.0)
./dev-bin/bump-version major

# Bump and commit changes
./dev-bin/bump-version patch --commit

# Bump minor version, commit, and tag
./dev-bin/bump-version minor --commit --tag

# Show what a patch bump would do
./dev-bin/bump-version patch --dry-run
```

## When to Bump Versions

### Patch Version (1.0.0 → 1.0.1)
- Bug fixes
- Minor improvements
- Documentation updates
- Code style changes
- Performance optimizations

### Minor Version (1.0.0 → 1.1.0)
- New features (backward-compatible)
- New CLI options
- Enhanced functionality
- New modes or capabilities

### Major Version (1.0.0 → 2.0.0)
- Breaking changes to CLI interface
- Incompatible changes to configuration
- Major architectural changes
- Removal of deprecated features

## Git Integration

### Tags
Each release should be tagged with the version number. Tags are automatically created by the version bump workflow with the format `vX.Y.Z`.

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Tag Management

The project includes tools for managing tags:

#### Tag Manager Script
```bash
# List all tags
./dev-bin/tag-manager list

# Clean up old tags (keep 10 most recent)
./dev-bin/tag-manager cleanup 10

# Create a new tag
./dev-bin/tag-manager create 1.2.0

# Show tag information
./dev-bin/tag-manager info v1.1.2
```

#### Automated Tag Cleanup
The project includes a GitHub Actions workflow that automatically cleans up old tags:
- Runs weekly on Sundays
- Keeps the 10 most recent tags by default
- Can be triggered manually with custom parameters

### Commits
Version bumps should be committed with clear messages:

```bash
git commit -m "Bump version to 1.0.1"
```

## Release Process

### Semantic Release Process (Recommended)

1. **Analyze Changes**: Use the semantic version analyzer to understand what changed
   ```bash
   ./dev-bin/semantic-version-analyzer --verbose
   ```

2. **Review Suggestion**: The analyzer suggests the appropriate version bump type
   - MAJOR for breaking changes
   - MINOR for new features
   - PATCH for bug fixes

3. **Manual Trigger**: Use GitHub Actions to create the release
   - Go to Actions → Auto Version Bump → Run workflow
   - Choose the suggested bump type
   - Add custom release notes if needed

4. **Review Release**: Check the generated release notes and tag

### Alternative Manual Process

1. **Analyze changes manually**
   - Review code changes since last release
   - Determine impact on users

2. **Bump the version**
   ```bash
   ./dev-bin/bump-version patch --commit
   ```

3. **Push changes**
   ```bash
   git push origin main
   ```

4. **Create GitHub release** (optional)
   - Go to GitHub repository
   - Create a new release from the tag
   - Add release notes

## Version in Code

The version is automatically read from the `VERSION` file and made available as the `AURGEN_VERSION` environment variable in the main script.

### Accessing Version in Scripts

```bash
# In any sourced script
echo "AURGen version: $AURGEN_VERSION"
```

## Best Practices

1. **Always bump version before releasing**
2. **Use semantic versioning consistently**
3. **Tag releases with git tags**
4. **Write clear commit messages for version bumps**
5. **Document breaking changes in release notes**
6. **Test thoroughly before releasing**

## Pre-release Versions

For development and testing, you can use pre-release suffixes:

- `1.0.0-alpha.1` (alpha releases)
- `1.0.0-beta.1` (beta releases)
- `1.0.0-rc.1` (release candidates)

These should be manually edited in the `VERSION` file and tagged accordingly.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-01-XX | Initial release |

## Related Files

- `VERSION` - Current version number
- `dev-bin/bump-version` - Version bumping script
- `dev-bin/semantic-version-analyzer` - Semantic version analysis script
- `dev-bin/tag-manager` - Tag management script
- `bin/aurgen` - Main script (reads version)
- `.github/workflows/version-bump.yml` - Manual version bump workflow
- `.github/workflows/tag-cleanup.yml` - Automated tag cleanup workflow

## Version File

The current version is stored in the `VERSION` file at the project root. This file is automatically updated by the version bump workflow and should not be manually edited. 