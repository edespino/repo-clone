#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
CLONE_DIR="$HOME/workspace"
DRY_RUN=false
LIST_ONLY=false
FILTER_REPOS=""

# Catalog data arrays (parallel arrays — index N in each corresponds to the same entry)
REPO_NAMES=()
REPO_URLS=()
REPO_BRANCHES=()
REPO_CATEGORIES=()

parse_catalog() {
    local content="$1"
    local current_category="uncategorized"

    while IFS= read -r line; do
        # Skip blank lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Category header
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_category="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse entry: name|url or name|url|branch
        IFS='|' read -r name url branch <<< "$line"
        # Trim leading/trailing whitespace
        name="${name#"${name%%[![:space:]]*}"}" ; name="${name%"${name##*[![:space:]]}"}"
        url="${url#"${url%%[![:space:]]*}"}" ; url="${url%"${url##*[![:space:]]}"}"
        branch="${branch:-}"
        branch="${branch#"${branch%%[![:space:]]*}"}" ; branch="${branch%"${branch##*[![:space:]]}"}"

        if [[ -z "$name" || -z "$url" ]]; then
            continue  # skip malformed lines
        fi

        REPO_NAMES+=("$name")
        REPO_URLS+=("$url")
        REPO_BRANCHES+=("$branch")
        REPO_CATEGORIES+=("$current_category")
    done <<< "$content"
}

fetch_remote_catalog() {
    local tmpdir
    tmpdir=$(mktemp -d)

    if ! git clone --depth 1 --filter=blob:none --sparse \
        "$CATALOG_SOURCE" "$tmpdir/repo" 2>/dev/null; then
        rm -rf "$tmpdir"
        echo "Error: Failed to clone catalog repo: $CATALOG_SOURCE" >&2
        exit 1
    fi

    (cd "$tmpdir/repo" && git sparse-checkout set "$CATALOG_PATH" 2>/dev/null)

    local catalog_file="$tmpdir/repo/$CATALOG_PATH"
    if [[ ! -f "$catalog_file" ]]; then
        rm -rf "$tmpdir"
        echo "Error: Catalog file not found in repo: $CATALOG_PATH" >&2
        exit 1
    fi

    cat "$catalog_file"
    rm -rf "$tmpdir"
}

fetch_catalog() {
    if [[ "$CATALOG_MODE" == "local" ]]; then
        if [[ ! -f "$CATALOG_PATH" ]]; then
            echo "Error: Catalog file not found: $CATALOG_PATH" >&2
            exit 1
        fi
        cat "$CATALOG_PATH"
    else
        fetch_remote_catalog
    fi
}

display_menu() {
    local last_category=""
    for i in "${!REPO_NAMES[@]}"; do
        local cat="${REPO_CATEGORIES[$i]}"
        if [[ "$cat" != "$last_category" ]]; then
            echo ""
            echo "  [$cat]"
            last_category="$cat"
        fi
        local entry="  $((i + 1))) ${REPO_NAMES[$i]}"
        if [[ -n "${REPO_BRANCHES[$i]}" ]]; then
            entry+=" (branch: ${REPO_BRANCHES[$i]})"
        fi
        echo "$entry"
    done
    echo ""
}

read_selection() {
    local max=$1
    local selection

    while true; do
        printf 'Select repos to clone (e.g. 1 3 4, 1,3,4, or "all"): '
        read -r selection < /dev/tty

        # Handle "all"
        if [[ "$selection" == "all" ]]; then
            SELECTED=()
            for ((i = 0; i < max; i++)); do
                SELECTED+=("$i")
            done
            return
        fi

        # Normalize: replace commas with spaces
        selection="${selection//,/ }"

        # Validate each token
        SELECTED=()
        local valid=true
        for token in $selection; do
            if ! [[ "$token" =~ ^[0-9]+$ ]] || [[ "$token" -lt 1 || "$token" -gt "$max" ]]; then
                echo "Invalid selection: $token (must be 1-$max)" >&2
                valid=false
                break
            fi
            SELECTED+=("$((token - 1))")
        done

        if [[ "$valid" == true && ${#SELECTED[@]} -gt 0 ]]; then
            return
        fi
        echo "Please enter valid numbers between 1 and $max." >&2
    done
}

SELECTED=()

resolve_repo_filter() {
    local filter="$1"
    local max="${#REPO_NAMES[@]}"
    local found_any=false

    # Split comma-separated tokens into an array
    IFS=',' read -ra filter_tokens <<< "$filter"

    for token in "${filter_tokens[@]}"; do
        # Trim whitespace
        token="${token#"${token%%[![:space:]]*}"}"
        token="${token%"${token##*[![:space:]]}"}"
        [[ -z "$token" ]] && continue

        # Check if token is a number (1-based index)
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            if [[ "$token" -lt 1 || "$token" -gt "$max" ]]; then
                echo "Error: Invalid repo number: $token (must be 1-$max)" >&2
                echo "Use --list to see available repos." >&2
                exit 1
            fi
            SELECTED+=("$((token - 1))")
            found_any=true
            continue
        fi

        # Otherwise match by display name
        local matched=false
        for i in "${!REPO_NAMES[@]}"; do
            if [[ "${REPO_NAMES[$i]}" == "$token" ]]; then
                SELECTED+=("$i")
                matched=true
                found_any=true
                break
            fi
        done

        if [[ "$matched" == false ]]; then
            echo "Error: No repo found matching name: $token" >&2
            echo "Use --list to see available repo names." >&2
            exit 1
        fi
    done

    if [[ "$found_any" == false ]]; then
        echo "Error: No repo names provided to --repos." >&2
        exit 1
    fi
}

derive_repo_dir() {
    local url="$1"
    # git@github.com:org/repo-name.git -> repo-name
    local name="${url##*/}"
    name="${name%.git}"
    echo "$name"
}

dry_run_report() {
    echo "[dry-run] No filesystem changes will be made."
    echo ""
    for idx in "${SELECTED[@]}"; do
        local name="${REPO_NAMES[$idx]}"
        local url="${REPO_URLS[$idx]}"
        local branch="${REPO_BRANCHES[$idx]}"
        local dir_name
        dir_name=$(derive_repo_dir "$url")
        local target="$CLONE_DIR/$dir_name"

        local display="$name"
        if [[ -n "$branch" ]]; then
            display+=" (branch: $branch)"
        fi

        if [[ -d "$target" ]]; then
            echo "[dry-run] Would skip $display: already exists at $target"
        else
            echo "[dry-run] Would clone $display into $target"
        fi
    done
}

clone_repos() {
    local cloned=0 skipped=0 failed=0

    for idx in "${SELECTED[@]}"; do
        local name="${REPO_NAMES[$idx]}"
        local url="${REPO_URLS[$idx]}"
        local branch="${REPO_BRANCHES[$idx]}"
        local dir_name
        dir_name=$(derive_repo_dir "$url")
        local target="$CLONE_DIR/$dir_name"

        local display="$name"
        if [[ -n "$branch" ]]; then
            display+=" (branch: $branch)"
        fi

        # Check if already exists
        if [[ -d "$target" ]]; then
            echo "Skipping $display: already exists at $target"
            skipped=$((skipped + 1))
            continue
        fi

        # Build clone command
        local clone_args=("clone")
        if [[ -n "$branch" ]]; then
            clone_args+=("-b" "$branch")
        fi
        clone_args+=("$url" "$target")

        printf "Cloning %s into %s... " "$display" "$target"
        if git "${clone_args[@]}" 2>/dev/null; then
            echo "done"
            cloned=$((cloned + 1))
        else
            echo "FAILED"
            failed=$((failed + 1))
        fi
    done

    echo ""
    echo "Summary:"
    echo "  Cloned: $cloned"
    echo "  Skipped: $skipped"
    echo "  Failed: $failed"
}

check_ssh_agent() {
    if ! ssh-add -l &>/dev/null; then
        echo "Error: No SSH identities found. Start your SSH agent and add keys:" >&2
        echo "  eval \"\$(ssh-agent -s)\"" >&2
        echo "  ssh-add ~/.ssh/id_ed25519" >&2
        exit 1
    fi
}

usage() {
    cat <<'EOF'
Usage: repo-clone.sh [options] <catalog-source>

Catalog source can be:
  Local file:   repo-clone.sh /path/to/catalog.txt
  Remote repo:  repo-clone.sh git@github.com:org/repo.git path/to/catalog.txt

Options:
  --dry-run          Preview what would be cloned without making changes
  --list             List available repos from the catalog and exit
  --repos val,...    Clone only the specified repos (comma-separated numbers or names)
  --help             Show this help message
  --version          Show version

Examples:
  repo-clone.sh --list catalog.txt
  repo-clone.sh --repos "Build Pipeline,Common Utils" catalog.txt
  repo-clone.sh --repos "1,3" catalog.txt
  repo-clone.sh --dry-run --repos "Build Pipeline" catalog.txt
EOF
    exit "${1:-0}"
}

# Parse --flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --list) LIST_ONLY=true; shift ;;
        --repos)
            if [[ $# -lt 2 ]]; then
                echo "Error: --repos requires a comma-separated list of repo names." >&2
                exit 1
            fi
            FILTER_REPOS="$2"; shift 2 ;;
        --help) usage 0 ;;
        --version) echo "repo-clone $VERSION"; exit 0 ;;
        --test-parse)
            # Hidden flag: parse catalog and print structured output for testing
            shift
            CATALOG_MODE="local"
            CATALOG_PATH="$1"
            shift
            CATALOG_CONTENT=$(fetch_catalog)
            parse_catalog "$CATALOG_CONTENT"
            if [[ ${#REPO_NAMES[@]} -eq 0 ]]; then
                echo "Error: No repos found in catalog." >&2
                exit 1
            fi
            for i in "${!REPO_NAMES[@]}"; do
                echo "${REPO_CATEGORIES[$i]}|${REPO_NAMES[$i]}|${REPO_URLS[$i]}|${REPO_BRANCHES[$i]}"
            done
            exit 0
            ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) break ;;
    esac
done

# Determine catalog source
if [[ $# -eq 0 ]]; then
    echo "Error: No catalog source provided." >&2
    usage 1
fi

CATALOG_SOURCE="$1"
CATALOG_PATH="${2:-}"

# Detect remote vs local
if [[ "$CATALOG_SOURCE" == git@*:*.git ]]; then
    if [[ -z "$CATALOG_PATH" ]]; then
        echo "Error: Remote catalog requires a file path argument." >&2
        echo "Usage: repo-clone.sh git@github.com:org/repo.git path/to/catalog.txt" >&2
        exit 1
    fi
    CATALOG_MODE="remote"
else
    CATALOG_MODE="local"
    # For local mode, CATALOG_PATH is unused — source IS the path
    CATALOG_PATH="$CATALOG_SOURCE"
fi

check_ssh_agent

echo "Fetching catalog..."
CATALOG_CONTENT=$(fetch_catalog)

if [[ -z "$CATALOG_CONTENT" ]]; then
    echo "Error: Catalog is empty." >&2
    exit 1
fi

parse_catalog "$CATALOG_CONTENT"

if [[ ${#REPO_NAMES[@]} -eq 0 ]]; then
    echo "Error: No repos found in catalog." >&2
    exit 1
fi

if [[ "$LIST_ONLY" == true ]]; then
    display_menu
    exit 0
fi

if [[ -n "$FILTER_REPOS" ]]; then
    resolve_repo_filter "$FILTER_REPOS"
else
    display_menu
    read_selection "${#REPO_NAMES[@]}"
fi

echo ""
if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$CLONE_DIR"
    clone_repos
else
    dry_run_report
fi
