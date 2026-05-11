import { useState, useCallback } from 'react';
import type { SessionHistoryMessage } from '../../types/history';
import { isQuestionReplyMessage } from '../../types/history';

export const QuestionMessage = ({
  message,
  messages,
}: {
  message: SessionHistoryMessage;
  messages: SessionHistoryMessage[];
}) => {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [pendingSelections, setPendingSelections] = useState<string[]>([]);

  const question = message.question;
  if (!question) return null;

  const isMultiSelect = question.multiSelect === true;
  const canReply = !!window.jsb?.MessagesBridge?.replyInteraction;

  // Check if already replied (find matching question_reply by interaction id)
  const replyMessage = messages.find(
    m =>
      isQuestionReplyMessage(m) && m.confirmationId === message.confirmationId
  );
  const isReplied = !!replyMessage;
  const isCancelled = replyMessage?.questionReply?.cancelled === true;

  // Extract selected labels from reply
  const selectedLabels: string[] = [];
  if (replyMessage?.questionReply?.reply) {
    const reply = replyMessage.questionReply.reply;
    const selected = (reply as Record<string, unknown>).selected;
    if (Array.isArray(selected)) {
      selectedLabels.push(...selected.map(String));
    } else if (typeof selected === 'string') {
      selectedLabels.push(selected);
    }
  }

  const submitReply = useCallback(
    async (labels: string[]) => {
      if (
        isReplied ||
        isSubmitting ||
        !message.confirmationId ||
        !window.jsb?.MessagesBridge?.replyInteraction
      ) {
        return;
      }
      setIsSubmitting(true);
      try {
        const reply = JSON.stringify({ selected: labels });
        await window.jsb.MessagesBridge.replyInteraction(
          message.confirmationId,
          reply
        );
      } catch (e) {
        console.error('Failed to reply interaction:', e);
        setIsSubmitting(false);
      }
    },
    [isReplied, isSubmitting, message.confirmationId]
  );

  const handleSelect = useCallback(
    (label: string) => {
      if (isReplied || isSubmitting) return;

      if (isMultiSelect) {
        // Toggle selection
        setPendingSelections(prev =>
          prev.includes(label)
            ? prev.filter(l => l !== label)
            : [...prev, label]
        );
      } else {
        // Single select: submit immediately
        submitReply([label]);
      }
    },
    [isReplied, isSubmitting, isMultiSelect, submitReply]
  );

  const handleSubmitMulti = useCallback(() => {
    if (pendingSelections.length > 0) {
      submitReply(pendingSelections);
    }
  }, [pendingSelections, submitReply]);

  // For display: show reply selections or pending selections
  const displaySelections = isReplied ? selectedLabels : pendingSelections;

  return (
    <div className="select-none rounded-[12px] overflow-hidden border border-border bg-surface-card">
      {question.header && (
        <div className="px-3 pt-2.5 pb-0.5">
          <span className="text-[11px] text-text-tertiary font-medium uppercase tracking-wide">
            {question.header}
          </span>
        </div>
      )}
      <div className="px-3 py-2">
        <p className="text-[13px] text-text-primary leading-snug">
          {question.question}
        </p>
      </div>
      {isCancelled ? (
        <div className="px-3 pb-2.5">
          <span className="text-[12px] text-text-tertiary italic">Skipped</span>
        </div>
      ) : (
        <div className="px-3 pb-2.5">
          <div className="flex flex-wrap gap-1.5">
            {question.options.map(option => {
              const isSelected = displaySelections.includes(option.label);
              return (
                <button
                  key={option.label}
                  disabled={isReplied || isSubmitting || !canReply}
                  onClick={() => handleSelect(option.label)}
                  className={`
                    px-3 py-1.5 rounded-lg text-[13px] font-medium transition-all
                    ${
                      isSelected
                        ? 'bg-primary text-primary-highlight'
                        : isReplied
                          ? 'bg-fill-soft text-text-tertiary cursor-default'
                          : 'bg-control-bg text-control-fg hover:bg-control-bg-hover active:bg-control-bg-active'
                    }
                    ${isSubmitting ? 'opacity-50 cursor-wait' : ''}
                    disabled:cursor-default
                  `}
                  title={option.description || undefined}
                >
                  {option.label}
                </button>
              );
            })}
          </div>
          {isMultiSelect && !isReplied && (
            <button
              disabled={
                isSubmitting || pendingSelections.length === 0 || !canReply
              }
              onClick={handleSubmitMulti}
              className={`
                mt-2 px-4 py-1.5 rounded-lg text-[13px] font-medium transition-all
                ${
                  pendingSelections.length > 0
                    ? 'bg-primary text-primary-highlight hover:brightness-95 active:brightness-90'
                    : 'bg-fill-soft text-text-tertiary cursor-default'
                }
                ${isSubmitting ? 'opacity-50 cursor-wait' : ''}
              `}
            >
              Confirm
              {pendingSelections.length > 0
                ? ` (${pendingSelections.length})`
                : ''}
            </button>
          )}
        </div>
      )}
    </div>
  );
};
