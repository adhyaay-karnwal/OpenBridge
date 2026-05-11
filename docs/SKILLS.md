# Skills

OpenBridge skills are local capability packages. Each skill has a `SKILL.md` entry point and may include references, scripts, assets, and metadata.

## Sources

Skills can come from:

- Bundled system skills in `macos/OpenBridge/Resources/SystemSkills.bundle`.
- User-created skills under `~/.openbridge/skills/custom`.
- Imported skills under `~/.openbridge/skills/imported`.
- Synced folders configured by the user.

Core Swift code:

| Area | Source |
| --- | --- |
| Skill model | `macos/OpenBridge/Backend/Skills/Skill.swift` |
| Skill manager | `macos/OpenBridge/Backend/Skills/SkillManager.swift` |
| Sync folders | `macos/OpenBridge/Backend/Skills/SkillManager+Sync.swift` |
| Zip import | `macos/OpenBridge/Backend/Skills/SkillManager+ZipImport.swift` |
| Usage tracking | `macos/OpenBridge/Backend/Skills/SkillManager+Usage.swift` |
| Settings UI | `macos/OpenBridge/Interface/Settings/Skills` |
| Chat activation | `macos/OpenBridge/Interface/Chat/ChatEditorViewModel.swift` |
| Agent prompt | `macos/OpenBridge/Agent/LocalRuntime/OpenBridgeSystemPromptBuilder.swift` |

## Agent Prompt Contract

OpenBridge advertises active skills to the agent as an inventory. The agent should not eagerly read every skill. It should:

1. Match the user request against active skill names and descriptions.
2. Read the exact `SKILL.md` for relevant skills.
3. Follow only the instructions needed for the task.
4. Load referenced files from the skill directory on demand.
5. Prefer scripts or assets shipped with the skill instead of recreating large logic inline.

This keeps the base prompt compact while still making specialized workflows available.

## Skill Package Shape

```text
my-skill/
├─ SKILL.md
├─ references/
├─ scripts/
└─ assets/
```

`SKILL.md` is required. Other folders are optional and should be used only when they keep the main instruction file concise.

## UI Behavior

The settings UI lets users enable, disable, pin, inspect, import, update, and delete skills. Chat input can activate a skill by name, and usage tracking helps keep frequently used skills discoverable.

## Development Notes

- Keep `SKILL.md` concise and task-oriented.
- Put long examples, fixtures, or domain references in `references/`.
- Put repeatable automation in `scripts/`.
- Do not store credentials inside skill packages.
- Avoid app-specific absolute paths in shared system skills.

