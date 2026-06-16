<h1 align="center">Lim@ck DevTools</h1>

<p align="center">
  <b>One command. A menu of dev tools that respect your bandwidth and your trust.</b><br>
  <i>Offline-first · francophone-friendly · audit-before-you-run.</i>
</p>

<p align="center">
  <a href="#-quick-start">Quick start</a> ·
  <a href="#-the-tools">Tools</a> ·
  <a href="#-why-a-hub">Why a hub</a> ·
  <a href="#-security">Security</a>
</p>

---

> **One repo. One domain. One command.** The only official source. Be wary of copies — see [Security](#-security).

## ⚡ Quick start

```sh
curl -fsSL get.limackcorp.online | sh
```

You get a menu. Pick a tool — it installs into `~/.local/bin`, or runs once. That's it.

Install a single tool directly, no menu:
```sh
curl -fsSL get.limackcorp.online | sh -s -- install peek
curl -fsSL get.limackcorp.online | sh -s -- run devbox --profile=web --silent
```

## 🧰 The tools

| Tool | What it does | Why it's different |
|------|--------------|--------------------|
| **devbox** | Sets up a dev machine (git, node, python, docker, dotfiles). | **Offline mode**: prep installers once, deploy anywhere with no network. The part every dotfiles repo forgets. |
| **peek** | Inspects a remote install script — scores its risk, shows the dangerous lines, asks before running. | The **antidote to `curl \| sh`**. The trust layer the whole pattern is missing. |
| **sneakersync** | Moves a git repo between machines over a USB key, no shared network — full or delta. | `git bundle` made dead-simple. Built for places where the **network is the unreliable part**. |
| **wat** | Pipe a command's error in, get a plain-**French** explanation and the exact fix (via OpenRouter). | Stops francophone devs copy-pasting cryptic stack traces into a search box. |
| **resurrect** | Snapshots this machine's tools/packages/config into a portable manifest; rebuilds it elsewhere. | A **Time Machine for dev boxes** — "my laptop died, give me the same" in one command. |
| **litemirror** | Turns one machine into a LAN package cache (pip/apt). Download once, install on N machines. | One good link feeds the whole room — built for **slow/metered connections**. |
| **tunnelforge** | Exposes a local port to the internet in one command via cloudflared. | **No ngrok account, no rate limits.** Quick ephemeral URL, or a stable one on your own domain. |
| **deadman** | Monitors services (http/tcp/command) and heartbeats; pings you on **Telegram** when something dies or recovers. | Personal uptime + dead-man's switch in one command. Alerts only on **state changes** — no spam. |
| **secrets-doctor** | Scans files for leaked API keys, tokens and private keys; gates commits via a pre-commit hook. | **100% local — nothing is uploaded.** Redacts findings, exits non-zero so it works in CI and hooks. |
| **relay** | Run any command through it: offline, it's queued and sent automatically when the network returns. | Makes **intermittent connectivity a non-event** — you keep working, it syncs when it can. |
| **fr** | Ask any dev question in French; get a concise answer tuned for the francophone / West-African context. | A terminal assistant in **your** language — stop translating questions into English first. |
| **oneshot** | Turns a fresh VPS into an app host: Docker + a Caddy auto-HTTPS reverse proxy + one-line app deploys. | Bring a domain, get a live HTTPS site. `--dry` previews every step. |
| **landrop** | Shares one machine's local AI model (Ollama) across the LAN so everyone queries it. | **Offline AI** — the strong box in the room serves the rest. No cloud, no per-seat downloads. |

### peek — make `curl | sh` safe

```sh
peek https://example.com/install.sh     # fetch, score, show, ask
curl -fsSL https://example.com/i.sh | peek   # analyze from a pipe
peek --print ./downloaded.sh             # analysis only, never runs
```

peek flags root usage, `rm -rf`, raw-disk writes, obfuscation/eval, credential access, persistence, and more — then refuses to auto-run HIGH-RISK scripts without an explicit `RUN` confirmation.

### devbox — your machine, ready in one line

```sh
curl -fsSL get.limackcorp.online | sh -s -- run devbox            # interactive
curl -fsSL get.limackcorp.online | sh -s -- run devbox --offline --profile=all
```

Prepare offline bundles on a connected machine with `tools/devbox-offline-bundle.sh`, copy `~/.devbox-init/offline/` to the target, install with no network.

### sneakersync — git over USB, no network

```sh
sneakersync push  /media/usb           # bundle this repo onto the key (delta after the first time)
sneakersync list  /media/usb           # what's on the key
sneakersync pull  /media/usb           # fetch into this repo, safely under refs/sneaker/*
sneakersync clone /media/usb myrepo .  # fresh clone from a bundle
```

### wat — explain an error in French

```sh
npm run build 2>&1 | wat        # explain whatever failed
wat -- pytest                   # run it, explain only on failure
wat --dry -- ls /nope           # show the request, never calls the API
```

Set `OPENROUTER_API_KEY` first. Override the model with `WAT_MODEL`, the language with `WAT_LANG`.

### resurrect — Time Machine for your dev environment

```sh
resurrect save                  # snapshot this machine -> manifest file
resurrect show   <file>         # read it back
resurrect diff   <file>         # what's missing on this machine
resurrect restore <file>        # plan the rebuild (dry)
resurrect restore <file> --apply   # actually reinstall
```

Captures tool versions, manually-installed packages (apt/brew/dnf/pacman), uv/pipx/npm globals, and git config.

### litemirror — one machine feeds the LAN

```sh
litemirror pull pip requests flask    # cache wheels once, on the connected box
litemirror pull apt build-essential   # cache .deb
litemirror serve                      # serve the cache over the LAN
litemirror client                     # print what other machines should set
```

On every other machine:
```sh
pip install --no-index --find-links http://<mirror-ip>:8919/pip <pkg>
```

### tunnelforge — share localhost, no ngrok

```sh
tunnelforge 3000                # instant https://<random>.trycloudflare.com
tunnelforge 3000 demo           # stable https://demo.limackcorp.online (your domain)
tunnelforge 3000 demo --dry     # show the plan, change nothing
tunnelforge list                # your named tunnels
tunnelforge rm demo             # delete one
```

Quick mode needs nothing. Named mode needs a cloudflared origin cert (`cloudflared tunnel login`). Set your domain with `TUNNELFORGE_DOMAIN`.

### deadman — uptime + dead-man's switch, alerts on Telegram

```sh
deadman add api https://api.example.com         # http check
deadman add db  db.example.com:5432             # tcp check
deadman add disk --cmd 'df / | awk "NR==2 && \$5+0>90{exit 1}"'
deadman add nightly-backup --beat 90000         # must check in within 25h
deadman beat  nightly-backup                    # ...call this from the cron job
deadman check                                    # run once (cron this every N min)
deadman watch --interval 60                      # or loop in the foreground
```

Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`. It alerts only when a target's
state **changes** (up→down or down→up). `DEADMAN_DRY=1` prints alerts instead of
sending them. Typical use: `*/5 * * * * deadman check` in cron.

### secrets-doctor — catch leaked secrets locally

```sh
secrets-doctor scan [path]      # scan a dir/file (default .)
secrets-doctor staged           # scan only git-staged files
secrets-doctor install-hook     # pre-commit hook that blocks leaking secrets
```

Detects AWS/GitHub/Slack/Google/OpenAI/Stripe/Telegram keys, JWTs, private-key
blocks and generic `secret=...` assignments. Findings are **redacted** (first
4 chars only) and obvious placeholders are skipped. Nothing ever leaves the
machine. Exit code is non-zero on findings, so CI and pre-commit hooks can gate on it.

### relay — connectivity that's *eventual*, not binary

```sh
relay git push                 # online? runs now. offline? queued.
relay -- curl -X POST api/deploy
relay status                   # network state + what's waiting
relay flush                    # send the queue now
relay daemon                   # auto-send whenever the network returns
```

Most tools error out the moment the network blinks. relay queues the command
instead and sends it automatically once you're back online — in order, with
dedupe. Commands that fail for a *non-network* reason are parked in `failed/`
so a broken one never blocks the queue. Optional Telegram pings when jobs send
(`TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`). Built for connections that drop.

### fr — your francophone dev assistant

```sh
fr comment annuler le dernier commit git sans perdre mes fichiers
fr "écris une fonction python qui lit un csv"
cat erreur.log | fr "c'est quoi ce problème ?"      # pipe context in
fr --dry "..."                                       # show the request, no API call
```

Set `OPENROUTER_API_KEY`. Answers come back in French, concise, with concrete
commands/code, tuned for limited-bandwidth contexts. Override the model with `FR_MODEL`.

### oneshot — fresh VPS to live host

```sh
oneshot init                                   # install docker + firewall
oneshot host --email you@example.com           # auto-HTTPS reverse proxy
oneshot add blog --image ghcr.io/you/blog --port 3000 --domain blog.example.com
oneshot status | logs <name> | rm <name>
```

Routing and TLS are automatic: apps run on the `oneshot` network with `caddy`
labels, and [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy)
fetches Let's Encrypt certs for each domain once DNS points at the server. Add
`--dry` to any command to preview without changing anything. `init`/`host` need root.

### landrop — offline AI for the whole LAN

```sh
# on the strongest machine (needs Ollama: curl -fsSL https://ollama.com/install.sh | sh)
landrop serve --model llama3.2:1b      # host the model on the LAN
landrop client                          # prints what others should set

# on every other machine
export LANDROP_HOST=http://<server-ip>:11434
landrop ask "explique les pointeurs en C"
cat erreur.log | landrop ask "c'est quoi ce crash ?"
```

Built on [Ollama](https://ollama.com): one box runs the model, the rest query it
over the LAN — no cloud, no per-machine downloads. Pick a small model
(`qwen2.5:0.5b`, `llama3.2:1b`) for low-RAM hosts. `landrop ask --dry` shows the
request without calling the server.

## 🧠 Why a hub

Twelve scattered repos = twelve reputations to build. **One hub = one URL to share, one repo to star, compounding trust.** Every new tool joins the menu and rides the same distribution. This is the model that made single-script tools spread.

## 🔒 Security

Piping a script into your shell is dangerous **if you don't trust the source**. So:

- **Open-source.** Every line is in this repo. Read it. (Better yet, read it *with* `peek`.)
- **One canonical source:** this repo + `get.limackcorp.online`. Anything else is a fork — audit it.
- **No hidden calls.** Tools use official upstreams, listed in each script.
- **User stays in control.** Installs go to user space; nothing auto-runs as root without explicit confirmation.

## 📜 License

MIT.
