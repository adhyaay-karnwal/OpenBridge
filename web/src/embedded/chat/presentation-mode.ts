export type EmbeddedChatPresentationMode = 'panel' | 'window';

const DEFAULT_CHAT_PRESENTATION_MODE: EmbeddedChatPresentationMode = 'window';
const VALID_CHAT_PRESENTATION_MODES = new Set<EmbeddedChatPresentationMode>([
  'panel',
  'window',
]);

export function getEmbeddedChatPresentationMode(): EmbeddedChatPresentationMode {
  if (typeof window === 'undefined') {
    return DEFAULT_CHAT_PRESENTATION_MODE;
  }

  const params = new URLSearchParams(window.location.search);
  const value = params.get('presentation');

  if (
    value &&
    VALID_CHAT_PRESENTATION_MODES.has(value as EmbeddedChatPresentationMode)
  ) {
    return value as EmbeddedChatPresentationMode;
  }

  return DEFAULT_CHAT_PRESENTATION_MODE;
}

export const PRESENTATION_MODE = getEmbeddedChatPresentationMode();
export const isPanelPresentationMode = PRESENTATION_MODE === 'panel';
export const isWindowPresentationMode = PRESENTATION_MODE === 'window';
