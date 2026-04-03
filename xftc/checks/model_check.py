from typing import Optional, Tuple

LIGHTWEIGHT_KEYWORDS = [
    "search", "find", "list", "format", "summarize", "check",
    "grep", "look", "scan", "read", "explore", "browse",
    "count", "inspect",
]


def check_subagent_model(tool_input: dict) -> Optional[Tuple[str, str]]:
    """
    Check if a sub-agent is using an expensive model.

    Returns (model_name, action) where action is one of:
      'block' — hard stop (Opus)
      'warn'  — soft stop (Sonnet on lightweight task)
      'nudge' — informational (unspecified model)

    Returns None if the model choice is fine (Haiku or Sonnet on heavy task).
    """
    model = tool_input.get("model", "")
    prompt = tool_input.get("prompt", "").lower()

    if not model:
        return ("unspecified", "nudge")

    model_lower = model.lower()

    if "opus" in model_lower:
        return (model, "block")

    if "sonnet" in model_lower:
        if any(kw in prompt for kw in LIGHTWEIGHT_KEYWORDS):
            return (model, "warn")

    return None
