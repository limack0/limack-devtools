# Dev.to — article long-form : "Pourquoi j'ai construit peek au lieu de faire confiance à curl | sh"

> Status: draft — audité AI-authorship ✅ / claims vérifiés ✅ / peek = heuristique, pas sandbox (honnête) ✅
> Frontmatter dev.to inclus. À coller dans l'éditeur dev.to.

---

```yaml
---
title: "I stopped trusting curl | sh — so I built a tool that reads the script first"
published: true
tags: [security, shell, devtools, opensource]
cover_image:
canonical_url:
---
```

---

Every developer has done it.

You hit a README, you see the install command:

```sh
curl -fsSL https://example.com/install.sh | sh
```

And you run it. Maybe you skim the script first. Maybe you don't. But you run it.

I've been doing this for years. And each time, a small voice in the back of my head says: *you have no idea what that script actually does. You just piped a stranger's code straight into your shell.*

Eventually I got tired of ignoring that voice.

---

## What the pattern actually is

`curl | sh` is not a bad pattern — it's a fast, convenient pattern with a real trust gap. The script runs with your permissions, in your shell, right now. It can:

- Install something with `sudo`
- Delete files with `rm -rf`
- Write to your disk with `dd`
- Access your SSH keys or `.env` files
- Set up a cron job or a systemd service that runs again next reboot
- Decode and run a payload with `base64 | eval`

Most install scripts do none of these things maliciously. But many do several of them legitimately — and you wouldn't know which ones until something went wrong.

---

## What I built instead

I'm a solo founder based in Ouagadougou, Burkina Faso. I build with heavy AI pairing — I'm not a trained engineer, I work with Claude, review the output, and ship. This tool (`peek`) was AI-paired and reviewed by me before release.

**peek** is a ~130-line POSIX shell script that sits in front of the pattern:

```sh
# Instead of:
curl -fsSL https://example.com/install.sh | sh

# Do:
peek https://example.com/install.sh
```

Before anything runs, peek:

1. Fetches the script
2. Scans it for risky patterns
3. Prints a risk score and the exact dangerous lines
4. Asks you to confirm — and refuses to auto-run a HIGH-RISK script unless you type `RUN`

You can also pipe into it, or run it in analysis-only mode:

```sh
curl -fsSL https://example.com/install.sh | peek     # analyze from a pipe
peek --print ./downloaded.sh                          # never runs, analysis only
```

---

## What it flags (and what it doesn't)

The patterns peek checks:

- **Root escalation** — `sudo`, running as root
- **Destructive file ops** — `rm -rf`, `find -delete`
- **Raw disk writes** — `dd of=/dev/sd`, `mkfs`
- **Obfuscated payloads** — `eval`, `base64 -d | sh`
- **Credential access** — reads from `~/.ssh`, `.env`, `.aws`
- **Persistence** — writes to cron, `systemctl enable`, init scripts
- **Network calls** — `wget`/`curl` inside the script (downloading more things)
- **Generic secret assignments** — `secret=`, `password=`, `token=`, `key=`

Each finding has a severity (CRITICAL / HIGH / MEDIUM / INFO). The final score gates the auto-run.

---

## The honest part: it's a heuristic, not a sandbox

This is important and I want to say it plainly.

**peek can be fooled.** If a script:
- uses obfuscation peek doesn't recognise yet
- downloads a second-stage payload after running
- does something destructive through a helper binary it installs first

...peek won't catch it. A clean score does not mean a script is safe. It means nothing obvious matched.

The real value isn't "this script is safe." The real value is: **it makes you stop and look**, and it surfaces the lines you'd otherwise skim past.

For HIGH-RISK scripts, peek will refuse to auto-run and will page the full script so you can read it yourself. That's the intended workflow: peek narrows your attention to the suspicious parts, then you judge.

I considered putting a disclaimer like "always read the full script before running" in the output. Then I realized: peek IS that disclaimer, in executable form.

---

## Yes, I see the irony

The pack that contains peek has its own one-liner installer:

```sh
curl -fsSL get.limackcorp.online | sh
```

I see the irony. So: before you use peek to audit anyone else's scripts, read mine first.

`peek.sh` is ~130 lines of plain POSIX shell, no dependencies, no hidden calls. The repo is at https://github.com/limack0/limack-devtools — read it, then use peek to audit it if you want the recursive experience.

---

## peek is part of a larger pack

I built 11 other tools in the same session, all single-file shell scripts, all targeting the same constraint: **things that work when the infrastructure doesn't**.

The ones most related to this post:

- **secrets-doctor** — scans your files for leaked API keys, tokens, private keys. Local-only, nothing uploaded, exits non-zero in CI.
- **tunnelforge** — exposes a local port via Cloudflare in one command. No ngrok account.
- **devbox** — sets up a dev machine including an offline mode: prep all installers on a connected machine, deploy on an air-gapped one.

Full pack: https://github.com/limack0/limack-devtools

---

## What I'd genuinely want feedback on

The pattern list in `peek.sh` is where I'm least confident. Specifically:

1. **False negatives** — what risky patterns am I missing? (Particularly multi-stage obfuscation, environment hijacking, LD_PRELOAD tricks)
2. **False positives** — the generic `secret=...` rule is the noisiest. What good scripts would peek flag unfairly?
3. **The scoring weights** — is CRITICAL/HIGH/MEDIUM calibrated right, or should the thresholds shift?

PRs very welcome. The whole point of an open-source script is that you can see exactly what it's doing — and improve it.

---

*All tools in this pack were AI-paired with Claude, reviewed and pushed by me.*
