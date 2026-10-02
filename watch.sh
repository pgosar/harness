#!/bin/bash
# VM-side file watcher: polls MacBook repo via SSH, auto-verifies changes.
# Usage: watch.sh <name> <macbook-repo-path>
# Logs to ~/workspace/harness/watch-<name>.log
# PID file: ~/workspace/harness/watch-<name>.pid

NAME="$1"
REPO="$2"
LOG=~/workspace/harness/watch-$NAME.log
PIDFILE=~/workspace/harness/watch-$NAME.pid
STATE=~/workspace/harness/watch-$NAME.state

if [ -z "$NAME" ] || [ -z "$REPO" ]; then
  echo "Usage: watch.sh <name> <macbook-repo-path>"
  exit 1
fi

SSH_MACBOOK=~/workspace/pc-access/ssh-macbook

echo $$ > "$PIDFILE"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ): Watcher '$NAME' started for $REPO" >> "$LOG"

# Initialize state
$SSH_MACBOOK "cd $REPO && find home -type f \( -name '*.lua' -o -name '*.sh' -o -name '*.py' \) -not -path '*/pack/*' -exec stat -f '%m %N' {} \;" 2>/dev/null | sort > "$STATE"

while true; do
  sleep 10
  
  TMP_STATE=$(mktemp)
  $SSH_MACBOOK "cd $REPO && find home -type f \( -name '*.lua' -o -name '*.sh' -o -name '*.py' \) -not -path '*/pack/*' -exec stat -f '%m %N' {} \;" 2>/dev/null | sort > "$TMP_STATE"
  
  CHANGED=$(comm -13 "$STATE" "$TMP_STATE" 2>/dev/null | cut -d' ' -f2-)
  
  if [ -n "$CHANGED" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ): Changed files:" >> "$LOG"
    echo "$CHANGED" | while read -r f; do
      [ -z "$f" ] && continue
      echo "  $f" >> "$LOG"
      
      case "$f" in
        *.lua)
          # Static
          RESULT=$($SSH_MACBOOK "cd $REPO && :; export PATH=/opt/homebrew/bin:\$PATH; luacheck --no-color --config home/.luacheckrc '$f' 2>&1 | tail -1" 2>/dev/null)
          if echo "$RESULT" | grep -q "0 warnings.*0 errors"; then
            echo "    ✓ luacheck clean" >> "$LOG"
          else
            echo "    ✗ luacheck FAILED: $RESULT" >> "$LOG"
          fi
          
          if $SSH_MACBOOK "cd $REPO && :; export PATH=/opt/homebrew/bin:\$PATH; stylua --check '$f'" 2>&1 | grep -q "Diff"; then
            echo "    ✗ stylua needs formatting" >> "$LOG"
          else
            echo "    ✓ stylua clean" >> "$LOG"
          fi

          # Behavioral: try loading as nvim module (if in nvim/lua/)
          if echo "$f" | grep -q "nvim/lua/"; then
            MOD=$(echo "$f" | sed 's|.*/nvim/lua/||; s|\.lua$||; s|/|.|g')
            # Skip init.lua and generated files (side effects)
            if ! echo "$MOD" | grep -q "generated\|init$"; then
              LOAD_ERR=$($SSH_MACBOOK "cd $REPO && :; export PATH=/opt/homebrew/bin:\$PATH; nvim --headless --noplugin -c \"lua ok, err = pcall(require, '$MOD'); if not ok then print('ERR:' .. tostring(err)) end\" -c \"qa!\" 2>&1 | grep '^ERR:' | head -1" 2>/dev/null)
              if [ -n "$LOAD_ERR" ]; then
                if echo "$LOAD_ERR" | grep -qi "module.*not found"; then
                  echo "    ○ nvim load skipped (requires plugin)" >> "$LOG"
                else
                  echo "    ✗ nvim load FAILED: $LOAD_ERR" >> "$LOG"
                fi
              else
                echo "    ✓ nvim module loads" >> "$LOG"
              fi
            fi
          fi
          ;;
        *.sh)
          if $SSH_MACBOOK "cd $REPO && :; export PATH=/opt/homebrew/bin:\$PATH; shellcheck -S warning '$f'" 2>&1 | grep -q .; then
            echo "    ✗ shellcheck FAILED" >> "$LOG"
          else
            echo "    ✓ shellcheck clean" >> "$LOG"
          fi
          ;;
        *.py)
          # Static
          if $SSH_MACBOOK "cd $REPO && python3 -m py_compile '$f'" 2>&1 | grep -q .; then
            echo "    ✗ python syntax FAILED" >> "$LOG"
          else
            echo "    ✓ python syntax clean" >> "$LOG"
          fi

          # Behavioral: try importing (if it looks like a module, not a script)
          # Skip if file has if __name__ == "__main__" (it's a script)
          if ! $SSH_MACBOOK "grep -q '__name__.*__main__' '$REPO/$f'" 2>/dev/null; then
            MOD=$(echo "$f" | sed 's|/|.|g; s|\.py$||')
            IMPORT_ERR=$($SSH_MACBOOK "cd $REPO && python3 -c \"import $MOD\" 2>&1 | head -3" 2>/dev/null)
            if [ -n "$IMPORT_ERR" ]; then
              echo "    ○ python import skipped: $IMPORT_ERR" >> "$LOG"
            else
              echo "    ✓ python imports cleanly" >> "$LOG"
            fi
          fi
          ;;
      esac
    done
    echo "" >> "$LOG"
  fi
  
  mv "$TMP_STATE" "$STATE"
done
