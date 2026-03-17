# Proactive Recommendations Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dispatch recommends better tools proactively at UserPromptSubmit time (dispatch.sh Stage 3), injecting ranked results across all three tool types (skills, MCPs, plugins) into CC's context so users can discover and install better tools conversationally — even if they never invoke a tool themselves.

**Architecture:** Stage 3 fires after Stage 2 state write on every confirmed shift where the category differs from `last_recommended_category`. It calls `recommend_tools()` in evaluator.py (BYOK local) or falls back to `/rank` with no cc_tool (hosted-only). Results are formatted and printed to stdout so CC injects them before formulating its response.

**Tech Stack:** Python 3.8+ · Bash · Claude Haiku API · skills.sh · glama.ai · official plugins cache

---

## Northstar Output (exact format — do not deviate)

```
[Dispatch] Recommended tools for this flutter-building task:

Plugins:
  • flutter-mobile-app-dev — Expert Flutter agent covering widgets, state management, iOS & Android.
    Install: claude install plugin:anthropic:flutter-mobile-app-dev
  • flutter-design-system — Flutter UI components and design system tooling.
    Install: claude install plugin:anthropic:flutter-design-system

Skills:
  • VisionAIrySE/flutter@flutter-dev — Flutter dev skill for widget building and navigation.
    Install: claude install VisionAIrySE/flutter@flutter-dev
  • VisionAIrySE/flutter@flutter-test — Flutter testing and widget inspection patterns.
    Install: claude install VisionAIrySE/flutter@flutter-test

MCPs:
  • fluttermcp — Dart analysis and widget tree inspection server.
    Install: claude mcp add fluttermcp npx -y @fluttermcp/server
  • flutter-tools-mcp — Flutter project analyzer and hot reload manager.
    Install: claude mcp add flutter-tools-mcp npx -y @flutter-tools/mcp

Not sure which to pick? Ask me — I can explain the differences.
```

**Scores are internal only.** Used for ranking and floor filtering (≥55) but never shown in output. Results are grouped by type (Plugins/Skills/MCPs) for clarity.
CC has the context and can explain relevance when user asks.

**Silent cases** (no stdout output at all):
- No confirmed shift
- Confidence < 0.7
- Category == `last_recommended_category` (already shown for this topic)
- Top tool score < 55
- All matching tools already installed (filtered by stack_profile)
- Any error in Stage 3

**Score floor:** 55. No tiers in display — just score and description. User judges.

**Diversity cap:** Max 2 per tool type, max 5 total. `preferred_tool_type` from classifier sorts that type first.

---

## File Map

| File | Change |
|------|--------|
| `interceptor.py` | Add `get_last_recommended_category()` + `write_last_recommended_category()` |
| `evaluator.py` | Add `RECOMMEND_SYSTEM_PROMPT` + `recommend_tools()` function |
| `dispatch.sh` | Add Stage 3 block after Stage 2 state write |
| `test_interceptor.py` | Add 4 tests for new state functions |
| `test_evaluator.py` | Add 6 tests for `recommend_tools()` |

**Server (`Dispatch-API`):** No changes required for MVP. Hosted-only users (no ANTHROPIC_API_KEY) call `/rank` with `cc_tool=""` — server already handles empty cc_tool gracefully (cc_score returns 0, which we ignore).

---

## Chunk 1: interceptor.py — state functions for recommendation tracking

### Task 1: Add `get_last_recommended_category` and `write_last_recommended_category` to interceptor.py

**Files:**
- Modify: `interceptor.py` (after `get_last_cc_tool_type`, ~line 273)
- Modify: `test_interceptor.py` (add 4 tests)

- [ ] **Step 1.1: Write the failing tests**

Add this class to `test_interceptor.py` (after the existing test classes):

```python
class TestLastRecommendedCategory(unittest.TestCase):
    def test_returns_empty_string_when_no_state(self):
        from interceptor import get_last_recommended_category
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            tmp = f.name
        os.unlink(tmp)
        try:
            result = get_last_recommended_category(state_file=tmp)
        finally:
            pass
        assert result == ""

    def test_returns_category_after_write(self):
        from interceptor import get_last_recommended_category, write_last_recommended_category
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            tmp = f.name
            json.dump({}, f)
        try:
            write_last_recommended_category("mobile", state_file=tmp)
            result = get_last_recommended_category(state_file=tmp)
            assert result == "mobile"
        finally:
            os.unlink(tmp)

    def test_write_preserves_existing_state_fields(self):
        from interceptor import write_last_recommended_category
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            tmp = f.name
            json.dump({"last_task_type": "flutter-building"}, f)
        try:
            write_last_recommended_category("mobile", state_file=tmp)
            with open(tmp) as f:
                d = json.load(f)
            assert d["last_task_type"] == "flutter-building"
            assert d["last_recommended_category"] == "mobile"
        finally:
            os.unlink(tmp)

    def test_get_returns_empty_on_corrupt_file(self):
        from interceptor import get_last_recommended_category
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            tmp = f.name
            f.write("NOT JSON")
        try:
            result = get_last_recommended_category(state_file=tmp)
            assert result == ""
        finally:
            os.unlink(tmp)
```

- [ ] **Step 1.2: Run tests to confirm they fail**

```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_interceptor.py::TestLastRecommendedCategory -v
```

Expected: `ImportError` or `AttributeError` — functions don't exist yet.

- [ ] **Step 1.3: Implement in interceptor.py**

Add after the `get_last_cc_tool_type` function (around line 273):

```python
def get_last_recommended_category(state_file: str = None) -> str:
    """Return the category last shown in a proactive recommendation, or '' if unset."""
    path = state_file or STATE_FILE
    try:
        with open(path) as f:
            return json.load(f).get("last_recommended_category", "")
    except Exception:
        return ""


def write_last_recommended_category(category: str, state_file: str = None) -> None:
    """Persist the category we just recommended so we don't re-fire for the same topic."""
    path = state_file or STATE_FILE
    try:
        try:
            with open(path) as f:
                state = json.load(f)
        except Exception:
            state = {}
        state["last_recommended_category"] = category
        _atomic_write(path, state)
    except Exception:
        pass
```

- [ ] **Step 1.4: Run tests to confirm they pass**

```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_interceptor.py::TestLastRecommendedCategory -v
```

Expected: 4 PASSED

- [ ] **Step 1.5: Run full interceptor suite to confirm nothing broke**

```bash
python3 -m pytest test_interceptor.py -v
```

Expected: all tests PASSED (was 62, now 66)

- [ ] **Step 1.6: Commit**

```bash
cd /home/visionairy/Dispatch
git add interceptor.py test_interceptor.py
git commit -m "feat(interceptor): add last_recommended_category state tracking"
```

---

## Chunk 2: evaluator.py — recommend_tools() for proactive mode

### Task 2: Add proactive-mode system prompt and recommend_tools() function

**Files:**
- Modify: `evaluator.py` (add after `RANK_SYSTEM_PROMPT`, around line 84)
- Modify: `test_evaluator.py` (add 6 tests)

- [ ] **Step 2.1: Write the failing tests**

Add this class to `test_evaluator.py`:

```python
class TestRecommendTools(unittest.TestCase):
    def test_returns_dict_with_all_and_top_pick_keys(self):
        from evaluator import recommend_tools
        from unittest.mock import patch, MagicMock
        mock_client = MagicMock()
        mock_client.complete.return_value = json.dumps({
            "all": [
                {"name": "VisionAIrySE/flutter@flutter-dev", "score": 82,
                 "reason": "Flutter dev skill.", "install_cmd": "npx skills add VisionAIrySE/flutter@flutter-dev -y"}
            ]
        })
        with patch("evaluator.get_client", return_value=mock_client), \
             patch("evaluator.search_by_category", return_value=[
                 {"id": "VisionAIrySE/flutter@flutter-dev", "description": "Flutter dev skill."}
             ]):
            result = recommend_tools("flutter-building", category_id="mobile")
        assert "all" in result
        assert "top_pick" in result

    def test_filters_tools_below_score_floor(self):
        from evaluator import recommend_tools
        from unittest.mock import patch, MagicMock
        mock_client = MagicMock()
        mock_client.complete.return_value = json.dumps({
            "all": [
                {"name": "tool-a", "score": 80, "reason": "Good."},
                {"name": "tool-b", "score": 40, "reason": "Below floor."},
            ]
        })
        with patch("evaluator.get_client", return_value=mock_client), \
             patch("evaluator.search_by_category", return_value=[]):
            result = recommend_tools("flutter-building", category_id="mobile")
        scores = [t["score"] for t in result["all"]]
        assert all(s >= 55 for s in scores)

    def test_returns_empty_on_llm_failure(self):
        from evaluator import recommend_tools
        from unittest.mock import patch, MagicMock
        mock_client = MagicMock()
        mock_client.complete.side_effect = Exception("LLM down")
        with patch("evaluator.get_client", return_value=mock_client), \
             patch("evaluator.search_by_category", return_value=[]):
            result = recommend_tools("flutter-building", category_id="mobile")
        assert result == {"all": [], "top_pick": None}

    def test_top_pick_is_highest_scored(self):
        from evaluator import recommend_tools
        from unittest.mock import patch, MagicMock
        mock_client = MagicMock()
        mock_client.complete.return_value = json.dumps({
            "all": [
                {"name": "tool-a", "score": 90, "reason": "Best."},
                {"name": "tool-b", "score": 75, "reason": "Good."},
            ]
        })
        with patch("evaluator.get_client", return_value=mock_client), \
             patch("evaluator.search_by_category", return_value=[]):
            result = recommend_tools("flutter-building", category_id="mobile")
        assert result["top_pick"]["name"] == "tool-a"

    def test_preferred_type_floats_to_front(self):
        from evaluator import recommend_tools
        from unittest.mock import patch, MagicMock
        mock_client = MagicMock()
        # Simulate ranker returning mixed types
        mock_client.complete.return_value = json.dumps({
            "all": [
                {"name": "tool-skill", "score": 82, "reason": "Skill."},
                {"name": "plugin:anthropic:tool-plugin", "score": 88, "reason": "Plugin."},
                {"name": "mcp:tool-mcp", "score": 77, "reason": "MCP."},
            ]
        })
        with patch("evaluator.get_client", return_value=mock_client), \
             patch("evaluator.search_by_category", return_value=[]):
            result = recommend_tools("flutter-building", category_id="mobile", preferred_type="mcp")
        # MCP should appear before higher-scored non-MCP tools
        names = [t["name"] for t in result["all"]]
        mcp_idx = names.index("mcp:tool-mcp")
        assert mcp_idx == 0

    def test_caps_at_two_per_type_max_five_total(self):
        from evaluator import recommend_tools
        from unittest.mock import patch, MagicMock
        mock_client = MagicMock()
        mock_client.complete.return_value = json.dumps({
            "all": [
                {"name": "skill-a", "score": 90, "reason": "A."},
                {"name": "skill-b", "score": 88, "reason": "B."},
                {"name": "skill-c", "score": 85, "reason": "C."},  # 3rd skill — drop
                {"name": "mcp:mcp-a", "score": 80, "reason": "D."},
                {"name": "mcp:mcp-b", "score": 78, "reason": "E."},
                {"name": "mcp:mcp-c", "score": 75, "reason": "F."},  # 3rd MCP — drop
                {"name": "plugin:anthropic:p-a", "score": 70, "reason": "G."},
            ]
        })
        with patch("evaluator.get_client", return_value=mock_client), \
             patch("evaluator.search_by_category", return_value=[]):
            result = recommend_tools("flutter-building", category_id="mobile")
        assert len(result["all"]) <= 5
        skill_count = sum(1 for t in result["all"] if not t["name"].startswith("mcp:") and not t["name"].startswith("plugin:"))
        mcp_count = sum(1 for t in result["all"] if t["name"].startswith("mcp:"))
        assert skill_count <= 2
        assert mcp_count <= 2
```

- [ ] **Step 2.2: Run tests to confirm they fail**

```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_evaluator.py::TestRecommendTools -v
```

Expected: `ImportError` — `recommend_tools` doesn't exist yet.

- [ ] **Step 2.3: Implement in evaluator.py**

Add after the `RANK_SYSTEM_PROMPT` block (after line 84):

```python
RECOMMEND_SYSTEM_PROMPT = """You are a tool recommendation engine for Claude Code.
Given a detected task type and context, rank available marketplace tools by relevance.

Respond with ONLY valid JSON:
{
  "all": [
    {"name": "owner/repo@skill-name", "score": 88,
     "install_cmd": "npx skills add owner/repo@skill-name -y",
     "reason": "one specific sentence grounded in the current task"}
  ]
}

Rules:
- all: marketplace tools sorted by relevance score (0-100) descending
- Only include tools with score >= 40 (caller applies final floor)
- Limit to top 8 tools across all types (skills, MCPs, plugins) before caller trims
- install_cmd: use provided hint exactly — do NOT fabricate
  - skills (format "owner/repo@name"): install_cmd = "npx skills add owner/repo@name -y"
  - MCPs (id starts with "mcp:"): omit install_cmd entirely
  - plugins (id starts with "plugin:"): use provided install_cmd if present, else omit
- Write specific reasons grounded in what the developer is actually doing
- If no tools are relevant, return {"all": []}

Reason quality:
GOOD: "Adds widget testing patterns directly applicable to the rendering crash you are diagnosing."
BAD: "Useful for Flutter." (too generic)
"""
```

Then add the `recommend_tools()` function after `build_recommendation_list()` (at the end of evaluator.py):

```python
def recommend_tools(
    task_type: str,
    context_snippet: str = None,
    category_id: str = None,
    stack_profile: dict = None,
    preferred_type: str = None,
    model: str = None,
) -> dict:
    """Proactive recommendation — no cc_tool comparison.

    Searches all three tool types (skills, MCPs, plugins) for the given category,
    ranks by task relevance, applies diversity caps and score floor.

    Returns {"all": [...], "top_pick": {...} or None}
    """
    SCORE_FLOOR = 55
    MAX_PER_TYPE = 2
    MAX_TOTAL = 5

    try:
        # 1. Fetch candidates
        if category_id and category_id != "unknown":
            candidates = search_by_category(category_id, limit=15)
        else:
            candidates = search_registry(task_type, limit=10)

        # 2. Filter already-installed MCPs
        installed_mcps: set = set()
        if stack_profile:
            for srv in stack_profile.get("mcp_servers", []):
                installed_mcps.add(srv.lower())
        if installed_mcps:
            from interceptor import normalize_tool_name_for_matching
            candidates = [
                c for c in candidates
                if normalize_tool_name_for_matching(c.get("id", "")) not in installed_mcps
            ]

        if not candidates:
            return {"all": [], "top_pick": None}

        # 3. Build stack context hint
        stack_hint = ""
        if stack_profile:
            terms = stack_profile.get("languages", []) + stack_profile.get("frameworks", [])
            if terms:
                stack_hint = "\nDeveloper stack: " + ", ".join(terms[:6])

        context_line = f"\nTask context: \"{(context_snippet or '')[:200]}\""
        if stack_hint:
            context_line += stack_hint

        registry_formatted = [
            {"id": c["id"], "desc": c.get("description", "")[:200]}
            for c in candidates
        ]

        user_content = f"""Task type: {task_type}{context_line}

Available tools:
{json.dumps(registry_formatted, indent=2)}

Rank these tools for this {task_type} task."""

        config = load_config()
        llm = get_client(config)
        effective_model = model or ranker_model(config) or "claude-haiku-4-5-20251001"

        text = llm.complete(
            system=RECOMMEND_SYSTEM_PROMPT,
            user=user_content,
            model=effective_model,
            max_tokens=600,
        )
        if not text:
            return {"all": [], "top_pick": None}

        parsed = json.loads(text)
        all_tools = parsed.get("all", [])

        # 4. Apply score floor
        all_tools = [t for t in all_tools if int(t.get("score", 0)) >= SCORE_FLOOR]
        if not all_tools:
            return {"all": [], "top_pick": None}

        # 5. Sort by preferred_type first, then score descending
        def _type_of(name: str) -> str:
            if name.startswith("plugin:"):
                return "plugin"
            if name.startswith("mcp:"):
                return "mcp"
            return "skill"

        if preferred_type:
            all_tools.sort(key=lambda t: (
                0 if _type_of(t.get("name", "")) == preferred_type else 1,
                -t.get("score", 0)
            ))
        else:
            all_tools.sort(key=lambda t: -t.get("score", 0))

        # 6. Diversity cap: max MAX_PER_TYPE per type, MAX_TOTAL total
        type_counts: dict = {}
        trimmed = []
        for t in all_tools:
            ttype = _type_of(t.get("name", ""))
            if type_counts.get(ttype, 0) < MAX_PER_TYPE:
                type_counts[ttype] = type_counts.get(ttype, 0) + 1
                trimmed.append(t)
            if len(trimmed) >= MAX_TOTAL:
                break
        all_tools = trimmed

        # 7. Derive install_url for skills
        for item in all_tools:
            name = item.get("name", "")
            if "@" in name and "/" in name and "install_url" not in item:
                item["install_url"] = f"https://github.com/{name.split('@')[0]}"

        top_pick = all_tools[0] if all_tools else None
        return {"all": all_tools, "top_pick": top_pick}

    except Exception:
        return {"all": [], "top_pick": None}
```

- [ ] **Step 2.4: Run tests to confirm they pass**

```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_evaluator.py::TestRecommendTools -v
```

Expected: 6 PASSED

- [ ] **Step 2.5: Run full evaluator suite**

```bash
python3 -m pytest test_evaluator.py -v
```

Expected: all tests PASSED (was 56, now 62)

- [ ] **Step 2.6: Commit**

```bash
cd /home/visionairy/Dispatch
git add evaluator.py test_evaluator.py
git commit -m "feat(evaluator): add recommend_tools() for proactive stage 3 recommendations"
```

---

## Chunk 3: dispatch.sh — Stage 3 proactive output

### Task 3: Add Stage 3 to dispatch.sh

**Files:**
- Modify: `dispatch.sh` (add Stage 3 block before final `exit 0`, around line 448)

**Design notes:**
- Stage 3 fires only when `CATEGORY != LAST_RECOMMENDED_CATEGORY` (Option A — once per category per session)
- BYOK path: calls `recommend_tools()` via inline Python
- Hosted-only path: calls `/rank` with `cc_tool=""` (server handles null cc_tool, cc_score ignored)
- Output to stdout (CC injects into context)
- 4-second total timeout on Stage 3 to stay within hook budget

- [ ] **Step 3.1: Read last_recommended_category and extract preferred_tool_type**

Add these two blocks immediately after the `CATEGORY` is set (after line 367 in dispatch.sh, inside the existing flow, before the state write):

```bash
# ── Read last recommended category (for once-per-category gate) ──────────
LAST_RECOMMENDED_CATEGORY=$(python3 -c "
import sys, json
sys.path.insert(0, sys.argv[1])
from interceptor import get_last_recommended_category
print(get_last_recommended_category())
" "$SKILL_ROUTER_DIR" 2>/dev/null || echo "")

# ── Extract preferred tool type from classifier output ────────────────────
PREFERRED_TOOL_TYPE=$(python3 -c "
import json, sys
print(json.loads(sys.argv[1]).get('preferred_tool_type', '') or '')
" "$CLASSIFICATION" 2>/dev/null || echo "")
```

- [ ] **Step 3.2: Add Stage 3 block after the stack rescan (after line ~447, before `exit 0`)**

```bash
# ── Stage 3: Proactive recommendations ────────────────────────────────────
# Fires only when category changes (once-per-category-per-session gate).
# Outputs ranked tools to stdout — CC injects before formulating response.
if [ "$CATEGORY" != "unknown" ] && [ "$CATEGORY" != "$LAST_RECOMMENDED_CATEGORY" ]; then
    STAGE3_OUTPUT=$(python3 -c "
import sys, json, signal
sys.path.insert(0, sys.argv[1])

task_type      = sys.argv[2]
category_id    = sys.argv[3]
context_snippet = sys.argv[4]
preferred_type = sys.argv[5] if len(sys.argv) > 5 else ''

# Hard 4-second timeout — hook budget is 10s total
def _timeout_handler(signum, frame):
    raise TimeoutError('stage3 timeout')

signal.signal(signal.SIGALRM, _timeout_handler)
signal.alarm(4)

try:
    from evaluator import recommend_tools

    # Build stack_profile from last_cwd
    stack_profile = {}
    try:
        from interceptor import STATE_FILE
        cwd = json.load(open(STATE_FILE)).get('last_cwd', '')
        if cwd:
            from stack_scanner import get_stack_profile
            stack_profile = get_stack_profile(cwd) or {}
    except Exception:
        pass

    result = recommend_tools(
        task_type=task_type,
        context_snippet=context_snippet,
        category_id=category_id,
        stack_profile=stack_profile,
        preferred_type=preferred_type or None,
    )

    signal.alarm(0)

    tools = result.get('all', [])
    if not tools:
        print('')
        sys.exit(0)

    # Format output — northstar spec
    lines = [f'[Dispatch] Better tools available for this {task_type} task:']
    for t in tools:
        name  = t.get('name', '')
        score = t.get('score', 0)
        reason = (t.get('reason', '') or '')[:120].rstrip('.')
        install_cmd = t.get('install_cmd', '')

        # Derive type label
        if name.startswith('plugin:'):
            ttype = 'plugin'
            display = name.split(':')[-1]
        elif name.startswith('mcp:'):
            ttype = 'MCP'
            display = name[4:]
        else:
            ttype = 'skill'
            display = name

        line = f'• {display} [{ttype}] — {reason}.'
        lines.append(line)
        if install_cmd:
            lines.append(f'  Install: {install_cmd}')

    print('\n'.join(lines))

except TimeoutError:
    print('')
except Exception:
    print('')
" "$SKILL_ROUTER_DIR" "$TASK_TYPE" "$CATEGORY" "$CONTEXT_SNIPPET" "$PREFERRED_TOOL_TYPE" 2>/dev/null || echo "")

    # Only emit and update state if we got actual output
    if [ -n "$STAGE3_OUTPUT" ] && [ "$STAGE3_OUTPUT" != "" ]; then
        echo "$STAGE3_OUTPUT"
        # Write last_recommended_category so we don't repeat for this topic
        python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
from interceptor import write_last_recommended_category
write_last_recommended_category(sys.argv[2])
" "$SKILL_ROUTER_DIR" "$CATEGORY" 2>/dev/null || true
    fi
fi
```

- [ ] **Step 3.3: Update first-run message to reflect proactive mode**

Change line 72 in dispatch.sh from:

```bash
    echo "[Dispatch is active and monitoring your session. It will surface better tools when it detects a task shift. No action needed — it runs silently in the background.]"
```

To:

```bash
    echo "[Dispatch is active. When you start a new type of task, it will suggest better skills, MCPs, or plugins — right here in context. No action needed.]"
```

- [ ] **Step 3.4: Sync to installed location**

```bash
cp /home/visionairy/Dispatch/dispatch.sh ~/.claude/hooks/skill-router.sh
cp /home/visionairy/Dispatch/interceptor.py \
   /home/visionairy/Dispatch/evaluator.py \
   ~/.claude/dispatch/
```

- [ ] **Step 3.5: Run full test suite to confirm nothing is broken**

```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_classifier.py test_evaluator.py test_interceptor.py test_category_mapper.py test_llm_client.py test_stack_scanner.py -v
```

Expected: all tests pass (was 205 total, now ~213)

- [ ] **Step 3.6: Commit**

```bash
cd /home/visionairy/Dispatch
git add dispatch.sh
git commit -m "feat(dispatch): add Stage 3 proactive recommendations at task shift"
```

---

## Chunk 4: Integration verification

### Task 4: Verify the full pipeline works end-to-end

**Note:** Live e2e requires a new CC session. The steps below verify the logic in isolation first.

- [ ] **Step 4.1: Smoke-test recommend_tools() manually**

```bash
cd /home/visionairy/Dispatch
ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" python3 -c "
from evaluator import recommend_tools
import json
result = recommend_tools(
    task_type='postgres-query-building',
    context_snippet='user wants to optimize slow queries in their app',
    category_id='data-storage',
)
print(json.dumps(result, indent=2))
"
```

Expected: `all` list with 1-5 tools, each with name/score/reason. Top score > 55.

- [ ] **Step 4.2: Smoke-test state functions**

```bash
python3 -c "
from interceptor import get_last_recommended_category, write_last_recommended_category
print('before:', repr(get_last_recommended_category()))
write_last_recommended_category('data-storage')
print('after:', repr(get_last_recommended_category()))
"
```

Expected:
```
before: ''   (or whatever was last set)
after: 'data-storage'
```

- [ ] **Step 4.3: Smoke-test dispatch.sh Stage 3 output format**

Create a test input and pipe to the hook:

```bash
echo '{"prompt":"I need to optimize my postgres queries","transcript_path":"","cwd":"/tmp"}' \
  | ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" bash ~/.claude/hooks/skill-router.sh
```

Expected one of:
- Block starting with `[Dispatch] Better tools available for this...` with 1-5 bullet lines
- Empty output (if category matches last_recommended_category or no tools scored ≥ 55)
- Silent exit (if ANTHROPIC_API_KEY is not set)

- [ ] **Step 4.4: Update MEMORY.md test counts**

Update the test count entry in `/home/visionairy/.claude/projects/-home-visionairy-Dispatch/memory/MEMORY.md`:

```
- test_category_mapper.py: 30
- test_evaluator.py: 62   ← was 56 (+6 TestRecommendTools)
- test_interceptor.py: 66  ← was 62 (+4 TestLastRecommendedCategory)
- Client total: 213        ← was 205
```

- [ ] **Step 4.5: Final sync and full test run**

```bash
cp /home/visionairy/Dispatch/interceptor.py \
   /home/visionairy/Dispatch/evaluator.py \
   /home/visionairy/Dispatch/categories.json \
   /home/visionairy/Dispatch/taxonomy.json \
   /home/visionairy/Dispatch/stack_scanner.py \
   /home/visionairy/Dispatch/category_mapper.py \
   /home/visionairy/Dispatch/llm_client.py \
   /home/visionairy/Dispatch/classifier.py \
   ~/.claude/dispatch/
cp /home/visionairy/Dispatch/preuse_hook.sh ~/.claude/hooks/preuse-hook.sh
cp /home/visionairy/Dispatch/dispatch.sh ~/.claude/hooks/skill-router.sh

cd /home/visionairy/Dispatch
python3 -m pytest test_classifier.py test_evaluator.py test_interceptor.py test_category_mapper.py test_llm_client.py test_stack_scanner.py -v --tb=short
```

Expected: 213 tests passing, 0 failures.

- [ ] **Step 4.6: Commit**

```bash
cd /home/visionairy/Dispatch
git add .
git commit -m "chore: sync installed hooks and update memory test counts"
```

---

## Known Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Stage 3 LLM call adds 2-3s latency to hook | 4s `signal.alarm` hard timeout — Stage 3 silently exits on timeout |
| signal.alarm not available on non-POSIX systems | Wrapped in try/except; Windows users see silent skip (POSIX only for now) |
| Hosted-only user (no ANTHROPIC_API_KEY) — BYOK path skipped | Hosted-only users call `/rank` with cc_tool="" — handled in preuse_hook.sh path; for dispatch.sh Stage 3, they'll see no output until server-side `/recommend` endpoint is added in V2 |
| glama.ai has no cache → first call hits network | Existing `_search_glama` has no cache; if it's slow, signal.alarm will kill Stage 3 silently. Add cache in V2. |
| Same category fires every session start | `last_recommended_category` persists in state.json across sessions — won't re-fire for same category until user hits a new one |
| Descriptions contain quotes → JSON formatting issue in output | `reason[:120]` truncation + `.rstrip('.')` handles most cases; malformed JSON from LLM caught by outer `except Exception` |
