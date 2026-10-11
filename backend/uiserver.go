package main

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"strings"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"

	pb "opensnitchdms/protocol"
)

// UIServer is the gRPC service the opensnitch daemon connects to. It is the
// counterpart of ui/opensnitch/service.py.
type UIServer struct {
	hub *Hub
}

func nodeKeyFromCtx(ctx context.Context) (key string, local bool) {
	p, ok := peer.FromContext(ctx)
	if !ok || p.Addr == nil {
		return "unix:/local", true
	}
	if p.Addr.Network() == "unix" {
		return "unix:/local", true
	}
	host, _, err := net.SplitHostPort(p.Addr.String())
	if err != nil {
		host = p.Addr.String()
	}
	ip := net.ParseIP(host)
	return "ip:" + host, ip != nil && ip.IsLoopback()
}

func (s *UIServer) Ping(ctx context.Context, req *pb.PingRequest) (*pb.PingReply, error) {
	key, _ := nodeKeyFromCtx(ctx)
	if n := s.hub.getNode(key); n != nil && req.Stats != nil {
		s.hub.updateStats(n, req.Stats)
	}
	return &pb.PingReply{Id: req.Id}, nil
}

// Subscribe: the daemon announces itself and gets back the config it should run
// with. As the Qt UI does, the user's default action overrides the daemon's for
// as long as we are connected.
func (s *UIServer) Subscribe(ctx context.Context, cfg *pb.ClientConfig) (*pb.ClientConfig, error) {
	key, local := nodeKeyFromCtx(ctx)
	log.Printf("daemon subscribed: %s (%s %s)", key, cfg.Name, cfg.Version)
	s.hub.subscribeNode(key, cfg.Name, cfg.Version, local, cfg)

	out := &pb.ClientConfig{
		Id: cfg.Id, Name: cfg.Name, Version: cfg.Version, IsFirewallRunning: cfg.IsFirewallRunning,
		Config: cfg.Config, LogLevel: cfg.LogLevel, Rules: cfg.Rules, SystemFirewall: cfg.SystemFirewall,
	}
	var c map[string]any
	if err := json.Unmarshal([]byte(cfg.Config), &c); err == nil {
		if s.hub.settings.Get().DefaultAction == actionAllow {
			c["DefaultAction"] = actionAllow
		} else {
			c["DefaultAction"] = actionDeny
		}
		if b, err := json.Marshal(c); err == nil {
			out.Config = string(b)
		}
	}
	return out, nil
}

func (s *UIServer) PostAlert(ctx context.Context, a *pb.Alert) (*pb.MsgResponse, error) {
	key, _ := nodeKeyFromCtx(ctx)
	s.hub.addAlert(s.hub.getNode(key), a)
	return &pb.MsgResponse{Id: 0}, nil
}

func (s *UIServer) Notifications(stream pb.UI_NotificationsServer) error {
	key, _ := nodeKeyFromCtx(stream.Context())
	h := s.hub
	h.mu.Lock()
	n := h.nodes[key]
	if n == nil {
		h.mu.Unlock()
		return status.Error(codes.FailedPrecondition, "subscribe first")
	}
	out := make(chan *pb.Notification, 32)
	n.out = out
	n.Online = true
	h.nodeUpdated(n)
	h.mu.Unlock()
	log.Printf("notifications channel open: %s", key)

	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			r, err := stream.Recv()
			if err != nil {
				return
			}
			if r.Id != 0 {
				h.deliverReply(n, r)
			}
		}
	}()
	defer h.nodeOffline(n, out)

	for {
		select {
		case m := <-out:
			if err := stream.Send(m); err != nil {
				return err
			}
		case <-done:
			log.Printf("notifications channel closed: %s", key)
			return nil
		case <-stream.Context().Done():
			return nil
		}
	}
}

func (s *UIServer) AskRule(ctx context.Context, c *pb.Connection) (*pb.Rule, error) {
	h := s.hub
	set := h.settings.Get()
	key, local := nodeKeyFromCtx(ctx)
	if set.DisablePopups || !h.hasPromptUI() {
		// Nobody to ask: the daemon falls back to its default action.
		return nil, status.Error(codes.Unavailable, "no prompt available")
	}
	n := h.getNode(key)
	if n == nil {
		return nil, status.Error(codes.FailedPrecondition, "unknown node")
	}

	opts := buildOptions(c, local)
	app := appInfoFor(c.ProcessPath)
	if app.Name == "" {
		app.Name = "Outgoing connection"
	}
	defs := set.defaultsFor(opts, c, app.Name)

	var ans Answer
	var pid string
	if set.Timeout == 0 {
		ans = defs.answer() // zero timeout: decide at once, show nothing
	} else {
		p := &Prompt{NodeKey: key, Conn: c, Local: local, Hostname: n.Name, App: app, Opts: opts,
			Defaults: defs, Timeout: set.Timeout, Created: time.Now()}
		h.addPrompt(p)
		pid = p.ID
		select {
		case ans = <-p.ch:
			h.finishPrompt(pid, "answered")
		case <-time.After(time.Duration(set.Timeout)*time.Second + promptSlack):
			// The UI should have answered when its countdown ended; if it
			// could not, the default still has to be applied.
			ans = defs.answer()
			h.finishPrompt(pid, "timeout")
		case <-ctx.Done():
			h.finishPrompt(pid, "cancelled")
			return nil, ctx.Err()
		}
	}

	h.mu.Lock()
	rule, err := buildRule(c, opts, ans, n.Rules)
	if err != nil && ans != defs.answer() {
		rule, err = buildRule(c, opts, defs.answer(), n.Rules)
	}
	if err != nil {
		h.mu.Unlock()
		log.Printf("could not build a rule: %v", err)
		return nil, status.Error(codes.Internal, err.Error())
	}
	if rule.Duration != "once" {
		h.putRuleLocked(n, rule)
		h.nodeUpdated(n)
	}
	h.mu.Unlock()
	if strings.TrimSpace(rule.Name) == "" {
		return nil, status.Error(codes.Internal, "empty rule name")
	}
	return rule, nil
}
