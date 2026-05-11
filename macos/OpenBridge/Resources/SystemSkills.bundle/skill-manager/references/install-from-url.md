# Install Skill from URL

When the user provides a URL to a skill and asks to "install this skill".

## Process

### Step 1: Fetch SKILL.md

Download the SKILL.md file from the provided URL.

Example URLs:
- `https://example.com/skills/my-skill/SKILL.md`
- `https://raw.githubusercontent.com/user/repo/main/.claude/skills/xxx/SKILL.md`

### Step 2: Parse and Extract Skill Name

Parse the frontmatter to extract:
- `name` field → use as the skill slug
- If no name, derive from the parent folder in the URL path

### Step 3: Check for Name Conflicts

Check if `~/.openbridge/skills/custom/<skill-slug>/` already exists.

If conflict exists:
- Append counter: `<skill-slug>-2`, `<skill-slug>-3`, etc.
- Find the first available name

### Step 4: Download Related Files

The URL points to `xxx/SKILL.md`. The goal is to download the entire `xxx/` folder.

Try these methods in order until one succeeds:

#### Method A: Direct Folder ZIP (if available)

Some servers provide a ZIP download URL for folders. Try constructing a ZIP URL and download.

#### Method B: GitHub Repository

If the URL is from GitHub (e.g., `raw.githubusercontent.com` or `github.com`):

1. Extract repo info: `owner`, `repo`, `branch`, `path/to/skill/`
2. Download the repo ZIP: `https://github.com/{owner}/{repo}/archive/refs/heads/{branch}.zip`
3. Unzip to a temp folder
4. Copy only the `path/to/skill/` folder to the destination
5. Delete the temp folder

Example:
```
URL: https://raw.githubusercontent.com/user/my-repo/main/.claude/skills/my-skill/SKILL.md
→ Download: https://github.com/user/my-repo/archive/refs/heads/main.zip
→ Extract: my-repo-main/.claude/skills/my-skill/
→ Copy to: ~/.openbridge/skills/custom/my-skill/
```

#### Method C: Heuristic File Discovery (fallback)

If Methods A and B are not applicable or fail:

1. Parse SKILL.md content for any relative path references (paths not starting with `/`, `http://`, or `https://`)
2. For each referenced file:
   - Construct the URL by replacing `SKILL.md` with the relative path
   - Attempt to download
   - If download fails, log warning but continue (some references may be optional)

Example:
```
URL: https://example.com/skills/my-skill/SKILL.md
Reference in SKILL.md: helpers/convert.py
Download: https://example.com/skills/my-skill/helpers/convert.py
```

### Step 5: Create Folder Structure

Create the skill folder at:
```
~/.openbridge/skills/custom/<skill-slug>/
```

**Preserve the original directory structure exactly as referenced in SKILL.md.** Do not rename or reorganize folders.

Example — if SKILL.md references:
- `helpers/convert.py`
- `docs/api.md`
- `templates/base.html`

Then create:
```
~/.openbridge/skills/custom/<skill-slug>/
├── SKILL.md
├── helpers/
│   └── convert.py
├── docs/
│   └── api.md
└── templates/
    └── base.html
```

### Step 6: Validate

Run the validator to ensure the skill is properly formed:

```bash
python3 scripts/quick_validate.py ~/.openbridge/skills/custom/<skill-slug>
```

Check for:
- Valid frontmatter (name, description)
- Name matches folder name
- Referenced files exist

### Step 7: Report

After installation, report:
- Skill name
- Installation path
- Files downloaded
- Any warnings (missing optional files, name conflicts resolved)

## Critical Rules

1. **Destination is always `~/.openbridge/skills/custom/`** — regardless of source URL path (e.g., `dot_claude/`, `.cursor/`)
2. **Never modify the source** — this is a one-way download
3. **Handle failures gracefully** — missing optional files should not abort installation
