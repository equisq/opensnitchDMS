.pragma library

function num(n) {
    n = Number(n) || 0;
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
    if (n >= 1e4) return (n / 1e3).toFixed(1) + "k";
    return String(n);
}

function uptime(s) {
    s = Number(s) || 0;
    const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    if (d > 0) return d + "d " + h + "h";
    if (h > 0) return h + "h " + m + "m";
    return m + "m " + Math.floor(s % 60) + "s";
}

function basename(p) {
    if (!p) return "";
    const i = p.lastIndexOf("/");
    return i >= 0 ? p.substring(i + 1) : p;
}

// "2026-10-08 10:00:00" or any Date-parsable string -> HH:MM:SS
function clock(t) {
    if (!t) return "";
    const m = /(\d{2}:\d{2}:\d{2})/.exec(t);
    return m ? m[1] : t;
}

function operatorSummary(op) {
    if (!op) return "";
    if (op.type === "list") {
        return (op.list || []).map(o => o.operand + " " + (o.type === "regexp" ? "~ " : "= ") + o.data).join("  ·  ");
    }
    return op.operand + " " + (op.type === "regexp" ? "~ " : op.type === "network" ? "in " : "= ") + op.data;
}

function durationLabel(d) {
    if (d === "always") return "forever";
    if (d === "until restart") return "until reboot";
    return d;
}

function isBlock(a) {
    return a === "deny" || a === "reject" || a === "drop";
}
