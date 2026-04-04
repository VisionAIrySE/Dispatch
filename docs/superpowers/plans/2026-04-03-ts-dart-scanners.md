# TypeScript + Dart Scanner Support Implementation Plan


> **STATUS: COMPLETE** — All tasks shipped. scanner_typescript.py, scanner_dart.py, scanner_registry.py, flow_analyzer.py, and tests exist in both test-xfba/ and ~/.claude/xf-boundary-auditor/. Verified 2026-04-03.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add TypeScript (.ts/.tsx) and Dart (.dart) scanner support to XFBA/XSIA so contract checking works in LC-Access and Perimeter without any changes to the checker logic.

**Architecture:** The auditor has a clean scanner plugin system — `ScannerBase` defines the interface, `scanner_registry.py` holds the list. We add two new scanners (regex-based, no external deps), update the flow indexer to walk TS/Dart files, and fix the pre-edit-audit.sh extension filter. Everything downstream (checkers, cascade, repair, consent, xsi) works automatically because it operates on the index, not the source language.

**Tech Stack:** Python 3.8+, `re` stdlib only — no tree-sitter, no npm, no external deps. Tests use `pytest` and `tempfile`.

---

## Test Environment Setup

All work happens in `/home/visionairy/Dispatch/test-xfba/` — a full copy of the live auditor. The live auditor at `~/.claude/xf-boundary-auditor/` is untouched until Task 7 (sync).

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `test-xfba/` | Create (copy) | Isolated dev environment |
| `test-xfba/scanner_typescript.py` | Create | Regex scanner for `.ts` / `.tsx` |
| `test-xfba/scanner_dart.py` | Create | Regex scanner for `.dart` |
| `test-xfba/scanner_registry.py` | Modify | Register both new scanners |
| `test-xfba/flow_analyzer.py` | Modify | Index `.ts`/`.tsx`/`.dart` files |
| `test-xfba/tests/test_scanner_typescript.py` | Create | Unit tests for TS scanner |
| `test-xfba/tests/test_scanner_dart.py` | Create | Unit tests for Dart scanner |
| `~/.claude/hooks/pre-edit-audit.sh` | Modify | Add `.dart` to extension filter |
| `~/.claude/xf-boundary-auditor/` | Sync (Task 6) | Deploy when all tests pass |

---

## Task 0: Set Up Test Environment

**Files:**
- Create: `/home/visionairy/Dispatch/test-xfba/` (copy of live auditor)

- [x] **Step 1: Copy live auditor to test dir**

```bash
cp -r ~/.claude/xf-boundary-auditor/ /home/visionairy/Dispatch/test-xfba/
```

- [x] **Step 2: Verify the copy has all source files**

```bash
ls /home/visionairy/Dispatch/test-xfba/
```

Expected output includes: `auditor.py  checkers.py  flow_analyzer.py  scanner_base.py  scanner_bash.py  scanner_python.py  scanner_registry.py  tests/`

- [x] **Step 3: Run existing tests against the copy to establish baseline**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/ -v --tb=short 2>&1 | tail -20
```

Expected: all 71 tests pass. If any fail, stop — the copy is corrupted.

- [x] **Step 4: Commit the test dir to Dispatch repo**

```bash
cd /home/visionairy/Dispatch
git add test-xfba/
git commit -m "chore: add test-xfba isolated dev environment for TS/Dart scanner work"
```

---

## Task 1: TypeScript Scanner

**Files:**
- Create: `test-xfba/scanner_typescript.py`
- Create: `test-xfba/tests/test_scanner_typescript.py`

### What the TypeScript scanner must extract

| SymbolTable field | TypeScript source pattern |
|---|---|
| `exports` | `export function foo`, `export class Foo`, `export const foo =`, `export default` |
| `functions[name]` | n_required, n_total, has_varargs, is_stub, line |
| `from_imports` | `import { foo } from './mod'` |
| `imports` | module path from any import |
| `calls` | `foo(a, b)` → {symbol, line, n_args, kind:'name'} |
| `env_vars_hard` | `process.env.FOO` with no fallback |
| `env_vars_soft` | `process.env.FOO ?? x` or `process.env.FOO || x` |

**Function signature rules:**
- `b?: T` = optional → does not count toward n_required
- `b: T = expr` = has default → does not count toward n_required
- `...rest: T[]` = varargs → `has_varargs = True`
- Stub body = `{}` with only a comment, `throw new Error(...)`, or empty

- [x] **Step 1: Write the failing tests**

Create `test-xfba/tests/test_scanner_typescript.py`:

```python
import os, sys, tempfile, pytest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from scanner_typescript import TypeScriptScanner

def _write(src, suffix=".ts"):
    f = tempfile.NamedTemporaryFile(suffix=suffix, mode="w", delete=False, encoding="utf-8")
    f.write(src); f.close(); return f.name

def test_supports_ts():
    s = TypeScriptScanner()
    assert s.supports("foo.ts") and s.supports("bar.tsx")
    assert not s.supports("baz.py") and not s.supports("baz.dart")

def test_exports_function():
    st = TypeScriptScanner().scan(_write("export function greet(name: string): string { return name; }\n"))
    assert "greet" in st.exports

def test_exports_class():
    st = TypeScriptScanner().scan(_write("export class MyService {}\n"))
    assert "MyService" in st.exports

def test_exports_const():
    st = TypeScriptScanner().scan(_write("export const API_URL = 'https://example.com';\n"))
    assert "API_URL" in st.exports

def test_function_arity_required():
    st = TypeScriptScanner().scan(_write("export function add(a: number, b: number): number { return a + b; }\n"))
    fn = st.functions.get("add")
    assert fn and fn["n_required"] == 2 and fn["n_total"] == 2 and not fn["has_varargs"]

def test_function_optional_param():
    st = TypeScriptScanner().scan(_write("export function greet(name: string, greeting?: string): string { return name; }\n"))
    fn = st.functions.get("greet")
    assert fn["n_required"] == 1 and fn["n_total"] == 2

def test_function_default_param():
    st = TypeScriptScanner().scan(_write("export function greet(name: string, greeting: string = 'Hello'): string { return name; }\n"))
    fn = st.functions.get("greet")
    assert fn["n_required"] == 1 and fn["n_total"] == 2

def test_function_varargs():
    st = TypeScriptScanner().scan(_write("export function sum(...args: number[]): number { return 0; }\n"))
    assert st.functions.get("sum", {}).get("has_varargs")

def test_stub_throw():
    st = TypeScriptScanner().scan(_write("export function todo(a: string): string { throw new Error('not implemented'); }\n"))
    assert st.functions.get("todo", {}).get("is_stub")

def test_from_import():
    st = TypeScriptScanner().scan(_write("import { foo, bar } from './utils';\n"))
    names = [fi["name"] for fi in st.from_imports]
    assert "foo" in names and "bar" in names

def test_call_detection():
    st = TypeScriptScanner().scan(_write("const x = greet('Alice', 'Hi');\n"))
    call = next((c for c in st.calls if c["symbol"] == "greet"), None)
    assert call and call["n_args"] == 2

def test_env_var_hard():
    st = TypeScriptScanner().scan(_write("const key = process.env.API_KEY;\n"))
    assert any(e["var_name"] == "API_KEY" for e in st.env_vars_hard)

def test_env_var_soft_nullish():
    st = TypeScriptScanner().scan(_write("const key = process.env.API_KEY ?? 'default';\n"))
    assert any(e["var_name"] == "API_KEY" for e in st.env_vars_soft)

def test_env_var_soft_or():
    st = TypeScriptScanner().scan(_write("const key = process.env.API_KEY || 'default';\n"))
    assert any(e["var_name"] == "API_KEY" for e in st.env_vars_soft)

def test_tsx_supported():
    st = TypeScriptScanner().scan(_write("export function MyComponent(): JSX.Element { return null; }\n", suffix=".tsx"))
    assert "MyComponent" in st.exports

def test_registry_scans_ts_file():
    from scanner_registry import scan_file
    st = scan_file(_write("export function hello(name: string): string { return name; }\n"))
    assert st is not None and "hello" in st.exports
```

- [x] **Step 2: Run tests to confirm they all fail**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/test_scanner_typescript.py -v 2>&1 | head -20
```

Expected: `ImportError: No module named 'scanner_typescript'`

- [x] **Step 3: Implement `test-xfba/scanner_typescript.py`**

```python
from __future__ import annotations
import os, re
from typing import Optional
from scanner_base import ScannerBase, SymbolTable

_IMPORT_NAMED_RE = re.compile(r'import\s+(?:type\s+)?\{([^}]+)\}\s+from\s+[\'"]([^\'"]+)[\'"]')
_IMPORT_DEFAULT_RE = re.compile(r'import\s+(\w+)\s+from\s+[\'"]([^\'"]+)[\'"]')
_IMPORT_STAR_RE = re.compile(r'import\s+\*\s+as\s+(\w+)\s+from\s+[\'"]([^\'"]+)[\'"]')
_EXPORT_FUNCTION_RE = re.compile(r'^export\s+(?:async\s+)?function\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)', re.MULTILINE)
_EXPORT_ARROW_RE = re.compile(r'^export\s+const\s+(\w+)\s*=\s*(?:async\s+)?\([^)]*\)', re.MULTILINE)
_EXPORT_CONST_RE = re.compile(r'^export\s+const\s+(\w+)\s*[=:]', re.MULTILINE)
_EXPORT_CLASS_RE = re.compile(r'^export\s+(?:abstract\s+)?class\s+(\w+)', re.MULTILINE)
_EXPORT_TYPE_RE = re.compile(r'^export\s+(?:type|interface)\s+(\w+)', re.MULTILINE)
_FUNC_RE = re.compile(r'(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)', re.MULTILINE)
_CALL_RE = re.compile(r'\b([a-zA-Z_]\w*)\s*\(([^)]*)\)')
_ENV_HARD_RE = re.compile(r'process\.env\.([A-Z_][A-Z0-9_]*)')
_ENV_SOFT_RE = re.compile(r'process\.env\.([A-Z_][A-Z0-9_]*)\s*(?:\?\?|(?<!\|)\|\|(?!\|))')
_STUB_RE = re.compile(r'throw\s+new\s+(?:Error|UnimplementedError)\s*\(|//\s*TODO|/\*\s*TODO')
_SKIP = {'if','for','while','switch','catch','function','async','return','typeof',
         'instanceof','new','import','export','class','interface','type','const','let','var'}

def _parse_params(s):
    s = s.strip()
    if not s: return {"n_required": 0, "n_total": 0, "has_varargs": False}
    parts = [p.strip() for p in re.split(r',(?![^<>]*>)(?![^{]*})', s) if p.strip()]
    n_total = n_required = 0; has_varargs = False
    for p in parts:
        if p.startswith('...'): has_varargs = True; continue
        n_total += 1
        if not (p.split(':')[0].strip().endswith('?') or '=' in p): n_required += 1
    return {"n_required": n_required, "n_total": n_total, "has_varargs": has_varargs}

def _count_args(s):
    s = s.strip()
    if not s: return 0
    depth = count = 0; count = 1
    for ch in s:
        if ch in '([{': depth += 1
        elif ch in ')]}': depth -= 1
        elif ch == ',' and depth == 0: count += 1
    return count

class TypeScriptScanner(ScannerBase):
    def supports(self, path):
        return (path.endswith('.ts') or path.endswith('.tsx')) and os.path.isfile(path)

    def scan(self, path) -> Optional[SymbolTable]:
        try: src = open(path, 'r', encoding='utf-8').read()
        except Exception: return None
        st = SymbolTable(module_name=os.path.splitext(os.path.basename(path))[0], path=path)
        lines = src.splitlines()

        for lineno, line in enumerate(lines, 1):
            for m in _IMPORT_NAMED_RE.finditer(line):
                mod = m.group(2); st.imports.append(mod)
                for n in [x.strip().split(' as ')[0].strip() for x in m.group(1).split(',') if x.strip()]:
                    if n: st.imported_symbols.append(n); st.from_imports.append({'module': mod, 'name': n, 'asname': None, 'line': lineno})
            for m in _IMPORT_DEFAULT_RE.finditer(line):
                if not _IMPORT_STAR_RE.search(line):
                    st.imports.append(m.group(2)); st.imported_symbols.append(m.group(1))
                    st.from_imports.append({'module': m.group(2), 'name': m.group(1), 'asname': None, 'line': lineno})

        for m in _EXPORT_CLASS_RE.finditer(src): st.exports.append(m.group(1))
        for m in _EXPORT_TYPE_RE.finditer(src): st.exports.append(m.group(1))

        for m in _FUNC_RE.finditer(src):
            name, params_str = m.group(1), m.group(2)
            arity = _parse_params(params_str)
            lineno = src[:m.start()].count('\n') + 1
            rest = src[m.end():]; brace = rest.find('{'); is_stub = False
            if brace != -1:
                depth = 0; body_end = brace
                for i, ch in enumerate(rest[brace:], brace):
                    if ch == '{': depth += 1
                    elif ch == '}':
                        depth -= 1
                        if depth == 0: body_end = i; break
                body = rest[brace+1:body_end].strip()
                is_stub = not body or bool(_STUB_RE.search(body))
            st.functions[name] = {**arity, 'has_varkw': False, 'return_annotation': None, 'is_stub': is_stub, 'line': lineno}
            if 'export' in src[max(0,m.start()-1):m.start()+7] and name not in st.exports: st.exports.append(name)

        for m in _EXPORT_ARROW_RE.finditer(src):
            if m.group(1) not in st.exports: st.exports.append(m.group(1))
        for m in _EXPORT_CONST_RE.finditer(src):
            if m.group(1) not in st.exports: st.exports.append(m.group(1))

        for lineno, line in enumerate(lines, 1):
            if line.strip().startswith('//'): continue
            for m in _CALL_RE.finditer(line):
                n = m.group(1)
                if n not in _SKIP:
                    st.calls.append({'symbol': n, 'line': lineno, 'kind': 'name',
                                     'n_args': _count_args(m.group(2)) if m.group(2).strip() else 0,
                                     'n_kwargs': 0, 'has_star_args': False, 'has_kwargs_unpack': False})

        for lineno, line in enumerate(lines, 1):
            for m in _ENV_SOFT_RE.finditer(line): st.env_vars_soft.append({'var_name': m.group(1), 'line': lineno})
            for m in _ENV_HARD_RE.finditer(line):
                if not any(e['var_name'] == m.group(1) and e['line'] == lineno for e in st.env_vars_soft):
                    st.env_vars_hard.append({'var_name': m.group(1), 'line': lineno})

        st.exports = list(dict.fromkeys(st.exports))
        return st
```

- [x] **Step 4: Run tests**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/test_scanner_typescript.py -v 2>&1
```

Expected: all 15 tests pass (14 unit + 1 registry integration).

- [x] **Step 5: Commit**

```bash
cd /home/visionairy/Dispatch
git add test-xfba/scanner_typescript.py test-xfba/tests/test_scanner_typescript.py
git commit -m "feat: TypeScript/TSX scanner for XFBA (regex-based, no deps)"
```

---

## Task 2: Dart Scanner

**Files:**
- Create: `test-xfba/scanner_dart.py`
- Create: `test-xfba/tests/test_scanner_dart.py`

### Dart parameter rules
- `String a` = required positional
- `[String a]` or `[String a = 'x']` = optional positional → does not count to n_required
- `{String? a}` = named optional → does not count to n_required
- `{required String a}` = named required → counts to n_required
- Stub = `throw UnimplementedError()` / `throw UnsupportedError()` / empty `{}`

- [x] **Step 1: Write the failing tests**

Create `test-xfba/tests/test_scanner_dart.py`:

```python
import os, sys, tempfile, pytest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from scanner_dart import DartScanner

def _write(src):
    f = tempfile.NamedTemporaryFile(suffix=".dart", mode="w", delete=False, encoding="utf-8")
    f.write(src); f.close(); return f.name

def test_supports_dart():
    s = DartScanner()
    assert s.supports("foo.dart") and not s.supports("foo.ts") and not s.supports("foo.py")

def test_exports_class():
    st = DartScanner().scan(_write("class MyWidget extends StatelessWidget {}\n"))
    assert "MyWidget" in st.exports

def test_exports_function():
    st = DartScanner().scan(_write("void main() { }\n"))
    assert "main" in st.exports

def test_exports_future_function():
    st = DartScanner().scan(_write("Future<String> fetchData(String url) async { return ''; }\n"))
    assert "fetchData" in st.exports

def test_function_required_positional():
    st = DartScanner().scan(_write("String greet(String name, String greeting) { return greeting + name; }\n"))
    fn = st.functions.get("greet")
    assert fn and fn["n_required"] == 2 and fn["n_total"] == 2

def test_function_optional_positional():
    st = DartScanner().scan(_write("String greet(String name, [String greeting = 'Hello']) { return name; }\n"))
    fn = st.functions.get("greet")
    assert fn["n_required"] == 1 and fn["n_total"] == 2

def test_function_named_optional():
    st = DartScanner().scan(_write("String greet(String name, {String? greeting}) { return name; }\n"))
    fn = st.functions.get("greet")
    assert fn["n_required"] == 1 and fn["n_total"] == 2

def test_function_named_required():
    st = DartScanner().scan(_write("String greet({required String name, String? greeting}) { return name; }\n"))
    fn = st.functions.get("greet")
    assert fn["n_required"] == 1 and fn["n_total"] == 2

def test_stub_unimplemented():
    st = DartScanner().scan(_write("String todo(String a) { throw UnimplementedError(); }\n"))
    assert st.functions.get("todo", {}).get("is_stub")

def test_import_package():
    st = DartScanner().scan(_write("import 'package:flutter/material.dart';\n"))
    assert "package:flutter/material.dart" in st.imports

def test_import_show():
    st = DartScanner().scan(_write("import 'package:myapp/utils.dart' show fetchData, parseJson;\n"))
    names = [fi["name"] for fi in st.from_imports]
    assert "fetchData" in names and "parseJson" in names

def test_call_detection():
    st = DartScanner().scan(_write("void main() { greet('Alice', 'Hi'); }\n"))
    call = next((c for c in st.calls if c["symbol"] == "greet"), None)
    assert call and call["n_args"] == 2

def test_env_var_hard_dotenv():
    st = DartScanner().scan(_write("final key = dotenv.env['API_KEY'];\n"))
    assert any(e["var_name"] == "API_KEY" for e in st.env_vars_hard)

def test_env_var_soft_dotenv():
    st = DartScanner().scan(_write("final key = dotenv.env['API_KEY'] ?? 'default';\n"))
    assert any(e["var_name"] == "API_KEY" for e in st.env_vars_soft)

def test_env_var_hard_platform():
    st = DartScanner().scan(_write("final key = Platform.environment['SECRET'];\n"))
    assert any(e["var_name"] == "SECRET" for e in st.env_vars_hard)

def test_registry_scans_dart_file():
    from scanner_registry import scan_file
    st = scan_file(_write("String hello(String name) { return name; }\n"))
    assert st is not None and "hello" in st.exports
```

- [x] **Step 2: Run to confirm failure**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/test_scanner_dart.py -v 2>&1 | head -10
```

Expected: `ImportError: No module named 'scanner_dart'`

- [x] **Step 3: Implement `test-xfba/scanner_dart.py`**

```python
from __future__ import annotations
import os, re
from typing import Optional
from scanner_base import ScannerBase, SymbolTable

_IMPORT_RE = re.compile(r"import\s+'([^']+)'(?:\s+show\s+([\w\s,]+))?(?:\s+hide\s+[\w\s,]+)?;")
_CLASS_RE = re.compile(r'^(?:abstract\s+)?class\s+(\w+)', re.MULTILINE)
_MIXIN_RE = re.compile(r'^mixin\s+(\w+)', re.MULTILINE)
_ENUM_RE = re.compile(r'^enum\s+(\w+)', re.MULTILINE)
_FUNC_RE = re.compile(
    r'^([\w<>\[\]?,\s]+?)\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*(?:\([^)]*\)[^)]*)*)\)\s*(?:async\s*)?\{',
    re.MULTILINE)
_CALL_RE = re.compile(r'\b([a-zA-Z_]\w*)\s*\(([^)]*)\)')
_ENV_KEY_RE = re.compile(r"(?:dotenv\.env|Platform\.environment)\['([A-Z_][A-Z0-9_]*)'\]")
_ENV_SOFT_RE = re.compile(r"(?:dotenv\.env|Platform\.environment)\['([A-Z_][A-Z0-9_]*)'\]\s*\?\?")
_STUB_RE = re.compile(r'throw\s+(?:UnimplementedError|UnsupportedError)\s*\(')
_SKIP = {'if','for','while','switch','catch','assert','return','new','class','import',
         'void','final','const','var','super','this','await','async','yield','print'}
_DART_TYPES = {'void','bool','int','double','num','String','List','Map','Set','Future',
               'Stream','Widget','BuildContext','State','dynamic','Object','Iterable',
               'Duration','DateTime','Color','Key','GlobalKey'}

def _parse_dart_params(s):
    s = s.strip()
    if not s: return {"n_required": 0, "n_total": 0, "has_varargs": False}
    n_required = n_total = 0
    opt_pos = re.search(r'\[([^\]]*)\]', s)
    named = re.search(r'\{([^}]*)\}', s)
    base = s[:s.index('[')] if opt_pos else (s[:s.index('{')] if named else s)
    for p in [x.strip() for x in base.split(',') if x.strip()]: n_total += 1; n_required += 1
    if opt_pos:
        for p in [x.strip() for x in opt_pos.group(1).split(',') if x.strip()]: n_total += 1
    if named:
        for p in [x.strip() for x in named.group(1).split(',') if x.strip()]:
            n_total += 1
            if p.startswith('required '): n_required += 1
    return {"n_required": n_required, "n_total": n_total, "has_varargs": False}

def _count_args(s):
    s = s.strip()
    if not s: return 0
    depth = 0; count = 1
    for ch in s:
        if ch in '([{': depth += 1
        elif ch in ')]}': depth -= 1
        elif ch == ',' and depth == 0: count += 1
    return count

class DartScanner(ScannerBase):
    def supports(self, path): return path.endswith('.dart') and os.path.isfile(path)

    def scan(self, path) -> Optional[SymbolTable]:
        try: src = open(path, 'r', encoding='utf-8').read()
        except Exception: return None
        st = SymbolTable(module_name=os.path.splitext(os.path.basename(path))[0], path=path)
        lines = src.splitlines()

        for lineno, line in enumerate(lines, 1):
            for m in _IMPORT_RE.finditer(line):
                mod = m.group(1); st.imports.append(mod)
                if m.group(2):
                    for n in [x.strip() for x in m.group(2).split(',') if x.strip()]:
                        st.imported_symbols.append(n)
                        st.from_imports.append({'module': mod, 'name': n, 'asname': None, 'line': lineno})

        for m in _CLASS_RE.finditer(src): st.exports.append(m.group(1))
        for m in _MIXIN_RE.finditer(src): st.exports.append(m.group(1))
        for m in _ENUM_RE.finditer(src): st.exports.append(m.group(1))

        for m in _FUNC_RE.finditer(src):
            ret = m.group(1).strip(); name = m.group(2).strip(); params = m.group(3) or ''
            rt_base = ret.split('<')[0].strip().split()[-1] if ret else ''
            if name in _SKIP or not rt_base: continue
            if not (rt_base in _DART_TYPES or rt_base[0].isupper() or rt_base == 'void'): continue
            arity = _parse_dart_params(params)
            lineno = src[:m.start()].count('\n') + 1
            rest = src[m.end()-1:]  # from opening {
            depth = 0; body_end = 0
            for i, ch in enumerate(rest):
                if ch == '{': depth += 1
                elif ch == '}':
                    depth -= 1
                    if depth == 0: body_end = i; break
            body = rest[1:body_end].strip()
            is_stub = not body or bool(_STUB_RE.search(body))
            st.functions[name] = {**arity, 'has_varkw': False, 'return_annotation': ret or None, 'is_stub': is_stub, 'line': lineno}
            if name not in st.exports: st.exports.append(name)

        for lineno, line in enumerate(lines, 1):
            if line.strip().startswith('//'): continue
            for m in _CALL_RE.finditer(line):
                n = m.group(1)
                if n not in _SKIP:
                    st.calls.append({'symbol': n, 'line': lineno, 'kind': 'name',
                                     'n_args': _count_args(m.group(2)) if m.group(2).strip() else 0,
                                     'n_kwargs': 0, 'has_star_args': False, 'has_kwargs_unpack': False})

        for lineno, line in enumerate(lines, 1):
            for m in _ENV_SOFT_RE.finditer(line): st.env_vars_soft.append({'var_name': m.group(1), 'line': lineno})
            for m in _ENV_KEY_RE.finditer(line):
                if not any(e['var_name'] == m.group(1) and e['line'] == lineno for e in st.env_vars_soft):
                    st.env_vars_hard.append({'var_name': m.group(1), 'line': lineno})

        st.exports = list(dict.fromkeys(st.exports))
        return st
```

- [x] **Step 4: Run tests**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/test_scanner_dart.py -v 2>&1
```

Expected: all 15 tests pass.

- [x] **Step 5: Commit**

```bash
cd /home/visionairy/Dispatch
git add test-xfba/scanner_dart.py test-xfba/tests/test_scanner_dart.py
git commit -m "feat: Dart scanner for XFBA (regex-based, no deps)"
```

---

## Task 3: Wire Scanners Into Registry and Flow Analyzer

**Files:**
- Modify: `test-xfba/scanner_registry.py`
- Modify: `test-xfba/flow_analyzer.py`

- [x] **Step 1: Update `scanner_registry.py`**

Replace entire file content:

```python
from __future__ import annotations
from typing import Optional
from scanner_base import SymbolTable
from scanner_python import PythonScanner
from scanner_bash import BashScanner
from scanner_typescript import TypeScriptScanner
from scanner_dart import DartScanner

SCANNERS = [PythonScanner(), BashScanner(), TypeScriptScanner(), DartScanner()]

def scan_file(path: str) -> Optional[SymbolTable]:
    for s in SCANNERS:
        if s.supports(path):
            return s.scan(path)
    return None
```

- [x] **Step 2: Update `flow_analyzer.py` — two changes**

Change 1 — `_iter_source_files`, line 19. Before:
```python
if fn.endswith(".py") or fn.endswith(".sh"):
```
After:
```python
if fn.endswith(".py") or fn.endswith(".sh") or fn.endswith(".ts") or fn.endswith(".tsx") or fn.endswith(".dart"):
```

Change 2 — `build_index`, line 64. Before:
```python
mod_key = rel[:-3] if rel.endswith(".py") else rel
```
After:
```python
_EXT_STRIP = (".py", ".ts", ".tsx", ".dart")
mod_key = next((rel[:-len(e)] for e in _EXT_STRIP if rel.endswith(e)), rel)
```

- [x] **Step 3: Run full test suite — no regressions**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/ -v --tb=short 2>&1 | tail -30
```

Expected: all 71 original + 2 registry integration tests pass (73 total).

- [x] **Step 4: Commit**

```bash
cd /home/visionairy/Dispatch
git add test-xfba/scanner_registry.py test-xfba/flow_analyzer.py
git commit -m "feat: wire TS/Dart scanners into registry and flow analyzer"
```

---

## Task 4: Fix XSIA Extension Filter for Dart

**Files:**
- Modify: `~/.claude/hooks/pre-edit-audit.sh`

- [x] **Step 1: Edit line 25**

Before:
```bash
echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|py|sql|sh)$' || exit 0
```
After:
```bash
echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|py|sql|sh|dart)$' || exit 0
```

- [x] **Step 2: Verify**

```bash
grep -n "dart" ~/.claude/hooks/pre-edit-audit.sh
```

Expected: `25:  echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|py|sql|sh|dart)$' || exit 0`

- [x] **Step 3: Commit source copy in Dispatch repo**

```bash
cp ~/.claude/hooks/pre-edit-audit.sh /home/visionairy/Dispatch/pre-edit-audit.sh
cd /home/visionairy/Dispatch
git add pre-edit-audit.sh
git commit -m "fix: add .dart to XSIA pre-edit extension filter"
```

---

## Task 5: Integration Test on Real Project Files

- [x] **Step 1: Test TS scanner on real LC-Access file**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 - <<'EOF'
import sys; sys.path.insert(0, '.')
from scanner_typescript import TypeScriptScanner
path = '/home/visionairy/LC-Access/mobile/index.ts'
st = TypeScriptScanner().scan(path)
if st:
    print(f"Exports ({len(st.exports)}): {st.exports[:5]}")
    print(f"Functions ({len(st.functions)}): {list(st.functions.keys())[:5]}")
    print(f"Calls: {len(st.calls)}, Imports: {len(st.imports)}")
else:
    print("FAIL: returned None")
EOF
```

Expected: non-empty exports/functions, no crash.

- [x] **Step 2: Test Dart scanner on real Perimeter file**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 - <<'EOF'
import sys; sys.path.insert(0, '.')
from scanner_dart import DartScanner
path = '/home/visionairy/Perimeter/lib/providers/job_provider.dart'
st = DartScanner().scan(path)
if st:
    print(f"Exports ({len(st.exports)}): {st.exports[:5]}")
    print(f"Functions ({len(st.functions)}): {list(st.functions.keys())[:5]}")
    print(f"Calls: {len(st.calls)}, Imports: {len(st.imports)}")
else:
    print("FAIL: returned None")
EOF
```

Expected: non-empty output, no crash.

- [x] **Step 3: Test full index build on Perimeter**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 - <<'EOF'
import sys; sys.path.insert(0, '.')
from flow_analyzer import build_index
idx = build_index('/home/visionairy/Perimeter')
mods = idx.get('modules', {})
print(f"Total modules: {len(mods)}")
print(f"Sample keys: {list(mods.keys())[:5]}")
EOF
```

Expected: `Total modules: N` where N > 0 and includes Dart files.

- [x] **Step 4: Test full index build on LC-Access**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 - <<'EOF'
import sys; sys.path.insert(0, '.')
from flow_analyzer import build_index
idx = build_index('/home/visionairy/LC-Access')
mods = idx.get('modules', {})
print(f"Total modules: {len(mods)}")
print(f"Sample keys: {list(mods.keys())[:5]}")
EOF
```

Expected: `Total modules: N` where N > 0 and includes TS files.

---

## Task 6: Sync to Live Auditor

Only run after Task 5 integration tests show valid non-zero module counts.

- [x] **Step 1: Sync to installed location**

```bash
cp /home/visionairy/Dispatch/test-xfba/scanner_typescript.py ~/.claude/xf-boundary-auditor/
cp /home/visionairy/Dispatch/test-xfba/scanner_dart.py ~/.claude/xf-boundary-auditor/
cp /home/visionairy/Dispatch/test-xfba/scanner_registry.py ~/.claude/xf-boundary-auditor/
cp /home/visionairy/Dispatch/test-xfba/flow_analyzer.py ~/.claude/xf-boundary-auditor/
```

- [x] **Step 2: Verify installed location**

```bash
ls ~/.claude/xf-boundary-auditor/scanner_*.py
```

Expected: `scanner_base.py  scanner_bash.py  scanner_dart.py  scanner_python.py  scanner_typescript.py`

- [x] **Step 3: Clear index caches so next session rebuilds from scratch**

```bash
rm -f /home/visionairy/LC-Access/.xf/index_cache.json
rm -f /home/visionairy/Perimeter/.xf/index_cache.json
```

- [x] **Step 4: Final commit**

```bash
cd /home/visionairy/Dispatch
git add test-xfba/
git commit -m "feat: TS/Dart scanner support complete — XFBA + XSIA now cover LC-Access and Perimeter"
```

---

## What This Does NOT Cover

- `syntax_violations()` — still Python-only (uses `py_compile`). TS/Dart syntax errors not caught by Stage 1. Safe — scanner returns None on parse failure.
- `silent_except_violations()` — still Python-only (uses Python AST). Dart/TS silent catches not flagged.
- xsi.py deep analysis — automatically gains TS/Dart support since it uses the same index.

---

## Task 7: Three-State Auto-Fix Consent Flow + Ralph Loop

**Files:**
- Modify: `test-xfba/consent.py` (installed: `~/.claude/xf-boundary-auditor/consent.py`)
- Modify: `test-xfba/auditor.py` (installed: `~/.claude/xf-boundary-auditor/auditor.py`)
- Create: `test-xfba/tests/test_consent_autofix.py`

### The three states

**State 1 — Initial block output (always shown):**
```
⚠ Violation: greet() called with 3 args, accepts 2 (caller.dart:47)
Repair: caller.dart:47 — remove 1 argument from the call to greet()

  [Fix problem]   Type "Fix problem" — I'll apply the repair, re-audit, and promise clean
  [Show diff]     Type "Show diff"  — Show me the exact change before deciding
```

**State 2 — After "Show diff" (diff view):**
```
Proposed fix:
  caller.dart:47
  - greet('Alice', 'Hi', true)
  + greet('Alice', 'Hi')

  [Apply fix]       Type "Apply fix"     — Apply this, re-audit, promise clean
  [I'll handle it]  Type "I'll handle it" — Allow edit, log violation for review
```

**State 3 — After "Fix problem" or "Apply fix":**
- auditor.py applies the repair via Edit tool call
- The resulting Edit re-triggers XFBA naturally
- When XFBA passes clean: Claude outputs `<promise>XFBA_CLEAN</promise>`
- If XFBA blocks again: loop continues from State 1

### Key rules
- "I'll fix" and "Show diff" are the same — always show the diff first, never leave user with just a violation description
- "I'll handle it" (from State 2 only) exits with 0, logs violation to `.xf/repair_log.json` with `accepted: false`
- Auto-fix path logs to `.xf/repair_log.json` with `accepted: true` after clean re-audit
- Ralph loop promise: `<promise>XFBA_CLEAN</promise>` — Claude must output this only after XFBA stamps clean

### What changes in consent.py

Current graduated trust levels (0 → show options, 1 → show diff, 2 → apply all) map directly to the three states. Changes needed:

1. `format_consent_options()` — rewrite output to match State 1 language above ("Fix problem" / "Show diff")
2. `format_diff_view()` — new function, generates unified diff of proposed repair + State 2 options ("Apply fix" / "I'll handle it")
3. `get_trust_level()` — unchanged (reads `.xf/session_state.json`)
4. `increment_trust()` — unchanged
5. `append_repair_log()` — add `accepted` bool field (True = auto-fix applied, False = I'll handle it)

### What changes in auditor.py

After building the repair plan (Stage 3), pass it through the new consent flow. When the consent output instructs "apply fix", auditor.py emits the repair as a structured JSON instruction on stdout that Claude executes as an Edit, then outputs the Ralph loop promise template.

Add to stdout block on exit 2:

```
After applying the fix, run XFBA again by making the edit.
When XFBA stamps clean (✓ 0 violations), output: <promise>XFBA_CLEAN</promise>
```

---

- [x] **Step 1: Write failing tests**

Create `test-xfba/tests/test_consent_autofix.py`:

```python
import os, sys, json, tempfile, pytest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from consent import format_consent_options, format_diff_view, append_repair_log


def test_consent_options_contains_fix_problem():
    violations = [{"id": "a001", "type": "arity_mismatch", "caller_module": "caller.dart",
                   "caller_line": 47, "symbol": "greet",
                   "fix": "caller.dart:47 — remove 1 argument from the call to greet()",
                   "consequence": "TypeError when greet() runs."}]
    repair = [{"id": "a001", "file": "caller.dart", "line": 47,
               "description": "remove 1 argument", "diff": "-greet('a','b','c')\n+greet('a','b')"}]
    out = format_consent_options(violations, repair, trust_level=0)
    assert "Fix problem" in out
    assert "Show diff" in out


def test_consent_options_not_apply_all():
    violations = [{"id": "a001", "type": "arity_mismatch", "caller_module": "caller.dart",
                   "caller_line": 47, "symbol": "greet",
                   "fix": "caller.dart:47 — remove 1 argument",
                   "consequence": "TypeError."}]
    repair = [{"id": "a001", "file": "caller.dart", "line": 47,
               "description": "remove 1 argument", "diff": "-foo(1,2,3)\n+foo(1,2)"}]
    out = format_consent_options(violations, repair, trust_level=0)
    assert "apply all" not in out.lower()


def test_diff_view_shows_diff():
    repair = [{"id": "a001", "file": "caller.dart", "line": 47,
               "description": "remove 1 argument from greet()",
               "diff": "-greet('Alice', 'Hi', True)\n+greet('Alice', 'Hi')"}]
    out = format_diff_view(repair)
    assert "caller.dart" in out
    assert "-greet" in out
    assert "+greet" in out


def test_diff_view_contains_apply_fix():
    repair = [{"id": "a001", "file": "caller.dart", "line": 47,
               "description": "remove 1 argument", "diff": "-foo(1,2,3)\n+foo(1,2)"}]
    out = format_diff_view(repair)
    assert "Apply fix" in out
    assert "I'll handle it" in out


def test_repair_log_accepted_field():
    with tempfile.TemporaryDirectory() as d:
        xf_dir = os.path.join(d, ".xf")
        os.makedirs(xf_dir)
        log_path = os.path.join(xf_dir, "repair_log.json")
        violation = {"id": "a001", "type": "arity_mismatch", "caller_module": "f.dart",
                     "caller_line": 10, "symbol": "foo", "consequence": "err", "fix": "remove arg"}
        repair = {"description": "remove arg from foo()", "file": "f.dart", "line": 10, "diff": ""}
        append_repair_log(xf_dir, violation, repair, accepted=True)
        entries = json.loads(open(log_path).read())
        assert entries[-1]["accepted"] is True

def test_repair_log_not_accepted():
    with tempfile.TemporaryDirectory() as d:
        xf_dir = os.path.join(d, ".xf")
        os.makedirs(xf_dir)
        log_path = os.path.join(xf_dir, "repair_log.json")
        violation = {"id": "a001", "type": "arity_mismatch", "caller_module": "f.dart",
                     "caller_line": 10, "symbol": "foo", "consequence": "err", "fix": "remove arg"}
        repair = {"description": "remove arg", "file": "f.dart", "line": 10, "diff": ""}
        append_repair_log(xf_dir, violation, repair, accepted=False)
        entries = json.loads(open(log_path).read())
        assert entries[-1]["accepted"] is False


def test_ralph_loop_promise_in_fix_output():
    violations = [{"id": "a001", "type": "arity_mismatch", "caller_module": "caller.dart",
                   "caller_line": 47, "symbol": "greet",
                   "fix": "caller.dart:47 — remove 1 argument",
                   "consequence": "TypeError."}]
    repair = [{"id": "a001", "file": "caller.dart", "line": 47,
               "description": "remove 1 argument", "diff": "-greet(a,b,c)\n+greet(a,b)"}]
    out = format_consent_options(violations, repair, trust_level=0)
    assert "XFBA_CLEAN" in out
```

- [x] **Step 2: Run to confirm failure**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/test_consent_autofix.py -v 2>&1 | head -20
```

Expected: failures on `format_diff_view` (doesn't exist) and `accepted` param (not in signature).

- [x] **Step 3: Read current consent.py before editing**

```bash
cat /home/visionairy/Dispatch/test-xfba/consent.py
```

Read fully before making any changes. All existing functions must remain — only add `format_diff_view` and update `format_consent_options` signature + `append_repair_log` signature.

- [x] **Step 4: Update `format_consent_options` in `consent.py`**

Replace the output block inside `format_consent_options` to produce State 1 language. Preserve all existing parameters — add `repair` as a parameter (list of repair dicts, may be empty):

```python
def format_consent_options(violations, repair=None, trust_level=0):
    repair = repair or []
    lines = []
    for v in violations[:3]:  # cap at 3 for readability
        lines.append(f"  ⚠  {v.get('consequence', '')}")
        if v.get('fix'):
            lines.append(f"     Repair: {v['fix']}")
    body = "\n".join(lines)
    return (
        f"{body}\n\n"
        f"  [Fix problem]   Type \"Fix problem\"   — apply repair, re-audit, promise clean\n"
        f"  [Show diff]     Type \"Show diff\"     — show exact change before deciding\n\n"
        f"After fix is applied and XFBA stamps clean, output: <promise>XFBA_CLEAN</promise>"
    )
```

- [x] **Step 5: Add `format_diff_view` to `consent.py`**

Add after `format_consent_options`:

```python
def format_diff_view(repair):
    """State 2: show unified diff + Apply fix / I'll handle it options."""
    lines = ["Proposed fix:"]
    for item in repair:
        lines.append(f"\n  {item.get('file', '?')}:{item.get('line', '?')} — {item.get('description', '')}")
        for diff_line in (item.get('diff') or '').splitlines():
            lines.append(f"  {diff_line}")
    lines.append(
        "\n  [Apply fix]       Type \"Apply fix\"      — apply this, re-audit, promise clean"
        "\n  [I'll handle it]  Type \"I'll handle it\" — allow edit, log for manual review"
        "\n\nAfter fix is applied and XFBA stamps clean, output: <promise>XFBA_CLEAN</promise>"
    )
    return "\n".join(lines)
```

- [x] **Step 6: Update `append_repair_log` to accept `accepted` bool**

Find the existing `append_repair_log` function. Add `accepted: bool = False` parameter and write it to the log entry:

```python
# Add accepted=False parameter and include in entry dict:
entry = {
    # ... existing fields ...
    "accepted": accepted,
}
```

- [x] **Step 7: Run tests**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/test_consent_autofix.py -v 2>&1
```

Expected: all 7 tests pass.

- [x] **Step 8: Run full suite — no regressions**

```bash
cd /home/visionairy/Dispatch/test-xfba && python3 -m pytest tests/ -v --tb=short 2>&1 | tail -20
```

Expected: all previous tests + 7 new = 80 total passing.

- [x] **Step 9: Sync consent.py to installed location**

```bash
cp /home/visionairy/Dispatch/test-xfba/consent.py ~/.claude/xf-boundary-auditor/consent.py
```

- [x] **Step 10: Commit**

```bash
cd /home/visionairy/Dispatch
git add test-xfba/consent.py test-xfba/tests/test_consent_autofix.py
git commit -m "feat: three-state auto-fix consent — Fix problem / Show diff / Apply fix + Ralph loop promise"
```
