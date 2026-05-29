#!/bin/bash
set -euo pipefail

# Input files
PUSH_CSV="results-2026-05-29-push.csv"
TEST_CSV="results-2026-05-29-test.csv"
RELEASE_CSV="results-2026-05-29-release.csv"
OUTPUT_PNG="results-combined.png"

# Check dependencies
if ! command -v gnuplot &>/dev/null; then
    echo "ERROR: 'gnuplot' is not installed."
    exit 1
fi

# Temp files
tmpdata=$(mktemp)
tmpgp=$(mktemp)
trap 'rm -f "$tmpdata" "$tmpgp"' EXIT

echo "Processing data..."

# We assume all CSVs have same repos in same order (or at least same repos exist)
# We will use the list of repos from the PUSH_CSV as the master list
repos=$(tail -n +2 "$PUSH_CSV" | cut -d',' -f1 | sort -V)

index=0
ytics=""
while read -r repo; do
    index=$((index + 1))
    label=${repo##*/}
    
    # Function to extract times and append to data
    # Format: start_epoch index duration 0 color_index
    
    # 1. Push Build (Color 1: Blue)
    line=$(grep "^${repo}," "$PUSH_CSV" || true)
    if [[ -n "$line" ]]; then
        start=$(echo "$line" | cut -d',' -f4)
        end=$(echo "$line" | cut -d',' -f5)
        start_epoch=$(date -d "$start" +%s)
        end_epoch=$(date -d "$end" +%s)
        duration=$((end_epoch - start_epoch))
        echo "$start_epoch $index $duration 0 1" >> "$tmpdata"
    fi

    # 2. Integration Test (Color 2: Green)
    line=$(grep "^${repo}," "$TEST_CSV" || true)
    if [[ -n "$line" ]]; then
        start=$(echo "$line" | cut -d',' -f4)
        end=$(echo "$line" | cut -d',' -f5)
        start_epoch=$(date -d "$start" +%s)
        end_epoch=$(date -d "$end" +%s)
        duration=$((end_epoch - start_epoch))
        echo "$start_epoch $index $duration 0 2" >> "$tmpdata"
    fi

    # 3. Release (Color 3: Red)
    line=$(grep "^${repo}," "$RELEASE_CSV" || true)
    if [[ -n "$line" ]]; then
        start=$(echo "$line" | cut -d',' -f4)
        end=$(echo "$line" | cut -d',' -f5)
        start_epoch=$(date -d "$start" +%s)
        end_epoch=$(date -d "$end" +%s)
        duration=$((end_epoch - start_epoch))
        echo "$start_epoch $index $duration 0 3" >> "$tmpdata"
    fi

    if [[ -n "$ytics" ]]; then ytics="${ytics}, "; fi
    ytics="${ytics}\"${label}\" $index"
done <<< "$repos"

png_height=$((index * 15 + 300))
if [[ "$png_height" -lt 800 ]]; then png_height=800; fi

echo "Generating chart..."

cat > "$tmpgp" <<GNUPLOT
set terminal pngcairo size 1600,$png_height font "monospace,10"
set output "$OUTPUT_PNG"

set xdata time
set timefmt "%s"
set format x "%H:%M"
set xlabel "Time (UTC)"
set ylabel "Repositories"
set ytics ($ytics)
set yrange [0:$((index + 1))]
set grid xtics ytics

set title "Konflux Pipeline Timeline: Build (Blue) -> Test (Green) -> Release (Red)"

# Arrow styles for the 3 stages
set style arrow 1 head filled size screen 0.005,15 lw 2 lc rgb "#0000FF" # Build: Blue
set style arrow 2 head filled size screen 0.005,15 lw 2 lc rgb "#00FF00" # Test: Green
set style arrow 3 head filled size screen 0.005,15 lw 2 lc rgb "#FF0000" # Release: Red

# Plot each stage by filtering the 5th column (color_index)
plot "$tmpdata" using 1:($5==1?$2:1/0):3:4 with vectors as 1 title "Build", \
     ""         using 1:($5==2?$2:1/0):3:4 with vectors as 2 title "Test", \
     ""         using 1:($5==3?$2:1/0):3:4 with vectors as 3 title "Release"
GNUPLOT

gnuplot "$tmpgp"

echo "Combined chart saved to $OUTPUT_PNG"
