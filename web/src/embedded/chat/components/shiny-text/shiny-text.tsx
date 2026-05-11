import { useEffect, useRef, type HTMLAttributes } from 'react';
import './shiny-text.css';
import { cn } from '@/utils/cn';
import { observeResize } from '@/utils/observe-resize';

export const ShinyText = ({
  children,
  className,
  speed = 250,
  size = 100,
  color = 'var(--color-text-highlight)',
  ...attrs
}: HTMLAttributes<HTMLSpanElement> & {
  /* how many pixels to move per second */
  speed?: number;
  /* Highlight size in px */
  size?: number;
  /* Highlight color (any CSS color) */
  color?: string;
}) => {
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const apply = (widthPx?: number) => {
      const width = widthPx ?? el.offsetWidth;
      const pxPerSec = Math.max(1, speed);
      const stripePx = Math.max(1, size);
      // Travel across full width + off-screen enter/exit equal to stripe width
      const durationSec = (width + stripePx * 2) / pxPerSec;

      el.style.setProperty('--shine-color', color);
      el.style.setProperty('--shine-size', `${stripePx}px`);
      el.style.setProperty('--shine-duration', `${durationSec.toFixed(3)}s`);
    };

    // initial
    apply();
    // react to resize
    const dispose = observeResize(el, entry => {
      apply(entry.contentRect.width);
    });
    return () => dispose();
  }, [speed, size, color]);

  return (
    <span ref={ref} className={cn('shiny-text', className)} {...attrs}>
      {children}
    </span>
  );
};
