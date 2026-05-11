import type { ScheduleCard } from '@/jsb';
import { useSyncExternalStore } from 'react';

type SchedulesSnapshot = ReadonlyMap<string, ScheduleCard> | null;

let snapshot: SchedulesSnapshot = null;

const listeners = new Set<() => void>();

function emitChange() {
  for (const listener of listeners) {
    listener();
  }
}

function buildSchedulesMap(
  schedules: ScheduleCard[]
): ReadonlyMap<string, ScheduleCard> {
  return new Map(schedules.map(schedule => [schedule.id, schedule]));
}

export function replaceSchedules(schedules: ScheduleCard[]) {
  snapshot = buildSchedulesMap(schedules);
  emitChange();
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

export function useSchedule(scheduleID: string) {
  const currentSnapshot = useSyncExternalStore(
    subscribe,
    getSnapshot,
    getSnapshot
  );
  return {
    hasLoadedSchedules: currentSnapshot !== null,
    schedule: currentSnapshot?.get(scheduleID),
  };
}

export function useSchedules() {
  const currentSnapshot = useSyncExternalStore(
    subscribe,
    getSnapshot,
    getSnapshot
  );
  return {
    hasLoadedSchedules: currentSnapshot !== null,
    schedules: currentSnapshot ? Array.from(currentSnapshot.values()) : [],
  };
}
