#!/usr/bin/env python3
"""End-to-end check of the Go backend against a simulated opensnitch daemon.

Dev only: needs `pip install grpcio grpcio-tools`. The daemon side uses stubs
generated straight from the original ui.proto, so this is the real wire format.

    python3 tests/e2e_sim.py /path/to/opensnitch-dmsd
"""
import json, os, queue, socket, subprocess, sys, tempfile, threading, time
import grpc, grpc_tools.protoc as protoc

here = os.path.dirname(os.path.abspath(__file__))
tmp = tempfile.mkdtemp()
protoc.main(["x", f"-I{here}/../tools", f"--python_out={tmp}", f"--grpc_python_out={tmp}", "ui.proto"])
sys.path.insert(0, tmp)
import ui_pb2 as pb, ui_pb2_grpc as pbg

binary = sys.argv[1]
osui, ctrl = f"{tmp}/osui.sock", f"{tmp}/ctrl.sock"
proc = subprocess.Popen([binary, "-listen", f"unix://{osui}", "-socket", ctrl, "-state", f"{tmp}/state"],
                        stderr=subprocess.PIPE, text=True)
for _ in range(50):
    if os.path.exists(ctrl) and os.path.exists(osui): break
    time.sleep(0.1)

fails = []
def check(name, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + name + (f"  {extra}" if extra and not cond else ""))
    if not cond: fails.append(name)

class Ctl:
    def __init__(self):
        self.s = socket.socket(socket.AF_UNIX); self.s.connect(ctrl)
        self.f = self.s.makefile("r")
        self.events = queue.Queue(); self.replies = {}; self.n = 0
        self.cv = threading.Condition()
        threading.Thread(target=self.read, daemon=True).start()
    def read(self):
        for line in self.f:
            m = json.loads(line)
            if "event" in m: self.events.put(m)
            else:
                with self.cv: self.replies[m["id"]] = m; self.cv.notify_all()
    def call(self, method, **params):
        self.n += 1; i = self.n
        self.s.sendall((json.dumps({"id": i, "method": method, "params": params}) + "\n").encode())
        with self.cv:
            self.cv.wait_for(lambda: i in self.replies, 15)
            return self.replies.pop(i)
    def event(self, name, timeout=8):
        end = time.time() + timeout
        while time.time() < end:
            try: m = self.events.get(timeout=0.2)
            except queue.Empty: continue
            if m["event"] == name: return m["data"]
        return None

ui = Ctl()
st = ui.call("hello", prompts=True)["result"]
check("hello returns state, no nodes yet", st["nodes"] == [])

# --- the daemon ---
chan = grpc.insecure_channel(f"unix://{osui}")
stub = pbg.UIStub(chan)
cfg_json = json.dumps({"Server": {"Address": "unix:///tmp/osui.sock"}, "DefaultAction": "allow",
                       "LogLevel": 2, "FwOptions": {"QueueBypass": True}, "InterceptUnknown": False})
rule0 = pb.Rule(name="allow-curl", enabled=True, action="allow", duration="always",
                operator=pb.Operator(type="simple", operand="process.path", data="/usr/bin/curl"))
fw = pb.SysFirewall(Enabled=True, Version=1)
sub = stub.Subscribe(pb.ClientConfig(id=1, name="testbox", version="1.8", isFirewallRunning=True,
                                     config=cfg_json, rules=[rule0], systemFirewall=fw))
check("subscribe overrides DefaultAction with the UI default (deny)", json.loads(sub.config)["DefaultAction"] == "deny", sub.config)
check("subscribe keeps rules", len(sub.rules) == 1)

received = queue.Queue(); out_q = queue.Queue()
def reqgen():
    yield pb.NotificationReply(id=0, code=pb.OK)
    while True:
        r = out_q.get()
        if r is None: return
        yield r
def notif_reader():
    try:
        for n in stub.Notifications(reqgen()):
            received.put(n)
            out_q.put(pb.NotificationReply(id=n.id, code=pb.OK))
    except grpc.RpcError: pass
threading.Thread(target=notif_reader, daemon=True).start()

node = ui.event("node")
check("node event after subscribe", node is not None and node["name"] == "testbox")
snap = ui.call("state")["result"]
n0 = snap["nodes"][0]
check("node online with notifications channel", n0["online"])
check("interception reported on", n0["interception"] is True)
check("rules synced", [r["name"] for r in n0["rules"]] == ["allow-curl"])
check("sys firewall known", n0["sysFirewall"]["known"] and n0["sysFirewall"]["enabled"])

# --- stats / events ---
ui.call("subscribe")
conn = pb.Connection(protocol="tcp", src_ip="192.168.1.5", src_port=40000, dst_ip="142.250.80.46",
                     dst_host="www.google.com", dst_port=443, user_id=1000, process_id=4242,
                     process_path="/usr/bin/curl", process_cwd="/home/u", process_args=["curl", "https://www.google.com"],
                     process_checksums={"process.hash.md5": "abc123"})
ev = pb.Event(time="2026-10-08 10:00:00", connection=conn, rule=pb.Rule(name="allow-curl", action="allow"), unixnano=111)
stub.Ping(pb.PingRequest(id=7, stats=pb.Statistics(daemon_version="1.8", connections=10, accepted=8, dropped=2,
                                                   by_host={"www.google.com": 5}, events=[ev])))
s = ui.event("stats")
check("stats streamed", s and s["stats"]["connections"] == 10 and s["stats"]["byHost"][0]["key"] == "www.google.com")
evs = ui.call("events", limit=10)["result"]["events"]
check("event recorded", len(evs) == 1 and evs[0]["process"] == "/usr/bin/curl" and evs[0]["rule"] == "allow-curl")
stub.Ping(pb.PingRequest(id=8, stats=pb.Statistics(events=[ev])))
check("duplicate events ignored", len(ui.call("events")["result"]["events"]) == 1)

# --- prompt: simple rule ---
def ask(c, box):
    try: box.append(stub.AskRule(c, timeout=30))
    except grpc.RpcError as e: box.append(e)
box = []; t = threading.Thread(target=ask, args=(conn, box)); t.start()
p = ui.event("prompt")
check("prompt event", p is not None and p["conn"]["dstPort"] == 443)
kinds = [o["kind"] for o in p["options"]["targets"]]
check("target options like Qt", kinds[:6] == ["process_path", "process_args", "dst_port", "dst_ip", "user_id", "process_id"], kinds)
labels = [o["label"] for o in p["options"]["targets"]]
check("network + host + regex options", "to 142.250.80.0/24" in labels and "www.google.com" in labels and "to *.google.com" in labels and "to 142.250.*" in labels, labels)
check("defaults: target 0, deny, 7=until reboot", p["defaults"]["target"] == 0 and p["defaults"]["action"] == "deny" and p["defaults"]["duration"] == 7)
r = ui.call("prompt.answer", id=p["id"], answer=dict(action="allow", target=0, ipTarget=0, duration=8, advanced=False))
check("answer accepted", "result" in r, r)
t.join(5)
rule = box[0]
check("simple rule returned", isinstance(rule, pb.Rule) and rule.operator.operand == "process.path"
      and rule.operator.data == "/usr/bin/curl" and rule.action == "allow" and rule.duration == "always", box)
check("rule name like Qt", rule.name == "allow-always-simple-usr-bin-curl", rule.name)
check("prompt.done event", ui.event("prompt.done") is not None)

# --- prompt: list rule (dst port + ip regexp + md5) with to-host target ---
box = []; t = threading.Thread(target=ask, args=(conn, box)); t.start()
p = ui.event("prompt")
host_idx = labels.index("to *.google.com")
ip_regex = [o for o in p["options"]["ipTargets"] if o["label"] == "to 142.250.*"][0]["index"]
ui.call("prompt.answer", id=p["id"], answer=dict(action="reject", target=host_idx, ipTarget=ip_regex, duration=3,
        advanced=True, dstIp=True, dstPort=True, uid=True, checksum=True))
t.join(5); rule = box[0]
ops = [(o.type, o.operand, o.data) for o in rule.operator.list]
check("list rule built", rule.operator.type == "list" and rule.action == "reject" and rule.duration == "15m", str(rule))
check("list operands", ops == [("regexp", "dest.ip", r"142\.250\..*"), ("simple", "dest.port", "443"),
                               ("simple", "user.id", "1000"), ("simple", "process.hash.md5", "abc123"),
                               ("regexp", "dest.host", r"^(|.*\.)google\.com$")], ops)
check("list data json", len(json.loads(rule.operator.data)) == 5)
node = ui.call("state")["result"]["nodes"][0]
check("temp rule tracked locally", any(r["name"] == rule.name for r in node["rules"]))

# --- prompt: command line with relative first arg pins executable ---
conn2 = pb.Connection(); conn2.CopyFrom(conn); conn2.process_args[:] = ["python", "x.py"]
box = []; t = threading.Thread(target=ask, args=(conn2, box)); t.start()
p = ui.event("prompt")
ui.call("prompt.answer", id=p["id"], answer=dict(action="deny", target=1, duration=0))
t.join(5); rule = box[0]
check("relative cmdline adds executable", rule.operator.type == "list" and
      [o.operand for o in rule.operator.list] == ["process.path", "process.command"], str(rule))
node = ui.call("state")["result"]["nodes"][0]
check("'once' rule is not kept", not any(r["name"] == rule.name for r in node["rules"]))

# --- invalid answer is refused ---
box = []; t = threading.Thread(target=ask, args=(conn, box)); t.start()
p = ui.event("prompt")
r = ui.call("prompt.answer", id=p["id"], answer=dict(action="allow", target=99, duration=0))
check("invalid answer rejected, prompt stays", "error" in r)
ui.call("prompt.answer", id=p["id"], answer=dict(action="allow", target=2, duration=0)); t.join(5)
check("then valid one works (port rule)", box[0].operator.operand == "dest.port" and box[0].operator.data == "443")

# --- timeout applies defaults ---
ui.call("settings.set", changes={"timeout": 1, "defaultAction": "allow"})
sset = ui.event("settings")
check("settings event", sset and sset["timeout"] == 1)
cfgn = received.get(timeout=8)
check("default action pushed to daemon as CHANGE_CONFIG", cfgn.type == pb.CHANGE_CONFIG and json.loads(cfgn.data)["DefaultAction"] == "allow")
box = []; t = threading.Thread(target=ask, args=(conn, box)); t.start()
p = ui.event("prompt"); check("timeout prompt shown", p is not None)
t0 = time.time(); t.join(20)
check("backend applies defaults when UI never answers", isinstance(box[0], pb.Rule) and box[0].action == "allow" and time.time() - t0 > 1, box)

# --- timeout 0 => no prompt at all ---
ui.call("settings.set", changes={"timeout": 0}); time.sleep(0.2)
while not ui.events.empty(): ui.events.get()
box = []; t = threading.Thread(target=ask, args=(conn, box)); t.start(); t.join(5)
check("zero timeout answers silently", isinstance(box[0], pb.Rule))
check("...without a prompt", ui.event("prompt", 0.5) is None)

# --- no UI / disabled popups -> daemon falls back to default ---
ui.call("settings.set", changes={"timeout": 15, "disablePopups": True}); time.sleep(0.2)
box = []; ask(conn, box)
check("popups disabled -> error to daemon (default action applies)", isinstance(box[0], grpc.RpcError))
ui.call("settings.set", changes={"disablePopups": False})

# --- daemon control ---
while not received.empty(): received.get()
r = ui.call("interception.set", enabled=False)
n = received.get(timeout=5)
check("interception off sent to daemon", n.type == pb.DISABLE_INTERCEPTION and "result" in r, r)
check("state reflects it", ui.call("state")["result"]["nodes"][0]["interception"] is False)
ui.call("interception.set", enabled=True); received.get(timeout=5)

r = ui.call("firewall.set", enabled=False); n = received.get(timeout=5)
check("system firewall off = RELOAD_FW_RULES with Enabled=false", n.type == pb.RELOAD_FW_RULES and n.sysFirewall.Enabled is False and "result" in r, r)

r = ui.call("config.set", changes={"LogLevel": 4, "FwOptions.QueueBypass": False, "ProcMonitorMethod": "proc"})
n = received.get(timeout=5); c = json.loads(n.data)
check("config change merges into the whole config", n.type == pb.CHANGE_CONFIG and c["LogLevel"] == 4 and
      c["FwOptions"]["QueueBypass"] is False and c["ProcMonitorMethod"] == "proc" and c["Server"]["Address"].startswith("unix"), n.data)

r = ui.call("rule.disable", name="allow-curl"); n = received.get(timeout=5)
check("rule.disable", n.type == pb.DISABLE_RULE and n.rules[0].name == "allow-curl")
r = ui.call("rule.delete", name="allow-curl"); n = received.get(timeout=5)
check("rule.delete", n.type == pb.DELETE_RULE)
r = ui.call("rule.set", rule={"name": "block-x", "enabled": True, "action": "deny", "duration": "always",
            "operator": {"type": "simple", "operand": "dest.host", "data": "x.example"}})
n = received.get(timeout=5)
check("rule.set -> CHANGE_RULE", n.type == pb.CHANGE_RULE and n.rules[0].operator.data == "x.example", r)
r = ui.call("rule.set", rule={"name": "bad", "action": "maybe", "operator": {"type": "simple", "operand": "x", "data": "y"}})
check("bad rule refused", "error" in r)

# --- alert ---
stub.PostAlert(pb.Alert(id=1, type=pb.Alert.ERROR, what=pb.Alert.FIREWALL, priority=pb.Alert.HIGH, text="fw broke"))
a = ui.event("alert")
check("alert event", a and a["text"] == "fw broke" and a["type"] == "error" and a["what"] == "firewall", a)

# --- daemon goes away ---
out_q.put(None); chan.close()
node = None
for _ in range(30):
    node = ui.event("node", 0.5)
    if node and not node["online"]: break
check("node offline after disconnect", node and not node["online"])
r = ui.call("interception.set", enabled=False)
check("control calls fail cleanly while offline", "error" in r, r)

proc.terminate(); proc.wait(5)
err = proc.stderr.read()
check("no panics", "panic" not in err, err[-500:])
print(f"\n{len(fails)} failed" if fails else "\nall passed")
sys.exit(1 if fails else 0)
