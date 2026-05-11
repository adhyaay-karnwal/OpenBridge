import type { SessionHistoryMessage } from '../../types/history';
import { CheckmarkCircleFillSFSymbolRegular } from '@/assets/sf-symbols/regular/checkmark.circle.fill';
import { DiffFileTree } from './diff-file-tree';

export const SandboxReviewMessage = ({
  message,
}: {
  message: SessionHistoryMessage;
}) => {
  const reviewDiff = message.reviewDiff ?? [];
  const reviewDiffTotal = message.reviewDiffTotal ?? reviewDiff.length;
  const hiddenCount = Math.max(0, reviewDiffTotal - reviewDiff.length);

  return (
    <div className="select-none rounded-[12px] overflow-hidden border border-border bg-surface-card">
      <div className="flex items-center px-[8px] py-[6px] gap-1">
        <div className="flex-shrink-0 w-5 h-5 flex items-center justify-center">
          <CheckmarkCircleFillSFSymbolRegular className="text-[#25D083] text-[15px]" />
        </div>
        <span className="text-[13px] text-text-primary font-medium leading-tight">
          {message.acceptedSummary ?? 'Workspace changes reviewed.'}
        </span>
      </div>

      {reviewDiff.length > 0 && (
        <div className="px-[8px] pb-[8px]">
          <DiffFileTree diffs={reviewDiff} readOnly maxHeight={240} />
        </div>
      )}

      {hiddenCount > 0 && (
        <div className="px-[8px] pb-[8px] text-[12px] leading-[16px] text-text-secondary">
          Showing first {reviewDiff.length} of {reviewDiffTotal} changes.{' '}
          {hiddenCount} hidden.
        </div>
      )}
    </div>
  );
};
