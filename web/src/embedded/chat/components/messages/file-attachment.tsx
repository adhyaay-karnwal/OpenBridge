import { cn } from '@/utils/cn';
import { Menu } from '@/utils/webview-context-menu';
import { useCallback, useEffect, useState } from 'react';
import {
  preparePreviewAsset,
  previewAttachmentSource,
} from './file-reference-actions';
import { useResolvedUrl } from './use-resolved-url';

export interface FileAttachmentData {
  filename: string;
  contentType: string;
  path?: string;
  url?: string;
  environmentId?: string;
  size: string; // Human-readable size string (e.g., "1.5 MB"), empty for directories
}

/**
 * Request a file thumbnail from Swift native code via WebKit bridge
 * Uses QuickLook to generate a thumbnail for the file at the given path
 * Returns a base64 data URL of the file thumbnail
 */
async function requestFileThumbnail(path: string): Promise<string | null> {
  try {
    const result = await window.jsb?.MessagesBridge?.getFileIcon(path);
    return result ?? null;
  } catch {
    return null;
  }
}

function getFileExtension(filename: string): string {
  const index = filename.lastIndexOf('.');
  if (index < 0 || index === filename.length - 1) {
    return '';
  }
  return filename.slice(index + 1).toLowerCase();
}

function getFriendlyFileType(filename: string, contentType: string): string {
  const ext = getFileExtension(filename);

  switch (ext) {
    case 'md':
    case 'markdown':
    case 'mdown':
    case 'mkd':
      return 'Markdown document';
    case 'pdf':
      return 'PDF document';
    case 'txt':
    case 'log':
      return 'Text document';
    case 'json':
      return 'JSON file';
    case 'png':
      return 'PNG image';
    case 'jpg':
    case 'jpeg':
      return 'JPEG image';
    case 'gif':
      return 'GIF image';
    case 'webp':
      return 'WebP image';
    case 'mp4':
      return 'MP4 video';
    case 'mov':
      return 'QuickTime video';
    case 'mp3':
      return 'MP3 audio';
    case 'wav':
      return 'WAV audio';
  }

  switch (contentType) {
    case 'application/pdf':
      return 'PDF document';
    case 'text/plain':
      return 'Text document';
    case 'application/json':
      return 'JSON file';
    case 'image/png':
      return 'PNG image';
    case 'image/jpeg':
      return 'JPEG image';
    case 'image/gif':
      return 'GIF image';
    case 'image/webp':
      return 'WebP image';
    case 'video/mp4':
      return 'MP4 video';
    case 'audio/mpeg':
      return 'MP3 audio';
  }

  if (!contentType || contentType === 'application/octet-stream') {
    return ext ? `${ext.toUpperCase()} file` : 'File';
  }

  return contentType;
}

/**
 * Hook to fetch file thumbnail from Swift bridge using QuickLook
 */
function useFileThumbnail(path?: string): string | null {
  const [iconUrl, setIconUrl] = useState<string | null>(null);

  useEffect(() => {
    if (!path) {
      setIconUrl(null);
      return;
    }

    let cancelled = false;

    requestFileThumbnail(path).then(url => {
      if (!cancelled) {
        setIconUrl(url);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [path]);

  return iconUrl;
}

/**
 * File attachment card component
 */
export const FileAttachmentCard = ({
  filename,
  contentType,
  path,
  url,
  environmentId,
  size,
  className,
  ...props
}: {
  filename: string;
  contentType: string;
  path?: string;
  url?: string;
  environmentId?: string;
  size?: string;
  className?: string;
} & React.HTMLAttributes<HTMLDivElement>) => {
  const iconUrl = useFileThumbnail(path);
  const resolvedUrl = useResolvedUrl({
    src: url,
    filePath: path,
    environmentId,
  });
  const fileType = getFriendlyFileType(filename, contentType);

  useEffect(() => {
    if (!resolvedUrl) {
      return;
    }
    preparePreviewAsset(resolvedUrl, filename, contentType);
  }, [contentType, filename, resolvedUrl]);

  const handleContextMenu = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      const menu = Menu.create().pushItem({
        title: 'Preview',
        icon: iconUrl
          ? Menu.icon.dataUrl(iconUrl)
          : Menu.icon.symbol('document'),
        onClick: () => {
          void previewAttachmentSource(resolvedUrl, {
            fileName: filename,
            mimeType: contentType,
            fallbackPath: path,
            environmentId,
          });
        },
      });

      menu.popup(event);
    },
    [contentType, environmentId, filename, iconUrl, path, resolvedUrl]
  );

  return (
    <div
      onContextMenu={handleContextMenu}
      onClick={() =>
        void previewAttachmentSource(resolvedUrl, {
          fileName: filename,
          mimeType: contentType,
          fallbackPath: path,
          environmentId,
        })
      }
      className={cn(
        'p-3 min-w-[40%] max-w-full w-full text-left',
        'flex items-center gap-3',
        'rounded-lg border border-border',
        'bg-surface-card',
        'transition-colors hover:bg-fill-soft active:bg-fill-medium',
        'cursor-pointer',
        className
      )}
      {...props}
    >
      <div className="shrink-0 w-8 h-8 flex items-center justify-center">
        {iconUrl ? (
          <img src={iconUrl} alt="" className="w-8 h-8 object-contain" />
        ) : (
          <span className="text-2xl leading-none">📎</span>
        )}
      </div>
      <div className="flex-1 min-w-0 overflow-hidden">
        <div className="font-medium text-sm truncate">{filename}</div>
        <div className="text-xs text-text-secondary whitespace-nowrap">
          {fileType} {size && `• ${size}`}
        </div>
      </div>
    </div>
  );
};
