# AURGen Versioning System

AURGen follows [Semantic Versioning (SemVer)](https://semver.org/) principles to ensure clear and predictable version management.

## Version Format

AURGen uses the standard semantic versioning format: `MAJOR.MINOR.PATCH`

- **MAJOR** version: Incompatible API changes
- **MINOR** version: New functionality in a backward-compatible manner  
- **PATCH** version: Backward-compatible bug fixes

**Examples:**
- `1.0.0` → `1.0.1` (bug fix)
- `1.0.1` → `1.1.0` (new feature)
- `1.1.0` → `2.0.0` (breaking change)

## Version Storage

The current version is stored in the `VERSION` file at the project root:

```
1.0.0
```

## Version Display

The version is automatically displayed when using the `--version` or `-v` flag:

```bash
aurgen --version
# Output: aurgen version 1.0.0
```

## Version Bumping

AURGen provides a dedicated script for version management: `dev-bin/bump-version`

### Usage

```bash
./dev-bin/bump-version [major|minor|patch] [--commit] [--tag]
```

### Arguments

- **major**: Increment major version (breaking changes)
- **minor**: Increment minor version (new features)
- **patch**: Increment patch version (bug fixes)

### Options

- **--commit**: Create a git commit with the version bump
- **--tag**: Create a git tag for the new version

### Examples

```bash
# Bump patch version (bug fix)
./dev-bin/bump-version patch

# Bump minor version and create commit
./dev-bin/bump-version minor --commit

# Bump major version, commit, and tag
./dev-bin/bump-version major --commit --tag
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
Each release should be tagged with the version number:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Commits
Version bumps should be committed with clear messages:

```bash
git commit -m "Bump version to 1.0.1"
```

## Release Process

1. **Determine the appropriate version bump type**
   - Patch for bug fixes
   - Minor for new features
   - Major for breaking changes

2. **Bump the version**
   ```bash
   ./dev-bin/bump-version patch --commit --tag
   ```

3. **Push changes**
   ```bash
   git push origin main
   git push origin v1.0.1
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
- `bin/aurgen` - Main CLI script (reads version)
- `lib/helpers.sh` - Help function (includes version option) 