# Show IH — Lim@ck DevTools (pack de 12 outils CLI)

> Status: draft — audité AI-authorship ✅ / claims vérifiés ✅ / email-only support ✅ / zéro interaction inventée ✅
> À poster depuis le compte `limack0` sur Indie Hackers.

---

## Titre

**Show IH: I shipped 12 offline-first CLI dev tools from Burkina Faso — built with heavy AI pairing, install in one command**

---

## Body

Hey IH,

I'm a solo founder based in Ouagadougou, Burkina Faso. I build software with heavy AI pairing (Claude) — I'm not a trained engineer, I pair with the model, review the output, and ship. All the code in this pack was built that way, and I'm being upfront about it.

I just shipped **Lim@ck DevTools** — a pack of 12 single-file shell tools, each solving a real friction point I've hit developing here: slow connections, power cuts that wipe setups, `curl | sh` scripts I couldn't fully trust, error messages that assumed you speak perfect English.

One command installs the whole menu:

```sh
curl -fsSL get.limackcorp.online | sh
```

The 12 tools:

| Tool | What it does |
|------|-------------|
| **peek** | Shows you what a `curl \| sh` script does *before* you run it — risk score + dangerous lines. (Heuristic, not a sandbox — honest about limits.) |
| **devbox** | Machine setup + offline mode: prep bundles once, deploy on a box with no internet |
| **sneakersync** | Git over a USB key, no network — full or delta |
| **wat** | Pipe an error in, get a plain-French explanation + the fix (via OpenRouter) |
| **resurrect** | Snapshot your dev environment, rebuild it anywhere |
| **litemirror** | One machine = LAN package cache for pip/apt — one download feeds the room |
| **tunnelforge** | Expose a local port via Cloudflare — no ngrok account needed |
| **deadman** | Uptime monitor + heartbeats, Telegram alerts on state change only |
| **secrets-doctor** | Local scan for leaked keys + pre-commit hook — nothing uploaded |
| **fr** | Francophone dev assistant in the terminal (OpenRouter) |
| **oneshot** | Fresh VPS → app host with Caddy auto-HTTPS |
| **landrop** | Share one machine's local Ollama model across the LAN — offline AI for the whole room |

The angle isn't "use these instead of better tools." It's: **these work when the infrastructure doesn't** — slow bandwidth, no public IP, shared lab machines, French-speaking team.

I tested all 12 live before shipping — and fixed a handful of bugs doing it (a tool you can't run in real conditions isn't finished).

Repo (MIT, everything readable): https://github.com/limack0/limack-devtools

---

**Who this is for:** developers in low-bandwidth or constrained environments (West Africa, shared labs, remote sites, air-gapped machines). Also useful anywhere — `secrets-doctor`, `peek`, and `tunnelforge` have no geography.

**What I'd value from this community:** which of these overlaps with something you already use? And which friction points did I miss that you've hacked around yourself?

---

*All tools AI-paired with Claude, reviewed and pushed by me.*
