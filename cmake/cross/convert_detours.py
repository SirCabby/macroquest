#!/usr/bin/env python3
"""Convert member-context DETOUR_TRAMPOLINE_DEF(...) usages to
DETOUR_TRAMPOLINE_DEF_MEMBER(<enclosing class>, ...). Namespace/global-scope
usages are left unchanged. Tracks brace scope to find the enclosing class."""
import re, sys

def convert(path):
    # newline='' preserves original line endings (files may be CRLF).
    src = open(path, encoding='utf-8', newline='').read()
    lines = src.splitlines(keepends=True)
    # scope stack: entries are class name (str) or None (non-class brace)
    stack = []
    pending_class = None      # class/struct name seen, waiting for its '{'
    pending_cancel = False
    out = []
    n_member = 0
    n_free = 0
    # Capture qualified names too (e.g. `class Outer::Inner`) so nested classes
    # are attributed to the class actually being defined.
    class_re = re.compile(r'\b(class|struct)\s+([A-Za-z_][\w:]*)')
    for line in lines:
        # Determine enclosing class BEFORE processing this line's braces,
        # so a DETOUR line inside a class is attributed correctly.
        enclosing = next((s for s in reversed(stack) if s is not None), None)

        if 'DETOUR_TRAMPOLINE_DEF(' in line and 'define' not in line:
            if enclosing is not None:
                line = line.replace('DETOUR_TRAMPOLINE_DEF(',
                                    f'DETOUR_TRAMPOLINE_DEF_MEMBER({enclosing}, ', 1)
                n_member += 1
            else:
                n_free += 1
        out.append(line)

        # Now update scope by scanning this line's tokens in order.
        i = 0
        while i < len(line):
            ch = line[i]
            # detect class/struct keyword start
            m = class_re.match(line, i)
            if m:
                pending_class = m.group(2)
                pending_cancel = False
                i = m.end()
                continue
            if ch == ';':
                # forward declaration or statement: cancel any pending class
                pending_class = None
            elif ch == '{':
                if pending_class is not None:
                    stack.append(pending_class)
                    pending_class = None
                else:
                    stack.append(None)
            elif ch == '}':
                if stack:
                    stack.pop()
            i += 1

    # Lines keep their original terminators, so join with '' and write with
    # newline='' to preserve the file's line endings (often CRLF).
    open(path, 'w', encoding='utf-8', newline='').write(''.join(out))
    print(f'{path}: converted {n_member} member-context, left {n_free} free-context')

for p in sys.argv[1:]:
    convert(p)
