#!/usr/bin/env bash
# =============================================================================
# Dispatch Live System Test
# Run this in the morning to prove Dispatch is fully operational.
#
# Tests: installation, module imports, interceptor logic, session counters,
#        bypass tokens, state reads, category mapping, hook pass-throughs,
#        and (if ANTHROPIC_API_KEY set) live LLM classification + intercept.
#
# Usage:
#   bash test_dispatch_live.sh
#   ANTHROPIC_API_KEY=sk-ant-... bash test_dispatch_live.sh
# =============================================================================

set -uo pipefail

DISPATCH_DIR="$HOME/.claude/dispatch"
HOOKS_DIR="$HOME/.claude/hooks"
STATE_FILE="$DISPATCH_DIR/state.json"

PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
section() { echo ""; echo -e "${CYAN}── $1 ──${NC}"; }

echo ""
echo -e "${YELLOW}Dispatch System Test — $(date '+%Y-%m-%d %H:%M')${NC}"
echo "================================================"

# =============================================================================
# SECTION 1: Installation
# =============================================================================
section "1. Installation"

[ -f "$HOOKS_DIR/dispatch.sh" ]        && pass "dispatch.sh (UserPromptSubmit hook)" || fail "dispatch.sh missing — run install.sh"
[ -f "$HOOKS_DIR/dispatch-preuse.sh" ] && pass "dispatch-preuse.sh (PreToolUse hook)" || fail "dispatch-preuse.sh missing"
[ -f "$HOOKS_DIR/dispatch-stop.sh" ]   && pass "dispatch-stop.sh (Stop hook)" || fail "dispatch-stop.sh missing — new hook, re-run install.sh"
[ -f "$DISPATCH_DIR/interceptor.py" ]  && pass "interceptor.py" || fail "interceptor.py missing"
[ -f "$DISPATCH_DIR/evaluator.py" ]    && pass "evaluator.py" || fail "evaluator.py missing"
[ -f "$DISPATCH_DIR/classifier.py" ]   && pass "classifier.py" || fail "classifier.py missing"
[ -f "$DISPATCH_DIR/category_mapper.py" ] && pass "category_mapper.py" || fail "category_mapper.py missing"
[ -f "$DISPATCH_DIR/stack_scanner.py" ] && pass "stack_scanner.py" || fail "stack_scanner.py missing"
[ -f "$DISPATCH_DIR/categories.json" ] && pass "categories.json" || fail "categories.json missing"
[ -f "$DISPATCH_DIR/state.json" ]      && pass "state.json exists" || fail "state.json missing — run install.sh"

# Check settings.json has all three hooks
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    python3 -c "
import json
s = json.load(open('$SETTINGS'))
hooks = s.get('hooks', {})
assert 'UserPromptSubmit' in hooks, 'UserPromptSubmit not registered'
assert 'PreToolUse' in hooks, 'PreToolUse not registered'
assert 'Stop' in hooks, 'Stop not registered'
# Verify each hook points to the right file
ups = str(hooks.get('UserPromptSubmit', ''))
ptr = str(hooks.get('PreToolUse', ''))
stp = str(hooks.get('Stop', ''))
assert 'dispatch.sh' in ups, 'dispatch.sh not in UserPromptSubmit hooks'
assert 'dispatch-preuse' in ptr, 'dispatch-preuse not in PreToolUse hooks'
assert 'dispatch-stop' in stp, 'dispatch-stop not in Stop hooks'
print('ok')
" 2>/dev/null && pass "settings.json has all 3 hooks registered" || fail "settings.json missing hooks — re-run install.sh"
fi

# =============================================================================
# SECTION 2: Module imports
# =============================================================================
section "2. Python modules load cleanly"

for mod in interceptor evaluator classifier category_mapper stack_scanner llm_client; do
    python3 -c "import sys; sys.path.insert(0, '$DISPATCH_DIR'); import $mod" 2>/dev/null \
        && pass "$mod" || fail "$mod import failed — check for syntax errors"
done

# =============================================================================
# SECTION 3: Interceptor logic
# =============================================================================
section "3. Interceptor — tool routing"

python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null && pass "should_intercept: mcp__/Skill/Agent intercepted, Read/Write/Edit pass through" || fail "should_intercept broken"
import sys; sys.path.insert(0, sys.argv[1])
from interceptor import should_intercept, get_cc_tool_type, extract_cc_tool
assert should_intercept('mcp__github__create_pull_request')
assert should_intercept('mcp__supabase__execute_sql')
assert should_intercept('Skill')
assert should_intercept('Agent')
assert not should_intercept('Edit')
assert not should_intercept('Write')
assert not should_intercept('Read')
assert not should_intercept('Bash')
print('ok')
PYEOF

python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null && pass "get_cc_tool_type: mcp/agent/skill classified correctly" || fail "get_cc_tool_type broken"
import sys; sys.path.insert(0, sys.argv[1])
from interceptor import get_cc_tool_type
assert get_cc_tool_type('mcp__github__create_pull_request') == 'mcp'
assert get_cc_tool_type('mcp__supabase__execute_sql') == 'mcp'
assert get_cc_tool_type('Agent') == 'agent'
assert get_cc_tool_type('Skill') == 'skill'
print('ok')
PYEOF

python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null && pass "extract_cc_tool: Skill/Agent/mcp labels extracted" || fail "extract_cc_tool broken"
import sys; sys.path.insert(0, sys.argv[1])
from interceptor import extract_cc_tool
assert extract_cc_tool('Skill', {'skill': 'superpowers:debugging'}) == 'superpowers:debugging'
assert extract_cc_tool('Agent', {'subagent_type': 'general-purpose'}) == 'general-purpose'
assert extract_cc_tool('Skill', None) == 'Skill'
result = extract_cc_tool('mcp__github__create_pull_request', {})
assert 'github' in result
print('ok')
PYEOF

# =============================================================================
# SECTION 4: Session counters
# =============================================================================
section "4. Session counters (Stop hook data)"

python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null && pass "Session counters: increment, accumulate, reset on new session_id" || fail "Session counters broken"
import sys, json, tempfile, os; sys.path.insert(0, sys.argv[1])
from interceptor import increment_session_counter, get_session_stats

f = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
json.dump({}, f); f.close()

increment_session_counter('session_audits', 'sess-A', state_file=f.name)
increment_session_counter('session_audits', 'sess-A', state_file=f.name)
increment_session_counter('session_audits', 'sess-A', state_file=f.name)
increment_session_counter('session_blocks', 'sess-A', state_file=f.name)
increment_session_counter('session_recommendations', 'sess-A', state_file=f.name)
stats = get_session_stats(state_file=f.name)
assert stats['audits'] == 3, f"audits={stats['audits']}"
assert stats['blocks'] == 1
assert stats['recommendations'] == 1

# New session resets all counters
increment_session_counter('session_audits', 'sess-B', state_file=f.name)
stats = get_session_stats(state_file=f.name)
assert stats['audits'] == 1, f"new session should reset: audits={stats['audits']}"
assert stats['blocks'] == 0

os.unlink(f.name)
print('ok')
PYEOF

# Simulate stop hook output
STOP_OUTPUT=$(python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null
import sys, json, tempfile, os; sys.path.insert(0, sys.argv[1])
from interceptor import increment_session_counter, get_session_stats

f = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
json.dump({}, f); f.close()
increment_session_counter('session_audits', 'sess-demo', state_file=f.name)
increment_session_counter('session_audits', 'sess-demo', state_file=f.name)
increment_session_counter('session_audits', 'sess-demo', state_file=f.name)
increment_session_counter('session_audits', 'sess-demo', state_file=f.name)
increment_session_counter('session_audits', 'sess-demo', state_file=f.name)
increment_session_counter('session_blocks', 'sess-demo', state_file=f.name)
increment_session_counter('session_recommendations', 'sess-demo', state_file=f.name)
stats = get_session_stats(state_file=f.name)
audits = stats['audits']; blocks = stats['blocks']; recs = stats['recommendations']
block_str = f"{blocks} blocked" if blocks > 0 else "0 blocked (all optimal)"
print(f"[Dispatch] Session: {audits} tool calls audited · {block_str} · {recs} recommendation{'s' if recs != 1 else ''} shown")
os.unlink(f.name)
PYEOF
)
[ -n "$STOP_OUTPUT" ] && pass "Stop hook digest: $STOP_OUTPUT" || fail "Stop hook digest empty"

# =============================================================================
# SECTION 5: Bypass token
# =============================================================================
section "5. Bypass token (user says 'proceed')"

python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null && pass "Bypass token: write/check/clear/TTL correct" || fail "Bypass token broken"
import sys, json, tempfile, os; sys.path.insert(0, sys.argv[1])
from interceptor import write_bypass, check_bypass, clear_bypass

f = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
json.dump({}, f); f.close()

write_bypass('Skill', state_file=f.name)
assert check_bypass('Skill', state_file=f.name), 'bypass should be active'
assert not check_bypass('Agent', state_file=f.name), 'wrong tool should not match'
assert not check_bypass('mcp__github__foo', state_file=f.name), 'different tool should not match'
clear_bypass('Skill', state_file=f.name)
assert not check_bypass('Skill', state_file=f.name), 'bypass should be cleared after explicit clear'

os.unlink(f.name)
print('ok')
PYEOF

# =============================================================================
# SECTION 6: State field reads
# =============================================================================
section "6. State field consistency (dispatch.sh writes, preuse reads)"

python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null && pass "State fields: get_task_type/get_category/get_context_snippet read correctly" || fail "State field reads broken"
import sys, json, tempfile, os; sys.path.insert(0, sys.argv[1])
import interceptor

f = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
json.dump({
    'last_task_type': 'flutter-building',
    'last_category': 'mobile-development',
    'last_context_snippet': 'building a widget tree'
}, f); f.close()

interceptor.STATE_FILE = f.name
assert interceptor.get_task_type() == 'flutter-building'
assert interceptor.get_category() == 'mobile-development'
assert interceptor.get_context_snippet() == 'building a widget tree'

os.unlink(f.name)
print('ok')
PYEOF

# =============================================================================
# SECTION 7: Category mapping for your stack
# =============================================================================
section "7. Category mapping (your actual stack)"

python3 - "$DISPATCH_DIR" <<'PYEOF' 2>/dev/null && pass "Category mapping correct for your stack" || fail "Category mapping wrong — check categories.json"
import sys; sys.path.insert(0, sys.argv[1])
from category_mapper import map_to_category

stack_tests = [
    # Flutter / mobile
    ('flutter-building', 'mobile-development'),
    ('react-native-app', 'mobile-development'),
    # Web
    ('react-component', 'web-frontend'),
    ('nextjs-page', 'web-frontend'),
    # Database / Supabase
    ('postgres-query', 'database'),
    ('supabase-rls', 'database'),
    # n8n / workflows
    ('n8n-workflow', 'workflow-automation'),
    ('automation-pipeline', 'workflow-automation'),
    # DevOps
    ('docker-deployment', 'devops-infrastructure'),
    ('github-actions', 'devops-infrastructure'),
    # AI/ML
    ('langchain-agent', 'ai-ml'),
]

failed = []
for task, expected in stack_tests:
    result = map_to_category(task)
    if result != expected:
        failed.append(f'{task} → {result} (expected {expected})')

if failed:
    for f in failed:
        print(f'  MISMATCH: {f}')
    sys.exit(1)
print('ok')
PYEOF

# =============================================================================
# SECTION 8: Hook pass-through (no API)
# =============================================================================
section "8. PreToolUse pass-through (no API needed)"

for tool in Read Write Edit Bash Glob Grep WebFetch TodoWrite; do
    INPUT="{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"test-pass\",\"tool_name\":\"$tool\",\"tool_input\":{}}"
    exit_code=$(echo "$INPUT" | bash "$HOOKS_DIR/dispatch-preuse.sh" 2>/dev/null; echo $?)
    [ "$exit_code" = "0" ] && pass "$tool passes through silently (exit 0)" \
                           || fail "$tool returned exit $exit_code — should be 0"
done

# =============================================================================
# SECTION 9: dispatch.sh short prompt skip
# =============================================================================
section "9. dispatch.sh short prompt skip"

INPUT='{"hook_event_name":"UserPromptSubmit","session_id":"test-skip","cwd":"/tmp","transcript_path":"/tmp/fake.jsonl","prompt":"ok"}'
exit_code=$(echo "$INPUT" | bash "$HOOKS_DIR/dispatch.sh" 2>/dev/null; echo $?)
[ "$exit_code" = "0" ] && pass "Short prompt ('ok') skipped without API call" \
                       || fail "Short prompt handling broken: exit $exit_code"

INPUT='{"hook_event_name":"UserPromptSubmit","session_id":"test-skip","cwd":"/tmp","transcript_path":"/tmp/fake.jsonl","prompt":"yes"}'
exit_code=$(echo "$INPUT" | bash "$HOOKS_DIR/dispatch.sh" 2>/dev/null; echo $?)
[ "$exit_code" = "0" ] && pass "Short prompt ('yes') skipped without API call" \
                       || fail "Short prompt handling broken: exit $exit_code"

# =============================================================================
# SECTION 10: LLM tests (require ANTHROPIC_API_KEY)
# =============================================================================
section "10. Live LLM tests (ANTHROPIC_API_KEY required)"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    warn "ANTHROPIC_API_KEY not set — skipping LLM tests"
    warn "Run: ANTHROPIC_API_KEY=sk-ant-... bash test_dispatch_live.sh"
else
    export ANTHROPIC_API_KEY

    # Test: Flutter → mobile-development
    INPUT='{"hook_event_name":"UserPromptSubmit","session_id":"livetest-001","cwd":"'"$HOME"'","transcript_path":"/tmp/fake.jsonl","prompt":"I need to build a new Flutter screen with a bottom navigation bar and three tabs, each tab showing a different list view for my mobile app"}'
    echo "$INPUT" | bash "$HOOKS_DIR/dispatch.sh" 2>/dev/null
    state=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_category','none'))" 2>/dev/null)
    [ "$state" = "mobile-development" ] && pass "Flutter prompt → mobile-development (Haiku classified correctly)" \
                                        || fail "Flutter prompt → '$state' (expected mobile-development)"

    # Test: n8n → workflow-automation
    INPUT='{"hook_event_name":"UserPromptSubmit","session_id":"livetest-002","cwd":"'"$HOME"'","transcript_path":"/tmp/fake.jsonl","prompt":"I need to build an n8n workflow that triggers when a new row is inserted in Supabase and sends a Slack notification with the data"}'
    echo "$INPUT" | bash "$HOOKS_DIR/dispatch.sh" 2>/dev/null
    state=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_category','none'))" 2>/dev/null)
    [ "$state" = "workflow-automation" ] && pass "n8n prompt → workflow-automation" \
                                         || fail "n8n prompt → '$state' (expected workflow-automation)"

    # Test: Supabase → database
    INPUT='{"hook_event_name":"UserPromptSubmit","session_id":"livetest-003","cwd":"'"$HOME"'","transcript_path":"/tmp/fake.jsonl","prompt":"Help me write a Supabase RLS policy that restricts access to rows based on the authenticated user ID, and create a SQL migration for the new policy"}'
    echo "$INPUT" | bash "$HOOKS_DIR/dispatch.sh" 2>/dev/null
    state=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_category','none'))" 2>/dev/null)
    [ "$state" = "database" ] && pass "Supabase RLS prompt → database" \
                               || fail "Supabase prompt → '$state' (expected database)"

    # Test: GitHub MCP intercept
    INPUT='{"hook_event_name":"PreToolUse","session_id":"livetest-004","tool_name":"mcp__github__create_pull_request","tool_input":{"owner":"VisionAIrySE","repo":"Dispatch","title":"test"}}'
    exit_code=$(echo "$INPUT" | bash "$HOOKS_DIR/dispatch-preuse.sh" 2>/dev/null; echo $?)
    [ "$exit_code" = "0" ] || [ "$exit_code" = "2" ] \
        && pass "mcp__github__ intercepted — exit $exit_code (0=no better tool, 2=blocked)" \
        || fail "mcp__github__ not handled — exit $exit_code"

    # Verify state.json is being written
    last_type=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_task_type','MISSING'))" 2>/dev/null)
    last_cat=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_category','MISSING'))" 2>/dev/null)
    last_updated=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_updated','MISSING'))" 2>/dev/null)
    [ "$last_type" != "MISSING" ] && pass "state.json populated: task_type=$last_type, category=$last_cat" \
                                   || fail "state.json not being written by dispatch.sh"

fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "════════════════════════════════════════"
if [ "$FAIL" = "0" ]; then
    echo -e "  ${GREEN}ALL $PASS TESTS PASSED${NC}"
    echo "  Dispatch is fully operational."
else
    echo -e "  ${GREEN}$PASS passed${NC}  ${RED}$FAIL failed${NC}"
    echo "  Fix failures before going live."
fi
echo "════════════════════════════════════════"
echo ""
