#!/usr/bin/env python3
"""
scripts/t2-plugins-helper.py
Helper for discovering, installing, updating, and removing T2-related Omarchy plugins.
Queries the Omarchy Plugins catalog (https://plugins.omarchy.org/catalog.json) matching query q=T2.
"""

import sys
import os
import json
import re
import time
import subprocess
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime

CATALOG_URL = "https://plugins.omarchy.org/catalog.json"
STATS_URL = "https://api.omarchyplugins.com/v1/stats"
QUERY_URL = "https://plugins.omarchy.org/?q=T2"
CACHE_DIR = os.path.expanduser("~/.cache/omarchy")
CACHE_FILE = os.path.join(CACHE_DIR, "t2-plugins-catalog.json")
STATS_CACHE_FILE = os.path.join(CACHE_DIR, "t2-plugins-stats.json")
CACHE_TTL = 3600  # 1 hour
PLUGINS_DIR = os.path.expanduser("~/.config/omarchy/plugins")

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


def ensure_cache_dir():
    os.makedirs(CACHE_DIR, exist_ok=True)


def safe_write_json(file_path, data):
    ensure_cache_dir()
    tmp_path = file_path + ".tmp." + str(os.getpid())
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp_path, file_path)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass


def fetch_catalog(force_refresh=False):
    ensure_cache_dir()
    now = time.time()

    if not force_refresh and os.path.exists(CACHE_FILE):
        try:
            mtime = os.path.getmtime(CACHE_FILE)
            if now - mtime < CACHE_TTL:
                with open(CACHE_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception:
            pass

    # Try downloading fresh catalog
    try:
        req = urllib.request.Request(
            CATALOG_URL,
            headers={"User-Agent": "Omarchy-T2-Linux-Plugin/1.0 (+https://plugins.omarchy.org)"}
        )
        with urllib.request.urlopen(req, timeout=6) as response:
            data = json.loads(response.read().decode("utf-8"))
            safe_write_json(CACHE_FILE, data)
            return data
    except Exception:
        # Fall back to cache if available
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
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
                with open(STATS_CACHE_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception:
            pass

    # Try downloading fresh engagement stats
    try:
        req = urllib.request.Request(
            STATS_URL,
            headers={
                "Accept": "application/json",
                "User-Agent": "Omarchy-T2-Linux-Plugin/1.0 (+https://plugins.omarchy.org)"
            }
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            stats = data.get("plugins", {})
            safe_write_json(STATS_CACHE_FILE, stats)
            return stats
    except Exception:
        if os.path.exists(STATS_CACHE_FILE):
            try:
                with open(STATS_CACHE_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
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
                pdir = os.path.join(PLUGINS_DIR, entry)
                if os.path.isdir(pdir) or os.path.islink(pdir):
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
    manifest_file = os.path.join(PLUGINS_DIR, plugin_id, "manifest.json")
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

    # 1. Matches for q=T2
    for p in catalog_plugins:
        pid = p.get("id", "")
        # Don't show this plugin itself
        if pid == "bramvanoploo.omarchy-t2-linux":
            continue

        if matches_q_t2(p):
            inst = installed_map.get(pid)
            is_installed = inst is not None or os.path.exists(os.path.join(PLUGINS_DIR, pid))
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
                "isExactT2": True,
                "category": "T2 Plugin",
                "_listingTime": parse_listing_time(p)
            }
            matched_dict[pid] = entry

    # Ensure known fallback T2 plugins are included if not present
    for fb in FALLBACK_T2_PLUGINS:
        pid = fb["id"]
        if pid not in matched_dict and pid != "bramvanoploo.omarchy-t2-linux":
            inst = installed_map.get(pid)
            is_installed = inst is not None or os.path.exists(os.path.join(PLUGINS_DIR, pid))
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
                "category": "T2 Plugin",
                "_listingTime": parse_listing_time(fb)
            }

    # Site default sort: recently added (listingTime descending, then name ascending)
    items = list(matched_dict.values())
    items.sort(key=lambda x: (-x.get("_listingTime", 0.0), x["name"].lower()))
    for x in items:
        x.pop("_listingTime", None)

    output = {
        "status": "ok",
        "fetchedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
        "sourceUrl": QUERY_URL,
        "query": "q=T2",
        "totalCount": len(items),
        "exactT2Count": len(items),
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
            timeout=120
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def install_plugin(repo_or_url, plugin_id=""):
    if not repo_or_url:
        print(json.dumps({"success": False, "error": "No repo URL provided"}))
        sys.exit(1)

    url = repo_or_url.strip()
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
    if not plugin_id:
        print(json.dumps({"success": False, "error": "No plugin ID provided"}))
        sys.exit(1)

    rc, out, err = run_cmd(["omarchy", "plugin", "update", plugin_id, "--yes"])
    if rc == 0:
        print(json.dumps({"success": True, "message": out or f"{plugin_id} updated successfully."}))
        sys.exit(0)
    else:
        print(json.dumps({"success": False, "error": err or out or "Failed to update plugin."}))
        sys.exit(rc or 1)


def remove_plugin(plugin_id):
    if not plugin_id:
        print(json.dumps({"success": False, "error": "No plugin ID provided"}))
        sys.exit(1)

    rc, out, err = run_cmd(["omarchy", "plugin", "remove", plugin_id, "--yes"])
    if rc == 0:
        print(json.dumps({"success": True, "message": out or f"{plugin_id} removed successfully."}))
        sys.exit(0)
    else:
        print(json.dumps({"success": False, "error": err or out or "Failed to remove plugin."}))
        sys.exit(rc or 1)


def toggle_plugin(plugin_id, state):
    if not plugin_id:
        print(json.dumps({"success": False, "error": "No plugin ID provided"}))
        sys.exit(1)

    subcmd = "enable" if state in ("enable", "true", "1", "on") else "disable"
    rc, out, err = run_cmd(["omarchy", "plugin", subcmd, plugin_id])
    if rc == 0:
        print(json.dumps({"success": True, "message": f"{plugin_id} {subcmd}d."}))
        sys.exit(0)
    else:
        print(json.dumps({"success": False, "error": err or out or f"Failed to {subcmd} plugin."}))
        sys.exit(rc or 1)


def main():
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
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
