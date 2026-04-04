import os
from typing import Optional

COMPACT_THRESHOLD = 0.60

# CC context window in tokens; ~4 chars per token → 800k chars = 200k tokens
_CONTEXT_CHARS = 800_000

# Constant overhead for CC system prompt + tool schemas (not in transcript)
_SYSTEM_OVERHEAD_CHARS = 40_000


def estimate_context_fill(message_count: int, cwd: str,
                          transcript_path: Optional[str] = None) -> float:
    """
    Estimate context fill as a fraction [0.0, 1.0].
    Dynamic model: measures actual bytes from transcript + all auto-loaded files.
    Falls back to message_count proxy when transcript_path unavailable.
    """
    total_chars = _SYSTEM_OVERHEAD_CHARS

    # Transcript (actual conversation history)
    if transcript_path and os.path.exists(transcript_path):
        try:
            total_chars += os.path.getsize(transcript_path)
        except Exception:
            pass
    else:
        # Fallback proxy when transcript not available
        total_chars += message_count * 2_000  # ~500 tokens per exchange

    # All auto-loaded CLAUDE.md files
    claude_paths = [
        os.path.join(cwd, "CLAUDE.md"),
        os.path.expanduser("~/.claude/CLAUDE.md"),
        os.path.expanduser("~/CLAUDE.md"),
    ]
    for path in claude_paths:
        if os.path.exists(path):
            try:
                total_chars += os.path.getsize(path)
            except Exception:
                pass

    # Auto-loaded MEMORY.md for this project
    encoded = cwd.replace("/", "-")
    memory_md = os.path.expanduser(
        f"~/.claude/projects/{encoded}/memory/MEMORY.md"
    )
    if os.path.exists(memory_md):
        try:
            total_chars += os.path.getsize(memory_md)
        except Exception:
            pass

    return min(total_chars / _CONTEXT_CHARS, 1.0)


def should_compact(message_count: int, cwd: str,
                   transcript_path: Optional[str] = None) -> Optional[float]:
    """
    Returns estimated fill if compact is recommended (>= 60%), else None.
    """
    fill = estimate_context_fill(message_count, cwd, transcript_path)
    if fill >= COMPACT_THRESHOLD:
        return fill
    return None
