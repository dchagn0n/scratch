#!/bin/bash
# ============================================================
# Automated R generation for NS-3 experiment directories
# Author: [you]
# ============================================================

while getopts e:i:d:p:c:g: flag
do
    case "${flag}" in
        e) do_evolution=${OPTARG};;
        i) trainonparasite=${OPTARG};;
        d) trainondetour=${OPTARG};;
        p) trainonpath=${OPTARG};;
        c) comment=${OPTARG};;
        g) dographs=${OPTARG};;
    esac
done
shift $((OPTIND - 1)) 

: ${do_evolution:=FALSE}
: ${trainonparasite:="60Mbps"}
: ${trainondetour:=0}
: ${trainonpath:=0}
: ${comment:=""}
: ${dographs:=TRUE}

# --- Base directories ---
BASE_DIR="$(pwd)"                  # typically ns-3.45
SCRATCH_DIR="$BASE_DIR/scratch"
#NINTH_DIR="$SCRATCH_DIR/ninth"

# Liste des niveaux à parcourir
LEVELS=("ninth" "tenth")


# --- Parameters ---
MAX_JOBS=2                         # Max concurrent processes
LOG_FILE="$SCRATCH_DIR/processed_dirs_evolution${do_evolution}_detour${trainondetour}_parasite${trainonparasite}_path${trainonpath}_${comment}_dograph${dographs}.txt"   # List of processed directories

# --- Optional argument: single directory ---
DATA_DIR_ARG="$1"

# --- Function to generate R commands ---
generate_commands() {
    local dir="$1"
    echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour -e $do_evolution -i $trainonparasite -d $trainondetour -p $trainonpath -c $comment -g $dographs" 
    echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path -e $do_evolution -i $trainonparasite -d $trainondetour -p $trainonpath -c $comment -g $dographs"
    echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite -e $do_evolution -i $trainonparasite -d $trainondetour -p $trainonpath -c $comment -g $dographs"
}

# --- Function to process a single directory ---
process_directory() {
    local dir="$1"

    printf "\n=== [%s] Processing: %s ===\n" "$(date '+%H:%M:%S')" "$dir"

    # Check if directory was already processed
    if grep -qxF "$dir" "$LOG_FILE" 2>/dev/null; then
        printf "[INFO] Skipping already processed: %s\n" "$dir"
        return
    fi

    # Check number of files
    local file_count
    file_count=$(find "$dir" -maxdepth 1 -type f -name "T60.000000s_L5ms*" | wc -l)

    if (( file_count != 1 )); then
        printf "[WARN] %s has %d files (expected 3). Running merge/copy scripts...\n" "$dir" "$file_count"
        #bash scratch/merge_all_ns3.sh
        #bash scratch/copy_all.sh
        return
    fi

    # Run Rscript commands in parallel for this directory
    printf "[INFO] Starting R scripts for %s\n" "$dir"
    printf "%s\n" "$dir" >> "$LOG_FILE"
    generate_commands "$dir" | xargs -I CMD -P 3 bash -c "CMD"

    # Mark as processed
    
    printf "[OK] Completed: %s\n" "$dir"
}

# ============================================================
# --- Main Execution ---
# ============================================================

# Create log file if missing
touch "$LOG_FILE"

if [[ -n "$DATA_DIR_ARG" ]]; then
    # Process only one directory (if provided)
    if [[ -d "$DATA_DIR_ARG" ]]; then
        process_directory "$DATA_DIR_ARG"
    else
        printf "[ERROR] Directory '%s' not found.\n" "$DATA_DIR_ARG" >&2
        exit 1
    fi
else

    for LEVEL in "${LEVELS[@]}"; do
        LEVEL_DIR="$SCRATCH_DIR/$LEVEL"


        # Vérifier que le répertoire existe
        if [[ ! -d "$LEVEL_DIR" ]]; then
            echo "⚠️  Répertoire absent : $LEVEL_DIR (ignoré)"
            continue
        fi


        # Process all directories concurrently
        printf "=== Scanning %s for subdirectories ===\n" "$LEVEL_DIR"

        find "$LEVEL_DIR" -maxdepth 1 -type d -regex ".*/\(2025\|2026\)-.*" | while read dir; do
            # Launch each directory in background, respecting MAX_JOBS
            while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
                sleep 5
            done

            process_directory "$dir" &
        done
    done

    # Wait for all background jobs
    wait
fi

printf "\n=== All executions completed. ===\n"


# #!/bin/bash

# # Base directories
# BASE_DIR="$(pwd)"                  # ns-3.45
# SCRATCH_DIR="$BASE_DIR/scratch"
# NINTH_DIR="$SCRATCH_DIR/ninth"

# # Maximum parallel processes
# MAX_JOBS=6

# # Log file for processed directories
# PROCESSED_LOG="$NINTH_DIR/processed_dirs.txt"

# # Optional argument: a specific directory
# DATA_DIR_ARG="$1"


# # --- Function to generate commands for a given directory ---
# generate_commands() {
#     local dir="$1"

#     # If directory already processed, skip it
#     if grep -Fxq "$dir" "$PROCESSED_LOG" 2>/dev/null; then
#         printf "[INFO] Skipping already processed: %s\n" "$dir"
#         return
#     fi

#     # --- Verify file count ---
#     printf "[INFO] Checking directory: %s\n" "$dir"
#     local file_count
#     file_count=$(find "$dir" -maxdepth 1 -type f | wc -l)

#     if (( file_count != 48 )); then
#         printf "[WARN] %s contains %d files — running merge and copy\n" "$dir" "$file_count"
#         bash scratch/merge_all_ns3.sh
#         bash scratch/copy_all.sh
#         #bash scratch/generation_all_R.sh &
#         return # Skip R processing for this directory
#     fi

#     # Log the directory as being processed
#     printf "%s\n" "$dir" >> "$PROCESSED_LOG"

#     # --- Generate commands for R processing ---
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite"
# }



# # --- Main Execution ---
# if [[ -n "$DATA_DIR_ARG" ]]; then
#     if [[ -d "$DATA_DIR_ARG" ]]; then
#         generate_commands "$DATA_DIR_ARG" | xargs -I CMD -P $MAX_JOBS bash -c CMD
#     else
#         echo "Error: directory '$DATA_DIR_ARG' not found." >&2
#         exit 1
#     fi
# else
#     find "$NINTH_DIR" -maxdepth 1 -type d -name "2025-*" | while read DATA_DIR; do
#         generate_commands "$DATA_DIR"
#     done | xargs -I CMD -P $MAX_JOBS bash -c CMD
# fi

# echo "All executions completed."



# #!/bin/bash

# # Base directories
# BASE_DIR="$(pwd)"                  # ns-3.45
# SCRATCH_DIR="$BASE_DIR/scratch"
# NINTH_DIR="$SCRATCH_DIR/ninth"

# # Maximum parallel processes
# MAX_JOBS=6

# # Log file for processed directories
# PROCESSED_LOG="$NINTH_DIR/processed_dirs.txt"

# # Optional argument: a specific directory
# DATA_DIR_ARG="$1"


# # --- Function to generate commands for a given directory ---
# generate_commands() {
#     local dir="$1"

#     # If directory already processed, skip it
#     if grep -Fxq "$dir" "$PROCESSED_LOG" 2>/dev/null; then
#         echo "[SKIP] $dir already processed."
#         return
#     fi

#     # Log the directory as being processed
#     echo "$dir" >> "$PROCESSED_LOG"

#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite"
# }



# # --- Main Execution ---
# if [[ -n "$DATA_DIR_ARG" ]]; then
#     if [[ -d "$DATA_DIR_ARG" ]]; then
#         generate_commands "$DATA_DIR_ARG" | xargs -I CMD -P $MAX_JOBS bash -c CMD
#     else
#         echo "Error: directory '$DATA_DIR_ARG' not found." >&2
#         exit 1
#     fi
# else
#     find "$NINTH_DIR" -maxdepth 1 -type d -name "2025-*" | while read DATA_DIR; do
#         generate_commands "$DATA_DIR"
#     done | xargs -I CMD -P $MAX_JOBS bash -c CMD
# fi

# echo "All executions completed."



# #!/bin/bash

# # ==========================
# # Configuration
# # ==========================
# BASE_DIR="$(pwd)"                  # ns-3.45
# SCRATCH_DIR="$BASE_DIR/scratch"
# NINTH_DIR="$SCRATCH_DIR/ninth"
# MAX_JOBS=6                         # maximum parallel Rscript processes
# DATA_DIR_ARG="$1"

# # Require inotifywait for live monitoring
# if ! command -v inotifywait >/dev/null 2>&1; then
#     echo "Error: 'inotifywait' not found. Please install it (e.g., sudo apt install inotify-tools)." >&2
#     exit 1
# fi

# # ==========================
# # Helper functions
# # ==========================
# generate_commands() {
#     local dir="$1"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite"
# }

# run_for_dir() {
#     local dir="$1"
#     printf '[%s] Starting directory: %s\n' "$(date '+%H:%M:%S')" "$dir"
#     generate_commands "$dir"
# }

# # ==========================
# # Function to feed jobs into the pool
# # ==========================
# enqueue_jobs() {
#     local dir="$1"
#     # Print log BEFORE sending commands to xargs
#     printf '[%s] Starting directory: %s\n' "$(date '+%H:%M:%S')" "$dir"
#     # Only the commands go to xargs
#     generate_commands "$dir" | xargs -I CMD -P 1 bash -c "CMD" &
# }

# # ==========================
# # Manage concurrency
# # ==========================
# wait_for_slot() {
#     while (( $(jobs -r | wc -l) >= MAX_JOBS )); do
#         sleep 1
#     done
# }

# # ==========================
# # Main Logic
# # ==========================
# if [[ -n "$DATA_DIR_ARG" ]]; then
#     if [[ -d "$DATA_DIR_ARG" ]]; then
#         enqueue_jobs "$DATA_DIR_ARG"
#     else
#         echo "Error: directory '$DATA_DIR_ARG' not found." >&2
#         exit 1
#     fi
#     wait
#     echo "All executions completed."
#     exit 0
# fi

# echo "=== Processing existing directories in $NINTH_DIR ==="
# find "$NINTH_DIR" -maxdepth 1 -type d -name "2025-*" | while read -r DIR; do
#     wait_for_slot
#     enqueue_jobs "$DIR"
# done

# echo "=== Watching for new directories in $NINTH_DIR ==="
# inotifywait -m -e create -e moved_to --format '%f' "$NINTH_DIR" | while read -r NEWDIR; do
#     FULL_PATH="$NINTH_DIR/$NEWDIR"
#     if [[ "$NEWDIR" == 2025-* && -d "$FULL_PATH" ]]; then
#         printf '[%s] New directory detected: %s\n' "$(date '+%H:%M:%S')" "$FULL_PATH"
#         wait_for_slot
#         enqueue_jobs "$FULL_PATH"
#     fi
# done &

# wait
# echo "All executions completed."


# #!/bin/bash

# # ==========================
# # Configuration
# # ==========================
# BASE_DIR="$(pwd)"                  # ns-3.45
# SCRATCH_DIR="$BASE_DIR/scratch"
# NINTH_DIR="$SCRATCH_DIR/ninth"
# MAX_JOBS=6                         # Parallel Rscript processes
# DATA_DIR_ARG="$1"                  # Optional specific directory

# # Require inotifywait for live monitoring
# if ! command -v inotifywait >/dev/null 2>&1; then
#     echo "Error: 'inotifywait' not found. Please install it (e.g., sudo apt install inotify-tools)." >&2
#     exit 1
# fi

# # ==========================
# # Helper Functions
# # ==========================
# generate_commands() {
#     local dir="$1"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite"
# }

# run_for_dir() {
#     local dir="$1"
#     echo ">>> Processing directory: $dir"
#     generate_commands "$dir" | xargs -I CMD -P $MAX_JOBS bash -c CMD
#     echo ">>> Completed: $dir"
# }

# # ==========================
# # Main Logic
# # ==========================

# # If a specific directory is provided, process only that
# if [[ -n "$DATA_DIR_ARG" ]]; then
#     if [[ -d "$DATA_DIR_ARG" ]]; then
#         run_for_dir "$DATA_DIR_ARG"
#     else
#         echo "Error: directory '$DATA_DIR_ARG' not found." >&2
#         exit 1
#     fi
#     exit 0
# fi

# # Otherwise, process existing directories first
# echo "=== Scanning existing directories in $NINTH_DIR ==="
# find "$NINTH_DIR" -maxdepth 1 -type d -name "2025-*" | while read DATA_DIR; do
#     run_for_dir "$DATA_DIR"
# done

# # ==========================
# # Watch for new directories
# # ==========================
# echo "=== Watching for new directories in $NINTH_DIR ==="
# inotifywait -m -e create -e moved_to --format '%f' "$NINTH_DIR" | while read NEW_DIR; do
#     FULL_PATH="$NINTH_DIR/$NEW_DIR"

#     # Ensure it matches the naming pattern and is a directory
#     if [[ "$NEW_DIR" == 2025-* && -d "$FULL_PATH" ]]; then
#         echo ">>> New directory detected: $FULL_PATH"
#         run_for_dir "$FULL_PATH"
#     fi
# done


# #!/bin/bash

# # Base directories
# BASE_DIR="$(pwd)"                  # ns-3.45
# SCRATCH_DIR="$BASE_DIR/scratch"
# NINTH_DIR="$SCRATCH_DIR/ninth"

# # Maximum parallel processes
# MAX_JOBS=6

# # Optional argument: a specific directory
# DATA_DIR_ARG="$1"


# # Function to generate commands for a given directory
# generate_commands() {
#     local dir="$1"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$dir\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite"
# }



# # If a directory argument is given, use only that one
# if [[ -n "$DATA_DIR_ARG" ]]; then
#     if [[ -d "$DATA_DIR_ARG" ]]; then
#         generate_commands "$DATA_DIR_ARG" | xargs -I CMD -P $MAX_JOBS bash -c CMD
#     else
#         echo "Error: directory '$DATA_DIR_ARG' not found." >&2
#         exit 1
#     fi
# else
#     # Otherwise, process all subdirectories
#     find "$NINTH_DIR" -maxdepth 1 -type d -name "2025-*" | while read DATA_DIR; do
#         generate_commands "$DATA_DIR"
#     done | xargs -I CMD -P $MAX_JOBS bash -c CMD
# fi

# echo "All executions completed."


# #!/bin/bash

# # Base directories
# BASE_DIR="$(pwd)"                  # ns-3.45
# SCRATCH_DIR="$BASE_DIR/scratch"
# NINTH_DIR="$SCRATCH_DIR/ninth"

# # Maximum parallel processes
# MAX_JOBS=6

# # Generate the list of commands and run them in parallel
# find "$NINTH_DIR" -maxdepth 1 -type d -name "2025-*" | while read DATA_DIR; do
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$DATA_DIR\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$DATA_DIR\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path"
#     echo "Rscript scratch/ninth/generation.R -t 60 -r \"$DATA_DIR\" -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite"
# done | xargs -I CMD -P $MAX_JOBS bash -c CMD

# echo "All executions completed."


# #!/bin/bash

# # This script lives in ns-3.45/scratch but is executed from ns-3.45
# BASE_DIR="$(pwd)"                      # ns-3.45
# SCRATCH_DIR="$BASE_DIR/scratch"
# NINTH_DIR="$SCRATCH_DIR/ninth"

# # Program names (without .cc extension)
# # FIRST_PROG="first_program"
# # SECOND_PROG="ninth/second_program"

# # Loop through all date directories in scratch/ninth
# for DATA_DIR in "$NINTH_DIR"/2025-*; do
#     if [ -d "$DATA_DIR" ]; then
#         echo "=== Processing data directory: $(basename "$DATA_DIR") ==="

#         # Run the second program
#         echo "Running second program..."
#         Rscript scratch/ninth/generation.R -t 60 -r $DATA_DIR -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n detour &
#         Rscript scratch/ninth/generation.R  -t 60 -r $DATA_DIR -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n path &
#         Rscript scratch/ninth/generation.R  -t 60 -r $DATA_DIR -l 5ms -b 120Mbps -a 10Mbps -o 12000 -m 0.5 -x 0.5 -n parasite &

#         echo "Completed directory: $(basename "$DATA_DIR")"
#         echo
#     fi
# done

# echo "All executions completed."
# # ================================
