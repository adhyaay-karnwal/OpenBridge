import { useState, useCallback } from 'react';
import { cn } from '@/utils/cn';
import { EyeSFSymbolMedium } from '@/assets/sf-symbols/medium/eye';
import { EyeSlashSFSymbolMedium } from '@/assets/sf-symbols/medium/eye.slash';
import { KeyFillSFSymbolMedium } from '@/assets/sf-symbols/medium/key.fill';
import type { SessionHistoryMessage } from '../../types/history';
import { isSecretInputReplyMessage } from '../../types/history';

type SaveState = 'idle' | 'saving' | 'saved' | 'error';

export const SecretInputMessage = ({
  message,
  messages,
}: {
  message: SessionHistoryMessage;
  messages: SessionHistoryMessage[];
}) => {
  const [value, setValue] = useState('');
  const [saveState, setSaveState] = useState<SaveState>('idle');
  const [errorMessage, setErrorMessage] = useState('');
  const [showValue, setShowValue] = useState(false);

  const secretInput = message.secretInput;
  if (!secretInput) return null;

  const replyMessage = messages.find(
    m =>
      isSecretInputReplyMessage(m) &&
      m.confirmationId === message.confirmationId
  );
  const isReplied = !!replyMessage;
  const isCancelled = replyMessage?.secretInputReply?.cancelled === true;
  const isProvided = replyMessage?.secretInputReply?.provided === true;

  const handleSave = useCallback(async () => {
    if (!value.trim() || !message.confirmationId) return;

    setSaveState('saving');
    setErrorMessage('');

    try {
      const reply = JSON.stringify({ value: value.trim() });
      await window.jsb?.MessagesBridge?.replyInteraction(
        message.confirmationId,
        reply
      );
      setSaveState('saved');
    } catch (err) {
      setSaveState('error');
      setErrorMessage(err instanceof Error ? err.message : 'Failed to save');
    }
  }, [value, message.confirmationId]);

  const handleCancel = useCallback(async () => {
    if (!message.confirmationId) return;
    setSaveState('saving');
    try {
      const reply = JSON.stringify({ cancelled: true });
      await window.jsb?.MessagesBridge?.replyInteraction(
        message.confirmationId,
        reply
      );
      setSaveState('saved');
    } catch (err) {
      setSaveState('error');
      setErrorMessage(err instanceof Error ? err.message : 'Failed to cancel');
    }
  }, [message.confirmationId]);

  if (saveState === 'saved' || isProvided) {
    return (
      <div className="my-2 rounded-lg border border-success-fg/20 bg-success-bg p-3">
        <div className="text-sm text-success-fg flex items-center gap-2">
          <KeyFillSFSymbolMedium />
          {secretInput.label || secretInput.slot} — saved
        </div>
      </div>
    );
  }

  if (isCancelled) {
    return (
      <div className="my-2 rounded-lg border border-border bg-surface-card p-3">
        <div className="text-sm text-text-tertiary flex items-center gap-2">
          <KeyFillSFSymbolMedium />
          {secretInput.label || secretInput.slot} — skipped
        </div>
      </div>
    );
  }

  if (isReplied) return null;

  return (
    <div className="my-2 rounded-lg space-y-2 border border-border bg-surface-card p-3">
      <div className="text-sm font-medium text-text-secondary flex items-center gap-2">
        <KeyFillSFSymbolMedium />
        {secretInput.label || secretInput.slot}
      </div>
      {secretInput.prompt && (
        <div className="text-xs text-text-secondary leading-relaxed whitespace-pre-wrap">
          {linkify(secretInput.prompt)}
        </div>
      )}
      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <input
            type={showValue ? 'text' : 'password'}
            value={value}
            onChange={e => setValue(e.target.value)}
            placeholder={`Enter ${secretInput.label || 'value'}…`}
            disabled={saveState === 'saving'}
            autoComplete="off"
            autoCorrect="off"
            autoCapitalize="off"
            spellCheck={false}
            onKeyDown={e => {
              if (e.key === 'Enter') handleSave();
              if (e.key === 'Escape') handleCancel();
            }}
            className={cn(
              'w-full rounded-lg border border-border bg-surface-card-muted px-3 py-1.5 pr-8 text-sm text-text-primary',
              'placeholder:text-text-tertiary focus:outline-none focus:border-primary/30 focus:bg-surface-card',
              'disabled:opacity-50'
            )}
          />
          <button
            type="button"
            onClick={() => setShowValue(prev => !prev)}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-text-tertiary hover:text-text-secondary text-xs"
            title={showValue ? 'Hide' : 'Show'}
          >
            {showValue ? (
              <EyeSFSymbolMedium className="w-4" />
            ) : (
              <EyeSlashSFSymbolMedium className="w-4" />
            )}
          </button>
        </div>
        <button
          type="button"
          onClick={handleSave}
          disabled={!value.trim() || saveState === 'saving'}
          className={cn(
            'rounded-lg border border-border px-4 py-1.5 text-sm cursor-pointer',
            'bg-primary text-primary-highlight hover:brightness-95',
            'disabled:opacity-50 disabled:cursor-not-allowed',
            'transition-all'
          )}
        >
          {saveState === 'saving' ? 'Saving…' : 'Save'}
        </button>
      </div>
      {saveState === 'error' && errorMessage && (
        <div className="text-xs text-red-400">{errorMessage}</div>
      )}
    </div>
  );
};

function linkify(text: string): React.ReactNode[] {
  const urlRegex = /(https?:\/\/[^\s)]+)/g;
  const parts: React.ReactNode[] = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;
  let i = 0;

  while ((match = urlRegex.exec(text)) !== null) {
    if (match.index > lastIndex) {
      parts.push(text.slice(lastIndex, match.index));
    }
    const url = match[1];
    parts.push(
      <a
        key={i++}
        href={url}
        target="_blank"
        rel="noopener noreferrer"
        className="text-blue-400 hover:underline"
        onClick={e => {
          e.preventDefault();
          window.jsb?.UtilsBridge?.openURL(url);
        }}
      >
        {url}
      </a>
    );
    lastIndex = match.index + match[0].length;
  }

  if (lastIndex < text.length) {
    parts.push(text.slice(lastIndex));
  }

  return parts;
}
