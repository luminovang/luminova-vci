#!/usr/bin/env bash

print_luminova_helps() {
    local name="${SELF_NAME:-$(_self_name "$SELF")}"
    cat <<EOF
Luminova Version Control Interface
Manages versioned deployments of the Luminova PHP framework modules
across a shared installation directory.

Usage:
  $name [options]       

Install or update a release:
  $name --install
  $name --install=3.8.0 --runtime=root
  $name --update=3.9.0
  $name --install=3.8.0 --delete
  $name --install=3.8.0 --lock-permission
  $name --install=3.8.0 --lock-permission=755

Switch to an existing release (no rebuild):
  $name --switch=3.8.0

List and inspect releases:
  $name --list
  $name --current

Options:
  -h, --help                    Show this help message
  --self=<action>               Manage Luminova VCI script (actions: update | install | uninstall)
                                  install              Install this script as 'luminova' in PATH
                                  update               Replace installed 'luminova' with the latest from git
                                  uninstall            Remove 'luminova' from its installed location
  -l, --list                    Show all available releases
  -v, --version                 Show this tool's version
  -b, --branch=<version>        Specify git branch or tag for --install, --update, or --self=update
  -c, --current                 Show the currently active release version
  --paths                       Print the VCI script directory and exit
  --path=<dir>                  Override the default packages storage directory
  -i, --install[=<version>]     Install a version (default: latest from git tags)
  -u, --update[=<version>]      Update to a version (always rebuilds, bypasses hash check)
  -f, --force                   Force re-clone by removing the existing repo
  -p, --purge                   Purge Luminova module configuration on uninstall
  -ru, --runtime[=<mode>]       Runtime user mode: root | user | auto (default: auto)
  -s, --switch=<version>        Switch to an installed release without rebuilding (request: installed version)
  -d, --delete                  Delete source files from repo dir after building
  -m, --lock-permission[=<mode>]
                                Lock permissions after deploy (recommended: 755 or 555)
  -r, --reset[=<target>]        Remove a specific version (--reset=3.8.0), the repo clone
                                (--reset=repo), or everything (--reset)
  -w, --where[=<target>]        Find path to (packages | releases | repo)

Directory structure:
  packages/
    repo/        → Cloned git source (temporary build directory)
    releases/    → One subdirectory per installed version
    current →    → Symlink pointing to the active release

Notes:
  - Version is auto-detected from git tags when not specified.
  - --switch only works with already-installed releases.
  - Use --force to discard and re-clone the source repo.
  - Use --update with --force to force a rebuild even if content is unchanged.
EOF
    exit 0
}