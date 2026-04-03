#!/bin/bash

# Whisper Slovak Transcription Script (Large V3 + VAD + Chunking)
# Rozdeluje audio na chunky pre prevenciu hallucination loops
# Vystup: .md (plaintext) + .srt (casove znacky)
# Pouzitie: ./prepisat.sh [--md|--srt] <audio_alebo_video>

set -e

# ── Config ──
CHUNK_MINUTES=5
CHUNK_SECONDS=$((CHUNK_MINUTES * 60))

# ── Farby ──
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Cesty ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_BIN="$SCRIPT_DIR/whisper.cpp/build/bin/whisper-cli"
MODEL="$SCRIPT_DIR/whisper.cpp/models/ggml-large-v3.bin"
VAD_MODEL="$SCRIPT_DIR/whisper.cpp/models/ggml-silero-v6.2.0.bin"

# ── Funkcie ──
print_status() { echo -e "${BLUE}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

show_help() {
    echo "Použitie: ./prepisat.sh [voľby] <audio_alebo_video>"
    echo ""
    echo "Voľby:"
    echo "  --md     iba plaintext (.md)"
    echo "  --srt    iba titulky (.srt)"
    echo "  (bez voľby = oboje .md + .srt)"
    echo ""
    echo "Príklady:"
    echo "  ./prepisat.sh hlasovka.m4a          # → .md + .srt"
    echo "  ./prepisat.sh --md hlasovka.m4a     # → len .md"
    echo "  ./prepisat.sh --srt hlasovka.m4a    # → len .srt"
}

# ── Parsovanie argumentov ──
OUTPUT_MD=true
OUTPUT_SRT=true
INPUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --md)
            OUTPUT_MD=true
            OUTPUT_SRT=false
            shift
            ;;
        --srt)
            OUTPUT_MD=false
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

# ── Validácia ──
if [ -z "$INPUT_FILE" ]; then
    echo "Chyba: Nebol zadaný súbor"
    show_help
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Chyba: Súbor '$INPUT_FILE' neexistuje"
    exit 1
fi

if [ ! -f "$WHISPER_BIN" ]; then
    echo "Chyba: whisper-cli sa nenašiel na $WHISPER_BIN"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Chyba: Model sa nenašiel na $MODEL"
    exit 1
fi

# ── Názvy súborov ──
FILENAME=$(basename "$INPUT_FILE")
BASENAME="${FILENAME%.*}"
TEMP_WAV="/tmp/${BASENAME}_temp.wav"
CHUNK_DIR="/tmp/${BASENAME}_chunks"

# Popis výstupu
if [ "$OUTPUT_MD" = true ] && [ "$OUTPUT_SRT" = true ]; then
    OUTPUT_DESC=".md + .srt"
elif [ "$OUTPUT_MD" = true ]; then
    OUTPUT_DESC="len .md"
else
    OUTPUT_DESC="len .srt"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
print_status "Slovenský prepis: $FILENAME"
print_status "Model: Large V3 + Silero VAD"
print_status "Chunky: ${CHUNK_MINUTES} minút"
print_status "Výstup: $OUTPUT_DESC"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""

# ── Fáza 1: Konverzia na WAV ──
print_status "Fáza 1/3: Konverzia na WAV (16kHz mono)..."
ffmpeg -i "$INPUT_FILE" -acodec pcm_s16le -ar 16000 -ac 1 "$TEMP_WAV" -loglevel error -y
print_success "Konverzia hotová"
echo ""

# ── Fáza 2: Rozdelenie na chunky ──
print_status "Fáza 2/3: Delenie audia na ${CHUNK_MINUTES}min chunky..."

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TEMP_WAV" | cut -d. -f1)
NUM_CHUNKS=$(( (DURATION + CHUNK_SECONDS - 1) / CHUNK_SECONDS ))

print_status "Celková dĺžka: $((DURATION / 60))m $((DURATION % 60))s → $NUM_CHUNKS chunkov"

rm -rf "$CHUNK_DIR"
mkdir -p "$CHUNK_DIR"

for i in $(seq 0 $((NUM_CHUNKS - 1))); do
    START=$((i * CHUNK_SECONDS))
    CHUNK_FILE="$CHUNK_DIR/chunk_$(printf '%03d' $i).wav"
    ffmpeg -i "$TEMP_WAV" -ss "$START" -t "$CHUNK_SECONDS" -acodec pcm_s16le -ar 16000 -ac 1 "$CHUNK_FILE" -loglevel error -y
done

print_success "Rozdelené: $NUM_CHUNKS chunkov"
echo ""

# ── Fáza 3: Prepis po chunkoch ──
print_status "Fáza 3/3: Prepis chunkov..."
echo ""

# Pripraviť výstupné súbory
if [ "$OUTPUT_MD" = true ]; then
    > "${BASENAME}.md"
fi
SRT_COUNTER=1

for i in $(seq 0 $((NUM_CHUNKS - 1))); do
    CHUNK_NUM=$((i + 1))
    CHUNK_FILE="$CHUNK_DIR/chunk_$(printf '%03d' $i).wav"
    CHUNK_OUT="$CHUNK_DIR/chunk_$(printf '%03d' $i)"
    OFFSET_SECONDS=$((i * CHUNK_SECONDS))

    print_status "  [$CHUNK_NUM/$NUM_CHUNKS] Prepis (offset ${OFFSET_SECONDS}s)..." >&2

    "$WHISPER_BIN" \
        -m "$MODEL" \
        -f "$CHUNK_FILE" \
        -l sk \
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
            print_warning "  Chunk $CHUNK_NUM zlyhal, preskakujem..." >&2
            continue
        }

    # Pripojiť plaintext do .md
    if [ "$OUTPUT_MD" = true ] && [ -f "${CHUNK_OUT}.txt" ]; then
        cat "${CHUNK_OUT}.txt" >> "${BASENAME}.md"
    fi

    # Spracovať SRT: posunúť časové značky o offset a prečíslovať
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

# Presunúť SRT na miesto (alebo zmazať tmp)
if [ "$OUTPUT_SRT" = true ]; then
    mv "/tmp/${BASENAME}_srt_tmp.txt" "${BASENAME}.srt"
else
    rm -f "/tmp/${BASENAME}_srt_tmp.txt"
fi

# ── Vyčistenie ──
rm -f "$TEMP_WAV"
rm -rf "$CHUNK_DIR"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
print_success "Hotovo!"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo "Výstupné súbory:"
if [ "$OUTPUT_MD" = true ]; then
    echo "  Plaintext: ${BASENAME}.md"
fi
if [ "$OUTPUT_SRT" = true ]; then
    echo "  Titulky:   ${BASENAME}.srt"
fi
echo ""
