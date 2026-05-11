import {
  type HTMLAttributes,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';
import type { TokensResult } from 'shiki';
import type { BundledTheme } from 'shiki';
import { StreamdownContext } from 'streamdown';
import { CodeBlockBody } from './body';
import { CodeBlockContainer } from './container';
import { CodeBlockContext } from './context';
import { CodeBlockHeader } from './header';
import { getHighlightedTokens } from './highlight';

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
  // TODO： current version of streamdown doesn't support cdnUrl,
  // waiting for the next version of streamdown to be released
  // const { shikiTheme, cdnUrl } = useContext(StreamdownContext);
  const { shikiTheme } = useContext(StreamdownContext);
  const bundledShikiTheme = shikiTheme as [BundledTheme, BundledTheme];
  const [expandable, setExpandable] = useState(false);
  const [expanded, setExpanded] = useState(false);

  // Memoize the raw fallback tokens to avoid recomputing on every render
  const raw: TokensResult = useMemo(
    () => ({
      bg: 'transparent',
      fg: 'inherit',
      tokens: code.split('\n').map(line => [
        {
          content: line,
          color: 'inherit',
          bgColor: 'transparent',
          htmlStyle: {},
          offset: 0,
        },
      ]),
    }),
    [code]
  );

  // Use raw as initial state
  const [result, setResult] = useState<TokensResult>(raw);

  // Try to get cached result or subscribe to highlighting
  useEffect(() => {
    const cachedResult = getHighlightedTokens({
      code,
      language,
      shikiTheme: bundledShikiTheme,
      // cdnUrl,
    });

    if (cachedResult) {
      // Already cached, use it immediately
      setResult(cachedResult);
      return;
    }

    // Not cached, subscribe to updates
    getHighlightedTokens({
      code,
      language,
      shikiTheme: bundledShikiTheme,
      // cdnUrl,
      callback: highlightedResult => {
        setResult(highlightedResult);
      },
    });
  }, [
    code,
    language,
    bundledShikiTheme,
    //cdnUrl
  ]);

  return (
    <CodeBlockContext.Provider
      value={{ code, expandable, expanded, setExpandable, setExpanded }}
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
