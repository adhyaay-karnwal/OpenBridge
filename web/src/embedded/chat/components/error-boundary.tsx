import { Component, type ErrorInfo, type ReactNode } from 'react';

import { captureOpenBridgeObservabilityEvent } from '@/utils/local-observability';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
  copied: boolean;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
      copied: false,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo);
    captureOpenBridgeObservabilityEvent({
      failureClass: 'client.web_error_boundary',
      severity: 'error',
      surface: 'embedded_chat',
      error,
      properties: {
        component_stack: errorInfo.componentStack,
        suspect_layer: 'web',
      },
    });
    this.setState({ errorInfo });
  }

  handleCopy = () => {
    const { error, errorInfo } = this.state;
    const errorText = [
      `Error: ${error?.message ?? 'Unknown error'}`,
      error?.stack ?? '',
      errorInfo?.componentStack ?? '',
    ]
      .filter(Boolean)
      .join('\n\n');

    navigator.clipboard.writeText(errorText).then(() => {
      this.setState({ copied: true });
      setTimeout(() => this.setState({ copied: false }), 2000);
    });
  };

  override render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }
      return (
        <div className="text-xs text-red-500 p-2 bg-red-50 rounded flex items-center gap-2">
          <span>Something went wrong</span>
          <button
            onClick={this.handleCopy}
            className="px-2 py-0.5 bg-red-100 hover:bg-red-200 rounded text-red-600 transition-colors"
          >
            {this.state.copied ? 'Copied!' : 'Copy error'}
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}
