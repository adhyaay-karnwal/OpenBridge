import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type RefObject,
} from 'react';
import { cn } from '@/utils/cn';
import { AnimatePresence, motion, type HTMLMotionProps } from 'motion/react';
import { ArrowDownSFSymbolRegular } from '@/assets/sf-symbols/regular/arrow.down';
import { useAutoScroll } from '../hooks/use-auto-scroll';

const ScrollToBottomContext = createContext({
  bottomRef: null as RefObject<HTMLDivElement> | null,
  showTrigger: false,
  setShowTrigger: ((_: boolean) => {}) as (show: boolean) => void,
  scrollToBottom: (() => {}) as (behavior?: ScrollBehavior) => void,
  observeBottomAnchor: ((_: Element | null) => {}) as (
    element: Element | null
  ) => void,
});

// Provider
export const ScrollToBottomProvider = ({
  children,
  containerRef,
  enableAutoScroll = true,
}: {
  children: React.ReactNode;
  containerRef?: RefObject<HTMLElement>;
  enableAutoScroll?: boolean;
}) => {
  const bottomRef = useRef<HTMLDivElement>(null);
  const [showTrigger, setShowTrigger] = useState(false);

  // Find the scroll container - either provided or find the MaskedScrollArea
  const scrollContainerRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (containerRef?.current) {
      scrollContainerRef.current = containerRef.current;
    } else {
      // Auto-find the scroll container
      const maskedScrollArea = document.querySelector(
        '.masked-scroll-area'
      ) as HTMLElement;
      if (maskedScrollArea) {
        scrollContainerRef.current = maskedScrollArea;
      }
    }
  }, [containerRef]);

  const { scrollToBottom, observeBottomAnchor } = useAutoScroll(
    scrollContainerRef,
    enableAutoScroll
  );

  return (
    <ScrollToBottomContext.Provider
      value={useMemo(
        () => ({
          bottomRef,
          showTrigger,
          setShowTrigger,
          scrollToBottom,
          observeBottomAnchor,
        }),
        [
          bottomRef,
          showTrigger,
          setShowTrigger,
          scrollToBottom,
          observeBottomAnchor,
        ]
      )}
    >
      {children}
    </ScrollToBottomContext.Provider>
  );
};

// Trigger
export const ScrollToBottomTrigger = ({
  className,
  onClick,
  ...attrs
}: HTMLMotionProps<'div'>) => {
  const { showTrigger, scrollToBottom } = useContext(ScrollToBottomContext);

  return (
    <AnimatePresence>
      {showTrigger ? (
        <motion.div
          key="scroll-to-bottom-trigger"
          initial={{ opacity: 0, y: 10, scale: 0.8 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 10, scale: 0 }}
          transition={{ duration: 0.2, ease: 'easeOut' }}
          className={cn(
            'chat-scroll-to-bottom-trigger',
            'w-8 h-8 rounded-full flex-center text-xs cursor-pointer',
            'shadow-xs dark:shadow-lg',
            className
          )}
          onClick={e => {
            onClick?.(e);
            scrollToBottom('smooth');
          }}
          {...attrs}
        >
          <ArrowDownSFSymbolRegular />
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
};

// Anchor
const SHOW_DELAY_MS = 300;

export const ScrollToBottomAnchor = () => {
  const { bottomRef, setShowTrigger, observeBottomAnchor } = useContext(
    ScrollToBottomContext
  );
  const showTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const el = bottomRef?.current;
    if (!el) return;

    // Set up the observer for auto-scroll
    observeBottomAnchor(el);

    // Set up the observer for show trigger
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) {
          // Show trigger with delay when bottom is not visible
          if (!showTimeoutRef.current) {
            showTimeoutRef.current = setTimeout(() => {
              setShowTrigger(true);
              showTimeoutRef.current = null;
            }, SHOW_DELAY_MS);
          }
        } else {
          // Hide trigger immediately
          if (showTimeoutRef.current) {
            clearTimeout(showTimeoutRef.current);
            showTimeoutRef.current = null;
          }
          setShowTrigger(false);
        }
      });
    });
    observer.observe(el);

    return () => {
      if (showTimeoutRef.current) {
        clearTimeout(showTimeoutRef.current);
        showTimeoutRef.current = null;
      }
      observer.disconnect();
      observeBottomAnchor(null);
      // reset showTrigger to false when the anchor is not visible
      setShowTrigger(false);
    };
  }, [bottomRef, setShowTrigger, observeBottomAnchor]);

  return <div className="w-full" ref={bottomRef} />;
};
