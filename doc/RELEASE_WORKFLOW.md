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

`--dry-run` writes nothing.

After a successful bump the script prints these next steps (`A.B.C` is the new version):

```bash
git commit -am "chore: release vA.B.C"
git tag -a vA.B.C -m "vA.B.C"
git push origin main vA.B.C
```

## Removing a tag

An old tag is removed by hand:

```bash
git tag -d vX.Y.Z
git push origin --delete vX.Y.Z
```
