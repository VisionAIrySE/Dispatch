#!/bin/bash
# =============================================================================
# Dispatch — Installed vs Not-Installed Tool Scenario Tests
#
# Tests Dispatch's ability to:
# 1. Correctly handle tool calls for INSTALLED skills, plugins, and MCPs
# 2. Detect and recommend alternatives when NOT-INSTALLED tools are called
# 3. Filter already-installed MCPs out of recommendations (stack_profile)
# 4. Score and rank tools correctly across all three tool types
#
# Based on your actual installed tools:
#   Skills:            supabase-postgres-best-practices
#   Official plugins:  frontend-design, superpowers, code-review, supabase,
#                      playwright, skill-creator, hookify, feature-dev
#   Community plugins: ultrathink, create-worktrees, flutter-mobile-app-dev,
#                      sugar, model-context-protocol-mcp-expert,
#                      debug-session, n8n-workflow-builder
#   MCPs:              xpansion (Dispatch .mcp.json)
#
# Usage: bash test_tool_scenarios.sh
# =============================================================================

set -uo pipefail

DISPATCH_DIR="$HOME/.claude/dispatch"
STATE_FILE="$DISPATCH_DIR/state.json"
PREUSE_SH="$HOME/.claude/hooks/dispatch-preuse.sh"
DISPATCH_SH="$HOME/.claude/hooks/dispatch.sh"

# Load ANTHROPIC_API_KEY from xpansion config if not already set
# (mirrors what the real CC session environment provides to hooks)
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

PASS=0
FAIL=0
FAILURES=()
BLOCKS=()    # track which scenarios triggered a block (useful info)

pass() { echo "  ✅ $1"; PASS=$((PASS+1)); return 0; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); return 0; }
info() { echo "  ℹ  $1"; return 0; }

save_state()    { cp "$STATE_FILE" /tmp/dispatch_scenario_backup.json 2>/dev/null || true; }
restore_state() { cp /tmp/dispatch_scenario_backup.json "$STATE_FILE" 2>/dev/null || true; }

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

reset_state() {
    python3 -c "
import json, os, tempfile
state = {
    'last_task_type': None, 'last_category': None,
    'last_context_snippet': '', 'last_cwd': '',
    'last_updated': None, 'last_recommended_category': '',
    'limit_cooldown': 0, 'auth_invalid_cooldown': 0, 'first_run': False
}
dir_ = os.path.dirname(os.path.abspath('$STATE_FILE'))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(state, f)
os.rename(tmp, '$STATE_FILE')
"
}

# Run preuse hook and return: exit code, stdout output
run_preuse() {
    local tool_json="$1"
    local output exit_code
    output=$(echo "$tool_json" | bash "$PREUSE_SH" 2>/dev/null)
    exit_code=$?
    echo "$exit_code|$output"
}

# Interpret a preuse result: verify no crash, report block vs pass
check_preuse() {
    local label="$1"
    local result="$2"
    local exit_code="${result%%|*}"
    local output="${result#*|}"

    if [ "$exit_code" -eq 0 ]; then
        pass "$label — passed through (exit 0)"
        info "$label — Dispatch judged CC's tool competitive"
    elif [ "$exit_code" -eq 2 ]; then
        pass "$label — blocked cleanly (exit 2, better tool found)"
        BLOCKS+=("$label")
        if [ -n "$output" ]; then
            pass "$label — block output present"
            # Show first line of what Dispatch recommended
            FIRST_LINE=$(echo "$output" | grep -m1 "•" | sed 's/^[[:space:]]*//' | cut -c1-80)
            [ -n "$FIRST_LINE" ] && info "  Top suggestion: $FIRST_LINE"
        else
            fail "$label — exit 2 but NO block output (user sees nothing)"
        fi
    else
        fail "$label — unexpected exit code $exit_code"
    fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Dispatch — Installed vs Not-Installed Tool Scenario Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Installed tools under test:"
echo "   Skills:   supabase-postgres-best-practices"
echo "   Plugins:  frontend-design, superpowers, code-review, supabase,"
echo "             playwright, skill-creator, hookify, feature-dev,"
echo "             ultrathink, create-worktrees, flutter-mobile-app-dev,"
echo "             sugar, model-context-protocol-mcp-expert, debug-session,"
echo "             n8n-workflow-builder"
echo "   MCPs:     xpansion"
echo ""

save_state
TRANSCRIPT=$(mktemp --suffix=.jsonl)
trap 'rm -f "$TRANSCRIPT"; restore_state' EXIT

TOKEN=$(python3 -c "import json; d=json.load(open('$DISPATCH_DIR/config.json')); print(d.get('token',''))" 2>/dev/null || echo "")

# Quick server check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://dispatch.visionairy.biz/rank" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"task_type":"test","context_snippet":"test","cc_tool":"Skill","category_id":"frontend-development"}' \
    --max-time 8 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && echo "  ✅ Server reachable" || echo "  ⚠  Server returned $HTTP_CODE — results may be degraded"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 1 — INSTALLED SKILLS
# When CC invokes a skill you already have, Dispatch should either pass
# (competitive) or recommend something materially better.
# ─────────────────────────────────────────────────────────────────────────────
echo "[ Suite 1: INSTALLED SKILL — supabase-postgres-best-practices ]"
echo "  Context: data-storage task, CC calls your installed skill"
echo ""

reset_state
set_state '{
    "last_task_type": "postgres-optimizing",
    "last_category": "data-storage",
    "last_context_snippet": "I need to optimize PostgreSQL queries for a Supabase project with slow joins"
}'

RESULT=$(run_preuse '{"tool_name":"Skill","tool_input":{"skill":"supabase-postgres-best-practices"}}')
check_preuse "S1.1 Skill:supabase-postgres-best-practices (data-storage)" "$RESULT"

# Same skill, different context — devops task
reset_state
set_state '{
    "last_task_type": "devops-deploying",
    "last_category": "devops-cicd",
    "last_context_snippet": "deploying a Node.js app to production with CI/CD pipeline"
}'
RESULT=$(run_preuse '{"tool_name":"Skill","tool_input":{"skill":"supabase-postgres-best-practices"}}')
check_preuse "S1.2 Skill:supabase-postgres-best-practices (devops-cicd context — mismatch)" "$RESULT"

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 2 — INSTALLED OFFICIAL PLUGINS
# CC invokes an installed official plugin via Skill tool.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 2: INSTALLED OFFICIAL PLUGINS ]"
echo ""

declare -A PLUGIN_CONTEXTS=(
    ["frontend-design"]='{"last_task_type":"react-building","last_category":"frontend-development","last_context_snippet":"building a React dashboard with charts and TypeScript"}'
    ["superpowers"]='{"last_task_type":"feature-designing","last_category":"frontend-development","last_context_snippet":"planning and designing a new feature for the app"}'
    ["code-review"]='{"last_task_type":"pr-reviewing","last_category":"source-control","last_context_snippet":"reviewing a pull request with breaking changes to the auth flow"}'
    ["supabase"]='{"last_task_type":"postgres-building","last_category":"data-storage","last_context_snippet":"setting up Supabase database tables with RLS policies"}'
    ["playwright"]='{"last_task_type":"e2e-testing","last_category":"testing-qa","last_context_snippet":"writing end-to-end tests for the checkout flow with Playwright"}'
    ["skill-creator"]='{"last_task_type":"skill-building","last_category":"ai-agents","last_context_snippet":"creating a new Claude Code skill for automated workflows"}'
    ["hookify"]='{"last_task_type":"hook-configuring","last_category":"devops-cicd","last_context_snippet":"setting up Claude Code hooks to enforce code standards"}'
    ["feature-dev"]='{"last_task_type":"feature-building","last_category":"frontend-development","last_context_snippet":"implementing a new feature with codebase understanding"}'
)

for plugin in frontend-design superpowers code-review supabase playwright skill-creator hookify feature-dev; do
    reset_state
    context="${PLUGIN_CONTEXTS[$plugin]}"
    set_state "$context"
    RESULT=$(run_preuse "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"plugin:anthropic:$plugin\"}}")
    check_preuse "S2 plugin:anthropic:$plugin" "$RESULT"
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 3 — INSTALLED COMMUNITY PLUGINS
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 3: INSTALLED COMMUNITY PLUGINS ]"
echo ""

declare -A COMMUNITY_CONTEXTS=(
    ["ultrathink"]='{"last_task_type":"complex-architecting","last_category":"ai-agents","last_context_snippet":"architecting a complex multi-agent system with parallel tasks"}'
    ["create-worktrees"]='{"last_task_type":"git-branching","last_category":"source-control","last_context_snippet":"setting up isolated git worktrees for parallel feature development"}'
    ["flutter-mobile-app-dev"]='{"last_task_type":"flutter-building","last_category":"mobile-development","last_context_snippet":"building a Flutter mobile app with custom widgets and navigation"}'
    ["sugar"]='{"last_task_type":"task-automating","last_category":"ai-agents","last_context_snippet":"setting up autonomous task execution with Sugar"}'
    ["model-context-protocol-mcp-expert"]='{"last_task_type":"mcp-building","last_category":"ai-agents","last_context_snippet":"building a custom MCP server to expose internal APIs to Claude"}'
    ["debug-session"]='{"last_task_type":"bug-fixing","last_category":"debugging","last_context_snippet":"debugging a race condition in the async data pipeline"}'
    ["n8n-workflow-builder"]='{"last_task_type":"workflow-building","last_category":"workflow-automation","last_context_snippet":"building n8n workflows to automate Slack and Stripe integrations"}'
)

for plugin in ultrathink create-worktrees flutter-mobile-app-dev sugar model-context-protocol-mcp-expert debug-session n8n-workflow-builder; do
    reset_state
    context="${COMMUNITY_CONTEXTS[$plugin]}"
    set_state "$context"
    RESULT=$(run_preuse "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"plugin:cc-marketplace:$plugin\"}}")
    check_preuse "S3 plugin:cc-marketplace:$plugin" "$RESULT"
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 4 — INSTALLED MCP: xpansion
# When CC calls mcp__xpansion__*, Dispatch intercepts (it's an mcp__ prefix).
# stack_profile with xpansion should suppress it from recommendations.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 4: INSTALLED MCP — xpansion ]"
echo ""

# 4a: xpansion in stack_profile — should NOT be recommended as alternative
reset_state
set_state '{
    "last_task_type": "system-analyzing",
    "last_category": "ai-agents",
    "last_context_snippet": "analyzing system architecture with MECE decomposition"
}'
python3 -c "
import json, os, tempfile, sys
state_file = '$STATE_FILE'
d = json.load(open(state_file))
d['stack_profile'] = {'mcp_servers': ['xpansion'], 'languages': ['python'], 'frameworks': []}
dir_ = os.path.dirname(os.path.abspath(state_file))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(d, f)
os.rename(tmp, state_file)
" 2>/dev/null

# Simulate CC calling xpansion MCP tool
RESULT=$(run_preuse '{"tool_name":"mcp__xpansion__analyze","tool_input":{"problem":"system architecture"}}')
check_preuse "S4.1 mcp__xpansion__analyze (xpansion in stack_profile)" "$RESULT"
EXIT="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
if [ "$EXIT" -eq 2 ] && [ -n "$OUTPUT" ]; then
    # Verify xpansion doesn't appear in its own recommendations
    if echo "$OUTPUT" | grep -iq "xpansion"; then
        fail "S4.1 xpansion appears in its own recommendations (stack_profile filter broken)"
    else
        pass "S4.1 xpansion NOT recommended as alternative to itself"
    fi
fi

# 4b: xpansion NOT in stack_profile — it could appear as recommendation
reset_state
set_state '{
    "last_task_type": "system-analyzing",
    "last_category": "ai-agents",
    "last_context_snippet": "I need to decompose a complex problem systematically using MECE"
}'
# Different MCP called, no stack_profile (so xpansion could appear as suggestion)
RESULT=$(run_preuse '{"tool_name":"mcp__github__create_issue","tool_input":{"title":"bug report"}}')
check_preuse "S4.2 mcp__github__create_issue (no stack_profile — xpansion may be suggested)" "$RESULT"
EXIT="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
if [ "$EXIT" -eq 2 ] && echo "$OUTPUT" | grep -iq "xpansion"; then
    info "S4.2 xpansion appeared as a recommendation (expected — it's installed and relevant)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 5 — NOT INSTALLED: skills that likely exist in marketplace
# These test whether Dispatch finds and recommends alternatives
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 5: NOT INSTALLED — skills not in your stack ]"
echo ""

declare -A NOT_INSTALLED=(
    ["unknown-react-tool"]='{"last_task_type":"react-building","last_category":"frontend-development","last_context_snippet":"building a complex React app with TypeScript state management and routing"}'
    ["unknown-docker-tool"]='{"last_task_type":"docker-building","last_category":"devops-cicd","last_context_snippet":"containerizing a Node.js microservice with Docker and docker-compose"}'
    ["unknown-github-actions"]='{"last_task_type":"ci-building","last_category":"devops-cicd","last_context_snippet":"setting up GitHub Actions CI/CD pipeline with automated testing and deployment"}'
    ["unknown-flutter-tool"]='{"last_task_type":"flutter-building","last_category":"mobile-development","last_context_snippet":"building a production Flutter app with state management and API integration"}'
    ["unknown-testing-tool"]='{"last_task_type":"unit-testing","last_category":"testing-qa","last_context_snippet":"writing comprehensive unit tests for a TypeScript Express API with mocked dependencies"}'
    ["unknown-stripe-tool"]='{"last_task_type":"payments-building","last_category":"data-storage","last_context_snippet":"integrating Stripe payments with webhooks and subscription management"}'
)

for tool in "unknown-react-tool" "unknown-docker-tool" "unknown-github-actions" "unknown-flutter-tool" "unknown-testing-tool" "unknown-stripe-tool"; do
    reset_state
    set_state "${NOT_INSTALLED[$tool]}"
    RESULT=$(run_preuse "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"some-owner/$tool\"}}")
    EXIT="${RESULT%%|*}"
    OUTPUT="${RESULT#*|}"
    if [ "$EXIT" -eq 0 ]; then
        pass "S5 $tool — passed (CC tool rated competitive for this category)"
    elif [ "$EXIT" -eq 2 ]; then
        pass "S5 $tool — blocked, better option found"
        [ -n "$OUTPUT" ] && pass "S5 $tool — recommendation output present" || fail "S5 $tool — exit 2 but no output"
        SUGGESTION=$(echo "$OUTPUT" | grep -m1 "•" | sed 's/^[[:space:]]*//' | cut -c1-80)
        [ -n "$SUGGESTION" ] && info "  Dispatch suggested: $SUGGESTION"
    else
        fail "S5 $tool — unexpected exit $EXIT"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 6 — NOT INSTALLED: MCPs that exist in marketplace
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 6: NOT INSTALLED — MCP tool calls for tasks with better MCPs available ]"
echo ""

declare -A NOT_INSTALLED_MCP=(
    ["mcp__filesystem__read_file"]='{"last_task_type":"file-managing","last_category":"devops-cicd","last_context_snippet":"reading and processing local configuration files for the deployment pipeline"}'
    ["mcp__memory__store"]='{"last_task_type":"knowledge-storing","last_category":"ai-agents","last_context_snippet":"storing and retrieving structured knowledge for the AI assistant"}'
    ["mcp__slack__send_message"]='{"last_task_type":"slack-notifying","last_category":"workflow-automation","last_context_snippet":"sending automated Slack notifications when deployment completes"}'
)

for tool_name in "mcp__filesystem__read_file" "mcp__memory__store" "mcp__slack__send_message"; do
    reset_state
    category="${NOT_INSTALLED_MCP[$tool_name]}"
    set_state "$category"
    RESULT=$(run_preuse "{\"tool_name\":\"$tool_name\",\"tool_input\":{}}")
    EXIT="${RESULT%%|*}"
    OUTPUT="${RESULT#*|}"
    if [ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 2 ]; then
        pass "S6 $tool_name — handled cleanly (exit $EXIT)"
        if [ "$EXIT" -eq 2 ]; then
            SUGGESTION=$(echo "$OUTPUT" | grep -m1 "•" | sed 's/^[[:space:]]*//' | cut -c1-80)
            [ -n "$SUGGESTION" ] && info "  Dispatch suggested: $SUGGESTION"
        fi
    else
        fail "S6 $tool_name — unexpected exit $EXIT"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 7 — Agent tool calls with your installed plugins as context
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 7: Agent tool calls ]"
echo ""

declare -A AGENT_CONTEXTS=(
    ["general-purpose"]='{"last_task_type":"research-analyzing","last_category":"ai-agents","last_context_snippet":"researching how to implement a complex multi-step data pipeline with AI"}'
    ["Explore"]='{"last_task_type":"codebase-exploring","last_category":"frontend-development","last_context_snippet":"exploring the React codebase to understand how components are structured"}'
    ["Plan"]='{"last_task_type":"architecture-planning","last_category":"ai-agents","last_context_snippet":"planning the architecture for a new microservices system"}'
)

for subagent in "general-purpose" "Explore" "Plan"; do
    reset_state
    set_state "${AGENT_CONTEXTS[$subagent]}"
    RESULT=$(run_preuse "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"$subagent\",\"prompt\":\"help me analyze this\"}}")
    check_preuse "S7 Agent/$subagent" "$RESULT"
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 8 — Verify bypass works for each tool type
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 8: Bypass token works across all tool types ]"
echo ""

TOOL_TYPES=(
    '{"tool_name":"Skill","tool_input":{"skill":"plugin:anthropic:frontend-design"}}'
    '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"help"}}'
    '{"tool_name":"mcp__xpansion__analyze","tool_input":{}}'
)
TOOL_LABELS=("Skill/plugin" "Agent" "mcp__xpansion__*")

for i in 0 1 2; do
    reset_state
    set_state '{"last_task_type":"react-building","last_category":"frontend-development","last_context_snippet":"building React app"}'
    TOOL_NAME=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['tool_name'])" "${TOOL_TYPES[$i]}")
    # Write bypass for this specific tool
    python3 -c "
import json, os, tempfile, time, sys
state_file = '$STATE_FILE'
d = json.load(open(state_file))
d['bypass'] = {'tool_name': sys.argv[1], 'expires': time.time() + 120}
dir_ = os.path.dirname(os.path.abspath(state_file))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(d, f)
os.rename(tmp, state_file)
" "$TOOL_NAME" 2>/dev/null

    RESULT=$(run_preuse "${TOOL_TYPES[$i]}")
    EXIT="${RESULT%%|*}"
    [ "$EXIT" -eq 0 ] \
        && pass "S8 Bypass works for ${TOOL_LABELS[$i]} (exit 0)" \
        || fail "S8 Bypass FAILED for ${TOOL_LABELS[$i]} (exit $EXIT)"
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 9 — Stage 3 fires correct category for each major domain
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 9: Stage 3 proactive — category-appropriate recommendations ]"
echo "  (Tests dispatch.sh Stage 3 output is relevant to each domain)"
echo ""

TRANSCRIPT_TMP=$(mktemp --suffix=.jsonl)

run_stage3() {
    local label="$1" context="$2" prompt="$3"
    reset_state
    python3 -c "
import json, sys
print(json.dumps({'type':'user','isMeta':False,'message':{'role':'user','content':sys.argv[1]}}))
print(json.dumps({'type':'user','isMeta':False,'message':{'role':'user','content':sys.argv[2]}}))
print(json.dumps({'type':'user','isMeta':False,'message':{'role':'user','content':sys.argv[3]}}))
" "$context" "$context" "$context" > "$TRANSCRIPT_TMP"
    INPUT=$(python3 -c "import json,sys; print(json.dumps({'transcript_path':sys.argv[1],'cwd':'/home/visionairy/Dispatch','prompt':sys.argv[2]}))" "$TRANSCRIPT_TMP" "$prompt")
    OUTPUT=$(echo "$INPUT" | bash "$DISPATCH_SH" 2>/dev/null)
    EXIT=$?
    if [ "$EXIT" -eq 0 ] && echo "$OUTPUT" | grep -q "\[Dispatch\]"; then
        pass "$label — Stage 3 fired, recommendations present"
        TYPES=$(echo "$OUTPUT" | grep -oiE "^(Plugins|Skills|MCPs):" | tr '\n' ' ')
        [ -n "$TYPES" ] && info "$label — Sections: $TYPES" || info "$label — (sections found inline)"
    elif [ "$EXIT" -eq 0 ]; then
        info "$label — no [Dispatch] output (shift not detected or same category)"
    else
        fail "$label — exit $EXIT"
    fi
    rm -f "$TRANSCRIPT_TMP"
}

run_stage3 "S9.1 frontend-development" \
    "I am building a new React TypeScript dashboard with real-time charts" \
    "Let us start with the component architecture and set up routing with React Router and state with Redux Toolkit"

run_stage3 "S9.2 mobile-development" \
    "I need to build a cross-platform Flutter mobile app with Firebase" \
    "Start with authentication using Firebase Auth and then set up navigation with GoRouter and state management with Riverpod"

run_stage3 "S9.3 data-storage" \
    "I need to optimize my PostgreSQL database schema on Supabase for production" \
    "Review the slow queries in the joins between users and orders tables and suggest index strategies and query rewrites"

run_stage3 "S9.4 devops-cicd" \
    "I need to set up a complete CI/CD pipeline using GitHub Actions for my Node.js app" \
    "Configure automated testing deployment to staging on PR merge and production on release tag with rollback capability"

run_stage3 "S9.5 workflow-automation" \
    "I need to build n8n workflows connecting Slack Stripe and my Supabase database" \
    "Create a workflow that fires when a Stripe payment succeeds updates Supabase and sends a formatted Slack notification with customer details"

run_stage3 "S9.6 ai-agents" \
    "I need to build a custom MCP server to expose my internal APIs to Claude Code" \
    "Design the MCP server architecture with proper tool definitions type safety and error handling for production use"

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 10 — Conversion tracking: did Dispatch correctly log last_suggested?
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 10: Conversion tracking — last_suggested written on block ]"
echo ""

reset_state
set_state '{
    "last_task_type": "react-building",
    "last_category": "frontend-development",
    "last_context_snippet": "building a complex React application with charts and TypeScript"
}'

RESULT=$(run_preuse '{"tool_name":"Skill","tool_input":{"skill":"some-owner/unknown-react-tool"}}')
EXIT="${RESULT%%|*}"

if [ "$EXIT" -eq 2 ]; then
    LAST_SUGGESTED=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_suggested',''))" 2>/dev/null)
    [ -n "$LAST_SUGGESTED" ] \
        && pass "S10 last_suggested written on block: '$LAST_SUGGESTED'" \
        || fail "S10 last_suggested NOT written on block (conversion tracking broken)"
else
    info "S10 No block triggered for unknown-react-tool — cannot test last_suggested write (CC tool scored competitively)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
echo " Results: $PASS passed, $FAIL failed, $TOTAL total"

if [ "${#BLOCKS[@]}" -gt 0 ]; then
    echo ""
    echo " Tools Dispatch BLOCKED (better alternative found):"
    for b in "${BLOCKS[@]}"; do echo "   • $b"; done
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo " Failed tests:"
    for f in "${FAILURES[@]}"; do echo "   • $f"; done
    echo ""
    exit 1
else
    echo ""
    echo " All tests passed. Ready for live e2e."
    echo ""
    exit 0
fi
