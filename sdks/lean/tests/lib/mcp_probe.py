#!/usr/bin/env python3
"""Drive lean-lsp-mcp over stdio with raw JSON-RPC (MCP), standard library only.

usage: mcp_probe.py <lake project dir> <file relative to it>
Prints one "MCP-<STEP>: ..." line per step and the raw tool results, for the spread task to check.
Exit 0 if every step got a response, 1 otherwise.
"""
import json, os, select, subprocess, sys, time

proj, rel = sys.argv[1], sys.argv[2]
path = os.path.join(proj, rel)
env = dict(os.environ, LEAN_PROJECT_PATH=proj)
srv = subprocess.Popen(["lean-lsp-mcp"], cwd=proj, env=env, stdin=subprocess.PIPE,
                       stdout=subprocess.PIPE, stderr=open("/tmp/lean-lsp-mcp.stderr", "w"))
buf = b""
nid = 0


def send(obj):
    srv.stdin.write((json.dumps(obj) + "\n").encode())
    srv.stdin.flush()


def request(method, params, timeout):
    global nid, buf
    nid += 1
    send({"jsonrpc": "2.0", "id": nid, "method": method, "params": params})
    end = time.time() + timeout
    while time.time() < end:
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if not line.strip():
                continue
            msg = json.loads(line)
            if msg.get("id") == nid and ("result" in msg or "error" in msg):
                return msg
        r, _, _ = select.select([srv.stdout], [], [], 1.0)
        if r:
            chunk = os.read(srv.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError("server closed stdout (exit %s)" % srv.poll())
            buf += chunk
    raise TimeoutError("%s: no answer in %ss" % (method, timeout))


def text(msg):
    res = msg.get("result", {})
    parts = [c.get("text", "") for c in res.get("content", []) if c.get("type") == "text"]
    if "structuredContent" in res:
        parts.append(json.dumps(res["structuredContent"]))
    return "\n".join(parts)


ok = True


def step(name, method, params, timeout=600):
    global ok
    try:
        msg = request(method, params, timeout)
    except Exception as e:  # noqa: BLE001
        ok = False
        print("MCP-%s: ERROR %s" % (name, e))
        return None
    if "error" in msg or msg.get("result", {}).get("isError"):
        ok = False
        print("MCP-%s: TOOL-ERROR %s" % (name, json.dumps(msg)[:2000]))
        return msg
    print("MCP-%s: OK" % name)
    return msg


m = step("INIT", "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                "clientInfo": {"name": "lean-tests", "version": "1"}},
         timeout=120)
if m:
    info = m["result"].get("serverInfo", {})
    print("MCP-SERVER: %s %s" % (info.get("name"), info.get("version")))
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

m = step("LIST", "tools/list", {}, timeout=60)
if m:
    tools = m["result"]["tools"]
    print("MCP-TOOLS: " + " ".join(sorted(t["name"] for t in tools)))
    for t in tools:
        if t["name"] in ("lean_goal", "lean_diagnostic_messages", "lean_local_search", "lean_verify"):
            print("MCP-SCHEMA %s: %s" % (t["name"], json.dumps(t.get("inputSchema", {}).get("properties", {}))))


def call(name, tool, args, timeout=900):
    m = step(name, "tools/call", {"name": tool, "arguments": args}, timeout)
    if m and "result" in m:
        print("----- %s result\n%s\n----- end %s" % (name, text(m)[:4000], name))


call("DIAG", "lean_diagnostic_messages", {"file_path": path})
call("GOAL", "lean_goal", {"file_path": path, "line": 3})
call("SEARCH", "lean_local_search", {"query": "isort_perm"}, timeout=120)
call("VERIFY", "lean_verify", {"file_path": os.path.join(proj, "Algo", "Sort.lean"),
                               "theorem_name": "Algo.isort_correct"})

srv.stdin.close()
try:
    srv.wait(timeout=20)
except subprocess.TimeoutExpired:
    srv.kill()
sys.exit(0 if ok else 1)
