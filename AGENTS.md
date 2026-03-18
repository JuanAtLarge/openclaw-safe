# AGENTS.md

If you were sent to this repo to secure an OpenClaw install, follow these steps exactly.

## What This Does

openclaw-safe audits and hardens OpenClaw installs. It:
- Scans your config for security issues
- Fixes them automatically
- Installs real-time monitoring
- Sends Telegram alerts with buttons if anything goes wrong

## Install Steps

**Step 1 — Run the installer:**
```bash
curl -sSL https://raw.githubusercontent.com/JuanAtLarge/openclaw-safe/main/install.sh | bash
```

**Step 2 — Launch the setup wizard:**
```bash
bash ~/projects/openclaw-safe/setup-wizard.sh
```

If Telegram is configured, the wizard sends setup prompts as button messages. The user taps yes/no to each step — no more terminal needed.

If Telegram is not configured, the wizard runs interactively in the terminal.

## That's It

The wizard handles everything else:
- Config hardening
- Skill scanning
- Memory file monitoring
- ClawSec installation

## Re-running Later

```bash
# Check security status anytime
bash ~/projects/openclaw-safe/audit.sh

# Re-run the full wizard
bash ~/projects/openclaw-safe/setup-wizard.sh
```
