---
name: openclaw-safe
version: 1.0.0
description: "Security hardening for OpenClaw — audit, harden, monitor, and auto-quarantine malicious skills. Interactive setup wizard included. Use when: user asks to secure, audit, harden, or monitor their OpenClaw install, scan skills for malware, or check security alerts. NOT for: general system security, non-OpenClaw tools."
homepage: https://github.com/JuanAtLarge/openclaw-safe
metadata: { "openclaw": { "emoji": "🔒", "requires": { "bins": ["bash", "python3"] } } }
---

# openclaw-safe Skill

Security hardening, auditing, and real-time monitoring for OpenClaw agents.

## Installation Check

Before running any command, verify openclaw-safe is installed:

```bash
if [[ ! -d ~/projects/openclaw-safe ]]; then
    echo "Installing openclaw-safe..."
    git clone https://github.com/JuanAtLarge/openclaw-safe.git ~/projects/openclaw-safe
    bash ~/projects/openclaw-safe/install.sh
fi
```

## When to Use

✅ **USE this skill when:**

- "audit my OpenClaw" / "check my security"
- "secure my OpenClaw" / "install openclaw-safe"
- "harden my OpenClaw"
- "scan my skills"
- "start security monitor" / "start monitoring"
- "check security alerts" / "any security alerts?"

## When NOT to Use

❌ **DON'T use this skill when:**

- General OS/server security (use dedicated security tools)
- Non-OpenClaw application hardening
- Network firewall configuration

## Commands

### Audit — "audit my OpenClaw" / "check my security"

Run a full security audit and report results:

```bash
bash ~/projects/openclaw-safe/audit.sh
```

Report the score and any flagged issues to the user. Highlight critical findings.

### Full Setup — "secure my OpenClaw" / "install openclaw-safe"

Run the interactive setup wizard (Telegram or terminal):

```bash
bash ~/projects/openclaw-safe/setup-wizard.sh
```

If Telegram is configured, the wizard runs via inline buttons. Otherwise it runs interactively in the terminal.

### Harden — "harden my OpenClaw"

Apply security hardening to OpenClaw config:

```bash
bash ~/projects/openclaw-safe/harden.sh
```

This backs up config first, then applies safe hardening settings. Confirm with the user before running if they seem unsure.

### Scan Skills — "scan my skills"

Scan installed skills for malicious or suspicious code:

```bash
bash ~/projects/openclaw-safe/scan-skills.sh
```

Report any flagged skills. If anything is quarantined, tell the user what was found and where it was moved.

### Start Monitor — "start security monitor" / "start monitoring"

Start real-time monitoring of memory files and skill integrity:

```bash
bash ~/projects/openclaw-safe/monitor.sh start
bash ~/projects/openclaw-safe/clawsec-monitor.sh &
```

Confirm monitor is running. Tell the user it will alert on suspicious changes.

### Check Alerts — "check security alerts" / "any security alerts?"

Run audit and surface alert status:

```bash
bash ~/projects/openclaw-safe/audit.sh
```

Check `~/.openclaw-safe/alerts/` for any pending alert files and report them.

## Response Style

- Lead with the security score: `🔒 Security score: XX/100`
- List issues as bullet points with severity (🔴 critical, 🟡 warning, 🟢 ok)
- Offer next steps: "Want me to fix these automatically?"
- Keep it concise — security output can be verbose; summarize, don't dump

## Notes

- harden.sh backs up config before making changes — safe to run
- scan-skills.sh may quarantine suspicious skills to `~/.openclaw-safe/quarantine/`
- monitor.sh runs as a background process; check `monitor.sh status` to verify
- All scripts are idempotent — safe to run multiple times
