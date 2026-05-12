"""
luminova — Python wrapper for the Luminova Version Control Interface.

Provides a CLI entry point and a programmatic API for running luminova.sh
from Python code or build pipelines.

Typical usage
-------------
Command line (after pip install):
    luminova --install=3.8.0
    luminova --list
    luminova self-update

Programmatic:
    from luminova import runner
    exit_code = runner.run(["--install=3.8.0", "--runtime=user"])
"""

__version__ = "2.1.0"
__author__ = "Luminova"
__license__ = "MIT"

__all__ = ["runner", "cli"]