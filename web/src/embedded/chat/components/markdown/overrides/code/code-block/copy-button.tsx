import {
  type ComponentProps,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react';
import { useCodeBlockContext } from './context';
import { StreamdownContext } from 'streamdown';
import { cn } from '@/utils/cn';
import { CheckmarkSFSymbolRegular } from '@/assets/sf-symbols/regular/checkmark';
import { DocumentOnDocumentSFSymbolRegular } from '@/assets/sf-symbols/regular/document.on.document';

export type CodeBlockCopyButtonProps = ComponentProps<'button'> & {
  onCopy?: () => void;
  onError?: (error: Error) => void;
  timeout?: number;
};

export const CodeBlockCopyButton = ({
  onCopy,
  onError,
  timeout = 2000,
  children,
  className,
  code: propCode,
  ...props
}: CodeBlockCopyButtonProps & { code?: string }) => {
  const [isCopied, setIsCopied] = useState(false);
  const timeoutRef = useRef(0);
  const { code: contextCode } = useCodeBlockContext();
  const { isAnimating } = useContext(StreamdownContext);
  const code = propCode ?? contextCode;

  const copyToClipboard = async () => {
    if (typeof window === 'undefined' || !navigator?.clipboard?.writeText) {
      onError?.(new Error('Clipboard API not available'));
      return;
    }

    try {
      if (!isCopied) {
        await navigator.clipboard.writeText(code);
        setIsCopied(true);
        onCopy?.();
        timeoutRef.current = window.setTimeout(
          () => setIsCopied(false),
          timeout
        );
      }
    } catch (error) {
      onError?.(error as Error);
    }
  };

  useEffect(
    () => () => {
      window.clearTimeout(timeoutRef.current);
    },
    []
  );

  const Icon = isCopied
    ? CheckmarkSFSymbolRegular
    : DocumentOnDocumentSFSymbolRegular;

  return (
    <button
      className={cn('icon-button size-5.5 flex-center opacity-85', className)}
      data-streamdown="code-block-copy-button"
      disabled={isAnimating}
      onClick={copyToClipboard}
      title="Copy Code"
      type="button"
      {...props}
    >
      {children ?? (
        <Icon className={cn(isCopied ? 'text-[10px]' : 'text-[16px]')} />
      )}
    </button>
  );
};
