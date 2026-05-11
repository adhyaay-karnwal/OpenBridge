import {
  isValidElement,
  memo,
  Suspense,
  useContext,
  type DetailedHTMLProps,
  type HTMLAttributes,
} from 'react';
import type { Element } from 'hast';
import { StreamdownContext } from 'streamdown';
import { cn } from '@/utils/cn';
import { MermaidDownloadDropdown } from './mermaid/download-button';
import { MermaidFullscreenButton } from './mermaid/fullscreen-button';
import { Mermaid } from './mermaid';

// Use v2 code-block components (upgraded for streamdown 2.x)
import {
  CodeBlock,
  CodeBlockCopyButton,
  CodeBlockDownloadButton,
  CodeBlockCollapseButton,
  CodeBlockSkeleton,
} from './code-block-v2';

type ExtraProps = {
  node?: Element | undefined;
};
type MarkdownPoint = { line?: number; column?: number };
type MarkdownPosition = { start?: MarkdownPoint; end?: MarkdownPoint };
type MarkdownNode = {
  position?: MarkdownPosition;
  properties?: { className?: string };
};

const LANGUAGE_REGEX = /language-([^\s]+)/;

function sameNodePosition(prev?: MarkdownNode, next?: MarkdownNode): boolean {
  if (!(prev?.position || next?.position)) {
    return true;
  }
  if (!(prev?.position && next?.position)) {
    return false;
  }

  const prevStart = prev.position.start;
  const nextStart = next.position.start;
  const prevEnd = prev.position.end;
  const nextEnd = next.position.end;

  return (
    prevStart?.line === nextStart?.line &&
    prevStart?.column === nextStart?.column &&
    prevEnd?.line === nextEnd?.line &&
    prevEnd?.column === nextEnd?.column
  );
}

const CodeComponent = ({
  node,
  className,
  children,
  ...props
}: DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> &
  // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: "Complex code block logic"
  ExtraProps) => {
  const inline = node?.position?.start.line === node?.position?.end.line;
  const { mermaid: mermaidContext } = useContext(StreamdownContext);

  if (inline) {
    return (
      <code
        className={cn(
          'rounded bg-user-bubble px-1.5 py-0.5 font-mono text-sm',
          className
        )}
        data-streamdown="inline-code"
        {...props}
      >
        {children}
      </code>
    );
  }

  const match = className?.match(LANGUAGE_REGEX);
  const language = match?.at(1) ?? '';

  // Extract code content from children safely
  let code = '';
  if (
    isValidElement(children) &&
    children.props &&
    typeof children.props === 'object' &&
    'children' in children.props &&
    typeof children.props.children === 'string'
  ) {
    code = children.props.children;
  } else if (typeof children === 'string') {
    code = children;
  }

  if (language === 'mermaid') {
    const showMermaidControls = true;
    const showDownload = true;
    const showCopy = true;
    const showFullscreen = false; // has issues with webview
    const showPanZoomControls = true;

    const shouldShowMermaidControls =
      showMermaidControls && (showDownload || showCopy || showFullscreen);

    return (
      <Suspense fallback={<CodeBlockSkeleton />}>
        <div
          className={cn(
            'glass-card-without-shadow',
            'group relative my-4 h-auto rounded-xl border pt-3',
            className
          )}
          data-streamdown="mermaid-block"
        >
          {shouldShowMermaidControls ? (
            <div className="flex items-center justify-end gap-2 border-b border-black/10 dark:border-white/10 pb-3 px-4">
              {showDownload ? (
                <MermaidDownloadDropdown
                  chart={code}
                  config={mermaidContext?.config}
                />
              ) : null}
              {showCopy ? <CodeBlockCopyButton code={code} /> : null}
              {showFullscreen ? (
                <MermaidFullscreenButton
                  chart={code}
                  config={mermaidContext?.config}
                />
              ) : null}
            </div>
          ) : null}
          <Mermaid
            chart={code}
            config={mermaidContext?.config}
            showControls={showPanZoomControls}
          />
        </div>
      </Suspense>
    );
  }

  const showCodeControls = true;

  return (
    <Suspense fallback={<CodeBlockSkeleton />}>
      <CodeBlock
        className={cn('overflow-x-auto', className)}
        code={code}
        language={language}
      >
        {showCodeControls ? (
          <>
            <CodeBlockDownloadButton code={code} language={language} />
            <CodeBlockCopyButton />
            <CodeBlockCollapseButton />
          </>
        ) : null}
      </CodeBlock>
    </Suspense>
  );
};

const MemoCode = memo<
  DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement> & ExtraProps
>(
  CodeComponent,
  (p, n) => p.className === n.className && sameNodePosition(p.node, n.node)
);
MemoCode.displayName = 'MarkdownCode';

export { MemoCode as CueStreamdownCode };
