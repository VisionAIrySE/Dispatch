import json
import os
import tempfile
import time
import unittest


def _make_dir(files: dict) -> str:
    """Create a temp dir with the given filename→content mapping. Returns path."""
    d = tempfile.mkdtemp()
    for name, content in files.items():
        path = os.path.join(d, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
    return d


class TestDetectStack(unittest.TestCase):
    def test_detect_stack_returns_empty_on_nonexistent_dir(self):
        from stack_scanner import detect_stack
        result = detect_stack("/nonexistent/path/that/does/not/exist")
        assert result["languages"] == []
        assert result["frameworks"] == []
        assert result["tools"] == []

    def test_detect_stack_finds_package_json(self):
        from stack_scanner import detect_stack
        d = _make_dir({"package.json": '{"name": "test", "dependencies": {}}'})
        result = detect_stack(d)
        assert "javascript" in result["languages"]

    def test_detect_stack_finds_requirements_txt(self):
        from stack_scanner import detect_stack
        d = _make_dir({"requirements.txt": "requests==2.28.0\n"})
        result = detect_stack(d)
        assert "python" in result["languages"]

    def test_detect_stack_finds_go_mod(self):
        from stack_scanner import detect_stack
        d = _make_dir({"go.mod": "module example.com/myapp\n\ngo 1.21\n"})
        result = detect_stack(d)
        assert "go" in result["languages"]

    def test_detect_stack_finds_cargo_toml(self):
        from stack_scanner import detect_stack
        d = _make_dir({"Cargo.toml": '[package]\nname = "myapp"\nversion = "0.1.0"\n'})
        result = detect_stack(d)
        assert "rust" in result["languages"]

    def test_detect_stack_includes_cwd_and_scanned_at(self):
        from stack_scanner import detect_stack
        d = _make_dir({"go.mod": "module x\n"})
        result = detect_stack(d)
        assert result["cwd"] == d
        assert "scanned_at" in result


class TestDetectJsFrameworks(unittest.TestCase):
    def test_detect_js_frameworks_react(self):
        from stack_scanner import _detect_js_frameworks
        pkg = json.dumps({"dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}})
        d = _make_dir({"package.json": pkg})
        result = _detect_js_frameworks(os.path.join(d, "package.json"))
        assert "react" in result

    def test_detect_js_frameworks_next(self):
        from stack_scanner import _detect_js_frameworks
        pkg = json.dumps({"dependencies": {"next": "^14.0.0"}})
        d = _make_dir({"package.json": pkg})
        result = _detect_js_frameworks(os.path.join(d, "package.json"))
        assert "next" in result

    def test_detect_js_frameworks_returns_empty_on_bad_json(self):
        from stack_scanner import _detect_js_frameworks
        d = _make_dir({"package.json": "not valid json {{{"})
        result = _detect_js_frameworks(os.path.join(d, "package.json"))
        assert result == []


class TestDetectPythonFrameworks(unittest.TestCase):
    def test_detect_python_frameworks_fastapi(self):
        from stack_scanner import _detect_python_frameworks
        d = _make_dir({"requirements.txt": "fastapi==0.110.0\nuvicorn==0.29.0\n"})
        result = _detect_python_frameworks(os.path.join(d, "requirements.txt"))
        assert "fastapi" in result


class TestDetectTools(unittest.TestCase):
    def test_detect_tools_dockerfile(self):
        from stack_scanner import _detect_tools
        d = _make_dir({"Dockerfile": "FROM python:3.12\n"})
        result = _detect_tools(d)
        assert "docker" in result

    def test_detect_tools_github_actions(self):
        from stack_scanner import _detect_tools
        d = _make_dir({".github/workflows/ci.yml": "on: push\n"})
        result = _detect_tools(d)
        assert "github-actions" in result


class TestShouldRescan(unittest.TestCase):
    def test_should_rescan_different_cwd(self):
        from stack_scanner import should_rescan
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump({"cwd": "/project-a", "scanned_at": "2026-03-14T12:00:00"}, f)
            path = f.name
        try:
            assert should_rescan("/project-b", stack_file=path) is True
        finally:
            os.unlink(path)

    def test_should_rescan_same_cwd_fresh(self):
        from stack_scanner import should_rescan
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump({"cwd": "/project-a", "scanned_at": "2099-01-01T00:00:00"}, f)
            path = f.name
        try:
            assert should_rescan("/project-a", stack_file=path) is False
        finally:
            os.unlink(path)


class TestScanAndSave(unittest.TestCase):
    def test_scan_and_save_writes_file(self):
        from stack_scanner import scan_and_save
        project_dir = _make_dir({"requirements.txt": "django==4.2\n"})
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            stack_path = f.name
        os.unlink(stack_path)  # let scan_and_save create it
        try:
            profile = scan_and_save(project_dir, stack_file=stack_path)
            assert os.path.exists(stack_path)
            with open(stack_path) as f:
                saved = json.load(f)
            assert saved["cwd"] == project_dir
            assert "python" in saved["languages"]
        finally:
            if os.path.exists(stack_path):
                os.unlink(stack_path)


if __name__ == "__main__":
    unittest.main()
