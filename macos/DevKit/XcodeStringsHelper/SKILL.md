# XcodeStringsHelper Skill

A tool for managing Xcode `.xcstrings` localization files.

## Quick Start

```bash
cd /Users/qaq/Desktop/XcodeStringsHelper
python3 i18n.py <command> <path> [options]
```

**Path can be:**
- A single `.xcstrings` file
- A project directory (recursively scans all `.xcstrings` files)

## Commands

### check - Check translation completeness
```bash
python3 i18n.py check /path/to/project
python3 i18n.py check /path/to/Localizable.xcstrings
```
Reports incomplete translations and stale entries for all xcstrings files.

### prune - Remove stale strings
```bash
# Preview what would be removed
python3 i18n.py prune /path/to/project --dry-run

# Actually remove stale strings
python3 i18n.py prune /path/to/project
```
Removes entries marked `extractionState=stale` (no longer in source code).

### fix-keys - Fix inconsistent keys
```bash
# Find inconsistent keys
python3 i18n.py fix-keys /path/to/project --find-only

# Fix keys to match English values
python3 i18n.py fix-keys /path/to/project
```
Updates keys to match their English translation values.

### find-missing - Find untranslated strings
```bash
# Check default languages (ja, de, fr, es, ko, zh-Hans)
python3 i18n.py find-missing /path/to/project

# Check specific languages
python3 i18n.py find-missing /path/to/project -l zh-Hans,ja
```

### update - Update translations
```bash
# Fix English anchors and states
python3 i18n.py update /path/to/project

# Apply translations from JSON
python3 i18n.py update /path/to/project -t translations.json
```

### context - Dump context for LLM translation (with pagination)
```bash
# Get first page of untranslated strings with source context
python3 i18n.py context /path/to/project -l zh-Hans

# Specify page number and page size
python3 i18n.py context /path/to/project -l zh-Hans --page 2 --page-size 5

# Customize context lines (before/after)
python3 i18n.py context /path/to/project -l zh-Hans --context 5
```
Outputs:
- Each untranslated string with its English value
- Source code context where the string is used
- Saves to `<project>/i18n_context.json`

### apply - Apply translations from JSON
```bash
# Preview what would be applied
python3 i18n.py apply /path/to/project -t translations.json --dry-run

# Apply translations
python3 i18n.py apply /path/to/project -t translations.json
```

## Translation JSON Format

### Simple format (for update/apply):
```json
{
  "English Key": {
    "zh-Hans": "Chinese translation",
    "ja": "Japanese translation"
  }
}
```

### Context output format (from context command):
```json
{
  "page": 1,
  "total_pages": 5,
  "total_items": 50,
  "target_languages": ["zh-Hans"],
  "items": [
    {
      "index": 1,
      "key": "Hello World",
      "english": "Hello World",
      "missing_languages": ["zh-Hans"],
      "contexts": [
        {
          "file": "/path/to/file.swift",
          "context": "10: Text(\"Hello World\")"
        }
      ]
    }
  ]
}
```

### Translation input format (for apply):
```json
{
  "items": [
    {
      "key": "Hello World",
      "translations": {
        "zh-Hans": "你好世界"
      }
    }
  ]
}
```

## Common Options

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes without modifying files |
| `-v, --verbose` | Show detailed output |
| `-l, --languages` | Target languages (comma-separated) |
| `-p, --page` | Page number for pagination |
| `-s, --page-size` | Items per page |
| `-c, --context` | Context lines to show |
| `-o, --output` | Custom output file path |
| `-t, --translations` | Input translation JSON file |

## Supported Languages

Default target languages: `ja`, `de`, `fr`, `es`, `ko`, `zh-Hans`

## Workflow Example

```bash
# 1. Check current status
python3 i18n.py check ~/MyProject

# 2. Remove stale strings
python3 i18n.py prune ~/MyProject

# 3. Get context for LLM translation (page by page)
python3 i18n.py context ~/MyProject -l zh-Hans --page 1

# 4. After LLM provides translations, apply them
python3 i18n.py apply ~/MyProject -t ~/MyProject/translations.json

# 5. Verify
python3 i18n.py check ~/MyProject
```
