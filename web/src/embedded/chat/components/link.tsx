import type { AnchorHTMLAttributes } from 'react';
import { cn } from '@/utils/cn';

export const Link = ({
  href,
  onClick,
  className,
  ...props
}: AnchorHTMLAttributes<HTMLAnchorElement>) => {
  const handleClick = (e: React.MouseEvent<HTMLAnchorElement>) => {
    e.preventDefault();
    onClick?.(e);
    if (!href) {
      return;
    }
    try {
      if (window.jsb?.UtilsBridge?.openURL) {
        window.jsb.UtilsBridge.openURL(href);
        return;
      }
      window.open(href, '_blank', 'noopener,noreferrer');
    } catch (error) {
      console.error(error);
    }
  };

  return (
    <a
      onClick={handleClick}
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className={cn(
        'text-apple-blue hover:underline cursor-pointer',
        className
      )}
      {...props}
    />
  );
};
