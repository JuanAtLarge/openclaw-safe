# Self-Audit Guide 📋

**The easiest way to audit your install:**

```bash
bash audit.sh
```

It does everything below automatically and saves a dated report to `audit-results/`. Run it anytime — quarterly is good, after anything unusual is mandatory.

If you want to dig deeper or understand what each check is looking at, this guide walks through the same steps manually.

---

## Automated Audit (Recommended)

```bash
# Full scan:
bash audit.sh

# Fix anything it finds:
bash harden.sh

# Scan your installed skills:
bash scan-skills.sh
```

That's it. The scripts handle the rest and tell you exactly what they found.

---

## Manual Audit (If You Want to Understand What's Happening)

### Version Check
```bash
openclaw --version
```
Must be >= v2026.2.25. Anything older is vulnerable to the ClawJacked remote takeover exploit.

### Plugin Allow-List
```bash
cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; c=json.load(sys.stdin); print(c.get('plugins',{}).get('allow','NOT SET'))"
```
Should show your active plugins (e.g. `['telegram']`). If it says `NOT SET`, run `harden.sh`.

### Exec Approval Settings
```bash
cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; c=json.load(sys.stdin); print(c.get('tools',{}).get('exec',{}).get('ask','NOT SET'))"
```
Should be `allowlist`, `ask`, or `security`. If `NOT SET`, run `harden.sh`.

### Gateway Exposure
```bash
cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; c=json.load(sys.stdin); print('mode:', c.get('gateway',{}).get('mode'))"
```
`local` is safe. If it says anything else, check your gateway config carefully.

### Cron Audit
```bash
openclaw cron list --json
```
For each cron: does it read external content? Is `sessionTarget` set to `isolated`? See CHECKLIST.md Step 3 for what to look for.

### Memory File Check
```bash
ls ~/.openclaw/workspace/memory/
cat ~/.openclaw/workspace/memory/$(date +%Y-%m-%d).md
```
Look for anything that doesn't sound like you — unexpected instructions, unusual links, commands you didn't write. See `MEMORY_SAFETY.md` for what prompt injection looks like.

### Installed Skills
```bash
bash scan-skills.sh
```
Or manually: `ls ~/.agents/skills/ ~/.openclaw/workspace/skills/ 2>/dev/null`

### File Permissions
```bash
ls -la ~/.openclaw/openclaw.json
```
Should show `-rw-------` (600). If it shows any group or world read permissions, fix it:
```bash
chmod 600 ~/.openclaw/openclaw.json
```

---

## Saving Your Results

`audit.sh` automatically saves results to `audit-results/YYYY-MM-DD.md`. To save a manual audit, copy this template:

```markdown
# OpenClaw Self-Audit
**Date:** YYYY-MM-DD
**OpenClaw version:** (openclaw --version)

## Findings
| Check | Status | Notes |
|-------|--------|-------|
| Version >= 2026.2.25 | ✅ / ❌ | |
| plugins.allow set | ✅ / ⚠️ | |
| exec.ask configured | ✅ / ⚠️ | |
| Gateway local-only | ✅ / ❌ | |
| Crons isolated | ✅ / ⚠️ | |
| Credentials in config | ✅ / ⚠️ | |
| Skills scanned | ✅ / ⚠️ | |
| File permissions 600 | ✅ / ❌ | |

## Actions Taken
1.
2.

## Next Audit Date
___
```

---

## Quick Monthly Re-Check

```bash
# Version still current?
openclaw --version

# Any new issues?
bash audit.sh

# Memory files look normal?
cat ~/.openclaw/workspace/memory/$(date +%Y-%m-%d).md

# Any cron errors?
openclaw cron list --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
jobs = data.get('jobs', data) if isinstance(data, dict) else data
for j in jobs:
    errors = j.get('state', {}).get('consecutiveErrors', 0)
    if errors > 0:
        print(f\"⚠ {j['name']}: {errors} consecutive errors — {j.get('state',{}).get('lastError','')}\")
"
```
