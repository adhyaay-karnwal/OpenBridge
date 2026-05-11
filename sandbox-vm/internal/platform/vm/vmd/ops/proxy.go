//go:build linux

package ops

import (
	"fmt"
	"log"
	"os"
	"strings"
)

// ProxyManager handles proxy environment configuration.
type ProxyManager struct{}

// NewProxyManager creates a new ProxyManager.
func NewProxyManager() *ProxyManager {
	return &ProxyManager{}
}

// SetProxyEnv configures proxy environment variables in the VM.
func (m *ProxyManager) SetProxyEnv(httpProxy, httpsProxy, noProxy string) error {
	if httpProxy == "" && httpsProxy == "" && noProxy == "" {
		log.Println("No proxy environment variables to configure")
		return nil
	}

	// Build environment content for SSH
	var envContent strings.Builder
	if httpProxy != "" {
		envContent.WriteString(fmt.Sprintf("http_proxy=%s\n", httpProxy))
		envContent.WriteString(fmt.Sprintf("HTTP_PROXY=%s\n", httpProxy))
	}
	if httpsProxy != "" {
		envContent.WriteString(fmt.Sprintf("https_proxy=%s\n", httpsProxy))
		envContent.WriteString(fmt.Sprintf("HTTPS_PROXY=%s\n", httpsProxy))
	}
	if noProxy != "" {
		envContent.WriteString(fmt.Sprintf("no_proxy=%s\n", noProxy))
		envContent.WriteString(fmt.Sprintf("NO_PROXY=%s\n", noProxy))
	}

	// Write to /root/.ssh/environment (SSH reads this with PermitUserEnvironment)
	sshEnvPath := "/root/.ssh/environment"
	if err := os.MkdirAll("/root/.ssh", 0700); err != nil {
		return fmt.Errorf("create .ssh directory: %w", err)
	}
	if err := os.WriteFile(sshEnvPath, []byte(envContent.String()), 0644); err != nil {
		return fmt.Errorf("write SSH environment: %w", err)
	}
	log.Printf("Configured proxy in %s", sshEnvPath)

	// Build profile content (with export prefix)
	var profileContent strings.Builder
	if httpProxy != "" {
		profileContent.WriteString(fmt.Sprintf("export http_proxy=%s\n", httpProxy))
		profileContent.WriteString(fmt.Sprintf("export HTTP_PROXY=%s\n", httpProxy))
	}
	if httpsProxy != "" {
		profileContent.WriteString(fmt.Sprintf("export https_proxy=%s\n", httpsProxy))
		profileContent.WriteString(fmt.Sprintf("export HTTPS_PROXY=%s\n", httpsProxy))
	}
	if noProxy != "" {
		profileContent.WriteString(fmt.Sprintf("export no_proxy=%s\n", noProxy))
		profileContent.WriteString(fmt.Sprintf("export NO_PROXY=%s\n", noProxy))
	}

	// Write to /etc/profile.d for shell sessions
	profilePath := "/etc/profile.d/host-proxy.sh"
	if err := os.WriteFile(profilePath, []byte(profileContent.String()), 0644); err != nil {
		return fmt.Errorf("write profile: %w", err)
	}
	log.Printf("Configured proxy in %s", profilePath)

	return nil
}
