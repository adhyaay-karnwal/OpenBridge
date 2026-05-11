# Agent Instructions

When working with Xcode localization files (`.xcstrings`), refer to `SKILL.md` in this directory for complete documentation.

## Tool Location

```
macos/DevKit/XcodeStringsHelper/i18n.py
```

## Quick Reference

```bash
cd macos/DevKit/XcodeStringsHelper

# Check status
python3 i18n.py check <project_or_file>

# Remove stale strings
python3 i18n.py prune <project_or_file> [--dry-run]

# Housekeep: prune stale + mark empty keys non-translatable
python3 i18n.py housekeep <project_or_file> [--dry-run]

# Backfill: copy key to value for empty translations (default: en)
python3 i18n.py backfill <project_or_file> [-l langs] [--override] [--dry-run]

# Fix inconsistent keys
python3 i18n.py fix-keys <project_or_file> [--find-only] [--dry-run]

# Find untranslated strings
python3 i18n.py find-missing <project_or_file> [-l langs] [-e exceptions]

# Update/fix translations
python3 i18n.py update <project_or_file> [-t translations.json] [--dry-run]

# Get context for LLM translation (paginated)
python3 i18n.py context <project> -l <langs> [--page N] [--page-size N] [--context N]

# Apply translations from JSON
python3 i18n.py apply <project_or_file> -t translations.json [--dry-run]

# Dump all strings with code context to a file
python3 i18n.py dump <project_or_file> [--context N] [--output path]
```

## LLM Translation Workflow

1. **Get untranslated strings with context:**
   ```bash
   python3 i18n.py context ~/MyProject -l zh-Hans --page 1
   ```
   This generates `~/MyProject/i18n_context.json`

2. **Review the context and provide translations**

3. **Create translations JSON:**
   ```json
   {
     "items": [
       {"key": "Hello", "translations": {"zh-Hans": "你好"}}
     ]
   }
   ```
   Or simpler format:
   ```json
   {"Hello": {"zh-Hans": "你好"}}
   ```

4. **Apply translations:**
   ```bash
   python3 i18n.py apply ~/MyProject -t translations.json
   ```

## Translation Quality Verification Workflow

When verifying translation quality with code context:

1. **Extract strings page by page** (30 items per page recommended):
   ```bash
   python3 -c "
   import json
   from pathlib import Path

   xc_path = Path('path/to/Localizable.xcstrings')
   data = json.loads(xc_path.read_text(encoding='utf-8'))
   strings = data.get('strings', {})

   page = 1
   page_size = 30
   start = (page - 1) * page_size
   keys = sorted(strings.keys())[start:start + page_size]

   for i, key in enumerate(keys, start + 1):
       localizations = strings[key].get('localizations', {})
       en = localizations.get('en', {}).get('stringUnit', {}).get('value', key)
       zh_hans = localizations.get('zh-Hans', {}).get('stringUnit', {}).get('value', '')
       zh_hant = localizations.get('zh-Hant', {}).get('stringUnit', {}).get('value', '')
       print(f'{i}. {key}')
       print(f'   EN: {en}')
       print(f'   zh-Hans: {zh_hans}')
       print(f'   zh-Hant: {zh_hant}')
   "
   ```

2. **Search for code context** to understand meaning:
   ```bash
   grep -rn "string key" macos --include="*.swift" -A 3 -B 3
   ```

3. **Verify translations** for:
   - Context accuracy (e.g., "stop recording" = clipboard vs audio)
   - Correct character sets (zh-Hans = simplified, zh-Hant = traditional)
   - Terminology consistency
   - Common issues:
     - Simplified chars in zh-Hant: 权→權, 默→預, 图→圖, 添加→新增
     - Product terms: Keep "Agent", "Skills", "OpenBridge" in English
     - "代理" = proxy (network), "Agent" = AI agent

4. **Create fixes JSON** with only keys that need corrections:
   ```json
   {
     "Key String": {
       "zh-Hans": "corrected simplified Chinese",
       "zh-Hant": "corrected traditional Chinese"
     }
   }
   ```

5. **Apply fixes using the script** (NOT direct editing):
   ```bash
   python3 i18n.py apply path/to/Localizable.xcstrings -t fixes.json
   ```

6. **Verify changes**:
   ```bash
   python3 i18n.py check path/to/Localizable.xcstrings
   ```

7. **Continue to next page** and repeat until all pages reviewed.

### Why Use Script Instead of Direct Editing

- Maintains JSON structure integrity
- Preserves metadata and state information
- Handles character encoding correctly
- Provides atomic updates with validation
- Easier to track and review changes

## Important

- Always use `--dry-run` first for destructive operations
- Path can be a single `.xcstrings` file or project directory
- Use the script's `apply` command for ALL translation updates
- Never directly edit `.xcstrings` files - use JSON + apply workflow
- **Note**: `apply` automatically runs housekeeping (prunes stale strings + marks empty keys as non-translatable)
- See `SKILL.md` for complete JSON formats and all options
