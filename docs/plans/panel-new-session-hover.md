# Panel New Session Hover Plan

## Goal
Make the small-window chat header “New Chat” / new-session button show a hover treatment that visually matches the adjacent header buttons.

## Current State
- The macOS 26 panel header uses `ConversationHistoryLiquidActionGroup` for the New Chat, History, and More capsule.
- The New Chat button owns its hover state separately and paints a low-contrast circle behind the plus icon.
- The legacy/fallback panel header `newChatButton` is only a borderless icon and has no custom hover background.
- Adjacent buttons use explicit circular glass/hover affordances, so the New Chat button can look like its hover is missing.

## Proposed Changes
1. Add a shared chat-header icon hover style so panel header buttons use one hover opacity/diameter source.
2. Apply the shared hover background to the liquid capsule buttons and to the legacy/fallback New Chat button.
3. Add full circular hit testing to the New Chat label so hovering anywhere in the intended button area activates the style.
4. Keep all actions, keyboard shortcuts, accessibility identifiers, and presentation logic unchanged.

## What Happens If We Do Not Change It
The New Chat button continues to look visually inconsistent in the small-window header and can appear to have no hover feedback.

## Expected Result After Change
Hovering the small-window New Chat button shows the same type and strength of circular hover feedback as adjacent header controls, without changing click behavior or shortcuts.

## Acceptance Criteria
- Panel New Chat hover has visible feedback comparable to adjacent header buttons.
- History, More, switch-presentation, and close behaviors remain unchanged.
- New Chat click and ⌘N still create a new chat.
- Accessibility identifiers remain stable.
- Unit/UI test coverage documents and protects the hover affordance.
- Build/test and manual smoke validation complete or blockers are explicitly reported.
