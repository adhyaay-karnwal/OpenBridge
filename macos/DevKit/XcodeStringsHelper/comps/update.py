#!/usr/bin/env python3
"""
Update translations in an xcstrings file.

This script:
- Ensures all entries have English anchors
- Fixes 'new' state English entries
- Applies explicit translations from a JSON file

Usage:
    python update.py <path_to_xcstrings>
    python update.py <path> --translations translations.json

Translation JSON format:
{
    "Key in English": {
        "zh-Hans": "Chinese translation",
        "ja": "Japanese translation"
    }
}

Exit codes:
    0 - Success
    1 - Error
"""

import argparse
import json
import sys
from pathlib import Path

from .xcstrings import XCStrings, apply_translations, ensure_english_anchor, fix_english_states


def main() -> int:
    parser = argparse.ArgumentParser(description="Update translations in xcstrings")
    parser.add_argument("path", help="Path to .xcstrings file")
    parser.add_argument(
        "--translations", "-t",
        help="Path to JSON file with translations to apply"
    )
    parser.add_argument("--dry-run", "-n", action="store_true", help="Show what would change")
    args = parser.parse_args()

    xc = XCStrings.load(args.path)

    # Load translations if provided
    translations = {}
    if args.translations:
        trans_path = Path(args.translations)
        if not trans_path.exists():
            print(f"Error: Translations file not found: {trans_path}", file=sys.stderr)
            return 1
        try:
            translations = json.loads(trans_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in {trans_path}: {e}", file=sys.stderr)
            return 1

    # Count changes
    added_en = ensure_english_anchor(xc)
    fixed_en = fix_english_states(xc)
    applied = apply_translations(xc, translations) if translations else 0

    if args.dry_run:
        print("[DRY RUN] Would make the following changes:")
        print(f"  - Add {added_en} missing English localizations")
        print(f"  - Fix {fixed_en} 'new' English states")
        print(f"  - Apply {applied} translations")
        return 0

    # Only save if changes were made
    total_changes = added_en + fixed_en + applied
    if total_changes == 0:
        print("No changes needed.")
        return 0

    xc.save()

    print(f"Updated {xc.path}")
    print(f"  - Added {added_en} missing English localizations")
    print(f"  - Fixed {fixed_en} 'new' English states")
    print(f"  - Applied {applied} translations")

    return 0


if __name__ == "__main__":
    sys.exit(main())
