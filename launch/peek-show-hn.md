# Show HN — peek

> Status: draft. Honest, no inflated claims. Discloses AI pairing. Post from the `limack0` account.

---

## Title (pick one)

- **Show HN: Peek – see what a `curl | sh` script does before you run it**
- Show HN: Peek – a risk check for `curl | sh` installers

## Body

Hi HN,

Like everyone, I install things with `curl -fsSL https://… | sh` constantly. And every time a small voice says: you have no idea what's in that script — you're piping a stranger's code straight into your shell.

**peek** is a tiny POSIX shell script that sits in front of that pattern. You give it a URL (or pipe the script in), and before anything runs it:

- fetches the script and flags risky patterns — `sudo`, `rm -rf`, raw-disk writes (`dd of=/dev/sd…`), `eval` / base64-decoded payloads, credential access (`~/.ssh`, `.env`), background persistence (`cron`, `systemctl`)
- prints a **risk score** and the **exact dangerous lines**
- asks you to confirm, and refuses to auto-run a HIGH-RISK script unless you type `RUN`

```
peek https://example.com/install.sh
curl -fsSL https://example.com/i.sh | peek      # analyze from a pipe
peek --print ./downloaded.sh                     # analysis only, never runs
```

**Honest about what it is:** it's a heuristic, not a sandbox. Regexes can be fooled by obfuscation, and a clean score doesn't mean a script is *safe* — it means nothing obvious matched. The real value is that it makes you **look before you run**, and surfaces the scary lines you'd otherwise skim past. For anything HIGH-RISK, read the whole thing (peek will page it for you).

And yes — I see the irony of shipping a one-liner installer for an anti-one-liner tool. So: read [`peek.sh`](https://github.com/limack0/limack-devtools/blob/main/tools/peek.sh) first. It's ~130 lines of plain shell.

It's part of a small pack of offline-first dev tools I've been building — `devbox` (machine setup), `sneakersync` (git over a USB key, no network), `litemirror` (turn one box into a LAN package cache), and a few more — all single shell scripts, one command each.

I'm not a security engineer. I'm a solo founder in Burkina Faso and I build these with heavy AI pairing, so I'd genuinely value scrutiny of the heuristics: **what patterns am I missing, and what would throw false alarms?**

- Code: https://github.com/limack0/limack-devtools (read `tools/peek.sh`)
- The pack: `curl -fsSL get.limackcorp.online | sh` (then pick peek)

Thanks for taking a look.

---

## Notes for posting
- Best window: weekday morning US time. Don't ask anyone to upvote/comment (against HN rules and it backfires — see prior launch lessons).
- First comment from me: pin the honest limitations (heuristic vs sandbox) so the framing is set before critics arrive.
- Expect "just read the script" replies — agree, and point out peek is the thing that makes you actually do that.
- If asked about false positives: the generic `secret=...` rule is the noisiest; invite PRs on the rule list.
