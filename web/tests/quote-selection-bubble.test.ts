import { describe, expect, it } from 'vitest';
import { resolveQuoteSelectionBubblePosition } from '../src/utils/quote-selection-bubble';

function createAnchorRect(overrides: Partial<DOMRect> = {}): DOMRect {
  return {
    bottom: 120,
    height: 24,
    left: 160,
    right: 280,
    top: 96,
    width: 120,
    x: 160,
    y: 96,
    toJSON: () => ({}),
    ...overrides,
  } as DOMRect;
}

const viewport = {
  left: 0,
  top: 0,
  width: 440,
  height: 272,
};

describe('resolveQuoteSelectionBubblePosition', () => {
  it('clamps the bubble inside the right viewport edge', () => {
    const position = resolveQuoteSelectionBubblePosition({
      anchorRect: createAnchorRect({
        left: 392,
        width: 40,
      }),
      bubbleSize: {
        width: 120,
        height: 48,
      },
      viewport,
    });

    expect(position.left).toBe(308);
    expect(position.placement).toBe('above');
  });

  it('clamps the bubble inside the left viewport edge', () => {
    const position = resolveQuoteSelectionBubblePosition({
      anchorRect: createAnchorRect({
        left: 0,
        width: 36,
      }),
      bubbleSize: {
        width: 120,
        height: 48,
      },
      viewport,
    });

    expect(position.left).toBe(12);
  });

  it('places the bubble below when the top safe area removes the above space', () => {
    const position = resolveQuoteSelectionBubblePosition({
      anchorRect: createAnchorRect({
        top: 56,
        bottom: 76,
        height: 20,
        left: 200,
        width: 48,
      }),
      bubbleSize: {
        width: 120,
        height: 48,
      },
      safeAreaInsetTop: 40,
      viewport,
    });

    expect(position.placement).toBe('below');
    expect(position.top).toBe(86);
  });
});
