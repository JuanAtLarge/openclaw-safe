# Hardening Checklist 🔒

Work through this top to bottom. Every item is actionable — no vague advice.

---

## Step 1: Version Check (CRITICAL)

**Versions before v2026.2.25 are vulnerable to ClawJacked remote takeover.**

```bash
openclaw --version
```

If it shows anything earlier than `2026.2.25`, update immediately:

```bash
npm update -g openclaw
# or if you used pnpm:
pnpm update -g openclaw
```

Then restart the gateway:
```bash
openclaw gateway restart
```

✅ **Safe:** v2026.2.25 or later  
⚠️ **Update needed:** anything before v2026.2.25

---

## Step 2: Run the Built-In Security Audit

```bash
openclaw security audit
openclaw security audit --deep
```

Read every WARN and CRITICAL. Don't skip them.

---

## Step 3: Lock Down Plugin Auto-Loading

If you see this warning in any openclaw output:
> `plugins.allow is empty; discovered non-bundled plugins may auto-load`

Fix it by explicitly listing trusted plugins in `~/.openclaw/openclaw.json`:

```json
{
  "plugins": {
    "allow": ["telegram"]
  }
}
```

This prevents unknown plugins from silently loading.

---

## Step 4: Check Your Crons for External Content Risk

```bash
openclaw cron list --json
```

Look at every cron job. Flag any that:
- Fetch URLs or RSS feeds (`web_fetch`, `web_search`)
- Read emails or Reddit posts
- Browse the web via `browser` tool
- Write output to shared state files other crons also read

**These are your highest-risk crons.** They're reading untrusted external content and taking actions. If a malicious website injects instructions into that content, your agent will follow them.

**What you can do:**
- Keep cron scope narrow — only do what's needed, nothing else
- Don't write web-fetched content directly into memory files
- Add a "review gate" for high-stakes actions (email sends, posts, etc.)

---

## Step 5: Audit Installed Skills

```bash
openclaw skills list
```

For each skill marked `✓ ready`, ask:
- Did I install this from ClawHub? Check it with ClawSec.
- Does the SKILL.md give the agent broad exec/file/browser access?
- Has it been updated recently? (Malicious updates are a real attack vector)

**The stat that should worry you:** 824 out of 10,700 ClawHub skills are malicious. That's ~8%.

If you installed skills from ClawHub, run ClawSec:
```bash
# If ClawSec is installed:
clawsec scan ~/.openclaw/skills/
clawsec scan ~/.agents/skills/
```

---

## Step 6: Protect Your Memory Files

Memory files in `~/.openclaw/workspace/memory/` are read by every agent session. If one gets poisoned via prompt injection, it affects all sessions.

**Check what's in memory:**
```bash
ls ~/.openclaw/workspace/memory/
cat ~/.openclaw/workspace/memory/YYYY-MM-DD.md  # today's date
```

Look for anything that seems off — instructions that don't sound like you, unusual file paths, unexpected links.

**Ongoing hygiene:**
- Don't let crons write raw web content into memory files
- State files (twitter-state.json, etc.) should be separate from memory/
- Review memory files periodically — at least weekly if you have active crons

---

## Step 7: Gateway Security

The Control UI runs at `http://127.0.0.1:18789`. Keep it local-only unless you have a specific reason to expose it.

If you're using a reverse proxy (nginx, Caddy), configure trusted proxies:

```json
{
  "gateway": {
    "trustedProxies": ["127.0.0.1"]
  }
}
```

If you're NOT using a reverse proxy (most personal setups), leave it — the loopback binding already protects you.

---

## Step 8: Auth Token Rotation

Your gateway auth token is in `~/.openclaw/openclaw.json` under `gateway.auth.token`. 

If you've ever:
- Shared this file
- Committed it to a git repo
- Pasted config to get help online

Rotate it:
```bash
openclaw gateway token rotate
```

---

## Step 9: Credentials Hygiene

```bash
ls ~/.openclaw/credentials/
```

Check what's stored. API keys, tokens, bot tokens should:
- Never be in state files (twitter-state.json, etc.)
- Never be in memory files
- Never be in skill SKILL.md files
- Live in `credentials/` or a proper secret manager

---

## Step 10: Telegram Channel Lockdown

If you use the Telegram channel, verify it's locked to your account only:

```bash
openclaw security audit | grep telegram
```

The `dmPolicy: pairing` setting is good — it means only paired accounts can DM your bot. Keep it that way.

---

## Ongoing Habits

- [ ] Update OpenClaw when a new version drops (subscribe to release notes)
- [ ] Review new cron jobs before enabling them — read the full prompt
- [ ] Don't install ClawHub skills you don't need
- [ ] Periodically scan with ClawSec if you install skills from the hub
- [ ] Review memory files weekly if you have active external-reading crons
- [ ] Keep state files out of the workspace memory directory
