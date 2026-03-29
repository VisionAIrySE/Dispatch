---
name: tooldispatch
description: >
  Your Claude Code insurance policy — best tool for the job up front, code that
  connects before it breaks. ToolDispatch is two modules: Dispatch proactively
  surfaces the best plugin, skill, or MCP for your current task and intercepts
  tool calls when a better marketplace alternative exists (UserPromptSubmit +
  PreToolUse hooks, 0–100 scoring, blocks on ≥10 point gap, "proceed" to bypass).
  XF Audit catches broken module contracts before they run — AST scan on every
  Edit/Write (~200ms), Xpansion cascade analysis on contract changes, concrete
  repair plan per violation, graduated consent. Hosted Free (8 intercepts/day,
  XF Audit Stage 1) and Pro (unlimited, Sonnet ranking, full XF Audit Stages 1–4,
  $10/month). BYOK open source available.
license: MIT
hooks:
  UserPromptSubmit:
    - type: command
      command: bash ~/.claude/hooks/dispatch.sh
      timeout_ms: 10000
  PreToolUse:
    - type: command
      command: bash ~/.claude/hooks/dispatch-preuse.sh
      timeout_ms: 10000
metadata:
  author: ToolDispatch
  version: "1.0.0"
  repository: https://github.com/ToolDispatch/Dispatch
  homepage: https://dispatch.visionairy.biz
  install: bash <(curl -fsSL https://raw.githubusercontent.com/ToolDispatch/Dispatch/main/install.sh)
---

# ToolDispatch

Your Claude Code insurance policy. Two modules that cover both sides of the
problem: Dispatch puts the best tool in Claude's hands at the right moment. XF
Audit ensures the code it produces actually connects. One platform. Both sides.
And it leaves a record of everything it did.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ToolDispatch/Dispatch/main/install.sh)
```

Requires Python 3.8+ and Node.js (for `npx skills list`).

## How it works — Dispatch module

**Hook 1 — UserPromptSubmit** (`dispatch.sh`): Detects topic shifts using Claude
Haiku (~100ms). On a confirmed shift, maps the task type to one of 16 MECE
categories using `category_mapper.py`. Stage 3 immediately surfaces grouped tool
recommendations into Claude's context — organized by Plugins, Skills, and MCPs,
2–3 per type, with install commands. Each category's recommendations appear once
per session. Hook 1 also writes category state used by Hook 2.

**Hook 2 — PreToolUse** (`preuse_hook.sh`): Before Claude invokes a Skill, Agent,
or MCP tool, searches the marketplace using the current task category, scores all
results 0–100, and scores Claude's chosen tool on the same scale. If the top
alternative scores ≥10 points higher, blocks (exit 2) and surfaces the ranked
comparison. The user can type "proceed" to bypass (one-time, no restart needed).

**Category-first routing**: 16 MECE categories. Haiku generates open-ended task
type labels; the category model translates them into targeted search queries.

**MCP server awareness**: Searches glama.ai, Smithery.ai, and the official MCP
registry alongside skills.sh. Already-installed MCPs excluded automatically.

## How it works — XF Audit module

**Stage 1 — AST scan** (always runs, ~200ms): Checks syntax, from-import existence,
arity mismatches, missing env vars, and consumed stubs. Blocks immediately on
violations. Clean result: `◈ XF Audit  47 modules · 203 edges checked  ✓ 0 violations`.

**Stage 2 — Xpansion cascade** (fires on contract changes only): Maps the full
caller chain using MECE boundary analysis. Shows consequence-first output:
"This will throw a TypeError when the ranker runs."

**Stage 3 — Repair plan**: Each violation gets one specific, file-and-line fix.

**Stage 4 — Graduated consent**: "show me the diff first" only until two verified
repairs this session. "apply all" unlocks after trust is earned. Resets each session.

**Refactor Mode**: `/xfa-refactor start` shifts XF Audit from blocking to tracking.
Auto-detected after 3+ consecutive edits to the same symbol.

**Provenance**: Every scan and repair logged to `.xf/repair_log.json`.

## Modes

| Mode | Dispatch | XF Audit | Cost |
|------|----------|----------|------|
| **BYOK / Open Source** | Unlimited | Stage 1 only | API costs |
| **Hosted Free** | 8/day | Stage 1 only | Free |
| **Hosted Pro** | Unlimited, Sonnet ranking | Full Stages 1–4 | $10/month |

> **Founding offer:** First 300 Pro subscribers lock in $6/month for life.

## Docs

- README: https://github.com/ToolDispatch/Dispatch
- Platform: https://dispatch.visionairy.biz
