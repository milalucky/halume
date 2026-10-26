#!/usr/bin/env python3
"""Lists the UI strings of Sources/HaluMe as localization keys (interpolations become %@ / %lld)."""
import re, sys, pathlib

INTS = {"days", "months", "drop", "passed", "total", "done", "plan.lines.count", "allowance.daysLeft",
        "current + 1", "count", "active.count", "i + 1", "project.tasks.count", "stage.tasks.count", "day", "runway.days", "monthsWithout", "working", "used", "percent", "-percent", "short", "periods.count"}
ICON = re.compile(r"^[a-z0-9]+(\.[a-z0-9]+)+$")

def literals(src):
    i = 0
    while i < len(src):
        if src.startswith('//', i):
            i = src.find('\n', i)
            if i < 0: return
            continue
        if src[i] == '"' and not src.startswith('"""', i):
            j, out, parts = i + 1, "", []
            while j < len(src) and src[j] != '"':
                if src.startswith('\\(', j):
                    depth, k = 1, j + 2
                    while depth:
                        if src[k] == '(': depth += 1
                        elif src[k] == ')': depth -= 1
                        elif src[k] == '"':  # nested string inside the interpolation
                            k = src.index('"', k + 1)
                        k += 1
                    expr = src[j + 2:k - 1].strip()
                    out += "%lld" if expr in INTS else "%@"
                    j = k
                elif src[j] == '\\':
                    out += src[j:j + 2]; j += 2
                else:
                    out += src[j]; j += 1
            # Interpolated strings escape a literal % as %% in their key.
            if "\\(" in src[i:j]:
                out = re.sub(r"%(?!@|lld)", "%%", out)
            yield out
            i = j + 1
        else:
            i += 1

keys = set()
for path in sorted(pathlib.Path(sys.argv[1]).glob("*.swift")):
    for s in literals(path.read_text()):
        if not s or ICON.match(s) or s.startswith("--") or s in {"%@", "%lld"}:
            continue
        if " " in s or s[0].isupper() or s in {"today", "tomorrow"} or "%" in s:
            keys.add(s)
for k in sorted(keys):
    print(k)
