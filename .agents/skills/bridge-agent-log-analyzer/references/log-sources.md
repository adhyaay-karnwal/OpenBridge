# Bridge Log Sources

## Session layout

Primary session path:

```text
~/.bridge/sessions/<session-id>/
```

Main agent artifacts:

```text
session-meta.json
agent/history.json
agent/context.json
agent/state.json
agent/meta.json
agent/toolcalls/<toolcall-id>/meta.json
agent/toolcalls/<toolcall-id>/output.log
```

Subagent artifacts:

```text
agents/<subagent-id>/agent/history.json
agents/<subagent-id>/agent/context.json
agents/<subagent-id>/agent/state.json
agents/<subagent-id>/agent/meta.json
agents/<subagent-id>/agent/toolcalls/<toolcall-id>/meta.json
agents/<subagent-id>/agent/toolcalls/<toolcall-id>/output.log
```

## Source-of-truth map

- `session-meta.json`
  - session title, environments, created/updated timestamps
- `history.json`
  - user-visible messages and task updates
- `context.json`
  - assistant decision points, tool calls, and immediate tool results
- `state.json`
  - model, reasoning effort, last-round counters
- `meta.json`
  - prompt/config snapshot when needed
- `toolcalls/*/meta.json`
  - runtime command, timing, environment, status, exit code, async promotion
- `toolcalls/*/output.log`
  - actual command output and error text

## Evidence grades

Use this ordering when describing confidence:

- `direct`
  - explicit persisted artifact
- `inferred`
  - plausible conclusion from indirect persisted evidence
- `unknown`
  - no supporting artifact

Examples:

- tool name from `context.json.tool_calls[].name`: `direct`
- runtime exit code from `toolcalls/*/meta.json`: `direct`
- traceback from `toolcalls/*/output.log`: `direct`
- "agent retried after diagnosing the failure" from a failure followed by diagnostic calls and a successful retry: `inferred`

## Recommended read order

1. `inspect_bridge_session.py` output
2. `history.json`
3. `context.json`
4. `toolcalls/*/meta.json`
5. `toolcalls/*/output.log`
6. `state.json`
7. `meta.json` only if prompt/config matters

## Known limitations

- `history.json` is narrower than `context.json`
- `context.json` may omit runtime details that only appear in `toolcalls/*`
- live progress events are not guaranteed to be persisted
- `session-meta.json.updated_at` may lag behind the true end of runtime activity
