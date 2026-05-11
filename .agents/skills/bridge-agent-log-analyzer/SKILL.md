---
name: bridge-agent-log-analyzer
description: Analyze Bridge agent execution logs from ~/.bridge/sessions, reconstruct the agent's actual runtime behavior, and explain tool execution, failures, retries, and artifacts from persisted session files.
---

# Bridge Agent Log Analyzer

## Overview

Inspect one persisted Bridge session and turn its on-disk logs into a behavior report.

This skill is for analyzing the agent itself:

- what it tried to do
- which tools it called
- which calls ran in the background
- where it failed
- how it recovered or retried
- which artifacts it read or produced

This skill is not for UI reconstruction. Ignore frontend display behavior unless the user explicitly asks for it.

## Default Workflow

1. Identify the target session or log identifier.
2. Run `scripts/inspect_bridge_session.py` first.
3. Read only the raw files needed to explain the behavior:
   - `session-meta.json`
   - `agent/history.json`
   - `agent/context.json`
   - `agent/state.json`
   - `agent/toolcalls/*/meta.json`
   - `agent/toolcalls/*/output.log`
   - subagent equivalents under `agents/<subagent-id>/agent/`
4. Reconstruct the execution chronologically.
5. Separate direct evidence from inference.

## Quick Start

Inspect the most recent session:

```bash
python3 .agents/skills/bridge-agent-log-analyzer/scripts/inspect_bridge_session.py
```

Inspect a specific session directory ID:

```bash
python3 .agents/skills/bridge-agent-log-analyzer/scripts/inspect_bridge_session.py --session-id <session-id>
```

Inspect using any UUID or identifier that appears inside that session's logs:

```bash
python3 .agents/skills/bridge-agent-log-analyzer/scripts/inspect_bridge_session.py --session-id <message-or-toolcall-id>
```

The helper script is the index. Use it to find the real session directory, runtime toolcalls, failures, and likely recovery paths before opening raw files.

## Primary Evidence Sources

- `history.json`
  - user-visible messages and task state transitions
- `context.json`
  - assistant decision points, tool calls, and tool results
- `toolcalls/*/meta.json`
  - runtime command, async promotion, exit code, timing, environment
- `toolcalls/*/output.log`
  - actual command output, error text, tracebacks, downloads, progress
- `state.json`
  - model, reasoning effort, last-round token and step summary
- `session-meta.json`
  - session title, environments, created/updated timestamps

Use workspace files only when the agent explicitly read or referenced them in logs.

## What To Extract

### Session overview

- real session directory ID
- whether the requested identifier was a direct session ID or a reverse lookup hit
- environment labels
- effective start/end time based on history and toolcall timestamps

### Behavior timeline

Use `context.json` as the main execution timeline.

- one assistant message is one decision point
- assistant content is a visible reply or intermediate narration
- assistant `tool_calls` are intended actions
- later `tool` messages are immediate tool results
- `toolcalls/*` supplies runtime metadata for those tool calls

### Tool execution

Summarize:

- tool name
- order of invocation
- arguments or command preview
- runtime status
- sync vs async/background execution
- exit code
- duration
- output preview

### Failures and recovery

Focus on:

- failed toolcalls
- error-like tool results
- retries of the same tool
- diagnostics between a failure and a retry
- mismatches between summary files and raw logs

### Artifacts and final state

Extract:

- files the agent explicitly read
- result files written and later inspected
- final kept state when the logs make it clear

### Skill evidence

Only mention skill usage when there is concrete evidence such as:

- a tool opening a `SKILL.md`
- a command explicitly targeting a skill path

Report this as `inferred skill usage`.

## Privacy Boundary

Do not output agent thinking.

- ignore `reasoning`
- ignore `encrypted_reasoning`
- do not decode or summarize hidden reasoning

This skill explains behavior from logs, not hidden chain-of-thought.

## Reporting Format

Default to a concise Markdown report with:

1. `Session overview`
2. `Behavior timeline`
3. `Tool execution summary`
4. `Failures and recovery`
5. `Artifacts and final state`
6. `Inferred skill usage`
7. `Gaps and uncertainty`

For each important step, include:

- trigger or input
- assistant action
- tools called
- outcome
- evidence source

## Failure Modes

- Missing `history.json`: rely on `context.json`, `toolcalls/*`, and `state.json`
- Missing `context.json`: restrict to user-visible history plus runtime toolcalls if present
- Missing `toolcalls/*`: fall back to `context.json` tool results
- Missing tool result for a `tool_call_id`: report it as unmatched, not failed
- Sessions with subagents: analyze each agent separately, then combine

## Resources

- `scripts/inspect_bridge_session.py`
  - behavior-focused summary for one session
- `references/log-sources.md`
  - artifact map and evidence grading
