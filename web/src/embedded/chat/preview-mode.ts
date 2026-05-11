export type EmbeddedChatPreviewMode = 'permission-message';

const VALID_CHAT_PREVIEW_MODES = new Set<EmbeddedChatPreviewMode>([
  'permission-message',
]);

export function getEmbeddedChatPreviewMode(): EmbeddedChatPreviewMode | null {
  if (typeof window === 'undefined' || process.env.NODE_ENV !== 'development') {
    return null;
  }

  const params = new URLSearchParams(window.location.search);
  const value = params.get('preview');

  if (value && VALID_CHAT_PREVIEW_MODES.has(value as EmbeddedChatPreviewMode)) {
    return value as EmbeddedChatPreviewMode;
  }

  return null;
}
