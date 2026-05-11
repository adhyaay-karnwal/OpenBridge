import type {
  SessionHistoryMessage,
  SessionHistoryMessageContent,
  SessionHistoryMessageFileRef,
  SessionHistoryMessageQuoteReference,
  SessionHistoryMessageTodoItem,
  SessionHistoryMessageQuestionInfo,
  SessionHistoryMessageQuestionOption,
  SessionHistoryMessageQuestionReplyInfo,
  SessionHistoryMessageSaveFileRequestInfo,
  SessionHistoryMessageSaveFileReplyInfo,
  SessionHistoryMessagePermissionRequestInfo,
  SessionHistoryMessagePermissionReplyInfo,
  SessionHistoryMessageComputerUseStartInfo,
  SessionHistoryMessageComputerUsePermissionPane,
  SessionHistoryMessageSecretInputInfo,
  SessionHistoryMessageSecretInputReplyInfo,
  AssistantState,
  AssistantToolCallState,
  FileDiff,
  WorkspaceState,
  FollowUpState,
  FollowUpItem,
  SessionListInfo,
} from '@/jsb';

export type {
  SessionHistoryMessage,
  SessionHistoryMessageContent,
  SessionHistoryMessageFileRef,
  SessionHistoryMessageQuoteReference,
  SessionHistoryMessageTodoItem,
  SessionHistoryMessageQuestionInfo,
  SessionHistoryMessageQuestionOption,
  SessionHistoryMessageQuestionReplyInfo,
  SessionHistoryMessageSaveFileRequestInfo,
  SessionHistoryMessageSaveFileReplyInfo,
  SessionHistoryMessagePermissionRequestInfo,
  SessionHistoryMessagePermissionReplyInfo,
  SessionHistoryMessageComputerUseStartInfo,
  SessionHistoryMessageComputerUsePermissionPane,
  SessionHistoryMessageSecretInputInfo,
  SessionHistoryMessageSecretInputReplyInfo,
  AssistantState,
  AssistantToolCallState,
  FileDiff,
  WorkspaceState,
  FollowUpState,
  FollowUpItem,
  SessionListInfo,
};

// Type guards

export function isUserMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'message' && msg.role === 'user';
}

export function isAssistantMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'message' && msg.role === 'assistant';
}

export function isMessageStartMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'message_start';
}

export function isTaskMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'task';
}

export function isSandboxReviewMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'sandbox_review';
}

export function isQuestionMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'question';
}

export function isQuestionReplyMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'question_reply';
}

export function isSaveFileRequestMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'save_file_request';
}

export function isSaveFileReplyMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'save_file_reply';
}

export function isPermissionRequestMessage(
  msg: SessionHistoryMessage
): boolean {
  return msg.type === 'permission_request';
}

export function isPermissionReplyMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'permission_reply';
}

export function isSecretInputMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'secret_input';
}

export function isSecretInputReplyMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'secret_input_reply';
}

export function isScheduleMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'schedule';
}

export function isToolMessage(msg: SessionHistoryMessage): boolean {
  return msg.type === 'message' && msg.role === 'tool';
}

export function isErrorMessage(msg: SessionHistoryMessage): boolean {
  return !!msg.error;
}

// Content extraction

export function getTextContent(msg: SessionHistoryMessage): string[] {
  if (!msg.content) return [];
  return msg.content.filter(c => c.type === 'text' && c.text).map(c => c.text!);
}

const leadingSystemReminderBlockRegex =
  /^\s*<system-reminder>[\s\S]*?<\/system-reminder>\s*/;
const leadingCompactedContextBlockRegex =
  /^\s*<compacted-context>[\s\S]*?<\/compacted-context>\s*/;
const userReminderBlockRegex = /<user-reminder>[\s\S]*?<\/user-reminder>\s*/g;
const leadingAppRequestTagRegex = /^\s*<app-request\s+type="[^"]*"\s*\/>\s*/;

export function stripLeadingSystemReminderBlock(text: string): string {
  return text.replace(leadingSystemReminderBlockRegex, '');
}

export function stripLeadingCompactedContextBlock(text: string): string {
  return text.replace(leadingCompactedContextBlockRegex, '');
}

export function stripUserReminderBlocks(text: string): string {
  return text
    .replace(userReminderBlockRegex, '')
    .replace(/^\s+/, '')
    .replace(/\n{3,}/g, '\n\n');
}

/**
 * Returns true when the user message is a compacted-context wrapper that should
 * be hidden from the UI entirely (not just trimmed).
 *
 * A message qualifies when its first text block starts with `<compacted-context>`
 * after stripping any leading `<system-reminder>` blocks.
 */
export function isCompactedContextMessage(msg: SessionHistoryMessage): boolean {
  if (msg.role !== 'user') return false;
  const texts = getTextContent(msg);
  if (texts.length === 0) return false;
  const stripped = stripUserReminderBlocks(
    stripLeadingSystemReminderBlock(texts[0])
  );
  return stripped.trimStart().startsWith('<compacted-context>');
}

export function stripLeadingAppRequestTag(text: string): string {
  return text.replace(leadingAppRequestTagRegex, '');
}

export function getUserDisplayTextContent(
  msg: SessionHistoryMessage
): string[] {
  return getTextContent(msg)
    .map((text, index) => {
      if (msg.role === 'assistant') {
        return index === 0 ? stripLeadingAppRequestTag(text) : text;
      }

      if (msg.role !== 'user') {
        return text;
      }

      const withoutReminder =
        index === 0 ? stripLeadingSystemReminderBlock(text) : text;
      const withoutUserReminders = stripUserReminderBlocks(withoutReminder);
      const withoutCompactedContext =
        index === 0
          ? stripLeadingCompactedContextBlock(withoutUserReminders)
          : withoutUserReminders;
      return withoutCompactedContext;
    })
    .filter(text => text.length > 0);
}

// Derived task state (from history scanning)

export type DerivedTaskStatus = 'running' | 'completed' | 'cancelled';

export interface DerivedTask {
  id: string;
  title: string;
  status: DerivedTaskStatus;
  todos: SessionHistoryMessageTodoItem[];
}

export function deriveCurrentTask(
  messages: SessionHistoryMessage[]
): DerivedTask | null {
  let currentTask: DerivedTask | null = null;

  for (const msg of messages) {
    if (msg.type !== 'task' || !msg.taskId) continue;

    switch (msg.action) {
      case 'start':
        currentTask = {
          id: msg.taskId,
          title: msg.taskTitle ?? '',
          status: 'running',
          todos: msg.todos ?? [],
        };
        break;
      case 'update':
        if (currentTask && currentTask.id === msg.taskId) {
          currentTask.todos = msg.todos ?? [];
        }
        break;
      case 'end':
        if (currentTask && currentTask.id === msg.taskId) {
          currentTask.status = 'completed';
        }
        break;
      case 'cancel':
        if (currentTask && currentTask.id === msg.taskId) {
          currentTask.status = 'cancelled';
        }
        break;
    }
  }

  return currentTask;
}
