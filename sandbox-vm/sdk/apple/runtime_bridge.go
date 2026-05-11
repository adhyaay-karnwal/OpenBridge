package sandboxvm

import (
	"fmt"

	"github.com/openbridge/sandbox-vm/internal/envhost"
	"github.com/openbridge/sandbox-vm/internal/framework/runtimebridge"
	"github.com/openbridge/sandbox-vm/internal/integrations/apiproxy"
)

type RuntimeBridgeConfig struct {
	BackendURL    string
	BackendAPIKey string
}

type RuntimeBridgeServer struct {
	server             *envhost.RuntimeBridgeHTTPServer
	capabilityProvider *apiproxy.CapabilityProvider
}

func NewRuntimeBridgeServer(cfg *RuntimeBridgeConfig) (*RuntimeBridgeServer, error) {
	if cfg == nil {
		return nil, fmt.Errorf("runtime bridge config is required")
	}

	capabilityProvider, bridge := runtimebridge.NewLocalExecutionBridge()
	server, err := envhost.NewRuntimeBridgeHTTPServer(bridge)
	if err != nil {
		return nil, err
	}

	return &RuntimeBridgeServer{
		server:             server,
		capabilityProvider: capabilityProvider,
	}, nil
}

func (s *RuntimeBridgeServer) Close() error {
	if s == nil || s.server == nil {
		return nil
	}
	return s.server.Close()
}

func (s *RuntimeBridgeServer) CapabilityURL(sessionID string, callerAgentID string) string {
	if s == nil || s.server == nil || s.capabilityProvider == nil {
		return ""
	}
	runtime := s.capabilityProvider.ExecutionRuntime(sessionID, callerAgentID)
	if runtime == nil {
		return ""
	}
	return envhost.RuntimeCapabilityURL(s.server.BaseURL(), runtime.CapabilityToken)
}
