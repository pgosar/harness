#!/bin/bash
# Task lifecycle manager: enforces the harness loop.
# Usage:
#   task.sh start "goal" "verifier"     - declare goal, verifier, run pre-mortem
#   task.sh verify                     - run verification checks
#   task.sh decide keep|revert|escalate|stop [note]
#   task.sh status                     - show current task state
#   task.sh fail                       - record a failed attempt (tracks count)
#   task.sh premortem                  - run pre-mortem prompts
#   task.sh review                     - spawn specialist review subagent prompt

# Namespace by chat to avoid conflicts across side chats
if [ -n "$CHAT_ID" ]; then
  TASK_FILE=~/workspace/harness/task-$CHAT_ID.json
else
  TASK_FILE=~/workspace/harness/current-task.json
fi

case "$1" in
  start)
    if [ -z "$2" ] || [ -z "$3" ]; then
      echo "Usage: task.sh start \"goal\" \"verifier\""
      exit 1
    fi
    cat > "$TASK_FILE" << EOF
{
  "goal": "$2",
  "verifier": "$3",
  "started": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "start_epoch": $(date +%s),
  "failures": 0,
  "status": "active"
}
EOF
    echo "Task started:"
    echo "  Goal: $2"
    echo "  Verifier: $3"
    echo ""
    echo "Pre-mortem (30 seconds):"
    echo "  1. What could go wrong here?"
    echo "  2. What would the failure look like?"
    echo "  3. What environment values am I assuming? (verify them)"
    ;;

  premortem)
    echo "Pre-mortem questions:"
    echo "  1. What could go wrong here?"
    echo "  2. What would the failure look like?"
    echo "  3. What modes/flags exist? Did I audit all settings that follow them?"
    echo "  4. Am I tracing the pipeline or just checking the symptom?"
    echo "  5. What environment values am I assuming? (verify them now)"
    ;;

  verify)
    if [ ! -f "$TASK_FILE" ]; then
      echo "No active task. Run: task.sh start \"goal\" \"verifier\""
      exit 1
    fi
    # Time-box check: warn at 30 minutes
    START=$(python3 -c "import json; print(json.load(open('$TASK_FILE')).get('start_epoch', 0))")
    NOW=$(date +%s)
    ELAPSED=$(( (NOW - START) / 60 ))
    if [ "$ELAPSED" -ge 30 ]; then
      echo "⚠️  ${ELAPSED} minutes elapsed. Per harness: time-box hit."
      echo "   Stop and either escalate or switch approaches (bisect, minimal repro, fresh session)."
      echo ""
    fi
    GOAL=$(python3 -c "import json; print(json.load(open('$TASK_FILE'))['goal'])")
    VERIFIER=$(python3 -c "import json; print(json.load(open('$TASK_FILE'))['verifier'])")
    echo "Verifying: $GOAL"
    echo "Expected evidence: $VERIFIER"
    echo ""
    echo "Verification levels (do ALL that apply):"
    echo "  1. Static: linters, syntax, style (luacheck, stylua, shellcheck)"
    echo "  2. Behavioral: exercise the changed code path"
    echo "     - Neovim Lua: nvim --headless -c 'qa!' (must start cleanly)"
    echo "     - Shell: run with test inputs, not just bash -n"
    echo "     - Python: import the module, not just py_compile"
    echo "     - Generated configs: verify the consumer reads them"
    echo "  3. Visual: screenshot showing actual rendered result"
    echo ""
    echo "Lint-clean is NOT verification. Show behavioral evidence."
    echo ""
    echo "Run your verification now, then: task.sh decide keep|revert|escalate|stop"
    ;;

  fail)
    if [ ! -f "$TASK_FILE" ]; then exit 1; fi
    FAILURES=$(python3 -c "import json; d=json.load(open('$TASK_FILE')); d['failures']+=1; json.dump(d, open('$TASK_FILE','w'), indent=2); print(d['failures'])")
    echo "Failure #$FAILURES recorded."
    if [ "$FAILURES" -eq 1 ]; then
      echo ""
      echo "Consider: bisect the regression? Create a minimal repro?"
    fi
    if [ "$FAILURES" -ge 2 ]; then
      echo ""
      echo "⚠️  TWO FAILURES: Per harness contract, REWIND to last good state and replan."
      echo "   Do NOT attempt a third fix on the same approach."
      echo "   Options: git bisect, minimal repro, escalate to user."
    fi
    ;;

  review)
    echo "Specialist review: spawn a subagent with ONLY the diff."
    echo ""
    echo "Prompt template:"
    echo "  'Review this diff adversarially. You have no implementation history."
    echo "   Find: logic errors, missed edge cases, hardcoded values that should"
    echo "   follow modes/flags, unverified assumptions. Be specific.'"
    echo ""
    echo "Then paste the diff."
    ;;

  decide)
    if [ ! -f "$TASK_FILE" ]; then exit 1; fi
    # If stopping, require structured intent verification
    if [ "$2" = "stop" ]; then
      # Parse structured args: --intent, --method, --evidence, [--gaps]
      INTENT=""
      METHOD=""
      EVIDENCE=""
      GAPS=""
      ARGS="$3 $4 $5 $6 $7 $8 $9"
      # Simple parse: look for key=value pairs
      # For now, require the note to contain all three sections
      NOTE="$3"
      if [ -z "$NOTE" ]; then
        echo ""
        echo "STOP requires structured verification."
        echo ""
        echo "Usage:"
        echo '  task.sh decide stop "intent: <what the change was supposed to do> | method: <how you verified> | evidence: <what you observed> | gaps: <what you could not verify>"'
        echo ""
        echo "Example:"
        echo '  task.sh decide stop "intent: firefox chrome shows wallpaper subtly | method: generated CSS, inspected color-mix value, checked in Firefox | evidence: wallpaper visible at 25% through 75% opaque overlay | gaps: could not screenshot, user to confirm visually"'
        exit 1
      fi
      # Check for required sections
      MISSING=""
      echo "$NOTE" | grep -qi "intent:" || MISSING="$MISSING intent"
      echo "$NOTE" | grep -qi "method:" || MISSING="$MISSING method"
      echo "$NOTE" | grep -qi "evidence:" || MISSING="$MISSING evidence"
      if [ -n "$MISSING" ]; then
        echo ""
        echo "BLOCKED: verification missing sections:$MISSING"
        echo ""
        echo "You must explain:"
        echo "  intent:   what was the change supposed to achieve?"
        echo "  method:   what did you actually do to verify it?"
        echo "  evidence: what did you observe that proves it worked?"
        echo "  gaps:     (optional) what could you not verify and why?"
        echo ""
        echo "Vague statements like 'looks good' or 'works' are not verification."
        exit 1
      fi
      # If --verified flag is present (subagent already approved), skip the prompt
      if [ "$4" = "--verified" ]; then
        echo "Verifier subagent approved. Completing."
      else
      # Quality judgment is done by a verifier subagent, not regex.
      # Print the prompt for the agent to use.
      echo ""
      echo "---"
      echo "Before completing, spawn a verifier subagent with this prompt:"
      echo ""
      echo "  You are verifying that a code change achieved its intent."
      echo "  Be adversarial. The author wants to mark this done; your job is"
      echo "  to catch hand-waving, insufficient verification, and unproven claims."
      echo ""
      echo "  Task goal: $(python3 -c "import json; print(json.load(open('$TASK_FILE')).get('goal',''))")"
      echo ""
      echo "  Claimed verification:"
      echo "  $NOTE"
      echo ""
      echo "  Judge:"
      echo "  1. Does the method actually test the intent? (Or just check syntax?)"
      echo "  2. Is the evidence specific? (What was observed, not just 'works'?)"
      echo "  3. Are the gaps acceptable? (Or do they undermine the claim?)"
      echo "  4. What would you check that they did not?"
      echo ""
      echo "  Reply with APPROVE or REJECT plus your reasoning."
      echo "---"
      echo ""
      echo "Spawn the subagent, then re-run decide stop with --verified flag"
      echo "if it approves."
      exit 1
      fi
      # If a watcher is active, also enforce the automated gate
      for pidfile in ~/workspace/harness/watch-*.pid; do
        [ -f "$pidfile" ] || continue
        if kill -0 $(cat "$pidfile") 2>/dev/null; then
          wname=$(basename "$pidfile" | sed 's/watch-//; s/.pid//')
          echo "Watcher '$wname' active, running verification gate..."
          if ! "$0" verify-check "$wname"; then
            echo ""
            echo "Cannot stop: unverified changes exist."
            echo "Fix the issues above, then try again."
            exit 1
          fi
        fi
      done
    fi
    case "$2" in
      keep|revert|escalate|stop)
        python3 -c "
import json
d = json.load(open('$TASK_FILE'))
d['status'] = '$2'
d['decision_note'] = '''$3'''
d['decided'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
json.dump(d, open('$TASK_FILE','w'), indent=2)
"
        echo "Decision: $2"
        if [ "$2" = "revert" ]; then
          echo "Rewinding to last good state. Replan before acting."
          python3 -c "
import json
d = json.load(open('$TASK_FILE'))
d['failures'] = 0
d['status'] = 'active'
json.dump(d, open('$TASK_FILE','w'), indent=2)
"
        fi
        if [ "$2" = "stop" ]; then
          # Require test evidence before stopping
          if [ -z "$3" ]; then
            echo ""
            echo "⚠️  STOP requires test evidence."
            echo "   Usage: task.sh decide stop \"what was tested and what the evidence showed\""
            echo "   Example: task.sh decide stop \"luacheck clean, nvim headless starts, screenshot shows solid bg\""
            exit 1
          fi
          mkdir -p ~/workspace/harness/completed
          TS=$(date -u +%Y%m%d-%H%M%S)
          cp "$TASK_FILE" ~/workspace/harness/completed/task-$TS.json
          rm "$TASK_FILE"
          echo "Task archived with evidence: $3"
        fi
        ;;
      *)
        echo "Usage: task.sh decide keep|revert|escalate|stop [note]"
        exit 1
        ;;
    esac
    ;;

  status)
    if [ ! -f "$TASK_FILE" ]; then
      echo "No active task."
    else
      cat "$TASK_FILE"
      # Time elapsed
      START=$(python3 -c "import json; print(json.load(open('$TASK_FILE')).get('start_epoch', 0))")
      NOW=$(date +%s)
      ELAPSED=$(( (NOW - START) / 60 ))
      echo "  elapsed_minutes: $ELAPSED"
    fi
    ;;

  watch)
    if [ -z "$2" ] || [ -z "$3" ]; then
      echo "Usage: task.sh watch <name> <macbook-repo-path>"
      echo "Example: task.sh watch dotfiles /Users/chilly/code/dotfiles"
      exit 1
    fi
    WATCH_PID=~/workspace/harness/watch-$2.pid
    if [ -f "$WATCH_PID" ] && kill -0 $(cat "$WATCH_PID") 2>/dev/null; then
      echo "Watcher '$2' already running (pid $(cat $WATCH_PID))"
      exit 1
    fi
    nohup ~/workspace/harness/watch.sh "$2" "$3" > /tmp/watch-$2.out 2>&1 &
    echo "Watcher '$2' started for $3"
    echo "Log: ~/workspace/harness/watch-$2.log"
    ;;

  watch-status)
    if [ -z "$2" ]; then
      echo "Active watchers:"
      for pidfile in ~/workspace/harness/watch-*.pid; do
        [ -f "$pidfile" ] || continue
        name=$(basename "$pidfile" | sed 's/watch-//; s/.pid//')
        if kill -0 $(cat "$pidfile") 2>/dev/null; then
          echo "  $name (pid $(cat $pidfile), running)"
        else
          echo "  $name (stopped)"
        fi
      done
    else
      LOG=~/workspace/harness/watch-$2.log
      if [ -f "$LOG" ]; then
        tail -30 "$LOG"
      else
        echo "No log for watcher '$2'"
      fi
    fi
    ;;

  watch-project)
    if [ -z "$2" ]; then
      echo "Usage: task.sh watch-project <project-name>"
      echo "Projects defined in ~/workspace/harness/projects.yaml"
      exit 1
    fi
    PROJ_PATH=$(python3 -c "
import yaml
with open('/home/hatch/workspace/harness/projects.yaml') as f:
    projects = yaml.safe_load(f)
print(projects.get('$2', ''))
")
    if [ -z "$PROJ_PATH" ]; then
      echo "Unknown project '$2'. Add it to ~/workspace/harness/projects.yaml"
      exit 1
    fi
    # Reuse the watch command
    exec "$0" watch "$2" "$PROJ_PATH"
    ;;

  verify-check)
    # Gate: ensure all changed files were verified after their last edit.
    # Usage: task.sh verify-check <watcher-name>
    if [ -z "$2" ]; then
      echo "Usage: task.sh verify-check <watcher-name>"
      exit 1
    fi
    LOG=~/workspace/harness/watch-$2.log
    if [ ! -f "$LOG" ]; then
      echo "No watcher log for '$2'. Start with: task.sh watch-project $2"
      exit 1
    fi
    python3 - "$2" << 'PYEOF2'
import re, sys
from datetime import datetime

name = sys.argv[1]
log_path = f"/home/hatch/workspace/harness/watch-{name}.log"

with open(log_path) as f:
    lines = f.readlines()

# Parse: track last change time and last verification time per file
last_change = {}  # file -> timestamp of last "Changed files" mentioning it
last_verify = {}  # file -> timestamp of last verification result

current_ts = None
in_change_block = False

for line in lines:
    # Timestamp lines: 2026-10-02T10:11:29Z: Changed files:
    m = re.match(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z): Changed files:', line)
    if m:
        current_ts = m.group(1)
        in_change_block = True
        continue
    m = re.match(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z): Watcher', line)
    if m:
        in_change_block = False
        continue
    if in_change_block and current_ts:
        m = re.match(r'^\s+(\S+)$', line.rstrip())
        if m and not m.group(1).startswith('✓') and not m.group(1).startswith('✗'):
            f = m.group(1)
            last_change[f] = current_ts
    # Verification results
    m = re.match(r'^\s+[✓✗] (?:luacheck|stylua|shellcheck|python)', line)
    if m and current_ts:
        # Find the file this belongs to (last file in change block)
        pass  # simplified: we track per-change-block

# Simpler approach: for each change block, check if all files got ✓
print("Verification gate check:")
print("")

blocks = []
current_block = None
for line in lines:
    m = re.match(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z): Changed files:', line)
    if m:
        if current_block:
            blocks.append(current_block)
        current_block = {'ts': m.group(1), 'files': [], 'results': {}}
        continue
    if current_block:
        m = re.match(r'^\s+(\S+\.\w+)$', line.rstrip())
        if m:
            current_block['files'].append(m.group(1))
        m = re.match(r'^\s+([✓✗]) (\w+)', line)
        if m:
            status, checker = m.group(1), m.group(2)
            # Associate with last file
            if current_block['files']:
                f = current_block['files'][-1]
                if f not in current_block['results']:
                    current_block['results'][f] = []
                current_block['results'][f].append((checker, status == '✓'))

if current_block:
    blocks.append(current_block)

unverified = []
for b in blocks:
    for f in b['files']:
        results = b['results'].get(f, [])
        if not results:
            unverified.append((b['ts'], f, 'no verification ran'))
        elif any(not ok for _, ok in results):
            failed = [c for c, ok in results if not ok]
            unverified.append((b['ts'], f, f"failed: {', '.join(failed)}"))

if unverified:
    print("BLOCKED - unverified changes:")
    for ts, f, reason in unverified:
        print(f"  {ts} {f}: {reason}")
    sys.exit(1)
else:
    print(f"All {sum(len(b['files']) for b in blocks)} changed files verified clean.")
PYEOF2
    ;;

  watch-stop)
    if [ -z "$2" ]; then
      echo "Usage: task.sh watch-stop <name>"
      exit 1
    fi
    WATCH_PID=~/workspace/harness/watch-$2.pid
    if [ -f "$WATCH_PID" ]; then
      PID=$(cat "$WATCH_PID")
      if kill -0 $PID 2>/dev/null; then
        kill $PID
        echo "Watcher '$2' stopped"
      else
        echo "Watcher '$2' not running"
      fi
      rm -f "$WATCH_PID"
    else
      echo "No watcher '$2'"
    fi
    ;;

  *)
    echo "Usage: task.sh start|premortem|verify|fail|review|decide|status|watch|watch-status|watch-stop"
    exit 1
    ;;
esac
