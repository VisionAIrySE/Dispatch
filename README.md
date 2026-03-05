# Dispatch

**Runtime skill router for Claude Code.**

Dispatch watches your conversation, detects when you shift to a new task, and recommends the best installed plugins and skills before Claude responds — including ones you haven't installed yet.

---

## What it does

Every time you send a message, Dispatch:

1. **Detects topic shifts** — Uses Claude Haiku (~$0.0001/message) to classify whether you've started a new type of task
2. **Evaluates your plugins** — Scans all installed Claude Code plugins and agent skills
3. **Searches the registry** — Queries skills.sh for relevant uninstalled options
4. **Shows recommendations** — Pauses before Claude responds so you can see what's available

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ⚡ Dispatch  →  Flutter task detected
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 RECOMMENDED (installed):
   + flutter-mobile-app-dev
     Direct Flutter/Dart development support
   + firebase-firestore-basics
     Firestore queries and Security Rules

 SUGGESTED (not installed):
   ↓ firebase/agent-skills@firebase-app-hosting
     → npx skills add firebase/agent-skills@firebase-app-hosting

 [Enter] or wait 3s to proceed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Install

```bash
git clone https://github.com/VisionAIrySE/Dispatch.git
cd Dispatch
chmod +x install.sh
./install.sh
```

Then set your Anthropic API key (used for Haiku classification):

```bash
export ANTHROPIC_API_KEY=sk-ant-...
# Add to ~/.bashrc or ~/.zshrc to persist
```

Start a **new** Claude Code session — Dispatch is active immediately.

---

## Requirements

- Claude Code (any version with hooks support)
- Python 3.8+
- `anthropic` Python package (install.sh handles this)
- Node.js + npx (for skills registry search)
- Anthropic API key

---

## How it works

**Stage 1 — Classification (every message)**
A Haiku call receives your last 3 messages + current working directory. Returns `{"shift": bool, "task_type": str, "confidence": float}`. Exits immediately if no shift or confidence < 0.7.

**Stage 2 — Evaluation (on confirmed shift only)**
Scans `~/.claude/plugins/marketplaces/` for installed plugins, queries `npx skills list` for agent skills, and searches the skills.sh registry for uninstalled options. Haiku ranks everything by relevance.

**Smart skipping** — messages under 6 words and follow-up questions never trigger a full evaluation.

---

## Supported task types

`flutter` · `firebase` · `supabase` · `n8n` · `git` · `debugging` · `planning` · `testing` · `api` · `frontend` · `general`

---

## Cost

~$0.0001 per message for Stage 1 classification. Stage 2 (plugin ranking) only fires on topic shifts — typically a few times per session. Daily cost for active use: less than $0.01.

---

## Uninstall

```bash
# Remove files
rm -rf ~/.claude/skill-router
rm ~/.claude/hooks/skill-router.sh

# Remove hook from settings.json
# Delete the UserPromptSubmit entry in ~/.claude/settings.json
```

---

## Status

**V1 — Personal/Testing.** Built and tested on Claude Code with the superpowers plugin stack. Feedback welcome via GitHub Issues.

V2 roadmap: hosted classifier endpoint, curated plugin rankings, skills.sh distribution.
