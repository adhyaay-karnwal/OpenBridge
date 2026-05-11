import { describe, expect, it } from 'vitest';
import { buildAssistantMessageFeedbackProperties } from '../../src/embedded/chat/components/messages/assistant-message-feedback';
import type { SessionHistoryMessage } from '../../src/embedded/chat/types/history';

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

describe('buildAssistantMessageFeedbackProperties', () => {
  it('collects stable feedback analytics fields from an assistant group', () => {
    const messages: SessionHistoryMessage[] = [
      makeMessage({
        id: 'assistant-1',
        role: 'assistant',
        content: [
          {
            type: 'text',
            text: 'Hello',
          },
          {
            type: 'image',
            url: 'https://example.com/image.png',
          },
        ],
      }),
      makeMessage({
        id: 'tool-1',
        role: 'tool',
        toolUseId: 'call-1',
        content: [
          {
            type: 'text',
            text: 'tool result',
          },
        ],
      }),
      makeMessage({
        id: 'assistant-2',
        role: 'assistant',
        content: [
          {
            type: 'text',
            text: 'World',
          },
          {
            type: 'file',
            fileName: 'notes.txt',
          },
        ],
        error: 'stale error for card state',
      }),
    ];

    expect(
      buildAssistantMessageFeedbackProperties({
        feedback: 'good',
        messages,
        userMessageId: 'user-1',
      })
    ).toEqual({
      feedback: 'good',
      user_message_id: 'user-1',
      assistant_message_count: 2,
      assistant_message_ids: ['assistant-1', 'assistant-2'],
      assistant_content_types: ['text', 'image', 'file'],
      assistant_text_length: 10,
      tool_message_count: 1,
      has_error: true,
    });
  });
});
