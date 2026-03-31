#!/bin/bash
# =============================================================================
# Dispatch — Live E2E Test Script
#
# Interactive test guide for a real Claude Code session.
# Run this in one terminal. Keep a CC session open in another.
#
# Flow: this script sets up state → you paste prompts into CC →
#       press Enter here → script verifies the outcome.
#
# Usage: bash test_e2e_live.sh
# =============================================================================

set -uo pipefail

DISPATCH_DIR="$HOME/.claude/dispatch"
STATE_FILE="$DISPATCH_DIR/state.json"

PASS=0
FAIL=0
SKIP=0
FAILURES=()

pass()  { echo "  ✅ $1"; PASS=$((PASS+1)); return 0; }
fail()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); return 0; }
skip()  { echo "  ⏭  $1"; SKIP=$((SKIP+1)); return 0; }
info()  { echo "  ℹ  $1"; return 0; }
hr()    { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
step()  { echo ""; echo "  👉 $1"; }
prompt(){ printf "\n  Press Enter when done (or type 'skip' to skip): "; read -r _R; echo "$_R"; }
ask()   { printf "\n  $1 [y/n]: "; read -r _A; echo "$_A"; }

set_state() {
    python3 -c "
import json, os, tempfile, sys
state_file = '$STATE_FILE'
updates = json.loads(sys.argv[1])
try:
    d = json.load(open(state_file))
except:
    d = {}
d.update(updates)
dir_ = os.path.dirname(os.path.abspath(state_file))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(d, f)
os.rename(tmp, state_file)
" "$1"
}

read_state() {
    python3 -c "import json; d=json.load(open('$STATE_FILE')); v=d.get('$1'); print(v if v is not None else '')" 2>/dev/null || echo ""
}

# Load API key (same as hooks need)
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    _KEY=$(python3 -c "
import json
try:
    d = json.load(open('$HOME/Dispatch/.mcp.json'))
    print(d['mcpServers']['xpansion']['env']['ANTHROPIC_API_KEY'])
except:
    print('')
" 2>/dev/null || echo "")
    [ -n "$_KEY" ] && export ANTHROPIC_API_KEY="$_KEY"
fi

# ── Banner ────────────────────────────────────────────────────────────────────
clear
hr
echo " Dispatch — Live E2E Test"
echo " Keep a fresh Claude Code session open in another window."
echo " This script tells you what to do. You verify in CC. It checks results."
hr
echo ""
echo " Your installed stack (what Dispatch knows about you):"
echo "   Skills:   supabase-postgres-best-practices"
echo "   Plugins:  frontend-design, superpowers, code-review, supabase,"
echo "             playwright, skill-creator, hookify, feature-dev,"
echo "             ultrathink, create-worktrees, flutter-mobile-app-dev,"
echo "             sugar, mcp-expert, debug-session, n8n-workflow-builder"
echo "   MCPs:     xpansion"
echo ""
printf "  Ready to start? Press Enter: "; read -r _

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1 — First-run welcome message
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 1 — First-run welcome message"
echo "  Dispatch should confirm it's active on your first message."
echo ""

set_state '{"first_run": true, "last_task_type": null, "last_category": null, "last_recommended_category": "", "limit_cooldown": 0}'
info "State reset. first_run=true"

step "START A FRESH CC SESSION (or /clear in existing one)"
step "Paste this prompt:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ What is 2 + 2?                                                  │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
info "Expected: Claude's response should include a note that Dispatch is active."
info "Look for: '[Dispatch is active...]' somewhere in the response."

_R=$(prompt)
if [ "$_R" = "skip" ]; then
    skip "T1: First-run welcome (skipped)"
else
    _A=$(ask "Did you see 'Dispatch is active' in Claude's response?")
    if [[ "$_A" =~ ^[Yy] ]]; then
        pass "T1: First-run welcome message displayed"
        FIRST_RUN=$(read_state first_run)
        if [ "$FIRST_RUN" = "False" ] || [ "$FIRST_RUN" = "false" ]; then
            pass "T1: first_run flag cleared in state.json"
        else
            fail "T1: first_run not cleared (value: '$FIRST_RUN')"
        fi
    else
        fail "T1: First-run welcome not seen"
        info "Check: is dispatch.sh registered? Run: python3 -c \"import json; s=json.load(open('$HOME/.claude/settings.json')); print(s.get('hooks',{}).get('UserPromptSubmit'))\""
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2 — Stage 3: Proactive recommendations (domain shift)
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 2 — Stage 3: Proactive recommendations on task shift"
echo "  Dispatch should inject tool recommendations when you shift to a new domain."
echo ""

set_state '{"last_task_type": "python-debugging", "last_category": "debugging", "last_recommended_category": "", "limit_cooldown": 0}'
info "State set: prior task = python-debugging. Shifting to GitHub Actions CI/CD."

step "In your CC session, paste this prompt:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ I need to set up a complete GitHub Actions CI/CD pipeline for   │"
echo "  │ my Node.js app. It should run tests on every PR, deploy to      │"
echo "  │ staging on merge to main, and deploy to production on version   │"
echo "  │ tags. Include environment secrets and rollback capability.       │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
info "Expected: BEFORE Claude responds, you should see a [Dispatch] block like:"
info "  [Dispatch] Recommended tools for this cicd-building task:"
info "  Plugins:"
info "    • ..."
info "  Skills:"
info "    • ..."
info "  Not sure which to pick? Ask me..."

_R=$(prompt)
if [ "$_R" = "skip" ]; then
    skip "T2: Stage 3 proactive (skipped)"
else
    _A=$(ask "Did you see a [Dispatch] recommendation block before Claude's response?")
    if [[ "$_A" =~ ^[Yy] ]]; then
        pass "T2: Stage 3 proactive recommendations fired"
        TASK=$(read_state last_task_type)
        CAT=$(read_state last_category)
        REC=$(read_state last_recommended_category)
        info "State written: task_type='$TASK' category='$CAT' last_recommended='$REC'"
        [ -n "$TASK" ] && [ "$TASK" != "None" ] && pass "T2: last_task_type written" || fail "T2: last_task_type not written"
        [ -n "$REC"  ] && [ "$REC"  != "None" ] && pass "T2: last_recommended_category written" || fail "T2: last_recommended_category not written"
    else
        fail "T2: Stage 3 proactive did not fire"
        TASK=$(read_state last_task_type)
        info "Diagnosis: last_task_type='$TASK'. If empty, shift was not detected."
        info "Try a longer, more specific prompt. Classifier needs >= 3 meaningful words."
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3 — Once-per-category gate (same domain second message)
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 3 — Once-per-category gate"
echo "  Dispatch should NOT fire Stage 3 again for the same category in same session."
echo ""

LAST_REC=$(read_state last_recommended_category)
if [ -z "$LAST_REC" ] || [ "$LAST_REC" = "None" ]; then
    skip "T3: Once-per-category gate (skipped — T2 must pass first)"
else
    info "last_recommended_category='$LAST_REC' — gate is set."
    step "In CC, paste this follow-up (same CI/CD domain):"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │ Now add a step to the pipeline that runs security scanning      │"
    echo "  │ with Snyk and posts results as a PR comment via the GitHub API. │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    info "Expected: NO [Dispatch] block this time. Claude responds directly."

    _R=$(prompt)
    if [ "$_R" = "skip" ]; then
        skip "T3: Once-per-category gate (skipped)"
    else
        _A=$(ask "Was there NO [Dispatch] block this time?")
        if [[ "$_A" =~ ^[Yy] ]]; then
            pass "T3: Once-per-category gate correctly suppressed Stage 3"
        else
            fail "T3: Stage 3 fired twice for same category (gate broken)"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4 — Stage 3 fires again for a NEW category
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 4 — Stage 3 fires for a different category"
echo "  Shift to Flutter/mobile — should trigger a fresh recommendation set."
echo ""

step "In CC, paste this prompt (completely different domain):"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ Switch gears completely. I need to build a Flutter mobile app   │"
echo "  │ with a Firebase backend. It needs Auth, Firestore database,     │"
echo "  │ push notifications, and offline sync. Start with the project    │"
echo "  │ structure and navigation using GoRouter and Riverpod.           │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
info "Expected: A NEW [Dispatch] block for mobile/Flutter tools."
info "Should be different tools from the CI/CD recommendations."

_R=$(prompt)
if [ "$_R" = "skip" ]; then
    skip "T4: Stage 3 new category (skipped)"
else
    _A=$(ask "Did you see a NEW [Dispatch] block with different (mobile/Flutter) tools?")
    if [[ "$_A" =~ ^[Yy] ]]; then
        pass "T4: Stage 3 fired for new category with relevant tools"
        NEW_CAT=$(read_state last_recommended_category)
        PREV_CAT="$LAST_REC"
        if [ "$NEW_CAT" != "$PREV_CAT" ]; then
            pass "T4: Different category written ('$NEW_CAT' vs previous '$PREV_CAT')"
        else
            fail "T4: Category unchanged — same category written for different domain"
        fi
    else
        fail "T4: Stage 3 did not fire for new domain"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5 — PreToolUse: non-intercepted tool passes silently
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 5 — PreToolUse: file operations pass through silently"
echo "  Dispatch should NOT interfere with Read, Write, Edit, Bash, etc."
echo ""

step "In CC, ask Claude to read a file:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ Read the file /home/visionairy/Dispatch/README.md and give me   │"
echo "  │ a one-sentence summary.                                         │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
info "Expected: Claude reads the file and responds. NO Dispatch interference."
info "Claude should NOT be blocked or shown alternatives for a Read operation."

_R=$(prompt)
if [ "$_R" = "skip" ]; then
    skip "T5: Non-intercepted tool pass-through (skipped)"
else
    _A=$(ask "Did Claude read the file without any Dispatch block or warning?")
    if [[ "$_A" =~ ^[Yy] ]]; then
        pass "T5: Non-intercepted tool passes through silently"
    else
        fail "T5: Dispatch incorrectly intercepted a file operation"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 6 — PreToolUse: Skill intercept with a block
# Set up state for a category where we know a block occurs reliably
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 6 — PreToolUse: Dispatch intercepts a Skill call and blocks"
echo "  Ask Claude to use code-review skill for a PR review (reliable block scenario)."
echo ""

set_state '{
    "last_task_type": "pr-reviewing",
    "last_category": "source-control",
    "last_context_snippet": "reviewing a pull request with breaking changes to the auth flow"
}'
info "State primed: category=source-control, task=pr-reviewing"

step "In CC, paste this prompt exactly:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ Use the code-review skill to review this TypeScript function:   │"
echo "  │                                                                 │"
echo "  │ async function getUser(id: string) {                            │"
echo "  │   const res = await fetch('/api/users/' + id);                  │"
echo "  │   return res.json();                                            │"
echo "  │ }                                                               │"
echo "  │                                                                 │"
echo "  │ Look for security issues and missing error handling.            │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
info "Expected: Dispatch intercepts the Skill tool call."
info "You should see a block message like:"
info "  ◎ Dispatch — Better option found for pr-reviewing"
info "  ..."
info "  Say 'proceed' to continue with code-review anyway."
echo ""
info "NOTE: If Claude handles this without using the Skill tool, re-phrase as:"
info "  '/code-review ... the function above'"

_R=$(prompt)
if [ "$_R" = "skip" ]; then
    skip "T6: PreToolUse block (skipped)"
else
    _A=$(ask "Did you see a Dispatch block message with a better tool recommendation?")
    if [[ "$_A" =~ ^[Yy] ]]; then
        pass "T6: Dispatch blocked the Skill call with a recommendation"
        BYPASS=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('bypass',{}).get('tool_name',''))" 2>/dev/null)
        [ -n "$BYPASS" ] && pass "T6: Bypass token written (tool_name='$BYPASS')" || fail "T6: Bypass token not written after block"
        SUGGESTED=$(read_state last_suggested)
        [ -n "$SUGGESTED" ] && pass "T6: last_suggested written ('$SUGGESTED')" || fail "T6: last_suggested not written"
    else
        _A2=$(ask "Did Dispatch pass through (no block)?")
        if [[ "$_A2" =~ ^[Yy] ]]; then
            info "T6: No block — Dispatch judged code-review as competitive for this context."
            skip "T6: No block triggered (CC tool scored competitively)"
        else
            fail "T6: Unexpected behavior"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 7 — Bypass: user says "proceed" and Dispatch allows
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 7 — Bypass: say 'proceed' to override the block"
echo ""

BYPASS_TOOL=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('bypass',{}).get('tool_name',''))" 2>/dev/null)
if [ -z "$BYPASS_TOOL" ]; then
    skip "T7: Bypass flow (skipped — T6 must produce a block first)"
else
    info "Bypass token present for tool: '$BYPASS_TOOL'"
    step "In CC, type exactly:"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │ proceed                                                         │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    info "Expected: Claude retries the tool call. Dispatch passes it through."
    info "You should see Claude using the skill WITHOUT another block message."

    _R=$(prompt)
    if [ "$_R" = "skip" ]; then
        skip "T7: Bypass (skipped)"
    else
        _A=$(ask "Did Claude proceed with the skill call without being blocked again?")
        if [[ "$_A" =~ ^[Yy] ]]; then
            pass "T7: Bypass allowed the tool call through"
            BYPASS_AFTER=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('bypass',{}).get('tool_name',''))" 2>/dev/null)
            [ -z "$BYPASS_AFTER" ] && pass "T7: Bypass token consumed (single-use confirmed)" || fail "T7: Bypass token not consumed"
        else
            fail "T7: Bypass did not work — tool was blocked again or Claude did not retry"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 8 — Conversion tracking: use a tool Dispatch previously recommended
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 8 — Conversion tracking: use a tool Dispatch recommended"
echo ""

LAST_SUGGESTED=$(read_state last_suggested)
if [ -z "$LAST_SUGGESTED" ] || [ "$LAST_SUGGESTED" = "None" ]; then
    skip "T8: Conversion tracking (skipped — no last_suggested from T6)"
else
    info "last_suggested = '$LAST_SUGGESTED'"
    info "If this is an installed plugin, ask Claude to use it."
    step "In CC, ask Claude to use the suggested tool. For example:"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │ Actually, use the $LAST_SUGGESTED skill instead.               │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    info "Expected: Dispatch detects that CC is now using the tool it suggested."
    info "This logs a 'was_installed' conversion event on the server."

    _R=$(prompt)
    if [ "$_R" = "skip" ]; then
        skip "T8: Conversion tracking (skipped)"
    else
        _A=$(ask "Did Claude use the suggested tool without a block?")
        if [[ "$_A" =~ ^[Yy] ]]; then
            pass "T8: Suggested tool used — conversion event should have logged"
            info "Verify in server logs: curl dispatch.visionairy.biz/admin/dashboard"
        else
            skip "T8: Couldn't confirm conversion (tool may not be installed)"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 9 — MCP intercept: xpansion tool call
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 9 — PreToolUse: MCP tool intercept (xpansion)"
echo ""

set_state '{
    "last_task_type": "system-analyzing",
    "last_category": "ai-ml",
    "last_context_snippet": "analyzing system architecture with MECE decomposition"
}'
info "State primed: category=ai-ml, task=system-analyzing"

step "In CC, invoke xpansion directly:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ Use the xpansion MCP to analyze this problem: I need to design  │"
echo "  │ a revenue model for a developer tool SaaS with a free tier.     │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
info "Expected: Either pass through (xpansion is competitive) OR"
info "          blocked with a better MCP recommendation for AI/ML tasks."

_R=$(prompt)
if [ "$_R" = "skip" ]; then
    skip "T9: MCP intercept (skipped)"
else
    _A=$(ask "Did xpansion run without a block?")
    if [[ "$_A" =~ ^[Yy] ]]; then
        pass "T9: MCP tool passed through — xpansion rated competitive"
    else
        _A2=$(ask "Did Dispatch block with a better MCP recommendation?")
        if [[ "$_A2" =~ ^[Yy] ]]; then
            pass "T9: MCP tool intercepted with better recommendation"
        else
            fail "T9: Unexpected behavior on MCP tool call"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 10 — Daily limit (quota) — simulate 402 display
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 10 — Free tier quota message"
echo "  Simulate the 402 limit display by setting limit_cooldown=0 and"
echo "  a fake 'already at limit' state. This tests the UI, not actual quota."
echo ""

# We can't force a 402 without exhausting real quota, so we test the UI
# by checking the upgrade message in dispatch.sh (look for hardcoded text)
LIMIT_MSG=$(grep -o "8 free detections today" "$HOME/.claude/hooks/dispatch.sh" 2>/dev/null || echo "")
if [ -n "$LIMIT_MSG" ]; then
    pass "T10: Limit message text present in hook ('8 free detections today')"
    UPGRADE_URL=$(grep -o "dispatch.visionairy.biz/pro" "$HOME/.claude/hooks/dispatch.sh" 2>/dev/null || echo "")
    [ -n "$UPGRADE_URL" ] && pass "T10: Upgrade URL present in limit message" || fail "T10: Upgrade URL missing from limit message"
else
    fail "T10: Limit message text not found in dispatch.sh"
fi
info "Actual 402 display requires hitting the free tier limit — test manually if needed."

# ─────────────────────────────────────────────────────────────────────────────
# TEST 11 — /dispatch status skill
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 11 — /dispatch status command"
echo ""

SKILL_FILE="$HOME/.claude/skills/dispatch-status/SKILL.md"
if [ -f "$SKILL_FILE" ]; then
    pass "T11: dispatch-status skill installed"
    step "In CC, type:"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │ /dispatch status                                                │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    info "Expected: Claude shows your current Dispatch state — plan, usage, token."

    _R=$(prompt)
    if [ "$_R" = "skip" ]; then
        skip "T11: /dispatch status (skipped)"
    else
        _A=$(ask "Did /dispatch status show your plan/usage info?")
        if [[ "$_A" =~ ^[Yy] ]]; then
            pass "T11: /dispatch status works"
        else
            fail "T11: /dispatch status did not return expected output"
        fi
    fi
else
    fail "T11: dispatch-status skill not installed at $SKILL_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 12 — State survives session (persistence check)
# ─────────────────────────────────────────────────────────────────────────────
hr
echo ""
echo "  TEST 12 — State persistence across messages"
echo ""

TASK=$(read_state last_task_type)
CAT=$(read_state last_category)
info "Current state: task='$TASK' category='$CAT'"

if [ -n "$TASK" ] && [ "$TASK" != "None" ]; then
    pass "T12: State persists — last_task_type='$TASK' still set from earlier tests"
    python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null \
        && pass "T12: state.json is valid JSON after full session" \
        || fail "T12: state.json corrupted after session"
else
    fail "T12: State not persisted — last_task_type empty"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Final results
# ─────────────────────────────────────────────────────────────────────────────
hr
TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo " E2E Results: $PASS passed, $FAIL failed, $SKIP skipped, $TOTAL total"
hr

if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo ""
    echo " Failed tests:"
    for f in "${FAILURES[@]}"; do echo "   • $f"; done
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo " ✅ All executed tests passed. Dispatch is working end-to-end."
else
    echo " ❌ $FAIL test(s) failed. Review failures above before launch."
fi
echo ""

# Restore state to a clean post-test condition
set_state '{"last_task_type": null, "last_category": null, "last_recommended_category": "", "first_run": false, "limit_cooldown": 0}' 2>/dev/null || true
echo " State restored to clean post-test condition."
echo ""
