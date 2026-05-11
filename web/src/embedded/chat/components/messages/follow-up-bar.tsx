import type { FollowUpItem } from '@/jsb';
import { cn } from '@/utils/cn';
import { AnimatePresence, motion } from 'motion/react';
import { useCallback } from 'react';
import { MaskedScrollArea } from '../masked-scrollarea';
import { ChevronLeftSFSymbolMedium } from '@/assets/sf-symbols/medium/chevron.left';
import { ChevronRightSFSymbolMedium } from '@/assets/sf-symbols/medium/chevron.right';

export const FollowUpBar = ({
  items,
  isGenerating,
  show,
  onSendMessage,
}: {
  items: FollowUpItem[];
  isGenerating: boolean;
  show?: boolean;
  onSendMessage: (text: string) => void;
}) => {
  const handleSelect = useCallback(
    (item: FollowUpItem) => {
      onSendMessage(item.sendText);
    },
    [onSendMessage]
  );

  const visible = items.length > 0 || isGenerating;

  return (
    <div className="h-11 w-full pb-2">
      <AnimatePresence>
        {visible && show && (
          <motion.div
            initial={{ opacity: 0, x: 8 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -8 }}
            transition={{ duration: 0.2 }}
            className="w-full"
          >
            <MaskedScrollArea
              horizontal
              navButtonsVisibility="hover"
              startNavButton={
                <div className="size-4">
                  <ChevronLeftSFSymbolMedium className="text-sm" />
                </div>
              }
              endNavButton={
                <div className="size-4">
                  <ChevronRightSFSymbolMedium className="text-sm" />
                </div>
              }
              maskSizeStart={40}
              maskSizeEnd={40}
            >
              <div className="flex gap-2">
                {items.map((item, index) => (
                  <motion.button
                    key={item.id}
                    type="button"
                    initial={{
                      opacity: 0,
                      scale: 0.9,
                      x: 8,
                      filter: 'blur(12px)',
                    }}
                    animate={{
                      opacity: 1,
                      scale: 1,
                      x: 0,
                      filter: 'blur(0px)',
                    }}
                    transition={{ duration: 0.15, delay: index * 0.05 }}
                    onClick={() => handleSelect(item)}
                    className={cn(
                      'origin-right',
                      'px-3 py-1.5 rounded-full shrink-0',
                      'border border-transparent bg-user-bubble',
                      'hover:bg-user-bubble-hover active:bg-user-bubble-active',
                      'text-[13px] text-text-secondary hover:text-text-primary whitespace-nowrap',
                      'transition-colors cursor-pointer'
                    )}
                  >
                    {item.displayText}
                  </motion.button>
                ))}
              </div>
            </MaskedScrollArea>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};
