import { hasNativeJSBridge } from '@/utils/bridge-runtime';

export type PreviewSourceRect = {
  x: number;
  y: number;
  width: number;
  height: number;
};

const hostFileExistenceCache = new Map<string, boolean>();
const previewPreparationCache = new Map<string, Promise<void>>();

async function hostFileExists(path: string): Promise<boolean> {
  const trimmedPath = path.trim();
  if (!trimmedPath) {
    return false;
  }

  const cached = hostFileExistenceCache.get(trimmedPath);
  if (cached !== undefined) {
    return cached;
  }

  try {
    const result = await window.jsb?.MessagesBridge?.checkFilesExist([
      trimmedPath,
    ]);
    const exists = Boolean(result?.[trimmedPath]);
    hostFileExistenceCache.set(trimmedPath, exists);
    return exists;
  } catch (error) {
    console.error('Failed to check file existence:', error);
    return false;
  }
}

export async function previewFileReference(
  path: string,
  environmentId?: string,
  sourceRect?: PreviewSourceRect | null
): Promise<void> {
  const trimmedPath = path.trim();
  if (!trimmedPath) {
    return;
  }

  try {
    const existsOnHost = await hostFileExists(trimmedPath);
    if (!existsOnHost && environmentId) {
      await window.jsb?.MessagesBridge?.previewWorkspaceFile(
        trimmedPath,
        environmentId,
        sourceRect ?? null
      );
      return;
    }

    await window.jsb?.MessagesBridge?.previewHostFile(
      trimmedPath,
      sourceRect ?? null
    );
  } catch (error) {
    console.error('Failed to preview file:', error);
  }
}

function previewAssetKey(
  source: string,
  fileName?: string,
  mimeType?: string
): string {
  return JSON.stringify([source, fileName ?? '', mimeType ?? '']);
}

export function preparePreviewAsset(
  source: string | null | undefined,
  fileName?: string,
  mimeType?: string
): void {
  if (!hasNativeJSBridge()) {
    return;
  }

  const trimmedSource = source?.trim();
  if (!trimmedSource) {
    return;
  }

  const cacheKey = previewAssetKey(trimmedSource, fileName, mimeType);
  if (previewPreparationCache.has(cacheKey)) {
    return;
  }

  const task = window.jsb?.MessagesBridge?.prepareAttachmentPreview(
    trimmedSource,
    fileName ?? null,
    mimeType ?? null
  );
  if (!task) {
    return;
  }

  previewPreparationCache.set(
    cacheKey,
    task.catch(error => {
      console.error('Failed to prepare preview asset:', error);
      previewPreparationCache.delete(cacheKey);
    })
  );
}

export async function previewAttachmentSource(
  source: string | null | undefined,
  options: {
    fileName?: string;
    mimeType?: string;
    fallbackPath?: string;
    environmentId?: string;
    sourceRect?: PreviewSourceRect | null;
  }
): Promise<void> {
  const trimmedSource = source?.trim();

  if (trimmedSource) {
    try {
      const previewAttachment = window.jsb?.MessagesBridge?.previewAttachment;
      if (previewAttachment) {
        await previewAttachment(
          trimmedSource,
          options.fileName ?? null,
          options.mimeType ?? null,
          options.sourceRect ?? null
        );
        return;
      }

      window.open(trimmedSource, '_blank', 'noopener,noreferrer');
      return;
    } catch (error) {
      console.error('Failed to preview attachment source:', error);
    }
  }

  if (options.fallbackPath) {
    await previewFileReference(
      options.fallbackPath,
      options.environmentId,
      options.sourceRect
    );
  }
}

export function previewSourceRectForElement(
  element: Element | null | undefined
): PreviewSourceRect | null {
  if (!element) {
    return null;
  }

  const rect = element.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) {
    return null;
  }

  const viewportWidth =
    window.innerWidth || document.documentElement.clientWidth || 0;
  const viewportHeight =
    window.innerHeight || document.documentElement.clientHeight || 0;
  const visibleLeft = Math.max(rect.left, 0);
  const visibleTop = Math.max(rect.top, 0);
  const visibleRight = Math.min(rect.right, viewportWidth);
  const visibleBottom = Math.min(rect.bottom, viewportHeight);
  const visibleWidth = visibleRight - visibleLeft;
  const visibleHeight = visibleBottom - visibleTop;

  if (visibleWidth <= 0 || visibleHeight <= 0) {
    return null;
  }

  return {
    x: visibleLeft,
    y: visibleTop,
    width: visibleWidth,
    height: visibleHeight,
  };
}
