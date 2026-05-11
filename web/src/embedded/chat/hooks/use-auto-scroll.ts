import { useCallback, useEffect, useMemo, useRef } from 'react';
import { throttle } from 'lodash';

/**
 * Auto-scroll hook for chat messages using IntersectionObserver
 *
 * Features:
 * - Uses IntersectionObserver to automatically trigger scrolling when content changes
 * - Automatically scrolls when bottom anchor is visible and content height changes
 * - Detects user manual scrolling and disables auto-scroll accordingly
 * - Provides smooth scrolling behavior
 *
 * @param containerRef - Reference to the scrollable container element
 * @returns Scroll state and control functions
 */
export const useAutoScroll = (
  containerRef: React.RefObject<HTMLElement | null>,
  enabled = true
) => {
  const lastScrollTopRef = useRef(0);
  const resizeObserverRef = useRef<ResizeObserver | null>(null);
  const bottomAnchorRef = useRef<Element | null>(null);
  const shouldAutoScrollRef = useRef(true);

  const scrollToBottom = useCallback(
    (behavior: ScrollBehavior = 'smooth') => {
      const container = containerRef.current;
      if (!container) return;

      container.scrollTo({
        top: container.scrollHeight,
        behavior,
      });
      shouldAutoScrollRef.current = true;
    },
    [containerRef]
  );

  // Throttled auto-scroll function (leading + trailing ensures first and last calls are executed)
  const triggerAutoScrollIfNeeded = useMemo(
    () =>
      throttle(
        () => {
          if (!shouldAutoScrollRef.current || !enabled) return;
          scrollToBottom('smooth');
        },
        50,
        { leading: true, trailing: true }
      ),
    [scrollToBottom, enabled]
  );

  // Cleanup throttle on unmount
  useEffect(() => {
    return () => {
      triggerAutoScrollIfNeeded.cancel();
    };
  }, [triggerAutoScrollIfNeeded]);

  const handleScroll = useCallback(() => {
    const container = containerRef.current;
    if (!container) return;

    const currentScrollTop = container.scrollTop;

    const distanceFromBottom =
      container.scrollHeight - currentScrollTop - container.clientHeight;
    const isScrollingUp = currentScrollTop < lastScrollTopRef.current;

    if (isScrollingUp && distanceFromBottom > 1) {
      // User is scrolling up, disable auto-scroll
      shouldAutoScrollRef.current = false;
    } else if (distanceFromBottom <= 1) {
      // User is at bottom, enable auto-scroll
      shouldAutoScrollRef.current = true;
    }

    lastScrollTopRef.current = currentScrollTop;
  }, [containerRef]);

  // Setup ResizeObserver to detect content changes
  const setupResizeObserver = useCallback(() => {
    if (!containerRef.current || resizeObserverRef.current) return;

    resizeObserverRef.current = new ResizeObserver(() => {
      const container = containerRef.current;
      if (container) {
        // Trigger auto-scroll if user is at bottom
        triggerAutoScrollIfNeeded();
      }
    });

    // Observe the container's content changes
    const contentElement = containerRef.current.firstElementChild;
    resizeObserverRef.current.observe(containerRef.current);
    if (contentElement) {
      resizeObserverRef.current.observe(contentElement);
    }

    return resizeObserverRef.current;
  }, [containerRef, triggerAutoScrollIfNeeded]);

  // Setup scroll event listener
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    container.addEventListener('scroll', handleScroll, { passive: true });

    return () => {
      container.removeEventListener('scroll', handleScroll);
    };
  }, [handleScroll, containerRef]);

  // Cleanup
  useEffect(() => {
    return () => {
      if (resizeObserverRef.current) {
        resizeObserverRef.current.disconnect();
        resizeObserverRef.current = null;
      }
    };
  }, []);

  // Function to observe the bottom anchor element
  const observeBottomAnchor = useCallback(
    (element: Element | null) => {
      if (resizeObserverRef.current) {
        resizeObserverRef.current.disconnect();
        resizeObserverRef.current = null;
      }

      bottomAnchorRef.current = element;

      if (element) {
        setupResizeObserver();
      }
    },
    [setupResizeObserver]
  );

  return {
    scrollToBottom,
    observeBottomAnchor,
  };
};
