# Hardening Checklist 🔒

**The fastest path: just run the one-liner and let it do the work.**

```bash
curl -sSL https://raw.githubusercontent.com/JuanAtLarge/openclaw-safe/main/install.sh | bash
```

That runs the full audit and tells you exactly what to fix. Then `./harden.sh` fixes most of it automatically.

If you want to understand what's happening under the hood, or prefer to do things step by step, read on.

---

## Step 1: Check Your Version (CRITICAL — takes 10 seconds)

**Versions before v2026.2.25 are vulnerable to remote takeover (ClawJacked).**

```bash
openclaw --version
```

If it's older than `2026.2.25`, update now:

```bash
npm update -g openclaw
openclaw gateway restart
```

✅ **Safe:** v2026.2.25 or later
❌ **Update immediately:** anything before v2026.2.25

---

## Step 2: Run the Automated Audit + Hardener

This is the whole checklist in two commands:

```bash
# See what needs fixing:
bash audit.sh

# Fix it automatically:
bash harden.sh
```

`harden.sh` will:
- Show you exactly what it's going to change
- Ask `[y/N]` before touching anything
- Back up your config first
- Offer to restart OpenClaw when done

You don't need to edit any config files manually.

---

## Step 3: Check Your Cron Jobs

```bash
openclaw cron list --json
```

Look for crons that read external content (emails, RSS feeds, websites) AND take external actions (posts, API calls). These are your highest-risk crons — a malicious instruction hidden in a webpage or email could get your agent to act on it.

**What to look for:**
- `sessionTarget` should be `"isolated"` for any cron reading external content
- Scope should be narrow — only do what's needed

---

## Step 4: Audit Installed Skills

```bash
bash scan-skills.sh
```

This checks your installed skills for suspicious patterns. For extra coverage, set a free VirusTotal API key:

```bash
VIRUSTOTAL_API_KEY=your_key bash scan-skills.sh
```

**The stat worth knowing:** ~8% of ClawHub skills are malicious. Treat every skill like a third-party app install — check before you run.

---

## Step 5: Protect Your Memory Files

Memory files in `~/.openclaw/workspace/memory/` are read by every agent session. If one gets poisoned via prompt injection, it affects everything.

```bash
ls ~/.openclaw/workspace/memory/
```

Look for anything odd — instructions that don't sound like you, unusual links, unexpected commands. See `MEMORY_SAFETY.md` for the full guide.

---

## Step 6: Rotate Your Gateway Token (if ever shared)

If you've ever shared your `openclaw.json`, committed it to git, or pasted it anywhere online, rotate the gateway token:

```bash
openclaw gateway token rotate
```

---

## Step 7: Install ClawSec (optional but recommended)

```bash
bash install-clawsec.sh
```

ClawSec is a free tool from Prompt Security (a SentinelOne company) that wraps your agents in continuous verification and zero-trust egress. Not required, but adds a meaningful layer.

---

## Ongoing Habits

- [ ] Update OpenClaw when new versions drop
- [ ] Re-run `audit.sh` quarterly or after anything unusual
- [ ] Read the full prompt of any cron before enabling it
- [ ] Don't install ClawHub skills you don't need
- [ ] Review memory files periodically if you have active external-reading crons
