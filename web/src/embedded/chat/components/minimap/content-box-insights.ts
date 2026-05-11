import type { MinimapLayout } from './minimap';

export function getContentBoxMinimapInsights(
  contentBoxId: string,
  scopeRoot?: HTMLElement | null
): MinimapLayout | undefined {
  if (typeof document === 'undefined') {
    return undefined;
  }

  const contentBox = document.getElementById(contentBoxId);
  if (!(contentBox instanceof HTMLElement)) {
    return undefined;
  }

  const rect = contentBox.getBoundingClientRect();
  if (rect.width <= 0) {
    return undefined;
  }

  const computedStyle = window.getComputedStyle(contentBox);
  const paddingLeft = Number.parseFloat(computedStyle.paddingLeft) || 0;
  const paddingRight = Number.parseFloat(computedStyle.paddingRight) || 0;
  const contentLeft = rect.left + paddingLeft;
  const contentRight = rect.right - paddingRight;
  const contentWidth = Math.max(0, contentRight - contentLeft);
  const rootRect =
    scopeRoot &&
    scopeRoot !== document.body &&
    scopeRoot !== document.documentElement
      ? scopeRoot.getBoundingClientRect()
      : {
          left: 0,
          right: document.documentElement.clientWidth || window.innerWidth,
        };

  return {
    viewportPaddingX: 0,
    insetLeft: Math.max(0, contentLeft - rootRect.left),
    insetRight: Math.max(0, rootRect.right - contentRight),
    contentMaxWidth: contentWidth,
  };
}
