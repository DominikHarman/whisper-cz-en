# whisper-cz-en

Local audio/video transcription for **Czech** and **English** using [whisper.cpp](https://github.com/ggml-org/whisper.cpp) on macOS. Runs completely offline with GPU acceleration on Apple Silicon.

Built for use with [Claude Code](https://claude.ai/claude-code) and other AI coding agents, but works great as a standalone CLI tool too.

## Features

- **Czech + English** transcription with dedicated scripts for each language
- **Any input format** — MP4, MOV, MP3, M4A, WAV, FLAC, OGG, AVI, MKV (auto-converts via ffmpeg)
- **Anti-hallucination pipeline** — 5-minute chunking + Silero VAD + tuned decoder params prevent Whisper's repetitive text loops
- **Dual output** — plaintext (`.md`/`.txt`) and subtitles (`.srt`) with correct global timestamps
- **Fully offline** — no API calls, no cloud, everything runs locally
- **Apple Silicon optimized** — Metal GPU acceleration via whisper.cpp
- **Agent-friendly** — designed to be orchestrated by Claude Code skills, but also works directly from the terminal

## Requirements

- **macOS with Apple Silicon** (M1/M2/M3/M4) — required for Metal GPU acceleration
- [Homebrew](https://brew.sh)
- `cmake` and `ffmpeg` (installed via Homebrew)

### Platform notes

| Platform | Status |
|----------|--------|
| macOS Apple Silicon | Fully supported, Metal GPU |
| macOS Intel | Works, but no GPU acceleration (significantly slower) |
| Linux | Possible — build whisper.cpp without `-DGGML_METAL=ON`, use CUDA or CPU |
| Windows | Possible via WSL2 — not tested or officially supported |

This project is optimized for macOS with Apple Silicon. Other platforms may work with modified build flags but are not actively maintained.

## Installation

### 1. Install dependencies

```bash
brew install cmake ffmpeg
```

### 2. Clone the repository

```bash
git clone --recursive https://github.com/faborsky/whisper-cz-en.git
cd whisper-cz-en
```

> If you already cloned without `--recursive`:
> ```bash
> git submodule init && git submodule update
> ```

### 3. Build whisper.cpp

```bash
cd whisper.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build -j --config Release
cd ..
```

### 4. Download models

```bash
# Whisper Large V3 (~3.1 GB)
cd whisper.cpp/models
bash download-ggml-model.sh large-v3

# Silero VAD v6.2.0 (~865 KB)
bash download-vad-model.sh silero-v6.2.0
cd ../..
```

### 5. Set permissions

```bash
chmod +x prepsat.sh transcribe.sh
```

### 6. Verify

```bash
./prepsat.sh -h
./transcribe.sh -h
```

## Usage

### Czech transcription

```bash
./prepsat.sh recording.m4a               # → recording.md + recording.srt
./prepsat.sh --md recording.m4a          # → only recording.md
./prepsat.sh --srt recording.m4a         # → only recording.srt
```

### English transcription

```bash
./transcribe.sh lesson.mov               # → lesson.txt + lesson.srt
./transcribe.sh --txt lesson.mov         # → only lesson.txt
./transcribe.sh --srt lesson.mov         # → only lesson.srt
```

Output files are created in the current working directory.

### Supported input formats

Any format ffmpeg can decode: **MP4, MOV, MP3, M4A, WAV, FLAC, OGG, AVI, MKV**, and more. The scripts automatically convert any input to 16kHz mono WAV before transcription.

## How it works

### 3-phase pipeline

1. **Convert** — ffmpeg converts any audio/video input to WAV (16kHz, mono, PCM s16le)
2. **Split** — Audio is divided into 5-minute chunks (configurable via `CHUNK_MINUTES`)
3. **Transcribe** — Each chunk is transcribed independently by whisper-cli, then outputs are merged

### Anti-hallucination strategy

Whisper is known to hallucinate repetitive text during silence or unclear audio. This project uses three countermeasures:

| Technique | What it does |
|-----------|-------------|
| **5-min chunking** | Model starts fresh for each chunk — cannot propagate repetition loops across segments |
| **Silero VAD** | Voice Activity Detection skips silent segments entirely, removing triggers for hallucination |
| **Tuned decoder** | `-mc 0` (zero context carryover), `-et 2.0` (low entropy threshold), `-ml 80` (max segment length), `--suppress-nst` (suppress non-speech tokens) |

These techniques work together to produce clean transcriptions even from long recordings with variable audio quality.

## Using with Claude Code

This tool is designed to be called from Claude Code as part of automated workflows. Example Claude Code skill configuration:

```bash
# Transcribe a Czech podcast episode
./prepsat.sh episode.mp4

# Transcribe English course content
./transcribe.sh lecture.mov --txt
```

The scripts use exit codes and stderr for progress messages, making them suitable for programmatic orchestration.

## Troubleshooting

### "whisper-cli not found"

Rebuild whisper.cpp:
```bash
cd whisper.cpp && cmake -B build -DGGML_METAL=ON && cmake --build build -j --config Release
```

### "Model not found"

Download the models:
```bash
cd whisper.cpp/models
bash download-ggml-model.sh large-v3
bash download-vad-model.sh silero-v6.2.0
```

### "ffmpeg: command not found"

```bash
brew install ffmpeg
```

### Hallucination loops (repetitive text)

The scripts handle this automatically via chunking and VAD. If it still occurs, try reducing the chunk size — edit `CHUNK_MINUTES` at the top of the script (default: 5).

## About

Built by [Jindrich Faborsky](https://www.faborsky.com) for personal use and as a learning resource.

Used in:
- **[Vibe Coding for Marketers](https://vibecodingformarketers.com)** — hands-on course teaching marketers to build with AI (podcast automation lesson)
- **[AI First](https://www.aifirst.cz)** — Czech AI course for entrepreneurs and marketers

Students are welcome to use this project as-is or as a starting point for their own transcription tools.

## License

MIT
