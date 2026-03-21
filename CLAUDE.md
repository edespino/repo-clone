# repo-clone Development Guide

## Versioning

- Two-digit semver: `MAJOR.MINOR` (e.g., `1.1`)
- Bump `VERSION` in `repo-clone.sh` with every feature or fix before committing
- Minor bump for new features, major bump for breaking changes

## Testing

- Run `./tests/test-repo-clone.sh` before committing
- Add tests for every new flag or behavior change
- All tests must pass before pushing

## Architecture

- Single-file bash script (`repo-clone.sh`)
- CLI flags parsed in a loop that collects positional args separately (flags can appear anywhere)
- Catalog data stored in parallel arrays: `REPO_NAMES`, `REPO_URLS`, `REPO_BRANCHES`, `REPO_CATEGORIES`
- Non-interactive selection via `--repos` (by number or name) and `--group` (by category)
