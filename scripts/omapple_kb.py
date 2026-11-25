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
import stat
import sys
import tempfile

RECORDS_GLOB = "~/.cache/omarchy/keybindings-*.records"
MOD_ORDER = {"SUPER": 0, "CTRL": 1, "ALT": 2, "SHIFT": 3}


def latest_records_file():
    files = [f for f in glob.glob(os.path.expanduser(RECORDS_GLOB)) if os.access(f, os.R_OK)]
    best = ""
    best_mtime = -1.0
    for f in files:
        try:
            mt = os.path.getmtime(f)
            if mt > best_mtime:
                best_mtime = mt
                best = f
        except OSError:
            continue
    return best


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


def _format_chord(mods, key):
    ordered = sorted(mods, key=lambda m: MOD_ORDER.get(m, 10))
    ordered.append(key)
    return " + ".join(ordered)


def canonical_chord(c):
    """Chord as written into settings.json and bindings.lua: ordered modifiers,
    aliases folded, so "cmd+s" and "WIN + S" both become "SUPER + S"."""
    mods, key = normalize_chord_tokens(c)
    if not key:
        return ""
    return _format_chord(mods, key)


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
    except (OSError, UnicodeDecodeError):
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
            return _format_chord(cand, key)
    return _format_chord(set(mods) | {"ALT"}, key)


def load_settings(path):
    """settings.json as a dict, with the ownership check every writer needs.

    Returns None when the file exists but cannot be read as an object: writing on
    top of it would replace it with only the keys one subcommand happens to touch,
    so the caller must stop instead of starting from an empty dict.
    Raises PermissionError when the file belongs to somebody else or is a symlink.
    """
    if not path:
        return {}
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return {}
    except OSError:
        return None
    if stat.S_ISLNK(st.st_mode):
        raise PermissionError("settings.json must not be a symlink")
    if not stat.S_ISREG(st.st_mode):
        return None
    if hasattr(os, "geteuid") and st.st_uid != os.geteuid():
        raise PermissionError("settings.json not owned by current user")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def load_settings_or_exit(path):
    """Load settings.json or exit 1 with a clear stderr message on error."""
    try:
        settings = load_settings(path)
    except PermissionError as exc:
        sys.stderr.write(f"Security Error: {exc}\n")
        sys.exit(1)
    if settings is None:
        sys.stderr.write("Error: settings.json is not readable as JSON, so nothing was changed\n")
        sys.exit(1)
    return settings


def save_settings(path, data):
    parent = os.path.dirname(os.path.abspath(path)) or "."
    if hasattr(os, "geteuid"):
        pst = os.lstat(parent)
        if stat.S_ISLNK(pst.st_mode) or pst.st_uid != os.geteuid():
            raise PermissionError("settings.json directory not owned by current user")
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".tmp.", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
