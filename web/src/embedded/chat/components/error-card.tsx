import { cn } from '@/utils/cn';
import { type HTMLAttributes } from 'react';
import { MaskedScrollArea } from './masked-scrollarea';
import { type ErrorPayload } from './error-card-utils';

export const ErrorCard = ({
  error,
  className,
  actions,
  onRetry,
  ...props
}: HTMLAttributes<HTMLDivElement> & {
  error: ErrorPayload;
  onRetry?: () => void;
  actions?: React.ReactNode;
}) => {
  return (
    <div
      className={cn(
        'flex flex-col gap-2 p-3 rounded-xl',
        'border border-border',
        'bg-error-bg',
        className
      )}
      {...props}
    >
      <MaskedScrollArea
        className="text-error-fg font-medium break-all"
        scrollViewClassName="max-h-[70px]"
      >
        {error.desc}
      </MaskedScrollArea>
      <div className="flex gap-2 hide-if-empty">
        {onRetry && (
          <button
            className={cn(
              'border border-border',
              'user-bubble-btn px-4 py-[3px] rounded-lg text-text-primary',
              'text-sm font-medium'
            )}
            onClick={onRetry}
          >
            Try Again
          </button>
        )}
        {actions}
      </div>
    </div>
  );
};
