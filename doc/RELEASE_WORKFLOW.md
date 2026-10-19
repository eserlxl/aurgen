# Release Workflow Guide

This guide walks you through the new semantic versioning release process for AURGen.

## Quick Start

### 1. Analyze Changes
```bash
# Analyze changes since last release
./dev-bin/semantic-version-analyzer --verbose

# Or analyze since a specific tag
./dev-bin/semantic-version-analyzer --since v1.1.0 --verbose
```

### 2. Review Suggestion
The analyzer will suggest the appropriate version bump:
- **MAJOR**: Breaking changes detected
- **MINOR**: New features detected  
- **PATCH**: Bug fixes detected
- **NONE**: No significant changes

### 3. Create Release

Cut the release locally, then push the commit and the tag. Pushing `main` alone does not create a release.

```bash
./dev-bin/bump-version <major|minor|patch> --commit --tag
git push origin main
git push origin vX.Y.Z
```

`bump-version` accepts `major`, `minor`, or `patch`, and the flags `--commit`, `--tag`, and `--dry-run`.

## Detailed Workflow

### Step 1: Prepare for Release

Before creating a release, ensure your changes are ready:

```bash
# Check current status
git status

# Make sure all changes are committed
git add .
git commit -m "feat: final changes before release"
```

A push to `main` does not cut a release. The version commit and tag are pushed in Step 4.

### Step 2: Analyze Changes

Use the semantic version analyzer to understand what changed:

```bash
# Basic analysis
./dev-bin/semantic-version-analyzer

# Detailed analysis with file changes
./dev-bin/semantic-version-analyzer --verbose

# Analyze since specific date
./dev-bin/semantic-version-analyzer --since-date 2025-01-01

# Analyze since specific tag
./dev-bin/semantic-version-analyzer --since v1.1.0
```

### Step 3: Review Analysis

The analyzer will show:
- **File Changes**: Added, modified, deleted files
- **Change Indicators**: Breaking changes, new features, bug fixes
- **Diff Size**: Number of lines changed
- **Recent Commits**: List of commits since last release
- **Version Suggestion**: Recommended bump type

#### Suggestion Thresholds

The analyzer uses these thresholds when suggesting a bump. It does not publish a release.

- **MAJOR**: Any breaking changes detected (no size threshold)
- **MINOR**: New features + diff size > 50 lines
- **PATCH**: Bug fixes + diff size > 20 lines
- **NONE**: Changes below thresholds or no significant indicators

### Step 4: Create Release

```bash
# Bump, commit, and tag (use the suggested major, minor, or patch)
./dev-bin/bump-version patch --commit --tag

# Publish the commit and the tag
git push origin main
git push origin vX.Y.Z
```

### Step 5: Verify Release

1. Confirm `./dev-bin/bump-version` printed the new version, commit, and tag
2. Confirm `vX.Y.Z` exists locally (`git tag`)
3. Confirm the tag is on the remote after `git push origin vX.Y.Z`

### Step 6: Clean Up (Optional)

Periodically clean up old tags:

```bash
# List current tags
./dev-bin/tag-manager list

# Clean up old tags (keep 10 most recent; asks before deleting)
./dev-bin/tag-manager cleanup 10

# Keep the default of 10
./dev-bin/tag-manager cleanup
```

## Examples

### Example 1: Bug Fix Release

```bash
# 1. Analyze changes
./dev-bin/semantic-version-analyzer --verbose
# Output: Suggested bump: PATCH

# 2. Cut the release
./dev-bin/bump-version patch --commit --tag
git push origin main
git push origin vX.Y.Z
```

### Example 2: New Feature Release

```bash
# 1. Analyze changes
./dev-bin/semantic-version-analyzer --since v1.1.0 --verbose
# Output: Suggested bump: MINOR

# 2. Cut the release
./dev-bin/bump-version minor --commit --tag
git push origin main
git push origin vX.Y.Z
```

### Example 3: Breaking Change Release

```bash
# 1. Analyze changes
./dev-bin/semantic-version-analyzer --verbose
# Output: Suggested bump: MAJOR

# 2. Cut the release
./dev-bin/bump-version major --commit --tag
git push origin main
git push origin vX.Y.Z
```

## Troubleshooting

### Common Issues

1. **Analyzer shows no changes**
   - Check if you're analyzing the right time period
   - Use `--since-date` or `--since-commit` for specific ranges

2. **Push does not show a new tag**
   - The tag stays local until `git push origin vX.Y.Z`
   - Push the version commit with `git push origin main`

3. **Wrong version bump suggested**
   - Review the analysis manually
   - Pass `major`, `minor`, or `patch` to `./dev-bin/bump-version`

4. **Tag cleanup**
   - `./dev-bin/tag-manager cleanup [count]` lists the tags and asks before deleting them
   - Answering anything other than `y` cancels the cleanup

### Getting Help

- Review the semantic analysis output
- Consult the main documentation in `doc/VERSIONING.md`
- Use the tag manager for manual operations

## Best Practices

1. **Regular Analysis**: Run the semantic analyzer before each release
2. **Meaningful Commits**: Write clear commit messages to help analysis
3. **Review Changes**: Always review what the analyzer found
4. **Confirm the bump**: Pass the intended `major`, `minor`, or `patch` to `bump-version`
5. **Clean Up**: Periodically clean up old tags
6. **Documentation**: Update release notes with meaningful information 