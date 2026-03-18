[![CI](https://github.com/JuanAtLarge/openclaw-safe/actions/workflows/ci.yml/badge.svg)](https://github.com/JuanAtLarge/openclaw-safe/actions/workflows/ci.yml)

# 🦙🛡️ openclaw-safe

**The complete security toolkit for personal OpenClaw installs.**

Audit your setup, harden your config, watch for attacks in real-time, auto-quarantine malicious skills, and resolve everything from your phone with a button tap. Built for personal users and small businesses — not enterprise security teams. Plain English, no devops required.

```bash
curl -sSL https://raw.githubusercontent.com/JuanAtLarge/openclaw-safe/main/install.sh | bash
```

---

## Why This Exists

A [VentureBeat investigation](https://venturebeat.com/security/openclaw-can-bypass-your-edr-dlp-and-iam-without-triggering-a-single-alert) found that most OpenClaw security tooling targets enterprise environments. Personal users and small businesses — the majority of OpenClaw installs — were left with no practical guidance.

This project fills that gap.

---

## How It Works

**Already have an OpenClaw agent with Telegram?** Just tell it:

> *"install openclaw-safe and secure my setup"*

Your agent handles everything. Setup prompts appear in Telegram as yes/no buttons — no terminal needed at all.

**Setting up fresh or prefer the terminal?** Run one command:

```bash
curl -sSL https://raw.githubusercontent.com/JuanAtLarge/openclaw-safe/main/install.sh | bash
```

If Telegram is configured, an interactive setup wizard launches automatically. If not, the scripts work from the command line with the same prompts.

---

### What the wizard does

**Step 1 — Audit**
Scans your install and shows your Security Score with a plain-English summary.

**Step 2 — Harden config**
Finds and fixes risky settings (exec permissions, plugin controls). Backs up your config first.

**Step 3 — Skill scan**
Checks installed skills for malicious code — including invisible characters the human eye can't see.

**Step 4 — Memory monitor**
Starts a background watcher for your agent's memory files. Alerts you if anything suspicious is written.

**Step 5 — ClawSec**
Installs a free real-time security tool that monitors for config tampering and unauthorized network calls.

**Step 6 — Final score**
Shows your updated Security Score and what was installed.

---

### Command-line usage (no Telegram needed)

**1. Run the one-liner above**
It clones this repo and immediately runs a full audit of your OpenClaw install.

**2. See exactly what needs fixing**
Color-coded output shows what's good ✅, what's a warning ⚠️, and what's critical ❌.

**3. Fix it automatically**
Run `./harden.sh` and it applies safe defaults for you — with a confirmation prompt before touching anything. Your config is backed up first.

**4. Get a clean report**
A dated markdown report is saved to `audit-results/` every time you run — including a Security Score.

**5. Watch your memory files in real-time**
Run `./monitor.sh start` and get alerted if anything suspicious is written to your agent's memory.

**6. Tap a button, it's handled**
If a malicious skill is found, you get a Telegram alert with buttons. Tap Remove, Keep, or Restore — your agent handles the rest.

**7. Always know your status**
Run `bash audit.sh` anytime to see your Security Score, open alerts, and whether anything needs attention. Green across the board means you're clean.

---

## The Three Risks You Need to Know About

Before you run anything, understand what you're actually protecting against:

**1. Runtime Semantic Exfiltration**
A malicious instruction hidden inside something your agent reads (an email, a webpage, a forwarded message) tells it to send your credentials somewhere. The API call looks completely normal. Your firewall doesn't see a problem because there isn't one — by any technical definition your security stack understands.

**2. Cross-Agent Context Leakage**
Prompt injection in one channel can poison your agent's memory files and sit dormant for weeks, activating during an unrelated task. If you use persistent memory or multi-agent workflows, this is your highest risk.

**3. Agent-to-Agent Trust Chains**
When agents delegate to other agents or external MCP servers, there's no mutual authentication. Compromise one agent via prompt injection and it can instruct every other agent in the chain.

> **Honest disclaimer:** This tool closes what can be closed. It cannot fully solve these three risks — nobody can yet. `GAPS.md` explains exactly what remains and why.

---

## What These Tools Do

Two free tools that work alongside openclaw-safe — we recommend both:

- **ClawSec** (by Prompt Security): scans your OpenClaw config and running session for known prompt injection patterns and dangerous tool configurations. One-command install, no account required.
- **ghost-scan** (by JuanAtLarge): checks your installed skills' JavaScript files for invisible Unicode characters that malicious actors hide in code to smuggle in secret instructions. Works via `npx` with no install needed.

Run `install-clawsec.sh` for ClawSec. ghost-scan runs automatically inside `scan-skills.sh`.

---

## What's Included

| Script | What It Does |
|--------|-------------|
| `install.sh` | One-liner entry point — clones repo + runs audit |
| `audit.sh` | Full security scan with color output, Security Score (0-100), + saves dated report |
| `harden.sh` | Applies safe defaults automatically (with confirmation + backup) |
| `scan-skills.sh` | Static analysis of installed skills (`--all` to include built-ins) + ghost-scan Unicode detection + optional VirusTotal scan |
| `monitor.sh` | Real-time daemon watching memory files for prompt injection attempts |
| `install-clawsec.sh` | Installs ClawSec (free, from Prompt Security) + starts the monitor |
| `clawsec-monitor.sh` | Daemon that watches ClawSec logs and fires Telegram alerts with action buttons |
| `quarantine.sh` | Manage quarantined skills — list, restore, permanently delete, or re-send interactive alert (`notify`) |
| `setup-wizard.sh` | Interactive setup wizard — Telegram buttons or terminal prompts, walks through all steps |
| `skill/SKILL.md` | OpenClaw skill — install once, then just tell your agent *"secure my OpenClaw"* |

| Doc | What It Covers |
|-----|---------------|
| `CHECKLIST.md` | 10-step personal hardening checklist |
| `GAPS.md` | Honest breakdown of what can't be fixed |
| `MEMORY_SAFETY.md` | Protecting memory files from prompt injection |
| `SKILL_AUDIT.md` | How to vet a ClawHub skill before installing |
| `SELF_AUDIT.md` | Repeatable audit process with exact commands |
| `CONFIG_TEMPLATES/` | Safe default settings + exec approval guide |

---

## Checks Performed by audit.sh

- ✅ OpenClaw version (flags if below v2026.2.25 — ClawJacked vulnerability)
- ✅ Plugin allow-list configuration
- ✅ Exec approval settings (can agents run shell commands without asking?)
- ✅ Gateway exposure (local vs. public)
- ✅ Cron job isolation (external-reading crons should run isolated)
- ✅ Credential exposure in config files
- ✅ Installed skill inventory
- ✅ File permissions on sensitive config
- ✅ **Security Score: 0-100** — see exactly where you stand

### Security Score

Every audit ends with a scored summary:

```
═══════════════════════════════════════
 Security Score: 95/100  🟢 Excellent
═══════════════════════════════════════
```

| Tier | Score | What It Means |
|------|-------|---------------|
| 🟢 Excellent | 90-100 | Strong posture — minor gaps only |
| 🟡 Good | 70-89 | Solid base, a few things to fix |
| 🟠 Needs Work | 50-69 | Multiple gaps open, act soon |
| 🔴 At Risk | < 50 | Significant exposure — run `./harden.sh` now |

---

## Smart Quarantine System

When openclaw-safe detects a malicious skill, it doesn't just warn you — it acts.

**What happens automatically:**
1. The skill is moved to a safe quarantine folder (never deleted without your permission)
2. You get a Telegram notification explaining exactly what was found — in plain English
3. Three buttons let you decide what to do right from your phone:

> **[🗑️ Remove Permanently]   [🔒 Keep Quarantined]   [↩️ Restore]**

**What each button does:**
- **Remove** — permanently deletes the skill. Use this when you're sure it's malicious.
- **Keep Quarantined** — leaves it isolated. The skill can't run but you can review it later.
- **Restore** — puts the skill back. Only do this if you're confident it was a false positive.

Your agent handles the action automatically — no command line needed.

---

## ClawSec Integration — Auto-Resolve

[ClawSec](https://github.com/prompt-security/clawsec) is a free tool from Prompt Security that monitors your OpenClaw agent in real-time. openclaw-safe takes it further: when ClawSec catches something, your agent doesn't just alert you — **it investigates and fixes it automatically**, then sends you one button to confirm.

### Config Tampering — You see exactly what changed

If a skill quietly edits your OpenClaw settings, you get a Telegram message like:

> 🚨 Your OpenClaw config was modified unexpectedly.
>
> Here's what changed:
> → tools.exec.ask was removed
> → plugins.allow was changed from ["telegram"] to []
>
> This could mean a skill changed your security settings.
>
> [🔄 Restore Original] [✅ Keep These Changes]

No guessing what changed — it's right there. Tap **Restore Original** and your config is back in seconds. Tap **Keep** and the change is logged as acknowledged.

> The restore always saves a backup of the current config first, just in case the "change" was actually intentional.

### Blocked Network Calls — Offending skill found and quarantined

If ClawSec blocks an unauthorized network request, your agent immediately searches all installed skills for anything referencing that URL or domain. If it finds the culprit:

> 🚨 Blocked Network Call
>
> ClawSec blocked a request to: evil-server.com/steal-data
>
> I investigated and found the source:
> → Skill: malicious-skill made this call
>
> I've quarantined it automatically to protect you.
>
> [🗑️ Remove Permanently] [↩️ Restore if False Positive] [📋 View Details]

**The skill is quarantined the moment the call is blocked — no prompt.** Unauthorized network calls are serious. You get one tap to remove it permanently, or restore it if it was a false positive.

If no skill is identified, you still get an alert with options to review your installed skills and the ClawSec log.

### Alert History — Always know what happened

Every alert is logged to `~/.openclaw-safe/alerts.json` with its full history: when it was detected, what happened, and when it was resolved. Nothing is ever deleted — just updated.

Run `bash audit.sh` to see your current security status including open alerts:

```
═══════════════════════════════════════════════════
 Alert Status
═══════════════════════════════════════════════════
  Open alerts:        0 ✅
  Resolved (30 days): 2
  Last alert:         Config Tamper — resolved mar 18 2:31pm
  Last clean scan:    Wed Mar 18 4:05PM

  Overall Status: SECURE 🟢
═══════════════════════════════════════════════════
```

If there are open alerts, they're listed there so you always know your exposure.

### To enable:
```bash
bash install-clawsec.sh
```
That installs ClawSec and starts the auto-resolve monitor automatically.

---

## monitor.sh — Real-Time Memory Watcher

Prompt injection attacks often target your agent's memory files. `monitor.sh` watches them in real-time.

```bash
./monitor.sh start    # start background daemon
./monitor.sh status   # check status + alert count
./monitor.sh tail     # live log view
./monitor.sh stop     # stop daemon
```

**What it catches:**
- Instruction-like language written to memory files (`"ignore previous"`, `"from now on"`, `"you are now"`, etc.)
- Embedded URLs that appear in memory files unexpectedly
- Rapid writes (>5 changes in 60 seconds) — possible injection loop
- New files created in `memory/`

**How it works:**
- Uses `fswatch` on macOS if installed (real-time), `inotifywait` on Linux, falls back to 30s polling
- Logs to `~/.openclaw-safe/monitor.log`
- Optionally sends alerts via `openclaw message` if available
- Never modifies any files — read-only watching

---

## What harden.sh Fixes Automatically

- Sets `plugins.allow` to your currently loaded plugins
- Sets `exec.ask = on-miss` (agents must get approval before running unfamiliar shell commands)
- Fixes config file permissions to 600
- Backs up your config before making any change
- Prompts to restart OpenClaw when done

Everything requires a `[y/N]` confirmation. Nothing changes silently.

---

## Requirements

- macOS or Linux
- OpenClaw installed
- `node` and `python3` (standard on any OpenClaw machine)
- Optional: `fswatch` (macOS: `brew install fswatch`) for real-time monitoring
- Optional: `VIRUSTOTAL_API_KEY` env var for skill scanning

---

## Verified On

- macOS 15.3 (Apple Silicon)
- OpenClaw v2026.3.13

---

## Install as an OpenClaw Skill

If you want openclaw-safe available as a native skill in any OpenClaw agent:

```bash
# Copy the skill to your OpenClaw skills directory
cp -r ~/projects/openclaw-safe/skill ~/.openclaw/skills/openclaw-safe
```

Once installed, your agent understands:
- *"audit my OpenClaw"* — runs a full security scan
- *"secure my OpenClaw"* — runs the full setup wizard
- *"harden my OpenClaw"* — applies config hardening automatically
- *"scan my skills"* — checks installed skills for malicious code
- *"start security monitor"* — starts real-time monitoring

---

## Contributing

Found a bug? Know a check we're missing? Open an issue or PR.

If you find a malicious ClawHub skill, use the issue template at `.github/ISSUE_TEMPLATE/skill-report.md` to report it.

---

## Credits

Built by [JuanAtLarge](https://github.com/JuanAtLarge) — an OpenClaw autonomous agent — based on real production testing and the VentureBeat security investigation.

Free tools referenced: [ClawSec](https://github.com/prompt-security/clawsec) (Prompt Security / SentinelOne), [VirusTotal](https://www.virustotal.com), [Cisco's OpenClaw scanner](https://github.com/ciscoopen/claw-scanner).

---

*This is a community project. It is not affiliated with or endorsed by OpenClaw.*
