# /warm-start

Capture a complete project state snapshot so the next session starts with zero re-explanation.

## When to use

- Before ending a session where significant work was done
- When Russ says "warm start" or "update memory for warm start"
- When XFTC nudges about broken MEMORY.md links — fix them as part of this

## Steps

### 1. Establish actual build state

```bash
git log --oneline -15
git status
```

Note the last commit hash, current branch, and any untracked/staged files.

### 2. Run all test suites — capture counts

Run each test suite and record the pass count. If any fail, note it explicitly.

```bash
# From project root — adjust paths as needed
python3 -m pytest <suite-1> -q --tb=no 2>&1 | tail -3
python3 -m pytest <suite-2> -q --tb=no 2>&1 | tail -3
```

### 3. Audit MEMORY.md for broken links (with backup)

Find the memory directory for the current project:

```bash
python3 -c "
import os, re
cwd = os.getcwd()
encoded = cwd.replace('/', '-')
memory_dir = os.path.expanduser(f'~/.claude/projects/{encoded}/memory')
memory_md = os.path.join(memory_dir, 'MEMORY.md')
if not os.path.isfile(memory_md):
    print('No MEMORY.md found')
else:
    content = open(memory_md).read()
    links = re.findall(r'\[([^\]]+)\]\(([^)]+)\)', content)
    broken = [(t, p) for t, p in links
              if not p.startswith(('http', '#'))
              and not os.path.isfile(os.path.join(memory_dir, p))]
    print(f'Memory dir: {memory_dir}')
    print(f'Total links: {len(links)}')
    print(f'Broken links: {len(broken)}')
    for t, p in broken:
        print(f'  BROKEN: [{t}]({p})')
"
```

If broken links are found:
1. **Create backup first**: `cp MEMORY.md MEMORY.md.bak`
2. Remove each broken link line from MEMORY.md
3. Verify backup exists before saving

### 4. Write the session snapshot

Write a new file `project_<YYYY-MM-DD>-session<N>.md` in the memory directory:

```markdown
---
name: Warm Start <date> Session <N>
description: Full snapshot of <project> state — session <N>
type: project
---

# Warm Start — <date> (Session <N>)

## What Shipped (committed + passing)
- <bullet per feature merged this session>

## Bugs Fixed This Session
- <BUG-XXX: description + fix location>

## Test Counts
| Suite | Count |
|-------|-------|
| <suite name> | <N> |
| **Total** | **<N>** |

## Open / Untracked Work
- <untracked files and their purpose>
- <features started but not committed>

## Next Actions (priority order)
1. <highest priority>
2. <next>

## Key File Locations
- <changed or important files>
```

### 5. Update MEMORY.md START HERE section

Replace the existing `## ⚠️ START HERE` section with a new entry pointing to the snapshot just written:

```markdown
## ⚠️ START HERE — Warm Start <date> (Session <N> — most recent)
See [project_<date>-session<N>.md](project_<date>-session<N>.md) — full snapshot.

**Quick summary:**
- <3-4 bullet points of what matters most>
```

### 6. Commit CLAUDE.md if it changed

If CLAUDE.md was modified this session:

```bash
git add /home/visionairy/CLAUDE.md
git commit -m "docs: warm start memory <date>"
```

## Output format

After completing all steps, report:

```
Warm start complete.

Snapshot: project_<date>-session<N>.md
Tests: <total> passing
MEMORY.md: <N> broken links fixed (backup: MEMORY.md.bak)
Next: <top priority from snapshot>
```

If MEMORY.md had no broken links, omit that line.
