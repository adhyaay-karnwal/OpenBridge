import { cn } from '@/utils/cn';
import { useState } from 'react';

interface WebBrowsePayload {
  message?: string;
  operation_id?: string;
  status?: string;
  streaming_url?: string;
  tinyfish_run_id?: string;
}

export function tryParseWebBrowsePayload(
  jsonText: string
): WebBrowsePayload | null {
  try {
    const parsed = JSON.parse(jsonText);
    if (
      typeof parsed === 'object' &&
      parsed !== null &&
      typeof parsed.streaming_url === 'string'
    ) {
      return parsed as WebBrowsePayload;
    }
  } catch {
    // not valid JSON or missing streaming_url
  }
  return null;
}

export const WebBrowseWidget = ({ payload }: { payload: WebBrowsePayload }) => {
  const [isLoaded, setIsLoaded] = useState(false);

  if (!payload.streaming_url) {
    return null;
  }

  return (
    <div
      className={cn(
        'w-full overflow-hidden rounded-2xl',
        'border border-border bg-surface-card'
      )}
    >
      <div className="flex items-center gap-2 border-b border-border px-3 py-2">
        <div className="h-2 w-2 rounded-full bg-blue-400 animate-pulse" />
        <span className="text-xs font-medium text-text-primary">
          Web Browse
        </span>
        {payload.status ? (
          <span className="text-xs text-text-secondary">
            &middot; {payload.status}
          </span>
        ) : null}
      </div>

      <div className="relative w-full" style={{ height: 420 }}>
        {!isLoaded ? (
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-sm text-text-secondary">
              Loading browser view...
            </span>
          </div>
        ) : null}
        <iframe
          src={payload.streaming_url}
          title="Web Browse session"
          className={cn('h-full w-full border-0', !isLoaded && 'opacity-0')}
          sandbox="allow-scripts allow-same-origin"
          onLoad={() => setIsLoaded(true)}
        />
      </div>
    </div>
  );
};
