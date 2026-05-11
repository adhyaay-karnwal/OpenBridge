import { Menu } from '@/utils/webview-context-menu';
import { useCallback, useState } from 'react';

/**
 * Custom image component with loading animation and error handling.
 */
export const CueStreamdownImg = ({
  src,
  alt,
  className,
  ...props
}: React.ComponentProps<'img'>) => {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleContextMenu = useCallback(
    (event: React.MouseEvent<HTMLImageElement>) => {
      const menu = Menu.create();
      if (src) {
        menu.pushItem({
          title: 'Save Image',
          icon: Menu.icon.symbol('square.and.arrow.down'),
          onClick: () => {
            window.jsb?.UtilsBridge?.saveImage(src, 'bridge-image');
          },
        });
      }

      menu.popup(event);
    },
    [src]
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
    <img
      src={src}
      alt={alt || 'Generated image'}
      onContextMenu={handleContextMenu}
      className={`
        ${className || ''}
        transition-opacity duration-500 ease-out
        ${imageLoaded ? 'opacity-100' : 'opacity-0'}
      `}
      onLoad={() => setImageLoaded(true)}
      onError={() => setError('Failed to load image')}
      {...props}
    />
  );
};
