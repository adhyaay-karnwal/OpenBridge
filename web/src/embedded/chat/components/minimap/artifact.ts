import { Minimap, type MinimapOptions, type NodeEntry } from './minimap';

const CHAT_MAX_WIDTH = 800;

export class ArtifactMinimap extends Minimap {
  constructor(artifactId?: string, options?: MinimapOptions) {
    super(artifactId, options);
  }

  protected get rootId() {
    return 'artifact-minimap-root';
  }

  static toggle(artifactId?: string, options?: MinimapOptions) {
    Minimap.toggleInstance(() => new ArtifactMinimap(artifactId, options));
  }

  static hasEntries(options?: MinimapOptions): boolean {
    return (
      Minimap.resolveScopeRoot(options).querySelectorAll('[data-artifact]')
        .length > 0
    );
  }

  protected queryNodes(): NodeEntry[] {
    const nodes: NodeEntry[] = [];
    this.querySelectorAll('[data-artifact]').forEach(el => {
      if (!(el instanceof HTMLElement)) return;
      if (el.dataset.isCloned) return;
      const artifactId = el.dataset.artifact;
      if (!artifactId) return;
      nodes.push({
        id: artifactId,
        sourceEl: el as HTMLDivElement,
        sourceRect: el.getBoundingClientRect(),
      });
    });
    return nodes;
  }

  protected getEntryId(sourceEl: HTMLElement): string | null {
    return sourceEl.dataset.artifact ?? null;
  }

  protected createLayout(rootEl: HTMLDivElement): HTMLElement {
    this.applyRootInsets(rootEl);
    rootEl.classList.add('pb-4', 'pt-20');

    const containerEl = document.createElement('div');
    containerEl.className = 'flex flex-col gap-2 items-start';
    this.applyContentMaxWidth(containerEl, CHAT_MAX_WIDTH);
    containerEl.style.margin = '0px auto';
    rootEl.appendChild(containerEl);
    return containerEl;
  }

  protected prepareClone(
    entry: NodeEntry,
    cloneEl: HTMLDivElement
  ): HTMLElement {
    const wrapperEl = document.createElement('div');
    wrapperEl.style.width = entry.sourceRect.width + 'px';
    wrapperEl.appendChild(cloneEl);

    // a fix for select element
    const selectEl = cloneEl.querySelector('select');
    if (selectEl) {
      const sourceSelect = entry.sourceEl.querySelector('select');
      if (sourceSelect) {
        selectEl.value = sourceSelect.value;
        selectEl.disabled = true;
      }
    }

    return wrapperEl;
  }
}
