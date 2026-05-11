import type { QuoteReference } from './chat-quote';

export type QuoteSelection = {
  text: string;
  quoteRef: QuoteReference;
  anchorRect: DOMRect;
};

function isQuotedTextNode(node: Text) {
  const parent = node.parentElement;
  if (!parent) {
    return false;
  }
  if (parent.closest('[data-quote-ignore="true"]')) {
    return false;
  }
  if (parent.closest('[aria-hidden="true"]')) {
    return false;
  }
  return true;
}

function collectTextNodes(root: HTMLElement) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: node => {
      if (
        !(node instanceof Text) ||
        !node.textContent ||
        !isQuotedTextNode(node)
      ) {
        return NodeFilter.FILTER_REJECT;
      }
      return NodeFilter.FILTER_ACCEPT;
    },
  });

  const nodes: Text[] = [];
  while (walker.nextNode()) {
    const current = walker.currentNode;
    if (current instanceof Text) {
      nodes.push(current);
    }
  }
  return nodes;
}

function findQuoteSourceRoot(node: Node | null) {
  if (!node) {
    return null;
  }
  const element = node instanceof Element ? node : node.parentElement;
  return (
    element?.closest<HTMLElement>(
      '[data-quote-source="true"][data-message-id]'
    ) ?? null
  );
}

function resolveTextOffset(
  root: HTMLElement,
  targetNode: Node,
  offset: number
) {
  if (!(targetNode instanceof Text)) {
    return null;
  }

  const textNodes = collectTextNodes(root);
  let total = 0;

  for (const textNode of textNodes) {
    const length = textNode.textContent?.length ?? 0;
    if (textNode === targetNode) {
      return total + Math.max(0, Math.min(offset, length));
    }
    total += length;
  }

  return null;
}

function buildRangeFromOffsets(
  root: HTMLElement,
  startOffset: number,
  endOffset: number
) {
  const textNodes = collectTextNodes(root);
  let traversed = 0;
  let startNode: Text | null = null;
  let endNode: Text | null = null;
  let startNodeOffset = 0;
  let endNodeOffset = 0;

  for (const textNode of textNodes) {
    const length = textNode.textContent?.length ?? 0;
    const next = traversed + length;

    if (!startNode && startOffset <= next) {
      startNode = textNode;
      startNodeOffset = Math.max(0, startOffset - traversed);
    }

    if (!endNode && endOffset <= next) {
      endNode = textNode;
      endNodeOffset = Math.max(0, endOffset - traversed);
      break;
    }

    traversed = next;
  }

  if (!startNode || !endNode) {
    return null;
  }

  const range = document.createRange();
  range.setStart(startNode, startNodeOffset);
  range.setEnd(endNode, endNodeOffset);
  return range;
}

function flashHighlightRects(range: Range, durationMs = 1000) {
  const rects = Array.from(range.getClientRects()).filter(
    rect => rect.width > 0 && rect.height > 0
  );
  if (rects.length === 0) {
    return;
  }

  const nodes = rects.map(rect => {
    const highlight = document.createElement('div');
    Object.assign(highlight.style, {
      position: 'fixed',
      pointerEvents: 'none',
      left: `${rect.left}px`,
      top: `${rect.top}px`,
      width: `${rect.width}px`,
      height: `${rect.height}px`,
      borderRadius: '6px',
      background: 'rgba(250, 204, 21, 0.35)',
      boxShadow: '0 0 0 1px rgba(250, 204, 21, 0.22) inset',
      zIndex: '2147483646',
    });
    document.body.append(highlight);
    return highlight;
  });

  window.setTimeout(() => {
    for (const node of nodes) {
      node.remove();
    }
  }, durationMs);
}

function flashFocusedMessage(element: HTMLElement, focusClassName: string) {
  element.classList.remove(focusClassName);
  void element.getBoundingClientRect();
  element.classList.add(focusClassName);
  window.setTimeout(() => {
    element.classList.remove(focusClassName);
  }, 2200);
}

export function getQuoteSelectionFromWindow(container: HTMLElement | null) {
  if (!container) {
    return null;
  }

  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
    return null;
  }

  const range = selection.getRangeAt(0);
  if (!container.contains(range.commonAncestorContainer)) {
    return null;
  }

  const startRoot = findQuoteSourceRoot(range.startContainer);
  const endRoot = findQuoteSourceRoot(range.endContainer);
  if (!startRoot || startRoot !== endRoot) {
    return null;
  }

  const startOffset = resolveTextOffset(
    startRoot,
    range.startContainer,
    range.startOffset
  );
  const endOffset = resolveTextOffset(
    startRoot,
    range.endContainer,
    range.endOffset
  );
  if (startOffset == null || endOffset == null || endOffset <= startOffset) {
    return null;
  }

  const text = selection.toString().trim();
  const anchorRect = range.getBoundingClientRect();
  const sourceMessageId = startRoot.dataset.messageId?.trim();

  if (
    !text ||
    !sourceMessageId ||
    anchorRect.width <= 0 ||
    anchorRect.height <= 0
  ) {
    return null;
  }

  return {
    text,
    quoteRef: {
      sourceMessageId,
      startOffset,
      endOffset,
    },
    anchorRect,
  } satisfies QuoteSelection;
}

export function focusQuoteInContainer(params: {
  container: HTMLElement | null;
  quoteRef: QuoteReference;
  focusClassName: string;
  textHighlightDurationMs?: number;
}) {
  const {
    container,
    quoteRef,
    focusClassName,
    textHighlightDurationMs = 1000,
  } = params;
  if (!container) {
    return false;
  }

  const escapedId = window.CSS?.escape
    ? window.CSS.escape(quoteRef.sourceMessageId)
    : quoteRef.sourceMessageId.replace(/["\\]/g, '\\$&');

  const quoteRoots = Array.from(
    container.querySelectorAll<HTMLElement>(
      `[data-quote-source="true"][data-message-id="${escapedId}"]`
    )
  );

  for (const quoteRoot of quoteRoots) {
    const range = buildRangeFromOffsets(
      quoteRoot,
      quoteRef.startOffset,
      quoteRef.endOffset
    );
    if (!range) {
      continue;
    }

    const focusTarget =
      quoteRoot.closest<HTMLElement>('.conversation-message-focus-target') ??
      quoteRoot;

    focusTarget.scrollIntoView({
      block: 'center',
      behavior: 'smooth',
    });
    flashFocusedMessage(focusTarget, focusClassName);

    window.setTimeout(() => {
      flashHighlightRects(range, textHighlightDurationMs);
    }, 260);

    return true;
  }

  const fallback = container.querySelector<HTMLElement>(
    `[data-message-id="${escapedId}"]`
  );
  if (!fallback) {
    return false;
  }

  fallback.scrollIntoView({
    block: 'center',
    behavior: 'smooth',
  });
  flashFocusedMessage(fallback, focusClassName);
  return true;
}
