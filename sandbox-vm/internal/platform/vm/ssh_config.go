package vm

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
)

const (
	// maxConfigSize limits the SSH config file size to prevent DoS
	maxConfigSize = 10 * 1024 * 1024 // 10MB
	// validHostNameChars defines valid characters for SSH hostname
	validHostNameChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
)

// SSHEntry represents an SSH config entry that was added
type SSHEntry struct {
	HostName string
	KeyPath  string // Path to SSH private key file (for cleanup)
}

// AddSSHConfigEntry adds a temporary SSH config entry for VM access.
// It writes the SSH private key to a temporary file if not already written.
func AddSSHConfigEntry(vmManager *Manager, sshHost string, sshPort int) (*SSHEntry, error) {
	// Validate inputs
	if err := validateSSHTarget(sshHost, sshPort); err != nil {
		return nil, fmt.Errorf("invalid SSH target: %w", err)
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get home directory: %w", err)
	}

	sshConfigPath := filepath.Join(home, ".ssh", "config")
	// Validate that the resolved path is within home directory to prevent path traversal
	if !strings.HasPrefix(sshConfigPath, home) {
		return nil, fmt.Errorf("invalid SSH config path: %s", sshConfigPath)
	}

	// Get or write SSH private key file
	keyPath, err := vmManager.EnsureSSHKeyFile()
	if err != nil {
		return nil, fmt.Errorf("failed to ensure SSH key file: %w", err)
	}

	// Validate key path doesn't contain dangerous characters
	if strings.Contains(keyPath, "\n") || strings.Contains(keyPath, "\r") {
		return nil, fmt.Errorf("invalid key path: contains newline characters")
	}

	// Generate fixed host name
	hostName := "openbridge-vm"

	// Create SSH config entry with markers for easy removal
	// Quote the IdentityFile path in case it contains spaces
	entry := fmt.Sprintf(`
# >>> openbridge-vm-auto-config [%s] >>>
Host %s
    HostName %s
    Port %d
    User root
    IdentityFile "%s"
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
# <<< openbridge-vm-auto-config [%s] <<<
`, hostName, hostName, sshHost, sshPort, keyPath, hostName)

	// Ensure .ssh directory exists
	sshDir := filepath.Join(home, ".ssh")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		return nil, fmt.Errorf("failed to create .ssh directory: %w", err)
	}

	// Check if config file exists and is not a symlink (security: prevent symlink attacks)
	if info, err := os.Lstat(sshConfigPath); err == nil {
		if info.Mode()&os.ModeSymlink != 0 {
			return nil, fmt.Errorf("SSH config is a symlink, refusing to modify for security")
		}
		// Check file size to prevent DoS
		if info.Size() > maxConfigSize {
			return nil, fmt.Errorf("SSH config file too large (%d bytes), max %d bytes", info.Size(), maxConfigSize)
		}
	}

	// Read existing config
	existingContent := []byte{}
	if _, err := os.Stat(sshConfigPath); err == nil {
		existingContent, err = os.ReadFile(sshConfigPath)
		if err != nil {
			return nil, fmt.Errorf("failed to read SSH config: %w", err)
		}
		// Additional size check after reading
		if len(existingContent) > maxConfigSize {
			return nil, fmt.Errorf("SSH config file too large (%d bytes), max %d bytes", len(existingContent), maxConfigSize)
		}
	}

	// Clean up any existing entry with the same hostname before adding new one
	contentStr := string(existingContent)
	startMarker := fmt.Sprintf("# >>> openbridge-vm-auto-config [%s] >>>", hostName)
	endMarker := fmt.Sprintf("# <<< openbridge-vm-auto-config [%s] <<<", hostName)

	for {
		startIdx := strings.Index(contentStr, startMarker)
		endIdx := strings.Index(contentStr, endMarker)
		if startIdx == -1 || endIdx == -1 || endIdx <= startIdx {
			break
		}
		// Include the end marker and trailing newline
		removeEnd := endIdx + len(endMarker)
		for removeEnd < len(contentStr) && contentStr[removeEnd] == '\n' {
			removeEnd++
		}
		// Also remove leading newline if present
		removeStart := startIdx
		if removeStart > 0 && contentStr[removeStart-1] == '\n' {
			removeStart--
		}
		contentStr = contentStr[:removeStart] + contentStr[removeEnd:]
	}

	// Append new entry
	newContent := contentStr + entry
	newContentBytes := []byte(newContent)

	// Write atomically using temp file + rename (prevents race conditions and partial writes)
	tmpFile, err := os.CreateTemp(filepath.Dir(sshConfigPath), ".ssh-config-*.tmp")
	if err != nil {
		return nil, fmt.Errorf("failed to create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()

	// Write to temp file
	if _, err := tmpFile.Write(newContentBytes); err != nil {
		tmpFile.Close()
		os.Remove(tmpPath)
		return nil, fmt.Errorf("failed to write temp SSH config: %w", err)
	}

	// Sync to disk
	if err := tmpFile.Sync(); err != nil {
		tmpFile.Close()
		os.Remove(tmpPath)
		return nil, fmt.Errorf("failed to sync temp SSH config: %w", err)
	}

	if err := tmpFile.Close(); err != nil {
		os.Remove(tmpPath)
		return nil, fmt.Errorf("failed to close temp SSH config: %w", err)
	}

	// Set correct permissions before rename
	if err := os.Chmod(tmpPath, 0o600); err != nil {
		os.Remove(tmpPath)
		return nil, fmt.Errorf("failed to set temp file permissions: %w", err)
	}

	// Atomically replace the config file
	if err := os.Rename(tmpPath, sshConfigPath); err != nil {
		os.Remove(tmpPath)
		return nil, fmt.Errorf("failed to replace SSH config: %w", err)
	}

	log.Printf("✅ SSH config entry added: %s", hostName)
	log.Printf("   Connect with: ssh %s", hostName)
	log.Printf("   Or use VSCode Remote-SSH to connect to '%s'", hostName)

	return &SSHEntry{
		HostName: hostName,
		KeyPath:  keyPath,
	}, nil
}

// RemoveSSHConfigEntry removes the temporary SSH config entry and cleans up key files
func RemoveSSHConfigEntry(entry *SSHEntry) {
	if entry == nil || entry.HostName == "" {
		return
	}

	// Clean up SSH key files if they were created by AddSSHConfigEntry
	if entry.KeyPath != "" {
		if err := os.Remove(entry.KeyPath); err != nil && !os.IsNotExist(err) {
			log.Printf("Warning: failed to remove SSH private key %s: %v", entry.KeyPath, err)
		}
		pubKeyPath := entry.KeyPath + ".pub"
		if err := os.Remove(pubKeyPath); err != nil && !os.IsNotExist(err) {
			log.Printf("Warning: failed to remove SSH public key %s: %v", pubKeyPath, err)
		}
	}

	home, err := os.UserHomeDir()
	if err != nil {
		log.Printf("Warning: failed to get home directory for SSH cleanup: %v", err)
		return
	}

	sshConfigPath := filepath.Join(home, ".ssh", "config")

	// Validate hostname to prevent injection
	if !isValidHostName(entry.HostName) {
		log.Printf("Warning: invalid hostname for cleanup: %s", entry.HostName)
		return
	}

	// Check if file exists and is not a symlink
	if info, err := os.Lstat(sshConfigPath); err != nil {
		log.Printf("Warning: SSH config file not found for cleanup: %v", err)
		return
	} else if info.Mode()&os.ModeSymlink != 0 {
		log.Printf("Warning: SSH config is a symlink, skipping cleanup for security")
		return
	}

	content, err := os.ReadFile(sshConfigPath)
	if err != nil {
		log.Printf("Warning: failed to read SSH config for cleanup: %v", err)
		return
	}

	// Remove the entry between markers
	startMarker := fmt.Sprintf("# >>> openbridge-vm-auto-config [%s] >>>", entry.HostName)
	endMarker := fmt.Sprintf("# <<< openbridge-vm-auto-config [%s] <<<", entry.HostName)

	contentStr := string(content)
	startIdx := strings.Index(contentStr, startMarker)
	endIdx := strings.LastIndex(contentStr, endMarker)

	if startIdx != -1 && endIdx != -1 && endIdx > startIdx {
		// Include the end marker and trailing newline
		endIdx = endIdx + len(endMarker)
		for endIdx < len(contentStr) && contentStr[endIdx] == '\n' {
			endIdx++
		}

		newContent := contentStr[:startIdx] + contentStr[endIdx:]
		newContentBytes := []byte(newContent)

		// Write atomically
		tmpFile, err := os.CreateTemp(filepath.Dir(sshConfigPath), ".ssh-config-*.tmp")
		if err != nil {
			log.Printf("Warning: failed to create temp file for cleanup: %v", err)
			return
		}
		tmpPath := tmpFile.Name()

		if _, err := tmpFile.Write(newContentBytes); err != nil {
			tmpFile.Close()
			os.Remove(tmpPath)
			log.Printf("Warning: failed to write temp SSH config for cleanup: %v", err)
			return
		}

		if err := tmpFile.Sync(); err != nil {
			tmpFile.Close()
			os.Remove(tmpPath)
			log.Printf("Warning: failed to sync temp SSH config for cleanup: %v", err)
			return
		}

		if err := tmpFile.Close(); err != nil {
			os.Remove(tmpPath)
			log.Printf("Warning: failed to close temp SSH config for cleanup: %v", err)
			return
		}

		if err := os.Chmod(tmpPath, 0o600); err != nil {
			os.Remove(tmpPath)
			log.Printf("Warning: failed to set temp file permissions for cleanup: %v", err)
			return
		}

		if err := os.Rename(tmpPath, sshConfigPath); err != nil {
			os.Remove(tmpPath)
			log.Printf("Warning: failed to replace SSH config during cleanup: %v", err)
		} else {
			log.Printf("✅ SSH config entry removed: %s", entry.HostName)
		}
	}
}

// generateRandomSuffix generates a short random hex string
func generateRandomSuffix() string {
	b := make([]byte, 4)
	_, err := rand.Read(b)
	if err != nil {
		// Fallback: use current time if crypto/rand fails (shouldn't happen in practice)
		// This is not cryptographically secure but acceptable for non-security-critical use
		log.Printf("Warning: crypto/rand failed, using fallback: %v", err)
		// Return a fixed fallback pattern - caller should retry if this happens
		return "fallback"
	}
	return hex.EncodeToString(b)
}

// validateSSHTarget validates that the SSH host and port are in a safe format.
func validateSSHTarget(host string, port int) error {
	if host == "" {
		return fmt.Errorf("host is empty")
	}
	if strings.ContainsAny(host, "\n\r\t") {
		return fmt.Errorf("host contains invalid characters")
	}
	if len(host) > 255 {
		return fmt.Errorf("host is too long")
	}
	if port <= 0 || port > 65535 {
		return fmt.Errorf("port %d is out of range", port)
	}
	return nil
}

// isValidHostName validates that the hostname only contains safe characters
func isValidHostName(hostName string) bool {
	if hostName == "" || len(hostName) > 255 {
		return false
	}
	for _, r := range hostName {
		if !strings.ContainsRune(validHostNameChars, r) {
			return false
		}
	}
	return true
}
