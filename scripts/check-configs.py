#!/usr/bin/env python3
"""
Filter live VLESS/Reality configs from a public subscription list.

Reality from a blocked region: a TCP port can be open while the TLS handshake
still fails, so a port check is not enough. This script narrows thousands of
configs down to a handful that are actually worth testing.

Usage:
    python check-configs.py            # fetch, validate, write live.json
    python check-configs.py --top 40   # test only the first 40 candidates
"""

import argparse
import concurrent.futures
import json
import os
import re
import socket
import sys
import urllib.request

SOURCES = [
    "https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt",
]

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
LIVE_JSON = os.path.join(OUT_DIR, "live.json")

VLESS_RE = re.compile(r"^vless://([^@]+)@([^:/?]+):(\d+)\?(.*?)#")


def fetch(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def parse(line):
    """Return a dict describing a vless:// URI, or None if unusable."""
    m = VLESS_RE.match(line.strip())
    if not m:
        return None
    uuid, host, port, qs = m.groups()

    params = {}
    for part in qs.split("&"):
        if "=" in part:
            k, v = part.split("=", 1)
            params[k] = urllib.parse.unquote(v)

    if params.get("security") != "reality":
        return None
    if not params.get("pbk") or not params.get("sni"):
        return None

    return {
        "uuid": uuid,
        "host": host,
        "port": int(port),
        "sni": params["sni"],
        "pbk": params["pbk"],
        "sid": params.get("sid", ""),
        "flow": params.get("flow", ""),
        "raw": line.strip(),
    }


def tcp_open(host, port, timeout=2.0):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def to_singbox(cfg, tag):
    """Build a sing-box outbound for this config."""
    out = {
        "type": "vless",
        "tag": tag,
        "server": cfg["host"],
        "server_port": cfg["port"],
        "uuid": cfg["uuid"],
        "tls": {
            "enabled": True,
            "server_name": cfg["sni"],
            "utls": {"enabled": True, "fingerprint": "chrome"},
            "reality": {
                "enabled": True,
                "public_key": cfg["pbk"],
                "short_id": cfg["sid"],
            },
        },
    }
    if cfg["flow"]:
        out["flow"] = cfg["flow"]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=80,
                    help="how many unique candidates to test (default 80)")
    ap.add_argument("--workers", type=int, default=40)
    args = ap.parse_args()

    print("Fetching configs...")
    lines = []
    for url in SOURCES:
        try:
            text = fetch(url)
            lines.extend(text.splitlines())
            print(f"  ok  {url}  ({len(text)} bytes)")
        except Exception as e:
            print(f"  fail {url}: {e}")

    if not lines:
        print("No configs fetched. Check your connection or the source URL.")
        return 1

    configs = [c for c in (parse(l) for l in lines) if c]
    print(f"parsed {len(configs)} reality configs")

    # unique by host, keep the first occurrence
    seen, unique = set(), []
    for c in configs:
        if c["host"] not in seen:
            seen.add(c["host"])
            unique.append(c)
    print(f"unique hosts: {len(unique)}")

    candidates = unique[: args.top]
    print(f"testing {len(candidates)} candidates on tcp/{candidates[0]['port'] if candidates else 443}...")

    live = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(tcp_open, c["host"], c["port"]): c for c in candidates}
        for i, fut in enumerate(concurrent.futures.as_completed(futs), 1):
            cfg = futs[fut]
            try:
                ok = fut.result()
            except Exception:
                ok = False
            if ok:
                live.append(cfg)
            if i % 20 == 0:
                print(f"  {i}/{len(candidates)}  live so far: {len(live)}")

    print(f"\ntcp-reachable: {len(live)} / {len(candidates)}")

    if not live:
        print("None reachable. Try again later - public servers rotate constantly.")
        return 1

    outbounds = [to_singbox(c, f"s{i+1}") for i, c in enumerate(live)]
    with open(LIVE_JSON, "w", encoding="utf-8") as f:
        json.dump(outbounds, f, indent=2, ensure_ascii=False)

    print(f"wrote {len(outbounds)} outbounds to {LIVE_JSON}")
    print("\nNOTE: tcp reachable does not mean the handshake works.")
    print("      Test each one with a real request before trusting it:")
    print('      Invoke-RestMethod https://api.ipify.org -Proxy http://127.0.0.1:18888')
    return 0


if __name__ == "__main__":
    import urllib.parse  # noqa: E402  (used inside parse)
    sys.exit(main())
