// @vitest-environment jsdom
/* oxlint-disable no-await-in-loop */

import React from 'react';
import { flushSync } from 'react-dom';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  buildAgentFileURL,
  type AttachmentDisplayURLParams,
} from '../../src/utils/agent-file-url';
import { useResolvedUrl } from '../../src/embedded/chat/components/messages/use-resolved-url';

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

function Harness(props: AttachmentDisplayURLParams) {
  const resolved = useResolvedUrl(props);
  return <div data-testid="resolved-url">{resolved ?? ''}</div>;
}

const mountedRoots: Root[] = [];
const originalWebkit = (window as Window & { webkit?: unknown }).webkit;

describe('useResolvedUrl', () => {
  beforeEach(() => {
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
  });

  it('resolves service-provided agent file routes in native bridge mode', async () => {
    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <Harness
          src={buildAgentFileURL('/.agent/deliveries/session/call/image.png')}
        />
      );
    });
    await waitForCondition(
      () =>
        container.querySelector('[data-testid="resolved-url"]')?.textContent ===
        `signed:${buildAgentFileURL('/.agent/deliveries/session/call/image.png')}`
    );

    expect(
      container.querySelector('[data-testid="resolved-url"]')?.textContent
    ).toBe(
      `signed:${buildAgentFileURL('/.agent/deliveries/session/call/image.png')}`
    );
    expect(
      window.jsb.MessagesBridge.getStorageDownloadUrl
    ).toHaveBeenCalledWith(
      buildAgentFileURL('/.agent/deliveries/session/call/image.png')
    );
  });

  it('keeps using the service-provided route directly', async () => {
    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <Harness
          src={buildAgentFileURL('/.agent/deliveries/session/call/cat.png')}
        />
      );
    });
    await waitForCondition(
      () =>
        container.querySelector('[data-testid="resolved-url"]')?.textContent ===
        `signed:${buildAgentFileURL('/.agent/deliveries/session/call/cat.png')}`
    );

    expect(
      container.querySelector('[data-testid="resolved-url"]')?.textContent
    ).toBe(
      `signed:${buildAgentFileURL('/.agent/deliveries/session/call/cat.png')}`
    );
    expect(
      window.jsb.MessagesBridge.getStorageDownloadUrl
    ).toHaveBeenCalledWith(
      buildAgentFileURL('/.agent/deliveries/session/call/cat.png')
    );
  });

  it('does not route direct browser URLs through the native bridge', async () => {
    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(<Harness src="https://cdn.example.com/cat.png" />);
    });
    await waitForCondition(
      () =>
        container.querySelector('[data-testid="resolved-url"]')?.textContent ===
        'https://cdn.example.com/cat.png'
    );

    expect(
      container.querySelector('[data-testid="resolved-url"]')?.textContent
    ).toBe('https://cdn.example.com/cat.png');
    expect(
      window.jsb.MessagesBridge.getStorageDownloadUrl
    ).not.toHaveBeenCalled();
  });

  it('fails closed when native-only routes cannot be resolved', async () => {
    vi.mocked(
      window.jsb.MessagesBridge.getStorageDownloadUrl
    ).mockRejectedValueOnce(new Error('boom'));

    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <Harness
          src={buildAgentFileURL('/.agent/deliveries/session/call/broken.png')}
        />
      );
    });
    await waitForCondition(
      () =>
        vi.mocked(window.jsb.MessagesBridge.getStorageDownloadUrl).mock.calls
          .length === 1
    );

    expect(
      container.querySelector('[data-testid="resolved-url"]')?.textContent
    ).toBe('');
  });
});
