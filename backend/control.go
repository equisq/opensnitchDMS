package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"strings"

	pb "opensnitchdms/protocol"
)

// The control socket is how the QML plugin talks to this process: one JSON
// object per line. Requests carry an id and get one reply with the same id;
// events carry no id.
//
//	-> {"id":1,"method":"state","params":{}}
//	<- {"id":1,"result":{...}}      or      {"id":1,"error":"why"}
//	<- {"event":"prompt","data":{...}}

type request struct {
	ID     int64           `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
}

func serveControl(h *Hub, path string) (net.Listener, error) {
	if c, err := net.Dial("unix", path); err == nil {
		c.Close()
		return nil, fmt.Errorf("another instance is already listening on %s", path)
	}
	_ = os.Remove(path)
	l, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	_ = os.Chmod(path, 0o600)
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go handleClient(h, conn)
		}
	}()
	return l, nil
}

func handleClient(h *Hub, conn net.Conn) {
	c := newClient()
	h.addClient(c)
	defer func() { h.removeClient(c); conn.Close() }()

	go func() {
		w := bufio.NewWriter(conn)
		for {
			select {
			case b := <-c.out:
				if _, err := w.Write(b); err != nil {
					c.kill()
					return
				}
				// drain what is already queued before flushing
				for more := true; more; {
					select {
					case b := <-c.out:
						if _, err := w.Write(b); err != nil {
							c.kill()
							return
						}
					default:
						more = false
					}
				}
				if err := w.Flush(); err != nil {
					c.kill()
					return
				}
			case <-c.dead:
				conn.Close()
				return
			}
		}
	}()

	sc := bufio.NewScanner(conn)
	sc.Buffer(make([]byte, 64*1024), 8*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var req request
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			log.Printf("control: unreadable line: %v", err)
			continue
		}
		go func() {
			res, err := dispatch(h, c, &req)
			m := map[string]any{"id": req.ID}
			if err != nil {
				m["error"] = err.Error()
			} else {
				m["result"] = res
			}
			b, merr := json.Marshal(m)
			if merr != nil {
				b, _ = json.Marshal(map[string]any{"id": req.ID, "error": merr.Error()})
			}
			c.send(append(b, '\n'))
		}()
	}
}

type nodeParams struct {
	Node    string `json:"node"`
	Enabled bool   `json:"enabled"`
	Name    string `json:"name"`
}

func dispatch(h *Hub, c *client, req *request) (any, error) {
	var np nodeParams
	if len(req.Params) > 0 {
		_ = json.Unmarshal(req.Params, &np)
	}
	switch req.Method {
	case "hello":
		var p struct {
			Prompts bool `json:"prompts"`
		}
		_ = json.Unmarshal(req.Params, &p)
		h.mu.Lock()
		c.prompts = p.Prompts
		h.mu.Unlock()
		return h.Snapshot(), nil

	case "state":
		return h.Snapshot(), nil

	case "subscribe", "unsubscribe":
		h.mu.Lock()
		c.subbed = req.Method == "subscribe"
		h.mu.Unlock()
		return map[string]any{"ok": true}, nil

	case "events":
		var p struct {
			Limit int `json:"limit"`
		}
		_ = json.Unmarshal(req.Params, &p)
		return map[string]any{"events": h.recentEvents(p.Limit)}, nil

	case "events.clear":
		h.clearEvents()
		return map[string]any{"ok": true}, nil

	case "interception.set":
		t := pb.Action_DISABLE_INTERCEPTION
		if np.Enabled {
			t = pb.Action_ENABLE_INTERCEPTION
		}
		n, err := h.notify(np.Node, t, "", nil, nil)
		if err != nil {
			return nil, err
		}
		h.mu.Lock()
		n.IsFirewallRunning = np.Enabled
		h.nodeUpdated(n)
		h.mu.Unlock()
		return map[string]any{"enabled": np.Enabled}, nil

	case "firewall.set":
		h.mu.Lock()
		n, err := h.resolveNodeLocked(np.Node)
		var fw *pb.SysFirewall
		if err == nil {
			if n.SysFW == nil {
				err = errors.New("the daemon did not report a system firewall")
			} else {
				fw = &pb.SysFirewall{Enabled: np.Enabled, Version: n.SysFW.Version, SystemRules: n.SysFW.SystemRules}
			}
		}
		h.mu.Unlock()
		if err != nil {
			return nil, err
		}
		if _, err := h.notify(n.Key, pb.Action_RELOAD_FW_RULES, "", nil, fw); err != nil {
			return nil, err
		}
		h.mu.Lock()
		n.SysFW = fw
		h.nodeUpdated(n)
		h.mu.Unlock()
		return map[string]any{"enabled": np.Enabled}, nil

	case "firewall.policy":
		var p struct {
			Node   string `json:"node"`
			Hook   string `json:"hook"`
			Policy string `json:"policy"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return nil, err
		}
		h.mu.Lock()
		n, err := h.resolveNodeLocked(p.Node)
		var fw *pb.SysFirewall
		if err == nil {
			if n.SysFW == nil {
				err = errors.New("the daemon did not report a system firewall")
			} else {
				fw, err = withPolicy(n.SysFW, p.Hook, p.Policy)
			}
		}
		h.mu.Unlock()
		if err != nil {
			return nil, err
		}
		if _, err := h.notify(n.Key, pb.Action_RELOAD_FW_RULES, "", nil, fw); err != nil {
			return nil, err
		}
		h.mu.Lock()
		n.SysFW = fw
		h.nodeUpdated(n)
		h.mu.Unlock()
		return map[string]any{"ok": true}, nil

	case "config.set":
		var p struct {
			Node    string         `json:"node"`
			Changes map[string]any `json:"changes"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return nil, err
		}
		return nil, setConfig(h, p.Node, p.Changes)

	case "rule.set":
		var p struct {
			Node string         `json:"node"`
			Rule map[string]any `json:"rule"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return nil, err
		}
		r, err := ruleFromJSON(p.Rule)
		if err != nil {
			return nil, err
		}
		n, err := h.notify(p.Node, pb.Action_CHANGE_RULE, "", []*pb.Rule{r}, nil)
		if err != nil {
			return nil, err
		}
		h.mu.Lock()
		h.putRuleLocked(n, r)
		h.nodeUpdated(n)
		h.mu.Unlock()
		return map[string]any{"name": r.Name}, nil

	case "rule.enable", "rule.disable", "rule.delete":
		if np.Name == "" {
			return nil, errors.New("missing rule name")
		}
		t := map[string]pb.Action{"rule.enable": pb.Action_ENABLE_RULE, "rule.disable": pb.Action_DISABLE_RULE, "rule.delete": pb.Action_DELETE_RULE}[req.Method]
		n, err := h.notify(np.Node, t, "", []*pb.Rule{{Name: np.Name}}, nil)
		if err != nil {
			return nil, err
		}
		h.mu.Lock()
		switch req.Method {
		case "rule.delete":
			h.removeRuleLocked(n, np.Name)
		default:
			for _, r := range n.Rules {
				if r.Name == np.Name {
					r.Enabled = req.Method == "rule.enable"
				}
			}
		}
		h.nodeUpdated(n)
		h.mu.Unlock()
		return map[string]any{"ok": true}, nil

	case "settings.set":
		var p struct {
			Changes json.RawMessage `json:"changes"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return nil, err
		}
		before := h.settings.Get()
		after, err := h.settings.Update(p.Changes)
		if err != nil {
			return nil, err
		}
		h.mu.Lock()
		h.emitLocked("settings", after, false)
		h.mu.Unlock()
		if before.DefaultAction != after.DefaultAction {
			go pushDefaultAction(h, after.DefaultAction)
		}
		return after, nil

	case "prompt.answer":
		var p struct {
			ID     string `json:"id"`
			Answer Answer `json:"answer"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return nil, err
		}
		if err := h.answerPrompt(p.ID, p.Answer); err != nil {
			return nil, err
		}
		return map[string]any{"ok": true}, nil
	}
	return nil, fmt.Errorf("unknown method %q", req.Method)
}

// setConfig changes the daemon's config. The daemon takes the whole document,
// so the current one is edited and sent back; dotted keys reach into objects
// ("FwOptions.QueueBypass").
func setConfig(h *Hub, nodeKey string, changes map[string]any) error {
	h.mu.Lock()
	n, err := h.resolveNodeLocked(nodeKey)
	if err != nil {
		h.mu.Unlock()
		return err
	}
	var cfg map[string]any
	if err := json.Unmarshal([]byte(n.Config), &cfg); err != nil || cfg == nil {
		h.mu.Unlock()
		return errors.New("the daemon's configuration is unknown")
	}
	key := n.Key
	h.mu.Unlock()

	for k, v := range changes {
		parts := strings.Split(k, ".")
		m := cfg
		for _, p := range parts[:len(parts)-1] {
			next, ok := m[p].(map[string]any)
			if !ok {
				next = map[string]any{}
				m[p] = next
			}
			m = next
		}
		m[parts[len(parts)-1]] = v
	}
	b, _ := json.MarshalIndent(cfg, "", "    ")
	if _, err := h.notify(key, pb.Action_CHANGE_CONFIG, string(b), nil, nil); err != nil {
		return err
	}
	h.mu.Lock()
	n.Config = string(b)
	h.nodeUpdated(n)
	h.mu.Unlock()
	return nil
}

func pushDefaultAction(h *Hub, action string) {
	if action != actionAllow {
		action = actionDeny
	}
	h.mu.Lock()
	var keys []string
	for k, n := range h.nodes {
		if n.Online {
			keys = append(keys, k)
		}
	}
	h.mu.Unlock()
	for _, k := range keys {
		if err := setConfig(h, k, map[string]any{"DefaultAction": action}); err != nil {
			log.Printf("could not set the daemon's default action on %s: %v", k, err)
		}
	}
}
