# PHP Luminova — Shared Module Deployment Guide

A step-by-step guide to installing, managing, and switching Luminova framework releases on your server using `luminova.sh` or the `luminova` Python CLI.

---

## What does this tool do?

Instead of bundling the Luminova framework inside every project, this tool installs it **once** into a shared directory (e.g. `/opt/luminova/packages`). Each PHP project then points to that shared installation. This means:

- Update the framework in one place and all projects benefit immediately.
- Install multiple versions side-by-side and switch between them without downtime.
- Roll back to a previous version in seconds.

---

## Installation

### Install via pip (Python CLI wrapper)

```bash
pip install git+https://github.com/luminovang/luminova-vci.git
```

Or pin to a specific release:

```bash
pip install git+https://github.com/luminovang/luminova-vci.git@v2.0.0
```

After installation the `luminova` command is available in your shell.

### Install as a system command (shell only)

Upload `luminova.sh` to your server, make it executable, then install it:

```bash
scp luminova.sh user@your-server:/opt/luminova/luminova.sh
ssh user@your-server
chmod +x /opt/luminova/luminova.sh
sudo /opt/luminova/luminova.sh self-install
```

This symlinks the script to `/usr/local/bin/luminova` so you can run `luminova` from anywhere.

---

## Before you begin

**Requirements on your server:**

| Tool | Purpose |
|------|---------|
| `bash` 4+ | Run the script |
| `git` | Clone the framework source |
| `rsync` | Build release directories |
| `sha256sum` or `shasum` | Detect changes between builds |
| `sudo` / `root` | Write to `/opt/` and lock permissions |

Check availability:

```bash
git --version && rsync --version && sha256sum --version
```

---

## Directory structure

The script manages this layout automatically:

```
/opt/luminova/
    luminova.sh               ← deployment script
    packages/
        repo/               ← temporary git clone (build source)
        releases/
            3.8.0/          ← a built release
            3.9.0/          ← another built release
        current ->          ← symlink to the active release
```

PHP projects reference `packages/current/`, so switching versions updates only the symlink — no file copying required.

---

## Step 1 — Upload and prepare the script

```bash
scp luminova.sh user@your-server:/opt/luminova/luminova.sh
ssh user@your-server
chmod +x /opt/luminova/luminova.sh
cd /opt/luminova
```

---

## Step 2 — Install a release

Install a specific version:

```bash
sudo ./luminova.sh --install=3.8.0
```

Install the **latest** version (auto-detected from git tags):

```bash
sudo ./luminova.sh --install
```

What happens during install:
1. Clones the framework source from GitHub into `packages/repo/`
2. Builds the release into `packages/releases/3.8.0/`
3. Points `packages/current` at the new release
4. Records a content hash to avoid redundant rebuilds on the next run

> **Tip:** Running the same install command twice with no source changes is safe — the script detects this via hash comparison and skips the rebuild automatically.

---

## Step 3 — Configure your PHP project

Add a `.luminova.php` file to the root of each project:

```php
<?php
// /.luminova.php
return [
    /*
     | Enable shared framework resolution.
     */
    'resolve.paths' => true,

    /*
     | Autoloader strategy:
     |   'auto'     → prefer Composer, fall back to Luminova's own loader
     |   'composer' → Composer only
     |   'luminova' → Luminova's loader only
     */
    'resolve.autoloader' => 'auto',

    /*
     | Minimum required framework version.
     */
    'luminova.version' => '>=3.8',

    /*
     | Paths to the shared framework directories.
     | 'current' always resolves to the active symlink.
     */
    'luminova.paths' => [
        'root'      => '/opt/luminova/packages',
        'system'    => '/opt/luminova/packages/current/system',
        'bootstrap' => '/opt/luminova/packages/current/bootstrap',
    ],
];
```

To pin a project to a **specific version** rather than always following `current`:

```php
'system'    => '/opt/luminova/packages/releases/3.8.0/system',
'bootstrap' => '/opt/luminova/packages/releases/3.8.0/bootstrap',
```

---

## Common commands

### See all installed releases

```bash
sudo ./luminova.sh --list
```

Example output:
```
Installed releases:
  3.7.8
  3.8.0  ← active
  3.9.0
```

### Check which version is active

```bash
sudo ./luminova.sh --current
```

### Switch to a different installed release (instant, no rebuild)

```bash
sudo ./luminova.sh --switch=3.9.0
```

Only works if the target version is already installed. Updates the symlink only — no files are copied.

### Update to the latest version

```bash
sudo ./luminova.sh --update
```

Or update to a specific version:

```bash
sudo ./luminova.sh --update=3.9.0
```

---

## Advanced options

### Force a fresh clone

Use `--force` if the local repo clone is corrupted or you want to start from scratch:

```bash
sudo ./luminova.sh --install=3.8.0 --force
```

Deletes the `repo/` directory and re-clones. Also disables the hash check for that run.

### Clean up source files after build

The `repo/` directory is only needed during the build. Use `--delete` to remove its contents afterwards (`.git` is kept so future pulls are fast):

```bash
sudo ./luminova.sh --install=3.8.0 --delete
```

### Lock permissions after deploy

For production servers, lock the packages directory so only `root` can modify it:

```bash
sudo ./luminova.sh --install=3.8.0 --lock-permission
```

Default mode is `755`. For a stricter `555` (read + execute only):

```bash
sudo ./luminova.sh --install=3.8.0 --lock-permission=555
```

---

## Removing releases

### Remove a specific version

```bash
sudo ./luminova.sh --reset=3.7.8
```

If the removed version was active, the script automatically promotes the next latest release.

### Remove the repo clone only (free up disk space)

```bash
sudo ./luminova.sh --reset=repo
```

Does not touch `releases/` or `current`.

### Full reset (remove everything)

```bash
sudo ./luminova.sh --reset
```

⚠️ Warning
Removes all releases, the repo clone, and the active symlink. 
Prompts for confirmation unless `--force` is also passed.

### Skip the confirmation prompt

```bash
sudo ./luminova.sh --reset --force
sudo ./luminova.sh --reset=3.7.8 --force
```

---

## Rollback procedure

```bash
# Check what's installed
sudo ./luminova.sh --list

# Switch back to the previous working version
sudo ./luminova.sh --switch=3.8.0
```

No rebuild required. Projects resume using `3.8.0` immediately.

---

## Self-management

### Install as a global command

```bash
sudo ./luminova.sh self-install          # installs to /usr/local/bin/luminova
./luminova.sh self-install               # installs to ~/.local/bin/luminova
```

### Update the installed script from GitHub

```bash
sudo luminova self-update
```

### Uninstall

```bash
sudo luminova self-uninstall             # remove binary only
sudo luminova self-uninstall --purge     # remove binary + all data directories
```

---

## Python API

```python
from luminova import runner

# Run a command programmatically
exit_code = runner.run(["--install=3.8.0", "--runtime=user"])

# Or let it call sys.exit automatically
runner.run_or_exit(["--list"])

# Enable bash xtrace for debugging
runner.run(["--install"], env={"DEBUG": "1"})
```

---

## Reference: all options

| Flag | Description |
|------|-------------|
| `--help` | Show usage summary |
| `--version` | Show the deploy tool version |
| `--list` | List all installed releases |
| `--current` | Show the active release |
| `--install[=<version>]` | Install a release (omit version to use latest tag) |
| `--update[=<version>]` | Update to a release (always rebuilds) |
| `--switch=<version>` | Activate an already-installed release without rebuilding |
| `--reset` | Remove all releases, repo, and symlink |
| `--reset=<version>` | Remove one release (or `repo` to remove the clone only) |
| `--force` | Skip confirmation prompts; force re-clone on install |
| `--delete` | Remove repo source files after building |
| `--lock-permission[=<mode>]` | Lock packages dir to `root:root` with given mode (default `755`) |
| `--runtime=<mode>` | Runtime user mode: `root` \| `user` \| `auto` |
| `--purge` | Purge Luminova data directories on `self-uninstall` |

---

## Troubleshooting

**"Release not found" when switching**
The version isn't in `releases/`. Run `--list` to see what's installed, then `--install=<version>` if missing.

**Build fails with "Source directory not found"**
The repo clone failed or was deleted. Re-clone with:
```bash
sudo ./luminova.sh --install=3.8.0 --force
```

**"No changes detected" but you expect a rebuild**
The hash from the previous build matches the current source. Use `--update` (or `--force`) to bypass the hash check:
```bash
sudo ./luminova.sh --update=3.8.0
```

**Active symlink is broken after a crash**
```bash
sudo rm /opt/luminova/packages/current
sudo ./luminova.sh --switch=3.8.0
```

**Permission errors when running the script**
Most operations writing to `/opt/` require root. Prefix with `sudo`.

**Repo cloned on the wrong branch**
Use `--force` to discard the existing clone and re-clone cleanly:
```bash
sudo ./luminova.sh --install=3.8.0 --force
```