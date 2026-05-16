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
        epilog=(
            "Run 'luminova package --help' or 'luminova self --help' "
            "for command-specific options."
        ),
    )

    parser.add_argument(
        "-v", "--version",
        action="store_true",
        help="Show the VCI tool version",
    )
    parser.add_argument(
        "--paths",
        action="store_true",
        help="Print VCI path information and exit",
    )
    parser.add_argument(
        "-w", "--where",
        metavar="TARGET",
        choices=["packages", "release", "current", "repo"],
        help=(
            "Print the resolved path for a specific directory: "
            "packages | release | current | repo"
        ),
    )

    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")

    # ── 'package' subcommand ──────────────────────────────────────────────────
    pkg = subparsers.add_parser(
        "package",
        help="Install, update, switch, list, or remove framework releases",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Manage shared Luminova PHP framework releases.",
        epilog="""
Examples:
  luminova package --install
  luminova package --install=3.8.0
  luminova package --install=3.8.0 --runtime=root
  luminova package --install=3.8.0 --path=/etc/luminova/packages
  luminova package --install=3.8.0 --delete
  luminova package --install=3.8.0 --lock
  luminova package --install=3.8.0 --lock-mode=755
  luminova package --update
  luminova package --update=3.9.0
  luminova package --update=3.9.0 --force
  luminova package --switch=3.8.0
  luminova package --list
  luminova package --current
  luminova package --remove
  luminova package --remove=3.7.8
  luminova package --remove=repo
""",
    )

    pkg_action = pkg.add_mutually_exclusive_group()
    pkg_action.add_argument(
        "-i", "--install",
        nargs="?",
        const="",
        metavar="VERSION",
        help="Install a release (omit VERSION to use the latest git tag)",
    )
    pkg_action.add_argument(
        "-u", "--update",
        nargs="?",
        const="",
        metavar="VERSION",
        help="Rebuild a release; always bypasses the hash check",
    )
    pkg_action.add_argument(
        "-s", "--switch",
        metavar="VERSION",
        help="Switch to an already-installed release without rebuilding",
    )
    pkg_action.add_argument(
        "-l", "--list",
        action="store_true",
        help="List all installed releases",
    )
    pkg_action.add_argument(
        "-c", "--current",
        action="store_true",
        help="Show the currently active release",
    )
    pkg_action.add_argument(
        "-r", "--remove",
        nargs="?",
        const="",
        metavar="TARGET",
        help=(
            "Remove a specific release (e.g. --remove=3.8.0), only the "
            "repo clone (--remove=repo), or all releases (--remove)"
        ),
    )

    pkg.add_argument(
        "-b", "--branch",
        metavar="REF",
        help="Git branch or tag to use with --install or --update",
    )
    pkg.add_argument(
        "--path",
        metavar="DIR",
        help="Override the default packages storage directory",
    )
    pkg.add_argument(
        "-ru", "--runtime",
        choices=["root", "user", "auto"],
        default=None,
        metavar="MODE",
        help="Runtime mode: root | user | auto (default: auto)",
    )
    pkg.add_argument(
        "-f", "--force",
        action="store_true",
        help=(
            "Delete the existing repo clone and re-clone from scratch; "
            "also disables the hash check for that run"
        ),
    )
    pkg.add_argument(
        "-d", "--delete",
        action="store_true",
        help="Remove repo source files after building",
    )

    # Lock flags — three distinct bash options preserved as three Python flags
    pkg.add_argument(
        "--lock",
        action="store_true",
        help="Lock packages directory permissions after deploy (default mode: 755)",
    )
    pkg.add_argument(
        "-m", "--mode",
        metavar="MODE",
        dest="mode",
        help="Set a specific permission mode when locking (e.g. 755, 555)",
    )
    pkg.add_argument(
        "--lock-mode",
        metavar="MODE",
        dest="lock_mode",
        help="Equivalent to --lock with an explicit mode value",
    )

    # ── 'self' subcommand ─────────────────────────────────────────────────────
    slf = subparsers.add_parser(
        "self",
        help="Install, update, or uninstall the VCI script itself",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Manage the Luminova VCI script itself.",
        epilog="""
Examples:
  luminova self --install
  luminova self --update
  luminova self --update --branch=v2.1.0
  luminova self --uninstall
  luminova self --uninstall --purge
""",
    )

    slf_action = slf.add_mutually_exclusive_group()
    slf_action.add_argument(
        "-i", "--install",
        action="store_true",
        help="Install this script as 'luminova' in PATH",
    )
    slf_action.add_argument(
        "-u", "--update",
        nargs="?",
        const="",
        metavar="VERSION",
        help="Replace the installed binary with the latest from GitHub",
    )
    slf_action.add_argument(
        "-ui", "--uninstall",
        action="store_true",
        help="Remove the installed 'luminova' binary or main installation",
    )

    slf.add_argument(
        "-b", "--branch",
        metavar="REF",
        help="Git branch or tag to use with --update",
    )
    slf.add_argument(
        "-ru", "--runtime",
        choices=["root", "user", "auto"],
        default=None,
        metavar="MODE",
        help="Runtime mode: root | user | auto (default: auto)",
    )
    slf.add_argument(
        "-p", "--purge",
        action="store_true",
        help="Also remove vci.conf when running --uninstall",
    )

    return parser


# ── Argument → shell flag translation ─────────────────────────────────────────

def _self_commands(args: argparse.Namespace, flags: list[str]) -> list[str]:
    flags.append("self")

    if args.install:
        flags.append("--install")
    elif args.update is not None:
        flags.append(f"--update={args.update}" if args.update else "--update")
    elif args.uninstall:
        flags.append("--uninstall")

    if args.uninstall and args.purge:
        flags.append("--purge")

    if args.runtime:
        flags.append(f"--runtime={args.runtime}")

    if args.branch:
        flags.append(f"--branch={args.branch}")

    return flags


def _package_commands(args: argparse.Namespace, flags: list[str]) -> list[str]:
    flags.append("package")

    if args.path:
        flags.append(f"--path={args.path}")

    if args.install is not None:
        flags.append(f"--install={args.install}" if args.install else "--install")
    elif args.update is not None:
        flags.append(f"--update={args.update}" if args.update else "--update")
    elif args.switch:
        flags.append(f"--switch={args.switch}")
    elif args.list:
        flags.append("--list")
    elif args.current:
        flags.append("--current")
    elif args.remove is not None:
        flags.append(f"--remove={args.remove}" if args.remove else "--remove")

    if args.branch:
        flags.append(f"--branch={args.branch}")
    if args.runtime:
        flags.append(f"--runtime={args.runtime}")
    if args.force:
        flags.append("--force")
    if args.delete:
        flags.append("--delete")

    if args.lock_mode:
        flags.append(f"--lock-mode={args.lock_mode}")
    elif args.mode:
        flags.append(f"--mode={args.mode}")
    elif args.lock:
        flags.append("--lock")

    return flags


def _build_shell_args(args: argparse.Namespace) -> list[str]:
    """Convert parsed arguments into luminova.sh CLI flags."""

    # ── Global informational flags ────────────────────────────
    if getattr(args, "version", False):
        return ["--version"]

    if getattr(args, "paths", False):
        return ["--paths"]

    if getattr(args, "where", None):
        return [f"--where={args.where}"]

    flags: list[str] = []

    # ── Subcommands ───────────────────────────────────────────
    if args.command == "self":
        return _self_commands(args, flags)

    if args.command == "package":
        return _package_commands(args, flags)

    return flags


def main(argv: list[str] | None = None) -> None:
    """Parse arguments and delegate to luminova.sh via runner."""
    parser = _build_parser()
    args = parser.parse_args(argv)

    # Show top-level help when called with no arguments
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