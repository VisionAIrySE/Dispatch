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
