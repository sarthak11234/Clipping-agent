# Self-hosting SupoClip on this Mac

This checkout runs SupoClip natively on macOS (no Docker) with a **fully local AI
pipeline**: Whisper transcribes, Ollama selects the clips. No cloud API keys are
required.

## What is running

| Component | Where | Port |
| --- | --- | --- |
| Frontend (Next.js) | local process, `frontend/` | 3107 |
| Backend API (FastAPI) | local process, `backend/.venv` | 8000 |
| Video worker (ARQ + cron) | local process, `backend/.venv` | — |
| PostgreSQL 15 | Homebrew service | 5432 |
| Redis | Homebrew service | 6379 |
| Ollama | Homebrew service | 11434 |

Media is stored under `data/uploads` and `data/clips`. Runtime logs are in `logs/`.

## Start and stop

```bash
./start-local.sh     # starts Ollama (if needed), backend, worker, frontend
./stop-local.sh      # stops SupoClip processes; Postgres/Redis keep running
```

Open <http://localhost:3107>, create an account, then upload a video or paste a
YouTube/Twitch/Kick link. The API docs are at <http://localhost:8000/docs>.

End-to-end check (signs up, uploads `testdata/podcast-test.mp4`, waits for clips,
and requests the first clip with a byte range):

```bash
cd frontend && node smoke-local.mjs
```

On 2026-11-19 this produced 3 vertical 1080×1920 clips with burned-in captions,
and the clip file endpoint answered `206 Partial Content`. The source fixture is a
solid blue slate, so that is what the clip frames show behind the captions.

## Configuration

All settings live in `~/supoclip/.env`. The AI section is:

```env
TRANSCRIPTION_PROVIDER=whisper
WHISPER_MODEL_SIZE=small          # tiny | base | small | medium | large
LLM=ollama:qwen3:4b               # any installed Ollama model
OLLAMA_BASE_URL=http://127.0.0.1:11434/v1
```

The frontend reads `frontend/.env.local` (generated to match). The secrets in both
files were generated for this installation; change them together if you rotate them.
`start-local.sh` deliberately does not export the root `.env` into the frontend:
its backend `DATABASE_URL` uses `postgresql+asyncpg://`, which would override the
Prisma URL in `frontend/.env.local` and break sign-up.

Clip analysis uses Ollama's grammar-constrained JSON output with thinking disabled
(`reasoning_effort: "none"`), so qwen3 does not spend its output budget on
reasoning or fall into tool-call retries.

### Using a bigger local model

For better clip selection on a machine with more free RAM:

```bash
ollama pull qwen3:8b
# then edit .env:
# LLM=ollama:qwen3:8b
./stop-local.sh && ./start-local.sh
```

### Long videos (up to 6 hours)

This install is configured to accept finished videos up to six hours long
(uploads, YouTube, Twitch VODs, and Kick VODs):

```env
MAX_VIDEO_DURATION=21600                 # 6 hours
MAX_VIDEO_UPLOAD_BYTES=24000000000       # 24 GB
VIDEO_JOB_TIMEOUT_SECONDS=25200          # 7 hours
PROCESSING_TASK_TIMEOUT_SECONDS=28800    # 8 hours
TRANSCRIPT_ANALYSIS_TOTAL_TIMEOUT_SECONDS=7200
YOUTUBE_DOWNLOAD_MAX_BYTES=24000000000
```

Keep `frontend/.env.local` in sync for browser uploads:

```env
NEXT_PUBLIC_MAX_VIDEO_UPLOAD_BYTES=24000000000
```

Notes:

- Only **finished** videos are supported. An actively live stream is still
  rejected; wait for the VOD, use a platform clip, or record it locally and
  upload the file.
- On this 16 GB M5, a six-hour video can take roughly 2–3 hours end to end
  (Whisper on CPU, then windowed Ollama analysis, then rendering). Keep the Mac
  awake with `caffeinate -s` while it runs.
- Prefer 1080p sources. A source above 1080p/60 fps is transcoded down first,
  which adds a lot of time for a six-hour file.
- Pasting a VOD URL is much faster than uploading a 10–20 GB file. If you do
  upload, the browser and backend limits above both need to allow the file.
- `MAX_CLIPS=10` still caps a task at ten clips. Raise it up to 20 if you want
  more coverage from a long stream; the analysis code has a hard ceiling of 20.

### Using cloud providers instead

Set `TRANSCRIPTION_PROVIDER=assemblyai` with `ASSEMBLY_AI_API_KEY`, and set
`LLM` plus the matching key (`OPENAI_API_KEY`, `GOOGLE_API_KEY`,
`ANTHROPIC_API_KEY`, or `OPENROUTER_API_KEY`). Restart with `./stop-local.sh &&
./start-local.sh`.

## Database

PostgreSQL runs as the Homebrew `postgresql@15` service. The app database is
`supoclip`, owned by the `supoclip` role (password `supoclip_password`, local
connections only). The schema was created with the frontend's Prisma migrations
(`pnpm exec prisma migrate deploy`), and the backend applies its incremental SQL
migrations on startup.

Back up:

```bash
pg_dump -d supoclip -Fc -f supoclip-$(date +%F).dump
```

## Resource notes

Whisper runs on the CPU (`small` is a good 16 GB trade-off). Ollama runs on the
Apple GPU via Metal. A 1–2 minute video is a comfortable test; full-length podcasts
will take a while. If you see heavy swapping, stop other apps or pick smaller models.

## Troubleshooting

```bash
# service logs
tail -f logs/backend.log logs/worker.log logs/frontend.log

# health checks
curl -s http://127.0.0.1:8000/health
curl -s http://127.0.0.1:8000/health/db
curl -s http://127.0.0.1:8000/health/redis
curl -s http://127.0.0.1:11434/api/version

# installed Ollama models
ollama list
```

- **Task fails at transcription** – the Whisper model downloads on first use; check
  `logs/worker.log` for a download or ffmpeg error.
- **Task fails at rendering with `No such filter: 'subtitles'`** – Homebrew's regular
  `ffmpeg` is built without libass. Install the keg-only full build
  (`brew install ffmpeg-full`); `start-local.sh` already puts it first in `PATH`.
- **Task fails at clip selection** – make sure Ollama is running and the model in
  `LLM` is installed (`ollama list`). `ollama pull <model>` fixes a missing model.
- **Port already in use** – stop the process using 3107 or 8000, or change
  `FRONTEND_PORT`/the backend port consistently in `.env` and `frontend/.env.local`.
- **Frontend build/runtime errors on a new Node version** – this install was
  verified with the Homebrew Node on `PATH`.

Licensed for noncommercial self-hosting under the SupoClip Noncommercial Source
License; see `LICENSE`.
