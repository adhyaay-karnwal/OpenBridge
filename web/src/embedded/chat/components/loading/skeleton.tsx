import { cn } from '@/utils/cn';
import './skeleton.css';

interface SkeletonProps {
  width?: string | number;
  height?: number;
  className?: string;
}

export const Skeleton = ({ className }: SkeletonProps) => (
  <div
    className={cn(
      'relative overflow-hidden rounded-lg bg-fill-medium',
      className
    )}
  >
    <div
      className={cn(
        'absolute inset-0',
        '-translate-x-full animate-[shimmer_1.5s_infinite]',
        'bg-linear-to-r from-transparent via-bg-highlight/70 to-transparent dark:via-white/20',
        'border-t-[0.5px] border-t-border'
      )}
    />
  </div>
);
