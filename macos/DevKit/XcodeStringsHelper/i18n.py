#!/usr/bin/env python3
"""
Xcode .xcstrings file management tool.

Unified CLI for managing localization files:
  - check: Check translation completeness
  - prune: Remove stale strings
  - housekeep: Prune stale + mark empty keys non-translatable
  - backfill: Copy key to value for empty translations
  - fix-keys: Fix inconsistent keys
  - delete-keys: Delete explicit obsolete keys
  - find-missing: Find untranslated strings
  - update: Update translations
  - context: Dump string context for LLM translation

Usage:
    python i18n.py <command> <path> [options]
    python i18n.py check /path/to/Localizable.xcstrings
    python i18n.py check /path/to/project  # Scans directory for all .xcstrings
    python i18n.py prune /path/to/project --dry-run
    python i18n.py housekeep /path/to/project  # Clean up stale + empty keys
    python i18n.py backfill /path/to/project -l en  # Copy key to empty English values
    python i18n.py context /path/to/project -l zh-Hans  # Dump context for translation
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from comps import (
    DEFAULT_LANGUAGES,
    XCStrings,
    apply_translations,
    backfill_keys_to_values,
    ensure_english_anchor,
    find_empty_keys,
    find_incomplete,
    find_inconsistent_keys,
    find_stale,
    find_untranslated,
    fix_english_states,
    fix_inconsistent_keys,
    mark_empty_untranslatable,
    prune_stale,
    truncate,
)


# --- Path Resolution ---

def resolve_xcstrings(path: str) -> list[Path]:
    """Resolve path to list of .xcstrings files."""
    p = Path(path)

    if not p.exists():
        print(f"Error: Path not found: {p}", file=sys.stderr)
        sys.exit(1)

    if p.is_file():
        if not p.suffix == ".xcstrings":
            print(f"Error: Not an xcstrings file: {p}", file=sys.stderr)
            sys.exit(1)
        return [p]

    # Directory: scan for all .xcstrings files
    files = sorted(p.rglob("*.xcstrings"))
    if not files:
        print(f"Error: No .xcstrings files found in: {p}", file=sys.stderr)
        sys.exit(1)

    return files


def for_each_file(args: argparse.Namespace, handler) -> int:
    """Run handler for each xcstrings file. Returns max exit code."""
    files = resolve_xcstrings(args.path)
    results = []

    for i, file in enumerate(files):
        if len(files) > 1:
            if i > 0:
                print()
            print(f"{'=' * 70}")
            print(f"File: {file}")
            print(f"{'=' * 70}")

        args.current_file = file
        results.append(handler(args))

    return max(results) if results else 0


# --- Command Handlers ---

def _check_single(args: argparse.Namespace) -> int:
    """Check single file."""
    xc = XCStrings.load(args.current_file)

    stale = find_stale(xc)
    if stale:
        print(f"Found {len(stale)} stale entries (use 'prune' to remove)")

    incomplete = find_incomplete(xc)
    languages = sorted(xc.languages())
    total = len(xc.translatable_entries())

    print(f"Languages: {', '.join(languages)}")
    print(f"Total strings: {total}")
    print()

    if not incomplete:
        print("All translations are complete.")
        return 0

    print(f"Found {len(incomplete)} incomplete translations:")
    print("-" * 70)
    for entry in incomplete:
        print(f"  {truncate(entry.key, 40)}")
        print(f"    [{entry.language}] {entry.reason}")

    return 1


def cmd_check(args: argparse.Namespace) -> int:
    """Check translation completeness."""
    return for_each_file(args, _check_single)


def _prune_single(args: argparse.Namespace) -> int:
    """Prune single file."""
    xc = XCStrings.load(args.current_file)

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
    print(f"Removed {len(removed)} stale strings")

    if args.verbose:
        for key in removed:
            print(f"  - {truncate(key, 70)}")

    return 0


def cmd_prune(args: argparse.Namespace) -> int:
    """Remove stale strings."""
    return for_each_file(args, _prune_single)


def _delete_keys_single(args: argparse.Namespace) -> int:
    """Delete explicit keys from a single file."""
    xc = XCStrings.load(args.current_file)
    removed: list[str] = []
    missing: list[str] = []

    for key in args.keys:
        if key not in xc.strings:
            missing.append(key)
            continue

        removed.append(key)
        if not args.dry_run:
            del xc.strings[key]

    if args.dry_run:
        print(f"[DRY RUN] Would remove {len(removed)} string(s)")
    else:
        if removed:
            xc.save()
        print(f"Removed {len(removed)} string(s)")

    if args.verbose or args.dry_run:
        for key in removed:
            print(f"  - {truncate(key, 70)}")

    if missing and args.verbose:
        print(f"Missing {len(missing)} string(s)")
        for key in missing:
            print(f"  - {truncate(key, 70)}")

    return 0


def cmd_delete_keys(args: argparse.Namespace) -> int:
    """Delete explicitly listed strings."""
    if not args.keys:
        print("Error: at least one key is required", file=sys.stderr)
        return 1
    return for_each_file(args, _delete_keys_single)


def _housekeep_single(args: argparse.Namespace) -> int:
    """Housekeep single file."""
    xc = XCStrings.load(args.current_file)

    # 1. Find stale and empty keys
    stale = find_stale(xc)
    empty = find_empty_keys(xc)

    if args.dry_run:
        if not stale and not empty:
            print("No housekeeping needed.")
            return 0
        print("[DRY RUN] Would perform:")
        if stale:
            print(f"  - Remove {len(stale)} stale strings")
            for key in stale:
                print(f"      - {truncate(key, 60)}")
        if empty:
            print(f"  - Mark {len(empty)} empty key(s) as non-translatable")
        return 0

    # 2. Prune stale
    removed = prune_stale(xc)

    # 3. Mark empty keys as non-translatable
    marked = mark_empty_untranslatable(xc)

    if not removed and not marked:
        print("No housekeeping needed.")
        return 0

    xc.save()

    if removed:
        print(f"Removed {len(removed)} stale strings")
        if args.verbose:
            for key in removed:
                print(f"  - {truncate(key, 60)}")

    if marked:
        print(f"Marked {len(marked)} empty key(s) as non-translatable")

    return 0


def cmd_housekeep(args: argparse.Namespace) -> int:
    """Clean up xcstrings files."""
    return for_each_file(args, _housekeep_single)


def _backfill_single(args: argparse.Namespace) -> int:
    """Backfill single file."""
    xc = XCStrings.load(args.current_file)

    languages = set(args.languages.split(",")) if args.languages else {"en"}
    override = args.override

    if args.dry_run:
        # Count how many would be filled
        count = 0
        for key, entry in xc.strings.items():
            if not key or entry.get("shouldTranslate", True) is False:
                continue
            locs = entry.get("localizations", {})
            for lang in languages:
                loc = locs.get(lang, {})
                unit = loc.get("stringUnit", {})
                current = unit.get("value", "")
                if (not current or override) and current != key:
                    count += 1
        if count == 0:
            print("No values to backfill.")
        else:
            print(f"[DRY RUN] Would backfill {count} values for languages: {', '.join(sorted(languages))}")
        return 0

    filled = backfill_keys_to_values(xc, languages, override)

    if filled == 0:
        print("No values to backfill.")
        return 0

    xc.save()
    print(f"Backfilled {filled} values for languages: {', '.join(sorted(languages))}")

    return 0


def cmd_backfill(args: argparse.Namespace) -> int:
    """Backfill empty values with keys."""
    return for_each_file(args, _backfill_single)


def _fix_keys_single(args: argparse.Namespace) -> int:
    """Fix keys in single file."""
    xc = XCStrings.load(args.current_file)
    inconsistent = find_inconsistent_keys(xc)

    if not inconsistent:
        print("All keys match their English translations.")
        return 0

    print(f"Found {len(inconsistent)} inconsistent keys:")

    for i, item in enumerate(inconsistent, 1):
        print(f"\n{i}. Key: {truncate(item.key, 60)}")
        print(f"   EN:  {truncate(item.english_value, 60)}")
        langs = [k for k, v in item.has_translations.items() if v]
        if langs:
            print(f"   Has: {', '.join(sorted(langs))}")

    print()

    if args.find_only:
        return 1

    if args.dry_run:
        print(f"[DRY RUN] Would fix {len(inconsistent)} keys")
        return 0

    fixed = fix_inconsistent_keys(xc)
    xc.save()
    print(f"Fixed {len(fixed)} keys")

    return 0


def cmd_fix_keys(args: argparse.Namespace) -> int:
    """Fix inconsistent keys."""
    return for_each_file(args, _fix_keys_single)


def _find_missing_single(args: argparse.Namespace) -> int:
    """Find missing in single file."""
    xc = XCStrings.load(args.current_file)

    target = set(args.languages.split(",")) if args.languages else None
    exceptions = set(args.exceptions.split(",")) if args.exceptions else {"%@", "%lld"}

    print(f"Target languages: {', '.join(sorted(target or DEFAULT_LANGUAGES))}")
    print()

    missing = find_untranslated(xc, target, exceptions)

    if not missing:
        print("All strings are properly translated.")
        return 0

    print(f"Found {len(missing)} untranslated strings:")
    print("-" * 70)

    for item in missing:
        print(f"\n  Key: {truncate(item.key, 60)}")
        print(f"  Missing: {', '.join(item.missing_languages)}")
        if args.verbose and item.english_value:
            print(f"  EN: {truncate(item.english_value, 60)}")

    return 1


def cmd_find_missing(args: argparse.Namespace) -> int:
    """Find untranslated strings."""
    return for_each_file(args, _find_missing_single)


def _update_single(args: argparse.Namespace) -> int:
    """Update single file."""
    xc = XCStrings.load(args.current_file)

    translations = {}
    if args.translations:
        trans_path = Path(args.translations)
        if not trans_path.exists():
            print(f"Error: File not found: {trans_path}", file=sys.stderr)
            return 1
        try:
            translations = json.loads(trans_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON: {e}", file=sys.stderr)
            return 1

    added_en = ensure_english_anchor(xc)
    fixed_en = fix_english_states(xc)
    applied = apply_translations(xc, translations) if translations else 0

    if args.dry_run:
        print("[DRY RUN] Changes:")
        print(f"  - Add {added_en} missing English localizations")
        print(f"  - Fix {fixed_en} 'new' English states")
        print(f"  - Apply {applied} translations")
        return 0

    total = added_en + fixed_en + applied
    if total == 0:
        print("No changes needed.")
        return 0

    xc.save()
    print(f"Updated:")
    print(f"  - Added {added_en} English localizations")
    print(f"  - Fixed {fixed_en} 'new' states")
    print(f"  - Applied {applied} translations")

    return 0


def cmd_update(args: argparse.Namespace) -> int:
    """Update translations."""
    return for_each_file(args, _update_single)


# --- Context Search ---

SOURCE_EXTENSIONS = {".swift", ".m", ".mm", ".h", ".c", ".cpp"}


def search_string_context(project_dir: Path, key: str, context_lines: int = 3) -> list[dict]:
    """Search for string key usage in source files."""
    results = []

    # Escape special regex characters but keep it searchable
    escaped_key = re.escape(key)

    try:
        # Use grep for fast searching
        cmd = [
            "grep", "-rn", "--include=*.swift", "--include=*.m", "--include=*.mm",
            "-B", str(context_lines), "-A", str(context_lines),
            key, str(project_dir)
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        output = result.stdout

        if not output:
            return results

        # Parse grep output
        current_file = None
        current_lines = []

        for line in output.split("\n"):
            if not line:
                if current_file and current_lines:
                    results.append({
                        "file": current_file,
                        "context": "\n".join(current_lines)
                    })
                    current_lines = []
                continue

            if line == "--":
                if current_file and current_lines:
                    results.append({
                        "file": current_file,
                        "context": "\n".join(current_lines)
                    })
                    current_lines = []
                continue

            # Parse file:line:content or file-line-content
            match = re.match(r'^(.+?)[:-](\d+)[:-](.*)$', line)
            if match:
                file_path, line_no, content = match.groups()
                if current_file != file_path:
                    if current_file and current_lines:
                        results.append({
                            "file": current_file,
                            "context": "\n".join(current_lines)
                        })
                    current_file = file_path
                    current_lines = []
                current_lines.append(f"{line_no}: {content}")

        if current_file and current_lines:
            results.append({
                "file": current_file,
                "context": "\n".join(current_lines)
            })

    except subprocess.TimeoutExpired:
        print(f"Warning: Search timed out for key: {key}", file=sys.stderr)
    except Exception as e:
        print(f"Warning: Search failed for key: {key}: {e}", file=sys.stderr)

    return results


def cmd_context(args: argparse.Namespace) -> int:
    """Dump string context for LLM translation."""
    path = Path(args.path)

    if not path.exists():
        print(f"Error: Path not found: {path}", file=sys.stderr)
        return 1

    # Find project root (directory containing xcstrings)
    if path.is_file():
        project_dir = path.parent.parent.parent  # Assume Resources/Localizable.xcstrings
        xcstrings_files = [path]
    else:
        project_dir = path
        xcstrings_files = sorted(path.rglob("*.xcstrings"))

    if not xcstrings_files:
        print(f"Error: No .xcstrings files found", file=sys.stderr)
        return 1

    # Collect all untranslated strings
    target = set(args.languages.split(",")) if args.languages else None
    context_lines = args.context

    all_missing = []
    for xc_file in xcstrings_files:
        xc = XCStrings.load(xc_file)
        missing = find_untranslated(xc, target)
        for item in missing:
            all_missing.append({
                "key": item.key,
                "english": item.english_value or item.key,
                "missing_languages": item.missing_languages,
                "xcstrings_file": str(xc_file),
            })

    if not all_missing:
        print("All strings are translated.")
        return 0

    # Pagination
    page_size = args.page_size
    total = len(all_missing)
    total_pages = (total + page_size - 1) // page_size

    # Handle page selection
    page = args.page
    if page < 1 or page > total_pages:
        print(f"Error: Page {page} out of range (1-{total_pages})", file=sys.stderr)
        return 1

    start_idx = (page - 1) * page_size
    end_idx = min(start_idx + page_size, total)
    page_items = all_missing[start_idx:end_idx]

    print(f"# Untranslated Strings - Page {page}/{total_pages}")
    print(f"# Total: {total} strings, showing {start_idx + 1}-{end_idx}")
    print(f"# Target languages: {', '.join(sorted(target or DEFAULT_LANGUAGES))}")
    print()

    output_data = []

    for i, item in enumerate(page_items, start_idx + 1):
        print(f"## [{i}] {truncate(item['key'], 60)}")
        print(f"English: {item['english']}")
        print(f"Missing: {', '.join(item['missing_languages'])}")

        # Search for context
        contexts = search_string_context(project_dir, item['key'], context_lines)

        entry = {
            "index": i,
            "key": item['key'],
            "english": item['english'],
            "missing_languages": item['missing_languages'],
            "contexts": []
        }

        if contexts:
            print(f"Context ({len(contexts)} occurrences):")
            for ctx in contexts[:3]:  # Limit to 3 contexts
                print(f"```")
                print(f"// {ctx['file']}")
                print(ctx['context'])
                print(f"```")
                entry["contexts"].append(ctx)
        else:
            print("Context: (no source references found)")

        print()
        output_data.append(entry)

    # Output JSON (default to project root)
    output_file = Path(args.output) if args.output else (project_dir / "i18n_context.json")
    output = {
        "page": page,
        "total_pages": total_pages,
        "total_items": total,
        "target_languages": sorted(target or DEFAULT_LANGUAGES),
        "items": output_data,
    }
    output_file.write_text(json.dumps(output, ensure_ascii=False, indent=2))
    print(f"Context saved to: {output_file}")

    # Print navigation hint
    if total_pages > 1:
        print("-" * 70)
        if page < total_pages:
            print(f"Next page: python i18n.py context {args.path} --page {page + 1}")
        if page > 1:
            print(f"Prev page: python i18n.py context {args.path} --page {page - 1}")

    return 0


def cmd_dump(args: argparse.Namespace) -> int:
    """Dump all strings with context (full list) to desktop."""
    path = Path(args.path)

    if not path.exists():
        print(f"Error: Path not found: {path}", file=sys.stderr)
        return 1

    # Find project root and xcstrings files
    if path.is_file():
        project_dir = path.parent.parent.parent
        xcstrings_files = [path]
    else:
        project_dir = path
        xcstrings_files = sorted(path.rglob("*.xcstrings"))

    if not xcstrings_files:
        print(f"Error: No .xcstrings files found", file=sys.stderr)
        return 1

    context_lines = args.context
    output_lines = []
    output_lines.append("=" * 80)
    output_lines.append("I18N FULL DUMP WITH CODE CONTEXT")
    output_lines.append(f"Project: {project_dir}")
    output_lines.append("=" * 80)
    output_lines.append("")

    total_strings = 0

    for xc_file in xcstrings_files:
        xc = XCStrings.load(xc_file)
        entries = xc.translatable_entries()
        languages = sorted(xc.languages())

        output_lines.append("=" * 80)
        output_lines.append(f"File: {xc_file.name}")
        output_lines.append(f"Path: {xc_file}")
        output_lines.append(f"Languages: {', '.join(languages)}")
        output_lines.append(f"Total Strings: {len(entries)}")
        output_lines.append("=" * 80)
        output_lines.append("")

        # Sort entries by key
        sorted_entries = sorted(entries, key=lambda e: e.key)

        for i, entry in enumerate(sorted_entries, 1):
            total_strings += 1
            output_lines.append(f"[{i}/{len(entries)}] Key: {entry.key}")

            # Extraction state
            state = entry.extraction_state or "unknown"
            output_lines.append(f"  State: {state}")

            # Translations
            if entry.localizations:
                output_lines.append("  Translations:")
                for lang in languages:
                    if lang in entry.localizations:
                        loc = entry.localizations[lang]
                        if "stringUnit" in loc:
                            value = loc["stringUnit"].get("value", "")
                            trans_state = loc["stringUnit"].get("state", "")
                            marker = "*" if lang == xc.source_language else " "
                            output_lines.append(f"    {marker}[{lang}] ({trans_state}): {value}")
                        elif "variations" in loc:
                            output_lines.append(f"    [{lang}] (plural variations)")

            # Code context
            contexts = search_string_context(project_dir, entry.key, context_lines)
            if contexts:
                output_lines.append(f"  Code References ({len(contexts)}):")
                for ctx in contexts[:5]:  # Limit to 5
                    rel_path = ctx['file']
                    try:
                        rel_path = str(Path(ctx['file']).relative_to(project_dir))
                    except ValueError:
                        pass
                    output_lines.append(f"    --- {rel_path} ---")
                    for line in ctx['context'].split('\n'):
                        output_lines.append(f"    {line}")
            else:
                output_lines.append("  Code References: (none found)")

            output_lines.append("-" * 40)
            output_lines.append("")

    # Summary
    output_lines.append("=" * 80)
    output_lines.append("SUMMARY")
    output_lines.append("=" * 80)
    output_lines.append(f"Files: {len(xcstrings_files)}")
    output_lines.append(f"Total Strings: {total_strings}")

    # Write to desktop
    output_path = Path(args.output) if args.output else (Path.home() / "Desktop" / "i18n_dump.txt")
    output_path.write_text("\n".join(output_lines), encoding="utf-8")
    print(f"Dumped {total_strings} strings from {len(xcstrings_files)} files to: {output_path}")

    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    """Apply translations from JSON file."""
    trans_path = Path(args.translations)
    if not trans_path.exists():
        print(f"Error: File not found: {trans_path}", file=sys.stderr)
        return 1

    try:
        data = json.loads(trans_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON: {e}", file=sys.stderr)
        return 1

    # Support both formats:
    # 1. {"Key": {"zh-Hans": "value"}}
    # 2. {"items": [{"key": "Key", "translations": {"zh-Hans": "value"}}]}

    if "items" in data:
        translations = {}
        for item in data["items"]:
            key = item.get("key")
            trans = item.get("translations", {})
            if key and trans:
                translations[key] = trans
    else:
        translations = data

    if not translations:
        print("No translations found in file.")
        return 0

    # Find xcstrings files
    path = Path(args.path)
    xcstrings_files = resolve_xcstrings(str(path))

    total_applied = 0
    total_housekeep = {"stale": 0, "empty": 0}

    for xc_file in xcstrings_files:
        xc = XCStrings.load(xc_file)
        applied = apply_translations(xc, translations)

        # Auto housekeep: prune stale + mark empty keys
        removed = prune_stale(xc)
        marked = mark_empty_untranslatable(xc)

        if applied > 0 or removed or marked:
            if not args.dry_run:
                xc.save()
            if applied > 0:
                print(f"{'[DRY RUN] ' if args.dry_run else ''}Applied {applied} translations to {xc_file.name}")
            total_applied += applied
            total_housekeep["stale"] += len(removed)
            total_housekeep["empty"] += len(marked)

    if total_applied == 0:
        print("No translations applied.")
    else:
        print(f"\nTotal: {total_applied} translations {'would be ' if args.dry_run else ''}applied")

    # Report housekeeping
    if total_housekeep["stale"] or total_housekeep["empty"]:
        print(f"Housekeep: removed {total_housekeep['stale']} stale, marked {total_housekeep['empty']} empty key(s)")

    return 0


# --- Main ---

def main() -> int:
    parser = argparse.ArgumentParser(
        prog="i18n",
        description="Xcode .xcstrings file management tool",
        epilog="Path can be a single .xcstrings file or a directory to scan recursively.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # check
    p = subparsers.add_parser("check", help="Check translation completeness")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(func=cmd_check)

    # prune
    p = subparsers.add_parser("prune", help="Remove stale strings")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(func=cmd_prune)

    # delete explicit keys
    p = subparsers.add_parser("delete-keys", help="Delete explicit obsolete strings")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("keys", nargs="+", help="Exact string keys to delete")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(func=cmd_delete_keys)

    # housekeep
    p = subparsers.add_parser("housekeep", help="Clean up: prune stale + mark empty keys non-translatable")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(func=cmd_housekeep)

    # backfill
    p = subparsers.add_parser("backfill", help="Copy key to value for empty translations")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("-l", "--languages", default="en", help="Target languages (comma-separated, default: en)")
    p.add_argument("--override", action="store_true", help="Override existing values")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.set_defaults(func=cmd_backfill)

    # fix-keys
    p = subparsers.add_parser("fix-keys", help="Fix inconsistent keys")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("-f", "--find-only", action="store_true")
    p.set_defaults(func=cmd_fix_keys)

    # find-missing
    p = subparsers.add_parser("find-missing", help="Find untranslated strings")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("-l", "--languages", help="Comma-separated languages")
    p.add_argument("-e", "--exceptions", help="Keys to ignore")
    p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(func=cmd_find_missing)

    # update
    p = subparsers.add_parser("update", help="Update translations")
    p.add_argument("path", help="Path to .xcstrings file or directory")
    p.add_argument("-t", "--translations", help="JSON file with translations")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.set_defaults(func=cmd_update)

    # context
    p = subparsers.add_parser("context", help="Dump string context for LLM translation")
    p.add_argument("path", help="Path to project directory or .xcstrings file")
    p.add_argument("-l", "--languages", help="Target languages (comma-separated)")
    p.add_argument("-c", "--context", type=int, default=3, help="Context lines (default: 3)")
    p.add_argument("-p", "--page", type=int, default=1, help="Page number (default: 1)")
    p.add_argument("-s", "--page-size", type=int, default=10, help="Items per page (default: 10)")
    p.add_argument("-o", "--output", help="Output JSON file (default: <project>/i18n_context.json)")
    p.set_defaults(func=cmd_context)

    # apply
    p = subparsers.add_parser("apply", help="Apply translations from JSON file")
    p.add_argument("path", help="Path to project directory or .xcstrings file")
    p.add_argument("-t", "--translations", required=True, help="JSON file with translations")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.set_defaults(func=cmd_apply)

    # dump
    p = subparsers.add_parser("dump", help="Dump all strings with code context to desktop")
    p.add_argument("path", help="Path to project directory or .xcstrings file")
    p.add_argument("-c", "--context", type=int, default=3, help="Context lines (default: 3)")
    p.add_argument("-o", "--output", help="Output file (default: ~/Desktop/i18n_dump.txt)")
    p.set_defaults(func=cmd_dump)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
