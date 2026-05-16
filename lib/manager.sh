#!/usr/bin/env bash
manager_detect_version() {
    local dir="$1"

    get_version bash "$dir/luminova.sh" && return 0
    get_version git "$dir" && return 0
    get_version composer "$dir/composer.json" && return 0
    return 1
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

# Install this script to the system PATH as 'luminova'
# Install luminova into a system executable PATH.
self_install_script() {
    local runtime="${1:-root}"
    local script_path="$2"
    local default_target="${3:-}"
    local install_dir=""
    local target=""
    local bin_name="luminova"
    local conf_file=""

    if [ -z "$default_target" ]; then
        default_target="$(config_script_target_bin "$runtime")" || {
            _print "Unable to detect installation path." error 1
            default_target=""
        }

        if [ -n "$default_target" ] && _confirm "Install luminova to '$default_target'" "Y"; then
            install_dir="$(dirname "$default_target")"
        fi
    else
        install_dir="$default_target"
    fi

    if [ -z "$install_dir" ]; then
        install_dir="$(_prompt 'Enter installation directory or full path')" || true
    fi

    if [ -z "$install_dir" ]; then
        _print "Installation path cannot be empty." error 1
        exit 1
    fi

    install_dir="${install_dir%/}"

    # Normalize: accept both directory and full binary path
    if [ -f "$install_dir" ] || [ -L "$install_dir" ]; then
        target="$install_dir"
        install_dir="$(dirname "$install_dir")"
    elif [ "${install_dir##*/}" = "$bin_name" ]; then
        target="$install_dir"
        install_dir="$(dirname "$install_dir")"
    else
        target="$install_dir/$bin_name"
    fi

    if ! _in_executable_path "$install_dir"; then
        _print "Invalid or inaccessible installation directory:" error 1
        _print "  $install_dir" plain
        exit 1
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        _print "Already installed:" warn 1
        _print "  $target" plain
        _print "Use '--self=uninstall' to remove luminova binary." info
        exit 1
    fi

    mkdir -p "$install_dir" || {
        _print "Failed to create directory:" error 1
        _print "  $install_dir" plain
        exit 1
    }

    if _can_symlink "$install_dir"; then
        ln -sfn "$script_path" "$target" || {
            _print "Failed to create symlink:" error 1
            _print "  $target" plain
            exit 1
        }
        _print "Symlink created:" success 1
        _print "  $target → $script_path" plain
    else
        cp "$script_path" "$target" || {
            _print "Failed to copy file:" error 1
            _print "  $target" plain
            exit 1
        }
        _print "Installed binary:" success 1
        _print "  $target" plain
    fi

    chmod +x "$target" 2>/dev/null || true

    conf_file="$(config_get_file)"

    if [ -n "$conf_file" ]; then
        _print "  Writing configurations to '$conf_file'" plain
        config_write "$conf_file" \
            "LUMINOVA_VCI_BIN=$target" \
            "LUMINOVA_VCI_CONF=$conf_file"
    fi

    if ! _command_exists "luminova"; then
        if _confirm "Add '$install_dir' to PATH" "Y"; then
            config_add_global_path "$install_dir"
        else
            _print "PATH not updated:" warn 1
            _print "  $install_dir not in PATH" plain
            _print "Add manually:" info
            _print "  export PATH=\"$install_dir:\$PATH\"" plain
        fi
    fi

    _print "Installation completed." success 1
    _print "Binary: $target" info

    exit 0
}

# Remove the installed 'luminova' binary and optionally purge data directories
self_uninstall_script() {
    local runtime="${1:-root}"
    local purge="${2:-0}"
    local main_dir="${3:-$SCRIPT_DIR}"
    local main_script="${4:-$SELF}"
    local ok=1
    local target=""
    local is_local=0
    local conf_file mode="file"

    # Resolve installation target
    target="$(config_get "LUMINOVA_VCI_BIN")" || target=""

    if [ -z "$target" ]; then
        target="$(config_script_target_bin "$runtime")" || target=""
    fi

    if [ -z "$target" ]; then
        if _command_exists "luminova"; then
            target="$(command -v luminova 2>/dev/null)" || target=""
        else
            _print "Luminova is not installed." warn 1
            exit 1
        fi
    fi

    if [ -z "$target" ]; then
        _print "Unable to resolve installed binary path." error 1
        exit 1
    fi

    # Validate existence
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        _print "Luminova not found at: $target" warn 1
        exit 1
    fi

    # Detect local install
    case "$target" in
        "$main_dir/"*) is_local=1 ;;
    esac

    # Safety confirmation
    if [[ "$is_local" -eq 1 || ( -e "$target" && ! -L "$target" ) ]]; then
        _print "Removing full Luminova installation:" warn 1
        _print "  $target" plain

        if ! _confirm "Continue" "N"; then
            _print "Uninstall aborted." info 1
            exit 1
        fi
    fi

    # Remove binary
    if [ "$is_local" -eq 1 ]; then
        _print "Removing full Luminova installation directory:" warn 1
        _print "  $main_dir" plain

        rm -rf "$main_dir" || {
            _print "Failed to remove directory: $main_dir" error 1
            exit 1
        }

        purge=1
        mode="dir"
    else
        _print "Removing binary:" warn 1
        _print "  $target" plain

        rm -f "$target" || {
            _print "Failed to remove binary: $target" error 1
            exit 1
        }
    fi

    # Config cleanup (ONLY global uninstall)
    if [ "$purge" -eq 1 ]; then
        config_clear "" "$mode" || ok=0
    fi
    
    if [ "$is_local" -eq 0 ]; then
        conf_file="$(config_get_file)"

        if [ -n "$conf_file" ]; then
            config_write "$conf_file" "LUMINOVA_VCI_BIN=$main_script"
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        _print "Uninstall completed successfully." success 1
        exit 0
    fi

    _print "Uninstall completed with warnings." warn 1
    exit 1
}

# Replace the installed script with the latest version downloaded from GitHub.
#
# Steps:
#   1. Resolve where luminova is installed.
#   2. Download to a temp file (curl preferred, wget as fallback).
#   3. Validate syntax with bash -n.
#   4. Compare VERSION strings; skip if already current.
#   5. Set +x and atomically rename over the installed copy.
#  self_update_script "$RUNTIME_USER" "$SCRIPT_DIR" "$SELF_REPO_URL" "$TARGET_VERSION"
self_update_script() {
    local runtime="${1:-root}"
    local destination="${2:-${SCRIPT_DIR}}"
    local target="$3"
    local branch="${4:-main}"
    local cur_version="${5:-${VERSION}}" 

    local isolation handler new_version new_script

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