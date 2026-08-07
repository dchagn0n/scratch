#!/bin/bash

# This script lives in ns-3.45/scratch but is executed from ns-3.45
BASE_DIR="$(pwd)"                      # ns-3.45
SCRATCH_DIR="$BASE_DIR/scratch"
NINTH_DIR="$SCRATCH_DIR/ninth"

# Program names (without .cc extension)
# FIRST_PROG="first_program"
# SECOND_PROG="ninth/second_program"

# Loop through all date directories in scratch/ninth
for DATA_DIR in "$NINTH_DIR"/2025-*; do
    if [ -d "$DATA_DIR" ]; then
        echo "=== Processing data directory: $(basename "$DATA_DIR") ==="

        CSV_COUNT=$(find "$DATA_DIR" -maxdepth 1 -type f -name "T60.000000s_L5ms*" | wc -l)

        if [ "$CSV_COUNT" -eq 1 ]; then
            echo "Found 1 CSV file special. Running duplication..."

            for f in "$DATA_DIR"/T*_merge_path_trace_all_output_stats.csv; do
                # Skip if no file found
                [ -f "$f" ] || continue

                echo "  Duplicating in $(basename "$DATA_DIR") : $(basename "$f")"

                cp "$f" "${f/_merge_path_/_merge_detour_}" &
                cp "$f" "${f/_merge_path_/_merge_parasite_}" &
            done

        else
            echo "Skipping directory $(basename "$DATA_DIR") — found $CSV_COUNT CSV files."
            continue
        fi

        echo "Completed directory: $(basename "$DATA_DIR")"
        echo
    fi
done

echo "All executions completed."
# ================================
