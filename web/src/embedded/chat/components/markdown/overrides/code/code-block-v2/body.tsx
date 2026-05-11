import { cn } from '@/utils/cn';
import { useCodeContentHeight } from '@/utils/use-code-content-height';
import {
  type ComponentProps,
  memo,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
} from 'react';
import { StreamdownContext } from 'streamdown';
import { useCodeBlockContext } from './context';
import type { HighlightResult } from './types';

type CodeBlockBodyProps = ComponentProps<'pre'> & {
  result: HighlightResult;
  language: string;
  showLineNumbers?: boolean;
};

// Memoize line numbers class string since it's constant
const LINE_NUMBER_CLASSES = cn(
  'block',
  'before:content-[counter(line)]',
  'before:inline-block',
  'before:[counter-increment:line]',
  'before:w-6',
  'before:mr-4',
  'before:text-[13px]',
  'before:text-right',
  'before:text-muted-foreground/50',
  'before:font-mono',
  'before:select-none'
);

const MASK_SIZE = 40;
const MAX_HEIGHT = 200;

export const CodeBlockBody = memo(
  ({
    children: _children,
    result,
    language,
    className,
    showLineNumbers = false,
    ...rest
  }: CodeBlockBodyProps) => {
    const containerRef = useRef<HTMLDivElement>(null);
    const contentRef = useRef<HTMLPreElement>(null);

    const { code, expandable, expanded, setExpandable, setExpanded } =
      useCodeBlockContext();
    const { isAnimating } = useContext(StreamdownContext);

    // auto scroll to bottom when streaming
    useEffect(() => {
      if (!isAnimating) return;
      const interval = setInterval(() => {
        const container = containerRef.current;
        if (!container) return;

        container.scrollTo({
          top: container.scrollHeight,
          behavior: 'smooth',
        });
      }, 100);
      return () => clearInterval(interval);
    }, [isAnimating]);

    const onHeight = useCallback(
      (height: number) => setExpandable(height > MAX_HEIGHT),
      [setExpandable]
    );
    useCodeContentHeight(code, contentRef, onHeight);

    // Memoize the pre style object
    const preStyle = useMemo(
      () => ({
        backgroundColor: result.bg,
        color: result.fg,
      }),
      [result.bg, result.fg]
    );

    const maskStyle = useMemo(
      () => ({
        mask:
          expandable && !expanded
            ? `linear-gradient(to bottom, transparent, black 0px, black calc(100% - ${MASK_SIZE}px), transparent)`
            : undefined,
        maxHeight: expanded ? undefined : MAX_HEIGHT,
        overflowY: 'hidden' as const,
      }),
      [expandable, expanded]
    );

    return (
      <div style={maskStyle} className="relative" ref={containerRef}>
        <pre
          className={cn(className, 'p-4 text-sm dark:bg-(--shiki-dark-bg)!')}
          data-language={language}
          data-streamdown="code-block-body"
          style={preStyle}
          ref={contentRef}
          {...rest}
        >
          <code
            className={cn(
              showLineNumbers
                ? '[counter-increment:line_0] [counter-reset:line]'
                : null
            )}
          >
            {result.tokens.map((row, index) => (
              <span
                className={cn(showLineNumbers ? LINE_NUMBER_CLASSES : 'block')}
                // biome-ignore lint/suspicious/noArrayIndexKey: "This is a stable key."
                key={index}
              >
                {row.map((token, tokenIndex) => (
                  <span
                    className="dark:bg-(--shiki-dark-bg)! dark:text-(--shiki-dark)!"
                    // biome-ignore lint/suspicious/noArrayIndexKey: "This is a stable key."
                    key={tokenIndex}
                    style={{
                      color: token.color,
                      backgroundColor: token.bgColor,
                      ...token.htmlStyle,
                    }}
                    {...token.htmlAttrs}
                  >
                    {token.content}
                  </span>
                ))}
              </span>
            ))}
          </code>
        </pre>
        {expandable && !expanded ? (
          <div
            className="w-full absolute left-0 bottom-0 cursor-default"
            style={{ height: MASK_SIZE }}
            onClick={() => setExpanded(true)}
          />
        ) : null}
      </div>
    );
  },
  (prevProps, nextProps) => {
    // Custom comparison: only re-render if result tokens actually changed
    return (
      prevProps.result === nextProps.result &&
      prevProps.language === nextProps.language &&
      prevProps.className === nextProps.className
    );
  }
);
