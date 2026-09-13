#!/usr/bin/env python3
"""Checks that call-site argument labels are a subsequence of the initializer's
parameter order.

Swift requires arguments in declaration order, and the content databases use
initializers with thirty-plus defaulted parameters, where a transposed pair is easy to
write and invisible until the compiler runs. This catches it without a toolchain.

    python3 Tools/argorder.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources")

TYPES = ["WeaponData", "AttachmentData", "PerkData", "GrenadeData", "CharacterData",
         "CosmeticData", "MapData", "GameModeData", "MapBrush", "MapLight", "MapProp",
         "SpawnPoint", "ObjectiveZone", "IAPProduct", "LootCrate", "Mission",
         "MapEnvironment", "NavNode", "HUDElementLayout", "PlayerSnapshot", "PlayerResult",
         "WeaponBuild", "Loadout", "PlayerState", "WeaponSlotState", "BattlePassTier",
         "BattlePassSeason", "BattlePassProgress", "MissionProgress", "Lobby", "LobbyMember",
         "MatchmakingTicket", "NetHandshake", "NetMatchInfo", "NetInputPacket",
         "NetChatMessage", "InputCommand", "WorldSnapshot", "MatchResult", "KillFeedEntry",
         "ObjectiveSummary", "Callout", "PickupSpawn", "HitboxDefinition", "HitVolume",
         "DamageResult", "Wallet", "CrateReward", "ShotHit", "ShotImpact", "Projectile",
         "AreaEffect", "ExplosionEvent", "PickupInstance", "HUDState", "MinimapMarker",
         "DamageIndicator", "FloatingDamage", "Toast", "CaptureState", "LeaderboardEntry"]


def read_all():
    files = {}
    for dirpath, _, names in os.walk(SOURCES):
        for name in sorted(names):
            if name.endswith(".swift"):
                path = os.path.join(dirpath, name)
                files[os.path.relpath(path, ROOT)] = open(path, encoding="utf-8").read()
    return files


def find_init_params(text, type_name):
    """Returns every public initializer's ordered parameter labels for `type_name`."""
    marker = re.search(r'(?:struct|class)\s+' + type_name + r'\b', text)
    if not marker:
        return None
    body = text[marker.end():]
    # Stop at the next top-level type so a later declaration's init is not attributed here.
    next_type = re.search(
        r'\n(?:@[\w()]+\s+)*(?:public |internal |private |fileprivate |open )?'
        r'(?:final\s+)?(?:struct|class|enum|protocol|actor|extension)\s+[A-Z]', body)
    if next_type:
        body = body[:next_type.start()]
    signatures = []
    for init in re.finditer(r'(?:public |)init\(', body):
        signatures.append(_parse_params(body, init.end()))
    if signatures:
        return signatures
    # No explicit initializer: the compiler synthesizes a memberwise one in stored
    # property order, so derive the order from the declarations instead.
    stored = re.findall(r'^\s{4}(?:public |internal |private |)(?:var|let)\s+([a-zA-Z_][A-Za-z0-9_]*)\s*:',
                        body, re.MULTILINE)
    return [stored] if stored else None


def _parse_params(body, start):
    depth, i = 1, start
    while i < len(body) and depth:
        if body[i] == '(':
            depth += 1
        elif body[i] == ')':
            depth -= 1
        i += 1
    params = body[start:i - 1]
    labels, depth = [], 0
    current = ""
    for ch in params:
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
        if ch == ',' and depth == 0:
            labels.append(current)
            current = ""
        else:
            current += ch
    labels.append(current)
    out = []
    for label in labels:
        match = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)', label)
        if match:
            out.append(match.group(1))
    return out


def call_sites(text, type_name):
    """Yields (line number, [labels]) for each call to `type_name(...)`."""
    for match in re.finditer(r'\b' + type_name + r'\(', text):
        start = match.end()
        depth, i, in_string = 1, start, False
        while i < len(text) and depth:
            ch = text[i]
            if ch == '"':
                in_string = not in_string
            elif not in_string:
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
            i += 1
        args = text[start:i - 1]
        labels, depth, in_string = [], 0, False
        current = ""
        for ch in args:
            if ch == '"':
                in_string = not in_string
            if not in_string:
                if ch in "([{<":
                    depth += 1
                elif ch in ")]}>":
                    depth -= 1
            if ch == ',' and depth == 0 and not in_string:
                labels.append(current)
                current = ""
            else:
                current += ch
        labels.append(current)
        parsed = []
        for label in labels:
            m = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*:', label)
            parsed.append(m.group(1) if m else None)
        line = text[:match.start()].count('\n') + 1
        yield line, parsed


def is_subsequence(labels, order):
    index = 0
    for label in labels:
        if label is None:
            continue
        if label not in order:
            return False, label
        position = order.index(label)
        if position < index:
            return False, label
        index = position + 1
    return True, None


def main():
    files = read_all()
    errors = 0
    checked = 0
    for type_name in TYPES:
        orders = None
        for text in files.values():
            orders = find_init_params(text, type_name) or orders
        if not orders:
            continue
        for rel, text in files.items():
            for line, labels in call_sites(text, type_name):
                # Skip the declaration itself and anything with no labels at all.
                if not any(labels):
                    continue
                checked += 1
                results = [is_subsequence(labels, order) for order in orders]
                if any(ok for ok, _ in results):
                    continue
                errors += 1
                offender = next((bad for ok, bad in results if not ok), "?")
                print(f"  error: {rel}:{line}: {type_name}(...) argument "
                      f"'{offender}' is out of declaration order")
    print(f"checked {checked} call sites across {len(TYPES)} types")
    if errors:
        print(f"FAILED with {errors} ordering error(s)")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
