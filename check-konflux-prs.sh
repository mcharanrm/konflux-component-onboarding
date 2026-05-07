#!/bin/bash
set -euo pipefail

# Argument validation
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <start> <end>"
    echo "Example: $0 1 10"
    exit 1
fi

start="$1"
end="$2"

if ! [[ "$start" =~ ^[0-9]+$ ]] || ! [[ "$end" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Both arguments must be positive integers."
    exit 1
fi

if [[ "$start" -gt "$end" ]]; then
    echo "ERROR: <start> ($start) must be <= <end> ($end)."
    exit 1
fi

# Check dependencies
if ! command -v gh &>/dev/null; then
    echo "ERROR: 'gh' is not installed."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: 'jq' is not installed."
    exit 1
fi

if ! command -v gnuplot &>/dev/null; then
    echo "ERROR: 'gnuplot' is not installed."
    exit 1
fi

# Colors (disabled if not a tty or NO_COLOR is set)
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BOLD=''
    RESET=''
fi

# CSV setup
CSV_FILE="results.csv"
CHECK_NAME="Konflux Staging / example-rok-libecpg-on-pull-request"

if [[ ! -f "$CSV_FILE" ]]; then
    echo "repo,pr_url,pipelinerun,started_at,completed_at,result" > "$CSV_FILE"
fi

# Counters
total=0
exactly_one_pr=0
check_finished=0
check_passed=0
skipped=0

# Main loop
for i in $(seq "$start" "$end"); do
    repo="mcharanrm/example-rok-libecpg-$i"
    total=$((total + 1))

    echo -e "${BOLD}[$i] $repo${RESET}"

    # Idempotency check — skip gh calls entirely if repo already in CSV
    csv_line=$(grep "^${repo}," "$CSV_FILE" || true)
    if [[ -n "$csv_line" ]]; then
        csv_result=$(echo "$csv_line" | cut -d',' -f6)
        csv_pipelinerun_name=$(echo "$csv_line" | cut -d',' -f3)
        csv_started_at=$(echo "$csv_line" | cut -d',' -f4)
        csv_completed_at=$(echo "$csv_line" | cut -d',' -f5)
        exactly_one_pr=$((exactly_one_pr + 1))
        check_finished=$((check_finished + 1))
        if [[ "$csv_result" == "pass" ]]; then
            check_passed=$((check_passed + 1))
        fi
        if [[ "$csv_result" == "pass" ]]; then
            result_color="$GREEN"
        else
            result_color="$RED"
        fi
        echo -e "  ${YELLOW}[SKIP]${RESET} | pipelinerun: $csv_pipelinerun_name | $csv_started_at -> $csv_completed_at (result: ${result_color}${csv_result}${RESET})"
        skipped=$((skipped + 1))
        continue
    fi

    # Get open PRs
    pr_json=$(gh pr list -R "$repo" --state open --json number,url 2>&1) || {
        echo -e "  ${RED}ERROR: Failed to list PRs for $repo${RESET}"
        continue
    }

    pr_count=$(echo "$pr_json" | jq 'length')

    if [[ "$pr_count" -ne 1 ]]; then
        echo -e "  ${YELLOW}WARNING: Expected 1 open PR, found $pr_count. Skipping.${RESET}"
        continue
    fi

    exactly_one_pr=$((exactly_one_pr + 1))

    pr_number=$(echo "$pr_json" | jq -r '.[0].number')
    pr_url=$(echo "$pr_json" | jq -r '.[0].url')

    echo "  PR #$pr_number: $pr_url"

    # Get checks for this PR
    checks_json=$(gh pr checks "$pr_number" -R "$repo" --json name,state,bucket,startedAt,completedAt,link 2>&1) || {
        echo -e "  ${RED}ERROR: Failed to get checks for PR #$pr_number${RESET}"
        continue
    }

    # Filter for the specific check
    check=$(echo "$checks_json" | jq -r --arg name "$CHECK_NAME" '[.[] | select(.name == $name)] | first // empty')

    if [[ -z "$check" ]]; then
        echo -e "  ${YELLOW}Check '$CHECK_NAME' not found. Skipping.${RESET}"
        continue
    fi

    check_state=$(echo "$check" | jq -r '.state')
    check_bucket=$(echo "$check" | jq -r '.bucket')

    # Check if finished (state is not empty and bucket is not "pending")
    if [[ "$check_bucket" == "pending" ]]; then
        echo -e "  ${YELLOW}Check not finished yet (state: $check_state). Skipping.${RESET}"
        continue
    fi

    check_finished=$((check_finished + 1))

    link=$(echo "$check" | jq -r '.link')
    started_at=$(echo "$check" | jq -r '.startedAt')
    completed_at=$(echo "$check" | jq -r '.completedAt')
    pipelinerun=$(echo "$link" | grep -oP '[^/]+$')

    if [[ "$check_bucket" != "pass" ]]; then
        echo -e "  ${RED}FAILED${RESET} | pipelinerun: $pipelinerun | $started_at -> $completed_at"
        echo -e "  ${RED}Link: $link${RESET}"
        echo "$repo,$pr_url,$pipelinerun,$started_at,$completed_at,fail" >> "$CSV_FILE"
        continue
    fi

    check_passed=$((check_passed + 1))

    echo -e "  ${GREEN}PASSED${RESET} | pipelinerun: $pipelinerun | $started_at -> $completed_at"

    echo "$repo,$pr_url,$pipelinerun,$started_at,$completed_at,pass" >> "$CSV_FILE"
done

# Summary
echo ""
echo -e "${BOLD}=== Summary ===${RESET}"
echo "  Total repos checked:     $total"
echo "  Repos with exactly 1 PR: $exactly_one_pr"
echo -e "  Checks finished:         $check_finished"
echo -e "  Checks ${GREEN}passed${RESET}:          $check_passed"
if [[ $skipped -gt 0 ]]; then
    echo -e "  ${YELLOW}Skipped (already in CSV)${RESET}: $skipped"
fi

# Timeline chart
csv_data_lines=$(tail -n +2 "$CSV_FILE" | wc -l)
if [[ "$csv_data_lines" -eq 0 ]]; then
    echo ""
    echo "No passed pipelineruns to chart."
    exit 0
fi

echo ""
echo -e "${BOLD}=== Pipelinerun Timeline ===${RESET}"

tmpdata=$(mktemp)
tmpgp=$(mktemp)
trap 'rm -f "$tmpdata" "$tmpgp"' EXIT

index=0
ytics=""
while IFS=',' read -r csv_repo csv_pr_url csv_pipelinerun csv_started csv_completed csv_result; do
    index=$((index + 1))
    start_epoch=$(date -d "$csv_started" +%s)
    end_epoch=$(date -d "$csv_completed" +%s)
    duration=$((end_epoch - start_epoch))
    echo "$start_epoch $index $duration 0" >> "$tmpdata"
    label=$(echo "$csv_repo" | grep -oP '[^/]+$')
    if [[ -n "$ytics" ]]; then
        ytics="${ytics}, "
    fi
    ytics="${ytics}\"${label}\" $index"
done < <(tail -n +2 "$CSV_FILE")

chart_height=$((index * 2 + 8))
if [[ "$chart_height" -lt 20 ]]; then
    chart_height=20
fi

cat > "$tmpgp" <<GNUPLOT
set terminal dumb size 120 $chart_height
set xdata time
set timefmt "%s"
set format x "%H:%M"
set xlabel "Time (UTC)"
set ytics ($ytics)
set yrange [0:$((index + 1))]
set grid xtics
set style arrow 1 head filled size screen 0.008,15 lw 2
plot "$tmpdata" using 1:2:3:4 with vectors arrowstyle 1 notitle
GNUPLOT

gnuplot "$tmpgp"
