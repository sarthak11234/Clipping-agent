#!/bin/bash
# Stop the locally started SupoClip processes.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

for name in frontend worker backend ollama; do
  pidfile="run/$name.pid"
  if [ -f "$pidfile" ]; then
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then
      # Stop children (next dev / uvicorn reload) before the parent.
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 10); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      kill -KILL "$pid" 2>/dev/null || true
      echo "stopped $name"
    fi
    rm -f "$pidfile"
  fi
done

echo "SupoClip processes stopped. PostgreSQL and Redis keep running as Homebrew services."
