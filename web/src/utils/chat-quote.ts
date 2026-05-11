import type { SessionHistoryMessageContent } from '@/embedded/chat/types/history';

export type QuoteReference = NonNullable<
  SessionHistoryMessageContent['quoteRef']
>;

export type QuoteContent = SessionHistoryMessageContent & {
  type: 'quote';
  text: string;
  quoteRef: QuoteReference;
};

const quoteTagPattern =
  /^\s*<quote\s+source-message-id="([^"]+)"\s+start="(\d+)"\s+end="(\d+)">([\s\S]*)<\/quote>\s*$/;

function escapeQuoteText(text: string) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\n', '&#10;');
}

function unescapeQuoteText(text: string) {
  return text
    .replaceAll('&#10;', '\n')
    .replaceAll('&quot;', '"')
    .replaceAll('&gt;', '>')
    .replaceAll('&lt;', '<')
    .replaceAll('&amp;', '&');
}

export function normalizeQuoteReference(raw: unknown): QuoteReference | null {
  if (typeof raw !== 'object' || raw === null) {
    return null;
  }

  const record = raw as Record<string, unknown>;

  const sourceMessageId =
    typeof record.sourceMessageId === 'string'
      ? record.sourceMessageId
      : typeof record.source_message_id === 'string'
        ? record.source_message_id
        : null;
  const normalizeOffset = (value: unknown) => {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number.parseInt(value, 10);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  };
  const startOffset = normalizeOffset(
    record.startOffset ?? record.start_offset
  );
  const endOffset = normalizeOffset(record.endOffset ?? record.end_offset);

  if (!sourceMessageId || startOffset == null || endOffset == null) {
    return null;
  }

  return {
    sourceMessageId,
    startOffset,
    endOffset,
  };
}

export function isQuoteContent(
  content: SessionHistoryMessageContent
): content is QuoteContent {
  return content.type === 'quote' && !!content.text && !!content.quoteRef;
}

export function buildQuoteContent(
  text: string,
  quoteRef: QuoteReference
): QuoteContent {
  return {
    type: 'quote',
    text,
    quoteRef,
  };
}

export function serializeQuoteTag(text: string, quoteRef: QuoteReference) {
  return `<quote source-message-id="${quoteRef.sourceMessageId}" start="${quoteRef.startOffset}" end="${quoteRef.endOffset}">${escapeQuoteText(text)}</quote>`;
}

export function parseQuoteTagLine(line: string): QuoteContent | null {
  const match = line.match(quoteTagPattern);
  if (!match) {
    return null;
  }

  const startOffset = Number.parseInt(match[2], 10);
  const endOffset = Number.parseInt(match[3], 10);
  if (!Number.isFinite(startOffset) || !Number.isFinite(endOffset)) {
    return null;
  }

  return buildQuoteContent(unescapeQuoteText(match[4]), {
    sourceMessageId: match[1],
    startOffset,
    endOffset,
  });
}

export function expandQuoteAwareText(
  text: string
): SessionHistoryMessageContent[] {
  const lines = text.split('\n');
  const blocks: SessionHistoryMessageContent[] = [];
  let bufferedLines: string[] = [];

  const flushBufferedText = () => {
    if (bufferedLines.length === 0) {
      return;
    }
    blocks.push({
      type: 'text',
      text: bufferedLines.join('\n'),
    });
    bufferedLines = [];
  };

  for (const line of lines) {
    const quote = parseQuoteTagLine(line);
    if (quote) {
      flushBufferedText();
      blocks.push(quote);
      continue;
    }
    bufferedLines.push(line);
  }

  flushBufferedText();
  return blocks;
}
