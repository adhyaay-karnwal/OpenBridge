import { ChevronRightSFSymbolMedium } from '@/assets/sf-symbols/medium/chevron.right';
import { cn } from '@/utils/cn';
import { useEffect, useMemo, useRef, useState } from 'react';
import type {
  AssistantState,
  AssistantToolCallState,
} from '../../types/history';
import { ShinyText } from '../shiny-text/shiny-text';
import { DebugMessage } from '@/utils/debug-message';
import { AnimatePresence, motion } from 'motion/react';
import { AnimatedLogo } from '../animated-logo';
import {
  getToolCallDisplayName,
  normalizeToolCallStatus,
} from '@/utils/tool-call-status';

const formatSeconds = (seconds: number) => {
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const remain = seconds % 60;
  if (remain === 0) return `${minutes}m`;
  return `${minutes}m ${remain}s`;
};

const executionToolNames = new Set(['exec', 'bash', 'python']);

const parseJSON = (raw?: string) => {
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as unknown;
  } catch {
    return undefined;
  }
};

const omitToolDebugPayload = (tool: AssistantToolCallState) => ({
  callId: tool.callId,
  toolName: tool.toolName,
  summary: tool.summary,
  startedAt: tool.startedAt,
  endedAt: tool.endedAt,
  success: tool.success,
  error: tool.error,
  status: tool.status,
  statusUpdatedAt: tool.statusUpdatedAt,
});

const getToolDescription = (
  tool: AssistantToolCallState,
  args: unknown
): string | undefined => {
  if (!executionToolNames.has(tool.toolName.toLowerCase())) {
    return undefined;
  }
  if (!args || typeof args !== 'object') {
    return undefined;
  }
  const description = (args as Record<string, unknown>).description;
  if (typeof description !== 'string') {
    return undefined;
  }
  const trimmed = description.trim();
  return trimmed || undefined;
};

const getToolDisplayDetail = (tool: AssistantToolCallState, args: unknown) => {
  if (tool.error?.trim()) {
    return tool.error.trim();
  }

  return getToolDescription(tool, args);
};

const ToolRow = ({
  tool,
  isCurrentExecution,
}: {
  tool: AssistantToolCallState;
  isCurrentExecution: boolean;
}) => {
  const args = parseJSON(tool.args);
  const result = parseJSON(tool.result);
  const detail = getToolDisplayDetail(tool, args);
  const displayName = getToolCallDisplayName({
    toolName: tool.toolName,
    argumentsText: tool.args,
    status: normalizeToolCallStatus(tool.status),
  });
  const isRunning = tool.endedAt === undefined;
  const useShiny = isCurrentExecution && isRunning;
  const showDetail = detail !== undefined && detail.trim() !== displayName;
  const debugPayload = {
    args,
    result,
    meta: omitToolDebugPayload(tool),
  };

  const content = useShiny ? (
    <div className="flex min-w-0 flex-col gap-0.5">
      <ShinyText className="text-sm font-medium text-text-secondary">
        {displayName}
      </ShinyText>
      {showDetail ? (
        <span className="text-xs text-text-tertiary">{detail}</span>
      ) : null}
    </div>
  ) : (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="text-sm font-medium text-text-secondary">
        {displayName}
      </span>
      {showDetail ? (
        <span className="text-xs text-text-tertiary">{detail}</span>
      ) : null}
    </div>
  );

  return (
    <DebugMessage title={`Tool call: ${displayName}`} data={debugPayload}>
      {content}
    </DebugMessage>
  );
};

const usePhaseSeconds = (state: AssistantState, isCurrent: boolean) => {
  // phaseStartedAt and updatedAt are Unix timestamps in seconds (from Swift's
  // Date().timeIntervalSince1970), so the difference is already in seconds.
  const baseSeconds = useMemo(
    () => Math.floor(Math.max(0, state.updatedAt - state.phaseStartedAt)),
    [state.updatedAt, state.phaseStartedAt]
  );

  const [seconds, setSeconds] = useState(baseSeconds);

  useEffect(() => {
    setSeconds(baseSeconds);
  }, [baseSeconds, state.sequence]);

  useEffect(() => {
    if (!isCurrent) {
      return;
    }

    const interval = setInterval(() => {
      setSeconds(Math.floor(Date.now() / 1000 - state.phaseStartedAt));
    }, 1000);

    return () => clearInterval(interval);
  }, [isCurrent, state.phaseStartedAt]);

  return seconds;
};

export const AssistantStateSection = ({
  state,
  isCurrent,
  inlineTools = [],
  inlineEntries = [],
  titleOverride,
}: {
  state: AssistantState;
  isCurrent: boolean;
  inlineTools?: AssistantToolCallState[];
  inlineEntries?: React.ReactNode[];
  titleOverride?: string;
}) => {
  const seconds = usePhaseSeconds(state, isCurrent);
  const elapsedTitle =
    state.phase === 'execution'
      ? `${isCurrent ? 'Executing' : 'Executed'} for ${formatSeconds(seconds)}`
      : `${isCurrent ? 'Thinking' : 'Thought'} for ${formatSeconds(seconds)}`;
  const collapsedTitle = titleOverride ?? elapsedTitle;
  const currentTitle = titleOverride ?? elapsedTitle;

  const reasoningText = state.reasoning?.text?.trim() ?? '';
  const executionTools = inlineTools;
  const hasDetails =
    state.phase === 'thinking'
      ? reasoningText.length > 0
      : executionTools.length > 0 || inlineEntries.length > 0;
  const stateKey = `${state.sequence}:${state.phase}:${titleOverride ?? ''}`;
  const [expanded, setExpanded] = useState(
    state.phase === 'execution' && isCurrent && hasDetails
  );
  const userToggledStateKeyRef = useRef<string | null>(null);
  const lastResetStateKeyRef = useRef<string | null>(null);
  const wasCurrentRef = useRef(isCurrent);

  useEffect(() => {
    if (lastResetStateKeyRef.current === stateKey) {
      return;
    }

    lastResetStateKeyRef.current = stateKey;
    userToggledStateKeyRef.current = null;
    setExpanded(state.phase === 'execution' && isCurrent && hasDetails);
  }, [hasDetails, isCurrent, state.phase, stateKey]);

  useEffect(() => {
    if (
      userToggledStateKeyRef.current === stateKey ||
      state.phase !== 'execution' ||
      !isCurrent ||
      !hasDetails ||
      expanded
    ) {
      return;
    }

    setExpanded(true);
  }, [expanded, hasDetails, isCurrent, state.phase, stateKey]);

  useEffect(() => {
    if (wasCurrentRef.current && !isCurrent && state.phase === 'execution') {
      setExpanded(false);
      userToggledStateKeyRef.current = null;
    }

    wasCurrentRef.current = isCurrent;
  }, [isCurrent, state.phase]);

  const toolsToRender =
    expanded && state.phase === 'execution' ? executionTools : [];
  const visibleInlineEntries =
    expanded && state.phase === 'execution' ? inlineEntries : [];
  const shouldRenderDetails =
    (state.phase === 'thinking' && expanded && reasoningText.length > 0) ||
    (state.phase === 'execution' &&
      (toolsToRender.length > 0 || visibleInlineEntries.length > 0));

  if (!isCurrent && !hasDetails) {
    return null;
  }

  return (
    <div className="mb-1">
      {hasDetails ? (
        <WithLogoAnimation playing={isCurrent}>
          <button
            type="button"
            onClick={() => {
              userToggledStateKeyRef.current = stateKey;
              setExpanded(v => !v);
            }}
            className={cn(
              'group text-sm text-text-secondary transition-opacity hover:opacity-80 cursor-pointer',
              'flex items-center gap-1'
            )}
          >
            {isCurrent ? (
              <ShinyText className="text-sm text-text-secondary">
                {currentTitle}
              </ShinyText>
            ) : (
              <span>{collapsedTitle}</span>
            )}
            <ChevronRightSFSymbolMedium
              className={cn(
                'h-2.5 w-2.5 shrink-0 transition-all duration-200',
                expanded
                  ? 'rotate-90 opacity-100'
                  : 'opacity-0 group-hover:opacity-100'
              )}
            />
          </button>
        </WithLogoAnimation>
      ) : isCurrent ? (
        <WithLogoAnimation playing key="current-state-title">
          <ShinyText className="text-sm text-text-secondary">
            {currentTitle}
          </ShinyText>
        </WithLogoAnimation>
      ) : (
        <WithLogoAnimation playing={false} key="current-state-title">
          <span className="text-sm text-text-secondary">{collapsedTitle}</span>
        </WithLogoAnimation>
      )}

      {shouldRenderDetails ? (
        <div className="mt-1 pl-2 border-l-2 border-black/5 dark:border-white/10">
          {state.phase === 'thinking' ? (
            <div className="text-xs leading-5 text-text-secondary/75 whitespace-pre-wrap">
              {reasoningText}
            </div>
          ) : (
            <div className="flex flex-col gap-1">
              {toolsToRender.map(tool => (
                <ToolRow
                  key={tool.callId}
                  tool={tool}
                  isCurrentExecution={isCurrent}
                />
              ))}
              {visibleInlineEntries}
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
};

export const WithLogoAnimation = ({
  children,
  playing,
  gap = 4,
}: {
  children: React.ReactNode;
  playing?: boolean;
  gap?: number;
  logoSize?: number;
}) => {
  return (
    <div className="flex items-center">
      <AnimatePresence>
        {playing && (
          <motion.div
            className="h-5 flex"
            initial={{ opacity: 0, width: 0, marginRight: 0, scale: 0 }}
            animate={{ opacity: 1, width: 20, marginRight: gap, scale: 1 }}
            exit={{ opacity: 0, width: 0, marginRight: 0, scale: 0 }}
            transition={{ duration: 0.2 }}
          >
            <AnimatedLogo />
          </motion.div>
        )}
      </AnimatePresence>
      {children}
    </div>
  );
};
