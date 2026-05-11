import type { SessionHistoryMessage } from '../../types/history';
import {
  getTextContent,
  isAssistantMessage,
  isToolMessage,
} from '../../types/history';
import {
  setAssistantMessageFeedback,
  type AssistantMessageFeedback,
} from '../../stores/message-feedback-store';

type AssistantMessageFeedbackProperties = {
  feedback: AssistantMessageFeedback;
  user_message_id: string;
  assistant_message_count: number;
  assistant_message_ids: string[];
  assistant_content_types: string[];
  assistant_text_length: number;
  tool_message_count: number;
  has_error: boolean;
};

export function buildAssistantMessageFeedbackProperties({
  feedback,
  messages,
  userMessageId,
}: {
  feedback: AssistantMessageFeedback;
  messages: SessionHistoryMessage[];
  userMessageId: string;
}): AssistantMessageFeedbackProperties {
  const assistantMessages = messages.filter(isAssistantMessage);
  const toolMessages = messages.filter(isToolMessage);
  const assistantMessageIds = assistantMessages
    .map(message => message.id)
    .filter(messageId => messageId.length > 0);
  const assistantContentTypes = Array.from(
    new Set(
      assistantMessages.flatMap(message =>
        (message.content ?? []).map(content => content.type)
      )
    )
  );
  const assistantTextLength = assistantMessages.reduce(
    (total, message) =>
      total +
      getTextContent(message).reduce((messageTotal, text) => {
        return messageTotal + text.length;
      }, 0),
    0
  );

  return {
    feedback,
    user_message_id: userMessageId,
    assistant_message_count: assistantMessages.length,
    assistant_message_ids: assistantMessageIds,
    assistant_content_types: assistantContentTypes,
    assistant_text_length: assistantTextLength,
    tool_message_count: toolMessages.length,
    has_error: messages.some(message => Boolean(message.error)),
  };
}

export async function submitAssistantMessageFeedback({
  feedback,
  messages: _messages,
  userMessageId,
}: {
  feedback: AssistantMessageFeedback;
  messages: SessionHistoryMessage[];
  userMessageId?: string;
}) {
  if (!userMessageId) {
    return false;
  }

  setAssistantMessageFeedback(userMessageId, feedback);

  const bridgeMethod =
    feedback === 'good'
      ? window.jsb?.MessagesBridge?.goodMessage
      : window.jsb?.MessagesBridge?.badMessage;

  if (bridgeMethod) {
    try {
      await bridgeMethod(userMessageId);
    } catch (error) {
      console.error('[AssistantMessageOperations] feedback bridge failed', {
        feedback,
        userMessageId,
        error,
      });
    }
  }

  return true;
}
