# Classifier Action Mode Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the Dispatch classifier to detect action mode shifts (building→fixing, designing→building) in addition to domain shifts, so Dispatch fires whenever a different tool would help — not just when the topic changes.

**Architecture:** Replace the single-question SYSTEM_PROMPT with a 7-mode taxonomy prompt. Add `domain` and `mode` fields to classifier output alongside the existing `task_type` (now `{domain}-{mode}`). All existing consumers read `task_type` only — backward compatible.

**Tech Stack:** Python 3.8+, anthropic SDK, unittest/mock, classifier.py (client + server copies)

**Design doc:** `docs/plans/2026-03-06-classifier-action-mode-redesign.md`

---

## Pre-flight checks

Before starting, confirm you are on the `ui-experiments` branch:
```bash
cd /home/visionairy/Dispatch
git branch   # should show * ui-experiments
```

Confirm all current tests pass:
```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_classifier.py test_evaluator.py -v
# Must be 20/20 before touching anything
```

---

### Task 1: Update test fixtures to new output shape

The existing mock tests return the old 3-field shape. Update them to return the new 5-field shape before changing the implementation — so tests fail for the right reason.

**Files:**
- Modify: `test_classifier.py`

**Step 1: Update `test_returns_structured_result_on_shift` mock return value**

Find this block in `test_classifier.py` (line ~94):
```python
mock_client.messages.create.return_value = MagicMock(
    content=[MagicMock(text=json.dumps({
        "shift": True,
        "task_type": "flutter",
        "confidence": 0.92
    }))]
)
```

Replace with:
```python
mock_client.messages.create.return_value = MagicMock(
    content=[MagicMock(text=json.dumps({
        "shift": True,
        "domain": "flutter",
        "mode": "building",
        "task_type": "flutter-building",
        "confidence": 0.92
    }))]
)
```

Also update the assertions below it:
```python
assert result["shift"] is True
assert result["domain"] == "flutter"
assert result["mode"] == "building"
assert result["task_type"] == "flutter-building"
assert result["confidence"] == 0.92
```

**Step 2: Update `test_returns_no_shift_on_continuation` mock return value**

Find the mock return value (line ~114):
```python
mock_client.messages.create.return_value = MagicMock(
    content=[MagicMock(text=json.dumps({
        "shift": False,
        "task_type": "flutter",
        "confidence": 0.95
    }))]
)
```

Replace with:
```python
mock_client.messages.create.return_value = MagicMock(
    content=[MagicMock(text=json.dumps({
        "shift": False,
        "domain": "flutter",
        "mode": "building",
        "task_type": "flutter-building",
        "confidence": 0.95
    }))]
)
```

**Step 3: Run tests — expect failures**

```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_classifier.py -v
```

Expected: `test_returns_structured_result_on_shift` FAILS (old assertions). Everything else passes. If more than 1 test fails, stop and investigate before continuing.

**Step 4: Commit**
```bash
git add test_classifier.py
git commit -m "test: update classifier fixtures to new 5-field output shape"
```

---

### Task 2: Add new tests for action mode behavior

Add tests that validate intra-domain mode shifts — the core new behavior. These tests will fail until the implementation is updated.

**Files:**
- Modify: `test_classifier.py` — add to the `TestClassifyTopicShift` class

**Step 1: Add intra-domain mode shift test**

Append to `TestClassifyTopicShift` class (after `test_handles_malformed_response_gracefully`):

```python
@patch('classifier.anthropic.Anthropic')
def test_intra_domain_mode_shift_triggers_shift(self, mock_client_cls):
    """Same domain (flutter), different mode (building→fixing) must trigger shift=True."""
    mock_client = MagicMock()
    mock_client_cls.return_value = mock_client
    mock_client.messages.create.return_value = MagicMock(
        content=[MagicMock(text=json.dumps({
            "shift": True,
            "domain": "flutter",
            "mode": "fixing",
            "task_type": "flutter-fixing",
            "confidence": 0.88
        }))]
    )
    result = classify_topic_shift(
        messages=["the widget crashes with a null pointer", "why is this blowing up"],
        cwd="/home/visionairy/SNAP-app",
        last_task_type="flutter-building"
    )
    assert result["shift"] is True
    assert result["domain"] == "flutter"
    assert result["mode"] == "fixing"
    assert result["task_type"] == "flutter-fixing"

@patch('classifier.anthropic.Anthropic')
def test_same_domain_same_mode_is_not_shift(self, mock_client_cls):
    """Same domain, same mode, follow-up question — must NOT be a shift."""
    mock_client = MagicMock()
    mock_client_cls.return_value = mock_client
    mock_client.messages.create.return_value = MagicMock(
        content=[MagicMock(text=json.dumps({
            "shift": False,
            "domain": "flutter",
            "mode": "fixing",
            "task_type": "flutter-fixing",
            "confidence": 0.95
        }))]
    )
    result = classify_topic_shift(
        messages=["the widget crashes", "try checking the null", "still getting the same error"],
        cwd="/home/visionairy/SNAP-app",
        last_task_type="flutter-fixing"
    )
    assert result["shift"] is False

@patch('classifier.anthropic.Anthropic')
def test_mode_field_is_valid_enum_value(self, mock_client_cls):
    """Mode field must be one of the 7 valid values."""
    mock_client = MagicMock()
    mock_client_cls.return_value = mock_client
    mock_client.messages.create.return_value = MagicMock(
        content=[MagicMock(text=json.dumps({
            "shift": True,
            "domain": "supabase",
            "mode": "designing",
            "task_type": "supabase-designing",
            "confidence": 0.81
        }))]
    )
    valid_modes = {"discovering", "designing", "building", "fixing",
                   "validating", "shipping", "maintaining"}
    result = classify_topic_shift(
        messages=["how should I structure the schema for this?"],
        cwd="/home/visionairy/StockerAI",
        last_task_type="supabase-building"
    )
    assert result["mode"] in valid_modes

@patch('classifier.anthropic.Anthropic')
def test_malformed_response_returns_safe_default(self, mock_client_cls):
    """Malformed response must return safe defaults with all 5 fields."""
    mock_client = MagicMock()
    mock_client_cls.return_value = mock_client
    mock_client.messages.create.return_value = MagicMock(
        content=[MagicMock(text="not json at all")]
    )
    result = classify_topic_shift(
        messages=["something"],
        cwd="/home/visionairy",
        last_task_type=None
    )
    assert result["shift"] is False
    assert result["domain"] == "general"
    assert result["mode"] == "building"
    assert result["task_type"] == "general"
    assert result["confidence"] == 0.0
```

**Step 2: Run new tests — expect failures**

```bash
python3 -m pytest test_classifier.py::TestClassifyTopicShift -v
```

Expected: new tests pass (they're mocked), but `test_handles_malformed_response_gracefully` may conflict with the new `test_malformed_response_returns_safe_default`. Delete the old `test_handles_malformed_response_gracefully` test (lines ~127-141) since the new one replaces it.

**Step 3: Run all classifier tests**

```bash
python3 -m pytest test_classifier.py -v
```

Expected: all classifier tests pass (all mocked — implementation not changed yet).

**Step 4: Commit**
```bash
git add test_classifier.py
git commit -m "test: add action mode shift tests — intra-domain, enum validation, safe defaults"
```

---

### Task 3: Rewrite SYSTEM_PROMPT and update classifier output

Now update the implementation to match what the tests expect.

**Files:**
- Modify: `classifier.py` (lines 5-23 for SYSTEM_PROMPT, lines 53-84 for `classify_topic_shift`)

**Step 1: Replace SYSTEM_PROMPT**

Replace the entire `SYSTEM_PROMPT` string (lines 5-23) with:

```python
VALID_MODES = {
    "discovering", "designing", "building", "fixing",
    "validating", "shipping", "maintaining"
}

SYSTEM_PROMPT = """You are an action-mode classifier for a developer tool that surfaces the right tools at the right time.

Given the last few messages in a conversation and the current working directory, determine:
1. Whether the developer has shifted to a different action mode OR a different domain
2. What domain they are working in (the technology, framework, or subject)
3. What action mode they are currently in
4. Your confidence level

ACTION MODES — pick exactly one:
- discovering  : researching, learning, exploring options, asking "what is" or "how does"
- designing    : planning, architecting, deciding approach, brainstorming before building
- building     : writing new code, creating, implementing, adding features
- fixing       : debugging, diagnosing errors, tracing failures, something is broken
- validating   : testing, reviewing, verifying correctness, checking work
- shipping     : deploying, releasing, publishing, going live, CI/CD pipelines
- maintaining  : refactoring, improving, cleaning up, restructuring existing code

A "shift" is true when EITHER:
- The domain changes (flutter → supabase)
- The action mode changes within the same domain (flutter building → flutter fixing)

Continuing, refining, or asking follow-up questions in the same domain and mode is NOT a shift.

Infer mode from natural developer language — not just keywords:
- "this blows up with a null" → fixing
- "let me sanity check this" → validating
- "it works but feels gross" → maintaining
- "how should I structure this?" → designing
- "write the auth middleware" → building
- "what is the best pattern for..." → discovering

The last_task_type provided is in "{domain}-{mode}" format (e.g., "flutter-building").
Use it to determine whether a shift has occurred.

Respond with ONLY valid JSON — no markdown, no explanation:
{"shift": true/false, "domain": "<technology>", "mode": "<mode>", "task_type": "<domain>-<mode>", "confidence": 0.0-1.0}

For domain: use the most specific label available (flutter, react, supabase, stripe, dispatch, postgres, etc.).
Use lowercase-hyphenated format. Use "general" if no clear domain.
For mode: must be exactly one of the 7 modes listed above.
"""
```

**Step 2: Update `classify_topic_shift` return and error handling**

Replace the `classify_topic_shift` function body (lines 58-84):

```python
def classify_topic_shift(messages: list, cwd: str, last_task_type: str = None, api_key: str = None) -> dict:
    """
    Call Haiku to classify whether an action mode or domain shift has occurred.
    Returns: {"shift": bool, "domain": str, "mode": str, "task_type": str, "confidence": float}
    """
    try:
        client = anthropic.Anthropic(api_key=api_key or os.environ.get("ANTHROPIC_API_KEY"))

        user_content = f"""Current directory: {cwd}
Last task type: {last_task_type or 'unknown'}

Recent messages:
{chr(10).join(f'- {m}' for m in messages)}

Has the developer shifted to a different action mode or domain?"""

        response = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=120,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_content}]
        )

        text = response.content[0].text.strip()
        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
        result = json.loads(text.strip())

        # Validate mode is a known value — default to "building" if unrecognised
        if result.get("mode") not in VALID_MODES:
            result["mode"] = "building"

        # Ensure task_type is always present even if Haiku omits it
        if "task_type" not in result or not result["task_type"]:
            domain = result.get("domain", "general")
            mode = result.get("mode", "building")
            result["task_type"] = f"{domain}-{mode}"

        return result

    except Exception:
        return {
            "shift": False,
            "domain": "general",
            "mode": "building",
            "task_type": "general",
            "confidence": 0.0
        }
```

**Step 3: Run all tests**

```bash
cd /home/visionairy/Dispatch
python3 -m pytest test_classifier.py test_evaluator.py -v
```

Expected: all tests pass. If any fail, read the error carefully — do not proceed until 20/20.

**Step 4: Commit**
```bash
git add classifier.py
git commit -m "feat: rewrite classifier to detect action mode shifts — 7-mode MECE taxonomy"
```

---

### Task 4: Sync to installed location and smoke test

The installed hook uses the copy at `~/.claude/skill-router/classifier.py`. Sync it and test in a live session.

**Files:**
- Runtime: `~/.claude/skill-router/classifier.py`
- Runtime: `~/.claude/hooks/skill-router.sh` (already updated in previous session)

**Step 1: Sync classifier to installed location**

```bash
cp /home/visionairy/Dispatch/classifier.py ~/.claude/skill-router/classifier.py
```

**Step 2: Start a new Claude Code session**

Hooks reload at session start — an existing session will not pick up the change.

**Step 3: Trigger a mode shift within the same domain**

In the new session, stay on one topic (e.g., Dispatch) but shift mode:
- Start: "Let's plan how to add a weekly digest email to Dispatch" (designing)
- Then: "Why is the /rank endpoint returning empty results?" (fixing)

Expected: Dispatch fires with mode visible in banner: `◎ Dispatch → Dispatch Fixing (high confidence)`

**Step 4: Confirm no regression on domain shift**

- Start: "Help me set up Supabase RLS policies" (supabase)
- Then: "Now let's work on the Flutter camera screen" (flutter)

Expected: Dispatch fires as before.

**Step 5: Commit**
```bash
cd /home/visionairy/Dispatch
git add classifier.py
git commit -m "chore: sync updated classifier — no code change, confirms installed copy matches"
```

---

### Task 5: Sync server-side copy (Dispatch-API)

The hosted `/classify` endpoint uses its own copy of `classifier.py` in the Dispatch-API repo.

**Files:**
- Modify: `/home/visionairy/Dispatch-API/classifier.py`

**Step 1: Verify the server copy is the same structure**

```bash
diff /home/visionairy/Dispatch/classifier.py /home/visionairy/Dispatch-API/classifier.py
```

Read the diff. If they diverged, note the differences before overwriting.

**Step 2: Copy updated classifier to API repo**

```bash
cp /home/visionairy/Dispatch/classifier.py /home/visionairy/Dispatch-API/classifier.py
```

**Step 3: Verify API repo still has no syntax errors**

```bash
cd /home/visionairy/Dispatch-API
python3 -c "import classifier; print('OK')"
```

Expected: prints `OK`.

**Step 4: Commit in API repo**

```bash
cd /home/visionairy/Dispatch-API
git add classifier.py
git commit -m "feat: sync action mode classifier — domain+mode detection, 7-mode MECE taxonomy"
```

**Step 5: Deploy to Render**

Push the API repo to trigger Render auto-deploy:
```bash
git push origin main
```

Verify deploy at https://dispatch.visionairy.biz/health — should return `{"status": "ok"}`.

**Step 6: Smoke test hosted mode**

With a Dispatch token configured (hosted mode), trigger the same mode-shift test as Task 4 Step 3 in a new CC session. Confirm the hosted endpoint returns the new 5-field response and the banner shows `{domain} {mode}` correctly.

---

### Task 6: Update README

**Files:**
- Modify: `README.md` — "How it works" section (lines ~154-165)

**Step 1: Update Stage 1 description**

Find:
```
**Stage 1 — Classification (every message, ~100ms)**

Haiku receives your last 3 messages and current working directory. Returns `{"shift": bool, "task_type": str, "confidence": float}`. If no shift or confidence below 0.7, exits silently — you never see it.
```

Replace with:
```
**Stage 1 — Classification (every message, ~100ms)**

Haiku receives your last 3 messages and current working directory. Detects two types of shifts:
- **Domain shift** — the technology or subject changed (Flutter → Supabase)
- **Mode shift** — what you're *doing* changed within the same domain (Flutter building → Flutter debugging)

Returns `{"shift": bool, "domain": str, "mode": str, "task_type": str, "confidence": float}`. If no shift or confidence below 0.7, exits silently — you never see it.
```

**Step 2: Commit**
```bash
cd /home/visionairy/Dispatch
git add README.md
git commit -m "docs: update How It Works to describe action mode detection"
```

---

### Task 7: Merge to main

Once all tasks pass and the live smoke test confirms correct behavior:

```bash
cd /home/visionairy/Dispatch
git checkout main
git merge ui-experiments
git push origin main
```

Verify Dispatch-API is already deployed (done in Task 5).

---

## Verification Checklist

Before declaring done:

- [ ] All `test_classifier.py` tests pass (check count — should be more than 12 now)
- [ ] All `test_evaluator.py` tests pass (unchanged — regression check)
- [ ] `flutter-building → flutter-fixing` triggers shift in live session
- [ ] Follow-up within same domain+mode does NOT trigger shift
- [ ] Terminal banner shows `Flutter Fixing` style label (not just `Flutter`)
- [ ] Hosted endpoint returns 5-field response
- [ ] README updated
- [ ] Both repos committed and pushed
