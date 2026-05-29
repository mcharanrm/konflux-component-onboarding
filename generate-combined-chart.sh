#!/bin/bash
set -euo pipefail

# Default values
BUILD_CSV=""
TEST_CSV=""
RELEASE_CSV=""
OUTPUT_PNG="results-combined.png"

usage() {
    echo "Usage: $0 --build <build.csv> --test <test.csv> --release <release.csv> [--output <output.png>]"
    echo "Example: $0 --build results-push.csv --test results-test.csv --release results-release.csv"
    echo ""
    echo "Options:"
    echo "  -b, --build    CSV file for Build/Push stage"
    echo "  -t, --test     CSV file for Integration Test stage"
    echo "  -r, --release  CSV file for Release stage"
    echo "  -o, --output   Output PNG filename (default: results-combined.png)"
    echo "  -h, --help     Show this help message"
    exit 1
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--build)
            BUILD_CSV="$2"
            shift 2
            ;;
        -t|--test)
            TEST_CSV="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_CSV="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_PNG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            ;;
    esac
done

# Validation
if [[ -z "$BUILD_CSV" || -z "$TEST_CSV" || -z "$RELEASE_CSV" ]]; then
    echo "ERROR: --build, --test, and --release are all required."
    usage
fi

for f in "$BUILD_CSV" "$TEST_CSV" "$RELEASE_CSV"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: File not found: $f"
        exit 1
    fi
done

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

# Use the list of repos from the BUILD_CSV as the master list
repos=$(tail -n +2 "$BUILD_CSV" | cut -d',' -f1 | sort -V)

index=0
ytics=""
while read -r repo; do
    [[ -z "$repo" ]] && continue
    index=$((index + 1))
    label=${repo##*/}

    # 1. Build (Color 1: Blue)
    line=$(grep "^${repo}," "$BUILD_CSV" || true)
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
[[ "$png_height" -lt 800 ]] && png_height=800

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
set style arrow 2 head filled size screen 0.005,15 lw 2 lc rgb "#008000" # Test: Dark Green
set style arrow 3 head filled size screen 0.005,15 lw 2 lc rgb "#FF0000" # Release: Red

# Plot each stage by filtering the 5th column (color_index)
plot "$tmpdata" using 1:(\$5==1?\$2:1/0):3:4 with vectors as 1 title "Build", \
     ""         using 1:(\$5==2?\$2:1/0):3:4 with vectors as 2 title "Test", \
     ""         using 1:(\$5==3?\$2:1/0):3:4 with vectors as 3 title "Release"
GNUPLOT

gnuplot "$tmpgp"

echo "Combined chart saved to $OUTPUT_PNG"
