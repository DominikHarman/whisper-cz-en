#!/bin/bash

# Whisper English Transcription Script (Large V3 + VAD + Chunking)
# Splits long audio into chunks to prevent hallucination loops
# Output: .txt (plaintext) + .srt (subtitles)
# Usage: ./transcribe.sh [--txt|--srt] <audio_or_video_file>

set -e

# ── Config ──
CHUNK_MINUTES=5
CHUNK_SECONDS=$((CHUNK_MINUTES * 60))

# ── Colors ──
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Paths ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_BIN="$SCRIPT_DIR/whisper.cpp/build/bin/whisper-cli"
MODEL="$SCRIPT_DIR/whisper.cpp/models/ggml-large-v3.bin"
VAD_MODEL="$SCRIPT_DIR/whisper.cpp/models/ggml-silero-v6.2.0.bin"

# ── Functions ──
print_status() { echo -e "${BLUE}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

show_help() {
    echo "Usage: ./transcribe.sh [options] <audio_or_video_file>"
    echo ""
    echo "Options:"
    echo "  --txt    plaintext only (.txt)"
    echo "  --srt    subtitles only (.srt)"
    echo "  (no option = both .txt + .srt)"
    echo ""
    echo "Examples:"
    echo "  ./transcribe.sh lesson.mov            # → .txt + .srt"
    echo "  ./transcribe.sh --txt lesson.mov      # → only .txt"
    echo "  ./transcribe.sh --srt lesson.mov      # → only .srt"
}

# ── Parse arguments ──
OUTPUT_TXT=true
OUTPUT_SRT=true
INPUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --txt)
            OUTPUT_TXT=true
            OUTPUT_SRT=false
            shift
            ;;
        --srt)
            OUTPUT_TXT=false
            OUTPUT_SRT=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            INPUT_FILE="$1"
            shift
            ;;
    esac
done

# ── Input validation ──
if [ -z "$INPUT_FILE" ]; then
    echo "Error: No file specified"
    show_help
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File '$INPUT_FILE' does not exist"
    exit 1
fi

if [ ! -f "$WHISPER_BIN" ]; then
    echo "Error: whisper-cli not found at $WHISPER_BIN"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model not found at $MODEL"
    exit 1
fi

# ── Filenames ──
FILENAME=$(basename "$INPUT_FILE")
BASENAME="${FILENAME%.*}"
TEMP_WAV="/tmp/${BASENAME}_temp.wav"
CHUNK_DIR="/tmp/${BASENAME}_chunks"

# Output description
if [ "$OUTPUT_TXT" = true ] && [ "$OUTPUT_SRT" = true ]; then
    OUTPUT_DESC=".txt + .srt"
elif [ "$OUTPUT_TXT" = true ]; then
    OUTPUT_DESC="only .txt"
else
    OUTPUT_DESC="only .srt"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
print_status "English transcription: $FILENAME"
print_status "Model: Large V3 + Silero VAD"
print_status "Chunk size: ${CHUNK_MINUTES} minutes"
print_status "Output: $OUTPUT_DESC"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""

# ── Phase 1: Convert to WAV ──
print_status "Phase 1/3: Converting to WAV (16kHz mono)..."
ffmpeg -i "$INPUT_FILE" -acodec pcm_s16le -ar 16000 -ac 1 "$TEMP_WAV" -loglevel error -y
print_success "Conversion done"
echo ""

# ── Phase 2: Split into chunks ──
print_status "Phase 2/3: Splitting audio into ${CHUNK_MINUTES}-minute chunks..."

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TEMP_WAV" | cut -d. -f1)
NUM_CHUNKS=$(( (DURATION + CHUNK_SECONDS - 1) / CHUNK_SECONDS ))

print_status "Total duration: $((DURATION / 60))m $((DURATION % 60))s → $NUM_CHUNKS chunks"

rm -rf "$CHUNK_DIR"
mkdir -p "$CHUNK_DIR"

for i in $(seq 0 $((NUM_CHUNKS - 1))); do
    START=$((i * CHUNK_SECONDS))
    CHUNK_FILE="$CHUNK_DIR/chunk_$(printf '%03d' $i).wav"
    ffmpeg -i "$TEMP_WAV" -ss "$START" -t "$CHUNK_SECONDS" -acodec pcm_s16le -ar 16000 -ac 1 "$CHUNK_FILE" -loglevel error -y
done

print_success "Split done: $NUM_CHUNKS chunks"
echo ""

# ── Phase 3: Transcribe each chunk ──
print_status "Phase 3/3: Transcribing chunks..."
echo ""

# Prepare output files
if [ "$OUTPUT_TXT" = true ]; then
    > "${BASENAME}.txt"
fi
SRT_COUNTER=1

for i in $(seq 0 $((NUM_CHUNKS - 1))); do
    CHUNK_NUM=$((i + 1))
    CHUNK_FILE="$CHUNK_DIR/chunk_$(printf '%03d' $i).wav"
    CHUNK_OUT="$CHUNK_DIR/chunk_$(printf '%03d' $i)"
    OFFSET_SECONDS=$((i * CHUNK_SECONDS))

    print_status "  [$CHUNK_NUM/$NUM_CHUNKS] Transcribing (offset ${OFFSET_SECONDS}s)..." >&2

    "$WHISPER_BIN" \
        -m "$MODEL" \
        -f "$CHUNK_FILE" \
        -l en \
        -otxt \
        -osrt \
        -of "$CHUNK_OUT" \
        --vad \
        --vad-model "$VAD_MODEL" \
        --vad-threshold 0.5 \
        --vad-min-silence-duration-ms 500 \
        --vad-speech-pad-ms 200 \
        -et 2.0 \
        -ml 80 \
        -mc 0 \
        --suppress-nst \
        -np >/dev/null 2>&1 || {
            print_warning "  Chunk $CHUNK_NUM failed, skipping..." >&2
            continue
        }

    # Append plaintext
    if [ "$OUTPUT_TXT" = true ] && [ -f "${CHUNK_OUT}.txt" ]; then
        cat "${CHUNK_OUT}.txt" >> "${BASENAME}.txt"
    fi

    # Process SRT: adjust timestamps by chunk offset and renumber
    if [ "$OUTPUT_SRT" = true ] && [ -f "${CHUNK_OUT}.srt" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})\ --\>\ ([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})$ ]]; then
                S_H=${BASH_REMATCH[1]#0}; [ -z "$S_H" ] && S_H=0
                S_M=${BASH_REMATCH[2]#0}; [ -z "$S_M" ] && S_M=0
                S_S=${BASH_REMATCH[3]#0}; [ -z "$S_S" ] && S_S=0
                S_MS=${BASH_REMATCH[4]}
                E_H=${BASH_REMATCH[5]#0}; [ -z "$E_H" ] && E_H=0
                E_M=${BASH_REMATCH[6]#0}; [ -z "$E_M" ] && E_M=0
                E_S=${BASH_REMATCH[7]#0}; [ -z "$E_S" ] && E_S=0
                E_MS=${BASH_REMATCH[8]}

                S_TOTAL=$(( S_H*3600 + S_M*60 + S_S + OFFSET_SECONDS ))
                E_TOTAL=$(( E_H*3600 + E_M*60 + E_S + OFFSET_SECONDS ))

                printf "%02d:%02d:%02d,%s --> %02d:%02d:%02d,%s\n" \
                    $((S_TOTAL/3600)) $(((S_TOTAL%3600)/60)) $((S_TOTAL%60)) "$S_MS" \
                    $((E_TOTAL/3600)) $(((E_TOTAL%3600)/60)) $((E_TOTAL%60)) "$E_MS"
            elif [[ "$line" =~ ^[0-9]+$ ]]; then
                echo "$SRT_COUNTER"
                SRT_COUNTER=$((SRT_COUNTER + 1))
            else
                echo "$line"
            fi
        done < "${CHUNK_OUT}.srt"
    fi
done > "/tmp/${BASENAME}_srt_tmp.txt"

# Move SRT to final location (or discard tmp)
if [ "$OUTPUT_SRT" = true ]; then
    mv "/tmp/${BASENAME}_srt_tmp.txt" "${BASENAME}.srt"
else
    rm -f "/tmp/${BASENAME}_srt_tmp.txt"
fi

# ── Cleanup ──
rm -f "$TEMP_WAV"
rm -rf "$CHUNK_DIR"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
print_success "Done!"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo "Output files:"
if [ "$OUTPUT_TXT" = true ]; then
    echo "  Plaintext: ${BASENAME}.txt"
fi
if [ "$OUTPUT_SRT" = true ]; then
    echo "  Subtitles: ${BASENAME}.srt"
fi
echo ""
