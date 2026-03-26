# repo-clone

Curl-installable bash tool that clones multiple GitHub repos (public/private) from a catalog file via interactive selection menu. Supports SSH auth, category grouping, per-repo branch targeting, and dry-run mode.

## Quick Start

```bash
# From a local catalog file
./repo-clone.sh /path/to/catalog.txt

# From a private repo (requires active SSH agent)
./repo-clone.sh git@github.com:your-org/config-repo.git path/to/catalog.txt

# One-liner via curl
curl -sL https://raw.githubusercontent.com/edespino/repo-clone/main/repo-clone.sh \
  | bash -s -- git@github.com:your-org/config-repo.git path/to/catalog.txt
```

## How It Works

1. Fetches a catalog file (from a local path or a private Git repo via SSH)
2. Displays an interactive numbered menu grouped by category
3. You select which repos to clone (by number, group name, comma-separated, or `all`)
4. Selected repos are cloned into `~/`

```
Fetching catalog...

  [infra]
      1) Build Pipeline  — https://github.com/org/build-pipeline
      2) Deploy Tool     — https://github.com/org/deploy-tool (branch: staging)

  [libs]
      3) Common Utils    — https://github.com/org/common-utils

Select repos to clone (e.g. 1 3 4, 1,3,4, group name, or "all"): 1 3

Clone into /current/working/directory? [Y/n/path]: Y

Cloning Build Pipeline into /current/working/directory/build-pipeline...  done
Cloning Common Utils into /current/working/directory/common-utils...  done

Summary:
  Cloned: 2
  Skipped: 0
  Failed: 0
```

## Catalog Format

Plain text, pipe-delimited. Category headers use `[brackets]`. Comments (`#`) and blank lines are ignored.

```
# Infrastructure repos
[infra]
Build Pipeline|git@github.com:org/build-pipeline.git
Deploy Tool|git@github.com:org/deploy-tool.git|staging

# Shared libraries
[libs]
Common Utils|git@github.com:org/common-utils.git
```

Each line: `display_name|ssh_clone_url` or `display_name|ssh_clone_url|branch`

| Field | Required | Description |
|-------|----------|-------------|
| `display_name` | Yes | Human-readable name shown in the menu |
| `ssh_clone_url` | Yes | SSH clone URL (`git@github.com:...`) |
| `branch` | No | Specific branch to clone (default branch if omitted) |

### YAML Format

Files ending in `.yml` or `.yaml` are parsed automatically. This is useful when a repo already maintains a structured registry of repositories (e.g., `upstream/repos.yml` in the build pipeline repo).

```yaml
github_org: Synx-Data-Labs

repos:
  - name: database
    github_repo: hashdata-cloud
    source: enterprise

  - name: gpbackup
    github_repo: hashdata-gpbackup
    source: enterprise,lightning

  - name: pgvector-enterprise
    github_repo: hashdata-pgvector
    github_branch: support_cloud_service
    source: enterprise
```

| Field | Required | Description |
|-------|----------|-------------|
| `github_org` | Yes | Top-level field — GitHub organization used to construct clone URLs |
| `name` | Yes | Display name shown in the menu |
| `github_repo` | Yes | Repository name under `github_org` |
| `source` | Yes | Category grouping — comma-separated values place the repo in multiple groups |
| `github_branch` | No | Specific branch to clone (default branch if omitted) |

Categories and entries are sorted alphabetically in the output. Example usage:

```bash
# List repos from the build pipeline's upstream registry
./repo-clone.sh --list git@github.com:Synx-Data-Labs/synxdb-build-pipeline.git upstream/repos.yml

# Clone all enterprise repos
./repo-clone.sh --groups enterprise git@github.com:Synx-Data-Labs/synxdb-build-pipeline.git upstream/repos.yml

# Dry-run for lightning group
./repo-clone.sh --dry-run --groups lightning git@github.com:Synx-Data-Labs/synxdb-build-pipeline.git upstream/repos.yml
```

## Options

| Flag | Description |
|------|-------------|
| `--clone-dir path` | Set the directory to clone repos into (default: current directory) |
| `--dry-run` | Preview what would be cloned without making changes |
| `--list` | List available repos from the catalog and exit |
| `--repos val,...` | Clone specific repos by number or display name (comma-separated) |
| `--groups name,...` | Clone all repos in the specified groups (comma-separated category names) |
| `--help` | Show usage information |
| `--version` | Show version number |

Numbers correspond to positions shown by `--list`. Flags can appear before or after positional arguments.

## Prerequisites

- **bash** 3.2+
- **git**
- An active **SSH agent** with keys that have access to the target repos

The script checks for loaded SSH keys at startup and exits with guidance if none are found.

## Behavior

- All repos are cloned into `<clone-dir>/<repo-name>`
- Defaults to the current working directory; override with `--clone-dir` or by entering a path at the confirmation prompt
- If a repo directory already exists, it is skipped with a warning
- Failed clones are reported but do not stop the remaining clones
- A summary of cloned/skipped/failed repos is printed at the end

## Remote Catalog Fetching

When the catalog source matches `git@*:*.git`, the script treats it as a remote Git repo. It fetches the catalog file using a shallow sparse clone over SSH:

```bash
./repo-clone.sh git@github.com:org/private-config.git catalogs/my-catalog.txt
```

This works with private repos as long as your SSH agent has access. The temporary clone is cleaned up automatically.

## CDN Caching

When running via `curl` from GitHub's raw URL, responses are served through a CDN that may cache files. If you've just pushed changes and need the latest version immediately, reference the commit SHA instead of the branch name:

```bash
curl -sL "https://raw.githubusercontent.com/edespino/repo-clone/<commit-sha>/repo-clone.sh" \
  | bash -s -- --help
```

The SHA points to an immutable object that is never stale. This is only needed during development right after pushing — under normal use the `main` branch URL works fine.

## Running Tests

```bash
./tests/test-repo-clone.sh
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
