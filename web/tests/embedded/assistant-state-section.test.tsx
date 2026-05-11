import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import type {
  AssistantState,
  AssistantToolCallState,
} from '../../src/embedded/chat/types/history';

vi.mock('../../src/embedded/chat/components/shiny-text/shiny-text', () => ({
  ShinyText: ({ children }: React.PropsWithChildren<Record<string, never>>) => (
    <span>{children}</span>
  ),
}));

vi.mock('../../src/utils/debug-message', () => ({
  DebugMessage: ({
    children,
  }: React.PropsWithChildren<Record<string, never>>) => <>{children}</>,
}));

vi.mock('../../src/embedded/chat/components/animated-logo', () => ({
  AnimatedLogo: () => <span data-testid="animated-logo" />,
}));

import { AssistantStateSection } from '../../src/embedded/chat/components/messages/assistant-state-section';

function makeExecutionState(
  state: Partial<AssistantState> = {}
): AssistantState {
  return {
    phase: 'execution',
    sequence: 1,
    phaseStartedAt: 90,
    updatedAt: 95,
    reasoning: undefined,
    messaging: undefined,
    tools: [],
    asyncToolcalls: [],
    ...state,
  };
}

function makeTool(
  tool: Partial<AssistantToolCallState> = {}
): AssistantToolCallState {
  return {
    callId: 'tool-1',
    toolName: 'Exec',
    summary: 'Run tests',
    args: JSON.stringify({ command: 'yarn test' }),
    startedAt: 92,
    ...tool,
  };
}

describe('AssistantStateSection timing', () => {
  it('keeps elapsed execution title while rendering OpenBridge inline tools', () => {
    const markup = renderToStaticMarkup(
      <AssistantStateSection
        state={makeExecutionState()}
        isCurrent
        inlineTools={[makeTool()]}
      />
    );

    expect(markup).toContain('Executing for 5s');
    expect(markup).toContain('Running yarn test');
  });

  it('keeps elapsed thinking title', () => {
    const markup = renderToStaticMarkup(
      <AssistantStateSection
        state={{
          ...makeExecutionState({
            phase: 'thinking',
            reasoning: {
              text: 'Planning',
              isStreaming: false,
            },
          }),
        }}
        isCurrent
      />
    );

    expect(markup).toContain('Thinking for 5s');
  });
});
