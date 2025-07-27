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

#### Option A: Automatic Release (Recommended for significant changes)
- Push your changes to main
- If significant changes are detected, a release will be created automatically
- Check GitHub Actions to see if auto-release was triggered

#### Option B: Manual Release
1. Go to GitHub → Actions → "Auto Version Bump with Semantic Release Notes"
2. Click "Run workflow"
3. Choose the suggested bump type (or "auto" for automatic detection)
4. Add custom release notes (optional)
5. Mark as prerelease if needed
6. Click "Run workflow"

## Detailed Workflow

### Step 1: Prepare for Release

Before creating a release, ensure your changes are ready:

```bash
# Check current status
git status

# Make sure all changes are committed
git add .
git commit -m "feat: final changes before release"

# Push to main
git push origin main
```

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

#### Automatic Release Thresholds

The system uses these thresholds for automatic releases:

- **MAJOR**: Any breaking changes detected (no size threshold)
- **MINOR**: New features + diff size > 50 lines
- **PATCH**: Bug fixes + diff size > 20 lines
- **NO RELEASE**: Changes below thresholds or no significant indicators

### Step 4: Create Release

#### Option A: Automatic Release (Recommended)
- Simply push your changes to main
- The system will automatically analyze and release if significant changes are detected
- Check GitHub Actions to monitor the process

#### Option B: Manual GitHub Actions
1. Go to your repository on GitHub
2. Navigate to Actions tab
3. Select "Auto Version Bump with Semantic Release Notes"
4. Click "Run workflow"
5. Fill in the form:
   - **Bump type**: Choose "auto" for automatic detection or specific type
   - **Release notes**: Add custom notes (optional)
   - **Prerelease**: Check if this is a prerelease
6. Click "Run workflow"

#### Option C: Command Line
```bash
# Bump version locally
./dev-bin/bump-version patch --commit

# Push changes
git push origin main

# Create tag
git tag v1.1.3
git push origin v1.1.3
```

### Step 5: Verify Release

1. Check the GitHub Actions run completed successfully
2. Verify the new tag was created
3. Review the generated release notes
4. Check the release on GitHub Releases page

### Step 6: Clean Up (Optional)

Periodically clean up old tags:

```bash
# List current tags
./dev-bin/tag-manager list

# Clean up old tags (keep 10 most recent)
./dev-bin/tag-manager cleanup 10

# Or use GitHub Actions cleanup workflow
# Go to Actions → Tag Cleanup → Run workflow
```

## Examples

### Example 1: Bug Fix Release

```bash
# 1. Analyze changes
./dev-bin/semantic-version-analyzer --verbose
# Output: Suggested bump: PATCH

# 2. Create release via GitHub Actions
# - Bump type: patch
# - Release notes: "Fixed issue with empty mapping files"
```

### Example 2: New Feature Release

```bash
# 1. Analyze changes
./dev-bin/semantic-version-analyzer --since v1.1.0 --verbose
# Output: Suggested bump: MINOR

# 2. Create release via GitHub Actions
# - Bump type: minor
# - Release notes: "Added support for custom PKGBUILD templates"
```

### Example 3: Breaking Change Release

```bash
# 1. Analyze changes
./dev-bin/semantic-version-analyzer --verbose
# Output: Suggested bump: MAJOR

# 2. Create release via GitHub Actions
# - Bump type: major
# - Release notes: "Breaking: Changed CLI interface"
# - Prerelease: true (if testing)
```

## Troubleshooting

### Common Issues

1. **Analyzer shows no changes**
   - Check if you're analyzing the right time period
   - Use `--since-date` or `--since-commit` for specific ranges

2. **GitHub Actions fails**
   - Check the workflow logs for errors
   - Ensure you have write permissions to the repository

3. **Wrong version bump suggested**
   - Review the analysis manually
   - Override the suggestion in GitHub Actions

4. **Tag cleanup issues**
   - Use dry-run mode first: `./dev-bin/tag-manager cleanup 5`
   - Check GitHub Actions cleanup workflow

### Getting Help

- Check the logs in GitHub Actions
- Review the semantic analysis output
- Consult the main documentation in `doc/VERSIONING.md`
- Use the tag manager for manual operations

## Best Practices

1. **Regular Analysis**: Run the semantic analyzer before each release
2. **Meaningful Commits**: Write clear commit messages to help analysis
3. **Review Changes**: Always review what the analyzer found
4. **Test Releases**: Use prerelease flags for testing
5. **Clean Up**: Periodically clean up old tags
6. **Documentation**: Update release notes with meaningful information 