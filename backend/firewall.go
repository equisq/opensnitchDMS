package main

import (
	"errors"
	"strings"

	pb "opensnitchdms/protocol"
)

// Default input/output policy, ported from the Qt firewall dialog: it flips
// the policy of the opensnitch filter/input and mangle/output chains, and when
// dropping it adds the rules that keep local and established traffic working.

type fwProfile struct {
	hook, ctype string
	rules       []*pb.FwRule
}

func stmt(name string, kv ...string) []*pb.Expressions {
	s := &pb.Statement{Name: name}
	for i := 0; i+1 < len(kv); i += 2 {
		s.Values = append(s.Values, &pb.StatementValues{Key: kv[i], Value: kv[i+1]})
	}
	return []*pb.Expressions{{Statement: s}}
}

var dropProfiles = map[string]fwProfile{
	"input": {"input", "filter", []*pb.FwRule{
		{UUID: "profile-drop-inbound-2d7e6fe4-c21d-11ec-99a6-3c970e298b0c", Enabled: true,
			Description: "[profile-drop-inbound] allow localhost connections",
			Expressions: stmt("iifname", "lo", ""), Target: "accept"},
		{UUID: "profile-drop-inbound-e1fc1a1c-c21c-11ec-9a2a-3c970e298b0c", Enabled: true,
			Description: "[profile-drop-inbound] allow established,related connections",
			Expressions: stmt("ct", "state", "related", "state", "established"), Target: "accept"},
	}},
	"output": {"output", "mangle", []*pb.FwRule{
		{UUID: "profile-drop-outbound-e1fc1a1c-c21c-11ec-9a2a-3c970e298b0c", Enabled: true,
			Description: "[profile-drop-outbound] allow established,related connections",
			Expressions: stmt("ct", "state", "established,related"), Target: "accept"},
	}},
}

func chainPolicy(fw *pb.SysFirewall, hook string) string {
	p := dropProfiles[hook]
	if fw == nil {
		return ""
	}
	for _, fc := range fw.SystemRules {
		for _, c := range fc.Chains {
			if matchChain(c, p) {
				return strings.ToLower(c.Policy)
			}
		}
	}
	return ""
}

func matchChain(c *pb.FwChain, p fwProfile) bool {
	return strings.ToLower(c.Hook) == p.hook && strings.ToLower(c.Type) == p.ctype &&
		strings.ToLower(c.Family) == "inet" && strings.ToLower(c.Table) == "opensnitch"
}

// withPolicy returns a copy of fw with the chain policy changed.
func withPolicy(fw *pb.SysFirewall, hook, policy string) (*pb.SysFirewall, error) {
	p, ok := dropProfiles[hook]
	if !ok || (policy != "accept" && policy != "drop") {
		return nil, errors.New("unsupported firewall policy")
	}
	out := &pb.SysFirewall{Enabled: fw.Enabled, Version: fw.Version}
	found := false
	for _, fc := range fw.SystemRules {
		nfc := &pb.FwChains{Rule: fc.Rule}
		for _, c := range fc.Chains {
			nc := *c
			if matchChain(c, p) {
				found = true
				nc.Policy = policy
				nc.Rules = nil
				mine := map[string]bool{}
				for _, r := range p.rules {
					mine[r.UUID] = true
				}
				for _, r := range c.Rules {
					if !mine[r.UUID] {
						nc.Rules = append(nc.Rules, r)
					}
				}
				if policy == "drop" {
					// profile rules go first so nothing existing can shadow them
					nc.Rules = append(append([]*pb.FwRule{}, p.rules...), nc.Rules...)
				}
			}
			nfc.Chains = append(nfc.Chains, &nc)
		}
		out.SystemRules = append(out.SystemRules, nfc)
	}
	if !found {
		return nil, errors.New("the daemon has no " + hook + " chain to change")
	}
	return out, nil
}
