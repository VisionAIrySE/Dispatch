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
        return path.endswith('.ts') or path.endswith('.tsx')

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
