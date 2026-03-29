# ToolDispatch Launch Plan — Week of March 29, 2026

**Goal:** First 100 installs + first paying customer by Friday.

**The product works. 216 tests passing. The gap is reach.**

---

## THE MESSAGES (memorize these, use exactly)

### Message A — Vibe Coders
> "Claude Code generates architecturally sound code that doesn't connect. I built a hook that catches broken imports, wrong function signatures, and missing env vars at the point of edit — before you run anything.
>
> Vibe coders are spending HOURS debugging symptoms. This catches the root cause in 200ms, automatically, every time CC edits a file.
>
> It's called ToolDispatch. Free to install."

### Message B — Experienced Devs
> "The Claude Code plugin ecosystem is growing faster than anyone can track. CC defaults to whatever worked last time — not the best tool for your current task.
>
> I built a hook that intercepts CC's tool calls and blocks them if a marketplace alternative scores 10+ points higher for your task. Shows you the comparison, lets you decide.
>
> Free: 8 intercepts/day. Install in 2 minutes."

### Message C — Technical / Static Analysis Angle
> "Static analysis tools like Pyright and mypy were designed for human-written code. They fail on the specific bugs AI generates: hallucinated APIs, stale function signatures from training data, missing env vars.
>
> XF Audit is an AST scanner built specifically for AI-generated Python code. Caller chain analysis. 200ms at edit time. Catches the class of errors type checkers miss.
>
> Open source. Free tier. 2-minute install."

### Hook Lines (use as post titles or opening sentences)
- "Claude Code leaves a specific class of bug that Pyright will never catch. Here's the fix."
- "I spent 4 hours debugging a Claude Code session. Then I built something so I'd never have to again."
- "The Claude Code plugin ecosystem has 300+ tools. You're probably using 10. Here's how I found the rest."
- "Vibe coding is amazing until your code doesn't connect. Here's what I built to stop the whack-a-mole."

---

## NETWORK EFFECTS NOTE (use in pitches and community posts)

ToolDispatch gets better with adoption. Every intercept tells the platform which tools developers actually switch to for which tasks. Every install conversion teaches the ranker what works. The recommendations improve as the user base grows — early adopters get a better product over time, not the same one.

Use this in: Pro tier upsell copy, community posts, investor pitches, README.

---

## DAY BY DAY — THIS WEEK

---

### MONDAY — Foundation (3 hours)

**Step 1: Submit to awesome-claude-skills (30 min)**
1. Go to: https://github.com/travisvn/awesome-claude-skills
2. Fork the repo
3. Add ToolDispatch to the README under a "Utilities / Developer Productivity" section:
```
- [ToolDispatch](https://github.com/ToolDispatch/Dispatch) — Runtime tool router + AI code contract checker. Surfaces the best plugin/skill/MCP for your task; catches broken imports, wrong signatures, and missing env vars at edit time. [Free + Pro]
```
4. Open a PR. Title: "Add ToolDispatch — runtime tool router + AI code contract checker"

**Step 2: Submit to claudemarketplaces.com (15 min)**
1. Go to: https://claudemarketplaces.com
2. Find the submit/add tool option
3. Submit both modules:
   - Name: ToolDispatch
   - Description: Use Message C above (technical angle)
   - GitHub: https://github.com/ToolDispatch/Dispatch
   - Category: Developer Tools / Utilities

**Step 3: Submit to CC Marketplace (30 min)**
1. plugin.json is ready in `.claude-plugin/`
2. Submit to: platform.claude.com/plugins/submit
3. Use Message B as the description
4. This is the highest-leverage single placement. One official listing outperforms all other channels.

**Step 4: Get `npx skills add` working (1 hour)**
Test the install command in a clean environment:
```bash
npx skills add ToolDispatch/Dispatch
```
If it doesn't work cleanly, fix it. This is the in-ecosystem install path.

---

### TUESDAY — The Demo (3 hours)

**This is the most important day. Nothing converts without a demo.**

**Step 1: Set up the demo project (30 min)**
Create a clean vibe-coded Python project that will trigger both modules:
```bash
mkdir /tmp/demo-app && cd /tmp/demo-app
# Create a few Python files with:
# - An import that references a package not in requirements.txt
# - A function called with the wrong number of arguments somewhere
# - An env var referenced but not in .env
# - Some production stubs (pass / raise NotImplementedError)
git init && git add . && git commit -m "initial"
```

**Step 2: Record the demo (2 hours)**

Install asciinema if not already installed:
```bash
pip install asciinema
# or: sudo apt-get install asciinema
```

Start recording:
```bash
asciinema rec demo.cast --title "ToolDispatch in action"
```

**The demo script — follow this exactly:**
1. Open a CC session in the demo project: `claude`
2. Say: "Add a function to process user payments"
3. Let CC generate code with contract issues
4. PAUSE — show the XF Audit violation output (it fires on the edit)
5. Say: "Now add Stripe webhook handling"
6. Let CC use whatever tool it reaches for
7. SHOW the Dispatch intercept notification (scored comparison)
8. Say "proceed" to let it continue
9. Stop recording

Convert to GIF:
```bash
pip install agg
agg demo.cast demo.gif
# Or: https://asciinema.org/docs/how-it-works — upload and download GIF
```

**What you'll have:** A 30-45 second GIF showing both modules firing in sequence.

---

### WEDNESDAY — The Launch Post (2 hours)

**Target: r/ClaudeAI first, then Discord, then X.**

**r/ClaudeAI post (Vibe Coder angle — use this exactly):**

```
Title: I built a hook that stops Claude Code from leaving broken code in your project

[POST BODY — copy and paste]

Something I've noticed: Claude Code generates architecturally sound code that often doesn't connect. Broken imports, wrong function signatures, missing env vars. You run it, something blows up, you ask Claude Code to fix it, it fixes a symptom, something else blows up. Repeat for 2-4 hours.

I built something to stop this.

**XF Audit** hooks into Claude Code's PreToolUse event. Every time CC edits a file, it runs an AST scan (~200ms): checks imports exist, function signatures match their callers, env vars are defined, no stubs in production code. If it catches something, it shows the violation and a repair plan before the code runs.

[INSERT YOUR GIF HERE]

**Dispatch** catches the other problem — CC defaults to whatever tool worked last time, not the best tool for your current task. It intercepts CC's tool calls and blocks them if something in the marketplace scores significantly higher for what you're actually building. Shows you the comparison. You decide.

Both run automatically. Silent on clean pass. Loud when they catch something.

**Free tier:** 8 Dispatch intercepts/day, XF Audit Stage 1 always free.
**Founding Pro:** $6/month, first 300 users (locks in forever). Unlimited everything.

Install (2 min):
```
git clone https://github.com/ToolDispatch/Dispatch
cd Dispatch && bash install.sh
```

Happy to answer questions about the architecture or how it works.
```

**Discord post (Anthropic developer community):**
Same post, but shorten it. Lead with the GIF. One paragraph of context. Install link. "DM or reply with questions."

**X/Twitter thread:**
Tweet 1: "I built a Claude Code hook that catches broken contracts at the point of edit. 200ms. Automatic. Shows the violation + repair plan before you run anything. [GIF]"
Tweet 2: "Called XF Audit. It catches: broken imports, wrong function signatures, missing env vars, stubs left in prod. The class of bugs Pyright doesn't catch in AI-generated code."
Tweet 3: "The second module (Dispatch) intercepts Claude Code's tool calls and blocks them if the marketplace has something better. Shows you the scored comparison."
Tweet 4: "Both free to start. 2-minute install. github.com/ToolDispatch/Dispatch"

---

### THURSDAY — Respond and Amplify (2 hours)

**Step 1: Reply to every comment on Wednesday's posts (1 hour)**
- For "how does it work" questions: link to the technical blog post you'll write (or the README)
- For "what about X" questions: answer specifically
- For "that's cool" responses: "Thanks — what's your biggest CC pain right now?" (start conversations)

**Step 2: Share in additional communities (30 min)**
- Hacker News "Show HN" (only if you have the GIF — HN punishes weak demos)
  - Title: "Show HN: ToolDispatch – runtime tool router and AI code contract checker for Claude Code"
- dev.to article — expand the r/ClaudeAI post into a longer technical piece
  - Title: "Why static analysis fails on AI-generated code (and what to do about it)"
  - Include: Pyright/mypy gap, XF Audit architecture, how the AST scan works

**Step 3: Post to Product Hunt (if ready)**
- Only if you have a clean product page + demo GIF
- Prep: hunter + maker profile, product description, gallery images
- DO NOT post on a Friday/weekend. Monday-Tuesday is the window.

---

### FRIDAY — First Sale (1 hour)

**Identify your most engaged users from the week's posts.**

Anyone who:
- Asked a detailed technical question
- Said they installed it
- Replied twice or more

**Direct message them (exact copy):**
```
Hey [name] — saw you tried ToolDispatch this week. Any issues with the install?

Founding Pro is $6/month, first 300 users lock in that price for life. That's the tier that gets unlimited intercepts + Stages 2-4 of XF Audit (full caller chain analysis + repair plans).

If you're using CC heavily, it'll catch something real in the first week. If it doesn't, I'll refund you.

[Upgrade link: https://tooldispatch.visionairy.biz/pro?token=YOUR_TOKEN]
```

Goal: 1 paying customer by EOD Friday.

---

## AUTOMATIONS TO SET UP (once, then runs itself)

### Automation 1: Signup → Slack notification (already built)
Verify SLACK_LOG_WEBHOOK_URL is working: when someone signs up via GitHub OAuth, #dispatch-log should get a notification. Test it.

### Automation 2: n8n — Reddit/HN mention tracker
Set up an n8n workflow that monitors Reddit (r/ClaudeAI) and HN for mentions of "ToolDispatch". Trigger: RSS or API poll every 2 hours. Action: Slack notification to #dispatch-queue.

### Automation 3: n8n — New GitHub star → welcome DM
When someone stars the ToolDispatch/Dispatch repo, send them a GitHub API welcome message:
"Thanks for the star! If you try it out, I'd love to hear what you're using CC for — it helps me improve the tool recommendations. Reply here anytime."

### Automation 4: OpenClaw — Outreach queue
Point OpenClaw at the ToolDispatch repo. Target: developers who comment in r/ClaudeAI complaining about broken CC output or missing tool discovery. Queue personalized outreach messages for Russ to approve in #dispatch-queue.

---

## GSTACK TOOLS FOR THIS WEEK

### `/ship` — Push the committed changes to GitHub
Run after Monday's changes are verified. Pushes to GitHub, opens a PR if needed.
```
/ship
```

### `/browse` — QA test the landing page
Test `https://tooldispatch.visionairy.biz` — check install flow, token page, Pro upgrade. Use before the launch post goes live.
```
/browse
```

### `/document-release` — Update all docs after shipping
After `/ship` completes, run this to catch any stale README or doc entries.

### `/canary` — Monitor Render after deploy
After the launch post goes live and install traffic spikes, run this to watch for errors.

### `/retro` — End of week review
Friday EOD: run `/retro` to see what shipped, what the install rate was, what to fix next week.

---

## SUCCESS METRICS — THIS WEEK

| Metric | Target |
|--------|--------|
| awesome-claude-skills PR | Filed by Monday |
| CC Marketplace submitted | Filed by Monday |
| Demo GIF exists | Done by Tuesday |
| r/ClaudeAI post live | Wednesday |
| GitHub stars | +25 by Friday |
| Installs from post | 50+ by Friday |
| First paying customer | 1 by Friday |

---

## WHAT NOT TO DO THIS WEEK

- Don't polish the README instead of launching
- Don't add features before getting the launch post out
- Don't post without the GIF — text posts about dev tools get ignored
- Don't wait for CC Marketplace approval before launching elsewhere
- Don't skip the DM to engaged users on Friday — that's where the first sale comes from

---

## COMPETITIVE POSITIONING (if asked)

"Pyright/mypy catch type errors in human-written code. They don't catch hallucinated APIs, stale function signatures from AI training data, or missing env vars that AI assumed would exist. XF Audit is designed for that class of failure. There's nothing else in the market doing this for CC."

"The CC plugin ecosystem has no discovery layer. You install tools based on what you heard about, not what's best for your current task. Dispatch is the missing discovery layer. No competition."
