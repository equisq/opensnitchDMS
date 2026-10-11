package main

// Port of the Qt prompt's rule logic (ui/opensnitch/dialogs/prompt/utils.py and
// dialog.py:_send_rule). The QML side only ever sends *indexes* into the option
// lists below; the rule itself is always built here, from the connection the
// daemon reported, so the two cannot disagree about what a choice means.

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"os"
	"os/user"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"

	pb "opensnitchdms/protocol"
)

const (
	operandProcessID      = "process.id"
	operandProcessPath    = "process.path"
	operandProcessCommand = "process.command"
	operandProcessMD5     = "process.hash.md5"
	operandUserID         = "user.id"
	operandDestIP         = "dest.ip"
	operandDestHost       = "dest.host"
	operandDestPort       = "dest.port"
	operandDestNetwork    = "dest.network"

	typeList    = "list"
	typeSimple  = "simple"
	typeRegexp  = "regexp"
	typeNetwork = "network"

	actionAllow  = "allow"
	actionDeny   = "deny"
	actionReject = "reject"

	appImagePrefix = "/tmp/.mount_"
	snapPrefix     = "/snap"
)

// Target kinds, the "don't translate" field ids of the Qt prompt.
const (
	kProcPath    = "process_path"
	kProcArgs    = "process_args"
	kProcID      = "process_id"
	kUserID      = "user_id"
	kDstIP       = "dst_ip"
	kDstPort     = "dst_port"
	kDstNetwork  = "dst_network"
	kDstHost     = "simple_host"
	kRegexHost   = "regex_host"
	kRegexIP     = "regex_ip"
	kAppImage    = "appimage_path"
	kSnap        = "snap_path"
	targetIdxPID = 5
)

// Durations, in the order of the Qt duration combo (utils.get_duration).
var durations = []struct{ ID, Label string }{
	{"once", "once"},
	{"30s", "30 seconds"},
	{"5m", "5 minutes"},
	{"15m", "15 minutes"},
	{"30m", "30 minutes"},
	{"1h", "1 hour"},
	{"12h", "12 hours"},
	{"until restart", "until reboot"},
	{"always", "forever"},
}

func durationIndex(id string) int {
	for i, d := range durations {
		if d.ID == id {
			return i
		}
	}
	return 7
}

type Option struct {
	Index   int    `json:"index"`
	Kind    string `json:"kind"`
	Label   string `json:"label"`
	Enabled bool   `json:"enabled"`
}

type Options struct {
	Targets   []Option `json:"targets"`
	IPTargets []Option `json:"ipTargets"`
}

func userLabel(uid uint32) string {
	if u, err := user.LookupId(strconv.FormatUint(uint64(uid), 10)); err == nil {
		return fmt.Sprintf("%d (%s)", uid, u.Username)
	}
	return strconv.FormatUint(uint64(uid), 10)
}

func networksFor(dstIP string) []string {
	a, err := netip.ParseAddr(dstIP)
	if err != nil {
		return nil
	}
	a = a.WithZone("")
	var bits []int
	if a.Is4() || a.Is4In6() {
		a = a.Unmap()
		bits = []int{24, 16, 8}
	} else {
		bits = []int{64, 128}
	}
	var out []string
	for _, b := range bits {
		p, err := a.Prefix(b)
		if err != nil {
			continue
		}
		out = append(out, p.String())
	}
	return out
}

// buildOptions is add_fixed_options_to_combo + the pattern/network/host/ip
// entries, in the same order as the original combo boxes.
func buildOptions(c *pb.Connection, local bool) Options {
	var o Options
	add := func(list *[]Option, kind, label string, enabled bool) {
		*list = append(*list, Option{Index: len(*list), Kind: kind, Label: label, Enabled: enabled})
	}
	uid := userLabel(c.UserId)
	if !local {
		uid = strconv.FormatUint(uint64(c.UserId), 10)
	}
	t := &o.Targets
	add(t, kProcPath, "from this executable", int32(c.ProcessId) >= 0 && c.ProcessPath != "")
	add(t, kProcArgs, "from this command line", len(c.ProcessArgs) > 0 && c.ProcessArgs[0] != "")
	add(t, kDstPort, fmt.Sprintf("to port %d", c.DstPort), true)
	add(t, kDstIP, "to "+c.DstIp, true)
	add(t, kUserID, "from user "+uid, int32(c.UserId) >= 0)
	add(t, kProcID, "from this PID", true)

	if strings.HasPrefix(c.ProcessPath, appImagePrefix) {
		dir := path.Dir(c.ProcessPath)
		if n := len(appImagePrefix) + 6; len(dir) > n {
			dir = dir[:n]
		}
		add(t, kAppImage, fmt.Sprintf("from %s*/%s", dir, path.Base(c.ProcessPath)), true)
	} else if strings.HasPrefix(c.ProcessPath, snapPrefix) {
		if parts := strings.Split(c.ProcessPath, "/"); len(parts) > 4 {
			add(t, kSnap, fmt.Sprintf("from /snap/%s/*/%s", parts[2], strings.Join(parts[4:], "/")), true)
		}
	}
	for _, n := range networksFor(c.DstIp) {
		add(t, kDstNetwork, "to "+n, true)
	}

	ip := &o.IPTargets
	add(ip, kDstIP, "to "+c.DstIp, true)

	if c.DstHost != "" && c.DstHost != c.DstIp {
		add(t, kDstHost, c.DstHost, true)
		add(ip, kDstHost, c.DstHost, true)
		parts := strings.Split(c.DstHost, ".")[1:]
		for i := 0; i < len(parts)-1; i++ {
			l := "to *." + strings.Join(parts[i:], ".")
			add(t, kRegexHost, l, true)
			add(ip, kRegexHost, l, true)
		}
	}
	ipParts := strings.Split(c.DstIp, ".")
	for i := 1; i < len(ipParts); i++ {
		l := "to " + strings.Join(ipParts[:i], ".") + ".*"
		add(t, kRegexIP, l, true)
		add(ip, kRegexIP, l, true)
	}
	for _, n := range networksFor(c.DstIp) {
		add(ip, kDstNetwork, "to "+n, true)
	}
	return o
}

func lastWord(s string) string {
	f := strings.Fields(s)
	if len(f) == 0 {
		return ""
	}
	return f[len(f)-1]
}

// operatorFor is utils.get_combo_operator.
func operatorFor(opt Option, c *pb.Connection) (typ, operand, data string) {
	switch opt.Kind {
	case kProcPath:
		return typeSimple, operandProcessPath, c.ProcessPath
	case kProcArgs:
		if len(c.ProcessArgs) == 0 || c.ProcessArgs[0] == "" {
			return typeSimple, operandProcessPath, c.ProcessPath
		}
		return typeSimple, operandProcessCommand, strings.Join(c.ProcessArgs, " ")
	case kProcID:
		return typeSimple, operandProcessID, strconv.FormatUint(uint64(c.ProcessId), 10)
	case kUserID:
		return typeSimple, operandUserID, strconv.FormatUint(uint64(c.UserId), 10)
	case kDstPort:
		return typeSimple, operandDestPort, strconv.FormatUint(uint64(c.DstPort), 10)
	case kDstIP:
		return typeSimple, operandDestIP, c.DstIp
	case kDstHost:
		return typeSimple, operandDestHost, opt.Label
	case kDstNetwork:
		return typeNetwork, operandDestNetwork, lastWord(opt.Label)
	case kRegexHost:
		text := lastWord(opt.Label)
		h := strings.ReplaceAll(strings.Join(strings.Split(text, "."), `\.`), "*", "")
		if len(h) >= 2 {
			h = h[2:]
		}
		return typeRegexp, operandDestHost, `^(|.*\.)` + h + `$`
	case kRegexIP:
		text := lastWord(opt.Label)
		return typeRegexp, operandDestIP, strings.ReplaceAll(strings.Join(strings.Split(text, "."), `\.`), "*", ".*")
	case kAppImage:
		bin := path.Base(c.ProcessPath)
		dir := strings.ReplaceAll(path.Dir(c.ProcessPath), ".", `\.`)
		if n := len(appImagePrefix) + 7; len(dir) > n {
			dir = dir[:n]
		}
		return typeRegexp, operandProcessPath, `^` + dir + `[0-9A-Za-z]+\/.*` + bin + `$`
	case kSnap:
		parts := strings.Split(c.ProcessPath, "/")
		if len(parts) <= 4 {
			return "", "", ""
		}
		return typeRegexp, operandProcessPath,
			`^\/` + parts[1] + `\/` + parts[2] + `\/[0-9]+\/` + strings.Join(parts[4:], `\/`) + `$`
	}
	return "", "", ""
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	return strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(s), "-"), "-")
}

// Answer is what the QML prompt sends back.
type Answer struct {
	Action   string `json:"action"` // allow | deny | reject
	Target   int    `json:"target"`
	IPTarget int    `json:"ipTarget"`
	Duration int    `json:"duration"`
	Advanced bool   `json:"advanced"`
	DstIP    bool   `json:"dstIp"`
	DstPort  bool   `json:"dstPort"`
	UID      bool   `json:"uid"`
	Checksum bool   `json:"checksum"`
}

type opSpec struct{ Type, Operand, Data string }

// buildRule is dialog._send_rule.
func buildRule(c *pb.Connection, opts Options, a Answer, existing []*pb.Rule) (*pb.Rule, error) {
	if a.Target < 0 || a.Target >= len(opts.Targets) {
		return nil, fmt.Errorf("invalid target")
	}
	if a.Duration < 0 || a.Duration >= len(durations) {
		return nil, fmt.Errorf("invalid duration")
	}
	target := opts.Targets[a.Target]
	if !target.Enabled {
		return nil, fmt.Errorf("that target is not available for this connection")
	}
	switch a.Action {
	case actionAllow, actionDeny, actionReject:
	default:
		return nil, fmt.Errorf("invalid action")
	}

	r := &pb.Rule{
		Name:     "user.choice",
		Created:  time.Now().Unix(),
		Enabled:  true,
		Duration: durations[a.Duration].ID,
		Action:   a.Action,
	}
	typ, operand, data := operatorFor(target, c)
	if data == "" {
		return nil, fmt.Errorf("the rule would be empty")
	}
	r.Operator = &pb.Operator{Type: typ, Operand: operand, Data: data}

	// Checkboxes only count while the advanced section is shown.
	chkIP := a.Advanced && a.DstIP
	chkPort := a.Advanced && a.DstPort && c.DstPort != 0
	chkUID := a.Advanced && a.UID
	md5 := c.ProcessChecksums[operandProcessMD5]
	chkSum := a.Advanced && a.Checksum && md5 != ""
	isList := chkIP || chkPort || chkUID || chkSum

	name := slugify(fmt.Sprintf("%s %s", r.Action, r.Duration))
	if isList {
		name += "-list"
	} else {
		name += "-simple"
	}
	name = slugify(name + " " + data)
	if len(name) > 128 {
		name = name[:128]
	}

	var list []opSpec
	if chkIP && target.Kind != kDstIP {
		if a.IPTarget < 0 || a.IPTarget >= len(opts.IPTargets) {
			return nil, fmt.Errorf("invalid ip target")
		}
		t, o, d := operatorFor(opts.IPTargets[a.IPTarget], c)
		list = append(list, opSpec{t, o, d})
		name = slugify(name + " " + d)
	}
	if chkPort && target.Kind != kDstPort {
		d := strconv.FormatUint(uint64(c.DstPort), 10)
		list = append(list, opSpec{typeSimple, operandDestPort, d})
		name = slugify(name + " " + d)
	}
	if chkUID && target.Kind != kUserID {
		d := strconv.FormatUint(uint64(c.UserId), 10)
		list = append(list, opSpec{typeSimple, operandUserID, d})
		name = slugify(name + " " + d)
	}
	if chkSum {
		list = append(list, opSpec{typeSimple, operandProcessMD5, md5})
		name = slugify(name + " " + operandProcessMD5)
	}

	// A command line whose first word is not an absolute path (or is under
	// /proc) cannot be trusted alone: pin the executable too.
	if operand == operandProcessCommand {
		first := strings.Fields(strings.Join(c.ProcessArgs, " "))
		if len(first) == 0 || !path.IsAbs(first[0]) || strings.HasPrefix(first[0], "/proc") {
			isList = true
			list = append(list, opSpec{typeSimple, operandProcessPath, c.ProcessPath})
		}
	}

	if isList {
		list = append(list, opSpec{typ, operand, data})
		js := make([]map[string]string, 0, len(list))
		r.Operator.List = nil
		for _, o := range list {
			js = append(js, map[string]string{"type": o.Type, "operand": o.Operand, "data": o.Data})
			r.Operator.List = append(r.Operator.List, &pb.Operator{Type: o.Type, Operand: o.Operand, Data: o.Data})
		}
		b, _ := json.Marshal(js)
		r.Operator.Data = string(b)
		r.Operator.Type = typeList
		r.Operator.Operand = typeList
	}

	r.Name = uniqueRuleName(name, r, existing)
	return r, nil
}

func sameRule(a, b *pb.Rule) bool {
	if a.Action != b.Action || a.Duration != b.Duration || a.Operator == nil || b.Operator == nil {
		return false
	}
	x, y := a.Operator, b.Operator
	return x.Type == y.Type && x.Operand == y.Operand && x.Data == y.Data
}

// uniqueRuleName keeps the name when the very same rule already exists (the
// daemon then updates it in place) and otherwise avoids clobbering another.
func uniqueRuleName(base string, r *pb.Rule, existing []*pb.Rule) string {
	taken := map[string]*pb.Rule{}
	for _, e := range existing {
		taken[e.Name] = e
	}
	if e, ok := taken[base]; !ok || sameRule(e, r) {
		return base
	}
	for i := 1; ; i++ {
		n := fmt.Sprintf("%s-%d", base, i)
		if e, ok := taken[n]; !ok || sameRule(e, r) {
			return n
		}
	}
}

// Defaults are what a prompt starts out as, and what applies on timeout.
type Defaults struct {
	Target   int    `json:"target"`
	IPTarget int    `json:"ipTarget"`
	Duration int    `json:"duration"`
	Action   string `json:"action"`
	Advanced bool   `json:"advanced"`
	DstIP    bool   `json:"dstIp"`
	DstPort  bool   `json:"dstPort"`
	UID      bool   `json:"uid"`
	Checksum bool   `json:"checksum"`
}

func findKind(list []Option, kind string) int {
	for _, o := range list {
		if o.Kind == kind {
			return o.Index
		}
	}
	return -1
}

// defaultTarget is utils.set_default_target.
func defaultTarget(opts Options, c *pb.Connection, saved int, appName, appArgs string) int {
	if i := findKind(opts.Targets, kAppImage); i >= 0 {
		return i
	}
	if i := findKind(opts.Targets, kSnap); i >= 0 {
		return i
	}
	pid := int64(int32(c.ProcessId))
	switch {
	case saved == targetIdxPID && pid > 0:
		return targetIdxPID
	case saved == 4, saved == 3, saved == 2:
		return saved
	case pid > 0 && appName != "" && appArgs != "":
		if saved >= 0 && saved < len(opts.Targets) {
			return saved
		}
		return 0
	case pid > 0 && appName != "" && appArgs == "":
		return 0
	}
	return 2
}

func (s *Settings) defaultsFor(opts Options, c *pb.Connection, appName string) Defaults {
	d := Defaults{
		Target:   defaultTarget(opts, c, s.DefaultTarget, appName, strings.Join(c.ProcessArgs, " ")),
		Duration: durationIndex(s.DefaultDuration),
		Action:   s.DefaultAction,
		Advanced: s.PopupAdvanced,
		DstIP:    s.AdvDstIP,
		DstPort:  s.AdvDstPort,
		UID:      s.AdvUID,
		Checksum: s.AdvChecksum,
	}
	if d.Target < 0 || d.Target >= len(opts.Targets) || !opts.Targets[d.Target].Enabled {
		d.Target = 2
		for _, o := range opts.Targets {
			if o.Enabled && o.Kind == kDstPort {
				d.Target = o.Index
			}
		}
	}
	return d
}

func (d Defaults) answer() Answer {
	return Answer{Action: d.Action, Target: d.Target, IPTarget: d.IPTarget, Duration: d.Duration,
		Advanced: d.Advanced, DstIP: d.DstIP, DstPort: d.DstPort, UID: d.UID, Checksum: d.Checksum}
}

func hostname() string { h, _ := os.Hostname(); return h }
