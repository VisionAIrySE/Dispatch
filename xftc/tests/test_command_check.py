import pytest


class TestCommandCheck:
    def test_clean_git_log_passes(self):
        from xftc.checks.command_check import check_verbose_command
        assert check_verbose_command("git log --oneline -20") is None

    def test_bare_git_log_triggers(self):
        from xftc.checks.command_check import check_verbose_command
        result = check_verbose_command("git log")
        assert result is not None
        _, issue, suggestion = result
        assert "--oneline" in suggestion

    def test_find_without_maxdepth_triggers(self):
        from xftc.checks.command_check import check_verbose_command
        result = check_verbose_command("find . -name '*.py'")
        assert result is not None
        _, issue, suggestion = result
        assert "maxdepth" in suggestion

    def test_find_with_maxdepth_passes(self):
        from xftc.checks.command_check import check_verbose_command
        assert check_verbose_command("find . -maxdepth 2 -name '*.py'") is None

    def test_cat_command_triggers(self):
        from xftc.checks.command_check import check_verbose_command
        result = check_verbose_command("cat somefile.txt")
        assert result is not None

    def test_npm_install_without_silent_triggers(self):
        from xftc.checks.command_check import check_verbose_command
        result = check_verbose_command("npm install")
        assert result is not None
        _, issue, suggestion = result
        assert "--silent" in suggestion

    def test_npm_install_with_silent_passes(self):
        from xftc.checks.command_check import check_verbose_command
        assert check_verbose_command("npm install --silent") is None

    def test_ls_la_triggers(self):
        from xftc.checks.command_check import check_verbose_command
        result = check_verbose_command("ls -la")
        assert result is not None

    def test_plain_ls_passes(self):
        from xftc.checks.command_check import check_verbose_command
        assert check_verbose_command("ls") is None

    def test_git_status_passes(self):
        from xftc.checks.command_check import check_verbose_command
        assert check_verbose_command("git status") is None

    def test_pip_install_without_quiet_triggers(self):
        from xftc.checks.command_check import check_verbose_command
        result = check_verbose_command("pip install requests")
        assert result is not None
        _, issue, suggestion = result
        assert "-q" in suggestion or "quiet" in suggestion

    def test_pip_install_with_quiet_passes(self):
        from xftc.checks.command_check import check_verbose_command
        assert check_verbose_command("pip install -q requests") is None
