#!/usr/bin/env bash
# ------------------------------------------------------------
# PHP Luminova — Version Control Interface
# ------------------------------------------------------------
# Manages versioned deployments of the Luminova PHP framework
# across a shared installation directory.
#
# Features:
#   - Clone and build framework releases from git or local source
#   - Switch between installed releases instantly (no rebuild)
#   - List all releases with the active version highlighted
#   - Hash-based change detection to skip redundant deploys
#   - Optional permission locking for production hardening
#   - Safe destructive operations with path validation and prompts
#   - macOS/BSD and GNU/Linux compatible
# ------------------------------------------------------------

# Enable xtrace when DEBUG=1|yes|true
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace
fi

# Strict mode only when executed directly (not sourced)
if ! (return 0 2>/dev/null); then
    set -euo pipefail
fi

readonly VERSION="1.3.1"
readonly PRODUCTION=1
readonly SELF_REPO_URL="https://github.com/luminovang/vci.git"
readonly PACKAGE_REPO_URL="https://github.com/luminovang/framework.git"
readonly _OS="$(uname -s)"
readonly SCRIPT_ENTRY="${BASH_SOURCE[0]}"

SOURCE="$SCRIPT_ENTRY"

while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"

    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done

readonly SCRIPT_REAL="$SOURCE"
readonly SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_REAL")" && pwd)"
readonly BASE_SOURCE="${BASH_SOURCE[0]}"

# Trap state: tracks a partial release so it can be cleaned on failure
_RELEASE_PATH=""
_HASH_FILE=""

# Include a named source from the lib/ directory
_include() {
    local filename="$1"
    local lib_path="$SCRIPT_DIR/lib/${filename}.sh"

    if [ ! -f "$lib_path" ]; then
        echo "Module not found: $lib_path" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$lib_path"
}

_self_name() {
    local self="$1"

    if [ -L "$self" ]; then
        printf "%s\n" "luminova"
    else
        printf "%s\n" "./luminova.sh"
    fi
}

_cmd() {
    local name="${SELF_NAME:-$(_self_name "$BASE_SOURCE")}"
    local cmd

    printf -v cmd '%q ' "$name" "$@"
    cmd=${cmd% }

    printf '%s\n' "$cmd"
}

_include "head"

# Resolved absolute path to this script and the preferred hash algorithm
readonly SELF="$(_realpath "$BASE_SOURCE")"
readonly SELF_NAME="$(_self_name "$BASE_SOURCE")"
readonly HASH_ALGO="$(_hash_algo)"

# Default flag values
FORCE=0
HELP_MODE=0
HASH_CHECK=1
DELETE_REPO=0
SWITCH_ONLY=0
OLD_VERSION=""
SELF_ACTION=""
RUNTIME_USER=""
REMOVE_ACTION=""
UPDATE_PKG_PATH=0
COMMAND_ACTION=""
TARGET_VERSION=""
UNINSTALL_PURGE=0
LOCK_PERMISSION=0
PERMISSION_MODE=""
PREFER_PACKAGES_DIR=""
PULL_ORIGIN_SOURCE="local"
COMMANDS=()

# Load help text and print it, then exit
_help() {
    _include "helps"
    print_helps "${1:-}"
}

_version() {
    _print "PHP Luminova — Shared Module Manager"
    _print "Version: $VERSION" success
    exit 0
}

_paths() {
    local where="${1:-}"
    local path
    _include "config"

    if [ -z "$where" ]; then
        _print "Luminova VCI Paths" success
        _print "LUMINOVA_VCI_SCRIPT_DIR=$SCRIPT_DIR"

        config_get
    else
        if config_has "LUMINOVA_PACKAGE_DIR"; then
            path="$(config_get LUMINOVA_PACKAGE_DIR)"
        else
            path="$SCRIPT_DIR/packages"
        fi

        case "$where" in
            packages)
                _print "$path"
                exit 1
                ;;
            release)
                _print "$path/release"
                exit 1
                ;;
            current)
                _print "$path/current"
                exit 1
                ;;
            repo)
                _print "$path/repo"
                exit 1
                ;;
            *)
                _print "Invalid where command target '$where'" error
                exit 1
                ;;
        esac
    fi
    exit 0
}


trap _cleanup_trap EXIT

# ── Argument parsing
for arg in "$@"; do
    case "$arg" in
        -h|--help)                HELP_MODE=1 ;;
        -v|--version)             _version ;;
        --paths)                  _paths ;;
        -w=*|--where=*)           _paths "${arg#*=}" ;;

        # Package Arguments (luminova package ...) ;;

        --path=*)                 PREFER_PACKAGES_DIR="${arg#*=}" ;;
        --path)                   PREFER_PACKAGES_DIR="$(pwd)" ;;
        -b=*|--branch=*)          TARGET_VERSION="${arg#*=}" ;;
        -l|--list)                COMMAND_ACTION="list" ;;
        -c|--current)             COMMAND_ACTION="show_current" ;;
        -r|--remove)              COMMAND_ACTION="remove"; REMOVE_ACTION="all" ;;
        -r=*|--remove=*)          COMMAND_ACTION="remove"; REMOVE_ACTION="${arg#*=}" ;;
        -s=*|--switch=*)          COMMAND_ACTION="switch"; TARGET_VERSION="${arg#*=}" ;;

        # Package and Self arguments (luminova [package|self] ...) ;;
        -i|--install)             COMMAND_ACTION="install" ;;
        -u|--update)              COMMAND_ACTION="update" ;;
        -i=*|--install=*)         COMMAND_ACTION="install"; TARGET_VERSION="${arg#*=}" ;;
        -u=*|--update=*)          COMMAND_ACTION="update"; TARGET_VERSION="${arg#*=}" ;;

        # Self only arguments (luminova self ...) ;;
        -ui|--uninstall)          COMMAND_ACTION="uninstall" ;;

        # Command tools arguments ;;
        -ru=*|--runtime=*)        RUNTIME_USER="${arg#*=}" ;;
        -p|--purge)               UNINSTALL_PURGE=1 ;;
        -f|--force)               FORCE=1 ;;
        -d|--delete)              DELETE_REPO=1 ;;

        --lock)                   LOCK_PERMISSION=1 ;;
        -m=*|--mode=*)            LOCK_PERMISSION=1; PERMISSION_MODE="${arg#*=}" ;;
        -lm=*|--lock-mode=*)      LOCK_PERMISSION=1; PERMISSION_MODE="${arg#*=}" ;;
        *)                        COMMANDS+=("$arg") ;;
    esac
done

# Handle positional arguments
readonly CMD_POSITION="${COMMANDS[0]:-}"
COMMAND=""

case "$CMD_POSITION" in
    package)                 COMMAND="package" ;;
    self)                    COMMAND="self" ;;
    *)      
        if [ "$HELP_MODE" -eq 1 ]; then
            _help
            exit 0
        fi

        _help info
        #_print "Unknown command '$SELF_NAME $CMD_POSITION'" error 0 1
        exit 1
        ;;
esac

if [ "$HELP_MODE" -eq 1 ]; then
    _help "$COMMAND"
    exit 0
fi

_include "config"


if [ -n "$PREFER_PACKAGES_DIR" ]; then
    if [ "$SCRIPT_DIR" = "$PREFER_PACKAGES_DIR" ]; then
        readonly PACKAGES_DIR="$PREFER_PACKAGES_DIR/packages"
    else
        readonly PACKAGES_DIR="$PREFER_PACKAGES_DIR"
    fi
elif config_has "LUMINOVA_PACKAGE_DIR"; then
    readonly PACKAGES_DIR="$(config_get LUMINOVA_PACKAGE_DIR)"
else
    readonly PACKAGES_DIR="$SCRIPT_DIR/packages"
fi

export CONFIG_FILE="$(config_get_file)"
readonly REPO_DIR="$PACKAGES_DIR/repo"
readonly RELEASES_DIR="$PACKAGES_DIR/releases"
readonly CURRENT_DIR="$PACKAGES_DIR/current"

# Prerequisite check runs after arg parsing so --help/--version bypass it
_require_cmds

# Only root user can run install and update commands
if ! _is_root; then
    _print "Luminova VCI '$COMMAND' command requires root privileges." error 0 1
    _print "Try: sudo $(_cmd "$@")" plain 0 1

    exit 1
fi

if [ -n "$PREFER_PACKAGES_DIR" ] && [ -z "$COMMAND_ACTION" ]; then
    UPDATE_PKG_PATH=1
fi

_setup "$CONFIG_FILE" "$SELF" "$PACKAGES_DIR" "$UPDATE_PKG_PATH"
status=$?

if [ "$UPDATE_PKG_PATH" -eq 1 ]; then
    exit "$status"
fi

# Resolve runtime mode
RUNTIME_USER="${RUNTIME_USER:-auto}"

if [ "$RUNTIME_USER" = "auto" ]; then
    RUNTIME_USER="$(_runtime_user)"
fi

if [ "$RUNTIME_USER" != "root" ] && [ "$RUNTIME_USER" != "user" ]; then
    _print "Invalid runtime mode: '$RUNTIME_USER'" error 1 1
    exit 1
fi

# Require a valid command action
_command_action_in "$COMMAND_ACTION" "$COMMAND" "$SELF_NAME" 

mkdir -p "$PACKAGES_DIR"
cd "$PACKAGES_DIR"

_include "request"

# Self-management commands
if [ "$COMMAND" = "self" ]; then
    _include "manager"

    case "$COMMAND_ACTION" in
        update)
            self_update_script "$RUNTIME_USER" "$SCRIPT_DIR" "$SELF_REPO_URL" "$TARGET_VERSION"
            exit $?
            ;;
        install)
            _skip_version "$TARGET_VERSION"
            self_install_script "$RUNTIME_USER" "$SELF"
            exit $?
            ;;
        uninstall)
            _skip_version "$TARGET_VERSION"
            self_uninstall_script "$RUNTIME_USER" "$UNINSTALL_PURGE" "$SCRIPT_DIR" "$SELF"
            exit $?
            ;;
        *)
            _print "Invalid self command '$(_cmd "$@")'" error 0 1
            exit 1
            ;;
    esac
fi

if [ "$COMMAND" != "package" ]; then
   _print "Unknown command '$(_cmd "$@")'" error 0 1
    exit 1
fi

_include "package"

# Query commands (read-only, no build)
if [ "$COMMAND_ACTION" = "show_current" ]; then
    package_current_release "$PACKAGES_DIR"
    exit $?
fi

if [ "$COMMAND_ACTION" = "list" ]; then
    package_list_versions "$RELEASES_DIR" "$CURRENT_DIR"
    exit $?
fi

# Package switch command
if [ "$COMMAND_ACTION" = "switch" ]; then
    package_switch_version "$TARGET_VERSION" "$RELEASES_DIR" "$CURRENT_DIR" "$SCRIPT_DIR"
    exit $?
fi

# Remove package module 
if [ "$COMMAND_ACTION" = "remove" ]; then
    if [ -z "$REMOVE_ACTION" ]; then
        _print "Unknown command action '$COMMAND_ACTION'" error 0 1
        exit 1
    fi

    case "$REMOVE_ACTION" in
        all)
            package_clear_modules "$PACKAGES_DIR" "$SCRIPT_DIR" "$FORCE"
            exit $?
            ;;
        *)
            package_remove_module "$PACKAGES_DIR" "$SCRIPT_DIR" "$RESET_TARGET" "$FORCE"
            exit $?
            ;;
    esac
fi

_command_action_in "$COMMAND_ACTION" "$COMMAND" "$SELF_NAME" install update

# Package update module check
if [ "$COMMAND_ACTION" = "update" ]; then
    package_installed "$RELEASES_DIR" || {
        _print "No installed luminova package to update" warn
        _print "Run command '$SELF_NAME --install' first"
        exit 1
    }
fi

# Determine whether source URL is remote or local
if [[ "$PACKAGE_REPO_URL" == http* ]] || [[ "$PACKAGE_REPO_URL" == git@* ]]; then
    PULL_ORIGIN_SOURCE="remote"
else
    # Local sources are always re-synced; no value in keeping the repo dir
    DELETE_REPO=1
fi

# Force mode: wipe the existing clone so we start from scratch.
# Also disables hash check because the repo state is unknown after a wipe.
if [ "$FORCE" -eq 1 ]; then
    package_force_delete_repo "$REPO_DIR"
    HASH_CHECK=0
fi

# Package update module command
if [ "$COMMAND_ACTION" = "update" ]; then
    # Always rebuild on update; skip hash comparison
    HASH_CHECK=0
    package_clean_repo "$REPO_DIR" "full" 1
fi

# Clone (remote) or rsync (local) the source into the repo directory
package_clone_repo "$PACKAGES_DIR" "$REPO_DIR" "$PACKAGE_REPO_URL" "$PULL_ORIGIN_SOURCE" "$TARGET_VERSION"

# Auto-detect version from git tags or composer.json when not specified
if [ -z "$TARGET_VERSION" ]; then
    _print "Auto-detecting version..." info
    TARGET_VERSION="$(package_detect_version "$REPO_DIR" "$PULL_ORIGIN_SOURCE")"

    if [ -n "$TARGET_VERSION" ]; then
        _print "Auto-detected version: $TARGET_VERSION" info 1
    else
        op_label="Install"
        [ "$COMMAND_ACTION" = "update" ] && op_label="Update"

        _print "$op_label mode requires a version; no tags found in repo." error 1 1
        _print "Usage: $SELF_NAME --${COMMAND_ACTION}=<version>" plain
        _print "Cleaning up temporary repo clone..." warn
        package_clean_repo "$REPO_DIR" "full"
        exit 1
    fi
fi

RELEASE_PATH="$RELEASES_DIR/$TARGET_VERSION"
RELEASE_METADATA_PATH="$RELEASES_DIR/$TARGET_VERSION/.metadata"
HASH_FILE="$RELEASE_METADATA_PATH/.hash"

# mkdir -p "$RELEASE_METADATA_PATH"

# Register with the cleanup trap so partial builds are removed on failure
_RELEASE_PATH="$RELEASE_PATH"
_HASH_FILE="$HASH_FILE"

# Bring the repo to the exact requested version
package_sync_repo "$REPO_DIR" "$PULL_ORIGIN_SOURCE" "$TARGET_VERSION" "$RUNTIME_USER" || true

# Compute a content fingerprint for change detection
REPO_HASH="$(request_hash_repo "$REPO_DIR" "$PULL_ORIGIN_SOURCE" "$HASH_ALGO")"

# Skip rebuild when source is unchanged (install mode only)
if [ "$HASH_CHECK" -eq 1 ] && [ -f "$HASH_FILE" ]; then
    EXISTING_HASH="$(cat "$HASH_FILE")"
    if [ "$EXISTING_HASH" = "$REPO_HASH" ]; then
        _print "No changes detected in $TARGET_VERSION — skipping rebuild." info 1

        if [ "$DELETE_REPO" -eq 0 ] && [ "$PULL_ORIGIN_SOURCE" = "local" ]; then
            package_clean_repo "$REPO_DIR" "full" 1
        fi
        exit 0
    fi
fi

# Build the versioned release directory from the repo source
package_build_repo_structure "$REPO_DIR" "$RELEASE_PATH"

# Write the hash before creating the symlink so a mid-run crash leaves
# the release dir without a hash file, triggering cleanup on next run
printf "%s\n" "$REPO_HASH" > "$HASH_FILE"

# Point 'current' at the newly built release
if [ -L "$CURRENT_DIR" ]; then
    OLD_VERSION="$(basename "$(realpath "$CURRENT_DIR")")"
fi

if [ -z "$OLD_VERSION" ] || _version_compare "$TARGET_VERSION" ">" "$OLD_VERSION"; then
    printf 'Updating current release: %s -> %s\n' \
        "${OLD_VERSION:-none}" \
        "$TARGET_VERSION"

    _create_symlink "$RELEASE_PATH" "$CURRENT_DIR" "$SCRIPT_DIR"
fi

# Optionally remove repo source files to reclaim disk space after build
if [ "$DELETE_REPO" -eq 1 ]; then
    _print "Cleaning repo source files after build..." warn
    package_clean_repo "$REPO_DIR" "keep_git"
fi

# _setup "$CONFIG_FILE" "$SELF" "$PACKAGES_DIR"

# Harden the base directory if it isn't already locked at 755
if ! _is_locked "$SCRIPT_DIR" 755; then
    _lock_permission "$SCRIPT_DIR" 755 "$RUNTIME_USER"
fi

# Apply the user-requested permission lock to the packages directory
if [ "${LOCK_PERMISSION:-0}" -eq 1 ]; then
    _lock_mode="${PERMISSION_MODE:-755}"

    if _is_locked "$PACKAGES_DIR" "$_lock_mode"; then
        _print "Permissions already locked ($_lock_mode) on $PACKAGES_DIR. Skipping." info 1
    else
        _lock_permission "$PACKAGES_DIR" "$_lock_mode" "$RUNTIME_USER"
    fi
fi

_print "Runtime mode: $RUNTIME_USER active version: $TARGET_VERSION" info 1
_print "Deployment complete." success 1
_print "Package location $PACKAGES_DIR"
_print "Config location $CONFIG_FILE"

exit 0