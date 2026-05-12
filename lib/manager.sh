#!/usr/bin/env bash

# Install this script to the system PATH as 'luminova'
manager_install_self() {
    local runtime="${1:-root}"
    local script_path="$2"
    local base="${3:-${SCRIPT_DIR}}"
    local target="${4:-}"
    local target_dir conf_dir

    if [ "$runtime" = "root" ] && ! _is_root; then
        _print "Global install requires root. Try: sudo $0 self-install" error 1 1
        exit 1
    fi

    if [ -z "$target" ]; then
        target="$(config_script_target_bin "$runtime")" || {
            _print "Could not find PATH. Use --target=<path> to specify installation path"
            exit 1
        }

        target_dir="$(dirname "$target")"
    else
        _in_executable_path "$target" || {
            _print "Target $target is not in an executable or not accessible PATH"
            exit 1
        }

        target_dir="$target"
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        _print "Already installed at $target" warn 1
        _print "Use 'self-update' to upgrade or 'self-uninstall' to remove." info
        exit 1
    fi

    mkdir -p "$target_dir" || {
        _print "Failed to create install directory: $target_dir" error 1
        exit 1
    }

    # Prefer a symlink so updates to the source are reflected immediately
    if _can_symlink "$target_dir"; then
        ln -sfn "$script_path" "$target" || {
            _print "Failed to create symlink at $target" error 1
            exit 1
        }
        _print "Symlinked: $script_path → $target" info 1
    else
        cp "$script_path" "$target" || {
            _print "Failed to copy script to $target" error 1
            exit 1
        }
        _print "Copied to $target" info 1
    fi

    chmod +x "$target" 2>/dev/null || true
    # config_clear "" 1

    conf_dir="$(config_path)"

    if [ -n "$conf_dir" ]; then
        config_write "$conf_dir" \
            "LUMINOVA_VCI_BIN=$target" \
            "LUMINOVA_VCI_BASE=$base" \
            "LUMINOVA_VCI_CONF=$conf_dir"
    fi
    
    # Offer to add the install directory to PATH if luminova isn't found yet
    if ! _command_exists "luminova"; then
        if _confirm "Add '$target_dir' to PATH"; then
            config_add_global_path "$target_dir"
        else
            _print "Directory not in PATH: $target_dir" warn 1
            _print "Add this to your shell config:" info
            _print "  export PATH=\"$target_dir:\$PATH\"" plain
        fi
    fi

    _print "Install completed" success 1
    _print "Installed target: $target"
    exit 0
}

# Remove the installed 'luminova' binary and optionally purge data directories
manager_uninstall_self() {
    local runtime="${1:-root}"
    local purge="${2:-0}"
    local target="${3:-${BASE_SOURCE}}"
    local main_dir="${4:-${SCRIPT_DIR}}"
    local main_script="${5:-${BASE_SOURCE}}"
    local ok=1
    local link_path is_main_script

    if [ "$runtime" = "root" ] && ! _is_root; then
        _print "Root privileges required for global uninstall. Try: sudo luminova self-uninstall" error 1 1
        exit 1
    fi

    link_path=""
    is_main_script=0

    if [[ "$target" == "$main_dir/luminova.sh" || "$target" == "$main_dir/"* ]]; then
        is_main_script=1
        link_path="$(config_script_target_bin "$runtime")"

        if [ -n "$link_path" ] && [ -L "$link_path" ]; then

            _print "Target is part of main Luminova installation: $target" warn 1
            _print "A global symlink exists: $link_path" warn 1

            if _confirm "Uninstall the global link instead of full installation"; then
                target="$link_path"
            fi
        fi
    fi

    # Guard: refuse to uninstall if target is the main script or inside main dir
    case "$target" in
        "$main_dir/luminova.sh" | "$main_dir"/*)
            _print "Cannot uninstall: script was never installed as a global command" error 1 1
            exit 1
            ;;
    esac

    if [[ -z "$target" || ( ! -e "$target" && ! -L "$target" ) ]]; then
        target="$(config_script_target_bin "$runtime")" || exit 1
    fi

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        _print "Not installed at $target" warn 1
        exit 1
    fi

    if [ -e "$target" ] && [ ! -L "$target" ]; then
        _print "Uninstalling main luminova VCI at $target." error 1 
        _print "This will delete everything including releases." error 1

        if ! _confirm "Continue"; then
            _print "Abort uninstallation" info 1 1
            exit 1
        fi
    fi

    _print "Removing $target..."
    rm -f "$target" || {
        _print "Failed to remove $target" error 1 1
        exit 1
    }

    if [ "$is_main_script" -eq 1 ] && [ "$purge" -eq 1 ]; then
        config_clear || ok=0
    fi

    if [ "$ok" -eq 1 ]; then
        _print "Uninstall completed." success 1
        exit 0
    fi

    _print "Uninstall completed with errors." warn 1
    exit 1
}

manager_copy_updates() {
    local isolation="$1"
    local destination="$2"
    local runtime="${3:-${RUNTIME_USER: -root}}"

    local src dst

    src="$(cd "$isolation" && pwd -P)"
    dst="$(cd "$destination" && pwd -P)"

    _print "Updating:"
    _print "  from: $src"
    _print "  to:   $dst"

    # prevent self-copy
    if [ "$src" = "$dst" ]; then
        _print "Source and destination are identical. Aborting." error 1 1
        return 1
    fi

    # ensure source exists
    [ -d "$src" ] || {
        _print "Invalid source directory: $src" error 1 1
        return 1
    }

    local opts=()
    [ "$runtime" = "root" ] && opts+=(--no-owner --no-group)

    # sync contents (not folder itself)
    rsync -a --delete \
        --copy-links \
        --exclude='.git' \
        "${opts[@]}" "$src/" "$dst/" || {
        _print "Failed to sync update files." error 1 1
        return 1
    }

    return 0
}

manager_detect_version() {
    local dir="$1"

    get_version bash "$dir/luminova.sh" && return 0
    get_version git "$dir" && return 0
    get_version composer "$dir/composer.json" && return 0
    return 1
}

# Replace the installed script with the latest version downloaded from GitHub.
#
# Steps:
#   1. Resolve where luminova is installed.
#   2. Download to a temp file (curl preferred, wget as fallback).
#   3. Validate syntax with bash -n.
#   4. Compare VERSION strings; skip if already current.
#   5. Set +x and atomically rename over the installed copy.
#  manager_update_self "$RUNTIME_USER" "$SCRIPT_DIR" "$SELF_REPO_URL" "$BRANCH"
manager_update_self() {
    local runtime="${1:-root}"
    local destination="${2:-${SCRIPT_DIR}}"
    local target="$3"
    local branch="${4:-main}"
    local cur_version="${5:-${VERSION}}" 

    local isolation handler new_version new_script
    
    if [ "$runtime" = "root" ] && ! _is_root; then
        _print "Root required for global update. Use: sudo luminova self-update" error 1 1
        exit 1
    fi

    isolation="$(_make_temp dir "" "luminova.vci.update.isolation")" || {
        _print "Failed to prepare update workspace: $isolation" error 1 1
        exit 1
    }

    tmp="$(_make_temp file "$destination/tmp" "luminova.vci.update")" || {
        rm -f "$isolation"
        _print "Failed to create a temporary download file." error 1 1
        exit 1
    }

    _print "Fetching update from:" info 1
    _print "  $target ($branch)" plain

    if ! request_clone_repo "$target" "$isolation" "$branch" "remote" "$tmp"; then
        rm -f "$tmp" "$isolation"
        _print "Failed to fetch update source." error 1 1
        exit 1
    fi

    new_version="$(manager_detect_version "$isolation")"
    new_script="$isolation/luminova.sh"

    if [ -n "$cur_version" ] && [ -n "$new_version" ] && [ "$cur_version" = "$new_version" ]; then
        _print "Already up to date ($cur_version)." info 1
        rm -f "$tmp" "$isolation"
        exit 0
    fi

    if [ ! -f "$new_script" ]; then
        _print "Update failed: missing luminova.sh in source." error 1 1
        rm -f "$tmp" "$isolation"
        return 1
    fi

    if ! bash -n "$new_script" 2>/dev/null; then
        _print "Update aborted: invalid script syntax." error 1 1
        rm -f "$tmp" "$isolation"
        return 1
    fi

    chmod +x "$new_script" 2>/dev/null || true

    if ! manager_copy_updates "$isolation" "$destination" "$runtime"; then
        _print "Failed to apply update." error 1 1
        rm -f "$tmp" "$isolation"
        return 1
    fi

    if [ -n "$cur_version" ] && [ -n "$new_version" ]; then
        _print "Updated: $cur_version → $new_version" success 1
    elif [ -n "$new_version" ]; then
        _print "Updated to version $new_version" success 1
    else
        _print "Update completed." success 1
    fi

    rm -f "$tmp" "$isolation"
    exit 0
}