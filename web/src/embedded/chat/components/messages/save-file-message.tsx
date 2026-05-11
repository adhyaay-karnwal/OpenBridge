import { useCallback, useState } from 'react';
import type { SessionHistoryMessage } from '../../types/history';
import { isSaveFileReplyMessage } from '../../types/history';

const DownloadIcon = () => (
  <svg
    height="1em"
    viewBox="0 0 16 16"
    fill="currentColor"
    xmlns="http://www.w3.org/2000/svg"
  >
    <path d="M8.75 1.5a.75.75 0 0 0-1.5 0v6.19L5.53 5.97a.75.75 0 1 0-1.06 1.06l3 3a.75.75 0 0 0 1.06 0l3-3a.75.75 0 0 0-1.06-1.06L8.75 7.69V1.5Z" />
    <path d="M2 10.75A.75.75 0 0 1 2.75 10h10.5a.75.75 0 0 1 0 1.5H2.75A.75.75 0 0 1 2 10.75Zm1 2.5A.75.75 0 0 1 3.75 12.5h8.5a.75.75 0 0 1 0 1.5h-8.5A.75.75 0 0 1 3 13.25Z" />
  </svg>
);

export const SaveFileMessage = ({
  message,
  messages,
}: {
  message: SessionHistoryMessage;
  messages: SessionHistoryMessage[];
}) => {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const directReply = message.saveFileReply;
  const request = message.saveFileRequest;
  const replyMessage =
    message.type === 'save_file_request'
      ? messages.find(
          m =>
            isSaveFileReplyMessage(m) &&
            m.confirmationId === message.confirmationId
        )
      : undefined;
  const reply = directReply ?? replyMessage?.saveFileReply;

  if (!request && !reply) return null;

  const fileName = request?.fileName ?? reply?.fileName ?? 'download';
  const path = request?.path;
  const isCancelled = reply?.cancelled === true;
  const isApproved = reply?.approved === true;
  const isResolvedReply = message.type === 'save_file_reply';
  const canAct = message.type === 'save_file_request' && !!request && !reply;
  const canSaveFile = !!window.jsb?.MessagesBridge?.saveRemoteFile;
  const canReply = !!window.jsb?.MessagesBridge?.replyInteraction;

  const handleSave = useCallback(async () => {
    if (
      !canAct ||
      isSubmitting ||
      !message.confirmationId ||
      !window.jsb?.MessagesBridge?.saveRemoteFile
    ) {
      return;
    }
    setIsSubmitting(true);
    try {
      await window.jsb.MessagesBridge.saveRemoteFile(message.confirmationId);
    } catch (e) {
      console.error('Failed to open save dialog:', e);
    } finally {
      setIsSubmitting(false);
    }
  }, [canAct, isSubmitting, message.confirmationId]);

  const handleCancel = useCallback(async () => {
    if (
      !canAct ||
      isSubmitting ||
      !message.confirmationId ||
      !window.jsb?.MessagesBridge?.replyInteraction
    ) {
      return;
    }
    setIsSubmitting(true);
    try {
      await window.jsb.MessagesBridge.replyInteraction(
        message.confirmationId,
        JSON.stringify({ approved: false, cancelled: true })
      );
    } catch (e) {
      console.error('Failed to cancel save file request:', e);
      setIsSubmitting(false);
    }
  }, [canAct, isSubmitting, message.confirmationId]);

  return (
    <div className="select-none rounded-[14px] overflow-hidden border border-border bg-surface-card">
      <div className="flex items-center gap-2 px-3 pt-3 pb-2">
        <div className="flex-shrink-0 w-6 h-6 rounded-full bg-info-bg flex items-center justify-center text-info-fg text-[12px]">
          <DownloadIcon />
        </div>
        <div className="flex flex-col min-w-0">
          <span className="text-[11px] text-text-tertiary font-medium uppercase tracking-wide leading-none mb-0.5">
            Save File
          </span>
          <span className="text-[11px] text-text-secondary font-medium leading-none truncate">
            {fileName}
          </span>
        </div>
      </div>

      <div className="mx-3 border-t border-border" />

      <div className="px-3 pt-2.5 pb-3 space-y-1">
        {request?.message ? (
          <p className="text-[13px] text-text-primary leading-snug font-medium">
            {request.message}
          </p>
        ) : null}
        {path ? (
          <p className="text-[12px] text-text-secondary leading-snug break-all">
            {path}
          </p>
        ) : null}
      </div>

      <div className="px-3 pb-3">
        {isCancelled ? (
          <span className="text-[12px] text-text-tertiary italic">
            Cancelled
          </span>
        ) : isApproved ? (
          <span className="text-[12px] font-medium text-success-fg">
            Saved{reply?.bytesWritten ? ` · ${reply.bytesWritten} bytes` : ''}
          </span>
        ) : isResolvedReply ? (
          <span className="text-[12px] text-text-secondary">
            Save completed
          </span>
        ) : canAct ? (
          <div className="flex gap-2">
            <button
              disabled={isSubmitting || !canSaveFile}
              onClick={handleSave}
              className={`
                flex-1 px-3 py-1.5 rounded-[8px] text-[13px] font-semibold transition-all
                bg-primary text-primary-highlight hover:brightness-95 active:brightness-90
                ${isSubmitting ? 'opacity-50 cursor-wait' : ''}
                disabled:cursor-default
              `}
            >
              Save
            </button>
            <button
              disabled={isSubmitting || !canReply}
              onClick={handleCancel}
              className={`
                px-3 py-1.5 rounded-[8px] text-[13px] font-medium transition-all
                border border-border bg-surface-card-muted text-text-secondary hover:bg-fill-soft active:bg-fill-medium
                ${isSubmitting ? 'opacity-50 cursor-wait' : ''}
                disabled:cursor-default
              `}
            >
              Cancel
            </button>
          </div>
        ) : (
          <span className="text-[12px] text-text-secondary">
            Waiting for a save location…
          </span>
        )}
      </div>
    </div>
  );
};
