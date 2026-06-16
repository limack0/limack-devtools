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
| _more coming_ | tunnel, litemirror, resurrect… | Each one solves an acute pain in one command. |

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
