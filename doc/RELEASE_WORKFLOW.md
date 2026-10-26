# Release Workflow

A release updates the `VERSION` file. The maintainer then commits, tags, and pushes. `scripts/bump-version.sh` updates only that file. It never commits, tags, or pushes.

There is no automatic bump suggestion. The maintainer chooses `major`, `minor`, `patch`, or an explicit `X.Y.Z`. [Semantic Versioning](https://semver.org/) and Conventional Commits, described in [VERSIONING.md](VERSIONING.md), are advice for that choice.

## Command

```bash
scripts/bump-version.sh <major|minor|patch|X.Y.Z> [--dry-run]
```

The script refuses:

- a dirty work tree (`ALLOW_DIRTY=1` overrides this check)
- a version that is not `X.Y.Z`
- a target that does not increase the current version
- an existing `vX.Y.Z` tag for the target

`--dry-run` writes nothing and prints no release commands.

After a successful bump the script prints these next steps (`A.B.C` is the new version, `/path/to/repo` the repository root, shell-quoted, and `feature` the current branch):

```bash
git -C /path/to/repo commit -m "chore: release vA.B.C" -- VERSION
git tag -a vA.B.C -m "vA.B.C"
git push origin feature vA.B.C
```

The commit includes only `VERSION`, even with `ALLOW_DIRTY=1`, and works from any directory, such as `scripts/`. The push uses `main` if branch detection fails or HEAD is detached.

## Release gate

Run these three commands from the repository root after the bump and before the commit, the tag, and the push. They are the release gate; the GitHub workflows do not run them.

```bash
bash tests/run.sh
./bin/aurgen lint
./bin/aurgen test
```

## Removing a tag

An old tag is removed by hand:

```bash
git tag -d vX.Y.Z
git push origin --delete vX.Y.Z
```
