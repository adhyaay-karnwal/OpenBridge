#!/usr/bin/env python3
"""
Core utilities for Xcode .xcstrings file manipulation.

This module provides robust, low-indentation functions for:
- Loading and saving xcstrings files
- Finding untranslated/incomplete strings
- Pruning stale entries
- Fixing inconsistent keys
- Updating translations
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


# Default supported languages
DEFAULT_LANGUAGES = frozenset({"ja", "de", "fr", "es", "ko", "zh-Hans"})


@dataclass
class StringEntry:
    """Represents a single localization entry."""
    key: str
    localizations: dict[str, dict[str, Any]] = field(default_factory=dict)
    should_translate: bool = True
    extraction_state: str | None = None

    @classmethod
    def from_dict(cls, key: str, data: dict[str, Any]) -> StringEntry:
        return cls(
            key=key,
            localizations=data.get("localizations", {}),
            should_translate=data.get("shouldTranslate", True) is not False,
            extraction_state=data.get("extractionState"),
        )

    def get_value(self, lang: str) -> str | None:
        """Get translated value for a language."""
        loc = self.localizations.get(lang, {})
        unit = loc.get("stringUnit", {})
        return unit.get("value")

    def get_state(self, lang: str) -> str | None:
        """Get translation state for a language."""
        loc = self.localizations.get(lang, {})
        unit = loc.get("stringUnit", {})
        return unit.get("state")

    def is_stale(self) -> bool:
        return self.extraction_state == "stale"


@dataclass
class XCStrings:
    """Represents an xcstrings file."""
    path: Path
    source_language: str
    strings: dict[str, dict[str, Any]]
    version: str

    @classmethod
    def load(cls, path: str | Path) -> XCStrings:
        """Load xcstrings file with error handling."""
        path = Path(path)
        if not path.exists():
            print(f"Error: File not found: {path}", file=sys.stderr)
            sys.exit(1)

        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in {path}: {e}", file=sys.stderr)
            sys.exit(1)

        return cls(
            path=path,
            source_language=data.get("sourceLanguage", "en"),
            strings=data.get("strings", {}),
            version=data.get("version", "1.0"),
        )

    def save(self) -> None:
        """Save xcstrings file with consistent formatting."""
        data = {
            "sourceLanguage": self.source_language,
            "strings": self.strings,
            "version": self.version,
        }
        content = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "))
        self.path.write_text(content, encoding="utf-8")

    def entries(self) -> list[StringEntry]:
        """Get all entries as StringEntry objects."""
        return [StringEntry.from_dict(k, v) for k, v in self.strings.items()]

    def translatable_entries(self) -> list[StringEntry]:
        """Get only translatable entries."""
        return [e for e in self.entries() if e.should_translate]

    def languages(self) -> set[str]:
        """Collect all language codes present in any entry."""
        langs = set()
        for entry in self.strings.values():
            langs.update(entry.get("localizations", {}).keys())
        return langs


# --- Stale String Operations ---

def find_stale(xc: XCStrings) -> list[str]:
    """Find keys marked as stale."""
    return [k for k, v in xc.strings.items() if v.get("extractionState") == "stale"]


def prune_stale(xc: XCStrings) -> list[str]:
    """Remove stale entries. Returns list of removed keys."""
    stale_keys = find_stale(xc)
    for key in stale_keys:
        del xc.strings[key]
    return stale_keys


# --- Empty Key Operations ---

def find_empty_keys(xc: XCStrings) -> list[str]:
    """Find keys that are empty strings and should be marked as non-translatable."""
    return [
        k for k, v in xc.strings.items()
        if k == "" and v.get("shouldTranslate", True) is not False
    ]


def mark_empty_untranslatable(xc: XCStrings) -> list[str]:
    """Mark empty string keys as shouldTranslate=false. Returns list of marked keys."""
    marked = []
    for key, entry in xc.strings.items():
        if key != "":
            continue
        if entry.get("shouldTranslate", True) is False:
            continue
        entry["shouldTranslate"] = False
        marked.append(key)
    return marked


def backfill_keys_to_values(
    xc: XCStrings,
    languages: set[str],
    override: bool = False,
) -> int:
    """
    Copy key to value for specified languages where value is empty.
    If override=True, also overwrite non-empty values.
    Returns count of values filled.
    """
    count = 0

    for key, entry in xc.strings.items():
        if not key:  # Skip empty keys
            continue
        if entry.get("shouldTranslate", True) is False:
            continue

        locs = entry.setdefault("localizations", {})

        for lang in languages:
            loc = locs.get(lang, {})
            unit = loc.get("stringUnit", {})
            current_value = unit.get("value", "")

            # Skip if value exists and not overriding
            if current_value and not override:
                continue

            # Skip if already equals key
            if current_value == key:
                continue

            locs[lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": key,
                }
            }
            count += 1

    return count


# --- Untranslated String Operations ---

@dataclass
class UntranslatedEntry:
    """Entry missing translations."""
    key: str
    missing_languages: list[str]
    english_value: str | None = None


def find_untranslated(
    xc: XCStrings,
    target_languages: set[str] | None = None,
    exceptions: set[str] | None = None,
) -> list[UntranslatedEntry]:
    """Find entries missing translations for target languages."""
    target_languages = target_languages or DEFAULT_LANGUAGES
    exceptions = exceptions or set()
    results = []

    for entry in xc.translatable_entries():
        if entry.key in exceptions:
            continue

        missing = []
        for lang in target_languages:
            value = entry.get_value(lang)
            if not value or not value.strip():
                missing.append(lang)

        if not missing:
            continue

        results.append(UntranslatedEntry(
            key=entry.key,
            missing_languages=sorted(missing),
            english_value=entry.get_value("en"),
        ))

    return results


# --- Incomplete Translation Operations ---

@dataclass
class IncompleteEntry:
    """Entry with incomplete translation."""
    key: str
    language: str
    reason: str


def find_incomplete(
    xc: XCStrings,
    languages: set[str] | None = None,
) -> list[IncompleteEntry]:
    """Find entries with missing/empty/non-translated states."""
    languages = languages or xc.languages()
    results = []

    for entry in xc.translatable_entries():
        for lang in languages:
            loc = entry.localizations.get(lang, {})
            unit = loc.get("stringUnit")

            if not unit:
                results.append(IncompleteEntry(entry.key, lang, "missing localization"))
                continue

            state = unit.get("state")
            value = unit.get("value", "").strip()

            if state != "translated":
                results.append(IncompleteEntry(entry.key, lang, f"state: {state}"))
            elif not value:
                results.append(IncompleteEntry(entry.key, lang, "empty value"))

    return results


# --- Inconsistent Key Operations ---

@dataclass
class InconsistentKey:
    """Entry where key doesn't match English value."""
    key: str
    english_value: str
    has_translations: dict[str, bool] = field(default_factory=dict)


def find_inconsistent_keys(xc: XCStrings) -> list[InconsistentKey]:
    """Find entries where key != English value."""
    results = []

    for entry in xc.translatable_entries():
        en_value = entry.get_value("en")
        if en_value is None:
            continue
        if entry.key == en_value:
            continue

        has_translations = {
            lang: bool(entry.get_value(lang))
            for lang in DEFAULT_LANGUAGES
        }

        results.append(InconsistentKey(
            key=entry.key,
            english_value=en_value,
            has_translations=has_translations,
        ))

    return results


def fix_inconsistent_keys(xc: XCStrings) -> list[tuple[str, str]]:
    """Fix keys to match English values. Returns (old_key, new_key) pairs."""
    inconsistent = find_inconsistent_keys(xc)
    if not inconsistent:
        return []

    new_strings = {}
    fixed = []

    for key, entry in xc.strings.items():
        # Check if this key needs fixing
        match = next((i for i in inconsistent if i.key == key), None)
        if match:
            new_strings[match.english_value] = entry
            fixed.append((key, match.english_value))
        else:
            new_strings[key] = entry

    xc.strings = new_strings
    return fixed


# --- Translation Update Operations ---

def ensure_english_anchor(xc: XCStrings) -> int:
    """Ensure all entries have English localization. Returns count added."""
    count = 0

    for key, entry in xc.strings.items():
        locs = entry.setdefault("localizations", {})
        if "en" in locs:
            continue

        locs["en"] = {
            "stringUnit": {
                "state": "translated",
                "value": key,
            }
        }
        count += 1

    return count


def fix_english_states(xc: XCStrings) -> int:
    """Fix English entries with 'new' state. Returns count fixed."""
    count = 0

    for key, entry in xc.strings.items():
        locs = entry.get("localizations", {})
        en_loc = locs.get("en", {})
        unit = en_loc.get("stringUnit", {})

        if unit.get("state") != "new":
            continue

        if not unit.get("value", "").strip():
            unit["value"] = key
        unit["state"] = "translated"
        count += 1

    return count


def apply_translations(
    xc: XCStrings,
    translations: dict[str, dict[str, str]],
) -> int:
    """
    Apply explicit translations.
    Format: {"Key": {"zh-Hans": "value", "ja": "value"}}
    Returns count of translations applied.
    """
    count = 0

    for key, lang_map in translations.items():
        if key not in xc.strings:
            continue

        entry = xc.strings[key]
        locs = entry.setdefault("localizations", {})

        for lang, value in lang_map.items():
            current = locs.get(lang, {}).get("stringUnit", {}).get("value", "")
            if current == value:
                continue

            locs[lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": value,
                }
            }
            count += 1

    return count


# --- Utility Functions ---

def truncate(s: str, max_len: int = 60) -> str:
    """Truncate string with ellipsis if needed."""
    if len(s) <= max_len:
        return s
    return s[:max_len - 3] + "..."
