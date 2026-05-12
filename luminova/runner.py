"""
runner.py — Low-level subprocess executor for luminova.sh.

Responsible for:
  - Locating the luminova.sh script relative to this package
  - Executing it via bash with the supplied argument list
  - Streaming stdout/stderr live (no buffering)
  - Passing the shell exit code back to the caller
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

# luminova.sh lives one level above the luminova/ Python package directory
_SCRIPT_NAME = "luminova.sh"
_PACKAGE_DIR = Path(__file__).resolve().parent
_SCRIPT_PATH = _PACKAGE_DIR.parent / _SCRIPT_NAME


def _find_script() -> Path:
    """Return the absolute path to luminova.sh, raising if it is missing."""
    if not _SCRIPT_PATH.exists():
        raise FileNotFoundError(
            f"luminova.sh not found at expected location: {_SCRIPT_PATH}\n"
            "Re-install the package or run from the repository root."
        )
    return _SCRIPT_PATH


def run(args: list[str], *, env: dict[str, str] | None = None) -> int:
    """
    Execute luminova.sh with *args* and return its exit code.

    Parameters
    ----------
    args:
        Command-line arguments forwarded verbatim to luminova.sh.
    env:
        Optional environment overrides merged on top of the current process
        environment.  Pass ``{"DEBUG": "1"}`` to enable bash xtrace.

    Returns
    -------
    int
        The exit code produced by the shell script (0 = success).

    Raises
    ------
    FileNotFoundError
        If luminova.sh cannot be located.
    """
    script = _find_script()

    merged_env = {**os.environ, **(env or {})}

    cmd = ["bash", str(script)] + [str(a) for a in args]

    try:
        result = subprocess.run(cmd, env=merged_env)
        return result.returncode
    except KeyboardInterrupt:
        # Let Ctrl-C exit cleanly without a traceback
        return 130


def run_or_exit(args: list[str], *, env: dict[str, str] | None = None) -> None:
    """
    Execute luminova.sh and call ``sys.exit`` with the resulting exit code.

    Convenience wrapper used by the CLI entry point so that the Python
    process mirrors the shell script's exit behavior exactly.
    """
    code = run(args, env=env)
    if code != 0:
        sys.exit(code)