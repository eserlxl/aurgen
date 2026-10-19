# Versioning Strategy

AURGen follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`):

- **MAJOR** for incompatible API changes
- **MINOR** for backwards-compatible additions
- **PATCH** for backwards-compatible bug fixes

Examples: `1.0.0` → `1.0.1` (bug fix), `1.0.1` → `1.1.0` (new feature), `1.1.0` → `2.0.0` (breaking change).

The current version is the `VERSION` file at the repository root. `bin/aurgen` reads it into `AURGEN_VERSION` and prints it for `--version` and `-v`:

```bash
aurgen --version
# aurgen version 1.0.0
```

The maintainer chooses the next bump. Nothing in the repository suggests `major`, `minor`, or `patch`. The steps that update `VERSION` are in [RELEASE_WORKFLOW.md](RELEASE_WORKFLOW.md).

## Conventional Commits

Commit messages may use [Conventional Commits](https://www.conventionalcommits.org/). That form is advice for readers of history. It does not select the next version.

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Usual types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`.

```bash
git commit -m "feat: add support for custom PKGBUILD templates"
git commit -m "fix: handle empty mapping files correctly"
git commit -m "docs: update installation instructions"
```

## When to bump

- **Patch** (`1.0.0` → `1.0.1`): bug fixes, small improvements, documentation, style, performance
- **Minor** (`1.0.0` → `1.1.0`): backwards-compatible features, CLI options, or modes
- **Major** (`1.0.0` → `2.0.0`): incompatible CLI or configuration changes, or removal of existing behavior
