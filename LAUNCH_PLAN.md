# Dispatch — Launch Plan
# Coordinator: Claude Code | Executor: You (approve/execute each step before advancing)
#
# Rules:
# - Complete and confirm each step before moving to the next
# - Claude Code coordinates, drafts code, and reviews output
# - You execute terminal commands, approve posts, and make platform decisions
# - Mark steps DONE by adding [x] and a note before moving on
# - If a step fails, stop and resolve before continuing

---

## PHASE 0 — Foundation (Prerequisites for everything else)

### Step 0.1 — Create UI Experiments Branch
**NOTE: Loom demo moved to AFTER UI polish (Phase 1). No second chances at first impressions.**
**Who:** You
**What:**
```bash
cd /home/visionairy/Dispatch
git checkout -b ui-experiments
```
**Success criteria:** On `ui-experiments` branch, `git status` clean.
**Status:** [ ]

---

### Step 0.2 — Record the Loom Demo (AFTER Phase 1 UI polish is live)
**Who:** You
**What:** Record a 30-60 second Loom clip showing Dispatch firing naturally in a Claude Code session.
- Open a new CC session in a real project
- Start on one task (e.g., Flutter), then switch topics (e.g., "let's write some tests")
- Capture the terminal showing the polished Dispatch banner firing with recommendations
- No narration needed — let the UI speak
- Export as: GIF (for Reddit/Twitter posts) + full video link (for HN/Product Hunt)

**Success criteria:** GIF exported, Loom link working, both saved locally.
**Status:** [ ]
**Who:** You (Claude Code coordinates)
**What:**
```bash
cd /home/visionairy/Dispatch
git checkout -b ui-experiments
```
**Success criteria:** On `ui-experiments` branch, `git status` clean.
**Status:** [ ]

---

## PHASE 1 — UI Polish

### Step 1.1 — Implement Dual UI Approach (Terminal)
**Who:** Claude Code writes the code, you apply and test
**What:** Two changes to `dispatch.sh`:

**A. Add pending_notification.json writer** — on confirmed shift, hook writes:
```json
{"task_type": "flutter", "installed": [...], "suggested": [...]}
```
to `~/.claude/skill-router/pending_notification.json` before the /dev/tty output.

**B. Auto-add CLAUDE.md instruction** — install.sh appends to `~/.claude/CLAUDE.md`:
```
## Dispatch Hook Notifications
At the start of each response, check if ~/.claude/skill-router/pending_notification.json
exists. If it does, read it and display a brief formatted summary of the detected task
and tool recommendations, then delete the file before continuing.
```

**C. Visual improvements to /dev/tty output:**
- Detected task type name in cyan bold
- Confidence shown as `high` / `medium` label (not raw float)
- Installed items in green `+`, suggested in yellow `↓`
- `[Enter] or wait 3s` on its own prominent centered line

**Test:** Start a new CC session (required for hook reload), switch task types, confirm both
/dev/tty banner (CLI) and Claude surfacing notification (TUI) work.

**Success criteria:** Both display modes working, 20/20 tests still passing.
**Status:** [ ]

---

### Step 1.2 — Web UI Polish (app.py)
**Who:** Claude Code writes, you deploy to Render
**What:** Polish four pages in `Dispatch-API/app.py`:

**Landing page (`/`):**
- Add 3-step "how it works" section below the demo block
- Add GitHub star badge (dynamic via shields.io)
- Add "500+ plugins surfaced" social proof line
- Add Vib8 subtle cross-promo in footer

**Token page (`/auth/callback`):**
- Add explicit CLI paste commands below the token
- Add "What's next" section with 3 bullet steps
- Make the click-to-copy area more prominent (pulsing border on load)

**Pro sales page (`/pro` — before Stripe redirect):**
- Build an actual sales page with feature comparison table (Free vs Pro)
- Only redirect to Stripe when user clicks "Upgrade Now" button
- Add testimonial placeholder slot

**Success page (`/success`):**
- Add onboarding checklist (3 steps to get started)
- Add Vib8 cross-promo block
- Add Discord/GitHub community links

**Success criteria:** All four pages render correctly on dispatch.visionairy.biz after deploy.
**Status:** [ ]

---

### Step 1.3 — Merge UI Branch + Deploy
**Who:** You
**What:**
```bash
cd /home/visionairy/Dispatch
git checkout main
git merge ui-experiments
git push origin main
# Render auto-deploys from main — verify at dispatch.visionairy.biz
```
Also push Dispatch-API changes:
```bash
cd /home/visionairy/Dispatch-API
git push origin main
```

**Success criteria:** Live site reflects all UI changes, hook still fires in a new CC session.
**Status:** [ ]

---

## PHASE 2 — GitHub Repo Polish

### Step 2.1 — README Hero + GIF
**Who:** You add the GIF, Claude Code drafts any README text changes
**What:**
- Export Loom clip as GIF (from Step 0.1)
- Add GIF to README below the logo, above the terminal code block
- Add shields.io badges row: GitHub stars, license, Python version, "works with Claude Code"
- Update the "Early release" callout to reflect current stable status

**Success criteria:** README renders correctly on GitHub with animated GIF and badges.
**Status:** [ ]

---

### Step 2.2 — Add CONTRIBUTING.md and CHANGELOG.md
**Who:** Claude Code drafts, you review and commit
**What:**
- `CONTRIBUTING.md`: how to submit classifier improvements, evaluator improvements, bug reports
- `CHANGELOG.md`: document all fixes from 2026-03-05 session as v0.2.0

**Success criteria:** Both files on main, rendering on GitHub.
**Status:** [ ]

---

### Step 2.3 — Pin Repo to VisionAIrySE Org Profile
**Who:** You (GitHub UI)
**What:** Go to VisionAIrySE org → Settings → Pinned repositories → pin Dispatch.

**Success criteria:** Dispatch appears on VisionAIrySE org homepage.
**Status:** [ ]

---

## PHASE 3 — OpenClaw VPS Setup

### Step 3.1 — Provision Hetzner CX11
**Who:** You
**What:**
1. Create account at hetzner.com if needed
2. Create CX11 server:
   - Image: Ubuntu 24.04
   - Location: Ashburn (US) or Nuremberg (EU) — your preference
   - Add your SSH public key
   - Name it: `openclaw-vps`
3. Note the IP address

**Cost:** ~$4/month
**Success criteria:** Can SSH in as root.
**Status:** [ ]

---

### Step 3.2 — Initial Server Hardening
**Who:** You (Claude Code provides exact commands)
**What:** Run after SSH in as root:
```bash
# Create non-root user
adduser ocuser
usermod -aG sudo ocuser

# Copy SSH keys to new user
rsync --archive --chown=ocuser:ocuser ~/.ssh /home/ocuser

# Firewall — only SSH open initially, OC gateway stays private via Tailscale
ufw allow OpenSSH
ufw enable

# Disable root SSH login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd
```

**Success criteria:** Can SSH as `ocuser`, root login rejected, `ufw status` shows only SSH allowed.
**Status:** [ ]

---

### Step 3.3 — Install Tailscale (Private Access Layer)
**Who:** You
**What:**
```bash
# On VPS as ocuser
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Follow link to authenticate with your Tailscale account
```
Also install Tailscale on your local machine if not already installed.

**Why:** OpenClaw gateway stays on localhost — Tailscale provides secure private access
from your machine without exposing OC to the public internet.

**Success criteria:** VPS and your machine both appear in Tailscale network. Can ping VPS via Tailscale IP.
**Status:** [ ]

---

### Step 3.4 — Install Node 22 + OpenClaw
**Who:** You
**What:**
```bash
# On VPS as ocuser
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version  # must be v22.x

# Install OpenClaw globally
sudo npm install -g openclaw
openclaw --version
```

**Success criteria:** `openclaw --version` returns successfully.
**Status:** [ ]

---

### Step 3.5 — Run OpenClaw Onboarding
**Who:** You (Claude Code advises on configuration choices)
**What:**
```bash
openclaw onboard
```
Wizard will ask for:
- Gateway port: use `3001` (not default 3000, avoids common conflicts)
- Workspace name: `visionairy`
- Channels to connect: skip all for now — configured per-step below

**Success criteria:** OpenClaw gateway starts, accessible via `http://<tailscale-ip>:3001`
**Status:** [ ]

---

### Step 3.6 — Run OC as Persistent systemd Service
**Who:** You
**What:**
```bash
sudo tee /etc/systemd/system/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw Agent
After=network.target

[Service]
Type=simple
User=ocuser
ExecStart=/usr/bin/openclaw start
Restart=on-failure
RestartSec=5
Environment="OC_GATEWAY_HOST=127.0.0.1"
Environment="OC_GATEWAY_PORT=3001"
WorkingDirectory=/home/ocuser

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable openclaw
sudo systemctl start openclaw
sudo systemctl status openclaw
```

**Success criteria:** Service shows `active (running)`, survives a `sudo reboot`.
**Status:** [ ]

---

### Step 3.7 — Set Up Approval Gateway Slack Channel
**Who:** You (Claude Code advises on skill configuration)
**What:**
1. In your Slack workspace, create private channel: `#dispatch-staging`
2. Create a new Slack app (separate from VPE bot) at api.slack.com:
   - Name: `OpenClaw`
   - Scopes: `chat:write`, `reactions:read`, `channels:history`
   - Install to workspace, note Bot Token (`xoxb-...`)
3. Invite the bot to `#dispatch-staging`
4. Store token securely in `/home/ocuser/.env` on VPS (not in OC config directly)

**Approval rules (configure in OC):**
- ✅ reaction on staged post → OC publishes to platform
- ❌ reaction → OC discards
- No reaction within 24h → auto-publish for GitHub issue responses only, discard everything else

**Success criteria:** OC can post to `#dispatch-staging`, you can react to approve/reject.
**Status:** [ ]

---

## PHASE 4 — OpenClaw Channel Configuration

NOTE: For each channel, use the minimum-scope credentials needed.
All credentials stored in `/home/ocuser/.env` — never hardcoded in OC config files.

### Step 4.1 — Email Forwarding Proxy
**Who:** You
**What:**
1. Create dedicated address: `dispatch-agent@gmail.com` (or alias on existing domain)
2. In your main email: set auto-forward rules for:
   - GitHub notifications (stars, issues, PRs)
   - Stripe receipts/alerts
   - Any newsletter/digest relevant to dev tools
3. Connect `dispatch-agent@gmail.com` to OC via Gmail skill (OAuth read-only scope)
4. OC analyzes incoming email, drafts responses → stages to `#dispatch-staging`
5. You paste/send approved responses from your real account

**Success criteria:** Test forward arrives, OC picks it up, draft appears in staging channel.
**Status:** [ ]

---

### Step 4.2 — RSS/Keyword Monitoring (Zero Credentials)
**Who:** Claude Code configures, you apply
**What:** Configure OC to monitor these feeds (no auth needed):
- `reddit.com/r/ClaudeAI/.rss` — keyword: "plugin", "skill", "hook", "task shift"
- `reddit.com/r/ChatGPTCoding/.rss` — keyword: "claude code"
- `news.ycombinator.com/rss` — keyword: "claude", "AI agent", "developer tools"
- `dev.to/feed` — keyword: "claude code", "AI tools"
- Competitor GitHub releases feed (SummonAI if available)

OC posts keyword matches to `#dispatch-staging` as FYI (no approval needed for monitoring).
OC flags posts that are good reply opportunities → those require your ✅ before responding.

**Success criteria:** First batch of RSS matches appears in staging channel.
**Status:** [ ]

---

### Step 4.3 — Twitter/X (Shadow Account)
**Who:** You
**What:**
1. Create `@DispatchAI` Twitter/X account (separate from personal)
2. Register a Twitter Developer App with write access
3. Connect to OC via Twitter skill
4. Approval flow: OC drafts → `#dispatch-staging` → ✅ → OC posts from `@DispatchAI`
5. You manually repost notable content to your personal account

**Content OC will post:**
- Dispatch demo GIF with launch message
- Star milestone celebrations (100, 250, 500 stars)
- New skill recommendations discovered in the registry
- Vib8 cross-promotions (2x/week)
- Developer tip threads

**Success criteria:** Test post staged, approved, published to `@DispatchAI`.
**Status:** [ ]

---

### Step 4.4 — LinkedIn
**Who:** You
**What:**
1. Connect OC to LinkedIn via LinkedIn skill (OAuth)
2. Approval flow: same staging pattern
3. Content angle: professional/builder narrative — "I built this over a weekend with Claude Code"

**Content cadence:** 2x/week — alternating Dispatch and Vib8 angles.

**Success criteria:** Test post staged and published.
**Status:** [ ]

---

### Step 4.5 — Reddit
**Who:** You
**What:**
1. Create dedicated `u/DispatchAI` Reddit account
2. Register Reddit API app, connect to OC
3. Target subreddits: r/ClaudeAI, r/ChatGPTCoding, r/programming, r/SideProject, r/artificial
4. OC monitors for reply opportunities (from RSS step) — drafts replies for approval
5. OC queues launch post (with GIF) for manual trigger on launch day

**Note:** Reddit anti-spam requires account age and karma before posting freely.
Create the account now so it ages before launch week.

**Success criteria:** Account created, OC connected, first monitored reply opportunity staged.
**Status:** [ ]

---

### Step 4.6 — Facebook Groups
**Who:** You
**What:**
1. Identify target groups: "Claude AI Users", "AI Developer Tools", "Side Projects & Startups"
2. Join groups from your personal account (OC cannot join on your behalf — you do this manually)
3. Connect Facebook account to OC (Page or personal — use Page for less risk)
4. OC drafts posts → `#dispatch-staging` → you post manually to groups (FB Groups don't have API post access)

**Note:** Facebook Groups API for posting is restricted — OC drafts, you copy-paste into groups.
OC handles your Facebook Page (if you have one) with full API access.

**Success criteria:** First Group post draft staged, OC connected to FB Page.
**Status:** [ ]

---

### Step 4.7 — TikTok
**Who:** You + Claude Code
**What:**
1. Create `@DispatchAI` TikTok account
2. TikTok content = short terminal screen recordings (15-30 sec):
   - Dispatch banner firing
   - "I built this in a weekend" developer story clips
   - "How to install Dispatch in 60 seconds"
3. OC drafts captions + hashtag sets → stages for approval
4. You record/upload the video clips (TikTok API video upload is available for approved apps)
5. Register TikTok Developer app for caption/upload automation

**Content cadence:** 1x/week at minimum. Higher frequency if clips are easy to produce.

**Success criteria:** First TikTok caption + hashtags staged by OC. Account created.
**Status:** [ ]

---

### Step 4.8 — YouTube
**Who:** You + Claude Code
**What:**
1. Create "Dispatch AI" YouTube channel
2. Content: longer-form demos (2-5 min), "how it works" explainers, "Claude Code plugin deep dives"
3. OC drafts titles, descriptions, tags → stages for approval
4. You record and upload videos (YouTube Data API v3 for description/metadata automation)
5. First video: the Loom demo expanded into a proper YouTube tutorial

**Content cadence:** 1x/2-3 weeks. Quality over quantity.

**Success criteria:** Channel created, OC connected for metadata drafting.
**Status:** [ ]

---

### Step 4.9 — GitHub Monitoring
**Who:** Claude Code configures
**What:** Connect OC to Dispatch repo (VisionAIrySE/Dispatch) via GitHub skill:
- Read-only PAT scope: `public_repo` read + `issues` read
- OC monitors: new issues, new stars, PRs, mentions
- Star milestones → draft celebration post for Twitter + LinkedIn → stage for approval
- New issues → OC drafts triage response → stages for 24h auto-publish

**Success criteria:** OC picks up a test issue, draft appears in staging channel.
**Status:** [ ]

---

## PHASE 5 — Dispatch Content Library (OC Configuration)

### Step 5.1 — Vet and Install ClawHub Skills
**Who:** Claude Code reviews, you install
**What:** For each skill, verify: 200+ GitHub stars, active commits in last 90 days, no open security issues.

Approved list to evaluate:
- `social-media-scheduler` — cross-platform post scheduling
- `github-notifier` — repo monitoring and alerts
- `slack-broadcaster` — cross-post to Slack channels
- `content-drafter` — AI-assisted post drafting with templates
- `rss-monitor` — RSS feed monitoring with keyword filtering
- `web-watcher` — competitor/site monitoring

**Do not install** skills without verifying the above criteria.

**Success criteria:** Only vetted skills installed, all confirmed functional.
**Status:** [ ]

---

### Step 5.2 — Build Dispatch Content Templates
**Who:** Claude Code drafts, you review
**What:** Create `/home/ocuser/templates/dispatch/` with:
- `launch-post.md` — the main announcement (tailored per platform)
- `milestone-post.md` — star count milestones
- `reply-opportunity.md` — template for replying to relevant threads
- `demo-caption.md` — TikTok/YouTube caption templates
- `weekly-tip.md` — "tip of the week" format

**Success criteria:** Templates in place, OC can reference them for drafting.
**Status:** [ ]

---

### Step 5.3 — Build Vib8 Content Templates
**Who:** Claude Code drafts, you review
**What:** Same structure at `/home/ocuser/templates/vib8/`
Reference Vib8 marketing research in `/home/visionairy/vib8-debug/` for angle and positioning.

**Success criteria:** Templates ready, Vib8 angle clearly differentiated from Dispatch angle.
**Status:** [ ]

---

### Step 5.4 — End-to-End Approval Gateway Test
**Who:** You + Claude Code observing
**What:** Trigger a full test run:
1. OC drafts a test Dispatch post using templates
2. Post appears in `#dispatch-staging`
3. You react ✅
4. OC publishes to `@DispatchAI` Twitter (test/staging mode if possible)
5. Verify the post content matches what was approved

**Success criteria:** Full approval loop works without manual intervention after your ✅.
**Status:** [ ]

---

## PHASE 6 — Dispatch ClawHub Skill

### Step 6.1 — Write the Skill
**Who:** Claude Code writes, you review
**What:** Create `dispatch-router.skill/` directory with:
- `SKILL.md` — name, description, version, author, license, install instructions
- `dispatch-wrapper.sh` — thin wrapper that calls dispatch.visionairy.biz API
- `README.md` — BYOK and hosted mode setup, why to install, what it does

**Positioning:** "The skill that surfaces other skills." Lead with BYOK option (zero risk).
Cross-link to GitHub repo and dispatch.visionairy.biz.

**Success criteria:** Skill runs cleanly in a test OC environment.
**Status:** [ ]

---

### Step 6.2 — Publish to ClawHub
**Who:** You
**What:** Follow ClawHub submission process (SKILL.md + GitHub repo).
Register as `VisionAIrySE/dispatch-router`.

**Success criteria:** Skill appears in ClawHub search for "dispatch" and "claude code".
**Status:** [ ]

---

## PHASE 7 — skills.sh Listing

### Step 7.1 — Submit to skills.sh
**Who:** You + Claude Code drafts submission
**What:** Submit Dispatch to skills.sh registry so install command becomes:
```bash
npx skills add visionairy/dispatch
```
Follow skills.sh contributor documentation for submission process.

**Success criteria:** `npx skills find dispatch` returns Dispatch in results.
**Status:** [ ]

---

## PHASE 8 — Directory Listings (One-Time, Passive Traffic)

### Step 8.1 — Submit to AI Directories
**Who:** OC drafts submissions, you review and submit
**What:** Submit to each directory with OC-drafted description tailored to each:

| Directory | URL | Type |
|-----------|-----|------|
| Futurepedia | futurepedia.io | Free listing |
| There's An AI For That | theresanaiforthat.com | Free submission |
| Toolify.ai | toolify.ai | Free listing |
| AlternativeTo | alternativeto.net | List as alt to SummonAI |
| Product Hunt | producthunt.com | Launch — time carefully, line up upvotes first |

**Success criteria:** Submitted to all 5. Product Hunt launch scheduled (not yet live — gate on star count).
**Status:** [ ]

---

### Step 8.2 — Newsletter Submissions
**Who:** OC drafts pitch, you send
**What:**
| Newsletter | Contact | Reach |
|-----------|---------|-------|
| Ben's Bites | bensbites.com/submit | 100k+ AI devs |
| TLDR AI | tldr.tech/ai | Large AI audience |
| The Rundown AI | therundown.ai | Growing AI newsletter |

**Success criteria:** Submissions sent, OC tracking for responses.
**Status:** [ ]

---

## PHASE 9 — Launch Week Execution

### Step 9.1 — Confirm Launch Readiness Checklist
**Who:** Both
**Before launching, verify:**
- [ ] Loom GIF ready and hosted
- [ ] UI polish live on dispatch.visionairy.biz
- [ ] README has GIF and badges
- [ ] ClawHub skill published
- [ ] skills.sh listing live
- [ ] All OC channels configured and approval gateway tested
- [ ] Content templates reviewed and approved
- [ ] Reddit account aged (at least 1 week old)

**Do not proceed to Step 9.2 until all boxes checked.**
**Status:** [ ]

---

### Step 9.2 — Launch Day: Community Posts
**Who:** OC queues, you ✅ each before publishing
**Order:**
1. r/ClaudeAI — lead post with GIF (highest ROI, do first)
2. Anthropic Discord (#claude-code or #community)
3. r/ChatGPTCoding — same post adapted
4. r/programming — technical angle
5. r/SideProject — builder angle
6. Twitter/X — GIF + one-liner, tag @AnthropicAI
7. LinkedIn — builder narrative post
8. Dev.to — full blog post "I built a task-shift detector for Claude Code"
9. IndieHackers — product page + milestone post

**Success criteria:** All posts live within 48 hours of launch start.
**Status:** [ ]

---

### Step 9.3 — Direct Outreach
**Who:** OC identifies targets, you send
**What:**
- OC monitors Twitter/X for developers posting about Claude Code plugins
- OC drafts 10-15 personalized DMs: "built something you might find useful" + Loom link — no ask
- You review and send from personal account

**Success criteria:** 10+ DMs sent within launch week.
**Status:** [ ]

---

### Step 9.4 — Monitor and Respond
**Who:** OC monitors, you respond with OC drafts
**What:** OC watches all platforms for:
- Replies/comments on launch posts
- New GitHub issues or stars
- Mentions of Dispatch anywhere online
- Reply opportunities in monitored subreddits

OC drafts responses → stages for approval → you ✅ → OC posts (or you post for platforms without API access).

**Success criteria:** No unanswered comments after 24 hours during launch week.
**Status:** [ ]

---

## PHASE 10 — Post-Launch

### Step 10.1 — 300 Stars: Flip Stripe On
**Who:** You
**What:** When Dispatch hits 300 GitHub stars:
1. Send email to waitlist: "Pro is live, founding member rate"
2. OC posts star milestone celebration across all platforms
3. Verify Stripe webhook is live and handling subscriptions

**Status:** [ ]

---

### Step 10.2 — Ongoing OC Maintenance (Weekly)
**Who:** OC autonomous, you review weekly
**What:**
- OC posts 2x/week to Twitter, LinkedIn (Dispatch + Vib8 alternating)
- OC monitors RSS feeds daily, flags reply opportunities
- OC tracks GitHub star trajectory, flags milestone approaches
- You spend ~30 min/week reviewing staging channel and approving queued posts

**Status:** [ ] (ongoing)

---

## COORDINATION NOTES

### Claude Code Role (me)
- Write all code changes (dispatch.sh, app.py, SKILL.md, wrapper scripts)
- Draft all content templates (you review before OC uses them)
- Advise on each step before you execute
- Review OC skill vetting (stars, commit history, security)
- Troubleshoot any issues at each step

### Your Role
- Execute terminal commands on local machine and VPS
- Approve all staged content before it goes live
- Handle platform account creation (Twitter, LinkedIn, Reddit, TikTok, YouTube)
- Make final decisions on timing and messaging

### One Step at a Time Rule
Complete the current step. Confirm it worked. Then ask Claude Code for the next step.
Do not skip steps or run steps out of order — each step gates the next.

### Current Step
**Start here: Step 0.1 — Record the Loom Demo**
