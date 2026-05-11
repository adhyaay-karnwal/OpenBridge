import {
  forwardRef,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  type HtmlHTMLAttributes,
  type Ref,
} from 'react';
import { cn } from '@/utils/cn';
import './index.css';
import { observeResize } from '@/utils/observe-resize';

function setRef<T>(ref: Ref<T> | undefined, value: T | null) {
  if (typeof ref === 'function') {
    ref(value);
  } else if (ref) {
    (ref as React.MutableRefObject<T | null>).current = value;
  }
}

export type MaskedScrollAreaProps = HtmlHTMLAttributes<HTMLDivElement> & {
  horizontal?: boolean;
  maskSize?: number;
  maskSizeStart?: number;
  maskSizeEnd?: number;
  triggerSize?: number;
  triggerSizeStart?: number;
  triggerSizeEnd?: number;
  enable?: boolean;
  navButtonsVisibility?: 'always' | 'hover' | 'never';
  startNavButton?: React.ReactNode;
  startNavButtonClassName?: string;
  endNavButton?: React.ReactNode;
  endNavButtonClassName?: string;
  scrollViewClassName?: string;
  contentClassName?: string;
  contentStyle?: React.CSSProperties;
};

export const MaskedScrollArea = forwardRef<
  HTMLDivElement,
  MaskedScrollAreaProps
>(
  (
    {
      className,
      horizontal,
      children,
      maskSizeStart: propMaskSizeStart,
      maskSizeEnd: propMaskSizeEnd,
      triggerSizeStart: propTriggerSizeStart,
      triggerSizeEnd: propTriggerSizeEnd,
      maskSize = 20,
      triggerSize = 2,
      enable = true,

      // nav buttons
      navButtonsVisibility = 'never',
      startNavButton,
      endNavButton,
      startNavButtonClassName,
      endNavButtonClassName,
      scrollViewClassName,
      contentClassName,
      contentStyle,
      ...attrs
    },
    forwardedRef
  ) => {
    const internalRef = useRef<HTMLDivElement>(null);
    // Use a ref to store the latest forwardedRef to avoid stale closure
    const forwardedRefRef = useRef(forwardedRef);
    forwardedRefRef.current = forwardedRef;
    const contentRef = useRef<HTMLDivElement>(null);
    const maskSizeStart = propMaskSizeStart ?? maskSize;
    const maskSizeEnd = propMaskSizeEnd ?? maskSize;
    const triggerSizeStart = propTriggerSizeStart ?? triggerSize;
    const triggerSizeEnd = propTriggerSizeEnd ?? triggerSize;

    const detect = useCallback(() => {
      const el = internalRef.current;
      if (!el) return;
      if (!enable) return;
      const scrollPos = horizontal ? el.scrollLeft : el.scrollTop;

      const isStart = scrollPos <= triggerSizeStart;
      const isEnd = horizontal
        ? el.scrollLeft >= el.scrollWidth - el.offsetWidth - triggerSizeEnd
        : el.scrollTop >= el.scrollHeight - el.offsetHeight - triggerSizeEnd;

      // apply mask
      const dir = horizontal ? 'to right' : 'to bottom';
      const start = isStart ? '0px' : `${maskSizeStart}px`;
      const end = isEnd ? '0px' : `${maskSizeEnd}px`;
      el.style.setProperty('--masked-scroll-area-mask-distance-start', start);
      el.style.setProperty('--masked-scroll-area-mask-distance-end', end);
      el.style.setProperty('--masked-scroll-area-mask-direction', dir);

      // update info to container
      const container = el.closest('.masked-scroll-area-container');
      if (container) {
        container.classList.toggle('is-at-start', isStart);
        container.classList.toggle('is-at-end', isEnd);
      }

      return { isStart, isEnd };
    }, [
      enable,
      horizontal,
      maskSizeStart,
      maskSizeEnd,
      triggerSizeStart,
      triggerSizeEnd,
    ]);

    useEffect(() => {
      const el = internalRef.current;
      if (!el) return;

      el.addEventListener('scroll', detect);
      detect();

      return () => {
        el.removeEventListener('scroll', detect);
      };
    }, [detect]);

    useEffect(() => {
      const el = contentRef.current;
      if (!el) return;
      return observeResize(el, detect);
    }, [detect]);

    const scrollForward = useCallback(() => {
      const el = internalRef.current;
      if (!el) return;
      if (horizontal) {
        el.scrollTo({
          left: el.scrollLeft + el.offsetWidth,
          behavior: 'smooth',
        });
      } else {
        el.scrollTo({
          top: el.scrollTop + el.offsetHeight,
          behavior: 'smooth',
        });
      }
    }, [internalRef, horizontal]);

    const scrollBackward = useCallback(() => {
      const el = internalRef.current;
      if (!el) return;
      if (horizontal) {
        el.scrollTo({
          left: el.scrollLeft - el.offsetWidth,
          behavior: 'smooth',
        });
      } else {
        el.scrollTo({
          top: el.scrollTop - el.offsetHeight,
          behavior: 'smooth',
        });
      }
    }, [internalRef, horizontal]);

    const mergedRef = useCallback((node: HTMLDivElement | null) => {
      (internalRef as React.MutableRefObject<HTMLDivElement | null>).current =
        node;
      setRef(forwardedRefRef.current, node);
    }, []);

    const navButtons = useMemo(() => {
      if (navButtonsVisibility === 'never') return null;
      return (
        <>
          <div
            className={cn(
              'masked-scroll-area-nav-button-start',
              navButtonsVisibility === 'hover' &&
                'masked-scroll-area-nav-button-hover',
              horizontal
                ? 'left-0 top-[50%] -translate-y-1/2'
                : 'top-0 left-[50%] -translate-x-1/2',
              startNavButtonClassName
            )}
            onClick={e => {
              e.stopPropagation();
              e.preventDefault();
              scrollBackward();
            }}
          >
            {startNavButton}
          </div>
          <div
            className={cn(
              'masked-scroll-area-nav-button-end',
              navButtonsVisibility === 'hover' &&
                'masked-scroll-area-nav-button-hover',
              horizontal
                ? 'right-0 top-[50%] -translate-y-1/2'
                : 'bottom-0 right-[50%] -translate-x-1/2',
              endNavButtonClassName
            )}
            onClick={e => {
              e.stopPropagation();
              e.preventDefault();
              scrollForward();
            }}
          >
            {endNavButton}
          </div>
        </>
      );
    }, [
      navButtonsVisibility,
      startNavButton,
      endNavButton,
      horizontal,
      startNavButtonClassName,
      endNavButtonClassName,
      scrollBackward,
      scrollForward,
    ]);

    return (
      <div className={cn('masked-scroll-area-container relative', className)}>
        <div
          ref={mergedRef}
          className={cn(
            'masked-scroll-area',
            horizontal ? 'overflow-x-auto' : 'overflow-y-auto',
            horizontal ? 'w-full' : 'h-full',
            scrollViewClassName
          )}
          {...attrs}
        >
          <div
            className={cn('masked-scroll-area-content', contentClassName)}
            ref={contentRef}
            style={contentStyle}
          >
            {children}
          </div>
        </div>
        {navButtons}
      </div>
    );
  }
);

MaskedScrollArea.displayName = 'MaskedScrollArea';
