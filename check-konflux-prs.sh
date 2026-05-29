#!/bin/bash
set -euo pipefail

# Default values
action=""
start=""
end=""

usage() {
    echo "Usage: $0 --action <on-pull|on-push> --start <start> --end <end>"
    echo "Example: $0 --action on-push --start 1 --end 10"
    echo ""
    echo "Options:"
    echo "  -a, --action  Action to check (on-pull or on-push)"
    echo "  -s, --start   Start index of the repository range"
    echo "  -e, --end     End index of the repository range"
    echo "  -h, --help    Show this help message"
    exit 1
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--action)
            action="$2"
            shift 2
            ;;
        -s|--start)
            start="$2"
            shift 2
            ;;
        -e|--end)
            end="$2"
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
if [[ -z "$action" ]]; then
    echo "ERROR: --action is required."
    usage
fi

if [[ "$action" != "on-pull" && "$action" != "on-push" ]]; then
    echo "ERROR: --action must be 'on-pull' or 'on-push'."
    usage
fi

if [[ -z "$start" || -z "$end" ]]; then
    echo "ERROR: --start and --end are required."
    usage
fi

if ! [[ "$start" =~ ^[0-9]+$ ]] || ! [[ "$end" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Both start and end must be positive integers."
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

if [[ ! -f "$CSV_FILE" ]]; then
    echo "repo,pr_url,pipelinerun,started_at,completed_at,result" > "$CSV_FILE"
fi

# Counters
total=0
processed_items=0
check_finished=0
check_passed=0
skipped=0

# === Scenario configuration ===
REPO_BASE="jhutar/example-repo-"
if [[ "$action" == "on-pull" ]]; then
    CHECK_NAME="Konflux Staging / jhutar-comp-on-pull-request"
else
    CHECK_NAME="Konflux Staging / jhutar-comp-on-push"
fi

fetch_on_pull() {
    local repo=$1
    # Get open PRs
    pr_json=$(gh pr list -R "$repo" --state open --json number,url 2>&1) || {
        echo -e "  ${RED}ERROR: Failed to list PRs for $repo${RESET}"
        return 1
    }

    pr_count=$(echo "$pr_json" | jq 'length')

    if [[ "$pr_count" -ne 1 ]]; then
        echo -e "  ${RED}ERROR: Expected 1 open PR, found $pr_count. Skipping.${RESET}"
        return 1
    fi

    processed_items=$((processed_items + 1))

    pr_number=$(echo "$pr_json" | jq -r '.[0].number')
    pr_url=$(echo "$pr_json" | jq -r '.[0].url')

    echo "  PR #$pr_number: $pr_url"

    # Get checks for this PR
    checks_json=$(gh pr checks "$pr_number" -R "$repo" --json name,state,bucket,startedAt,completedAt,link 2>&1) || {
        echo -e "  ${RED}ERROR: Failed to get checks for PR #$pr_number${RESET}"
        return 1
    }

    # Filter for the specific check
    check=$(echo "$checks_json" | jq -r --arg name "$CHECK_NAME" '[.[] | select(.name == $name)] | first // empty')

    if [[ -z "$check" ]]; then
        echo -e "  ${RED}Check '$CHECK_NAME' not found. Skipping.${RESET}"
        return 1
    fi

    check_state=$(echo "$check" | jq -r '.state')
    check_bucket=$(echo "$check" | jq -r '.bucket')
    link=$(echo "$check" | jq -r '.link')
    started_at=$(echo "$check" | jq -r '.startedAt')
    completed_at=$(echo "$check" | jq -r '.completedAt')
    return 0
}

fetch_on_push() {
    local repo=$1
    # on-push
    sha=$(gh api repos/"$repo"/commits/main --jq '.sha' 2>/dev/null) || {
        echo -e "  ${RED}ERROR: Failed to get SHA for $repo${RESET}"
        return 1
    }
    pr_url="https://github.com/$repo/commit/$sha"
    echo "  Commit $sha: $pr_url"

    processed_items=$((processed_items + 1))

    # Get check runs for this SHA
    checks_json=$(gh api repos/"$repo"/commits/"$sha"/check-runs 2>/dev/null) || {
        echo -e "  ${RED}ERROR: Failed to get check runs for $repo${RESET}"
        return 1
    }

    # Filter for the specific check
    check=$(echo "$checks_json" | jq -r --arg name "$CHECK_NAME" '.check_runs | [.[] | select(.name == $name)] | first // empty')

    if [[ -z "$check" ]]; then
        echo -e "  ${RED}Check '$CHECK_NAME' not found. Skipping.${RESET}"
        return 1
    fi

    status=$(echo "$check" | jq -r '.status')
    conclusion=$(echo "$check" | jq -r '.conclusion')
    
    check_state="$status"
    if [[ "$status" != "completed" ]]; then
        check_bucket="pending"
    elif [[ "$conclusion" == "success" ]]; then
        check_bucket="pass"
    else
        check_bucket="fail"
    fi

    link=$(echo "$check" | jq -r '.html_url')
    started_at=$(echo "$check" | jq -r '.started_at')
    completed_at=$(echo "$check" | jq -r '.completed_at')
    return 0
}

# Main loop
for i in $(seq "$start" "$end"); do
    repo="${REPO_BASE}$i"

    total=$((total + 1))

    echo -e "${BOLD}[$i] $repo${RESET}"

    # Idempotency check — skip gh calls entirely if repo already in CSV
    csv_line=$(grep "^${repo}," "$CSV_FILE" || true)
    if [[ -n "$csv_line" ]]; then
        csv_result=$(echo "$csv_line" | cut -d',' -f6)
        csv_pipelinerun_name=$(echo "$csv_line" | cut -d',' -f3)
        csv_started_at=$(echo "$csv_line" | cut -d',' -f4)
        csv_completed_at=$(echo "$csv_line" | cut -d',' -f5)
        processed_items=$((processed_items + 1))
        check_finished=$((check_finished + 1))
        if [[ "$csv_result" == "pass" ]]; then
            check_passed=$((check_passed + 1))
            result_color="$GREEN"
        else
            result_color="$RED"
        fi
        echo -e "  ${YELLOW}[SKIP]${RESET} | pipelinerun: $csv_pipelinerun_name | $csv_started_at -> $csv_completed_at (result: ${result_color}${csv_result}${RESET})"
        skipped=$((skipped + 1))
        continue
    fi

    check_state=""
    check_bucket=""
    started_at=""
    completed_at=""
    pipelinerun=""
    link=""
    pr_url=""

    if [[ "$action" == "on-pull" ]]; then
        fetch_on_pull "$repo" || continue
    else
        fetch_on_push "$repo" || continue
    fi

    # Check if finished
    if [[ "$check_bucket" == "pending" ]]; then
        echo -e "  ${YELLOW}Check not finished yet (state: $check_state). Skipping.${RESET}"
        continue
    fi

    check_finished=$((check_finished + 1))

    pipelinerun=$(echo "$link" | grep -oP '[^/]+$')

    if [[ "$check_bucket" != "pass" ]]; then
        echo -e "  ${RED}FAILED${RESET} | pipelinerun: $pipelinerun | $started_at -> $completed_at"
        echo -e "  ${YELLOW}Link: $link${RESET}"
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
echo "  Total repos checked: $total"
if [[ "$action" == "on-pull" ]]; then
    echo "  Repos with 1 PR:     $processed_items"
else
    echo "  Repos checked (push): $processed_items"
fi
echo -e "  Checks finished:     $check_finished"
echo -e "  Checks ${GREEN}passed${RESET}:        $check_passed"
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

PNG_FILE="${CSV_FILE%.csv}.png"
png_height=$((index * 10 + 200))
if [[ "$png_height" -lt 600 ]]; then
    png_height=600
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

set terminal pngcairo size 1200,$png_height font "monospace,10"
set output "$PNG_FILE"
set style arrow 1 head filled size screen 0.008,15 lw 2
replot
GNUPLOT

gnuplot "$tmpgp"
echo -e "PNG chart saved to ${BOLD}${PNG_FILE}${RESET}"
