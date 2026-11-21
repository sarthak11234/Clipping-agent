#!/bin/bash
# Start SupoClip locally (native macOS install).
# Backend/worker use the existing Homebrew PostgreSQL and Redis services,
# the frontend uses Next.js, and Ollama provides the local LLM.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

mkdir -p logs run data/uploads data/clips

if [ ! -f .env ]; then
  echo "Missing .env - copy .env.example and configure it first." >&2
  exit 1
fi

# Backend/worker load the root .env themselves (src.config uses python-dotenv) and
# the frontend reads frontend/.env.local. Do not export the root .env globally:
# its backend DATABASE_URL uses postgresql+asyncpg://, which overrides
# frontend/.env.local in Next.js and makes Prisma reject the datasource.

# Caption burn-in needs the `subtitles` filter, which only the keg-only
# ffmpeg-full build ships (Homebrew's regular ffmpeg omits libass).
if [ -x /opt/homebrew/opt/ffmpeg-full/bin/ffmpeg ]; then
  export PATH="/opt/homebrew/opt/ffmpeg-full/bin:$PATH"
fi

is_up() { curl -fsS --max-time 2 "$1" >/dev/null 2>&1; }

wait_for() {
  local url="$1" name="$2" tries="${3:-60}"
  for _ in $(seq 1 "$tries"); do
    if is_up "$url"; then echo "$name is ready"; return 0; fi
    sleep 2
  done
  echo "$name did not become ready at $url" >&2
  return 1
}

start_pid() {
  local name="$1"; shift
  if [ -f "run/$name.pid" ] && kill -0 "$(cat "run/$name.pid")" 2>/dev/null; then
    echo "$name already running (pid $(cat "run/$name.pid"))"
    return 0
  fi
  "$@" >"logs/$name.log" 2>&1 &
  echo $! >"run/$name.pid"
  echo "started $name (pid $!)"
}

# PostgreSQL and Redis are Homebrew services on this machine.
if ! pg_isready -h 127.0.0.1 -p 5432 -q; then
  brew services start postgresql@15 >/dev/null
fi
if ! redis-cli -h 127.0.0.1 ping >/dev/null 2>&1; then
  brew services start redis >/dev/null
fi

# Ollama provides the local LLM for clip selection.
if ! is_up http://127.0.0.1:11434/api/version; then
  if ! command -v ollama >/dev/null 2>&1; then
    echo "ollama is not installed (brew install ollama)" >&2
    exit 1
  fi
  start_pid ollama ollama serve
  wait_for http://127.0.0.1:11434/api/version "Ollama"
fi

# Backend API
if ! is_up http://127.0.0.1:8000/health; then
  start_pid backend bash -c "cd '$ROOT/backend' && exec .venv/bin/uvicorn src.main:app --host 127.0.0.1 --port 8000"
fi

# Background video worker (also runs the embedded cron worker)
if ! { [ -f run/worker.pid ] && kill -0 "$(cat run/worker.pid)" 2>/dev/null; }; then
  start_pid worker bash -c "cd '$ROOT/backend' && exec .venv/bin/python -m src.workers.run_workers"
fi

# Frontend
if ! is_up http://127.0.0.1:3107/; then
  start_pid frontend bash -c "cd '$ROOT/frontend' && exec ./node_modules/.bin/next dev --turbopack --port 3107"
fi

wait_for http://127.0.0.1:8000/health/db "Backend" 60 || true
wait_for http://127.0.0.1:3107 "Frontend" 90 || true

cat <<EOF

SupoClip is running:
  Frontend: http://localhost:${FRONTEND_PORT:-3107}
  Backend:  http://localhost:8000
  API docs: http://localhost:8000/docs

Logs:  tail -f logs/backend.log logs/worker.log logs/frontend.log
Stop:  ./stop-local.sh
EOF
