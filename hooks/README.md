# Git Hooks

This directory contains git hooks that can be installed to improve the development workflow.

## Available Hooks

### post-push
Automatically pulls after pushing to handle version conflicts from GitHub CI.

**Features:**
- Waits 5 seconds for GitHub CI to potentially update the version
- Checks for remote changes
- Automatically pulls if version conflicts are detected
- Only runs when push is successful

## Installation

To install the hooks, run:

```bash
# Install all hooks
ln -sf ../../hooks/post-push .git/hooks/post-push

# Or install individual hooks
ln -sf ../../hooks/post-push .git/hooks/post-push
```

## Usage

After installation, simply use `git push` normally. The hook will automatically:
1. Push your changes
2. Wait 5 seconds for GitHub CI
3. Check for remote changes
4. Pull if version conflicts are detected

## Manual Installation

If you prefer to install manually:

```bash
cp hooks/post-push .git/hooks/post-push
chmod +x .git/hooks/post-push
``` 