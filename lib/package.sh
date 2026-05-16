#!/usr/bin/env bash

# package.sh depends on get_version() which is defined in request.sh.
# Fail early with a clear message rather than a cryptic "command not found" later.
declare -f get_version >/dev/null 2>&1 || {
    echo "[error] package.sh requires request.sh to be sourced first" >&2
    exit 1
}

package_installed() {
    local releases="$1"

    [ -n "$releases" ] || return 1
    [ -d "$releases" ] || return 1

    find "$releases" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null | grep -q .
}

# Copy framework source files into a versioned release directory
package_build_repo_structure() {
    local src="$1"
    local dest="$2"
    local metadata="$dest/.metadata"

    if [ ! -d "$src" ]; then
        _print "Source directory not found: $src" error 1 1
        exit 1
    fi

    if [ -z "$dest" ]; then
        _print "Destination path is missing." error 1 1
        exit 1
    fi

    _print "Building release: $(basename "$dest")" info

    mkdir -p \
        "$dest/system" \
        "$dest/bootstrap" \
        "$metadata/system" \
        "$metadata/bootstrap"

    #
    # Capture excluded files BEFORE rsync
    #
    local boot_src="$src/src/Boot.php"
    local const_src="$src/install/Boot/constants.php"

    if [ -f "$boot_src" ]; then
        cp -f "$boot_src" "$metadata/system/Boot.php"
    fi

    if [ -f "$const_src" ]; then
        cp -f "$const_src" "$metadata/bootstrap/constants.php"
    fi

    #
    # Sync system (clean mirror)
    #
    rsync -a --delete \
        --exclude='Boot.php' \
        "$src/src/" "$dest/system/"

    #
    # Sync bootstrap (clean mirror)
    #
    rsync -a --delete \
        --exclude='constants.php' \
        "$src/install/Boot/" "$dest/bootstrap/"

    # Ensure runtime is writable if PHP will modify it later
    # chown -R www-data:www-data "$dest"
    # chmod -R 775 "$dest"
    # chmod -R 775 "$dest/system" "$dest/bootstrap" "$metadata/system" "$metadata/bootstrap"
}

# Print all installed releases, marking the currently active one
package_list_versions() {
    local dir="$1"
    local current_link="$2"
    local current=""

    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        _print "No releases installed yet." warn 1
        return 0
    fi

    # Resolve the active version whether current is a symlink or a plain directory
    if [ -L "$current_link" ] || [ -d "$current_link" ]; then
        current="$(basename "$(_readlink_resolved "$current_link" 2>/dev/null || true)")"
    fi

    _print "Installed releases:" info

    while IFS= read -r ver; do
        if [ "$ver" = "$current" ]; then
            _print "  $ver  ← active" success
        else
            _print "  $ver"
        fi
    done < <(ls -1 "$dir" | _sort_version)
}

# Remove contents of the repo directory, with two filter modes:
#   keep_git — deletes everything except the .git folder
#   full     — deletes everything including .git
package_clean_repo() {
    local path="${1:-}"
    local filter="${2:-}"
    local silent="${3:-0}"

    if [ -z "$path" ] || [ "$path" = "/" ] || [ "$path" = "." ]; then
        [ "$silent" -eq 0 ] && _print "Refusing cleanup — unsafe path: '$path'" error 1 1
        exit 1
    fi

    if [ ! -d "$path" ]; then
        [ "$silent" -eq 0 ] && _print "Repo directory not found: $path" error 1 1
        exit 1
    fi

    case "$filter" in
        keep_git)
            [ "$silent" -eq 0 ] && _print "Cleaning repo source files (keeping .git)..." warn 1
            find "$path" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
            ;;
        full)
            [ "$silent" -eq 0 ] && _print "Removing entire repo directory..." warn 1
            find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
            ;;
        *)
            _print "Unknown cleanup mode: '$filter'" warn 1 1
            exit 1
            ;;
    esac
}

# Update the current symlink to point to an already-installed release
package_switch_version() {
    local branch="$1"
    local releases="$2"
    local current="$3"
    local base="$4"
    local from_dir

    if [ -z "$branch" ]; then
        _print "No version specified for --switch." error 1 1
        _print "Usage: $0 --switch=<version>" plain
        exit 1
    fi

    from_dir="$releases/$branch"

    if [ ! -d "$from_dir" ]; then
        _print "Release not found: $branch" error 1 1
        _print "Run --list to see installed versions." info
        exit 1
    fi

    _print "Switching to version: $branch..." info
    _create_symlink "$from_dir" "$current" "$base"
    _print "Active version: $branch" success 1
    exit 0
}

# Clone from a remote URL, or rsync from a local source, into the repo dir
# package_clone_repo PACKAGES_DIR REPO_DIR PACKAGE_REPO_URL PULL_ORIGIN_SOURCE BRANCH
package_clone_repo() {
    local packages="$1"
    local location="$2"
    local target="$3"
    local source="$4"
    local version="${5:-}"

    #if [ -d "$location/.git" ]; then
    #    rm -rf "$location"
    # elif [ -n "$(find "$location" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    #    _print "Destination already exists and is not empty: $location" warn 0 1
    # fi

    mkdir -p "$(dirname "$location")" || return 1
    mkdir -p "$packages" || return 1

    if request_clone_repo "$target" "$location" "$version" "$source"; then
        return 0
    fi
    
    return 1
}

# Bring the repo to a clean, known state at the requested version
package_sync_repo() {
    local target="$1"
    local source="$2"
    local version="${3:-}"
    local runtime="${4:-root}"

    if [ "$source" = "local" ] && [ ! -d "$target/.git" ]; then
        return 1
    fi

    if request_sync_repo "$target" "$version" "$source" "$runtime"; then
        return 0
    fi

    return 1
}

# Infer the version when the caller did not specify one.
# Remote: latest git tag. Local: version field from composer.json.
package_detect_version() {
    local repo_dir="$1"

    get_version php "$repo_dir/src/Luminova.php" && return 0
    get_version git "$repo_dir" && return 0
    get_version composer "$repo_dir/composer.json" && return 0
    return 1
}

# Delete the repo directory so the next install starts with a clean clone
package_force_delete_repo() {
    local repo="${1:-${REPO_DIR}}"
    local base="${2:-${SCRIPT_DIR}}"

    _assert_path "$repo" "$base" || return 1

    if [[ -d "$repo" ]]; then
        _print "Force mode: removing existing repo at $repo..." warn 1

        if rm -rf -- "$repo"; then
            _clear_temp "$base"
        else
            _print "Failed to remove repo: $repo" error 1 1
            return 1
        fi
    fi

    return 0
}

# Remove all releases, the repo clone, and the current symlink
package_clear_modules() {
    local packages="${1:-${PACKAGES_DIR}}"
    local base="${2:-${SCRIPT_DIR}}"
    local force="$3"

    _assert_path "$packages" "$base" || exit 1
    _confirm_path "$packages" "$force" || exit 1

    _print "Performing full reset of $packages..." warn 1
    rm -rf "$packages/repo" "$packages/releases" "$packages/current"

    _clear_temp "$base"

    _print "Full reset complete." success 1
}

# Remove a single release version or the repo clone directory
package_remove_module() {
    local packages="${1:-${PACKAGES_DIR}}"
    local base="${2:-${SCRIPT_DIR}}"
    local target="$3"
    local force="$4"
    local releases="$packages/releases"
    local current="$packages/current"

    # Special target: remove only the repo clone directory
    if [ "$target" = "repo" ]; then
        local repo="$packages/repo"
        _assert_path "$repo" "$base" || exit 1

        _confirm_path "$repo" "$force" || exit 1

        rm -rf "$repo"
        _print "Repo directory removed." success 1
        return 0
    fi

    local version="$releases/$target"

    if [ ! -d "$version" ]; then
        _print "Release not found: $target" warn 1
        _print "Run --list to see installed versions." info
        return 1
    fi

    _assert_path "$version" "$base" || exit 1
    _confirm_path "$version" "$force" || exit 1

    _print "Removing release: $target..." warn
    rm -rf "$version"
    _print "Release $target removed." success 1

    # If the removed version was active, promote the next latest release
    local current_target
    current_target="$(_readlink_resolved "$current" 2>/dev/null || true)"

    if [ "$current_target" = "$version" ]; then
        _print "Removed version was active. Promoting latest remaining release..." warn

        local new_current
        new_current="$(ls -1 "$releases" 2>/dev/null | _sort_version | tail -n 1)"

        if [ -n "$new_current" ]; then
            ln -sfn "$releases/$new_current" "$current"
            _print "Active version is now: $new_current" success 1
        else
            _print "No releases remaining. Removing active symlink." warn 1
            rm -f "$current"

            _clear_temp "$base"
        fi
    fi
}

# Print the currently active release version and exit
package_current_release() {
    local packages="${1:-${PACKAGES_DIR}}"
    local link="$packages/current"

    if [ ! -L "$link" ] && [ ! -d "$link" ]; then
        _print "No active release found. Nothing has been deployed yet." info 1
        exit 0
    fi

    local resolved current
    resolved="$(_readlink_resolved "$link" 2>/dev/null || true)"

    if [ -z "$resolved" ]; then
        _print "Active symlink exists but does not resolve. It may be broken." warn 1
        exit 1
    fi

    current="$(basename "$resolved")"

    if [ -z "$current" ] || [ "$current" = "current" ]; then
        _print "Active symlink is broken or unresolvable." warn 1
        exit 1
    fi

    _print "Active Luminova release:" info
    _print "$current" success
    exit 0
}