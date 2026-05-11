type LocalObservabilityEvent = {
  failureClass: string;
  severity?: 'info' | 'warning' | 'error' | 'critical';
  surface: string;
  error?: unknown;
  properties?: Record<string, unknown>;
};

export function captureOpenBridgeObservabilityEvent(
  event: LocalObservabilityEvent
) {
  if (event.severity === 'critical' || event.severity === 'error') {
    console.error('[local-observability]', event);
    return true;
  }

  console.info('[local-observability]', event);
  return true;
}
