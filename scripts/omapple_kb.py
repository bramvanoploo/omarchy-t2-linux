# scripts/omapple_kb.py: Omarchy keybinding records parsing and chord handling,
# plus the shared settings.json read/write.
# Imported by scripts/omapple-helper (which passes its own directory on sys.path)
# so the status payload, the recommended-keybindings pass and the bindings.lua
# writer cannot drift apart. Mirrored in JS by OmappleModel.js normalizeChord,
# which tests/run.sh checks against normalize_chord_tokens below.

import glob
import json
import os
import re

RECORDS_GLOB = "~/.cache/omarchy/keybindings-*.records"
MOD_ORDER = {"SUPER": 0, "CTRL": 1, "ALT": 2, "SHIFT": 3}


def latest_records_file():
    files = [f for f in glob.glob(os.path.expanduser(RECORDS_GLOB)) if os.access(f, os.R_OK)]
    if not files:
        return ""
    return max(files, key=os.path.getmtime)


def normalize_chord_tokens(c):
    if not c:
        return frozenset(), None
    tokens = [t.strip().upper() for t in re.split(r"[\+\s]+", c) if t.strip()]
    mods = set()
    key = None
    for t in tokens:
        if t in ("SUPER", "LOGO", "WIN", "CMD", "COMMAND", "META"):
            mods.add("SUPER")
        elif t in ("CTRL", "CONTROL"):
            mods.add("CTRL")
        elif t in ("ALT", "OPTION"):
            mods.add("ALT")
        elif t in ("SHIFT",):
            mods.add("SHIFT")
        else:
            key = t
    return frozenset(mods), key


def canonical_chord(c):
    """Chord as written into settings.json and bindings.lua: ordered modifiers,
    aliases folded, so "cmd+s" and "WIN + S" both become "SUPER + S"."""
    mods, key = normalize_chord_tokens(c)
    if not key:
        return ""
    ordered = sorted(mods, key=lambda m: MOD_ORDER.get(m, 10))
    ordered.append(key)
    return " + ".join(ordered)


def load_records(path=None):
    """Omarchy's keybinding dump as [(chord, action, dispatcher, arg)].

    The arrow lives in the first tab field. A line whose first field has no arrow
    is skipped: one odd record must not drop the whole list.
    """
    path = path if path is not None else latest_records_file()
    out = []
    if not path:
        return out
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                combo, arrow, desc = parts[0].partition("\u2192")
                if not arrow:
                    continue
                combo = combo.strip()
                if not combo:
                    continue
                disp = parts[1].strip() if len(parts) > 1 and parts[1].strip() else "exec"
                arg = parts[2].strip() if len(parts) > 2 else ""
                out.append((combo, desc.strip(), disp, arg))
    except OSError:
        pass
    return out


def get_rec(chord, bound=()):
    """A chord for `chord` that is not already taken: same modifiers plus ALT, then
    plus CTRL. `bound` is the set of chords in use (compared canonically)."""
    mods, key = normalize_chord_tokens(chord)
    if not key:
        return ""
    taken = {normalize_chord_tokens(b) for b in bound}
    for extra in ("ALT", "CTRL"):
        if extra in mods:
            continue
        cand = set(mods)
        cand.add(extra)
        if (frozenset(cand), key) not in taken:
            ordered = sorted(cand, key=lambda m: MOD_ORDER.get(m, 10))
            ordered.append(key)
            return " + ".join(ordered)
    ordered = sorted(set(mods) | {"ALT"}, key=lambda m: MOD_ORDER.get(m, 10))
    ordered.append(key)
    return " + ".join(ordered)


def load_settings(path):
    """settings.json as a dict, with the ownership check every writer needs.

    Returns None when the file exists but cannot be read as an object: writing on
    top of it would replace it with only the keys one subcommand happens to touch,
    so the caller must stop instead of starting from an empty dict.
    Raises PermissionError when the file belongs to somebody else.
    """
    if not path or not os.path.isfile(path):
        return {}
    if hasattr(os, "geteuid") and os.stat(path).st_uid != os.geteuid():
        raise PermissionError("settings.json not owned by current user")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def save_settings(path, data):
    tmp = path + ".tmp." + str(os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.replace(tmp, path)
