import { useEffect, useState } from 'react';
import {
  requiresNativeURLResolution,
  resolveAttachmentDisplayURL,
  type AttachmentDisplayURLParams,
} from '@/utils/agent-file-url';
import { hasNativeJSBridge } from '@/utils/bridge-runtime';

/**
 * Resolves attachment URLs for display. Data URLs are returned as-is.
 * Browser runtimes consume service-provided URLs directly.
 */
export function useResolvedUrl(
  params: AttachmentDisplayURLParams
): string | null {
  const { environmentId, filePath, src } = params;
  const [resolved, setResolved] = useState<string | null>(null);

  useEffect(() => {
    const source = resolveAttachmentDisplayURL({
      environmentId,
      filePath,
      src,
    });

    if (!source) {
      setResolved(null);
      return;
    }

    if (source.startsWith('data:')) {
      setResolved(source);
      return;
    }

    if (!hasNativeJSBridge()) {
      setResolved(source);
      return;
    }

    if (!requiresNativeURLResolution(source)) {
      setResolved(source);
      return;
    }

    let cancelled = false;

    const resolve = async () => {
      try {
        const url =
          await window.jsb?.MessagesBridge?.getStorageDownloadUrl(source);
        if (!cancelled) {
          setResolved(url ?? null);
        }
      } catch {
        if (!cancelled) {
          setResolved(null);
        }
      }
    };

    setResolved(null);
    void resolve();

    return () => {
      cancelled = true;
    };
  }, [environmentId, filePath, src]);

  return resolved;
}
