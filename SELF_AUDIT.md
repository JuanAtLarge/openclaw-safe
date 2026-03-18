# Self-Audit Template 📋

Use this template to audit your OpenClaw installation. Run it periodically — quarterly is reasonable, after any incident is mandatory.

Copy the template below, fill it in, and save your results to `audit-results/yourname-YYYY-MM-DD.md`.

---

## Audit Template

```markdown
# OpenClaw Self-Audit
**Date:** YYYY-MM-DD  
**Auditor:** (your name or "self")  
**OpenClaw version:** (run: openclaw --version)

---

## Version Check
- [ ] Version >= v2026.2.25 (ClawJacked fix)
- Current version: ___
- Status: SAFE / NEEDS UPDATE

---

## Built-In Audit
Run: `openclaw security audit --deep`

Results:
- Critical issues: ___
- Warnings: ___
- Notable items: ___

---

## Cron Audit
Run: `openclaw cron list --json`

For each cron, fill in:

| Cron Name | Reads External Content? | Actions It Can Take | Risk Level |
|-----------|------------------------|---------------------|------------|
| | | | |
| | | | |

Crons marked HIGH risk (reads external + takes external actions):
- 

---

## Skill Audit
Run: `openclaw skills list`

Installed skills:
- 

Skills from ClawHub (higher risk):
- 

ClawSec scan results:
- 

---

## Memory File Check
Run: `ls ~/.openclaw/workspace/memory/ && cat ~/.openclaw/workspace/memory/YYYY-MM-DD.md`

Anything suspicious in memory files? YES / NO

If yes, describe:

---

## Config Review
- plugins.allow set? YES / NO (if NO: risk of auto-loading unknown plugins)
- Telegram dmPolicy: (should be "pairing")
- Gateway exposed externally? YES / NO
- Auth token ever shared/committed? YES / NO (if yes: rotate it)

---

## Credentials Check
Run: `ls ~/.openclaw/credentials/`

Are any credentials also duplicated in state files or memory? YES / NO

---

## Red Flags Found
(List anything that needs action)
1.
2.
3.

---

## Actions Taken
1.
2.
3.

---

## Next Audit Date
___
```

---

## Interpreting Risk Levels

| Risk Level | Definition |
|------------|-----------|
| LOW | Doesn't read external content, or reads it but takes no external actions |
| MEDIUM | Reads external content and writes to local files |
| HIGH | Reads external content AND takes external actions (posts, emails, API calls) |
| CRITICAL | HIGH + uses shared memory / main session context |

---

## Quick Re-Audit (Monthly)

For a faster check between full audits:

```bash
# Version still current?
openclaw --version

# Any new warnings?
openclaw security audit

# Any memory weirdness?
cat ~/.openclaw/workspace/memory/$(date +%Y-%m-%d).md | grep -i "remember\|important\|instruction"

# Cron errors recently?
openclaw cron list --json | python3 -c "import json,sys; jobs=json.load(sys.stdin)['jobs']; [print(j['name'], j['state'].get('consecutiveErrors', 0), j['state'].get('lastError', '')) for j in jobs if j['state'].get('consecutiveErrors', 0) > 0]"
```
