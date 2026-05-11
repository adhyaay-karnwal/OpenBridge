import { isPanelPresentationMode } from '@/embedded/chat/presentation-mode';
import { cn } from '@/utils/cn';
import type { ReactNode } from 'react';

interface CodeBlockHeaderProps {
  language: string;
  children: ReactNode;
  className?: string;
}

export const CodeBlockHeader = ({
  language,
  children,
  className,
}: CodeBlockHeaderProps) => (
  <div
    className={cn(
      'flex items-center justify-between p-3 text-muted-foreground text-xs gap-2',
      isPanelPresentationMode ? 'bg-user-bubble-hover' : 'bg-user-bubble',
      className
    )}
    data-language={language}
    data-streamdown="code-block-header"
  >
    <span className="ml-1 font-mono lowercase">{language}</span>
    <div className="min-w-0 flex-1" />
    <div className="flex items-center gap-2">{children}</div>
  </div>
);
