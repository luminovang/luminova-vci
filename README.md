![PHP Luminova VCI](https://github.com/luminovang/vci-admin/blob/main/logo.svg?v=2)

# PHP Luminova — Version Control Interface (VCI)

A lightweight tool for managing shared Luminova PHP framework installations across one or more
projects on a single server.

---

## What problem does this solve?

Normally, each PHP project carries its own copy of the Luminova framework. That means:

- The same files duplicated across every project
- Framework updates applied one project at a time
- No easy way to roll back if an update breaks something

**Luminova VCI solves this by installing the framework once** into a shared directory. Every
project points to that shared copy. When you update or switch versions, all projects follow
immediately — no per-project changes needed.

Think of it like a PHP version manager (e.g. `phpenv`), but for the Luminova framework itself.

---

## How it works

```
/opt/luminova/packages/
    releases/
        3.8.0/      ← a full framework build
        3.9.0/      ← another build
    current  →      ← symlink pointing to the active release
```

Your PHP projects reference `packages/current/`. When you run `package --switch=3.9.0`, only
the symlink changes. No files are copied, no projects need to be restarted.

A `vci.conf` file records the VCI binary location and packages directory. A future VCI
switcher UI will use this file to manage versions without shell access.

---

## Requirements

| Tool | Purpose |
|------|---------|
| `bash` 4+ | Runs the VCI script |
| `git` | Clones the framework source |
| `rsync` | Builds release directories |
| `sha256sum` or `shasum` | Detects unchanged builds (skips unnecessary rebuilds) |
| `sudo` / root access | Writes to `/opt/` and locks permissions |

Verify everything is available before you start:

```bash
bash --version && git --version && rsync --version && sha256sum --version
```

---

## Installation

There are two ways to install the VCI: via **Git clone** (shell-only) or via **pip** (adds a
Python CLI wrapper). Choose the one that fits your workflow.

---

### Option A — Git clone (recommended for servers)

```bash
# SSH into your server
ssh user@your-server

# Create the installation directory
sudo mkdir -p /opt/luminova

# Clone the VCI into it
sudo git clone https://github.com/luminovang/vci.git /opt/luminova

# Make the script executable
sudo chmod +x /opt/luminova/luminova.sh

# Register it as a global command (so you can run 'luminova' from anywhere)
sudo /opt/luminova/luminova.sh self --install
```

After the last step, the `luminova` command is available system-wide.

> **User-mode install (no root required)**
> Drop `sudo` from the commands above and use `--runtime=user`. The script will install to
> `~/.local/bin/luminova` instead of `/usr/local/bin/luminova`.

---

### Option B — pip (Python CLI wrapper)

If you prefer Python tooling or want to use the VCI inside build pipelines:

```bash
pip install git+https://github.com/luminovang/vci.git
```

Pin to a specific version:

```bash
pip install git+https://github.com/luminovang/vci.git@v2.1.0
```

The `luminova` command installed by pip accepts all the same flags as the shell script. See
[Python usage](#python-api) for programmatic access.

---

### Option C — manual upload (shared hosting)

If you cannot clone directly on the server, upload the files from your local machine first:

```bash
scp -r /path/to/vci/. user@your-server:/opt/luminova/
```

Then SSH in and follow the steps from Option A starting at `chmod +x`.

---

## Directory structure

After installation, your directory will look like this:

```
/opt/luminova/
    luminova.sh               ← main VCI script
    lib/                      ← internal modules (do not edit)
    packages/
        repo/                 ← temporary git clone used during builds
        releases/
            3.8.0/            ← built release
            3.9.0/            ← another built release
        current  →            ← symlink to the active release
```

`vci.conf` is saved to the first writable location found in this order:

```
/etc/luminova/
/var/lib/luminova/
~/.config/.luminova/
~/.local/share/.luminova/
~/.luminova/
```

---

## Installing a framework release

Once the VCI itself is installed, use it to install Luminova framework versions.

**Install the latest version** (auto-detected from git tags):

```bash
sudo luminova package --install
```

**Install a specific version:**

```bash
sudo luminova package --install=3.8.0
```

What happens during install:

1. The framework source is cloned from [GitHub](https://github.com/luminovang/framework) into `packages/repo/`
2. The requested version is checked out and built into `packages/releases/3.8.0/`
3. `packages/current` is updated to point at the new release
4. A content hash is saved so identical rebuilds are skipped automatically
5. `vci.conf` is written with the binary path and packages directory

> **Running the same install command twice is safe.**
> The VCI compares content hashes and skips the rebuild if nothing has changed. Use
> `--update` or `--force` when you need to override this.

---

## Configuring your PHP project

Add a `.luminova.php` file to the root of each project. This tells the framework where to find
the shared installation.

```php
<?php
// .luminova.php (project root)
return [

    // Enable shared framework resolution
    'resolve.paths' => true,

    // Autoloader strategy:
    //   'auto'     → prefer Composer, fall back to Luminova's own loader
    //   'composer' → Composer only
    //   'luminova' → Luminova's loader only
    'resolve.autoloader' => 'auto',

    // Minimum required framework version
    'luminova.version' => '>=3.8',

    // Paths to the shared framework
    // 'current' always follows the active symlink
    'luminova.paths' => [
        'root'      => '/opt/luminova/packages',
        'target'    => '/opt/luminova/packages/current',
    ],
];
```

**To pin a project to a specific version** instead of always following `current`:

```php
'target' => '/opt/luminova/packages/releases/3.8.0',
```

---

## Common commands

### List all installed releases

```bash
sudo luminova package --list
```

Example output:

```
Installed releases:
  3.7.8
  3.8.0  ← active
  3.9.0
```

### Check the active version

```bash
sudo luminova package --current
```

### Switch to a different release (instant, no rebuild)

```bash
sudo luminova package --switch=3.9.0
```

This only works if the target version is already installed. Only the symlink is updated — no
files are copied or rebuilt.

### Update to the latest version

```bash
sudo luminova package --update
```

Or update to a specific version:

```bash
sudo luminova package --update=3.9.0
```

`--update` always rebuilds from source and bypasses the hash check. Use it when you want to
force reinstallation of a version that is already present.

### Roll back to a previous version

```bash
# See what is installed
sudo luminova package --list

# Switch back
sudo luminova package --switch=3.8.0
```

No rebuild needed. Projects resume using `3.8.0` immediately.

---

## Advanced options

### Install from a specific git branch

```bash
sudo luminova package --install --branch=develop
sudo luminova package --install=3.8.0 --branch=hotfix/3.8.x
```

When combined with `--install=<version>`, the tag is checked out within that branch. When used
with `--install` alone, the latest tag on that branch is auto-detected.

### Change the packages directory

By default, packages are stored in `packages/` next to `luminova.sh`. Override this with
`--path`:

```bash
sudo luminova package --install=3.8.0 --path=/srv/luminova/shared
```

Print the current VCI script directory and configured paths:

```bash
luminova --paths
```

Print the path to a specific directory:

```bash
luminova --where=packages
luminova --where=release
luminova --where=current
luminova --where=repo
```

### Force a fresh clone

Use `--force` when the local repo clone is corrupted or you want a clean start:

```bash
sudo luminova package --install=3.8.0 --force
```

This deletes the `repo/` directory and re-clones from scratch. It also disables the hash check
for that run.

### Remove the repo after building

`repo/` is only needed during the build. Use `--delete` to remove it afterwards:

```bash
sudo luminova package --install=3.8.0 --delete
```

The `.git` folder is preserved so future updates are incremental rather than full re-clones.

### Lock file permissions

On production servers, restrict the packages directory so only root can modify it:

```bash
# Default mode (755) — recommended for most setups
sudo luminova package --install=3.8.0 --lock

# Stricter mode (555) — read and execute only, no writes even for root
sudo luminova package --install=3.8.0 --lock --mode=555

# Equivalent long form with an explicit mode
sudo luminova package --install=3.8.0 --lock-mode=555
```

---

## Removing releases

### Remove a specific version

```bash
sudo luminova package --remove=3.7.8
```

If the removed version was active, the VCI automatically promotes the next latest installed
release and updates the symlink.

### Free up disk space (remove the repo clone only)

```bash
sudo luminova package --remove=repo
```

This removes the temporary `repo/` directory but does not touch `releases/` or `current`.

### Full reset — remove everything

```bash
sudo luminova package --remove
```

> ⚠️ **Warning:**
> This removes all releases, the repo clone, and the active symlink.
> The script will ask for confirmation before proceeding.

### Skip the confirmation prompt

```bash
sudo luminova package --remove --force
sudo luminova package --remove=3.7.8 --force
```

---

## Self-management

These commands manage the `luminova` VCI binary itself — not the framework packages.

### Install as a global command

```bash
# System-wide (requires root) → /usr/local/bin/luminova
sudo ./luminova.sh self --install

# User-space (no root needed) → ~/.local/bin/luminova
./luminova.sh self --install --runtime=user
```

A symlink is created so that changes to `luminova.sh` are reflected immediately. If the
filesystem does not support symlinks, a plain copy is made instead.

### Update the VCI script from GitHub

```bash
# Update to the latest version
sudo luminova self --update

# Update to a specific tag
sudo luminova self --update --branch=v2.1.0
```

The update process downloads to an isolated temp directory, validates the new script syntax
with `bash -n`, compares version strings, and only then replaces the installed binary.

### Uninstall the VCI script

```bash
# Remove the binary only
sudo luminova self --uninstall

# Remove the binary and vci.conf
sudo luminova self --uninstall --purge
```

---

## Python API

The `luminova` Python package provides a thin programmatic interface for build pipelines and
deployment scripts.

```python
from luminova import runner

# Returns the shell exit code
exit_code = runner.run(["package", "--install=3.8.0", "--runtime=user"])

# Install from a branch
runner.run(["package", "--install", "--branch=develop"])

# Exit automatically if the command fails
runner.run_or_exit(["package", "--list"])

# Enable bash xtrace for debugging
runner.run(["package", "--install"], env={"DEBUG": "1"})
```

### Python CLI examples

```bash
# Self-management
luminova self --install
luminova self --update
luminova self --update --branch=v2.1.0
luminova self --uninstall --purge

# Installing and updating
luminova package --install
luminova package --install=3.8.0
luminova package --install=3.8.0 --runtime=root --lock-mode=755
luminova package --install --branch=develop
luminova package --update=3.9.0
luminova package --update --force

# Switching and inspecting
luminova package --switch=3.8.0
luminova package --list
luminova package --current

# Cleanup
luminova package --remove
luminova package --remove=3.7.8
luminova package --remove=repo --force
```

---

## All options reference

### Global options

| Flag | Short | Description |
|------|-------|-------------|
| `--help` | `-h` | Show usage summary |
| `--version` | `-v` | Show the VCI tool version |
| `--paths` | | Print VCI path information and exit |
| `--where=<target>` | `-w` | Print the path for `packages`, `release`, `current`, or `repo` |

### `package` subcommand

| Flag | Short | Description |
|------|-------|-------------|
| `--install[=<version>]` | `-i` | Install a release (omit version for latest git tag) |
| `--update[=<version>]` | `-u` | Rebuild a release — always bypasses the hash check |
| `--switch=<version>` | `-s` | Activate an already-installed release without rebuilding |
| `--list` | `-l` | List all installed releases |
| `--current` | `-c` | Show the active release |
| `--remove[=<target>]` | `-r` | Remove a specific release, the repo clone (`repo`), or all releases |
| `--branch=<ref>` | `-b` | Git branch or tag for `--install` or `--update` |
| `--path=<dir>` | | Override the default packages storage directory |
| `--runtime=<mode>` | `-ru` | Runtime mode: `root` \| `user` \| `auto` (default: `auto`) |
| `--force` | `-f` | Re-clone from scratch; disables the hash check for that run |
| `--delete` | `-d` | Remove repo source files after building |
| `--lock` | | Lock packages directory permissions after deploy (default mode: `755`) |
| `--mode=<mode>` | `-m` | Set a specific permission mode with `--lock` (e.g. `755`, `555`) |
| `--lock-mode=<mode>` | | Equivalent to `--lock` with an explicit mode value |

### `self` subcommand

| Flag | Short | Description |
|------|-------|-------------|
| `--install` | `-i` | Install this script as `luminova` in PATH |
| `--update[=<version>]` | `-u` | Replace the installed binary with the latest from GitHub |
| `--uninstall` | `-ui` | Remove the installed `luminova` binary |
| `--branch=<ref>` | `-b` | Git branch or tag to use with `--update` |
| `--runtime=<mode>` | `-ru` | Runtime mode: `root` \| `user` \| `auto` (default: `auto`) |
| `--purge` | `-p` | Also remove `vci.conf` when running `--uninstall` |

---

## Troubleshooting

**"Release not found" when switching**

The version is not in `releases/`. Run `--list` to see what is installed:

```bash
sudo luminova package --list
sudo luminova package --install=3.9.0   # install it if missing
```

---

**Build fails with "Source directory not found"**

The repo clone failed or was removed. Force a clean re-clone:

```bash
sudo luminova package --install=3.8.0 --force
```

---

**"No changes detected" but you expect a rebuild**

The content hash from the previous build matches the source. Use `--update` to bypass it:

```bash
sudo luminova package --update=3.8.0
```

---

**Active symlink is broken after a crash**

An interrupted build may have left a partial release without a hash file. The VCI cleans these
up automatically on the next run. If `current` is also broken, restore it manually:

```bash
sudo rm /opt/luminova/packages/current
sudo luminova package --switch=3.8.0
```

---

**Permission errors when running the script**

Operations that write to `/opt/` require root. Add `sudo`, or use `--runtime=user` to work in
user space (`~/.local/`):

```bash
sudo luminova package --install=3.8.0
# or
luminova package --install=3.8.0 --runtime=user
```

---

**Repo was cloned from the wrong branch**

Discard the existing clone and start fresh:

```bash
sudo luminova package --install=3.8.0 --branch=hotfix/3.8.x --force
```

---

**`self --update` does not apply the update**

If the binary is in `/usr/local/bin/`, writing to it requires root:

```bash
sudo luminova self --update
```