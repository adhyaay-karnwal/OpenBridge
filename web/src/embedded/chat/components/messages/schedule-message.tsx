import { cn } from '@/utils/cn';
import { Menu } from '@/utils/webview-context-menu';
import { useState } from 'react';
import type { MouseEvent } from 'react';
import type { SessionHistoryMessage } from '../../types/history';
import { useSchedule } from '../../stores/schedule-store';

export const ScheduleMessage = ({
  message,
}: {
  message: SessionHistoryMessage;
}) => {
  const scheduleInfo = message.schedule;
  if (!scheduleInfo) {
    return null;
  }

  const { schedule: liveSchedule, hasLoadedSchedules } = useSchedule(
    scheduleInfo.scheduleId
  );
  const isScheduleInactive = hasLoadedSchedules && liveSchedule === undefined;
  const canTogglePause =
    !isScheduleInactive && (liveSchedule?.willTriggerAgain ?? true);
  const isSchedulePaused =
    !isScheduleInactive &&
    (liveSchedule?.isPaused ?? scheduleInfo.isPaused ?? false);
  const isScheduleError =
    liveSchedule?.hasError ?? scheduleInfo.hasError === true;
  const subtitleText = !hasLoadedSchedules
    ? scheduleInfo.subtitle
    : isScheduleInactive
      ? 'No longer runs'
      : isSchedulePaused
        ? 'Paused'
        : (liveSchedule?.subtitle ?? scheduleInfo.subtitle);

  const [isBusy, setIsBusy] = useState(false);

  const handleMenuClick = async (event: MouseEvent<HTMLElement>) => {
    const menu = Menu.create();

    if (canTogglePause) {
      menu.pushItem({
        title: isSchedulePaused ? 'Resume' : 'Pause',
        icon: Menu.icon.symbol(
          isSchedulePaused ? 'play.circle' : 'pause.circle'
        ),
        enabled: !isBusy,
        onClick: async () => {
          if (isBusy) {
            return;
          }

          setIsBusy(true);
          const nextPaused = !isSchedulePaused;

          try {
            if (nextPaused) {
              await window.jsb.MessagesBridge.pauseSchedule(
                scheduleInfo.scheduleId
              );
            } else {
              await window.jsb.MessagesBridge.resumeSchedule(
                scheduleInfo.scheduleId
              );
            }
          } catch (error) {
            console.error(
              '[ScheduleMessage] Failed to toggle schedule pause',
              error
            );
          } finally {
            setIsBusy(false);
          }
        },
      });
    }

    menu.pushItem({
      title: 'Delete',
      icon: Menu.icon.symbol('trash'),
      enabled: !isBusy,
      onClick: async () => {
        if (isBusy) {
          return;
        }

        setIsBusy(true);
        try {
          await window.jsb.MessagesBridge.deleteSchedule(
            scheduleInfo.scheduleId
          );
        } catch (error) {
          console.error('[ScheduleMessage] Failed to delete schedule', error);
          const message =
            error instanceof Error
              ? error.message
              : 'Failed to delete schedule';
          window.alert(message);
        } finally {
          setIsBusy(false);
        }
      },
    });

    menu.popup(event);
  };

  return (
    <div
      className={cn(
        'group relative w-full overflow-hidden',
        'flex items-center gap-2 rounded-2xl',
        isScheduleInactive
          ? 'border-border bg-surface-card-muted opacity-70'
          : isSchedulePaused
            ? 'border-warning-fg/20 bg-warning-bg'
            : 'border-border bg-surface-card',
        'border',
        'px-4 py-3',
        isScheduleInactive
          ? 'cursor-not-allowed'
          : isSchedulePaused
            ? 'cursor-default hover:bg-warning-bg'
            : 'cursor-default hover:bg-fill-soft'
      )}
      role="button"
      tabIndex={-1}
      onContextMenu={event => {
        if (isScheduleInactive) return;
        event.preventDefault();
        void handleMenuClick(event);
      }}
    >
      <div className="min-w-0 flex flex-1 flex-col gap-0.5">
        <div
          className={`w-[386px] truncate text-[15px] font-medium leading-[22px] tracking-[-0.18px] ${
            isScheduleInactive ? 'text-text-tertiary' : 'text-text-primary'
          }`}
        >
          {scheduleInfo.title}
        </div>
        {subtitleText || isScheduleInactive ? (
          <div
            className={`truncate text-[15px] leading-[22px] tracking-[-0.18px] ${
              isScheduleInactive
                ? 'text-text-tertiary'
                : isScheduleError
                  ? 'text-error-fg'
                  : isSchedulePaused
                    ? 'text-warning-fg'
                    : 'text-text-secondary'
            }`}
          >
            {subtitleText}
          </div>
        ) : null}
      </div>

      <button
        type="button"
        disabled={isScheduleInactive || isBusy}
        onClick={event => {
          event.preventDefault();
          if (!isScheduleInactive) {
            void handleMenuClick(event);
          }
        }}
        onContextMenu={event => {
          event.preventDefault();
          if (!isScheduleInactive) {
            void handleMenuClick(event);
          }
        }}
        className={cn(
          'relative z-10 flex h-[30px] w-[30px] shrink-0 items-center justify-center rounded-full transition disabled:opacity-50',
          isScheduleInactive
            ? 'text-text-tertiary'
            : isSchedulePaused
              ? 'text-warning-fg'
              : 'text-text-secondary hover:bg-fill-soft hover:text-text-primary'
        )}
        aria-label="Schedule actions"
      >
        <span className="flex items-center gap-1">
          <span className="h-1 w-1 rounded-full bg-current" />
          <span className="h-1 w-1 rounded-full bg-current" />
          <span className="h-1 w-1 rounded-full bg-current" />
        </span>
      </button>
    </div>
  );
};
