---
name: skill-manager
description: |
  Manage skills: create, install, modify, or delete skills.
  Trigger when user asks to: "create a skill", "save this as a skill", "install this skill" (from URL/link), "edit/modify a skill", "delete a skill".
  User skills live under ~/.openbridge/skills/.
metadata:
  displayName: Skill Manager
  icon: folder.badge.plus
  color: red
  visibility: toggled
  placeholder: Describe the skill to create, install, or manage
---

# Skill Manager

This skill provides guidance for all skill-related operations: creating, installing, modifying, and deleting skills.

## About Skills

Skills are modular, self-contained packages that extend the agent by providing specialized workflows and bundled resources. Think of them as an "onboarding guide" for a specific task category.

## Skill Directories

User skills live under `~/.openbridge/skills/`:

| Directory   | Purpose                                       |
| ----------- | --------------------------------------------- |
| `custom/`   | User-created skills                           |
| `imported/` | Skills imported from the OpenBridge skill library |

Synced local skills may also appear through configured sync folders. Those stay at their original locations and are not installed into `~/.openbridge/skills/`.

**IMPORTANT**: When creating or installing managed local skills, always use `~/.openbridge/skills/custom/<skill-slug>/` unless the flow explicitly targets `imported/`.

---

## Operation: Install Skill from URL

When the user provides a URL to a skill (e.g., `https://example.com/dot_claude/skills/xxx/SKILL.md`) and asks to "install this skill".

**Read the detailed guide**: `references/install-from-url.md`

---

## Operation: Install Skill via npx skills CLI

When the user asks to install a skill using `npx skills add`.

**Read the detailed guide**: `references/install-from-npx-skills.md`

---

## Operation: Create Skill from Current Conversation

Convert the current multi-turn chat solution into a reusable custom skill.

**Read the detailed guide**: `references/create-from-conversation.md`

---

## Operation: Modify Existing Skill

When the user asks to modify, edit, or update an existing skill:

1. **Locate** the SKILL.md in `~/.openbridge/skills/` (check custom/ and imported/) or in a configured sync folder
2. **Read** current content
3. **Apply changes** as requested
4. **Validate** if possible
5. **Report** what was changed

**Note**: System skills are read-only. To customize behavior, create a new skill under `~/.openbridge/skills/custom/`.

---

## Operation: Delete Skill

When the user asks to delete or remove a skill:

1. **Confirm location**: Only `~/.openbridge/skills/custom/` or `~/.openbridge/skills/imported/` skills can be deleted
2. **Confirm with user** (list what will be removed)
3. **Delete**: `rm -rf ~/.openbridge/skills/custom/<skill-slug>/`
4. **Report** deletion

**Cannot delete**: system skills, synced skills (manage at original location)
