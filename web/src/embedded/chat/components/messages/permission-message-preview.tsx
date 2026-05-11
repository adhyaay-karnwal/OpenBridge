import { useEffect } from 'react';
import type {
  SessionHistoryMessage,
  SessionHistoryMessagePermissionRequestInfo,
} from '../../types/history';
import { PermissionMessage } from './permission-message';

type PreviewScenario = {
  id: string;
  label: string;
  description: string;
  messages: SessionHistoryMessage[];
};

function makePermissionRequestMessage({
  id,
  environmentLabel,
  description,
  kind,
  computerUseStart,
}: {
  id: string;
  environmentLabel?: string;
  description: string;
  kind?: string;
  computerUseStart?: SessionHistoryMessagePermissionRequestInfo['computerUseStart'];
}): SessionHistoryMessage {
  return {
    id,
    type: 'permission_request',
    role: 'assistant',
    timestamp: Date.now(),
    confirmationId: id,
    permissionRequest: {
      environmentId: 'local_macos',
      environmentLabel,
      description,
      kind,
      computerUseStart,
    },
  };
}

function makePermissionReplyMessage({
  id,
  confirmationId,
  approved,
  reason,
  mode,
}: {
  id: string;
  confirmationId: string;
  approved: boolean;
  reason?: string;
  mode?: string;
}): SessionHistoryMessage {
  return {
    id,
    type: 'permission_reply',
    role: 'assistant',
    timestamp: Date.now(),
    confirmationId,
    permissionReply: { approved, reason, mode },
  };
}

function ensurePreviewBridges() {
  if (typeof window === 'undefined') return () => {};

  const previousJSB = window.jsb;
  const existingReplyInteraction = (
    previousJSB?.MessagesBridge as { replyInteraction?: unknown } | undefined
  )?.replyInteraction;
  if (typeof existingReplyInteraction === 'function') {
    return () => {};
  }

  const previewJSB = {
    ...previousJSB,
    MessagesBridge: {
      ...previousJSB?.MessagesBridge,
      replyInteraction: async () => {},
    },
  } satisfies Partial<Window['jsb']>;

  window.jsb = previewJSB as Window['jsb'];

  return () => {
    if (previousJSB) {
      window.jsb = previousJSB;
      return;
    }
    Reflect.deleteProperty(window, 'jsb');
  };
}

const GENERIC_PERMISSION_DESCRIPTION =
  'Undo the recent Desktop file organization on your local Mac because the safer workspace disconnected\nRequested environment: This Mac';

const COMPUTER_USE_START_DESCRIPTION =
  'Agent wants to start ComputerUse (suggested mode: background).\nApps in focus: Figma\nRequested environment: local-09a0fdaf15d0';

const previewScenarios: PreviewScenario[] = [
  {
    id: 'generic-pending',
    label: 'Generic · Pending',
    description: 'Leading-aligned title, body, detail, and two actions.',
    messages: [
      makePermissionRequestMessage({
        id: 'generic-pending',
        environmentLabel: 'This Mac',
        description: GENERIC_PERMISSION_DESCRIPTION,
      }),
    ],
  },
  {
    id: 'generic-approved',
    label: 'Generic · Approved',
    description: 'Resolved success state keeps the same leading edge.',
    messages: [
      makePermissionRequestMessage({
        id: 'generic-approved',
        environmentLabel: 'This Mac',
        description: GENERIC_PERMISSION_DESCRIPTION,
      }),
      makePermissionReplyMessage({
        id: 'generic-approved-reply',
        confirmationId: 'generic-approved',
        approved: true,
      }),
    ],
  },
  {
    id: 'generic-denied',
    label: 'Generic · Denied',
    description: 'Resolved warning state keeps a single content column.',
    messages: [
      makePermissionRequestMessage({
        id: 'generic-denied',
        environmentLabel: 'This Mac',
        description: GENERIC_PERMISSION_DESCRIPTION,
      }),
      makePermissionReplyMessage({
        id: 'generic-denied-reply',
        confirmationId: 'generic-denied',
        approved: false,
      }),
    ],
  },
  {
    id: 'generic-expired',
    label: 'Generic · Expired',
    description: 'Expired state preserves structure and muted tone.',
    messages: [
      makePermissionRequestMessage({
        id: 'generic-expired',
        environmentLabel: 'This Mac',
        description: GENERIC_PERMISSION_DESCRIPTION,
      }),
      makePermissionReplyMessage({
        id: 'generic-expired-reply',
        confirmationId: 'generic-expired',
        approved: false,
        reason: 'expired',
      }),
    ],
  },
  {
    id: 'computer-use-pending-missing',
    label: 'Computer use · Pending · Missing permissions',
    description:
      'Mode picker with Foreground / Background + Deny; suggested mode highlighted.',
    messages: [
      makePermissionRequestMessage({
        id: 'computer-use-pending-missing',
        kind: 'computer_use_start',
        environmentLabel: 'Local macOS',
        description: COMPUTER_USE_START_DESCRIPTION,
        computerUseStart: {
          availableModes: ['background', 'foreground'],
          apps: ['Figma'],
          permissions: [
            { pane: 'accessibility', granted: true },
            { pane: 'input_monitoring', granted: false },
            { pane: 'screen_recording', granted: false },
          ],
        },
      }),
    ],
  },
  {
    id: 'computer-use-start-pending',
    label: 'Computer use · Start · Pending',
    description: 'Mode picker with Foreground / Background + Deny.',
    messages: [
      makePermissionRequestMessage({
        id: 'computer-use-start-pending',
        kind: 'computer_use_start',
        environmentLabel: 'Local macOS',
        description: COMPUTER_USE_START_DESCRIPTION,
        computerUseStart: {
          availableModes: ['background', 'foreground'],
          apps: ['Figma'],
        },
      }),
    ],
  },
  {
    id: 'computer-use-start-accepted',
    label: 'Computer use · Start · Accepted',
    description: 'User picked Background; resolved success state.',
    messages: [
      makePermissionRequestMessage({
        id: 'computer-use-start-accepted',
        kind: 'computer_use_start',
        environmentLabel: 'Local macOS',
        description: COMPUTER_USE_START_DESCRIPTION,
        computerUseStart: {
          availableModes: ['background', 'foreground'],
          apps: ['Figma'],
        },
      }),
      makePermissionReplyMessage({
        id: 'computer-use-start-accepted-reply',
        confirmationId: 'computer-use-start-accepted',
        approved: true,
        mode: 'background',
      }),
    ],
  },
  {
    id: 'computer-use-start-denied',
    label: 'Computer use · Start · Denied',
    description: 'User denied the start request; resolved denied state.',
    messages: [
      makePermissionRequestMessage({
        id: 'computer-use-start-denied',
        kind: 'computer_use_start',
        environmentLabel: 'Local macOS',
        description: COMPUTER_USE_START_DESCRIPTION,
        computerUseStart: {
          availableModes: ['background', 'foreground'],
        },
      }),
      makePermissionReplyMessage({
        id: 'computer-use-start-denied-reply',
        confirmationId: 'computer-use-start-denied',
        approved: false,
      }),
    ],
  },
  {
    id: 'computer-use-start-expired',
    label: 'Computer use · Start · Expired',
    description: 'Resolved expired state with unchanged card structure.',
    messages: [
      makePermissionRequestMessage({
        id: 'computer-use-start-expired',
        kind: 'computer_use_start',
        environmentLabel: 'Local macOS',
        description: COMPUTER_USE_START_DESCRIPTION,
        computerUseStart: {
          availableModes: ['background', 'foreground'],
          apps: ['Figma'],
        },
      }),
      makePermissionReplyMessage({
        id: 'computer-use-start-expired-reply',
        confirmationId: 'computer-use-start-expired',
        approved: false,
        reason: 'expired',
      }),
    ],
  },
];

export const PermissionMessagePreviewPage = () => {
  useEffect(() => ensurePreviewBridges(), []);

  return (
    <main className="min-h-screen bg-bg-primary px-6 py-8 text-text-primary">
      <div className="mx-auto flex max-w-6xl flex-col gap-6">
        <header className="space-y-2">
          <h1 className="text-2xl font-semibold leading-8">
            Permission card preview
          </h1>
          <p className="max-w-3xl text-sm leading-5 text-text-secondary">
            Generic permission prompts and the ComputerUse start mode picker.
          </p>
        </header>

        <section className="grid grid-cols-1 gap-4 xl:grid-cols-2">
          {previewScenarios.map(scenario => {
            const message = scenario.messages[0];
            return (
              <div
                key={scenario.id}
                className="flex flex-col gap-3 rounded-3xl border border-border bg-surface-card p-4"
              >
                <div className="space-y-1">
                  <h2 className="text-sm font-semibold leading-5 text-text-primary">
                    {scenario.label}
                  </h2>
                  <p className="text-xs leading-4 text-text-tertiary">
                    {scenario.description}
                  </p>
                </div>

                <PermissionMessage
                  message={message}
                  messages={scenario.messages}
                />
              </div>
            );
          })}
        </section>
      </div>
    </main>
  );
};
