#!/bin/bash

# Whisper Czech Transcription Script (Large V3 + VAD + Chunking)
# Rozdeluje audio na chunky pro prevenci hallucination loops
# Vystup: .md (plaintext) + .srt (casove znacky)
# Pouziti: ./prepsat.sh [--md|--srt] <audio_nebo_video>

set -e

# ── Config ──
CHUNK_MINUTES=5
CHUNK_SECONDS=$((CHUNK_MINUTES * 60))

# ── Barvy ──
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Cesty ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_BIN="$SCRIPT_DIR/whisper.cpp/build/bin/whisper-cli"
MODEL="$SCRIPT_DIR/whisper.cpp/models/ggml-large-v3.bin"
VAD_MODEL="$SCRIPT_DIR/whisper.cpp/models/ggml-silero-v6.2.0.bin"

# ── Funkce ──
print_status() { echo -e "${BLUE}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

show_help() {
    echo "Použití: ./prepsat.sh [volby] <audio_nebo_video>"
    echo ""
    echo "Volby:"
    echo "  --md     pouze plaintext (.md)"
    echo "  --srt    pouze titulky (.srt)"
    echo "  (bez volby = obojí .md + .srt)"
    echo ""
    echo "Příklady:"
    echo "  ./prepsat.sh hlasovka.m4a          # → .md + .srt"
    echo "  ./prepsat.sh --md hlasovka.m4a     # → jen .md"
    echo "  ./prepsat.sh --srt hlasovka.m4a    # → jen .srt"
}

# ── Parsovani argumentu ──
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

# ── Validace ──
if [ -z "$INPUT_FILE" ]; then
    echo "Chyba: Není zadán soubor"
    show_help
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Chyba: Soubor '$INPUT_FILE' neexistuje"
    exit 1
fi

if [ ! -f "$WHISPER_BIN" ]; then
    echo "Chyba: whisper-cli nenalezen na $WHISPER_BIN"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Chyba: Model nenalezen na $MODEL"
    exit 1
fi

# ── Nazvy souboru ──
FILENAME=$(basename "$INPUT_FILE")
BASENAME="${FILENAME%.*}"
TEMP_WAV="/tmp/${BASENAME}_temp.wav"
CHUNK_DIR="/tmp/${BASENAME}_chunks"

# Popis vystupu
if [ "$OUTPUT_MD" = true ] && [ "$OUTPUT_SRT" = true ]; then
    OUTPUT_DESC=".md + .srt"
elif [ "$OUTPUT_MD" = true ]; then
    OUTPUT_DESC="jen .md"
else
    OUTPUT_DESC="jen .srt"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
print_status "Český přepis: $FILENAME"
print_status "Model: Large V3 + Silero VAD"
print_status "Chunky: ${CHUNK_MINUTES} minut"
print_status "Výstup: $OUTPUT_DESC"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""

# ── Faze 1: Konverze na WAV ──
print_status "Fáze 1/3: Konverze na WAV (16kHz mono)..."
ffmpeg -i "$INPUT_FILE" -acodec pcm_s16le -ar 16000 -ac 1 "$TEMP_WAV" -loglevel error -y
print_success "Konverze hotová"
echo ""

# ── Faze 2: Rozdeleni na chunky ──
print_status "Fáze 2/3: Dělení audia na ${CHUNK_MINUTES}min chunky..."

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TEMP_WAV" | cut -d. -f1)
NUM_CHUNKS=$(( (DURATION + CHUNK_SECONDS - 1) / CHUNK_SECONDS ))

print_status "Celková délka: $((DURATION / 60))m $((DURATION % 60))s → $NUM_CHUNKS chunků"

rm -rf "$CHUNK_DIR"
mkdir -p "$CHUNK_DIR"

for i in $(seq 0 $((NUM_CHUNKS - 1))); do
    START=$((i * CHUNK_SECONDS))
    CHUNK_FILE="$CHUNK_DIR/chunk_$(printf '%03d' $i).wav"
    ffmpeg -i "$TEMP_WAV" -ss "$START" -t "$CHUNK_SECONDS" -acodec pcm_s16le -ar 16000 -ac 1 "$CHUNK_FILE" -loglevel error -y
done

print_success "Rozděleno: $NUM_CHUNKS chunků"
echo ""

# ── Faze 3: Prepis po chuncich ──
print_status "Fáze 3/3: Přepis chunků..."
echo ""

# Pripravit vystupni soubory
if [ "$OUTPUT_MD" = true ]; then
    > "${BASENAME}.md"
fi
SRT_COUNTER=1

for i in $(seq 0 $((NUM_CHUNKS - 1))); do
    CHUNK_NUM=$((i + 1))
    CHUNK_FILE="$CHUNK_DIR/chunk_$(printf '%03d' $i).wav"
    CHUNK_OUT="$CHUNK_DIR/chunk_$(printf '%03d' $i)"
    OFFSET_SECONDS=$((i * CHUNK_SECONDS))

    print_status "  [$CHUNK_NUM/$NUM_CHUNKS] Přepis (offset ${OFFSET_SECONDS}s)..." >&2

    "$WHISPER_BIN" \
        -m "$MODEL" \
        -f "$CHUNK_FILE" \
        -l cs \
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
            print_warning "  Chunk $CHUNK_NUM selhal, přeskakuji..." >&2
            continue
        }

    # Pripojit plaintext do .md
    if [ "$OUTPUT_MD" = true ] && [ -f "${CHUNK_OUT}.txt" ]; then
        cat "${CHUNK_OUT}.txt" >> "${BASENAME}.md"
    fi

    # Zpracovat SRT: posunout casove znacky o offset a precislovat
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

# Presunout SRT na misto (nebo smazat tmp)
if [ "$OUTPUT_SRT" = true ]; then
    mv "/tmp/${BASENAME}_srt_tmp.txt" "${BASENAME}.srt"
else
    rm -f "/tmp/${BASENAME}_srt_tmp.txt"
fi

# ── Vycisteni ──
rm -f "$TEMP_WAV"
rm -rf "$CHUNK_DIR"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
print_success "Vše hotovo!"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo "Výstupní soubory:"
if [ "$OUTPUT_MD" = true ]; then
    echo "  Plaintext: ${BASENAME}.md"
fi
if [ "$OUTPUT_SRT" = true ]; then
    echo "  Titulky:   ${BASENAME}.srt"
fi
echo ""
