import { useCallback, useState } from 'react';
import { Menu } from '@/utils/webview-context-menu';
import {
  preparePreviewAsset,
  previewAttachmentSource,
} from '../../messages/file-reference-actions';

/**
 * Custom video component with error handling.
 */
export const CueStreamdownVideo = ({
  src,
  sourcePath,
  environmentId,
  fileName,
  mimeType,
  className,
  ...props
}: React.ComponentProps<'video'> & {
  sourcePath?: string;
  environmentId?: string;
  fileName?: string;
  mimeType?: string;
}) => {
  const [error, setError] = useState<string | null>(null);

  const handleLoadedData = useCallback(() => {
    if (typeof src === 'string') {
      preparePreviewAsset(src, fileName, mimeType);
    }
  }, [fileName, mimeType, src]);

  const handleContextMenu = useCallback(
    (event: React.MouseEvent<HTMLVideoElement>) => {
      const previewSource = typeof src === 'string' ? src : undefined;
      if (!previewSource && !sourcePath) {
        return;
      }

      const menu = Menu.create().pushItem({
        title: 'Preview',
        icon: Menu.icon.symbol('document.viewfinder'),
        onClick: () => {
          void previewAttachmentSource(previewSource, {
            fileName,
            mimeType,
            fallbackPath: sourcePath,
            environmentId,
          });
        },
      });

      menu.popup(event);
    },
    [environmentId, fileName, mimeType, sourcePath, src]
  );

  // Error state
  if (error) {
    return (
      <div className="inline-flex flex-col items-start bg-red-50 dark:bg-red-900/20 rounded p-4 border border-red-200 dark:border-red-800 max-w-full overflow-hidden">
        <span className="text-sm text-red-600 dark:text-red-400">{error}</span>
        <code className="text-xs text-red-500 dark:text-red-400 mt-1 break-all">
          {src}
        </code>
      </div>
    );
  }

  return (
    <video
      src={src}
      className={`w-full max-w-2xl rounded ${className || ''}`}
      controls
      onLoadedData={handleLoadedData}
      onContextMenu={handleContextMenu}
      onError={() => setError('Failed to load video')}
      {...props}
    />
  );
};
