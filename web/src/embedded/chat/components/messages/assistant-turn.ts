import type {
  AssistantState,
  SessionHistoryMessage,
} from '../../types/history';
import { isUserMessage } from '../../types/history';
import type { AssistantGroupItem } from './assistant-message';

export type ConversationTimelineItem =
  | { type: 'message'; message: SessionHistoryMessage }
  | { type: 'state'; state: AssistantState };

export type ConversationMessageGroup =
  | { type: 'user'; message: SessionHistoryMessage }
  | {
      type: 'assistant';
      items: AssistantGroupItem[];
      userMessageId?: string;
    };

type ActiveAssistantTurn = {
  userMessageId?: string;
  startedAt?: number;
};

function getTimelineItemTimestamp(item: ConversationTimelineItem): number {
  return item.type === 'message'
    ? item.message.timestamp
    : item.state.phaseStartedAt;
}

export function findLatestUserMessageId(
  messages: SessionHistoryMessage[]
): string | undefined {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (isUserMessage(message)) {
      return message.id;
    }
  }

  return undefined;
}

export function getActiveAssistantTurn(
  messages: SessionHistoryMessage[],
  currentAssistantState: AssistantState | null
): ActiveAssistantTurn {
  if (!currentAssistantState || currentAssistantState.phase === 'idle') {
    return {};
  }

  return {
    userMessageId: findLatestUserMessageId(messages),
    startedAt: currentAssistantState.phaseStartedAt,
  };
}

export function resolveAssistantTurnUserMessageId({
  naturalUserMessageId,
  activeTurnUserMessageId,
  activeTurnStartedAt,
  itemTimestamp,
}: {
  naturalUserMessageId?: string;
  activeTurnUserMessageId?: string;
  activeTurnStartedAt?: number;
  itemTimestamp: number;
}): string | undefined {
  if (!activeTurnUserMessageId) {
    return naturalUserMessageId;
  }

  if (
    activeTurnStartedAt !== undefined &&
    itemTimestamp >= activeTurnStartedAt
  ) {
    return activeTurnUserMessageId;
  }

  return naturalUserMessageId;
}

export function shouldHideAssistantOperations(
  groupUserMessageId: string | undefined,
  activeTurnUserMessageId: string | undefined
): boolean {
  return (
    activeTurnUserMessageId !== undefined &&
    groupUserMessageId === activeTurnUserMessageId
  );
}

export function reorderActiveTurnGroups(
  groups: ConversationMessageGroup[],
  activeTurnUserMessageId: string | undefined
): ConversationMessageGroup[] {
  if (!activeTurnUserMessageId) {
    return groups;
  }

  const activeAssistantGroups = groups.filter(
    group =>
      group.type === 'assistant' &&
      group.userMessageId === activeTurnUserMessageId
  );
  if (activeAssistantGroups.length === 0) {
    return groups;
  }

  const remainingGroups = groups.filter(
    group =>
      group.type !== 'assistant' ||
      group.userMessageId !== activeTurnUserMessageId
  );
  const activeUserIndex = remainingGroups.findIndex(
    group =>
      group.type === 'user' && group.message.id === activeTurnUserMessageId
  );
  if (activeUserIndex === -1) {
    return groups;
  }

  const reorderedGroups = [...remainingGroups];
  reorderedGroups.splice(activeUserIndex + 1, 0, ...activeAssistantGroups);
  return reorderedGroups;
}

export function mergeAdjacentAssistantGroups(
  groups: ConversationMessageGroup[]
): ConversationMessageGroup[] {
  const mergedGroups: ConversationMessageGroup[] = [];

  for (const group of groups) {
    const lastGroup = mergedGroups[mergedGroups.length - 1];
    if (
      group.type === 'assistant' &&
      lastGroup?.type === 'assistant' &&
      lastGroup.userMessageId === group.userMessageId
    ) {
      lastGroup.items.push(...group.items);
      continue;
    }

    mergedGroups.push(
      group.type === 'assistant'
        ? {
            ...group,
            items: [...group.items],
          }
        : group
    );
  }

  return mergedGroups;
}

export function groupConversationTimelineItems(
  items: ConversationTimelineItem[],
  activeTurn: ActiveAssistantTurn
): ConversationMessageGroup[] {
  const groups: ConversationMessageGroup[] = [];
  let lastUserMessageId: string | undefined;

  for (const item of items) {
    if (item.type === 'message' && isUserMessage(item.message)) {
      lastUserMessageId = item.message.id;
      groups.push({ type: 'user', message: item.message });
      continue;
    }

    const userMessageId = resolveAssistantTurnUserMessageId({
      naturalUserMessageId: lastUserMessageId,
      activeTurnUserMessageId: activeTurn.userMessageId,
      activeTurnStartedAt: activeTurn.startedAt,
      itemTimestamp: getTimelineItemTimestamp(item),
    });
    const lastGroup = groups[groups.length - 1];

    if (
      lastGroup &&
      lastGroup.type === 'assistant' &&
      lastGroup.userMessageId === userMessageId
    ) {
      lastGroup.items.push(item);
      continue;
    }

    groups.push({
      type: 'assistant',
      items: [item],
      userMessageId,
    });
  }

  return mergeAdjacentAssistantGroups(
    reorderActiveTurnGroups(groups, activeTurn.userMessageId)
  );
}

export function splitCurrentConversationGroups(
  groups: ConversationMessageGroup[]
): {
  historyGroups: ConversationMessageGroup[];
  currentGroups: ConversationMessageGroup[];
} {
  const lastUserGroupIndex = groups.findLastIndex(
    group => group.type === 'user'
  );
  const currentConversationStartIndex =
    lastUserGroupIndex === -1
      ? Math.max(groups.length - 2, 0)
      : lastUserGroupIndex;

  return {
    historyGroups: groups.slice(0, currentConversationStartIndex),
    currentGroups: groups.slice(currentConversationStartIndex),
  };
}
