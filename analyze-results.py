#!/usr/bin/env python3

import argparse
import csv
import sys
from datetime import datetime, timezone


def parse_args():
    parser = argparse.ArgumentParser(
        description="Analyze pipelinerun timing data from CSV"
    )
    parser.add_argument(
        "--csv",
        required=True,
        help="Path to the CSV file with pipelinerun results",
    )
    return parser.parse_args()


def parse_datetime(value):
    dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    return dt.replace(tzinfo=timezone.utc)


def human_duration(seconds):
    minutes, secs = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    if hours > 0:
        return f"{hours}h {minutes}m {secs}s"
    if minutes > 0:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def percentile(sorted_values, pct):
    if not sorted_values:
        return 0
    k = (len(sorted_values) - 1) * (pct / 100.0)
    f = int(k)
    c = f + 1
    if c >= len(sorted_values):
        return sorted_values[f]
    return sorted_values[f] + (k - f) * (sorted_values[c] - sorted_values[f])


def print_group_stats(label, durations):
    if not durations:
        print(f"\n=== {label}: no runs ===")
        return

    durations_sorted = sorted(durations)
    count = len(durations_sorted)
    avg = sum(durations_sorted) / count
    minimum = durations_sorted[0]
    maximum = durations_sorted[-1]
    p95 = percentile(durations_sorted, 95)

    print(f"\n=== {label}: {count} runs ===")
    print(f"  Average:          {avg:8.1f}s  ({human_duration(avg)})")
    print(f"  Min:              {minimum:8.1f}s  ({human_duration(minimum)})")
    print(f"  Max:              {maximum:8.1f}s  ({human_duration(maximum)})")
    print(f"  95th percentile:  {p95:8.1f}s  ({human_duration(p95)})")


def main():
    args = parse_args()

    try:
        with open(args.csv, newline="") as f:
            reader = csv.DictReader(f)

            required = {
                "repo",
                "started_at",
                "completed_at",
                "result",
            }
            if reader.fieldnames is None:
                print(f"ERROR: {args.csv} is empty", file=sys.stderr)
                sys.exit(1)
            missing = required - set(reader.fieldnames)
            if missing:
                cols = ", ".join(sorted(missing))
                print(
                    f"ERROR: CSV missing columns: {cols}",
                    file=sys.stderr,
                )
                sys.exit(1)

            rows = list(reader)
    except FileNotFoundError:
        print(f"ERROR: File not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    if not rows:
        print(f"ERROR: {args.csv} has no data rows", file=sys.stderr)
        sys.exit(1)

    passed_durations = []
    failed_durations = []
    all_starts = []
    all_ends = []

    for i, row in enumerate(rows, start=2):
        try:
            started = parse_datetime(row["started_at"])
            completed = parse_datetime(row["completed_at"])
        except (ValueError, KeyError) as e:
            print(
                f"ERROR: Bad datetime on CSV line {i}: {e}",
                file=sys.stderr,
            )
            sys.exit(1)

        duration = (completed - started).total_seconds()
        result = row["result"]

        all_starts.append(started)
        all_ends.append(completed)

        if result == "pass":
            passed_durations.append(duration)
        else:
            failed_durations.append(duration)

    print_group_stats("Passed", passed_durations)
    print_group_stats("Failed", failed_durations)

    total = len(passed_durations) + len(failed_durations)
    experiment_start = min(all_starts)
    experiment_end = max(all_ends)
    experiment_duration = (experiment_end - experiment_start).total_seconds()

    print(f"\n=== Overall: {total} runs ===")
    print(f"  Start: {experiment_start.strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print(f"  End:   {experiment_end.strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print(
        f"  Duration: {experiment_duration:.0f}s"
        f"  ({human_duration(experiment_duration)})"
    )


if __name__ == "__main__":
    main()
