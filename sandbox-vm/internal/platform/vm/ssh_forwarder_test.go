package vm

import (
	"errors"
	"io"
	"net"
	"strconv"
	"testing"
	"time"
)

func TestLocalPortForwarderCloseClosesActiveConnections(t *testing.T) {
	acceptedRemote := make(chan net.Conn, 1)

	forwarder, err := newLocalPortForwarder(func() (io.ReadWriteCloser, error) {
		serverConn, forwarderConn := net.Pipe()
		acceptedRemote <- serverConn
		return forwarderConn, nil
	})
	if err != nil {
		t.Fatalf("newLocalPortForwarder: %v", err)
	}

	clientConn, err := net.Dial("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(forwarder.Port())))
	if err != nil {
		t.Fatalf("dial forwarder: %v", err)
	}
	defer clientConn.Close()

	var remoteConn net.Conn
	select {
	case remoteConn = <-acceptedRemote:
	case <-time.After(2 * time.Second):
		t.Fatal("forwarder did not accept remote connection")
	}
	defer remoteConn.Close()

	if err := forwarder.Close(); err != nil {
		t.Fatalf("close forwarder: %v", err)
	}

	assertEventuallyClosed(t, clientConn, "client")
	assertEventuallyClosed(t, remoteConn, "remote")
}

func TestLocalPortForwarderCloseReturnsWhenDialIsStalled(t *testing.T) {
	dialStarted := make(chan struct{})
	releaseDial := make(chan struct{})

	forwarder, err := newLocalPortForwarder(func() (io.ReadWriteCloser, error) {
		close(dialStarted)
		<-releaseDial
		return nil, errors.New("dial cancelled by test")
	})
	if err != nil {
		t.Fatalf("newLocalPortForwarder: %v", err)
	}

	clientConn, err := net.Dial("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(forwarder.Port())))
	if err != nil {
		t.Fatalf("dial forwarder: %v", err)
	}
	defer clientConn.Close()

	select {
	case <-dialStarted:
	case <-time.After(2 * time.Second):
		t.Fatal("forwarder did not start upstream dial")
	}

	closeDone := make(chan error, 1)
	go func() {
		closeDone <- forwarder.Close()
	}()

	select {
	case err := <-closeDone:
		if err != nil && !errors.Is(err, net.ErrClosed) {
			t.Fatalf("close forwarder: %v", err)
		}
	case <-time.After(200 * time.Millisecond):
		t.Fatal("forwarder close should not block on a stalled upstream dial")
	}

	assertEventuallyClosed(t, clientConn, "client")
	close(releaseDial)
}

func assertEventuallyClosed(t *testing.T, conn net.Conn, label string) {
	t.Helper()

	buf := make([]byte, 1)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if err := conn.SetReadDeadline(time.Now().Add(50 * time.Millisecond)); err != nil {
			return
		}
		if _, err := conn.Read(buf); err != nil {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("%s connection should be closed when forwarder shuts down", label)
}
