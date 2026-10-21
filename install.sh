#!/usr/bin/env bash
# Agent Awake installer — builds the menu-bar app from source (no Gatekeeper warning that way),
# installs the engine, and sets up the one sudo rule it needs. Optional: Claude Code hooks.
#   ./install.sh                 # engine + app
#   ./install.sh --claude-hooks  # also arm/release automatically around Claude Code turns
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
command -v swiftc >/dev/null || { echo "swiftc not found. Install Xcode Command Line Tools: xcode-select --install"; exit 1; }
mkdir -p ~/.local/bin ~/Applications ~/.config/agent-awake
install -m 755 "$here/bin/agent-awake" "$here/bin/sleep-now" ~/.local/bin/
APP="$HOME/Applications/Agent Awake.app"; mkdir -p "$APP/Contents/MacOS"
echo "building the app…"; swiftc -O -o "$APP/Contents/MacOS/AgentAwake" "$here/app/main.swift"
cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.automyte.agent-awake</string><key>CFBundleName</key><string>Agent Awake</string>
<key>CFBundleExecutable</key><string>AgentAwake</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>LSUIElement</key><true/><key>LSMinimumSystemVersion</key><string>13.0</string></dict></plist>
PL
rule="$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep *"
if ! sudo -n pmset -a disablesleep 0 2>/dev/null; then
  echo; echo "One sudo rule is needed so the app can toggle lid-close sleep without a password."
  echo "It allows exactly this and nothing else:  $rule"
  echo "$rule" | sudo tee /etc/sudoers.d/agent-awake >/dev/null && sudo chmod 440 /etc/sudoers.d/agent-awake
fi
plist=~/Library/LaunchAgents/com.automyte.agent-awake-menu.plist
cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>Label</key><string>com.automyte.agent-awake-menu</string><key>ProgramArguments</key><array><string>$APP/Contents/MacOS/AgentAwake</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><false/></dict></plist>
PL
launchctl bootout "gui/$(id -u)/com.automyte.agent-awake-menu" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
if [ "${1:-}" = "--claude-hooks" ]; then
  mkdir -p ~/.claude/hooks; install -m 755 "$here/hooks/awake-on-work.py" "$here/hooks/awake-on-stop.py" ~/.claude/hooks/
  python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
h = d.setdefault("hooks", {})
def has(ev, n): return any(n in x.get("command", "") for m in h.get(ev, []) for x in m.get("hooks", []))
work = "python3 ~/.claude/hooks/awake-on-work.py"; stop = "python3 ~/.claude/hooks/awake-on-stop.py"
if not has("UserPromptSubmit", "awake-on-work"): h.setdefault("UserPromptSubmit", []).append({"hooks": [{"type": "command", "command": work}]})
if not has("PreToolUse", "awake-on-work"): h.setdefault("PreToolUse", []).append({"matcher": "Bash|Agent|Edit|Write", "hooks": [{"type": "command", "command": work}]})
if not has("Stop", "awake-on-stop"): h.setdefault("Stop", []).append({"hooks": [{"type": "command", "command": stop}]})
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n"); print("Claude Code hooks wired in ~/.claude/settings.json")
PY
fi
echo; echo "Installed. Look for the moon icon in your menu bar. ⌃⌥A opens it."
