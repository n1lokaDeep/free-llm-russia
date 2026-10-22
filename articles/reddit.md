# Getting free LLM APIs to work from Russia: Cloudflare, WARP, and a bug I wrote myself

I spent an evening on a task that sounds trivial: "make free LLM models answer from Russia." It turned out to be three different problems that look identical, plus a trap I walked straight into.

Here are the actual logs and commands.

---

## Symptom one: `403 Access denied by security policy`

The agent printed nothing useful:

```
AI_APICallError: Forbidden
```

I assumed the API key was wrong, generated a new one, pasted it. Same result.

So I dumped the raw response headers:

```
HTTP 403 Forbidden
Server: cloudflare
CF-RAY: a4d9c891184604fe-HKG
Set-Cookie: __cf_bm=...
{"success": false, "error": "Access denied by security policy."}
```

There it is. **`CF-RAY` means Cloudflare answered, not the service.** `Access denied by security policy` is an edge block based on IP reputation. The request never reached OpenRouter — the key was never checked.

How to tell these apart:

```
403 + Access denied by security policy  ->  IP block, key is irrelevant
401 + Authentication Fails              ->  wrong key, or key for a different service
404 + Not found for account             ->  model not available to your account
429                                     ->  rate limit
```

**Rotating the key does not help with a 403.** I tried two different keys from the same IP — identical 403.

One more detail. Across runs the `CF-RAY` changed:

```
CF-RAY: ...-HKG   (Hong Kong)
CF-RAY: ...-DME   (Moscow)
```

The block is not tied to a datacenter. It is tied to **your IP**. The only fix is changing the address.

---

## Symptom two: WARP does not work, and it is not obvious why

The standard advice is "just use Cloudflare WARP, it's free."

I had a client with a bundled WARP profile. Connecting failed with:

```
error patching outbound[m4 § 0][custom]:
netip.ParsePrefix("/24"): ParseAddr(""): unable to parse IP
```

The config explained it:

```json
"warp": {
    "enable": false,
    "clean-ip": "auto",
    "account-id": "",
    "access-token": "",
    "wireguard-config": ""
}
```

Empty. The WARP account was never registered, so `clean-ip: auto` resolves to nothing, and the parser chokes on an empty address.

Why unregistered? Check the endpoints:

```
188.114.97.170:894       ->  blocked
162.159.192.1:894        ->  blocked
api.cloudflareclient.com ->  timeout
```

**The WARP registration servers are unreachable.** No account, no working profile.

And the irony worth the whole write-up: **WARP hands you a Cloudflare address. Cloudflare is what is blocking you.** Even if it connected, you would be reaching Cloudflare through Cloudflare.

**Conclusion: WARP is not a fix here.** Not "needs configuring" — the endpoints are blocked.

---

## What actually works: a local proxy instead of a VPN

A full VPN needs administrator rights to create a TUN adapter. I did not have them, and it turned out not to matter.

The distinction people mix up:

| | VPN (TUN) | Local proxy |
|---|---|---|
| Covers | the whole machine | only the programs you point at it |
| Needs admin | **yes** | **no** |
| Good for | browser, games, everything | one specific tool |

I needed one agent to work. A local proxy was enough: `sing-box` listens on `127.0.0.1:18888`.

### The trap I fell into

I did the thing that seems obvious and set the proxy **globally**:

```powershell
[Environment]::SetEnvironmentVariable('HTTPS_PROXY','http://127.0.0.1:18888','User')
```

The agent worked. Then **Roblox stopped launching**:

```
HttpError: ConnectFail
Critical failure fetching flags, terminating application.
```

It was routing through my proxy, the proxy was restarting, the connection dropped, and the client died.

**Global proxy variables are inherited by every process.** Games, launchers, updaters — everything that should not use the proxy uses it, and breaks.

Set it **inside the process only**:

```powershell
$env:HTTPS_PROXY = 'http://127.0.0.1:18888'
& myapp.exe
```

One program sees it. Nothing else does.

---

## Symptom three: where to get servers

Public `vless://` configs live in open repos. I pulled a list:

```
2196 reality configs, 1053 unique hosts
```

Now the interesting part. **Checking these with ping or `Test-NetConnection` is useless.** With Reality the TCP port can be open while the handshake fails. The port accepts, but the TLS session never comes up.

The only real test is an HTTP request **through the proxy**, comparing the exit IP to your own:

```powershell
Invoke-RestMethod https://api.ipify.org -Proxy http://127.0.0.1:18888
```

If it returns **your own** IP, traffic went direct and the proxy did nothing.

**Measured: out of 5681 configs, 2 were alive.**

### And then I caught myself

I wrote a Python checker. It reported cheerfully:

```
[1] OK  77.110.105.122      exit IP 94.245.148.251
[2] OK  158.160.160.21      exit IP 94.245.148.251
working: 6 / 6
```

Six out of six! Except **all six returned the same IP — mine.** `urllib` silently fell back to a direct connection, and the script counted it as success.

After adding an IP comparison, the honest result:

```
[1] fail  77.110.105.122
[2] fail  158.160.160.21
working: 0 / 8
```

**A check that cannot distinguish "it worked" from "it failed but the request succeeded anyway" is worse than no check.** It produces false confidence.

---

## What works, in short

**No proxy needed** (no region block, key obtainable):
- Z AI (Zhipu) — `open.bigmodel.cn`, GLM-4.7-Flash, no card
- Mistral — `api.mistral.ai`, ~$10/month in credits
- OVHcloud AI — no key at all, 2 requests/minute
- ModelScope, SiliconFlow — identity verification required

**Proxy required:**
- OpenRouter — 50 requests/day **per model**, no card needed
- Groq — 30 RPM, 1000 RPD, very fast
- Google Gemini — 15 RPM, 1500 RPD
- Cloudflare Workers AI — 10,000 neurons/day
- NVIDIA NIM — 40 RPM, 10,000 RPD

**Does not work at all from RU:**
- ChatGPT / OpenAI API — full regional block
- Claude / Anthropic API — full regional block
- Cloudflare WARP — endpoints blocked

On OpenRouter specifically: **50 requests/day per free model**, not a shared pool. A one-time $10 credit purchase raises it to 1000/day.

---

## Scripts

Everything is in an open repo:

**github.com/n1lokaDeep/free-llm-russia**

| File | Purpose |
|---|---|
| `check-configs.py` | filter candidates from a public config list |
| `verify-live.py` | verify each with a real request (guards against false positives) |
| `start-proxy.ps1` | bring up the local proxy on `127.0.0.1:18888` |
| `proxy.ps1` | start / stop / restart / status |

```powershell
python scripts/check-configs.py --top 80
python scripts/verify-live.py
powershell -File scripts/start-proxy.ps1
powershell -File scripts/proxy.ps1 status
```

The repo also has the full provider table with "needs a card", "needs a VPN", limits, and the error-diagnosis table.

---

## Takeaways

1. **`403 Access denied by security policy` is an IP block, not a key problem.** Check for `CF-RAY`: if it is there, Cloudflare answered, not the service.

2. **WARP does not work here** — registration servers are blocked. And even if it did, you would reach Cloudflare through Cloudflare.

3. **Never set proxy variables globally.** It breaks games and launchers with `ConnectFail`. Set them per process.

4. **Verify proxies with a real request and an IP comparison.** An open TCP port means nothing.

5. **Public configs die fast.** 2 alive out of 5681. Automate the filtering.

---

If you have hit similar blocks, or spot an error in the provider table, tell me and I will update it. Providers change policy without notice.
