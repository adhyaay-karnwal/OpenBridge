import { cn } from '@/utils/cn';
import type { ReactNode } from 'react';

type CodeBlockHeaderProps = {
  language: string;
  children: ReactNode;
  className?: string;
};

export const CodeBlockHeader = ({
  language,
  children,
  className,
}: CodeBlockHeaderProps) => {
  return (
    <div
      className={cn(
        'flex items-center justify-between bg-muted/80 p-3 text-muted-foreground text-xs gap-2',
        className
      )}
      data-language={language}
      data-streamdown="code-block-header"
    >
      <span className="ml-1 font-mono lowercase">{language}</span>
      <div className="min-w-0 flex-1"></div>
      <div className="flex items-center gap-2">{children}</div>
    </div>
  );
};
