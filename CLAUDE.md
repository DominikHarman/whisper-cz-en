# Whisper Transcription Project

Local audio/video transcription using whisper.cpp on macOS (Apple Silicon, Metal GPU).

## Project Structure

```
whisperproject/
├── transcribe.sh          # English transcription script
├── prepsat.sh             # Czech transcription script
├── README.md              # User-facing docs (Czech)
├── CLAUDE.md              # This file
├── whisper.cpp/           # Git submodule — whisper.cpp project
│   ├── build/bin/whisper-cli
│   └── models/
│       ├── ggml-large-v3.bin          # 3.1 GB — primary model for both scripts
│       └── ggml-silero-v5.1.2.bin     # 885 KB — VAD model
└── venv/                  # Python venv (unused by scripts, kept for whisper.cpp tooling)
```

## Scripts

Both scripts share identical architecture — only language differs.

### `transcribe.sh` (English)
- Usage: `./transcribe.sh [--txt|--srt] <file>`
- Language: `-l en`
- Output: `.txt` + `.srt` (default both, `--txt` or `--srt` for single)

### `prepsat.sh` (Czech)
- Usage: `./prepsat.sh [--md|--srt] <file>`
- Language: `-l cs`
- Output: `.md` + `.srt` (default both, `--md` or `--srt` for single)

## Processing Pipeline

Both scripts follow the same 3-phase pipeline:

1. **Convert** — ffmpeg converts input to WAV (16kHz, mono, PCM)
2. **Split** — Audio is split into 5-minute chunks (configurable via `CHUNK_MINUTES`)
3. **Transcribe** — Each chunk is transcribed independently by whisper-cli

SRT output is post-processed: timestamps are offset by chunk position and sequence numbers are renumbered globally. The loop's stdout is redirected to a temp file, then moved to final `.srt`. Whisper-cli stdout/stderr must be `>/dev/null 2>&1` to prevent raw output from leaking into the SRT file.

## Anti-Hallucination Strategy

Whisper hallucinates repetitive text during silence or unclear audio. Three countermeasures:

1. **Chunking** — 5-min segments, model starts fresh each chunk (cannot propagate loops)
2. **Silero VAD** — Voice Activity Detection skips silent segments
3. **Decoder params:**
   - `-mc 0` — zero max context (no previous text carried over)
   - `-et 2.0` — lower entropy threshold (faster fallback on confusion)
   - `-ml 80` — max segment length 80 chars
   - `--suppress-nst` — suppress non-speech tokens

## Key Implementation Details

- Whisper-cli is called with `-otxt -osrt` (file output flags) regardless of user's output choice — the unwanted output is simply not collected
- Progress messages use `>&2` to avoid contaminating the stdout→SRT redirect
- The for loop redirects stdout to a temp file (`/tmp/${BASENAME}_srt_tmp.txt`), which is then moved or deleted based on output flags
- `cat "${CHUNK_OUT}.txt" >> "${BASENAME}.txt"` works inside the redirected loop because `>>` is an explicit redirect that overrides the loop-level redirect
- ffmpeg uses `-y` flag to overwrite without prompting

## Dependencies

- **whisper.cpp** — compiled with Metal support (`whisper-cli` binary)
- **ffmpeg/ffprobe** — audio conversion and duration detection
- **bash** — scripts use bash-specific features (BASH_REMATCH, `[[ ]]`)

## Development Notes

- When modifying whisper-cli flags, check `whisper-cli --help` — the flag set varies by whisper.cpp version
- Model files are large (3.1 GB) — not tracked in git, must be downloaded via `whisper.cpp/models/download-ggml-model.sh`
- VAD model downloaded via `whisper.cpp/models/download-vad-model.sh`
- Media files (`.mp3`, `.mp4`, `.mov`, `.m4a`) in the project root are user data, not project assets
- `.md` and `.txt` files in the root (other than README/CLAUDE) are transcription outputs
