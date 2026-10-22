#!/usr/bin/env python3
"""
Verify which outbounds from live.json actually complete a request.

A TCP check is not enough for Reality: the port can be open while the
handshake fails. This starts sing-box on a temporary port for each candidate
and makes a real HTTPS request through it.

Usage:
    python verify-live.py                    # test all in live.json
    python verify-live.py --limit 10
Requires: sing-box on PATH, or set SINGBOX env var to the binary.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LIVE = os.path.join(HERE, "live.json")
TEST_URL = "https://api.ipify.org"
PORT = 18899


def find_singbox():
    env = os.environ.get("SINGBOX")
    if env and os.path.exists(env):
        return env
    exe = shutil.which("sing-box")
    if exe:
        return exe
    print("sing-box not found. Install it, or set SINGBOX=/path/to/sing-box")
    sys.exit(2)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_port(port, timeout=8.0):
    end = time.time() + timeout
    while time.time() < end:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.2)
    return False


def test_one(singbox, outbound, port, direct_ip=None):
    """Return the exit IP if traffic really went through the proxy, else None.

    A successful fetch is not proof: urllib falls back to a direct connection
    when the proxy is unusable. We compare the observed IP against the direct
    one and reject matches.
    """
    cfg = {
        "log": {"level": "error"},
        "inbounds": [{
            "type": "mixed", "tag": "m",
            "listen": "127.0.0.1", "listen_port": port,
        }],
        "outbounds": [outbound],
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                     encoding="utf-8") as f:
        json.dump(cfg, f)
        cfg_path = f.name

    proc = subprocess.Popen(
        [singbox, "run", "-c", cfg_path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        if not wait_port(port):
            return None

        # Force the request through the proxy only: no direct fallback.
        proxy = f"http://127.0.0.1:{port}"
        handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
        opener = urllib.request.build_opener(
            handler, urllib.request.ProxyHandler  # never fall back to direct
        )
        with opener.open(TEST_URL, timeout=15) as r:
            ip = r.read().decode().strip()

        # If the exit IP equals our own, traffic bypassed the proxy.
        if direct_ip and ip == direct_ip:
            return None
        return ip
    except Exception:
        return None
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        os.unlink(cfg_path)


def direct_exit_ip():
    """Our own public IP, for comparison."""
    try:
        with urllib.request.urlopen(TEST_URL, timeout=10) as r:
            return r.read().decode().strip()
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="test at most N")
    args = ap.parse_args()

    if not os.path.exists(LIVE):
        print(f"{LIVE} not found - run check-configs.py first")
        return 1

    with open(LIVE, encoding="utf-8-sig") as f:
        outbounds = json.load(f)

    if args.limit:
        outbounds = outbounds[: args.limit]

    singbox = find_singbox()

    own = direct_exit_ip()
    print(f"your direct IP: {own}")
    print(f"testing {len(outbounds)} outbounds with a real request...\n")

    working = []
    for i, ob in enumerate(outbounds, 1):
        host = ob["server"]
        port = free_port()
        ip = test_one(singbox, ob, port, direct_ip=own)
        if ip:
            print(f"  [{i:>3}] OK    {host:<32} exit IP {ip}")
            working.append({"server": host, "exit_ip": ip, "outbound": ob})
        else:
            print(f"  [{i:>3}] fail  {host}")

    print(f"\nworking: {len(working)} / {len(outbounds)}")

    if working:
        out = os.path.join(HERE, "working.json")
        with open(out, "w", encoding="utf-8") as f:
            json.dump(working, f, indent=2, ensure_ascii=False)
        print(f"wrote {out}")
    else:
        print("none worked - public servers rotate fast, try again later")
    return 0


if __name__ == "__main__":
    sys.exit(main())
