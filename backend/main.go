// opensnitch-dmsd is the OpenSnitch UI for DankMaterialShell, minus the pixels:
// it is the gRPC server the (unmodified) opensnitch daemon connects to, and it
// hands what it learns to the QML plugin over a local socket.
package main

import (
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"google.golang.org/grpc"

	pb "opensnitchdms/protocol"
)

const uiVersion = "1.0.0"

func defaultState() string {
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return filepath.Join(d, "DankMaterialShell", "opensnitch")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state", "DankMaterialShell", "opensnitch")
}

func defaultControl() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return filepath.Join(d, "dms-opensnitch.sock")
	}
	return "/tmp/dms-opensnitch.sock"
}

// listenerFor parses the address the daemon is configured with
// (Server.Address in default-config.json): "unix:///tmp/osui.sock" or host:port.
func listenerFor(addr string) (net.Listener, error) {
	if p, ok := strings.CutPrefix(addr, "unix://"); ok {
		if c, err := net.Dial("unix", p); err == nil {
			c.Close()
			return nil, errAddrInUse(addr)
		}
		_ = os.Remove(p)
		l, err := net.Listen("unix", p)
		if err != nil {
			return nil, err
		}
		// the daemon runs as root and does not need this, but a user-owned
		// socket in /tmp should not be open to everybody
		_ = os.Chmod(p, 0o666)
		return l, nil
	}
	return net.Listen("tcp", addr)
}

type errAddrInUse string

func (e errAddrInUse) Error() string {
	return "address already in use: " + string(e) + " (is the Qt opensnitch-ui running?)"
}

func main() {
	listen := flag.String("listen", "unix:///tmp/osui.sock", "address the opensnitch daemon connects to (Server.Address)")
	control := flag.String("socket", defaultControl(), "control socket for the DMS plugin")
	state := flag.String("state", defaultState(), "directory for the UI's own settings")
	flag.Parse()
	log.SetFlags(log.Ltime)
	log.SetOutput(os.Stderr)

	hub := NewHub(loadSettings(*state))

	cl, err := serveControl(hub, *control)
	if err != nil {
		log.Fatalf("ERROR control socket: %v", err)
	}
	defer os.Remove(*control)
	defer cl.Close()

	l, err := listenerFor(*listen)
	if err != nil {
		log.Fatalf("ERROR listening on %s: %v", *listen, err)
	}
	srv := grpc.NewServer()
	pb.RegisterUIServer(srv, &UIServer{hub: hub})
	log.Printf("opensnitch-dmsd %s: daemon at %s, plugin at %s", uiVersion, *listen, *control)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sig
		srv.Stop()
	}()
	if err := srv.Serve(l); err != nil {
		log.Fatalf("ERROR serving: %v", err)
	}
}
