import { useEffect, useState, type HTMLAttributes } from 'react';
import { cn } from '@/utils/cn';

const DOTS = [
  { id: 'first', value: '.' },
  { id: 'second', value: '.' },
  { id: 'third', value: '.' },
];

export const LoadingEllipsis = ({
  className,
  speed = 700,
  ...props
}: Omit<HTMLAttributes<HTMLSpanElement>, 'children'> & {
  speed?: number;
}) => {
  const [dotCount, setDotCount] = useState(0);

  useEffect(() => {
    let interval = setInterval(() => {
      setDotCount(prev => (prev === DOTS.length ? 0 : prev + 1));
    }, speed);

    return () => clearInterval(interval);
  }, [speed]);

  return (
    <span className={cn('relative', className)} {...props}>
      <span className="absolute">
        {DOTS.slice(0, dotCount).map(dot => (
          <span key={dot.id}>{dot.value}</span>
        ))}
      </span>
      {/* Placeholder for the ellipsis */}
      <span className="opacity-0">...</span>
    </span>
  );
};
