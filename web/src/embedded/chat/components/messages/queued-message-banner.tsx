import { cn } from '@/utils/cn';
import { AnimatePresence, motion } from 'motion/react';
import { ClockSFSymbolRegular } from '@/assets/sf-symbols/regular/clock';
import { XmarkCircleFillSFSymbolRegular } from '@/assets/sf-symbols/regular/xmark.circle.fill';
import { useMacosVersion } from '@/utils/use-utils-bridge';

export const QueuedMessageBanner = ({
  message,
  onCancel,
}: {
  message: string | null;
  onCancel: () => void;
}) => {
  const macosVersion = useMacosVersion();

  return (
    <AnimatePresence>
      {message !== null && (
        <motion.div
          initial={{ opacity: 0, y: 8, scale: 0.97 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 6, scale: 0.97 }}
          transition={{ duration: 0.18, ease: 'easeOut' }}
          className={cn(
            'w-full rounded-2xl border',
            !macosVersion || macosVersion >= 26
              ? 'bg-surface-overlay backdrop-blur-lg'
              : 'bg-surface-card',
            'border-border shadow-lg'
          )}
        >
          <div className="flex items-center gap-2 px-3 py-2.5">
            <ClockSFSymbolRegular className="shrink-0 text-[13px] text-text-secondary" />
            <span className="min-w-0 flex-1 truncate text-[13px] text-text-primary">
              {message}
            </span>
            <button
              type="button"
              onClick={onCancel}
              className="shrink-0 cursor-pointer text-text-tertiary transition-colors hover:text-text-primary"
              aria-label="Cancel queued message"
            >
              <XmarkCircleFillSFSymbolRegular className="text-[15px]" />
            </button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};
