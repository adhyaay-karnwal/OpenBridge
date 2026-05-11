import { prepare, layout } from '@chenglou/pretext';
import { useEffect, useRef, type RefObject } from 'react';

/**
 * Uses Pretext to predict the content height of a code block without
 * triggering DOM layout reflow. Replaces ResizeObserver-based measurement.
 *
 * On first mount, reads the computed font and line-height from the element.
 * On each code change, runs Pretext's pure-arithmetic layout to predict height.
 */
export function useCodeContentHeight(
  code: string,
  contentRef: RefObject<HTMLElement | null>,
  onHeight: (height: number) => void
) {
  const fontRef = useRef<{ font: string; lineHeight: number } | null>(null);

  useEffect(() => {
    const el = contentRef.current;
    if (!el) return;

    // Read and cache font spec from computed styles (system monospace fonts
    // don't require async loading, so this is stable after first mount)
    if (!fontRef.current) {
      const cs = getComputedStyle(el);
      fontRef.current = {
        font: `${cs.fontSize} ${cs.fontFamily}`,
        lineHeight: parseFloat(cs.lineHeight) || 20,
      };
    }

    const { font, lineHeight } = fontRef.current;
    // Use pre-wrap mode to preserve hard breaks and whitespace (matches <pre>).
    // maxWidth is set very large so soft-wrapping never occurs (white-space: pre).
    const prepared = prepare(code, font, { whiteSpace: 'pre-wrap' });
    const result = layout(prepared, 100000, lineHeight);
    onHeight(result.height);
  }, [code, contentRef, onHeight]);
}
