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
3. You select which repos to clone (by number, comma-separated, or `all`)
4. Selected repos are cloned into `~/workspace/`

```
Fetching catalog...

  [infra]
  1) Build Pipeline
  2) Deploy Tool (branch: staging)

  [libs]
  3) Common Utils

Select repos to clone (e.g. 1 3, 1,3, or "all"): 1 3

Cloning Build Pipeline into ~/workspace/build-pipeline...  done
Cloning Common Utils into ~/workspace/common-utils...  done

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

## Options

| Flag | Description |
|------|-------------|
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

- All repos are cloned into `~/workspace/<repo-name>`
- `~/workspace/` is created automatically if it does not exist
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

When running via `curl` from GitHub's raw URL, responses are served through a CDN that caches files for up to 5 minutes. If you've just pushed changes and need the latest version immediately, append a unique query parameter to bypass the cache:

```bash
curl -sL "https://raw.githubusercontent.com/edespino/repo-clone/main/repo-clone.sh?$(date +%s)" \
  | bash -s -- --help
```

The `$(date +%s)` generates a unique Unix timestamp on each invocation. The server ignores the query parameter but the CDN treats it as an uncached URL. This is only needed right after pushing — under normal use the standard URL works fine.

## Running Tests

```bash
./tests/test-repo-clone.sh
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
