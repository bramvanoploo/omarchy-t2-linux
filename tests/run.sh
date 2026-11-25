#!/usr/bin/env bash
# tests/run.sh: the checks that catch the mistakes this repo actually makes -
# a subcommand the polkit rule or the QML names but the helper does not have,
# the two chord normalisers drifting apart, and a status payload that stops
# being valid JSON. Run: ./tests/run.sh
set -uo pipefail

# The setup flow runs this suite as root (sudo or pkexec); the helper refuses
# user-config subcommands as root (assert_user_operation), so drop back to the
# calling user before driving it.
target=""
if (( EUID == 0 )); then
  target="${SUDO_USER:-}"
  [[ -z "$target" && -n "${PKEXEC_UID:-}" ]] && target=$(id -nu "$PKEXEC_UID" 2>/dev/null || true)
fi
if [[ -n "$target" && "$target" != root ]] && command -v sudo >/dev/null 2>&1; then
  # env -u: the outer sudo sets SUDO_UID=<original>, and this nested sudo
  # re-adds its own (root, 0); the helper's cross-user guard sees neither as
  # matching the new EUID, so hand the test a clean user session instead.
  exec sudo -u "$target" env -u SUDO_USER -u SUDO_UID -u SUDO_GID \
    bash "$(readlink -f "$0")" "$@"
fi

cd "$(dirname "$0")/.." || exit 1
HELPER=scripts/omapple-helper
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Syntax of every executable source file.
bash -n "$HELPER" && ok "bash -n helper" || bad "bash -n helper"
python3 -I -m py_compile scripts/omapple-plugins-helper.py && ok "py_compile plugins helper" || bad "py_compile plugins helper"

# 2. The polkit allow-list and the QML may only name subcommands the helper dispatches.
dispatch=$(sed -n '/^case "${1:-status}" in/,/^esac/p' "$HELPER" | grep -oE '^  [a-z0-9|-]+\)' | tr -d ' )' | tr '|' '\n' | sort -u)
check_against_dispatch() { # $1 = label, $2 = list
  local cmd missing=""
  for cmd in $2; do
    grep -qx "$cmd" <<<"$dispatch" || missing="$missing $cmd"
  done
  if [[ -z "$missing" ]]; then ok "$1"; else bad "$1 names undispatched subcommands:$missing"; fi
}
check_against_dispatch "polkit allow-list is dispatched" \
  "$(grep -oE 'subcommand === "[a-z0-9-]+"' system/90-omapple.rules | cut -d'"' -f2 | sort -u)"
check_against_dispatch "BarWidget subcommands are dispatched" \
  "$(grep -ohE 'helper, "[a-z0-9-]+"' BarWidget.qml | cut -d'"' -f2 | sort -u)"

# 3. The chord normaliser inside the helper's python and the one in
# OmappleModel.js must agree: both name the same chords in the same strings.
if command -v node >/dev/null 2>&1; then
  # Bare modifiers are left out: the JS mirror keeps them for display, the python
  # writer refuses them (see test 6).
  printf '%s\n' 'SUPER + A' 'ctrl+a' 'CMD + Shift + Z' 'LOGO+ALT+Delete' 'META + Return' \
    'OPTION + CTRL + W' 'F11' 'CTRL + SUPER + a' 'pause' > "$tmp/chords"
  node -e 'const fs=require("fs");eval(fs.readFileSync(process.argv[1],"utf8"));const t=fs.readFileSync(process.argv[2],"utf8").split("\n").filter(x=>x);process.stdout.write(JSON.stringify(t.map(c=>normalizeChord(c))))' \
    OmappleModel.js "$tmp/chords" > "$tmp/js.json"
  # The python side is the shared module the helper imports, so the test imports
  # that module rather than scraping it back out of the helper.
  diff_out=$(python3 -I - "$tmp/chords" "$tmp/js.json" "$PWD/scripts" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[3])
import omapple_kb
chords = open(sys.argv[1], encoding="utf-8").read().split("\n")
chords = [c for c in chords if c]
theirs = json.load(open(sys.argv[2], encoding="utf-8"))
for chord, other in zip(chords, theirs):
    mine = omapple_kb.canonical_chord(chord)
    if mine != other:
        print(f"{chord!r}: helper={mine!r} model={other!r}")
PYEOF
)
  [[ -z "$diff_out" ]] && ok "chord normalisers agree" || bad "chord normalisers disagree: $diff_out"
else
  ok "chord normalisers (skipped: node not installed)"
fi

# 4. The status payload stays valid JSON, and the keybinding map / speaker
# calibrator probe are only in the --keys / --sound variants (poll stays small).
bash "$HELPER" status > "$tmp/status.json" || bad "status exited non-zero"
bash "$HELPER" status --keys --sound > "$tmp/status-keys.json" || bad "status --keys --sound exited non-zero"
shape=$(python3 -I - "$tmp/status.json" "$tmp/status-keys.json" <<'PYEOF'
import json, sys
lite = json.load(open(sys.argv[1], encoding="utf-8"))
keys = json.load(open(sys.argv[2], encoding="utf-8"))
if lite.get("systemKeybindings") is not None:
    print("poll payload still carries the keybinding map")
if lite.get("speakerCalibrator") is not None:
    print("poll payload still carries speakerCalibrator")
if not isinstance(keys.get("systemKeybindings"), dict):
    print("--keys payload lost the map")
if not isinstance(keys.get("speakerCalibrator"), dict):
    print("--sound payload lost speakerCalibrator")
PYEOF
)
[[ -z "$shape" ]] && ok "status payload shape" || bad "status payload: $shape"

# 5. QML still compiles (warnings are pre-existing; errors are not).
if command -v qmllint >/dev/null 2>&1; then
  errors=$(qmllint BarWidget.qml 2>&1 | grep -c '^Error')
  [[ "$errors" == "0" ]] && ok "qmllint: no errors" || bad "qmllint reported $errors errors"
fi

# 6. The shared module: one chord normaliser in the repo, records lines without
# an arrow are skipped, and a corrupt settings.json never reads back as {}.
nrm=$(grep -c 'def normalize_chord\|def canonical_chord' "$HELPER")
[[ "$nrm" == "0" ]] && ok "no chord normaliser left in the helper" \
  || bad "helper grew $nrm chord normaliser(s) again (use omapple_kb)"
kb_out=$(python3 -I - "$PWD/scripts" "$tmp" <<'PYEOF'
import os, sys
sys.path.insert(0, sys.argv[1])
import omapple_kb

tmp = sys.argv[2]
# load_records: a line whose first field has no arrow must not drop the rest.
recs_file = os.path.join(tmp, "keybindings-test.records")
with open(recs_file, "w", encoding="utf-8") as f:
    f.write("CTRL ALT + space \u2192 focus-menu\t invoke\n")
    f.write("no arrow here\texec\tx\n")
    f.write("BAD \u2192 bad\tkeyword\t\n")
recs = omapple_kb.load_records(recs_file)
if [r[0] for r in recs] != ["CTRL ALT + space", "BAD"]:
    print(f"records parsed as {recs!r}")
elif recs[0][2] != "invoke" or recs[0][3] != "" or recs[1][2] != "keyword":
    print(f"records fields wrong: {recs!r}")

# canonical_chord folds the aliases the UI offers.
for raw, want in (("cmd+s", "SUPER + S"), ("CTRL ALT+space", "CTRL + ALT + SPACE"),
                  ("Escape", "ESCAPE"), ("option+shift+k", "ALT + SHIFT + K"),
                  ("SUPER", ""), ("SUPER + CTRL", "")):
    got = omapple_kb.canonical_chord(raw)
    if got != want:
        print(f"canonical_chord({raw!r}) = {got!r}, want {want!r}")

# load_settings: corrupt JSON reads back as None so the writers stop, and a
# missing file is an empty dict (the first-run case).
bad = os.path.join(tmp, "settings.json")
with open(bad, "w", encoding="utf-8") as f:
    f.write('{"battery": ')
if omapple_kb.load_settings(bad) is not None:
    print("corrupt settings.json did not read back as None")
if omapple_kb.load_settings(os.path.join(tmp, "nope.json")) != {}:
    print("missing settings.json did not read back as {}")
PYEOF
)
[[ -z "$kb_out" ]] && ok "omapple_kb records/chords/settings guards" || bad "omapple_kb: $kb_out"

# 7. The systemd unit may only name a subcommand the helper dispatches, and the
# installed helper must be able to import the module it lives next to.
unit_cmd=$(sed -n 's/^ExecStart=.*omapple-helper //p' system/omapple-wake.service)
check_against_dispatch "omapple-wake.service is dispatched" "$unit_cmd"
grep -q 'install.*omapple_kb\.py.*usr/local/libexec' setup-system \
  && ok "setup-system installs omapple_kb.py next to the helper" \
  || bad "setup-system does not install omapple_kb.py (the installed helper cannot import it)"

# 8. quickshell's Qt has no Repeater.active (qmllint does not say so, the QML
# engine fails the whole widget), so gating must go through the model.
bad_active=$(python3 -I - BarWidget.qml <<'PYEOF'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
for i, line in enumerate(lines):
    if not re.match(r"^\s*active:", line):
        continue
    indent = len(line) - len(line.lstrip())
    for k in range(i - 1, -1, -1):
        prev = lines[k].rstrip()
        if not prev.endswith("{"):
            continue
        if len(prev) - len(prev.lstrip()) >= indent:
            continue
        words = re.findall(r"[A-Za-z][A-Za-z0-9_.]*", prev)
        if words and words[-1] == "Repeater":
            print(f"{i + 1}: active: inside a Repeater (gate its model instead)")
        break
PYEOF
)
[[ -z "$bad_active" ]] && ok "no Repeater.active in BarWidget.qml" || bad "BarWidget.qml $bad_active"

# 9. The settings write path stores one chord form, so the widget and
# bindings.lua cannot disagree about what the user pressed.
if (( EUID == 0 )); then
  ok "set-keybindings write path (skipped: helper refuses root, and no calling user to drop to)"
  exit $fail
fi
sb="$tmp/sandbox"
mkdir -p "$sb/bin" "$sb/.config/hypr" "$sb/.config/omarchy/t2-linux"
printf '#!/bin/sh\ntrue\n' > "$sb/bin/hyprctl" && chmod +x "$sb/bin/hyprctl"
printf -- '-- existing\n' > "$sb/.config/hypr/bindings.lua"
printf '{}\n' > "$sb/.config/omarchy/t2-linux/settings.json"
if ! env HOME="$sb" XDG_CONFIG_HOME="$sb/.config" PATH="$sb/bin:$PATH" bash "$HELPER" set-keybindings keybindingSave "cmd+s" >/dev/null 2>"$tmp/setkey.err"; then
  bad "set-keybindings failed: $(head -c 200 "$tmp/setkey.err")"
else
  stored=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("keybindingSave"))' "$sb/.config/omarchy/t2-linux/settings.json")
  [[ "$stored" == "SUPER + S" ]] && ok "set-keybindings stores the canonical chord" \
    || bad "set-keybindings stored $stored (expected 'SUPER + S')"
fi

# 10. Security & input validation guards
! bash "$HELPER" open-url "file:///etc/passwd" >/dev/null 2>&1 \
  && ok "open-url rejects non-HTTP(S) scheme" \
  || bad "open-url accepted file:// URL"

! python3 -I scripts/omapple-plugins-helper.py toggle some.plugin invalid_state >/dev/null 2>&1 \
  && ok "plugins helper rejects invalid toggle state" \
  || bad "plugins helper accepted invalid toggle state"

! env PKEXEC_UID=notanumber python3 -I scripts/omapple-plugins-helper.py status-speaker-calibrator >/dev/null 2>&1 \
  && ok "plugins helper fails closed on non-integer PKEXEC_UID" \
  || bad "plugins helper ignored non-integer PKEXEC_UID"

# 11. Limine cmdline writer (pcie_ports=compat and mem_sleep_default).
lim_conf="$tmp/t2-mac.conf"
lim_out=$(bash -c '
  source "$1"
  update_limine_cmdline_flag "$2" set "pcie_ports=compat" || true
  update_limine_cmdline_flag "$2" set "mem_sleep_default" "deep" || true
  update_limine_cmdline_flag "$2" set "mem_sleep_default" "s2idle" || true
  update_limine_cmdline_flag "$2" remove "pcie_ports=compat" || true
  cat "$2"
' _ "$HELPER" "$lim_conf")
if grep -q 'mem_sleep_default=s2idle' <<<"$lim_out" && ! grep -q 'pcie_ports=compat' <<<"$lim_out" && ! grep -q 'deep' <<<"$lim_out"; then
  ok "update_limine_cmdline_flag add/update/remove"
else
  bad "update_limine_cmdline_flag produced: $lim_out"
fi

# 12. apply_keybindings writes marker block and rejects unsafe lua overrides.
python3 -I - "$sb/.config/omarchy/t2-linux/settings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["systemKeybindingOverrides"] = {
    "Bad Lua": {"defaultChord": "SUPER + B", "currentChord": "SUPER + ALT + B", "dispatcher": "lua", "arg": "os.execute('id');"},
    "Safe Exec": {"defaultChord": "SUPER + E", "currentChord": "SUPER + ALT + E", "dispatcher": "exec", "arg": "notify-send ok"}
}
json.dump(d, open(p, "w", encoding="utf-8"))
PYEOF
env HOME="$sb" XDG_CONFIG_HOME="$sb/.config" PATH="$sb/bin:$PATH" bash "$HELPER" apply-keybindings >/dev/null 2>"$tmp/kb.err" || true
if grep -q 'BEGIN omarchy-t2-linux keybindings' "$sb/.config/hypr/bindings.lua" \
   && grep -q 'Safe Exec' "$sb/.config/hypr/bindings.lua" \
   && ! grep -q 'os.execute' "$sb/.config/hypr/bindings.lua"; then
  ok "apply-keybindings marker block and LUA_ARG guard"
else
  bad "apply-keybindings output unexpected"
fi

# 13. apply_trackpad writes t2-trackpad.lua, updates hyprland.lua/input.lua, and enforces 3fg mutual exclusion.
printf 'require("hypr.input")\n' > "$sb/.config/hypr/hyprland.lua"
printf 'hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })\n' > "$sb/.config/hypr/input.lua"
env HOME="$sb" XDG_CONFIG_HOME="$sb/.config" PATH="$sb/bin:$PATH" bash "$HELPER" set trackpad_drag_3fg 1 >/dev/null 2>"$tmp/tp.err" \
  && grep -q 'require("hypr.t2-trackpad")' "$sb/.config/hypr/hyprland.lua" \
  && grep -q 'managed by t2-trackpad' "$sb/.config/hypr/input.lua" \
  && grep -q 'drag_3fg = 1' "$sb/.config/hypr/t2-trackpad.lua" \
  && ! grep -q 'hl.gesture' "$sb/.config/hypr/t2-trackpad.lua" \
  && ok "apply_trackpad config generation and 3fg mutual exclusion" \
  || bad "apply_trackpad failed or missed mutual exclusion"

exit $fail
