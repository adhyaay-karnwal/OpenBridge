import { useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { AppLogo } from '@/assets/logos/app-logo';
import { useUtilsBridgeUsername } from '@/utils/use-utils-bridge';
import type { ScheduleCard, SessionListInfo } from '@/jsb';
import { MessageSFSymbolMedium } from '@/assets/sf-symbols/medium/message';
import { cn } from '@/utils/cn';
import { ChevronRightSFSymbolMedium } from '@/assets/sf-symbols/medium/chevron.right';
import { motion } from 'framer-motion';
import { ClockSFSymbolMedium } from '@/assets/sf-symbols/medium/clock';
import { PauseCircleSFSymbolMedium } from '@/assets/sf-symbols/medium/pause.circle';
import { CheckmarkCircleFillSFSymbolMedium } from '@/assets/sf-symbols/medium/checkmark.circle.fill';
import { ExclamationmarkTriangleFillSFSymbolMedium } from '@/assets/sf-symbols/medium/exclamationmark.triangle.fill';
import { useSchedules } from '../stores/schedule-store';
import { isPanelPresentationMode } from '../presentation-mode';

const suggestionRowHeight = 26;
const suggestionRowGap = 8;
const suggestionSectionGap = 16;
const suggestionIconSlotClass =
  'flex h-[24px] w-[24px] shrink-0 items-center justify-center';
const suggestionChevronSlotClass =
  'flex h-[20px] w-[20px] shrink-0 items-center justify-center';
const suggestionTextClass =
  'w-[170px] overflow-hidden text-[13px] leading-[19px] tracking-[0px] truncate';

const getSuggestionStackHeight = (count: number) => {
  if (count <= 0) {
    return 0;
  }
  return count * suggestionRowHeight + (count - 1) * suggestionRowGap;
};

const getScheduleSuggestionState = (schedule: ScheduleCard) => {
  if (schedule.hasError) {
    return 'error';
  }
  if (!schedule.willTriggerAgain) {
    return 'completed';
  }
  if (schedule.isPaused) {
    return 'paused';
  }
  return 'scheduled';
};

const SuggestionPill = ({
  children,
  clickable = false,
  onClick,
}: {
  children: ReactNode;
  clickable?: boolean;
  onClick?: () => void;
}) => {
  return (
    <div
      onClick={onClick}
      className={cn(
        'inline-flex w-[230px] items-center justify-start gap-[2px] rounded-full',
        isPanelPresentationMode
          ? 'bg-black/10 dark:bg-white/10'
          : 'bg-black/5 dark:bg-white/5',
        'py-px pl-1 pr-2 text-[13px] font-500 leading-[19px] tracking-[0px]',
        clickable
          ? cn(
              'cursor-pointer transition-colors duration-150',
              isPanelPresentationMode
                ? 'hover:bg-black/20 dark:hover:bg-white/20'
                : 'hover:bg-black/10 dark:hover:bg-white/10'
            )
          : 'cursor-default'
      )}
    >
      {children}
    </div>
  );
};

const ScheduleSuggestionIcon = ({ schedule }: { schedule: ScheduleCard }) => {
  const state = getScheduleSuggestionState(schedule);

  if (state === 'error') {
    return (
      <ExclamationmarkTriangleFillSFSymbolMedium className="text-[14px] text-red-500 dark:text-red-300" />
    );
  }

  if (state === 'completed') {
    return (
      <CheckmarkCircleFillSFSymbolMedium className="text-[14px] text-black/35 dark:text-white/30" />
    );
  }

  if (state === 'paused') {
    return (
      <PauseCircleSFSymbolMedium className="text-[14px] text-black/55 dark:text-white/75" />
    );
  }

  return (
    <ClockSFSymbolMedium className="text-[14px] text-black/60 dark:text-white/75" />
  );
};

export const Greet = () => {
  const username = useUtilsBridgeUsername();
  const [loading, setLoading] = useState(false);
  const [recentConversations, setRecentConversations] = useState<
    SessionListInfo[]
  >([]);
  const { schedules } = useSchedules();

  const greet = useMemo(() => {
    const now = new Date();
    const hour = now.getHours();
    if (hour < 12) {
      return 'Morning';
    } else if (hour < 18) {
      return 'Afternoon';
    } else {
      return 'Evening';
    }
  }, []);

  const visibleSchedules = useMemo(
    () =>
      schedules
        .filter(schedule => !schedule.isDeleted && schedule.title)
        .slice(0, 3),
    [schedules]
  );

  const suggestionStackHeight = useMemo(() => {
    const recentHeight = getSuggestionStackHeight(recentConversations.length);
    const scheduleHeight = getSuggestionStackHeight(visibleSchedules.length);
    return (
      recentHeight +
      scheduleHeight +
      (recentHeight > 0 && scheduleHeight > 0 ? suggestionSectionGap : 0)
    );
  }, [recentConversations.length, visibleSchedules.length]);

  useEffect(() => {
    let isCancelled = false;

    const applyRecentConversations = (
      conversations: SessionListInfo[] | undefined | null
    ) => {
      if (isCancelled) {
        return;
      }

      setRecentConversations((conversations ?? []).slice(0, 3));
      setLoading(false);
    };

    setLoading(true);

    const unsubscribe = window.jsb.MessagesBridge.onRecentSessions(
      applyRecentConversations
    );

    window.jsb.MessagesBridge.fetchRecentConversations()
      .then(applyRecentConversations)
      .catch(error => {
        if (isCancelled) {
          return;
        }
        console.error(error);
        setLoading(false);
      });

    return () => {
      isCancelled = true;
      unsubscribe();
    };
  }, []);

  return (
    <div className="size-full flex-col flex items-center justify-center gap-4">
      <AppLogo className="text-[64px] text-black/20 dark:text-white/20" />
      <div className="text-center">
        <h1 className="max-w-[min(80vw,500px)] text-[24px] font-500 mb-1 truncate">
          <span>{greet}</span>
          {username ? (
            <>
              <span>,&nbsp;</span>
              <span>{username || 'Unknown'}</span>
            </>
          ) : null}
        </h1>
        <p className="text-sm opacity-55">How can I help you today?</p>
      </div>
      <motion.div
        initial={{ height: 0, opacity: 0 }}
        animate={{ height: suggestionStackHeight, opacity: 1 }}
        transition={{ duration: 0.4, ease: 'easeOut', delay: 0.05 }}
        className="flex flex-col items-start gap-4"
      >
        {recentConversations.length > 0 ? (
          <div className="flex flex-col items-start gap-2">
            {recentConversations.map((conversation, index) => (
              <motion.div
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.4, delay: index * 0.1 }}
                key={conversation.id}
              >
                <SuggestionPill
                  clickable
                  onClick={() => {
                    window.jsb.MessagesBridge.openConversation(conversation.id);
                  }}
                >
                  <span className={suggestionIconSlotClass}>
                    <MessageSFSymbolMedium className="text-[14px] text-black/60 dark:text-white/75" />
                  </span>
                  <span
                    className={cn(
                      suggestionTextClass,
                      'text-black/90 dark:text-white'
                    )}
                  >
                    {conversation.title}
                  </span>
                  <span className={suggestionChevronSlotClass}>
                    <ChevronRightSFSymbolMedium className="text-xs text-black/40 dark:text-white/65" />
                  </span>
                </SuggestionPill>
              </motion.div>
            ))}
          </div>
        ) : null}

        {/* make sure the histories are loaded before showing the schedules */}
        {!loading && visibleSchedules.length > 0 ? (
          <div className="flex flex-col items-start gap-2">
            {visibleSchedules.map((schedule, index) => {
              const state = getScheduleSuggestionState(schedule);
              const isCompleted = state === 'completed';
              const isError = state === 'error';

              return (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{
                    duration: 0.4,
                    delay: recentConversations.length * 0.1 + index * 0.1,
                  }}
                  key={schedule.id}
                >
                  <SuggestionPill>
                    <span className={suggestionIconSlotClass}>
                      <ScheduleSuggestionIcon schedule={schedule} />
                    </span>
                    <span
                      className={cn(
                        suggestionTextClass,
                        isCompleted
                          ? 'text-black/35 line-through decoration-black/35 dark:text-white/30 dark:decoration-white/30'
                          : isError
                            ? 'text-red-500 dark:text-red-300'
                            : 'text-black/90 dark:text-white'
                      )}
                    >
                      {schedule.title}
                    </span>
                  </SuggestionPill>
                </motion.div>
              );
            })}
          </div>
        ) : null}
      </motion.div>
    </div>
  );
};
