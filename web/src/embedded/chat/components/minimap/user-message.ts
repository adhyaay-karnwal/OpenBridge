import { Minimap, type MinimapOptions, type NodeEntry } from './minimap';

const CHAT_MAX_WIDTH = 800;
const MESSAGE_NODE_PADDING_LEFT = 40;
const NODE_CONTENT_TRANSITION = 'max-height 0.5s cubic-bezier(.62,.26,.02,.99)';
const NODE_MAX_LINE = 3;
const NODE_CONTENT_MAX_HEIGHT = NODE_MAX_LINE * 20;
const NODE_PADDING_Y = 8 * 2;

export class UserMessageMinimap extends Minimap {
  constructor(messageId?: string, options?: MinimapOptions) {
    super(messageId, options);
  }

  protected get rootId() {
    return 'user-message-minimap-root';
  }

  static toggle(messageId?: string, options?: MinimapOptions) {
    Minimap.toggleInstance(() => new UserMessageMinimap(messageId, options));
  }

  protected queryNodes(): NodeEntry[] {
    const nodes: NodeEntry[] = [];
    this.querySelectorAll('.user-message-bubble').forEach((el, index) => {
      if (!(el instanceof HTMLDivElement)) return;
      if (el.dataset.isCloned) return;
      nodes.push({
        id: el.dataset.messageId ?? index.toString(),
        sourceEl: el,
        sourceRect: el.getBoundingClientRect(),
      });
    });
    return nodes;
  }

  protected getEntryId(sourceEl: HTMLElement): string | null {
    return sourceEl.dataset.messageId ?? null;
  }

  protected createLayout(rootEl: HTMLDivElement): HTMLElement {
    this.applyRootInsets(rootEl);
    rootEl.classList.add('pb-4', 'pt-20');

    const containerEl = document.createElement('div');
    containerEl.className = 'flex flex-col gap-2 items-end';
    this.applyContentMaxWidth(containerEl, CHAT_MAX_WIDTH);
    containerEl.style.margin = '0px auto';
    containerEl.style.paddingLeft = `${MESSAGE_NODE_PADDING_LEFT}px`;
    rootEl.appendChild(containerEl);
    return containerEl;
  }

  protected prepareClone(
    entry: NodeEntry,
    cloneEl: HTMLDivElement
  ): HTMLElement {
    if (cloneEl.firstChild instanceof HTMLDivElement) {
      cloneEl.firstChild.style.transition = NODE_CONTENT_TRANSITION;
      cloneEl.firstChild.style.maxHeight = `${entry.sourceRect.height - NODE_PADDING_Y}px`;
    }

    const wrapperEl = document.createElement('div');
    wrapperEl.style.maxHeight = `${NODE_CONTENT_MAX_HEIGHT + NODE_PADDING_Y}px`;
    wrapperEl.style.width = entry.sourceRect.width + 'px';
    wrapperEl.appendChild(cloneEl);
    return wrapperEl;
  }

  protected override onOpenAnimate(
    _entry: NodeEntry,
    cloneEl: HTMLDivElement
  ): void {
    if (cloneEl.firstChild instanceof HTMLDivElement) {
      cloneEl.firstChild.style.maxHeight = `${NODE_CONTENT_MAX_HEIGHT}px`;
      cloneEl.firstChild.style.overflow = 'hidden';
    }
  }

  protected override onCloseAnimate(
    entry: NodeEntry,
    cloneEl: HTMLDivElement
  ): void {
    if (cloneEl.firstChild instanceof HTMLDivElement) {
      cloneEl.firstChild.style.maxHeight =
        entry.sourceRect.height - NODE_PADDING_Y + 'px';
    }
  }
}
