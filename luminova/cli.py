"""
cli.py — Command-line interface for the Luminova Version Control Interface.

Translates Python argparse arguments into the equivalent luminova.sh flags
and delegates execution to runner.run_or_exit().

Entry point (defined in pyproject.toml):
  [project.scripts]
  luminova = "luminova.cli:main"
"""

from __future__ import annotations

import argparse
import sys

from . import runner


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="luminova",
        description=(
            "Luminova Version Control Interface — manages versioned deployments "
            "of the Luminova PHP framework across a shared installation directory."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  luminova self-install
  luminova self-update
  luminova self-uninstall --purge

  luminova --install
  luminova --install=3.8.0
  luminova --install=3.8.0 --runtime=root --lock-permission=755
  luminova --update=3.9.0
  luminova --update --force

  luminova --switch=3.8.0
  luminova --list
  luminova --current

  luminova --reset
  luminova --reset=3.7.8
  luminova --reset=repo --force
""",
    )

    # ── Positional self-management commands ───────────────────
    parser.add_argument(
        "command",
        nargs="?",
        choices=["self-install", "self-update", "self-uninstall"],
        metavar="COMMAND",
        help="Self-management command: self-install | self-update | self-uninstall",
    )

    # ── Install / update ──
    install_group = parser.add_mutually_exclusive_group()
    install_group.add_argument(
        "-i", "--install",
        nargs="?",
        const="",          # --install with no value → install latest
        metavar="VERSION",
        help="Install a release (omit VERSION to use the latest git tag)",
    )
    install_group.add_argument(
        "-u", "--update",
        nargs="?",
        const="",          # --update with no value → update to latest
        metavar="VERSION",
        help="Update to a release (always rebuilds; bypasses hash check)",
    )

    # ── Switch──────
    parser.add_argument(
        "-s", "--switch",
        metavar="VERSION",
        help="Switch to an already-installed release without rebuilding",
    )

    # ── Query───────
    parser.add_argument(
        "-l", "--list",
        action="store_true",
        help="Show all installed releases",
    )
    parser.add_argument(
        "-c", "--current",
        action="store_true",
        help="Show the currently active release version",
    )

    # ── Reset───────
    parser.add_argument(
        "-r", "--reset",
        nargs="?",
        const="",          # --reset with no value → reset everything
        metavar="TARGET",
        help=(
            "Remove a specific VERSION, the repo clone (repo), "
            "or everything (omit TARGET)"
        ),
    )

    # ── Behavior flags ───
    parser.add_argument(
        "-f", "--force",
        action="store_true",
        help="Force re-clone by removing the existing repo; skip confirmations",
    )
    parser.add_argument(
        "-d", "--delete",
        action="store_true",
        help="Delete repo source files after the build",
    )
    parser.add_argument(
        "-p", "--purge",
        action="store_true",
        help="Purge Luminova data directories on self-uninstall",
    )

    # Permission locking 
    parser.add_argument(
        "-m", "--lock-permission",
        nargs="?",
        const="",          # --lock-permission with no value → use default mode (755)
        metavar="MODE",
        dest="lock_permission",
        help="Lock permissions after deploy (recommended: 755 or 555; default: 755)",
    )

    # Runtime mode
    parser.add_argument(
        "-ru", "--runtime",
        choices=["root", "user", "auto"],
        default=None,
        metavar="MODE",
        help="Runtime user mode: root | user | auto (default: auto)",
    )

    # Branch / tag targeting
    parser.add_argument(
        "-b", "--branch",
        metavar="BRANCH",
        help="Git branch or tag for --install, --update, or self-update",
    )

    # Version
    parser.add_argument(
        "-v", "--version",
        action="store_true",
        help="Show this tool's version",
    )

    return parser


# ── Argument → shell flag translation ─────────────────────────

def _build_shell_args(args: argparse.Namespace) -> list[str]:
    """Convert parsed arguments into luminova.sh CLI flags."""
    flags: list[str] = []

    # Positional self-management commands: "self-install" → --self=install etc.
    if args.command:
        action = args.command.removeprefix("self-")   # "install" | "update" | "uninstall"
        flags.append(f"--self={action}")
        if action == "uninstall" and args.purge:
            flags.append("--purge")
        if args.runtime:
            flags.append(f"--runtime={args.runtime}")
        if args.branch:
            flags.append(f"--branch={args.branch}")
        return flags

    if args.version:
        flags.append("--version")
        return flags

    if args.list:
        flags.append("--list")

    if args.current:
        flags.append("--current")

    # reset: --reset (all) or --reset=<target>
    if args.reset is not None:
        flags.append(f"--reset={args.reset}" if args.reset else "--reset")

    # install
    if args.install is not None:
        flags.append(f"--install={args.install}" if args.install else "--install")

    # update
    if args.update is not None:
        flags.append(f"--update={args.update}" if args.update else "--update")

    # switch
    if args.switch:
        flags.append(f"--switch={args.switch}")

    if args.force:
        flags.append("--force")

    if args.delete:
        flags.append("--delete")

    if args.purge:
        flags.append("--purge")

    # lock-permission: --lock-permission or --lock-permission=<mode>
    if args.lock_permission is not None:
        flags.append(
            f"--lock-permission={args.lock_permission}"
            if args.lock_permission
            else "--lock-permission"
        )

    if args.runtime:
        flags.append(f"--runtime={args.runtime}")

    if args.branch:
        flags.append(f"--branch={args.branch}")

    return flags

def main(argv: list[str] | None = None) -> None:
    """Parse arguments and delegate to luminova.sh via runner."""
    parser = _build_parser()
    args = parser.parse_args(argv)

    # Show help when called with no arguments
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(0)

    shell_args = _build_shell_args(args)

    if not shell_args:
        parser.print_help()
        sys.exit(0)

    runner.run_or_exit(shell_args)


if __name__ == "__main__":
    main()