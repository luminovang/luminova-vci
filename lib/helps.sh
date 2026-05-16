#!/usr/bin/env bash

print_helps() {
    local context="${1:-}"
    local name="${SELF_NAME:-$(_self_name "$SELF")}"

    case "$context" in
        package)  package_helps "$name" ;;
        self)     self_script_helps "$name" ;;
        info)     show_info "$name" ;;
        *)        global_helps "$name" ;;
    esac
}

show_info() {
    local name="${1:-luminova}"
    local version="${VERSION:-unknown}"

    cat <<EOF
$name - Luminova VCI Manager
Version: $version

Packages:
  $name package --install[=<version>]       Install a framework release
  $name package --update[=<version>]        Rebuild and update a release
  $name package --switch=<version>          Switch the active version (no rebuild)
  $name package --list                      List all installed releases
  $name package --current                   Show the active release version

Self:
  $name self --install                      Install VCI as a global command
  $name self --update[=<version>]           Update the VCI script from GitHub
  $name self --uninstall                    Remove the installed VCI binary

Help:
  $name --help
  $name package --help
  $name self --help

EOF
}

package_helps() {
    local name="${1:-luminova}"
    cat <<EOF
Luminova Version Control Interface
Manage shared Luminova PHP framework releases.

Usage:
  $name package <options>

Install or update a release:
  $name package --install
  $name package --install=3.8.0
  $name package --install=3.8.0 --runtime=root
  $name package --install=3.8.0 --path=/etc/luminova/packages
  $name package --install=3.8.0 --delete
  $name package --install=3.8.0 --lock
  $name package --install=3.8.0 --lock-mode=755
  $name package --update
  $name package --update=3.9.0
  $name package --update=3.9.0 --force

Switch to an installed release (no rebuild):
  $name package --switch=3.8.0

Inspect releases:
  $name package --list
  $name package --current

Remove releases:
  $name package --remove
  $name package --remove=3.7.8
  $name package --remove=repo

Options:
  -h, --help                      Show this help message
  -i, --install[=<version>]       Install a release (default: latest git tag)
  -u, --update[=<version>]        Rebuild a release; always bypasses the hash check
  -s, --switch=<version>          Switch to an already-installed release without rebuilding
  -l, --list                      List all installed releases
  -c, --current                   Show the currently active release
  -r, --remove[=<target>]         Remove a specific release (e.g. --remove=3.8.0), only the
                                  repo clone (--remove=repo), or all releases (--remove)
  -b, --branch=<ref>              Git branch or tag to use with --install or --update
      --path=<dir>                Override the default packages storage directory
  -f, --force                     Delete the existing repo clone and re-clone from scratch;
                                  also disables the hash check for that run
  -d, --delete                    Remove repo source files after building
      --lock                      Lock packages directory permissions after deploy (default mode: 755)
  -m, --mode=<mode>               Set a specific permission mode when locking (e.g. 755, 555)
  -lm, --lock-mode=<mode>         Equivalent to --lock with an explicit mode value

Directory structure:
  packages/
    repo/      → Temporary git clone used during builds
    releases/  → One subdirectory per installed release
    current  → → Symlink pointing to the active release

Notes:
  - Version is auto-detected from git tags when --install is used without a version argument.
  - --switch only works with already-installed releases; it does not trigger a rebuild.
  - Use --force to discard and re-clone the source repository.
  - Use --update instead of --install to force a rebuild of an already-present version.
EOF
    exit 0
}

self_script_helps() {
    local name="${1:-luminova}"
    cat <<EOF
Luminova Version Control Interface
Manage the Luminova VCI script itself.

Usage:
  $name self <options>

Examples:
  $name self --install
  $name self --update
  $name self --update --branch=v2.1.0
  $name self --uninstall
  $name self --uninstall --purge

Options:
  -h, --help                      Show this help message
  -i, --install                   Install this script as 'luminova' in PATH
  -u, --update[=<version>]        Replace the installed binary with the latest from GitHub
  -ui, --uninstall                Remove the installed 'luminova' binary or main installation
  -b, --branch=<ref>              Git branch or tag to use with --update
  -p, --purge                     Also remove vci.conf when running --uninstall
EOF
    exit 0
}

global_helps() {
    local name="${1:-luminova}"
    cat <<EOF
Luminova Version Control Interface
Manages versioned deployments of the Luminova PHP framework across a shared
installation directory.

Usage:
  $name <command> [options]
  $name [--help] [--version] [--paths] [--where=<target>]

Commands:
  package     Install, update, switch, list, or remove framework releases
  self        Install, update, or uninstall the VCI script itself

Global options:
  -h, --help              Show this help message (append to a command for command-specific help)
  -v, --version           Show the VCI tool version
      --paths             Print VCI path information
  -w, --where=<target>    Print the resolved path for a specific directory:
                            packages   → packages storage root
                            release    → releases subdirectory
                            current    → active release symlink
                            repo       → temporary repo clone directory
  -ru, --runtime=<mode>   Runtime mode: root | user | auto (default: auto)

Helps:
  '$name package --help'    For package-specific command options.
  '$name self --help'       For VCI self-specific command options.
EOF
    exit 0
}