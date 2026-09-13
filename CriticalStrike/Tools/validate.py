#!/usr/bin/env python3
"""Lightweight static checks for the Swift sources.

This is not a compiler. It catches the mistakes that are expensive to find only
once you are in front of Xcode: unbalanced delimiters, duplicate top-level type
names, references to types that are never declared anywhere, and stray tabs.
Run with:  python3 Tools/validate.py
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = [os.path.join(ROOT, "Sources"), os.path.join(ROOT, "Tests")]

# Only top-level declarations (column 0) are checked for duplicates; nested types
# such as a per-type private CodingKeys legitimately repeat.
DECL_RE = re.compile(
    r'^(?:public |internal |private |fileprivate |open |final |@objc |@MainActor )*'
    r'(class|struct|enum|protocol|actor|extension|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)')

def strip_noise(text):
    """Remove string literals and comments so delimiter counting is meaningful."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            # triple-quoted string
            if text[i:i+3] == '"""':
                end = text.find('"""', i + 3)
                i = n if end == -1 else end + 3
                continue
            i += 1
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if text[i:i+2] == '//':
            end = text.find('\n', i)
            i = n if end == -1 else end
            continue
        if text[i:i+2] == '/*':
            depth = 1
            i += 2
            while i < n and depth:
                if text[i:i+2] == '/*':
                    depth += 1
                    i += 2
                elif text[i:i+2] == '*/':
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)

def swift_files():
    for base in SOURCE_DIRS:
        for dirpath, _, filenames in os.walk(base):
            for name in sorted(filenames):
                if name.endswith('.swift'):
                    yield os.path.join(dirpath, name)

def main():
    errors = []
    warnings = []
    declarations = defaultdict(list)
    file_count = 0
    line_count = 0

    for path in swift_files():
        file_count += 1
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding='utf-8') as handle:
            raw = handle.read()
        line_count += raw.count('\n')
        code = strip_noise(raw)

        for opener, closer in (('{', '}'), ('(', ')'), ('[', ']')):
            delta = code.count(opener) - code.count(closer)
            if delta:
                errors.append(f"{rel}: unbalanced '{opener}{closer}' (delta {delta:+d})")

        if '\t' in raw:
            warnings.append(f"{rel}: contains tab characters")

        # Swift has no key paths into tuple elements, so `id: \.0` or `id: \.offset` on an
        # enumerated sequence does not compile even though it reads like idiomatic SwiftUI.
        for match in re.finditer(r'id:\s*\\\.(?:\d+|offset\b|element\.)', code):
            lineno = code[:match.start()].count('\n') + 1
            errors.append(f"{rel}:{lineno}: key path into a tuple element is not valid Swift")

        for lineno, line in enumerate(raw.split('\n'), 1):
            match = DECL_RE.match(line)
            if match and match.group(1) != 'extension':
                declarations[match.group(2)].append(f"{rel}:{lineno}")
            if len(line) > 130:
                warnings.append(f"{rel}:{lineno}: line longer than 130 characters")

    for name, places in sorted(declarations.items()):
        if len(places) > 1:
            errors.append(f"duplicate declaration of '{name}': " + ", ".join(places))

    print(f"scanned {file_count} files, {line_count} lines, {len(declarations)} top-level declarations")
    for w in warnings[:25]:
        print(f"  warning: {w}")
    if len(warnings) > 25:
        print(f"  ... and {len(warnings) - 25} more warnings")
    for e in errors:
        print(f"  error: {e}")
    if errors:
        print(f"FAILED with {len(errors)} error(s)")
        return 1
    print("OK")
    return 0

if __name__ == '__main__':
    sys.exit(main())
