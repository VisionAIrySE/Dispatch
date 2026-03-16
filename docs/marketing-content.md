# Dispatch — Marketing Content Package

**Updated:** 2026-03-16
**Version:** v0.9.0
**Repo:** https://github.com/VisionAIrySE/Dispatch

---

## Table of Contents

1. [Show HN Post](#1-show-hn-post)
2. [r/ClaudeCode Post](#2-rclaudecode-post)
3. [r/ClaudeDev Post](#3-rclaudedev-post)
4. [Twitter/X Launch Thread](#4-twitterx-launch-thread)
5. [Discord Message Templates](#5-discord-message-templates)
6. [Blogwatcher Keyword List](#6-blogwatcher-keyword-list)
7. [Response Templates](#7-response-templates)
8. [awesome-claude-code PR Description](#8-awesome-claude-code-pr-description)
9. [Dev.to Article Outline](#9-devto-article-outline)

---

## 1. Show HN Post

**Title:**
```
Show HN: Dispatch – intercepts Claude Code before it picks the wrong tool (10K+ alternatives catalogued)
```

**Body:**

Last week Claude was about to use a generic GitHub skill on a task where I had a purpose-built GitHub Actions deployment skill installed. I'd had it for three months. It scored 30 points higher for what I was doing. Claude had no idea it existed.

That's the problem Dispatch solves.

Claude Code has access to 10,978 tools across 6 sources — skills.sh, glama.ai, Smithery.ai, the official MCP registry, and both plugin marketplaces. At runtime, Claude picks from a handful of defaults. It has no mechanism to know what's available, what's installed, or what actually performs best for the task in front of it. Every session, you're flying blind on tool selection.

Dispatch is two hooks. Hook 1 (UserPromptSubmit) runs on every message — ~100ms, silent when nothing changed. When you shift tasks, it maps the shift to one of 16 MECE categories, queries the catalog, and surfaces the ranked list into Claude's context before it responds. Hook 2 (PreToolUse) fires before Claude invokes any Skill, Agent, or MCP tool. It compares CC's chosen tool against marketplace alternatives on a 0–100 scale. If a better tool scores 10+ points higher, it blocks and shows you the comparison. One word — "proceed" — to override.

The catalog isn't static. It's rebuilt daily from live sources, scored by real behavioral signals: install counts, GitHub stars, forks, freshness. Tools that developers actually reach for score higher than tools that just exist. And every time a Dispatch user installs a recommended tool — or bypasses a block — that signal feeds back into the scores. The more developers use it, the sharper it gets for everyone.

This is the part I find most interesting: we now have category-level data on where Claude Code's native tool choices consistently underperform marketplace alternatives. Not anecdotes — scored intercepts across real sessions. I'm calling it the CC Weakness Map. It's currently showing the biggest gaps in mobile development, database tooling, and cloud infrastructure. That's behavioral data Anthropic can't collect internally.

Install is one command:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/VisionAIrySE/Dispatch/main/install.sh)
```

Requires Python 3.8+ and Node.js. Two modes: BYOK (your own Anthropic/OpenRouter key, everything local) or Hosted (free token at dispatch.visionairy.biz, 8 detections/day free, Pro for unlimited + pre-ranked catalog). 298 tests across 8 modules if you want to read the code before installing.

Honest limitations: the intercept is only as good as what's in the catalog. Tools with no description or no GitHub repo get a lower baseline score. Cold-start is real — the more you use it, the better the catalog gets for your stack. And adding ~100–500ms to every message (Stage 1) and ~3–5s on confirmed shifts is a real cost — still within CC's 10s hook timeout, but not nothing.

Looking for feedback on: whether the 10-point gap threshold feels right, whether the PreToolUse intercept is useful or annoying in practice, and what task types it consistently misses. The category mapper is the easiest place to contribute.

---

## 2. r/ClaudeCode Post

**Title:**
```
Claude keeps picking mediocre tools when better ones exist. I built something that intercepts it.
```

**Body:**

Here's a thing that happens silently every CC session: Claude reaches for a tool. Not because it's the best one for your task — because it's the one it knows about. The GitHub skill when you have a GitHub Actions-specific skill installed. The generic testing approach when you have a purpose-built TDD skill. The built-in filesystem tool when you have an MCP that scores 40 points higher for exactly what you're doing.

Claude has no runtime awareness of the tool ecosystem. It doesn't know about skills.sh. It doesn't know what you installed last week. It doesn't know what's in the MCP registries. It picks what it knows.

I catalogued 10,978 tools this week across 6 sources (skills.sh, glama.ai, Smithery.ai, official MCP registry, both CC plugin marketplaces). Then I built Dispatch: two hooks that fire at the two moments that matter.

**At every message:** ~100ms check. When you shift tasks, it surfaces the ranked list of what's actually available for that category — installed and uninstalled — into Claude's context before it responds.

**Before every tool call:** If Claude is about to invoke a Skill, Agent, or MCP and a marketplace alternative scores 10+ points higher, it blocks. You see the comparison. One word to proceed if you disagree.

No API key required to start — free hosted tier. BYOK if you prefer everything local.

The thing that surprised me most building this: we now have category-level data on where Claude's native tool selection is weakest. Mobile development. Database tooling. Cloud infrastructure. Not impressions — scored behavioral data from real intercepts. The gap in some categories is significant.

Repo: https://github.com/VisionAIrySE/Dispatch

Would be curious whether the detection granularity feels right for different workflows.

---

## 3. r/ClaudeDev Post

**Title:**
```
I built a two-hook runtime that intercepts Claude's tool selection — here's what 10,978 catalogued tools revealed about where CC underperforms
```

**Body:**

I want to write up the architecture because the findings were more interesting than the implementation.

**The setup:** Two hooks — UserPromptSubmit for task shift detection, PreToolUse for tool selection interception. Hook 1 classifies the shift with Haiku (~100ms), maps it to one of 16 MECE categories, and writes state. Hook 2 reads that state, queries a pre-ranked catalog of 10,978 tools, scores CC's chosen tool alongside alternatives (0–100), and exits 2 to block if the gap is 10+ points.

**What the catalog revealed:**

I crawled skills.sh, glama.ai, Smithery.ai, registry.modelcontextprotocol.io, and both CC plugin marketplaces. After dedup and a MIN_INSTALLS ≥ 20 filter on skills, the catalog settled at ~11K tools. Scored by installs (60%), GitHub stars (25%), forks (15%), staleness penalty above 18 months.

Then I ran the first real sessions and looked at where blocks were firing. The CC Weakness Map — category-level comparison of average CC tool scores vs. top marketplace alternatives — showed consistent gaps in:

- **Mobile development:** CC defaults score in the 50s. Purpose-built Flutter/React Native skills score in the 90s.
- **Database tooling:** Generic approach vs. stack-specific MCPs. 25–35 point gaps common.
- **Cloud infrastructure:** Same pattern. CC doesn't reach for the Terraform/AWS-specific tools that score 2x higher for those tasks.

That's not a surprise — it's exactly what you'd expect when Claude doesn't have runtime marketplace awareness. But having it scored and categorized is the interesting part. This is the data you'd need to make the argument to Anthropic that the plugin ecosystem is underutilized by default.

**A few things I learned building this:**

CC transcript JSONL nests `role` inside `message`, not at the top level. `isMeta=True` entries are loaded skill file content — not user messages. Tool results serialize as strings starting with `[{`. Without filtering all three, Haiku sees skill file text as conversation context and fires on ghost signals. Burned a day on this.

Haiku returns markdown-wrapped JSON even when you ask it not to. Always strip the fence.

`head -n -1` is GNU-only. `sed '$d'` is portable. Found this the hard way on macOS.

Exit code 2 from a PreToolUse hook blocks the tool call. Exit 0 passes through. Stdout goes into Claude's context. Stderr is suppressed. The whole hook must complete within 10 seconds or CC bypasses it regardless.

298 tests across 8 modules. The hardest thing to test is transcript parsing — the edge cases keep multiplying.

Repo: https://github.com/VisionAIrySE/Dispatch

Happy to go deep on the hook architecture or the catalog scoring logic.

---

## 4. Twitter/X Launch Thread

**Tweet 1 — The hook:**
```
Claude just picked the wrong tool for your task.

There's a better one installed on your machine.
It scores 35 points higher.
Claude doesn't know it exists.

This happens every session.

Thread: Dispatch, a runtime interceptor for Claude Code 🧵
```

**Tweet 2 — The scale:**
```
I crawled 10,978 tools this week.

skills.sh. Smithery.ai. glama.ai.
Official MCP registry. Both CC plugin marketplaces.

Scored by real signals — installs, stars, forks, freshness.

Claude Code knows about almost none of them at runtime.
```

**Tweet 3 — Hook 1:**
```
Hook 1 fires on every message. ~100ms.

Detects if you shifted tasks (flutter-debugging → writing tests).

On a confirmed shift: queries the catalog, ranks what's available for your category, injects the list into Claude's context before it responds.

Silent when nothing changes.
```

**Tweet 4 — Hook 2 (the money feature):**
```
Hook 2 is the one that matters.

Fires before Claude invokes any Skill, Agent, or MCP.

Scores CC's chosen tool vs marketplace alternatives: 0–100.

Gap ≥ 10 points → blocks. Shows you the comparison.

"proceed" to override. That's it. One word.
```

**Tweet 5 — The intercept moment:**
```
What it looks like when it fires:

[DISPATCH] CC is about to use 'superpowers:systematic-debugging' for Flutter work.
CC score: 58/100

1. flutter-mobile-app-dev [94/100] ← TOP PICK
   Purpose-built for Flutter/Dart. Widget tree inspection.
   Install: npx skills add flutter-mobile-app-dev -y

Gap: 36 points. Claude was about to leave 36 points on the table.
```

**Tweet 6 — The data:**
```
The CC Weakness Map.

Category-level data on where Claude's tool selection consistently underperforms:

📱 Mobile: CC ~55, market ~92 (+37)
🗄️ Database: CC ~61, market ~88 (+27)
☁️ Cloud infra: CC ~58, market ~85 (+27)

Not impressions. Scored behavioral data from real intercepts.
```

**Tweet 7 — Network effect:**
```
Here's the part that compounds.

Every install after a Dispatch recommendation → signal.
Every bypass → signal.
Every blocked intercept → signal.

The catalog scores update from real developer behavior.
Not LLM guesses. What developers actually reach for.

Gets sharper with every user.
```

**Tweet 8 — Founding tier:**
```
Hosted Pro: pre-ranked catalog, <200ms responses, Sonnet ranking.

First 300 users: $6/month, locked for life.
After that: $10/month.

You're not just buying a tool.
You're locking in a rate before the network effect makes this obviously worth more.

300 seats. Building now.
```

**Tweet 9 — Install:**
```
Install:

bash <(curl -fsSL https://raw.githubusercontent.com/VisionAIrySE/Dispatch/main/install.sh)

Sign in with GitHub. Copy the token. Start a new CC session.

Free hosted tier to start.
No API key required.

https://github.com/VisionAIrySE/Dispatch
```

**Tweet 10 — CTA:**
```
298 tests. MIT licensed. Read every line before installing.

The plugin ecosystem is deeper than most Claude Code users know.

Dispatch makes Claude actually use it.

⭐ https://github.com/VisionAIrySE/Dispatch
dispatch.visionairy.biz
```

---

## 5. Discord Message Templates

### Variant A — General dev server #tools channel

```
If you use Claude Code seriously, this is the gap nobody talks about: Claude has no runtime awareness of the tool ecosystem. It picks what it knows — not what's best for your task.

I catalogued 10,978 tools across skills.sh, Smithery.ai, glama.ai, and the MCP registries. Then built Dispatch: two CC hooks that intercept at the two moments that matter — when you shift tasks, and when Claude is about to invoke a tool.

When it fires, you see CC's choice scored against marketplace alternatives (0–100). If the gap is 10+ points, it blocks. One word to proceed.

GitHub: https://github.com/VisionAIrySE/Dispatch
Free to start, no API key required.
```

---

### Variant B — Claude Code official server

```
Something I've been working on that's relevant here: Dispatch is a two-hook runtime interceptor for CC that addresses a gap I kept running into.

The problem: Claude picks tools from what it knows — its defaults and whatever you've explicitly invoked before. It has no awareness of the 10,000+ tools across skills.sh, Smithery, glama.ai, the official MCP registry, and both plugin marketplaces. No signal about which tools actually perform best for which tasks.

**What Dispatch does:**

Hook 1 (UserPromptSubmit, ~100ms): Detects task shifts, maps to one of 16 MECE categories, surfaces ranked catalog results into Claude's context before it responds. Silent when nothing changed.

Hook 2 (PreToolUse): Before Claude invokes any Skill, Agent, or MCP — scores CC's choice vs marketplace alternatives on a 0–100 scale. Blocks if a better tool scores 10+ points higher. You type "proceed" to override.

The catalog is built from 10,978 tools crawled daily, scored by real signals (installs, stars, forks, freshness). Behavioral data from intercepts feeds back in. Gets sharper with use.

Free hosted tier (8/day) or BYOK. Pro = pre-ranked catalog (<200ms), Sonnet ranking, unlimited.

https://github.com/VisionAIrySE/Dispatch

298 tests if you want to audit before installing. Happy to discuss the hook architecture.
```

---

### Variant C — MCP community server

```
For folks building or maintaining MCPs: I built a runtime layer for CC that actively surfaces your tools to the right users at the right moment.

Dispatch intercepts before Claude invokes a tool. If your MCP scores higher than what Claude was about to use for that task category, it gets surfaced — scored, with install command, before Claude proceeds.

The catalog now covers 4,800+ MCPs across glama.ai, Smithery.ai, and the official registry. Scored by GitHub stars/forks/freshness. Better quality signal than raw install count for repos that are newer.

From the distribution angle: if you publish an MCP, Dispatch surfaces it to CC users doing exactly the tasks it's built for — no manual discovery required on their end.

Repo: https://github.com/VisionAIrySE/Dispatch
```

---

## 6. Blogwatcher Keyword List

### High Intent — Actively Looking for Tools

**Claude Code plugins and skills:**
- "Claude Code plugins"
- "Claude Code skills"
- "best Claude Code plugins"
- "Claude Code marketplace"
- "npx skills"
- "skills.sh"
- "agent skills Claude Code"
- "MCP server recommendations"
- "best MCP servers"
- "Claude Code MCP"
- "which MCP should I use"
- "Claude Code hooks"
- "UserPromptSubmit hook"
- "PreToolUse hook"
- "Claude Code hook examples"
- "Claude Code tool selection"
- "Claude picks wrong tool"

**Plugin/tool discovery pain:**
- "too many Claude Code plugins"
- "Claude Code plugin not working"
- "Claude Code skill not loading"
- "Claude Code context plugin"
- "how to use Claude Code plugins"
- "Claude Code plugin management"
- "install Claude Code skill"
- "Claude Code ignoring my skills"
- "Claude not using installed plugins"

### Medium Intent — Related Pain Points

**Workflow friction:**
- "Claude Code workflow tips"
- "Claude Code productivity"
- "getting more from Claude Code"
- "Claude Code mid-session"
- "Claude Code session management"
- "Claude Code best practices"
- "Claude Code setup"
- "improve Claude Code"

**MCP discovery:**
- "find MCP servers"
- "MCP registry"
- "modelcontextprotocol registry"
- "MCP server list"
- "Claude MCP plugins"
- "awesome MCP servers"
- "Smithery MCP"
- "glama MCP"

**Task switching and context:**
- "AI coding tool switching"
- "Claude Code different tasks"
- "Claude wrong tool"
- "Claude Code tool choice"

### Competitor and Related Project Mentions

- "SummonAI Claude"
- "claude-plugins-official"
- "awesome-agent-skills"
- "firebase agent-skills"
- "supabase agent-skills"
- "flutter-mobile-app-dev Claude"
- "superpowers skills Claude"
- "github-actions Claude Code"
- "systematic-debugging Claude"

### Brand Monitoring

- "Dispatch VisionAIrySE"
- "dispatch.visionairy.biz"
- "VisionAIrySE"
- "Dispatch Claude Code"
- "skill router Claude"
- "@VisionAIrySE"

### Technical Community Signals

- "UserPromptSubmit Claude"
- "PreToolUse Claude"
- "Claude Code hooks tutorial"
- "hook Claude Code session"
- "Claude Code settings.json hooks"
- "Claude hook exit code 2"
- "PreToolUse block tool call"

---

## 7. Response Templates

### Tier 1 — Reactive/Helpful

**Template 1A: "Claude isn't using my installed plugins/skills"**

> This is actually a real gap in how CC works — Claude has no runtime awareness of what's in the ecosystem, installed or not. It reaches for defaults.
>
> I built Dispatch specifically for this: a PreToolUse hook that intercepts before Claude invokes a tool and checks if something better-suited to your current task exists. If you have a purpose-built skill installed that scores higher, it surfaces it before Claude proceeds.
>
> Free to start: https://github.com/VisionAIrySE/Dispatch

---

**Template 1B: "Which MCP should I use for X?"**

> [Answer their specific question with genuine info — specific tool names, honest tradeoffs.]
>
> For finding the right MCP for a task automatically mid-session: I built Dispatch — a CC hook that intercepts before Claude invokes a tool and surfaces better alternatives from a catalog of 4,800+ MCPs scored by real signals. It fires at the moment it matters, not at install time.
>
> https://github.com/VisionAIrySE/Dispatch — free tier, open source.

---

**Template 1C: "Are there hooks for Claude Code?"**

> CC has two hook points: `UserPromptSubmit` (fires on every message) and `PreToolUse` (fires before any tool call). Both take a command, get 10 seconds, and exit code 2 on a PreToolUse hook blocks the tool call.
>
> I built Dispatch on both — UserPromptSubmit for task shift detection + catalog search, PreToolUse for intercepting bad tool choices before they happen. The code is a decent real-world reference for both hooks:
>
> https://github.com/VisionAIrySE/Dispatch — `dispatch.sh` and `dispatch-preuse.sh`.

---

**Template 1D: "How do you get Claude to use better tools?"**

> Short answer: you have to intercept it at the moment it's choosing. Claude doesn't proactively search for the best tool — it picks what it knows.
>
> I built a PreToolUse hook called Dispatch that does this: before Claude invokes any Skill, Agent, or MCP, it scores CC's choice against a catalog of 10,978 marketplace tools (0–100). If a better-suited tool scores 10+ points higher, it blocks and shows you the comparison. One word to override.
>
> https://github.com/VisionAIrySE/Dispatch

---

### Tier 2 — Proactive/Community

**Template 2A: "Show your CC setup" threads**

> Current setup beyond the usual MCPs:
>
> Dispatch (https://github.com/VisionAIrySE/Dispatch) — a two-hook runtime interceptor. Catches when Claude reaches for a suboptimal tool and surfaces what actually scores highest for the task. I've had it block and redirect to a purpose-built skill I'd installed months ago and never reached for manually. The 30-point gap intercepts are the useful ones.
>
> Free to run, BYOK or hosted free tier. If you're already invested in the CC plugin ecosystem, it's the layer that makes that investment actually pay off.

---

**Template 2B: "What tools are you using with CC?" threads**

> The one that changed how I think about the plugin ecosystem: Dispatch.
>
> It's a runtime interceptor — fires before Claude picks a tool, compares it against 10,978+ catalogued alternatives scored by real signals, and blocks if something better-suited scores 10+ points higher.
>
> What I didn't expect: the CC Weakness Map it generates. Category-level data showing where Claude's default tool choices consistently underperform. Mobile development and database tooling have the biggest gaps in my sessions.
>
> https://github.com/VisionAIrySE/Dispatch

---

### Tier 3 — Cold Outreach (GitHub Stargazers)

**Template 3A: Stargazers of skills.sh or awesome-agent-skills**

> Hey — saw you starred [repo]. Figured you're thinking about the CC tool ecosystem.
>
> I catalogued 10,978 tools this week across skills.sh, Smithery, glama.ai, and the MCP registries. Then built Dispatch: a CC hook that intercepts before Claude invokes a tool and surfaces what actually scores highest for the task — from that full catalog, at runtime.
>
> The gap between what Claude defaults to and what's available is bigger than I expected. Some categories are 30+ points apart.
>
> Free, open source: https://github.com/VisionAIrySE/Dispatch
>
> Happy to hear what you think if you try it.

---

**Template 3B: Stargazers of claude-code-related repos**

> Hey — noticed you're watching CC tooling. Built something you might find worth trying.
>
> Dispatch intercepts Claude's tool selection at runtime — before it invokes a Skill, Agent, or MCP, it compares the choice against 10K+ catalogued alternatives on a 0–100 scale. If a better tool exists for the current task, it surfaces it. You decide whether to proceed.
>
> The catalog is rebuilt daily from live sources scored by real behavioral signals. Gets sharper with use.
>
> Source open, 298 tests: https://github.com/VisionAIrySE/Dispatch
>
> Technical feedback welcome — especially on detection granularity.

---

**Template 3C: Stargazers of MCP-related repos**

> Hi — saw you starred [repo]. You're clearly invested in the MCP ecosystem.
>
> I built Dispatch: a CC PreToolUse hook that intercepts before Claude invokes an MCP and checks whether a higher-scoring alternative exists in a catalog of 4,800+ MCPs (glama.ai, Smithery, official registry). If the gap is 10+ points, it blocks and shows the comparison.
>
> From the other direction: if you publish an MCP, Dispatch surfaces it to CC users doing the exact tasks it's built for — scored by real signals, at the moment they need it.
>
> Open source: https://github.com/VisionAIrySE/Dispatch

---

## 8. awesome-claude-code PR Description

**PR Title:**
```
Add Dispatch — runtime tool interceptor for Claude Code
```

**Line to add** (Hooks section):

```markdown
- [Dispatch](https://github.com/VisionAIrySE/Dispatch) — Runtime tool interceptor: fires before Claude invokes any Skill, Agent, or MCP, scores the choice against 10,978 catalogued alternatives (0–100), and blocks when a better-suited tool exists. Also detects task shifts and surfaces ranked recommendations into context. Free hosted tier or BYOK.
```

**PR Body:**

```markdown
## What this adds

Dispatch is a two-hook CC runtime that intercepts Claude's tool selection at the moment it happens.

**The problem it addresses:** Claude has no awareness of the plugin/MCP ecosystem at runtime. It picks from defaults — not from what's installed, not from what's available, not from what actually performs best for the current task. With 10,978+ tools now catalogued across skills.sh, Smithery.ai, glama.ai, the official MCP registry, and both CC plugin marketplaces, the gap between what Claude picks and what's available is significant.

**Hook 1 (UserPromptSubmit):** Detects task domain/mode shifts (~100ms). On a confirmed shift, maps to one of 16 MECE categories, queries the pre-ranked catalog, injects ranked recommendations into Claude's context before it responds. Silent otherwise.

**Hook 2 (PreToolUse):** Before Claude invokes any Skill, Agent, or MCP — scores CC's chosen tool vs catalog alternatives 0–100. Blocks (exit 2) if a better-suited tool scores 10+ points higher. User types "proceed" to override.

## Why it fits here

- Hooks section is the right home — both hooks are the core of the project
- Addresses a structural gap: the CC plugin ecosystem is deep, Claude doesn't use it at runtime
- Open source (MIT), 298 tests, Python 3.8+ and Bash
- Free hosted tier (8 detections/day) or BYOK (unlimited)

## Links

- GitHub: https://github.com/VisionAIrySE/Dispatch
- Hosted tier: https://dispatch.visionairy.biz
- Catalog sources: skills.sh, Smithery.ai, glama.ai, registry.modelcontextprotocol.io
```

---

## 9. Dev.to Article Outline

**Title:**
```
I catalogued 10,978 Claude Code tools and built a runtime interceptor. Here's what the data shows.
```

**Subtitle:**
```
Two hooks, 298 tests, and a map of exactly where Claude's tool selection underperforms
```

---

### Section 1: The Problem Nobody Talks About

- Claude Code has 10,978+ tools across 6 marketplaces. At runtime, Claude picks from a handful of defaults.
- It's not a gap in capability — it's a gap in awareness. Claude has no mechanism to know what's available, what's installed, or what performs best for the current task.
- The specific failure mode: you install a skill or MCP, Claude never reaches for it unprompted, you eventually forget you have it. The gap between your install list and Claude's actual tool usage grows over time.
- Why this gets worse over time: the MCP ecosystem alone crossed 5,000 registered servers. The surface area of "things Claude doesn't know about" expands daily.
- The pivot moment: Claude was about to use a generic GitHub skill. I had a GitHub Actions-specific skill installed. It scored 35 points higher for what I was doing. Claude had no idea it was there.

**Narrative beat:** "The problem isn't that the tools don't exist. The problem is nothing connects them to Claude at runtime."

---

### Section 2: What Dispatch Does

- Two hooks, two jobs, two moments that matter
- Hook 1 (task shift detection): the silent background layer — runs on every message, exits in ~100ms when nothing changed, fires on confirmed shifts
- What "shift" means: domain changes (flutter → supabase) and mode changes (debugging → building) are both shifts. The granularity is tunable.
- What fires on shift: category mapping → catalog query → ranked list injected into Claude's context before it responds
- Hook 2 (PreToolUse intercept): the moment that matters most — before Claude commits to a tool choice
- Show the intercept output. Make it vivid. This is the sizzle.
- "proceed" as a design decision — one word, no friction, user stays in control
- The bypass token (120s TTL) — why it exists and how it prevents re-blocking the same choice

---

### Section 3: Building the Catalog

- 6 sources: skills.sh, glama.ai, Smithery.ai, registry.modelcontextprotocol.io, anthropics/claude-plugins-official, ananddtyagi/claude-code-marketplace
- What each source contributes and what it lacks (skills.sh has install counts, MCPs often don't)
- Scoring: installs 60% + GitHub stars 25% + forks 15%, log-normalized, staleness penalty
- MIN_INSTALLS ≥ 20 filter: why — noise reduction, quality signal, safety
- MCP safety note: MCPs run as processes with full tool access. No description + no GitHub repo = skip.
- What came back: 12,635 raw skills → 5,962 after filter. 4,821 MCPs. 195 plugins. 10,978 unique after dedup.
- The daily rebuild: why not incremental (simplicity, freshness), why it works at this scale (~5 minutes)

---

### Section 4: The CC Weakness Map

- What it shows: category-level comparison of average CC tool score vs. top marketplace alternative
- The categories with the biggest gaps: mobile development, database tooling, cloud infrastructure
- Why these gaps exist: Claude's defaults are general-purpose. The marketplace has purpose-built specialists.
- What this data means for the Anthropic relationship: behavioral data on CC tool selection gaps that Anthropic cannot collect internally. The pitch writes itself.
- The compounding signal: every Dispatch intercept adds a data point. More users = sharper map = better recommendations = more users.

---

### Section 5: Architecture Decisions and What I Learned

**The two-hook split:**
- Why not one hook: UserPromptSubmit and PreToolUse have different latency budgets, different output contracts, different trigger conditions
- Hook 1 is context-building. Hook 2 is decision-interception. They're different jobs.

**The transcript format:**
- `role` nested inside `message` — `entry.get("role")` always returns None
- `isMeta=True` entries are loaded skill file content — up to 1,400 words of noise
- `[{` strings are serialized tool results — not user messages
- How to filter: three conditions, all required
- How I found it: a day of ghost signals and eventually diffing raw transcript vs. what Haiku was seeing

**Hook output routing:**
- stdout → Claude's context (this is how recommendations surface)
- stderr → suppressed by CC
- exit 2 → blocks the tool call (PreToolUse only)
- The 10-second hard limit: real constraint, real design budget

**GNU vs. BSD:**
- `head -n -1` destroys you on macOS. `sed '$d'` works everywhere.
- This one broke a colleague's install and took 45 minutes to trace.

**State between hooks:**
- Hook 1 writes `~/.claude/dispatch/state.json`. Hook 2 reads it.
- Bypass token: 120s TTL, single-use. Prevents re-blocking the same tool invocation.
- Broad exception catches throughout — a hook that throws is a hook that blocks Claude. Never acceptable.

---

### Section 6: The Collective Intelligence Layer

- BYOK and Hosted run the same algorithm. BYOK is good. Hosted gets better with users.
- What aggregate data adds: install rates per category, bypass rates (signals where Claude's choice was actually right), conversion patterns
- How this changes scores over time: tools that developers actually reach for after a recommendation rise. Tools that get bypassed fall.
- The founding tier story: 300 seats at $6/month locked for life. You're not buying a current tool — you're buying in when the catalog is young and the behavioral data is just starting to compound.

---

### Section 7: Results and Honest Assessment

- The CC Weakness Map numbers (mobile, database, cloud infra gaps)
- What works well: the PreToolUse intercept, category-level routing, the 10-point gap threshold
- What's rough: cold start without many plugins installed, MCPs without GitHub repos get flat scores, catalog is only as good as what's crawlable
- The one intercept that made the build worth it: the GitHub Actions case
- What I'd do differently: build the category taxonomy before the task type generator

---

### Section 8: Install and What to Read First

- One-command install, requirements, what to do after
- Where to look in the source first: `dispatch-preuse.sh` for the intercept logic, `categories.json` for the taxonomy, `catalog_cron.py` for how the catalog is built
- Contributing: category mapper and scoring logic are the best entry points
- What the 298 tests cover and where the gaps are

---

**Tone notes:**
- Lead every section with a specific example or concrete number, not a general claim
- The data is the credibility — use the catalog numbers everywhere
- Acknowledge what doesn't work as readily as what does
- Technical specifics are the sizzle for a dev audience — precision sells
- Don't oversell the collective intelligence story — describe the mechanism, let developers understand the compounding math themselves

---

*End of marketing content package.*
