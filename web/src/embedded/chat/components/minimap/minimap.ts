const NODE_TRANSITION =
  'transform 0.5s cubic-bezier(.62,.26,.02,.99), background 0.2s ease';
const BG_BLUR_TRANSITION = 'filter 0.4s ease';
const BG_BLUR_RADIUS = 10;

/**
 * The strategy to scroll to the target message
 * - start: the target message is at the top of the screen
 * - middle: the target message is at the middle of the screen
 * - original: the target message is at the original position of the minimap
 */
const DEFAULT_SCROLL_TO_STRATEGY: ScrollToStrategy = 'middle';

type ScrollToStrategy = 'start' | 'middle' | 'original';

export type MinimapCloseSubscription = (
  close: () => void
) => void | (() => void);

export interface MinimapLayout {
  viewportPaddingX?: number;
  insetLeft?: number;
  insetRight?: number;
  contentMaxWidth?: number;
}

export interface MinimapOptions {
  closeSubscriptions?: MinimapCloseSubscription[];
  getScopeRoot?: () => HTMLElement | null | undefined;
  layout?: MinimapLayout;
  scopeRoot?: HTMLElement | null;
  getInsights?: () => MinimapLayout | undefined;
}

interface ResolvedMinimapLayout {
  viewportPaddingX: number;
  insetLeft: number;
  insetRight: number;
  contentMaxWidth?: number;
}

export interface NodeEntry {
  id: string;
  sourceEl: HTMLDivElement;
  sourceRect: DOMRect;
  cloneEl?: HTMLDivElement;
  cloneRect?: DOMRect;
}

export abstract class Minimap {
  protected static activeMinimap: Minimap | null = null;

  private rootEl: HTMLDivElement | null = null;
  private scopeRoot: HTMLElement | null = null;
  private entries: NodeEntry[] = [];
  private cleanups: (() => void)[] = [];
  private closed = false;
  private state: 'idle' | 'opening' | 'opened' | 'closing' | 'closed' = 'idle';

  constructor(
    protected readonly targetId?: string,
    private readonly options: MinimapOptions = {}
  ) {}

  protected abstract get rootId(): string;

  /** Find all source DOM nodes for this minimap type */
  protected abstract queryNodes(): NodeEntry[];

  /** Extract the entry identifier from a source element (used for click-to-scroll) */
  protected abstract getEntryId(sourceEl: HTMLElement): string | null;

  /**
   * Create the layout inside rootEl. The subclass has full control over
   * the container structure, padding, alignment, grid/flex, etc.
   * Must append its container to rootEl and return the element where
   * cloned nodes should be inserted.
   */
  protected abstract createLayout(rootEl: HTMLDivElement): HTMLElement;

  /**
   * Prepare a cloned element for the minimap layout.
   * Wrap it, set constraints (e.g. max-height), configure content transitions.
   * Return the outermost element to insert into the layout container.
   */
  protected abstract prepareClone(
    entry: NodeEntry,
    cloneEl: HTMLDivElement
  ): HTMLElement;

  /** Called during the opening animation for each clone (e.g. collapse content height) */
  protected onOpenAnimate(_entry: NodeEntry, _cloneEl: HTMLDivElement): void {}

  /** Called during the closing animation for each clone (e.g. restore content height) */
  protected onCloseAnimate(_entry: NodeEntry, _cloneEl: HTMLDivElement): void {}

  protected getLayout(fallbackContentMaxWidth?: number): ResolvedMinimapLayout {
    const layout = {
      ...this.options.layout,
      ...this.options.getInsights?.(),
    };

    return {
      viewportPaddingX: Math.max(0, layout.viewportPaddingX ?? 20),
      insetLeft: Math.max(0, layout.insetLeft ?? 0),
      insetRight: Math.max(0, layout.insetRight ?? 0),
      contentMaxWidth: layout.contentMaxWidth ?? fallbackContentMaxWidth,
    };
  }

  protected applyRootInsets(rootEl: HTMLDivElement): void {
    const layout = this.getLayout();
    rootEl.style.paddingLeft = `${layout.viewportPaddingX + layout.insetLeft}px`;
    rootEl.style.paddingRight = `${layout.viewportPaddingX + layout.insetRight}px`;
  }

  protected applyContentMaxWidth(
    containerEl: HTMLElement,
    fallbackContentMaxWidth: number
  ): void {
    const layout = this.getLayout(fallbackContentMaxWidth);
    const contentMaxWidth = layout.contentMaxWidth ?? fallbackContentMaxWidth;
    containerEl.style.maxWidth = `${contentMaxWidth}px`;
  }

  protected querySelectorAll(selector: string): Element[] {
    return Array.from(this.getScopeRoot().querySelectorAll(selector));
  }

  protected static toggleInstance(factory: () => Minimap): void {
    if (Minimap.activeMinimap) {
      Minimap.activeMinimap.close();
      return;
    }
    const minimap = factory();
    minimap.open();
    Minimap.activeMinimap = minimap;
  }

  protected static resolveScopeRoot(options: MinimapOptions = {}): HTMLElement {
    return options.getScopeRoot?.() ?? options.scopeRoot ?? document.body;
  }

  private getScopeRoot(): HTMLElement {
    return this.scopeRoot ?? Minimap.resolveScopeRoot(this.options);
  }

  private isGlobalScope(scopeRoot: HTMLElement): boolean {
    return (
      scopeRoot === document.body || scopeRoot === document.documentElement
    );
  }

  private getScopeViewportRect() {
    const scopeRoot = this.getScopeRoot();
    if (this.isGlobalScope(scopeRoot)) {
      const width = document.documentElement.clientWidth || window.innerWidth;
      const height =
        document.documentElement.clientHeight || window.innerHeight;
      return {
        bottom: height,
        height,
        left: 0,
        right: width,
        top: 0,
        width,
      };
    }

    return scopeRoot.getBoundingClientRect();
  }

  private ensureScopeContainingBlock(scopeRoot: HTMLElement) {
    if (this.isGlobalScope(scopeRoot)) {
      return;
    }

    if (window.getComputedStyle(scopeRoot).position !== 'static') {
      return;
    }

    const previousPosition = scopeRoot.style.position;
    scopeRoot.style.position = 'relative';
    this.cleanups.push(() => {
      scopeRoot.style.position = previousPosition;
    });
  }

  public open() {
    const scopeRoot = Minimap.resolveScopeRoot(this.options);
    this.scopeRoot = scopeRoot;
    const rootEl = document.createElement('div');
    this.rootEl = rootEl;
    rootEl.id = this.rootId;
    rootEl.className = this.isGlobalScope(scopeRoot)
      ? 'minimap fixed inset-0 z-100 overflow-y-hidden'
      : 'minimap absolute inset-0 z-100 overflow-y-hidden';
    rootEl.onclick = () => {
      this.close();
    };

    const containerEl = this.createLayout(rootEl);

    this.ensureScopeContainingBlock(scopeRoot);
    scopeRoot.appendChild(this.rootEl);

    this.listenForInteraction();

    // 1. Clone all source nodes
    this.entries = this.queryNodes();
    this.entries.forEach(entry => {
      const cloneEl = entry.sourceEl.cloneNode(true) as HTMLDivElement;
      cloneEl.className +=
        ' cursor-pointer dark:hover:bg-gray-200/20 hover:bg-gray-900/10';
      cloneEl.dataset.isCloned = 'true';
      // 1.1 temporary set opacity to 0
      cloneEl.style.opacity = '0';

      const wrapperEl = this.prepareClone(entry, cloneEl);
      containerEl.appendChild(wrapperEl);

      // 1.2 update entry
      entry.cloneEl = cloneEl;

      // 1.3 register click event
      cloneEl.onclick = () => {
        const id = this.getEntryId(entry.sourceEl);
        if (!id) return;
        this.to(id);
      };
    });

    // 1.5. Scroll rootEl so the target entry aligns with its anchor position
    this.scrollToInitialPosition();

    // 2. Query clone rects (after scroll) and calculate vertical offset
    this.entries.forEach(entry => {
      if (!entry.cloneEl) return;
      entry.cloneRect = entry.cloneEl.getBoundingClientRect();
      const offset = entry.sourceRect.top - entry.cloneRect.top;
      entry.cloneEl.style.transform = `translateY(${offset}px)`;
      entry.cloneEl.style.opacity = '1';
    });

    requestAnimationFrame(() => {
      // 3. Animate the nodes to their final position
      this.state = 'opening';
      this.entries.forEach(entry => {
        // 3.1 hide source element
        entry.sourceEl.style.opacity = '0';
        if (!entry.cloneEl || !entry.cloneRect) return;
        // 3.2 animate entry
        entry.cloneEl.style.transition = NODE_TRANSITION;
        entry.cloneEl.style.transform = 'translateY(0)';
        // 3.3 subclass-specific open animation
        this.onOpenAnimate(entry, entry.cloneEl);
      });
      this.animateBgBlur('in');
      const firstClone = this.entries[0]?.cloneEl;
      if (firstClone) {
        const onTransformEnd = (e: TransitionEvent) => {
          if (e.propertyName !== 'transform' || e.target !== firstClone) return;
          firstClone.removeEventListener('transitionend', onTransformEnd);
          if (this.closed) return;
          this.state = 'opened';
          this.entries.forEach(entry => {
            if (!entry.cloneEl) return;
            entry.cloneEl.style.transition = 'background 0.2s ease';
            entry.cloneEl.style.transform = '';
          });
          if (this.rootEl) {
            void this.rootEl.offsetHeight;
            this.rootEl.style.overflowY = 'auto';
          }
        };
        firstClone.addEventListener('transitionend', onTransformEnd);
      }
    });
  }

  private prevElStyleMap = new WeakMap<
    HTMLElement,
    { transition: string; filter: string }
  >();
  private animateBgBlur(dir: 'in' | 'out' = 'in') {
    const scopeRoot = this.getScopeRoot();
    scopeRoot.childNodes.forEach(child => {
      if (!(child instanceof HTMLElement)) return;
      if (child === this.rootEl || child.id === this.rootId) return;
      if (child.dataset['ignoreMinimapBlur']) return;
      if (dir === 'in') {
        this.prevElStyleMap.set(child, {
          transition: child.style.transition,
          filter: child.style.filter,
        });
        child.style.transition = BG_BLUR_TRANSITION;
        child.style.filter = `blur(${BG_BLUR_RADIUS}px)`;
      } else {
        const prevStyle = this.prevElStyleMap.get(child);
        if (!prevStyle) {
          child.style.transition = '';
          child.style.filter = '';
          return;
        }
        if (prevStyle.transition) {
          child.style.transition = prevStyle.transition;
        }
        child.style.filter = prevStyle.filter;
      }
    });
  }

  private scrollToInitialPosition() {
    if (!this.rootEl || this.entries.length === 0) return;

    let target: NodeEntry | undefined;

    if (this.targetId) {
      target = this.entries.find(e => e.id === this.targetId);
    }

    if (!target) {
      const viewportRect = this.getScopeViewportRect();
      const viewportCenterY = viewportRect.top + viewportRect.height / 2;
      let minDist = Infinity;
      for (const entry of this.entries) {
        const entryCenterY = entry.sourceRect.top + entry.sourceRect.height / 2;
        const dist = Math.abs(entryCenterY - viewportCenterY);
        if (dist < minDist) {
          minDist = dist;
          target = entry;
        }
      }
    }

    if (!target?.cloneEl) return;

    const viewportRect = this.getScopeViewportRect();
    const isInViewport =
      target.sourceRect.top >= viewportRect.top &&
      target.sourceRect.bottom <= viewportRect.bottom;
    const anchorY = isInViewport
      ? target.sourceRect.top + target.sourceRect.height / 2
      : viewportRect.top + viewportRect.height / 2;

    const cloneRect = target.cloneEl.getBoundingClientRect();
    const cloneCenterY = cloneRect.top + cloneRect.height / 2;

    const maxScroll = this.rootEl.scrollHeight - this.rootEl.clientHeight;
    this.rootEl.scrollTop = Math.max(
      0,
      Math.min(maxScroll, cloneCenterY - anchorY)
    );
  }

  public to(id: string) {
    const entry = this.entries.find(e => e.id === id);
    if (!entry) return;

    const scrollView = entry.sourceEl.closest(
      '.masked-scroll-area'
    ) as HTMLDivElement;
    if (!scrollView) return;

    const scrollViewRect = scrollView.getBoundingClientRect();
    const scopeViewportRect = this.getScopeViewportRect();
    const targetTop =
      (entry.cloneEl?.getBoundingClientRect().top ?? scrollViewRect.top) -
      scrollViewRect.top;
    const scopeTop = scopeViewportRect.top - scrollViewRect.top;
    const scopeCenter =
      scopeViewportRect.top + scopeViewportRect.height / 2 - scrollViewRect.top;
    const strategy =
      (window as any)['USER_MESSAGE_MINIMAP_SCROLL_TO_STRATEGY'] ??
      DEFAULT_SCROLL_TO_STRATEGY;
    let finalScrollTop = 0;
    const clamp = (value: number) =>
      Math.max(
        0,
        Math.min(
          scrollView.scrollHeight - scrollView.getBoundingClientRect().height,
          value
        )
      );
    const sourceElScrollTop = getTopWithinScrollView(
      entry.sourceEl,
      scrollView
    );
    if (strategy === 'original') {
      finalScrollTop = clamp(sourceElScrollTop - targetTop);
    } else if (strategy === 'start') {
      finalScrollTop = clamp(sourceElScrollTop - scopeTop - 8);
    } else if (strategy === 'middle') {
      const messageHeight = entry.sourceRect.height;
      finalScrollTop = clamp(
        sourceElScrollTop - scopeCenter + messageHeight / 2
      );
    }

    const scrollOffset = scrollView.scrollTop - finalScrollTop;
    scrollView.scrollTo({ top: finalScrollTop, behavior: 'smooth' });
    this.close(scrollOffset);
  }

  public close(scrollOffset: number = 0) {
    // 1. re-calculate node rects
    if (this.state === 'opened') {
      this.entries.forEach(entry => {
        if (!entry.cloneEl || !entry.cloneRect) return;
        entry.cloneRect = entry.cloneEl.getBoundingClientRect();
      });
    } else if (this.state === 'opening') {
      // do nothing, don't need to re-calculate node rects
    } else {
      return;
    }

    // avoid closing twice
    if (this.closed) return;
    this.closed = true;
    if (!this.rootEl) return;

    this.rootEl.style.overflowY = 'hidden';

    // 2. animate
    requestAnimationFrame(() => {
      this.entries.forEach(entry => {
        if (!entry.cloneEl || !entry.cloneRect) return;
        // 2.1 restore transform transition and animate Y position
        entry.cloneEl.style.transition = NODE_TRANSITION;
        const offset = entry.sourceRect.top - entry.cloneRect.top;
        entry.cloneEl.style.transform = `translateY(${offset + scrollOffset}px)`;

        // 2.2 subclass-specific close animation
        this.onCloseAnimate(entry, entry.cloneEl);
      });

      // 3. animation end, replace cloned elements with source elements
      const cleanup = () => {
        this.rootEl?.remove();
        this.rootEl = null;
        this.scopeRoot = null;
        this.entries.forEach(entry => {
          entry.sourceEl.style.opacity = '1';
        });
      };
      const onTransitionEnd = (e: TransitionEvent) => {
        if (e.propertyName !== 'transform') return;
        cleanup();
        this.entries[0].cloneEl?.removeEventListener(
          'transitionend',
          onTransitionEnd
        );
      };
      this.entries[0].cloneEl?.addEventListener(
        'transitionend',
        onTransitionEnd
      );

      // a timeout to ensure the transitionend event is triggered
      setTimeout(() => cleanup(), 400);
    });

    // restore source elements
    this.animateBgBlur('out');

    // clean up
    this.cleanups.forEach(cleanup => cleanup());
    this.cleanups = [];
    Minimap.activeMinimap = null;
  }

  private listenForInteraction() {
    const escapeKeyHandler = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        this.close();
      }
    };
    document.addEventListener('keydown', escapeKeyHandler);
    this.cleanups.push(() =>
      document.removeEventListener('keydown', escapeKeyHandler)
    );

    const windowResizeHandler = () => {
      this.close();
    };
    window.addEventListener('resize', windowResizeHandler);
    this.cleanups.push(() =>
      window.removeEventListener('resize', windowResizeHandler)
    );

    for (const subscribe of this.options.closeSubscriptions ?? []) {
      const cleanup = subscribe(() => this.close());
      if (cleanup) {
        this.cleanups.push(cleanup);
      }
    }
  }
}

function getTopWithinScrollView(el: HTMLElement, scrollView: HTMLElement) {
  const elRect = el.getBoundingClientRect();
  const scrollRect = scrollView.getBoundingClientRect();

  return (
    elRect.top - scrollRect.top - scrollView.clientTop + scrollView.scrollTop
  );
}
