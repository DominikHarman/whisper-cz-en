# Whisper Transcription Tools

Lokalni prepis audio a video souboru do textu a titulku. Bezi offline na macOS (Apple Silicon).

## Co to umi

| Skript | Jazyk | Vystup |
|--------|-------|--------|
| `prepsat.sh` | Cestina | `.md` + `.srt` |
| `transcribe.sh` | Anglictina | `.txt` + `.srt` |

Oba skripty automaticky resi problem s halucinacemi Whisperu (opakujici se text) pomoci rozdeleni na 5min chunky a detekce reci (VAD).

## Pouziti

### Cesky prepis

```bash
./prepsat.sh hlasovka.m4a               # → .md + .srt
./prepsat.sh --md hlasovka.m4a          # → jen .md
./prepsat.sh --srt hlasovka.m4a         # → jen .srt
```

### Anglicky prepis

```bash
./transcribe.sh lesson.mov              # → .txt + .srt
./transcribe.sh --txt lesson.mov        # → jen .txt
./transcribe.sh --srt lesson.mov        # → jen .srt
```

Napoveda: `./prepsat.sh -h` nebo `./transcribe.sh -h`

## Podporovane formaty

mp4, mov, mp3, m4a, wav, flac, ogg — konverze probiha automaticky.

## Instalace na novem pocitaci

### 1. Pozadavky

- macOS s Apple Silicon (M1/M2/M3/M4)
- Homebrew (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)

### 2. Instalace zavislosti

```bash
brew install cmake ffmpeg
```

### 3. Klonovani projektu

```bash
git clone --recursive git@github.com:faborsky/whisper.git
cd whisper
```

> Pokud uz jsi klonoval bez `--recursive`:
> ```bash
> git submodule init && git submodule update
> ```

### 4. Kompilace whisper.cpp

```bash
cd whisper.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build -j --config Release
cd ..
```

### 5. Stazeni modelu

```bash
# Whisper Large V3 (~3.1 GB)
cd whisper.cpp/models
bash download-ggml-model.sh large-v3

# Silero VAD v6.2.0 (~865 KB)
bash download-vad-model.sh silero-v6.2.0
cd ../..
```

### 6. Nastaveni prav

```bash
chmod +x prepsat.sh transcribe.sh
```

### 7. Overeni

```bash
./prepsat.sh -h
./transcribe.sh -h
```

## Troubleshooting

### "whisper-cli binary nenalezen"

```bash
cd whisper.cpp && cmake -B build && cmake --build build -j --config Release
```

### "Model nenalezen"

```bash
cd whisper.cpp/models && bash download-ggml-model.sh large-v3 && bash download-vad-model.sh silero-v6.2.0
```

### "ffmpeg: command not found"

```bash
brew install ffmpeg
```

### Hallucination loop (opakujici se text)

Skripty `prepsat.sh` a `transcribe.sh` tento problem resi automaticky pomoci chunkingu a VAD. Pokud se presto objevi, zkus zmensit velikost chunku (promenna `CHUNK_MINUTES` na zacatku skriptu).
