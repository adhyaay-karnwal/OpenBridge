import { bridgeReady } from '../../utils/jsbridge-client';
import { Menu } from '../../utils/webview-context-menu';
import './style.css';
import { createRoot } from 'react-dom/client';
import { useEffect, useState } from 'react';
import { CueStreamdown } from '../chat/components/markdown/streamdown';

type PreviewKind =
  | 'markdown'
  | 'markdown_error'
  | 'text'
  | 'image'
  | 'video'
  | 'audio'
  | 'pdf'
  | 'unsupported';

type PreviewPayload = {
  title: string;
  fileName: string;
  kind: PreviewKind;
  content?: string | null;
  resourceURL?: string | null;
  mimeType?: string | null;
  message?: string | null;
};

declare global {
  interface Window {
    updateFilePreview?: (payload: PreviewPayload) => void;
    webkit?: {
      messageHandlers?: {
        previewReady?: {
          postMessage: (message: string) => void;
        };
      };
    };
  }
}

const container = document.getElementById('root');
if (!container) {
  throw new Error('Root element not found');
}

Menu.install();

const fallbackMessage = 'Select a file from chat to preview it here.';

const EmptyState = ({ message }: { message: string }) => (
  <div className="preview-empty">
    <div className="preview-empty__note" role="status">
      <div className="preview-empty__eyebrow">Preview</div>
      <p>{message}</p>
    </div>
  </div>
);

const MarkdownErrorState = ({ payload }: { payload: PreviewPayload }) => (
  <div className="preview-markdown-error">
    <div className="preview-markdown-error__content">
      <p className="preview-markdown-error__eyebrow">Markdown preview</p>
      <h1>{payload.fileName}</h1>
      <p className="preview-markdown-error__message">
        {payload.message ?? "This Markdown file couldn't be rendered."}
      </p>
      <p className="preview-markdown-error__hint">
        Try reopening the file, or check whether the file is still available and
        encoded as readable text.
      </p>
    </div>
  </div>
);

const PreviewDocument = ({ payload }: { payload: PreviewPayload }) => {
  switch (payload.kind) {
    case 'markdown':
      return (
        <article className="preview-markdown">
          <CueStreamdown className="preview-markdown__content text-[15px] leading-7">
            {payload.content ?? ''}
          </CueStreamdown>
        </article>
      );
    case 'markdown_error':
      return <MarkdownErrorState payload={payload} />;
    case 'text':
      return (
        <div className="preview-text">
          <pre className="preview-text__content">{payload.content ?? ''}</pre>
        </div>
      );
    case 'image':
      return (
        <div className="preview-media preview-media--image">
          <img alt={payload.fileName} src={payload.resourceURL ?? ''} />
        </div>
      );
    case 'video':
      return (
        <div className="preview-media">
          <video
            controls
            playsInline
            preload="metadata"
            src={payload.resourceURL ?? ''}
          />
        </div>
      );
    case 'audio':
      return (
        <div className="preview-audio">
          <audio controls preload="metadata" src={payload.resourceURL ?? ''} />
        </div>
      );
    case 'pdf':
      return (
        <iframe
          className="preview-frame"
          src={payload.resourceURL ?? ''}
          title={payload.title}
        />
      );
    case 'unsupported':
      return (
        <EmptyState
          message={`Preview is not available for ${payload.fileName}${payload.mimeType ? ` (${payload.mimeType})` : ''}.`}
        />
      );
    default:
      return <EmptyState message={fallbackMessage} />;
  }
};

const App = () => {
  const [payload, setPayload] = useState<PreviewPayload | null>(null);

  useEffect(() => {
    window.updateFilePreview = nextPayload => {
      setPayload(nextPayload);
    };

    bridgeReady();
    window.webkit?.messageHandlers?.previewReady?.postMessage('complete');

    return () => {
      delete window.updateFilePreview;
    };
  }, []);

  if (!payload) {
    return <EmptyState message={fallbackMessage} />;
  }

  return (
    <main className={`preview-shell preview-shell--${payload.kind}`}>
      <section className="preview-body">
        <PreviewDocument payload={payload} />
      </section>
    </main>
  );
};

const root = createRoot(container);
root.render(<App />);
