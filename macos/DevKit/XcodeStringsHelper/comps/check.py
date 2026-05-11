#!/usr/bin/env python3
"""
Check translation completeness in an xcstrings file.

Usage:
    python check.py <path_to_xcstrings>
    python check.py  # Uses default path if configured

Exit codes:
    0 - All translations complete
    1 - Found incomplete translations
"""

import argparse
import sys
from pathlib import Path

from .xcstrings import XCStrings, find_incomplete, find_stale, truncate


def main() -> int:
    parser = argparse.ArgumentParser(description="Check xcstrings translation completeness")
    parser.add_argument("path", nargs="?", help="Path to .xcstrings file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show all issues")
    args = parser.parse_args()

    if not args.path:
        print("Usage: python check.py <path_to_xcstrings>", file=sys.stderr)
        return 1

    xc = XCStrings.load(args.path)

    # Report stale entries
    stale = find_stale(xc)
    if stale:
        print(f"Found {len(stale)} stale entries (use prune_stale.py to remove)")

    # Report incomplete entries
    incomplete = find_incomplete(xc)

    languages = sorted(xc.languages())
    total = len(xc.translatable_entries())

    print(f"File: {xc.path}")
    print(f"Languages: {', '.join(languages)}")
    print(f"Total strings: {total}")
    print()

    if not incomplete:
        print("All translations are complete.")
        return 0

    print(f"Found {len(incomplete)} incomplete translations:")
    print("-" * 70)

    for entry in incomplete:
        key_display = truncate(entry.key, 40)
        print(f"  {key_display}")
        print(f"    [{entry.language}] {entry.reason}")

    return 1


if __name__ == "__main__":
    sys.exit(main())
