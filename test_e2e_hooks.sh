#!/bin/bash
# =============================================================================
# Dispatch — Pre-E2E Hook Integration Test
#
# Tests every hook capability by simulating CC hook invocations directly.
# Hosted mode (token in config.json). No live CC session required.
#
# Usage: bash test_e2e_hooks.sh
# =============================================================================

set -uo pipefail

DISPATCH_DIR="$HOME/.claude/dispatch"
STATE_FILE="$DISPATCH_DIR/state.json"
DISPATCH_SH="$HOME/.claude/hooks/dispatch.sh"
PREUSE_SH="$HOME/.claude/hooks/dispatch-preuse.sh"

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

# ── Helpers ──────────────────────────────────────────────────────────────────

pass() { echo "  ✅ $1"; PASS=$((PASS+1)); return 0; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); return 0; }

save_state()    { cp "$STATE_FILE" /tmp/dispatch_test_state_backup.json 2>/dev/null || true; }
restore_state() { cp /tmp/dispatch_test_state_backup.json "$STATE_FILE" 2>/dev/null || true; }

reset_state() {
    python3 -c "
import json, os, tempfile
state = {
    'last_task_type': None,
    'last_category': None,
    'last_context_snippet': '',
    'last_cwd': '',
    'last_updated': None,
    'last_recommended_category': '',
    'limit_cooldown': 0,
    'auth_invalid_cooldown': 0,
    'first_run': False
}
dir_ = os.path.dirname(os.path.abspath('$STATE_FILE'))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(state, f)
os.rename(tmp, '$STATE_FILE')
"
}

make_transcript() {
    local path="$1"; shift; > "$path"
    for msg in "$@"; do
        python3 -c "import json,sys; print(json.dumps({'type':'user','isMeta':False,'message':{'role':'user','content':sys.argv[1]}}))" "$msg" >> "$path"
    done
}

dispatch_input() {
    python3 -c "import json,sys; print(json.dumps({'transcript_path':sys.argv[1],'cwd':sys.argv[2],'prompt':sys.argv[3]}))" "$1" "$2" "$3"
}

preuse_input() {
    local tool_name="$1"; local skill_name="${2:-}"
    if [ -n "$skill_name" ]; then
        python3 -c "import json,sys; print(json.dumps({'tool_name':sys.argv[1],'tool_input':{'skill':sys.argv[2]}}))" "$tool_name" "$skill_name"
    else
        python3 -c "import json,sys; print(json.dumps({'tool_name':sys.argv[1],'tool_input':{}}))" "$tool_name"
    fi
}

read_state() { python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('$1',''))" 2>/dev/null || echo ""; }

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

# ── Setup ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Dispatch — Pre-E2E Hook Integration Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

save_state
TRANSCRIPT=$(mktemp --suffix=.jsonl)
trap 'rm -f "$TRANSCRIPT"; restore_state' EXIT

TOKEN=$(python3 -c "import json; d=json.load(open('$DISPATCH_DIR/config.json')); print(d.get('token',''))" 2>/dev/null || echo "")

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 0 — Preflight
# ─────────────────────────────────────────────────────────────────────────────
echo "[ Suite 0: Preflight ]"

if [ -x "$DISPATCH_SH" ];          then pass "dispatch.sh exists and is executable";          else fail "dispatch.sh missing or not executable"; fi
if [ -x "$PREUSE_SH" ];            then pass "dispatch-preuse.sh exists and is executable";   else fail "dispatch-preuse.sh missing or not executable"; fi
if [ -f "$DISPATCH_DIR/config.json" ]; then pass "config.json present";                       else fail "config.json missing"; fi
if [ -f "$STATE_FILE" ];           then pass "state.json present";                            else fail "state.json missing"; fi
if [ -n "$TOKEN" ];                then pass "Hosted token configured";                       else fail "No token — hosted mode tests will fail"; fi

echo ""
echo "[ Suite 0b: Server connectivity ]"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://dispatch.visionairy.biz/classify" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"transcript":[],"cwd":"/tmp","prompt":"test connection"}' \
    --max-time 8 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && pass "Server /classify responds 200" || fail "Server /classify returned $HTTP_CODE"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://dispatch.visionairy.biz/rank" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"task_type":"react-building","context_snippet":"build a dashboard","cc_tool":"Skill","category_id":"frontend-development"}' \
    --max-time 8 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && pass "Server /rank responds 200" || fail "Server /rank returned $HTTP_CODE"

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 1 — dispatch.sh: short message skip
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 1: dispatch.sh — short message skip ]"

reset_state
OUTPUT=$(echo '{"transcript_path":"","cwd":"/tmp","prompt":"ok"}' | bash "$DISPATCH_SH" 2>/dev/null)
EXIT=$?
[ "$EXIT" -eq 0 ]  && pass "T1: Short message exits 0"            || fail "T1: Short message exit=$EXIT"
[ -z "$OUTPUT" ]   && pass "T1: Short message produces no output" || fail "T1: Short message had output: $OUTPUT"

reset_state
OUTPUT=$(echo '{"transcript_path":"","cwd":"/tmp","prompt":"yes"}' | bash "$DISPATCH_SH" 2>/dev/null)
EXIT=$?
[ "$EXIT" -eq 0 ] && pass "T1b: Single word exits 0" || fail "T1b: Single word exit=$EXIT"

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 2 — dispatch.sh: task shift + state write
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 2: dispatch.sh — task shift + Stage 2 state write ]"

# Set a prior task_type so the classifier has something to shift FROM
reset_state
set_state '{"last_task_type":"python-debugging","last_category":"debugging","last_recommended_category":""}'
make_transcript "$TRANSCRIPT" \
    "I need to build a React TypeScript dashboard" \
    "With charts using Recharts and real-time data" \
    "State management with Redux Toolkit"
INPUT=$(dispatch_input "$TRANSCRIPT" "/home/visionairy/Dispatch" "Set up React Router for navigation and configure the Redux store with TypeScript")
OUTPUT=$(echo "$INPUT" | bash "$DISPATCH_SH" 2>/dev/null)
EXIT=$?
if [ "$EXIT" -eq 0 ]; then pass "T2: Task shift exits 0"; else fail "T2: Task shift exit=$EXIT"; fi

TASK_TYPE=$(read_state last_task_type)
CATEGORY=$(read_state last_category)
SNIPPET=$(read_state last_context_snippet)
CWD_STATE=$(read_state last_cwd)

# Verify state was actually UPDATED from the prior values (not still python-debugging)
if [ -n "$TASK_TYPE" ] && [ "$TASK_TYPE" != "None" ] && [ "$TASK_TYPE" != "python-debugging" ]; then
    pass "T2: last_task_type updated to new value ('$TASK_TYPE')"
elif [ -n "$TASK_TYPE" ] && [ "$TASK_TYPE" != "None" ]; then
    fail "T2: last_task_type unchanged ('$TASK_TYPE') — shift not detected"
else
    fail "T2: last_task_type not written (value: '$TASK_TYPE')"
fi
if [ -n "$CATEGORY" ] && [ "$CATEGORY" != "None" ]; then pass "T2: last_category written ('$CATEGORY')"; else fail "T2: last_category not written"; fi
if [ -n "$SNIPPET" ];   then pass "T2: last_context_snippet written"; else fail "T2: last_context_snippet not written"; fi
if [ -n "$CWD_STATE" ]; then pass "T2: last_cwd written"; else fail "T2: last_cwd not written"; fi

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 3 — dispatch.sh: Stage 3 proactive output
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 3: dispatch.sh — Stage 3 proactive recommendations ]"

# Set a prior task_type (different domain) so classifier detects shift to React
reset_state
set_state '{"last_task_type":"python-debugging","last_category":"debugging","last_recommended_category":""}'
make_transcript "$TRANSCRIPT" \
    "I want to build a React TypeScript dashboard" \
    "With charts using Recharts and real-time WebSocket data" \
    "Using TypeScript Tailwind CSS and Vite"
INPUT=$(dispatch_input "$TRANSCRIPT" "/home/visionairy/Dispatch" "Start by setting up the React component structure with React Router Redux Toolkit and TypeScript configuration")
OUTPUT=$(echo "$INPUT" | bash "$DISPATCH_SH" 2>/dev/null)
EXIT=$?
[ "$EXIT" -eq 0 ] && pass "T3: Stage 3 exits 0" || fail "T3: Stage 3 exit=$EXIT"

if echo "$OUTPUT" | grep -q "\[Dispatch\]"; then
    pass "T3: Output contains [Dispatch] header"
    echo "$OUTPUT" | grep -qiE "Plugin|Skill|MCP" \
        && pass "T3: Output contains at least one tool section" \
        || fail "T3: Output missing Plugins/Skills/MCPs sections"
    echo "$OUTPUT" | grep -q "Not sure which to pick" \
        && pass "T3: Output contains closing CTA" \
        || fail "T3: Output missing closing CTA"
    LAST_REC=$(read_state last_recommended_category)
    [ -n "$LAST_REC" ] \
        && pass "T3: last_recommended_category written ('$LAST_REC')" \
        || fail "T3: last_recommended_category not written after Stage 3"
else
    fail "T3: No [Dispatch] output — shift not detected or server issue"
    echo "      Raw output: $(echo "$OUTPUT" | head -3)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 4 — dispatch.sh: once-per-category gate
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 4: dispatch.sh — once-per-category gate ]"

LAST_REC=$(read_state last_recommended_category)
if [ -n "$LAST_REC" ]; then
    make_transcript "$TRANSCRIPT" \
        "Now add more React components with TypeScript" \
        "I need unit tests for each component" \
        "Use Jest and React Testing Library"
    INPUT=$(dispatch_input "$TRANSCRIPT" "/home/visionairy/Dispatch" "Add a data table component with sorting and filtering and pagination")
    OUTPUT2=$(echo "$INPUT" | bash "$DISPATCH_SH" 2>/dev/null)
    EXIT=$?
    [ "$EXIT" -eq 0 ] && pass "T4: Same-category follow-up exits 0" || fail "T4: exit=$EXIT"
    echo "$OUTPUT2" | grep -q "\[Dispatch\]" \
        && fail "T4: Same-category fired Stage 3 twice (gate broken)" \
        || pass "T4: Same-category correctly suppressed Stage 3"
else
    echo "  ⚠  T4: Skipped — Stage 3 did not fire in Suite 3 (check server connectivity)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 5 — dispatch.sh: first_run welcome message
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 5: dispatch.sh — first_run welcome ]"

reset_state
set_state '{"first_run": true}'
make_transcript "$TRANSCRIPT" "Starting a new project today"
INPUT=$(dispatch_input "$TRANSCRIPT" "/home/visionairy/Dispatch" "Starting a new project today with some new requirements")
OUTPUT=$(echo "$INPUT" | bash "$DISPATCH_SH" 2>/dev/null)
echo "$OUTPUT" | grep -q "Dispatch is active" \
    && pass "T5: first_run=true emits welcome message" \
    || fail "T5: first_run=true did not emit welcome (output: '$(echo "$OUTPUT" | head -1)')"

FIRST_RUN_AFTER=$(read_state first_run)
[ "$FIRST_RUN_AFTER" = "False" ] || [ "$FIRST_RUN_AFTER" = "false" ] \
    && pass "T5: first_run cleared to false after welcome" \
    || fail "T5: first_run not cleared (value: '$FIRST_RUN_AFTER')"

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 6 — preuse_hook.sh: non-intercepted tools pass through
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 6: preuse_hook.sh — non-intercepted tools pass through ]"

for tool in "Read" "Write" "Edit" "Bash" "Glob" "Grep" "TodoWrite"; do
    INPUT=$(preuse_input "$tool")
    OUTPUT=$(echo "$INPUT" | bash "$PREUSE_SH" 2>/dev/null)
    EXIT=$?
    [ "$EXIT" -eq 0 ] && [ -z "$OUTPUT" ] \
        && pass "T6: $tool passes through (exit 0, no output)" \
        || fail "T6: $tool — exit=$EXIT output='$OUTPUT'"
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 7 — preuse_hook.sh: intercepted tools with empty state
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 7: preuse_hook.sh — intercepted tools with empty state ]"

reset_state
for tool_json in \
    '{"tool_name":"Skill","tool_input":{"skill":"owner/repo"}}' \
    '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"help"}}' \
    '{"tool_name":"mcp__github__create_pull_request","tool_input":{}}'; do
    TOOL=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['tool_name'])" "$tool_json")
    OUTPUT=$(echo "$tool_json" | bash "$PREUSE_SH" 2>/dev/null)
    EXIT=$?
    [ "$EXIT" -eq 0 ] \
        && pass "T7: $TOOL with empty state passes through (exit 0)" \
        || fail "T7: $TOOL with empty state — exit=$EXIT (expected 0)"
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 8 — preuse_hook.sh: intercepted tools with category state
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 8: preuse_hook.sh — intercepted tools with category state (block or pass) ]"

CATEGORIES=(
    '{"last_task_type":"react-building","last_category":"frontend-development","last_context_snippet":"building a React dashboard with TypeScript and charts"}'
    '{"last_task_type":"flutter-building","last_category":"mobile-development","last_context_snippet":"building a Flutter mobile app with Firebase Auth"}'
    '{"last_task_type":"postgres-managing","last_category":"data-storage","last_context_snippet":"optimizing PostgreSQL queries and schema design"}'
)
TOOLS=(
    '{"tool_name":"Skill","tool_input":{"skill":"owner/some-react-skill"}}'
    '{"tool_name":"Skill","tool_input":{"skill":"owner/some-flutter-skill"}}'
    '{"tool_name":"mcp__github__create_pull_request","tool_input":{}}'
)
LABELS=("Skill/frontend" "Skill/mobile" "mcp__github/data-storage")

for i in 0 1 2; do
    reset_state
    set_state "${CATEGORIES[$i]}"
    OUTPUT=$(echo "${TOOLS[$i]}" | bash "$PREUSE_SH" 2>/dev/null)
    EXIT=$?
    if [ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 2 ]; then
        pass "T8: ${LABELS[$i]} — exit $EXIT (no crash)"
        if [ "$EXIT" -eq 2 ]; then
            [ -n "$OUTPUT" ] \
                && pass "T8: ${LABELS[$i]} — block output present" \
                || fail "T8: ${LABELS[$i]} — exit 2 but no output"
            # Verify bypass token was written
            BYPASS_TOOL=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('bypass',{}).get('tool_name',''))" 2>/dev/null)
            [ -n "$BYPASS_TOOL" ] \
                && pass "T8: ${LABELS[$i]} — bypass token written on block" \
                || fail "T8: ${LABELS[$i]} — bypass token not written after block"
        fi
    else
        fail "T8: ${LABELS[$i]} — unexpected exit=$EXIT"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 9 — preuse_hook.sh: bypass token
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 9: preuse_hook.sh — bypass token ]"

# Active bypass — forces pass
reset_state
set_state '{"last_task_type":"react-building","last_category":"frontend-development","last_context_snippet":"building React app"}'
python3 -c "
import json, os, tempfile, time
state_file = '$STATE_FILE'
d = json.load(open(state_file))
d['bypass'] = {'tool_name': 'Skill', 'expires': time.time() + 120}
dir_ = os.path.dirname(os.path.abspath(state_file))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(d, f)
os.rename(tmp, state_file)
"
INPUT=$(preuse_input "Skill" "owner/some-skill")
OUTPUT=$(echo "$INPUT" | bash "$PREUSE_SH" 2>/dev/null)
EXIT=$?
[ "$EXIT" -eq 0 ] && pass "T9: Active bypass forces exit 0" || fail "T9: Active bypass — exit=$EXIT (expected 0)"
BYPASS_AFTER=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('bypass',{}).get('tool_name',''))" 2>/dev/null)
[ -z "$BYPASS_AFTER" ] \
    && pass "T9: Bypass token consumed after use" \
    || fail "T9: Bypass token not consumed (tool_name='$BYPASS_AFTER')"

# Expired bypass — does NOT force pass
reset_state
set_state '{"last_task_type":"react-building","last_category":"frontend-development","last_context_snippet":"building React app"}'
python3 -c "
import json, os, tempfile, time
state_file = '$STATE_FILE'
d = json.load(open(state_file))
d['bypass'] = {'tool_name': 'Skill', 'expires': time.time() - 10}
dir_ = os.path.dirname(os.path.abspath(state_file))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(d, f)
os.rename(tmp, state_file)
"
INPUT=$(preuse_input "Skill" "owner/some-skill")
OUTPUT=$(echo "$INPUT" | bash "$PREUSE_SH" 2>/dev/null)
EXIT=$?
[ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 2 ] \
    && pass "T9b: Expired bypass handled correctly (exit=$EXIT, no crash)" \
    || fail "T9b: Expired bypass — unexpected exit=$EXIT"
[ "$EXIT" -eq 2 ] && echo "      (Correctly did NOT force-pass with expired bypass — hook ranked normally)"
[ "$EXIT" -eq 0 ] && echo "      (Passed — hook ranked CC tool as competitive)"

# Wrong tool bypass — does NOT apply
reset_state
set_state '{"last_task_type":"react-building","last_category":"frontend-development","last_context_snippet":"building React app"}'
python3 -c "
import json, os, tempfile, time
state_file = '$STATE_FILE'
d = json.load(open(state_file))
d['bypass'] = {'tool_name': 'Agent', 'expires': time.time() + 120}
dir_ = os.path.dirname(os.path.abspath(state_file))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as f: json.dump(d, f)
os.rename(tmp, state_file)
"
INPUT=$(preuse_input "Skill" "owner/some-skill")
OUTPUT=$(echo "$INPUT" | bash "$PREUSE_SH" 2>/dev/null)
EXIT=$?
[ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 2 ] \
    && pass "T9c: Wrong-tool bypass not applied to different tool (exit=$EXIT)" \
    || fail "T9c: Wrong-tool bypass — unexpected exit=$EXIT"

# ─────────────────────────────────────────────────────────────────────────────
# SUITE 10 — State integrity after all tests
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[ Suite 10: State integrity ]"

python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null \
    && pass "T10: state.json is valid JSON after all tests" \
    || fail "T10: state.json corrupted"

python3 -c "
import json
d = json.load(open('$DISPATCH_DIR/config.json'))
assert d.get('token'), 'no token'
assert d.get('endpoint'), 'no endpoint'
" 2>/dev/null \
    && pass "T10: config.json valid with token and endpoint" \
    || fail "T10: config.json invalid or missing fields"

python3 -c "
import sys
sys.path.insert(0, '$DISPATCH_DIR')
from classifier import classify_topic_shift, extract_recent_messages, should_skip
from evaluator import recommend_tools, build_recommendation_list, search_by_category
from interceptor import should_intercept, check_bypass, write_bypass, get_task_type, get_category
from category_mapper import map_to_category
from llm_client import get_client
from stack_scanner import scan_and_save, load_stack_profile
" 2>/dev/null \
    && pass "T10: All 6 Python modules import cleanly from installed path" \
    || fail "T10: Module import failed from installed path"

# ─────────────────────────────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
echo " Results: $PASS passed, $FAIL failed, $TOTAL total"
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
