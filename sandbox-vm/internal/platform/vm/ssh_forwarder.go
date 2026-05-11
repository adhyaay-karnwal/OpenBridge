package vm

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"sync"
)

type localPortForwarder struct {
	listener net.Listener
	dial     func() (io.ReadWriteCloser, error)
	done     chan struct{}
	wg       sync.WaitGroup

	activeMu sync.Mutex
	active   map[*forwardConnPair]struct{}
	closing  bool
}

func newLocalPortForwarder(dial func() (io.ReadWriteCloser, error)) (*localPortForwarder, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, fmt.Errorf("listen local forwarder: %w", err)
	}
	fwd := &localPortForwarder{
		listener: listener,
		dial:     dial,
		done:     make(chan struct{}),
		active:   make(map[*forwardConnPair]struct{}),
	}
	go fwd.acceptLoop()
	return fwd, nil
}

func (f *localPortForwarder) Port() int {
	addr, _ := f.listener.Addr().(*net.TCPAddr)
	if addr == nil {
		return 0
	}
	return addr.Port
}

func (f *localPortForwarder) Close() error {
	f.activeMu.Lock()
	f.closing = true
	pairs := make([]*forwardConnPair, 0, len(f.active))
	for pair := range f.active {
		pairs = append(pairs, pair)
	}
	f.activeMu.Unlock()

	err := f.listener.Close()
	for _, pair := range pairs {
		pair.Close()
	}
	<-f.done
	f.wg.Wait()
	return err
}

func (f *localPortForwarder) acceptLoop() {
	defer close(f.done)
	for {
		clientConn, err := f.listener.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			log.Printf("local SSH forwarder accept failed: %v", err)
			continue
		}
		f.wg.Add(1)
		go func() {
			defer f.wg.Done()
			f.handleConn(clientConn)
		}()
	}
}

func (f *localPortForwarder) handleConn(clientConn net.Conn) {
	pair := newForwardConnPair(clientConn)
	if !f.registerPair(pair) {
		pair.Close()
		return
	}
	defer f.unregisterPair(pair)

	type dialResult struct {
		conn io.ReadWriteCloser
		err  error
	}

	dialResultCh := make(chan dialResult, 1)
	go func() {
		remoteConn, err := f.dial()
		select {
		case dialResultCh <- dialResult{conn: remoteConn, err: err}:
		case <-pair.Done():
			if remoteConn != nil {
				_ = remoteConn.Close()
			}
		}
	}()

	var remoteConn io.ReadWriteCloser
	select {
	case <-pair.Done():
		return
	case result := <-dialResultCh:
		if result.err != nil {
			pair.Close()
			return
		}
		remoteConn = result.conn
	}
	pair.SetRemote(remoteConn)

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		_, _ = io.Copy(remoteConn, clientConn)
		pair.Close()
	}()

	go func() {
		defer wg.Done()
		_, _ = io.Copy(clientConn, remoteConn)
		pair.Close()
	}()

	wg.Wait()
}

func (f *localPortForwarder) registerPair(pair *forwardConnPair) bool {
	f.activeMu.Lock()
	defer f.activeMu.Unlock()
	if f.closing {
		return false
	}
	f.active[pair] = struct{}{}
	return true
}

func (f *localPortForwarder) unregisterPair(pair *forwardConnPair) {
	f.activeMu.Lock()
	defer f.activeMu.Unlock()
	delete(f.active, pair)
}

type forwardConnPair struct {
	mu     sync.Mutex
	client net.Conn
	remote io.ReadWriteCloser
	closed bool
	done   chan struct{}
	once   sync.Once
}

func newForwardConnPair(client net.Conn) *forwardConnPair {
	return &forwardConnPair{
		client: client,
		done:   make(chan struct{}),
	}
}

func (p *forwardConnPair) SetRemote(remote io.ReadWriteCloser) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.closed {
		if remote != nil {
			_ = remote.Close()
		}
		return
	}
	p.remote = remote
}

func (p *forwardConnPair) Done() <-chan struct{} {
	if p == nil {
		return nil
	}
	return p.done
}

func (p *forwardConnPair) Close() {
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return
	}
	p.closed = true
	client := p.client
	remote := p.remote
	p.client = nil
	p.remote = nil
	p.mu.Unlock()

	p.once.Do(func() {
		close(p.done)
	})

	if client != nil {
		_ = client.Close()
	}
	if remote != nil {
		_ = remote.Close()
	}
}

// EnsureLocalSSHForwarder returns a localhost endpoint that proxies to VM SSH over vsock.
func (m *Manager) EnsureLocalSSHForwarder() (host string, port int, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if !m.isRunning {
		return "", 0, fmt.Errorf("VM is not running")
	}
	if m.sshForwarder != nil {
		return "127.0.0.1", m.sshForwarder.Port(), nil
	}

	forwarder, err := newLocalPortForwarder(func() (io.ReadWriteCloser, error) {
		return m.VsockConnect(uint32(m.config.SSHPort))
	})
	if err != nil {
		return "", 0, err
	}
	m.sshForwarder = forwarder
	return "127.0.0.1", m.sshForwarder.Port(), nil
}
