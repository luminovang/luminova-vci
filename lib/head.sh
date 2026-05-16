#!/usr/bin/env bash

# Remove an incomplete release directory on unexpected exit
_cleanup_trap() {
    local code=$?

    if [ "$code" -ne 0 ] \
        && [ -n "$_RELEASE_PATH" ] \
        && [ -d "$_RELEASE_PATH" ] \
        && [ -n "$_HASH_FILE" ] \
        && [ ! -f "$_HASH_FILE" ]; then
        _print "Cleaning up incomplete release: $_RELEASE_PATH" warn 1
        rm -rf "$_RELEASE_PATH"
    fi
}

_setup() {
    local config_file="${1:-$CONFIG_FILE}"
    local self_bin="${2:-$SELF}"
    local packages="${3:-$PACKAGES_DIR}"
    local is_update_pkg_path="${4:-0}"

    local bin_file="$self_bin"
    local old_packages=""
    local move_data=0
    local self_dir="$(dirname "$(realpath "$self_bin")")"

    if [ "$packages" = "$self_dir" ]; then
        packages="$packages/packages"
    fi

    # -----------------------------
    # Validate config file
    # -----------------------------
    if [ -z "$config_file" ]; then
        return 1
    fi

    # -----------------------------
    # Resolve binary path
    # -----------------------------
    if config_has "LUMINOVA_VCI_BIN"; then
        bin_file="$(config_get "LUMINOVA_VCI_BIN")"
    fi

    # -----------------------------
    # Resolve package directory
    # -----------------------------
    if config_has "LUMINOVA_PACKAGE_DIR"; then
        old_packages="$(config_get "LUMINOVA_PACKAGE_DIR")"

        if [ -n "$old_packages" ] && [ "$old_packages" != "$packages" ]; then

            if [ "$is_update_pkg_path" -eq 0 ]; then
                _print "Mixed target package directory" warn
            else
                _print "Changing luminova package target directory" info
            fi
            
            _print "Previous package directory: $old_packages" plain
            _print "New package directory:      $packages" plain

            if _confirm "Update to new package directory" "N"; then

                # check if old directory is empty (safe, no ls, no glob bugs)
                if [ -d "$old_packages" ] && \
                   [ -n "$(find "$old_packages" -mindepth 1 -print -quit 2>/dev/null)" ]; then

                    _print "Previous package directory is not empty" warn 1

                    if _confirm "Move existing data to new location" "Y"; then
                        move_data=1
                    fi
                fi
            else
                config_write "$config_file" \
                    "LUMINOVA_VCI_CONF=$config_file" \
                    "LUMINOVA_VCI_BIN=$bin_file"
                    
                return 1
                # packages="$old_packages"
            fi
        fi
    fi

    # -----------------------------
    # Write config atomically
    # -----------------------------
    config_write "$config_file" \
        "LUMINOVA_VCI_CONF=$config_file" \
        "LUMINOVA_PACKAGE_DIR=$packages" \
        "LUMINOVA_VCI_BIN=$bin_file" || {

        if [ "$is_update_pkg_path" -eq 1 ]; then
            _print "Failed to update package configuration" error 0 1
        fi

        return 1
    }

    # -----------------------------
    # Move data if required
    # -----------------------------
    if [ "$move_data" -eq 1 ] && [ -n "$old_packages" ] && [ -d "$old_packages" ]; then
        mkdir -p "$packages" || {
            _print "Failed to create target package directory" error 0 1
            return 1
        }

        # copy first, fail loudly if anything breaks
        if ! cp -a "$old_packages/." "$packages/"; then
            _print "Failed to copy package data" error 0 1
            return 1
        fi

        # only delete if copy succeeded
        rm -rf "$old_packages" || {
            _print "Warning: failed to remove old package directory" warn
        }
    fi

    if [ "$is_update_pkg_path" -eq 1 ]; then
        _print "Luminova package directory was updated" success
        _print "New package directory: $packages" plain
    fi

    return 0
}

# Return 0 if the current process is running as root (UID 0)
_is_root() {
    [ "$(id -u)" -eq 0 ]
}

_is_path_rw() {
    local p="$1"
    [ -d "$p" ] && [ -r "$p" ] && [ -w "$p" ]
}

_in_path() {
    local dir="$1"

    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
        *) return 1 ;;
    esac
}

# True if string matches X.Y.Z semver
_is_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]
}

_skip_version() {
    [ -n "$1" ] || return 0

    _print \
        "Ignoring target version '$1'; this command does not use a version argument." \
        info
}

_command_action_in() {
    local action="$1"
    local command="${2:-$COMMAND}"
    local name="${3:-$SELF_NAME}"

    shift 3

    local expected
    local actions=("$@")

    # Default allowed actions
    if [ "${#actions[@]}" -eq 0 ]; then
        actions=(
            install
            update
            show_current
            list
            uninstall
            switch
            remove
        )
    fi

    for expected in "${actions[@]}"; do
        [ "$action" = "$expected" ] && return 0
    done

    _print "Unknown command: '$name $command $action'" error 0 1

    _help "$command"
    exit 1
}

# Normalize path separators and strip trailing slash
_normalize_path() {
    local p="${1//\\//}"
    printf '%s\n' "${p%/}"
}

# True if command is available
_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

_in_executable_path() {
    local dir="$1"

    _in_path "$dir" || return 1
    
    [ -d "$dir" ] || return 1
    [ -x "$dir" ] || return 1

    return 0
}

_version_compare() {
    local v1="$1"
    local op="$2"
    local v2="$3"

    case "$op" in
        ">")
            [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | tail -n1)" = "$v1" ] \
            && [ "$v1" != "$v2" ]
            ;;
        "<")
            [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ] \
            && [ "$v1" != "$v2" ]
            ;;
        ">=")
            [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | tail -n1)" = "$v1" ]
            ;;
        "<=")
            [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ]
            ;;
        "="|"==")
            [ "$v1" = "$v2" ]
            ;;
        "!=")
            [ "$v1" != "$v2" ]
            ;;
        *)
            return 2
            ;;
    esac
}

# Return 0 if path is owned by root with the given permission mode
_is_locked() {
    local path="$1"
    local permission="${2:-755}"

    [ -e "$path" ] || return 1

    local owner mode
    owner="$(_stat_owner "$path")"
    mode="$(_stat_mode "$path")"

    [ "$owner" = "root" ] && [ "$mode" = "$permission" ]
}

# ── Output helper ─────
# _print <message> [type] [icon] [stderr]
#   type:   success | error | info | warn | plain  (default: plain)
#   icon:   1 = prepend [✔]/[✖]/[i]/[!]           (default: 0)
#   stderr: 1 = write to stderr                    (default: 0)
_print() {
    local text="$1"
    local type="${2:-plain}"
    local icon="${3:-0}"
    local use_stderr="${4:-0}"

    local fd=1
    [ "$use_stderr" = "1" ] && fd=2

    local prefix=""
    if [ "$icon" = "1" ]; then
        case "$type" in
            success) prefix="[✔] " ;;
            error)   prefix="[✖] " ;;
            info)    prefix="[i] " ;;
            warn)    prefix="[!] " ;;
        esac
    fi

    local output="${prefix}${text}"

    # Skip color when NO_COLOR is set or the file descriptor is not a terminal
    if [ "$type" = "plain" ] \
        || [ "${NO_COLOR:-0}" = "1" ] \
        || ! [ -t "$fd" ]; then
        printf "%s\n" "$output" >&"$fd"
        return
    fi

    local reset="\033[0m"
    case "$type" in
        success) printf "%b\n" "\033[32m${output}${reset}" >&"$fd" ;;
        error)   printf "%b\n" "\033[31m${output}${reset}" >&"$fd" ;;
        info)    printf "%b\n" "\033[34m${output}${reset}" >&"$fd" ;;
        warn)    printf "%b\n" "\033[33m${output}${reset}" >&"$fd" ;;
        *)       printf "%s\n"  "$output"                  >&"$fd" ;;
    esac
}

# Prerequisite check 
# Called after argument parsing so --help/--version bypass it
_require_cmds() {
    local missing=()
    local cmd
    for cmd in git rsync find mktemp awk sed basename dirname; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        _print "Missing required commands: ${missing[*]}" error 1 1
        exit 1
    fi
}

# Resolve an absolute path without relying on readlink -f (macOS safe)
_realpath() {
    local p="$1"
    if command -v realpath &>/dev/null; then
        realpath "$p"
    elif command -v greadlink &>/dev/null; then
        greadlink -f "$p"
    else
        # Pure-bash fallback: canonicalize directory, append basename
        local dir base
        dir="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
        base="$(basename "$p")"
        printf "%s/%s\n" "$dir" "$base"
    fi
}

# Resolve symlink targets without readlink -f (macOS safe)
_readlink_resolved() {
    local p="$1"
    if readlink -f "$p" 2>/dev/null; then
        return
    fi
    if command -v greadlink &>/dev/null; then
        greadlink -f "$p"
        return
    fi
    _realpath "$p"
}

# Return 0 if /usr/local/bin is writable directly or via passwordless sudo
_can_write_global_bin() {
    if [ -w /usr/local/bin ]; then
        return 0
    fi
    if sudo -n test -w /usr/local/bin 2>/dev/null; then
        return 0
    fi
    return 1
}

# Runtime environment detection 
# Returns "root" when the process has effective root privileges or write
# access to system directories; otherwise returns "user"
_runtime_user() {
    if _is_root; then
        printf "root\n"; return
    fi

    if sudo -n true 2>/dev/null; then
        printf "root\n"; return
    fi

    local sys_dir
    for sys_dir in /opt /usr/local /etc; do
        if [ -d "$sys_dir" ] && [ -w "$sys_dir" ]; then
            printf "root\n"; return
        fi
    done

    # Known control-panel environments — treat as user-space
    if [ -f "/usr/local/cpanel/cpanel" ] \
        || [ -f "/usr/local/psa/bin/psadmin" ] \
        || [ -f "/usr/local/directadmin/directadmin" ]; then
        printf "user\n"; return
    fi

    printf "user\n"
}

# Print the owning username of a path (handles macOS vs Linux stat syntax)
_stat_owner() {
    if [ "$_OS" = "Darwin" ]; then
        stat -f "%Su" "$1" 2>/dev/null || true
    else
        stat -c "%U" "$1" 2>/dev/null || true
    fi
}

# Print the octal permission mode of a path (e.g. 755)
_stat_mode() {
    if [ "$_OS" = "Darwin" ]; then
        stat -f "%OLp" "$1" 2>/dev/null || true
    else
        stat -c "%a" "$1" 2>/dev/null || true
    fi
}

# Sort semantic version strings from stdin (GNU sort -V preferred, BSD fallback)
_sort_version() {
    if sort --version 2>/dev/null | grep -q GNU; then
        sort -V
    else
        sort -t. -k1,1n -k2,2n -k3,3n -k4,4n
    fi
}

# Select the best available hash algorithm and return its canonical name
_hash_algo() {
    if _command_exists "sha256sum"; then
        printf "sha256sum"; return
    fi

    if _command_exists "shasum"; then
        printf "shasum"; return
    fi

    if _command_exists "md5sum"; then
        printf "md5sum"; return
    fi

    if _command_exists "md5"; then
        printf "md5"; return
    fi

    printf "cksum"
}

# Invoke the chosen hash tool with the right flags
_hash_run() {
    local algo="$1"
    shift
    case "$algo" in
        sha256sum) sha256sum "$@" ;;
        shasum)    shasum -a 256 "$@" ;;
        md5sum)    md5sum "$@" ;;
        md5)       md5 -q "$@" ;;
        cksum)     cksum "$@" ;;
    esac
}

_hash_sha256() {
    local algo="$(_hash_algo)"
    case "$algo" in
        sha256sum) sha256sum "$@" | awk '{print $1}' ;;
        shasum)    shasum -a 256 "$@" | awk '{print $1}' ;;
        *)          return 1 ;;
    esac
}


# _hash <input> [algo] [mode]
#   mode: file (hash a file path) | string (hash a string value, default)
_hash() {
    local input="$1"
    local algo="${2:-$(_hash_algo)}"
    local mode="${3:-string}"

    case "$mode" in
        file)   _hash_run "$algo" "$input" | awk '{print $1}' ;;
        *)      printf "%s" "$input" | _hash_run "$algo" - | awk '{print $1}' ;;
    esac
}

_prompt() {
    local message="$1"
    local default="${2:-}"
    local value

    if [ -n "$default" ]; then
        read -rp "$message [$default]: " value
        value="${value:-$default}"
    else
        read -rp "$message: " value
    fi

    printf '%s' "$value"
}

# Prompt for yes/no confirmation; respects a default and non-interactive mode
_confirm() {
    local message="${1:-Confirm execution}"
    local default="${2:-N}"
    local reply

    # Non-interactive: apply the default silently
    if [ ! -t 0 ]; then
        [ "$default" = "Y" ] && return 0 || return 1
    fi

    if [ "$default" = "Y" ]; then
        printf "\n%s? [Y/n]: " "$message"
    else
        printf "\n%s? [y/N]: " "$message"
    fi

    read -r reply
    reply="${reply:-$default}"

    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *)            return 1 ;;
    esac
}

# Confirm before acting on a path; skip confirmation in force mode
_confirm_path() {
    local path="$1"
    local force="${2:-0}"

    if [ "$force" -eq 1 ]; then
        _print "Force mode: skipping confirmation for '$path'" info
        return 0
    fi

    if _confirm "Permanently delete: $path"; then
        return 0
    fi

    _print "Aborted by user." warn
    return 1
}

# Create a temp file or directory in a given dir with a sanitized name prefix
_make_temp() {
    local type="${1:-file}"
    local dir="${2:-${TMPDIR:-/tmp}/luminova}"
    local name="${3:-test}"

    # local tmp="$(config_path 2>/dev/null)" || true
    # [ -n "$tmp" ] || tmp="${TMPDIR:-/tmp}"
    # dir="$tmp/tmp"

    [ -n "$dir" ] || return 1
    mkdir -p "$dir" || return 1

    # Sanitize name: keep only safe characters, strip leading dashes
    name="${name//[^a-zA-Z0-9._-]/_}"
    name="${name#-}"
    name="${name:-tmp}"

    local result
    case "$type" in
        file) result="$(mktemp "${dir}/${name}.XXXXXX")" || return 1 ;;
        dir)  result="$(mktemp -d "${dir}/${name}.XXXXXX")" || return 1 ;;
        *)    return 1 ;;
    esac

    printf '%s\n' "$result"
}

# Create a symlink from release_path to link_path; fall back to rsync copy
# when symlinks are not supported on the filesystem
_create_symlink() {
    local release_path="$1"
    local link_path="$2"
    local base_dir="$3"

    if [ ! -d "$release_path" ]; then
        _print "Release directory not found: $release_path" error 1 1
        return 1
    fi

    if [ -z "$base_dir" ]; then
        _print "Base directory required for symlink fallback." error 1 1
        return 1
    fi

    if _can_symlink "$base_dir"; then
        _print "Creating release symlink..." info 1
        ln -sfn "$release_path" "$link_path"
        return 0
    fi

    _print "Symlinks not supported; using directory-copy fallback..." warn 1

    local tmp_dir
    tmp_dir="$(_make_temp dir "$base_dir" "current")" || {
        _print "Failed to create temp directory for fallback copy." error 1 1
        return 1
    }

    rsync -a --delete "$release_path"/ "$tmp_dir"/

    local backup="${link_path}.old"
    rm -rf "$backup"
    [ -d "$link_path" ] && mv "$link_path" "$backup"
    mv "$tmp_dir" "$link_path"
    rm -rf "$backup"
}

# Return 0 if the filesystem under dir supports symlinks
_can_symlink() {
    local dir="$1"
    [ -d "$dir" ] || return 1

    local tmp_dir target link
    tmp_dir="$(_make_temp dir "$dir" "symlink_test")" || return 1

    target="$tmp_dir/target"
    link="$tmp_dir/link"

    if ! touch "$target" 2>/dev/null; then
        rm -rf "$tmp_dir"
        return 1
    fi

    if ln -s "$target" "$link" 2>/dev/null; then
        rm -rf "$tmp_dir"
        return 0
    fi

    rm -rf "$tmp_dir"
    return 1
}

_user_group() {
     case "$1" in
        root)
            printf "%s:%s\n" "root" "root"
            return 0
            ;;
        user)
            printf "%s:%s\n" "$(id -un)" "$(id -gn)"
            return 0
            ;;
        *)
            if _is_root; then
                printf "%s:%s\n" "root" "root"
                return 0
            fi
            
            _print "Unknown runtime mode: '$1'" error 1 1
            return 1
            ;;
    esac
}

# Apply ownership and permission mode to a path recursively
_lock_permission() {
    local path="$1"
    local mode="${2:-755}"
    local runtime="${3:-root}"
    local user_group

    if [ -z "$path" ] || [ "$path" = "/" ]; then
        _print "Unsafe path for locking: '$path'" error 1 1
        return 1
    fi

    user_group="$(_user_group "$runtime")" || return 1

    _print "Locking $path (mode: $mode, owner: $user_group)..." warn 1

    chown -R "$user_group" "$path" 2>/dev/null \
        || _print "Ownership change skipped (insufficient permissions)." info 1

    if [ "$runtime" = "root" ]; then
        chmod -R "$mode" "$path"
    else
        chmod -R "$mode" "$path" 2>/dev/null || true
    fi

    _print "Permissions applied ($mode)." success 1
}

_clear_temp() {
    local base="${1:-$SCRIPT_DIR}"
    local silent="${2:-1}"
    local tmp_dir="$base/tmp"

    # Always validate
    _assert_path "$tmp_dir" "$base" "" "$silent" || return 0

    # Safe delete
    [ -d "$tmp_dir" ] || return 0

    rm -rf -- "$tmp_dir" 2>/dev/null || return 0

    return 0
}

# Validate that a reset target is safe: non-empty, non-root, within base dir,
# and does not contain this script itself
_assert_path() {
    local target="$1"
    local base="${2:-${SCRIPT_DIR}}"
    local self="${3:-${SELF}}"
    local silent="${4:-0}"

   if [[ ! -d "$target" ]]; then
        return 0
    fi

    # Resolve real paths (portable fallback if readlink -f is missing)
    target="$(cd "$target" 2>/dev/null && pwd -P)" || {
        [ "$silent" -eq 1 ] || _print "Invalid target path "$target"." error 1 1
        return 1
    }

    # Prevent deleting base itself unless explicitly intended
    if [ "$target" = "$base" ]; then
        [ "$silent" -eq 1 ] || _print "Refusing reset: cannot delete base directory directly $target." warn 1 1
        return 1
    fi

    base="$(cd "$base" 2>/dev/null && pwd -P)" || {
        [ "$silent" -eq 1 ] || _print "Invalid base path." error 1 1
        return 1
    }

    self="$(cd "$(dirname "$self")" 2>/dev/null && pwd -P)/$(basename "$self")" || {
       [ "$silent" -eq 1 ] ||  _print "Invalid script path." error 1 1
        return 1
    }

    # Safety guard: empty or root
    if [ -z "$target" ] || [ "$target" = "/" ]; then
        [ "$silent" -eq 1 ] || _print "Refusing reset: target path is empty or root." error 1 1
        return 1
    fi

    # Ensure target is inside base (strict boundary match)
    # case "$target/" in
    #    "$base/"*) ;;
    #    *)
    #       [ "$silent" -eq 1 ] ||  _print "Refusing reset: path is outside the managed directory." error 1 1
    #        return 1
    #        ;;
    # esac

    # Ensure script is NOT inside target
    case "$self" in
        "$target/"* )
            [ "$silent" -eq 1 ] || _print "Refusing reset: this script is inside the target path." warn 1 1
            return 1
            ;;
    esac

    return 0
}