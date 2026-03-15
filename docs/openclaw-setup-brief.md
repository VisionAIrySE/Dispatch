# OpenClaw Setup Brief — Dispatch Launch Automation

**Purpose:** Step-by-step setup guide for OpenClaw. Bridges `openclaw-workflow-spec.md`
(n8n architecture + node definitions) and `marketing-content.md` (all post text).
Read this doc first. Reference the others for detail.

**Repo:** https://github.com/VisionAIrySE/Dispatch
**Full spec:** `docs/openclaw-workflow-spec.md`
**All post content:** `docs/marketing-content.md`

---

## What You're Building

4 n8n workflows on the OpenClaw Hostinger VPS:

| # | Workflow | Trigger | Auto-post? |
|---|----------|---------|-----------|
| 1 | Keyword Monitor → Slack Queue | Every 30 min | No — all queued for approval |
| 2 | Slack Approval → Publish | Slack button click | On approval only |
| 3 | Launch Schedule | Cron (set launch date below) | Yes — pre-written content |
| 4 | GitHub Stargazer Outreach | Daily | No — queued for approval |

---

## Phase 1 — Infrastructure (do this first)

### 1. Slack Channels

Create two channels in your Visionairy Slack:

- `#dispatch-queue` — incoming approval requests (one message per item)
- `#dispatch-log` — audit trail after every publish/reject

Message format in `#dispatch-queue`:
```
[PLATFORM] [INTENT: high/medium/low]
Original: <url>
Context: <first 280 chars>
---
Draft response:
<humanized draft>
---
[Approve] [Edit] [Reject]
```

Slack app permissions needed: `chat:write`, `interactive_components`, `incoming-webhook`

### 2. Notion Databases

Create three databases in Notion (integration must have access to all three):

**Seen Items DB** (deduplication — prevents re-processing the same post)

| Column | Type | Notes |
|--------|------|-------|
| Item ID | Title | Platform-specific ID (Reddit post ID, tweet ID, GitHub issue number) |
| Platform | Select | reddit, twitter, github, discord, blog |
| URL | URL | Link to original |
| Seen At | Date | Created time |

**Activity Log DB** (audit trail of all publish/reject actions)

| Column | Type | Notes |
|--------|------|-------|
| Action | Title | "published" or "rejected" |
| Platform | Select | reddit, twitter, github, discord, email |
| Content | Text | First 200 chars of posted content |
| URL | URL | Link to published post (if published) |
| Timestamp | Date | Action time |

**Contacts DB** (stargazer CRM for Workflow 4)

| Column | Type | Notes |
|--------|------|-------|
| GitHub Username | Title | Stargazer handle |
| Email | Email | If available from public profile |
| Location | Text | From profile |
| Bio | Text | From profile |
| Outreach Sent | Checkbox | Prevents duplicate outreach |
| Outreach Date | Date | When email sent |
| Response | Select | none, replied, installed, star-only |

### 3. Environment Variables

Load all secrets into 1password via `op` skill, then reference in n8n:

```bash
ANTHROPIC_API_KEY          # Claude API key
REDDIT_CLIENT_ID           # From reddit.com/prefs/apps → "Dispatch-Automation" app
REDDIT_CLIENT_SECRET       # Same app
REDDIT_USERNAME            # Account posting as
REDDIT_PASSWORD            # Account password
SLACK_BOT_TOKEN            # xoxb- token
SLACK_APPROVAL_WEBHOOK_URL # Workflow 2 webhook URL (set after creating workflow)
SLACK_QUEUE_CHANNEL_ID     # #dispatch-queue channel ID
SLACK_LOG_CHANNEL_ID       # #dispatch-log channel ID
GITHUB_TOKEN               # PAT with repo + issues read scope
NOTION_API_KEY             # Integration secret
NOTION_SEEN_ITEMS_DB_ID    # From Seen Items DB URL
NOTION_ACTIVITY_LOG_DB_ID  # From Activity Log DB URL
NOTION_CONTACTS_DB_ID      # From Contacts DB URL
```

Reddit app setup: https://www.reddit.com/prefs/apps → "create another app" → type: `script`

---

## Phase 2 — Workflow 3 (Launch Schedule) — Build This Second

**Why second:** This is the highest-value workflow. Pre-written content, auto-fires.
Set the launch date before building Workflows 1 and 4 so you know the cron times.

### Set Launch Date

Replace `LAUNCH_DATE` everywhere below with the actual date.
Format: `YYYY-MM-DD` — pick a Monday (best HN + Reddit engagement).

```
LAUNCH_DATE = [SET THIS BEFORE BUILDING]
```

### Cron Triggers and Their Content

**Action 1 — Show HN post**
- Cron: `LAUNCH_DATE` Monday 9:00 AM ET
- Platform: Hacker News (manual fallback recommended — HN has no public API for submissions)
- Title: `Show HN: Dispatch – runtime skill router for Claude Code (detects task shifts, recommends plugins)`
- Body: *full text in `docs/marketing-content.md` → Section 1 "Show HN Post"*

**Action 2 — r/ClaudeCode post**
- Cron: `LAUNCH_DATE` Monday 9:30 AM ET (30 min after HN)
- Subreddit: `ClaudeCode`
- Title: `Anyone else forgetting to switch plugins when they shift tasks mid-session? I built something to fix that.`
- Body:

```
I noticed I was spending the whole session with the wrong tools active. I'd be deep in Flutter debugging with the flutter-mobile-app-dev skill loaded, then pivot to writing tests — and never think to switch. The plugin was there. I just forgot.

So I built Dispatch: a Claude Code hook that watches your conversation, detects when you shift tasks, and surfaces a ranked list of relevant plugins before Claude responds. If you shift to GitHub Actions work, it shows you the github-actions skill you have installed (and any relevant ones you don't). If you're mid-way through a Supabase task and switch to Firebase, it catches that too.

It also has a second hook (PreToolUse) that intercepts before Claude invokes a skill and checks if a marketplace alternative would score ≥10 points higher. If it finds one, it blocks and shows you the recommendation — one word ("proceed") to bypass if you want to continue anyway.

No API key required to start — free hosted tier gives you 8 detections/day. BYOK works too if you prefer to keep everything local.

Repo + install: https://github.com/VisionAIrySE/Dispatch

Would be curious whether the detection granularity feels right to others — I've been tuning when it fires vs. stays silent.
```

**Action 3 — r/ClaudeDev post**
- Cron: `LAUNCH_DATE` Monday 10:00 AM ET
- Subreddit: `ClaudeDev`
- Title: `I built a two-hook runtime for Claude Code that intercepts task shifts and PreToolUse calls — here's the architecture`
- Body: *full text in `docs/marketing-content.md` → Section 3 "r/ClaudeDev Post"*

**Action 4 — Twitter/X thread**
- Cron: `LAUNCH_DATE` Monday 10:30 AM ET
- Post all 10 tweets as a thread via xurl skill
- Tweet text: *full thread in `docs/marketing-content.md` → Section 4 "Twitter/X Launch Thread"*

**Action 5 — awesome-claude-code PR**
- Cron: `LAUNCH_DATE` Monday 11:00 AM ET
- Repo: `awesome-claude-code` (find via GitHub search)
- PR title: `Add Dispatch — runtime skill router / hook for Claude Code`
- PR body: *full text in `docs/marketing-content.md` → Section 8 "awesome-claude-code PR Description"*

### Reddit Post node config

```
POST https://oauth.reddit.com/api/submit
Authorization: Bearer <fresh token — fetch immediately before this node>
User-Agent: OpenClaw-Dispatch-Monitor/1.0 (by /u/{{REDDIT_USERNAME}})
Content-Type: application/x-www-form-urlencoded

Body:
sr=ClaudeCode&kind=self&title={{title}}&text={{body}}&resubmit=false
```

Fetch fresh OAuth token before each post node (tokens expire 1 hour):
```
POST https://www.reddit.com/api/v1/access_token
Authorization: Basic base64({{REDDIT_CLIENT_ID}}:{{REDDIT_CLIENT_SECRET}})
Body: grant_type=password&username={{REDDIT_USERNAME}}&password={{REDDIT_PASSWORD}}&scope=submit
```

---

## Phase 3 — Workflow 1 (Keyword Monitor)

Polls every 30 min. Deduplicates against Notion. Drafts responses via Claude. Queues to Slack.

### Subreddits to Monitor

```
r/ClaudeCode         — primary target
r/ClaudeDev          — technical audience
r/MachineLearning    — broader AI tools
r/programming        — general dev
r/SideProject        — launch announcements
```

### Keywords to Watch

Paste these into the blogwatcher skill config and the Reddit/Twitter HTTP Request nodes.
Full list with categories in `docs/marketing-content.md` → Section 6 "Blogwatcher Keyword List".

**Top priority keywords (set as high-intent alerts):**
```
"Claude Code plugins"
"Claude Code skills"
"npx skills"
"skills.sh"
"UserPromptSubmit hook"
"PreToolUse hook"
"MCP server recommendations"
"best Claude Code plugins"
```

**Brand monitoring (always-on):**
```
"Dispatch VisionAIrySE"
"dispatch.visionairy.biz"
"VisionAIrySE"
"Dispatch Claude Code"
```

### Claude API node (classify intent)

```json
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 100,
  "system": "You are an intent classifier. Given a social media post, return JSON: {\"intent\": \"high|medium|low\", \"category\": \"question|complaint|share|neutral\", \"relevant\": true|false}. Relevant means the post is about Claude Code plugins, skills, MCP servers, or the Dispatch tool specifically.",
  "messages": [{"role": "user", "content": "Post: {{post_text}}"}]
}
```

### Claude API node (draft response)

```json
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 300,
  "system": "You are a helpful developer responding to posts about Claude Code tools. You work on Dispatch (https://github.com/VisionAIrySE/Dispatch), a runtime skill router for Claude Code. Write a genuine, helpful reply that addresses the person's question first, then mentions Dispatch only if directly relevant. Never be promotional. Match the tone of the platform. Keep it under 200 words.",
  "messages": [{"role": "user", "content": "Platform: {{platform}}\nOriginal post: {{post_text}}\nURL: {{post_url}}\n\nWrite a response:"}]
}
```

### Approval rules (Switch node)

```
NEVER auto-post:
- intent = "low"
- category = "complaint" or "negative"
- post mentions a competitor negatively
- cold DM (any platform)

QUEUE for approval:
- All replies to keyword mentions
- Discord community posts
- Cold outreach emails

AUTO-POST (Workflow 3 only):
- Scheduled launch posts (pre-written, cron-triggered)
```

---

## Phase 4 — Workflow 2 (Slack Approval → Publish)

Triggered by Slack button clicks from `#dispatch-queue`.

### Webhook setup

1. Create n8n webhook trigger node — copy the webhook URL
2. Set `SLACK_APPROVAL_WEBHOOK_URL` env var to that URL
3. Configure Slack app Interactivity → Request URL = the webhook URL

### Route by action

```
action_id = "approve"  →  Route by source  →  post to platform
action_id = "edit"     →  Post edit modal to Slack  →  re-queue with edited text
action_id = "reject"   →  Log to Notion Activity Log only
```

### Post to Notion Activity Log (all paths)

```json
{
  "parent": {"database_id": "{{NOTION_ACTIVITY_LOG_DB_ID}}"},
  "properties": {
    "Action": {"title": [{"text": {"content": "{{action_id}}"}}]},
    "Platform": {"select": {"name": "{{platform}}"}},
    "Content": {"rich_text": [{"text": {"content": "{{content_preview}}"}}]},
    "URL": {"url": "{{published_url}}"},
    "Timestamp": {"date": {"start": "{{now}}"}}
  }
}
```

---

## Phase 5 — Workflow 4 (Stargazer Outreach)

Runs daily. Gets new stargazers from GitHub, enriches profiles, checks CRM, drafts outreach, queues for approval.

### GitHub stargazers endpoint

```
GET https://api.github.com/repos/VisionAIrySE/Dispatch/stargazers
Authorization: Bearer {{GITHUB_TOKEN}}
Accept: application/vnd.github.v3.star+json
Per-page: 30
```

### Claude API node (draft outreach)

```json
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 200,
  "system": "Write a short, genuine outreach email to a developer who starred the Dispatch repo on GitHub. They are likely a Claude Code user. Keep it under 100 words. Do not be promotional. Mention one specific thing from their GitHub profile (bio, repos, location if available). Ask if they tried it and if they have feedback. Sign as Russ from Visionairy.",
  "messages": [{"role": "user", "content": "Recipient: {{github_username}}\nBio: {{bio}}\nLocation: {{location}}\nTop repos: {{top_repo_names}}"}]
}
```

**Hard rules:**
- Never send if `Outreach Sent` = true in Contacts DB
- Never send to accounts with < 5 GitHub repos (likely bots)
- Always queue for Slack approval before sending — never auto-fire

---

## Phase 6 — Response Templates

When Workflow 1 drafts a reply to a keyword mention, prime Claude with the appropriate template from `docs/marketing-content.md` → Section 7.

Quick reference — inject the right template based on post category:

| Post is about... | Use template |
|-----------------|-------------|
| "Which MCP should I use?" | Template 1A |
| "How do you manage plugins?" | Template 1B |
| "Are there hooks for Claude Code?" | Template 1C |
| General community question | Template 2A |
| Cold outreach to developer | Template 3A |

Full template text in `docs/marketing-content.md` → Section 7 "Response Templates".

---

## Launch Day Checklist

- [ ] `LAUNCH_DATE` set in all Workflow 3 cron nodes
- [ ] All environment variables loaded in 1password + n8n
- [ ] Notion databases created with schemas above
- [ ] Slack app created, channels made, webhook URL set
- [ ] Reddit OAuth app created, credentials in 1password
- [ ] Workflow 3 dry-run with test cron (fire once manually, check output)
- [ ] Workflow 1 running — verify one item flows to `#dispatch-queue`
- [ ] Workflow 2 test — approve a test item, verify it posts and logs to Notion
- [ ] `#dispatch-log` receiving audit entries
- [ ] HN post ready for manual submit (no API — post manually on launch day)
