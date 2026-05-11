export type ToolCallStatus = 'running' | 'completed' | 'failed';

export type ToolCallStatusPayload = {
  kind: 'tool_call';
  tool_name: string;
  summary?: string;
  arguments?: string;
  command?: string;
  status: ToolCallStatus;
  completed: boolean;
};

type ToolCallArgs = Record<string, unknown>;

const SUMMARY_MAX_LENGTH = 96;

function parseJSON(raw?: string | null): unknown {
  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function trimString(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed || undefined;
}

function trimArray(values: unknown): string[] {
  if (!Array.isArray(values)) {
    return [];
  }

  return values
    .map(value => trimString(value))
    .filter((value): value is string => value !== undefined);
}

function shorten(text: string, maxLength = SUMMARY_MAX_LENGTH): string {
  if (text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, maxLength - 1).trimEnd()}...`;
}

function quote(text: string | undefined, fallback: string): string {
  return text ? `"${shorten(text, 40)}"` : fallback;
}

function environmentLocation(
  environment: string | undefined
): { preposition: 'in' | 'on'; label: string } | undefined {
  if (!environment) {
    return undefined;
  }

  const trimmed = environment.trim();
  if (!trimmed) {
    return undefined;
  }

  const normalized = trimmed.toLowerCase().replace(/_/g, '-');
  if (normalized === 'vfs') {
    return undefined;
  }
  if (normalized === 'local-vm' || normalized.startsWith('local-vm-')) {
    return { preposition: 'in', label: 'a safe workspace on this Mac' };
  }
  if (normalized === 'local' || normalized.startsWith('local-')) {
    return { preposition: 'on', label: 'this Mac' };
  }
  if (normalized === 'cloud-vm') {
    return { preposition: 'in', label: 'a safe workspace on this Mac' };
  }

  return { preposition: 'in', label: trimmed };
}

function humanizeToolName(toolName: string): string {
  if (!toolName) {
    return 'Tool call';
  }

  const withSpaces = toolName
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .trim();

  if (!withSpaces) {
    return 'Tool call';
  }

  return withSpaces[0].toUpperCase() + withSpaces.slice(1);
}

export function getToolDisplayName(toolName: string): string {
  switch (toolName) {
    case 'Read':
      return 'Read File';
    case 'Write':
      return 'Write File';
    case 'Edit':
      return 'Edit File';
    case 'Delete':
      return 'Delete File';
    case 'Stat':
      return 'Inspect File';
    case 'List':
      return 'List Files';
    case 'Glob':
      return 'Find Files';
    case 'Grep':
      return 'Search Files';
    case 'Copy':
      return 'Copy File';
    case 'JavaScript':
      return 'Run JavaScript';
    case 'Exec':
    case 'bash':
    case 'Bash':
      return 'Run Command';
    case 'python':
    case 'Python':
      return 'Run Python';
    case 'RequestPermission':
      return 'Request Permission';
    case 'wait_for':
      return 'Wait';
    case 'ExaSearch':
      return 'Web Search';
    case 'ExaContents':
      return 'Fetch Web Pages';
    case 'WebBrowse':
      return 'Browse Website';
    case 'cancel_operation':
      return 'Cancel Operation';
    case 'ListEnvironments':
      return 'List Workspaces';
    case 'ComputerUse':
      return 'Computer Use';
    case 'manage_task':
      return 'Todo List';
    case 'manage_schedule':
      return 'Schedule Manager';
    case 'manage_memory':
      return 'Memory Manager';
    default:
      return humanizeToolName(toolName);
  }
}

export function getToolCallDisplayName(params: {
  toolName: string;
  argumentsText?: string;
  command?: string;
  summary?: string;
  status?: ToolCallStatus;
}): string {
  const args = asArgs(params.argumentsText);
  const status = params.status ?? 'running';
  const toolName = params.toolName.toLowerCase();
  const phase = status === 'running' ? 'running' : status;
  const path = trimString(args.path);
  const environment = trimString(args.environment);

  switch (toolName) {
    case 'read':
      return shorten(
        `${phaseVerb(phase, 'Reading', 'Read', 'Failed reading')} ${pathLabel(path, environment)}`
      );
    case 'write':
      return shorten(
        `${phaseVerb(phase, 'Writing', 'Wrote', 'Failed writing')} ${pathLabel(path, environment)}`
      );
    case 'edit':
      return shorten(
        `${phaseVerb(phase, 'Editing', 'Edited', 'Failed editing')} ${pathLabel(path, environment)}`
      );
    case 'delete':
      return shorten(
        `${phaseVerb(phase, 'Deleting', 'Deleted', 'Failed deleting')} ${pathLabel(path, environment)}`
      );
    case 'stat':
      return shorten(
        `${phaseVerb(phase, 'Inspecting', 'Inspected', 'Failed inspecting')} ${pathLabel(path, environment)}`
      );
    case 'list':
    case 'ls':
      return shorten(
        `${phaseVerb(phase, 'Reading', 'Read', 'Failed reading')} ${pathLabel(path ?? 'directory', environment)}`
      );
    case 'glob':
    case 'find': {
      const pattern = trimString(args.pattern) ?? 'files';
      const basePath = trimString(args.path) ?? '/';
      return shorten(
        `${phaseVerb(phase, 'Finding', 'Found', 'Failed finding')} ${pattern} in ${basePath}${environmentSuffix(environment)}`
      );
    }
    case 'grep': {
      const pattern = trimString(args.pattern) ?? 'pattern';
      const basePath = trimString(args.path);
      const suffix = basePath
        ? ` in ${basePath}${environmentSuffix(environment)}`
        : environmentSuffix(environment);
      return shorten(
        `${phaseVerb(phase, 'Grep', 'Grepped', 'Failed grep')} ${pattern}${suffix}`
      );
    }
    case 'exec':
    case 'bash': {
      const label =
        trimString(args.command) ??
        trimString(args.description) ??
        trimString(params.command) ??
        extractQuotedActionLabel(params.summary, 'Run') ??
        'command';
      const runtime = toolName === 'bash' ? 'bash ' : '';
      return shorten(
        `${phaseVerb(phase, 'Running', 'Ran', 'Failed running')} ${runtime}${label}${environmentSuffix(environment)}`
      );
    }
    case 'python': {
      const label =
        trimString(args.command) ??
        trimString(args.description) ??
        trimString(params.command) ??
        'python';
      return shorten(
        `${phaseVerb(phase, 'Running', 'Ran', 'Failed running')} python ${label}${environmentSuffix(environment)}`
      );
    }
    case 'manage_task':
      return summarizeTodoListAction(args, status);
  }

  switch (params.toolName) {
    case 'Exec': {
      const label =
        trimString(args.description) ??
        trimString(args.command) ??
        trimString(params.command) ??
        extractQuotedActionLabel(params.summary, 'Run');
      return `Run ${label ?? 'command'}`;
    }
    case 'Read': {
      const label =
        trimString(args.path) ?? extractActionLabel(params.summary, 'Read');
      return `Read ${label ?? 'file'}`;
    }
    default:
      return getToolDisplayName(params.toolName);
  }
}

function phaseVerb(
  phase: ToolCallStatus,
  running: string,
  completed: string,
  failed: string
): string {
  switch (phase) {
    case 'running':
      return running;
    case 'failed':
      return failed;
    case 'completed':
      return completed;
  }
}

function extractQuotedActionLabel(
  summary: string | undefined,
  verb: string
): string | undefined {
  const trimmed = trimString(summary);
  if (!trimmed) {
    return undefined;
  }
  const match = new RegExp(`^${verb}\\s+"([^"]+)"`).exec(trimmed);
  return match?.[1]?.trim() || undefined;
}

function extractActionLabel(
  summary: string | undefined,
  verb: string
): string | undefined {
  const trimmed = trimString(summary);
  if (!trimmed || !trimmed.startsWith(`${verb} `)) {
    return undefined;
  }
  return trimmed.slice(verb.length + 1).trim() || undefined;
}

function environmentSuffix(environment: string | undefined): string {
  const location = environmentLocation(environment);
  if (!location) {
    return '';
  }

  return ` ${location.preposition} ${location.label}`;
}

function pathLabel(
  path: string | undefined,
  environment: string | undefined
): string {
  return `${path ?? 'file'}${environmentSuffix(environment)}`;
}

function formatTimeout(seconds: number | undefined): string | undefined {
  if (!Number.isFinite(seconds) || !seconds || seconds <= 0) {
    return undefined;
  }

  if (seconds < 60) {
    return `${seconds}s`;
  }

  const minutes = Math.floor(seconds / 60);
  const remain = seconds % 60;
  if (remain === 0) {
    return `${minutes}m`;
  }

  return `${minutes}m ${remain}s`;
}

function urlLabel(rawURL: string | undefined): string | undefined {
  if (!rawURL) {
    return undefined;
  }

  try {
    return new URL(rawURL).hostname || rawURL;
  } catch {
    return rawURL;
  }
}

function shortIdentifier(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }

  return value.length > 12 ? value.slice(0, 12) : value;
}

function asArgs(argumentsText?: string): ToolCallArgs {
  const parsed = parseJSON(argumentsText);
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return {};
  }

  return parsed as ToolCallArgs;
}

export function normalizeToolCallStatus(
  status: string | undefined
): ToolCallStatus {
  return status === 'completed' || status === 'failed' ? status : 'running';
}

function summarizeCopy(args: ToolCallArgs): string {
  const srcPath = trimString(args.src_path) ?? 'source';
  const dstPath = trimString(args.dst_path) ?? 'destination';
  const srcEnv = trimString(args.src_environment);
  const dstEnv = trimString(args.dst_environment);
  return shorten(
    `Copy ${srcPath}${environmentSuffix(srcEnv)} to ${dstPath}${environmentSuffix(dstEnv)}`
  );
}

function summarizeTodoListAction(
  args: ToolCallArgs,
  status: ToolCallStatus
): string {
  const action = trimString(args.action);
  const title = trimString(args.title);
  const target = title ? ` for ${title}` : '';

  switch (action) {
    case 'start':
      return shorten(
        `${phaseVerb(status, 'Writing', 'Wrote', 'Failed writing')} todo list${target}`
      );
    case 'update':
      return shorten(
        `${phaseVerb(status, 'Updating', 'Updated', 'Failed updating')} todo list${target}`
      );
    case 'complete':
    case 'end':
      return shorten(
        `${phaseVerb(status, 'Completing', 'Completed', 'Failed completing')} todo list${target}`
      );
    case 'cancel':
      return shorten(
        `${phaseVerb(status, 'Cancelling', 'Cancelled', 'Failed cancelling')} todo list${target}`
      );
    default:
      return shorten(
        `${phaseVerb(status, 'Updating', 'Updated', 'Failed updating')} todo list${target}`
      );
  }
}

function summarizeManageTask(args: ToolCallArgs): string {
  return summarizeTodoListAction(args, 'running');
}

function summarizeManageSchedule(args: ToolCallArgs): string {
  const action = trimString(args.action) ?? 'list';
  const name = trimString(args.name);
  const scheduleId = trimString(args.schedule_id);

  switch (action) {
    case 'create':
      return shorten(`Create schedule ${quote(name, 'schedule')}`);
    case 'list':
      return 'List schedules';
    case 'get':
      return shorten(`Inspect schedule ${scheduleId ?? 'schedule'}`);
    case 'update':
      return shorten(
        `Update schedule ${scheduleId ?? quote(name, 'schedule')}`
      );
    case 'pause':
      return shorten(`Pause schedule ${scheduleId ?? 'schedule'}`);
    case 'resume':
      return shorten(`Resume schedule ${scheduleId ?? 'schedule'}`);
    case 'delete':
      return shorten(`Delete schedule ${scheduleId ?? 'schedule'}`);
    default:
      return 'Manage schedule';
  }
}

function summarizeComputerUse(args: ToolCallArgs): string {
  const action = trimString(args.action);
  const environment = trimString(args.environment);

  if (!action) {
    return shorten(`Computer Use${environmentSuffix(environment)}`);
  }

  return shorten(
    `Computer Use: ${humanizeToolName(action)}${environmentSuffix(environment)}`
  );
}

export function describeToolCallSummary(params: {
  toolName: string;
  argumentsText?: string;
}): string {
  const { toolName } = params;
  const args = asArgs(params.argumentsText);

  switch (toolName) {
    case 'Read':
      return shorten(
        `Read ${pathLabel(trimString(args.path), trimString(args.environment))}`
      );
    case 'Write':
      return shorten(
        `Write ${pathLabel(trimString(args.path), trimString(args.environment))}`
      );
    case 'Edit':
      return shorten(
        `Edit ${pathLabel(trimString(args.path), trimString(args.environment))}`
      );
    case 'Delete':
      return shorten(
        `${args.recursive === true ? 'Delete recursively ' : 'Delete '}${pathLabel(trimString(args.path), trimString(args.environment))}`
      );
    case 'Stat':
      return shorten(
        `Inspect ${pathLabel(trimString(args.path), trimString(args.environment))}`
      );
    case 'List':
      return shorten(
        `${args.recursive === true ? 'List recursively ' : 'List '}${pathLabel(trimString(args.path), trimString(args.environment))}`
      );
    case 'Glob':
      return shorten(
        `Find ${quote(trimString(args.pattern), 'files')} in ${trimString(args.path) ?? '/'}${environmentSuffix(trimString(args.environment))}`
      );
    case 'Grep':
      return shorten(
        `Search ${trimString(args.path) ?? '/'}${environmentSuffix(trimString(args.environment))} for ${quote(trimString(args.pattern), 'pattern')}`
      );
    case 'Copy':
      return summarizeCopy(args);
    case 'JavaScript':
      return 'Run JavaScript';
    case 'Exec': {
      const description = trimString(args.description);
      const command = trimString(args.command);
      const environment = trimString(args.environment);
      const label = description ?? command ?? 'command';
      return shorten(
        `Run ${quote(label, 'command')}${environmentSuffix(environment)}`
      );
    }
    case 'RequestPermission':
      return shorten(
        `Request permission for ${quote(trimString(args.description), 'action')}${environmentSuffix(trimString(args.environment))}`
      );
    case 'wait_for': {
      const duration =
        formatTimeout(
          typeof args.timeout_seconds === 'number'
            ? args.timeout_seconds
            : undefined
        ) ?? 'a while';
      return shorten(
        `Wait ${duration} for ${quote(trimString(args.reason), 'event')}`
      );
    }
    case 'ExaSearch':
      return shorten(
        `Search web for ${quote(trimString(args.query), 'query')}`
      );
    case 'ExaContents': {
      const urls = trimArray(args.urls);
      if (urls.length === 0) {
        return 'Fetch web pages';
      }
      if (urls.length === 1) {
        return shorten(`Fetch ${urlLabel(urls[0]) ?? urls[0]}`);
      }
      return shorten(`Fetch ${urls.length} web pages`);
    }
    case 'WebBrowse': {
      const target = urlLabel(trimString(args.url)) ?? trimString(args.url);
      const goal = trimString(args.goal);
      if (target && goal) {
        return shorten(`Browse ${target} for ${quote(goal, 'goal')}`);
      }
      if (target) {
        return shorten(`Browse ${target}`);
      }
      return 'Browse website';
    }
    case 'cancel_operation':
      return shorten(
        `Cancel operation ${shortIdentifier(trimString(args.operation_id)) ?? 'operation'}`
      );
    case 'ListEnvironments':
      return 'List environments';
    case 'ComputerUse':
      return summarizeComputerUse(args);
    case 'manage_task':
      return summarizeManageTask(args);
    case 'manage_schedule':
      return summarizeManageSchedule(args);
    default:
      return humanizeToolName(toolName);
  }
}

export function createToolCallStatusContent(params: {
  toolName: string;
  argumentsText?: string;
  status: ToolCallStatus;
}): string {
  const args = asArgs(params.argumentsText);
  const command =
    params.toolName === 'Exec' ? trimString(args.command) : undefined;

  return JSON.stringify({
    kind: 'tool_call',
    tool_name: params.toolName,
    arguments: params.argumentsText,
    command,
    status: params.status,
    completed: params.status !== 'running',
  } satisfies ToolCallStatusPayload);
}

export function tryParseToolCallStatusPayload(
  jsonText: string
): ToolCallStatusPayload | null {
  try {
    const parsed = JSON.parse(jsonText);
    if (
      typeof parsed !== 'object' ||
      parsed === null ||
      parsed.kind !== 'tool_call' ||
      typeof parsed.tool_name !== 'string' ||
      (parsed.status !== 'running' &&
        parsed.status !== 'completed' &&
        parsed.status !== 'failed')
    ) {
      return null;
    }

    return {
      kind: 'tool_call',
      tool_name: parsed.tool_name,
      summary:
        typeof parsed.summary === 'string' && parsed.summary.trim()
          ? parsed.summary
          : undefined,
      arguments:
        typeof parsed.arguments === 'string' && parsed.arguments.trim()
          ? parsed.arguments.trim()
          : undefined,
      command:
        typeof parsed.command === 'string' && parsed.command.trim()
          ? parsed.command.trim()
          : undefined,
      status: parsed.status,
      completed:
        typeof parsed.completed === 'boolean'
          ? parsed.completed
          : parsed.status !== 'running',
    };
  } catch {
    return null;
  }
}
