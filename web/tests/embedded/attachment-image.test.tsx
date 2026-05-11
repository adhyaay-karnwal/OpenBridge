// @vitest-environment jsdom
/* oxlint-disable no-await-in-loop */

import React from 'react';
import { flushSync } from 'react-dom';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildAgentFileURL } from '../../src/utils/agent-file-url';
import { AttachmentImage } from '../../src/embedded/chat/components/messages/attachment-image';

async function waitForCondition(condition: () => boolean, timeoutMs = 1000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (condition()) {
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 0));
    flushSync(() => {});
  }
  throw new Error('Timed out waiting for condition');
}

vi.mock('../../src/embedded/chat/components/loading/spinner', () => ({
  Spinner: () => <div data-testid="spinner" />,
}));

const mountedRoots: Root[] = [];
const originalWebkit = (window as Window & { webkit?: unknown }).webkit;
let consoleErrorSpy: ReturnType<typeof vi.spyOn> | null = null;

describe('AttachmentImage', () => {
  beforeEach(() => {
    consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    window.webkit = {
      messageHandlers: {
        jsb: {},
        openbridgeReady: {},
      },
    } as never;
    window.jsb = {
      MessagesBridge: {
        getStorageDownloadUrl: vi.fn(async (url: string) => `signed:${url}`),
      },
    } as never;
  });

  afterEach(async () => {
    for (const root of mountedRoots.splice(0)) {
      flushSync(() => {
        root.unmount();
      });
      await waitForCondition(() => true);
    }
    document.body.innerHTML = '';
    vi.clearAllMocks();

    if (originalWebkit) {
      window.webkit = originalWebkit as never;
    } else {
      Reflect.deleteProperty(window, 'webkit');
    }
    Reflect.deleteProperty(window, 'jsb');
    consoleErrorSpy?.mockRestore();
    consoleErrorSpy = null;
  });

  it('resolves authenticated agent file routes through the native bridge', async () => {
    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <AttachmentImage
          src={buildAgentFileURL('/.agent/deliveries/session/call/cat.png')}
          fileName="cat.png"
          mimeType="image/png"
          sourcePath="/.agent/deliveries/session/call/cat.png"
          environmentId="vfs"
        />
      );
    });
    await waitForCondition(
      () =>
        vi.mocked(window.jsb.MessagesBridge.getStorageDownloadUrl).mock.calls
          .length === 1
    );

    expect(
      window.jsb.MessagesBridge.getStorageDownloadUrl
    ).toHaveBeenCalledWith(
      buildAgentFileURL('/.agent/deliveries/session/call/cat.png')
    );
  });

  it('does not ask the native bridge to re-resolve direct browser URLs', async () => {
    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <AttachmentImage
          src="https://cdn.example.com/cat.png"
          fileName="cat.png"
          mimeType="image/png"
        />
      );
    });
    await waitForCondition(
      () =>
        container.querySelector('img')?.getAttribute('src') ===
        'https://cdn.example.com/cat.png'
    );

    expect(
      window.jsb.MessagesBridge.getStorageDownloadUrl
    ).not.toHaveBeenCalled();
  });

  it('fails closed when authenticated attachment resolution fails', async () => {
    vi.mocked(
      window.jsb.MessagesBridge.getStorageDownloadUrl
    ).mockRejectedValueOnce(new Error('boom'));

    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <AttachmentImage
          src={buildAgentFileURL('/.agent/deliveries/session/call/cat.png')}
          fileName="cat.png"
          mimeType="image/png"
        />
      );
    });
    await waitForCondition(
      () => container.textContent?.includes('Image unavailable') ?? false
    );

    expect(container.textContent).toContain('Image unavailable');
  });
});
