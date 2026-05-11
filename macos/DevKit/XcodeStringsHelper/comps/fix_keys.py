#!/usr/bin/env python3
"""
Fix inconsistent keys in an xcstrings file.

This script finds entries where the key doesn't match the English
translation value, and updates the key to match.

Usage:
    python fix_keys.py <path_to_xcstrings>
    python fix_keys.py <path> --dry-run
    python fix_keys.py <path> --find-only

Exit codes:
    0 - Success (or no inconsistent keys found)
    1 - Error or found inconsistent keys (with --find-only)
"""

import argparse
import json
import sys

from .xcstrings import XCStrings, find_inconsistent_keys, fix_inconsistent_keys, truncate


def main() -> int:
    parser = argparse.ArgumentParser(description="Fix inconsistent keys in xcstrings")
    parser.add_argument("path", help="Path to .xcstrings file")
    parser.add_argument("--dry-run", "-n", action="store_true", help="Show what would be fixed")
    parser.add_argument("--find-only", "-f", action="store_true", help="Only find, don't fix")
    parser.add_argument("--output-json", "-o", help="Output inconsistent keys to JSON file")
    args = parser.parse_args()

    xc = XCStrings.load(args.path)

    # Find inconsistent keys
    inconsistent = find_inconsistent_keys(xc)

    if not inconsistent:
        print("All keys match their English translations.")
        return 0

    print(f"Found {len(inconsistent)} inconsistent keys:")
    print("=" * 80)

    for i, item in enumerate(inconsistent, 1):
        print(f"\n{i}. Key: {truncate(item.key, 60)}")
        print(f"   EN:  {truncate(item.english_value, 60)}")
        langs_with_trans = [k for k, v in item.has_translations.items() if v]
        if langs_with_trans:
            print(f"   Has translations: {', '.join(sorted(langs_with_trans))}")

    print()

    # Output to JSON if requested
    if args.output_json:
        output_data = [
            {"key": i.key, "english_value": i.english_value}
            for i in inconsistent
        ]
        with open(args.output_json, "w", encoding="utf-8") as f:
            json.dump(output_data, f, ensure_ascii=False, indent=2)
        print(f"Saved to: {args.output_json}")

    if args.find_only:
        return 1

    if args.dry_run:
        print(f"[DRY RUN] Would fix {len(inconsistent)} keys")
        return 0

    # Actually fix
    fixed = fix_inconsistent_keys(xc)
    xc.save()

    print(f"Fixed {len(fixed)} keys in {xc.path}")

    # Save mapping for reference
    mapping_file = xc.path.parent / "key_mapping.json"
    mapping_data = [{"old": old, "new": new} for old, new in fixed]
    with open(mapping_file, "w", encoding="utf-8") as f:
        json.dump(mapping_data, f, ensure_ascii=False, indent=2)
    print(f"Key mapping saved to: {mapping_file}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
