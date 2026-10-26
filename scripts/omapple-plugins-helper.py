#!/usr/bin/env -S python3 -I
"""
scripts/omapple-plugins-helper.py
Helper for discovering, installing, updating, and removing Apple/T2-related Omarchy plugins.
Queries the Omarchy Plugins catalog (https://plugins.omarchy.org/catalog.json) matching query q=T2.
"""

import sys

# Ensure caller-controlled directories or current working directory cannot be imported from
sys.path = [p for p in sys.path if p and p != "." and not p.startswith(".")]

import os

# If running as root / privileged, switch away from caller-controlled CWD
if hasattr(os, "geteuid") and os.geteuid() == 0:
    try:
        os.chdir("/")
    except Exception:
        pass
import json
import re
import time
import socket
import subprocess
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime

CATALOG_URL = "https://plugins.omarchy.org/catalog.json"
STATS_URL = "https://api.omarchyplugins.com/v1/stats"
QUERY_URL = "https://plugins.omarchy.org/?q=T2"
CACHE_DIR = os.path.expanduser("~/.cache/omarchy")
CACHE_FILE = os.path.join(CACHE_DIR, "omapple-plugins-catalog.json")
STATS_CACHE_FILE = os.path.join(CACHE_DIR, "omapple-plugins-stats.json")
CACHE_TTL = 3600  # 1 hour
PLUGINS_DIR = os.path.expanduser("~/.config/omarchy/plugins")

# Hard ceilings for remote JSON payloads. A compromised catalog/stats endpoint
# must not be able to exhaust helper memory, so every fetch is bounded by
# declared size, streamed size, wall-clock budget and parsed entry count, and
# every retained cache is read under the same byte ceiling. Exceeding any
# ceiling fails closed and falls back to the cache, then to the built-in list.
# The ceilings sit above the current legitimate payloads with ~2x headroom so a
# growing catalog keeps working: catalog.json is ~15.1 MB with 5,952 plugins and
# the stats API is ~0.38 MB with 6,045 entries.
MAX_CATALOG_BYTES = 32000000
MAX_STATS_BYTES = 1500000
MAX_CATALOG_PLUGINS = 12000
MAX_STATS_ENTRIES = 15000
FETCH_CHUNK = 65536
# Wall-clock budget for reading a whole body: a slow-drip endpoint stays under
# the per-read socket timeout, so bound the total time as well. The catalog is
# ~15 MB, so the budget must allow a sustained transfer on a normal link.
CATALOG_FETCH_BUDGET = 45.0
STATS_FETCH_BUDGET = 8.0

# Built-in fallback in case network is down and cache doesn't exist
FALLBACK_T2_PLUGINS = [
    {
        "id": "io.github.niraj-envision.touch-bar",
        "name": "Touch Bar",
        "author": "niraj-envision",
        "version": "2.0.1",
        "description": "Context-aware, themed Touch Bar for T2 MacBooks: app shortcuts, live browser tabs, Codex and Claude usage telemetry, dictation, sliders, media and system vitals.",
        "repo": "https://github.com/niraj-envision/touch-bar",
        "installCommand": "omarchy plugin add https://github.com/niraj-envision/touch-bar.git --enable",
        "tags": ["bar", "hyprland", "system"],
        "stars": 3,
        "rank": 1030,
        "rankLabel": "#1030",
        "views": 1014,
        "copies": 0,
        "hearts": 13,
        "accent": "lime"
    },
    {
        "id": "tonybo.touchbar-radio",
        "name": "Music Touchbar",
        "author": "tonybo",
        "version": "1.4.0",
        "description": "T2 Touch Bar controls for Radio Atlas, Sonora and Apple Music, with synced lyrics, local Japanese-to-Chinese translation, live spectrum, artwork, and song details.",
        "repo": "https://github.com/tonybo/omarchy-music-touchbar",
        "installCommand": "omarchy plugin add https://github.com/tonybo/omarchy-music-touchbar.git --enable",
        "tags": ["media", "hyprland", "quickshell"],
        "stars": 0,
        "rank": 1943,
        "rankLabel": "#1943",
        "views": 196,
        "copies": 28,
        "hearts": 3,
        "accent": "cyan"
    },
    {
        "id": "io.github.yadav-prakhar.omafan",
        "name": "omafan",
        "author": "Prakhar Yadav",
        "version": "1.0.0",
        "description": "Fan control for pre-T2 Intel Macs: firmware auto, five presets and an RPM slider on top of afanctl, with live temperature and RPM in the bar.",
        "repo": "https://github.com/yadav-prakhar/omafan",
        "installCommand": "omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable",
        "tags": ["power-management", "bar", "quickshell"],
        "stars": 0,
        "rank": 2342,
        "rankLabel": "#2342",
        "views": 134,
        "copies": 35,
        "hearts": 2,
        "accent": "lime"
    },
    {
        "id": "io.github.endijs.t2-fan-control",
        "name": "T2 Fan Control",
        "author": "Endijs",
        "version": "1.2.0",
        "description": "Monitor and configure t2fanrd from the Omarchy bar",
        "repo": "https://github.com/Endijs/omarchy-t2-fan-control",
        "installCommand": "omarchy plugin add https://github.com/Endijs/omarchy-t2-fan-control.git --enable",
        "tags": ["bar", "quickshell", "system"],
        "stars": 0,
        "rank": 2485,
        "rankLabel": "#2485",
        "views": 260,
        "copies": 0,
        "hearts": 4,
        "accent": "lime"
    },
    {
        "id": "marchybar.touchbar",
        "name": "MarchyBar",
        "author": "Githubguy132010",
        "version": "1.0.1",
        "description": "Your Touch Bar, at home in Omarchy. Editable presets, live controls and automatic app layouts for Intel T2 Macs.",
        "repo": "https://github.com/Githubguy132010/MarchyBar",
        "installCommand": "omarchy plugin add https://github.com/Githubguy132010/MarchyBar.git --enable",
        "tags": ["bar", "media", "quickshell"],
        "stars": 0,
        "rank": 3004,
        "rankLabel": "#3004",
        "views": 129,
        "copies": 16,
        "hearts": 1,
        "accent": "cyan"
    },
    {
        "id": "benekuehn.macbook-fans",
        "name": "MacBook Fans",
        "author": "benekuehn",
        "version": "1.0.0",
        "description": "MacBook T2 fan profiles and live fan speeds",
        "repo": "https://github.com/benekuehn/omarchy.mac-fans",
        "installCommand": "omarchy plugin add https://github.com/benekuehn/omarchy.mac-fans.git --enable",
        "tags": ["bar"],
        "stars": 1,
        "rank": 3257,
        "rankLabel": "#3257",
        "views": 198,
        "copies": 0,
        "hearts": 0,
        "accent": "amber"
    }
]


import tempfile


def user_owned_dir(path):
    if not os.path.exists(path):
        return True
    try:
        return os.stat(path).st_uid == os.geteuid()
    except Exception:
        return False


def ensure_cache_dir():
    if os.path.exists(CACHE_DIR) and not user_owned_dir(CACHE_DIR):
        raise PermissionError(f"Cache directory not owned by current user: {CACHE_DIR}")
    os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)


def safe_write_json(file_path, data):
    ensure_cache_dir()
    parent = os.path.dirname(file_path) or "."
    if not user_owned_dir(parent):
        raise PermissionError(f"Cache directory not owned by current user: {parent}")
    fd, tmp_path = tempfile.mkstemp(prefix=os.path.basename(file_path) + ".tmp.", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, file_path)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
        raise


def load_json_cache(file_path, max_bytes):
    """Load a retained cache under the same byte ceiling as a live fetch.

    A cache written by an older, unbounded helper can be arbitrarily large, so
    a payload a compromised endpoint supplied back then still exhausts helper
    memory when the cache is read after upgrade, including as the fallback
    after a failed fetch. Check the size and cap the read so oversized legacy
    caches fail closed like an oversized response does.
    """
    size = os.path.getsize(file_path)
    if size > max_bytes:
        raise ValueError(
            "Cache file %s is %d bytes, above the %d byte ceiling"
            % (file_path, size, max_bytes)
        )
    with open(file_path, "rb") as f:
        raw = f.read(max_bytes + 1)
    if len(raw) > max_bytes:
        # The file grew between stat and read; the capped read is authoritative.
        raise ValueError(
            "Cache file %s exceeded the %d byte ceiling while reading"
            % (file_path, max_bytes)
        )
    return json.loads(raw.decode("utf-8"))


def safe_plugin_path(plugin_id, *parts):
    if not plugin_id or not re.match(r"^[a-zA-Z0-9_.-]+$", plugin_id) or plugin_id.startswith("-"):
        return None
    base = os.path.realpath(PLUGINS_DIR)
    candidate = os.path.realpath(os.path.join(base, plugin_id, *parts))
    if candidate != base and not candidate.startswith(base + os.sep):
        return None
    return candidate


def _read_capped(response, max_bytes, deadline):
    """Read a response body under a hard byte and wall-clock ceiling.

    An endpoint can ignore Content-Length and stream an unbounded body, and a
    slow-drip body evades the per-read socket timeout. Both are bounded here.
    The caller treats the raised ValueError as a fetch failure and falls back
    to the on-disk cache.
    """
    declared = response.headers.get("Content-Length")
    if declared is not None:
        try:
            declared_bytes = int(str(declared).strip())
        except (TypeError, ValueError):
            declared_bytes = None
        if declared_bytes is not None and declared_bytes > max_bytes:
            raise ValueError(
                "Response declares %s bytes, above the %d byte ceiling"
                % (declared_bytes, max_bytes)
            )

    chunks = []
    total = 0
    while True:
        chunk = response.read(FETCH_CHUNK)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise ValueError("Response exceeded the %d byte ceiling" % max_bytes)
        if time.monotonic() > deadline:
            raise ValueError("Response exceeded fetch budget")
        chunks.append(chunk)
    return b"".join(chunks)


class BoundedRedirectHandler(urllib.request.HTTPRedirectHandler):
    """HTTP redirect handler that enforces bounded memory, budget, and scheme.

    Standard urllib drains redirect bodies with unbounded fp.read() inside
    HTTPRedirectHandler.http_error_302 before returning the response. This
    handler closes the response socket immediately without draining the body,
    bounds the wall-clock budget, restricts redirection strictly to HTTPS, and
    caps max redirections.
    """

    max_redirections = 3
    max_repeats = 1

    def __init__(self, deadline, max_bytes):
        super().__init__()
        self.deadline = deadline
        self.max_bytes = max_bytes

    def http_error_302(self, req, fp, code, msg, headers):
        # Prevent urllib's unbounded fp.read() by closing response immediately
        try:
            fp.close()
        except Exception:
            pass

        if time.monotonic() > self.deadline:
            raise ValueError("Fetch exceeded wall-clock budget during redirect")

        declared = headers.get("Content-Length")
        if declared is not None:
            try:
                declared_bytes = int(str(declared).strip())
                if declared_bytes > self.max_bytes:
                    raise ValueError(
                        f"Redirect response declared {declared_bytes} bytes, above {self.max_bytes} byte ceiling"
                    )
            except (TypeError, ValueError) as err:
                if "above" in str(err):
                    raise

        if "location" in headers:
            newurl = headers["location"]
        elif "uri" in headers:
            newurl = headers["uri"]
        else:
            return None

        newurl = urllib.parse.urljoin(req.full_url, newurl)
        urlparts = urllib.parse.urlparse(newurl)
        if urlparts.scheme != "https":
            raise urllib.error.HTTPError(
                newurl,
                code,
                f"Redirection to non-HTTPS URL '{newurl}' is forbidden",
                headers,
                None,
            )

        new = self.redirect_request(req, fp, code, msg, headers, newurl)
        if new is None:
            return None

        if hasattr(req, "redirect_dict"):
            visited = new.redirect_dict = req.redirect_dict
            if (
                visited.get(newurl, 0) >= self.max_repeats
                or len(visited) >= self.max_redirections
            ):
                raise urllib.error.HTTPError(
                    req.full_url, code, self.inf_msg + msg, headers, None
                )
        else:
            visited = new.redirect_dict = req.redirect_dict = {}
        visited[newurl] = visited.get(newurl, 0) + 1

        rem_budget = self.deadline - time.monotonic()
        if rem_budget <= 0:
            raise ValueError("Fetch exceeded wall-clock budget during redirect")
        if isinstance(getattr(req, "timeout", None), (int, float)):
            timeout = min(req.timeout, rem_budget)
        else:
            timeout = rem_budget

        return self.parent.open(new, timeout=timeout)

    http_error_301 = http_error_303 = http_error_307 = http_error_308 = http_error_302


def make_bounded_opener(deadline, max_bytes):
    opener = urllib.request.OpenerDirector()
    opener.add_handler(urllib.request.ProxyHandler())
    opener.add_handler(urllib.request.HTTPSHandler())
    opener.add_handler(urllib.request.HTTPDefaultErrorHandler())
    opener.add_handler(urllib.request.HTTPErrorProcessor())
    opener.add_handler(urllib.request.UnknownHandler())
    opener.add_handler(BoundedRedirectHandler(deadline=deadline, max_bytes=max_bytes))
    return opener


def http_get_json(url, timeout, max_bytes, budget):
    """Fetch a JSON document over HTTPS with bounded memory and time."""
    if not url.startswith("https://"):
        raise ValueError(f"Only HTTPS URLs are allowed: {url}")

    deadline = time.monotonic() + budget
    opener = make_bounded_opener(deadline, max_bytes)
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "Omarchy-T2-Linux-Plugin/1.0 (+https://plugins.omarchy.org)",
        },
    )
    rem_budget = max(0.1, deadline - time.monotonic())
    with opener.open(req, timeout=min(timeout, rem_budget)) as response:
        raw = _read_capped(response, max_bytes, deadline)
    return json.loads(raw.decode("utf-8"))


def fetch_catalog(force_refresh=False):
    ensure_cache_dir()
    now = time.time()

    if not force_refresh and os.path.exists(CACHE_FILE):
        try:
            mtime = os.path.getmtime(CACHE_FILE)
            if now - mtime < CACHE_TTL:
                return load_json_cache(CACHE_FILE, MAX_CATALOG_BYTES)
        except Exception:
            pass

    # Try downloading fresh catalog, with bounded size, time and entry count
    try:
        data = http_get_json(CATALOG_URL, 6, MAX_CATALOG_BYTES, CATALOG_FETCH_BUDGET)
        if not isinstance(data, dict):
            raise ValueError("Catalog payload is not a JSON object")
        plugins = data.get("plugins")
        if isinstance(plugins, list) and len(plugins) > MAX_CATALOG_PLUGINS:
            raise ValueError(
                "Catalog lists %d plugins, above the %d entry ceiling"
                % (len(plugins), MAX_CATALOG_PLUGINS)
            )
        safe_write_json(CACHE_FILE, data)
        return data
    except Exception:
        # Fall back to cache if available
        if os.path.exists(CACHE_FILE):
            try:
                return load_json_cache(CACHE_FILE, MAX_CATALOG_BYTES)
            except Exception:
                pass
        return {"plugins": FALLBACK_T2_PLUGINS}


def fetch_stats(force_refresh=False):
    ensure_cache_dir()
    now = time.time()

    if not force_refresh and os.path.exists(STATS_CACHE_FILE):
        try:
            mtime = os.path.getmtime(STATS_CACHE_FILE)
            if now - mtime < CACHE_TTL:
                return load_json_cache(STATS_CACHE_FILE, MAX_STATS_BYTES)
        except Exception:
            pass

    # Try downloading fresh engagement stats, with bounded size, time and entries
    try:
        data = http_get_json(STATS_URL, 5, MAX_STATS_BYTES, STATS_FETCH_BUDGET)
        if not isinstance(data, dict):
            raise ValueError("Stats payload is not a JSON object")
        stats = data.get("plugins", {})
        if not isinstance(stats, dict):
            raise ValueError("Stats payload has no per-plugin object")
        if len(stats) > MAX_STATS_ENTRIES:
            raise ValueError(
                "Stats list %d entries, above the %d entry ceiling"
                % (len(stats), MAX_STATS_ENTRIES)
            )
        safe_write_json(STATS_CACHE_FILE, stats)
        return stats
    except Exception:
        if os.path.exists(STATS_CACHE_FILE):
            try:
                return load_json_cache(STATS_CACHE_FILE, MAX_STATS_BYTES)
            except Exception:
                pass
        return {}


def compute_engagement_ranks(plugins, stats):
    """
    Computes engagement ranks exactly like https://plugins.omarchy.org/assets/js/shared.js.
    Rank metrics evaluated: hearts, copies, views, stars.
    """
    metrics = ["hearts", "copies", "views", "stars"]
    stars_map = {p.get("id"): int(p.get("stars", 0) or 0) for p in plugins if p.get("id")}

    def get_count(pid, metric):
        if metric == "stars":
            return stars_map.get(pid, 0)
        return int(stats.get(pid, {}).get(metric, 0) or 0)

    ids = [p.get("id") for p in plugins if p.get("id")]
    ranked_ids = [pid for pid in ids if any(get_count(pid, m) > 0 for m in metrics)]

    ranks = {pid: {} for pid in ids}

    for metric in metrics:
        ordered = sorted(ranked_ids, key=lambda pid: (-get_count(pid, metric), pid))
        rank = 0
        prev = None
        for idx, pid in enumerate(ordered):
            val = get_count(pid, metric)
            if val != prev:
                rank = idx + 1
            prev = val
            ranks[pid][metric] = rank

    def score(pid):
        return sum(ranks[pid].get(m, len(ranked_ids) + 1) for m in metrics)

    overall_ordered = sorted(ranked_ids, key=lambda pid: (score(pid), pid))
    rank = 0
    prev = None
    for idx, pid in enumerate(overall_ordered):
        s = score(pid)
        if s != prev:
            rank = idx + 1
        prev = s
        ranks[pid]["overall"] = rank

    return ranks


def get_installed_plugins_map():
    installed = {}
    try:
        raw = subprocess.check_output(
            ["omarchy", "plugin", "list", "--json"],
            stderr=subprocess.DEVNULL,
            timeout=5
        ).decode("utf-8")
        items = json.loads(raw)
        for item in items:
            pid = item.get("id")
            if pid:
                installed[pid] = item
    except Exception:
        # Fallback inspection of ~/.config/omarchy/plugins
        if os.path.isdir(PLUGINS_DIR):
            for entry in os.listdir(PLUGINS_DIR):
                pdir = safe_plugin_path(entry)
                if pdir and os.path.isdir(pdir):
                    manifest_file = os.path.join(pdir, "manifest.json")
                    v = "1.0.0"
                    if os.path.exists(manifest_file):
                        try:
                            with open(manifest_file) as mf:
                                v = json.load(mf).get("version", "1.0.0")
                        except Exception:
                            pass
                    installed[entry] = {
                        "id": entry,
                        "enabled": True,
                        "installed": True,
                        "version": v
                    }
    return installed


def get_local_plugin_version(plugin_id):
    manifest_file = safe_plugin_path(plugin_id, "manifest.json")
    if not manifest_file:
        return ""
    if os.path.isfile(manifest_file):
        try:
            with open(manifest_file, "r", encoding="utf-8") as f:
                return json.load(f).get("version", "")
        except Exception:
            pass
    return ""


def parse_semver(v_str):
    if not v_str:
        return [0, 0, 0]
    clean = re.sub(r'^[^\d]*', '', str(v_str)).split('-')[0].split('+')[0]
    parts = []
    for p in clean.split('.'):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return parts[:3]


def is_version_newer(remote_v, local_v):
    if not remote_v or not local_v:
        return False
    return parse_semver(remote_v) > parse_semver(local_v)


def matches_q_t2(plugin):
    """
    Search logic matching https://plugins.omarchy.org/?q=T2:
    Tokens starting with 't2' in name, id, description, tags, or author.
    """
    name = plugin.get("name", "")
    pid = plugin.get("id", "")
    desc = plugin.get("description", "")
    tags = " ".join(plugin.get("tags", []))
    author = plugin.get("author", "")
    full_text = f"{name} {pid} {desc} {tags} {author}".lower()
    words = re.findall(r'[\w]+', full_text)
    return any(w.startswith("t2") for w in words)


def is_apple_plugin(plugin):
    """
    Search logic for all Apple-related Omarchy plugins:
    Matches Apple, MacBook, Mac, macOS, Touch Bar, AirDrop, Sidecar, iCloud, Magic Mouse/Trackpad, etc.
    """
    pid = plugin.get("id", "")
    if pid == "bramvanoploo.omarchy-t2-linux":
        return False

    if matches_q_t2(plugin):
        return True

    name = plugin.get("name", "").lower()
    pid_lower = pid.lower()
    desc = plugin.get("description", "").lower()
    tags = [t.lower() for t in plugin.get("tags", [])]
    author = plugin.get("author", "").lower()
    full_text = f"{name} {pid_lower} {desc} {' '.join(tags)} {author}"

    apple_phrases = [
        "apple", "macbook", "macos", "mac os", "mac-style", "mac style",
        "mac-like", "mac like", "touch bar", "touchbar", "touch-bar",
        "imac", "mac mini", "mac pro", "magic mouse", "magic trackpad",
        "magic keyboard", "butterfly keyboard", "airdrop", "airplay",
        "sidecar", "icloud", "mbpfan", "afanctl", "tiny-dfr",
        "apple silicon", "apple tv", "apple music", "studio display",
        "omafan", "kait2en", "t2fanrd", "retina", "speaker-calibrator"
    ]
    for phrase in apple_phrases:
        if phrase in full_text:
            return True

    if any(t in ["apple", "mac", "macos", "macbook", "t2", "touchbar"] for t in tags):
        return True

    # Standalone "mac" word, ignoring "mac address" / "mac addresses"
    clean_desc = re.sub(r'\bmac\s+address(es)?\b', '', desc)
    clean_text = f"{name} {pid_lower} {clean_desc} {author}"
    if re.search(r'\bmac(s)?\b', clean_text):
        return True

    return False


def parse_listing_time(plugin):
    val = plugin.get("listedAt") or plugin.get("addedAt") or ""
    try:
        if "T" in val:
            return datetime.fromisoformat(val.replace("Z", "+00:00")).timestamp()
        elif val:
            return datetime.fromisoformat(val + "T00:00:00+00:00").timestamp()
    except Exception:
        pass
    return 0.0


def list_plugins(force_refresh=False):
    catalog = fetch_catalog(force_refresh)
    catalog_plugins = catalog.get("plugins", [])
    stats = fetch_stats(force_refresh)
    ranks = compute_engagement_ranks(catalog_plugins, stats)
    installed_map = get_installed_plugins_map()

    matched_dict = {}

    # 1. Matches for Apple & T2 plugins
    for p in catalog_plugins:
        pid = p.get("id", "")
        # Don't show this plugin itself
        if pid == "bramvanoploo.omarchy-t2-linux":
            continue

        if is_apple_plugin(p):
            t2_flag = matches_q_t2(p)
            inst = installed_map.get(pid)
            is_installed = inst is not None or (bool(safe_plugin_path(pid)) and os.path.exists(os.path.join(safe_plugin_path(pid), "")))
            is_enabled = inst.get("enabled", False) if inst else False

            local_v = get_local_plugin_version(pid) if is_installed else ""
            remote_v = p.get("version", "1.0.0")

            # Check update
            update_avail = False
            if is_installed and local_v:
                update_avail = is_version_newer(remote_v, local_v)

            repo = p.get("repo", "")
            install_cmd = p.get("installCommand", "")
            if not install_cmd and repo:
                git_url = repo if repo.endswith(".git") else f"{repo}.git"
                install_cmd = f"omarchy plugin add {git_url} --enable"

            rank_info = ranks.get(pid, {})
            rank_val = rank_info.get("overall")
            rank_label = f"#{rank_val}" if rank_val else ""
            p_stats = stats.get(pid, {})

            entry = {
                "id": pid,
                "name": p.get("name", pid),
                "author": p.get("author", "Community"),
                "description": p.get("description", ""),
                "version": remote_v,
                "installedVersion": local_v,
                "installed": is_installed,
                "enabled": is_enabled,
                "updateAvailable": update_avail,
                "repo": repo,
                "installCommand": install_cmd,
                "tags": p.get("tags", []),
                "stars": p.get("stars", 0),
                "rank": rank_val,
                "rankLabel": rank_label,
                "views": p_stats.get("views", 0),
                "copies": p_stats.get("copies", 0),
                "hearts": p_stats.get("hearts", 0),
                "accent": p.get("accent", "cyan"),
                "webUrl": f"https://plugins.omarchy.org/plugin.html?id={urllib.parse.quote(pid)}",
                "isExactT2": t2_flag,
                "isT2": t2_flag,
                "isApple": True,
                "category": "T2 Plugin" if t2_flag else "Apple Plugin",
                "_listingTime": parse_listing_time(p)
            }
            matched_dict[pid] = entry

    # Ensure known fallback T2 plugins are included if not present
    for fb in FALLBACK_T2_PLUGINS:
        pid = fb["id"]
        if pid not in matched_dict and pid != "bramvanoploo.omarchy-t2-linux":
            inst = installed_map.get(pid)
            is_installed = inst is not None or (bool(safe_plugin_path(pid)) and os.path.exists(os.path.join(safe_plugin_path(pid), "")))
            is_enabled = inst.get("enabled", False) if inst else False
            local_v = get_local_plugin_version(pid) if is_installed else ""
            remote_v = fb.get("version", "1.0.0")

            update_avail = is_version_newer(remote_v, local_v) if is_installed and local_v else False
            rank_info = ranks.get(pid, {})
            rank_val = rank_info.get("overall", fb.get("rank"))
            rank_label = f"#{rank_val}" if rank_val else fb.get("rankLabel", "")
            p_stats = stats.get(pid, {})

            matched_dict[pid] = {
                "id": pid,
                "name": fb.get("name", pid),
                "author": fb.get("author", "Community"),
                "description": fb.get("description", ""),
                "version": remote_v,
                "installedVersion": local_v,
                "installed": is_installed,
                "enabled": is_enabled,
                "updateAvailable": update_avail,
                "repo": fb.get("repo", ""),
                "installCommand": fb.get("installCommand", ""),
                "tags": fb.get("tags", []),
                "stars": fb.get("stars", 0),
                "rank": rank_val,
                "rankLabel": rank_label,
                "views": p_stats.get("views", fb.get("views", 0)),
                "copies": p_stats.get("copies", fb.get("copies", 0)),
                "hearts": p_stats.get("hearts", fb.get("hearts", 0)),
                "accent": fb.get("accent", "lime"),
                "webUrl": f"https://plugins.omarchy.org/plugin.html?id={urllib.parse.quote(pid)}",
                "isExactT2": True,
                "isT2": True,
                "isApple": True,
                "category": "T2 Plugin",
                "_listingTime": parse_listing_time(fb)
            }

    # Site default sort: recently added (listingTime descending, then name ascending)
    items = list(matched_dict.values())
    if "--t2-only" in sys.argv:
        items = [x for x in items if x.get("isT2") or x.get("isExactT2")]

    items.sort(key=lambda x: (-x.get("_listingTime", 0.0), x["name"].lower()))
    for x in items:
        x.pop("_listingTime", None)

    output = {
        "status": "ok",
        "fetchedAt": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "sourceUrl": "https://plugins.omarchy.org/?q=Apple",
        "query": "q=Apple",
        "totalCount": len(items),
        "appleCount": len(items),
        "t2Count": sum(1 for x in items if x.get("isT2") or x.get("isExactT2")),
        "installedCount": sum(1 for x in items if x["installed"]),
        "plugins": items
    }
    print(json.dumps(output, indent=2))


def run_cmd(cmd_list):
    try:
        proc = subprocess.run(
            cmd_list,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
            start_new_session=True
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def install_plugin(repo_or_url, plugin_id=""):
    if not repo_or_url:
        print(json.dumps({"success": False, "error": "No repo URL provided"}))
        sys.exit(1)

    url = repo_or_url.strip()
    if url.startswith("-"):
        print(json.dumps({"success": False, "error": f"Invalid repository URL format: {repo_or_url}"}))
        sys.exit(1)
    if not re.match(r'^(https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:\.git)?|git@github\.com:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:\.git)?)$', url):
        print(json.dumps({"success": False, "error": f"Invalid GitHub repository URL: {repo_or_url}"}))
        sys.exit(1)

    if not url.startswith("http://") and not url.startswith("https://") and not url.startswith("git@"):
        url = f"https://github.com/{url}"
    if not url.endswith(".git") and "github.com" in url:
        url = f"{url}.git"

    rc, out, err = run_cmd(["omarchy", "plugin", "add", url, "--enable", "--yes"])
    if rc == 0:
        print(json.dumps({"success": True, "message": out or "Plugin installed and enabled."}))
        sys.exit(0)
    else:
        print(json.dumps({"success": False, "error": err or out or "Failed to install plugin."}))
        sys.exit(rc or 1)


def update_plugin(plugin_id):
    if not plugin_id or not re.match(r'^[a-zA-Z0-9_.-]+$', plugin_id) or plugin_id.startswith("-"):
        print(json.dumps({"success": False, "error": f"Invalid plugin ID: {plugin_id}"}))
        sys.exit(1)

    rc, out, err = run_cmd(["omarchy", "plugin", "update", plugin_id, "--yes"])
    if rc == 0:
        print(json.dumps({"success": True, "message": out or f"{plugin_id} updated successfully."}))
        sys.exit(0)
    else:
        print(json.dumps({"success": False, "error": err or out or "Failed to update plugin."}))
        sys.exit(rc or 1)


def remove_plugin(plugin_id):
    if not plugin_id or not re.match(r'^[a-zA-Z0-9_.-]+$', plugin_id) or plugin_id.startswith("-"):
        print(json.dumps({"success": False, "error": f"Invalid plugin ID: {plugin_id}"}))
        sys.exit(1)

    rc, out, err = run_cmd(["omarchy", "plugin", "remove", plugin_id, "--yes"])
    if rc == 0:
        print(json.dumps({"success": True, "message": out or f"{plugin_id} removed successfully."}))
        sys.exit(0)
    else:
        print(json.dumps({"success": False, "error": err or out or "Failed to remove plugin."}))
        sys.exit(rc or 1)


def toggle_plugin(plugin_id, state):
    if not plugin_id or not re.match(r'^[a-zA-Z0-9_.-]+$', plugin_id) or plugin_id.startswith("-"):
        print(json.dumps({"success": False, "error": f"Invalid plugin ID: {plugin_id}"}))
        sys.exit(1)

    subcmd = "enable" if state in ("enable", "true", "1", "on") else "disable"
    rc, out, err = run_cmd(["omarchy", "plugin", subcmd, plugin_id])
    if rc == 0:
        print(json.dumps({"success": True, "message": f"{plugin_id} {subcmd}d."}))
        sys.exit(0)
    else:
        print(json.dumps({"success": False, "error": err or out or f"Failed to {subcmd} plugin."}))
        sys.exit(rc or 1)


def check_speaker_calibrator_source_available():
    """
    Checks if the installation source for the speaker-calibrator plugin is available.
    Returns True if:
    1. The catalog has an active installable entry for the plugin (installAvailable != False, status != unavailable),
       AND
    2. Network reachability to repository/catalog hosts is functional.
    """
    # 1. Check network connectivity to repository host (github.com)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.6)
        res = s.connect_ex(("github.com", 443))
        s.close()
        if res != 0:
            return False
    except Exception:
        return False

    # 2. Check catalog cache / listing
    catalog = None
    if os.path.exists(CACHE_FILE):
        try:
            catalog = load_json_cache(CACHE_FILE, MAX_CATALOG_BYTES)
        except Exception:
            pass

    if catalog and "plugins" in catalog:
        found = False
        for p in catalog.get("plugins", []):
            if p.get("id") == "thefreshoffice.speaker-calibrator":
                found = True
                if p.get("installAvailable") is False:
                    return False
                st = str(p.get("status", "")).lower()
                if st in ("unavailable", "deprecated", "removed", "disabled", "archived"):
                    return False
                repo = p.get("repo") or p.get("installCommand")
                if not repo:
                    return False
                break
        if not found:
            return False

    return True


def get_speaker_calibrator_status():
    plugins_dir = os.path.expanduser("~/.config/omarchy/plugins/thefreshoffice.speaker-calibrator")
    installed = os.path.isdir(plugins_dir)
    enabled = False
    version = ""
    active_profile = ""
    service_active = False

    if installed:
        manifest_path = os.path.join(plugins_dir, "manifest.json")
        if os.path.exists(manifest_path):
            try:
                with open(manifest_path, "r", encoding="utf-8") as f:
                    m = json.load(f)
                    version = m.get("version", "")
            except Exception:
                pass

        shell_path = os.path.expanduser("~/.config/omarchy/shell.json")
        if os.path.exists(shell_path):
            try:
                with open(shell_path, "r", encoding="utf-8") as f:
                    shell_data = json.load(f)
                    disabled = set(shell_data.get("disabledPlugins", []))
                    if "thefreshoffice.speaker-calibrator" not in disabled:
                        layout = shell_data.get("bar", {}).get("layout", {})
                        in_bar = any(
                            item.get("id") == "thefreshoffice.speaker-calibrator"
                            for sec in ("left", "center", "right")
                            for item in layout.get(sec, [])
                        )
                        in_plugins = any(
                            item.get("id") == "thefreshoffice.speaker-calibrator"
                            for item in shell_data.get("plugins", [])
                        )
                        enabled = in_bar or in_plugins
            except Exception:
                pass

        cache_path = os.path.expanduser("~/.local/share/omarchy-speaker-calibrator/status-cache.json")
        if os.path.exists(cache_path):
            try:
                with open(cache_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    service_active = bool(data.get("service") == "active" or data.get("enabled"))
                    compare = data.get("compare", {})
                    curr = compare.get("current", {})
                    if curr.get("label"):
                        active_profile = curr.get("label")
            except Exception:
                pass

        if not active_profile:
            cal_script = os.path.join(plugins_dir, "speaker-calibrate.py")
            if os.path.exists(cal_script):
                try:
                    proc = subprocess.run(["python3", cal_script, "status-cache-json"], capture_output=True, text=True, timeout=2)
                    if proc.returncode == 0:
                        data = json.loads(proc.stdout)
                        service_active = bool(data.get("service") == "active" or data.get("enabled"))
                        compare = data.get("compare", {})
                        curr = compare.get("current", {})
                        if curr.get("label"):
                            active_profile = curr.get("label")
                except Exception:
                    pass

    source_available = True
    if not installed:
        source_available = check_speaker_calibrator_source_available()

    return {
        "id": "thefreshoffice.speaker-calibrator",
        "name": "Speaker Calibrator",
        "url": "https://plugins.omarchy.org/plugin.html?id=thefreshoffice.speaker-calibrator",
        "repo": "https://github.com/thefreshoffice/omarchy-speaker-calibrator.git",
        "installed": installed,
        "enabled": enabled,
        "version": version,
        "activeProfile": active_profile,
        "serviceActive": service_active,
        "sourceAvailable": source_available
    }


def check_user_access():
    if hasattr(os, "geteuid"):
        euid = os.geteuid()
        if euid == 0:
            print(json.dumps({"status": "error", "error": "Plugin operations cannot be run as root"}), file=sys.stderr)
            sys.exit(1)
        pkexec_uid = os.environ.get("PKEXEC_UID")
        if pkexec_uid is not None:
            try:
                if int(pkexec_uid) != euid:
                    print(json.dumps({"status": "error", "error": f"Security Error: Cross-user access denied for plugin operations (caller UID {pkexec_uid} != target UID {euid})"}), file=sys.stderr)
                    sys.exit(1)
            except ValueError:
                pass
        sudo_uid = os.environ.get("SUDO_UID")
        if sudo_uid is not None:
            try:
                if int(sudo_uid) != euid:
                    print(json.dumps({"status": "error", "error": f"Security Error: Cross-user access denied for plugin operations (caller UID {sudo_uid} != target UID {euid})"}), file=sys.stderr)
                    sys.exit(1)
            except ValueError:
                pass
        if os.path.exists(PLUGINS_DIR):
            try:
                stat = os.stat(PLUGINS_DIR)
                if stat.st_uid != euid:
                    print(json.dumps({"status": "error", "error": f"Security Error: Plugins directory not owned by current user (owner UID {stat.st_uid} != current UID {euid})"}), file=sys.stderr)
                    sys.exit(1)
            except Exception:
                pass


def emit_error(error):
    print(json.dumps({"status": "error", "error": str(error)}))
    sys.exit(1)


def main():
    check_user_access()
    if len(sys.argv) < 2:
        list_plugins()
        return

    cmd = sys.argv[1]
    if cmd in ("list", "plugins-list"):
        force = "--force-refresh" in sys.argv
        list_plugins(force_refresh=force)
    elif cmd in ("install", "plugin-install"):
        repo = sys.argv[2] if len(sys.argv) > 2 else ""
        pid = sys.argv[3] if len(sys.argv) > 3 else ""
        install_plugin(repo, pid)
    elif cmd in ("update", "plugin-update"):
        pid = sys.argv[2] if len(sys.argv) > 2 else ""
        update_plugin(pid)
    elif cmd in ("remove", "plugin-remove"):
        pid = sys.argv[2] if len(sys.argv) > 2 else ""
        remove_plugin(pid)
    elif cmd in ("toggle", "plugin-toggle"):
        pid = sys.argv[2] if len(sys.argv) > 2 else ""
        st = sys.argv[3] if len(sys.argv) > 3 else "enable"
        toggle_plugin(pid, st)
    elif cmd in ("status-speaker-calibrator", "speaker-calibrator-status"):
        print(json.dumps(get_speaker_calibrator_status(), indent=2))
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        emit_error(exc)
