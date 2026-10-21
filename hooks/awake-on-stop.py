#!/usr/bin/env python3
"""Stop hook: this session finished its turn — clear its marker. When no markers remain the
agent-awake guard releases the hold within 20 seconds and the Mac sleeps normally. Does not
release directly: another session may still be mid-turn. Silent; fails open."""
import json, os, sys
ACTIVE = "/tmp/agent-awake.active"
def main():
    try: p = json.load(sys.stdin)
    except Exception: return 0
    sid = str(p.get("session_id") or "unknown")[:36]
    try: os.unlink(os.path.join(ACTIVE, sid))
    except OSError: pass
    return 0
if __name__ == "__main__":
    try: sys.exit(main())
    except Exception: sys.exit(0)
