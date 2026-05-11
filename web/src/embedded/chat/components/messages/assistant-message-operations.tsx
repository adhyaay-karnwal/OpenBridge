import type { SessionHistoryMessage } from '../../types/history';
import { CopyButton, copyAssistantMessages } from './copy';
import { HandThumbsupSFSymbolMedium } from '@/assets/sf-symbols/medium/hand.thumbsup';
import { HandThumbsdownSFSymbolMedium } from '@/assets/sf-symbols/medium/hand.thumbsdown';
import { useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { cn } from '@/utils/cn';
import { HandThumbsupFillSFSymbolMedium } from '@/assets/sf-symbols/medium/hand.thumbsup.fill';
import { HandThumbsdownFillSFSymbolMedium } from '@/assets/sf-symbols/medium/hand.thumbsdown.fill';
import {
  useAssistantMessageFeedback,
  type AssistantMessageFeedback,
} from '../../stores/message-feedback-store';
import { submitAssistantMessageFeedback } from './assistant-message-feedback';

export const AssistantMessageOperations = ({
  messages,
  userMessageId,
}: {
  messages: SessionHistoryMessage[];
  userMessageId?: string;
}) => {
  const feedback = useAssistantMessageFeedback(userMessageId);
  const [pendingFeedback, setPendingFeedback] =
    useState<AssistantMessageFeedback | null>(null);
  const supportsFeedback = Boolean(userMessageId);

  const handleFeedback = async (nextFeedback: AssistantMessageFeedback) => {
    if (!userMessageId || feedback || pendingFeedback) {
      return;
    }

    setPendingFeedback(nextFeedback);
    try {
      await submitAssistantMessageFeedback({
        feedback: nextFeedback,
        messages,
        userMessageId,
      });
    } finally {
      setPendingFeedback(null);
    }
  };

  return (
    <div className="flex gap-1">
      <CopyButton
        className="flex-center icon-button size-6 text-[14px] opacity-65"
        onCopy={() => copyAssistantMessages(messages)}
      />

      <AnimatePresence>
        {supportsFeedback && feedback !== 'bad' && (
          <motion.div
            initial={{ opacity: 0, width: 0 }}
            animate={{ opacity: 1, width: 'auto' }}
            exit={{ opacity: 0, width: 0 }}
            transition={{ duration: 0.15, ease: 'easeOut' }}
          >
            <GoodButton
              value={feedback === 'good'}
              disabled={pendingFeedback !== null}
              onClick={() => handleFeedback('good')}
            />
          </motion.div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {supportsFeedback && feedback !== 'good' && (
          <motion.div
            initial={{ opacity: 0, width: 0 }}
            animate={{ opacity: 1, width: 'auto' }}
            exit={{ opacity: 0, width: 0 }}
            transition={{ duration: 0.15, ease: 'easeOut' }}
          >
            <BadButton
              value={feedback === 'bad'}
              disabled={pendingFeedback !== null}
              onClick={() => handleFeedback('bad')}
            />
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

const GoodButton = ({
  value,
  disabled,
  onClick,
}: {
  value: boolean;
  disabled: boolean;
  onClick: () => void;
}) => {
  const [isPressed, setIsPressed] = useState(false);
  const [clicked, setClicked] = useState(false);

  const iconClassName = cn('opacity-65 text-[14px] w-6');
  return (
    <button
      className="flex-center icon-button size-6"
      disabled={disabled}
      onMouseDown={() => {
        if (value || disabled) return;
        setIsPressed(true);
      }}
      onMouseUp={() => {
        if (value || disabled) return;
        setIsPressed(false);
      }}
      onMouseLeave={() => {
        if (value || disabled) return;
        setIsPressed(false);
      }}
      onBlur={() => {
        if (value || disabled) return;
        setIsPressed(false);
      }}
      onClick={() => {
        if (value || disabled) return;
        onClick();
        setClicked(true);
        setTimeout(() => {
          setClicked(false);
        }, 300);
      }}
    >
      <motion.div
        className="origin-left"
        initial={{ scale: 1, rotate: 0 }}
        animate={{
          scale: clicked ? 1.05 : isPressed ? 1.01 : 1,
          rotate: clicked ? -10 : isPressed ? 10 : 0,
        }}
      >
        {value ? (
          <HandThumbsupFillSFSymbolMedium className={iconClassName} />
        ) : (
          <HandThumbsupSFSymbolMedium className={iconClassName} />
        )}
      </motion.div>
    </button>
  );
};

const BadButton = ({
  value,
  disabled,
  onClick,
}: {
  value: boolean;
  disabled: boolean;
  onClick: () => void;
}) => {
  const [isPressed, setIsPressed] = useState(false);
  const [clicked, setClicked] = useState(false);

  const iconClassName = cn('opacity-65 text-[14px] w-6');
  return (
    <button
      className="flex-center icon-button size-6"
      disabled={disabled}
      onMouseDown={() => {
        if (value || disabled) return;
        setIsPressed(true);
      }}
      onMouseUp={() => {
        if (value || disabled) return;
        setIsPressed(false);
      }}
      onMouseLeave={() => {
        if (value || disabled) return;
        setIsPressed(false);
      }}
      onBlur={() => {
        if (value || disabled) return;
        setIsPressed(false);
      }}
      onClick={() => {
        if (value || disabled) return;
        onClick();
        setClicked(true);
        setTimeout(() => {
          setClicked(false);
        }, 300);
      }}
    >
      <motion.div
        className="origin-right"
        initial={{ scale: 1, rotate: 0 }}
        animate={{
          scale: clicked ? 1.05 : isPressed ? 1.01 : 1,
          rotate: clicked ? -10 : isPressed ? 10 : 0,
        }}
      >
        {value ? (
          <HandThumbsdownFillSFSymbolMedium className={iconClassName} />
        ) : (
          <HandThumbsdownSFSymbolMedium className={iconClassName} />
        )}
      </motion.div>
    </button>
  );
};
