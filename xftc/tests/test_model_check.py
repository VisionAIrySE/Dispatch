import pytest


class TestModelCheck:
    def test_haiku_passes_silently(self):
        from xftc.checks.model_check import check_subagent_model
        result = check_subagent_model({"model": "claude-haiku-4-5-20251001", "prompt": "search for files"})
        assert result is None

    def test_opus_triggers_block(self):
        from xftc.checks.model_check import check_subagent_model
        result = check_subagent_model({"model": "claude-opus-4-6", "prompt": "analyze architecture"})
        assert result is not None
        model, action = result
        assert action == "block"
        assert "opus" in model.lower()

    def test_sonnet_on_lightweight_task_triggers_warn(self):
        from xftc.checks.model_check import check_subagent_model
        result = check_subagent_model({"model": "claude-sonnet-4-6", "prompt": "search for the config file"})
        assert result is not None
        model, action = result
        assert action == "warn"

    def test_sonnet_on_heavy_task_passes(self):
        from xftc.checks.model_check import check_subagent_model
        result = check_subagent_model({"model": "claude-sonnet-4-6", "prompt": "implement the auth module"})
        assert result is None

    def test_unspecified_model_triggers_nudge(self):
        from xftc.checks.model_check import check_subagent_model
        result = check_subagent_model({"prompt": "do something"})
        assert result is not None
        model, action = result
        assert action == "nudge"

    def test_opus_short_form_triggers_block(self):
        from xftc.checks.model_check import check_subagent_model
        result = check_subagent_model({"model": "opus", "prompt": "review code"})
        assert result is not None
        _, action = result
        assert action == "block"

    def test_lightweight_keywords_match(self):
        from xftc.checks.model_check import check_subagent_model
        for kw in ["search", "find", "list", "format", "summarize", "check"]:
            result = check_subagent_model({"model": "claude-sonnet-4-6", "prompt": f"please {kw} things"})
            assert result is not None, f"Expected warn for keyword '{kw}'"
            _, action = result
            assert action == "warn"
