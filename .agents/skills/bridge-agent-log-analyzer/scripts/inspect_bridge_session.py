#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_ROOT = Path.home() / ".bridge" / "sessions"
SEARCHABLE_SUFFIXES = {".json", ".log", ".md", ".txt"}


@dataclass
class SessionResolution:
    requested_id: str | None
    session_dir: Path
    mode: str
    matched_path: str | None = None


@dataclass
class AgentPaths:
    agent_id: str
    kind: str
    agent_dir: Path

    @property
    def history_path(self) -> Path:
        return self.agent_dir / "history.json"

    @property
    def context_path(self) -> Path:
        return self.agent_dir / "context.json"

    @property
    def state_path(self) -> Path:
        return self.agent_dir / "state.json"

    @property
    def meta_path(self) -> Path:
        return self.agent_dir / "meta.json"

    @property
    def toolcalls_dir(self) -> Path:
        return self.agent_dir / "toolcalls"


def load_json(path: Path) -> Any | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return {"_error": f"invalid json: {exc}"}


def load_text(path: Path) -> str | None:
    if not path.exists():
        return None
    try:
        return path.read_text(errors="ignore")
    except OSError:
        return None


def preview_text(value: str, limit: int = 160) -> str:
    compact = " ".join(value.split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 3] + "..."


def ms_to_iso(value: Any) -> str | None:
    if not isinstance(value, (int, float)):
        return None
    dt = datetime.fromtimestamp(value / 1000, tz=timezone.utc)
    return dt.isoformat().replace("+00:00", "Z")


def iso_to_ms(value: Any) -> int | None:
    if not isinstance(value, str) or not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    return int(dt.timestamp() * 1000)


def first_non_null_int(values: list[int | None]) -> int | None:
    filtered = [value for value in values if isinstance(value, int)]
    if not filtered:
        return None
    return min(filtered)


def last_non_null_int(values: list[int | None]) -> int | None:
    filtered = [value for value in values if isinstance(value, int)]
    if not filtered:
        return None
    return max(filtered)


def iter_session_dirs(root: Path) -> list[Path]:
    if not root.exists():
        return []

    session_dirs = []
    for child in root.iterdir():
        if child.is_dir() and (child / "session-meta.json").exists():
            session_dirs.append(child)
    return sorted(session_dirs)


def choose_latest_session(root: Path) -> Path:
    candidates = []
    for session_dir in iter_session_dirs(root):
        meta_path = session_dir / "session-meta.json"
        try:
            candidates.append((meta_path.stat().st_mtime, session_dir))
        except OSError:
            continue
    if not candidates:
        raise SystemExit(f"no sessions found under {root}")
    candidates.sort(reverse=True)
    return candidates[0][1]


def is_searchable_file(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.suffix in SEARCHABLE_SUFFIXES:
        return True
    return path.name == "output.log"


def resolve_session(root: Path, requested_id: str | None) -> SessionResolution:
    if requested_id is None:
        session_dir = choose_latest_session(root)
        return SessionResolution(
            requested_id=None,
            session_dir=session_dir,
            mode="latest_session",
            matched_path=str(session_dir / "session-meta.json"),
        )

    direct_dir = root / requested_id
    if (direct_dir / "session-meta.json").exists():
        return SessionResolution(
            requested_id=requested_id,
            session_dir=direct_dir,
            mode="direct_session_dir",
            matched_path=str(direct_dir / "session-meta.json"),
        )

    for session_dir in reversed(iter_session_dirs(root)):
        for path in session_dir.rglob("*"):
            if not is_searchable_file(path):
                continue
            text = load_text(path)
            if text and requested_id in text:
                return SessionResolution(
                    requested_id=requested_id,
                    session_dir=session_dir,
                    mode="artifact_search",
                    matched_path=str(path),
                )

    raise SystemExit(f"session not found for id: {requested_id}")


def discover_agents(session_dir: Path) -> list[AgentPaths]:
    agents: list[AgentPaths] = []

    main_dir = session_dir / "agent"
    if main_dir.exists():
        agents.append(AgentPaths(agent_id="main", kind="main", agent_dir=main_dir))

    subagents_dir = session_dir / "agents"
    if subagents_dir.exists():
        for sub_dir in sorted(subagents_dir.iterdir()):
            agent_dir = sub_dir / "agent"
            if agent_dir.exists():
                agents.append(AgentPaths(agent_id=sub_dir.name, kind="subagent", agent_dir=agent_dir))

    return agents


def flatten_argument_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        items: list[str] = []
        for nested in value.values():
            items.extend(flatten_argument_strings(nested))
        return items
    if isinstance(value, list):
        items: list[str] = []
        for nested in value:
            items.extend(flatten_argument_strings(nested))
        return items
    return []


def normalize_argument_paths(arguments: Any) -> list[str]:
    paths = []
    for text in flatten_argument_strings(arguments):
        candidate = text.strip()
        if not candidate:
            continue
        if "/" in candidate or candidate.endswith(".md") or candidate.endswith(".json") or candidate.endswith(".log"):
            paths.append(candidate)
    deduped = []
    seen = set()
    for path in paths:
        if path in seen:
            continue
        seen.add(path)
        deduped.append(path)
    return deduped


def classify_result(content: str) -> str:
    text = content.strip().lower()
    if not text:
        return "empty"
    if text.startswith("error:") or "command exited with code" in text:
        return "error_like"
    return "ok_like"


def summarize_tasks(history: Any) -> list[dict[str, Any]]:
    if not isinstance(history, list):
        return []

    tasks: dict[str, dict[str, Any]] = {}
    for index, message in enumerate(history):
        if not isinstance(message, dict) or message.get("type") != "task":
            continue

        task_id = message.get("task_id") or f"task-{index}"
        entry = tasks.setdefault(
            task_id,
            {
                "task_id": task_id,
                "title": None,
                "actions": [],
                "final_todos": [],
            },
        )
        if message.get("task_title"):
            entry["title"] = message.get("task_title")

        todos = []
        for todo in message.get("todos") or []:
            if not isinstance(todo, dict):
                continue
            todos.append(
                {
                    "content": todo.get("content"),
                    "status": todo.get("status"),
                }
            )

        entry["actions"].append(
            {
                "history_index": index,
                "timestamp": ms_to_iso(message.get("timestamp")),
                "action": message.get("action"),
                "todo_statuses": [f"{todo['status']}:{todo['content']}" for todo in todos],
            }
        )
        if todos:
            entry["final_todos"] = todos

    return list(tasks.values())


def summarize_history(history: Any) -> dict[str, Any]:
    if not isinstance(history, list):
        return {
            "count": 0,
            "role_counts": {},
            "type_counts": {},
            "first_timestamp": None,
            "last_timestamp": None,
        }

    role_counts: dict[str, int] = {}
    type_counts: dict[str, int] = {}
    timestamps: list[int] = []
    for message in history:
        if not isinstance(message, dict):
            continue
        role = message.get("role") or "(none)"
        message_type = message.get("type") or "(none)"
        role_counts[role] = role_counts.get(role, 0) + 1
        type_counts[message_type] = type_counts.get(message_type, 0) + 1
        timestamp = message.get("timestamp")
        if isinstance(timestamp, int):
            timestamps.append(timestamp)

    return {
        "count": len(history),
        "role_counts": role_counts,
        "type_counts": type_counts,
        "first_timestamp": ms_to_iso(min(timestamps)) if timestamps else None,
        "last_timestamp": ms_to_iso(max(timestamps)) if timestamps else None,
    }


def summarize_toolcalls(paths: AgentPaths) -> list[dict[str, Any]]:
    if not paths.toolcalls_dir.exists():
        return []

    summaries = []
    for toolcall_dir in sorted(paths.toolcalls_dir.iterdir()):
        if not toolcall_dir.is_dir():
            continue

        meta_path = toolcall_dir / "meta.json"
        output_path = toolcall_dir / "output.log"
        meta = load_json(meta_path)
        output_text = load_text(output_path) or ""
        invocation = meta.get("invocation") if isinstance(meta, dict) else {}
        command = invocation.get("command") if isinstance(invocation, dict) else None

        started_at = meta.get("started_at") if isinstance(meta, dict) else None
        ended_at = meta.get("ended_at") if isinstance(meta, dict) else None
        duration_ms = None
        if isinstance(started_at, int) and isinstance(ended_at, int):
            duration_ms = ended_at - started_at

        summaries.append(
            {
                "toolcall_id": toolcall_dir.name,
                "llm_call_id": meta.get("llm_call_id") if isinstance(meta, dict) else None,
                "tool_name": meta.get("tool_name") if isinstance(meta, dict) else None,
                "status": meta.get("status") if isinstance(meta, dict) else None,
                "exit_code": meta.get("exit_code") if isinstance(meta, dict) else None,
                "requested_mode": meta.get("requested_mode") if isinstance(meta, dict) else None,
                "promoted_to_async": bool(meta.get("promoted_to_async")) if isinstance(meta, dict) else False,
                "environment_label": meta.get("environment_label") if isinstance(meta, dict) else None,
                "created_at": ms_to_iso(meta.get("created_at") if isinstance(meta, dict) else None),
                "started_at": ms_to_iso(started_at),
                "ended_at": ms_to_iso(ended_at),
                "duration_ms": duration_ms,
                "command_preview": preview_text(command or ""),
                "output_preview": preview_text(output_text, limit=200),
                "output_path": str(output_path) if output_path.exists() else None,
                "meta_path": str(meta_path) if meta_path.exists() else None,
            }
        )

    summaries.sort(key=lambda item: (item.get("started_at") or "", item["toolcall_id"]))
    return summaries


def summarize_context(context: Any, runtime_toolcalls: list[dict[str, Any]]) -> dict[str, Any]:
    if not isinstance(context, list):
        return {
            "count": 0,
            "assistant_turns": [],
            "tool_calls": [],
            "skill_evidence": [],
            "unmatched_tool_results": [],
            "read_artifacts": [],
        }

    runtime_by_llm_call_id = {
        toolcall.get("llm_call_id"): toolcall
        for toolcall in runtime_toolcalls
        if toolcall.get("llm_call_id")
    }

    tool_results: dict[str, dict[str, Any]] = {}
    for index, message in enumerate(context):
        if not isinstance(message, dict) or message.get("role") != "tool":
            continue

        tool_call_id = message.get("tool_call_id")
        if not tool_call_id:
            continue
        content = message.get("content") or ""
        tool_results[tool_call_id] = {
            "tool_call_id": tool_call_id,
            "message_index": index,
            "result_type": classify_result(content),
            "content_preview": preview_text(content),
        }

    assistant_turns = []
    tool_calls = []
    skill_evidence = []
    matched_tool_call_ids: set[str] = set()
    read_artifacts: list[str] = []

    for index, message in enumerate(context):
        if not isinstance(message, dict) or message.get("role") != "assistant":
            continue

        content = message.get("content") or ""
        turn_tools = []
        for call in message.get("tool_calls") or []:
            if not isinstance(call, dict):
                continue

            llm_call_id = call.get("id")
            arguments = call.get("arguments") or {}
            argument_paths = normalize_argument_paths(arguments)
            result = tool_results.get(llm_call_id)
            runtime = runtime_by_llm_call_id.get(llm_call_id)
            if llm_call_id and result is not None:
                matched_tool_call_ids.add(llm_call_id)

            record = {
                "message_index": index,
                "tool_call_id": llm_call_id,
                "tool_name": call.get("name"),
                "arguments_preview": preview_text(json.dumps(arguments, ensure_ascii=False)),
                "argument_paths": argument_paths,
                "has_result": result is not None,
                "result": result,
                "runtime_toolcall_id": runtime.get("toolcall_id") if runtime else None,
                "runtime_status": runtime.get("status") if runtime else None,
                "runtime_duration_ms": runtime.get("duration_ms") if runtime else None,
                "runtime_async": runtime.get("promoted_to_async") if runtime else None,
                "runtime_command_preview": runtime.get("command_preview") if runtime else None,
            }
            tool_calls.append(record)
            turn_tools.append(record)

            if call.get("name") == "read":
                read_artifacts.extend(argument_paths)

            for path in argument_paths:
                if path.endswith("SKILL.md"):
                    skill_evidence.append(
                        {
                            "message_index": index,
                            "tool_call_id": llm_call_id,
                            "tool_name": call.get("name"),
                            "skill_name": Path(path).parent.name,
                            "path": path,
                            "evidence": "tool_argument_path",
                        }
                    )

        assistant_turns.append(
            {
                "message_index": index,
                "content_preview": preview_text(content),
                "tool_names": [tool["tool_name"] for tool in turn_tools],
                "tool_call_count": len(turn_tools),
                "tool_result_types": [
                    tool["result"]["result_type"] for tool in turn_tools if tool.get("result")
                ],
            }
        )

    unmatched_tool_results = []
    for tool_call_id, result in tool_results.items():
        if tool_call_id not in matched_tool_call_ids:
            unmatched_tool_results.append(result)

    deduped_read_artifacts = []
    seen_artifacts = set()
    for path in read_artifacts:
        if path in seen_artifacts:
            continue
        seen_artifacts.add(path)
        deduped_read_artifacts.append(path)

    deduped_skill_evidence = []
    seen_skill_hits = set()
    for item in skill_evidence:
        key = (
            item.get("message_index"),
            item.get("tool_call_id"),
            item.get("tool_name"),
            item.get("path"),
        )
        if key in seen_skill_hits:
            continue
        seen_skill_hits.add(key)
        deduped_skill_evidence.append(item)

    return {
        "count": len(context),
        "assistant_turns": assistant_turns,
        "tool_calls": tool_calls,
        "skill_evidence": deduped_skill_evidence,
        "unmatched_tool_results": unmatched_tool_results,
        "read_artifacts": deduped_read_artifacts,
    }


def summarize_state(state: Any) -> dict[str, Any]:
    if not isinstance(state, dict):
        return {}

    last_round = state.get("last_round")
    summary = {
        "model": state.get("model"),
        "reasoning_effort": state.get("reasoning_effort"),
    }
    if isinstance(last_round, dict):
        summary["last_round"] = {
            "outcome": last_round.get("outcome"),
            "prompt_tokens": last_round.get("prompt_tokens"),
            "completion_tokens": last_round.get("completion_tokens"),
            "total_tokens": last_round.get("total_tokens"),
            "steps": last_round.get("steps"),
            "error": last_round.get("error"),
            "pending_confirmation_count": len(last_round.get("pending_confirmations") or []),
        }
    return summary


def summarize_meta(meta: Any) -> dict[str, Any]:
    if not isinstance(meta, dict):
        return {}

    return {
        "compaction_threshold": meta.get("compaction_threshold"),
        "max_context_tokens": meta.get("max_context_tokens"),
        "system_prompt_preview": preview_text(meta.get("system_prompt") or ""),
    }


def detect_failures(
    runtime_toolcalls: list[dict[str, Any]],
    context_summary: dict[str, Any],
) -> list[dict[str, Any]]:
    failures = []
    seen_runtime_toolcall_ids = set()

    for toolcall in runtime_toolcalls:
        if toolcall.get("status") == "succeeded":
            continue
        seen_runtime_toolcall_ids.add(toolcall.get("toolcall_id"))
        failures.append(
            {
                "source": "runtime_toolcall",
                "toolcall_id": toolcall.get("toolcall_id"),
                "llm_call_id": toolcall.get("llm_call_id"),
                "tool_name": toolcall.get("tool_name"),
                "status": toolcall.get("status"),
                "exit_code": toolcall.get("exit_code"),
                "command_preview": toolcall.get("command_preview"),
                "output_preview": toolcall.get("output_preview"),
            }
        )

    for tool in context_summary.get("tool_calls") or []:
        result = tool.get("result") or {}
        if result.get("result_type") != "error_like":
            continue
        if tool.get("runtime_toolcall_id") in seen_runtime_toolcall_ids:
            continue
        failures.append(
            {
                "source": "context_tool_result",
                "toolcall_id": tool.get("runtime_toolcall_id"),
                "llm_call_id": tool.get("tool_call_id"),
                "tool_name": tool.get("tool_name"),
                "status": "error_like_result",
                "exit_code": None,
                "command_preview": tool.get("runtime_command_preview"),
                "output_preview": result.get("content_preview"),
            }
        )

    return failures


def detect_recoveries(runtime_toolcalls: list[dict[str, Any]]) -> list[dict[str, Any]]:
    recoveries = []
    for index, toolcall in enumerate(runtime_toolcalls):
        if toolcall.get("status") == "succeeded":
            continue

        failed_command = toolcall.get("command_preview")
        for later_index, later in enumerate(runtime_toolcalls[index + 1 :], start=index + 1):
            if later.get("tool_name") != toolcall.get("tool_name"):
                continue
            if later.get("status") != "succeeded":
                continue
            later_command = later.get("command_preview")
            if failed_command and later_command and failed_command != later_command:
                continue

            intermediate_tools = [
                candidate.get("tool_name")
                for candidate in runtime_toolcalls[index + 1 : later_index]
            ]
            recoveries.append(
                {
                    "failed_toolcall_id": toolcall.get("toolcall_id"),
                    "failed_tool_name": toolcall.get("tool_name"),
                    "failed_command_preview": toolcall.get("command_preview"),
                    "recovered_by_toolcall_id": later.get("toolcall_id"),
                    "recovery_pattern": "same_tool_retry_succeeded",
                    "intermediate_tools": intermediate_tools[:8],
                }
            )
            break

    return recoveries


def summarize_behavior(
    history_summary: dict[str, Any],
    context_summary: dict[str, Any],
    runtime_toolcalls: list[dict[str, Any]],
    tasks: list[dict[str, Any]],
) -> dict[str, Any]:
    runtime_tool_name_counts = Counter()
    context_tool_name_counts = Counter()
    background_toolcalls = 0
    failed_toolcalls = 0

    for toolcall in runtime_toolcalls:
        tool_name = toolcall.get("tool_name") or "(unknown)"
        runtime_tool_name_counts[tool_name] += 1
        if toolcall.get("promoted_to_async"):
            background_toolcalls += 1
        if toolcall.get("status") != "succeeded":
            failed_toolcalls += 1

    error_like_results = 0
    for tool in context_summary.get("tool_calls") or []:
        tool_name = tool.get("tool_name") or "(unknown)"
        context_tool_name_counts[tool_name] += 1
        result = tool.get("result") or {}
        if result.get("result_type") == "error_like":
            error_like_results += 1

    return {
        "history_messages": history_summary.get("count"),
        "context_messages": context_summary.get("count"),
        "assistant_turns": len(context_summary.get("assistant_turns") or []),
        "assistant_tool_calls": len(context_summary.get("tool_calls") or []),
        "task_count": len(tasks),
        "runtime_toolcalls": len(runtime_toolcalls),
        "background_toolcalls": background_toolcalls,
        "failed_runtime_toolcalls": failed_toolcalls,
        "error_like_tool_results": error_like_results,
        "context_tools_by_name": dict(sorted(context_tool_name_counts.items())),
        "runtime_tools_by_name": dict(sorted(runtime_tool_name_counts.items())),
    }


def summarize_time_bounds(
    session_meta: Any,
    history_summary: dict[str, Any],
    runtime_toolcalls: list[dict[str, Any]],
) -> dict[str, Any]:
    session_created = iso_to_ms(session_meta.get("created_at")) if isinstance(session_meta, dict) else None
    session_updated = iso_to_ms(session_meta.get("updated_at")) if isinstance(session_meta, dict) else None
    history_first = iso_to_ms(history_summary.get("first_timestamp"))
    history_last = iso_to_ms(history_summary.get("last_timestamp"))

    tool_start_candidates = []
    tool_end_candidates = []
    for toolcall in runtime_toolcalls:
        tool_start_candidates.append(iso_to_ms(toolcall.get("started_at")))
        tool_end_candidates.append(iso_to_ms(toolcall.get("ended_at")))

    effective_start = first_non_null_int([session_created, history_first, *tool_start_candidates])
    effective_end = last_non_null_int([session_updated, history_last, *tool_end_candidates])

    duration_ms = None
    if isinstance(effective_start, int) and isinstance(effective_end, int):
        duration_ms = effective_end - effective_start

    return {
        "session_meta_created_at": ms_to_iso(session_created),
        "session_meta_updated_at": ms_to_iso(session_updated),
        "history_first_timestamp": ms_to_iso(history_first),
        "history_last_timestamp": ms_to_iso(history_last),
        "first_tool_started_at": ms_to_iso(first_non_null_int(tool_start_candidates)),
        "last_tool_ended_at": ms_to_iso(last_non_null_int(tool_end_candidates)),
        "effective_started_at": ms_to_iso(effective_start),
        "effective_ended_at": ms_to_iso(effective_end),
        "effective_duration_ms": duration_ms,
    }


def summarize_agent(paths: AgentPaths) -> dict[str, Any]:
    history = load_json(paths.history_path)
    context = load_json(paths.context_path)
    state = load_json(paths.state_path)
    meta = load_json(paths.meta_path)

    artifact_paths = {
        "history": str(paths.history_path),
        "context": str(paths.context_path),
        "state": str(paths.state_path),
        "meta": str(paths.meta_path),
        "toolcalls": str(paths.toolcalls_dir),
    }
    artifact_presence = {
        "history": paths.history_path.exists(),
        "context": paths.context_path.exists(),
        "state": paths.state_path.exists(),
        "meta": paths.meta_path.exists(),
        "toolcalls": paths.toolcalls_dir.exists(),
    }

    anomalies = []
    if artifact_presence["context"] and not artifact_presence["history"]:
        anomalies.append("context_without_history")
    if artifact_presence["history"] and not artifact_presence["context"]:
        anomalies.append("history_without_context")

    runtime_toolcalls = summarize_toolcalls(paths)
    history_summary = summarize_history(history)
    tasks = summarize_tasks(history)
    context_summary = summarize_context(context, runtime_toolcalls)
    failures = detect_failures(runtime_toolcalls, context_summary)
    recoveries = detect_recoveries(runtime_toolcalls)
    if context_summary["unmatched_tool_results"]:
        anomalies.append("unmatched_tool_results")

    return {
        "agent_id": paths.agent_id,
        "kind": paths.kind,
        "agent_dir": str(paths.agent_dir),
        "artifacts": {
            "paths": artifact_paths,
            "present": artifact_presence,
        },
        "timing": summarize_time_bounds({}, history_summary, runtime_toolcalls),
        "behavior_summary": summarize_behavior(history_summary, context_summary, runtime_toolcalls, tasks),
        "tasks": tasks,
        "assistant_timeline": context_summary["assistant_turns"],
        "runtime_toolcalls": runtime_toolcalls,
        "failures": failures,
        "recovery_sequences": recoveries,
        "read_artifacts": context_summary["read_artifacts"],
        "skill_evidence": context_summary["skill_evidence"],
        "unmatched_tool_results": context_summary["unmatched_tool_results"],
        "state_summary": summarize_state(state),
        "meta_summary": summarize_meta(meta),
        "anomalies": anomalies,
    }


def build_summary(root: Path, resolution: SessionResolution) -> dict[str, Any]:
    session_dir = resolution.session_dir
    session_meta = load_json(session_dir / "session-meta.json")
    agents = discover_agents(session_dir)
    summarized_agents = [summarize_agent(agent) for agent in agents]

    runtime_toolcalls = [
        toolcall
        for agent in summarized_agents
        for toolcall in agent.get("runtime_toolcalls") or []
    ]
    session_history_first = []
    session_history_last = []
    for agent in summarized_agents:
        timing = agent.get("timing") or {}
        session_history_first.append(iso_to_ms(timing.get("history_first_timestamp")))
        session_history_last.append(iso_to_ms(timing.get("history_last_timestamp")))

    session_timing = {
        "session_meta_created_at": session_meta.get("created_at") if isinstance(session_meta, dict) else None,
        "session_meta_updated_at": session_meta.get("updated_at") if isinstance(session_meta, dict) else None,
        "history_first_timestamp": ms_to_iso(first_non_null_int(session_history_first)),
        "history_last_timestamp": ms_to_iso(last_non_null_int(session_history_last)),
        "first_tool_started_at": ms_to_iso(
            first_non_null_int([iso_to_ms(toolcall.get("started_at")) for toolcall in runtime_toolcalls])
        ),
        "last_tool_ended_at": ms_to_iso(
            last_non_null_int([iso_to_ms(toolcall.get("ended_at")) for toolcall in runtime_toolcalls])
        ),
    }
    effective_start = first_non_null_int(
        [
            iso_to_ms(session_timing["session_meta_created_at"]),
            iso_to_ms(session_timing["history_first_timestamp"]),
            iso_to_ms(session_timing["first_tool_started_at"]),
        ]
    )
    effective_end = last_non_null_int(
        [
            iso_to_ms(session_timing["session_meta_updated_at"]),
            iso_to_ms(session_timing["history_last_timestamp"]),
            iso_to_ms(session_timing["last_tool_ended_at"]),
        ]
    )
    session_timing["effective_started_at"] = ms_to_iso(effective_start)
    session_timing["effective_ended_at"] = ms_to_iso(effective_end)
    session_timing["effective_duration_ms"] = (
        effective_end - effective_start
        if isinstance(effective_start, int) and isinstance(effective_end, int)
        else None
    )

    return {
        "root": str(root),
        "requested_id": resolution.requested_id,
        "resolution": {
            "mode": resolution.mode,
            "matched_path": resolution.matched_path,
        },
        "session_id": session_dir.name,
        "session_dir": str(session_dir),
        "session_meta_path": str(session_dir / "session-meta.json"),
        "session_meta": session_meta,
        "session_timing": session_timing,
        "agent_count": len(agents),
        "agents": summarized_agents,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Inspect one Bridge session and emit a behavior-focused JSON summary "
            "covering history, context, runtime toolcalls, failures, and recoveries."
        ),
    )
    parser.add_argument(
        "--root",
        default=str(DEFAULT_ROOT),
        help="Session root directory. Defaults to ~/.bridge/sessions.",
    )
    parser.add_argument(
        "--session-id",
        help=(
            "Session directory ID or any UUID/string that appears in that session's persisted logs. "
            "Defaults to the most recently updated session."
        ),
    )
    args = parser.parse_args()

    root = Path(args.root).expanduser()
    resolution = resolve_session(root, args.session_id)
    summary = build_summary(root, resolution)
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
