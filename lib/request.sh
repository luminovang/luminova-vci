#!/usr/bin/env bash
HAS_ZIP=0
expected_checksum="${CHECKSUM:-}"

if command -v unzip >/dev/null 2>&1; then
    HAS_ZIP=1
fi

request_detect_handler() {
    if command -v git >/dev/null 2>&1; then
        echo git
    elif command -v curl >/dev/null 2>&1; then
        echo curl
    elif command -v wget >/dev/null 2>&1; then
        echo wget
    else
        _print "Missing required tools: git, curl, or wget." error 1 1
        return 1
    fi
}

strip_git_suffix() {
    local url="$1"
    printf "%s\n" "${url%.git}"
}

build_archive_url() {
    local repo="$1"
    local branch="${2:-}"
    local type    # "tag" | "branch"

    if -z "$branch"; then
        type="branch"
    elif _is_version "$branch"; then
        type="tag"
    else
        type="branch"
    fi

    repo="$(strip_git_suffix "$repo")"

    if [ "$type" = "branch" ]; then
        printf "%s/archive/refs/heads/%s.zip\n" "$repo" "${branch:-main}"
    elif [ -n "$branch" ]; then
        printf "%s/archive/refs/tags/%s.zip\n" "$repo" "$branch"
    else
        printf "%s/archive/refs/heads/main.zip\n" "$repo"
    fi
}


request_download_file() {
    local url="$1"
    local output="$2"
    local handler="$3"

    case "$handler" in
        curl)
            curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$output"
            ;;
        wget)
            wget -qO "$output" "$url"
            ;;
        *)
            return 1
            ;;
    esac
}

request_clone_repo() {
    local target="$1"
    local destination="$2"
    local branch="${3:-}"
    local source="${4:-remote}"
    local tmp="${5:-}"
    local handler download_url version ok=0

    # --- local copy ---
    if [ "$source" = "local" ]; then
        _print "Copying from "$source" source: $target"
        _print "Copying into target $destination"
        rsync -a --delete \
            --exclude='.git' \
            --exclude='vendor/' \
            --exclude='libraries/' \
            "$target/" "$destination/"
        return 0
    fi

    handler="$(request_detect_handler)" || return 1

    _print "Cloning from "$source" source: $target"

    # --- git path ---
    if [ "$handler" = "git" ]; then
        if [ -n "$branch" ]; then
            version="$branch"
        else
            version="main"
        fi

        if output=$(git clone --depth 1 --branch "$version" "$target" "$destination" 2>&1); then
            _print "Clone successful" success
            return 0
        else
            _print "Clone failed" error 0 1

            if [ -d "$destination" ] && [ "$(ls -A "$destination")" ]; then
                _print "Destination '$destination' already exists and is not empty" warn 0
                return 1
            fi

            _print "$output" plain
            return 1
        fi
    fi

    if [ "$HAS_ZIP" -eq 0 ]; then
        _print "unzip not available. Cannot extract archive." error 1 1
        return 1
    fi

    # --- archive fallback ---
    if [ -z "$tmp" ]; then
        tmp="$(_make_temp file "$destination/tmp" "luminova.vci.clones")" || {
            _print "Failed to create a temporary download file." error 1 1
            return 1
        }
    fi

    download_url="$(build_archive_url "$target" "$branch")"

    request_download_file "$download_url" "$tmp" "$handler" || {
        rm -f "$tmp"
        _print "Download failed: $target" error 1 1
        return 1
    }

    [ -s "$tmp" ] || {
        rm -f "$tmp"
        _print "Downloaded file is empty" error 1 1
        return 1
    }

    # --- checksum check here ---
    # local expected="$(curl -fsSL "$target.sha256" | awk '{print $1}')"
    # https://raw.githubusercontent.com/luminovang/vci/refs/heads/main/main.zip.sha256
    # if [ -n "$expected" ]; then
    #    verify_checksum "$tmp" "$expected" || {
    #        rm -f "$tmp"
    #        _print "Aborting: file integrity check failed" error 1 1
    #        return 1
    #    }
    # fi

    mkdir -p "$destination" || return 1
    unzip -q "$tmp" -d "$destination" || {
        rm -f "$tmp"
        _print "Failed to extract archive" error 1 1
        return 1
    }

    rm -f "$tmp"
    printf "%s\n" "$destination"
}

# Infer the version when the caller did not specify one.
# Remote: latest git tag. Local: version field from composer.json.
get_version() {
    local type="${1:-php}"
    local target="$2"
    local version handler

    case "$type" in
        php)
            version="$(
                awk '
                    /public[[:space:]]+const[[:space:]]+VERSION[[:space:]]*=/ {
                        # single-quoted string literal
                        if (match($0, /'"'"'([^'"'"']+)'"'"'/, a)) { print a[1]; exit }
                        # double-quoted string literal
                        if (match($0, /"([^"]+)"/, a))             { print a[1]; exit }
                    }
                ' "$target" 2>/dev/null
            )"
            ;;
        bash)
            version="$(
                awk -F'"' '/^readonly VERSION="/ { print $2; exit }' \
                "$target" 2>/dev/null
            )"
            ;;
        composer)
            version="$(
                awk -F'"' '/"version"[[:space:]]*:/ { print $4; exit }' \
                "$target" 2>/dev/null
            )"
            ;;
        git)
            handler="$(request_detect_handler 2>/dev/null)" || return 1
            [ "$handler" = "git" ] || return 1

            git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
            git -C "$target" fetch --tags --quiet >/dev/null 2>&1 || true

            version="$(git -C "$target" describe --tags --abbrev=0 2>/dev/null)"
            ;;
        *)
            return 1
            ;;
    esac

    [ -n "$version" ] || return 1

    printf "%s\n" "$version"
    return 0
}


# Compute a content fingerprint used to detect unchanged sources.
# Remote: git commit SHA (fast, exact). Local: hash of all non-.git file hashes.
request_hash_repo() {
    local target="$1"
    local source="${2:-local}"
    local algo="${3:-}"

    if [ "$source" = "local" ]; then
        # Run in a sub-shell with pipefail so an error in find or _hash_run
        # propagates rather than silently producing a wrong or empty fingerprint
        (
            set -o pipefail
            find "$target" -type f -not -path '*/.git/*' -print0 \
                | sort -z \
                | while IFS= read -r -d '' file; do
                    _hash "$file" "$algo" file
                done \
                | _hash_run "$algo" - \
                | awk '{print $1}'
        ) || return 1
    else
        handler="$(request_detect_handler)" || return 1

        if [ "$handler" = "git" ]; then
            git -C "$target" rev-parse HEAD 2>/dev/null
            return 0
        fi

        return 1
    fi
}

# package_sync_repo "$REPO_DIR" "$PULL_ORIGIN_SOURCE" "$TARGET_VERSION" "$RUNTIME_USER"
# request_sync_repo "$target" "$version" "$source" "$runtime"
request_sync_repo() {
    local target="$1"
    local branch="${2:-}"
    local source="${3:-remote}"
    local runtime="${4:-root}"
    local default_branch current_tag handler tmp ok=1

    handler="$(request_detect_handler)" || return 1

    if [ "$handler" = "git" ]; then
        if [ "$source" = "local" ]; then
            if [ -d "$target/.git" ]; then
                _print "Local git source: resetting working tree..." info
                git -C "$target" reset --hard

                # Remove untracked files (skip in user mode to avoid permission errors)
                if [ "$runtime" = "root" ]; then
                    git -C "$target" clean -fdx 2>/dev/null || true
                fi

                return $?
            fi

            return 1
        fi

        if [ -n "$branch" ]; then
            current_tag="$(git -C "$target" describe --tags --exact-match HEAD 2>/dev/null || true)"

            if [ "$current_tag" = "$branch" ]; then
                _print "Repo already at $branch; ensuring clean working tree..." info
                git -C "$target" reset --hard HEAD
            else
                _print "Fetching tag: $branch" info

                # Try a targeted fetch first; fall back to fetching all tags
                git -C "$target" fetch --depth 1 origin \
                    "refs/tags/${branch}:refs/tags/${branch}" --quiet 2>/dev/null \
                    || git -C "$target" fetch --tags --quiet
                git -C "$target" checkout --quiet "$branch"
            fi
        else
            _print "Fetching latest changes from remote..." info
            git -C "$target" fetch origin --prune --quiet

            default_branch="$(
                git -C "$target" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
                    | sed 's@^refs/remotes/origin/@@'
            )"
            default_branch="${default_branch:-main}"

            git -C "$target" reset --hard "origin/$default_branch"
        fi

        # Remove untracked files (skip in user mode to avoid permission errors)
        if [ "$runtime" = "root" ]; then
            git -C "$target" clean -fdx 2>/dev/null || true
        fi

        return 0
    fi

    request_sync_non_git_repo "$target" "$handler" || return 1
}

request_sync_non_git_repo() {
    local target="$1"
    local handler="$2"

    if [ "$HAS_ZIP" -eq 0 ]; then
        _print "unzip not available" error 1 1
        return 1
    fi

    # --- non-git fallback ---
    _print "Syncing via archive (no git available)..." info

    tmp="$(_make_temp dir "" "luminova_sync")" || return 1

    archive="$tmp/archive.zip"

    download_file "$target" "$archive" "$handler" || {
        rm -rf "$tmp"
        return 1
    }

    [ -s "$archive" ] || {
        _print "Downloaded archive is empty" error 1 1
        rm -rf "$tmp"
        return 1
    }

    unzip -q "$archive" -d "$tmp" || {
        _print "Failed to extract archive" error 1 1
        rm -rf "$tmp"
        return 1
    }

    new_root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

    [ -d "$new_root" ] || {
        _print "Invalid archive structure" error 1 1
        rm -rf "$tmp"
        return 1
    }

    _print "Changes:" info

    # if [ "$runtime" = "root" ]; then
    #    opts="--no-owner --no-group"
    # else
    #    opts=""
    # fi

    rsync -a --delete --dry-run \
        --exclude='.git' \
        "$new_root/" "$target/" \
        | sed 's/^/  /'

    rsync -a --delete \
        --exclude='.git' \
        "$new_root/" "$target/" || {
        _print "Sync failed" error 1 1
        rm -rf "$tmp"
        return 1
    }

    rm -rf "$tmp"
    return 0
}

verify_checksum() {
    local file="$1"
    local expected="$2"
    local actual

    actual="$(_hash_sha256 "$file")" || {
        _print "No SHA256 tool available" error 1 1
        return 1
    }

    if [ "$actual" != "$expected" ]; then
        _print "Checksum mismatch!" error 1 1
        _print "Expected: $expected" error
        _print "Actual:   $actual" error
        return 1
    fi

    return 0
}