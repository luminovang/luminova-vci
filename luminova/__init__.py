"""
luminova — Python wrapper for the Luminova Version Control Interface.

Provides a CLI entry point and a programmatic API for running luminova.sh
from Python code or build pipelines.

Typical usage
-------------
Command line (after pip install):
    luminova package --install=3.8.0
    luminova package --list
    luminova self --update

Programmatic:
    from luminova import runner
    exit_code = runner.run(["package", "--install=3.8.0", "--runtime=user"])
"""

__version__ = "1.3.0"
__author__ = "Luminova"
__license__ = "MIT"

__all__ = ["runner", "cli"]