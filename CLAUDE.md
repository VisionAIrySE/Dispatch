# Dispatch — Claude Code Configuration

**Project:** Dispatch — Runtime skill router for Claude Code
**Repo:** github.com/VisionAIrySE/Dispatch
**Stack:** Python 3.8+ · Bash · Claude Haiku API

---

## Architecture

Two-stage UserPromptSubmit hook:

**Stage 1 — classifier.py** (every message, ~100ms)
- Haiku call with last 3 transcript messages + cwd
- Returns `{"shift": bool, "task_type": str, "confidence": float}`
- Exits silently if no shift or confidence < 0.7
- Task type is open-ended (not a fixed list) — Haiku generates the most specific label it can

**Stage 2 — evaluator.py** (on confirmed shift only)
- Scans `~/.claude/plugins/marketplaces/` for installed plugins
- Runs `npx skills list -g` for installed agent skills
- Runs `npx skills find <primary_term>` for registry search
- Haiku ranks all results by relevance, returns top 4 installed + top 3 suggested

**dispatch.sh** — orchestrates Stage 1 + 2, renders UI, updates state.json

---

## Key Files

| File | Purpose |
|------|---------|
| `classifier.py` | Haiku shift detection + task classification |
| `evaluator.py` | Plugin inventory + Haiku ranking |
| `dispatch.sh` | Main hook — orchestrates everything |
| `install.sh` | Copies files, registers hook in settings.json |
| `test_classifier.py` | 9 unit tests for classifier |
| `test_evaluator.py` | 11 unit tests for evaluator |

**Installed location:** `~/.claude/skill-router/` (classifier.py, evaluator.py)
**Hook location:** `~/.claude/hooks/skill-router.sh`
**State:** `~/.claude/skill-router/state.json`

---

## Critical Patterns

**Haiku returns markdown-wrapped JSON** — Always strip code blocks before `json.loads()`:
```python
text = response.content[0].text.strip()
if text.startswith("```"):
    text = text.split("```")[1]
    if text.startswith("json"):
        text = text[4:]
return json.loads(text.strip())
```

**Hook timeout is 10 seconds total** — Budget carefully:
- Stage 1 (Haiku): ~500ms
- Stage 2 (npx + Haiku): ~3-5s
- UI wait: 3s
- npx timeout set to 6s, not 20s

**Compound task types** — Classifier may return `docker-aws-github-actions`. Registry search uses only the primary term (`docker`) via `.split("-")[0]`.

**Broad exception catches are intentional** — Hook must never block Claude. Every function returns a safe default on failure.

**Task type is open-ended** — Haiku generates descriptive labels like `react-native`, `langchain`, `github-actions`. Not a fixed list. New skills in the registry are auto-discoverable.

**TASK_TYPE passed as argv, not interpolated** — Prevents shell injection. Always use `sys.argv[n]` in inline Python, never `'$TASK_TYPE'`.

---

## Testing

```bash
cd ~/.claude/skill-router
python3 -m pytest test_classifier.py test_evaluator.py -v
```

All 20 tests must pass before pushing.

**Live test:** Requires a new CC session. Cannot simulate UserPromptSubmit from inside a session.

**Manual classifier test:**
```bash
ANTHROPIC_API_KEY=sk-ant-... python3 classifier.py \
  --transcript /path/to/transcript.jsonl \
  --cwd /your/project \
  --last-task-type firebase
```

---

## Install / Sync

After editing source files, sync to installed location:
```bash
cp classifier.py evaluator.py ~/.claude/skill-router/
cp dispatch.sh ~/.claude/hooks/skill-router.sh
```

install.sh handles this automatically for fresh installs.

---

## Known Issues / History

- **2026-03-05:** Haiku markdown wrapping bug — fixed in classifier.py and evaluator.py
- **2026-03-05:** Compound task types broke registry search — fixed with primary term split
- **2026-03-05:** Double-wait bug (6s instead of 3s) — fixed in dispatch.sh
- **2026-03-05:** Shell injection via TASK_TYPE — fixed with argv passing
- **2026-03-05:** Open-ended taxonomy — removed fixed task type list, Haiku now generates labels freely

---

## Roadmap

- [ ] End-to-end live session testing + screen recording for promotion
- [ ] Caching layer for plugin registry (reduce npx latency)
- [ ] `/dispatch status` command
- [ ] V2: Hosted classifier endpoint (no API key required, $9/month)
- [ ] V2: skills.sh distribution
