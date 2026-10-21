#!/usr/bin/env python3
"""Arm the lid-close hold whenever Claude is working, automatically.

On 2026-10-20 a session's response was cut off by the lid: the hold had been released on
request an hour earlier and nothing re-armed it. The mental model "Claude is working, so the
laptop stays awake" is the right one; until now the hold was manual, so it was only true when
someone remembered. This fires on every prompt and, throttled, on tool calls during long
autonomous turns, and arms a 120-minute, ownerless hold. Release is agent-awake's job: the
deadline, the 25% battery floor, ten minutes of idle, or `agent-awake stop`.

Trade-off, stated: while Claude is active the Mac will not sleep from the menu or the lid.
To sleep it mid-task: `agent-awake stop`. Silent; fails open.
"""
import json, os, subprocess, sys, time
AWAKE = os.path.expanduser("~/.local/bin/agent-awake")
STAMP = "/tmp/agent-awake.last-arm"
ACTIVE = "/tmp/agent-awake.active"
THROTTLE = 30 * 60   # re-arm at most every 30 minutes from tool calls
MINUTES = "240"
def main():
    try: p = json.load(sys.stdin)
    except Exception: return 0
    ev = p.get("hook_event_name") or ("PreToolUse" if p.get("tool_name") else "UserPromptSubmit")
    if not os.access(AWAKE, os.X_OK): return 0
    # Master switch from the menu-bar app: feature off means no automatic holds at all.
    if os.path.exists(os.path.expanduser("~/.config/agent-awake/disabled")): return 0
    # This session is mid-turn: leave a marker the Stop hook removes. The guard releases the
    # hold when no markers remain — that is "Claude finished". Written BEFORE the throttle:
    # a turn that begins with a tool call inside the throttle window had no marker and the
    # guard could release under it (found in audit, 2026-10-21).
    sid = str(p.get("session_id") or "unknown")[:36]
    try:
        os.makedirs(ACTIVE, exist_ok=True); open(os.path.join(ACTIVE, sid), "w").close()
    except Exception: pass
    if ev != "UserPromptSubmit":
        try:
            if time.time() - os.path.getmtime(STAMP) < THROTTLE: return 0
        except OSError: pass
    try:
        # Arm only if nothing is holding; re-arming every prompt would spam notifications.
        st = subprocess.run([AWAKE, "status"], capture_output=True, text=True, timeout=10)
        if "watcher pid" not in (st.stderr + st.stdout):
            subprocess.run([AWAKE, "start", "--no-owner", "--minutes", MINUTES],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           env=dict(os.environ, AGENT_AWAKE_MARKERS="1"), timeout=20)
        open(STAMP, "w").close()
    except Exception: pass
    return 0
if __name__ == "__main__":
    try: sys.exit(main())
    except Exception: sys.exit(0)
