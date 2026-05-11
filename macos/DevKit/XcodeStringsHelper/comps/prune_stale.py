#!/usr/bin/env python3
"""
Remove stale strings from an xcstrings file.

Stale strings are entries marked with extractionState="stale",
meaning they are no longer referenced in the source code.

Usage:
    python prune_stale.py <path_to_xcstrings>
    python prune_stale.py <path> --dry-run

Exit codes:
    0 - Success (or no stale strings found)
    1 - Error
"""

import argparse
import sys

from .xcstrings import XCStrings, find_stale, prune_stale, truncate


def main() -> int:
    parser = argparse.ArgumentParser(description="Remove stale strings from xcstrings")
    parser.add_argument("path", help="Path to .xcstrings file")
    parser.add_argument("--dry-run", "-n", action="store_true", help="Show what would be removed")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show all removed keys")
    args = parser.parse_args()

    xc = XCStrings.load(args.path)

    if args.dry_run:
        stale = find_stale(xc)
        if not stale:
            print("No stale strings found.")
            return 0

        print(f"[DRY RUN] Would remove {len(stale)} stale strings:")
        for key in stale:
            print(f"  - {truncate(key, 70)}")
        return 0

    removed = prune_stale(xc)

    if not removed:
        print("No stale strings found.")
        return 0

    xc.save()

    print(f"Removed {len(removed)} stale strings from {xc.path}")

    if args.verbose:
        print()
        for key in removed:
            print(f"  - {truncate(key, 70)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
