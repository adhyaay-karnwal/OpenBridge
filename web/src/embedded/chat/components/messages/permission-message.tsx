import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type {
  SessionHistoryMessage,
  SessionHistoryMessageComputerUsePermissionPane,
} from '../../types/history';
import {
  isPermissionReplyMessage,
  isPermissionRequestMessage,
} from '../../types/history';
import { cn } from '@/utils/cn';
import { ShieldLefthalfFilledSFSymbolMedium } from '@/assets/sf-symbols/medium/shield.lefthalf.filled';
import { MonitorIcon } from 'lucide-react';

function splitPermissionDescription(description: string): {
  body: string;
  requestedEnvironment: string | null;
} {
  const [body, requestedEnvironment] = description.split(
    /\nRequested environment:\s*/
  );

  return {
    body: body?.trim() ?? description.trim(),
    requestedEnvironment: requestedEnvironment?.trim() || null,
  };
}

function permissionCardTone({
  isApproved,
  isExpired,
  isReplied,
}: {
  isApproved: boolean;
  isExpired: boolean;
  isReplied: boolean;
}) {
  if (!isReplied) return 'pending';
  if (isApproved) return 'approved';
  if (isExpired) return 'expired';
  return 'denied';
}

function permissionCardContent(
  permissionRequest: NonNullable<SessionHistoryMessage['permissionRequest']>
) {
  const { body } = splitPermissionDescription(permissionRequest.description);

  if (permissionRequest.computerUseStart) {
    return {
      title: 'Agent wants to start ComputerUse',
      subtitle: permissionRequest.environmentLabel?.trim() || undefined,
      body,
    };
  }

  return {
    title: permissionRequest.environmentLabel?.trim() || 'Permission request',
    subtitle: undefined,
    body,
  };
}

export const PermissionMessage = ({
  message,
  messages,
}: {
  message: SessionHistoryMessage;
  messages: SessionHistoryMessage[];
}) => {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [localReplyState, setLocalReplyState] = useState<{
    approved: boolean;
    reason?: string;
    mode?: string;
  } | null>(null);
  const canReply = !!window.jsb?.MessagesBridge?.replyInteraction;
  const latestPermissionRequestKey = useMemo(() => {
    for (let i = messages.length - 1; i >= 0; i--) {
      const candidate = messages[i];
      if (!isPermissionRequestMessage(candidate)) continue;
      return candidate.confirmationId ?? candidate.id ?? null;
    }
    return null;
  }, [messages]);

  const permissionRequest = message.permissionRequest;
  const computerUseStart = permissionRequest?.computerUseStart;
  const messageKey = message.confirmationId ?? message.id ?? null;
  const replyMessage = messages.find(
    m =>
      isPermissionReplyMessage(m) && m.confirmationId === message.confirmationId
  );
  const effectiveReply =
    localReplyState ?? replyMessage?.permissionReply ?? null;
  const isReplied = !!effectiveReply;
  const isApproved = effectiveReply?.approved === true;
  const isExpired = effectiveReply?.reason === 'expired';
  const tone = permissionCardTone({ isApproved, isExpired, isReplied });
  const content = permissionRequest
    ? permissionCardContent(permissionRequest)
    : null;

  const submitReply = useCallback(
    async (approved: boolean, mode?: string) => {
      if (
        isReplied ||
        isSubmitting ||
        !message.confirmationId ||
        !window.jsb?.MessagesBridge?.replyInteraction
      ) {
        return;
      }
      setIsSubmitting(true);
      try {
        const reply = JSON.stringify({ approved, mode });
        await window.jsb.MessagesBridge.replyInteraction(
          message.confirmationId,
          reply
        );
      } catch (e) {
        console.error('Failed to reply permission:', e);
        const errorMessage = e instanceof Error ? e.message : String(e);
        if (errorMessage.includes('Unknown confirmation')) {
          setLocalReplyState({ approved: false, reason: 'expired' });
          return;
        }
        setIsSubmitting(false);
      }
    },
    [isReplied, isSubmitting, message.confirmationId]
  );

  if (
    !permissionRequest ||
    !content ||
    latestPermissionRequestKey !== messageKey
  )
    return null;

  return (
    <div
      className={cn(
        'w-full',
        'select-none overflow-hidden rounded-2xl',
        'border',
        'px-4 py-4',
        tone === 'approved'
          ? 'border-success-fg/20 bg-success-bg'
          : tone === 'expired'
            ? 'border-border bg-surface-card-muted'
            : tone === 'denied'
              ? 'border-warning-fg/20 bg-warning-bg'
              : 'border-border bg-surface-card'
      )}
    >
      <div className="flex flex-col gap-3">
        <div className="flex size-10 items-center justify-center rounded-2xl bg-fill-soft text-text-primary">
          {computerUseStart ? (
            <MonitorIcon className="size-4" />
          ) : (
            <ShieldLefthalfFilledSFSymbolMedium className="text-[16px]" />
          )}
        </div>

        <div className="min-w-0 space-y-1">
          <div className="text-[15px] font-semibold leading-5 text-text-primary">
            {content.title}
          </div>
          {content.subtitle ? (
            <div className="text-[12px] font-medium leading-4 text-text-tertiary">
              {content.subtitle}
            </div>
          ) : null}
        </div>

        <p className="text-[15px] leading-5.5 text-text-secondary whitespace-pre-line">
          {content.body}
        </p>

        {computerUseStart ? (
          <ComputerUseStartFooter
            info={computerUseStart}
            isReplied={isReplied}
            isApproved={isApproved}
            isExpired={isExpired}
            chosenMode={effectiveReply?.mode ?? null}
            disabled={isSubmitting || !canReply}
            onAccept={mode => submitReply(true, mode)}
            onDeny={() => submitReply(false)}
          />
        ) : (
          <div className="flex flex-wrap gap-2 pt-1">
            {isReplied ? (
              <PermissionButton disabled>
                {isApproved ? 'Approved' : isExpired ? 'Expired' : 'Denied'}
              </PermissionButton>
            ) : (
              <>
                <PermissionButton
                  disabled={isSubmitting || !canReply}
                  onClick={() => submitReply(true)}
                >
                  Approve
                </PermissionButton>
                <PermissionButton
                  disabled={isSubmitting || !canReply}
                  onClick={() => submitReply(false)}
                  variant="secondary"
                >
                  Deny
                </PermissionButton>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
};

function ComputerUseStartFooter({
  info,
  isReplied,
  isApproved,
  isExpired,
  chosenMode,
  disabled,
  onAccept,
  onDeny,
}: {
  info: NonNullable<
    NonNullable<SessionHistoryMessage['permissionRequest']>['computerUseStart']
  >;
  isReplied: boolean;
  isApproved: boolean;
  isExpired: boolean;
  chosenMode: string | null;
  disabled: boolean;
  onAccept: (mode: string) => void;
  onDeny: () => void;
}) {
  const [livePermissions, setLivePermissions] = useState<
    SessionHistoryMessageComputerUsePermissionPane[] | null
  >(info.permissions ?? null);
  const [isOpeningAuth, setIsOpeningAuth] = useState(false);
  const pollRef = useRef<number | null>(null);

  const missingPermissions = (livePermissions ?? []).filter(p => !p.granted);
  const hasMissing = missingPermissions.length > 0;
  // If permissions were not supplied at all (daemon unreachable), treat as
  // missing — showing the authorize button at least gets the daemon launched.
  const permissionsUnknown = livePermissions == null;
  const needsAuthorize = !isReplied && (hasMissing || permissionsUnknown);

  const refreshPermissions = useCallback(async () => {
    const bridge = window.jsb?.MessagesBridge;
    if (!bridge?.getComputerUsePermissionsStatus) return;
    try {
      const fresh = await bridge.getComputerUsePermissionsStatus();
      setLivePermissions(fresh);
    } catch (err) {
      console.warn('fetch ComputerUse permissions status failed', err);
    }
  }, []);

  // Poll while any permission is missing so the UI flips to mode buttons as
  // soon as the user returns from System Settings. Stop polling once all
  // permissions are granted.
  useEffect(() => {
    if (!needsAuthorize) {
      if (pollRef.current != null) {
        window.clearInterval(pollRef.current);
        pollRef.current = null;
      }
      return;
    }
    pollRef.current = window.setInterval(refreshPermissions, 1500);
    const onFocus = () => refreshPermissions();
    window.addEventListener('focus', onFocus);
    return () => {
      if (pollRef.current != null) {
        window.clearInterval(pollRef.current);
        pollRef.current = null;
      }
      window.removeEventListener('focus', onFocus);
    };
  }, [needsAuthorize, refreshPermissions]);

  const handleRequestPermission = useCallback(
    async (pane: string) => {
      const bridge = window.jsb?.MessagesBridge;
      if (isReplied || isOpeningAuth) return;
      setIsOpeningAuth(true);
      try {
        if (bridge?.requestComputerUsePermission) {
          const fresh = await bridge.requestComputerUsePermission(pane);
          setLivePermissions(fresh);
        } else if (bridge?.openComputerUsePermissionFlow) {
          await bridge.openComputerUsePermissionFlow();
          await refreshPermissions();
        }
      } catch (err) {
        console.error('request ComputerUse permission failed', err);
      } finally {
        setIsOpeningAuth(false);
      }
    },
    [isOpeningAuth, isReplied, refreshPermissions]
  );

  if (isReplied) {
    const summary = isApproved
      ? chosenMode
        ? chosenMode === 'allow'
          ? 'Started'
          : `Started in ${chosenMode} mode`
        : 'Started'
      : isExpired
        ? 'Expired'
        : 'Denied';
    return (
      <div className="flex flex-wrap gap-2 pt-1">
        <PermissionButton disabled>{summary}</PermissionButton>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {info.apps && info.apps.length > 0 ? (
        <p className="text-[12px] leading-4 text-text-tertiary">
          Apps in focus: {info.apps.join(', ')}
        </p>
      ) : null}
      {hasMissing ? (
        <p className="text-[12px] leading-4 text-warning-fg">
          ComputerUse needs{' '}
          {missingPermissions.map(p => paneDisplayName(p.pane)).join(' and ')}.
        </p>
      ) : null}
      <div className="flex flex-wrap gap-2">
        {needsAuthorize
          ? missingPermissions.map(permission => (
              <PermissionButton
                key={permission.pane}
                disabled={disabled || isOpeningAuth}
                onClick={() => handleRequestPermission(permission.pane)}
              >
                {isOpeningAuth
                  ? 'Opening authorization…'
                  : `Enable ${paneDisplayName(permission.pane)}`}
              </PermissionButton>
            ))
          : info.availableModes.map(mode => (
              <PermissionButton
                key={mode}
                disabled={disabled}
                onClick={() => onAccept(mode)}
              >
                {modeDisplayName(mode)}
              </PermissionButton>
            ))}
        <PermissionButton
          disabled={disabled}
          onClick={onDeny}
          variant="secondary"
        >
          Deny
        </PermissionButton>
      </div>
    </div>
  );
}

function paneDisplayName(pane: string): string {
  switch (pane) {
    case 'accessibility':
      return 'Accessibility';
    case 'screen_recording':
    case 'screen-recording':
      return 'Screen Recording';
    case 'input_monitoring':
      return 'Input Monitoring';
    default:
      return pane
        .split('_')
        .map(p => p.charAt(0).toUpperCase() + p.slice(1))
        .join(' ');
  }
}

function modeDisplayName(mode: string): string {
  switch (mode) {
    case 'allow':
      return 'Allow';
    case 'foreground':
      return 'Foreground';
    case 'background':
      return 'Background';
    default:
      return mode.charAt(0).toUpperCase() + mode.slice(1);
  }
}

function PermissionButton({
  children,
  onClick,
  variant = 'primary',
  disabled = false,
  className,
}: {
  children: React.ReactNode;
  onClick?: () => void;
  variant?: 'primary' | 'secondary';
  disabled?: boolean;
  className?: string;
}) {
  return (
    <button
      disabled={disabled}
      onClick={onClick}
      className={cn(
        'rounded-[10px] px-4 py-1.5 text-[13px] font-medium leading-[17px]',
        'border border-border',
        variant === 'primary'
          ? 'bg-control-bg text-control-fg hover:bg-control-bg-hover active:bg-control-bg-active'
          : 'bg-transparent text-text-secondary hover:bg-fill-soft active:bg-fill-medium',
        disabled ? 'opacity-50' : '',
        'disabled:cursor-default',
        'transition-all',
        className
      )}
    >
      {children}
    </button>
  );
}
