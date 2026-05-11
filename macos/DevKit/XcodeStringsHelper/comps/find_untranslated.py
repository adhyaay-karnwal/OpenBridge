#!/usr/bin/env python3
"""
Find untranslated strings in an xcstrings file.

Reports strings that are missing translations for specified target languages.

Usage:
    python find_untranslated.py <path_to_xcstrings>
    python find_untranslated.py <path> --languages zh-Hans,ja,ko
    python find_untranslated.py <path> --output-json missing.json

Exit codes:
    0 - All strings are properly translated
    1 - Found untranslated strings
"""

import argparse
import json
import sys

from .xcstrings import DEFAULT_LANGUAGES, XCStrings, find_untranslated, truncate


def main() -> int:
    parser = argparse.ArgumentParser(description="Find untranslated strings in xcstrings")
    parser.add_argument("path", help="Path to .xcstrings file")
    parser.add_argument(
        "--languages", "-l",
        help=f"Comma-separated target languages (default: {','.join(sorted(DEFAULT_LANGUAGES))})"
    )
    parser.add_argument(
        "--exceptions", "-e",
        help="Comma-separated keys to ignore"
    )
    parser.add_argument("--output-json", "-o", help="Output results to JSON file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show English values")
    args = parser.parse_args()

    xc = XCStrings.load(args.path)

    target_langs = set(args.languages.split(",")) if args.languages else None
    exceptions = set(args.exceptions.split(",")) if args.exceptions else {"%@", "%lld"}

    print(f"Checking: {xc.path}")
    print(f"Target languages: {', '.join(sorted(target_langs or DEFAULT_LANGUAGES))}")
    print()

    untranslated = find_untranslated(xc, target_langs, exceptions)

    if not untranslated:
        print("All strings are properly translated.")
        return 0

    print(f"Found {len(untranslated)} untranslated strings:")
    print("-" * 70)

    for item in untranslated:
        print(f"\n  Key: {truncate(item.key, 60)}")
        print(f"  Missing: {', '.join(item.missing_languages)}")
        if args.verbose and item.english_value:
            print(f"  EN: {truncate(item.english_value, 60)}")

    if args.output_json:
        output_data = [
            {
                "key": i.key,
                "missing": i.missing_languages,
                "english": i.english_value,
            }
            for i in untranslated
        ]
        with open(args.output_json, "w", encoding="utf-8") as f:
            json.dump(output_data, f, ensure_ascii=False, indent=2)
        print(f"\nSaved to: {args.output_json}")

    return 1


if __name__ == "__main__":
    sys.exit(main())
