import { describe, expect, it } from 'vitest';
import {
  findLatestUserMessageId,
  getActiveAssistantTurn,
  groupConversationTimelineItems,
  mergeAdjacentAssistantGroups,
  reorderActiveTurnGroups,
  splitCurrentConversationGroups,
  shouldHideAssistantOperations,
  type ConversationTimelineItem,
  type ConversationMessageGroup,
} from '../../src/embedded/chat/components/messages/assistant-turn';
import type {
  AssistantState,
  SessionHistoryMessage,
} from '../../src/embedded/chat/types/history';

function makeMessage(
  message: Partial<SessionHistoryMessage>
): SessionHistoryMessage {
  return {
    id: message.id ?? 'message-id',
    type: message.type ?? 'message',
    timestamp: message.timestamp ?? 1,
    ...message,
  };
}

function makeState(state: Partial<AssistantState>): AssistantState {
  return {
    phase: state.phase ?? 'execution',
    sequence: state.sequence ?? 1,
    phaseStartedAt: state.phaseStartedAt ?? 1,
    updatedAt: state.updatedAt ?? 1,
    tools: state.tools ?? [],
    asyncToolcalls: state.asyncToolcalls ?? [],
    reasoning: state.reasoning,
    messaging: state.messaging,
  };
}

describe('conversation-thread', () => {
  it('tracks the latest user as the active assistant turn anchor', () => {
    const messages = [
      makeMessage({
        id: 'user-0',
        role: 'user',
        timestamp: 1,
      }),
      makeMessage({
        id: 'assistant-0',
        role: 'assistant',
        timestamp: 2,
        content: [{ type: 'text', text: 'Done' }],
      }),
      makeMessage({
        id: 'user-1',
        role: 'user',
        timestamp: 10,
      }),
    ];
    const currentAssistantState = makeState({
      sequence: 42,
      phase: 'thinking',
      phaseStartedAt: 9.5,
    });

    expect(findLatestUserMessageId(messages)).toBe('user-1');
    expect(getActiveAssistantTurn(messages, currentAssistantState)).toEqual({
      userMessageId: 'user-1',
      startedAt: 9.5,
    });
  });

  it('keeps active turn items behind the triggering user and in one assistant group', () => {
    const items: ConversationTimelineItem[] = [
      {
        type: 'state',
        state: makeState({
          sequence: 42,
          phase: 'thinking',
          phaseStartedAt: 9.5,
        }),
      },
      {
        type: 'message',
        message: makeMessage({
          id: 'user-1',
          role: 'user',
          timestamp: 10,
          content: [{ type: 'text', text: 'Summarize today' }],
        }),
      },
      {
        type: 'message',
        message: makeMessage({
          id: 'tool-1',
          role: 'tool',
          timestamp: 10.1,
          toolUseId: 'call-1',
          content: [{ type: 'text', text: 'Read /tmp/today.md' }],
        }),
      },
      {
        type: 'message',
        message: makeMessage({
          id: 'assistant-1',
          role: 'assistant',
          timestamp: 10.2,
          content: [{ type: 'text', text: 'Working on it' }],
        }),
      },
    ];

    const grouped = groupConversationTimelineItems(items, {
      userMessageId: 'user-1',
      startedAt: 9.5,
    });

    expect(grouped).toHaveLength(2);
    expect(grouped[0]).toMatchObject({
      type: 'user',
      message: { id: 'user-1' },
    });
    expect(grouped[1]).toMatchObject({
      type: 'assistant',
      userMessageId: 'user-1',
    });
    if (grouped[1]?.type !== 'assistant') {
      throw new Error('expected assistant group');
    }
    expect(grouped[1].items).toHaveLength(3);
    expect(grouped[1].items[0]).toMatchObject({
      type: 'state',
    });
  });

  it('hides operations for assistant groups that belong to the active turn', () => {
    expect(shouldHideAssistantOperations('user-1', 'user-1')).toBe(true);
    expect(shouldHideAssistantOperations('user-1', 'user-2')).toBe(false);
    expect(shouldHideAssistantOperations('user-1', undefined)).toBe(false);
  });

  it('moves active assistant groups behind the triggering user group', () => {
    const userGroup: ConversationMessageGroup = {
      type: 'user',
      message: makeMessage({
        id: 'user-1',
        role: 'user',
        content: [{ type: 'text', text: 'Make a PPT' }],
      }),
    };
    const toolGroup: ConversationMessageGroup = {
      type: 'assistant',
      userMessageId: 'user-1',
      items: [
        {
          type: 'message',
          message: makeMessage({
            id: 'tool-1',
            role: 'tool',
            content: [{ type: 'text', text: 'Read /tmp/slides.md' }],
          }),
        },
      ],
    };
    const stateGroup: ConversationMessageGroup = {
      type: 'assistant',
      userMessageId: 'user-1',
      items: [
        {
          type: 'state',
          state: makeState({
            sequence: 42,
            phase: 'execution',
          }),
        },
      ],
    };

    const reordered = reorderActiveTurnGroups(
      [toolGroup, userGroup, stateGroup],
      'user-1'
    );

    expect(reordered).toEqual([userGroup, toolGroup, stateGroup]);
  });

  it('merges adjacent assistant groups for the same user turn', () => {
    const merged = mergeAdjacentAssistantGroups([
      {
        type: 'assistant',
        userMessageId: 'user-1',
        items: [
          {
            type: 'state',
            state: makeState({
              sequence: 42,
            }),
          },
        ],
      },
      {
        type: 'assistant',
        userMessageId: 'user-1',
        items: [
          {
            type: 'message',
            message: makeMessage({
              id: 'assistant-1',
              role: 'assistant',
              content: [{ type: 'text', text: 'Done' }],
            }),
          },
        ],
      },
    ]);

    expect(merged).toHaveLength(1);
    expect(merged[0]).toMatchObject({
      type: 'assistant',
      userMessageId: 'user-1',
    });
    if (merged[0]?.type !== 'assistant') {
      throw new Error('expected assistant group');
    }
    expect(merged[0].items).toHaveLength(2);
  });

  it('keeps the latest user turn together in the current conversation area', () => {
    const olderUserGroup: ConversationMessageGroup = {
      type: 'user',
      message: makeMessage({
        id: 'user-0',
        role: 'user',
      }),
    };
    const olderAssistantGroup: ConversationMessageGroup = {
      type: 'assistant',
      userMessageId: 'user-0',
      items: [
        {
          type: 'message',
          message: makeMessage({
            id: 'assistant-0',
            role: 'assistant',
            content: [{ type: 'text', text: 'Done' }],
          }),
        },
      ],
    };
    const latestUserGroup: ConversationMessageGroup = {
      type: 'user',
      message: makeMessage({
        id: 'user-1',
        role: 'user',
      }),
    };
    const latestToolGroup: ConversationMessageGroup = {
      type: 'assistant',
      userMessageId: 'user-1',
      items: [
        {
          type: 'message',
          message: makeMessage({
            id: 'tool-1',
            role: 'tool',
            content: [{ type: 'text', text: 'Searching...' }],
          }),
        },
      ],
    };
    const latestStateGroup: ConversationMessageGroup = {
      type: 'assistant',
      userMessageId: 'user-1',
      items: [
        {
          type: 'state',
          state: makeState({
            sequence: 42,
            phase: 'execution',
          }),
        },
      ],
    };

    expect(
      splitCurrentConversationGroups([
        olderUserGroup,
        olderAssistantGroup,
        latestUserGroup,
        latestToolGroup,
        latestStateGroup,
      ])
    ).toEqual({
      historyGroups: [olderUserGroup, olderAssistantGroup],
      currentGroups: [latestUserGroup, latestToolGroup, latestStateGroup],
    });
  });
});
