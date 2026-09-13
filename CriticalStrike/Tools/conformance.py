#!/usr/bin/env python3
"""Checks that every type claiming a protocol actually implements it.

This is the check that was missing when TrainingRules shipped without
`checkMatchEnd(sim:)`: eleven game modes implement a twelve-method protocol, most of it
defaulted in an extension, and the one requirement with no default was easy to forget. The
other checkers verify delimiters, duplicate declarations, cross-file type references and
initializer argument order — none of which notices a missing conformance.

Matching is by member name, not by full signature. That is deliberate: parsing Swift
generic signatures properly is a compiler's job, and a missing name is the mistake people
actually make.

    python3 Tools/conformance.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [os.path.join(ROOT, "Sources"), os.path.join(ROOT, "Tests")]

# Conformances whose requirements the compiler synthesises or the standard library
# provides, so an empty body is correct and expected.
SYNTHESIZED = {
    "Codable", "Decodable", "Encodable", "Equatable", "Hashable", "Comparable",
    "CaseIterable", "Sendable", "Identifiable", "RawRepresentable", "Error",
    "CustomStringConvertible", "ExpressibleByStringLiteral", "ObservableObject",
    "AnyObject", "Sequence", "IteratorProtocol", "RandomNumberGenerator",
}

DECL = re.compile(r'^(?:public |internal |private |fileprivate |open |final |@objc |@MainActor )*'
                  r'(class|struct|enum|actor|protocol|extension)\s+([A-Za-z_][A-Za-z0-9_]*)'
                  r'\s*(?::\s*([^{]+?))?\s*\{', re.MULTILINE)
FUNC = re.compile(r'\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)')
VAR = re.compile(r'\bvar\s+([A-Za-z_][A-Za-z0-9_]*)')


def swift_files():
    for base in SOURCES:
        for dirpath, _, names in os.walk(base):
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(dirpath, name)


def body_of(text, open_brace_index):
    """Returns the source between a declaration's braces."""
    depth = 0
    for index in range(open_brace_index, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[open_brace_index + 1:index]
    return text[open_brace_index + 1:]


def strip_comments(text):
    text = re.sub(r'//[^\n]*', '', text)
    return re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)


def main():
    protocols = {}        # name -> set of required member names
    defaulted = {}        # protocol name -> set of member names with a default
    conformers = []       # (file, line, type name, [protocol names])
    members = {}          # type name -> set of member names it declares anywhere

    files = {}
    for path in swift_files():
        rel = os.path.relpath(path, ROOT)
        files[rel] = strip_comments(open(path, encoding="utf-8").read())

    # Pass one: protocols and their requirements.
    for rel, text in files.items():
        for match in DECL.finditer(text):
            kind, name = match.group(1), match.group(2)
            if kind != "protocol":
                continue
            body = body_of(text, match.end() - 1)
            required = set()
            for line in body.split('\n'):
                stripped = line.strip()
                # A requirement has no body. Anything with a brace is an associated type's
                # default or a nested declaration, which is not ours to check.
                if '{' in stripped:
                    continue
                found = FUNC.search(stripped) or VAR.search(stripped)
                if found:
                    required.add(found.group(1))
            protocols[name] = required
            defaulted.setdefault(name, set())

    # Pass two: protocol extensions supply defaults; type bodies and extensions supply
    # members; declarations record what each type claims to conform to.
    for rel, text in files.items():
        for match in DECL.finditer(text):
            kind, name, inherits = match.group(1), match.group(2), match.group(3)
            body = body_of(text, match.end() - 1)

            if kind == "extension" and name in protocols:
                for found in FUNC.finditer(body):
                    defaulted[name].add(found.group(1))
                for found in VAR.finditer(body):
                    defaulted[name].add(found.group(1))
                continue

            if kind in ("class", "struct", "enum", "actor", "extension"):
                declared = members.setdefault(name, set())
                for found in FUNC.finditer(body):
                    declared.add(found.group(1))
                for found in VAR.finditer(body):
                    declared.add(found.group(1))
                # `let x = ...` satisfies a `var x { get }` requirement too.
                for found in re.finditer(r'\blet\s+([A-Za-z_][A-Za-z0-9_]*)', body):
                    declared.add(found.group(1))

            if inherits:
                claimed = [part.strip().split('<')[0] for part in inherits.split(',')]
                claimed = [c for c in claimed if c and c not in SYNTHESIZED]
                if claimed:
                    line = text[:match.start()].count('\n') + 1
                    conformers.append((rel, line, name, claimed))

    errors = []
    checked = 0
    for rel, line, type_name, claimed in conformers:
        for protocol in claimed:
            if protocol not in protocols:
                continue    # a superclass, or a protocol from a framework
            checked += 1
            have = members.get(type_name, set())
            for requirement in sorted(protocols[protocol]):
                if requirement in have or requirement in defaulted.get(protocol, set()):
                    continue
                errors.append(f"{rel}:{line}: {type_name} claims {protocol} but does not "
                              f"implement '{requirement}', and the protocol has no default")

    print(f"checked {checked} conformances against {len(protocols)} protocols")
    for error in errors:
        print(f"  error: {error}")
    if errors:
        print(f"FAILED with {len(errors)} error(s)")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
