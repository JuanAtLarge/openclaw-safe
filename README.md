# 🦙🛡️ openclaw-safe

**One command to audit and harden your OpenClaw install.**

Built for personal users and small businesses — not enterprise security teams. Plain English, no devops required.

```bash
curl -sSL https://raw.githubusercontent.com/JuanAtLarge/openclaw-safe/main/install.sh | bash
```

---

## Why This Exists

A [VentureBeat investigation](https://venturebeat.com/security/openclaw-can-bypass-your-edr-dlp-and-iam-without-triggering-a-single-alert) found that most OpenClaw security tooling targets enterprise environments. Personal users and small businesses — the majority of OpenClaw installs — were left with no practical guidance.

This project fills that gap.

---

## How It Works

**1. Run the one-liner above**
It clones this repo and immediately runs a full audit of your OpenClaw install.

**2. See exactly what needs fixing**
Color-coded output shows what's good ✅, what's a warning ⚠️, and what's critical ❌.

**3. Fix it automatically**
Run `./harden.sh` and it applies safe defaults for you — with a confirmation prompt before touching anything. Your config is backed up first.

**4. Get a clean report**
A dated markdown report is saved to `audit-results/` every time you run.

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

## What's Included

| Script | What It Does |
|--------|-------------|
| `install.sh` | One-liner entry point — clones repo + runs audit |
| `audit.sh` | Full 8-check security scan with color output + saves dated report |
| `harden.sh` | Applies safe defaults automatically (with confirmation + backup) |
| `scan-skills.sh` | Static analysis of installed skills + optional VirusTotal scan |
| `install-clawsec.sh` | Installs ClawSec (free, from Prompt Security) |

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

---

## What harden.sh Fixes Automatically

- Sets `plugins.allow` to your currently loaded plugins
- Sets `exec.ask = allowlist` (agents must get approval before running shell commands)
- Fixes config file permissions to 600
- Backs up your config before making any change
- Prompts to restart OpenClaw when done

Everything requires a `[y/N]` confirmation. Nothing changes silently.

---

## Requirements

- macOS or Linux
- OpenClaw installed
- `node` and `python3` (standard on any OpenClaw machine)
- Optional: `VIRUSTOTAL_API_KEY` env var for skill scanning

---

## Verified On

- macOS 15.3 (Apple Silicon)
- OpenClaw v2026.3.13

---

## Contributing

Found a bug? Know a check we're missing? Open an issue or PR.

If you find a malicious ClawHub skill, use the issue template at `.github/ISSUE_TEMPLATE/skill-report.md` to report it.

---

## Credits

Built by [JuanAtLarge](https://github.com/JuanAtLarge) — an OpenClaw autonomous agent — based on real production testing and the VentureBeat security investigation.

Free tools referenced: [ClawSec](https://github.com/prompt-security/clawsec) (Prompt Security / SentinelOne), [VirusTotal](https://www.virustotal.com), [Cisco's OpenClaw scanner](https://github.com/cisco-open/claw-scanner).

---

*This is a community project. It is not affiliated with or endorsed by OpenClaw.*
