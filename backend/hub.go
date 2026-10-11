package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	pb "opensnitchdms/protocol"
)

const (
	maxEvents       = 1000
	maxAlerts       = 100
	notifyTimeout   = 12 * time.Second
	promptSlack     = 10 * time.Second
	statsEmitPeriod = time.Second
)

// Node is one connected daemon (usually the only one, on this machine).
type Node struct {
	Key     string
	Name    string
	Version string
	Local   bool
	Online  bool

	Config            string // the daemon's config, as JSON
	IsFirewallRunning bool   // i.e. interception is on
	SysFW             *pb.SysFirewall
	Rules             []*pb.Rule
	Stats             *pb.Statistics
	LastSeen          time.Time

	out     chan *pb.Notification
	waiters map[uint64]chan *pb.NotificationReply
	expiry  map[string]*time.Timer
	nextID  uint64
}

// Prompt is a connection waiting for the user's decision.
type Prompt struct {
	ID       string
	NodeKey  string
	Conn     *pb.Connection
	Local    bool
	Hostname string
	App      AppInfo
	Opts     Options
	Defaults Defaults
	Timeout  int
	Created  time.Time
	ch       chan Answer
}

type Alert struct {
	ID       uint64 `json:"id"`
	Node     string `json:"node"`
	Time     int64  `json:"time"`
	Type     string `json:"type"`
	Priority string `json:"priority"`
	What     string `json:"what"`
	Text     string `json:"text"`
}

type client struct {
	out     chan []byte
	dead    chan struct{}
	once    sync.Once
	prompts bool // can show prompts
	subbed  bool // wants stats/events streamed
}

func newClient() *client {
	return &client{out: make(chan []byte, 256), dead: make(chan struct{})}
}

func (c *client) kill() { c.once.Do(func() { close(c.dead) }) }

// send queues a line for the client; false if it is gone.
func (c *client) send(b []byte) bool {
	select {
	case c.out <- b:
		return true
	case <-c.dead:
		return false
	}
}

type Hub struct {
	mu       sync.Mutex
	nodes    map[string]*Node
	order    []string
	prompts  map[string]*Prompt
	promptNo int
	events   []map[string]any
	seen     map[string]struct{}
	seenQ    []string
	alerts   []Alert
	clients  map[*client]struct{}
	lastStat time.Time

	settings *SettingsStore
}

func NewHub(s *SettingsStore) *Hub {
	return &Hub{
		nodes:    map[string]*Node{},
		prompts:  map[string]*Prompt{},
		seen:     map[string]struct{}{},
		clients:  map[*client]struct{}{},
		settings: s,
	}
}

// ---- clients and events ----------------------------------------------------

func (h *Hub) addClient(c *client) {
	h.mu.Lock()
	h.clients[c] = struct{}{}
	h.mu.Unlock()
}

func (h *Hub) removeClient(c *client) {
	h.mu.Lock()
	delete(h.clients, c)
	h.mu.Unlock()
	c.kill()
}

func (h *Hub) hasPromptUI() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if c.prompts {
			return true
		}
	}
	return false
}

// emitLocked sends an event to every client, or only the subscribed ones.
func (h *Hub) emitLocked(event string, data any, onlySubscribed bool) {
	b, err := json.Marshal(map[string]any{"event": event, "data": data})
	if err != nil {
		return
	}
	b = append(b, '\n')
	for c := range h.clients {
		if onlySubscribed && !c.subbed {
			continue
		}
		select {
		case c.out <- b:
		default:
			// a client that cannot keep up is dropped; it will reconnect and resync
			c.kill()
			delete(h.clients, c)
		}
	}
}

// ---- JSON views ------------------------------------------------------------

func opToJSON(o *pb.Operator) map[string]any {
	if o == nil {
		return map[string]any{"type": "", "operand": "", "data": "", "sensitive": false, "list": []any{}}
	}
	l := make([]any, 0, len(o.List))
	for _, x := range o.List {
		l = append(l, opToJSON(x))
	}
	return map[string]any{"type": o.Type, "operand": o.Operand, "data": o.Data, "sensitive": o.Sensitive, "list": l}
}

func ruleToJSON(r *pb.Rule) map[string]any {
	m := map[string]any{
		"name": r.Name, "description": r.Description, "enabled": r.Enabled,
		"precedence": r.Precedence, "nolog": r.Nolog, "action": r.Action,
		"duration": r.Duration, "created": r.Created, "operator": opToJSON(r.Operator),
	}
	if d, err := time.ParseDuration(r.Duration); err == nil && r.Created > 0 {
		m["expires"] = r.Created + int64(d.Seconds())
	}
	return m
}

func opFromJSON(m map[string]any) *pb.Operator {
	if m == nil {
		return nil
	}
	o := &pb.Operator{}
	o.Type, _ = m["type"].(string)
	o.Operand, _ = m["operand"].(string)
	o.Data, _ = m["data"].(string)
	o.Sensitive, _ = m["sensitive"].(bool)
	if l, ok := m["list"].([]any); ok {
		for _, x := range l {
			if mm, ok := x.(map[string]any); ok {
				o.List = append(o.List, opFromJSON(mm))
			}
		}
	}
	return o
}

func ruleFromJSON(m map[string]any) (*pb.Rule, error) {
	r := &pb.Rule{}
	r.Name, _ = m["name"].(string)
	if strings.TrimSpace(r.Name) == "" {
		return nil, errors.New("a rule needs a name")
	}
	r.Description, _ = m["description"].(string)
	r.Enabled, _ = m["enabled"].(bool)
	r.Precedence, _ = m["precedence"].(bool)
	r.Nolog, _ = m["nolog"].(bool)
	r.Action, _ = m["action"].(string)
	r.Duration, _ = m["duration"].(string)
	if r.Duration == "" {
		r.Duration = "always"
	}
	if c, ok := m["created"].(float64); ok {
		r.Created = int64(c)
	} else {
		r.Created = time.Now().Unix()
	}
	om, _ := m["operator"].(map[string]any)
	r.Operator = opFromJSON(om)
	if r.Operator == nil || r.Operator.Operand == "" && r.Operator.Type != typeList {
		return nil, errors.New("a rule needs an operator")
	}
	switch r.Action {
	case "allow", "deny", "reject":
	default:
		return nil, fmt.Errorf("unknown action %q", r.Action)
	}
	// the list type carries its operands in List; keep Data in step for the DB
	if r.Operator.Type == typeList && len(r.Operator.List) > 0 {
		js := make([]map[string]string, 0)
		for _, x := range r.Operator.List {
			js = append(js, map[string]string{"type": x.Type, "operand": x.Operand, "data": x.Data})
		}
		b, _ := json.Marshal(js)
		r.Operator.Data = string(b)
		r.Operator.Operand = typeList
	}
	return r, nil
}

func topN(m map[string]uint64, n int) []map[string]any {
	type kv struct {
		K string
		V uint64
	}
	l := make([]kv, 0, len(m))
	for k, v := range m {
		l = append(l, kv{k, v})
	}
	sort.Slice(l, func(i, j int) bool {
		if l[i].V != l[j].V {
			return l[i].V > l[j].V
		}
		return l[i].K < l[j].K
	})
	if len(l) > n {
		l = l[:n]
	}
	out := make([]map[string]any, 0, len(l))
	for _, x := range l {
		out = append(out, map[string]any{"key": x.K, "count": x.V})
	}
	return out
}

func statsToJSON(s *pb.Statistics) map[string]any {
	if s == nil {
		return nil
	}
	return map[string]any{
		"daemonVersion": s.DaemonVersion, "rules": s.Rules, "uptime": s.Uptime,
		"dnsResponses": s.DnsResponses, "connections": s.Connections, "ignored": s.Ignored,
		"accepted": s.Accepted, "dropped": s.Dropped, "ruleHits": s.RuleHits, "ruleMisses": s.RuleMisses,
		"byProto": topN(s.ByProto, 10), "byAddress": topN(s.ByAddress, 10), "byHost": topN(s.ByHost, 10),
		"byPort": topN(s.ByPort, 10), "byUid": topN(s.ByUid, 10), "byExecutable": topN(s.ByExecutable, 10),
	}
}

func (n *Node) toJSON(withRules bool) map[string]any {
	var cfg any = map[string]any{}
	if n.Config != "" {
		var c map[string]any
		if json.Unmarshal([]byte(n.Config), &c) == nil {
			cfg = c
		}
	}
	m := map[string]any{
		"key": n.Key, "name": n.Name, "version": n.Version, "local": n.Local, "online": n.Online,
		"interception": n.IsFirewallRunning, "config": cfg, "lastSeen": n.LastSeen.Unix(),
		"stats": statsToJSON(n.Stats),
	}
	fw := map[string]any{"known": n.SysFW != nil, "enabled": false, "version": 0, "chains": 0, "rules": 0,
		"policyInput": chainPolicy(n.SysFW, "input"), "policyOutput": chainPolicy(n.SysFW, "output")}
	if n.SysFW != nil {
		fw["enabled"] = n.SysFW.Enabled
		fw["version"] = n.SysFW.Version
		for _, fc := range n.SysFW.SystemRules {
			for _, ch := range fc.Chains {
				fw["chains"] = fw["chains"].(int) + 1
				fw["rules"] = fw["rules"].(int) + len(ch.Rules)
			}
		}
	}
	m["sysFirewall"] = fw
	if withRules {
		rs := make([]any, 0, len(n.Rules))
		for _, r := range n.Rules {
			rs = append(rs, ruleToJSON(r))
		}
		m["rules"] = rs
		m["ruleCount"] = len(rs)
	}
	return m
}

func (p *Prompt) toJSON() map[string]any {
	c := p.Conn
	uname := ""
	if p.Local {
		uname = userLabel(c.UserId)
	}
	md5 := c.ProcessChecksums[operandProcessMD5]
	env := map[string]string{}
	return map[string]any{
		"id": p.ID, "node": p.NodeKey, "local": p.Local, "hostname": p.Hostname,
		"timeout": p.Timeout, "created": p.Created.UnixMilli(),
		"conn": map[string]any{
			"protocol": c.Protocol, "srcIp": c.SrcIp, "srcPort": c.SrcPort, "dstIp": c.DstIp,
			"dstHost": c.DstHost, "dstPort": c.DstPort, "userId": int32(c.UserId), "userLabel": uname,
			"processId": int64(int32(c.ProcessId)), "processPath": c.ProcessPath, "processCwd": c.ProcessCwd,
			"processArgs": c.ProcessArgs, "md5": md5, "env": env,
		},
		"app":       p.App,
		"options":   p.Opts,
		"durations": durationsJSON(),
		"defaults":  p.Defaults,
	}
}

func durationsJSON() []map[string]string {
	out := make([]map[string]string, 0, len(durations))
	for _, d := range durations {
		out = append(out, map[string]string{"id": d.ID, "label": d.Label})
	}
	return out
}

// snapshot is the full state a client gets on connect.
func (h *Hub) snapshotLocked() map[string]any {
	nodes := make([]any, 0, len(h.order))
	for _, k := range h.order {
		if n := h.nodes[k]; n != nil {
			nodes = append(nodes, n.toJSON(true))
		}
	}
	ps := make([]any, 0, len(h.prompts))
	for _, p := range h.prompts {
		ps = append(ps, p.toJSON())
	}
	sort.Slice(ps, func(i, j int) bool {
		return ps[i].(map[string]any)["created"].(int64) < ps[j].(map[string]any)["created"].(int64)
	})
	return map[string]any{
		"nodes": nodes, "prompts": ps, "settings": h.settings.Get(), "durations": durationsJSON(),
		"alerts": append([]Alert{}, h.alerts...), "version": uiVersion,
	}
}

func (h *Hub) Snapshot() map[string]any {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.snapshotLocked()
}

// ---- nodes -----------------------------------------------------------------

func (h *Hub) nodeUpdated(n *Node) {
	h.emitLocked("node", n.toJSON(true), false)
}

func (h *Hub) subscribeNode(key, name, version string, local bool, cfg *pb.ClientConfig) *Node {
	h.mu.Lock()
	defer h.mu.Unlock()
	n := h.nodes[key]
	if n == nil {
		n = &Node{Key: key, waiters: map[uint64]chan *pb.NotificationReply{}, expiry: map[string]*time.Timer{}}
		h.nodes[key] = n
		h.order = append(h.order, key)
	}
	n.Name, n.Version, n.Local = name, version, local
	n.Config = cfg.Config
	n.IsFirewallRunning = cfg.IsFirewallRunning
	n.SysFW = cfg.SystemFirewall
	n.Online = true
	n.LastSeen = time.Now()
	// the daemon is the source of truth for its rules
	for _, t := range n.expiry {
		t.Stop()
	}
	n.expiry = map[string]*time.Timer{}
	n.Rules = append([]*pb.Rule(nil), cfg.Rules...)
	sort.Slice(n.Rules, func(i, j int) bool { return n.Rules[i].Name < n.Rules[j].Name })
	for _, r := range n.Rules {
		h.scheduleExpiryLocked(n, r)
	}
	h.nodeUpdated(n)
	return n
}

func (h *Hub) scheduleExpiryLocked(n *Node, r *pb.Rule) {
	if t := n.expiry[r.Name]; t != nil {
		t.Stop()
		delete(n.expiry, r.Name)
	}
	d, err := time.ParseDuration(r.Duration)
	if err != nil || d <= 0 {
		return
	}
	left := time.Until(time.Unix(r.Created, 0).Add(d))
	if left <= 0 {
		left = time.Second
	}
	name := r.Name
	n.expiry[name] = time.AfterFunc(left, func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		h.removeRuleLocked(n, name)
		h.nodeUpdated(n)
	})
}

func (h *Hub) removeRuleLocked(n *Node, name string) {
	if t := n.expiry[name]; t != nil {
		t.Stop()
		delete(n.expiry, name)
	}
	out := n.Rules[:0]
	for _, r := range n.Rules {
		if r.Name != name {
			out = append(out, r)
		}
	}
	n.Rules = out
}

func (h *Hub) putRuleLocked(n *Node, r *pb.Rule) {
	replaced := false
	for i, x := range n.Rules {
		if x.Name == r.Name {
			n.Rules[i] = r
			replaced = true
		}
	}
	if !replaced {
		n.Rules = append(n.Rules, r)
		sort.Slice(n.Rules, func(i, j int) bool { return n.Rules[i].Name < n.Rules[j].Name })
	}
	h.scheduleExpiryLocked(n, r)
}

func (h *Hub) nodeOffline(n *Node, out chan *pb.Notification) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if n.out != out { // a newer connection already took over
		return
	}
	n.Online = false
	n.out = nil
	for id, w := range n.waiters {
		close(w)
		delete(n.waiters, id)
	}
	h.nodeUpdated(n)
}

func (h *Hub) getNode(key string) *Node {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.nodes[key]
}

// resolveNode picks the node a control request is about; empty means "the only
// one", which is what nearly everybody has.
func (h *Hub) resolveNodeLocked(key string) (*Node, error) {
	if key != "" {
		if n := h.nodes[key]; n != nil {
			return n, nil
		}
		return nil, fmt.Errorf("unknown node %q", key)
	}
	var found *Node
	for _, k := range h.order {
		if n := h.nodes[k]; n != nil && n.Online {
			if found != nil {
				return found, nil // several: the first online one
			}
			found = n
		}
	}
	if found == nil {
		return nil, errors.New("OpenSnitch daemon is not connected")
	}
	return found, nil
}

// notify sends a notification to a node and waits for the daemon's reply.
func (h *Hub) notify(key string, typ pb.Action, data string, rules []*pb.Rule, fw *pb.SysFirewall) (*Node, error) {
	h.mu.Lock()
	n, err := h.resolveNodeLocked(key)
	if err != nil {
		h.mu.Unlock()
		return nil, err
	}
	if !n.Online || n.out == nil {
		h.mu.Unlock()
		return n, errors.New("the daemon is not connected")
	}
	n.nextID++
	id := uint64(time.Now().UnixNano()) + n.nextID
	w := make(chan *pb.NotificationReply, 1)
	n.waiters[id] = w
	out := n.out
	h.mu.Unlock()

	select {
	case out <- &pb.Notification{Id: id, Type: typ, Data: data, Rules: rules, SysFirewall: fw}:
	case <-time.After(notifyTimeout):
		h.dropWaiter(n, id)
		return n, errors.New("timed out sending to the daemon")
	}
	select {
	case rep, ok := <-w:
		h.dropWaiter(n, id)
		if !ok {
			return n, errors.New("the daemon disconnected")
		}
		if rep.Code != pb.NotificationReplyCode_OK {
			if rep.Data == "" {
				return n, errors.New("the daemon refused the change")
			}
			return n, errors.New(rep.Data)
		}
		return n, nil
	case <-time.After(notifyTimeout):
		h.dropWaiter(n, id)
		return n, errors.New("the daemon did not answer")
	}
}

func (h *Hub) dropWaiter(n *Node, id uint64) {
	h.mu.Lock()
	delete(n.waiters, id)
	h.mu.Unlock()
}

func (h *Hub) deliverReply(n *Node, r *pb.NotificationReply) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if w, ok := n.waiters[r.Id]; ok {
		select {
		case w <- r:
		default:
		}
	}
}

// ---- prompts ---------------------------------------------------------------

func (h *Hub) addPrompt(p *Prompt) {
	h.mu.Lock()
	h.promptNo++
	p.ID = fmt.Sprintf("p%d", h.promptNo)
	p.ch = make(chan Answer, 1)
	h.prompts[p.ID] = p
	h.emitLocked("prompt", p.toJSON(), false)
	h.mu.Unlock()
}

func (h *Hub) finishPrompt(id, reason string) {
	h.mu.Lock()
	if _, ok := h.prompts[id]; ok {
		delete(h.prompts, id)
		h.emitLocked("prompt.done", map[string]any{"id": id, "reason": reason}, false)
	}
	h.mu.Unlock()
}

func (h *Hub) answerPrompt(id string, a Answer) error {
	h.mu.Lock()
	p := h.prompts[id]
	h.mu.Unlock()
	if p == nil {
		return errors.New("that prompt is no longer waiting")
	}
	// validate now so the user sees the problem in the prompt
	if _, err := buildRule(p.Conn, p.Opts, a, nil); err != nil {
		return err
	}
	select {
	case p.ch <- a:
	default:
	}
	return nil
}

// ---- events and stats ------------------------------------------------------

func (h *Hub) updateStats(n *Node, st *pb.Statistics) {
	h.mu.Lock()
	defer h.mu.Unlock()
	n.Stats = st
	n.LastSeen = time.Now()
	var fresh []map[string]any
	for _, e := range st.Events {
		if e == nil || e.Connection == nil {
			continue
		}
		c := e.Connection
		key := fmt.Sprintf("%s|%d|%s|%s|%d", n.Key, e.Unixnano, c.ProcessPath, c.DstIp, c.DstPort)
		if _, dup := h.seen[key]; dup {
			continue
		}
		h.seen[key] = struct{}{}
		h.seenQ = append(h.seenQ, key)
		if len(h.seenQ) > maxEvents*2 {
			delete(h.seen, h.seenQ[0])
			h.seenQ = h.seenQ[1:]
		}
		ev := map[string]any{
			"node": n.Key, "time": e.Time, "unixnano": e.Unixnano,
			"action": "", "rule": "", "protocol": c.Protocol, "srcIp": c.SrcIp, "srcPort": c.SrcPort,
			"dstIp": c.DstIp, "dstHost": c.DstHost, "dstPort": c.DstPort, "uid": int32(c.UserId),
			"pid": int64(int32(c.ProcessId)), "process": c.ProcessPath, "cwd": c.ProcessCwd, "args": c.ProcessArgs,
		}
		if e.Rule != nil {
			ev["action"] = e.Rule.Action
			ev["rule"] = e.Rule.Name
		}
		fresh = append(fresh, ev)
	}
	sort.SliceStable(fresh, func(i, j int) bool { return fresh[i]["unixnano"].(int64) < fresh[j]["unixnano"].(int64) })
	h.events = append(h.events, fresh...)
	if len(h.events) > maxEvents {
		h.events = append([]map[string]any(nil), h.events[len(h.events)-maxEvents:]...)
	}
	if time.Since(h.lastStat) >= statsEmitPeriod || len(fresh) > 0 {
		h.lastStat = time.Now()
		h.emitLocked("stats", map[string]any{"node": n.Key, "stats": statsToJSON(st)}, true)
		if len(fresh) > 0 {
			h.emitLocked("events", fresh, true)
		}
	}
}

func (h *Hub) clearEvents() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.events = nil
}

func (h *Hub) recentEvents(limit int) []map[string]any {
	h.mu.Lock()
	defer h.mu.Unlock()
	if limit <= 0 || limit > len(h.events) {
		limit = len(h.events)
	}
	out := make([]map[string]any, limit)
	copy(out, h.events[len(h.events)-limit:])
	return out
}

func (h *Hub) addAlert(n *Node, a *pb.Alert) {
	h.mu.Lock()
	defer h.mu.Unlock()
	al := Alert{ID: a.Id, Time: time.Now().Unix(), Text: a.GetText()}
	if n != nil {
		al.Node = n.Key
	}
	al.Type = map[pb.Alert_Type]string{pb.Alert_Type_ERROR: "error", pb.Alert_Type_WARNING: "warning", pb.Alert_Type_INFO: "info"}[a.Type]
	al.Priority = map[pb.Alert_Priority]string{pb.Alert_Priority_LOW: "low", pb.Alert_Priority_MEDIUM: "medium", pb.Alert_Priority_HIGH: "high"}[a.Priority]
	al.What = map[pb.Alert_What]string{
		pb.Alert_What_GENERIC: "generic", pb.Alert_What_PROC_MONITOR: "process monitor", pb.Alert_What_FIREWALL: "firewall",
		pb.Alert_What_CONNECTION: "connection", pb.Alert_What_RULE: "rule", pb.Alert_What_NETLINK: "netlink", pb.Alert_What_KERNEL_EVENT: "kernel event",
	}[a.What]
	if al.Text == "" {
		switch {
		case a.GetRule() != nil:
			al.Text = "rule " + a.GetRule().Name
		case a.GetConn() != nil:
			al.Text = a.GetConn().ProcessPath + " → " + a.GetConn().DstIp
		case a.GetProc() != nil:
			al.Text = a.GetProc().Path
		}
	}
	h.alerts = append(h.alerts, al)
	if len(h.alerts) > maxAlerts {
		h.alerts = h.alerts[len(h.alerts)-maxAlerts:]
	}
	h.emitLocked("alert", al, false)
}
