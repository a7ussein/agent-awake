#!/usr/bin/env bash
set -u
~/.local/bin/agent-awake stop 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.automyte.agent-awake-menu" 2>/dev/null || true
pkill -x AgentAwake 2>/dev/null || true
rm -rf "$HOME/Applications/Agent Awake.app" ~/Library/LaunchAgents/com.automyte.agent-awake-menu.plist ~/.local/bin/agent-awake ~/.local/bin/sleep-now ~/.config/agent-awake /tmp/agent-awake.active
rm -f ~/.claude/hooks/awake-on-work.py ~/.claude/hooks/awake-on-stop.py
echo "Removed. The sudo rule stays unless you remove it: sudo rm /etc/sudoers.d/agent-awake"
echo "If ~/.claude/settings.json had the hooks wired, remove the two awake-on-* entries by hand."
