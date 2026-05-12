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

readonly VERSION="1.1.0"
readonly PRODUCTION=1
readonly SELF_REPO_URL="https://github.com/luminovang/luminova-vci.git"
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

_include "head"

# Resolved absolute path to this script and the preferred hash algorithm
readonly SELF="$(_realpath "$BASE_SOURCE")"
readonly SELF_NAME="$(_self_name "$SELF")"
readonly HASH_ALGO="$(_hash_algo)"

# Default flag values
FORCE=0
BRANCH=""
RESET_ALL=0
HASH_CHECK=1
DELETE_REPO=0
SWITCH_ONLY=0
SHOW_CURRENT=0
SELF_ACTION=""
PULL_ACTION=""
RESET_TARGET=""
LIST_RELEASES=0
RUNTIME_USER=""
UNINSTALL_PURGE=0
LOCK_PERMISSION=0
PERMISSION_MODE=""
USE_PACKAGES_DIR=""
PULL_ORIGIN_SOURCE="local"
POSITIONAL=()

# Load help text and print it, then exit
_help() {
    _include "helps"
    print_luminova_helps
}

_version() {
    _print "PHP Luminova — Shared Module Manager"
    _print "Version: $VERSION" success
    exit 0
}

_paths() {
    _include "config"

    _print "Luminova VCI Paths" success
    _print "LUMINOVA_VCI_SCRIPT_DIR=$SCRIPT_DIR"

    config_get
    exit 0
}


trap _cleanup_trap EXIT

# ── Argument parsing
for arg in "$@"; do
    case "$arg" in
        -h|--help)                _help ;;
        -l|--list)                LIST_RELEASES=1 ;;
        -f|--force)               FORCE=1 ;;
        -d|--delete)              DELETE_REPO=1 ;;
        --paths)                  _paths ;;
        --path=*)                 USE_PACKAGES_DIR="${arg#*=}" ;;
        --self=*)                 SELF_ACTION="${arg#*=}" ;;
        -b=*|--branch=*)          BRANCH="${arg#*=}" ;;
        -s=*|--switch=*)          SWITCH_ONLY=1; BRANCH="${arg#*=}" ;;
        -m|--lock-permission)     LOCK_PERMISSION=1 ;;
        -m=*|--lock-permission=*) LOCK_PERMISSION=1; PERMISSION_MODE="${arg#*=}" ;;
        -i|--install)             PULL_ACTION="install" ;;
        -i=*|--install=*)         PULL_ACTION="install"; BRANCH="${arg#*=}" ;;
        -u|--update)              PULL_ACTION="update" ;;
        -u=*|--update=*)          PULL_ACTION="update"; BRANCH="${arg#*=}" ;;
        -ru=*|--runtime=*)        RUNTIME_USER="${arg#*=}" ;;
        -r|--reset)               RESET_ALL=1 ;;
        -r=*|--reset=*)           RESET_TARGET="${arg#*=}" ;;
        -p|--purge)               UNINSTALL_PURGE=1 ;;
        -v|--version)             _version ;;
        -c|--current)             SHOW_CURRENT=1 ;;
        *)                        POSITIONAL+=("$arg") ;;
    esac
done

_include "config"

# Handle positional arguments
if [ -z "$USE_PACKAGES_DIR" ]; then
    USE_PACKAGES_DIR="${POSITIONAL[0]:-}"
fi

if config_has "LUMINOVA_PACKAGE_DIR"; then
    readonly PACKAGES_DIR="$(config_get LUMINOVA_PACKAGE_DIR)"
elif [ -n "$USE_PACKAGES_DIR" ]; then
    if [ "$SCRIPT_DIR" = "$USE_PACKAGES_DIR" ]; then
        readonly PACKAGES_DIR="$USE_PACKAGES_DIR/packages"
    else
        readonly PACKAGES_DIR="$USE_PACKAGES_DIR"
    fi
else
    readonly PACKAGES_DIR="$SCRIPT_DIR/packages"
fi

readonly CONFIG_DIR="$(config_path)"
readonly REPO_DIR="$PACKAGES_DIR/repo"
readonly RELEASES_DIR="$PACKAGES_DIR/releases"
readonly CURRENT_DIR="$PACKAGES_DIR/current"

# Prerequisite check runs after arg parsing so --help/--version bypass it
_require_cmds

# Resolve runtime mode
RUNTIME_USER="${RUNTIME_USER:-auto}"

if [ "$RUNTIME_USER" = "auto" ]; then
    RUNTIME_USER="$(_runtime_user)"
fi

if [ "$RUNTIME_USER" != "root" ] && [ "$RUNTIME_USER" != "user" ]; then
    _print "Invalid runtime mode: '$RUNTIME_USER'" error 1 1
    exit 1
fi

mkdir -p "$PACKAGES_DIR"
cd "$PACKAGES_DIR"

_include "request"

# Self-management commands
if [ -n "$SELF_ACTION" ]; then
    _include "manager"

    case "$SELF_ACTION" in
        update)
            manager_update_self "$RUNTIME_USER" "$SCRIPT_DIR" "$SELF_REPO_URL" "$BRANCH"
            exit $?
            ;;
        install)
            manager_install_self "$RUNTIME_USER" "$SELF" "$SCRIPT_DIR"
            exit $?
            ;;
        uninstall)
            manager_uninstall_self "$RUNTIME_USER" "$UNINSTALL_PURGE" "$SELF" "$SCRIPT_DIR"
            exit $?
            ;;
        *)
            _print "Invalid self command '$SELF_ACTION'" error
            exit 1
            ;;
    esac
fi

_include "package"

# Query commands (read-only, no build)
if [ "${SHOW_CURRENT:-0}" -eq 1 ]; then
    package_current_release "$PACKAGES_DIR"
fi

if [ "$LIST_RELEASES" -eq 1 ]; then
    package_list_versions "$RELEASES_DIR" "$CURRENT_DIR"
    exit 0
fi

# Reset commands 
if [ "$RESET_ALL" -eq 1 ]; then
    package_modules_reset_all "$PACKAGES_DIR" "$SCRIPT_DIR" "$FORCE"
    exit 0
fi

if [ -n "$RESET_TARGET" ]; then
    package_reset_target_module "$PACKAGES_DIR" "$SCRIPT_DIR" "$RESET_TARGET" "$FORCE" || exit 1
    exit 0
fi

# Switch command
if [ "$SWITCH_ONLY" -eq 1 ]; then
    package_switch_version "$BRANCH" "$RELEASES_DIR" "$CURRENT_DIR" "$SCRIPT_DIR"
    exit 0
fi

# Require an explicit install or update command from this point on
if [ "$PULL_ACTION" != "install" ] && [ "$PULL_ACTION" != "update" ]; then
    _help
fi

if [ "$PULL_ACTION" = "update" ]; then
    package_installed "$RELEASES_DIR" || {
        _print "No installed luminova package to update" warn
        _print "Run command `$SELF_NAME --install` first"
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

if [ "$PULL_ACTION" = "update" ]; then
    # Always rebuild on update; skip hash comparison
    HASH_CHECK=0
    package_clean_repo "$REPO_DIR" "full" 1
fi

# Clone (remote) or rsync (local) the source into the repo directory
package_clone_repo "$PACKAGES_DIR" "$REPO_DIR" "$PACKAGE_REPO_URL" "$PULL_ORIGIN_SOURCE" "$BRANCH"

# Auto-detect version from git tags or composer.json when not specified
if [ -z "$BRANCH" ]; then
    _print "Auto-detecting version..." info
    BRANCH="$(package_detect_version "$REPO_DIR" "$PULL_ORIGIN_SOURCE")"

    if [ -n "$BRANCH" ]; then
        _print "Auto-detected version: $BRANCH" info 1
    else
        op_label="Install"
        [ "$PULL_ACTION" = "update" ] && op_label="Update"

        _print "$op_label mode requires a version; no tags found in repo." error 1 1
        _print "Usage: $0 --${PULL_ACTION}=<version>" plain
        _print "Cleaning up temporary repo clone..." warn
        package_clean_repo "$REPO_DIR" "full"
        exit 1
    fi
fi

RELEASE_PATH="$RELEASES_DIR/$BRANCH"
HASH_FILE="$RELEASE_PATH/.hash"

# Register with the cleanup trap so partial builds are removed on failure
_RELEASE_PATH="$RELEASE_PATH"
_HASH_FILE="$HASH_FILE"

# Bring the repo to the exact requested version
package_sync_repo "$REPO_DIR" "$PULL_ORIGIN_SOURCE" "$BRANCH" "$RUNTIME_USER" || true

# Compute a content fingerprint for change detection
REPO_HASH="$(request_hash_repo "$REPO_DIR" "$PULL_ORIGIN_SOURCE" "$HASH_ALGO")"

# Skip rebuild when source is unchanged (install mode only)
if [ "$HASH_CHECK" -eq 1 ] && [ -f "$HASH_FILE" ]; then
    EXISTING_HASH="$(cat "$HASH_FILE")"
    if [ "$EXISTING_HASH" = "$REPO_HASH" ]; then
        _print "No changes detected in $BRANCH — skipping rebuild." info 1

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
_create_symlink "$RELEASE_PATH" "$CURRENT_DIR" "$SCRIPT_DIR"

# Optionally remove repo source files to reclaim disk space after build
if [ "$DELETE_REPO" -eq 1 ]; then
    _print "Cleaning repo source files after build..." warn
    package_clean_repo "$REPO_DIR" "keep_git"
fi

if [ -n "$CONFIG_DIR" ]; then
    config_write "$CONFIG_DIR" \
        "LUMINOVA_VCI_BIN=$SELF" \
        "LUMINOVA_VCI_CONF=$CONFIG_DIR" \
        "LUMINOVA_PACKAGE_DIR=$PACKAGES_DIR"
fi

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

_print "Runtime mode: $RUNTIME_USER active version: $BRANCH" info 1
_print "Deployment complete." success 1
_print "Package location $PACKAGES_DIR"
_print "Config location $CONFIG_DIR"

exit 0