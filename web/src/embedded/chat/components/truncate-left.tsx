import { cn } from '@/utils/cn';
import type { HTMLAttributes } from 'react';

export const TruncateLeft = ({
  children,
  className,
}: HTMLAttributes<HTMLDivElement>) => {
  return (
    <div className={cn('text-left', className)}>
      <span className="inline-block max-w-full truncate" dir="rtl">
        {children}
      </span>
    </div>
  );
};
