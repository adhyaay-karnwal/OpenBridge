import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type RefObject,
} from 'react';
import { createPortal } from 'react-dom';
import type { QuoteSelection } from './chat-quote-dom';
import { getQuoteSelectionFromWindow } from './chat-quote-dom';

type BubblePlacement = 'above' | 'below';

type BubbleViewport = {
  left: number;
  top: number;
  width: number;
  height: number;
};

type BubbleSize = {
  width: number;
  height: number;
};

const DEFAULT_BUBBLE_SIZE: BubbleSize = {
  width: 120,
  height: 40,
};

const BUBBLE_GAP_PX = 10;
const BUBBLE_VIEWPORT_MARGIN_PX = 12;

function clamp(value: number, minimum: number, maximum: number) {
  if (maximum < minimum) {
    return minimum;
  }

  return Math.min(Math.max(value, minimum), maximum);
}

export function getBubbleViewport(): BubbleViewport {
  return {
    left: window.visualViewport?.offsetLeft ?? 0,
    top: window.visualViewport?.offsetTop ?? 0,
    width: window.visualViewport?.width ?? window.innerWidth,
    height: window.visualViewport?.height ?? window.innerHeight,
  };
}

export function resolveQuoteSelectionBubblePosition(params: {
  anchorRect: Pick<DOMRect, 'bottom' | 'height' | 'left' | 'top' | 'width'>;
  safeAreaInsetTop?: number;
  bubbleSize?: BubbleSize | null;
  viewport?: BubbleViewport;
}) {
  const {
    anchorRect,
    safeAreaInsetTop = 0,
    bubbleSize = DEFAULT_BUBBLE_SIZE,
    viewport = getBubbleViewport(),
  } = params;
  const resolvedBubbleSize = bubbleSize ?? DEFAULT_BUBBLE_SIZE;

  const bubbleWidth = Math.max(
    0,
    resolvedBubbleSize.width || DEFAULT_BUBBLE_SIZE.width
  );
  const bubbleHeight = Math.max(
    0,
    resolvedBubbleSize.height || DEFAULT_BUBBLE_SIZE.height
  );
  const viewportLeft = viewport.left;
  const viewportTop = viewport.top;
  const viewportRight = viewport.left + viewport.width;
  const viewportBottom = viewport.top + viewport.height;
  const minimumLeft = viewportLeft + BUBBLE_VIEWPORT_MARGIN_PX;
  const maximumWidth = Math.max(
    0,
    viewport.width - BUBBLE_VIEWPORT_MARGIN_PX * 2
  );
  const resolvedBubbleWidth =
    maximumWidth > 0 ? Math.min(bubbleWidth, maximumWidth) : bubbleWidth;
  const maximumLeft =
    viewportRight - BUBBLE_VIEWPORT_MARGIN_PX - resolvedBubbleWidth;
  const centeredLeft =
    anchorRect.left + anchorRect.width / 2 - resolvedBubbleWidth / 2;
  const minimumTop = viewportTop + safeAreaInsetTop + BUBBLE_VIEWPORT_MARGIN_PX;
  const maximumTop = viewportBottom - BUBBLE_VIEWPORT_MARGIN_PX - bubbleHeight;

  const availableAbove =
    anchorRect.top - minimumTop - BUBBLE_GAP_PX - bubbleHeight;
  const availableBelow =
    viewportBottom -
    BUBBLE_VIEWPORT_MARGIN_PX -
    anchorRect.bottom -
    BUBBLE_GAP_PX -
    bubbleHeight;
  const placement: BubblePlacement =
    availableAbove >= 0 || availableAbove >= availableBelow ? 'above' : 'below';

  const unclampedTop =
    placement === 'above'
      ? anchorRect.top - BUBBLE_GAP_PX - bubbleHeight
      : anchorRect.bottom + BUBBLE_GAP_PX;

  return {
    left: clamp(centeredLeft, minimumLeft, maximumLeft),
    top: clamp(unclampedTop, minimumTop, maximumTop),
    maxWidth: maximumWidth,
    placement,
  };
}

export function QuoteSelectionBubble({
  containerRef,
  label = 'Ask OpenBridge',
  safeAreaInsetTop = 0,
  onAskQuote,
}: {
  containerRef: RefObject<HTMLElement | null>;
  label?: string;
  safeAreaInsetTop?: number;
  onAskQuote: (selection: QuoteSelection) => void;
}) {
  const [selection, setSelection] = useState<QuoteSelection | null>(null);
  const [bubbleSize, setBubbleSize] = useState<BubbleSize | null>(null);
  const buttonRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    let isPointerSelecting = false;
    const visualViewport = window.visualViewport;

    const updateSelection = () => {
      if (isPointerSelecting) {
        setSelection(null);
        return;
      }

      setSelection(getQuoteSelectionFromWindow(containerRef.current));
    };

    const handleMouseDown = (event: MouseEvent) => {
      if (!containerRef.current?.contains(event.target as Node | null)) {
        return;
      }

      isPointerSelecting = true;
      setSelection(null);
    };

    const handleMouseUp = () => {
      if (!isPointerSelecting) {
        return;
      }

      isPointerSelecting = false;
      window.requestAnimationFrame(updateSelection);
    };

    document.addEventListener('selectionchange', updateSelection);
    document.addEventListener('mousedown', handleMouseDown);
    document.addEventListener('mouseup', handleMouseUp);
    window.addEventListener('resize', updateSelection);
    window.addEventListener('scroll', updateSelection, true);
    visualViewport?.addEventListener('resize', updateSelection);
    visualViewport?.addEventListener('scroll', updateSelection);

    return () => {
      document.removeEventListener('selectionchange', updateSelection);
      document.removeEventListener('mousedown', handleMouseDown);
      document.removeEventListener('mouseup', handleMouseUp);
      window.removeEventListener('resize', updateSelection);
      window.removeEventListener('scroll', updateSelection, true);
      visualViewport?.removeEventListener('resize', updateSelection);
      visualViewport?.removeEventListener('scroll', updateSelection);
    };
  }, [containerRef]);

  useEffect(() => {
    if (!selection) {
      setBubbleSize(null);
    }
  }, [selection]);

  useLayoutEffect(() => {
    if (!selection) {
      return;
    }

    const nextRect = buttonRef.current?.getBoundingClientRect();
    if (!nextRect || nextRect.width <= 0 || nextRect.height <= 0) {
      return;
    }

    setBubbleSize(current => {
      if (
        current &&
        Math.abs(current.width - nextRect.width) < 0.5 &&
        Math.abs(current.height - nextRect.height) < 0.5
      ) {
        return current;
      }

      return {
        width: nextRect.width,
        height: nextRect.height,
      };
    });
  }, [label, selection]);

  const position = useMemo(() => {
    if (!selection) {
      return null;
    }

    return resolveQuoteSelectionBubblePosition({
      anchorRect: selection.anchorRect,
      safeAreaInsetTop,
      bubbleSize,
    });
  }, [bubbleSize, safeAreaInsetTop, selection]);

  if (!selection || !position) {
    return null;
  }

  return createPortal(
    <button
      ref={buttonRef}
      type="button"
      className="fixed z-[2147483645] inline-flex items-center gap-2 rounded-full border border-black/10 bg-white px-4 py-2 text-[13px] font-medium text-neutral-900 shadow-[0_12px_30px_rgba(15,23,42,0.18)] transition-transform hover:scale-[1.01] dark:border-white/10 dark:bg-neutral-900 dark:text-white"
      style={{
        left: position.left,
        top: position.top,
        maxWidth: position.maxWidth,
        visibility: bubbleSize ? 'visible' : 'hidden',
      }}
      onMouseDown={event => {
        event.preventDefault();
      }}
      onClick={() => {
        onAskQuote(selection);
        window.getSelection()?.removeAllRanges();
        setSelection(null);
      }}
    >
      <span className="text-base leading-none">❝</span>
      <span>{label}</span>
    </button>,
    document.body
  );
}
