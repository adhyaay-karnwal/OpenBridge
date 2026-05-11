import '../../utils/jsbridge-client';
import './style.css';
import { createRoot } from 'react-dom/client';
import { createPortal } from 'react-dom';
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { throttle } from 'lodash';
import { Messages } from './components/messages';
import { useChatSwiftBridge } from './hooks/use-swift-bridge';
import { Greet } from './components/greet';
import { MaskedScrollArea } from '@/embedded/chat/components/masked-scrollarea';
import { DebugMessageProvider } from '@/utils/debug-message';
import { ThemeProvider } from '@/utils/theme-provider';
import { ActivityCenter } from './components/messages/activity-center';
import { QueuedMessageBanner } from './components/messages/queued-message-banner';
import { Menu } from '@/utils/webview-context-menu';
import { isUserMessage } from './types/history';
import { UserMessageMinimap, ArtifactMinimap } from './components/minimap';
import { globalVar } from './global-css-var';
import { focusQuoteInContainer } from '@/utils/chat-quote-dom';
import { QuoteSelectionBubble } from '@/utils/quote-selection-bubble';
import { hasNativeJSBridge } from '@/utils/bridge-runtime';
import { getEmbeddedChatPresentationMode } from './presentation-mode';
import { getEmbeddedChatPreviewMode } from './preview-mode';
import { PermissionMessagePreviewPage } from './components/messages/permission-message-preview';

const container = document.getElementById('root');
if (!container) {
  throw new Error('Root element not found');
}

Menu.install();

const FOCUS_MESSAGE_RETRY_LIMIT = 120;
const FOCUS_MESSAGE_FAST_RETRY_DELAY_MS = 80;
const FOCUS_MESSAGE_SLOW_RETRY_DELAY_MS = 160;

function installNativeClipboardBridge() {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') {
    return;
  }

  if (!hasNativeJSBridge()) {
    return;
  }

  const bridge = window.jsb?.MessagesBridge as
    | {
        copyText?: (text: string) => Promise<boolean>;
      }
    | undefined;

  if (typeof bridge?.copyText !== 'function') {
    return;
  }

  const nativeWriteText = async (text: string): Promise<void> => {
    await bridge.copyText!(text);
  };

  const readClipboardText = async (
    items: ClipboardItem[],
    index = 0
  ): Promise<string | null> => {
    if (index >= items.length) {
      return null;
    }

    const item = items[index];
    const types = new Set(item.types ?? []);

    if (types.has('text/plain')) {
      const blob = await item.getType('text/plain');
      return blob.text();
    }

    if (types.has('text/html')) {
      const blob = await item.getType('text/html');
      return blob.text();
    }

    return readClipboardText(items, index + 1);
  };

  const nativeWrite = async (items: ClipboardItem[]): Promise<void> => {
    const text = await readClipboardText(items);
    if (text !== null) {
      await nativeWriteText(text);
    }
  };

  const clipboard = navigator.clipboard as
    | (Clipboard & {
        writeText?: (text: string) => Promise<void>;
        write?: (items: ClipboardItem[]) => Promise<void>;
      })
    | undefined;

  if (clipboard) {
    try {
      clipboard.writeText = nativeWriteText;
      clipboard.write = nativeWrite;
      return;
    } catch {
      try {
        Object.defineProperties(clipboard, {
          writeText: {
            configurable: true,
            value: nativeWriteText,
          },
          write: {
            configurable: true,
            value: nativeWrite,
          },
        });
        return;
      } catch {}
    }
  }

  try {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: {
        writeText: nativeWriteText,
        write: nativeWrite,
      },
    });
  } catch {}
}

installNativeClipboardBridge();

const ChatPage = () => {
  const {
    isStreaming,
    hasOpenTask,
    messages,
    assistantStateSequence,
    workspaceState,
    paddingTop,
    followUpState,
    historyInitVersion,
    restoreScrollTop,
    queuedMessage,
    focusMessageRequest,
    focusQuoteRequest,
    sendOrQueueMessage,
    cancelQueuedMessage,
    clearRestoreScrollTop,
  } = useChatSwiftBridge();
  const hasConversationContent = messages.length > 0;
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const focusedMessageElementRef = useRef<HTMLElement | null>(null);
  const focusedMessageCleanupTimeoutRef = useRef<number | null>(null);
  const [autoScrollAllowed, setAutoScrollAllowed] = useState(true);
  const [pendingFocusMessageRequest, setPendingFocusMessageRequest] =
    useState<typeof focusMessageRequest>(null);
  const chatPresentationMode = useMemo(
    () => getEmbeddedChatPresentationMode(),
    []
  );

  const hasUserMessages = useMemo(
    () => messages.some(m => isUserMessage(m)),
    [messages]
  );

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.chatPresentationMode = chatPresentationMode;

    return () => {
      delete root.dataset.chatPresentationMode;
    };
  }, [chatPresentationMode]);

  useEffect(() => {
    if (!focusMessageRequest) {
      return;
    }
    setPendingFocusMessageRequest(focusMessageRequest);
  }, [focusMessageRequest]);

  useEffect(() => {
    if (!focusQuoteRequest) {
      return;
    }

    let timeoutId: number | null = null;
    let cancelled = false;
    const request = focusQuoteRequest;

    const attemptFocus = (attempt: number) => {
      if (cancelled) {
        return;
      }

      const didFocus = focusQuoteInContainer({
        container: scrollContainerRef.current,
        quoteRef: request.quoteRef,
        focusClassName: 'conversation-message-focused',
      });

      if (didFocus || attempt >= 20) {
        return;
      }

      timeoutId = window.setTimeout(
        () => attemptFocus(attempt + 1),
        attempt < 6 ? 80 : 140
      );
    };

    const frame = window.requestAnimationFrame(() => {
      attemptFocus(0);
    });

    return () => {
      cancelled = true;
      window.cancelAnimationFrame(frame);
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId);
      }
    };
  }, [focusQuoteRequest]);

  useEffect(() => {
    Menu.configure({
      defaults: () => {
        const menu = Menu.create();

        if (hasUserMessages) {
          menu.pushItem({
            title: 'View Messages',
            icon: Menu.icon.symbol('text.alignleft'),
            onClick: () => UserMessageMinimap.toggle(),
          });
        }

        if (ArtifactMinimap.hasEntries()) {
          menu.pushItem({
            title: 'View Artifacts',
            icon: Menu.icon.symbol('sparkles.rectangle.stack'),
            onClick: () => ArtifactMinimap.toggle(),
          });
        }

        return menu;
      },
    });
  }, [hasUserMessages]);

  useEffect(() => () => Menu.clearDefaults(), []);

  useLayoutEffect(() => {
    setAutoScrollAllowed(true);
  }, [historyInitVersion]);

  useLayoutEffect(() => {
    if (restoreScrollTop == null) {
      return;
    }

    const container = scrollContainerRef.current;
    if (!container) {
      return;
    }

    container.scrollTop = restoreScrollTop;
    const distanceFromBottom =
      container.scrollHeight - container.scrollTop - container.clientHeight;
    setAutoScrollAllowed(distanceFromBottom <= 1);
    clearRestoreScrollTop();
  }, [clearRestoreScrollTop, restoreScrollTop]);

  const reportScrollPosition = useMemo(
    () =>
      throttle((scrollTop: number) => {
        window.jsb.MessagesBridge.updateScrollPosition(scrollTop).catch(
          () => {}
        );
      }, 150),
    []
  );

  useEffect(() => {
    return () => {
      reportScrollPosition.cancel();
    };
  }, [reportScrollPosition]);

  const clearFocusedMessage = useCallback(() => {
    if (focusedMessageCleanupTimeoutRef.current !== null) {
      window.clearTimeout(focusedMessageCleanupTimeoutRef.current);
      focusedMessageCleanupTimeoutRef.current = null;
    }

    focusedMessageElementRef.current?.classList.remove(
      'conversation-message-focused'
    );
    focusedMessageElementRef.current = null;
  }, []);

  useEffect(() => {
    return () => {
      clearFocusedMessage();
    };
  }, [clearFocusedMessage]);

  const syncScrollState = useCallback(() => {
    const container = scrollContainerRef.current;
    if (!container) {
      return;
    }

    const distanceFromBottom =
      container.scrollHeight - container.scrollTop - container.clientHeight;
    setAutoScrollAllowed(distanceFromBottom <= 1);
    reportScrollPosition(container.scrollTop);
  }, [reportScrollPosition]);

  const highlightMessageElement = useCallback(
    (element: HTMLElement) => {
      clearFocusedMessage();
      element.classList.remove('conversation-message-focused');
      void element.getBoundingClientRect();
      element.classList.add('conversation-message-focused');
      element.scrollIntoView({
        block: 'center',
        behavior: 'auto',
      });
      focusedMessageElementRef.current = element;
      focusedMessageCleanupTimeoutRef.current = window.setTimeout(() => {
        if (focusedMessageElementRef.current !== element) {
          return;
        }
        element.classList.remove('conversation-message-focused');
        focusedMessageElementRef.current = null;
        focusedMessageCleanupTimeoutRef.current = null;
      }, 2200);
    },
    [clearFocusedMessage]
  );

  const findMessageElement = useCallback((messageId: string) => {
    const container = scrollContainerRef.current;
    if (!container) {
      return null;
    }

    const escapedId = window.CSS?.escape
      ? window.CSS.escape(messageId)
      : messageId.replace(/["\\]/g, '\\$&');

    return container.querySelector<HTMLElement>(
      `[data-message-id="${escapedId}"]`
    );
  }, []);

  useEffect(() => {
    if (!pendingFocusMessageRequest) {
      return;
    }

    let timeoutId: number | null = null;
    let cancelled = false;
    const request = pendingFocusMessageRequest;

    const attemptFocus = (attempt: number) => {
      if (cancelled) {
        return;
      }

      const element = findMessageElement(request.messageId);
      if (element) {
        highlightMessageElement(element);
        setPendingFocusMessageRequest(current =>
          current?.requestId === request.requestId ? null : current
        );
        return;
      }

      if (attempt >= FOCUS_MESSAGE_RETRY_LIMIT) {
        setPendingFocusMessageRequest(current =>
          current?.requestId === request.requestId ? null : current
        );
        return;
      }

      timeoutId = window.setTimeout(
        () => attemptFocus(attempt + 1),
        attempt < 10
          ? FOCUS_MESSAGE_FAST_RETRY_DELAY_MS
          : FOCUS_MESSAGE_SLOW_RETRY_DELAY_MS
      );
    };

    const frame = window.requestAnimationFrame(() => {
      attemptFocus(0);
    });

    return () => {
      cancelled = true;
      window.cancelAnimationFrame(frame);
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId);
      }
    };
  }, [
    findMessageElement,
    highlightMessageElement,
    historyInitVersion,
    pendingFocusMessageRequest,
  ]);

  useEffect(() => {
    const container = scrollContainerRef.current;
    if (!container || messages.length === 0) {
      return;
    }

    const flushScrollPosition = () => {
      syncScrollState();
    };

    container.addEventListener('scroll', flushScrollPosition, {
      passive: true,
    });

    return () => {
      flushScrollPosition();
      container.removeEventListener('scroll', flushScrollPosition);
    };
  }, [messages.length, syncScrollState]);

  return (
    <>
      <MaskedScrollArea
        ref={scrollContainerRef}
        className="h-full px-5"
        maskSizeStart={0}
        contentStyle={{ paddingTop }}
      >
        <div
          className="mx-auto w-full max-w-[800px]"
          data-quote-container="true"
          data-quote-focus-class="conversation-message-focused"
        >
          {!hasConversationContent ? (
            <div
              className="flex flex-col pb-4"
              style={{ height: `calc(100dvh - ${paddingTop}px)` }}
            >
              <div className="h-0 flex-1" />
              <Greet />
            </div>
          ) : (
            <Messages
              messages={messages}
              assistantStateSequence={assistantStateSequence}
              isStreaming={isStreaming}
              followUpState={followUpState}
              pagePaddingTop={paddingTop}
              enableAutoScroll={isStreaming && autoScrollAllowed}
              onSendMessage={sendOrQueueMessage}
            />
          )}
        </div>
      </MaskedScrollArea>
      <QuoteSelectionBubble
        containerRef={scrollContainerRef}
        safeAreaInsetTop={paddingTop}
        onAskQuote={selection => {
          window.jsb.MessagesBridge.setComposerQuote({
            text: selection.text,
            quoteRef: selection.quoteRef,
          });
        }}
      />
      {createPortal(
        <div className="fixed bottom-0 left-0 right-0 z-10 flex flex-col items-center px-6">
          <ActivityCenter
            messages={messages}
            workspaceState={workspaceState}
            isStreaming={isStreaming}
            hasOpenTask={hasOpenTask}
          />
        </div>,
        document.body
      )}
      {createPortal(
        <div
          className="fixed left-0 right-0 z-20 flex justify-center px-6 pb-3"
          style={{
            bottom: `calc(${globalVar('activityCenterHeight')} + 8px)`,
          }}
        >
          <div className="w-full max-w-[calc(800px-48px)]">
            <QueuedMessageBanner
              message={queuedMessage}
              onCancel={cancelQueuedMessage}
            />
          </div>
        </div>,
        document.body
      )}
    </>
  );
};

const root = createRoot(container);
const previewMode = getEmbeddedChatPreviewMode();

root.render(
  <ThemeProvider>
    <DebugMessageProvider>
      {previewMode === 'permission-message' ? (
        <PermissionMessagePreviewPage />
      ) : (
        <ChatPage />
      )}
    </DebugMessageProvider>
  </ThemeProvider>
);
