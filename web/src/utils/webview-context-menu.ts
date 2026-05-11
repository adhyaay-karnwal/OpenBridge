import type {
  WebViewContextMenuActionEvent,
  WebViewContextMenuClosedEvent,
  WebViewContextMenuIcon,
  WebViewContextMenuItem,
  WebViewContextMenuRequest,
} from '@/jsb';

export type MenuAction = () => void | Promise<void>;

export type MenuTriggerEvent = {
  clientX: number;
  clientY: number;
  defaultPrevented: boolean;
  target: EventTarget | null;
  preventDefault: () => void;
  stopPropagation: () => void;
};

export type MenuItemOptions = {
  title: string;
  icon?: WebViewContextMenuIcon;
  enabled?: boolean;
  onClick: MenuAction;
};

export type MenuSubmenuOptions = {
  title: string;
  icon?: WebViewContextMenuIcon;
  enabled?: boolean;
  items: Menu | readonly MenuEntryInput[];
};

type MenuItemEntry = {
  kind: 'item';
  title: string;
  icon?: WebViewContextMenuIcon;
  enabled?: boolean;
  onClick: MenuAction;
};

type MenuSubmenuEntry = {
  kind: 'submenu';
  title: string;
  icon?: WebViewContextMenuIcon;
  enabled?: boolean;
  items: MenuEntry[];
};

type MenuSeparatorEntry = {
  kind: 'separator';
};

export type MenuEntry = MenuItemEntry | MenuSubmenuEntry | MenuSeparatorEntry;
type MenuEntryInput = MenuEntry | null | undefined;

type BuiltMenu = {
  handlers: Map<string, MenuAction>;
  items: WebViewContextMenuItem[];
};

type ResolvedPopupRequest = {
  handlers: Map<string, MenuAction>;
  items: WebViewContextMenuItem[];
  menuId: string;
};

export type MenuContext = {
  event: MenuTriggerEvent;
  target: EventTarget | null;
  hasSelection: boolean;
  isEditable: boolean;
};

export type MenuPopupOptions = {
  fallbackToSelectionMenu?: boolean;
  includeDefaults?: boolean;
  defaultPlacement?: 'append' | 'prepend';
  separateDefaults?: boolean;
  stopPropagation?: boolean;
  preventDefault?: boolean;
};

export type MenuConfigureOptions = {
  defaults?: Menu | ((context: MenuContext) => Menu | undefined);
};

export class Menu {
  private static readonly menuRegistry = new Map<
    string,
    Map<string, MenuAction>
  >();
  private static readonly menuCloseTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();
  private static bridgeListenersInstalled = false;
  private static installedDocument: Document | undefined;
  private static defaultMenuFactory:
    | ((context: MenuContext) => Menu | undefined)
    | undefined;
  private static readonly documentContextMenuHandler = (
    event: MouseEvent
  ): void => {
    if (event.defaultPrevented) {
      return;
    }

    Menu.popup(event);
  };

  static readonly icon = {
    symbol(name: string): WebViewContextMenuIcon {
      return { kind: 'symbol', value: name };
    },

    dataUrl(value: string): WebViewContextMenuIcon {
      return { kind: 'dataUrl', value };
    },
  };

  private readonly entries: MenuEntry[];

  private constructor(entries: MenuEntry[]) {
    this.entries = entries;
  }

  static create(entries: readonly MenuEntryInput[] = []): Menu {
    return new Menu(this.normalizeEntries(entries));
  }

  static configure(options: MenuConfigureOptions): void {
    if (!options.defaults) {
      this.clearDefaults();
      return;
    }

    if (options.defaults instanceof Menu) {
      const defaults = options.defaults.clone();
      this.defaultMenuFactory = () => defaults.clone();
      return;
    }

    const defaultsProvider = options.defaults;
    this.defaultMenuFactory = context => defaultsProvider(context)?.clone();
  }

  static clearDefaults(): void {
    this.defaultMenuFactory = undefined;
  }

  static install(target?: Document): void {
    const resolvedTarget =
      target ?? (typeof document !== 'undefined' ? document : undefined);
    if (!resolvedTarget) {
      return;
    }

    if (this.installedDocument === resolvedTarget) {
      return;
    }

    this.uninstall();
    resolvedTarget.addEventListener(
      'contextmenu',
      this.documentContextMenuHandler
    );
    this.installedDocument = resolvedTarget;
  }

  static uninstall(): void {
    if (!this.installedDocument) {
      return;
    }

    this.installedDocument.removeEventListener(
      'contextmenu',
      this.documentContextMenuHandler
    );
    this.installedDocument = undefined;
  }

  static popup(
    event: MenuTriggerEvent,
    menu?: Menu,
    options?: MenuPopupOptions
  ): boolean {
    if (!this.hasNativeContextMenuBridge()) {
      return false;
    }

    const context = this.createContext(event);
    if (options?.fallbackToSelectionMenu !== false && context.hasSelection) {
      return false;
    }

    if (options?.stopPropagation !== false) {
      event.stopPropagation();
    }
    if (options?.preventDefault !== false) {
      event.preventDefault();
    }

    const resolvedPopup = this.resolvePopupRequest(menu, context, options);
    if (resolvedPopup.handlers.size > 0) {
      this.menuRegistry.set(resolvedPopup.menuId, resolvedPopup.handlers);
    }

    this.showNativeContextMenu({
      menuId: resolvedPopup.menuId,
      x: event.clientX,
      y: event.clientY,
      items: resolvedPopup.items,
      hasSelection: context.hasSelection,
      isEditable: context.isEditable,
    });

    return true;
  }

  push(...entries: MenuEntryInput[]): this {
    this.entries.push(...Menu.normalizeEntries(entries));
    return this;
  }

  prepend(...entries: MenuEntryInput[]): this {
    this.entries.unshift(...Menu.normalizeEntries(entries));
    return this;
  }

  shift(...entries: MenuEntryInput[]): this {
    return this.prepend(...entries);
  }

  pushItem(options: MenuItemOptions): this {
    return this.push(Menu.createItemEntry(options));
  }

  prependItem(options: MenuItemOptions): this {
    return this.prepend(Menu.createItemEntry(options));
  }

  pushSubmenu(options: MenuSubmenuOptions): this {
    return this.push(Menu.createSubmenuEntry(options));
  }

  prependSubmenu(options: MenuSubmenuOptions): this {
    return this.prepend(Menu.createSubmenuEntry(options));
  }

  pushSeparator(): this {
    return this.push(Menu.createSeparatorEntry());
  }

  prependSeparator(): this {
    return this.prepend(Menu.createSeparatorEntry());
  }

  remove(predicate: (entry: MenuEntry, index: number) => boolean): this {
    const nextEntries = this.entries.filter(
      (entry, index) => !predicate(entry, index)
    );
    this.entries.splice(0, this.entries.length, ...nextEntries);
    return this;
  }

  clear(): this {
    this.entries.length = 0;
    return this;
  }

  clone(): Menu {
    return new Menu(Menu.cloneEntries(this.entries));
  }

  isEmpty(): boolean {
    return this.entries.length === 0;
  }

  popup(event: MenuTriggerEvent, options?: MenuPopupOptions): boolean {
    return Menu.popup(event, this, options);
  }

  private static createId(prefix: string): string {
    if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
      return `${prefix}_${crypto.randomUUID()}`;
    }
    return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  }

  private static hasNativeContextMenuBridge(): boolean {
    return Boolean((window as any).webkit?.messageHandlers?.jsb);
  }

  private static ensureBridgeListeners(): void {
    if (this.bridgeListenersInstalled || !this.hasNativeContextMenuBridge()) {
      return;
    }

    this.bridgeListenersInstalled = true;

    window.jsb.ContextMenuBridge.onMenuAction(
      ({ menuId, itemId }: WebViewContextMenuActionEvent) => {
        const closeTimer = Menu.menuCloseTimers.get(menuId);
        if (closeTimer) {
          clearTimeout(closeTimer);
          Menu.menuCloseTimers.delete(menuId);
        }

        const handler = Menu.menuRegistry.get(menuId)?.get(itemId);
        try {
          const result = handler?.();
          if (result instanceof Promise) {
            void result.catch(error => {
              console.error('Failed to run context menu action', error);
            });
          }
        } catch (error) {
          console.error('Failed to run context menu action', error);
        }

        Menu.menuRegistry.delete(menuId);
      }
    );

    window.jsb.ContextMenuBridge.onMenuClosed(
      ({ menuId }: WebViewContextMenuClosedEvent) => {
        const existingTimer = Menu.menuCloseTimers.get(menuId);
        if (existingTimer) {
          clearTimeout(existingTimer);
        }

        const closeTimer = setTimeout(() => {
          Menu.menuRegistry.delete(menuId);
          Menu.menuCloseTimers.delete(menuId);
        }, 0);

        Menu.menuCloseTimers.set(menuId, closeTimer);
      }
    );
  }

  private static showNativeContextMenu(
    request: WebViewContextMenuRequest
  ): void {
    this.ensureBridgeListeners();
    void window.jsb.ContextMenuBridge.popupMenu(request).catch(
      (error: unknown) => {
        this.menuRegistry.delete(request.menuId);
        console.error('Failed to show native context menu', error);
      }
    );
  }

  private static createContext(event: MenuTriggerEvent): MenuContext {
    const target = event.target;

    return {
      event,
      target,
      hasSelection: this.hasActiveSelection(target),
      isEditable: this.isEditableTarget(target),
    };
  }

  private static resolvePopupRequest(
    menu: Menu | undefined,
    context: MenuContext,
    options?: MenuPopupOptions
  ): ResolvedPopupRequest {
    const menuId = this.createId('ctx_menu');
    const defaultMenu = this.resolveDefaultMenu(context, options);
    const mergedMenu = this.mergeMenus(menu, defaultMenu, options);
    const builtMenu = this.buildMenu(menuId, mergedMenu);

    return {
      menuId,
      items: builtMenu.items,
      handlers: builtMenu.handlers,
    };
  }

  private static resolveDefaultMenu(
    context: MenuContext,
    options?: MenuPopupOptions
  ): Menu | undefined {
    if (options?.includeDefaults === false) {
      return undefined;
    }

    return this.defaultMenuFactory?.(context)?.clone();
  }

  private static mergeMenus(
    menu: Menu | undefined,
    defaultMenu: Menu | undefined,
    options?: MenuPopupOptions
  ): Menu | undefined {
    const menuEntries = menu ? Menu.cloneEntries(menu.entries) : [];
    const defaultEntries = defaultMenu
      ? Menu.cloneEntries(defaultMenu.entries)
      : [];
    if (menuEntries.length === 0 && defaultEntries.length === 0) {
      return undefined;
    }

    const combinedEntries: MenuEntry[] = [];
    const defaultPlacement = options?.defaultPlacement ?? 'append';
    const separateDefaults = options?.separateDefaults !== false;
    const shouldInsertSeparator =
      separateDefaults && menuEntries.length > 0 && defaultEntries.length > 0;

    if (defaultPlacement === 'prepend') {
      combinedEntries.push(...defaultEntries);
      if (shouldInsertSeparator) {
        combinedEntries.push(this.createSeparatorEntry());
      }
      combinedEntries.push(...menuEntries);
      return Menu.create(combinedEntries);
    }

    combinedEntries.push(...menuEntries);
    if (shouldInsertSeparator) {
      combinedEntries.push(this.createSeparatorEntry());
    }
    combinedEntries.push(...defaultEntries);
    return Menu.create(combinedEntries);
  }

  private static buildMenu(menuId: string, menu?: Menu): BuiltMenu {
    const handlers = new Map<string, MenuAction>();
    const items = menu
      ? this.buildMenuItems(menu.entries, menuId, handlers)
      : [];

    return {
      handlers,
      items,
    };
  }

  private static buildMenuItems(
    entries: readonly MenuEntry[],
    menuId: string,
    handlers: Map<string, MenuAction>
  ): WebViewContextMenuItem[] {
    const items: WebViewContextMenuItem[] = [];

    for (const entry of entries) {
      if (entry.kind === 'separator') {
        items.push({
          kind: 'separator',
          id: undefined,
          title: undefined,
          icon: undefined,
          enabled: undefined,
          items: undefined,
        });
        continue;
      }

      if (entry.kind === 'submenu') {
        const childItems = this.buildMenuItems(entry.items, menuId, handlers);
        if (childItems.length === 0) {
          continue;
        }

        items.push({
          kind: 'submenu',
          id: undefined,
          title: entry.title,
          icon: entry.icon,
          enabled: entry.enabled ?? true,
          items: childItems,
        });
        continue;
      }

      const itemId = this.createId('ctx_item');
      handlers.set(itemId, entry.onClick);
      items.push({
        kind: 'item',
        id: itemId,
        title: entry.title,
        icon: entry.icon,
        enabled: entry.enabled ?? true,
        items: undefined,
      });
    }

    return items;
  }

  private static createItemEntry(options: MenuItemOptions): MenuItemEntry {
    return {
      kind: 'item',
      ...options,
    };
  }

  private static createSubmenuEntry(
    options: MenuSubmenuOptions
  ): MenuSubmenuEntry {
    return {
      kind: 'submenu',
      title: options.title,
      icon: options.icon,
      enabled: options.enabled,
      items:
        options.items instanceof Menu
          ? Menu.cloneEntries(options.items.entries)
          : Menu.normalizeEntries(options.items),
    };
  }

  private static createSeparatorEntry(): MenuSeparatorEntry {
    return { kind: 'separator' };
  }

  private static normalizeEntries(
    entries: readonly MenuEntryInput[]
  ): MenuEntry[] {
    const normalizedEntries: MenuEntry[] = [];

    for (const entry of entries) {
      if (!entry) {
        continue;
      }

      if (entry.kind === 'submenu') {
        normalizedEntries.push({
          kind: 'submenu',
          title: entry.title,
          icon: entry.icon,
          enabled: entry.enabled,
          items: Menu.cloneEntries(entry.items),
        });
        continue;
      }

      normalizedEntries.push(entry);
    }

    return normalizedEntries;
  }

  private static cloneEntries(entries: readonly MenuEntry[]): MenuEntry[] {
    return entries.map(entry => {
      if (entry.kind !== 'submenu') {
        return { ...entry };
      }

      return {
        kind: 'submenu',
        title: entry.title,
        icon: entry.icon,
        enabled: entry.enabled,
        items: this.cloneEntries(entry.items),
      };
    });
  }

  private static getEditableElement(
    target: EventTarget | null
  ): HTMLElement | null {
    if (!(target instanceof Element)) {
      return null;
    }

    const editable = target.closest(
      'input, textarea, [contenteditable=""], [contenteditable="true"], [contenteditable="plaintext-only"]'
    );

    return editable instanceof HTMLElement ? editable : null;
  }

  private static isTextInputElement(
    element: HTMLElement | null
  ): element is HTMLInputElement | HTMLTextAreaElement {
    if (!element) {
      return false;
    }

    if (element instanceof HTMLTextAreaElement) {
      return true;
    }

    if (!(element instanceof HTMLInputElement)) {
      return false;
    }

    return !['button', 'checkbox', 'color', 'file', 'hidden', 'radio'].includes(
      element.type
    );
  }

  private static isEditableTarget(target: EventTarget | null): boolean {
    const editable = this.getEditableElement(target);

    if (!editable) {
      return false;
    }

    if (
      editable instanceof HTMLInputElement ||
      editable instanceof HTMLTextAreaElement
    ) {
      return !editable.readOnly && !editable.disabled;
    }

    return editable.isContentEditable;
  }

  private static hasActiveSelection(target: EventTarget | null): boolean {
    const editable = this.getEditableElement(target);

    if (this.isTextInputElement(editable)) {
      const start = editable.selectionStart ?? 0;
      const end = editable.selectionEnd ?? 0;
      return end > start;
    }

    const selection = window.getSelection();
    return Boolean(
      selection &&
      !selection.isCollapsed &&
      selection.toString().trim().length > 0
    );
  }
}

export type WebViewContextMenu = Menu;
export type WebViewContextMenuEntry = MenuEntry;
export type WebViewContextMenuPopupOptions = MenuPopupOptions;
