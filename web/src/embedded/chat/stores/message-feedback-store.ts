import { useSyncExternalStore } from 'react';

export type AssistantMessageFeedback = 'good' | 'bad';

type FeedbackSnapshot = ReadonlyMap<string, AssistantMessageFeedback>;

let snapshot: FeedbackSnapshot = new Map();

const listeners = new Set<() => void>();

function emitChange() {
  for (const listener of listeners) {
    listener();
  }
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot() {
  return snapshot;
}

export function setAssistantMessageFeedback(
  userMessageId: string,
  feedback: AssistantMessageFeedback
) {
  if (snapshot.get(userMessageId) === feedback) {
    return;
  }

  const next = new Map(snapshot);
  next.set(userMessageId, feedback);
  snapshot = next;
  emitChange();
}

export function getAssistantMessageFeedback(userMessageId?: string) {
  if (!userMessageId) {
    return null;
  }
  return snapshot.get(userMessageId) ?? null;
}

export function useAssistantMessageFeedback(userMessageId?: string) {
  const currentSnapshot = useSyncExternalStore(
    subscribe,
    getSnapshot,
    getSnapshot
  );

  if (!userMessageId) {
    return null;
  }

  return currentSnapshot.get(userMessageId) ?? null;
}
