# Install Skill via npx skills CLI

When the user asks to install a skill using `npx skills add`.

## Process

### Step 1: Run the CLI command

```bash
npx skills add <skill-name>
```

### Step 2: Parse output for installation path

The CLI will output the installation directory. Look for the path in the output (typically something like `.claude/skills/xxx/` or `.cursor/skills/xxx/`).

### Step 3: Copy to custom directory

After successful installation, copy the entire skill folder to `~/.openbridge/skills/custom/`:

```bash
cp -r <installed-path> ~/.openbridge/skills/custom/
```

### Step 4: Report

Report both:
- Original installation location (from CLI output)
- Custom directory copy location: `~/.openbridge/skills/custom/<skill-slug>/`

## Critical Rules

1. **Always copy to `~/.openbridge/skills/custom/`** — this ensures the skill is available in OpenBridge
2. **Preserve folder structure** — copy the entire skill folder, not just SKILL.md
3. **Handle name conflicts** — if the skill name already exists in custom/, append a counter (e.g., `skill-name-2`)
