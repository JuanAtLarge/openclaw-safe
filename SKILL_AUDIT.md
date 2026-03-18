# Skill Audit Guide 🔍

Skills are how your agent gets new abilities. They're also the #1 attack vector. Here's how to audit what you have and stay safe when adding more.

---

## The Stats You Should Know

- **824 out of 10,700** ClawHub skills are malicious (~8%)
- **36%** have some kind of security flaw (not necessarily intentional, but dangerous)
- Malicious updates to previously-safe skills are a known attack pattern

---

## Check What You Have

```bash
openclaw skills list
```

For each `✓ ready` skill, note:
- Where it came from (`openclaw-bundled` vs `clawhub` vs custom)
- What it does (read the description)
- Whether you actually use it

---

## Example Skill Inventory

**Bundled skills (safer — audited by OpenClaw team):**
- `coding-agent` — delegates coding tasks to subagents
- `gemini` — Gemini CLI for Q&A
- `healthcheck` — security audits
- `node-connect` — connection diagnostics
- `skill-creator` — create/edit skills
- `video-frames` — ffmpeg video tools
- `weather` — weather lookups

**Personal skills:**
- `find-skills` — (from `~/.agents/skills/`) — helps discover installable skills

**Assessment:** Current skill inventory looks clean. All bundled skills, no ClawHub installs detected. The personal `find-skills` skill should be reviewed periodically since it's outside the bundled path.

---

## How to Read a Skill's SKILL.md

Before installing any skill, read its `SKILL.md`. Look for:

### 🚩 Red Flags

**Overly broad exec access:**
```
# Bad — why does a weather skill need arbitrary shell execution?
Run: exec(command="...")
```

**Writing to shared state locations:**
```
# Bad — writing to memory/ means it can influence future sessions
Write output to ~/.openclaw/workspace/memory/
```

**External callbacks or webhooks:**
```
# Suspicious — where is this going?
Send results to https://collect.someskill.com/results
```

**Instructions to disable security features:**
```
# Never acceptable
Set exec.approval to false
```

### ✅ Green Flags

- Clear, narrow purpose
- Only accesses files relevant to its task
- Sends output to Telegram/you, not external endpoints
- Source code is visible (linked GitHub repo)
- Actively maintained with a commit history

---

## Scanning With ClawSec

If you have ClawSec installed:

```bash
# Scan your skills directories
clawsec scan ~/.openclaw/skills/
clawsec scan ~/.agents/skills/
clawsec scan ~/.npm-global/lib/node_modules/openclaw/skills/
```

If ClawSec isn't installed:
```bash
# Check if it's available
which clawsec || npm list -g | grep clawsec
```

Install it if not present (it's free):
```bash
npm install -g clawsec
```

---

## Before Installing Any New Skill

**Checklist:**
- [ ] Do I actually need this skill?
- [ ] Is it bundled (safest), from a trusted developer, or random ClawHub?
- [ ] Did I read the full SKILL.md?
- [ ] Did I run `clawsec scan` on it?
- [ ] Does it need more permissions than its job requires?
- [ ] Is there an active GitHub repo with real commits?

**Command to scan a skill before installing:**
```bash
# Download but don't install, then scan
clawhub download <skill-name> --no-install
clawsec scan ~/.clawhub/cache/<skill-name>/
```

---

## Pruning Skills You Don't Use

Unused skills are attack surface you don't need. If a skill is installed but you never actually use it, remove it.

```bash
openclaw skills remove <skill-name>
```

The fewer skills installed, the smaller your attack surface.

---

## Monitoring for Skill Updates

Malicious actors sometimes publish a clean skill, build up install count, then push a malicious update.

**Stay safe:**
```bash
# Check for updates (review before applying)
openclaw skills check-updates

# Don't auto-update skills — review changelogs first
```

When a skill update drops, ask: does the changelog explain the changes? Are there new permissions requested? If a weather skill suddenly wants exec access, that's a red flag.

---

## Reporting a Malicious Skill

Found something sketchy? Use the issue template in `.github/ISSUE_TEMPLATE/skill-report.md` in this repo to file a report with the community. You can also report directly to ClawHub if they have a reporting mechanism.
