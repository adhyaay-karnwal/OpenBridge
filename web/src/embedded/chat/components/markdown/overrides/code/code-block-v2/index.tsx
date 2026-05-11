import {
  type HTMLAttributes,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';
import { StreamdownContext } from 'streamdown';
import type { BundledLanguage } from 'shiki';
import { code as codePlugin } from '@streamdown/code';
import { CodeBlockBody } from './body';
import { CodeBlockContainer } from './container';
import { CodeBlockContext } from './context';
import { CodeBlockHeader } from './header';
import type { HighlightResult } from './types';

const TRAILING_NEWLINES_REGEX = /\n+$/;

type CodeBlockProps = HTMLAttributes<HTMLPreElement> & {
  code: string;
  language: string;
};

export const CodeBlock = ({
  code,
  language,
  className,
  children,
  ...rest
}: CodeBlockProps) => {
  const { shikiTheme } = useContext(StreamdownContext);
  const [expandable, setExpandable] = useState(false);
  const [expanded, setExpanded] = useState(false);

  // Remove trailing newlines to prevent empty line at end of code blocks
  const trimmedCode = useMemo(
    () => code.replace(TRAILING_NEWLINES_REGEX, ''),
    [code]
  );

  // Memoize the raw fallback tokens to avoid recomputing on every render
  const raw: HighlightResult = useMemo(
    () => ({
      bg: 'transparent',
      fg: 'inherit',
      tokens: trimmedCode.split('\n').map(line => [
        {
          content: line,
          color: 'inherit',
          bgColor: 'transparent',
          htmlStyle: {},
          offset: 0,
        },
      ]),
    }),
    [trimmedCode]
  );

  // Use raw as initial state
  const [result, setResult] = useState<HighlightResult>(raw);

  // Try to get cached result or subscribe to highlighting using @streamdown/code plugin
  useEffect(() => {
    const cachedResult = codePlugin.highlight(
      {
        code: trimmedCode,
        language: language as BundledLanguage,
        themes: shikiTheme,
      },
      highlightedResult => {
        setResult(highlightedResult);
      }
    );

    if (cachedResult) {
      setResult(cachedResult);
    }
  }, [trimmedCode, language, shikiTheme]);

  return (
    <CodeBlockContext.Provider
      value={{
        code: trimmedCode,
        expandable,
        expanded,
        setExpandable,
        setExpanded,
      }}
    >
      <CodeBlockContainer language={language}>
        <CodeBlockHeader
          className="border-b border-glass-card-border"
          language={language}
        >
          {children}
        </CodeBlockHeader>
        <CodeBlockBody
          className={className}
          language={language}
          result={result}
          {...rest}
        />
      </CodeBlockContainer>
    </CodeBlockContext.Provider>
  );
};

// Re-export components for external use
export { CodeBlockCopyButton } from './copy-button';
export { CodeBlockDownloadButton } from './download-button';
export { CodeBlockCollapseButton } from './collapse-button';
export { CodeBlockSkeleton } from './skeleton';
export { useCodeBlockContext } from './context';
