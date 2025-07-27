# Tag Management Guide

This document provides guidance on managing Git tags in the AURGen project to avoid tag proliferation and maintain a clean repository.

## Current Tag Issues

### Problems with Previous Approach
1. **Too Many Tags**: Automated version bumping based on commit messages created tags for every small change
2. **No Cleanup**: Old tags accumulated over time
3. **Inconsistent Format**: Mixed tag formats (e.g., `v1.1.2` vs `1.0.0`)
4. **Unreliable Detection**: Commit message analysis was not always accurate

## Solutions Implemented

### 1. Semantic Version Bumping

The version bump workflow has been redesigned to use semantic analysis with intelligent automation:

#### Automatic Release Detection
- **MAJOR releases**: Any breaking changes detected
- **MINOR releases**: New features with large diffs (>50 lines)
- **PATCH releases**: Bug fixes with significant diffs (>20 lines)
- **No release**: Small changes that don't meet thresholds

#### Manual Trigger Options
- Use GitHub Actions interface to manually trigger version bumps
- Choose specific bump type (major, minor, patch) or "auto" for detection
- Add custom release notes
- Mark as prerelease if needed
- Full control over when releases are created

#### Semantic Version Analyzer
- Analyzes actual code changes rather than commit messages
- Examines file modifications, additions, and deletions
- Suggests appropriate version bump type
- Provides detailed analysis of changes
- Includes diff size analysis for threshold-based decisions

### 2. Automated Tag Cleanup

A new workflow (`.github/workflows/tag-cleanup.yml`) automatically manages tags:

#### Features
- **Weekly Cleanup**: Runs every Sunday at 2 AM UTC
- **Configurable Retention**: Keeps the 10 most recent tags by default
- **Manual Trigger**: Can be run manually with custom parameters
- **Dry Run Mode**: Preview what would be deleted before actual cleanup

#### Usage
```bash
# Via GitHub Actions interface:
# 1. Go to Actions tab
# 2. Select "Tag Cleanup"
# 3. Click "Run workflow"
# 4. Set keep_count (default: 10)
# 5. Set dry_run (default: true)
```

### 3. Tag Manager Script

A new script (`dev-bin/tag-manager`) provides command-line tag management:

#### Commands
```bash
# List all tags (sorted by version)
./dev-bin/tag-manager list

# Clean up old tags (interactive)
./dev-bin/tag-manager cleanup [count]

# Create a new tag
./dev-bin/tag-manager create <version>

# Show detailed tag information
./dev-bin/tag-manager info <tag>
```

#### Examples
```bash
# List current tags
./dev-bin/tag-manager list

# Keep only 5 most recent tags
./dev-bin/tag-manager cleanup 5

# Create tag for version 1.2.0
./dev-bin/tag-manager create 1.2.0

# Show info about v1.1.2
./dev-bin/tag-manager info v1.1.2
```

## Best Practices

### 1. When to Create Tags
- **Major Releases**: Significant new features or breaking changes
- **Minor Releases**: New features (backward-compatible)
- **Patch Releases**: Bug fixes and minor improvements
- **NOT for every commit**: Avoid tagging every small change

### 2. Tag Naming Convention
- Use consistent format: `vX.Y.Z` (e.g., `v1.2.3`)
- Always prefix with `v` for version tags
- Use semantic versioning

### 3. Tag Cleanup Strategy
- **Keep Recent**: Maintain the 10 most recent tags
- **Archive Old**: Consider archiving old releases on GitHub
- **Document Breaking Changes**: Keep tags for major version changes longer

### 4. Release Workflow
1. **Develop**: Make changes with clear commit messages
2. **Analyze**: Use semantic version analyzer to understand changes
3. **Review**: Check the suggested version bump type
4. **Trigger**: Manually trigger version bump when ready
5. **Review**: Check generated release notes
6. **Cleanup**: Run tag cleanup periodically

## Migration from Current State

### Immediate Actions
1. **Standardize Tag Format**: Ensure all future tags use `vX.Y.Z` format
2. **Clean Up Inconsistent Tags**: Remove or rename tags with inconsistent formats
3. **Set Up Automated Cleanup**: Enable the tag cleanup workflow

### Long-term Strategy
1. **Reduce Tag Frequency**: Use manual triggers for more control
2. **Batch Changes**: Group related changes into single releases
3. **Document Releases**: Maintain good release notes for each tag

## Configuration

### GitHub Actions Settings
- **Version Bump**: Manual trigger with auto-detection option
- **Tag Cleanup**: Weekly automatic + manual trigger
- **Retention**: 10 tags by default (configurable)

### Local Development
- Use `./dev-bin/tag-manager` for local tag operations
- Use `./dev-bin/bump-version` for version management
- Use `./dev-bin/semantic-version-analyzer` for change analysis
- Write clear commit messages to help with analysis

## Troubleshooting

### Common Issues
1. **Too Many Tags**: Run cleanup workflow or use tag manager
2. **Inconsistent Formats**: Use tag manager to standardize
3. **Accidental Tags**: Delete via GitHub interface or tag manager
4. **Workflow Failures**: Check GitHub Actions logs for errors

### Commands Reference
```bash
# List all tags
git tag --sort=-version:refname

# Delete local tag
git tag -d <tag_name>

# Delete remote tag
git push origin :refs/tags/<tag_name>

# Show tag details
git show <tag_name>

# Compare tags
git log <old_tag>..<new_tag> --oneline
```

## Future Improvements

### Potential Enhancements
1. **Release Notes Templates**: Custom templates for different release types
2. **Tag Categories**: Different retention policies for different tag types
3. **Integration**: Better integration with package managers (AUR, etc.)
4. **Notifications**: Slack/Discord notifications for releases
5. **Analytics**: Track release frequency and impact

### Monitoring
- Monitor tag creation frequency
- Track release quality and user feedback
- Adjust retention policies based on project needs
- Review and update this guide periodically 