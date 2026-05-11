// @vitest-environment jsdom

import React from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PermissionMessage } from '../../src/embedded/chat/components/messages/permission-message';
import type { SessionHistoryMessage } from '../../src/embedded/chat/types/history';

const mountedRoots: Root[] = [];
const originalWebkit = (window as Window & { webkit?: unknown }).webkit;
let consoleErrorSpy: ReturnType<typeof vi.spyOn> | null = null;

function makeMessage(
  message: Partial<SessionHistoryMessage>
): SessionHistoryMessage {
  return {
    id: message.id ?? 'message-id',
    type: message.type ?? 'permission_request',
    role: message.role ?? 'assistant',
    timestamp: message.timestamp ?? 1,
    ...message,
  };
}

function setMockJSB(bridge: Partial<Window['jsb']>) {
  window.jsb = bridge as Window['jsb'];
}

describe('PermissionMessage', () => {
  beforeEach(() => {
    consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    window.webkit = {
      messageHandlers: {
        jsb: {},
        bridgeReady: {},
      },
    } as never;
  });

  afterEach(async () => {
    for (const root of mountedRoots.splice(0)) {
      flushSync(() => {
        root.unmount();
      });
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

  it('renders expired state from a permission reply reason', async () => {
    setMockJSB({
      MessagesBridge: {
        replyInteraction: vi.fn(),
      },
    });

    const request = makeMessage({
      id: 'connector-1',
      confirmationId: 'connector-1',
      permissionRequest: {
        environmentId: 'local_macos',
        environmentLabel: 'Host',
        description: 'Need host access',
      },
    });
    const reply = makeMessage({
      id: 'reply-connector-1',
      type: 'permission_reply',
      confirmationId: 'connector-1',
      permissionReply: {
        approved: false,
        reason: 'expired',
      },
    });

    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <PermissionMessage message={request} messages={[request, reply]} />
      );
    });

    expect(container.textContent).toContain('Expired');
    expect(container.textContent).toContain('Need host access');
  });

  it('renders generic permission details in a single leading content column', async () => {
    setMockJSB({
      MessagesBridge: {
        replyInteraction: vi.fn(),
      },
    });

    const request = makeMessage({
      id: 'generic-approved',
      confirmationId: 'generic-approved',
      permissionRequest: {
        environmentId: 'local_macos',
        environmentLabel: 'This Mac',
        description:
          'Undo the recent Desktop file organization on your local Mac because the safer workspace disconnected\nRequested environment: This Mac',
      },
    });
    const reply = makeMessage({
      id: 'generic-approved-reply',
      type: 'permission_reply',
      confirmationId: 'generic-approved',
      permissionReply: {
        approved: true,
      },
    });

    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(
        <PermissionMessage message={request} messages={[request, reply]} />
      );
    });

    expect(container.textContent).toContain('This Mac');
    expect(container.textContent).toContain(
      'Undo the recent Desktop file organization on your local Mac because the safer workspace disconnected'
    );
    expect(container.textContent).not.toContain('Requested environment:');
    expect(
      Array.from(container.querySelectorAll('button')).some(
        button => button.textContent === 'Approved'
      )
    ).toBe(true);
  });

  it('renders computer-use permissions and enables accept when all are granted', async () => {
    setMockJSB({
      MessagesBridge: {
        replyInteraction: vi.fn(),
        getComputerUsePermissionsStatus: vi.fn(),
        openComputerUsePermissionFlow: vi.fn(),
      },
    });

    const request = makeMessage({
      id: 'computer-use-ready',
      confirmationId: 'computer-use-ready',
      permissionRequest: {
        environmentId: 'local_macos',
        environmentLabel: 'This Mac',
        kind: 'computer_use_start',
        description:
          'Control Figma on your Mac to create a new design file with a red rectangle\nRequested environment: This Mac',
        computerUseStart: {
          availableModes: ['background', 'foreground'],
          apps: ['Figma'],
          permissions: [
            { pane: 'accessibility', granted: true },
            { pane: 'input_monitoring', granted: true },
            { pane: 'screen_recording', granted: true },
          ],
        },
      },
    });

    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(<PermissionMessage message={request} messages={[request]} />);
    });

    expect(container.textContent).toContain('Agent wants to start ComputerUse');
    expect(container.textContent).toContain('This Mac');
    expect(container.textContent).not.toContain('Requested environment:');
    expect(container.textContent).toContain('Apps in focus: Figma');

    const backgroundButton = Array.from(
      container.querySelectorAll('button')
    ).find(button => button.textContent === 'Background');
    const foregroundButton = Array.from(
      container.querySelectorAll('button')
    ).find(button => button.textContent === 'Foreground');
    expect(backgroundButton).toBeTruthy();
    expect(backgroundButton?.disabled).toBe(false);
    expect(foregroundButton).toBeTruthy();
    expect(foregroundButton?.disabled).toBe(false);
  });

  it('shows authorization action while computer-use permissions are incomplete', async () => {
    setMockJSB({
      MessagesBridge: {
        replyInteraction: vi.fn(),
        getComputerUsePermissionsStatus: vi.fn(),
        openComputerUsePermissionFlow: vi.fn(),
      },
    });

    const request = makeMessage({
      id: 'computer-use-missing',
      confirmationId: 'computer-use-missing',
      permissionRequest: {
        environmentId: 'local_macos',
        environmentLabel: 'This Mac',
        kind: 'computer_use_start',
        description:
          'Control Figma on your Mac to create a new design file with a red rectangle\nRequested environment: This Mac',
        computerUseStart: {
          availableModes: ['background', 'foreground'],
          apps: ['Figma'],
          permissions: [
            { pane: 'accessibility', granted: true },
            { pane: 'input_monitoring', granted: false },
            { pane: 'screen_recording', granted: false },
          ],
        },
      },
    });

    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(<PermissionMessage message={request} messages={[request]} />);
    });

    expect(container.textContent).toContain(
      'ComputerUse needs Input Monitoring and Screen Recording.'
    );

    const grantButton = Array.from(container.querySelectorAll('button')).find(
      button => button.textContent === 'Grant permissions'
    );
    const backgroundButton = Array.from(
      container.querySelectorAll('button')
    ).find(button => button.textContent === 'Background');
    expect(grantButton).toBeTruthy();
    expect(grantButton?.disabled).toBe(false);
    expect(backgroundButton).toBeFalsy();
  });

  it('converts unknown confirmation failures into expired state', async () => {
    const replyInteraction = vi.fn(async () => {
      throw new Error('Unknown confirmation: connector-1');
    });
    setMockJSB({
      MessagesBridge: {
        replyInteraction,
      },
    });

    const request = makeMessage({
      id: 'connector-1',
      confirmationId: 'connector-1',
      permissionRequest: {
        environmentId: 'local_macos',
        environmentLabel: 'Host',
        description: 'Need host access',
      },
    });

    const container = document.createElement('div');
    document.body.appendChild(container);
    const root = createRoot(container);
    mountedRoots.push(root);

    flushSync(() => {
      root.render(<PermissionMessage message={request} messages={[request]} />);
    });

    const approveButton = Array.from(container.querySelectorAll('button')).find(
      button => button.textContent === 'Approve'
    );
    expect(approveButton).toBeTruthy();

    flushSync(() => {
      approveButton?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await new Promise(resolve => setTimeout(resolve, 0));
    await new Promise(resolve => setTimeout(resolve, 0));

    expect(replyInteraction).toHaveBeenCalledWith(
      'connector-1',
      JSON.stringify({ approved: true })
    );
    expect(container.textContent).toContain('Expired');
  });
});
